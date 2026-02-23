<?php

namespace Paymenter\Extensions\Gateways\MercadoPago;

use App\Attributes\ExtensionMeta;
use App\Classes\Extension\Gateway;
use App\Helpers\ExtensionHelper;
use App\Models\Invoice;
use Exception;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\View;

#[ExtensionMeta(
    name: 'MercadoPago Gateway',
    description: 'Accept payments via MercadoPago (Checkout Pro).',
    version: '1.0.0',
    author: 'ServersMX',
    url: 'https://serversmx.online',
    icon: 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA1MTIgNTEyIj48cmVjdCB3aWR0aD0iNTEyIiBoZWlnaHQ9IjUxMiIgZmlsbD0iIzAwYjFlYSIvPjx0ZXh0IHg9IjI1NiIgeT0iMjgwIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjZmZmIiBmb250LXNpemU9IjIwMCIgZm9udC1mYW1pbHk9IkFyaWFsIj5NUDwvdGV4dD48L3N2Zz4='
)]
class MercadoPago extends Gateway
{
    public function boot()
    {
        require __DIR__ . '/routes.php';
        View::addNamespace('gateways.mercadopago', __DIR__ . '/resources/views');
    }

    public function getConfig($values = [])
    {
        return [
            [
                'name' => 'access_token',
                'label' => 'Access Token',
                'type' => 'text',
                'description' => 'Your MercadoPago Access Token (from https://www.mercadopago.com.mx/developers/panel/app)',
                'required' => true,
            ],
            [
                'name' => 'public_key',
                'label' => 'Public Key',
                'type' => 'text',
                'description' => 'Your MercadoPago Public Key',
                'required' => true,
            ],
            [
                'name' => 'sandbox',
                'label' => 'Sandbox Mode',
                'type' => 'checkbox',
                'description' => 'Enable sandbox/test mode',
                'required' => false,
            ],
            [
                'name' => 'webhook_secret',
                'label' => 'Webhook Secret (optional)',
                'type' => 'text',
                'description' => 'Secret for verifying webhook signatures (from MP developer panel)',
                'required' => false,
            ],
        ];
    }

    private function request($method, $url, $data = [])
    {
        $response = Http::withHeaders([
            'Authorization' => 'Bearer ' . $this->config('access_token'),
            'Content-Type' => 'application/json',
            'X-Idempotency-Key' => uniqid('mp_', true),
        ])->$method('https://api.mercadopago.com' . $url, $data);

        if (!$response->successful()) {
            $error = $response->json();
            throw new Exception('MercadoPago API error: ' . ($error['message'] ?? $response->body()));
        }

        return $response->object();
    }

    public function pay(Invoice $invoice, $total)
    {
        $preference = $this->request('post', '/checkout/preferences', [
            'items' => [
                [
                    'title' => __('invoices.payment_for_invoice', ['number' => $invoice->number ?? $invoice->id]),
                    'quantity' => 1,
                    'unit_price' => (float) $total,
                    'currency_id' => strtoupper($invoice->currency_code),
                ],
            ],
            'back_urls' => [
                'success' => route('invoices.show', $invoice) . '?checkPayment=true',
                'failure' => route('invoices.show', $invoice) . '?paymentFailed=true',
                'pending' => route('invoices.show', $invoice) . '?paymentPending=true',
            ],
            'auto_return' => 'approved',
            'external_reference' => (string) $invoice->id,
            'notification_url' => route('extensions.gateways.mercadopago.webhook'),
            'statement_descriptor' => config('app.name'),
        ]);

        $checkoutUrl = $this->config('sandbox')
            ? $preference->sandbox_init_point
            : $preference->init_point;

        return $checkoutUrl;
    }

    public function webhook(Request $request)
    {
        $type = $request->input('type') ?? $request->input('topic');
        $dataId = $request->input('data.id') ?? $request->input('id');

        if ($type !== 'payment' || !$dataId) {
            return response()->json(['status' => 'ignored']);
        }

        $payment = $this->request('get', '/v1/payments/' . $dataId);

        if (!$payment || !isset($payment->external_reference)) {
            return response()->json(['status' => 'no_reference']);
        }

        $invoiceId = $payment->external_reference;

        switch ($payment->status) {
            case 'approved':
                $fee = $payment->fee_details[0]->amount ?? 0;
                ExtensionHelper::addPayment(
                    $invoiceId,
                    'MercadoPago',
                    $payment->transaction_amount,
                    $fee,
                    $payment->id
                );
                break;

            case 'pending':
            case 'in_process':
                ExtensionHelper::addProcessingPayment(
                    $invoiceId,
                    'MercadoPago',
                    $payment->transaction_amount,
                    null,
                    $payment->id
                );
                break;

            case 'rejected':
            case 'cancelled':
                ExtensionHelper::addFailedPayment(
                    $invoiceId,
                    'MercadoPago',
                    $payment->transaction_amount,
                    null,
                    $payment->id
                );
                break;
        }

        return response()->json(['status' => 'ok']);
    }

    public function supportsBillingAgreements(): bool
    {
        return false;
    }
}

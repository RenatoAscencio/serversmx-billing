<?php

namespace Paymenter\Extensions\Others\MXNotifications;

use App\Attributes\ExtensionMeta;
use App\Classes\Extension\Extension;
use App\Events\Invoice\Paid as InvoicePaid;
use App\Events\Order\Created as OrderCreated;
use App\Events\Ticket\Created as TicketCreated;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Http;

#[ExtensionMeta(
    name: 'MX Telegram Notifications',
    description: 'Send Telegram notifications for payments, orders and tickets.',
    version: '1.0.0',
    author: 'ServersMX',
    url: 'https://serversmx.online'
)]
class MXNotifications extends Extension
{
    public function getConfig($values = [])
    {
        return [
            [
                'name' => 'telegram_bot_token',
                'label' => 'Telegram Bot Token',
                'type' => 'text',
                'required' => true,
            ],
            [
                'name' => 'telegram_chat_id',
                'label' => 'Telegram Chat ID',
                'type' => 'text',
                'required' => true,
            ],
        ];
    }

    public function boot()
    {
        Event::listen(InvoicePaid::class, function (InvoicePaid $event) {
            $invoice = $event->invoice;
            $this->sendTelegram(
                "*Pago recibido*\n" .
                "Factura: #{$invoice->id}\n" .
                "Cliente: {$invoice->user->name}\n" .
                "Monto: \${$invoice->total} {$invoice->currency_code}"
            );
        });

        Event::listen(OrderCreated::class, function (OrderCreated $event) {
            $order = $event->order;
            $this->sendTelegram(
                "*Nueva orden*\n" .
                "Orden: #{$order->id}\n" .
                "Cliente: {$order->user->name}"
            );
        });

        Event::listen(TicketCreated::class, function (TicketCreated $event) {
            $ticket = $event->ticket;
            $this->sendTelegram(
                "*Nuevo ticket*\n" .
                "#{$ticket->id}: {$ticket->subject}\n" .
                "Cliente: {$ticket->user->name}\n" .
                "Prioridad: {$ticket->priority}"
            );
        });
    }

    private function sendTelegram(string $message): void
    {
        $token = $this->config('telegram_bot_token');
        $chatId = $this->config('telegram_chat_id');

        if (!$token || !$chatId) {
            return;
        }

        Http::post("https://api.telegram.org/bot{$token}/sendMessage", [
            'chat_id' => $chatId,
            'text' => $message,
            'parse_mode' => 'Markdown',
        ]);
    }
}

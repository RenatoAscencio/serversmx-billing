#!/bin/bash
DOMAIN="https://serversmx.online"
ERRORS=0

echo "=== Smoke Test: $DOMAIN ==="

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DOMAIN" --max-time 10)
[ "$STATUS" == "200" ] && echo "[OK] Homepage -> $STATUS" || { echo "[FAIL] Homepage -> $STATUS"; ERRORS=$((ERRORS+1)); }

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DOMAIN/login" --max-time 10)
[ "$STATUS" == "200" ] && echo "[OK] Login -> $STATUS" || { echo "[FAIL] Login -> $STATUS"; ERRORS=$((ERRORS+1)); }

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DOMAIN/admin" --max-time 10)
[[ "$STATUS" == "302" || "$STATUS" == "200" ]] && echo "[OK] Admin -> $STATUS" || { echo "[FAIL] Admin -> $STATUS"; ERRORS=$((ERRORS+1)); }

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DOMAIN/.env" --max-time 10)
[[ "$STATUS" == "403" || "$STATUS" == "404" ]] && echo "[OK] .env protected -> $STATUS" || { echo "[FAIL] .env EXPOSED -> $STATUS"; ERRORS=$((ERRORS+1)); }

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DOMAIN/composer.json" --max-time 10)
[[ "$STATUS" == "403" || "$STATUS" == "404" ]] && echo "[OK] composer.json protected -> $STATUS" || { echo "[WARN] composer.json -> $STATUS"; }

REAL_PATH=$(ssh mx4 "readlink -f /home/servers/public_html" 2>/dev/null)
[ "$REAL_PATH" == "/home/servers/paymenter/public" ] && echo "[OK] Webroot -> $REAL_PATH" || { echo "[FAIL] Webroot -> $REAL_PATH"; ERRORS=$((ERRORS+1)); }

ssh mx4 "crontab -l -u servers 2>/dev/null | grep -q 'schedule:run'" && echo "[OK] Cron configured" || { echo "[FAIL] Cron missing"; ERRORS=$((ERRORS+1)); }

ssh mx4 'cd /home/servers/paymenter && /opt/alt/php83/usr/bin/php artisan tinker --execute="echo cache()->put(\"smoke\",\"ok\",60)?\"ok\":\"fail\";" 2>/dev/null' | grep -q "ok" && echo "[OK] Redis working" || { echo "[FAIL] Redis"; ERRORS=$((ERRORS+1)); }

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "=== $ERRORS FAILURES ==="
    exit 1
else
    echo "=== ALL CHECKS PASSED ==="
fi

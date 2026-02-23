#!/bin/bash
set -euo pipefail

SERVER="mx4"
USER="servers"
APP_DIR="/home/${USER}/paymenter"
PHP="/opt/alt/php83/usr/bin/php"
BRANCH="production"

echo "=== Deploy ServersMX Billing ==="
echo "Target: ${USER}@${SERVER}:${APP_DIR}"
echo "Branch: ${BRANCH}"
echo ""

ACCOUNT_DOMAIN=$(ssh $SERVER "grep '^DNS=' /var/cpanel/users/$USER | head -1 | cut -d= -f2")
if [[ "$ACCOUNT_DOMAIN" != *"serversmx.online"* ]]; then
    echo "ABORT: Account $USER does not match serversmx.online (found: $ACCOUNT_DOMAIN)"
    exit 1
fi
echo "[OK] Account verified: $ACCOUNT_DOMAIN"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo "[..] Creating backup..."
ssh $SERVER "cd $APP_DIR && tar -czf /home/${USER}/backup_${TIMESTAMP}.tar.gz \
    --exclude=vendor --exclude=node_modules --exclude=.git \
    . 2>/dev/null" && echo "[OK] Backup: backup_${TIMESTAMP}.tar.gz" || echo "[SKIP] No previous deploy to backup"

echo "[..] Pulling latest code..."
ssh $SERVER "cd $APP_DIR && git fetch origin && git checkout $BRANCH && git pull origin $BRANCH"
echo "[OK] Code updated"

echo "[..] Installing PHP dependencies..."
ssh $SERVER "cd $APP_DIR && $PHP /usr/local/bin/composer install --no-dev --optimize-autoloader --no-interaction"
echo "[OK] Composer done"

echo "[..] Building frontend assets..."
ssh $SERVER "cd $APP_DIR && npm ci --silent && npm run build && npm run build:admin"
echo "[OK] Assets built"

echo "[..] Running migrations..."
ssh $SERVER "cd $APP_DIR && $PHP artisan migrate --force"
echo "[OK] Migrations done"

echo "[..] Caching config/routes/views..."
ssh $SERVER "cd $APP_DIR && \
    $PHP artisan config:cache && \
    $PHP artisan route:cache && \
    $PHP artisan view:cache && \
    $PHP artisan icons:cache && \
    $PHP artisan storage:link 2>/dev/null || true"
echo "[OK] Caches refreshed"

ssh $SERVER "chmod -R 755 $APP_DIR/storage $APP_DIR/bootstrap/cache && \
    chmod 600 $APP_DIR/.env && \
    chown -R ${USER}:${USER} $APP_DIR/storage $APP_DIR/bootstrap/cache"
echo "[OK] Permissions set"

ssh $SERVER "
    if [ ! -L /home/${USER}/public_html ]; then
        mv /home/${USER}/public_html /home/${USER}/public_html.bak 2>/dev/null || true
        ln -sfn $APP_DIR/public /home/${USER}/public_html
        chown -h ${USER}:${USER} /home/${USER}/public_html
        echo 'Symlink created'
    else
        echo 'Symlink already exists'
    fi
"

ssh $SERVER "supervisorctl restart paymenter-worker:* 2>/dev/null || echo 'Supervisor not configured'"

echo "[..] Purging Cloudflare cache..."
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/c7bba61b36119ec39d772d79924a354c/purge_cache" \
    -H "X-Auth-Email: renato_ascencio@hotmail.com" \
    -H "X-Auth-Key: cd50c4d6c11a9a581a32d464a55fb08667849" \
    -H "Content-Type: application/json" \
    --data '{"purge_everything":true}' > /dev/null
echo "[OK] Cloudflare purged"

echo ""
echo "=== Deploy complete. Running smoke test... ==="
bash "$(dirname "$0")/smoke-test.sh"

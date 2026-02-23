#!/bin/bash
set -euo pipefail

SERVER="mx4"
USER="servers"
APP_DIR="/home/${USER}/paymenter"
PHP="/opt/alt/php83/usr/bin/php"

echo "=== Rollback ServersMX Billing ==="

BACKUP=$(ssh $SERVER "ls -t /home/${USER}/backup_*.tar.gz 2>/dev/null | head -1")

if [ -z "$BACKUP" ]; then
    echo "No backups found. Manual rollback options:"
    echo "  1. git log --oneline -5  (then git checkout <hash>)"
    echo "  2. Restore from JetBackup"
    ssh $SERVER "cd $APP_DIR && git log --oneline -5"
    exit 1
fi

echo "Restoring from: $BACKUP"
read -p "Continue? (y/N): " confirm
[ "$confirm" != "y" ] && exit 0

ssh $SERVER "
    cd $APP_DIR
    tar -xzf $BACKUP
    $PHP /usr/local/bin/composer install --no-dev --optimize-autoloader --no-interaction
    $PHP artisan migrate --force
    $PHP artisan config:cache
    $PHP artisan route:cache
    $PHP artisan view:cache
    supervisorctl restart paymenter-worker:* 2>/dev/null || true
"

echo "=== Rollback complete ==="
echo "Verify: https://serversmx.online"

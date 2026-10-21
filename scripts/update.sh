#!/usr/bin/env bash
# Copy this checkout into /opt/tunnel-kit, rebuild the dashboard, re-apply configs.
# On the VPS, after git pull:
#   cd tunnel-kit && sudo bash scripts/update.sh
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/update.sh" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
OPT_ROOT=/opt/tunnel-kit
WWW_DIR=/var/www/tunnel-kit

mkdir -p "$OPT_ROOT" /var/www/acme "$WWW_DIR"
if [[ $REPO_ROOT != "$OPT_ROOT" ]]; then
  rsync -a \
    --exclude '.git' \
    --exclude 'web/node_modules' \
    --exclude 'web/dist' \
    --exclude 'scripts/__pycache__' \
    "$REPO_ROOT/" "$OPT_ROOT/"
fi

echo "Building dashboard..."
cd "$OPT_ROOT/web"
npm install
npm run build
rm -rf "$WWW_DIR"
mkdir -p "$WWW_DIR"
cp -a dist/. "$WWW_DIR/"

bash "$OPT_ROOT/scripts/apply.sh"
echo "Updated from ${REPO_ROOT}"

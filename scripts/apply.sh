#!/usr/bin/env bash
# Re-render configs from /etc/tunnel-kit.env and restart services.
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/apply.sh" >&2
  exit 1
fi

OPT_ROOT=/opt/tunnel-kit
XRAY_CFG=/usr/local/etc/xray/config.json
CADDY_CFG=/etc/caddy/Caddyfile

mkdir -p /usr/local/etc/xray /var/log/xray
python3 "$OPT_ROOT/scripts/render.py" "$OPT_ROOT/server/xray.json.tpl" "$XRAY_CFG"
python3 "$OPT_ROOT/scripts/render.py" "$OPT_ROOT/server/Caddyfile.tpl" "$CADDY_CFG"
chmod 644 "$XRAY_CFG" "$CADDY_CFG"
chmod 755 /usr/local/etc/xray /var/log/xray
# Existing access.log/error.log are often root:root; chown the dir alone is not enough.
if id nobody >/dev/null 2>&1; then
  if getent group nogroup >/dev/null 2>&1; then
    chown -R nobody:nogroup /var/log/xray
  else
    chown -R nobody:nobody /var/log/xray
  fi
fi
find /var/log/xray -type f -exec chmod 644 {} +

if command -v caddy >/dev/null 2>&1; then
  caddy validate --config "$CADDY_CFG"
fi
if [[ -x /usr/local/bin/xray ]]; then
  echo "Testing Xray config as nobody (the service user)..."
  if id nobody >/dev/null 2>&1; then
    runuser -u nobody -- /usr/local/bin/xray run -test -c "$XRAY_CFG"
  else
    /usr/local/bin/xray run -test -c "$XRAY_CFG"
  fi
fi

systemctl restart caddy xray tunnel-kit-api
sleep 0.4
systemctl --no-pager --full status caddy xray tunnel-kit-api | sed -n '1,28p'

if ! systemctl is-active --quiet xray; then
  echo
  echo "Xray failed to start. Last logs:"
  journalctl -u xray -n 40 --no-pager || true
  echo
  echo "Config perms: $(ls -l "$XRAY_CFG" 2>/dev/null || echo missing)"
  exit 1
fi
echo "Applied."

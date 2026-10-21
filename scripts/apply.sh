#!/usr/bin/env bash
# Re-render configs from /etc/tunnel-kit.env and restart services.
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/apply.sh" >&2
  exit 1
fi

OPT_ROOT=/opt/tunnel-kit
ENV_FILE=${TUNNEL_KIT_ENV:-/etc/tunnel-kit.env}
XRAY_CFG=/usr/local/etc/xray/config.json
CADDY_CFG=/etc/caddy/Caddyfile
OVERRIDE=/etc/systemd/system/xray.service.d/20-tunnel-kit.conf

if [[ -f $ENV_FILE ]]; then
  grep -q '^WS_PATH=' "$ENV_FILE" || echo "WS_PATH=/$(openssl rand -hex 12)" >>"$ENV_FILE"
  grep -q '^XHTTP_PATH=' "$ENV_FILE" || echo "XHTTP_PATH=/$(openssl rand -hex 12)" >>"$ENV_FILE"
fi

mkdir -p /usr/local/etc/xray /var/log/xray /var/log/v2ray /etc/systemd/system/xray.service.d
install -m 644 "$OPT_ROOT/server/xray.override.conf" "$OVERRIDE"
systemctl daemon-reload
python3 "$OPT_ROOT/scripts/render.py" "$OPT_ROOT/server/xray.json.tpl" "$XRAY_CFG"
python3 "$OPT_ROOT/scripts/render.py" "$OPT_ROOT/server/Caddyfile.tpl" "$CADDY_CFG"
chmod 644 "$XRAY_CFG" "$CADDY_CFG"
chmod 755 /usr/local/etc/xray /var/log/xray /var/log/v2ray

if command -v caddy >/dev/null 2>&1; then
  caddy validate --config "$CADDY_CFG"
fi
if [[ -x /usr/local/bin/xray ]]; then
  echo "Testing Xray config..."
  /usr/local/bin/xray run -test -c "$XRAY_CFG"
fi

systemctl restart caddy xray tunnel-kit-api
sleep 1
systemctl --no-pager --full status caddy xray tunnel-kit-api | sed -n '1,28p'

listening_port() {
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -E ":${1}$" >/dev/null
}

if ! systemctl is-active --quiet xray || ! listening_port 10086 || ! listening_port 10087; then
  echo
  echo "Xray is not serving 10086/10087 (systemd active=$(systemctl is-active xray || true))."
  echo "ss listeners:"
  ss -lnt 2>/dev/null | awk 'NR==1 || $4 ~ /:(80|443|10086|10087|8787)$/' || true
  echo
  echo "Last logs:"
  journalctl -u xray -n 40 --no-pager || true
  exit 1
fi
echo "Applied. Xray is listening on 10086 (ws) and 10087 (xhttp)."

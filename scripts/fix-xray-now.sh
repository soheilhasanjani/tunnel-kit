#!/usr/bin/env bash
# One-shot: start VLESS WS :10086 and XHTTP :10087.
#   sudo bash /opt/tunnel-kit/scripts/fix-xray-now.sh
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/fix-xray-now.sh" >&2
  exit 1
fi

CFG=/usr/local/etc/xray/config.json
OPT_ROOT=/opt/tunnel-kit
OVERRIDE=/etc/systemd/system/xray.service.d/20-tunnel-kit.conf

if [[ ! -f $CFG ]]; then
  echo "Missing $CFG — run install.sh first." >&2
  exit 1
fi

chmod 644 "$CFG"
mkdir -p /etc/systemd/system/xray.service.d /var/log/v2ray /var/log/xray
if [[ -f $OPT_ROOT/server/xray.override.conf ]]; then
  install -m 644 "$OPT_ROOT/server/xray.override.conf" "$OVERRIDE"
fi
chmod 755 /var/log/v2ray /var/log/xray
systemctl daemon-reload

echo "Testing config..."
/usr/local/bin/xray run -test -c "$CFG"

systemctl restart xray
sleep 1
echo "xray: $(systemctl is-active xray || true)"
echo "listeners:"
ss -lnt | awk 'NR==1 || $4 ~ /:(80|443|10086|10087|8787)$/'
if ! ss -lnt | awk '{print $4}' | grep -E ':10086$' >/dev/null; then
  echo
  echo "Still no :10086. Journal:"
  journalctl -u xray -n 30 --no-pager || true
  exit 1
fi
echo "Xray is on 10086/10087. Refresh the dashboard."

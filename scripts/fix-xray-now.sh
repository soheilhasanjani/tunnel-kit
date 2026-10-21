#!/usr/bin/env bash
# One-shot: stop Xray crashing on root-owned access.log and bind :443.
#   sudo bash /opt/tunnel-kit/scripts/fix-xray-now.sh
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/fix-xray-now.sh" >&2
  exit 1
fi

CFG=/usr/local/etc/xray/config.json
if [[ ! -f $CFG ]]; then
  echo "Missing $CFG — run install.sh first." >&2
  exit 1
fi

python3 - "$CFG" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
log = data.get("log") or {}
log["access"] = "none"
log.pop("error", None)
log.setdefault("loglevel", "warning")
data["log"] = log
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print("set log.access=none in", path)
PY

chmod 644 "$CFG"
mkdir -p /var/log/xray
rm -f /var/log/xray/access.log /var/log/xray/error.log
chmod 755 /var/log/xray
if getent group nogroup >/dev/null 2>&1; then
  chown -R nobody:nogroup /var/log/xray
else
  chown -R nobody:nobody /var/log/xray
fi

systemctl restart xray
sleep 1
echo "xray: $(systemctl is-active xray || true)"
echo "listeners:"
ss -lnt | awk 'NR==1 || $4 ~ /:(80|443|8443|8787)$/'
if ! ss -lnt | awk '{print $4}' | grep -E ':443$' >/dev/null; then
  echo
  echo "Still no :443. Journal:"
  journalctl -u xray -n 25 --no-pager || true
  exit 1
fi
echo "Xray is on 443."

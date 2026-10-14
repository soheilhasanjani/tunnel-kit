#!/usr/bin/env bash
# Re-render configs from /etc/tunnel-kit.env and restart services.
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/apply.sh" >&2
  exit 1
fi

OPT_ROOT=/opt/tunnel-kit
python3 "$OPT_ROOT/scripts/render.py" "$OPT_ROOT/server/xray.json.tpl" /usr/local/etc/xray/config.json
python3 "$OPT_ROOT/scripts/render.py" "$OPT_ROOT/server/Caddyfile.tpl" /etc/caddy/Caddyfile
systemctl restart caddy xray tunnel-kit-api
systemctl --no-pager --full status caddy xray tunnel-kit-api | sed -n '1,24p'
echo "Applied."

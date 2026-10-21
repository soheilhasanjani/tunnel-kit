#!/usr/bin/env bash
# Stop tunnel-kit services. Does not delete /etc/tunnel-kit.env unless you pass --purge.
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/uninstall.sh" >&2
  exit 1
fi

systemctl disable --now tunnel-kit-api 2>/dev/null || true
systemctl disable --now xray 2>/dev/null || true
systemctl disable --now caddy 2>/dev/null || true
rm -f /etc/systemd/system/tunnel-kit-api.service
rm -f /etc/systemd/system/xray.service.d/20-tunnel-kit.conf
rmdir /etc/systemd/system/xray.service.d 2>/dev/null || true
systemctl daemon-reload

if [[ ${1:-} == --purge ]]; then
  rm -rf /opt/tunnel-kit /var/www/tunnel-kit /etc/tunnel-kit.env /etc/tunnel-kit
  rm -f /etc/sysctl.d/99-tunnel-kit-bbr.conf
  echo "Removed app files and secrets."
else
  echo "Services stopped. Secrets kept in /etc/tunnel-kit.env"
  echo "To delete everything: sudo bash scripts/uninstall.sh --purge"
fi

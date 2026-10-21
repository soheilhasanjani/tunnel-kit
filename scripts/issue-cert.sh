#!/usr/bin/env bash
# Issue a Let's Encrypt cert for the proxy hostname and install it for Caddy.
# Needs port 80 reachable on this VPS (CDN may proxy HTTP). Run as root:
#   sudo bash /opt/tunnel-kit/scripts/issue-cert.sh
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/issue-cert.sh" >&2
  exit 1
fi

ENV_FILE=${TUNNEL_KIT_ENV:-/etc/tunnel-kit.env}
CERT_DIR=/etc/tunnel-kit/certs
WEBROOT=/var/www/acme

if [[ ! -f $ENV_FILE ]]; then
  echo "Missing $ENV_FILE — run scripts/install.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
DOMAIN=$(awk -F= '/^DOMAIN=/{print $2; exit}' "$ENV_FILE")
if [[ -z ${DOMAIN:-} ]]; then
  echo "DOMAIN is empty in $ENV_FILE" >&2
  exit 1
fi

if ! command -v certbot >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends certbot
fi

mkdir -p "$WEBROOT" "$CERT_DIR"

echo "Requesting a Let's Encrypt certificate for ${DOMAIN} (HTTP-01 via ${WEBROOT})..."
certbot certonly --webroot -w "$WEBROOT" -d "$DOMAIN" --agree-tos --non-interactive \
  --register-unsafely-without-email --keep-until-expiry

LIVE=/etc/letsencrypt/live/${DOMAIN}
if [[ ! -s $LIVE/fullchain.pem || ! -s $LIVE/privkey.pem ]]; then
  echo "certbot did not write $LIVE/{fullchain,privkey}.pem" >&2
  exit 1
fi

if id caddy >/dev/null 2>&1; then
  install -m 640 -o root -g caddy "$LIVE/fullchain.pem" "$CERT_DIR/cert.pem"
  install -m 640 -o root -g caddy "$LIVE/privkey.pem" "$CERT_DIR/key.pem"
else
  install -m 640 "$LIVE/fullchain.pem" "$CERT_DIR/cert.pem"
  install -m 640 "$LIVE/privkey.pem" "$CERT_DIR/key.pem"
fi
systemctl reload caddy

echo "Installed certificate for ${DOMAIN} -> ${CERT_DIR}/cert.pem"
echo "Reload any CDN SSL settings so it trusts a public CA (not a Cloudflare Origin CA)."

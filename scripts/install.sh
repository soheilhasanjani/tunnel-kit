#!/usr/bin/env bash
# Install Xray + Caddy + dashboard on Ubuntu. Prefer cloning on the VPS:
#   git clone https://github.com/soheilhasanjani/tunnel-kit.git
#   cd tunnel-kit && sudo bash scripts/install.sh
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run this as root: sudo bash scripts/install.sh" >&2
  exit 1
fi

if [[ ! -f /etc/os-release ]] || ! grep -qiE 'ubuntu|debian' /etc/os-release; then
  echo "This script expects Ubuntu or Debian." >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
OPT_ROOT=/opt/tunnel-kit
ENV_FILE=/etc/tunnel-kit.env
CERT_DIR=/etc/tunnel-kit/certs
WWW_DIR=/var/www/tunnel-kit

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ask() {
  local prompt=$1 default=${2:-} value
  if [[ -n $default ]]; then
    read -r -p "$prompt [$default]: " value || true
    echo "${value:-$default}"
  else
    read -r -p "$prompt: " value
    echo "$value"
  fi
}

ask_secret() {
  local prompt=$1 value
  read -r -s -p "$prompt: " value
  echo >&2
  echo "$value"
}

public_ip() {
  curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null \
    || curl -4 -fsS --max-time 8 https://ifconfig.me 2>/dev/null \
    || hostname -I | awk '{print $1}'
}

parse_x25519() {
  # Supports both "PrivateKey/Password" and "Private key/Public key" output.
  local out private public
  out=$(/usr/local/bin/xray x25519)
  private=$(printf '%s\n' "$out" | awk -F': *' '/[Pp]rivate/{print $2; exit}')
  public=$(printf '%s\n' "$out" | awk -F': *' '/Password:|[Pp]ublic/{print $2; exit}')
  if [[ -z $private || -z $public ]]; then
    echo "Could not parse xray x25519 output:" >&2
    echo "$out" >&2
    exit 1
  fi
  printf '%s %s\n' "$private" "$public"
}

echo
echo "=== tunnel-kit installer ==="
echo "You will need:"
echo "  1. A hostname for the proxied profile, e.g. vpn.example.com"
echo "  2. Any reverse proxy / CDN in front of this VPS (Cloudflare, Fastly, nginx, ...)"
echo "     or skip that and use Reality only"
echo "  3. Optional DNS-only name for Reality, e.g. direct.yourdomain.com"
echo

DOMAIN=$(ask "Proxy hostname (clients + CDN), e.g. vpn.example.com")
if [[ -z $DOMAIN ]]; then
  echo "Domain is required." >&2
  exit 1
fi

PROXY_NAME=$(ask "Reverse proxy / CDN name (Cloudflare, Fastly, Bunny, nginx, ...)" "CDN")
DEFAULT_DIRECT=$(public_ip)
DIRECT_HOST=$(ask "Reality host (DNS-only name or this server IP)" "$DEFAULT_DIRECT")
DASHBOARD_PASSWORD=$(ask_secret "Dashboard password (you will type this in the browser)")
if [[ -z $DASHBOARD_PASSWORD ]]; then
  echo "Password is required." >&2
  exit 1
fi

echo
echo "Installing packages (this takes a minute)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg ufw python3 openssl rsync \
  debian-keyring debian-archive-keyring apt-transport-https

if ! need_cmd node || ! node -e 'process.exit(Number(process.versions.node.split(".")[0] < 18))'; then
  echo "Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi

if ! need_cmd xray && [[ ! -x /usr/local/bin/xray ]]; then
  echo "Installing Xray..."
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

if ! need_cmd caddy; then
  echo "Installing Caddy..."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update -y
  apt-get install -y caddy
fi

mkdir -p "$OPT_ROOT" "$CERT_DIR" "$WWW_DIR" /var/www/acme /var/log/xray
if [[ $REPO_ROOT != "$OPT_ROOT" ]]; then
  rsync -a \
    --exclude '.git' \
    --exclude 'web/node_modules' \
    --exclude 'web/dist' \
    "$REPO_ROOT/" "$OPT_ROOT/"
fi

write_env() {
  python3 - "$ENV_FILE" "$CERT_DIR" <<'PY' "$@"
import pathlib, sys
path = pathlib.Path(sys.argv[1])
cert_dir = sys.argv[2]
values = dict(item.split("=", 1) for item in sys.argv[3:])
if path.exists():
    print(f"Updating {path} (existing keys are kept)")
    current = {}
    for line in path.read_text().splitlines():
        if line.strip() and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            current[k] = v
    for key in ("UUID", "XHTTP_PATH", "REALITY_PRIVATE_KEY", "REALITY_PUBLIC_KEY", "REALITY_SHORT_ID", "SESSION_SECRET"):
        if key in current:
            values[key] = current[key]
    values.setdefault("XHTTP_PORT", current.get("XHTTP_PORT", "10000"))
    values.setdefault("CADDY_HTTPS_PORT", current.get("CADDY_HTTPS_PORT", "8443"))
    values.setdefault("PROXY_NAME", current.get("PROXY_NAME", "CDN"))
else:
    print("Generating secrets...")
values["CERT_FILE"] = f"{cert_dir}/cert.pem"
values["KEY_FILE"] = f"{cert_dir}/key.pem"
values["API_HOST"] = "127.0.0.1"
values["API_PORT"] = "8787"
values["TUNNEL_KIT_ENV"] = str(path)
order = [
    "DOMAIN", "PROXY_NAME", "DIRECT_HOST", "PUBLIC_IP", "UUID", "XHTTP_PATH",
    "XHTTP_PORT", "CADDY_HTTPS_PORT", "REALITY_PRIVATE_KEY", "REALITY_PUBLIC_KEY",
    "REALITY_SHORT_ID", "REALITY_SNI", "DASHBOARD_PASSWORD", "SESSION_SECRET",
    "CERT_FILE", "KEY_FILE", "API_HOST", "API_PORT", "TUNNEL_KIT_ENV",
]
lines = [f"{k}={values[k]}" for k in order if k in values]
path.write_text("\n".join(lines) + "\n")
path.chmod(0o600)
PY
}

UUID=$(/usr/local/bin/xray uuid)
read -r REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY <<<"$(parse_x25519)"
REALITY_SHORT_ID=$(openssl rand -hex 4)
XHTTP_PATH="/$(openssl rand -hex 12)"
SESSION_SECRET=$(openssl rand -hex 32)
PUBLIC_IP=$(public_ip)

write_env \
  "DOMAIN=${DOMAIN}" \
  "PROXY_NAME=${PROXY_NAME}" \
  "DIRECT_HOST=${DIRECT_HOST}" \
  "PUBLIC_IP=${PUBLIC_IP}" \
  "UUID=${UUID}" \
  "XHTTP_PATH=${XHTTP_PATH}" \
  "XHTTP_PORT=10000" \
  "CADDY_HTTPS_PORT=8443" \
  "REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}" \
  "REALITY_PUBLIC_KEY=${REALITY_PUBLIC_KEY}" \
  "REALITY_SHORT_ID=${REALITY_SHORT_ID}" \
  "REALITY_SNI=${DOMAIN}" \
  "DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}" \
  "SESSION_SECRET=${SESSION_SECRET}"

systemctl stop caddy 2>/dev/null || true
systemctl stop xray 2>/dev/null || true

if [[ ! -s $CERT_DIR/cert.pem || ! -s $CERT_DIR/key.pem ]]; then
  echo "No origin certificate found. Creating a temporary self-signed cert."
  echo "Any CDN that verifies the origin certificate will FAIL until you replace these files."
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -days 825 -nodes \
    -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
    -subj "/CN=${DOMAIN}" >/dev/null 2>&1
  chmod 640 "$CERT_DIR/key.pem" "$CERT_DIR/cert.pem"
fi
if id caddy >/dev/null 2>&1; then
  chown root:caddy "$CERT_DIR/cert.pem" "$CERT_DIR/key.pem"
  chmod 640 "$CERT_DIR/cert.pem" "$CERT_DIR/key.pem"
fi

echo "Writing Xray and Caddy configs..."
python3 "$OPT_ROOT/scripts/render.py" "$OPT_ROOT/server/xray.json.tpl" /usr/local/etc/xray/config.json
python3 "$OPT_ROOT/scripts/render.py" "$OPT_ROOT/server/Caddyfile.tpl" /etc/caddy/Caddyfile
/usr/local/bin/xray run -test -c /usr/local/etc/xray/config.json
install -m 644 "$OPT_ROOT/server/sysctl-bbr.conf" /etc/sysctl.d/99-tunnel-kit-bbr.conf
sysctl -p /etc/sysctl.d/99-tunnel-kit-bbr.conf >/dev/null || true
install -m 644 "$OPT_ROOT/server/tunnel-kit-api.service" /etc/systemd/system/tunnel-kit-api.service

echo "Building dashboard..."
cd "$OPT_ROOT/web"
npm install
npm run build
rm -rf "$WWW_DIR"
mkdir -p "$WWW_DIR"
cp -a dist/. "$WWW_DIR/"

echo "Firewall: allow SSH, HTTP (ACME), and HTTPS..."
ufw allow 22/tcp >/dev/null
ufw allow OpenSSH >/dev/null || true
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

systemctl daemon-reload
systemctl enable --now caddy xray tunnel-kit-api
systemctl restart caddy xray tunnel-kit-api

echo
echo "=== Done ==="
echo "Browser dashboard:  https://${DOMAIN}"
echo "Reverse proxy / CDN: ${PROXY_NAME}"
echo
echo "DNS:"
echo "  ${DOMAIN}        -> this VPS (through ${PROXY_NAME})"
echo "  ${DIRECT_HOST}   -> this VPS IP, DNS only   [Reality; skip if this is already an IP]"
echo
echo "Origin certificate (the CDN must trust it):"
echo "  Cloudflare Origin CA, or: sudo bash ${OPT_ROOT}/scripts/issue-cert.sh"
echo "  save cert  -> ${CERT_DIR}/cert.pem"
echo "  save key   -> ${CERT_DIR}/key.pem"
echo "  then: systemctl reload caddy"
echo
echo "On your phone: open the dashboard, scan  Stable / Reality  first."
echo "Secrets file: ${ENV_FILE}  (do not commit this)"
echo

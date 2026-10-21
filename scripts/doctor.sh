#!/usr/bin/env bash
# Print why the dashboard URL might not open. Run on the VPS:
#   sudo bash /opt/tunnel-kit/scripts/doctor.sh
set -u

ENV_FILE=${TUNNEL_KIT_ENV:-/etc/tunnel-kit.env}
fail=0

read_env() {
  local key=$1
  [[ -f $ENV_FILE ]] || return 0
  awk -F= -v k="$key" '$1==k {print substr($0, index($0, "=")+1); exit}' "$ENV_FILE"
}

DOMAIN=$(read_env DOMAIN)
PUBLIC_IP=$(read_env PUBLIC_IP)
if [[ -z ${PUBLIC_IP:-} ]] && command -v curl >/dev/null 2>&1; then
  PUBLIC_IP=$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
fi
if [[ -z ${PUBLIC_IP:-} ]]; then
  PUBLIC_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

echo "=== tunnel-kit doctor ==="
echo "Env file: ${ENV_FILE}"
echo "Proxy hostname: ${DOMAIN:-<missing>}"
echo

check_svc() {
  local name=$1
  if systemctl is-active --quiet "$name"; then
    echo "OK   service ${name} is running"
  else
    echo "FAIL service ${name} is NOT running"
    systemctl --no-pager --full status "$name" 2>/dev/null | sed -n '1,8p' || true
    fail=1
  fi
}

check_svc xray
check_svc caddy
check_svc tunnel-kit-api
echo

if [[ -e /var/log/xray/access.log ]]; then
  logperms=$(stat -c '%a %U:%G' /var/log/xray/access.log 2>/dev/null || true)
  echo "Xray access.log: ${logperms}"
  owner=${logperms##* }
  if [[ $owner == root:root ]]; then
    echo "FAIL /var/log/xray/access.log is root-owned; Xray (nobody) cannot write it."
    echo "     fix: sudo chown -R nobody:nogroup /var/log/xray && sudo systemctl restart xray"
    fail=1
  fi
fi

XRAY_CFG=/usr/local/etc/xray/config.json
if [[ -f $XRAY_CFG ]]; then
  perms=$(stat -c '%a %U:%G' "$XRAY_CFG" 2>/dev/null || stat -f '%OLp %Su:%Sg' "$XRAY_CFG")
  echo "Xray config: ${XRAY_CFG} (${perms})"
  mode=${perms%% *}
  if [[ $mode != 644 && $mode != 664 && $mode != 755 ]]; then
    echo "FAIL Xray config mode is ${mode}; the xray user (nobody) must be able to read it."
    echo "     fix: chmod 644 ${XRAY_CFG} && systemctl restart xray"
    fail=1
  fi
else
  echo "FAIL missing ${XRAY_CFG}"
  fail=1
fi
if [[ -x /usr/local/bin/xray && -f $XRAY_CFG ]]; then
  echo "Xray config test (as nobody):"
  if id nobody >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
    if runuser -u nobody -- /usr/local/bin/xray run -test -c "$XRAY_CFG"; then
      echo "OK   xray -test as nobody"
    else
      echo "FAIL xray -test as nobody (exit $?). This is why port 443 is down."
      fail=1
    fi
  elif /usr/local/bin/xray run -test -c "$XRAY_CFG"; then
    echo "OK   xray -test as root"
  else
    echo "FAIL xray -test failed"
    fail=1
  fi
fi
if ! systemctl is-active --quiet xray; then
  echo "--- journalctl -u xray ---"
  journalctl -u xray -n 25 --no-pager || true
  echo "--------------------------"
fi
echo

listening() {
  local spec=$1
  if ! command -v ss >/dev/null 2>&1; then
    echo "WARN ss not installed; skip port ${spec}"
    return 0
  fi
  if ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "$spec"; then
    echo "OK   listening ${spec}"
  else
    echo "FAIL not listening ${spec}"
    fail=1
  fi
}

listening ':80$'
listening ':443$'
listening ':8443$'
listening ':8787$'
echo

if curl -fsS -m 5 http://127.0.0.1/api/health >/dev/null; then
  echo "OK   http://127.0.0.1/api/health"
else
  echo "FAIL dashboard HTTP on port 80 (Caddy). The browser page cannot load."
  fail=1
fi

if curl -fskS -m 5 https://127.0.0.1:8443/api/health >/dev/null; then
  echo "OK   local HTTPS origin on 8443"
else
  echo "WARN local HTTPS origin on 8443 did not answer (CDN https:// may fail until the cert is valid)"
fi

if [[ -s /etc/tunnel-kit/certs/cert.pem && -s /etc/tunnel-kit/certs/key.pem ]]; then
  subj=$(openssl x509 -in /etc/tunnel-kit/certs/cert.pem -noout -subject 2>/dev/null || true)
  issuer=$(openssl x509 -in /etc/tunnel-kit/certs/cert.pem -noout -issuer 2>/dev/null || true)
  echo "OK   origin cert ${subj}"
  echo "     ${issuer}"
  if [[ -n $subj && $subj == "$issuer" ]]; then
    echo "WARN cert is self-signed. Chrome and Cloudflare Full (strict) will refuse https:// until you replace it."
  fi
else
  echo "FAIL missing /etc/tunnel-kit/certs/cert.pem or key.pem"
  fail=1
fi

echo
echo "Open in a web browser (this is the dashboard):"
if [[ -n ${PUBLIC_IP:-} ]]; then
  echo "  http://${PUBLIC_IP}/          ← try this first"
fi
if [[ -n ${DOMAIN:-} ]]; then
  echo "  http://${DOMAIN}/"
  echo "  https://${DOMAIN}/         ← needs a real origin certificate + CDN SSL"
fi
echo
echo "Do NOT paste vless:// links into Chrome. Those are for v2rayNG / Hiddify / Streisand."
echo
echo "If HTTP works but HTTPS does not:"
echo "  Cloudflare SSL/TLS: use Full (strict) only AFTER an Origin Certificate"
echo "  or run: sudo bash /opt/tunnel-kit/scripts/issue-cert.sh"
echo
if [[ $fail -ne 0 ]]; then
  echo "Doctor found problems. Fix the FAIL lines, then:"
  echo "  sudo bash /opt/tunnel-kit/scripts/apply.sh"
  exit 1
fi
echo "Doctor: no local FAIL lines. If the public URL still fails, it is DNS or the CDN in front."

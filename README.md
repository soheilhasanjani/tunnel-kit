# tunnel-kit

Personal V2Ray/Xray on an Ubuntu VPS, with a small web dashboard.

You get **two** ways to connect:

1. **Stable / Reality** — phone talks straight to your VPS. Use this every day.
2. **Cloudflare** — hides your server IP. Backup if Reality is blocked.

The dashboard shows both as QR codes.

You do **not** need to be a sysadmin. Follow the steps in order. If a step fails, stop and fix that step before continuing.

## What you need

- An Ubuntu VPS (a rented Linux computer) and its **IP address**
- SSH access (`root` or a user that can `sudo`)
- A domain in **Cloudflare** (example: `example.com`)

## 1. Cloudflare DNS

In Cloudflare, open your domain → **DNS**.

Add two A records, both pointing to your **VPS IP**:

| Name | Content | Proxy |
| --- | --- | --- |
| `vpn` | VPS IP | **Proxied** (orange cloud) |
| `direct` | VPS IP | **DNS only** (grey cloud) |

That gives you:

- `vpn.example.com` — dashboard + Cloudflare proxy (orange)
- `direct.example.com` — Reality (grey, not through Cloudflare)

Then: **SSL/TLS** → overview → set encryption mode to **Full (strict)**.

Do this **after** you install the origin certificate in step 4. Until then, **Full** (not Flexible) is OK.

## 2. Copy this folder to the VPS

On **your laptop** (in this project folder):

```bash
rsync -av --exclude .git --exclude node_modules --exclude web/node_modules --exclude web/dist . root@YOUR_VPS_IP:~/tunnel-kit
ssh root@YOUR_VPS_IP
cd ~/tunnel-kit
bash scripts/install.sh
```

Replace `YOUR_VPS_IP` with the server IP.

The installer asks for:

- Cloudflare domain — type `vpn.example.com` (the orange one)
- Reality host — type `direct.example.com` (the grey one)
- Dashboard password — invent one and remember it

Wait until it prints `=== Done ===`.

## 3. Origin certificate (so HTTPS works through Cloudflare)

Cloudflare must trust your VPS. A normal Let's Encrypt cert is harder here because Xray owns port 443.

1. Cloudflare → **SSL/TLS** → **Origin Server** → **Create Certificate**
2. Leave the default hostnames (your domain and `*.yourdomain.com`)
3. Create
4. On the VPS, paste them into these two files:

```bash
nano /etc/tunnel-kit/certs/cert.pem    # the certificate block
nano /etc/tunnel-kit/certs/key.pem     # the private key block
```

Save, then:

```bash
chown root:caddy /etc/tunnel-kit/certs/cert.pem /etc/tunnel-kit/certs/key.pem
chmod 640 /etc/tunnel-kit/certs/cert.pem /etc/tunnel-kit/certs/key.pem
systemctl reload caddy
```

Set Cloudflare SSL/TLS to **Full (strict)**.

## 4. Open the dashboard

In a browser: `https://vpn.example.com`

Log in with the dashboard password. You should see Xray **running** and two QR codes.

- Scan **Stable / Reality** first
- Keep **Cloudflare** as a backup

## 5. Phone / laptop apps

Install a **recent** client (old apps do not support XHTTP / Reality):

- Android: **v2rayNG** or **Hiddify**
- iOS: **Streisand** or **Hiddify**
- Windows / Mac: **v2rayN** or **Hiddify**

Scan the QR (or copy the link). In Hiddify you can import **both** and let it fail over.

Mux / multiplexing: leave **off**.

## If something is wrong

On the VPS:

```bash
systemctl status xray caddy tunnel-kit-api
journalctl -u xray -n 50 --no-pager
journalctl -u caddy -n 50 --no-pager
```

Re-apply configs after you edit `/etc/tunnel-kit.env`:

```bash
bash /opt/tunnel-kit/scripts/apply.sh
```

Secrets live in `/etc/tunnel-kit.env`. Do not put that file in git.

## Uninstall

```bash
sudo bash /opt/tunnel-kit/scripts/uninstall.sh
# or delete secrets too:
sudo bash /opt/tunnel-kit/scripts/uninstall.sh --purge
```

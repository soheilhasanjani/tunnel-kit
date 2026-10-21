# tunnel-kit

Personal V2Ray/Xray on an Ubuntu VPS, with a small web dashboard.

You get **two** ways to connect:

1. **Stable / Reality** — the phone talks straight to your VPS. Use this every day.
2. **Proxied** — traffic goes through **any** reverse proxy or CDN in front of the VPS (Cloudflare, Fastly, Bunny, nginx, Caddy, HAProxy, …). That hides the server IP. Use it as a backup if Reality is blocked.

The dashboard shows both as QR codes.

You do **not** need to be a sysadmin. Follow the steps in order. If a step fails, stop and fix that step before continuing.

## What Cloudflare did here (and what changed)

This project used to assume **Cloudflare** was the only proxy: orange-cloud DNS, an Origin Certificate, and a dashboard profile literally named “Cloudflare”.

Cloudflare is still a good choice. It is just **one** reverse proxy. The proxied profile is now generic:

- Clients connect to your **proxy hostname** (example: `vpn.example.com`) with VLESS + XHTTP + TLS.
- Whatever sits in front — Cloudflare, another CDN, or a second VPS running nginx/Caddy/HAProxy — terminates or forwards that TLS and sends it to this VPS on port **443**.
- Xray owns 443. Connections that are not Reality fall through to Caddy, which serves the dashboard and the XHTTP path.

Reality (direct) is unchanged. It does **not** go through the CDN.

## What you need

- An **Ubuntu** VPS (22.04 or 24.04) and its **IP address**
- SSH access (`root` or a user that can `sudo`)
- A domain, plus **any** reverse proxy / CDN you want in front (or skip the proxy and use Reality only)

## 1. Clone this project on the Ubuntu VPS

SSH into the server, then clone with `git` (preferred):

```bash
ssh root@YOUR_VPS_IP

apt-get update
apt-get install -y git

git clone https://github.com/soheilhasanjani/tunnel-kit.git
cd tunnel-kit
bash scripts/install.sh
```

Replace `YOUR_VPS_IP` with the server IP.

If the repo is private, use SSH instead of HTTPS:

```bash
git clone git@github.com:soheilhasanjani/tunnel-kit.git
cd tunnel-kit
bash scripts/install.sh
```

From a laptop you can still copy the folder with `rsync` instead of cloning:

```bash
rsync -av --exclude .git --exclude node_modules --exclude web/node_modules --exclude web/dist . root@YOUR_VPS_IP:~/tunnel-kit
ssh root@YOUR_VPS_IP
cd ~/tunnel-kit
bash scripts/install.sh
```

The installer asks for:

- **Proxy hostname** — `vpn.example.com` (the name clients and the CDN use)
- **Proxy / CDN name** — `Cloudflare`, `Fastly`, `Bunny`, `nginx`, or any label you like
- **Reality host** — `direct.example.com` (DNS-only) or the VPS IP
- **Dashboard password** — invent one and remember it

Wait until it prints `=== Done ===`.

## 2. DNS

You need two names. How you create them depends on the proxy, but the idea is the same:

| Name | Points at | Proxied? |
| --- | --- | --- |
| `vpn.example.com` | VPS IP (or the CDN origin) | **Yes** — through Cloudflare / Fastly / nginx / … |
| `direct.example.com` | VPS IP | **No** — DNS only, for Reality |

That gives you:

- `vpn.example.com` — dashboard + the proxied XHTTP profile
- `direct.example.com` — Reality (straight to the VPS)

### ArvanCloud (ابر آروان)

This is the usual setup in Iran. Two A records, both to the VPS IP (`64.227.29.143` in the example):

| Record | Cloud icon | Why |
| --- | --- | --- |
| `vpn` → `vpn.akbarbegins.ir` | **ON** (active cloud) | Dashboard + proxied XHTTP. Visitors hit ArvanCloud, not the raw IP. |
| `direct` → `direct.akbarbegins.ir` | **OFF** | Reality. Must skip the CDN or Reality breaks. |

The raw IP (`http://64.227.29.143/`) opening the dashboard is expected: that hits Caddy on **port 80**. The domain `vpn.…` goes through ArvanCloud, which by default talks to origin **port 443**. If Xray is down, 443 is closed, so **the domain fails and the IP still works**.

In ArvanCloud → **CDN** → your domain:

1. **HTTPS for visitors** — enable it and issue Arvan’s free edge certificate so `https://vpn.akbarbegins.ir` has a valid public cert. That cert is on ArvanCloud, not on the VPS.
2. **Origin protocol / اتصال به سرور اصلی** for the `vpn` record — set to **HTTP** until Xray is listening on 443 and you have a real origin certificate. Then ArvanCloud fetches `http://VPS:80` (the dashboard).
3. Do **not** set origin to HTTPS while Xray is down, or while the VPS cert is self-signed. That is why `vpn.akbarbegins.ir` does not load.
4. After Xray is `active` **and** `ss` shows `0.0.0.0:443` (not `8443`), you may switch origin to HTTPS and install an origin cert (`scripts/issue-cert.sh`).

### Cloudflare (still supported)

In Cloudflare → **DNS**, add two A records to the VPS IP:

- `vpn` → **Proxied** (orange cloud)
- `direct` → **DNS only** (grey cloud)

Then **SSL/TLS** → overview → **Full (strict)** after the origin certificate is installed. Until then, **Full** (not Flexible) is OK.

### Other CDNs (Fastly, Bunny, CloudFront, …)

Create a hostname (`vpn.example.com`) whose origin is this VPS, **port 443**, HTTPS. Use a second DNS-only name (or the raw IP) for Reality.

The CDN must talk HTTPS to the origin and leave the URL path unchanged (the XHTTP path is a secret prefix). HTTP/2 to origin is best.

### Another VPS as the reverse proxy (nginx / Caddy / HAProxy)

Point `vpn.example.com` at the **proxy** VPS, not the origin. Forward 443 to the origin VPS.

TCP passthrough (simplest, works with any TLS client):

```nginx
# nginx on the proxy VPS — /etc/nginx/nginx.conf (stream {})
stream {
    server {
        listen 443;
        proxy_pass ORIGIN_VPS_IP:443;
        proxy_connect_timeout 5s;
    }
}
```

Caddy on the proxy VPS (HTTP reverse proxy, HTTP/2):

```caddy
vpn.example.com {
	reverse_proxy https://ORIGIN_VPS_IP {
		header_up Host {host}
		transport http {
			tls_server_name vpn.example.com
			versions h2
		}
	}
}
```

Replace `ORIGIN_VPS_IP` with the tunnel-kit server. Reality still uses `direct.example.com` (or the origin IP) so it does not go through this proxy.

## 3. TLS certificate on the origin

The reverse proxy must trust the certificate Caddy presents on the VPS. A normal public HTTPS listener on 443 is not used here, because **Xray owns port 443**. Put the cert files here:

```bash
nano /etc/tunnel-kit/certs/cert.pem    # certificate (full chain)
nano /etc/tunnel-kit/certs/key.pem     # private key
```

Then:

```bash
chown root:caddy /etc/tunnel-kit/certs/cert.pem /etc/tunnel-kit/certs/key.pem
chmod 640 /etc/tunnel-kit/certs/cert.pem /etc/tunnel-kit/certs/key.pem
systemctl reload caddy
```

Pick **one** source for those files:

### Cloudflare Origin Certificate

1. Cloudflare → **SSL/TLS** → **Origin Server** → **Create Certificate**
2. Leave the default hostnames (your domain and `*.yourdomain.com`)
3. Paste the cert and key into the two files above
4. Set Cloudflare SSL/TLS to **Full (strict)**

### Let’s Encrypt (any other CDN or nginx reverse proxy)

Port **80** must reach this VPS (open on the firewall; the CDN can proxy HTTP). Then:

```bash
sudo bash /opt/tunnel-kit/scripts/issue-cert.sh
```

That uses HTTP-01, writes the same `cert.pem` / `key.pem` paths, and reloads Caddy.

### Already have a cert

Copy any valid cert for `vpn.example.com` (or a covering wildcard) into those two files. Self-signed only works if the reverse proxy does **not** verify the origin cert.

## 4. Open the dashboard

**Use a web browser**, and try HTTP first (this does not need a certificate):

```text
http://YOUR_VPS_IP/
http://vpn.example.com/
```

Log in with the dashboard password. You should see Xray **running** and two QR codes.

- Scan **Stable / Reality** first
- Keep **Proxied** (labeled with your CDN name) as a backup

`https://vpn.example.com` only works after step 3 (a real origin certificate). A `vless://` link is **not** a website — Chrome will not load it. Paste that into v2rayNG / Hiddify.

If you already installed an older copy, update then check:

```bash
cd ~/tunnel-kit   # or wherever you cloned it
git pull
sudo bash scripts/update.sh
sudo bash /opt/tunnel-kit/scripts/doctor.sh
```

## 5. Phone / laptop apps

Install a **recent** client (old apps do not support XHTTP / Reality):

- Android: **v2rayNG** or **Hiddify**
- iOS: **Streisand** or **Hiddify**
- Windows / Mac: **v2rayN** or **Hiddify**

Scan the QR (or copy the link). In Hiddify you can import **both** and let it fail over.

Mux / multiplexing: leave **off**.

## If the address does not load

The usual causes:

1. **Xray is not running** (dashboard shows Xray **down**, `ss` has no `0.0.0.0:443`). `grep 443` also matches Caddy’s **8443** — that is not Xray. Xray runs as `nobody`. Exit **23** is usually:
   - `config.json` mode `600` (cannot read), or
   - `/var/log/xray/access.log` owned by **root** (cannot write). `chown` on the directory does not change that file. `scripts/apply.sh` now `chown -R` the log dir and sends Xray logs to the systemd journal instead.
2. You opened `https://…` before installing an origin certificate (browser or Cloudflare Error 526).
3. You pasted a `vless://` share link into the browser. That is for the phone app.
4. You opened the VPS **IP on port 443**. Xray owns 443; the website is on **port 80**.

On the VPS:

```bash
sudo bash /opt/tunnel-kit/scripts/fix-xray-now.sh
sudo bash /opt/tunnel-kit/scripts/doctor.sh
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

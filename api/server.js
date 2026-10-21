#!/usr/bin/env node
"use strict";

const http = require("http");
const crypto = require("crypto");
const fs = require("fs");
const { execFileSync } = require("child_process");

const PORT = Number(process.env.API_PORT || 8787);
const HOST = process.env.API_HOST || "127.0.0.1";
const ENV_PATH = process.env.TUNNEL_KIT_ENV || "/etc/tunnel-kit.env";

function loadEnv(path) {
  const out = {};
  if (!fs.existsSync(path)) return out;
  for (const raw of fs.readFileSync(path, "utf8").split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) continue;
    const i = line.indexOf("=");
    out[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return out;
}

function env(key, fallback = "") {
  return process.env[key] || CFG[key] || fallback;
}

let CFG = loadEnv(ENV_PATH);

function reloadCfg() {
  CFG = loadEnv(ENV_PATH);
}

function cookieToken() {
  const secret = env("SESSION_SECRET");
  if (!secret) return "";
  return crypto.createHmac("sha256", secret).update("tunnel-kit").digest("hex");
}

function parseCookies(header) {
  const out = {};
  if (!header) return out;
  for (const part of header.split(";")) {
    const i = part.indexOf("=");
    if (i === -1) continue;
    out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

function timingSafeEqual(a, b) {
  const ab = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
}

function isAuthed(req) {
  const token = cookieToken();
  if (!token) return false;
  const cookies = parseCookies(req.headers.cookie);
  return Boolean(cookies.tk_session && timingSafeEqual(cookies.tk_session, token));
}

function send(res, status, body, extraHeaders = {}) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(data),
    ...extraHeaders,
  });
  res.end(data);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > 4096) {
        reject(new Error("body too large"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => {
      if (!chunks.length) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch (err) {
        reject(err);
      }
    });
    req.on("error", reject);
  });
}

function serviceActive(name) {
  try {
    execFileSync("systemctl", ["is-active", "--quiet", name], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function encodeQuery(params) {
  return Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join("&");
}

function proxyLabel() {
  return env("PROXY_NAME") || "CDN";
}

function shareFragment(name) {
  return encodeURIComponent(String(name || "Proxied").replace(/\s+/g, "-"));
}

function shareLinks() {
  const uuid = env("UUID");
  const domain = env("DOMAIN");
  const direct = env("DIRECT_HOST") || env("PUBLIC_IP") || domain;
  const path = env("XHTTP_PATH");
  const pbk = env("REALITY_PUBLIC_KEY");
  const sid = env("REALITY_SHORT_ID");
  const sni = env("REALITY_SNI") || domain;
  const proxyName = proxyLabel();

  const reality =
    `vless://${uuid}@${direct}:443?` +
    encodeQuery({
      encryption: "none",
      flow: "xtls-rprx-vision",
      security: "reality",
      sni,
      fp: "chrome",
      pbk,
      sid,
      type: "tcp",
      headerType: "none",
    }) +
    "#Reality-Stable";

  const proxy =
    `vless://${uuid}@${domain}:443?` +
    encodeQuery({
      encryption: "none",
      security: "tls",
      sni: domain,
      host: domain,
      fp: "chrome",
      alpn: "h2",
      type: "xhttp",
      path,
      mode: "packet-up",
    }) +
    `#${shareFragment(proxyName)}`;

  return { reality, proxy, proxyName };
}

async function handler(req, res) {
  const url = new URL(req.url, "http://127.0.0.1");
  const path = url.pathname;

  if (req.method === "GET" && path === "/api/health") {
    return send(res, 200, { ok: true });
  }

  if (req.method === "POST" && path === "/api/login") {
    reloadCfg();
    let body;
    try {
      body = await readJson(req);
    } catch {
      return send(res, 400, { error: "Invalid JSON" });
    }
    const password = env("DASHBOARD_PASSWORD");
    if (!password || !timingSafeEqual(String(body.password || ""), password)) {
      return send(res, 401, { error: "Wrong password" });
    }
    const token = cookieToken();
    const secure = req.headers["x-forwarded-proto"] === "https";
    const cookie = [
      `tk_session=${token}`,
      "Path=/",
      "HttpOnly",
      "SameSite=Lax",
      "Max-Age=2592000",
      ...(secure ? ["Secure"] : []),
    ].join("; ");
    return send(res, 200, { ok: true }, { "Set-Cookie": cookie });
  }

  if (req.method === "POST" && path === "/api/logout") {
    const secure = req.headers["x-forwarded-proto"] === "https";
    const cookie = `tk_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${secure ? "; Secure" : ""}`;
    return send(res, 200, { ok: true }, { "Set-Cookie": cookie });
  }

  if (!isAuthed(req)) {
    return send(res, 401, { error: "Login required" });
  }

  if (req.method === "GET" && path === "/api/status") {
    reloadCfg();
    return send(res, 200, {
      xray: serviceActive("xray"),
      caddy: serviceActive("caddy"),
      api: true,
      domain: env("DOMAIN"),
      proxyName: proxyLabel(),
      directHost: env("DIRECT_HOST") || env("PUBLIC_IP"),
    });
  }

  if (req.method === "GET" && path === "/api/share") {
    reloadCfg();
    const links = shareLinks();
    return send(res, 200, {
      domain: env("DOMAIN"),
      proxyName: links.proxyName,
      directHost: env("DIRECT_HOST") || env("PUBLIC_IP"),
      profiles: [
        {
          id: "reality",
          title: "Stable / Reality",
          hint: "Use this every day. Direct to your VPS, usually the steadiest.",
          link: links.reality,
        },
        {
          id: "proxy",
          title: links.proxyName,
          hint: `Goes through ${links.proxyName} and hides the VPS IP. Backup if Reality is blocked.`,
          link: links.proxy,
        },
      ],
    });
  }

  return send(res, 404, { error: "Not found" });
}

const server = http.createServer((req, res) => {
  handler(req, res).catch((err) => {
    console.error(err);
    send(res, 500, { error: "Server error" });
  });
});

server.listen(PORT, HOST, () => {
  console.log(`tunnel-kit api on ${HOST}:${PORT}`);
});

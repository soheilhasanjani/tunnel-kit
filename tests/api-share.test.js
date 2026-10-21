#!/usr/bin/env node
"use strict";

const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

const PORT = 18787;
const PASSWORD = "test-dashboard-pass";
const envPath = path.join(os.tmpdir(), `tunnel-kit-test-${process.pid}.env`);

fs.writeFileSync(
  envPath,
  [
    "DOMAIN=vpn.example.com",
    "PROXY_NAME=Fastly",
    "DIRECT_HOST=direct.example.com",
    "PUBLIC_IP=203.0.113.10",
    "UUID=00000000-0000-4000-8000-000000000000",
    "XHTTP_PATH=/secretpath",
    "REALITY_PUBLIC_KEY=publickey",
    "REALITY_SHORT_ID=abcd1234",
    "REALITY_SNI=vpn.example.com",
    `DASHBOARD_PASSWORD=${PASSWORD}`,
    "SESSION_SECRET=session-secret-for-tests",
  ].join("\n") + "\n"
);

const child = spawn(process.execPath, [path.join(__dirname, "..", "api", "server.js")], {
  env: {
    ...process.env,
    API_HOST: "127.0.0.1",
    API_PORT: String(PORT),
    TUNNEL_KIT_ENV: envPath,
  },
  stdio: ["ignore", "pipe", "pipe"],
});

function request(method, urlPath, { body, cookie } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: PORT,
        path: urlPath,
        method,
        headers: {
          "Content-Type": "application/json",
          ...(cookie ? { Cookie: cookie } : {}),
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const raw = Buffer.concat(chunks).toString("utf8");
          let json = {};
          try {
            json = JSON.parse(raw);
          } catch {
            json = { raw };
          }
          resolve({ status: res.statusCode, headers: res.headers, json });
        });
      }
    );
    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

function waitForHealth(tries = 40) {
  return new Promise((resolve, reject) => {
    const tick = async (left) => {
      try {
        const res = await request("GET", "/api/health");
        if (res.status === 200 && res.json.ok) return resolve();
      } catch {
        /* server not up yet */
      }
      if (left <= 0) return reject(new Error("api did not become healthy"));
      setTimeout(() => tick(left - 1), 50);
    };
    tick(tries);
  });
}

async function main() {
  await waitForHealth();
  const login = await request("POST", "/api/login", { body: { password: PASSWORD } });
  if (login.status !== 200) throw new Error(`login failed: ${login.status}`);
  const cookie = (login.headers["set-cookie"] || [])[0];
  if (!cookie) throw new Error("missing session cookie");

  const share = await request("GET", "/api/share", { cookie });
  if (share.status !== 200) throw new Error(`share failed: ${share.status}`);
  const ids = (share.json.profiles || []).map((p) => p.id);
  if (!ids.includes("reality") || !ids.includes("proxy")) {
    throw new Error(`expected reality + proxy profiles, got ${ids.join(",")}`);
  }
  if (ids.includes("cloudflare")) {
    throw new Error("legacy cloudflare profile id should be gone");
  }
  const proxied = share.json.profiles.find((p) => p.id === "proxy");
  if (proxied.title !== "Fastly") throw new Error(`proxy title: ${proxied.title}`);
  if (!proxied.link.includes("vpn.example.com") || !proxied.link.includes("type=xhttp")) {
    throw new Error(`proxy link looks wrong: ${proxied.link}`);
  }
  if (proxied.link.includes("Cloudflare")) {
    throw new Error("share link still hardcodes Cloudflare");
  }
  if (share.json.proxyName !== "Fastly") throw new Error("share.proxyName");

  const status = await request("GET", "/api/status", { cookie });
  if (status.json.proxyName !== "Fastly") throw new Error("status.proxyName");

  console.log("api-share.test.js ok");
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => {
    child.kill("SIGTERM");
    try {
      fs.unlinkSync(envPath);
    } catch {
      /* ignore */
    }
  });

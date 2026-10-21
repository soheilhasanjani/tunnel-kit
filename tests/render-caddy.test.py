#!/usr/bin/env python3
"""Caddyfile must serve the dashboard on :80, not a stub 'ok' page."""

from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main() -> None:
    with tempfile.TemporaryDirectory() as raw:
        tmp = pathlib.Path(raw)
        env = tmp / "env"
        env.write_text(
            "\n".join(
                [
                    "DOMAIN=vpn.example.com",
                    "XHTTP_PATH=/secretpath",
                    "XHTTP_PORT=10000",
                    "CADDY_HTTPS_PORT=8443",
                    "CERT_FILE=/etc/tunnel-kit/certs/cert.pem",
                    "KEY_FILE=/etc/tunnel-kit/certs/key.pem",
                    "UUID=00000000-0000-4000-8000-000000000000",
                    "REALITY_PRIVATE_KEY=priv",
                    "REALITY_PUBLIC_KEY=pub",
                    "REALITY_SHORT_ID=abcd",
                    "REALITY_SNI=vpn.example.com",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        out = tmp / "Caddyfile"
        subprocess.check_call(
            ["python3", str(ROOT / "scripts/render.py"), str(ROOT / "server/Caddyfile.tpl"), str(out)],
            env={**os.environ, "TUNNEL_KIT_ENV": str(env)},
        )
        text = out.read_text(encoding="utf-8")
        assert "{{" not in text, text
        assert ":80 {" in text
        assert "import app" in text
        assert 'respond "ok"' not in text
        assert "root * /var/www/tunnel-kit" in text
        assert "bind 127.0.0.1" in text
        assert ":8443 {" in text
        print("render-caddy.test.py ok")


if __name__ == "__main__":
    main()

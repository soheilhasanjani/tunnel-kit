#!/usr/bin/env python3
"""Caddyfile must proxy WS and XHTTP paths and serve the dashboard on :80."""

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
                    "WS_PATH=/secretws",
                    "XHTTP_PATH=/secretpath",
                    "CERT_FILE=/etc/tunnel-kit/certs/cert.pem",
                    "KEY_FILE=/etc/tunnel-kit/certs/key.pem",
                    "UUID=00000000-0000-4000-8000-000000000000",
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
        assert ":443 {" in text
        assert "127.0.0.1:10086" in text
        assert "127.0.0.1:10087" in text
        assert "/secretws" in text
        assert "/secretpath" in text
        assert "root * /var/www/tunnel-kit" in text
        print("render-caddy.test.py ok")


if __name__ == "__main__":
    main()

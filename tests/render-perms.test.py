#!/usr/bin/env python3
"""Rendered files must be world-readable even with a strict umask (Xray runs as nobody)."""

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
                    'DOMAIN=vpn.example.com',
                    'XHTTP_PATH=/secret"path',
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
        out = tmp / "config.json"
        envp = {**os.environ, "TUNNEL_KIT_ENV": str(env)}
        subprocess.check_call(
            ["python3", str(ROOT / "scripts/render.py"), str(ROOT / "server/xray.json.tpl"), str(out)],
            env=envp,
            preexec_fn=lambda: os.umask(0o077),
        )
        mode = oct(out.stat().st_mode)[-3:]
        assert mode == "644", mode
        text = out.read_text(encoding="utf-8")
        assert r"/secret\"path" in text, text
        import json

        json.loads(text)
        print("render-perms.test.py ok")


if __name__ == "__main__":
    main()

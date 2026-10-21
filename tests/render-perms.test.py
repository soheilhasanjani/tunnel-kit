#!/usr/bin/env python3
"""Rendered Xray JSON matches simple VLESS WS + XHTTP and is world-readable."""

from __future__ import annotations

import json
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
                    "WS_PATH=/wssecret",
                    'XHTTP_PATH=/secret"path',
                    "UUID=00000000-0000-4000-8000-000000000000",
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
        data = json.loads(out.read_text(encoding="utf-8"))
        assert "reality" not in json.dumps(data).lower()
        ports = [i["port"] for i in data["inbounds"]]
        assert ports == [10086, 10087], ports
        assert data["inbounds"][0]["streamSettings"]["network"] == "ws"
        assert data["inbounds"][0]["streamSettings"]["wsSettings"]["path"] == "/wssecret"
        assert data["inbounds"][1]["streamSettings"]["network"] == "xhttp"
        assert data["inbounds"][1]["streamSettings"]["xhttpSettings"]["path"] == '/secret"path'
        print("render-perms.test.py ok")


if __name__ == "__main__":
    main()

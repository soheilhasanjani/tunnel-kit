#!/usr/bin/env python3
"""Fill {{VAR}} placeholders in templates from /etc/tunnel-kit.env (or TUNNEL_KIT_ENV)."""

from __future__ import annotations

import os
import pathlib
import re
import sys

ENV_PATH = os.environ.get("TUNNEL_KIT_ENV", "/etc/tunnel-kit.env")
PLACEHOLDER = re.compile(r"\{\{([A-Z0-9_]+)\}\}")


def load_env(path: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip("'").strip('"')
    return values


def render(text: str, values: dict[str, str]) -> str:
    missing: set[str] = set()

    def repl(match: re.Match[str]) -> str:
        key = match.group(1)
        if key not in values:
            missing.add(key)
            return match.group(0)
        return values[key]

    out = PLACEHOLDER.sub(repl, text)
    if missing:
        names = ", ".join(sorted(missing))
        raise SystemExit(f"Missing values in {ENV_PATH}: {names}")
    leftover = PLACEHOLDER.findall(out)
    if leftover:
        raise SystemExit(f"Unreplaced placeholders: {', '.join(leftover)}")
    return out


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: render.py <template> <output>")
    src = pathlib.Path(sys.argv[1])
    dest = pathlib.Path(sys.argv[2])
    values = load_env(ENV_PATH)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(render(src.read_text(encoding="utf-8"), values), encoding="utf-8")
    print(f"wrote {dest}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
from __future__ import annotations

import sys

from config import ConfigError, atomic_write, read_env, validate_image, ROOT


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: update_image.py <image>", file=sys.stderr)
        return 2
    try:
        image = validate_image(sys.argv[1])
    except ConfigError as exc:
        print(f"配置错误: {exc}", file=sys.stderr)
        return 2
    path = ROOT / ".env"
    values = read_env(path)
    if not values:
        print(".env 不存在", file=sys.stderr)
        return 2
    lines = path.read_text(encoding="utf-8").splitlines()
    replaced = False
    output: list[str] = []
    for line in lines:
        if line.startswith("CINQUAIN_HOMESERVER_IMAGE="):
            output.append(f"CINQUAIN_HOMESERVER_IMAGE={image}")
            replaced = True
        else:
            output.append(line)
    if not replaced:
        output.append(f"CINQUAIN_HOMESERVER_IMAGE={image}")
    atomic_write(path, "\n".join(output) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Absolute path with existing symlinks resolved and a missing tail kept.

The result is absolute. . and .. are collapsed, symlinks that exist are
resolved, and components that do not exist stay as written. One path.
"""
from __future__ import annotations

import os
import sys


def main(argv: list[str]) -> int:
    args = argv[1:]
    if args[:1] == ['--']:
        args = args[1:]
    if len(args) != 1:
        print('canonicalize-missing: need exactly one path', file=sys.stderr)
        return 2
    try:
        print(os.path.realpath(args[0]))
    except (OSError, ValueError):
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))

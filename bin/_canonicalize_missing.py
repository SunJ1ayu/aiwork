#!/usr/bin/env python3
"""Absolute path, with or without resolving existing symlinks.

Default matches GNU realpath -m: absolute, . and .. collapsed, existing
symlinks resolved, a missing tail kept. --no-symlinks matches GNU realpath -s:
absolute, . and .. collapsed as text, symlinks left as written. One path.
An empty path is an error.
"""
from __future__ import annotations

import os
import sys


def main(argv: list[str]) -> int:
    args = argv[1:]
    literal = False
    if args[:1] == ['--no-symlinks']:
        literal = True
        args = args[1:]
    if args[:1] == ['--']:
        args = args[1:]
    if len(args) != 1:
        print('canonicalize-missing: need exactly one path', file=sys.stderr)
        return 2
    if args[0] == '':
        print('canonicalize-missing: empty path', file=sys.stderr)
        return 1
    try:
        print(os.path.abspath(args[0]) if literal else os.path.realpath(args[0]))
    except (OSError, ValueError):
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))

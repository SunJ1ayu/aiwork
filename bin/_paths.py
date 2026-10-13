#!/usr/bin/env python3
"""Path canonicalization and directory containment.

canon [--no-symlinks] -- PATH
    One absolute path. Default matches GNU realpath -m: existing symlinks
    resolved, a missing tail kept, . and .. collapsed. --no-symlinks matches
    GNU realpath -m -s: the same, but symlinks stay as written. A leading //
    collapses to /, the way GNU does. An empty path is an error.

inside [--no-symlinks] -- ROOT PATH
    Whether PATH is ROOT or inside it. ROOT is always read with canon's
    default mode. PATH uses that mode, or --no-symlinks when asked.
    Each side is split into its deepest existing ancestor and the names that
    do not exist yet. They are the same directory when those ancestors have
    the same device and inode (os.stat, following links) and the missing
    names match one by one. The first ancestor of PATH that matches is a hit:
    print the relative remainder from there to PATH (empty line when PATH is
    that directory) and exit 0. No match: exit 1, print nothing.
    ENOENT and ENOTDIR count as "does not exist". Any other stat error, or an
    empty ROOT, exits 2.
"""
from __future__ import annotations

import errno
import os
import sys

_MISSING = (errno.ENOENT, errno.ENOTDIR)


def _fail(message: str, code: int) -> int:
    print(f'paths: {message}', file=sys.stderr)
    return code


def lexical_abs(path: str) -> str:
    """Absolute path with . and .. collapsed as text. Symlinks stay. // becomes /."""
    if not os.path.isabs(path):
        path = os.path.join(os.getcwd(), path)
    parts: list[str] = []
    for part in path.split('/'):
        if part in ('', '.'):
            continue
        if part == '..':
            if parts:
                parts.pop()
            continue
        parts.append(part)
    return '/' + '/'.join(parts)


def canon(path: str, *, literal: bool) -> str:
    if literal:
        return lexical_abs(path)
    resolved = os.path.realpath(path)
    if resolved.startswith('//'):
        resolved = '/' + resolved.lstrip('/')
    return resolved


def _stat_existing(path: str):
    """Return os.stat result, or None when the path does not exist.

    ENOTDIR is "does not exist" (a file sits where a directory was required).
    Any other OSError propagates.
    """
    try:
        return os.stat(path)
    except OSError as err:
        if err.errno in _MISSING:
            return None
        raise


def split_existing(abs_path: str):
    """Return (existing ancestor, missing names from there, stat of the ancestor)."""
    missing: list[str] = []
    cur = abs_path
    while True:
        st = _stat_existing(cur)
        if st is not None:
            missing.reverse()
            return cur, missing, st
        parent, name = os.path.split(cur)
        if not name or parent == cur:
            raise OSError(errno.ENOENT, 'no existing ancestor', abs_path)
        missing.append(name)
        cur = parent


def _same_place(root_split, ancestor_split) -> bool:
    _, root_missing, root_st = root_split
    _, ancestor_missing, ancestor_st = ancestor_split
    if (root_st.st_dev, root_st.st_ino) != (ancestor_st.st_dev, ancestor_st.st_ino):
        return False
    return root_missing == ancestor_missing


def _ancestors(abs_path: str):
    cur = abs_path
    while True:
        yield cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent


def _remainder(ancestor: str, path: str) -> str:
    if ancestor == path:
        return ''
    if ancestor == '/':
        return path[1:]
    prefix = ancestor + '/'
    if path.startswith(prefix):
        return path[len(prefix):]
    raise OSError(errno.EINVAL, 'ancestor is not a prefix', ancestor)


def inside(root: str, path: str, *, literal: bool) -> tuple[int, str]:
    if root == '':
        return 2, ''
    if path == '':
        return 2, ''
    try:
        root_abs = canon(root, literal=False)
        path_abs = canon(path, literal=literal)
        root_split = split_existing(root_abs)
        for ancestor in _ancestors(path_abs):
            if _same_place(root_split, split_existing(ancestor)):
                return 0, _remainder(ancestor, path_abs)
    except OSError as err:
        if err.errno in _MISSING:
            return 1, ''
        return 2, ''
    return 1, ''


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in ('canon', 'inside'):
        return _fail('需要子命令 canon 或 inside', 2)
    cmd = argv[1]
    args = argv[2:]
    literal = False
    if args[:1] == ['--no-symlinks']:
        literal = True
        args = args[1:]
    if args[:1] == ['--']:
        args = args[1:]
    want = 2 if cmd == 'inside' else 1
    if len(args) != want:
        return _fail('参数个数不对', 2)
    if cmd == 'canon':
        if args[0] == '':
            return _fail('空路径', 1)
        try:
            print(canon(args[0], literal=literal))
        except (OSError, ValueError):
            return 1
        return 0
    root, path = args
    code, rel = inside(root, path, literal=literal)
    if code == 0:
        print(rel)
    elif code == 2:
        print('paths: 路径检查失败', file=sys.stderr)
    return code


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))

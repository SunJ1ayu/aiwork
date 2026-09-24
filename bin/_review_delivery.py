"""Versioned delivery projection shared by snapshot producers and archive checks.

Policy 1 covers the repository, normalizing only the current track's relocation
and its protocol-defined closeout records. Ordinary evidence remains content.
This is an integrity check for accidental drift, not protection against an owner
deliberately disguising executable input as a workflow receipt.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


POLICY_VERSION = 1
RECEIPT = re.compile(rb"evidence/[0-9]{8}T[0-9]{6}Z-[0-9]{2}-[A-Za-z0-9._-]+\.txt$")


class DeliveryError(ValueError):
    pass


def _git(repo: Path, *args: str, env=None, data=None) -> bytes:
    proc = subprocess.run(["git", "-C", os.fspath(repo), *args], input=data,
                          capture_output=True, env=env, check=False)
    if proc.returncode:
        # Git/filter diagnostics can contain source or credentials. Report only
        # the failed operation; callers must never turn an unreadable view green.
        raise DeliveryError(f"git {args[0]} failed (rc={proc.returncode})")
    return proc.stdout


def _rows(repo: Path, track: str, tree: str, env=None, scope: str = "repo") -> list:
    """Sorted delivery rows of one tree. scope="track" keeps only this track's own
    files — used to ask "did the archived track itself change after it was archived",
    a question the repository-wide view cannot answer once the tree is pinned."""
    entries = _git(repo, "ls-tree", "-rz", "--full-tree", tree, env=env)
    prefixes = (f"tracks/{track}/".encode(), f"tracks/archive/{track}/".encode())
    rows = []
    seen = set()
    roots = set()
    for entry in entries.split(b"\0"):
        if not entry:
            continue
        metadata, path = entry.split(b"\t", 1)
        mode, kind, oid = metadata.split(b" ")
        if kind != b"blob" or mode not in (b"100644", b"100755", b"120000"):
            raise DeliveryError("unsupported tree entry (gitlink/submodule or unknown mode)")
        suffix = None
        for prefix in prefixes:
            if path.startswith(prefix):
                roots.add(prefix)
                suffix = path[len(prefix):]
                # Same track content keeps its identity across the archive move.
                path = prefixes[0] + suffix
                break
        if len(roots) > 1 or path in seen:
            raise DeliveryError("active/archive track collision")
        seen.add(path)
        content_id = oid
        if suffix is not None and mode == b"100644":
            if suffix == b"verify.md":
                continue
            if re.fullmatch(rb"observations/[^/]+\.json", suffix):
                # The strict observation validator checks these separately.
                continue
            if suffix in (b"decision.json", b"tasks.md") or RECEIPT.fullmatch(suffix):
                blob = _git(repo, "cat-file", "blob", oid.decode("ascii"), env=env)
                if suffix == b"decision.json":
                    try:
                        decision = json.loads(blob)
                        if not isinstance(decision, dict) or not isinstance(decision.get("outcome"), dict):
                            raise ValueError("invalid decision")
                        outcome = {**decision["outcome"], "verdict": None}
                        # 主裁对分裂评审的裁决记录与 verdict 同类:评审之后才写,写它不许作废这次评审。
                        # 删键而不是置空 —— 没有这个键的旧记录字节不变,进行中的绑定都不受影响
                        # (track arbiter-resolves-split-review,判据 R11b 钉着改动前的指纹)。
                        outcome.pop("split_resolutions", None)
                        decision["outcome"] = outcome
                        blob = json.dumps(decision, sort_keys=True, separators=(",", ":"),
                                          ensure_ascii=True, allow_nan=False).encode()
                    except (ValueError, TypeError, UnicodeError) as exc:
                        raise DeliveryError("invalid decision in delivery view") from exc
                elif suffix == b"tasks.md":
                    blob = re.sub(rb"(?m)^(\s*[-*] )\[[ xX]\]( )", rb"\1[ ]\2", blob)
                elif blob.startswith(b"# runlog receipt ") and any(
                        line.startswith(b"runlog: ") for line in blob.splitlines()):
                    continue
                content_id = b"sha256:" + hashlib.sha256(blob).hexdigest().encode()
        if scope == "track" and suffix is None:
            continue
        rows.append(path + b"\0" + mode + b"\0" + content_id + b"\0")
    return sorted(rows)


def _digest(repo: Path, track: str, rows, env=None, scope: str = "repo") -> str:
    object_format = _git(repo, "rev-parse", "--show-object-format", env=env).strip()
    # The repository-wide domain string is frozen: changing it would invalidate every
    # delivery digest already bound by a past review. Track scope gets its own domain
    # so the two can never be mistaken for each other.
    domain = b"aiwork-delivery-v1\0" if scope == "repo" else b"aiwork-delivery-track-v1\0"
    return "sha256:" + hashlib.sha256(
        domain + track.encode() + b"\0" + object_format + b"\0" + b"".join(rows)
    ).hexdigest()


def _project(repo: Path, track: str, tree: str, env=None, scope: str = "repo") -> str:
    return _digest(repo, track, _rows(repo, track, tree, env, scope), env, scope)


def _check_track(track: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", track) or track == "archive":
        raise DeliveryError("invalid delivery track")


def _scan_rows(repo: Path, track: str, *, source: str, scope: str = "repo") -> list:
    if source not in ("working", "staged"):
        raise DeliveryError("unknown delivery view")
    # A private index AND private object store keep hashing from writing to the
    # user's index/object database. Preserve the actual index as the scan base.
    entries = _git(repo, "ls-files", "--stage", "-z")
    objects = _git(repo, "rev-parse", "--path-format=absolute", "--git-path", "objects").decode().strip()
    with tempfile.TemporaryDirectory(prefix="aiwork-delivery-") as tmp:
        objdir = Path(tmp) / "objects"
        objdir.mkdir()
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(tmp) / "index"),
                   GIT_OBJECT_DIRECTORY=str(objdir), GIT_ALTERNATE_OBJECT_DIRECTORIES=objects,
                   GIT_OPTIONAL_LOCKS="0")
        def scan():
            _git(repo, "read-tree", "--empty", env=env)
            _git(repo, "update-index", "-z", "--index-info", env=env, data=entries)
            if source == "working":
                # The working view is index + worktree changes + UNTRACKED files;
                # the staged view is the index alone. They agree only on a worktree
                # that is clean of delivery-relevant content — that is this gate's
                # precondition, and view_difference() is how a caller names it.
                _git(repo, "add", "-A", "--", ":/", env=env)
            oid = _git(repo, "write-tree", env=env).decode().strip()
            return _rows(repo, track, oid, env, scope)
        first = scan()
        second = scan()
        if entries != _git(repo, "ls-files", "--stage", "-z") or first != second:
            raise DeliveryError("delivery view changed during capture")
        return first


def delivery_fingerprint(repo: Path, track: str, *, source="working", tree=None, scope="repo") -> str:
    _check_track(track)
    repo = Path(repo)
    if tree is not None:
        return _project(repo, track, tree, scope=scope)
    return _digest(repo, track, _scan_rows(repo, track, source=source, scope=scope), scope=scope)


def _rows_of(repo: Path, track: str, *, source=None, tree=None, scope="repo") -> list:
    if tree is not None:
        return _rows(repo, track, tree, None, scope)
    return _scan_rows(repo, track, source=source, scope=scope)


def _differing_paths(left: list, right: list) -> list:
    """Paths that are not identical on both sides. A refusal that can name the files
    is the difference between an actionable stop and the loop this track was opened
    to remove, so every comparison in this module reports through here."""
    def table(rows):
        out = {}
        for row in rows:
            path, mode, content_id, _ = row.split(b"\0")
            out[path] = (mode, content_id)
        return out

    a, b = table(left), table(right)
    return sorted(path.decode("utf-8", "surrogateescape")
                  for path in set(a) | set(b) if a.get(path) != b.get(path))


def view_difference(repo: Path, track: str, *, scope="repo") -> list:
    """Paths whose delivery content differs between the working and the staged view.
    Empty means the two views deliver the same thing."""
    _check_track(track)
    repo = Path(repo)
    return _differing_paths(_rows_of(repo, track, source="working", scope=scope),
                            _rows_of(repo, track, source="staged", scope=scope))


def tree_difference(repo: Path, track: str, tree: str, *, source="staged", scope="track") -> list:
    """Paths where a view no longer matches a pinned tree — used to say WHICH file
    inside an archived track changed after it was archived."""
    _check_track(track)
    repo = Path(repo)
    return _differing_paths(_rows_of(repo, track, tree=tree, scope=scope),
                            _rows_of(repo, track, source=source, scope=scope))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--track", required=True)
    parser.add_argument("--tree")
    parser.add_argument("--source", choices=("working", "staged"), default="working")
    parser.add_argument("--scope", choices=("repo", "track"), default="repo")
    parser.add_argument("--explain-views", action="store_true",
                        help="print the paths that make the working and staged views differ")
    args = parser.parse_args()
    try:
        if args.explain_views:
            for path in view_difference(args.repo, args.track, scope=args.scope):
                print(path)
        else:
            print(delivery_fingerprint(args.repo, args.track, source=args.source,
                                       tree=args.tree, scope=args.scope))
    except (OSError, DeliveryError) as exc:
        parser.exit(1, f"review-delivery: {exc}\n")


if __name__ == "__main__":
    main()

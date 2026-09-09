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


def _project(repo: Path, track: str, tree: str, env=None) -> str:
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
                        decision["outcome"] = {**decision["outcome"], "verdict": None}
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
        rows.append(path + b"\0" + mode + b"\0" + content_id + b"\0")
    object_format = _git(repo, "rev-parse", "--show-object-format", env=env).strip()
    return "sha256:" + hashlib.sha256(
        b"aiwork-delivery-v1\0" + track.encode() + b"\0" + object_format + b"\0" + b"".join(sorted(rows))
    ).hexdigest()


def delivery_fingerprint(repo: Path, track: str, *, source="working", tree=None) -> str:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", track) or track == "archive":
        raise DeliveryError("invalid delivery track")
    repo = Path(repo)
    if tree is not None:
        return _project(repo, track, tree)
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
                _git(repo, "add", "-A", "--", ":/", env=env)
            oid = _git(repo, "write-tree", env=env).decode().strip()
            return _project(repo, track, oid, env)
        first = scan()
        second = scan()
        if entries != _git(repo, "ls-files", "--stage", "-z") or first != second:
            raise DeliveryError("delivery view changed during capture")
        return first


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--track", required=True)
    parser.add_argument("--tree")
    parser.add_argument("--source", choices=("working", "staged"), default="working")
    args = parser.parse_args()
    try:
        print(delivery_fingerprint(args.repo, args.track, source=args.source, tree=args.tree))
    except (OSError, DeliveryError) as exc:
        parser.exit(1, f"review-delivery: {exc}\n")


if __name__ == "__main__":
    main()

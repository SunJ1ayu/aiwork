#!/usr/bin/env python3
"""Shared leg invocation, repository snapshot, and report file for review-pr and explore."""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
from typing import NamedTuple

from _review_result import load_result, sha256_file


READER_TIMEOUT_ENV = {
    "subdeepseek-agent": "DEEPSEEK_TIMEOUT",
    "subcodex": "SUBCODEX_TIMEOUT", "subcursor": "CURSOR_TIMEOUT",
    "submimo": "MIMO_CLI_TIMEOUT", "subkimi": "KIMI_TIMEOUT",
}
READER_TIMEOUT_SECONDS = "2400"
SHA = re.compile(r"^[0-9a-f]{40}$")


class ReviewError(ValueError):
    pass


class Change(NamedTuple):
    status: str
    path: str
    old_path: str | None
    added: int | None
    removed: int | None


def choose_leg(name: str, bin_dir: Path) -> tuple[str, str | None]:
    """The family this review is published under, and the model frozen for this run.

    A leg only has to be attributable to one family. Which families count for which
    PR is the gate's call (gate/decide.mjs), not this tool's.
    Cursor's model is frozen once here (CURSOR_MODEL, else ~/.config/aiwork/models.env)
    and decides the family.
    """
    from _aiwork_config import ConfigError, model as configured_model
    from _review_result import leg_identity
    model = None
    if name == "subcursor":
        try:
            model = configured_model("cursor", os.environ.get("CURSOR_MODEL"))
        except ConfigError as exc:
            raise ReviewError(str(exc)) from exc
    identity = leg_identity(name, model)
    if identity is None or not (bin_dir / name).is_file():
        raise ReviewError(f"unsupported review leg: {name}" + (f" (model {model!r})" if model else ""))
    return identity[0], model


def redact(text: str) -> str:
    from _secret_shapes import redact_shapes
    text = redact_shapes(text)
    value = r'''(?:"[^"]*"|'[^']*'|[^\s,;]+)'''
    text = re.sub(r'''(?i)(?<![\w-])((?:[a-z_][a-z0-9_]*)?(?:token|key|secret|password)|api-key)(["']?\s*[:=]\s*)''' + value,
                  r"\1\2[redacted]", text)
    text = re.sub(r"(?i)(\bBearer\s+)" + value, r"\1[redacted]", text)
    return text


def run(command: list[str], *, env: dict[str, str] | None = None,
        input_text: str | None = None, cwd: Path | None = None) -> str:
    process = subprocess.run(command, input=input_text, text=True, capture_output=True,
                             cwd=cwd, env=env, check=False)
    if process.returncode:
        reason = process.stderr.strip() or process.stdout.strip() or f"exit {process.returncode}"
        # Provider and Git errors are diagnostics, never a place to echo credentials.
        reason = redact(reason)
        raise ReviewError(f"{Path(command[0]).name} failed (rc={process.returncode}): {reason[:800]}")
    return process.stdout


def review_report(report: Path) -> str:
    # The leg writes the model's last message to this file. The log keeps the
    # whole process; publication never reconstructs a report from that text.
    if not report.is_file():
        raise ReviewError(f"review leg did not write the report file {report}; refusing to publish")
    text = report.read_text(encoding="utf-8", errors="replace")
    if not text.strip():
        raise ReviewError(f"review leg wrote an empty report file {report}; refusing to publish")
    return text


def assert_snapshot_checkout(repo: Path, expected: str, *, label: str) -> None:
    if run(["git", "-C", str(repo), "rev-parse", "HEAD"]).strip() != expected:
        raise ReviewError(f"snapshot HEAD differs from {label}")
    if "160000 " in run(["git", "-C", str(repo), "ls-files", "--stage"]):
        raise ReviewError("snapshot contains submodules; full view cannot be verified")


def _git_bytes(repo: Path, *args: str) -> bytes:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=True).stdout


def _z_fields(blob: bytes) -> list[bytes]:
    fields = blob.split(b"\0")
    if fields and fields[-1] == b"":
        fields.pop()
    return fields


def _take_fields(fields: list[bytes], index: int, count: int) -> tuple[list[bytes], int]:
    if index + count > len(fields):
        raise ReviewError("git -z record is truncated")
    return fields[index:index + count], index + count


def _parse_name_status(blob: bytes) -> list[tuple[str, str, str | None]]:
    """Status letter, path, and the old path for a rename or copy. From git -z, not a diff header."""
    fields = _z_fields(blob)
    rows: list[tuple[str, str, str | None]] = []
    index = 0
    while index < len(fields):
        status, index = _take_fields(fields, index, 1)
        letter = os.fsdecode(status[0])[:1]
        if not letter:
            raise ReviewError("git name-status -z record is empty")
        if letter in "RC":
            pair, index = _take_fields(fields, index, 2)
            rows.append((letter, os.fsdecode(pair[1]), os.fsdecode(pair[0])))
        else:
            path, index = _take_fields(fields, index, 1)
            rows.append((letter, os.fsdecode(path[0]), None))
    return rows


def _count(field: bytes) -> int | None:
    return None if field == b"-" else int(field)


def _parse_numstat(blob: bytes) -> list[tuple[int | None, int | None, str, str | None]]:
    """Added, removed, path, and the old path when numstat -z emits the empty rename field."""
    fields = _z_fields(blob)
    rows: list[tuple[int | None, int | None, str, str | None]] = []
    index = 0
    while index < len(fields):
        record, index = _take_fields(fields, index, 1)
        added_b, removed_b, path_b = record[0].split(b"\t", 2)
        if path_b == b"":
            pair, index = _take_fields(fields, index, 2)
            rows.append((_count(added_b), _count(removed_b), os.fsdecode(pair[1]), os.fsdecode(pair[0])))
        else:
            rows.append((_count(added_b), _count(removed_b), os.fsdecode(path_b), None))
    return rows


def collect_review_diff(repo: Path, merge_base: str, head: str
                        ) -> tuple[list[str], str, list[Change]]:
    """Changed paths, the complete diff, and one status row per path from git -z.

    name-status and numstat are the same diff. A rename keeps both paths. Nothing parses a diff header.
    """
    spec = ["--find-renames", merge_base, head]
    status_rows = _parse_name_status(_git_bytes(repo, "diff", "--name-status", "-z", *spec))
    stat_rows = _parse_numstat(_git_bytes(repo, "diff", "--numstat", "-z", *spec))
    if len(status_rows) != len(stat_rows):
        raise ReviewError("git name-status and numstat disagree")
    changes: list[Change] = []
    files: list[str] = []
    for status, stat in zip(status_rows, stat_rows):
        letter, path, old = status
        added, removed, stat_path, stat_old = stat
        if path != stat_path or old != stat_old:
            raise ReviewError("git name-status and numstat disagree")
        changes.append(Change(letter, path, old, added, removed))
        files.append(path)
    diff = run(["git", "-C", str(repo), "diff", "--binary", "--no-ext-diff", *spec])
    return files, diff, changes


def snapshot(token: str, pr: dict, directory: Path, *, repository: str):
    repo = directory / "repo"
    repo.mkdir()
    run(["git", "init", "-q", str(repo)])
    askpass = directory / "askpass"
    askpass.write_text(
        "#!/bin/sh\ncase \"$1\" in *sername*) printf x-access-token;; *) printf %s \"$AIWORK_REVIEW_GIT_TOKEN\";; esac\n",
        encoding="utf-8",
    )
    askpass.chmod(0o700)
    env = dict(os.environ, GIT_ASKPASS=str(askpass), GIT_TERMINAL_PROMPT="0",
               AIWORK_REVIEW_GIT_TOKEN=token)
    head = pr["head"]["sha"]
    base = pr["base"]["sha"]
    run(["git", "-C", str(repo), "-c", "credential.helper=", "fetch", "-q", "--no-tags",
         f"https://github.com/{repository}.git", head, base, "refs/heads/main:refs/aiwork/main"], env=env)
    run(["git", "-C", str(repo), "checkout", "-q", "--detach", head])
    # The reviewer sees a complete checkout, not a sparse or partial worktree.
    assert_snapshot_checkout(repo, head, label="PR head")
    merge_base = run(["git", "-C", str(repo), "merge-base", base, head]).strip()
    files, diff, changes = collect_review_diff(repo, merge_base, head)
    if not files:
        raise ReviewError("PR has no changed files relative to merge base")
    if not diff.strip():
        raise ReviewError("PR diff is empty")
    return repo, merge_base, files, diff, changes


def current_main(source: Path) -> str:
    sha = run(["git", "-C", str(source), "rev-parse", "--verify", "refs/heads/main"]).strip()
    if not SHA.fullmatch(sha):
        raise ReviewError("target repository main is missing or invalid")
    return sha


def snapshot_main(source: Path, directory: Path, main_sha: str) -> Path:
    """One checkout of the pinned main commit. The caller gives each leg its own directory."""
    if not SHA.fullmatch(main_sha):
        raise ReviewError("target repository main is missing or invalid")
    repo = directory / "repo"
    repo.mkdir()
    run(["git", "init", "-q", str(repo)])
    run(["git", "-C", str(repo), "fetch", "-q", "--no-tags", str(source),
         f"{main_sha}:refs/heads/main"])
    run(["git", "-C", str(repo), "checkout", "-q", "--detach", main_sha])
    assert_snapshot_checkout(repo, main_sha, label="main")
    return repo


def run_leg_attempt(leg_name: str, family: str, task: Path, repo: Path, directory: Path,
                    env: dict[str, str], run_id: str, frozen_model: str | None, *,
                    bin_dir: Path, mode: str = "review",
                    review_contract_version: int | None = None):
    log, facts = directory / "review.log", directory / "facts.json"
    report = directory / "report.md"
    result_file, diagnostic = directory / "result.json", directory / "leg.stderr"
    env = dict(env, AIWORK_REVIEW_FACTS_PATH=str(facts), AIWORK_REVIEW_REPORT_PATH=str(report))
    leg = subprocess.run([str(bin_dir / leg_name), mode, str(task), str(log), str(repo)],
                         text=True, capture_output=True, env=env, check=False)
    diagnostic.write_text(leg.stderr, encoding="utf-8")
    command = [sys.executable, str(bin_dir / "_review_result.py"), "emit", "--result", str(result_file),
               "--run-id", run_id, "--name", leg_name, "--family", family, "--adapter", leg_name,
               "--exit-code", str(leg.returncode), "--task-sha256", sha256_file(task),
               "--log", str(log), "--diagnostic", str(diagnostic)]
    if facts.is_file():
        command += ["--facts", str(facts)]
    command += ["--report", str(report)]
    if frozen_model is not None:
        command += ["--expected-model", frozen_model]
    if review_contract_version is not None:
        command += ["--review-contract-version", str(review_contract_version)]
    run(command)
    return load_result(result_file), report

#!/usr/bin/env python3
"""Shared leg invocation, repository snapshot, and report file for review-pr and explore."""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys


READER_TIMEOUT_ENV = {
    "subdeepseek-agent": "DEEPSEEK_TIMEOUT",
    "subcodex": "SUBCODEX_TIMEOUT", "subcursor": "CURSOR_TIMEOUT",
    "submimo": "MIMO_CLI_TIMEOUT", "subkimi": "KIMI_TIMEOUT",
}
READER_TIMEOUT_SECONDS = "2400"
SHA = re.compile(r"^[0-9a-f]{40}$")


class ReviewError(ValueError):
    pass


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
        input_text: str | None = None, cwd: Path | None = None,
        subprocess_run=subprocess.run, redact=redact) -> str:
    process = subprocess_run(command, input=input_text, text=True, capture_output=True,
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


def assert_snapshot_checkout(repo: Path, expected: str, run, *, label: str) -> None:
    if run(["git", "-C", str(repo), "rev-parse", "HEAD"]).strip() != expected:
        raise ReviewError(f"snapshot HEAD differs from {label}")
    if "160000 " in run(["git", "-C", str(repo), "ls-files", "--stage"]):
        raise ReviewError("snapshot contains submodules; full view cannot be verified")


def snapshot(token: str, pr: dict, directory: Path, *, repository: str, run, collect_review_diff):
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
    assert_snapshot_checkout(repo, head, run, label="PR head")
    merge_base = run(["git", "-C", str(repo), "merge-base", base, head]).strip()
    files, diff, changes = collect_review_diff(repo, merge_base, head)
    if not files:
        raise ReviewError("PR has no changed files relative to merge base")
    if not diff.strip():
        raise ReviewError("PR diff is empty")
    return repo, merge_base, files, diff, changes


def current_main(source: Path, run) -> str:
    sha = run(["git", "-C", str(source), "rev-parse", "--verify", "refs/heads/main"]).strip()
    if not SHA.fullmatch(sha):
        raise ReviewError("target repository main is missing or invalid")
    return sha


def snapshot_main(source: Path, directory: Path, main_sha: str, *, run) -> Path:
    """One checkout of the pinned main commit. The caller gives each leg its own directory."""
    if not SHA.fullmatch(main_sha):
        raise ReviewError("target repository main is missing or invalid")
    repo = directory / "repo"
    repo.mkdir()
    run(["git", "init", "-q", str(repo)])
    run(["git", "-C", str(repo), "fetch", "-q", "--no-tags", str(source),
         f"{main_sha}:refs/heads/main"])
    run(["git", "-C", str(repo), "checkout", "-q", "--detach", main_sha])
    assert_snapshot_checkout(repo, main_sha, run, label="main")
    return repo


def run_leg_attempt(leg_name: str, family: str, task: Path, repo: Path, directory: Path,
                    env: dict[str, str], run_id: str, frozen_model: str | None, *,
                    run, subprocess_run, load_result, sha256_file, bin_dir: Path,
                    mode: str = "review", review_contract_version: int | None = None):
    log, facts = directory / "review.log", directory / "facts.json"
    report = directory / "report.md"
    result_file, diagnostic = directory / "result.json", directory / "leg.stderr"
    env = dict(env, AIWORK_REVIEW_FACTS_PATH=str(facts), AIWORK_REVIEW_REPORT_PATH=str(report))
    leg = subprocess_run([str(bin_dir / leg_name), mode, str(task), str(log), str(repo)],
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

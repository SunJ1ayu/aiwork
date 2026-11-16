#!/usr/bin/env python3
"""Shared leg invocation, repository snapshot, and report file for review-pr and explore."""

from __future__ import annotations

from contextlib import contextmanager
import os
import pwd
import shutil
import stat
import tempfile
from pathlib import Path
import re
import subprocess
import sys
from typing import NamedTuple, cast

from _review_result import load_result, sha256_file
from _aiwork_config import (RUNTIME_OPTIONS, app_key, apps_dir, data_dir,
                            review_location, setting_path, setting_value)


SHA = re.compile(r"^[0-9a-f]{40}$")


class ReviewError(ValueError):
    pass


def reader_environment(leg: str, env: dict[str, str]) -> dict[str, str]:
    """Freeze resolved reader parameters before the direct wrapper sees them."""
    from _aiwork_config import ConfigError, RUNTIME_OPTIONS, runtime_settings
    try:
        if enabled():
            values = {spec[0]: query(Path(__file__).parent, 'runtime', leg, option,
                      '--context', 'reader') for option, spec in RUNTIME_OPTIONS[leg].items()}
            return dict(env, **values)
        return dict(env, **runtime_settings(leg, context="reader", environ=env))
    except ConfigError as exc:
        raise ReviewError(str(exc)) from exc


class Change(NamedTuple):
    status: str
    path: str
    old_path: str | None
    added: int | None
    removed: int | None


def check_leg_platform(name: str, bin_dir: Path) -> None:
    """Ask the wrappers' platform authority before reading any leg settings."""
    result = subprocess.run(['/bin/bash', '-c', '. "$1"; review_platform_check "$2"',
                             'aiwork-leg-platform', str(bin_dir / '_review-platform.sh'), name],
                            capture_output=True, text=True, check=False)
    if result.returncode:
        raise ReviewError(result.stderr.strip() or f'platform check exited {result.returncode}')


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
            if enabled():
                args = ['model', 'cursor'] + ([os.environ['CURSOR_MODEL']] if os.environ.get('CURSOR_MODEL') else [])
                model = query(bin_dir, *args)
            else:
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
        binary: bool = False) -> str | bytes:
    """Run a command. Failure becomes one redacted ReviewError.

    binary returns stdout bytes unchanged (git -z). The failure text is still decoded
    and redacted here; callers do not grow a second error path.
    """
    stdin = None if input_text is None else input_text.encode() if binary else input_text
    process = subprocess.run(
        command, input=stdin, text=not binary, capture_output=True,
        cwd=cwd, env=env, check=False)
    if process.returncode:
        err, out = process.stderr, process.stdout
        if binary:
            err, out = err.decode("utf-8", "replace"), out.decode("utf-8", "replace")
        reason = err.strip() or out.strip() or f"exit {process.returncode}"
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
    return cast(bytes, run(["git", "-C", str(repo), *args], binary=True))


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
         f"{main_sha}:refs/aiwork/main"])
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
    command = [str(bin_dir / leg_name), mode, str(task), str(log), str(repo)]
    if mode == 'review' and enabled():
        leg = run_leg(command, env=env, directory=directory,
                                   repo=repo, task=task, bin_dir=bin_dir)
    else:
        leg = subprocess.run(command, text=True, capture_output=True, env=env, check=False)
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


def enabled():
    return review_location() == 'local'


def account():
    info = setting_path('review-user.env').stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022 or info.st_nlink != 1:
        raise ReviewError('评审账号配置须由发布账号独立持有，不能由腿修改')
    name = setting_value('review-user.env', 'user')
    try:
        selected = pwd.getpwnam(name)
    except KeyError as exc:
        raise ReviewError('评审腿账号尚未部署') from exc
    home = Path(selected.pw_dir)
    if (os.geteuid() != 0 or selected.pw_uid == 0 or selected.pw_gid == 0
            or not home.is_absolute() or not home.is_dir()
            or home.stat().st_uid != selected.pw_uid):
        raise ReviewError('发布程序须由 root 运行，评审腿须使用拥有独立 home 的普通账号')
    return selected


def environment(selected):
    # Do not enumerate publisher secrets: nothing is inherited except public
    # review parameters selected below. Provider credentials belong to this home.
    return {'HOME': selected.pw_dir, 'USER': selected.pw_name, 'LOGNAME': selected.pw_name,
            'PATH': '/usr/local/bin:/usr/bin:/bin', 'LANG': 'C.UTF-8'}


def execute(selected, command, *, env, cwd):
    for tool in ('/usr/bin/unshare', '/usr/bin/setpriv'):
        if not os.access(tool, os.X_OK):
            raise ReviewError('评审账号运行需要 util-linux；未启动评审腿')
    # Only /proc changes. The account retains its ordinary filesystem, DNS and
    # writable login files. Namespace PID 1 exiting reaps even detached workers.
    return subprocess.run([
        '/usr/bin/unshare', '--mount', '--propagation', 'private', '--pid', '--fork',
        '--kill-child', '--mount-proc', '--', '/usr/bin/setpriv',
        '--reuid=' + str(selected.pw_uid), '--regid=' + str(selected.pw_gid),
        '--clear-groups', '--bounding-set=-all', '--inh-caps=-all',
        '--ambient-caps=-all', '--no-new-privs', '--', *map(str, command)],
        env=env, cwd=cwd, stdin=subprocess.DEVNULL, text=True, capture_output=True, check=False)


def protected_paths(bin_dir, directory=None):
    paths = [Path.home(), setting_path('apps').parent, apps_dir(), data_dir(), bin_dir]
    if directory is not None:
        paths.append(directory)
    for role in apps_dir().glob('*.env'):
        fd = os.open(role, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022 or info.st_nlink != 1:
                raise ReviewError('角色配置须由发布账号独立持有，不能由腿修改')
            result = subprocess.run(['/bin/bash', '-c',
                'set -eu; KEY=; . "$1"; printf "%s" "${KEY:?}"', 'key-path', '/proc/self/fd/' + str(fd)],
                pass_fds=(fd,), text=True, capture_output=True, check=False)
        finally:
            os.close(fd)
        if result.returncode:
            raise ReviewError('无法核实发布凭证权限；未启动评审腿')
        key = app_key(result.stdout).resolve(strict=True)
        if not stat.S_ISREG(key.stat().st_mode) or key.stat().st_nlink != 1 or key.stat().st_uid != 0:
            raise ReviewError('发布凭证不是独立普通文件；未启动评审腿')
        paths.append(key)
    return paths


@contextmanager
def tools(bin_dir, directory=None):
    selected = account()
    env = environment(selected)
    # Probe access only; never read a key or copy a publisher setting/login.
    private = protected_paths(bin_dir, directory)
    probe = execute(selected, ['/bin/sh', '-c',
        'for p do if test -r "$p" || test -w "$p" || test -x "$p"; then exit 78; fi; done',
        'publisher-permissions', *private], env=env, cwd=selected.pw_dir)
    if probe.returncode:
        raise ReviewError('评审账号隔离预检失败；核对账号切换及发布目录、凭证的私有权限')
    with tempfile.TemporaryDirectory(prefix='aiwork-leg-', dir='/var/tmp') as name:
        root = Path(name)
        os.chown(root, 0, selected.pw_gid)
        root.chmod(0o750)
        runtime = root / 'runtime'
        bundle = runtime / 'bin'
        credentials = [apps_dir().resolve(), *(path.resolve() for path in private if path.is_file())]
        # Git is the authority for public runtime inputs. Do not copy ignored
        # local settings, credentials or caches, and do not maintain a second
        # list of every adapter's helper/configuration dependencies.
        checkout = Path(__file__).resolve().parent.parent
        manifest = subprocess.run(['git', '-c', 'safe.directory=' + str(checkout),
            '-C', str(checkout), 'ls-files', '-z'], capture_output=True, check=False)
        if manifest.returncode:
            raise ReviewError('无法取得公开运行文件清单；未启动评审腿')
        runtime.mkdir()
        for relative in map(Path, os.fsdecode(manifest.stdout).split('\0')):
            if relative == Path('.') or relative in (Path('bin/review-pr'), Path('bin/gh-app-token')):
                continue
            source = bin_dir.parent / relative
            if any(source.resolve().is_relative_to(path) for path in credentials):
                continue
            if source.is_symlink():
                raise ReviewError('公开运行文件含链接；未启动评审腿')
            if source.is_file():
                target = runtime / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        # Public runtime code is readable but not owned/writable by a leg.
        # Operational publisher paths remain private and were checked above.
        for path in root.rglob('*'):
            if path.is_symlink():
                raise ReviewError('评审运行工具含链接；未启动评审腿')
            os.chown(path, 0, selected.pw_gid)
            path.chmod(0o750 if path.is_dir() or path.stat().st_mode & 0o111 else 0o640)
        yield selected, root, bundle, env


def query(bin_dir, *arguments):
    with tools(bin_dir) as (selected, root, bundle, env):
        result = execute(selected, [bundle / 'aiwork-config', *arguments], env=env,
                         cwd=selected.pw_dir)
        if result.returncode:
            raise ReviewError('评审账号的程序或模型设置不可用：' + result.stderr[-800:])
        return result.stdout.strip()


def run_leg(command, *, env, directory, repo, task, bin_dir):
    with tools(bin_dir, directory) as (selected, root, bundle, child_env):
        source = root / 'repo'
        shutil.copytree(repo, source, symlinks=True)
        task_copy = root / 'task.md'
        shutil.copyfile(task, task_copy)
        os.chown(task_copy, 0, selected.pw_gid)
        task_copy.chmod(0o640)
        for path in [source, *source.rglob('*')]:
            if not path.is_symlink():
                os.chown(path, 0, selected.pw_gid)
                path.chmod(0o750 if path.is_dir() or path.stat().st_mode & 0o111 else 0o640)
        work = root / 'work'
        work.mkdir(mode=0o700)
        os.chown(work, selected.pw_uid, selected.pw_gid)
        # Local clone/upload-pack clears repository-scoped config environment.
        # A per-run global file trusts only this root-owned source (both Git
        # spellings), without editing the leg account's persistent Git config.
        git_config = root / 'gitconfig'
        git_config.write_text('[safe]\n\tdirectory = ' + str(source)
                              + '\n\tdirectory = ' + str(source / '.git') + '\n')
        os.chown(git_config, 0, selected.pw_gid)
        git_config.chmod(0o640)
        # These are public invocation parameters, not arbitrary publisher env.
        parameters = {'PANEL_DIFF_BASE', 'AIWORK_REVIEW_PR', 'CURSOR_MODEL'}
        parameters.update(spec[0] for settings in RUNTIME_OPTIONS.values() for spec in settings.values())
        child_env.update({key: value for key, value in env.items() if key in parameters})
        child_env.update(AIWORK_REVIEW_RESULT_BIN=str(bundle / '_review_result.py'),
            AIWORK_REVIEW_FACTS_PATH=str(work / 'facts.json'),
            AIWORK_REVIEW_REPORT_PATH=str(work / 'report.md'),
            GIT_CONFIG_GLOBAL=str(git_config))
        # Pin the leg's output directory. A link or replacement cannot redirect
        # a privileged collector into publisher files, FIFOs or device nodes.
        fd = os.open(work, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            result = execute(selected, [bundle / Path(command[0]).name, command[1], task_copy,
                work / 'review.log', source], env=child_env, cwd=work)
            for name in ('review.log', 'facts.json', 'report.md', 'review.stream.jsonl',
                         'review.stream-summary.json', 'review.log.stream.jsonl', 'review.stderr'):
                try:
                    output = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                except FileNotFoundError:
                    continue
                with os.fdopen(output, 'rb') as stream:
                    info = os.fstat(stream.fileno())
                    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                        raise ReviewError('评审输出不是独立普通文件；拒绝接收')
                    (directory / name).write_bytes(stream.read())
            return result
        finally:
            os.close(fd)

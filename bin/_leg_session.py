#!/usr/bin/env python3
"""Shared leg invocation, repository snapshot, and report file for review-pr and explore."""

from __future__ import annotations

from contextlib import contextmanager
import os
import array
import fcntl
import json
import signal
import select
import socket
import struct
import threading
import time
import pwd
import shutil
import stat
import tempfile
from pathlib import Path
import re
import subprocess
import sys
from typing import NamedTuple, cast

from _review_result import load_result, sha256_file, managed_artifacts
from _aiwork_config import (RUNTIME_OPTIONS, app_key, apps_dir, data_dir,
                            review_location, setting_path, setting_value, data_path, MODEL_LOGINS)


SHA = re.compile(r"^[0-9a-f]{40}$")


class ReviewError(ValueError):
    pass


def network_read(operation):
    """Bound retries for remote reads; never wrap publication writes."""
    for attempt in range(3):
        try:
            return operation()
        except (ReviewError, OSError):
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


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
    network_read(lambda: run(["git", "-C", str(repo), "-c", "credential.helper=", "fetch", "-q", "--no-tags",
         f"https://github.com/{repository}.git", head, base, "refs/heads/main:refs/aiwork/main"], env=env))
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
    artifacts = managed_artifacts(directory)
    log, facts, report = (artifacts[kind] for kind in ("log", "facts", "report"))
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


def drop_command(selected, gid):
    return ['/usr/bin/setpriv', '--reuid=' + str(selected.pw_uid), '--regid=' + str(gid),
            '--groups=' + str(selected.pw_gid), '--bounding-set=-all', '--inh-caps=-all',
            '--ambient-caps=-all', '--no-new-privs', '--']


def execute(selected, command, *, env, cwd):
    if 'AIWORK_ACCOUNT_SETUP' in env:
        setup = json.loads(Path(env['AIWORK_ACCOUNT_SETUP']).read_text())
        host, view = setup['root'], setup['view']
        translate = lambda value: str(value).replace(host, view)
        setup.update(command=[translate(v) for v in command], cwd=translate(cwd),
                     env={k: translate(v) for k, v in env.items() if k != 'AIWORK_ACCOUNT_SETUP'})
        Path(env['AIWORK_ACCOUNT_SETUP']).write_text(json.dumps(setup))
        return subprocess.run(['/usr/bin/unshare', '--mount', '--propagation', 'private',
            '--pid', '--fork', '--kill-child', '--mount-proc', '--',
            sys.executable, '-Es', str(Path(__file__).resolve()), '--account-job', env['AIWORK_ACCOUNT_SETUP']],
            env={'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'}, cwd='/',
            stdin=subprocess.DEVNULL, text=True, capture_output=True, check=False)
    return subprocess.run(['/usr/bin/unshare', '--mount', '--propagation', 'private',
        '--pid', '--fork', '--kill-child', '--mount-proc', '--',
        *drop_command(selected, selected.pw_gid), *map(str, command)],
        env=env, cwd=cwd, stdin=subprocess.DEVNULL, text=True, capture_output=True, check=False)


def trusted_settings(selected):
    profile = Path(setting_value('review-user.env', 'settings'))
    if not profile.is_absolute() or profile.is_relative_to(selected.pw_dir):
        raise ReviewError('评审程序和设置须在腿 home 之外，由发布账号持有')
    # Links in programs/ are registration, not a second software installation.
    # Validate both the link and every target/ancestor, including executable
    # installation directories from which native CLIs load their modules.
    for path in [profile, *profile.rglob('*')]:
        info = path.lstat()
        if (not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode) or
                 (stat.S_ISLNK(info.st_mode) and path.parent == profile / 'programs'))
                or stat.S_ISREG(info.st_mode) and info.st_nlink != 1):
            raise ReviewError('评审设置只允许独立普通文件、目录和程序登记链接')
        for item in {path, *path.parents, path.resolve(), *path.resolve().parents}:
            info = item.lstat()
            if info.st_uid != 0 or (not stat.S_ISLNK(info.st_mode) and info.st_mode & 0o022 and not
                    (stat.S_ISDIR(info.st_mode) and info.st_mode & stat.S_ISVTX)):
                raise ReviewError('评审程序和设置须由发布账号持有且腿不可改写')
    return profile


def account_data():
    root = data_path('review-account')
    root.mkdir(mode=0o700, exist_ok=True)
    info = root.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
        raise ReviewError('评审账号运行数据目录须由发布账号私有持有')
    return root


def next_group():
    # Never reuse a job group: a previous job may leave setgid files in its
    # writable login store. This counter is publisher-private, not OS accounts.
    path = account_data() / 'group-counter'
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'r+') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        info = os.fstat(stream.fileno())
        if info.st_uid != 0 or info.st_nlink != 1 or info.st_mode & 0o077:
            raise ReviewError('评审运行组计数器权限不安全')
        gid = int(stream.read() or str(0xc0000000)) + 1
        if gid >= 0xfffffffe:
            raise ReviewError('评审运行组计数器已耗尽')
        import grp
        ranges = []
        subordinate = Path('/etc/subgid')
        if subordinate.exists():
            for line in subordinate.read_text().splitlines():
                if line and not line.startswith('#'):
                    _, first, count = line.split(':')
                    ranges.append((int(first), int(first) + int(count)))
        while True:
            reserved = next((end for start, end in ranges if start <= gid < end), None)
            if reserved is not None:
                gid = reserved
                continue
            if gid >= 0xfffffffe:
                raise ReviewError('评审运行组计数器已耗尽')
            try:
                grp.getgrgid(gid)
            except KeyError:
                break
            gid += 1
        stream.seek(0)
        stream.write(str(gid))
        stream.truncate()
        stream.flush()
        os.fsync(stream.fileno())
        return gid


SEALED_DIRECTORY = 'sealed'
SEALED_COMPLETE = '.complete'


def login_fds(selected):
    result = []
    home = os.open(selected.pw_dir, os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for relative in MODEL_LOGINS.values():
            fd = os.dup(home)
            try:
                for component in Path(relative).parts:
                    child = os.open(component, os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                    os.close(fd)
                    fd = child
                if os.fstat(fd).st_uid != selected.pw_uid:
                    raise ReviewError('模型登录目录须属于评审腿账号')
                result.append((relative, fd))
                fd = -1
            except FileNotFoundError:
                pass
            finally:
                if fd >= 0:
                    os.close(fd)
    finally:
        os.close(home)
    return result


def account_client(command):
    # The root broker never decodes the provider environment (which may contain
    # a token). Only the unprivileged child loads it, after setpriv.
    fd = os.memfd_create('leg-environment', os.MFD_ALLOW_SEALING)
    try:
        os.write(fd, json.dumps(dict(os.environ)).encode())
        os.lseek(fd, 0, 0)
        fcntl.fcntl(fd, fcntl.F_ADD_SEALS, fcntl.F_SEAL_WRITE | fcntl.F_SEAL_GROW |
                    fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_SEAL)
        with socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET) as client:
            client.connect(os.environ['AIWORK_ACCOUNT_BROKER'])
            client.sendmsg([json.dumps({'command': command, 'cwd': os.getcwd()}).encode()],
                [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array('i', [fd, 0, 1, 2]))])
            return int(client.recv(64))
    finally:
        os.close(fd)


def account_job(setup_path):
    if os.geteuid() != 0:
        raise ReviewError('账号监管入口只允许发布账号运行')
    from types import SimpleNamespace
    setup = json.loads(Path(setup_path).read_text())
    selected = SimpleNamespace(**setup['account'])
    gid = setup['gid']
    root, view = Path(setup['root']), Path(setup['view'])
    logins = login_fds(selected)
    def mount(*args):
        subprocess.run(['/usr/bin/mount', *map(str, args)], check=True,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    mount('--bind', root, view)
    home = view / 'home'
    if home.exists():
        shutil.rmtree(home)
    if (root / SEALED_DIRECTORY).exists():
        shutil.rmtree(root / SEALED_DIRECTORY)
    home.mkdir(mode=0o700)
    templates = Path(setup['profile']) / 'home'
    if templates.exists():
        shutil.copytree(templates, home, dirs_exist_ok=True)
    for relative in MODEL_LOGINS.values():
        (home / relative).mkdir(parents=True, exist_ok=True)
    for path in [home, *home.rglob('*')]:
        os.chown(path, selected.pw_uid, gid, follow_symlinks=False)
    # Keep the NSS home spelling stable. No system-root read-only remount, DNS
    # copying, chroot or system-directory exceptions are involved.
    mount('--bind', home, selected.pw_dir)
    persistent = view / 'login'
    persistent.mkdir(mode=0o750, exist_ok=True)
    os.chown(persistent, 0, gid)
    persistent.chmod(0o750)
    for relative, fd in logins:
        target = persistent / 'codex' if relative == MODEL_LOGINS['codex'] else Path(selected.pw_dir) / relative
        target.mkdir(parents=True, exist_ok=True)
        mount('--no-canonicalize', '--bind', '/proc/' + str(os.getpid()) + '/fd/' + str(fd), target)
        os.close(fd)
    broker_path = view / 'broker'
    broker_path.unlink(missing_ok=True)
    broker = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    broker.setsockopt(socket.SOL_SOCKET, socket.SO_PASSCRED, 1)
    broker.bind(str(broker_path))
    os.chown(broker_path, 0, gid)
    os.chmod(broker_path, 0o660)
    broker.listen()
    module = view / 'runtime/bin/_leg_session.py'
    minimal = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'}
    spawn_lock = threading.Lock()
    closing = threading.Event()
    def serve(connection):
        fds = []
        try:
            payload, ancillary, flags, _ = connection.recvmsg(131072, 256)
            credentials = None
            for level, kind, data in ancillary:
                if level == socket.SOL_SOCKET and kind == socket.SCM_CREDENTIALS:
                    credentials = struct.unpack('iII', data)
                elif level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                    received = array.array('i')
                    received.frombytes(data[:len(data) - len(data) % received.itemsize])
                    fds.extend(received)
            if flags or len(fds) != 4 or credentials is None or not (
                    credentials[0] > 0 and credentials[1:] == (selected.pw_uid, gid)):
                raise ReviewError('拒绝非本次评审的 CLI 请求')
            request = json.loads(payload)
            # Every client controls only its own unprivileged command; no uid,
            # mounts, capabilities or privileged environment are caller inputs.
            with spawn_lock:
                if closing.is_set():
                    raise ReviewError('评审已结束')
                process = subprocess.Popen(['/usr/bin/unshare', '--pid', '--fork', '--kill-child',
                '--mount-proc', '--', *drop_command(selected, gid), str(Path(setup['profile']) / 'programs/python3'), '-Es',
                str(module), '--account-env', str(fds[0]), *request['command']],
                env=minimal, cwd=request['cwd'], pass_fds=(fds[0],),
                    stdin=fds[1], stdout=fds[2], stderr=fds[3], start_new_session=True)
            # The timeout wraps the unprivileged client, not this root helper.
            # Disconnect must cancel its CLI as well, or inherited stdout keeps
            # the adapter's decoder pipeline alive after the timeout fired.
            while process.poll() is None:
                readable, _, _ = select.select([connection], [], [], 0.1)
                if readable:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    break
            connection.send(str(process.wait()).encode())
        except Exception:
            try:
                connection.send(b'78')
            except OSError:
                pass
        finally:
            for fd in fds:
                os.close(fd)
            connection.close()
    def accept():
        while True:
            connection, _ = broker.accept()
            threading.Thread(target=serve, args=(connection,), daemon=True).start()
    threading.Thread(target=accept, daemon=True).start()
    env = setup['env']
    env['AIWORK_ACCOUNT_BROKER'] = str(broker_path)
    env['AIWORK_ACCOUNT_LOGIN'] = str(persistent / 'codex')
    # Authentication copying/syncing is performed by the ordinary account;
    # publisher code does not open any model login contents.
    result = subprocess.run([*drop_command(selected, gid), str(Path(setup['profile']) / 'programs/python3'), '-Es',
        str(module), '--account-adapter', *setup['command']], cwd=setup['cwd'], env=env, check=False)
    with spawn_lock:
        closing.set()
    # Kill every survivor before sealing files. Outer PID 1 remains root and
    # cannot be signalled or ptraced by the leg. Its lifetime is the job's.
    for path in Path('/proc').iterdir():
        if path.name.isdigit() and int(path.name) not in (1, os.getpid()):
            try:
                os.kill(int(path.name), signal.SIGKILL)
            except ProcessLookupError:
                pass
    while True:
        try:
            os.waitpid(-1, 0)
        except ChildProcessError:
            break
    work = view / 'work'
    if work.exists():
        sealed = root / SEALED_DIRECTORY
        sealed.mkdir(mode=0o700)
        fd = os.open(work, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            for path in managed_artifacts(work).values():
                name = path.name
                try:
                    output = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                except FileNotFoundError:
                    continue
                with os.fdopen(output, 'rb') as stream:
                    info = os.fstat(stream.fileno())
                    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                        raise ReviewError('评审输出不是独立普通文件；拒绝接收')
                    (sealed / name).write_bytes(stream.read())
        finally:
            os.close(fd)
        (sealed / SEALED_COMPLETE).touch(mode=0o600)
    return result.returncode


def account_adapter(command):
    if Path(command[0]).name != 'subcodex':
        return subprocess.call(command)
    login = Path(os.environ['AIWORK_ACCOUNT_LOGIN']) / 'auth.json'
    auth = Path.home() / MODEL_LOGINS['codex'] / 'auth.json'
    auth.parent.mkdir(parents=True, exist_ok=True)
    if not login.parent.exists():
        return subprocess.call(command)
    # Only Codex needs auth copied away from persistent config. Serialize those
    # copies, and never overwrite a concurrent manual login or unchanged auth.
    # These reads and writes all run as the ordinary account, never publisher.
    fd = os.open(login.parent / '.aiwork-review.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'r+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        original = sha256_file(login) if login.exists() else None
        if original is not None:
            shutil.copyfile(login, auth)
        result = subprocess.call(command)
        if auth.exists() and sha256_file(auth) != original:
            current = sha256_file(login) if login.exists() else None
            if current != original:
                raise ReviewError('登录已被其他会话更新；保留该更新，本次不覆盖')
            temporary = login.with_name('auth.aiwork-' + str(os.getpid()) + '.json')
            shutil.copyfile(auth, temporary)
            os.replace(temporary, login)
        return result


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
    profile = trusted_settings(selected)
    gid = next_group()
    with tempfile.TemporaryDirectory(prefix='job-', dir=account_data()) as name, \
            tempfile.TemporaryDirectory(prefix='aiwork-view-', dir='/var/tmp') as view:
        root = Path(name)
        os.chown(root, 0, gid)
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
            if relative == Path('.') or (relative.parent == Path('bin') and
                    relative.name in ('review-pr', 'gh-app-token')):
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
            os.chown(path, 0, gid)
            path.chmod(0o750 if path.is_dir() or path.stat().st_mode & 0o111 else 0o640)
        setup = root / 'setup.json'
        setup.write_text(json.dumps({'root': str(root), 'view': view, 'gid': gid,
            'profile': str(profile), 'account': {'pw_uid': selected.pw_uid,
            'pw_gid': selected.pw_gid, 'pw_dir': selected.pw_dir}}))
        setup.chmod(0o600)
        env.update(AIWORK_ACCOUNT_SETUP=str(setup), AIWORK_CONFIG_DIR=str(profile),
                   AIWORK_DATA_DIR=str(root / 'work/data'), TMPDIR=str(root / 'work/tmp'),
                   PYTHONNOUSERSITE='1')
        work = root / 'work'
        work.mkdir(mode=0o770)
        work.chmod(0o770)
        os.chown(work, 0, gid)
        for name in ('tmp', 'data'):
            (work / name).mkdir(mode=0o700)
            os.chown(work / name, selected.pw_uid, gid)
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
        setup = json.loads(Path(child_env['AIWORK_ACCOUNT_SETUP']).read_text())
        gid = setup['gid']
        source = root / 'repo'
        shutil.copytree(repo, source, symlinks=True)
        task_copy = root / 'task.md'
        shutil.copyfile(task, task_copy)
        os.chown(task_copy, 0, gid)
        task_copy.chmod(0o640)
        for path in [source, *source.rglob('*')]:
            if not path.is_symlink():
                os.chown(path, 0, gid)
                path.chmod(0o750 if path.is_dir() or path.stat().st_mode & 0o111 else 0o640)
        work = root / 'work'
        # Local clone/upload-pack clears repository-scoped config environment.
        # A per-run global file trusts only this root-owned source (both Git
        # spellings), without editing the leg account's persistent Git config.
        git_config = root / 'gitconfig'
        view_source = Path(setup['view']) / 'repo'
        git_config.write_text('[safe]\n\tdirectory = ' + str(view_source)
                              + '\n\tdirectory = ' + str(view_source / '.git') + '\n')
        os.chown(git_config, 0, gid)
        git_config.chmod(0o640)
        # These are public invocation parameters, not arbitrary publisher env.
        parameters = {'PANEL_DIFF_BASE', 'AIWORK_REVIEW_PR', 'CURSOR_MODEL'}
        parameters.update(spec[0] for settings in RUNTIME_OPTIONS.values() for spec in settings.values())
        child_env.update({key: value for key, value in env.items() if key in parameters})
        artifacts = managed_artifacts(work)
        child_env.update(AIWORK_REVIEW_RESULT_BIN=str(bundle / '_review_result.py'),
            AIWORK_REVIEW_FACTS_PATH=str(artifacts['facts']),
            AIWORK_REVIEW_REPORT_PATH=str(artifacts['report']),
            GIT_CONFIG_GLOBAL=str(git_config))
        result = execute(selected, [bundle / Path(command[0]).name, command[1], task_copy,
            artifacts['log'], source], env=child_env, cwd=work)
        sealed = root / SEALED_DIRECTORY
        if not (sealed / SEALED_COMPLETE).exists():
            raise ReviewError('账号监管未封存结果：' + result.stderr[-800:])
        for path in artifacts.values():
            name = path.name
            if (sealed / name).exists():
                (directory / name).write_bytes((sealed / name).read_bytes())
        return result


if __name__ == '__main__':
    if sys.argv[1] == '--account-job':
        raise SystemExit(account_job(sys.argv[2]))
    if sys.argv[1] == '--account-cli':
        raise SystemExit(account_client(sys.argv[2:]))
    if sys.argv[1] == '--account-env':
        with os.fdopen(int(sys.argv[2])) as stream:
            env = json.load(stream)
        os.execvpe(sys.argv[3], sys.argv[3:], env)
    if sys.argv[1] == '--account-adapter':
        raise SystemExit(account_adapter(sys.argv[2:]))
    raise SystemExit(78)

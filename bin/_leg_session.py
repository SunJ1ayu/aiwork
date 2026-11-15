#!/usr/bin/env python3
"""Shared leg invocation, repository snapshot, and report file for review-pr and explore."""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
from typing import NamedTuple, cast

from _review_result import load_result, sha256_file


SHA = re.compile(r"^[0-9a-f]{40}$")


class ReviewError(ValueError):
    pass


def without_publication_credentials(env: dict[str, str]) -> dict[str, str]:
    return {key: value for key, value in env.items() if key not in (
        'GH_TOKEN', 'GITHUB_TOKEN', 'AIWORK_REVIEW_GIT_TOKEN', 'GIT_ASKPASS')}


def reader_environment(leg: str, env: dict[str, str]) -> dict[str, str]:
    """Freeze resolved reader parameters before the direct wrapper sees them."""
    from _aiwork_config import ConfigError, runtime_settings
    try:
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


def run_isolated_leg(command: list[str], *, env: dict[str, str], directory: Path,
                     repo: Path, task: Path, bin_dir: Path):
    """Only the trusted publisher runs outside this filesystem/process boundary."""
    import shutil
    import tempfile
    import stat
    from _aiwork_config import apps_dir, config_dir, app_key, data_dir

    bwrap = Path('/usr/bin/bwrap')
    if not bwrap.is_file():
        raise ReviewError('评审隔离需要 bubblewrap；未启动评审腿')
    caller = Path.cwd()
    env = without_publication_credentials(env)
    env['HOME'] = str(Path(env.get('HOME', str(Path.home()))).resolve())
    config = config_dir(environ=env).resolve()
    env['AIWORK_CONFIG_DIR'] = str(config)
    apps = apps_dir(environ=env).resolve()
    env['AIWORK_APPS_DIR'] = str(apps)
    data = data_dir(environ=env)
    env['AIWORK_DATA_DIR'] = str(data)
    for variable in ('CURSOR_AUTH_FILE', 'XDG_CONFIG_HOME',
                     'AIWORK_REVIEW_RESULT_BIN'):
        if env.get(variable):
            env[variable] = str(Path(env[variable]).resolve())
    if env.get('KIMI_REVIEW_HOME'):
        env['KIMI_REVIEW_HOME'] = str(Path(env['KIMI_REVIEW_HOME']).absolute())
    directory, repo, task = directory.resolve(), repo.resolve(), task.resolve()
    # Role configuration is trusted input, as in gh-app-token. Read only KEY's
    # path; never open or copy private-key contents. Resolve symlink targets too.
    hidden = {apps} if apps.exists() else set()
    if apps.exists():
        for role in apps.glob('*.env'):
            selected = subprocess.run(
                ['/bin/bash', '-c', 'set -eu; KEY=; . "$1"; printf "%s" "${KEY:?}"',
                 'app-key-path', str(role)], env=env, text=True, capture_output=True)
            if selected.returncode or not selected.stdout:
                raise ReviewError('无法确定发布钥匙位置；未启动评审腿')
            key = app_key(selected.stdout, environ=env).resolve(strict=True)
            if not stat.S_ISREG(key.stat().st_mode) or key.stat().st_nlink != 1:
                raise ReviewError('发布钥匙有硬链接副本；未启动评审腿')
            if not key.is_relative_to(apps):
                hidden.add(key)

    def protected(path: Path) -> bool:
        return any(path.resolve().is_relative_to(hidden_path) for hidden_path in hidden)

    def tool_ignores(directory, names):
        return [name for name in names if name == '__pycache__' or name.endswith('.pyc')
                or protected(Path(directory) / name)
                or not ((Path(directory) / name).is_file() or (Path(directory) / name).is_dir())]

    child_env = without_publication_credentials(env)
    with tempfile.TemporaryDirectory(prefix='aiwork-leg-home-') as scratch:
        # A privileged caller may start inside another user's private parent
        # (including sudo CI checkouts). Namespace root cannot traverse it.
        # Keep the same cwd name using a filtered snapshot and private parent
        # skeleton; never chmod the host or expose that user's sibling files.
        private_parents = []
        for parent in reversed((caller, *caller.parents)):
            info = parent.stat()
            execute = (stat.S_IXUSR if info.st_uid == os.getuid() else
                       stat.S_IXGRP if info.st_gid == os.getgid() else stat.S_IXOTH)
            if not info.st_mode & execute:
                private_parents.append(parent)
                break
        input_snapshots = {}

        def readable_source(path):
            if not any(path.is_relative_to(parent) for parent in private_parents):
                return path
            if protected(path):
                raise ReviewError('运行输入与发布凭证位置重叠；未启动评审腿')
            for original, snapshot in input_snapshots.items():
                if path.is_relative_to(original):
                    return snapshot / path.relative_to(original)
            snapshot = Path(scratch) / ('input-' + str(len(input_snapshots)))
            def input_ignores(directory, names):
                ignored = tool_ignores(directory, names)
                # The later masks need mountpoints within a read-only snapshot.
                # Preserve only empty placeholders, never credential/IPC data.
                for name in ignored:
                    entry = Path(directory) / name
                    if protected(entry) or (entry.exists() and not (entry.is_file() or entry.is_dir())):
                        placeholder = snapshot / entry.relative_to(path)
                        if entry.is_dir():
                            placeholder.mkdir(parents=True, exist_ok=True)
                        else:
                            placeholder.parent.mkdir(parents=True, exist_ok=True)
                            placeholder.touch()
                return ignored
            if path.is_dir():
                shutil.copytree(path, snapshot, ignore=input_ignores, dirs_exist_ok=True)
            else:
                shutil.copy2(path, snapshot)
            input_snapshots[path] = snapshot
            return snapshot
        # A root publisher can read a checkout owned by another user, but its
        # user namespace cannot traverse that user's private ancestors. Stage
        # trusted public tools before dropping privileges, never chmod the host.
        original_bin = bin_dir.resolve()
        tools = Path(scratch) / 'tools'
        shutil.copytree(original_bin, tools, ignore=tool_ignores)
        staged_paths = [tools]
        seed = original_bin.parent / 'kimi-review-home'
        if seed.is_dir() and not protected(seed):
            staged_seed = Path(scratch) / seed.name
            shutil.copytree(seed, staged_seed, ignore=tool_ignores)
            staged_paths.append(staged_seed)
        command = list(command)
        if Path(command[0]).resolve().parent == original_bin:
            command[0] = str(tools / Path(command[0]).name)
        result_bin = child_env.get('AIWORK_REVIEW_RESULT_BIN')
        if result_bin and Path(result_bin).resolve().parent == original_bin:
            child_env['AIWORK_REVIEW_RESULT_BIN'] = str(tools / Path(result_bin).name)
        # Resolver/hosts/NSS configuration can be symlinks into the private
        # runtime trees. Preserve only their data, never a runtime directory or
        # its sockets. Bind at the real targets so the original aliases work.
        network = Path(scratch) / 'network'
        network.mkdir(mode=0o700)
        network_files = []
        for name in ('resolv.conf', 'hosts', 'nsswitch.conf'):
            source = Path('/etc') / name
            if protected(source):
                raise ReviewError('网络配置与发布凭证位置重叠；未启动评审腿')
            if source.is_file():
                snapshot = network / name
                shutil.copyfile(source, snapshot)
                network_files.append((snapshot, source.resolve(strict=True)))
        private_roots = (Path('/tmp'), Path('/run'), *private_parents)
        readonly_directories = [(config, config)]
        if private_parents:
            readonly_directories.insert(0, (caller, caller))
        # Inputs hidden by private runtime mounts are restored at their caller
        # paths. Only directory data is exposed; IPC/special files and protected
        # credentials are masked below, including aliases introduced by binds.
        directory_inputs = [data]
        directory_inputs += [Path(part or str(caller)).absolute()
                             for part in env.get('PATH', '').split(os.pathsep)]
        for path in directory_inputs:
            if path.is_dir() and any(path.is_relative_to(root) for root in private_roots):
                readonly_directories.append((path.resolve(), path))
        input_masks = {}
        readonly_files = []
        pending = readonly_directories[:]
        readonly_directories = []
        visited = set()
        while pending:
            source, target = pending.pop()
            if (source, target) in visited:
                continue
            visited.add((source, target))
            readonly_directories.append((source, target))
            for parent, directories, files in os.walk(source, followlinks=False):
                for name in directories[:] + files:
                    entry = Path(parent) / name
                    mode = entry.stat().st_mode if entry.exists() else 0
                    if mode and (protected(entry) or not (stat.S_ISREG(mode) or stat.S_ISDIR(mode))):
                        if entry.is_symlink():
                            # The original alias must resolve even when its target
                            # was hidden by a private runtime mount. Mask the
                            # restored target, never mount through a dangling alias.
                            resolved = entry.resolve()
                            if stat.S_ISDIR(mode):
                                readonly_directories.append((resolved, resolved))
                            else:
                                readonly_files.append(resolved)
                            input_masks[resolved] = stat.S_ISDIR(mode)
                            if name in directories:
                                directories.remove(name)
                            continue
                        input_masks[target / entry.relative_to(source)] = stat.S_ISDIR(mode)
                        if name in directories:
                            directories.remove(name)
                    elif mode and entry.is_symlink():
                        resolved = entry.resolve()
                        if any(resolved.is_relative_to(root) for root in private_roots):
                            if stat.S_ISDIR(mode):
                                pending.append((resolved, resolved))
                            else:
                                readonly_files.append(resolved)
        cursor_auth = Path(env.get('CURSOR_AUTH_FILE') or
                           str(Path(env.get('XDG_CONFIG_HOME') or env['HOME'] + '/.config')
                               / 'cursor/auth.json'))
        readonly_files += [cursor_auth, Path(env['HOME']) / '.kimi-code/credentials/kimi-code.json']
        if child_env.get('AIWORK_REVIEW_RESULT_BIN'):
            readonly_files.append(Path(child_env['AIWORK_REVIEW_RESULT_BIN']))
        kimi_home = env.get('KIMI_REVIEW_HOME')
        kimi_state = None
        if kimi_home and Path(kimi_home).is_dir():
            if protected(Path(kimi_home)):
                raise ReviewError('模型运行目录与发布凭证位置重叠；未启动评审腿')
            kimi_state = Path(scratch) / 'kimi'
            shutil.copytree(kimi_home, kimi_state, ignore=tool_ignores)
        # Codex otherwise updates the publisher account's persistent config/sessions.
        codex_source = Path(env.get('CODEX_HOME', env['HOME'] + '/.codex')).resolve()
        codex_home = Path(scratch) / 'codex'
        codex_home.mkdir(mode=0o700)
        output = Path(scratch) / 'output'
        output.mkdir(mode=0o700)
        for name in ('auth.json', 'config.toml', 'models_cache.json'):
            source = codex_source / name
            if Path(command[0]).name == 'subcodex' and not protected(source) and source.is_file():
                shutil.copyfile(source, codex_home / name)
        child_env['CODEX_HOME'] = str(codex_home)
        child_env['TMPDIR'] = '/tmp'
        child_env.pop('REVIEW_WORKSPACE_BASE', None)
        child_env['AIWORK_LEG_ISOLATED'] = '1'
        argv = [str(bwrap), '--die-with-parent', '--new-session', '--unshare-user',
                '--unshare-pid', '--unshare-ipc', '--unshare-uts', '--cap-drop', 'ALL',
                '--ro-bind', '/', '/']
        for root in private_roots:
            argv += ['--tmpfs', str(root)]
        argv += ['--proc', '/proc', '--dev', '/dev']
        # Tests and supported installations may keep tools/settings under /tmp.
        # Restore only these read-only paths, never the publisher's whole temp tree.
        for path in (*staged_paths, Path(command[0]).resolve()):
            argv += ['--ro-bind', str(path), str(path)]
        for source, target in dict.fromkeys(readonly_directories):
            if protected(source):
                continue
            argv += ['--ro-bind', str(source), str(target)]
        for path in readonly_files:
            if path.is_file() and not protected(path):
                argv += ['--ro-bind', str(path.resolve()), str(path)]
        argv += ['--bind', str(codex_home), str(codex_home)]
        if kimi_state is not None:
            argv += ['--bind', str(kimi_state), kimi_home]
        argv += ['--bind', str(output), str(directory),
                 '--ro-bind', str(repo), str(repo), '--ro-bind', str(task), str(task)]
        for snapshot, target in network_files:
            argv += ['--ro-bind', str(snapshot), str(target)]
        for path, directory_mask in sorted(input_masks.items()):
            argv += (['--tmpfs', str(path), '--remount-ro', str(path)] if directory_mask
                     else ['--ro-bind', '/dev/null', str(path)])
        # Apply masks last, including keys configured outside apps/ or via symlinks.
        for path in sorted(hidden):
            if path.is_dir():
                argv += ['--tmpfs', str(path), '--remount-ro', str(path)]
            else:
                argv += ['--ro-bind', '/dev/null', str(path)]
        # Wrappers initialize caller settings here, then explicitly run their
        # provider in a disposable repository. Do not change their starting cwd.
        argv += ['--dir', str(caller)]
        for parent in private_parents:
            argv += ['--remount-ro', str(parent)]
        # Inputs beneath private parents use filtered snapshots, including
        # settings and declared PATH/link targets outside the caller directory.
        for index, option in enumerate(argv):
            if option == '--ro-bind':
                argv[index + 1] = str(readable_source(Path(argv[index + 1])))
        argv += ['--chdir', str(caller), '--', *command]
        try:
            completed = subprocess.run(argv, text=True, capture_output=True, env=child_env, check=False)
            # The model may leave symlinks/devices/FIFOs. The parent must never
            # follow them with its own credentials or write through their targets.
            for name in ('review.log', 'facts.json', 'report.md',
                         'review.stream.jsonl', 'review.stream-summary.json',
                         'review.log.stream.jsonl', 'review.stderr'):
                try:
                    fd = os.open(output / name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                except FileNotFoundError:
                    continue
                with os.fdopen(fd, 'rb') as stream:
                    info = os.fstat(stream.fileno())
                    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                        raise ReviewError('评审输出不是独立普通文件；拒绝接收')
                    (directory / name).write_bytes(stream.read())
            return completed
        except OSError as exc:
            raise ReviewError('无法启动评审隔离或安全收取结果') from exc


def run_leg_attempt(leg_name: str, family: str, task: Path, repo: Path, directory: Path,
                    env: dict[str, str], run_id: str, frozen_model: str | None, *,
                    bin_dir: Path, mode: str = "review",
                    review_contract_version: int | None = None):
    directory, repo, task, bin_dir = (path.resolve() for path in (directory, repo, task, bin_dir))
    log, facts = directory / "review.log", directory / "facts.json"
    report = directory / "report.md"
    result_file, diagnostic = directory / "result.json", directory / "leg.stderr"
    env = dict(env, AIWORK_REVIEW_FACTS_PATH=str(facts), AIWORK_REVIEW_REPORT_PATH=str(report))
    command = [str(bin_dir / leg_name), mode, str(task), str(log), str(repo)]
    if mode == "review":
        leg = run_isolated_leg(command, env=env, directory=directory,
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

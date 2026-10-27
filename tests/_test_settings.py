"""Disposable machine settings for offline tests; never inspect user settings."""
import atexit
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import stat
import sys
import tempfile

# Existing model samples, retained as test data after defaults leave the repo.
MODELS = {'codex': 'gpt-6-sol', 'cursor': 'grok-4.7-high',
          'deepseek': 'deepseek-flash', 'gemini': 'gemini-3.8-flash-high',
          'glm': 'glm-5.3-flash', 'grok': 'grok-4.6',
          'kimi': 'kimi-code/kimi-for-coding', 'mimo': 'mimo-v2.6-pro'}


PROXY_BYPASS = {'NO_PROXY': '*', 'no_proxy': '*'}


def inherited_environment_keys():
    """Remove inherited review context and proxy settings before suites set fixtures."""
    return [key for key in os.environ
            if key.startswith(('AIWORK_REVIEW_', 'PANEL_', 'REVIEW_'))
            or key.lower().endswith('_proxy') or key.lower() == 'git_proxy_command']


def clear_inherited_environment():
    for key in inherited_environment_keys():
        os.environ.pop(key)
    # A nonempty proxy dictionary also prevents urllib's macOS system-proxy fallback.
    os.environ.update(PROXY_BYPASS)


PROGRAMS = ('codex', 'cursor-agent', 'kimi', 'claude')


def context():
    """A supervisor's locked record proves its disposable tree is still live.

    Children reopen the record, so Python's default close_fds does not lose
    ownership. Exported paths alone, or a record without its live lock, do
    not authorize fixtures. This prevents accidents, not malicious callers.
    """
    try:
        path = os.environ.get('AIWORK_TEST_CONTEXT')
        if not path:
            return None
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd) as stream:
            info = os.fstat(stream.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                    or info.st_uid != os.getuid() or info.st_size > 4096):
                return None
            try:
                fcntl.flock(stream, fcntl.LOCK_SH | fcntl.LOCK_NB)
            except BlockingIOError:
                pass  # The supervisor still owns the exclusive lock.
            else:
                return None
            record = json.load(stream)
        root = Path(record['root'])
        current = root.stat()
        if (record['kind'] != 'aiwork-test-settings'
                or Path(path).parent != root
                or [current.st_dev, current.st_ino] != record['identity']):
            return None
        return root
    except (OSError, ValueError, KeyError, TypeError):
        return None


def owned_settings():
    owned = context()
    return bool(owned and os.environ.get('AIWORK_TEST_TMPDIR') == str(owned)
        and os.environ.get('AIWORK_PROGRAMS') == str(Path(os.environ.get('AIWORK_CONFIG_DIR', '')) / 'programs')
        and all(
        os.environ.get(key) and Path(os.environ[key]).resolve().is_relative_to(owned)
        and Path(os.environ[key]).is_dir()
        for key in ('AIWORK_CONFIG_DIR', 'AIWORK_DATA_DIR')))


def write_platform_probe(directory, *, macos=False):
    """Give disposable deployments the real routing rules with a fixed probe."""
    helper = Path(__file__).resolve().parents[1] / 'bin/_review-platform.sh'
    source, count = re.subn(r'review_platform_is_macos\(\) \{[^}]*\}',
                            'review_platform_is_macos() { return ' + ('0' if macos else '1') + '; }',
                            helper.read_text())
    if count != 1:
        raise ValueError('platform probe definition not found')
    (Path(directory) / helper.name).write_text(source)


def fixture_directory(directory):
    owned = context()
    if not owned:
        raise ValueError('fixture operation requires a test-owned context')
    root = owned
    path = Path(directory)
    if not path.resolve().is_relative_to(root):
        raise ValueError('program fixtures must live in the disposable test directory')
    return path


def _fixture_launcher(programs, name, source):
    with tempfile.NamedTemporaryFile(mode='w', dir=programs, delete=False) as temporary:
        temporary.write(source)
        os.chmod(temporary.name, 0o755)
    launcher = programs / name
    os.replace(temporary.name, launcher)
    return launcher


def claude_fixture_launcher(programs, target):
    """Model stubs also implement the native CLI's offline MCP startup protocol."""
    source = '#!' + sys.executable + '\n' + """
import json, os, sys
if sys.argv[-2:] == ['mcp', 'serve']:
    for line in sys.stdin:
        message = json.loads(line)
        if message.get('method') == 'initialize':
            result = {'protocolVersion': '2024-11-05', 'capabilities': {},
                      'serverInfo': {'name': 'offline-fixture', 'version': '2.1.301'}}
        elif message.get('method') == 'tools/call':
            result = {'content': [{'type': 'text', 'text': json.dumps({
                'stdout': 'AIWORK_NATIVE_SANDBOX_READY', 'stderr': '', 'interrupted': False})}]}
        else:
            continue
        print(json.dumps({'jsonrpc': '2.0', 'id': message['id'], 'result': result}), flush=True)
    raise SystemExit(0)
""" + 'os.execv(' + repr(str(target)) + ', [' + repr(str(target)) + '] + sys.argv[1:])\n'
    return _fixture_launcher(programs, '_claude-fixture', source)


def kimi_fixture_launcher(programs, target):
    """Exercise native reader preflight separately from the scenario's vendor stub."""
    fixture_directory(target)
    fixture = Path(__file__).resolve().with_name('_kimi_cli.py')
    schemas = fixture.parent / 'fixtures/kimi-code-0.36.1/reader-tools.json'
    command = [sys.executable, str(fixture), '--native-fixture', str(schemas),
               'valid', str(programs / 'kimi-probe-capture.json')]
    source = ('#!' + sys.executable + '\nimport os,sys\n'
              + 'if os.environ.get("AIWORK_KIMI_GUARD_PROBE_TAG"):\n'
              + '    os.execv(' + repr(sys.executable) + ', ' + repr(command) + ' + sys.argv[1:])\n'
              + 'os.execv(' + repr(str(target)) + ', [' + repr(str(target)) + '] + sys.argv[1:])\n')
    return _fixture_launcher(programs, '._kimi-fixture', source)


def write_programs(directory, fake=None):
    """Bind only disposable provider stubs; python/node belong to the test runtime."""
    programs = fixture_directory(directory) / 'programs'
    programs.mkdir(parents=True, exist_ok=True)
    reject = programs / '_unconfigured-provider'
    reject.write_text('#!/bin/sh\necho "test provider has no explicit stub" >&2\nexit 97\n')
    reject.chmod(0o755)
    runtime = {'python3': Path(sys.executable).resolve(), 'node': Path(shutil.which('node')).resolve()}
    for name in ('python3', 'node', *PROGRAMS):
        target = runtime.get(name, reject)
        if fake is not None and (Path(fake) / name).exists():
            target = Path(fake) / name
            if name == 'claude':
                target = claude_fixture_launcher(programs, target)
            elif name == 'kimi':
                target = kimi_fixture_launcher(programs, target)
        link = programs / name
        link.unlink(missing_ok=True)
        link.symlink_to(target)
    return programs


def run_with_programs(command):
    """Freeze shell oracle stubs for this invocation, then restore its fixtures."""
    source = fixture_directory(os.environ['AIWORK_CONFIG_DIR'])
    programs = source / 'programs'
    if not programs.exists():
        write_programs(source)
    saved = {name: os.readlink(programs / name) for name in ('python3', 'node', *PROGRAMS)}
    try:
        write_programs(source)
        for name in (*PROGRAMS, 'node'):
            search = os.pathsep.join(p for p in os.environ['PATH'].split(os.pathsep)
                                    if Path(p).resolve() != programs.resolve())
            target = shutil.which(name, path=search)
            if target:
                try:
                    fixture_directory(target)
                except ValueError:
                    continue
                (programs / name).unlink(missing_ok=True)
                if name == 'claude':
                    target = claude_fixture_launcher(programs, target)
                elif name == 'kimi':
                    target = kimi_fixture_launcher(programs, target)
                (programs / name).symlink_to(target)
        return subprocess.call(command)
    finally:
        for name, target in saved.items():
            (programs / name).unlink(missing_ok=True)
            (programs / name).symlink_to(target)


def write_settings(directory):
    directory = fixture_directory(directory)
    directory.mkdir(parents=True, exist_ok=True)
    write_programs(directory)
    (directory / 'models.env').write_text(''.join(f'{k}={v}\n' for k, v in MODELS.items()))
    (directory / 'mimo.env').write_text('MIMO_BASE_URL=https://token-plan-cn.xiaomimimo.com/anthropic\nMIMO_API_KEY=fixture-mimo-key\n')
    (directory / 'private-terms').write_text('unused\n')
    return directory


def write_kimi_config(home, config=None):
    """A caller-owned home must attach the same guard the wrapper preflights."""
    import json
    home = fixture_directory(home)
    (home / 'config.toml').write_text(
        'default_model = "fixture"\n[[hooks]]\nevent = "PreToolUse"\nmatcher = ".*"\ncommand = '
        + json.dumps(shlex.quote(str(Path(config or os.environ['AIWORK_CONFIG_DIR']) / 'programs/node')) + ' ' + shlex.quote(str(home / 'hooks/guard.mjs')))
        + '\ntimeout = 10\n')


def set_model(directory, leg, model):
    path = fixture_directory(directory) / 'models.env'
    lines = path.read_text().splitlines()
    found = False
    for i, line in enumerate(lines):
        if line.startswith(leg + '='):
            lines[i] = leg + '=' + model
            found = True
    if not found:
        lines.append(leg + '=' + model)
    path.write_text('\n'.join(lines) + '\n')


def ensure_settings(*, fresh=False):
    if fresh or not owned_settings():
        # Never create the new tree inside an inherited real data directory.
        temp = tempfile.TemporaryDirectory(prefix='ng-', dir='/tmp')
        atexit.register(temp.cleanup)
        root = Path(temp.name).resolve()
        info = root.stat()
        record = (root / '.context').open('x+')
        fcntl.flock(record, fcntl.LOCK_EX | fcntl.LOCK_NB)
        record.write(json.dumps({'kind': 'aiwork-test-settings', 'root': str(root),
                                 'identity': [info.st_dev, info.st_ino]}))
        record.flush()
        os.chmod(record.name, 0o400)
        atexit.register(record.close)
        os.environ['AIWORK_TEST_CONTEXT'] = record.name
        os.environ['AIWORK_CONFIG_DIR'] = str(root / 'settings')
        os.environ['AIWORK_DATA_DIR'] = str(root / 'data')
        (root / 'data').mkdir()
        write_settings(root / 'settings')
    root = context()
    os.environ['AIWORK_PROGRAMS'] = str(Path(os.environ['AIWORK_CONFIG_DIR']) / 'programs')
    os.environ.pop('AIWORK_TEST_FIXTURE_ROOT', None)
    os.environ['AIWORK_TEST_TMPDIR'] = str(root)
    os.environ.pop('AIWORK_TEST_RUNNER_READY', None)
    if not Path(os.environ.get('TMPDIR', '/')).resolve().is_relative_to(root):
        os.environ['TMPDIR'] = str(root)
    tempfile.tempdir = None


if __name__ == '__main__':
    if sys.argv[1] == 'owned':
        raise SystemExit(0 if owned_settings() else 1)
    elif sys.argv[1] == 'run-with-programs':
        raise SystemExit(run_with_programs(sys.argv[2:]))
    elif sys.argv[1] == 'clear-inherited-env':
        keys = inherited_environment_keys()
        print(shlex.join(['unset', '-v', '--', *keys]) if keys else ':')
        print(shlex.join(['export', *(key + '=' + value for key, value in PROXY_BYPASS.items())]))
    elif sys.argv[1] == 'kimi-config':
        write_kimi_config(sys.argv[2])
    elif sys.argv[1] == 'set-model':
        set_model(os.environ['AIWORK_CONFIG_DIR'], *sys.argv[2:])
    elif sys.argv[1] == 'mktemp':
        # BSD mktemp can ignore TMPDIR; both languages allocate in the owned tree.
        directory = fixture_directory(os.environ['TMPDIR'])
        if sys.argv[2:] == ['-d']:
            print(tempfile.mkdtemp(prefix='tmp.', dir=directory))
        elif not sys.argv[2:]:
            fd, path = tempfile.mkstemp(prefix='tmp.', dir=directory)
            os.close(fd)
            print(path)
        else:
            raise SystemExit('test_mktemp accepts only -d or no arguments')
    else:
        command = sys.argv[1:]
        isolated = command[:1] == ['--isolated']
        if isolated:
            command = command[1:]
        if command[:1] == ['--workspace']:
            command = command[1:]
        ensure_settings(fresh=isolated)
        raise SystemExit(subprocess.call(command))

"""Disposable machine settings for offline tests; never inspect user settings."""
import atexit
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

# Existing model samples, retained as test data after defaults leave the repo.
MODELS = {'codex': 'gpt-6-sol', 'cursor': 'grok-4.7-high',
          'deepseek': 'deepseek-flash', 'gemini': 'gemini-3.8-flash-high',
          'glm': 'glm-5.3-flash', 'grok': 'grok-4.6',
          'kimi': 'kimi-code/kimi-for-coding', 'mimo': 'xiaomi/mimo-v2.6-pro'}


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


PROGRAMS = ('codex', 'cursor-agent', 'kimi', 'mimo', 'claude')


def fixture_directory(directory):
    root = Path(os.environ.get('AIWORK_TEST_FIXTURE_ROOT', tempfile.gettempdir())).resolve()
    path = Path(directory)
    if not path.resolve().is_relative_to(root):
        raise ValueError('program fixtures must live in the disposable test directory')
    return path


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
            if target and Path(target).resolve().is_relative_to(Path(tempfile.gettempdir()).resolve()):
                (programs / name).unlink(missing_ok=True)
                (programs / name).symlink_to(target)
        return subprocess.call(command)
    finally:
        for name, target in saved.items():
            (programs / name).unlink(missing_ok=True)
            (programs / name).symlink_to(target)


def write_settings(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    write_programs(directory)
    (directory / 'models.env').write_text(''.join(f'{k}={v}\n' for k, v in MODELS.items()))
    (directory / 'private-terms').write_text('unused\n')
    return directory


def write_kimi_config(home, config=None):
    """A caller-owned home must attach the same guard the wrapper preflights."""
    import json
    home = Path(home)
    (home / 'config.toml').write_text(
        'default_model = "fixture"\n[[hooks]]\nevent = "PreToolUse"\nmatcher = ".*"\ncommand = '
        + json.dumps(shlex.quote(str(Path(config or os.environ['AIWORK_CONFIG_DIR']) / 'programs/node')) + ' ' + shlex.quote(str(home / 'hooks/guard.mjs')))
        + '\ntimeout = 10\n')


def set_model(directory, leg, model):
    path = Path(directory) / 'models.env'
    lines = path.read_text().splitlines()
    found = False
    for i, line in enumerate(lines):
        if line.startswith(leg + '='):
            lines[i] = leg + '=' + model
            found = True
    if not found:
        lines.append(leg + '=' + model)
    path.write_text('\n'.join(lines) + '\n')


def ensure_workspace():
    if not os.environ.get('AIWORK_TEST_TMPDIR'):
        workspace = tempfile.TemporaryDirectory(prefix='ng-')
        atexit.register(workspace.cleanup)
        os.environ['AIWORK_TEST_TMPDIR'] = workspace.name
        os.environ['TMPDIR'] = workspace.name


def ensure_settings(*, workspace=False):
    if workspace:
        ensure_workspace()
    if not os.environ.get('AIWORK_DATA_DIR'):
        data = tempfile.TemporaryDirectory(prefix='aiwork-test-data-')
        atexit.register(data.cleanup)
        os.environ['AIWORK_DATA_DIR'] = data.name
    if not os.environ.get('AIWORK_CONFIG_DIR'):
        temp = tempfile.TemporaryDirectory(prefix='aiwork-test-settings-')
        atexit.register(temp.cleanup)
        os.environ['AIWORK_CONFIG_DIR'] = str(write_settings(temp.name))


if __name__ == '__main__':
    if sys.argv[1] == 'run-with-programs':
        raise SystemExit(run_with_programs(sys.argv[2:]))
    elif sys.argv[1] == 'clear-inherited-env':
        keys = inherited_environment_keys()
        print(shlex.join(['unset', '-v', '--', *keys]) if keys else ':')
        print(shlex.join(['export', *(key + '=' + value for key, value in PROXY_BYPASS.items())]))
    elif sys.argv[1] == 'kimi-config':
        write_kimi_config(sys.argv[2])
    elif sys.argv[1] == 'set-model':
        set_model(os.environ['AIWORK_CONFIG_DIR'], *sys.argv[2:])
    else:
        command = sys.argv[1:]
        isolated = command[:1] == ['--isolated']
        if isolated:
            command = command[1:]
            os.environ['AIWORK_TEST_FIXTURE_ROOT'] = str(Path(tempfile.gettempdir()).resolve())
        if command[:1] == ['--workspace']:
            ensure_workspace()
            command = command[1:]
        with tempfile.TemporaryDirectory(prefix='aiwork-test-settings-') as directory, \
                tempfile.TemporaryDirectory(prefix='aiwork-test-data-') as data:
            env = dict(os.environ)
            env.setdefault('AIWORK_TEST_FIXTURE_ROOT', str(Path(tempfile.gettempdir()).resolve()))
            if isolated or not env.get('AIWORK_CONFIG_DIR'):
                env['AIWORK_CONFIG_DIR'] = str(write_settings(directory))
            if isolated or not env.get('AIWORK_DATA_DIR'):
                env['AIWORK_DATA_DIR'] = data
            if isolated:
                env['AIWORK_TEST_RUNNER_READY'] = '1'
            raise SystemExit(subprocess.call(command, env=env))

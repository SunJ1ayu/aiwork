"""Disposable machine settings for offline tests; never inspect user settings."""
import atexit
import os
from pathlib import Path
import shlex
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


def write_settings(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'models.env').write_text(''.join(f'{k}={v}\n' for k, v in MODELS.items()))
    (directory / 'private-terms').write_text('unused\n')
    return directory


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
    if sys.argv[1] == 'clear-inherited-env':
        keys = inherited_environment_keys()
        print(shlex.join(['unset', '-v', '--', *keys]) if keys else ':')
        print(shlex.join(['export', *(key + '=' + value for key, value in PROXY_BYPASS.items())]))
    elif sys.argv[1] == 'set-model':
        set_model(os.environ['AIWORK_CONFIG_DIR'], *sys.argv[2:])
    else:
        command = sys.argv[1:]
        if command[:1] == ['--workspace']:
            ensure_workspace()
            command = command[1:]
        with tempfile.TemporaryDirectory(prefix='aiwork-test-settings-') as directory, \
                tempfile.TemporaryDirectory(prefix='aiwork-test-data-') as data:
            env = dict(os.environ)
            if not env.get('AIWORK_CONFIG_DIR'):
                env['AIWORK_CONFIG_DIR'] = str(write_settings(directory))
            if not env.get('AIWORK_DATA_DIR'):
                env['AIWORK_DATA_DIR'] = data
            raise SystemExit(subprocess.call(command, env=env))

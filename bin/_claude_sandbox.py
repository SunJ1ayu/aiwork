"""Shared Mac Claude Code command policy for DeepSeek and MiMo."""
import json
import os
import sys
from pathlib import Path

TOOLS = ('Read', 'Glob', 'Grep', 'Bash')


def settings(home, repo, command_tmp):
    return {
        'permissions': {'blockReadsOutsideWorkingDirectories': True},
        'sandbox': {
            'enabled': True, 'failIfUnavailable': True,
            'allowUnsandboxedCommands': False, 'autoAllowBashIfSandboxed': True,
            'excludedCommands': [],
            'enableWeakerNetworkIsolation': False, 'allowAppleEvents': False,
            'network': {'allowedDomains': [], 'deniedDomains': ['*'],
                        'allowLocalBinding': False, 'allowAllUnixSockets': False,
                        'allowUnixSockets': [], 'allowMachLookup': []},
            'filesystem': {
                'allowWrite': [str(command_tmp)],
                'denyWrite': [str(home / '.npm/_logs'), '/tmp/claude', '/private/tmp/claude'],
                'denyRead': ['/'],
                'allowRead': [str(repo), str(command_tmp),
                    '/bin', '/sbin', '/usr/bin', '/usr/sbin', '/usr/lib',
                    '/usr/libexec', '/usr/share', '/System/Library', '/dev',
                    '/Library/Developer/CommandLineTools',
                    '/opt/homebrew/Cellar', '/opt/homebrew/opt', '/opt/homebrew/lib'],
            },
            'credentials': {'envVars': [{'name': name, 'mode': 'deny'} for name in sorted(
                set(os.environ) - {'PATH', 'HOME', 'TMPDIR', 'TMP', 'TEMP', 'SHELL',
                                   'LANG', 'LC_ALL', 'USER', 'LOGNAME', 'TERM',
                                   'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL', 'XDG_CONFIG_HOME'} |
                {'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'DEEPSEEK_API_KEY', 'MIMO_API_KEY'})]},
        },
    }


def preflight(cli, settings_file, repo):
    """Exercise native Bash through Claude's MCP server without dispatching a model."""
    import shlex
    import tempfile
    import select
    import signal
    import subprocess
    import time
    inside = tempfile.NamedTemporaryFile(prefix='.aiwork-read-check-', dir=repo)
    outside = tempfile.NamedTemporaryFile(prefix='aiwork-denied-read-', dir=Path(settings_file).parent)
    inside.write(b'probe'); inside.flush()
    outside.write(b'probe'); outside.flush()
    command = ('if /bin/cat ' + shlex.quote(inside.name) + ' >/dev/null 2>&1 && ! /bin/cat '
               + shlex.quote(outside.name) + ' >/dev/null 2>&1; then printf AIWORK_NATIVE_SANDBOX_READY; fi')
    process = subprocess.Popen(
        [cli, '--setting-sources', '', '--settings', settings_file, 'mcp', 'serve'],
        cwd=repo, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, start_new_session=True)
    pending = b''
    deadline = time.monotonic() + 20

    def request(message):
        nonlocal pending
        process.stdin.write((json.dumps(message) + '\n').encode())
        process.stdin.flush()
        if 'id' not in message:
            return None
        while True:
            if b'\n' not in pending:
                ready, _, _ = select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))
                if not ready:
                    raise ValueError('native sandbox preflight timed out')
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk or len(pending) > 1048576:
                    raise ValueError('native sandbox preflight missing response')
                pending += chunk
                continue
            line, pending = pending.split(b'\n', 1)
            reply = json.loads(line)
            if reply.get('id') == message['id']:
                if 'error' in reply:
                    raise ValueError('native sandbox preflight rejected')
                result = reply.get('result')
                if not isinstance(result, dict):
                    raise ValueError('native sandbox preflight invalid response')
                return result
    try:
        result = request({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
            'protocolVersion': '2024-11-05', 'capabilities': {},
            'clientInfo': {'name': 'aiwork-sandbox-preflight', 'version': '1'}}})
        if result.get('serverInfo', {}).get('version') != '2.1.301':
            raise ValueError('Claude Code must be 2.1.301')
        request({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        result = request({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {
            'name': 'Bash', 'arguments': {'command': command,
                                         'description': 'Offline native sandbox startup check'}}})
        content = result.get('content', [])
        if result.get('isError') or len(content) != 1:
            raise ValueError('native sandbox did not start')
        output = json.loads(content[0]['text'])
        if output.get('stdout') != 'AIWORK_NATIVE_SANDBOX_READY' or output.get('stderr') or output.get('interrupted'):
            raise ValueError('native sandbox did not run the startup check')
    finally:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            if process.poll() is None:
                raise
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        inside.close()
        outside.close()
        process.stdin.close()
        process.stdout.close()


if __name__ == '__main__':
    if sys.argv[1] == 'tools':
        print(','.join(TOOLS))
    elif sys.argv[1] == 'settings':
        dest, repo, command_tmp = map(Path, sys.argv[2:])
        dest.write_text(json.dumps(settings(Path.home(), repo.resolve(), command_tmp.resolve())) + '\n')
    elif sys.argv[1] == 'preflight':
        try:
            preflight(*sys.argv[2:])
        except (OSError, ValueError, KeyError, TypeError) as exc:
            print('Claude Code native sandbox preflight failed ⇒ 拒绝派发: ' + str(exc), file=sys.stderr)
            raise SystemExit(78)
    else:
        raise SystemExit(2)

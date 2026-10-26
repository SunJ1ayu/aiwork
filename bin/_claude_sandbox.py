"""Shared Mac Claude Code command policy for DeepSeek and MiMo."""
import json
import os
import sys
from pathlib import Path

TOOLS = ('Read', 'Glob', 'Grep', 'Bash')
PROXY_HOST = 'example.com'
AUTH_ENV_VARS = ('ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'DEEPSEEK_API_KEY', 'MIMO_API_KEY')

# Only constant public destinations and disposable files are probed.
PROBE = r'''
import errno
import os
from pathlib import Path
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request

inside, outside, port, proxy_host = sys.argv[1:5]
failed = []
def check(name, operation, denied=False):
    try:
        value = operation()
    except PermissionError as exc:
        passed = denied and exc.errno == errno.EPERM
    except Exception:
        passed = False
    else:
        passed = not denied and value is not False
    if not passed:
        failed.append(name)

def write(path):
    descriptor = os.open(path, os.O_WRONLY)
    os.close(descriptor)

def connect(address):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client:
        client.settimeout(1)
        client.connect(address)

def dns_packet():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.sendto(b'\0', ('1.1.1.1', 53))

def dns_lookup():
    try:
        socket.getaddrinfo(proxy_host, 443)
    except socket.gaierror:
        return True
    return False

def proxy():
    address = os.environ.get('HTTP_PROXY')
    if not address:
        return False
    endpoint = urllib.parse.urlsplit(address)
    if endpoint.hostname not in ('localhost', '127.0.0.1') or endpoint.port is None:
        return False
    # Resolve the native loopback endpoint locally; DNS itself must stay blocked.
    userinfo, separator, _ = endpoint.netloc.rpartition('@')
    authority = (userinfo + separator if separator else '') + '127.0.0.1:' + str(endpoint.port)
    address = endpoint._replace(netloc=authority).geturl()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({'http': address}))
    opener.addheaders = [('User-Agent', 'aiwork-sandbox-probe')]
    try:
        with opener.open('http://' + proxy_host + '/', timeout=2):
            return False
    except urllib.error.HTTPError as exc:
        return (exc.code == 403 and exc.geturl() == 'http://' + proxy_host + '/'
                and exc.headers.get('X-Proxy-Error') == 'blocked-by-allowlist')

check('read-inside', lambda: Path(inside).read_bytes() == b'probe')
check('read-outside', lambda: Path(outside).read_bytes(), denied=True)
check('write-inside', lambda: write(inside))
check('write-outside', lambda: write(outside), denied=True)
check('credential-env', lambda: all(name not in os.environ for name in sys.argv[5:]))
check('network-tcp', lambda: connect(('1.1.1.1',443)), denied=True)
check('network-loopback', lambda: connect(('127.0.0.1',int(port))), denied=True)
check('network-dns-packet', dns_packet, denied=True)
check('network-dns-lookup', dns_lookup)
check('network-proxy', proxy)
print('AIWORK_NATIVE_SANDBOX_FAILED:'+','.join(failed) if failed else 'AIWORK_NATIVE_SANDBOX_READY',end='')
'''


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
                set(AUTH_ENV_VARS))]},
        },
    }


def preflight(cli, settings_file, repo):
    """Exercise native Bash through Claude's MCP server without dispatching a model."""
    from contextlib import ExitStack
    import shlex
    import socket
    import tempfile
    import select
    import signal
    import subprocess
    import time
    with ExitStack() as resources:
        inside = resources.enter_context(tempfile.NamedTemporaryFile(prefix='.aiwork-read-check-', dir=repo))
        outside = resources.enter_context(tempfile.NamedTemporaryFile(prefix='aiwork-denied-read-', dir=Path(settings_file).parent))
        inside.write(b'probe'); inside.flush()
        outside.write(b'probe'); outside.flush()
        listener = resources.enter_context(socket.socket())
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        port = listener.getsockname()[1]
        # The listener is live; refusal must come from the sandbox, not a dead port.
        with socket.create_connection(('127.0.0.1', port), timeout=1):
            pass
        command = ' '.join(map(shlex.quote, [sys.executable, '-I', '-c', PROBE,
                            inside.name, outside.name, str(port), PROXY_HOST, *AUTH_ENV_VARS]))
        environment = dict(os.environ)
        # Probe only Claude's generated proxy, never an inherited authenticated proxy.
        for name in list(environment):
            if name.lower() in ('http_proxy', 'https_proxy', 'all_proxy', 'no_proxy'):
                del environment[name]
        environment.update({name: 'aiwork-harmless-credential-probe' for name in AUTH_ENV_VARS})
        process = subprocess.Popen(
            [cli, '--setting-sources', '', '--settings', settings_file, 'mcp', 'serve'],
            cwd=repo, stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=environment,
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
            request({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
                'protocolVersion': '2024-11-05', 'capabilities': {},
                'clientInfo': {'name': 'aiwork-sandbox-preflight', 'version': '1'}}})
            request({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
            result = request({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {
                'name': 'Bash', 'arguments': {'command': command,
                                             'description': 'Offline native sandbox startup check'}}})
            content = result.get('content', [])
            if result.get('isError') or len(content) != 1:
                raise ValueError('native sandbox did not start')
            output = json.loads(content[0]['text'])
            # Native denial diagnostics vary; the probe and tool status are the evidence.
            if output.get('stdout') != 'AIWORK_NATIVE_SANDBOX_READY' or output.get('interrupted'):
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

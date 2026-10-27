#!/usr/bin/env python3
"""Offline contract for the shared Claude Code sandbox settings."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import _no_egress  # noqa: F401,E402
import importlib.util
import unittest
import tempfile
import json

ROOT = Path(__file__).resolve().parents[1]

class ClaudeSandboxTests(unittest.TestCase):
    def test_shared_settings_require_confinement(self):
        spec = importlib.util.spec_from_file_location('claude_sandbox', ROOT / 'bin/_claude_sandbox.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        settings = module.settings(Path('/Users/fixture'), Path('/copy'), Path('/command-tmp'))
        sandbox = settings['sandbox']
        self.assertTrue(sandbox['enabled'])
        self.assertTrue(sandbox['failIfUnavailable'])
        self.assertFalse(sandbox['allowUnsandboxedCommands'])
        self.assertEqual(sandbox['excludedCommands'], [])
        self.assertEqual(sandbox['network']['allowedDomains'], [])
        self.assertFalse(sandbox['network']['allowLocalBinding'])
        self.assertFalse(sandbox['network']['allowAllUnixSockets'])
        self.assertTrue(settings['permissions']['blockReadsOutsideWorkingDirectories'])
        self.assertEqual(sandbox['filesystem']['denyRead'], ['/'])
        self.assertEqual(sandbox['filesystem']['allowWrite'], ['/command-tmp'])
        protected = {item['name'] for item in sandbox['credentials']['envVars'] if item['mode'] == 'deny'}
        self.assertTrue({'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'DEEPSEEK_API_KEY', 'MIMO_API_KEY'} <= protected)
        self.assertEqual(module.TOOLS, ('Read', 'Glob', 'Grep', 'Bash'))

    def test_read_scope_is_default_deny(self):
        spec = importlib.util.spec_from_file_location('claude_sandbox', ROOT / 'bin/_claude_sandbox.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        policy = module.settings(Path('/Users/fixture'), Path('/copy'), Path('/command-tmp'))['sandbox']['filesystem']
        self.assertIn('/', policy['denyRead'])
        self.assertEqual(policy['allowRead'][:2], ['/copy', '/command-tmp'])
        self.assertEqual(policy['allowRead'][2:], [
            '/bin', '/sbin', '/usr/bin', '/usr/sbin', '/usr/lib', '/usr/libexec',
            '/usr/share', '/System/Library', '/dev', '/Library/Developer/CommandLineTools',
            '/opt/homebrew/Cellar', '/opt/homebrew/opt', '/opt/homebrew/lib'])
        for broad in ('/Users', '/Volumes', '/private', '/tmp', '/var', '/System', '/usr'):
            self.assertNotIn(broad, policy['allowRead'])

    def test_command_audit_accepts_bash_but_rejects_other_tools(self):
        sys.path.insert(0, str(ROOT / 'bin'))
        from _claude_sandbox import TOOLS
        from _reader_tools import audit_claude
        events = [json.loads(line) for line in
                  (ROOT / 'tests/fixtures/claude-mimo-stream.jsonl').read_text().splitlines()]
        events[0]['tools'] = list(TOOLS)
        for event in events:
            for block in event.get('message', {}).get('content', []):
                if block.get('type') == 'tool_use':
                    block['name'] = 'Bash'
                    block['input'] = {'command': 'git status --short'}
        text = '\n'.join(json.dumps(event) for event in events)
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(audit_claude(text, Path(directory), TOOLS), ['Bash'])
            self.assertIsNone(audit_claude(text, Path(directory)))
            # Inventory is independent evidence: extra tools cannot be hidden
            # by a complete, otherwise-valid trace.
            events[0]['tools'].append('Write')
            self.assertIsNone(audit_claude('\n'.join(json.dumps(event) for event in events), Path(directory), TOOLS))

    def test_probe_executes_each_boundary_and_rejects_inconclusive_errors(self):
        import contextlib
        import errno
        import io
        import os
        import socket
        import urllib.error
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location('claude_sandbox', ROOT / 'bin/_claude_sandbox.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            inside, outside = Path(directory) / 'inside', Path(directory) / 'outside'
            inside.write_bytes(b'probe'); outside.write_bytes(b'probe')
            read, opening = Path.read_bytes, os.open
            scenarios = ('ready', 'read-outside', 'write-outside', 'credential-env',
                         'network-tcp', 'network-loopback', 'network-dns-packet',
                         'network-dns-lookup', 'network-proxy', 'tcp-timeout', 'wrong-permission-error')
            for scenario in scenarios:
                with self.subTest(scenario=scenario):
                    def denied():
                        raise PermissionError(errno.EPERM, 'fixture denial')
                    def read_file(path):
                        if path == outside and scenario != 'read-outside':
                            return denied()
                        return read(path)
                    def open_file(path, flags):
                        if Path(path) == outside and scenario != 'write-outside':
                            if scenario == 'wrong-permission-error':
                                raise PermissionError(errno.EACCES, 'not sandbox evidence')
                            return denied()
                        return opening(path, flags)
                    def connect(address):
                        label = 'network-tcp' if address[0] == '1.1.1.1' else 'network-loopback'
                        if scenario == 'tcp-timeout' and label == 'network-tcp':
                            raise TimeoutError('not sandbox evidence')
                        if scenario != label:
                            return denied()
                    def dns_packet(*args):
                        return 1 if scenario == 'network-dns-packet' else denied()
                    def lookup(*args):
                        if scenario == 'network-dns-lookup':
                            return [(socket.AF_INET, socket.SOCK_STREAM, 6, '', ('1.1.1.1', 443))]
                        raise socket.gaierror(socket.EAI_NONAME, 'fixture denial')
                    def proxy(*args, **kwargs):
                        if scenario == 'network-proxy':
                            return io.BytesIO(b'public fixture')
                        raise urllib.error.HTTPError('http://example.com/', 403, 'Forbidden',
                                                     {'X-Proxy-Error': 'blocked-by-allowlist'}, None)
                    output = io.StringIO()
                    with contextlib.ExitStack() as stack:
                        stack.enter_context(patch.dict(os.environ, {'HTTP_PROXY': 'http://localhost:32002'}, clear=True))
                        if scenario == 'credential-env':
                            os.environ[module.AUTH_ENV_VARS[0]] = 'harmless-probe'
                        stack.enter_context(patch.object(sys, 'argv', ['probe', str(inside), str(outside), '32001', module.PROXY_HOST, *module.AUTH_ENV_VARS]))
                        for name, replacement in [('pathlib.Path.read_bytes', read_file), ('os.open', open_file),
                            ('socket.socket.connect', connect), ('socket.socket.sendto', dns_packet),
                            ('socket.getaddrinfo', lookup), ('urllib.request.OpenerDirector.open', proxy)]:
                            stack.enter_context(patch(name, replacement) if name == 'pathlib.Path.read_bytes' else patch(name, side_effect=replacement))
                        stack.enter_context(contextlib.redirect_stdout(output))
                        exec(compile(module.PROBE, '<native-sandbox-probe>', 'exec'), {})
                    if scenario == 'ready':
                        self.assertEqual(output.getvalue(), 'AIWORK_NATIVE_SANDBOX_READY')
                    else:
                        label = {'tcp-timeout': 'network-tcp', 'wrong-permission-error': 'write-outside'}.get(scenario, scenario)
                        self.assertEqual(output.getvalue(), 'AIWORK_NATIVE_SANDBOX_FAILED:' + label)

    def test_native_preflight_fails_closed_before_model_dispatch(self):
        spec = importlib.util.spec_from_file_location('claude_sandbox', ROOT / 'bin/_claude_sandbox.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for scenario in ('ready', 'proxy-denial-report', 'diagnostic', 'different-version', 'sandbox-denied', 'missing-response', 'interrupted', 'ignored-policy', 'network-tcp', 'network-proxy', 'network-dns-lookup', 'network-dns-packet', 'network-loopback', 'credential-env', 'write-outside'):
                with self.subTest(scenario=scenario):
                    cli = root / 'claude'
                    # MCP shapes captured from the installed 2.1.301 CLI; no model
                    # request is available in this fixture.
                    cli.write_text('#!' + sys.executable + '\n' +
                        'import json,sys,os\nscenario=' + repr(scenario) + '\n' + """
assert not any(name.lower() in ('http_proxy','https_proxy','all_proxy','no_proxy') for name in os.environ)
for line in sys.stdin:
    request = json.loads(line)
    method = request['method']
    if method == 'notifications/initialized':
        continue
    if method == 'initialize':
        result = {'serverInfo': {'version': 'other' if scenario == 'different-version' else '2.1.301'}}
    elif method == 'tools/call':
        assert request['params']['name'] == 'Bash'
        if scenario == 'missing-response':
            break
        result = {'content': [{'type': 'text', 'text': json.dumps({
            'stdout': 'AIWORK_NATIVE_SANDBOX_READY', 'stderr': '', 'interrupted': False})}]}
        if scenario == 'proxy-denial-report':
            result['content'][0]['text'] = json.dumps({'stdout':'AIWORK_NATIVE_SANDBOX_READY','stderr':'<sandbox_violations>\\ndeny network-outbound example.com:80 (host is on the deny list)\\n</sandbox_violations>','interrupted':False})
        if scenario == 'diagnostic':
            result['content'][0]['text'] = json.dumps({'stdout':'AIWORK_NATIVE_SANDBOX_READY','stderr':'unexpected runtime error','interrupted':False})
        if scenario in ('network-tcp', 'network-proxy', 'network-dns-lookup', 'network-dns-packet', 'network-loopback', 'credential-env', 'write-outside'):
            command = request['params']['arguments']['command']
            if scenario in command:
                result['content'][0]['text'] = json.dumps({'stdout':'AIWORK_NATIVE_SANDBOX_FAILED:'+scenario,'stderr':'','interrupted':False})
        if scenario == 'ignored-policy':
            import subprocess
            output = subprocess.run(request['params']['arguments']['command'], shell=True, capture_output=True, text=True)
            result['content'][0]['text'] = json.dumps({'stdout': output.stdout, 'stderr': output.stderr, 'interrupted': False})
        if scenario == 'interrupted':
            result['content'][0]['text'] = json.dumps({'stdout':'AIWORK_NATIVE_SANDBOX_READY','stderr':'','interrupted':True})
        if scenario == 'sandbox-denied':
            result['isError'] = True
    else:
        raise SystemExit('unexpected model dispatch')
    print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': result}), flush=True)
""")
                    cli.chmod(0o755)
                    if scenario in ('ready', 'proxy-denial-report', 'diagnostic', 'different-version'):
                        module.preflight(str(cli), str(root / 'settings.json'), str(root))
                    else:
                        with self.assertRaises(ValueError):
                            module.preflight(str(cli), str(root / 'settings.json'), str(root))

if __name__ == '__main__':
    unittest.main()

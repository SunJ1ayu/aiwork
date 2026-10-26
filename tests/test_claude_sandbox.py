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
        settings = module.settings(Path('/Users/fixture'), Path('/settings'), Path('/runtime'), Path('/command-tmp'))
        sandbox = settings['sandbox']
        self.assertTrue(sandbox['enabled'])
        self.assertTrue(sandbox['failIfUnavailable'])
        self.assertFalse(sandbox['allowUnsandboxedCommands'])
        self.assertEqual(sandbox['excludedCommands'], [])
        self.assertEqual(sandbox['network']['allowedDomains'], [])
        self.assertFalse(sandbox['network']['allowLocalBinding'])
        self.assertFalse(sandbox['network']['allowAllUnixSockets'])
        self.assertTrue(settings['permissions']['blockReadsOutsideWorkingDirectories'])
        self.assertIn('/settings', sandbox['filesystem']['denyRead'])
        self.assertIn('/runtime', sandbox['filesystem']['denyRead'])
        self.assertEqual(sandbox['filesystem']['allowWrite'], ['/command-tmp'])
        for directory in ('.codex', '.claude', '.config/cursor', '.kimi-code', '.local/share/mimocode'):
            self.assertIn('/Users/fixture/' + directory, sandbox['filesystem']['denyRead'])
        protected = {item['name'] for item in sandbox['credentials']['envVars'] if item['mode'] == 'deny'}
        self.assertTrue({'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'DEEPSEEK_API_KEY', 'MIMO_API_KEY'} <= protected)
        self.assertEqual(module.TOOLS, ('Read', 'Glob', 'Grep', 'Bash'))

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

    def test_native_preflight_fails_closed_before_model_dispatch(self):
        spec = importlib.util.spec_from_file_location('claude_sandbox', ROOT / 'bin/_claude_sandbox.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for scenario in ('ready', 'wrong-version', 'sandbox-denied', 'missing-response'):
                with self.subTest(scenario=scenario):
                    cli = root / 'claude'
                    # MCP shapes captured from the installed 2.1.301 CLI; no model
                    # request is available in this fixture.
                    cli.write_text('#!' + sys.executable + '\n' +
                        'import json,sys\nscenario=' + repr(scenario) + '\n' + """
for line in sys.stdin:
    request = json.loads(line)
    method = request['method']
    if method == 'notifications/initialized':
        continue
    if method == 'initialize':
        result = {'serverInfo': {'version': 'other' if scenario == 'wrong-version' else '2.1.301'}}
    elif method == 'tools/call':
        assert request['params']['name'] == 'Bash'
        if scenario == 'missing-response':
            break
        result = {'content': [{'type': 'text', 'text': json.dumps({
            'stdout': 'AIWORK_NATIVE_SANDBOX_READY', 'stderr': '', 'interrupted': False})}]}
        if scenario == 'sandbox-denied':
            result['isError'] = True
    else:
        raise SystemExit('unexpected model dispatch')
    print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': result}), flush=True)
""")
                    cli.chmod(0o755)
                    if scenario == 'ready':
                        module.preflight(str(cli), str(root / 'settings.json'), str(root))
                    else:
                        with self.assertRaises(ValueError):
                            module.preflight(str(cli), str(root / 'settings.json'), str(root))

if __name__ == '__main__':
    unittest.main()

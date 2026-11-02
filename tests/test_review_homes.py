#!/usr/bin/env python3
"""Every bin/sub* must run offline and leave no runtime state in aiwork data."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import json
from pathlib import Path
import shutil
import signal
import subprocess
import time
import tomllib
import unittest

import test_leg_finish as finish

ROOT = Path(__file__).resolve().parents[1]

# Provider contracts reuse the existing finish fixtures. Discovery is independent
# of this routing table: a new adapter without a fixture is a failure.
STUBS = {'subcodex': 'codex', 'subcursor': 'cursor-agent',
         'subagent': 'claude', 'subdeepseek-agent': 'claude',
         'subkimi': 'kimi', 'submimo': 'claude'}
CAPTURE = '''
import json
from pathlib import Path
cli = Path(sys.argv[0]).name
record = {'workspace': os.environ['REVIEW_WORKSPACE_DIR'], 'cli': cli}
if cli == 'kimi':
    runtime = os.environ['KIMI_CODE_HOME']
elif cli == 'cursor-agent':
    runtime = os.environ['HOME']
elif cli == 'claude':
    runtime = os.environ['CLAUDE_CONFIG_DIR']
    record['session_persistence_disabled'] = '--no-session-persistence' in sys.argv[1:]
elif cli == 'codex':
    record['ephemeral'] = '--ephemeral' in sys.argv[1:]
    runtime = None
else:
    raise AssertionError('unknown CLI runtime contract: ' + cli)
record['runtime'] = runtime
if cli != 'codex':
    home = Path(runtime)
    record['mode'] = home.stat().st_mode & 0o777
    if Path(sys.argv[0]).name == 'kimi':
        cred = home / 'credentials'
        record['credentials_link'] = cred.is_symlink()
        record['credentials_target'] = str(cred.resolve())
        record['config'] = (home / 'config.toml').read_text()
        record['guard'] = (home / 'hooks/guard.mjs').read_text()
        record['seed_leftover'] = (home / 'hooks/leftover.mjs').exists()
    (home / 'sessions').mkdir(exist_ok=True)
    (home / 'sessions/fixture').write_text('runtime state')
capture = Path(os.environ['HOME_CAPTURE'])
temporary = capture.with_suffix('.tmp')
temporary.write_text(json.dumps(record))
temporary.replace(capture)
'''


class ReviewHomes(unittest.TestCase):
    def setUp(self):
        self.fixture = finish.LegFinish(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.d = self.fixture.root
        shutil.copytree(ROOT / 'bin', self.fixture.bin, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__'))
        self.seed = self.d / 'kimi-review-home'
        shutil.copytree(ROOT / 'kimi-review-home', self.seed)
        (self.seed / 'hooks/leftover.mjs').write_text('do not copy')
        (self.seed / 'credentials').mkdir()
        (self.seed / 'credentials/marker').write_text('do not copy')
        self.credentials = self.d / 'home/.kimi-code/credentials'
        self.credentials.mkdir(parents=True)
        (self.credentials / 'kimi-code.json').write_text('{}\n')
        self.data = self.d / 'data'
        self.data.mkdir()
        (self.data / 'existing-output').write_text('keep')
        self.env = self.fixture._env()
        for key in ('KIMI_REVIEW_HOME', 'CODEX_BIN',
                    'REVIEW_PRINT_HOME', 'CURSOR_API_KEY'):
            self.env.pop(key, None)
        self.env.update(AIWORK_DATA_DIR=str(self.data),
                        REVIEW_WORKSPACE_BASE=str(self.d / 'workspaces'),
                        HOME_CAPTURE=str(self.d / 'capture.json'))
        for cli in set(STUBS.values()):
            stub = self.fixture.bin / cli
            body = stub.read_text()
            self.assertIn('case = os.environ["FINISH_CASE"]', body)
            stub.write_text(body.replace('case = os.environ["FINISH_CASE"]',
                                         CAPTURE + '\ncase = os.environ["FINISH_CASE"]'))

    def run_leg(self, leg, case='pass', **extra):
        self.assertIn(leg, STUBS, f'{leg}: no offline CLI fixture; do not skip new legs')
        capture = Path(self.env['HOME_CAPTURE'])
        capture.unlink(missing_ok=True)
        prefix = ['deepseek', 'review'] if leg == 'subagent' else ['review']
        return subprocess.run([str(self.fixture.bin / leg), *prefix,
                               str(self.d / 'task.md'), str(self.d / 'review.log'),
                               str(self.fixture.repo)],
                              env=dict(self.env, FINISH_CASE=case, **extra),
                              capture_output=True, text=True, timeout=40)

    def assert_clean(self):
        self.assertEqual(sorted(p.relative_to(self.data).as_posix()
                                for p in self.data.rglob('*')), ['existing-output'])
        self.assertEqual((self.data / 'existing-output').read_text(), 'keep')
        self.assertEqual(list((self.d / 'workspaces').iterdir()), [])

    def test_claude_uses_disposable_config_instead_of_caller_state(self):
        caller = self.d / 'caller-claude'
        caller.mkdir()
        (caller / 'keep').write_text('caller state')
        for leg in ('subagent', 'subdeepseek-agent'):
            with self.subTest(leg=leg):
                result = self.run_leg(leg, CLAUDE_CONFIG_DIR=str(caller))
                self.assertEqual(result.returncode, 0, result.stderr)
                record = json.loads(Path(self.env['HOME_CAPTURE']).read_text())
                self.assertEqual(Path(record['runtime']).parent, Path(record['workspace']))
                self.assertTrue(record['session_persistence_disabled'])
                self.assertEqual(list(caller.iterdir()), [caller / 'keep'])
                self.assertEqual((caller / 'keep').read_text(), 'caller state')
                self.assert_clean()

    def test_unknown_cli_runtime_contract_is_rejected(self):
        self.fixture._write('unknown-cli', '#!/usr/bin/env python3\nimport os, sys\n' + CAPTURE)
        result = subprocess.run([str(self.fixture.bin / 'unknown-cli')],
                                env=dict(self.env, REVIEW_WORKSPACE_DIR=str(self.d)),
                                capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unknown CLI', result.stderr)
        self.assertFalse(Path(self.env['HOME_CAPTURE']).exists())

    def test_claude_signal_exit_cleans_runtime(self):
        stub = self.fixture.bin / 'claude'
        stub.write_text(stub.read_text().replace('case = os.environ["FINISH_CASE"]',
                                               'time.sleep(1)\ncase = os.environ["FINISH_CASE"]'))
        capture = Path(self.env['HOME_CAPTURE'])
        for sig in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=sig):
                capture.unlink(missing_ok=True)
                process = subprocess.Popen(
                    [str(self.fixture.bin / 'subdeepseek-agent'), 'review',
                     str(self.d / 'task.md'), str(self.d / 'signal.log'), str(self.fixture.repo)],
                    env=dict(self.env, FINISH_CASE='pass', DEEPSEEK_TIMEOUT='10'),
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    start_new_session=True)
                try:
                    deadline = time.monotonic() + 10
                    while not capture.exists() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue(capture.exists(), 'Claude stub never started')
                    record = json.loads(capture.read_text())
                    process.send_signal(sig)
                    _stdout, stderr = process.communicate(timeout=10)
                    self.assertEqual(process.returncode, 128 + sig, stderr)
                    self.assertFalse(Path(record['runtime']).exists())
                    self.assert_clean()
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.communicate()

    def test_every_discovered_leg_cleans_success_failure_and_timeout(self):
        legs = sorted(p.name for p in (ROOT / 'bin').glob('sub*') if p.is_file())
        self.assertTrue(legs)
        for leg in legs:
            for case, rc in [('pass', 0), ('review_nonzero', 1), ('review_timeout', 124)]:
                with self.subTest(leg=leg, case=case):
                    result = self.run_leg(leg, case)
                    capture = Path(self.env['HOME_CAPTURE'])
                    with self.subTest(actual_rc=result.returncode, cli_started=capture.exists(),
                                      diagnostic=result.stderr[-800:]):
                        self.assertTrue(capture.exists(), f'{leg}: CLI stub never ran: {result.stderr}')
                        self.assertEqual(result.returncode, rc, result.stderr)
                        record = json.loads(capture.read_text())
                        workspace = Path(record['workspace'])
                        self.assertFalse(workspace.exists())
                        if record['cli'] == 'codex':
                            self.assertTrue(record['ephemeral'])
                            self.assertIsNone(record['runtime'])
                        else:
                            self.assertEqual(Path(record['runtime']).parent, workspace)
                            self.assertEqual(record['mode'], 0o700)
                        self.assert_clean()

    def test_kimi_renders_only_seed_and_links_cli_credentials_each_run(self):
        homes = []
        for _ in range(2):
            result = self.run_leg('subkimi')
            self.assertEqual(result.returncode, 0, result.stderr)
            record = json.loads(Path(self.env['HOME_CAPTURE']).read_text())
            self.assertTrue(record['credentials_link'])
            self.assertEqual(record['credentials_target'], str(self.credentials))
            self.assertIn(record['runtime'] + '/hooks/guard.mjs', record['config'])
            self.assertEqual(record['guard'], (self.seed / 'hooks/guard.mjs').read_text())
            self.assertFalse(record['seed_leftover'])
            homes.append(record['runtime'])
            self.assert_clean()
        self.assertNotEqual(*homes)
        self.assertEqual((self.credentials / 'kimi-code.json').read_text(), '{}\n')
        self.assertEqual((self.seed / 'credentials/marker').read_text(), 'do not copy')

    def kimi_settings(self, **changes):
        from _test_settings import set_model
        values = dict(kimi='kimi-code/model-a', kimi_max_context_size='131072',
                      kimi_capabilities='thinking,image_in,tool_use',
                      kimi_support_efforts='low,high', kimi_default_effort='high',
                      kimi_thinking='true')
        values.update(changes)
        path = self.fixture.root / 'settings/models.env'
        for key, value in values.items():
            if value is None:
                path.write_text(''.join(line + '\n' for line in path.read_text().splitlines()
                                        if not line.startswith(key + '=')))
            else:
                set_model(path.parent, key, value)
        return path

    def test_kimi_local_model_and_parameters_change_generated_config(self):
        for model, context, caps, efforts, effort, thinking in (
                ('model-a', 131072, ['thinking', 'image_in', 'tool_use'], ['low', 'high'], 'high', True),
                ('model-b', 262144, ['thinking', 'tool_use'], ['medium', 'high'], 'medium', False)):
            with self.subTest(model=model):
                alias = 'kimi-code/' + model
                self.kimi_settings(kimi=alias, kimi_max_context_size=str(context),
                                   kimi_capabilities=','.join(caps), kimi_support_efforts=','.join(efforts),
                                   kimi_default_effort=effort, kimi_thinking=str(thinking).lower())
                result = self.run_leg('subkimi')
                self.assertEqual(result.returncode, 0, result.stderr)
                record = json.loads(Path(self.env['HOME_CAPTURE']).read_text())
                config = tomllib.loads(record['config'])
                self.assertEqual(config['default_model'], alias)
                self.assertEqual(config['models'][alias], dict(
                    provider='managed:kimi-code', model=model, max_context_size=context,
                    capabilities=caps, support_efforts=efforts, default_effort=effort))
                self.assertEqual(config['thinking']['enabled'], thinking)
                self.assert_clean()

    def test_kimi_missing_parameters_refuse_before_cli_even_with_override_home(self):
        keys = ('kimi_max_context_size', 'kimi_capabilities', 'kimi_support_efforts',
                'kimi_default_effort', 'kimi_thinking')
        for key in keys:
            for override in ({}, {'KIMI_REVIEW_HOME': str(self.d / 'kimi-home')}):
                with self.subTest(key=key, override=bool(override)):
                    path = self.kimi_settings(**{key: None})
                    result = self.run_leg('subkimi', **override)
                    self.assertEqual(result.returncode, 78, result.stderr)
                    self.assertIn(key, result.stderr)
                    self.assertIn(str(path), result.stderr)
                    self.assertFalse(Path(self.env['HOME_CAPTURE']).exists())

    def test_kimi_invalid_parameters_refuse_before_cli(self):
        cases = [('kimi_max_context_size', value) for value in
                 ('banana', '0', '-1', '1.5', '01', '9007199254740992', '9' * 5000)]
        cases += [('kimi_capabilities', value) for value in
                  ('thinkng,tool_use', 'thinking,,tool_use', 'thinking,thinking', 'image_in')]
        cases += [('kimi_support_efforts', 'extreme'), ('kimi_support_efforts', 'low,low'),
                  ('kimi_default_effort', 'max'), ('kimi_thinking', 'yes'),
                  ('kimi_capabilites', 'thinking,tool_use')]
        for key, value in cases:
            with self.subTest(key=key, value=value[:40]):
                path = self.kimi_settings(**{key: value})
                result = self.run_leg('subkimi')
                self.assertEqual(result.returncode, 78, result.stderr)
                self.assertIn(key, result.stderr)
                self.assertIn(str(path), result.stderr)
                self.assertNotIn('Traceback', result.stderr)
                self.assertFalse(Path(self.env['HOME_CAPTURE']).exists())

    def test_missing_kimi_credentials_refuses_before_model_and_cleans(self):
        (self.credentials / 'kimi-code.json').unlink()
        result = self.run_leg('subkimi')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('先用 kimi 登录', result.stderr)
        self.assertFalse(Path(self.env['HOME_CAPTURE']).exists())
        self.assert_clean()

    def test_override_homes_keep_caller_files_and_are_guarded(self):
        for leg, variable, directory in [('subkimi', 'KIMI_REVIEW_HOME', 'kimi-home')]:
            with self.subTest(leg=leg):
                home = self.d / directory
                marker = home / 'caller-file'
                marker.write_text('keep')
                config = home / 'config.toml'
                config.parent.mkdir(exist_ok=True)
                before = config.read_bytes()
                result = self.run_leg(leg, **{variable: str(home)})
                self.assertEqual(result.returncode, 0, result.stderr)
                record = json.loads(Path(self.env['HOME_CAPTURE']).read_text())
                self.assertEqual(record['runtime'], str(home))
                self.assertEqual(marker.read_text(), 'keep')
                self.assertEqual(config.read_bytes(), before)
                self.assertTrue((home / 'sessions/fixture').exists())
                self.assert_clean()
                inside = self.fixture.repo / directory
                shutil.copytree(home, inside)
                result = self.run_leg(leg, **{variable: str(inside)})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('仓内', result.stderr)
                self.assertFalse(Path(self.env['HOME_CAPTURE']).exists())
                self.assert_clean()


if __name__ == '__main__':
    unittest.main()

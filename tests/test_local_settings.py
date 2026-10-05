#!/usr/bin/env python3
"""Local settings through real entry points, with disposable config and providers."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bin'))


def load_script(name):
    loader = importlib.machinery.SourceFileLoader('settings_' + name.replace('-', '_'), str(ROOT / 'bin' / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class SettingsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.d = Path(self.temp.name)
        self.config = self.d / 'settings'
        self.config.mkdir()
        self.models = {'codex': 'gpt-fixture', 'cursor': 'composer-2.5',
                       'deepseek': 'deepseek-fixture', 'gemini': 'gemini-fixture',
                       'glm': 'glm-fixture', 'grok': 'grok-4.6',
                       'kimi': 'kimi-code/k3', 'mimo': 'xiaomi/mimo-v2.5-pro',
                       'triage': 'jev-fixture'}
        self.write_models()
        self.env = dict(os.environ, AIWORK_CONFIG_DIR=str(self.config), HOME=str(self.d / 'home'))
        self.environment = patch.dict(os.environ, self.env, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def write_models(self):
        (self.config / 'models.env').write_text(''.join(f'{k}={v}\n' for k, v in self.models.items()))

    def invoke_config(self, *args):
        return subprocess.run([sys.executable, str(ROOT / 'bin/aiwork-config'), *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_each_leg_is_read_from_models_env(self):
        for leg, expected in self.models.items():
            with self.subTest(leg=leg):
                result = self.invoke_config('model', leg)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_chat_engine_requires_its_selected_leg_only(self):
        self.models.pop('mimo')
        self.write_models()
        engine = load_script('submimo-review')
        for leg in ('deepseek', 'glm'):
            with self.subTest(leg=leg), patch.dict(os.environ,
                    AIWORK_MODEL_LEG=leg, MIMO_MODEL=self.models[leg]):
                self.assertEqual(engine.selected_model(), self.models[leg])

    def test_missing_file_and_each_missing_leg_name_the_path_and_leg(self):
        path = self.config / 'models.env'
        path.unlink()
        for leg in self.models:
            with self.subTest(file='absent', leg=leg):
                result = self.invoke_config('model', leg)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(str(path), result.stderr)
                self.assertIn(leg, result.stderr)
        for leg in list(self.models):
            saved = self.models.pop(leg)
            self.write_models()
            with self.subTest(file='missing-row', leg=leg):
                result = self.invoke_config('model', leg)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(str(path), result.stderr)
                self.assertIn(leg, result.stderr)
                self.assertEqual(result.stdout, '')
            self.models[leg] = saved
        self.write_models()

    def test_env_is_data_and_duplicate_leg_is_refused(self):
        sentinel = self.d / 'executed'
        (self.config / 'models.env').write_text(f'codex=$(touch {sentinel})\ncodex=gpt-fixture\n')
        result = self.invoke_config('model', 'codex')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(sentinel.exists())

    def repo_fixture(self):
        repo = self.d / 'repo'
        repo.mkdir()
        (repo / 'oracle.txt').write_text('oracle sentinel\n')
        for args in [('init', '-q', '-b', 'main'), ('config', 'user.name', 'test'),
                     ('config', 'user.email', 'test@example.invalid'), ('add', '.'),
                     ('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture')]:
            subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True)
        task = self.d / 'task.md'
        task.write_text('Inspect the sentinel; no network work.\n')
        return repo, task

    def test_missing_settings_stop_every_adapter_before_provider_invocation(self):
        repo, task = self.repo_fixture()
        fake = self.d / 'fake'
        fake.mkdir()
        marker = self.d / 'provider-called'
        for name in ('codex', 'cursor-agent', 'grok', 'kimi', 'mimo', 'agy', 'claude', 'opencode'):
            script = fake / name
            script.write_text('#!/bin/sh\ntouch "$PROVIDER_MARKER"\nexit 1\n')
            script.chmod(0o755)
        callers = {'codex': 'subcodex', 'cursor': 'subcursor', 'grok': 'subgrok',
                   'kimi': 'subkimi', 'mimo': 'submimo', 'gemini': 'subgemini',
                   'deepseek': 'subdeepseek-agent', 'glm': 'subglm-agent'}
        env = dict(self.env, PATH=str(fake) + os.pathsep + self.env['PATH'],
                   REVIEW_NO_MY_REVIEW='1', PROVIDER_MARKER=str(marker))
        for leg, caller in callers.items():
            for missing_file in (True, False):
                path = self.config / 'models.env'
                if missing_file:
                    path.unlink()
                else:
                    path.write_text(''.join(f'{k}={v}\n' for k, v in self.models.items() if k != leg))
                result = subprocess.run([str(ROOT / 'bin' / caller), 'review', str(task),
                                         str(self.d / (caller + '.log')), str(repo)],
                                        env=env, capture_output=True, text=True, timeout=10)
                with self.subTest(caller=caller, missing_file=missing_file):
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(str(path), result.stderr)
                    self.assertIn(leg, result.stderr)
                    self.assertFalse(marker.exists())
                self.write_models()

    def test_symlinked_settings_callers_report_the_real_missing_settings(self):
        repo, task = self.repo_fixture()
        installed = self.d / 'installed'
        installed.mkdir()
        callers = {'subcodex': [], 'subcursor': [], 'subgrok': [], 'subkimi': [],
                   'submimo': [], 'subgemini': [], 'subagent': ['deepseek'],
                   'subchat': ['deepseek']}
        # Derive coverage from the shell callers so another migrated leg cannot be missed.
        actual = {p.name for p in (ROOT / 'bin').iterdir()
                  if p.is_file() and p.read_bytes().startswith(b'#!/usr/bin/env bash')
                  and re.search(r'/aiwork-config" model ', p.read_text())}
        self.assertEqual(actual, set(callers) | {'delegate-codex', '_panel-roster-lib.sh'})
        (self.config / 'models.env').unlink()
        for name, prefix in callers.items():
            link = installed / name
            link.symlink_to(ROOT / 'bin' / name)
            result = subprocess.run([str(link), *prefix, 'review', str(task),
                                     str(self.d / (name + '.log')), str(repo)],
                                    env=dict(self.env, REVIEW_NO_MY_REVIEW='1'),
                                    capture_output=True, text=True, timeout=10)
            with self.subTest(caller=name):
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(str(self.config / 'models.env'), result.stderr)
                self.assertNotIn('No such file or directory', result.stderr)

    def test_codex_and_delegate_dry_runs_read_local_settings_and_keep_overrides(self):
        repo, task = self.repo_fixture()
        env = dict(self.env, REVIEW_NO_MY_REVIEW='1')
        attack = self.d / 'attack.md'
        hashed = subprocess.run([str(ROOT / 'bin/delegate-codex'), '--print-oracle-hash',
                                 '--repo', str(repo), '--protect', 'oracle.txt'],
                                env=env, capture_output=True, text=True)
        self.assertEqual(hashed.returncode, 0, hashed.stderr)
        attack.write_text('Dry-run checks local model selection and preserves overrides.\n' + hashed.stdout)
        delegate = [str(ROOT / 'bin/delegate-codex'), '--dry-run', '--no-isolate',
                    '--task', str(task), '--repo', str(repo), '--protect', 'oracle.txt',
                    '--attack-log', str(attack), '--log', str(self.d / 'delegate.log')]
        codex = [str(ROOT / 'bin/subcodex'), '--dry-run', 'review', str(task),
                 str(self.d / 'codex.log'), str(repo)]
        for selected in ('gpt-fixture', 'gpt-fixture-next'):
            self.models['codex'] = selected
            self.write_models()
            for command in (delegate, codex):
                result = subprocess.run(command, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('model=' + selected, result.stdout)
        result = subprocess.run(delegate + ['--model', 'gpt-override'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('model=gpt-override', result.stdout)
        result = subprocess.run(codex, env=dict(env, SUBCODEX_MODEL='gpt-override'), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('model=gpt-override', result.stdout)

        for command in (delegate, codex):
            link = self.d / Path(command[0]).name
            link.symlink_to(command[0])
            result = subprocess.run([str(link), *command[1:]], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('model=gpt-fixture-next', result.stdout)

    def test_app_keys_keep_absolute_paths_and_resolve_relative_paths_under_apps(self):
        for override in (None, str(self.d / 'other-apps')):
            if override:
                self.env['AIWORK_APPS_DIR'] = override
            else:
                self.env.pop('AIWORK_APPS_DIR', None)
            apps = Path(override) if override else self.config / 'apps'
            cases = {'aiwork-sync.pem': apps / 'aiwork-sync.pem',
                     'keys/aiwork-sync.pem': apps / 'keys/aiwork-sync.pem',
                     '/etc/aiwork/apps/aiwork-sync.pem': Path('/etc/aiwork/apps/aiwork-sync.pem'),
                     str(self.d / 'external/key.pem'): self.d / 'external/key.pem'}
            for configured, expected in cases.items():
                with self.subTest(override=override, configured=configured):
                    result = self.invoke_config('app-key', configured)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), str(expected))

    def test_untracked_judging_files_still_fail_the_original_assertions(self):
        source = (ROOT / 'tests/test-review-tooling.sh').read_text()
        fake = self.d / 'fake-git'
        fake.mkdir()
        git = fake / 'git'
        git.write_text('#!/bin/sh\ncase "$*" in\n'
                       '  *ls-files*) exit "$TRACKED_RC" ;;\n'
                       '  *check-ignore*) exit 0 ;;\n'
                       '  *) exit 99 ;;\nesac\n')
        git.chmod(0o755)
        for name in ('hooks/guard.mjs', 'config.toml'):
            command = re.search(r'^.*git .*' + re.escape('kimi-review-home/' + name)
                                + r'.*\n.*check .*', source, re.M)
            if command is None:
                command = re.search(r'^.*git .*\\\n.*' + re.escape('kimi-review-home/' + name)
                                    + r'.*\n.*check .*', source, re.M)
            self.assertIsNotNone(command, name)
            script = 'check() { exit "$2"; }; tool_root="$1"; BIN="$1/bin";\n' + command.group()
            for tracked_rc in ('0', '1'):
                result = subprocess.run(['bash', '-c', script, 'judging-test', str(ROOT)],
                                        env=dict(self.env, TRACKED_RC=tracked_rc,
                                                 PATH=str(fake) + os.pathsep + self.env['PATH']),
                                        capture_output=True, text=True)
                with self.subTest(file=name, tracked_rc=tracked_rc):
                    self.assertEqual(result.returncode, int(tracked_rc), result.stderr)

    def test_panel_settings_failure_names_the_initialization_failure(self):
        for missing_file in (True, False):
            if missing_file:
                (self.config / 'models.env').unlink()
            else:
                self.models.pop('cursor')
                self.write_models()
            for caller in ('panel-review', 'panel-slice'):
                result = subprocess.run([str(ROOT / 'bin' / caller), '--help'],
                                        env=dict(self.env, PANEL_CURSOR_LEG='off'),
                                        capture_output=True, text=True, timeout=10)
                with self.subTest(caller=caller, missing_file=missing_file):
                    self.assertEqual(result.returncode, 70)
                    self.assertIn(str(self.config / 'models.env'), result.stderr)
                    self.assertIn('cursor', result.stderr)
                    self.assertIn('加载失败', result.stderr)
                    self.assertNotIn('找不到', result.stderr)
            self.models['cursor'] = 'composer-2.5'
            self.write_models()

    def cursor_fixture(self):
        import test_subcursor
        fixture = test_subcursor.CursorTest('runTest')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.env['AIWORK_CONFIG_DIR'] = str(self.config)
        for name in ('aiwork-config', '_aiwork_config.py'):
            source = ROOT / 'bin' / name
            if source.exists():
                shutil.copy2(source, fixture.bin / name)
        return fixture

    def test_one_local_row_changes_actual_cursor_model_without_repository_edits(self):
        fixture = self.cursor_fixture()
        before = subprocess.check_output(['git', 'diff', '--binary'], cwd=ROOT)
        for model, mode in [('composer-2.5', 'review'), ('composer-2.6', 'explore')]:
            self.models['cursor'] = model
            self.write_models()
            result = fixture.run_leg(mode=mode, tag=mode)
            self.assertEqual(result.returncode, 0, result.stderr)
            record = json.loads((fixture.d / (mode + '.record.json')).read_text())
            self.assertEqual(record['model'], model)
        self.assertEqual(subprocess.check_output(['git', 'diff', '--binary'], cwd=ROOT), before)

    def test_cursor_override_is_preserved(self):
        fixture = self.cursor_fixture()
        result = fixture.run_leg(extra={'CURSOR_MODEL': 'composer-2.6'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((fixture.d / 'leg.record.json').read_text())['model'], 'composer-2.6')

    def test_missing_cursor_settings_never_start_provider(self):
        for absent_file in (True, False):
            fixture = self.cursor_fixture()
            if absent_file:
                (self.config / 'models.env').unlink()
            else:
                self.models.pop('cursor')
                self.write_models()
            result = fixture.run_leg()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(str(self.config / 'models.env'), result.stderr)
            self.assertIn('cursor', result.stderr)
            self.assertFalse((fixture.d / 'leg.record.json').exists())
            self.models['cursor'] = 'composer-2.5'
            self.write_models()

    def test_review_pr_freezes_local_cursor_model_and_honors_override(self):
        review = load_script('review-pr')
        self.models['cursor'] = 'gpt-5.6'
        self.write_models()
        with patch.dict(os.environ, CURSOR_MODEL=''):
            self.assertEqual(review.choose_leg('subcursor'), ('openai', 'gpt-5.6'))
        with patch.dict(os.environ, CURSOR_MODEL='composer-2.5'):
            self.assertEqual(review.choose_leg('subcursor'), ('cursor', 'composer-2.5'))

    def test_triage_model_and_key_come_from_disposable_settings(self):
        triage = load_script('triage')
        # Fail before load_key if an old implementation ignores the test directory.
        self.assertEqual(triage.ENV_FILE, self.config / 'typesafe.env')
        (self.config / 'typesafe.env').write_text('export TYPESAFE_API_KEY="test-only-key"\n')
        with patch.object(triage, 'ask', return_value={'model': 'jev-fixture', 'answers': {}}) as ask, \
             patch('sys.argv', ['triage', '-', '--json']), patch('sys.stdin', io.StringIO('a bounded change')), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(triage.main(), 0)
        self.assertEqual(ask.call_args.args[0:2], ('test-only-key', 'jev-fixture'))

    def test_token_helper_defaults_to_config_apps_and_preserves_apps_override(self):
        import test_app_token_scope
        fixture = test_app_token_scope.AppTokenScopeTest('runTest')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        shutil.copytree(fixture.root / 'apps', self.config / 'apps')
        fixture.env['AIWORK_CONFIG_DIR'] = str(self.config)
        fixture.env.pop('AIWORK_APPS_DIR')
        result = fixture.invoke(['--repo', 'SunJ1ayu/aiwork'], ['SunJ1ayu/aiwork'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'fake-test-token')
        fixture.env['AIWORK_CONFIG_DIR'] = str(self.d / 'absent')
        fixture.env['AIWORK_APPS_DIR'] = str(fixture.root / 'apps')
        result = fixture.invoke(['--repo', 'SunJ1ayu/aiwork'], ['SunJ1ayu/aiwork'])
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()

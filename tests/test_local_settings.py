#!/usr/bin/env python3
"""Local settings through real entry points, with disposable config and providers."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401
from _test_settings import write_programs

import importlib.machinery
import importlib.util
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
        write_programs(self.config)
        self.models = {'codex': 'gpt-fixture', 'cursor': 'composer-2.5',
                       'deepseek': 'deepseek-fixture',
                       'kimi': 'kimi-code/k3', 'mimo': 'mimo-v2.5-pro'}
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

    def test_public_test_startup_clears_inherited_review_context(self):
        inherited = {'AIWORK_REVIEW_PR': '1', 'AIWORK_REVIEW_FUTURE': 'fixture',
                     'PANEL_DIFF_BASE': 'fixture'}
        control = {'TEST_REVIEW_WORKSPACE_CASE': 'write-boundary'}
        keys = [*inherited, *control, 'AIWORK_CONFIG_DIR', 'AIWORK_DATA_DIR']
        output = f'print(json.dumps({{k: os.environ[k] for k in {keys!r} if k in os.environ}}))'
        probe = self.d / 'startup.py'
        probe.write_text(f'import sys\nsys.path.insert(0, {str(ROOT / "tests")!r})\n'
                         'import _no_egress\nimport json, os\n'
                         + output + '\n')
        shell = self.d / 'startup.sh'
        shell.write_text(f'. {ROOT / "tests/_no-egress.sh"}\n'
                         f'exec {sys.executable} -c "import json, os; {output}"\n')
        for command in ([sys.executable, str(probe)], ['bash', str(shell)]):
            with self.subTest(command=command[0]):
                result = subprocess.run(command, env=dict(self.env, **inherited, **control),
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                environment = json.loads(result.stdout)
                for key in inherited:
                    self.assertNotIn(key, environment)
                for key, value in control.items():
                    self.assertEqual(environment[key], value)
                self.assertEqual(environment['AIWORK_CONFIG_DIR'], str(self.config))
                self.assertEqual(environment['AIWORK_DATA_DIR'], self.env['AIWORK_DATA_DIR'])

    def test_each_leg_is_read_from_models_env(self):
        for leg, expected in self.models.items():
            with self.subTest(leg=leg):
                result = self.invoke_config('model', leg)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

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
        (repo / 'sentinel.txt').write_text('sentinel\n')
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
        for name in ('codex', 'cursor-agent', 'kimi', 'claude'):
            script = fake / name
            script.write_text('#!/bin/sh\ntouch "$PROVIDER_MARKER"\nexit 1\n')
            script.chmod(0o755)
        callers = {'codex': 'subcodex', 'cursor': 'subcursor',
                   'kimi': 'subkimi', 'mimo': 'submimo',
                   'deepseek': 'subdeepseek-agent'}
        env = dict(self.env, PATH=str(fake) + os.pathsep + self.env['PATH'],
                   PROVIDER_MARKER=str(marker))
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
        callers = {'subcodex': [], 'subcursor': [], 'subkimi': [],
                   'submimo': [], 'subdeepseek-agent': [], 'subagent': ['deepseek']}
        # Derive coverage from the shell callers so another migrated leg cannot be missed.
        sources = {p.name: p.read_text() for p in (ROOT / 'bin').iterdir()
                   if p.is_file() and p.read_bytes().startswith(b'#!/usr/bin/env bash')}
        direct = {name for name, source in sources.items()
                  if re.search(r'/aiwork-config" model ', source)}
        shim = re.compile(r'^exec.*?/(?:' + '|'.join(map(re.escape, direct)) + r')"\s', re.M)
        actual = direct | {name for name, source in sources.items() if shim.search(source)}
        self.assertEqual(actual, set(callers))
        (self.config / 'models.env').unlink()
        for name, prefix in callers.items():
            link = installed / name
            link.symlink_to(ROOT / 'bin' / name)
            result = subprocess.run([str(link), *prefix, 'review', str(task),
                                     str(self.d / (name + '.log')), str(repo)],
                                    env=dict(self.env),
                                    capture_output=True, text=True, timeout=10)
            with self.subTest(caller=name):
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(str(self.config / 'models.env'), result.stderr)
                self.assertNotIn('No such file or directory', result.stderr)

    def test_codex_dry_run_reads_local_settings_and_keeps_overrides(self):
        repo, task = self.repo_fixture()
        env = dict(self.env)
        codex = [str(ROOT / 'bin/subcodex'), '--dry-run', 'review', str(task),
                 str(self.d / 'codex.log'), str(repo)]
        for selected in ('gpt-fixture', 'gpt-fixture-next'):
            self.models['codex'] = selected
            self.write_models()
            result = subprocess.run(codex, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('model=' + selected, result.stdout)
        result = subprocess.run(codex, env=dict(env, SUBCODEX_MODEL='gpt-override'), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('model=gpt-override', result.stdout)

        link = self.d / 'subcodex'
        link.symlink_to(codex[0])
        result = subprocess.run([str(link), *codex[1:]], env=env, capture_output=True, text=True)
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

    def cursor_fixture(self):
        import test_subcursor
        fixture = test_subcursor.CursorTest('runTest')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.env['AIWORK_CONFIG_DIR'] = str(self.config)
        fixture.config = self.config
        write_programs(fixture.config, fixture.fake)
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
        session = sys.modules['_leg_session']
        with patch.dict(os.environ, CURSOR_MODEL=''):
            self.assertEqual(session.choose_leg('subcursor', review.BIN), ('openai', 'gpt-5.6'))
        with patch.dict(os.environ, CURSOR_MODEL='composer-2.5'):
            self.assertEqual(session.choose_leg('subcursor', review.BIN), ('cursor', 'composer-2.5'))

    def test_setting_value_reads_plain_export_and_quoted_assignments(self):
        from _aiwork_config import setting_value
        secret = 'fixture-setting-value'
        shapes = (
            f'DEEPSEEK_API_KEY={secret}\n',
            f'export DEEPSEEK_API_KEY={secret}\n',
            f'export DEEPSEEK_API_KEY="{secret}"\n',
            f"export DEEPSEEK_API_KEY='{secret}'\n",
        )
        variables = ('DEEPSEEK_API_KEY', 'DEEPSEEK_API_KEY', 'DEEPSEEK_API_KEY', 'DEEPSEEK_API_KEY')
        filenames = ('deepseek.env', 'deepseek.env', 'deepseek.env', 'deepseek.env')
        for filename, variable, text in zip(filenames, variables, shapes):
            with self.subTest(text=text):
                (self.config / filename).write_text(text)
                self.assertEqual(setting_value(filename, variable), secret)
                result = self.invoke_config('value', filename, variable)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, secret + '\n')
                self.assertNotIn(secret, result.stderr)

    def test_setting_value_does_not_source_the_file(self):
        from _aiwork_config import ConfigError, setting_value
        sentinel = self.d / 'sourced'
        path = self.config / 'deepseek.env'
        path.write_text(f'DEEPSEEK_API_KEY=$(touch {sentinel})\n')
        with self.assertRaises(ConfigError) as caught:
            setting_value('deepseek.env', 'DEEPSEEK_API_KEY')
        self.assertIn(f'{path}:1', str(caught.exception))
        self.assertNotIn(str(sentinel), str(caught.exception))
        self.assertFalse(sentinel.exists())

    def test_setting_value_errors_name_the_file_and_variable_without_the_value(self):
        from _aiwork_config import ConfigError, setting_value
        secret = 'fixture-do-not-leak'
        path = self.config / 'deepseek.env'
        cases = {
            'missing-file': None,
            'missing-line': f'OTHER={secret}\n',
            'empty': f'export DEEPSEEK_API_KEY=\nOTHER={secret}\n',
            'empty-quotes': f"DEEPSEEK_API_KEY=''\nOTHER={secret}\n",
        }
        for name, text in cases.items():
            with self.subTest(case=name):
                if path.exists():
                    path.unlink()
                if text is not None:
                    path.write_text(text)
                with self.assertRaises(ConfigError) as caught:
                    setting_value('deepseek.env', 'DEEPSEEK_API_KEY')
                message = str(caught.exception)
                self.assertIn(str(path), message)
                self.assertIn('DEEPSEEK_API_KEY', message)
                self.assertNotIn(secret, message)
                result = self.invoke_config('value', 'deepseek.env', 'DEEPSEEK_API_KEY')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
                self.assertIn(str(path), result.stderr)
                self.assertIn('DEEPSEEK_API_KEY', result.stderr)
                self.assertNotIn(secret, result.stderr)

    def test_inexact_setting_lines_name_the_path_and_line_without_the_value(self):
        from _aiwork_config import ConfigError, model, setting_value
        secret = 'fixture-exact-secret'
        path = self.config / 'deepseek.env'
        cases = {
            'trailing-comment': (f'export DEEPSEEK_API_KEY="{secret}" # note\n', 1),
            'whitespace': (f'DEEPSEEK_API_KEY={secret} tail\n', 1),
            'duplicate': (f'DEEPSEEK_API_KEY={secret}\nDEEPSEEK_API_KEY=other-exact\n', 2),
            'empty': ('DEEPSEEK_API_KEY=\n', 1),
            'empty-then-value': (f'DEEPSEEK_API_KEY=\nDEEPSEEK_API_KEY={secret}\n', 1),
        }
        for name, (text, line) in cases.items():
            with self.subTest(case=name):
                path.write_text(text)
                with self.assertRaises(ConfigError) as caught:
                    setting_value('deepseek.env', 'DEEPSEEK_API_KEY')
                message = str(caught.exception)
                self.assertIn(f'{path}:{line}', message)
                self.assertNotIn(secret, message)
                self.assertNotIn('other-exact', message)
                result = self.invoke_config('value', 'deepseek.env', 'DEEPSEEK_API_KEY')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
                self.assertIn(f'{path}:{line}', result.stderr)
                self.assertNotIn(secret, result.stderr)
        models = self.config / 'models.env'
        models.write_text(f'codex="{secret}" # note\n')
        with self.assertRaises(ConfigError) as caught:
            model('codex')
        self.assertIn(f'{models}:1', str(caught.exception))
        self.assertNotIn(secret, str(caught.exception))

    def test_setting_file_that_is_not_utf8_names_the_path_and_line(self):
        from _aiwork_config import ConfigError, setting_value
        secret = 'fixture-exact-secret'
        path = self.config / 'deepseek.env'
        path.write_bytes(f'DEEPSEEK_API_KEY={secret}\n'.encode('utf-8') + bytes((0xff,)))
        with self.assertRaises(ConfigError) as caught:
            setting_value('deepseek.env', 'DEEPSEEK_API_KEY')
        message = str(caught.exception)
        self.assertIn(f'{path}:2', message)
        self.assertNotIn(secret, message)
        result = self.invoke_config('value', 'deepseek.env', 'DEEPSEEK_API_KEY')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertIn(f'{path}:2', result.stderr)
        self.assertNotIn(secret, result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def test_value_only_accepts_path_names(self):
        result = self.invoke_config('value', 'other.env', 'DEEPSEEK_API_KEY')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertIn('invalid choice', result.stderr)

    def test_unreadable_deepseek_credential_is_classified_as_auth(self):
        repo, task = self.repo_fixture()
        fake = self.d / 'fake-bin'
        fake.mkdir()
        claude = fake / 'claude'
        claude.write_text('#!/bin/sh\nexit 1\n')
        claude.chmod(0o755)
        env = dict(self.env, PATH=str(fake) + os.pathsep + self.env['PATH'])
        env.pop('DEEPSEEK_API_KEY', None)
        log = self.d / 'deepseek.log'
        result = subprocess.run(
            [str(ROOT / 'bin' / 'subdeepseek-agent'), 'review', str(task), str(log), str(repo)],
            env=env, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('aiwork-config:', result.stderr)
        self.assertIn(str(self.config / 'deepseek.env'), result.stderr)
        self.assertRegex(result.stderr, r'\bauth\b')
        self.assertIn('凭证读不到', result.stderr)
        diagnostic = self.d / 'deepseek.err'
        diagnostic.write_text(result.stderr)
        evidence = self.d / 'deepseek-evidence.log'
        evidence.write_text('partial output\n')
        emitted = self.d / 'deepseek.result.json'
        classified = subprocess.run(
            [sys.executable, str(ROOT / 'bin' / '_review_result.py'), 'emit',
             '--result', str(emitted), '--run-id', 'missing-key', '--name', 'subdeepseek-agent',
             '--family', 'deepseek', '--adapter', 'subdeepseek-agent', '--exit-code', '1',
             '--task-sha256', 'sha256:' + '0' * 64, '--log', str(evidence),
             '--diagnostic', str(diagnostic)],
            capture_output=True, text=True, timeout=20)
        self.assertEqual(classified.returncode, 0, classified.stderr)
        self.assertEqual(json.loads(emitted.read_text())['failure_kind'], 'auth')

    def test_path_names_deepseek_env(self):
        result = self.invoke_config('path', 'deepseek.env')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.config / 'deepseek.env'))

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
        write_programs(self.d / 'programs-only')
        fixture.env['AIWORK_CONFIG_DIR'] = str(self.d / 'programs-only')
        fixture.env['AIWORK_APPS_DIR'] = str(fixture.root / 'apps')
        result = fixture.invoke(['--repo', 'SunJ1ayu/aiwork'], ['SunJ1ayu/aiwork'])
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()

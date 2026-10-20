#!/usr/bin/env python3
"""Data paths through relocated tools, with no user data or providers."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401
from _test_settings import write_programs

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LocalDataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.d = Path(self.temp.name).resolve()
        self.home = self.d / 'home'
        self.home.mkdir()
        self.tool = self.d / 'relocated tools'
        shutil.copytree(ROOT / 'bin', self.tool / 'bin', ignore=shutil.ignore_patterns('__pycache__'))
        self.data = self.d / 'machine data'
        self.data.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), AIWORK_DATA_DIR=str(self.data))

    def run_tool(self, name, *args, env=None):
        config = Path((env or self.env)['AIWORK_CONFIG_DIR'])
        if not (config / 'programs').exists():
            write_programs(config)
        return subprocess.run([str(self.tool / 'bin' / name), *args],
                              env=env or self.env, capture_output=True, text=True, timeout=20)

    def assert_data_dir_refused(self, result, path):
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout.strip(), '')
        self.assertNotIn(str(path), result.stdout)
        self.assertIn(str(path), result.stderr)
        self.assertIn('先确认盘已经挂好', result.stderr)
        self.assertFalse(Path(path).exists())

    def test_missing_data_dir_stops_without_printing_or_creating_it(self):
        env = dict(self.env)
        env.pop('AIWORK_DATA_DIR', None)
        env['XDG_DATA_HOME'] = str(self.d / 'provider-xdg')
        expected = self.home / '.local/share/aiwork'
        result = self.run_tool('aiwork-config', 'data-path', 'logs', env=env)
        self.assert_data_dir_refused(result, expected)
        self.assertFalse((self.d / 'provider-xdg').exists())

        target = self.d / 'unmounted'
        link = self.d / 'data-link'
        link.symlink_to(target)
        result = self.run_tool('aiwork-config', 'data-path', env=dict(env, AIWORK_DATA_DIR=str(link)))
        self.assert_data_dir_refused(result, target)
        self.assertFalse(link.is_dir())

        not_dir = self.d / 'not-a-directory'
        not_dir.write_text('file')
        result = self.run_tool('aiwork-config', 'data-path', env=dict(env, AIWORK_DATA_DIR=str(not_dir)))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout.strip(), '')
        self.assertIn(str(not_dir), result.stderr)
        self.assertTrue(not_dir.is_file())

    def test_existing_data_dir_query_does_not_create_children(self):
        env = dict(self.env)
        env.pop('AIWORK_DATA_DIR', None)
        env['XDG_DATA_HOME'] = str(self.d / 'provider-xdg')
        default = self.home / '.local/share/aiwork'
        default.mkdir(parents=True)
        result = self.run_tool('aiwork-config', 'data-path', 'logs', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(default / 'logs'))
        self.assertFalse((default / 'logs').exists())
        self.assertFalse((self.d / 'provider-xdg').exists())

        env['AIWORK_DATA_DIR'] = '~/custom data'
        missing = self.run_tool('aiwork-config', 'data-path', 'refs', env=env)
        self.assert_data_dir_refused(missing, self.home / 'custom data')
        (self.home / 'custom data').mkdir()
        result = self.run_tool('aiwork-config', 'data-path', 'refs', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.home / 'custom data/refs'))
        self.assertFalse((self.home / 'custom data/refs').exists())

        mounted = self.d / 'mounted'
        mounted.mkdir()
        alias = self.d / 'mounted-link'
        alias.symlink_to(mounted, target_is_directory=True)
        result = self.run_tool('aiwork-config', 'data-path', 'logs',
                               env=dict(self.env, AIWORK_DATA_DIR=str(alias)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(mounted / 'logs'))
        self.assertFalse((mounted / 'logs').exists())

        for name in ('out', '.mimocode', 'etc', 'scratch', 'tasks', 'worktrees'):
            result = self.run_tool('aiwork-config', 'data-path', name)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(self.data / name))
            self.assertFalse((self.data / name).exists())

    def test_subkimi_refuses_when_data_dir_is_missing_without_calling_the_model(self):
        missing = self.d / 'missing-data'
        config = self.d / 'kimi-settings'
        config.mkdir()
        (config / 'models.env').write_text('kimi=kimi-code/kimi-for-coding\n')
        seed = self.tool / 'kimi-review-home'
        (seed / 'hooks').mkdir(parents=True)
        (seed / 'hooks' / 'guard.mjs').write_text('process.exit(2);\n')
        (seed / 'config.toml').write_text('default_model="__KIMI_MODEL_ALIAS__"\n')
        calls = self.d / 'kimi-calls'
        fake = self.d / 'fakebin'
        fake.mkdir()
        (fake / 'kimi').write_text(f"#!/bin/sh\necho called >> '{calls}'\nexit 0\n")
        (fake / 'kimi').chmod(0o755)
        repo = self.d / 'kimi-repo'
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', '-b', 'main', str(repo)], check=True, capture_output=True)
        task = self.d / 'kimi-task.md'
        task.write_text('fixture')
        env = dict(self.env)
        env.update(AIWORK_DATA_DIR=str(missing), AIWORK_CONFIG_DIR=str(config),
                   PATH=str(fake) + os.pathsep + env.get('PATH', ''))
        env.pop('KIMI_REVIEW_HOME', None)
        env.pop('REVIEW_PRINT_HOME', None)
        result = self.run_tool('subkimi', 'review', str(task), str(self.d / 'kimi.log'), str(repo), env=env)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertFalse(missing.exists(), result.stderr)
        self.assertFalse(calls.exists(), result.stderr)
        self.assertIn(str(missing), result.stderr)

    def test_review_pr_stops_when_data_dir_is_missing(self):
        missing = self.d / 'missing-review-data'
        result = self.run_tool('review-pr', '1', '--repo', 'SunJ1ayu/aiwork',
                               env=dict(self.env, AIWORK_DATA_DIR=str(missing)))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), '')
        self.assertFalse(missing.exists(), result.stderr)
        self.assertIn(str(missing), result.stderr)
        self.assertIn('先确认盘已经挂好', result.stderr)

    def test_symlink_loop_data_dir_exits_2_without_a_traceback(self):
        left = self.d / 'loop-a'
        right = self.d / 'loop-b'
        left.symlink_to(right.name)
        right.symlink_to(left.name)
        result = self.run_tool('aiwork-config', 'data-path',
                               env=dict(self.env, AIWORK_DATA_DIR=str(left)))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout.strip(), '')
        self.assertNotIn('Traceback', result.stderr)
        self.assertIn(str(left), result.stderr)
        self.assertIn('先确认盘已经挂好', result.stderr)

    def test_review_legs_do_not_create_a_missing_data_dir_or_call_a_model(self):
        repo = self.d / 'leg-repo'
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', '-b', 'main', str(repo)], check=True, capture_output=True)
        subprocess.run(['git', '-C', str(repo), 'config', 'user.email', 'test@example.invalid'],
                       check=True, capture_output=True)
        subprocess.run(['git', '-C', str(repo), 'config', 'user.name', 'test'],
                       check=True, capture_output=True)
        (repo / 'a.txt').write_text('a\n')
        subprocess.run(['git', '-C', str(repo), 'add', 'a.txt'], check=True, capture_output=True)
        subprocess.run(['git', '-C', str(repo), 'commit', '-qm', 'init'], check=True, capture_output=True)
        task = self.d / 'leg-task.md'
        task.write_text('fixture\n')
        config = self.d / 'leg-settings'
        config.mkdir()
        (config / 'models.env').write_text(
            'codex=gpt-6-sol\n'
            'cursor=grok-4.7-high\n'
            'deepseek=deepseek-flash\n'
            'kimi=kimi-code/kimi-for-coding\n'
            'mimo=xiaomi/mimo-v2.6-pro\n')
        kimi_home = self.d / 'kimi-home'
        (kimi_home / 'hooks').mkdir(parents=True)
        (kimi_home / 'credentials').mkdir()
        (kimi_home / 'config.toml').write_text('model = "fixture"\n')
        (kimi_home / 'hooks' / 'guard.mjs').write_text('process.exit(2)\n')
        (kimi_home / 'credentials' / 'kimi-code.json').write_text('{}\n')
        mimo_home = self.d / 'mimo-home'
        mimo_home.mkdir()
        fake = self.d / 'leg-fake'
        fake.mkdir()
        cases = (
            ('subcodex', ('review',), {}),
            ('subcursor', ('review',), {'CURSOR_API_KEY': 'fixture'}),
            ('subagent', ('deepseek', 'review'), {'DEEPSEEK_API_KEY': 'fixture'}),
            ('subkimi', ('review',), {'KIMI_REVIEW_HOME': str(kimi_home)}),
            ('submimo', ('review',), {'MIMO_REVIEW_HOME': str(mimo_home)}),
        )
        binaries = ('codex', 'cursor-agent', 'claude', 'kimi', 'mimo')
        for name, prefix, extra in cases:
            missing = self.d / f'missing-{name}'
            calls = self.d / f'calls-{name}'
            for binary in binaries:
                script = fake / binary
                script.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$0\" >> '{calls}'\nexit 0\n")
                script.chmod(0o755)
            env = dict(self.env)
            env.update(AIWORK_DATA_DIR=str(missing), AIWORK_CONFIG_DIR=str(config),
                       PATH=str(fake) + os.pathsep + env.get('PATH', ''))
            for key in ('KIMI_REVIEW_HOME', 'MIMO_REVIEW_HOME', 'CURSOR_API_KEY',
                        'DEEPSEEK_API_KEY', 'REVIEW_PRINT_HOME'):
                env.pop(key, None)
            env.update(extra)
            log = missing / 'logs' / 'x.log'
            result = self.run_tool(name, *prefix, str(task), str(log), str(repo), env=env)
            with self.subTest(leg=name):
                self.assertEqual(result.returncode, 78, result.stderr)
                self.assertFalse(missing.exists(), result.stderr)
                self.assertFalse(calls.exists(), result.stderr)
                self.assertIn(str(missing), result.stderr)
                self.assertIn('先确认盘已经挂好', result.stderr)
                self.assertNotIn('Traceback', result.stderr)

if __name__ == '__main__':
    unittest.main()

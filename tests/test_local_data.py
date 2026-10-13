#!/usr/bin/env python3
"""Data paths through relocated tools, with no user data or providers."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

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
        self.d = Path(self.temp.name)
        self.home = self.d / 'home'
        self.home.mkdir()
        self.tool = self.d / 'relocated tools'
        shutil.copytree(ROOT / 'bin', self.tool / 'bin', ignore=shutil.ignore_patterns('__pycache__'))
        self.data = self.d / 'machine data'
        self.data.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), AIWORK_DATA_DIR=str(self.data))

    def run_tool(self, name, *args, env=None):
        return subprocess.run([str(self.tool / 'bin' / name), *args],
                              env=env or self.env, capture_output=True, text=True, timeout=20)

    def test_submimo_iso_seeds_credentials_from_home(self):
        canonical = self.home / '.local/share/mimocode'
        canonical.mkdir(parents=True)
        credential = ' '.join(('fixture', 'credential'))
        (canonical / 'auth.json').write_text(credential)
        stub = self.tool / 'bin/submimo'
        stub.write_text('#!/bin/bash\ncp "$XDG_DATA_HOME/mimocode/auth.json" "$3"\n')
        project = self.d / 'project'
        project.mkdir()
        subprocess.run(['git', 'init', '-q', str(project)], check=True, capture_output=True)
        task = self.d / 'task.md'
        task.write_text('fixture task')
        log = self.d / 'review.log'
        result = self.run_tool('submimo-iso', 'fixture', 'review', str(task), str(project), str(log))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(log.read_text() == credential, 'credentials did not come from HOME')
        self.assertTrue((self.data / 'mimo-home/fixture/data/mimocode/auth.json').read_text()
                        == credential, 'isolated home was not seeded from HOME')

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

        for name in ('out', '.mimocode', 'etc', 'attack-logs', 'tasks', 'worktrees'):
            result = self.run_tool('aiwork-config', 'data-path', name)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(self.data / name))
            self.assertFalse((self.data / name).exists())

    def test_default_review_home_query_uses_data_and_preserves_seed(self):
        seed = self.tool / 'kimi-review-home'
        (seed / 'credentials').mkdir(parents=True)
        (seed / 'credentials/marker').write_text('fixture only')
        repo = self.d / 'repo'
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        task = self.d / 'task.md'
        task.write_text('fixture')
        result = self.run_tool('subkimi', 'review', str(task), str(self.d / 'log'), str(repo),
                               env=dict(self.env, REVIEW_PRINT_HOME='1'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.data / 'kimi-review-home'))
        self.assertFalse((self.data / 'kimi-review-home').exists())
        self.assertTrue((seed / 'credentials/marker').exists())

    def test_kimi_sync_copies_only_seed_and_keeps_existing_runtime(self):
        seed = self.tool / 'kimi-review-home'
        (seed / 'hooks').mkdir(parents=True)
        shutil.copy2(ROOT / 'kimi-review-home/config.toml', seed / 'config.toml')
        (seed / 'hooks/guard.mjs').write_text('process.exit(2);\n')
        (seed / 'hooks/leftover.mjs').write_text('runtime leftover')
        for name in ('credentials', 'cache', 'sessions', 'logs', 'search-index', 'telemetry'):
            (seed / name).mkdir()
            (seed / name / 'marker').write_text('seed runtime: must stay here')
        repo = self.d / 'repo'
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        task = self.d / 'task.md'
        task.write_text('fixture')
        env = dict(self.env)
        env.pop('KIMI_REVIEW_HOME', None)
        runtime = self.data / 'kimi-review-home'
        for existing in (False, True):
            with self.subTest(existing=existing):
                if existing:
                    (runtime / 'sessions').mkdir(parents=True, exist_ok=True)
                    (runtime / 'sessions/marker').write_text('existing runtime')
                self.run_tool('subkimi', 'review', str(task), str(self.d / 'log'), str(repo), env=env)
                self.assertTrue((runtime / 'hooks/guard.mjs').is_file())
                self.assertFalse((runtime / 'hooks/leftover.mjs').exists())
                self.assertIn(str(runtime / 'hooks/guard.mjs'), (runtime / 'config.toml').read_text())
                for name in ('credentials', 'cache', 'logs', 'search-index', 'telemetry'):
                    self.assertFalse((runtime / name).exists(), name)
                if existing:
                    self.assertEqual((runtime / 'sessions/marker').read_text(), 'existing runtime')
                else:
                    self.assertFalse((runtime / 'sessions').exists())
                self.assertTrue((seed / 'credentials/marker').exists())

    def test_kimi_rejects_data_root_inside_reviewed_repo_before_sync(self):
        seed = self.tool / 'kimi-review-home'
        (seed / 'hooks').mkdir(parents=True)
        (seed / 'config.toml').write_text('default_model="__KIMI_MODEL_ALIAS__"\n')
        repo = self.d / 'repo'
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        task = self.d / 'task.md'
        task.write_text('fixture')
        link = self.d / 'data-link'
        link.symlink_to(repo, target_is_directory=True)
        (repo / 'runtime').mkdir()
        result = self.run_tool('subkimi', 'review', str(task), str(self.d / 'log'), str(repo),
                               env=dict(self.env, AIWORK_DATA_DIR=str(link / 'runtime')))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('仓内', result.stderr)
        self.assertFalse((repo / 'runtime' / 'hooks').exists())

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

if __name__ == '__main__':
    unittest.main()

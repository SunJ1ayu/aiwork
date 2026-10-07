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

    def test_data_default_override_and_query_do_not_create_directories(self):
        env = dict(self.env)
        env.pop('AIWORK_DATA_DIR', None)
        env['XDG_DATA_HOME'] = str(self.d / 'provider-xdg')
        result = self.run_tool('aiwork-config', 'data-path', 'logs', env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = self.home / '.local/share/aiwork/logs'
        self.assertEqual(result.stdout.strip(), str(expected))
        self.assertFalse(expected.exists())
        env['AIWORK_DATA_DIR'] = '~/custom data'
        result = self.run_tool('aiwork-config', 'data-path', 'refs', env=env)
        self.assertEqual(result.stdout.strip(), str(self.home / 'custom data/refs'))
        self.assertFalse((self.home / 'custom data').exists())
        for name in ('out', '.mimocode', 'etc', 'attack-logs', 'tasks', 'worktrees'):
            result = self.run_tool('aiwork-config', 'data-path', name)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(self.data / name))

    def test_track_templates_follow_the_relocated_tool(self):
        shutil.copytree(ROOT / 'track', self.tool / 'track')
        project = self.d / 'project'
        project.mkdir()
        link = self.d / 'track'
        link.symlink_to(self.tool / 'bin/track')
        result = subprocess.run([str(link), 'new', 'portable-fixture', str(project)],
                                env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ('proposal.md', 'design.md', 'tasks.md', 'verify.md', 'decision.json'):
            self.assertTrue((project / 'tracks/portable-fixture' / name).is_file())
        self.assertFalse(self.data.exists())

    def test_archive_refuses_registered_legacy_tree_without_moving_data(self):
        project = self.d / 'project'
        project.mkdir()
        def git(*args):
            return subprocess.run(['git', '-C', str(project), *args], check=True,
                                  capture_output=True, text=True)
        git('init', '-q', '-b', 'main')
        git('config', 'user.email', 'fixture@example.com')
        git('config', 'user.name', 'Fixture')
        record = project / 'tracks/legacy-fixture'
        record.mkdir(parents=True)
        (record / 'verify.md').write_text('# Verify\n- Verdict: PASS\n- 无机器证据:离线临时夹具\n')
        git('add', '.')
        git('commit', '-qm', 'fixture')
        old = self.tool / 'worktrees/legacy-fixture/job'
        old.parent.mkdir(parents=True)
        git('worktree', 'add', '-q', '-b', 'delegate/legacy-fixture/job', str(old))
        (old / 'precious').write_text('uncommitted state')
        env = dict(self.env)
        env.pop('DELEGATE_WORKTREE_ROOT', None)
        other = self.d / 'second checkout'
        shutil.copytree(self.tool / 'bin', other / 'bin')
        for tool in (self.tool, other):
            with self.subTest(tool=tool.name):
                result = subprocess.run([str(tool / 'bin/track'), 'archive', 'legacy-fixture', str(project)],
                                        env=env, capture_output=True, text=True, timeout=20)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(str(old), result.stderr)
                self.assertIn(str(self.data / 'worktrees'), result.stderr)
                self.assertTrue(record.is_dir())
                self.assertEqual((old / 'precious').read_text(), 'uncommitted state')
                self.assertFalse(self.data.exists())

    def test_archive_still_supports_projects_without_git(self):
        project = self.d / 'non-git project'
        record = project / 'tracks/plain-fixture'
        record.mkdir(parents=True)
        (record / 'verify.md').write_text('# Verify\n- Verdict: PASS\n- 无机器证据:离线临时夹具\n')
        env = dict(self.env)
        env.pop('DELEGATE_WORKTREE_ROOT', None)
        preflight = self.run_tool('track', 'preflight', 'plain-fixture', str(project), env=env)
        self.assertRegex(preflight.stdout, r'OK\s+worktrees:')
        self.assertNotIn('读取 Git worktree 注册信息失败', preflight.stderr)
        result = self.run_tool('track', 'archive', 'plain-fixture', str(project), env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((project / 'tracks/archive/plain-fixture/verify.md').is_file())
        self.assertFalse(self.data.exists())

    def test_old_tree_owned_by_parent_repo_does_not_block_nested_project(self):
        parent = self.d / 'parent repo'
        parent.mkdir()
        def git(*args):
            return subprocess.run(['git', '-C', str(parent), *args], check=True,
                                  capture_output=True, text=True)
        git('init', '-q', '-b', 'main')
        git('config', 'user.email', 'fixture@example.com')
        git('config', 'user.name', 'Fixture')
        (parent / 'file').write_text('fixture')
        git('add', '.')
        git('commit', '-qm', 'fixture')
        old = self.tool / 'worktrees/plain-fixture/job'
        old.parent.mkdir(parents=True)
        git('worktree', 'add', '-q', '-b', 'delegate/plain-fixture/job', str(old))
        (old / 'precious').write_text('parent state')
        project = parent / 'plain project'
        record = project / 'tracks/plain-fixture'
        record.mkdir(parents=True)
        (record / 'verify.md').write_text('# Verify\n- Verdict: PASS\n- 无机器证据:离线临时夹具\n')
        env = dict(self.env)
        env.pop('DELEGATE_WORKTREE_ROOT', None)
        result = self.run_tool('track', 'archive', 'plain-fixture', str(project), env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((project / 'tracks/archive/plain-fixture/verify.md').is_file())
        self.assertEqual((old / 'precious').read_text(), 'parent state')

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
                               env=dict(self.env, REVIEW_PRINT_HOME='1', REVIEW_NO_MY_REVIEW='1'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.data / 'kimi-review-home'))
        self.assertFalse(self.data.exists())
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
        env = dict(self.env, REVIEW_NO_MY_REVIEW='1')
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
        result = self.run_tool('subkimi', 'review', str(task), str(self.d / 'log'), str(repo),
                               env=dict(self.env, AIWORK_DATA_DIR=str(link / 'runtime'), REVIEW_NO_MY_REVIEW='1'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('仓内', result.stderr)
        self.assertFalse((repo / 'runtime').exists())

    def test_review_gate_resolves_default_self_review_outside_relocated_source(self):
        task = self.d / 'task.md'
        task.write_text('fixture')
        review = self.data / 'tasks/task-my-review.md'
        review.parent.mkdir(parents=True)
        review.write_text('first review')
        command = ['bash', '-c', '. "$1"; my_review_gate review "$2" "$3" fixture',
                   'fixture', str(self.tool / 'bin/_my-review-gate.sh'), str(task), str(self.tool)]
        env = dict(self.env)
        env.pop('REVIEW_NO_MY_REVIEW', None)
        env.pop('REVIEW_MY_REVIEW', None)
        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        review.unlink()
        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(review), result.stderr)


if __name__ == '__main__':
    unittest.main()

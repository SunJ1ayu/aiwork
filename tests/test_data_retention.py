#!/usr/bin/env python3
"""Retention uses the data registry, never follows links, and has a dry run."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import json
import errno
import io
from contextlib import redirect_stderr
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bin'))
import _aiwork_config as config
from test_review_pr import load_script


class DataRetentionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.data = self.root / 'data'
        self.data.mkdir()
        environment = patch.dict(os.environ, AIWORK_DATA_DIR=str(self.data))
        environment.start()
        self.addCleanup(environment.stop)

    def old(self, path):
        os.utime(path, (1, 1), follow_symlinks=False)
        return path

    def file(self, relative, text='artifact', old=True):
        path = self.data / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return self.old(path) if old else path

    def test_expired_items_deleted_recent_files_keep_old_directories_alive(self):
        for entry in config.DATA_ENTRIES:
            if entry['keep_days'] is None:
                continue
            prefix = entry['name']
            expired = self.file(f'{prefix}/old.log')
            nested = self.file(f'{prefix}/old-directory/nested/old.log')
            fresh = self.file(f'{prefix}/recent-directory/nested/recent.log', old=False)
            self.old(fresh.parent)
            self.old(fresh.parent.parent)
            fresh_file = self.file(f'{prefix}/recent.log', old=False)
            config.prune_data()
            self.assertFalse(expired.exists())
            self.assertFalse(nested.parent.parent.exists())
            self.assertTrue(fresh.exists())
            self.assertTrue(fresh_file.exists())

    def test_worktrees_and_unregistered_directories_are_untouched(self):
        work = self.file('worktrees/branch/file')
        other = self.file('not-registered/file')
        config.prune_data()
        self.assertTrue(work.exists())
        self.assertTrue(other.exists())

    def test_links_use_their_own_age_and_never_touch_targets(self):
        outside = self.root / 'outside'
        outside.mkdir()
        marker = outside / 'keep'
        marker.write_text('outside')
        logs = self.data / 'logs'
        logs.mkdir()
        link = logs / 'old-link'
        link.symlink_to(outside, target_is_directory=True)
        self.old(link)
        nested = logs / 'old-tree'
        nested.mkdir()
        (nested / 'link').symlink_to(outside, target_is_directory=True)
        self.old(nested / 'link')
        (logs / 'fresh-link').symlink_to(marker)
        config.prune_data()
        self.assertFalse(link.is_symlink())
        self.assertFalse(nested.exists())
        self.assertTrue((logs / 'fresh-link').is_symlink())
        self.assertEqual(marker.read_text(), 'outside')

    def test_registered_container_symlink_is_not_traversed(self):
        outside = self.root / 'outside'
        outside.mkdir()
        marker = outside / 'keep'
        marker.write_text('outside')
        self.old(marker)
        (self.data / 'logs').symlink_to(outside, target_is_directory=True)
        self.assertEqual(config.prune_data(), [])
        self.assertEqual(marker.read_text(), 'outside')

    def test_concurrent_deletion_is_not_an_error(self):
        first = self.file('logs/old-tree/first')
        second = self.file('logs/old-tree/second')
        real_unlink = os.unlink

        def deleted_by_peer(path, *args, **kwargs):
            real_unlink(path, *args, **kwargs)
            return real_unlink(path, *args, **kwargs)

        with patch.object(config.os, 'unlink', side_effect=deleted_by_peer):
            config.prune_data()
        self.assertFalse(first.parent.exists())
        self.assertFalse(second.exists())

    def test_directory_disappearing_during_scan_is_not_an_error(self):
        item = self.file('logs/old-tree/file').parent
        identity = item.stat().st_ino
        real_scandir = os.scandir
        removed = False

        def peer_removes_directory(fd):
            nonlocal removed
            if not removed and isinstance(fd, int) and os.fstat(fd).st_ino == identity:
                removed = True
                shutil.rmtree(item)
                raise FileNotFoundError('peer removed directory')
            return real_scandir(fd)

        with patch.object(config.os, 'scandir', side_effect=peer_removes_directory):
            config.prune_data()
        self.assertTrue(removed)
        self.assertFalse(item.exists())

    def test_registry_cannot_name_a_path_outside_data(self):
        outside = self.root / 'outside'
        outside.mkdir()
        marker = outside / 'keep'
        marker.write_text('outside')
        self.old(marker)
        with patch.object(config, 'DATA_ENTRIES', ({'name': '../outside', 'keep_days': 1},)):
            with self.assertRaises(config.ConfigError):
                config.prune_data()
        self.assertEqual(marker.read_text(), 'outside')

    def test_dry_run_lists_path_size_and_file_time_without_deleting(self):
        path = self.file('logs/old-tree/old.log', text='abc')
        fresh = self.file('logs/fresh.log', old=False)
        records = config.prune_data(dry_run=True)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]['path'], str(path.parent))
        self.assertEqual(records[0]['size_bytes'], 3)
        self.assertEqual(records[0]['last_modified'], '1970-01-01T00:00:01+00:00')
        self.assertEqual(path.read_text(), 'abc')
        self.assertTrue(fresh.exists())

    def test_empty_directory_and_expiry_boundary(self):
        path = self.data / 'tasks' / 'empty'
        path.mkdir(parents=True)
        self.old(path)
        boundary = self.file('logs/boundary.log')
        days = next(e['keep_days'] for e in config.DATA_ENTRIES if e['name'] == 'logs')
        now = time.time()
        cutoff = now - days * 24 * 60 * 60
        os.utime(boundary, (cutoff, cutoff))
        with patch.object(config.time, 'time', return_value=now):
            config.prune_data()
        self.assertFalse(path.exists())
        self.assertTrue(boundary.exists())

    def test_cli_dry_run_and_delete_use_the_same_candidates(self):
        old = self.file('logs/old.log')
        command = [str(ROOT / 'bin/aiwork-config'), 'prune-data']
        dry = subprocess.run(command + ['--dry-run'], capture_output=True, text=True, timeout=10)
        self.assertEqual(dry.returncode, 0, dry.stderr)
        self.assertEqual(json.loads(dry.stdout)[0]['path'], str(old))
        self.assertTrue(old.exists())
        real = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(real.returncode, 0, real.stderr)
        self.assertEqual(json.loads(real.stdout), json.loads(dry.stdout))
        self.assertFalse(old.exists())

    def archive(self, run_id, old=False):
        source = self.root / f'source-{run_id}'
        source.mkdir()
        (source / 'review.log').write_text(run_id)
        with redirect_stderr(io.StringIO()):
            load_script().report_failure(source, run_id)
        # Find the real writer's output, including on the pre-fix head.
        archive = next(self.data.rglob(f'{run_id}/review.log')).parent
        if old:
            self.old(archive / 'review.log')
            self.old(archive)
        return archive

    def test_failure_archives_expire_independently(self):
        old = self.archive('old-run', old=True)
        fresh = self.archive('new-run')
        records = config.prune_data()
        self.assertFalse(old.exists())
        self.assertEqual(fresh, self.data / 'review-failures/new-run')
        self.assertEqual((fresh / 'review.log').read_text(), 'new-run')
        self.assertEqual([row['path'] for row in records], [str(old)])

    def test_new_failure_during_deletion_is_a_separate_unit(self):
        old = self.archive('old-run', old=True)
        unit = old if old.parent.name == 'review-failures' else old.parent
        self.old(unit)
        identity = unit.stat().st_ino
        real_scandir = os.scandir
        scans = 0

        def concurrent_archive(fd):
            nonlocal scans
            if isinstance(fd, int) and os.fstat(fd).st_ino == identity:
                scans += 1
                if scans == 3:  # Two age checks, then enumeration for deletion.
                    self.archive('concurrent-run')
            return real_scandir(fd)

        with patch.object(config.os, 'scandir', side_effect=concurrent_archive):
            config.prune_data()
        self.assertEqual(scans, 3)
        self.assertFalse(old.exists())
        self.assertEqual((self.data / 'review-failures/concurrent-run/review.log').read_text(),
                         'concurrent-run')

    def test_delete_errors_warn_and_continue_with_other_units(self):
        bad = self.file('logs/a-denied.log')
        good = self.file('logs/b-good.log')
        other = self.file('tasks/good.md')
        real_unlink = os.unlink

        def denied(path, *args, **kwargs):
            if path == bad.name:
                raise PermissionError(errno.EACCES, 'simulated permission denied')
            return real_unlink(path, *args, **kwargs)

        stderr = io.StringIO()
        with patch.object(config.os, 'unlink', side_effect=denied), redirect_stderr(stderr):
            records = config.prune_data()
        self.assertTrue(bad.exists())
        self.assertFalse(good.exists())
        self.assertFalse(other.exists())
        self.assertEqual({row['path'] for row in records}, {str(good), str(other)})
        self.assertIn(str(bad), stderr.getvalue())
        self.assertIn('simulated permission denied', stderr.getvalue())

    def test_directory_changed_during_delete_warns_and_continues(self):
        bad = self.file('logs/a-changed/file').parent
        good = self.file('logs/z-good.log')
        real_rmdir = os.rmdir

        def changed(path, *args, **kwargs):
            if path == bad.name:
                raise OSError(errno.ENOTEMPTY, 'directory changed during deletion')
            return real_rmdir(path, *args, **kwargs)

        stderr = io.StringIO()
        with patch.object(config.os, 'rmdir', side_effect=changed), redirect_stderr(stderr):
            config.prune_data()
        self.assertTrue(bad.exists())
        self.assertFalse(good.exists())
        self.assertIn(str(bad), stderr.getvalue())
        self.assertIn('directory changed during deletion', stderr.getvalue())

    def test_mounts_at_registry_unit_and_nested_levels_are_skipped(self):
        for relative in ('logs', 'logs/mount', 'logs/unit/mount'):
            with self.subTest(relative=relative):
                marker = self.file(f'{relative}/marker')
                mount = marker.parent
                identity = mount.stat().st_ino
                real_stat, real_fstat = os.stat, os.fstat

                def foreign(info):
                    if info.st_ino == identity:
                        values = list(info)
                        values[2] += 1  # st_dev: simulate a different filesystem.
                        return os.stat_result(values)
                    return info

                stderr = io.StringIO()
                with patch.object(config.os, 'stat', side_effect=lambda *a, **k: foreign(real_stat(*a, **k))), \
                        patch.object(config.os, 'fstat', side_effect=lambda *a: foreign(real_fstat(*a))), \
                        redirect_stderr(stderr):
                    self.assertEqual(config.prune_data(dry_run=True), [])
                    self.assertEqual(config.prune_data(), [])
                self.assertTrue(marker.exists())
                self.assertIn('filesystem', stderr.getvalue())
                marker.unlink()
                while mount != self.data:
                    parent = mount.parent
                    mount.rmdir()
                    mount = parent

    def test_deep_tree_is_measured_and_deleted_without_python_recursion(self):
        unit = self.data / 'logs/deep'
        unit.mkdir(parents=True)
        directories = [unit]
        for _ in range(sys.getrecursionlimit() + 100):
            child = directories[-1] / 'd'
            child.mkdir()
            directories.append(child)
        marker = directories[-1] / 'file'
        marker.write_text('old')
        self.old(marker)
        try:
            listed = config.prune_data(dry_run=True)
            self.assertEqual([row['path'] for row in listed], [str(unit)])
            config.prune_data()
            self.assertFalse(unit.exists())
        finally:
            marker.unlink(missing_ok=True)
            for directory in reversed(directories):
                try:
                    directory.rmdir()
                except FileNotFoundError:
                    pass


if __name__ == '__main__':
    unittest.main()

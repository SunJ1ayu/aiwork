"""Repository tools must work without machine-specific paths or settings."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401
from _test_settings import context_fds

from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MachineBitsTests(unittest.TestCase):
    def test_home_guard_rejects_missing_home_beneath_symlinked_repo(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            repo = root / 'repo'
            repo.mkdir()
            alias = root / 'alias'
            alias.symlink_to(repo, target_is_directory=True)
            sibling = root / 'repo-other'
            sibling.mkdir()
            for home, expected in ((alias, 1), (alias / 'missing/home', 1), (sibling, 0)):
                with self.subTest(home=home):
                    result = subprocess.run(
                        ['bash', '-c', '. "$1"; review_home_guard test "$2" "$3"',
                         'home-guard', str(ROOT / 'bin/_review-home-guard.sh'),
                         str(home), str(repo)], capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, expected, result.stderr)

    def test_cleanup_accepts_alias_of_base_but_rejects_escape(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            base = root / 'base'
            base.mkdir()
            alias = root / 'alias'
            alias.symlink_to(base, target_is_directory=True)
            outside = root / 'outside'
            outside.mkdir()
            target = base / 'run'
            target.mkdir()
            escape = base / 'escape'
            escape.symlink_to(outside, target_is_directory=True)
            for path in (target, outside):
                (path / '.aiwork-review-workspace').touch()
            for path, expected in ((outside, 78), (escape, 78), (base, 78), (target, 0)):
                with self.subTest(path=path):
                    result = subprocess.run(
                        ['bash', '-c', '. "$1"; REVIEW_WORKSPACE_BASE_REAL="$2"; '
                         'REVIEW_WORKSPACE_DIR="$3"; review_workspace_cleanup',
                         'cleanup', str(ROOT / 'bin/_review-workspace.sh'),
                         str(alias), str(path)], capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertEqual(path.exists(), expected != 0)

    def test_existing_path_oracles_through_symlinked_temporary_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            real = root / 'real'
            real.mkdir()
            alias = root / 'alias'
            alias.symlink_to(real, target_is_directory=True)
            cases = (
                ('test_review_homes.py', 'ReviewHomes.test_kimi_renders_only_seed_and_links_cli_credentials_each_run'),
                ('test_local_data.py', 'LocalDataTests.test_existing_data_dir_query_does_not_create_children'),
                ('test_data_dir_registry.py', 'DataDirRegistryTest.test_data_path_still_accepts_an_unregistered_name'),
                ('test_data_retention.py', 'DataRetentionTests.test_dry_run_lists_path_size_and_file_time_without_deleting',
                 'DataRetentionTests.test_cli_dry_run_and_delete_use_the_same_candidates',
                 'DataRetentionTests.test_failure_archives_expire_independently',
                 'DataRetentionTests.test_delete_errors_warn_and_continue_with_other_units',
                 'DataRetentionTests.test_three_hundred_levels_with_sixty_four_fds'),
                ('test_explore.py', 'ExploreTests.test_parallel_legs_store_fixture_and_plain_answers_from_main',
                 'ExploreTests.test_one_leg_failure_keeps_the_other_result_and_exits_nonzero',
                 'ExploreTests.test_unexecutable_leg_fails_without_traceback_and_keeps_the_other'),
                ('test_review_pr.py', 'ReviewPrTests.test_authoritative_main_and_inherited_git_env_cannot_retarget_the_check',
                 'ReviewPrTests.test_prune_failure_warns_but_review_reaches_credentials',
                 'ReviewPrTests.test_failed_leg_keeps_whole_directory_and_reports_a_live_log_path'),
            )
            for filename, *tests in cases:
                with self.subTest(suite=filename):
                    result = subprocess.run(
                        [sys.executable, str(ROOT / 'tests' / filename), *tests],
                        env=dict(os.environ, TMPDIR=str(alias)), pass_fds=context_fds(),
                        capture_output=True, text=True, timeout=120)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def oracle_functions(self):
        # Exercise the suite's actual observation functions without running
        # provider fixtures or inspecting the caller's credential directories.
        source = (ROOT / 'tests/test-review-tooling.sh').read_text()
        start = source.index('_fp1() {')
        return source[start:source.index('OWNER_ENV_BEFORE=', start)]

    def test_owner_collection_rejects_empty_or_failed_reads(self):
        with tempfile.TemporaryDirectory() as folder:
            for status in (0, 1):
                with self.subTest(read_status=status):
                    script = self.oracle_functions() + '\n' + '''
OWNER_CRED_DIR="$1/credentials"
OWNER_KIMI_HOME="$1/kimi"
OWNER_MIMO_CFG="$1/mimo/config.json"
_fp1() { return %d; }
_owner_env_fp
''' % status
                    result = subprocess.run(['bash', '-c', script, 'collect', folder],
                                            capture_output=True, text=True, timeout=5)
                    self.assertNotEqual(result.returncode, 0, 'unavailable observation accepted')
                    self.assertEqual(result.stdout, '', 'partial observations must not be published')

    def test_owner_comparison_rejects_missing_observations_before_and_after(self):
        source = (ROOT / 'tests/test-review-tooling.sh').read_text()
        before = source[source.index('OWNER_ENV_BEFORE='):source.index('fixture_git_repo() {')]
        start = source.index('v45_oracle_never_touches_owner_credentials() {')
        after = source[start:source.index('v46_final_report_is_the_last_message() {', start)]
        for phase in ('before', 'after'):
            for status in (0, 1):
                with self.subTest(phase=phase, read_status=status):
                    script = '''
set -uo pipefail
ok() { printf 'PASS\\n'; }
bad() { printf 'FAIL\\n'; }
_owner_env_fp() { return %d; }
''' % status
                    if phase == 'before':
                        script += before + '\nprintf "continued after missing observation\\n"\n'
                    else:
                        script += after + '\nOWNER_ENV_BEFORE=""\nv45_oracle_never_touches_owner_credentials\n'
                    result = subprocess.run(['bash', '-c', script], capture_output=True,
                                            text=True, timeout=5)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotIn('PASS', result.stdout)
                    self.assertNotIn('continued after missing observation', result.stdout)

    def test_owner_fingerprint_detects_changes_without_gnu_metadata_tools(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            commands = root / 'commands'
            commands.mkdir()
            for name in ('stat', 'sha256sum'):
                command = commands / name
                command.write_text('#!/bin/sh\nexit 1\n')
                command.chmod(0o755)
            for unavailable in (False, True):
                with self.subTest(metadata_tools_unavailable=unavailable):
                    env = dict(os.environ)
                    if unavailable:
                        env['PATH'] = str(commands) + os.pathsep + env['PATH']
                    path = root / 'observed file'
                    path.write_bytes(b'original')
                    original = path.stat()

                    def fingerprint():
                        result = subprocess.run(
                            ['bash', '-c', self.oracle_functions() + '\n_fp1 "$1"',
                             'fingerprint', str(path)], env=env,
                            capture_output=True, text=True, timeout=5)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertTrue(result.stdout.strip(), 'missing observation')
                        return result.stdout

                    before = fingerprint()
                    path.write_bytes(b'modified')
                    os.utime(path, ns=(original.st_atime_ns, original.st_mtime_ns))
                    after_content = fingerprint()
                    self.assertNotEqual(before, after_content, 'content change went undetected')
                    replacement = root / 'replacement'
                    replacement.write_bytes(path.read_bytes())
                    os.utime(replacement, ns=(original.st_atime_ns, original.st_mtime_ns))
                    os.replace(replacement, path)
                    self.assertNotEqual(after_content, fingerprint(), 'file identity change went undetected')

    def test_workflow_sync_without_gnu_mv_keeps_replacement_semantics(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            commands = root / 'commands'
            commands.mkdir()
            real_mv = shutil.which('mv')
            real_install = shutil.which('install')
            (commands / 'mv').write_text(
                '#!/bin/sh\nfor arg do\ncase "$arg" in\n'
                '  -*T*) echo "mv: illegal option -- T" >&2; exit 64;;\n'
                'esac\ndone\nexec ' + shlex.quote(real_mv) + ' "$@"\n')
            (commands / 'install').write_text(
                '#!/bin/sh\nif [ -n "${SYNC_RACE_DEST:-}" ]; then\n'
                '  mkdir "$SYNC_RACE_DEST" || exit 1\nfi\nexec '
                + shlex.quote(real_install) + ' "$@"\n')
            for command in commands.iterdir():
                command.chmod(0o755)
            target = root / 'target'
            target.mkdir()
            sync = ROOT / 'bin/sync-workflow-docs'
            env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ['PATH'])
            result = subprocess.run([str(sync), '--target-root', str(target)],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            destination = target / 'CLAUDE.md'
            self.assertEqual(destination.read_bytes(), (ROOT / 'workflow/CLAUDE.md').read_bytes())
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o644)
            destination.write_text('local edit\n')
            result = subprocess.run([str(sync), '--force', '--target-root', str(target)],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(destination.read_bytes(), (ROOT / 'workflow/CLAUDE.md').read_bytes())

            # A directory appearing after preflight must not turn replacement
            # into a move inside that directory (plain mv would do that).
            destination.unlink()
            result = subprocess.run([str(sync), '--target-root', str(target)],
                                    env=dict(env, SYNC_RACE_DEST=str(destination)),
                                    capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(destination.is_dir())
            self.assertEqual(list(destination.iterdir()), [])
            self.assertEqual(list(target.glob('.workflow-sync.*.tmp')), [])

    def test_bin_has_no_root_paths_on_non_comment_lines(self):
        hits = []
        for path in sorted((ROOT / 'bin').rglob('*')):
            if not path.is_file() or '__pycache__' in path.parts:
                continue
            try:
                lines = path.read_text(encoding='utf-8').splitlines()
            except UnicodeDecodeError:
                continue
            for number, line in enumerate(lines, 1):
                if not line.lstrip().startswith('#') and '/root/' in line:
                    hits.append(f'{path.relative_to(ROOT)}:{number}')
        self.assertEqual(hits, [], '\n'.join(hits))


if __name__ == '__main__':
    unittest.main()

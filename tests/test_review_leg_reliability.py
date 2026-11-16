#!/usr/bin/env python3
"""Offline PR-to-provider regressions for review-leg reliability."""

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401
from _test_settings import write_kimi_config, write_platform_probe, write_settings
from _runtime_cases import RUNTIME_CASES

from contextlib import redirect_stderr, redirect_stdout
import http.server
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch

from test_review_pr import load_script, CiFixture, CI_POLICY
from test_leg_quick_fixes import LegCase


BIN = Path(__file__).resolve().parents[1] / 'bin'
DIFF_MARKER = 'UNIQUE_DIFF_CONTENT_7015'


class SeparateAccountTests(unittest.TestCase):
    def setUp(self):
        import pwd
        self.temp = tempfile.TemporaryDirectory(dir='/var/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.root.chmod(0o755)
        self.publisher = self.root / 'publisher'
        self.publisher.mkdir(mode=0o700)
        self.tools = self.publisher / 'bin'
        shutil.copytree(BIN, self.tools)
        self.config = self.publisher / 'settings'
        shutil.copytree(os.environ['AIWORK_CONFIG_DIR'], self.config, symlinks=True)
        (self.config / 'review.env').write_text('location=local\n')
        (self.config / 'review-user.env').write_text('user=nobody\n')
        self.data = self.publisher / 'data'
        self.data.mkdir()
        self.output = self.data / 'current'
        self.output.mkdir()
        self.repo = self.output / 'repo'
        self.repo.mkdir()
        self.key = self.publisher / 'fake-key'
        self.key.write_text('disposable publisher key')
        self.key.chmod(0o600)
        apps = self.config / 'apps'
        apps.mkdir(exist_ok=True)
        (apps / 'review.env').write_text('KEY=' + str(self.key) + '\n')
        self.program = self.publisher / 'publisher-program'
        self.program.write_text('publisher deployment')
        self.record = self.data / 'prior-record'
        self.record.write_text('previous result')
        account = pwd.getpwnam('nobody')
        self.uid, self.gid = account.pw_uid, account.pw_gid
        self.home = self.root / 'leg-home'
        (self.home / '.config').mkdir(parents=True)
        shutil.copytree(self.config, self.home / '.config/aiwork', symlinks=True,
                        ignore=shutil.ignore_patterns('apps', 'review.env', 'review-user.env'))
        programs = self.home / '.config/aiwork/programs'
        for item in programs.iterdir():
            if item.is_symlink():
                item.unlink()
                item.symlink_to(Path(sys.executable).resolve() if item.name == 'python3' else '/usr/bin/true')
        (self.home / '.local/share/aiwork').mkdir(parents=True)
        (self.home / '.fixture').mkdir()
        self.profile = self.root / 'runtime-settings'
        shutil.copytree(self.home / '.config/aiwork', self.profile, symlinks=True)
        for path in [self.profile, *self.profile.rglob('*')]:
            if not path.is_symlink():
                path.chmod(0o755 if path.is_dir() else 0o644)
        (self.config / 'review-user.env').write_text('user=nobody\nsettings=' + str(self.profile) + '\n')
        (self.home / '.kimi-code/credentials').mkdir(parents=True)
        (self.home / '.kimi-code/credentials/login').write_text('initial fixture login')
        self.home.chmod(0o700)
        for path in [self.home, *self.home.rglob('*')]:
            os.chown(path, self.uid, self.gid, follow_symlinks=False)
        replacement = pwd.struct_passwd((account.pw_name, account.pw_passwd, self.uid,
                                        self.gid, account.pw_gecos, str(self.home), '/bin/bash'))
        self.lookup = patch('pwd.getpwnam', return_value=replacement)
        self.lookup.start()
        self.addCleanup(self.lookup.stop)
        self.environment = patch.dict(os.environ, HOME=str(self.publisher),
                                      AIWORK_CONFIG_DIR=str(self.config), AIWORK_DATA_DIR=str(self.data),
                                      FAKE_PUBLISHER_SECRET='not-a-real-secret')
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_leg_identity_cannot_access_publisher_and_can_refresh_own_login(self):
        import _leg_session as session
        protected = [self.key, self.program, self.record]
        self.assertTrue(all(os.access(path, os.R_OK | os.W_OK) for path in protected))
        task = self.output / 'task.json'
        task.write_text(json.dumps({'protected': list(map(str, protected)), 'uid': self.uid, 'gid': self.gid}))
        probe = self.tools / 'subcodex'
        probe.write_text('''#!/usr/bin/python3
import json, os, pathlib, subprocess, sys
data = json.loads(pathlib.Path(sys.argv[2]).read_text())
exposed = [path for path in data['protected'] if os.access(path, os.R_OK) or os.access(path, os.W_OK)]
assert not exposed, 'publisher files accessible to leg'
assert os.getuid() == data['uid'] and os.geteuid() == data['uid']
assert os.getgroups() == [data['gid']]
assert os.environ.get('FAKE_PUBLISHER_SECRET') is None
assert 'NoNewPrivs:\\t1' in pathlib.Path('/proc/self/status').read_text()
login = pathlib.Path.home() / '.kimi-code/credentials/login'
assert login.read_text() == 'initial fixture login'
login.write_text('renewed fixture login')
subprocess.run([str(pathlib.Path(os.environ['AIWORK_REVIEW_RESULT_BIN']).parent / 'ro-repo-exec'),
    sys.argv[4], '--', '/bin/true'], check=True)
pathlib.Path(sys.argv[3]).write_text('ordinary account completed')
pathlib.Path(os.environ['AIWORK_REVIEW_REPORT_PATH']).write_text('Conclusion: PASS\\n')
subprocess.run([sys.executable, os.environ['AIWORK_REVIEW_RESULT_BIN'], 'facts',
    '--output', os.environ['AIWORK_REVIEW_FACTS_PATH'],
    '--requested-model', 'gpt-6-sol', '--invoked-model', 'gpt-6-sol',
    '--git-object-format', 'sha1', '--head-oid', 'a' * 40,
    '--index-tree-oid', 'b' * 40, '--worktree-tree-oid', 'b' * 40,
    '--view-delivery-state', 'complete', '--view-mode', 'full_snapshot',
    '--billing-mode', 'subscription', '--process-state', 'exited',
    '--evidence-completeness', 'complete', '--failure-kind', 'none'], check=True)
''')
        probe.chmod(0o755)
        result, report = session.run_leg_attempt('subcodex', 'openai', task, self.repo,
            self.output, dict(os.environ), 'fixture-run', None, bin_dir=self.tools)
        self.assertEqual(result['process']['exit_code'], 0, (self.output / 'leg.stderr').read_text())
        self.assertEqual(result['verdict'], 'PASS')
        self.assertEqual(report.read_text(), 'Conclusion: PASS\n')
        self.assertEqual((self.home / '.kimi-code/credentials/login').read_text(), 'renewed fixture login')
        self.assertEqual(self.program.read_text(), 'publisher deployment')
        self.assertEqual(self.record.read_text(), 'previous result')
        # Real terminal normalization and saved-publication checks; only the
        # GitHub transport is a stub, never an actual external review.
        review = load_script()
        model = review.publishable_model(result)
        body = review.build_body('subcodex', model, report.read_text(),
                                 {'head_sha': 'a' * 40, 'verdict': result['verdict']})
        review.save_publication(self.output, body=body, repository='fixture/project',
                                number=12, leg='subcodex', head='a' * 40)
        with patch.object(review, 'review_token', return_value='fixture-token'), \
                patch.object(review, 'pr_state', return_value={'head': {'sha': 'a' * 40}, 'state': 'open'}), \
                patch.object(review, 'github', return_value={'html_url': 'https://github.com/fixture/project/pull/12#review'}) as post:
            self.assertEqual(review.publish_saved(self.output, repository='fixture/project',
                number=12, leg='subcodex'), 'https://github.com/fixture/project/pull/12#review')
        self.assertEqual(post.call_args.args[2]['commit_id'], 'a' * 40)
        self.assertIn('Conclusion: PASS', post.call_args.args[2]['body'])

    def test_model_and_reader_settings_come_from_the_root_owned_profile(self):
        import _leg_session as session
        config = self.profile
        (config / 'models.env').write_text('cursor=gpt-6-sol\n')
        (config / 'runtime.env').write_text('SUBCODEX_TIMEOUT=456\n')
        (config / 'runtime.env').chmod(0o644)
        with patch.dict(os.environ, SUBCODEX_TIMEOUT='789'):
            self.assertEqual(session.reader_environment('subcodex', dict(os.environ))['SUBCODEX_TIMEOUT'], '456')
        with patch.dict(os.environ):
            os.environ.pop('CURSOR_MODEL', None)
            self.assertEqual(session.choose_leg('subcursor', self.tools), ('openai', 'gpt-6-sol'))

    def test_all_registered_adapters_run_as_the_ordinary_account(self):
        import _leg_session as session
        from _aiwork_config import RUNTIME_OPTIONS
        from _test_settings import kimi_fixture_launcher
        from test_review_homes import STUBS
        from test_leg_finish import LegFinish
        fixture = LegFinish(methodName='runTest')
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        shutil.copytree(fixture.repo, self.repo, dirs_exist_ok=True)
        shutil.copytree(BIN.parent / 'kimi-review-home', self.publisher / 'kimi-review-home')
        native = self.root / 'native'
        native.mkdir(mode=0o755)
        native.chmod(0o755)
        for cli in set(STUBS.values()):
            source = (fixture.bin / cli).read_text().replace('case = os.environ["FINISH_CASE"]', 'case = "pass"')
            if cli == 'cursor-agent' and getattr(self, 'cursor_worker', False):
                source = source.replace('case = \"pass\"', 'case = \"pass\"\nimport subprocess\nsubprocess.Popen([\"/bin/sleep\", \"20\"], start_new_session=True)')
            source = source.replace('\nimport ', '\nimport os\nassert os.getuid() == ' + str(self.uid) + '\nimport ', 1)
            (native / cli).write_text(source)
            (native / cli).chmod(0o755)
        # The parent has already enforced no egress. The fake native CLI runs in
        # another PID namespace, so attest the inherited network namespace by
        # kernel identity rather than comparing its new /proc/1 with itself.
        shutil.copy(BIN.parent / 'tests/_kimi_cli.py', native / '_kimi_cli.py')
        (native / '_no_egress.py').write_text('import os\nassert os.readlink("/proc/self/ns/net") == '
            + repr(os.readlink('/proc/self/ns/net')) + '\n')
        schema = native / 'fixtures/kimi-code-0.36.1'
        schema.mkdir(parents=True)
        shutil.copy(BIN.parent / 'tests/fixtures/kimi-code-0.36.1/reader-tools.json', schema)
        wrapper = kimi_fixture_launcher(fixture.root / 'settings/programs', fixture.bin / 'kimi')
        (native / 'kimi-launch').write_text(wrapper.read_text()
            .replace(str(fixture.bin), str(native))
            .replace(str(BIN.parent / 'tests'), str(native))
            .replace(str(fixture.root / 'settings/programs'), str(native))
            .replace(sys.executable, str(Path(sys.executable).resolve())))
        (native / 'kimi-launch').chmod(0o755)
        programs = self.profile / 'programs'
        for cli in set(STUBS.values()):
            (programs / cli).unlink()
            (programs / cli).symlink_to(native / ('kimi-launch' if cli == 'kimi' else cli))
        (programs / 'node').unlink()
        shutil.copy2(Path(shutil.which('node')).resolve(), native / 'node')
        (programs / 'node').symlink_to(native / 'node')
        (self.profile / 'deepseek.env').write_text('DEEPSEEK_API_KEY=fixture\n')
        (self.home / '.config/cursor').mkdir()
        (self.home / '.config/cursor/auth.json').write_text('{"accessToken":"fixture"}\n')
        (self.home / '.kimi-code/credentials').mkdir(parents=True, exist_ok=True)
        (self.home / '.kimi-code/credentials/kimi-code.json').write_text('{}\n')
        for path in [self.home, *self.home.rglob('*')]:
            os.chown(path, self.uid, self.gid, follow_symlinks=False)
        for path in native.rglob('*'):
            path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
        task = self.output / 'task.md'
        task.write_text('Review the fixture.\n')
        for leg in RUNTIME_OPTIONS:
            with self.subTest(leg=leg):
                self.assertIn(leg, STUBS)
                family, model = session.choose_leg(leg, self.tools)
                result, _ = session.run_leg_attempt(leg, family, task, self.repo,
                    self.output, session.reader_environment(leg, {}), 'fixture-native', model, bin_dir=self.tools)
                self.assertEqual(result['process']['exit_code'], 0, (self.output / 'leg.stderr').read_text())
                self.assertEqual(result['verdict'], 'PASS')

    def test_upgrade_with_root_owned_legacy_workspace(self):
        # Mount an isolated /tmp: never chmod/remove a real old deployment.
        result = subprocess.run(['unshare', '--mount', '--propagation', 'private', '--',
            '/bin/sh', '-ec', 'mount -t tmpfs tmpfs /tmp; '
            'mkdir -m 700 /tmp/aiwork-review-workspaces; exec "$@"', 'legacy-workspace',
            str(Path(sys.executable).resolve()), str(Path(__file__).resolve()),
            'SeparateAccountTests.test_all_registered_adapters_run_as_the_ordinary_account'],
            text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr[-6000:])

    def test_account_cannot_replace_future_runtime_settings(self):
        import _leg_session as session
        with session.tools(self.tools) as (selected, root, bundle, env):
            result = session.execute(selected, [bundle / 'aiwork-config', 'path', 'models.env'],
                                     env=env, cwd=selected.pw_dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            target = result.stdout.strip()
            result = session.execute(selected, ['/bin/sh', '-c',
                'test ! -w "$1" && test ! -w "$(dirname "$1")"', 'immutable-settings', target],
                env=env, cwd=selected.pw_dir)
            self.assertEqual(result.returncode, 0, ('leg can poison next review settings', target, result.stderr))

    def test_outside_account_cannot_replace_result_before_collection(self):
        import _leg_session as session
        task = self.output / 'task.md'
        task.write_text('fixture')
        probe = self.tools / 'subcodex'
        probe.write_text('#!/bin/sh\nprintf "Conclusion: BLOCK\\n" > "$AIWORK_REVIEW_REPORT_PATH"\n')
        probe.chmod(0o755)
        original = session.execute
        attacks = []
        def intercept(selected, command, *, env, cwd):
            result = original(selected, command, env=env, cwd=cwd)
            if Path(command[0]).name == 'subcodex':
                target = Path(env['AIWORK_REVIEW_REPORT_PATH'])
                attacks.append(subprocess.run(['/usr/bin/setpriv', '--reuid=' + str(self.uid),
                    '--regid=' + str(self.gid), '--clear-groups', '/bin/sh', '-c',
                    'printf "Conclusion: PASS\\n" > "$1"', 'outside-account', str(target)],
                    text=True, capture_output=True))
            return result
        with patch.object(session, 'execute', side_effect=intercept):
            session.run_leg(['subcodex', 'review'], env={}, directory=self.output,
                            repo=self.repo, task=task, bin_dir=self.tools)
        self.assertEqual(len(attacks), 1)
        self.assertNotEqual(attacks[0].returncode, 0, 'outside process rewrote result')
        self.assertEqual((self.output / 'report.md').read_text(), 'Conclusion: BLOCK\n')

    def test_outside_account_cannot_enter_a_live_job_through_proc(self):
        import _leg_session as session
        import time
        with session.tools(self.tools) as (selected, root, bundle, env):
            work = root / 'work'
            if not work.exists():
                work.mkdir(mode=0o700)
                os.chown(work, self.uid, self.gid)
            view = Path(json.loads(Path(env['AIWORK_ACCOUNT_SETUP']).read_text())['view']) \
                if 'AIWORK_ACCOUNT_SETUP' in env else root
            outcomes = []
            def invoke():
                outcomes.append(session.execute(selected, ['/bin/sh', '-c',
                    'echo ready > "$1"; sleep 3', 'live-job', work / 'ready'], env=env, cwd=work))
            thread = threading.Thread(target=invoke)
            thread.start()
            try:
                deadline = time.monotonic() + 2
                while not (work / 'ready').exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue((work / 'ready').exists(), 'job failed to start')
                processes = []
                for entry in Path('/proc').iterdir():
                    if entry.name.isdigit():
                        try:
                            if (entry.stat().st_uid == self.uid and
                                    os.readlink(entry / 'cwd') == str(view / 'work')):
                                processes.append(entry)
                        except (FileNotFoundError, PermissionError, ProcessLookupError):
                            pass
                self.assertTrue(processes)
                for entry in processes:
                    access = subprocess.run(['/usr/bin/setpriv', '--reuid=' + str(self.uid),
                        '--regid=' + str(self.gid), '--clear-groups', '/bin/sh', '-c',
                        'test ! -r "$1" && ! readlink "$2/0" >/dev/null 2>&1', 'outside-proc',
                        str(entry / 'root' / str(view / 'work/ready').lstrip('/')),
                        str(entry / 'fd')], text=True, capture_output=True)
                    self.assertEqual(access.returncode, 0, 'outside account can enter live job')
            finally:
                thread.join(timeout=10)
            self.assertFalse(thread.is_alive())
            self.assertEqual(outcomes[0].returncode, 0, outcomes[0].stderr)

    def test_persistent_cli_configuration_is_not_a_future_job_input(self):
        import _leg_session as session
        (self.home / '.config/aiwork/models.env').write_text('cursor=grok-4.7-high\n')
        (self.profile / 'models.env').write_text('cursor=gpt-6-sol\n')
        (self.home / '.codex').mkdir()
        (self.home / '.codex/config.toml').write_text('poisoned persistent config')
        (self.home / '.codex/auth.json').write_text('{"fixture":"initial"}')
        for path in (self.home / '.codex').rglob('*'):
            os.chown(path, self.uid, self.gid)
        os.chown(self.home / '.codex', self.uid, self.gid)
        with patch.dict(os.environ):
            os.environ.pop('CURSOR_MODEL', None)
            self.assertEqual(session.choose_leg('subcursor', self.tools), ('openai', 'gpt-6-sol'))
        task = self.output / 'task.md'
        task.write_text('fixture')
        probe = self.tools / 'subcodex'
        probe.write_text('''#!/bin/sh
set -eu
test ! -e "$HOME/.codex/config.toml"
test -f "$HOME/.codex/auth.json"
printf '{"fixture":"renewed"}' > "$HOME/.codex/auth.json"
''')
        probe.chmod(0o755)
        result = session.run_leg(['subcodex', 'review'], env={}, directory=self.output,
                                 repo=self.repo, task=task, bin_dir=self.tools)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((self.home / '.codex/auth.json').read_text()), {'fixture': 'renewed'})
        self.assertEqual((self.home / '.codex/config.toml').read_text(), 'poisoned persistent config')

    def test_cli_supervisor_runs_only_as_the_ordinary_account(self):
        import _leg_session as session
        with session.tools(self.tools) as (selected, root, bundle, env):
            result = session.execute(selected,
                [self.profile / 'programs/python3', bundle / '_leg_session.py',
                 '--account-cli', '/usr/bin/id', '-u'], env=env, cwd=selected.pw_dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(self.uid))

    def test_cli_timeout_closes_its_output_pipeline(self):
        import _leg_session as session
        import time
        with session.tools(self.tools) as (selected, root, bundle, env):
            started = time.monotonic()
            result = session.execute(selected, ['/bin/bash', '-o', 'pipefail', '-c',
                '"$1" 1 "$2" "$3" --account-cli /bin/sleep 20 | /bin/cat', 'cancel-cli',
                bundle / 'aiwork-timeout', self.profile / 'programs/python3', bundle / '_leg_session.py'],
                env=env, cwd=selected.pw_dir)
            self.assertEqual(result.returncode, 124, result.stderr)
            self.assertLess(time.monotonic() - started, 5, 'cancelled CLI still holds stdout')

    def test_cursor_detached_worker_does_not_hold_the_pipeline_open(self):
        self.cursor_worker = True
        import time
        started = time.monotonic()
        self.test_all_registered_adapters_run_as_the_ordinary_account()
        self.assertLess(time.monotonic() - started, 15, 'Cursor worker held pipeline open')

    def test_missing_or_root_account_fails_closed(self):
        import _leg_session as account
        import pwd
        (self.config / 'review-user.env').unlink()
        with self.assertRaises((OSError, ValueError)):
            account.account()
        (self.config / 'review-user.env').write_text('user=root\n')
        with patch('pwd.getpwnam', return_value=pwd.struct_passwd(('root', 'x', 0, 0, '', str(self.publisher), '/bin/bash'))):
            with self.assertRaises(ValueError):
                account.account()

    def test_readable_publisher_home_is_rejected(self):
        import _leg_session as account
        self.publisher.chmod(0o755)
        with self.assertRaisesRegex(ValueError, '隔离预检'):
            with account.tools(self.tools):
                self.fail('must not start a leg')

    def test_leg_cannot_own_the_account_selection_file(self):
        import _leg_session as account
        os.chown(self.config / 'review-user.env', self.uid, self.gid)
        with self.assertRaisesRegex(ValueError, '配置须由发布账号'):
            account.account()

    def test_role_configuration_is_not_executed_when_owned_by_the_leg(self):
        import _leg_session as account
        role = self.config / 'apps/review.env'
        marker = self.publisher / 'untrusted-role-ran'
        role.write_text('KEY=' + str(self.key) + '\ntouch ' + str(marker) + '\n')
        os.chown(role, self.uid, self.gid)
        with self.assertRaisesRegex(ValueError, '角色配置'):
            with account.tools(self.tools):
                pass
        self.assertFalse(marker.exists())

    def test_registered_keys_are_never_copied_as_public_runtime_tools(self):
        import _leg_session as account
        moved = self.tools / 'credential'
        self.key.rename(moved)
        (self.config / 'apps/review.env').write_text('KEY=' + str(moved) + '\n')
        with account.tools(self.tools) as (_, _, bundle, _):
            self.assertFalse((bundle / moved.name).exists())
            self.assertFalse((bundle / 'review-pr').exists())
            self.assertFalse((bundle / 'gh-app-token').exists())
        self.assertEqual(moved.read_text(), 'disposable publisher key')
        os.link(moved, self.tools / 'alias')
        with self.assertRaisesRegex(ValueError, '独立普通文件'):
            with account.tools(self.tools):
                self.fail('hardlinked credential must not be copied')

    def test_links_fifos_and_hardlinked_results_are_not_collected(self):
        import _leg_session as session
        task = self.output / 'task.md'
        task.write_text('fixture')
        probe = self.tools / 'subcodex'
        for kind, operation in (
                ('symlink', 'os.symlink(' + repr(str(self.record)) + ', report)'),
                ('fifo', 'os.mkfifo(report)'),
                ('hardlink', "pathlib.Path('payload').write_text('fixture'); os.link('payload', report)")):
            with self.subTest(kind=kind):
                probe.write_text('#!/usr/bin/python3\nimport os,pathlib\n'
                                 "report = os.environ['AIWORK_REVIEW_REPORT_PATH']\n" + operation + '\n')
                probe.chmod(0o755)
                with self.assertRaises((OSError, ValueError)):
                    session.run_leg_attempt('subcodex', 'openai', task, self.repo,
                        self.output, dict(os.environ), 'fixture-run', None, bin_dir=self.tools)
                self.assertEqual(self.record.read_text(), 'previous result')

    def test_leg_owned_source_is_not_accepted_as_readonly(self):
        import _leg_session as account
        with account.tools(self.tools) as (selected, root, bundle, env):
            work = root / 'work'
            os.chown(work, self.uid, self.gid)
            result = account.execute(selected, [bundle / 'ro-repo-exec', work, '--', '/bin/true'],
                                     env=env, cwd=work)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('只读保护', result.stderr)


class ReliabilityTests(unittest.TestCase):
    def setUp(self):
        self.review = load_script()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.run_count = 0
        self.repo = self.directory / 'repo'
        self.repo.mkdir()
        for args in [('init', '-q'), ('config', 'user.name', 'Test'),
                     ('config', 'user.email', 'test@example.invalid')]:
            self.git(*args)
        (self.repo / 'file').write_text('base\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        self.base = self.git('rev-parse', 'HEAD').strip()
        (self.repo / 'file').write_text('base\n' + DIFF_MARKER + '\n')
        self.git('commit', '-qam', 'change')
        self.head = self.git('rev-parse', 'HEAD').strip()
        self.diff = self.git('diff', self.base, self.head)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True)

    def server(self, responses):
        payloads = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                payloads.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
                response = responses[min(len(payloads) - 1, len(responses) - 1)]
                self.send_response(response.get('_status', 200))
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())

        server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f'http://127.0.0.1:{server.server_port}', payloads

    def run_review(self, leg='subdeepseek-agent', *, responses=None, env=None,
                   fake_attempts=None, missing_agent=False, files=None, changes=None,
                   on_leg=None, snapshot_side_effect=None):
        """Run the real publisher, leg, chat engine and result producer offline."""
        default_response = [
            {'choices': [{'message': {'content': 'Checked file.\nConclusion: PASS'},
                          'finish_reason': 'stop'}]}]
        endpoint, payloads = ('http://127.0.0.1:1', []) if fake_attempts is not None else self.server(responses or default_response)
        pr = {'state': 'open', 'head': {'sha': self.head, 'ref': 'feature'},
              'base': {'sha': self.base, 'ref': 'main'}}
        posted = []
        real_run = sys.modules["_leg_session"].run
        real_subprocess_run = subprocess.run
        bin_dir = BIN
        self.leg_calls = []
        self.seen_tasks = []
        ci = CiFixture(head=self.head, number=1)
        self.ci_reads = ci.reads
        if fake_attempts is not None:
            self.run_count += 1
            bin_dir = self.directory / f'bin-{self.run_count}'
            bin_dir.mkdir()
            write_platform_probe(bin_dir)
            for adapter in BIN.glob('sub*'):
                name = adapter.name
                if missing_agent and name == leg + '-agent':
                    continue
                (bin_dir / name).touch()
            for helper in ('_python', '_programs.sh', '_review_result.py'):
                shutil.copy2(BIN / helper, bin_dir / helper)
            (bin_dir / 'privacy-check').symlink_to(BIN / 'privacy-check')

        def invoke(command, **kwargs):
            is_leg = Path(command[0]).parent == bin_dir and Path(command[0]).name.startswith('sub')
            if is_leg and on_leg is not None:
                on_leg(len(self.leg_calls), Path(command[2]), Path(command[4]))
            if is_leg:
                self.leg_calls.append((Path(command[0]).name, kwargs['env'].copy()))
                self.seen_tasks.append(Path(command[2]).read_text(encoding='utf-8'))
            if fake_attempts is None or not is_leg:
                return real_subprocess_run(command, **kwargs)
            name = Path(command[0]).name
            attempt = fake_attempts[min(len(self.leg_calls) - 1, len(fake_attempts) - 1)]
            model = {'subdeepseek-agent': 'deepseek-flash',
                     'subcursor': 'gpt-6-sol', 'subcodex': 'gpt-6-sol',
                     'submimo': 'mimo-v2.6-pro', 'subkimi': 'kimi-code/kimi-for-coding'}[name]
            report_text = attempt.get('report', 'Conclusion: PASS')
            log_text = attempt.get('log')
            if log_text is None:
                log_text = '# fixture review log\n\n' + report_text + '\n'
            Path(command[3]).write_text(log_text)
            report_path = kwargs['env'].get('AIWORK_REVIEW_REPORT_PATH')
            if report_path and attempt.get('write_report', True):
                Path(report_path).write_text(report_text)
            facts_cmd = [sys.executable, str(BIN / '_review_result.py'), 'facts', '--output',
                         kwargs['env']['AIWORK_REVIEW_FACTS_PATH'], '--requested-model', model,
                         '--invoked-model', model, '--view-delivery-state', 'complete',
                         '--view-mode', 'full_snapshot', '--billing-mode', 'api']
            if 'failure' in attempt:
                facts_cmd += ['--failure-kind', attempt['failure']]
            real_subprocess_run(facts_cmd, check=True, capture_output=True)
            return subprocess.CompletedProcess(command, attempt.get('exit', 0), '', attempt.get('stderr', ''))

        def run(command, **kwargs):
            if command[0].endswith('/gh-app-token'):
                return 'fixture-token'
            return real_run(command, **kwargs)

        def github(token, endpoint, payload=None, **kwargs):
            if payload is None:
                return ci.api(endpoint, **kwargs)
            posted.append(payload)
            return {'html_url': 'https://github.com/example/repo/pull/1#pullrequestreview-1'}

        clean = {k: v for k, v in os.environ.items() if not k.startswith(
            ('MIMO_', 'DEEPSEEK_', 'ZHIPU_', 'SUBCODEX_', 'CURSOR_', 'KIMI_'))}
        clean.update(DEEPSEEK_API_KEY='fixture-key',
                     DEEPSEEK_API_BASE=endpoint, CURSOR_MODEL='gpt-6-sol',
                     AIWORK_DATA_DIR=str(self.directory / 'data'))
        clean.update(env or {})
        Path(clean['AIWORK_DATA_DIR']).mkdir(parents=True, exist_ok=True)
        if snapshot_side_effect is None:
            snapshot_return = (
                self.repo, self.base, files or ['file'], self.diff,
                changes if changes is not None else [
                    self.review.Change('M', (files or ['file'])[0], None, 1, 0)])

            def snapshot_side_effect(*_args, **_kwargs):
                return snapshot_return
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.dict(os.environ, clean, clear=True), \
                patch('sys.argv', ['review-pr', '1', '--repo', 'example/repo', '--leg', leg]), \
                patch.object(sys.modules['_leg_session'], 'run', side_effect=run), \
                patch.object(self.review, 'pr_state', return_value=pr), \
                patch.object(sys.modules['_leg_session'], 'snapshot',
                             side_effect=snapshot_side_effect), \
                patch.object(self.review, 'aiwork_main_rules', return_value=('d' * 40, 'Trusted rules.')), \
                patch.object(self.review, 'main_document', side_effect=lambda repo, path, **kwargs:
                             json.dumps(CI_POLICY) if path == '.aiwork/policy.json' else '无'), \
                patch.object(self.review, 'github', side_effect=github), \
                patch.object(self.review, 'BIN', bin_dir), \
                patch.object(self.review, 'aiwork_main_commit', return_value='d' * 40), \
                patch.object(self.review, 'require_latest_aiwork_main'), \
                patch.object(self.review.subprocess, 'run', side_effect=invoke), \
                redirect_stdout(stdout), redirect_stderr(stderr):
            rc = self.review.main()
        return rc, payloads, posted, stdout.getvalue(), stderr.getvalue()

    def test_review_pr_puts_the_diff_in_the_reader_task_once(self):
        rc, payloads, posted, _, stderr = self.run_review('subdeepseek-agent', fake_attempts=[{}])
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(payloads, [])
        self.assertEqual(self.seen_tasks[0].count(DIFF_MARKER), 1)
        self.assertIn('✅ G1 CI(ci.yml)在当前 head 上通过', self.seen_tasks[0])
        self.assertIn('existing-suite', self.seen_tasks[0])
        self.assertTrue(any(options.get('raw') for _, options in self.ci_reads))
        self.assertEqual(len(posted), 1)

    def test_conclusion_requirement_is_after_full_diff_at_task_end(self):
        pr = {'head': {'sha': self.head, 'ref': 'feature'},
              'base': {'sha': self.base, 'ref': 'main'}}
        padded = self.diff + 'x\n' * 75000
        task = self.review.task_text(1, pr, self.base, ['file'], padded,
                                     'Trusted rules.', '无', rules_sha='d' * 40, repository='SunJ1ayu/aiwork')
        requirement = self.review.CONCLUSION_REQUIREMENT
        self.assertTrue(task.endswith(requirement + "\n"))
        self.assertGreater(task.rfind(requirement), task.rfind('```'))
        self.assertEqual(
            [line for line in requirement.splitlines() if line.startswith("Conclusion:")],
            ["Conclusion: PASS", "Conclusion: BLOCK", "Conclusion: NEEDS_MORE_INFO"],
        )

    def whole_file_deletion_view(self):
        marker = 'DELETED_PAYLOAD_9f3c'
        count = (200 * 1024) // (len(marker) + 1) + 80
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True, text=True)
            git('init', '-q')
            git('config', 'user.name', 'Test')
            git('config', 'user.email', 'test@example.invalid')
            (repo / 'gone.txt').write_text((marker + '\n') * count)
            git('add', 'gone.txt')
            git('commit', '-qm', 'add')
            base = git('rev-parse', 'HEAD').stdout.strip()
            git('rm', '-q', 'gone.txt')
            git('commit', '-qm', 'delete')
            head = git('rev-parse', 'HEAD').stdout.strip()
            full = git('diff', '--binary', '--no-ext-diff', '--find-renames', base, head).stdout
            files, diff, changes = sys.modules['_leg_session'].collect_review_diff(repo, base, head)
        return full, files, diff, changes, count


    def test_large_deletion_reader_points_at_the_snapshot_diff(self):
        full, files, diff, changes, count = self.whole_file_deletion_view()
        self.diff = diff
        limit = self.review.READER_INLINE_DIFF_BYTES
        self.assertIn('DELETED_PAYLOAD_9f3c', full)
        self.assertGreater(len(diff.encode()), limit)
        rc, payloads, posted, _, stderr = self.run_review(
            'subdeepseek-agent', files=files, changes=changes, fake_attempts=[{}])
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(payloads, [])
        self.assertEqual(self.leg_calls[0][0], 'subdeepseek-agent')
        task = self.seen_tasks[0]
        self.assertLessEqual(len(task.encode()), limit)
        self.assertNotIn('DELETED_PAYLOAD_9f3c', task)
        self.assertNotIn('git diff ', task)
        self.assertNotIn('不要把', task)
        self.assertNotIn('整文件删除', task)
        self.assertIn(f'- D {json.dumps("gone.txt")} +0 -{count}', task)
        self.assertIn('DELETED_PAYLOAD_9f3c', (self.repo / self.review.REVIEW_DIFF_PATH).read_text())
        block = json.loads(posted[0]['body'].split('```json\n')[1].split('\n```')[0])
        self.assertEqual(block['completeness'], 'complete')

    def test_reader_under_the_limit_still_receives_the_inline_diff(self):
        rc, _, posted, _, stderr = self.run_review('subdeepseek-agent', fake_attempts=[{}])
        self.assertEqual(rc, 0, stderr)
        self.assertIn(DIFF_MARKER, self.seen_tasks[0])
        self.assertNotIn('不内联', self.seen_tasks[0])
        self.assertFalse((self.repo / self.review.REVIEW_DIFF_PATH).exists())
        block = json.loads(posted[0]['body'].split('```json\n')[1].split('\n```')[0])
        self.assertEqual(block['completeness'], 'complete')

    def test_all_repository_readers_keep_fallbacks_unless_caller_overrides(self):
        config = write_settings(self.directory / 'settings')
        for leg, option, variable, _, reader, _ in RUNTIME_CASES:
            for override in (None, '', '317'):
                with self.subTest(leg=leg, override=override):
                    if option == 'effort' and override:
                        override = 'xhigh'
                    env = {'AIWORK_CONFIG_DIR': str(config)}
                    if override is not None:
                        env[variable] = override
                    rc, _, posted, _, stderr = self.run_review(leg, env=env, fake_attempts=[{}])
                    self.assertEqual(rc, 0, stderr)
                    self.assertEqual(self.leg_calls[0][1].get(variable), override or reader)
                    self.assertEqual(len(posted), 1)

    def test_reader_runtime_file_and_environment_reach_all_legs(self):
        config = write_settings(self.directory / 'settings')
        configured = {variable: sample for _, _, variable, _, _, sample in RUNTIME_CASES}
        (config / 'runtime.env').write_text(''.join(f'{k}={v}\n' for k,v in configured.items()))
        for override in (False, True):
            env = {'AIWORK_CONFIG_DIR': str(config)}
            expected = configured
            if override:
                expected = {variable: 'xhigh' if option == 'effort' else '7201'
                            for _, option, variable, *_ in RUNTIME_CASES}
                env.update(expected)
            for leg in dict.fromkeys(row[0] for row in RUNTIME_CASES):
                with self.subTest(leg=leg, override=override):
                    rc, _, posted, _, stderr = self.run_review(leg, env=env, fake_attempts=[{}])
                    self.assertEqual(rc, 0, stderr)
                    self.assertEqual(len(posted), 1)
                    for adapter, _, variable, *_ in RUNTIME_CASES:
                        if adapter == leg:
                            self.assertEqual(self.leg_calls[0][1].get(variable), expected[variable])

    def test_bad_runtime_setting_stops_review_without_invocation_or_publication(self):
        config = write_settings(self.directory / 'settings')
        for bad_file in (True, False):
            with self.subTest(bad_file=bad_file):
                (config / 'runtime.env').write_text('MIMO_TIMEOUT=bad\n' if bad_file else '')
                env = {'AIWORK_CONFIG_DIR': str(config), 'MIMO_TIMEOUT': '7201' if bad_file else 'bad'}
                rc, _, posted, _, stderr = self.run_review('submimo', env=env, fake_attempts=[{}])
                self.assertEqual(rc, 1)
                self.assertEqual(self.leg_calls, [])
                self.assertEqual(posted, [])
                self.assertIn(str(config / 'runtime.env') if bad_file else 'environment MIMO_TIMEOUT', stderr)
                self.assertNotIn('Traceback', stderr)

    def test_last_message_without_conclusion_is_not_published(self):
        earlier = 'P1 remains.\n\nConclusion: BLOCK\n'
        last = '补充核对完毕，判断不变。'
        log = '# fixture review log\n\n' + earlier + '\n' + last + '\n'
        rc, _, posted, _, stderr = self.run_review(
            'subkimi', fake_attempts=[{'log': log, 'report': last, 'exit': 0}])
        self.assertEqual(rc, 1, stderr)
        self.assertEqual(posted, [])
        self.assertIn('no_verdict', stderr)
        self.assertIn('verdict=UNKNOWN', stderr)
        self.assertEqual(len(self.leg_calls), 2)

    def test_reader_missing_conclusion_retries_using_fresh_artifacts(self):
        attempts = [{'report': 'No conclusion.', 'failure': 'no_verdict', 'exit': 1}, {}]
        rc, _, posted, _, stderr = self.run_review('subcursor', fake_attempts=attempts)
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(len(self.leg_calls), 2)
        self.assertNotEqual(self.leg_calls[0][1]['AIWORK_REVIEW_FACTS_PATH'],
                            self.leg_calls[1][1]['AIWORK_REVIEW_FACTS_PATH'])
        self.assertIn('retry 2/2', posted[0]['body'])
        body = posted[0]['body']
        self.assertLess(body.index('**Execution:**'), body.index('Conclusion: PASS'))
        self.assertNotIn('**Execution:**', body.split('Conclusion: PASS', 1)[1].split('```json', 1)[0])

    def test_retry_second_leg_does_not_see_what_the_first_leg_wrote(self):
        for failure in ('no_verdict', 'output_truncated'):
            with self.subTest(failure=failure):
                seen = []

                def side_effect(token, pr, directory, *, repository):
                    repo = Path(directory) / 'repo'
                    repo.mkdir()
                    return (repo, self.base, ['file'], self.diff, [
                        self.review.Change('M', 'file', None, 1, 0)])

                def on_leg(index, task, repo):
                    seen.append({
                        'repo': repo,
                        'task_path': task,
                        'task': task.read_text(encoding='utf-8'),
                        'marker': (repo / 'leg-marker').is_file(),
                    })
                    if index == 0:
                        (repo / 'leg-marker').write_text('touched-by-first-leg\n')
                        task.write_text(
                            task.read_text(encoding='utf-8') + '\nLEG_TOUCHED_MARKER\n',
                            encoding='utf-8')

                rc, _, posted, _, stderr = self.run_review(
                    'subcursor',
                    fake_attempts=[
                        {'report': 'No conclusion.', 'failure': failure, 'exit': 1},
                        {},
                    ],
                    snapshot_side_effect=side_effect,
                    on_leg=on_leg,
                )
                self.assertFalse(
                    seen[1]['marker'],
                    'second leg still sees the marker the first leg wrote into its snapshot')
                self.assertNotIn('LEG_TOUCHED_MARKER', seen[1]['task'])
                self.assertEqual(seen[0]['task'], seen[1]['task'])
                self.assertNotEqual(seen[0]['repo'], seen[1]['repo'])
                self.assertNotEqual(seen[0]['task_path'], seen[1]['task_path'])
                self.assertEqual((rc, len(posted), len(seen)), (0, 1, 2), stderr)

    def test_retry_second_snapshot_keeps_the_full_diff_file(self):
        payload = 'RETRY_DIFF_PAYLOAD_9f3c\n'
        diff = payload * ((self.review.READER_INLINE_DIFF_BYTES // len(payload)) + 2)
        self.assertGreater(len(diff.encode()), self.review.READER_INLINE_DIFF_BYTES)
        change = self.review.Change('M', 'file', None, 1, 0)
        seen = []

        def side_effect(token, pr, directory, *, repository):
            repo = Path(directory) / 'repo'
            repo.mkdir()
            subprocess.check_call(['git', 'init', '-q', str(repo)])
            return (repo, self.base, ['file'], diff, [change])

        def on_leg(index, task, repo):
            diff_path = repo / self.review.REVIEW_DIFF_PATH
            seen.append({
                'repo': repo,
                'task': task.read_text(encoding='utf-8'),
                'diff': diff_path.read_bytes() if diff_path.is_file() else None,
            })
            if index == 0:
                diff_path.write_bytes(b'truncated-by-leg\n')

        rc, _, posted, _, stderr = self.run_review(
            'subcursor',
            fake_attempts=[
                {'report': 'No conclusion.', 'failure': 'no_verdict', 'exit': 1},
                {},
            ],
            snapshot_side_effect=side_effect,
            on_leg=on_leg,
        )
        self.assertEqual(seen[1]['diff'], diff.encode(),
                         'second leg does not see the full snapshot diff file')
        self.assertNotIn(payload.strip(), seen[1]['task'])
        self.assertIn(self.review.REVIEW_DIFF_PATH, seen[1]['task'])
        self.assertEqual(seen[0]['task'], seen[1]['task'])
        self.assertNotEqual(seen[0]['repo'], seen[1]['repo'])
        self.assertEqual((rc, len(posted), len(seen)), (0, 1, 2), stderr)

    def test_retry_is_refused_when_the_fresh_view_cannot_be_rebuilt(self):
        calls = {'n': 0}

        def side_effect(token, pr, directory, *, repository):
            calls['n'] += 1
            if calls['n'] > 1:
                raise self.review.ReviewError('fetch failed: simulated')
            repo = Path(directory) / 'repo'
            repo.mkdir()
            return (repo, self.base, ['file'], self.diff, [
                self.review.Change('M', 'file', None, 1, 0)])

        rc, _, posted, _, stderr = self.run_review(
            'subcursor',
            fake_attempts=[
                {'report': 'No conclusion.', 'failure': 'no_verdict', 'exit': 1},
                {},
            ],
            snapshot_side_effect=side_effect,
        )
        self.assertEqual(rc, 1, stderr)
        self.assertEqual(posted, [])
        self.assertEqual(len(self.leg_calls), 1)
        self.assertIn('retry refused after no_verdict', stderr)
        self.assertIn('fetch failed: simulated', stderr)
        self.assertNotIn('retry 2/2', stderr)

    def test_retry_is_refused_when_the_rebuilt_snapshot_does_not_match(self):
        calls = {'n': 0}

        def side_effect(token, pr, directory, *, repository):
            calls['n'] += 1
            repo = Path(directory) / 'repo'
            repo.mkdir()
            diff = self.diff if calls['n'] == 1 else self.diff + '\nnot-the-same\n'
            return (repo, self.base, ['file'], diff, [
                self.review.Change('M', 'file', None, 1, 0)])

        rc, _, posted, _, stderr = self.run_review(
            'subcursor',
            fake_attempts=[
                {'report': 'No conclusion.', 'failure': 'no_verdict', 'exit': 1},
                {},
            ],
            snapshot_side_effect=side_effect,
        )
        self.assertEqual(rc, 1, stderr)
        self.assertEqual(posted, [])
        self.assertEqual(len(self.leg_calls), 1)
        self.assertIn('retry refused after no_verdict', stderr)
        self.assertIn('does not match', stderr)
        self.assertIn('diff', stderr)

    def test_missing_report_file_is_not_published(self):
        rc, _, posted, _, stderr = self.run_review('subkimi', fake_attempts=[{'write_report': False}])
        self.assertEqual(rc, 1, stderr)
        self.assertEqual(posted, [])
        self.assertIn('no_verdict', stderr)
        self.assertIn('verdict=UNKNOWN', stderr)

    def test_rate_limit_without_a_report_names_the_failure(self):
        rc, _, posted, _, stderr = self.run_review(
            'subkimi', fake_attempts=[{
                'failure': 'rate_limit', 'exit': 1, 'write_report': False,
                'log': '# fixture review log\n',
            }])
        self.assertEqual(rc, 1, stderr)
        self.assertEqual(posted, [])
        self.assertEqual(len(self.leg_calls), 1)
        self.assertIn('rate_limit', stderr)
        self.assertNotIn('did not write the report file', stderr)

    def test_published_body_is_the_report_file_not_the_leg_log(self):
        last = 'Findings.\n\nConclusion: PASS'
        log = ('# fixture review log\n\n## 过程\n'
               '```python\n# 注释\nconclusion: pending ? null : value\n```\n'
               "  → Bash sed -n '1,20p' gate/decide.mjs\n"
               'kimi> \nConclusion: BLOCK\n')
        rc, _, posted, _, stderr = self.run_review('subkimi', fake_attempts=[{'log': log, 'report': last}])
        self.assertEqual(rc, 0, stderr)
        body = posted[0]['body']
        self.assertIn(last, body)
        self.assertNotIn('## 过程', body)
        self.assertNotIn('pending ? null', body)
        self.assertNotIn('Conclusion: BLOCK', body)
        block = json.loads(body.split('```json\n', 1)[1].split('\n```', 1)[0])
        self.assertEqual(block['verdict'], 'PASS')

    def test_other_reader_failures_are_never_retried(self):
        for failure in ('auth', 'quota', 'rate_limit', 'timeout', 'runtime',
                        'identity_mismatch', 'snapshot', 'unknown', 'readonly_tools'):
            with self.subTest(failure=failure):
                rc, _, posted, _, stderr = self.run_review('subcursor', fake_attempts=[
                    {'failure': failure, 'exit': 1}])
                self.assertEqual(rc, 1)
                self.assertEqual((len(self.leg_calls), posted), (1, []))
                self.assertNotIn('retry 2/2', stderr)

class FailureArchiveTests(unittest.TestCase):
    def setUp(self):
        self.review = load_script()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.source = self.directory / 'source'
        self.source.mkdir(mode=0o700)
        self.archives = self.directory / 'data/review-failures'
        self.addCleanup(patch.stopall)
        patch.object(self.review, 'data_path', return_value=self.archives).start()

    def test_failure_archive_keeps_diagnostics_without_repo_or_askpass(self):
        files = ('task.md', 'review.log', 'leg.stderr', 'facts.json', 'result.json',
                 'review.stream.jsonl')
        for name in files:
            (self.source / name).write_text('diagnostic ' + name)
        (self.source / 'repo').mkdir()
        (self.source / 'repo/checkout.txt').write_text('repository snapshot')
        (self.source / 'askpass').write_text('credential helper')
        with redirect_stderr(io.StringIO()):
            self.review.report_failure(self.source, 'new-failure')
        archive = self.archives / 'new-failure'
        self.assertEqual({p.name for p in archive.iterdir()}, set(files))
        for name in files:
            self.assertEqual((archive / name).read_bytes(), (self.source / name).read_bytes())
        self.assertTrue((self.source / 'repo/checkout.txt').exists())
        self.assertTrue((self.source / 'askpass').exists())

    def test_failure_archives_have_no_separate_count_limit(self):
        self.archives.mkdir(parents=True)
        previous = []
        for index in range(24):
            archive = self.archives / f'run-{24 - index:02d}'
            archive.mkdir()
            (archive / 'review.log').write_text(f'failure {index}')
            os.utime(archive, (index + 1, index + 1))
            previous.append(archive)
        (self.source / 'review.log').write_text('latest failure')
        os.utime(self.source, (0, 0))
        with redirect_stderr(io.StringIO()):
            self.review.report_failure(self.source, 'new-failure')
        remaining = {p.name for p in self.archives.iterdir()}
        self.assertEqual(remaining, {'new-failure', *(p.name for p in previous)})
        self.assertEqual(len(remaining), len(previous) + 1)
        self.assertEqual((self.archives / 'new-failure/review.log').read_text(), 'latest failure')


class ReaderFailureClassificationTests(LegCase):
    def test_real_readers_classify_completed_report_without_conclusion(self):
        self.copy('subdeepseek-agent', 'subagent', 'subkimi', 'ro-repo-exec')
        self.fake('claude', '#!/bin/sh\necho \'{"type":"assistant","message":{"content":[{"type":"text","text":"Checked the authentication code."}]}}\'\n')
        self.fake('kimi', '#!/bin/sh\necho "Checked the authentication code."\n')
        home = self.d / 'kimi-home'
        (home / 'hooks').mkdir(parents=True)
        (home / 'credentials').mkdir()
        write_kimi_config(home, self.config)
        shutil.copyfile(BIN.parent / 'kimi-review-home/hooks/guard.mjs', home / 'hooks/guard.mjs')
        (home / 'credentials/kimi-code.json').write_text('{}')
        for leg in ('subdeepseek-agent', 'subkimi'):
            with self.subTest(leg=leg):
                facts, log = self.d / (leg + '.json'), self.d / (leg + '.log')
                proc = self.run_cmd([str(self.bin / leg), 'review', str(self.task),
                                     str(log), str(self.repo)],
                                    AIWORK_REVIEW_FACTS_PATH=str(facts), AIWORK_REVIEW_PR='1',
                                    AIWORK_REVIEW_RESULT_BIN=str(self.bin / '_review_result.py'),
                                    DEEPSEEK_API_KEY='fixture',
                                    KIMI_REVIEW_HOME=str(home))
                self.assertNotEqual(proc.returncode, 0)
                self.assertIn('no verdict', proc.stderr, proc.stderr)
                self.assertIn('Checked the authentication code.', log.read_text())
                self.assertEqual(json.loads(facts.read_text())['failure_kind'], 'no_verdict')


if __name__ == '__main__':
    unittest.main()

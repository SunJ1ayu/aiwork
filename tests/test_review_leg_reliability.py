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
            original_command = command
            if command[0] == '/usr/bin/bwrap':
                command = command[command.index('--') + 1:]
                command = [str(bin_dir / Path(command[0]).name), *command[1:]]
            is_leg = Path(command[0]).parent == bin_dir and Path(command[0]).name.startswith('sub')
            if is_leg and on_leg is not None:
                on_leg(len(self.leg_calls), Path(command[2]), Path(command[4]))
            if is_leg:
                self.leg_calls.append((Path(command[0]).name, kwargs['env'].copy()))
                self.seen_tasks.append(Path(command[2]).read_text(encoding='utf-8'))
            if fake_attempts is None or not is_leg:
                return real_subprocess_run(original_command, **kwargs)
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


class PublisherIsolationTests(unittest.TestCase):
    def test_caller_beneath_another_users_private_parent(self):
        import _leg_session as session
        # Unlike /tmp, this tree is visible through the initial read-only root;
        # it reproduces sudo CI starting below the runner's private home.
        with tempfile.TemporaryDirectory(dir='/var/tmp') as name:
            root = Path(name)
            foreign = root / 'foreign'
            foreign.mkdir(mode=0o700)
            caller = foreign / 'checkout'
            caller.mkdir()
            (caller / 'marker').write_text('caller input')
            os.mkfifo(caller / 'control.fifo')
            settings = foreign / 'settings'
            shutil.copytree(os.environ['AIWORK_CONFIG_DIR'], settings, symlinks=True)
            data = foreign / 'data'
            data.mkdir()
            (data / 'marker').write_text('selected data')
            tools = foreign / 'tools'
            tools.mkdir()
            helper = foreign / 'runtime-helper'
            helper.write_text('#!/bin/sh\nprintf selected-tool\n')
            helper.chmod(0o755)
            (tools / 'caller-helper').symlink_to(helper)
            key = caller / 'publisher-key'
            key.write_text('disposable publisher key')
            apps = root / 'apps'
            apps.mkdir()
            (apps / 'review.env').write_text('KEY=' + str(key) + '\n')
            (foreign / 'unrelated').write_text('private sibling')
            os.chown(foreign, 65534, 65534)
            output = root / 'output'
            output.mkdir()
            repo = output / 'repo'
            repo.mkdir()
            task = output / 'check.py'
            task.write_text('''import os, pathlib, subprocess, sys
caller = pathlib.Path(sys.argv[1])
assert pathlib.Path.cwd() == caller
assert (caller / 'marker').read_text() == 'caller input'
import stat
assert not stat.S_ISFIFO((caller / 'control.fifo').stat().st_mode)
assert (pathlib.Path(os.environ['AIWORK_DATA_DIR']) / 'marker').read_text() == 'selected data'
assert subprocess.check_output(['caller-helper'], text=True) == 'selected-tool'
subprocess.run(['/bin/bash', '-c', '. "$1/_programs.sh"; aiwork_init subcodex',
                'bootstrap', str(pathlib.Path(os.environ['AIWORK_REVIEW_RESULT_BIN']).parent)], check=True)
try:
    assert not (caller / 'publisher-key').read_bytes()
except OSError:
    pass
assert not (caller.parent / 'unrelated').exists()
try:
    (caller / 'marker').write_text('changed')
except OSError:
    pass
else:
    raise AssertionError('caller snapshot writable')
''')
            previous = Path.cwd()
            try:
                os.chdir(caller)
                result = session.run_isolated_leg(
                    [sys.executable, str(task), str(caller)],
                    env=dict(os.environ, AIWORK_APPS_DIR=str(apps),
                             AIWORK_CONFIG_DIR='../settings', AIWORK_DATA_DIR='../data',
                             AIWORK_REVIEW_RESULT_BIN=str(BIN / '_review_result.py'),
                             PATH='../tools' + os.pathsep + os.environ['PATH']),
                    directory=output, repo=repo, task=task, bin_dir=BIN)
            finally:
                os.chdir(previous)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((caller / 'marker').read_text(), 'caller input')
            self.assertEqual(foreign.stat().st_uid, 65534)
            self.assertEqual(foreign.stat().st_mode & 0o777, 0o700)

    def test_caller_environment_survives_the_boundary_without_host_writes_or_ipc(self):
        import socket
        import _leg_session as session
        from _aiwork_config import RUNTIME_OPTIONS

        with tempfile.TemporaryDirectory() as name, socket.socket(socket.AF_UNIX) as control:
            root = Path(name)
            settings, data, home, kimi = (root / part for part in ('settings', 'data', 'home', 'kimi'))
            shutil.copytree(os.environ['AIWORK_CONFIG_DIR'], settings, symlinks=True)
            (settings / 'models.env').write_text('codex=gpt-6-sol-caller\n')
            (settings / 'runtime.env').write_text('SUBCODEX_EFFORT=xhigh\n')
            data.mkdir()
            (data / 'caller.marker').write_text('selected data')
            (data / 'stale').symlink_to('/absent-aiwork-test-target')
            control.bind(str(data / 'control.sock'))
            control.listen()
            (home / '.config/cursor').mkdir(parents=True)
            (home / '.config/cursor/auth.json').write_text('home login')
            (home / '.config/aiwork').symlink_to(settings, target_is_directory=True)
            (home / '.local/share').mkdir(parents=True)
            (home / '.local/share/aiwork').symlink_to(data, target_is_directory=True)
            (home / '.kimi-code/credentials').mkdir(parents=True)
            (home / '.kimi-code/credentials/kimi-code.json').write_text('kimi login')
            # The exact '~' form is supported by the bootstrap; its program and
            # settings links also exercise restoration of configuration aliases.
            for item in ('programs', 'models.env', 'runtime.env', 'apps'):
                (home / item).symlink_to(settings / item, target_is_directory=item in ('programs', 'apps'))
            (root / 'settings-alias').symlink_to(settings, target_is_directory=True)
            (root / 'login').mkdir()
            (root / 'login/cursor.json').write_text('explicit login')
            (root / 'xdg/cursor').mkdir(parents=True)
            (root / 'xdg/cursor/auth.json').write_text('xdg login')
            (root / 'caller-bin').mkdir()
            command = root / 'caller-bin/aiwork-caller-tool'
            command.write_text('#!/bin/sh\nprintf selected-tool\n')
            command.chmod(0o755)
            (kimi / 'hooks').mkdir(parents=True)
            (kimi / 'hooks/guard').write_text('selected guard')
            alias = root / 'kimi-alias'
            alias.symlink_to(kimi, target_is_directory=True)
            (kimi / 'config.json').write_text(json.dumps({'guard': str(alias / 'hooks/guard')}))
            (kimi / 'state').write_text('original')
            key = kimi / 'publisher-key'
            key.write_text('disposable publisher key')
            (settings / 'apps').mkdir(exist_ok=True)
            (settings / 'apps/review.env').write_text('KEY=' + str(key) + '\n')
            output = root / 'output'
            output.mkdir()
            repo = output / 'repo'
            repo.mkdir()
            task = output / 'observe.py'
            task.write_text('''import json, os, pathlib, socket, subprocess, sys
tools = pathlib.Path(os.environ['AIWORK_REVIEW_RESULT_BIN']).parent
sys.path.insert(0, str(tools))
from _aiwork_config import RUNTIME_OPTIONS, data_dir, model, runtime_value
assert pathlib.Path.cwd() == pathlib.Path(sys.argv[1])
for leg in RUNTIME_OPTIONS:
    subprocess.run(['/bin/bash', '-c', '. "$1/_programs.sh"; aiwork_init "$2"',
                    'bootstrap', str(tools), leg], check=True)
assert model('codex') == 'gpt-6-sol-caller'
assert runtime_value('subcodex', 'effort') == 'xhigh'
assert (data_dir() / 'caller.marker').read_text() == 'selected data'
auth = pathlib.Path(os.environ.get('CURSOR_AUTH_FILE') or
                    str(pathlib.Path(os.environ.get('XDG_CONFIG_HOME') or os.environ['HOME'] + '/.config') / 'cursor/auth.json'))
assert auth.read_text() == sys.argv[2]
assert (pathlib.Path(os.environ['HOME']) / '.kimi-code/credentials/kimi-code.json').read_text() == 'kimi login'
assert subprocess.check_output(['aiwork-caller-tool'], text=True) == 'selected-tool'
runtime = pathlib.Path(os.environ['KIMI_REVIEW_HOME'])
assert pathlib.Path(json.loads((runtime / 'config.json').read_text())['guard']).read_text() == 'selected guard'
assert (runtime / 'state').read_text() == 'original'
if os.environ.get('AIWORK_LEG_ISOLATED'):
    with socket.socket(socket.AF_UNIX) as connection:
        try:
            connection.connect(str(data_dir() / 'control.sock'))
        except OSError:
            pass
        else:
            raise AssertionError('outer control socket exposed')
    assert not (runtime / 'publisher-key').is_file()
    (runtime / 'state').write_text('private update')
    try:
        (data_dir() / 'caller.marker').write_text('injected')
    except OSError:
        pass
    else:
        raise AssertionError('caller data is writable')
    (pathlib.Path(sys.argv[3]) / 'report.md').write_text('Conclusion: PASS\\n')
''')
            previous = Path.cwd()
            try:
                os.chdir(root)
                for configured in (None, '', 'settings', './settings', 'settings-alias',
                                   '~/../settings', '~', str(settings)):
                    for auth_mode in ('explicit', 'xdg', 'home'):
                        with self.subTest(settings=configured, authentication=auth_mode):
                            env = dict(os.environ, HOME='home', AIWORK_DATA_DIR='data',
                                       AIWORK_APPS_DIR='settings/apps', KIMI_REVIEW_HOME='kimi-alias',
                                       AIWORK_REVIEW_RESULT_BIN=str(BIN / '_review_result.py'),
                                       PATH='caller-bin' + os.pathsep + os.environ['PATH'])
                            for options in RUNTIME_OPTIONS.values():
                                for variable, *_ in options.values():
                                    env.pop(variable, None)
                            for variable in ('AIWORK_CONFIG_DIR', 'CURSOR_AUTH_FILE', 'XDG_CONFIG_HOME'):
                                env.pop(variable, None)
                            if configured is not None:
                                env['AIWORK_CONFIG_DIR'] = configured
                            if auth_mode == 'explicit':
                                env['CURSOR_AUTH_FILE'] = 'login/cursor.json'
                            elif auth_mode == 'xdg':
                                env['XDG_CONFIG_HOME'] = 'xdg'
                            expected = {'explicit': 'explicit login', 'xdg': 'xdg login', 'home': 'home login'}[auth_mode]
                            arguments = [sys.executable, str(task), str(root), expected, str(output)]
                            direct = subprocess.run(arguments, env=env, text=True, capture_output=True)
                            self.assertEqual(direct.returncode, 0, direct.stderr)
                            isolated = session.run_isolated_leg(arguments, env=env, directory=output,
                                                                repo=repo, task=task, bin_dir=BIN)
                            self.assertEqual(isolated.returncode, 0, isolated.stderr)
                            self.assertEqual((kimi / 'state').read_text(), 'original')
                            self.assertEqual((data / 'caller.marker').read_text(), 'selected data')
            finally:
                os.chdir(previous)

    def test_relative_settings_match_direct_and_absolute_bootstrap(self):
        import _leg_session as session
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            settings = root / 'settings'
            shutil.copytree(os.environ['AIWORK_CONFIG_DIR'], settings, symlinks=True)
            output = root / 'output'
            output.mkdir()
            repo = output / 'repo'
            repo.mkdir()
            task = output / 'bootstrap.py'
            task.write_text('''import os, pathlib, subprocess
tools = pathlib.Path(os.environ['AIWORK_REVIEW_RESULT_BIN']).parent
result = subprocess.run(['/bin/bash', '-c', '. "$1/_programs.sh"; aiwork_init subcodex',
                         'bootstrap', str(tools)], capture_output=True, text=True)
assert result.returncode == 0, result.stderr
''')
            previous = Path.cwd()
            try:
                os.chdir(root)
                for configured in (str(settings), 'settings'):
                    with self.subTest(configured=configured):
                        env = dict(os.environ, AIWORK_CONFIG_DIR=configured,
                                   AIWORK_REVIEW_RESULT_BIN=str(BIN / '_review_result.py'))
                        with patch.dict(os.environ, env, clear=True):
                            direct = subprocess.run([sys.executable, str(task)], env=env,
                                                    text=True, capture_output=True)
                            self.assertEqual(direct.returncode, 0, direct.stderr)
                            isolated = session.run_isolated_leg(
                                [sys.executable, str(task)], env=env, directory=output,
                                repo=repo, task=task, bin_dir=BIN)
                        self.assertEqual(isolated.returncode, 0, isolated.stderr)
            finally:
                os.chdir(previous)

    def test_dns_with_resolver_configuration_under_private_run(self):
        import socket
        import socketserver
        import struct

        class Resolver(socketserver.BaseRequestHandler):
            def handle(self):
                query, connection = self.request
                end = 12
                while query[end]:
                    end += query[end] + 1
                end += 5
                question = query[12:end]
                answer = (b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 0, 4)
                          + socket.inet_aton('192.0.2.7'))
                connection.sendto(query[:2] + struct.pack('!HHHHH', 0x8180, 1, 1, 0, 0)
                                  + question + answer, self.client_address)

        # The suite owns an isolated network namespace. This DNS server cannot
        # send queries outside it and never needs a real model or provider key.
        with socketserver.UDPServer(('127.0.0.54', 53), Resolver) as resolver, \
                tempfile.TemporaryDirectory() as name:
            thread = threading.Thread(target=resolver.serve_forever, daemon=True)
            thread.start()
            self.addCleanup(resolver.shutdown)
            root = Path(name)
            output = root / 'output'
            output.mkdir()
            repo = output / 'repo'
            repo.mkdir()
            apps = root / 'apps'
            apps.mkdir()
            (apps / 'review.env').write_text('KEY=/run/publisher-key\n')
            task = output / 'task.py'
            task.write_text('''import pathlib, socket, sys
assert socket.getaddrinfo('model.example.test', 443, socket.AF_INET)[0][4][0] == '192.0.2.7'
assert socket.getaddrinfo('model.hosts.test', 443, socket.AF_INET)[0][4][0] == '192.0.2.8'
assert not pathlib.Path('/run/publisher.sock').exists()
with socket.socket(socket.AF_UNIX) as channel:
    try:
        channel.connect('/run/publisher.sock')
    except OSError:
        pass
    else:
        raise AssertionError('publisher socket exposed')
try:
    pathlib.Path('/run/publisher-key').read_bytes()
except OSError:
    pass
else:
    raise AssertionError('publisher key exposed')
for path in ('/etc/resolv.conf', '/etc/hosts', '/etc/nsswitch.conf'):
    try:
        pathlib.Path(path).write_text('injected')
    except OSError:
        pass
    else:
        raise AssertionError('network configuration is writable')
(pathlib.Path(sys.argv[1]) / 'report.md').write_text('Conclusion: PASS\\n')
''')
            driver = root / 'driver.py'
            driver.write_text('''import os, pathlib, socket, subprocess, sys
sys.path.insert(0, sys.argv[1])
from _leg_session import run_isolated_leg
root = pathlib.Path(sys.argv[2])
subprocess.run(['mount', '--make-rprivate', '/'], check=True)
# All changes below are inside this disposable mount namespace, not host /etc.
for path in ('/run', '/etc'):
    subprocess.run(['mount', '-t', 'tmpfs', 'tmpfs', path], check=True)
configuration = pathlib.Path('/run/systemd/resolve') if sys.argv[3] == 'run' else root / 'network'
configuration.mkdir(parents=True)
(configuration / 'stub-resolv.conf').write_text('nameserver 127.0.0.54\\noptions timeout:1 attempts:1\\n')
(configuration / 'hosts').write_text('192.0.2.8 model.hosts.test\\n')
(configuration / 'nsswitch.conf').write_text('hosts: files resolve [!UNAVAIL=return] dns\\n')
for name, target in (('resolv.conf', 'stub-resolv.conf'), ('hosts', 'hosts'), ('nsswitch.conf', 'nsswitch.conf')):
    alias = '../run/systemd/resolve/' + target if sys.argv[3] == 'run' else str(configuration / target)
    pathlib.Path('/etc', name).symlink_to(alias)
pathlib.Path('/run/publisher-key').write_text('disposable publisher credential')
with socket.socket(socket.AF_UNIX) as publisher:
    publisher.bind('/run/publisher.sock')
    publisher.listen()
    # Anchor: this exact resolver layout works before entering the leg boundary.
    assert socket.getaddrinfo('model.example.test', 443, socket.AF_INET)[0][4][0] == '192.0.2.7'
    output = root / 'output'
    result = run_isolated_leg([sys.executable, str(output / 'task.py'), str(output)],
        env=dict(os.environ, AIWORK_APPS_DIR=str(root / 'apps')), directory=output,
        repo=output / 'repo', task=output / 'task.py', bin_dir=pathlib.Path(sys.argv[1]))
    print(result.stderr, file=sys.stderr)
    raise SystemExit(result.returncode)
''')
            for layout in ('run', 'tmp'):
                with self.subTest(layout=layout):
                    result = subprocess.run(['unshare', '-m', '--', sys.executable, str(driver),
                                             str(BIN), str(root), layout], text=True,
                                            capture_output=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual((output / 'report.md').read_text(), 'Conclusion: PASS\n')

    def test_leg_cannot_read_key_or_change_publisher_but_can_return_report(self):
        import _leg_session as session
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            apps = root / 'apps'
            apps.mkdir()
            key = root / 'external-key'
            key.write_text('disposable credential fixture')
            (apps / 'key-link').symlink_to(key)
            (apps / 'review.env').write_text('KEY=key-link\n')
            publisher = root / 'publisher'
            publisher.write_text('trusted')
            output = root / 'output'
            output.mkdir()
            task = output / 'probe.py'
            repo = output / 'repo'
            repo.mkdir()
            program = task
            program.write_text("""import os, pathlib, subprocess, sys
key, publisher, task, repo, output = map(pathlib.Path, sys.argv[1:])
try:
    key.read_bytes()
except (OSError, PermissionError):
    pass
else:
    raise SystemExit('leg can read publisher credential')
for path in (task, repo / 'injected'):
    try:
        path.write_text('injected')
    except OSError:
        pass
    else:
        raise SystemExit('leg can alter trusted input: ' + str(path))
assert not pathlib.Path('/proc/' + os.environ['PUBLISHER_PID']).exists()
assert 'GH_TOKEN' not in os.environ
assert subprocess.run(['mount', '-o', 'remount,rw', '/'], capture_output=True).returncode
assert subprocess.run(['unshare', '-Ur', '-m', 'umount', str(key)], capture_output=True).returncode
(output / 'report.md').write_text('Conclusion: PASS\\n')
""")
            env = dict(os.environ, AIWORK_APPS_DIR=str(apps), GH_TOKEN='fixture',
                       PUBLISHER_PID=str(os.getpid()))
            launch = getattr(session, "run_isolated_leg",
                             lambda command, env, **_: subprocess.run(
                                 command, env=env, capture_output=True, text=True))
            result = launch(
                [sys.executable, str(program), str(key), str(publisher), str(task),
                 str(repo), str(output)], env=env, directory=output, repo=repo,
                task=task, bin_dir=BIN)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((output / 'report.md').read_text(), 'Conclusion: PASS\n')
            # The trusted parent can still use its credential and publish the report.
            self.assertEqual(key.read_text(), 'disposable credential fixture')
            self.assertEqual(publisher.read_text(), 'trusted')

    def test_normal_readonly_launcher_with_and_without_registered_key(self):
        import _leg_session as session
        from _aiwork_config import config_dir
        for registered in (False, True):
            with self.subTest(registered=registered), tempfile.TemporaryDirectory() as name, \
                    tempfile.TemporaryDirectory(dir=config_dir()) as config_case:
                directory = Path(name)
                repo = directory / 'repo'
                repo.mkdir()
                subprocess.run(['git', '-C', str(repo), 'init', '-q'], check=True)
                task = directory / 'task.md'
                task.write_text('Disposable launcher compatibility probe')
                apps = Path(config_case) / 'apps'
                if registered:
                    apps.mkdir()
                    (apps / 'fixture-key').write_text('disposable credential fixture')
                    (apps / 'review.env').write_text('KEY=fixture-key\n')
                env = dict(os.environ, AIWORK_APPS_DIR=str(apps))
                result = session.run_isolated_leg(
                    [str(BIN / 'ro-repo-exec'), str(repo), '--',
                     'git', '-C', str(repo), 'status', '--porcelain'],
                    env=env, directory=directory, repo=repo, task=task, bin_dir=BIN)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_state_and_tool_copies_never_copy_a_registered_publisher_key(self):
        import _leg_session as session
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            output, apps, codex = (root / part for part in ('output', 'apps', 'codex'))
            for path in (output, apps, codex):
                path.mkdir()
            key = codex / 'auth.json'
            key.write_text('disposable publisher credential fixture')
            (apps / 'review.env').write_text('KEY=' + str(key) + '\n')
            repo = output / 'repo'
            repo.mkdir()
            task = output / 'task.md'
            task.write_text('Probe copied state')
            leg = codex / 'subcodex'
            leg.write_text('#!/usr/bin/python3\nimport os, pathlib\n'
                           'if any((p / "auth.json").exists() for p in (pathlib.Path(os.environ["CODEX_HOME"]), pathlib.Path(__file__).parent)):\n'
                           '    raise SystemExit("copied publisher credential")\n')
            leg.chmod(0o755)
            result = session.run_isolated_leg(
                [str(leg)], env=dict(os.environ, AIWORK_APPS_DIR=str(apps), CODEX_HOME=str(codex)),
                directory=output, repo=repo, task=task, bin_dir=codex)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_tools_in_another_users_private_checkout_remain_readable(self):
        import _leg_session as session
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            foreign = root / 'foreign'
            foreign.mkdir(mode=0o700)
            tools = foreign / 'bin'
            tools.mkdir()
            leg = tools / 'reader'
            leg.write_text('#!/bin/sh\nexit 0\n')
            leg.chmod(0o755)
            os.chown(foreign, 65534, 65534)
            output = root / 'output'
            output.mkdir()
            repo = output / 'repo'
            repo.mkdir()
            task = output / 'task.md'
            task.write_text('Private checkout compatibility probe')
            result = session.run_isolated_leg(
                [str(leg)], env=dict(os.environ, AIWORK_APPS_DIR=str(root / 'absent-apps')),
                directory=output, repo=repo, task=task, bin_dir=tools)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_staged_tools_keep_kimi_seed_at_the_wrappers_relative_path(self):
        import _leg_session as session
        import re
        import hashlib
        relative = re.search(r'KIMI_SEED_HOME="\$BIN_DIR/([^"\n]+)"',
                             (BIN / 'subkimi').read_text()).group(1)
        digest = hashlib.sha256((BIN / relative / 'hooks/guard.mjs').read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            repo = directory / 'repo'
            repo.mkdir()
            task = directory / 'task.py'
            task.write_text('import hashlib, os, pathlib, sys\n'
                            'seed = pathlib.Path(os.environ["AIWORK_REVIEW_RESULT_BIN"]).parent / sys.argv[1]\n'
                            'assert hashlib.sha256((seed / "hooks/guard.mjs").read_bytes()).hexdigest() == sys.argv[2]\n')
            env = dict(os.environ, AIWORK_APPS_DIR=str(directory / 'absent-apps'),
                       AIWORK_REVIEW_RESULT_BIN=str(BIN / '_review_result.py'))
            result = session.run_isolated_leg([sys.executable, str(task), relative, digest],
                                              env=env, directory=directory, repo=repo,
                                              task=task, bin_dir=BIN)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_link_outputs_are_rejected_without_reading_or_overwriting_target(self):
        import _leg_session as session
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            output = root / 'output'
            output.mkdir()
            repo = output / 'repo'
            repo.mkdir()
            target = root / 'publisher-secret'
            target.write_text('unchanged fixture')
            task = output / 'task.py'
            task.write_text('import pathlib, sys; pathlib.Path(sys.argv[1]).symlink_to(sys.argv[2])')
            with patch.dict(os.environ, AIWORK_APPS_DIR=str(root / 'absent-apps')):
                with self.assertRaises(session.ReviewError):
                    session.run_isolated_leg(
                        [sys.executable, str(task), str(output / 'report.md'), str(target)],
                        env=dict(os.environ), directory=output, repo=repo, task=task, bin_dir=BIN)
            self.assertEqual(target.read_text(), 'unchanged fixture')
            self.assertFalse((output / 'report.md').exists())

    def test_missing_sandbox_refuses_before_starting_leg(self):
        import _leg_session as session
        with patch.object(Path, 'is_file', return_value=False):
            with self.assertRaisesRegex(session.ReviewError, 'bubblewrap'):
                session.run_isolated_leg([], env={}, directory=Path('/unused'),
                                         repo=Path('/unused'), task=Path('/unused'), bin_dir=BIN)

    def test_hardlinked_key_refuses_before_starting_leg(self):
        import _leg_session as session
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            apps = root / 'apps'
            apps.mkdir()
            key = apps / 'fixture-key'
            key.write_text('disposable fixture')
            (root / 'alias').hardlink_to(key)
            (apps / 'review.env').write_text('KEY=fixture-key\n')
            with self.assertRaisesRegex(session.ReviewError, '硬链接'):
                session.run_isolated_leg([], env=dict(os.environ, AIWORK_APPS_DIR=str(apps)),
                                         directory=root, repo=root, task=key, bin_dir=BIN)


if __name__ == '__main__':
    unittest.main()

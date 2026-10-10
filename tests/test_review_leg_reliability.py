#!/usr/bin/env python3
"""Offline PR-to-provider regressions for review-leg reliability."""

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

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

from test_review_pr import load_script
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
                   fake_attempts=None, missing_agent=False, files=None, changes=None):
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
        if fake_attempts is not None:
            self.run_count += 1
            bin_dir = self.directory / f'bin-{self.run_count}'
            bin_dir.mkdir()
            for adapter in BIN.glob('sub*'):
                name = adapter.name
                if missing_agent and name == leg + '-agent':
                    continue
                (bin_dir / name).touch()
            shutil.copy2(BIN / '_review_result.py', bin_dir / '_review_result.py')
            (bin_dir / 'privacy-check').symlink_to(BIN / 'privacy-check')

        def invoke(command, **kwargs):
            is_leg = Path(command[0]).parent == bin_dir and Path(command[0]).name.startswith('sub')
            if is_leg:
                self.leg_calls.append((Path(command[0]).name, kwargs['env'].copy()))
                self.seen_tasks.append(Path(command[2]).read_text(encoding='utf-8'))
            if fake_attempts is None or not is_leg:
                return real_subprocess_run(command, **kwargs)
            name = Path(command[0]).name
            attempt = fake_attempts[min(len(self.leg_calls) - 1, len(fake_attempts) - 1)]
            model = {'subdeepseek-agent': 'deepseek-flash',
                     'subcursor': 'gpt-6-sol', 'subcodex': 'gpt-6-sol',
                     'submimo': 'xiaomi/mimo-v2.6-pro', 'subkimi': 'kimi-code/kimi-for-coding'}[name]
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

        def github(token, endpoint, payload=None):
            posted.append(payload)
            return {'html_url': 'https://github.com/example/repo/pull/1#pullrequestreview-1'}

        clean = {k: v for k, v in os.environ.items() if not k.startswith(
            ('MIMO_', 'DEEPSEEK_', 'ZHIPU_'))}
        clean.update(DEEPSEEK_API_KEY='fixture-key',
                     DEEPSEEK_API_BASE=endpoint, CURSOR_MODEL='gpt-6-sol',
                     AIWORK_DATA_DIR=str(self.directory / 'data'))
        clean.update(env or {})
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.dict(os.environ, clean, clear=True), \
                patch('sys.argv', ['review-pr', '1', '--repo', 'example/repo', '--leg', leg]), \
                patch.object(sys.modules['_leg_session'], 'run', side_effect=run), \
                patch.object(self.review, 'pr_state', return_value=pr), \
                patch.object(sys.modules['_leg_session'], 'snapshot', return_value=(
                    self.repo, self.base, files or ['file'], self.diff,
                    changes if changes is not None else [
                        self.review.Change('M', (files or ['file'])[0], None, 1, 0)])), \
                patch.object(self.review, 'aiwork_main_rules', return_value=('d' * 40, 'Trusted rules.')), \
                patch.object(self.review, 'main_document', return_value='无'), \
                patch.object(self.review, 'github', side_effect=github), \
                patch.object(self.review, 'BIN', bin_dir), \
                patch.object(self.review.subprocess, 'run', side_effect=invoke), \
                redirect_stdout(stdout), redirect_stderr(stderr):
            rc = self.review.main()
        return rc, payloads, posted, stdout.getvalue(), stderr.getvalue()

    def test_review_pr_puts_the_diff_in_the_reader_task_once(self):
        rc, payloads, posted, _, stderr = self.run_review('subdeepseek-agent', fake_attempts=[{}])
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(payloads, [])
        self.assertEqual(self.seen_tasks[0].count(DIFF_MARKER), 1)
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

    def test_all_repository_readers_get_2400_seconds_unless_caller_overrides(self):
        timeouts = {'subdeepseek-agent': 'DEEPSEEK_TIMEOUT',
                    'subcodex': 'SUBCODEX_TIMEOUT', 'subcursor': 'CURSOR_TIMEOUT',
                    'submimo': 'MIMO_CLI_TIMEOUT', 'subkimi': 'KIMI_TIMEOUT'}
        for leg, variable in timeouts.items():
            for override in (None, '', '317'):
                with self.subTest(leg=leg, override=override):
                    env = {} if override is None else {variable: override}
                    rc, _, posted, _, stderr = self.run_review(leg, env=env, fake_attempts=[{}])
                    self.assertEqual(rc, 0, stderr)
                    self.assertEqual(self.leg_calls[0][1].get(variable), override or '2400')
                    self.assertEqual(len(posted), 1)

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
                        'identity_mismatch', 'snapshot', 'unknown'):
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
        self.archives = self.directory / 'data/logs/review-pr-failures'
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

    def test_failure_archives_keep_only_newest_twenty_by_archive_time(self):
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
        self.assertEqual(remaining, {'new-failure', *(p.name for p in previous[5:])})
        self.assertEqual(len(remaining), 20)
        self.assertEqual((self.archives / 'new-failure/review.log').read_text(), 'latest failure')


class ReaderFailureClassificationTests(LegCase):
    def test_real_readers_classify_completed_report_without_conclusion(self):
        self.copy('subdeepseek-agent', 'subagent', 'subkimi', 'ro-repo-exec')
        self.fake('claude', '#!/bin/sh\necho \'{"type":"assistant","message":{"content":[{"type":"text","text":"Checked the authentication code."}]}}\'\n')
        self.fake('kimi', '#!/bin/sh\necho "Checked the authentication code."\n')
        home = self.d / 'kimi-home'
        (home / 'hooks').mkdir(parents=True)
        (home / 'credentials').mkdir()
        (home / 'config.toml').write_text('default_model = "fixture"\n')
        (home / 'hooks/guard.mjs').write_text('process.exit(2); // offline deny fixture\n')
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

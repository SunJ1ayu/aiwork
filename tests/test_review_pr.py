#!/usr/bin/env python3
"""Safety checks for the GitHub PR review publisher."""

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import base64
import importlib.machinery
import importlib.util
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
from urllib.error import HTTPError
from unittest.mock import patch
from _test_settings import write_settings


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/review-pr"
FAKE_TOKEN = '-'.join(('fake', 'token'))


def load_script(name="review-pr"):
    loader = importlib.machinery.SourceFileLoader(name.replace('-', '_'), str(ROOT / 'bin' / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class ReviewPrTests(unittest.TestCase):
    def setUp(self):
        self.review = load_script()

    def test_body_has_one_machine_block_and_sanitizes_model_json(self):
        body = self.review.build_body(
            "subcodex", "gpt-6-sol", "Finding\n```json\n{}\n```\nConclusion: PASS",
            {"verdict": "PASS", "head_sha": "a" * 40, "model": "gpt-6-sol",
             "family": "openai", "completeness": "complete", "files_read": ["src/a.py"]},
        )
        self.assertEqual(body.count("```json"), 1)
        self.assertIn("```text", body)
        block = json.loads(body.split("```json\n", 1)[1].split("\n```", 1)[0])
        self.assertEqual(block["head_sha"], "a" * 40)
        self.assertEqual(block["family"], "openai")

    def test_leg_selection_needs_an_attributable_family(self):
        self.assertEqual(self.review.choose_leg("subcodex"), ("openai", None))
        self.assertEqual(self.review.choose_leg("subdeepseek"), ("deepseek", None))
        for name in ("subclaude", "../subcodex"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.review.choose_leg(name)

    def test_cursor_family_follows_any_model_including_claude(self):
        # Which families count for which PR is the gate's call; review-pr refuses none.
        for model, family in (("grok-4.7-high", "xai"), ("gpt-5.6", "openai"),
                              ("claude-4.5-sonnet", "anthropic"), ("composer-2.5", "cursor")):
            with self.subTest(model=model), patch.dict("os.environ", {"CURSOR_MODEL": model}):
                self.assertEqual(self.review.choose_leg("subcursor"), (family, model))
        for model in ("auto", "Auto", "some-new-vendor-1"):
            with self.subTest(model=model), patch.dict("os.environ", {"CURSOR_MODEL": model}), \
                    self.assertRaisesRegex(self.review.ReviewError, "unsupported review leg"):
                self.review.choose_leg("subcursor")

    def test_cursor_model_defaults_to_the_config_file(self):
        configured = self.review.configured_model("cursor")
        with patch.dict("os.environ", {"CURSOR_MODEL": ""}):
            self.assertEqual(self.review.choose_leg("subcursor")[1], configured)

    def run_main_with_leg_result(self, model_used: str, *, dry_run: bool = True,
                                 repository=None, source_failure=None, project_rules=False,
                                 local_rules="LOCAL WORKSPACE RULES", risks_present=True,
                                 leg_exit=0, leg_stderr="", view_state="complete", emit_failure=False,
                                 report="Finding\nConclusion: PASS", private_terms='unused\n'):
        """Exercise the real source readers and task, with offline HTTP and review leg."""
        calls = {"github_writes": [], "public_reads": [], "leg_runs": 0}
        rules = "# aiwork main 规则\r\n必须以此为准。\r\n"
        risks = "# project main 风险\r\n业主接受的平台上限。\r\n"
        source_sha = "d" * 40
        calls.update(rules=rules, risks=risks, source_sha=source_sha)
        real_run = self.review.run
        real_subprocess_run = subprocess.run

        def fake_public_read(request, **kwargs):
            url = request.full_url
            calls["public_reads"].append(url)
            self.assertNotIn("authorization", {key.lower() for key in request.headers})
            self.assertGreater(kwargs["timeout"], 0)
            if source_failure == "main_unreadable":
                raise HTTPError(url, 403, "Forbidden", {}, None)
            if url == "https://api.github.com/repos/SunJ1ayu/aiwork/commits/main":
                value = {"sha": "invalid" if source_failure == "invalid_sha" else source_sha}
            elif url == f"https://api.github.com/repos/SunJ1ayu/aiwork/contents/REVIEW-RULES.md?ref={source_sha}":
                if source_failure == "rules_unreadable":
                    raise HTTPError(url, 404, "Not Found", {}, None)
                raw = rules.encode("utf-8")
                value = {"type": "file", "encoding": "base64", "size": len(raw),
                         "content": base64.encodebytes(raw).decode("ascii")}
                if source_failure == "not_file":
                    value["type"] = "symlink"
                if source_failure == "invalid_content":
                    value["content"] = "not base64!"
                if source_failure == "truncated_content":
                    value["size"] += 1
            else:
                self.fail(f"unexpected public source read: {url}")
            return io.BytesIO(json.dumps(value).encode("utf-8"))

        def fake_github(token, endpoint, payload=None):
            if payload is not None:
                calls["github_writes"].append(endpoint)
                calls['posted_block'] = json.loads(payload['body'].split('```json\n', 1)[1].split('\n```', 1)[0])
            return {"html_url": "https://github.com/SunJ1ayu/OpenDesign/pull/12#pullrequestreview-1"}

        def fake_run(command, **kwargs):
            if command[0].endswith("gh-app-token"):
                calls["token_command"] = command
                return FAKE_TOKEN
            if command[0] == "git":
                return real_run(command, **kwargs)
            calls["emit"] = command
            if emit_failure:
                raise self.review.ReviewError("result producer failed")
            return ""

        def fake_leg(command, **kwargs):
            if command[0] != str(bin_dir / "subcursor"):
                return real_subprocess_run(command, **kwargs)
            calls["leg_runs"] += 1
            calls["task"] = Path(command[2]).read_bytes().decode("utf-8")
            calls["leg_env"] = kwargs["env"]
            calls["temporary"] = str(Path(command[2]).parent)
            Path(command[3]).write_text("# fake review log\n\nConclusion: PASS\n")
            Path(kwargs['env']['AIWORK_REVIEW_FACTS_PATH']).write_text('{"fixture":true}\n')
            os.environ["CURSOR_MODEL"] = "gpt-other"
            return subprocess.CompletedProcess(command, leg_exit, "", leg_stderr.replace("$LOG", command[3]))

        result = {
            "process": {"state": "exited", "exit_code": leg_exit},
            "verdict": "PASS", "failure_kind": "none", "degraded": False,
            "evidence": {"completeness": "complete"},
            "view": {"delivery_state": view_state},
            "model": {"requested": model_used, "invoked": model_used, "reported": None},
        }
        pr = {"state": "open", "head": {"sha": "a" * 40, "ref": "f"}, "base": {"sha": "b" * 40, "ref": "main"}}
        stdout, stderr = io.StringIO(), io.StringIO()
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            bin_dir = workspace / "bin"
            bin_dir.mkdir()
            for name in ('privacy-check', 'aiwork-config', '_aiwork_config.py',
                         '_secret_shapes.py', '_secret-shapes'):
                shutil.copy2(ROOT / 'bin' / name, bin_dir / name)
            config = workspace / 'settings'
            write_settings(config)
            if private_terms is not None:
                (config / 'private-terms').write_text(private_terms)
            else:
                (config / 'private-terms').unlink()
            (bin_dir / "subcursor").touch()
            (workspace / "REVIEW-RULES.md").write_text(local_rules, encoding="utf-8")
            repo = workspace / "project"
            repo.mkdir()
            def git(*args):
                return real_subprocess_run(["git", "-C", str(repo), *args], check=True,
                                           capture_output=True)
            git("init", "-q")
            git("config", "core.autocrlf", "false")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            (repo / ".aiwork").mkdir()
            if risks_present:
                (repo / ".aiwork/accepted-risks.md").write_bytes(risks.encode("utf-8"))
            if project_rules:
                (repo / ".aiwork/review-rules.md").write_text("PROJECT RULES DECOY", encoding="utf-8")
            (repo / "file").touch()
            git("add", ".")
            git("commit", "-qm", "project main")
            git("update-ref", "refs/aiwork/main", "HEAD")
            (repo / ".aiwork/accepted-risks.md").write_text("PR RISK DECOY", encoding="utf-8")
            with patch("sys.argv", ["review-pr", "12", "--leg", "subcursor"]
                       + (["--repo", repository] if repository else []) + (["--dry-run"] if dry_run else [])), \
                    patch.dict("os.environ", {"CURSOR_MODEL": "gpt-5.6"}), \
                    patch.object(self.review, "BIN", bin_dir), \
                    patch.dict(os.environ, AIWORK_DATA_DIR=str(workspace / "data"), AIWORK_CONFIG_DIR=str(config)), \
                    patch.object(self.review, "run", side_effect=fake_run), \
                    patch("urllib.request.urlopen", side_effect=fake_public_read), \
                    patch.object(self.review, "github", side_effect=fake_github), \
                    patch.object(self.review, "pr_state", return_value=pr) as state, \
                    patch.object(self.review, "snapshot", return_value=(repo, "c" * 40, ["src/a.py"], "diff")) as snapshot, \
                    patch.object(self.review, "load_result", return_value=result), \
                    patch.object(self.review, "review_report", return_value=report), \
                    patch.object(self.review.subprocess, "run", side_effect=fake_leg), \
                    redirect_stdout(stdout), redirect_stderr(stderr):
                rc = self.review.main()
                calls["pr_state"] = state.call_args_list
                calls["snapshot"] = snapshot.call_args
            failures = workspace / 'data/logs/review-pr-failures'
            calls['archives'] = {str(p): {str(f.relative_to(p)): f.read_bytes()
                                         for f in p.rglob('*') if f.is_file()}
                                 for p in failures.iterdir()} if failures.exists() else {}
            calls['archive_modes'] = [p.stat().st_mode & 0o777 for p in failures.iterdir()] if failures.exists() else []
            calls['temporary_exists'] = Path(calls.get('temporary', '/nonexistent')).exists()
        return rc, calls, stdout.getvalue(), stderr.getvalue()

    def test_private_review_body_is_refused_without_echoing_report_or_leg_stderr(self):
        marker = 'private-marker'
        for dry_run in (False, True):
            with self.subTest(dry_run=dry_run):
                rc, calls, stdout, stderr = self.run_main_with_leg_result(
                    'gpt-5.6', dry_run=dry_run, private_terms=' \t' + marker + '\t\n',
                    report='Finding ' + marker.upper() + '\nConclusion: PASS',
                    leg_stderr='provider diagnostic ' + marker)
                self.assertEqual(rc, 1)
                self.assertEqual(calls['github_writes'], [])
                self.assertEqual(stdout, '')
                self.assertIn('review-body.md:3 私人词第 1 条', stderr)
                self.assertNotIn(marker, stderr.casefold())
                self.assertNotIn('Finding', stderr)

    def test_secret_shape_in_review_body_is_refused_with_an_empty_wordlist(self):
        secret = 'sk' + '-' + 'a' * 20
        rc, calls, stdout, stderr = self.run_main_with_leg_result(
            'gpt-5.6', dry_run=False, private_terms='',
            report=secret + '\nConclusion: PASS')
        self.assertEqual(rc, 1)
        self.assertEqual(calls['github_writes'], [])
        self.assertEqual(stdout, '')
        self.assertIn('review-body.md:3 形状 sk-', stderr)
        self.assertIn('词表为空，只检查了密钥形状', stderr)
        self.assertNotIn(secret, stderr)

    def test_privacy_check_covers_machine_block_and_missing_wordlist_refuses_publication(self):
        for terms in ('src/a.py\n', None):
            with self.subTest(terms=terms):
                rc, calls, stdout, stderr = self.run_main_with_leg_result(
                    'gpt-5.6', dry_run=False, private_terms=terms)
                self.assertEqual(rc, 1)
                self.assertEqual(calls['github_writes'], [])
                self.assertEqual(stdout, '')
                if terms:
                    self.assertIn('review-body.md:7 私人词第 1 条', stderr)
                    self.assertNotIn('src/a.py', stderr)
                else:
                    self.assertIn('请建立并填写本机私人词表', stderr)

    def test_failed_leg_reports_only_last_40_lines_with_secrets_redacted(self):
        fake_token = 'ghs' + '_' + 'testsecret'
        diagnostic = ''.join(f'line-{i:02d}\n' for i in range(60)) + 'token: ' + fake_token + '\n'
        rc, calls, stdout, stderr = self.run_main_with_leg_result('gpt-5.6', dry_run=False,
                                                                leg_exit=1, leg_stderr=diagnostic)
        self.assertEqual(rc, 1)
        self.assertEqual(stdout, '')
        self.assertEqual(calls['github_writes'], [])
        self.assertIn('line-21', stderr)
        self.assertIn('line-59', stderr)
        self.assertNotIn('line-20', stderr)
        self.assertNotIn(fake_token, stderr)
        self.assertIn('[redacted]', stderr)

    def test_failed_leg_keeps_whole_directory_and_reports_a_live_log_path(self):
        rc, calls, _, stderr = self.run_main_with_leg_result('gpt-5.6', leg_exit=1,
                            leg_stderr='bad verdict; raw output kept in $LOG\n')
        self.assertEqual(rc, 1)
        self.assertFalse(calls['temporary_exists'])
        self.assertEqual(len(calls['archives']), 1)
        archive, files = next(iter(calls['archives'].items()))
        for name in ('task.md', 'review.log', 'leg.stderr', 'facts.json'):
            self.assertIn(name, files)
        self.assertIn('raw output kept in ' + archive + '/review.log', stderr)
        self.assertNotIn(calls['temporary'], stderr)
        self.assertEqual(calls['archive_modes'], [0o700])

    def test_success_does_not_keep_a_failure_directory(self):
        rc, calls, _, stderr = self.run_main_with_leg_result('gpt-5.6')
        self.assertEqual(rc, 0, stderr)
        self.assertFalse(calls['temporary_exists'])
        self.assertEqual(calls['archives'], {})

    def test_result_producer_failure_also_preserves_the_leg_diagnostic(self):
        rc, calls, _, stderr = self.run_main_with_leg_result('gpt-5.6', emit_failure=True,
                                                           leg_stderr='provider diagnostic\n')
        self.assertEqual(rc, 1)
        self.assertIn('provider diagnostic', stderr)
        self.assertEqual(len(calls['archives']), 1)

    def test_tool_name_token_is_not_redacted_but_actual_credentials_are(self):
        diagnostic = 'gh-app-token: 目标仓库不在角色配置范围内'
        with patch.object(self.review.subprocess, 'run', return_value=subprocess.CompletedProcess([], 2, '', diagnostic)):
            with self.assertRaises(self.review.ReviewError) as error:
                self.review.run(['gh-app-token', 'review'])
        self.assertIn(diagnostic, str(error.exception))
        fake_tokens = ['ghs' + '_' + 'first', 'ghp' + '_' + 'second', 'github' + '_pat_' + 'third']
        pem = '-----' + 'BEGIN PRIVATE KEY' + '-----\nprivate-material\n-----END PRIVATE KEY-----'
        ordinary, other = ['-'.join((word, 'value')) for word in ('ordinary', 'other')]
        secrets = ' '.join(fake_tokens) + f' token: {ordinary} token={other}\n' + pem
        with patch.object(self.review.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', secrets)):
            with self.assertRaises(self.review.ReviewError) as error:
                self.review.run(['provider'])
        for secret in (*fake_tokens, ordinary, other, 'private-material'):
            self.assertNotIn(secret, str(error.exception))

    def test_common_secret_assignments_headers_and_prefixes_are_redacted(self):
        fake_key = 'sk' + '-' + 'abcdefghijklmnop'
        opaque = '-'.join(('opaque', 'fixture'))
        spaced = ' '.join(('opaque', 'fixture'))
        cases = (
            (f'DEEPSEEK_API_KEY={fake_key}', 'DEEPSEEK_API_KEY=[redacted]'),
            (f'export MIMO_API_KEY="{fake_key}"', 'export MIMO_API_KEY=[redacted]'),
            (f'Authorization: Bearer {fake_key}', 'Authorization: Bearer [redacted]'),
            (f'GH_TOKEN={opaque}', 'GH_TOKEN=[redacted]'),
            (f'service_secret: "{spaced}"', 'service_secret: [redacted]'),
            (f"custom_PaSsWoRd='{spaced}'", 'custom_PaSsWoRd=[redacted]'),
            (f'myKey: {opaque}', 'myKey: [redacted]'),
            (f'TOKEN: {opaque}', 'TOKEN: [redacted]'),
            (f'API-KEY={opaque}', 'API-KEY=[redacted]'),
            (f'authorization: bearer {opaque}', 'authorization: bearer [redacted]'),
            (f'provider echoed {fake_key}', 'provider echoed [redacted]'),
            ('provider echoed ' + 'sk' + '-' + 'abcd_efgh-ijklmn', 'provider echoed [redacted]'),
            ('provider echoed ' + 'ghs' + '_' + 'fixture', 'provider echoed [redacted]'),
            ('provider echoed ' + 'ghp' + '_' + 'fixture', 'provider echoed [redacted]'),
            ('provider echoed ' + 'github' + '_pat_' + 'fixture', 'provider echoed [redacted]'),
            ('-----' + 'BEGIN PRIVATE KEY' + '-----\nfixture-only\n-----END PRIVATE KEY-----', '[redacted]'),
        )
        for original, expected in cases:
            with self.subTest(original=original):
                self.assertEqual(self.review.redact(original), expected)

    def test_secret_redaction_keeps_tool_errors_and_short_sk_text(self):
        for message in ('gh-app-token: 目标仓库不在角色配置范围内',
                        'fetch-key: 无法读取文件',
                        'codex/task-model-roles-closeout',
                        'provider mentioned ' + 'sk' + '-' + 'abcdefghijklmno'):
            with self.subTest(message=message):
                self.assertEqual(self.review.redact(message), message)

    def test_mimo_and_nested_pem_shapes_hide_the_entire_payload(self):
        fake = 'tp' + '-' + 'a' * 48
        self.assertEqual(self.review.redact('provider: ' + fake), 'provider: [redacted]')
        pem = '-----' + 'BEGIN PRIVATE KEY' + '-----\n' + fake + '\n-----END PRIVATE KEY-----'
        self.assertEqual(self.review.redact('before ' + pem + ' after'), 'before [redacted] after')

    def test_common_secrets_are_redacted_in_failed_leg_stderr(self):
        fake_key = 'sk' + '-' + 'abcdefghijklmnop'
        diagnostic = f'DEEPSEEK_API_KEY={fake_key}\nexport MIMO_API_KEY="{fake_key}"\n' \
                     f'Authorization: Bearer {fake_key}\ngh-app-token: 目标仓库不在角色配置范围内\n'
        rc, calls, _, stderr = self.run_main_with_leg_result('gpt-5.6', leg_exit=1, leg_stderr=diagnostic)
        self.assertEqual(rc, 1)
        self.assertNotIn(fake_key, stderr)
        self.assertIn('DEEPSEEK_API_KEY=[redacted]', stderr)
        self.assertIn('Authorization: Bearer [redacted]', stderr)
        self.assertIn('gh-app-token: 目标仓库不在角色配置范围内', stderr)
        self.assertEqual(calls['github_writes'], [])

    def run_chat_engine(self, *, oversized=None, finish_reason='stop', content='Conclusion: PASS'):
        engine = load_script('submimo-review')
        with tempfile.TemporaryDirectory() as temporary:
            d = Path(temporary)
            repo = d / 'repo'
            repo.mkdir()
            for args in (('init', '-q'), ('config', 'user.name', 'Test'),
                         ('config', 'user.email', 'test@example.invalid')):
                subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True)
            (repo / 'file').write_text('base\n')
            subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(repo), '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'base'],
                           check=True, capture_output=True)
            task = d / 'task.md'
            task.write_text('Review this change.\n' + ('task\n' * 30000 if oversized == 'task' else ''))
            (repo / 'file').write_text('base\n' + ('diff\n' * 100000 if oversized == 'diff' else 'change\n'))
            facts, log = d / 'facts.json', d / 'review.log'
            response = json.dumps({'choices': [{'message': {'content': content}, 'finish_reason': finish_reason}]})
            stdout, stderr = io.StringIO(), io.StringIO()
            with patch.dict(os.environ, {'AIWORK_REVIEW_FACTS_PATH': str(facts), 'PANEL_DIFF_BASE': '',
                    'MIMO_API_KEY': '-'.join(('fake', 'key')), 'MIMO_BASE_URL': 'http://127.0.0.1',
                    'AIWORK_MODEL_LEG': 'cursor', 'MIMO_MODEL': 'gpt-5.6'}), \
                    patch('sys.argv', ['submimo-review', str(task), str(log), '--repo', str(repo), '--git-diff']), \
                    patch.object(engine.urllib.request, 'urlopen', return_value=io.BytesIO(response.encode())), \
                    redirect_stdout(stdout), redirect_stderr(stderr):
                try:
                    engine.main()
                    rc = 0
                except SystemExit as exc:
                    rc = exc.code
            return rc, json.loads(facts.read_text()), log.read_text() if log.exists() else '', stderr.getvalue()

    def test_oversized_diff_and_task_publish_partial_completeness(self):
        for oversized in ('diff', 'task'):
            with self.subTest(oversized=oversized):
                rc, facts, _, stderr = self.run_chat_engine(oversized=oversized)
                self.assertEqual(rc, 0, stderr)
                self.assertEqual(facts['view']['delivery_state'], 'partial')
                rc, calls, _, stderr = self.run_main_with_leg_result('gpt-5.6', dry_run=False,
                                                        view_state=facts['view']['delivery_state'])
                self.assertEqual(rc, 0, stderr)
                self.assertEqual(calls['posted_block']['completeness'], 'partial')

    def test_untruncated_chat_delivery_stays_complete(self):
        rc, facts, _, stderr = self.run_chat_engine()
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(facts['view']['delivery_state'], 'complete')

    def test_length_finish_reason_reports_output_truncation_and_keeps_raw_text(self):
        for content in ('missing verdict', 'Conclusion: PASS'):
            with self.subTest(content=content):
                rc, _, log, stderr = self.run_chat_engine(finish_reason='length', content=content)
                self.assertNotEqual(rc, 0)
                self.assertIn('模型输出被截断', stderr)
                self.assertNotIn('no standalone', stderr)
                self.assertIn(content, log)

    def test_readme_documents_review_pr_network_credentials_and_sandbox(self):
        readme = (ROOT / 'README.md').read_text()
        self.assertIn('bin/review-pr', readme)
        self.assertIn('需要联网、需要读取本机模型凭证', readme)
        self.assertIn('必须在沙箱外运行', readme)

    def whole_file_deletion(self):
        marker = 'DELETED_PAYLOAD_9f3c'
        count = (200 * 1024) // (len(marker) + 1) + 80
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.run(['git', '-C', str(repo), *args], check=True,
                                       capture_output=True, text=True)
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
            diff = git('diff', '--binary', '--no-ext-diff', base, head).stdout
        pr = {'head': {'sha': head, 'ref': 'feature'}, 'base': {'sha': base, 'ref': 'main'}}
        return pr, base, head, ['gone.txt'], diff, count, marker

    def test_large_whole_file_deletion_reader_task_stays_within_limit(self):
        pr, base, head, files, diff, count, marker = self.whole_file_deletion()
        limit = 200 * 1024
        self.assertGreater(len(diff.encode()), limit)
        task = self.review.task_text(
            17, pr, base, files, diff, 'rules\n', '无',
            rules_sha='d' * 40, repository='SunJ1ayu/aiwork', reader=True)
        self.assertLessEqual(len(task.encode()), limit)
        self.assertNotIn(marker, task)
        self.assertIn(f'（{count} 行）', task)
        self.assertIn(f'git diff {base}..{head} -- gone.txt', task)
        self.assertEqual(self.review.READER_INLINE_DIFF_BYTES, limit)
        self.assertGreater(task.rfind('最后独占一行写'), task.rfind('```'))

    def test_large_whole_file_deletion_chat_task_omits_content_without_reader_instructions(self):
        pr, base, head, files, diff, count, marker = self.whole_file_deletion()
        limit = 200 * 1024
        self.assertGreater(len(diff.encode()), limit)
        task = self.review.task_text(
            17, pr, base, files, diff, 'rules\n', '无',
            rules_sha='d' * 40, repository='SunJ1ayu/aiwork')
        self.assertLessEqual(len(task.encode()), limit)
        self.assertNotIn(marker, task)
        self.assertIn(f'（{count} 行）', task)
        self.assertNotIn(f'git diff {base}..{head} -- gone.txt', task)
        self.assertNotIn('不内联', task)

    def test_other_hunks_stay_inlined_when_a_small_file_is_deleted(self):
        marker = 'ONLY_IN_DELETED_FILE'
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.run(['git', '-C', str(repo), *args], check=True,
                                       capture_output=True, text=True)
            git('init', '-q')
            git('config', 'user.name', 'Test')
            git('config', 'user.email', 'test@example.invalid')
            (repo / 'stay.txt').write_text('base\n')
            (repo / 'gone.txt').write_text(marker + '\n')
            git('add', '.')
            git('commit', '-qm', 'add')
            base = git('rev-parse', 'HEAD').stdout.strip()
            (repo / 'stay.txt').write_text('base\nchanged\n')
            git('add', 'stay.txt')
            git('rm', '-q', 'gone.txt')
            git('commit', '-qm', 'edit')
            head = git('rev-parse', 'HEAD').stdout.strip()
            diff = git('diff', '--binary', '--no-ext-diff', base, head).stdout
        pr = {'head': {'sha': head, 'ref': 'feature'}, 'base': {'sha': base, 'ref': 'main'}}
        task = self.review.task_text(
            3, pr, base, ['stay.txt', 'gone.txt'], diff, 'rules\n', '无',
            rules_sha='d' * 40, repository='SunJ1ayu/aiwork', reader=True)
        self.assertIn('\n+changed\n', task)
        self.assertNotIn(marker, task)
        self.assertIn('（1 行）', task)
        self.assertNotIn('不内联', task)

    def test_binary_whole_file_deletion_omits_patch_bytes(self):
        diff = (
            'diff --git a/a.bin b/a.bin\n'
            'deleted file mode 100644\n'
            'index 1111111..0000000\n'
            'GIT binary patch\n'
            'literal 5\n'
            'AAAAA_SECRET_BYTES\n'
        )
        pr = {'head': {'sha': 'a' * 40, 'ref': 'feature'}, 'base': {'sha': 'b' * 40, 'ref': 'main'}}
        task = self.review.task_text(
            4, pr, 'c' * 40, ['a.bin'], diff, 'rules\n', '无',
            rules_sha='d' * 40, repository='SunJ1ayu/aiwork')
        self.assertNotIn('AAAAA_SECRET_BYTES', task)
        self.assertIn('"a.bin"（二进制文件）', task)

    def test_quoted_deletion_path_keeps_its_name_and_line_count(self):
        name = '断线 砍断.txt'
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.run(['git', '-C', str(repo), *args], check=True,
                                       capture_output=True, text=True)
            git('init', '-q')
            git('config', 'user.name', 'Test')
            git('config', 'user.email', 'test@example.invalid')
            (repo / name).write_text('one\ntwo\n')
            git('add', '--', name)
            git('commit', '-qm', 'add')
            base = git('rev-parse', 'HEAD').stdout.strip()
            git('rm', '-q', '--', name)
            git('commit', '-qm', 'delete')
            head = git('rev-parse', 'HEAD').stdout.strip()
            diff = git('diff', '--binary', '--no-ext-diff', base, head).stdout
        pr = {'head': {'sha': head, 'ref': 'feature'}, 'base': {'sha': base, 'ref': 'main'}}
        task = self.review.task_text(
            5, pr, base, [name], diff, 'rules\n', '无',
            rules_sha='d' * 40, repository='SunJ1ayu/aiwork', reader=True)
        self.assertNotIn('\n-one\n', task)
        self.assertNotIn('\n-two\n', task)
        self.assertIn(f'{json.dumps(name, ensure_ascii=False)}（2 行）', task)

    def test_task_rules_are_aiwork_main_verbatim_with_commit(self):
        rc, calls, _, stderr = self.run_main_with_leg_result("gpt-5.6", project_rules=True)
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(calls["public_reads"], [
            "https://api.github.com/repos/SunJ1ayu/aiwork/commits/main",
            f"https://api.github.com/repos/SunJ1ayu/aiwork/contents/REVIEW-RULES.md?ref={calls['source_sha']}",
        ])
        self.assertIn("SunJ1ayu/aiwork main", calls["task"])
        self.assertIn("REVIEW-RULES.md", calls["task"])
        self.assertIn(calls["source_sha"], calls["task"])
        self.assertIn(calls["rules"], calls["task"])
        self.assertNotIn("PROJECT RULES DECOY", calls["task"])

    def test_project_without_rules_is_reviewed_and_published(self):
        rc, calls, _, stderr = self.run_main_with_leg_result("gpt-5.6", dry_run=False)
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(calls["leg_runs"], 1)
        self.assertEqual(calls["github_writes"], ["repos/SunJ1ayu/aiwork/pulls/12/reviews"])

    def test_unreadable_aiwork_rules_never_run_or_publish(self):
        for failure in ("main_unreadable", "rules_unreadable", "invalid_sha",
                        "not_file", "invalid_content", "truncated_content"):
            with self.subTest(failure=failure):
                rc, calls, stdout, stderr = self.run_main_with_leg_result(
                    "gpt-5.6", dry_run=False, source_failure=failure, project_rules=True)
                self.assertEqual(rc, 1)
                self.assertEqual(calls["leg_runs"], 0)
                self.assertEqual(calls["github_writes"], [])
                self.assertEqual(stdout, "")
                self.assertTrue(stderr)
                self.assertTrue(calls["public_reads"])

    def test_modified_local_rules_do_not_change_task(self):
        rc, calls, _, stderr = self.run_main_with_leg_result(
            "gpt-5.6", local_rules="MODIFIED LOCAL REVIEW RULES")
        self.assertEqual(rc, 0, stderr)
        self.assertIn(calls["rules"], calls["task"])
        self.assertNotIn("MODIFIED LOCAL REVIEW RULES", calls["task"])

    def test_task_risks_are_project_main_and_missing_risks_are_none(self):
        for present in (True, False):
            with self.subTest(present=present):
                rc, calls, _, stderr = self.run_main_with_leg_result("gpt-5.6", risks_present=present)
                self.assertEqual(rc, 0, stderr)
                section = calls["task"].split("## 项目 main 的 .aiwork/accepted-risks.md", 1)[1].split("## 改动文件", 1)[0]
                self.assertIn(calls["risks"] if present else "无", section)
                self.assertNotIn("PR RISK DECOY", section)

    def test_repository_routes_reads_snapshot_token_and_publication_together(self):
        target = "SunJ1ayu/aiwork"
        rc, calls, _, stderr = self.run_main_with_leg_result("gpt-5.6", dry_run=False, repository=target)
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(calls["github_writes"], [f"repos/{target}/pulls/12/reviews"])
        self.assertEqual(calls["token_command"][1:], ["review", "--repo", target])
        for call in calls["pr_state"]:
            self.assertEqual(call.kwargs["repository"], target)
        self.assertEqual(calls["snapshot"].kwargs["repository"], target)
        self.assertTrue(calls["task"].startswith("# SunJ1ayu/aiwork PR #12"))

    def test_repository_defaults_to_origin(self):
        cases = [
            ("https://github.com/SunJ1ayu/aiwork.git", "SunJ1ayu/aiwork"),
            ("https://github.com/SunJ1ayu/aiwork", "SunJ1ayu/aiwork"),
            ("git@github.com:SunJ1ayu/OpenDesign.git", "SunJ1ayu/OpenDesign"),
            ("ssh://git@github.com/SunJ1ayu/aiwork.git", "SunJ1ayu/aiwork"),
        ]
        for url, expected in cases:
            with self.subTest(url=url), patch.object(self.review, "run", return_value=url + "\n"):
                self.assertEqual(self.review.repository_from_origin(), expected)

    def test_unreadable_origin_requires_explicit_repo(self):
        for url in ("https://gitlab.com/a/b.git", "not a url", ""):
            with self.subTest(url=url), patch.object(self.review, "run", return_value=url + "\n"):
                with self.assertRaisesRegex(self.review.ReviewError, "--repo"):
                    self.review.repository_from_origin()
        with patch.object(self.review, "run", side_effect=self.review.ReviewError("git failed")):
            with self.assertRaisesRegex(self.review.ReviewError, "--repo"):
                self.review.repository_from_origin()

    def test_missing_origin_stops_before_credentials(self):
        with patch("sys.argv", ["review-pr", "12"]), \
                patch.object(self.review, "run", side_effect=self.review.ReviewError("git failed")) as run, \
                redirect_stderr(io.StringIO()) as err:
            rc = self.review.main()
        self.assertEqual(rc, 1)
        self.assertIn("--repo", err.getvalue())
        self.assertTrue(all(not str(call.args[0][0]).endswith("gh-app-token") for call in run.call_args_list))

    def test_invalid_repository_is_rejected_before_getting_credentials(self):
        for target in ("../aiwork", "owner/repo/extra", "https://github.com/owner/repo", "owner/repo\nother", "owner/.."):
            with self.subTest(target=target), patch("sys.argv", ["review-pr", "12", "--repo", target]), \
                    patch.object(self.review, "run") as run, redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as exit:
                    self.review.main()
                self.assertNotEqual(exit.exception.code, 0)
                run.assert_not_called()

    def test_pr_response_from_another_repository_is_rejected(self):
        pr = {"state": "open", "head": {"sha": "a" * 40, "ref": "f"},
              "base": {"sha": "b" * 40, "ref": "main", "repo": {"full_name": "SunJ1ayu/OpenDesign"}}}
        with patch.object(self.review, "github", return_value=pr) as api:
            with self.assertRaisesRegex(self.review.ReviewError, "repository"):
                self.review.pr_state(FAKE_TOKEN, 12, repository="SunJ1ayu/aiwork")
            self.assertEqual(api.call_args.args[1], "repos/SunJ1ayu/aiwork/pulls/12")

    def test_snapshot_fetches_the_selected_repository_and_its_main(self):
        pr = {"head": {"sha": "a" * 40}, "base": {"sha": "b" * 40}}
        commands = []

        def fake_git(command, **kwargs):
            commands.append(command)
            if command[-2:] == ["rev-parse", "HEAD"]:
                return "a" * 40
            if "merge-base" in command:
                return "c" * 40
            if "--binary" in command:
                return "patch"
            return ""

        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(self.review, "run", side_effect=fake_git), \
                patch.object(self.review.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"src/a.py\0", b"")):
            _, base, files, _ = self.review.snapshot(FAKE_TOKEN, pr, Path(temporary),
                                                   repository="SunJ1ayu/aiwork")
        fetch = next(command for command in commands if "fetch" in command)
        self.assertIn("https://github.com/SunJ1ayu/aiwork.git", fetch)
        self.assertNotIn("https://github.com/SunJ1ayu/OpenDesign.git", fetch)
        self.assertIn("refs/heads/main:refs/aiwork/main", fetch)
        self.assertEqual((base, files), ("c" * 40, ["src/a.py"]))

    def test_cursor_model_is_frozen_for_leg_and_result(self):
        rc, calls, body, stderr = self.run_main_with_leg_result("gpt-5.6")
        self.assertEqual(rc, 0, stderr)
        emit = calls["emit"]
        self.assertEqual(calls["leg_env"]["CURSOR_MODEL"], "gpt-5.6")
        self.assertEqual(emit[emit.index("--expected-model") + 1], "gpt-5.6")
        self.assertEqual(emit[emit.index("--family") + 1], "openai")
        self.assertIn("**aiwork-review · subcursor · gpt-5.6**", body)
        block = json.loads(body.split("```json\n", 1)[1].split("\n```", 1)[0])
        self.assertEqual((block["model"], block["family"]), ("gpt-5.6", "openai"))

    def test_cursor_result_from_another_model_is_not_published(self):
        rc, _, body, stderr = self.run_main_with_leg_result("claude-4.5-sonnet")
        self.assertEqual(rc, 1)
        self.assertEqual(body, "")
        self.assertIn("does not match selected family", stderr)

    def test_publishing_writes_only_the_review(self):
        # The review itself wakes the gate (the repo's aiwork-review-ping); a second write
        # such as a recheck label is a second doorbell, and its failure would turn a posted
        # review into exit 1. The target is this checkout's origin.
        rc, calls, stdout, stderr = self.run_main_with_leg_result("gpt-5.6", dry_run=False)
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(calls["github_writes"], ["repos/SunJ1ayu/aiwork/pulls/12/reviews"])
        self.assertEqual(stdout.strip(), "https://github.com/SunJ1ayu/OpenDesign/pull/12#pullrequestreview-1")

    def test_report_is_separated_only_at_the_leg_log_header(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "review.log"
            log.write_text("# subcursor review log\nmodel: gpt-5.6\n\nFirst paragraph.\n\n"
                           "Conclusion: PASS\n", encoding="utf-8")
            self.assertEqual(self.review.review_report(log), "First paragraph.\n\nConclusion: PASS")
            # Without the header, cutting at the first empty line would drop the report's opening.
            log.write_text("First paragraph.\n\nConclusion: PASS\n", encoding="utf-8")
            with self.assertRaisesRegex(self.review.ReviewError, "header"):
                self.review.review_report(log)

    def test_stale_head_is_refused_before_post(self):
        with self.assertRaises(ValueError):
            self.review.check_current_head("a" * 40, {"state": "open", "head": {"sha": "b" * 40}})

    def test_risks_come_from_project_main_even_when_pr_changes_them(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.run(["git", "-C", str(repo), *args], check=True,
                                      capture_output=True)
            git("init", "-q")
            git("config", "core.autocrlf", "false")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            documents = {".aiwork/accepted-risks.md": "# main 风险\r\n业主接受的平台上限。\r\n"}
            (repo / ".aiwork").mkdir()
            for path, trusted in documents.items():
                (repo / path).write_bytes(trusted.encode("utf-8"))
            git("add", ".")
            git("commit", "-qm", "main risks")
            git("update-ref", "refs/aiwork/main", "HEAD")
            for path in documents:
                (repo / path).write_text("PR 自行改写口径和豁免风险", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "untrusted PR risks")
            for path, trusted in documents.items():
                self.assertEqual(self.review.main_document(repo, path), trusted)
            git("rm", "-q", ".aiwork/accepted-risks.md")
            git("commit", "-qm", "main without risks")
            git("update-ref", "refs/aiwork/main", "HEAD")
            self.assertEqual(self.review.main_document(repo, ".aiwork/accepted-risks.md", required=False), "无")

    def test_failed_risk_lookup_is_not_treated_as_absence(self):
        with patch.object(self.review, "run", side_effect=self.review.ReviewError("fetch failed")):
            with self.assertRaises(self.review.ReviewError):
                self.review.main_document(Path("unused"), ".aiwork/accepted-risks.md", required=False)

    def test_unreadable_document_is_not_treated_as_absence(self):
        with patch.object(self.review, "run", return_value="100644 blob " + "a" * 40 + "\tfile"), \
                patch.object(self.review.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, b"", b"error")):
            for required in (True, False):
                with self.subTest(required=required), self.assertRaises(self.review.ReviewError):
                    self.review.main_document(Path("unused"), "file", required=required)

    def test_non_regular_document_is_refused(self):
        with patch.object(self.review, "run", return_value="120000 blob " + "a" * 40 + "\tfile"):
            with self.assertRaisesRegex(self.review.ReviewError, "not a regular file"):
                self.review.main_document(Path("unused"), "file", required=False)

    def test_failed_or_incomplete_leg_cannot_publish(self):
        result = {
            "process": {"state": "exited", "exit_code": 0},
            "verdict": "PASS", "failure_kind": "none", "degraded": False,
            "evidence": {"completeness": "complete"},
            "view": {"delivery_state": "complete"},
            "model": {"requested": "gpt-6-sol", "invoked": "gpt-6-sol", "reported": None},
        }
        self.assertEqual(self.review.publishable_model(result), "gpt-6-sol")
        for change in (
            {"process": {"state": "exited", "exit_code": 1}},
            {"verdict": "UNKNOWN"},
            {"failure_kind": "quota"},
            {"evidence": {"completeness": "none"}},
            {"model": {"requested": "gpt-6-sol", "invoked": "gpt-other", "reported": None}},
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.review.publishable_model(result | change)


if __name__ == "__main__":
    unittest.main()

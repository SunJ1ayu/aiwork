#!/usr/bin/env python3
"""Safety checks for the GitHub PR review publisher."""

import importlib.machinery
import importlib.util
from contextlib import redirect_stderr
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/review-pr"


def load_script():
    loader = importlib.machinery.SourceFileLoader("review_pr", str(SCRIPT))
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

    def test_leg_selection_rejects_unlisted_or_anthropic(self):
        self.assertEqual(self.review.choose_leg("subcodex"), "openai")
        self.assertEqual(self.review.choose_leg("subdeepseek"), "deepseek")
        for name in ("subclaude", "subcursor", "../subcodex"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.review.choose_leg(name)

    def test_stale_head_is_refused_before_post(self):
        with self.assertRaises(ValueError):
            self.review.check_current_head("a" * 40, {"state": "open", "head": {"sha": "b" * 40}})

    def test_task_includes_both_documents_verbatim(self):
        rules = "# 规则\r\n只有 P1 给 BLOCK。\r\n"
        risks = "# 已接受风险\n原样保留 ``` 和引号。\n"
        pr = {"head": {"sha": "a" * 40, "ref": "feature"},
              "base": {"sha": "b" * 40, "ref": "other-base"}}
        task = self.review.task_text(10, pr, "c" * 40, ["src/a.py"], "diff", rules, risks)
        self.assertIn(rules, task)
        self.assertIn(risks, task)
        self.assertIn("项目 main 的 .aiwork/review-rules.md", task)
        self.assertNotIn("REVIEW-RULES.md", task)

    def test_both_documents_come_from_main_even_when_pr_changes_them(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.run(["git", "-C", str(repo), *args], check=True,
                                      capture_output=True)
            git("init", "-q")
            git("config", "core.autocrlf", "false")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            documents = {".aiwork/review-rules.md": "# main 规则\r\n必须以此为准。\r\n",
                         ".aiwork/accepted-risks.md": "# main 风险\r\n业主接受的平台上限。\r\n"}
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
            git("rm", "-q", ".aiwork/review-rules.md")
            git("commit", "-qm", "main without rules")
            git("update-ref", "refs/aiwork/main", "HEAD")
            with self.assertRaisesRegex(self.review.ReviewError, "required review document"):
                self.review.main_document(repo, ".aiwork/review-rules.md")

    def test_failed_risk_lookup_is_not_treated_as_absence(self):
        with patch.object(self.review, "run", side_effect=self.review.ReviewError("fetch failed")):
            with self.assertRaises(self.review.ReviewError):
                self.review.main_document(Path("unused"), ".aiwork/accepted-risks.md", required=False)

    def test_missing_rules_prevent_running_a_leg(self):
        stderr = io.StringIO()
        with patch("sys.argv", ["review-pr", "12", "--dry-run"]), \
                patch.object(self.review, "run", side_effect=["fake-token", ""]), \
                patch.object(self.review, "pr_state", return_value={}), \
                patch.object(self.review, "snapshot", return_value=(Path("unused"), "a" * 40, ["file"], "diff")), \
                patch.object(self.review.subprocess, "run") as leg, redirect_stderr(stderr):
            self.assertEqual(self.review.main(), 1)
        leg.assert_not_called()
        self.assertIn("main:.aiwork/review-rules.md is missing", stderr.getvalue())

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

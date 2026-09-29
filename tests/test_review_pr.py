#!/usr/bin/env python3
"""Safety checks for the GitHub PR review publisher."""

import importlib.machinery
import importlib.util
import json
from pathlib import Path
import unittest


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

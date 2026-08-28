#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin"))

from _review_result import (  # noqa: E402
    ReviewResultError,
    canonical_subject_bytes,
    coverage_eligible,
    eligibility_reasons,
    evidence_ref,
    normalize_verdict,
    sha256_bytes,
    sha256_file,
    subject_digest,
    summarize_results,
    validate_result,
    write_result_no_clobber,
)


class ReviewResultTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.log = self.root / "leg.log"
        self.log.write_text("finding\nConclusion: PASS\n", encoding="utf-8")
        subject = {
            "manifest_version": 1,
            "task_sha256": sha256_bytes(b"review task\n"),
            "source": {
                "git_object_format": "sha1",
                "head_oid": "1" * 40,
                "index_tree_oid": "2" * 40,
                "worktree_tree_oid": "3" * 40,
            },
            "digest": None,
        }
        subject["digest"] = subject_digest(subject)
        self.result = {
            "schema_version": 2,
            "review_contract_version": 1,
            "run_id": "panel-1",
            "name": "subkimi",
            "family": "moonshot",
            "adapter": "subkimi",
            "process": {"state": "exited", "exit_code": 0},
            "model": {"requested": "kimi-code/k3", "invoked": "kimi-code/k3", "reported": None},
            "subject": subject,
            "view": {"delivery_state": "complete", "mode": "full_snapshot"},
            "verdict": "PASS",
            "degraded": False,
            "evidence": {
                "completeness": "complete",
                "ref": evidence_ref(self.log),
                "digest": sha256_file(self.log),
            },
            "normalizer_version": 1,
            "duration_ms": 12,
            "usage": {
                "input_tokens": None,
                "output_tokens": None,
                "total_tokens": None,
                "api_cost": None,
                "billing_mode": None,
            },
            "failure_kind": "none",
        }

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_valid_decisive_full_result_is_eligible(self) -> None:
        self.assertIs(validate_result(self.result), self.result)
        self.assertTrue(coverage_eligible(self.result))

    def test_unknown_timeout_degraded_and_partial_never_eligible(self) -> None:
        cases = []
        unknown = copy.deepcopy(self.result)
        unknown["verdict"] = "UNKNOWN"
        cases.append((unknown, "verdict_not_decisive"))
        timed_out = copy.deepcopy(self.result)
        timed_out["process"] = {"state": "timed_out", "exit_code": 124}
        timed_out["evidence"]["completeness"] = "partial"
        timed_out["failure_kind"] = "timeout"
        cases.append((timed_out, "process_not_successful"))
        degraded = copy.deepcopy(self.result)
        degraded["degraded"] = True
        cases.append((degraded, "degraded"))
        partial = copy.deepcopy(self.result)
        partial["view"] = {"delivery_state": "complete", "mode": "diff_bundle"}
        cases.append((partial, "view_incomplete"))
        for result, reason in cases:
            with self.subTest(reason=reason):
                self.assertFalse(coverage_eligible(result))
                self.assertIn(reason, eligibility_reasons(result))

    def test_review_contract_is_recorded_but_not_subject_identity(self) -> None:
        other = copy.deepcopy(self.result)
        other["review_contract_version"] = 2
        self.assertEqual(other["subject"]["digest"], self.result["subject"]["digest"])
        self.assertFalse(coverage_eligible(other))
        self.assertIn("review_contract_unsupported", eligibility_reasons(other))

    def test_evidence_ref_and_digest_have_separate_jobs(self) -> None:
        self.assertTrue(self.result["evidence"]["ref"].startswith("file://"))
        self.log.write_text("tampered\n", encoding="utf-8")
        self.assertFalse(coverage_eligible(self.result))
        self.assertIn("evidence_digest_mismatch", eligibility_reasons(self.result))

    def test_model_and_family_must_match_actual_adapter(self) -> None:
        invoked = copy.deepcopy(self.result)
        invoked["model"]["invoked"] = "kimi-code/k2"
        self.assertIn("model_invocation_unverified", eligibility_reasons(invoked))
        family = copy.deepcopy(self.result)
        family["family"] = "google"
        self.assertIn("adapter_family_unknown", eligibility_reasons(family))

    def test_exact_schema_rejects_unknown_fields(self) -> None:
        result = copy.deepcopy(self.result)
        result["eligible"] = True
        with self.assertRaisesRegex(ReviewResultError, "field.unknown"):
            validate_result(result)

    def test_normalizer_only_accepts_standalone_last_verdict(self) -> None:
        self.assertEqual(normalize_verdict("**Conclusion: PASS**\n"), "PASS")
        self.assertEqual(normalize_verdict("结论：NMI\n"), "NEEDS_MORE_INFO")
        self.assertEqual(
            normalize_verdict("Conclusion: PASS\nmore checking\n`Verdict: BLOCK`\n"),
            "BLOCK",
        )
        self.assertEqual(normalize_verdict("Conclusion: PASS | BLOCK | NEEDS_MORE_INFO\n"), "UNKNOWN")
        self.assertEqual(normalize_verdict("Conclusion: PASS but uncertain\n"), "UNKNOWN")

    def test_subject_canonicalization_is_stable_and_byte_sensitive(self) -> None:
        subject = self.result["subject"]
        raw = canonical_subject_bytes(subject)
        self.assertNotIn(b" ", raw)
        reordered = {
            "digest": subject["digest"],
            "source": dict(reversed(list(subject["source"].items()))),
            "task_sha256": subject["task_sha256"],
            "manifest_version": 1,
        }
        self.assertEqual(canonical_subject_bytes(reordered), raw)
        self.assertEqual(subject_digest(reordered), subject["digest"])
        changed = copy.deepcopy(subject)
        changed["task_sha256"] = sha256_bytes(b"review task")
        self.assertNotEqual(subject_digest(changed), subject["digest"])

    def test_summary_counts_distinct_family_and_detects_conflict(self) -> None:
        retry = copy.deepcopy(self.result)
        retry["name"] = "subkimi-retry"
        block = copy.deepcopy(self.result)
        block["name"] = "subgemini"
        block["family"] = "google"
        block["adapter"] = "subgemini"
        block["model"] = {"requested": "gemini-3", "invoked": "gemini-3", "reported": None}
        block["verdict"] = "BLOCK"
        summary = summarize_results([self.result, retry, block])
        self.assertEqual(summary["eligible_family_count"], 2)
        self.assertTrue(summary["conflict"])

    def test_summary_scopes_same_subject_and_run_without_mixing(self) -> None:
        cross_run = copy.deepcopy(self.result)
        cross_run["run_id"] = "panel-2"
        other_subject = copy.deepcopy(self.result)
        other_subject["run_id"] = "panel-2"
        other_subject["subject"]["source"]["worktree_tree_oid"] = "4" * 40
        other_subject["subject"]["digest"] = subject_digest(other_subject["subject"])
        digest = self.result["subject"]["digest"]
        self.assertEqual(
            summarize_results([self.result, cross_run, other_subject], subject=digest)["eligible_count"],
            2,
        )
        self.assertEqual(
            summarize_results([self.result, cross_run, other_subject], run_id="panel-1", subject=digest)[
                "eligible_count"
            ],
            1,
        )

    def test_terminal_writer_is_atomic_and_never_clobbers(self) -> None:
        path = self.root / "leg.result.json"
        self.assertTrue(write_result_no_clobber(path, self.result))
        changed = copy.deepcopy(self.result)
        changed["verdict"] = "BLOCK"
        self.assertFalse(write_result_no_clobber(path, changed))
        self.assertEqual(json.loads(path.read_text(encoding="utf-8"))["verdict"], "PASS")

    def test_emit_cli_can_leave_a_conservative_terminal_result(self) -> None:
        task = self.root / "task.md"
        task.write_bytes(b"task\n")
        path = self.root / "shadow.result.json"
        proc = subprocess.run(
            [
                sys.executable,
                str(ROOT / "bin" / "_review_result.py"),
                "emit",
                "--result",
                str(path),
                "--run-id",
                "panel-shadow",
                "--name",
                "subkimi",
                "--family",
                "moonshot",
                "--adapter",
                "subkimi",
                "--exit-code",
                "0",
                "--task-sha256",
                sha256_file(task),
                "--log",
                str(self.log),
                "--duration-ms",
                "7",
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        result = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(result["verdict"], "PASS")
        self.assertEqual(result["subject"]["source"], None)
        self.assertEqual(result["view"], {"delivery_state": "none", "mode": None})
        self.assertFalse(coverage_eligible(result))

    def test_adapter_facts_upgrade_the_supervisor_result_without_a_second_writer(self) -> None:
        facts = self.root / "attempt.facts.json"
        result_path = self.root / "attempt.result.json"
        helper = str(ROOT / "bin" / "_review_result.py")
        common_source = [
            "--git-object-format",
            "sha1",
            "--head-oid",
            "1" * 40,
            "--index-tree-oid",
            "2" * 40,
            "--worktree-tree-oid",
            "3" * 40,
        ]
        subprocess.run(
            [
                sys.executable,
                helper,
                "facts",
                "--output",
                str(facts),
                "--requested-model",
                "kimi-code/k3",
                "--invoked-model",
                "kimi-code/k3",
                *common_source,
                "--view-delivery-state",
                "complete",
                "--view-mode",
                "full_snapshot",
                "--billing-mode",
                "subscription",
            ],
            check=True,
        )
        proc = subprocess.run(
            [
                sys.executable,
                helper,
                "emit",
                "--result",
                str(result_path),
                "--facts",
                str(facts),
                "--run-id",
                "panel-facts",
                "--name",
                "subkimi",
                "--family",
                "moonshot",
                "--adapter",
                "subkimi",
                "--exit-code",
                "0",
                "--task-sha256",
                self.result["subject"]["task_sha256"],
                "--log",
                str(self.log),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        result = json.loads(result_path.read_text(encoding="utf-8"))
        self.assertEqual(result["subject"]["digest"], self.result["subject"]["digest"])
        self.assertTrue(coverage_eligible(result))


if __name__ == "__main__":
    unittest.main()

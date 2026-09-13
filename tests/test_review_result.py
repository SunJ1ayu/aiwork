#!/usr/bin/env python3
from __future__ import annotations

import os as _os
import sys as _sys

_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
import _no_egress  # noqa: F401,E402

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
        # NEEDS_MORE_INFO 是一次真做完的审查,但它不是裁决 —— 归档预算里没有它。
        # 08-28:面板侧只测到"NMI 不误伤 provider 健康",而"NMI 不算覆盖"这句话
        # 在这里才问得出,原先整条矩阵里没人问过。
        needs_more = copy.deepcopy(self.result)
        needs_more["verdict"] = "NEEDS_MORE_INFO"
        cases.append((needs_more, "verdict_not_decisive"))
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

    def test_a_review_of_an_unknown_object_is_never_coverage(self) -> None:
        # 2026-08-30 复核补钉:整条矩阵里没人单独问过「subject 不明」这一条。
        # 实测:把 `subject_unknown` 从谓词里删掉,整套判据仍然全绿 ——
        # 因为现实里它总和 view_incomplete 结伴出现,而结伴出现 = 谁都没被钉住。
        # 这里必须是**唯一**理由,否则它又变成搭别人便车的断言。
        result = copy.deepcopy(self.result)
        result["subject"]["source"] = None
        result["subject"]["digest"] = None
        self.assertIs(validate_result(result), result)
        self.assertFalse(coverage_eligible(result))
        self.assertEqual(eligibility_reasons(result), ["subject_unknown"])

    def test_a_verdict_with_no_preserved_evidence_is_never_coverage(self) -> None:
        # 同上:删掉 `evidence_incomplete` 那一条,判据也照样全绿。
        # 这条钉的是最难看的一种假覆盖 —— adapter 交了 facts 说「我 PASS 了」,
        # 但盘上一个字的评审正文都没留下,事后谁也复核不了它到底审没审。
        result = copy.deepcopy(self.result)
        result["evidence"] = {"completeness": "none", "ref": None, "digest": None}
        self.assertIs(validate_result(result), result)
        self.assertFalse(coverage_eligible(result))
        self.assertEqual(eligibility_reasons(result), ["evidence_incomplete"])

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
                "--degraded",
                "true",
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
        self.assertTrue(result["degraded"])
        self.assertFalse(coverage_eligible(result))
        self.assertIn("degraded", eligibility_reasons(result))

    def test_describe_and_failure_kind_are_derived_by_the_terminal_producer(self) -> None:
        self.log.write_text("partial output\n", encoding="utf-8")
        diagnostic = self.root / "failed.err"
        diagnostic.write_text("provider returned 429 rate limit\n", encoding="utf-8")
        path = self.root / "failed.result.json"
        proc = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "_review_result.py"), "emit",
             "--result", str(path), "--run-id", "panel-failure", "--name", "subkimi",
             "--family", "moonshot", "--adapter", "subkimi", "--exit-code", "1",
             "--task-sha256", self.result["subject"]["task_sha256"], "--log", str(self.log),
             "--diagnostic", str(diagnostic)],
            text=True, capture_output=True, check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        result = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(result["failure_kind"], "rate_limit")
        described = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "_review_result.py"), "describe", str(path)],
            text=True, capture_output=True, check=False,
        )
        self.assertEqual(described.returncode, 0, described.stderr)
        self.assertEqual(described.stdout.strip(), "exited\t1\tUNKNOWN\tfalse\trate_limit\tfalse")

    def test_provider_failure_is_classified_from_our_diagnostic_not_the_review_prose(self) -> None:
        # 2026-08-28 真事故:DeepSeek 腿评审的正是认证相关代码,正文里 "auth" 出现 13 次;
        # 它真正的死法是"没交裁决行"(.err 原话),而 failure_kind 拿正则扫**模型写的正文**,
        # 判成了 auth ⇒ 花名册和健康池都说这条腿凭证坏了。这台机器为一次假的"凭证坏了"
        # 追过六天(08-25 kimi)。报警器指错方向比不响还贵。
        self.log.write_text(
            "The auth adapter reads the auth token; auth failures return 401 here.\n",
            encoding="utf-8",
        )
        diagnostic = self.root / "noverdict.err"
        diagnostic.write_text(
            "subdeepseek-review: review output contains no standalone verdict\n",
            encoding="utf-8",
        )
        path = self.root / "noverdict.result.json"
        proc = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "_review_result.py"), "emit",
             "--result", str(path), "--run-id", "panel-noverdict", "--name", "subdeepseek",
             "--family", "deepseek", "--adapter", "subdeepseek", "--exit-code", "1",
             "--task-sha256", self.result["subject"]["task_sha256"], "--log", str(self.log),
             "--diagnostic", str(diagnostic)],
            text=True, capture_output=True, check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        result = json.loads(path.read_text(encoding="utf-8"))
        self.assertNotEqual(result["failure_kind"], "auth")
        self.assertEqual(result["failure_kind"], "runtime")

    def test_provider_failure_in_the_leg_log_is_still_classified_when_we_said_nothing(self) -> None:
        # 反向对照:agent 底座把 401 打在 stdout 上、我们自己的 .err 是空的 ⇒
        # 仍然要认出来,否则这个修法就是把真报警一起关掉了。
        self.log.write_text("Error: 401 unauthorized - invalid api key\n", encoding="utf-8")
        diagnostic = self.root / "silent.err"
        diagnostic.write_text("", encoding="utf-8")
        path = self.root / "silent.result.json"
        proc = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "_review_result.py"), "emit",
             "--result", str(path), "--run-id", "panel-silent", "--name", "subkimi",
             "--family", "moonshot", "--adapter", "subkimi", "--exit-code", "1",
             "--task-sha256", self.result["subject"]["task_sha256"], "--log", str(self.log),
             "--diagnostic", str(diagnostic)],
            text=True, capture_output=True, check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        result = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(result["failure_kind"], "auth")

    def _emit_complete(self, name: str, adapter: str, family: str, model: str, *extra: str) -> dict:
        helper = str(ROOT / "bin" / "_review_result.py")
        facts = self.root / f"{name}.facts.json"
        path = self.root / f"{name}.result.json"
        subprocess.run(
            [sys.executable, helper, "facts", "--output", str(facts),
             "--requested-model", model, "--invoked-model", model,
             "--git-object-format", "sha1", "--head-oid", "1" * 40,
             "--index-tree-oid", "2" * 40, "--worktree-tree-oid", "3" * 40,
             "--view-delivery-state", "complete", "--view-mode", "full_snapshot"],
            check=True,
        )
        proc = subprocess.run(
            [sys.executable, helper, "emit", "--result", str(path), "--facts", str(facts),
             "--run-id", f"panel-{name}", "--name", adapter, "--family", family,
             "--adapter", adapter, "--exit-code", "0",
             "--task-sha256", self.result["subject"]["task_sha256"], "--log", str(self.log), *extra],
            text=True, capture_output=True, check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(path.read_text(encoding="utf-8"))

    def test_scoped_slice_results_are_marked_in_data_and_never_old_coverage(self) -> None:
        # track sliced-panel-review:切片/整体/复核腿只对**分派给它的那部分**负责,不是旧契约里的
        # 「整任务全量评审」。只靠调度器不传 --track 是流程上的排除;手动 observe 一份切片结果
        # 就能凑满 standard track 的 1 家族预算。所以要在**数据上**就标出来。
        full = self._emit_complete("full", "subkimi", "moonshot", "kimi-code/k3")
        self.assertEqual(full["review_contract_version"], 1)
        self.assertEqual(eligibility_reasons(full), [])
        scoped = self._emit_complete(
            "scoped", "subkimi", "moonshot", "kimi-code/k3", "--review-contract-version", "2")
        self.assertEqual(scoped["review_contract_version"], 2)
        # 恰好只差这一条:别的理由混进来说明桩或实现在别处坏了,那种红不算咬住契约。
        self.assertEqual(eligibility_reasons(scoped), ["review_contract_unsupported"])
        self.assertEqual(summarize_results([scoped])["eligible_family_count"], 0)
        bad = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "_review_result.py"), "emit",
             "--result", str(self.root / "bad.result.json"), "--run-id", "panel-bad",
             "--name", "subkimi", "--family", "moonshot", "--adapter", "subkimi",
             "--exit-code", "0", "--task-sha256", self.result["subject"]["task_sha256"],
             "--review-contract-version", "3"],
            text=True, capture_output=True, check=False,
        )
        self.assertNotEqual(bad.returncode, 0)
        self.assertFalse((self.root / "bad.result.json").exists())

    def test_gpt_review_leg_has_a_known_family_identity(self) -> None:
        # subcodex(GPT 整体腿)是新腿:身份表漏了它,每份结果都会带 adapter_family_unknown,
        # 切片 status 会把一条好好的整体腿记成 ineligible。
        result = self._emit_complete("codex", "subcodex", "openai", "gpt-6-astra")
        self.assertEqual(eligibility_reasons(result), [])
        wrong = self._emit_complete("codex-wrong", "subcodex", "openai", "kimi-code/k3")
        self.assertIn("model_family_mismatch", eligibility_reasons(wrong))


if __name__ == "__main__":
    unittest.main()

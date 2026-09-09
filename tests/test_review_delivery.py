#!/usr/bin/env python3
"""Delivery identity through real Git working/index views and the archive CLI."""
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import copy
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin"))


class DeliveryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self.track = self.repo / "tracks/example"
        self.track.mkdir(parents=True)
        self.decision = {
            "schema_version": 2, "track": "example",
            "impact": {"level": "high", "factors": ["judging_control"]},
            "design": {"uncertainty": "low", "premise_attack": {
                "status": "not_required", "evidence": []}},
            "execution_plan": {"adapter": "main", "model": None},
            "outcome": {"verdict": None},
        }
        self.write_decision()
        (self.repo / "source.py").write_text("answer = 1\n")
        (self.track / "verify.md").write_text("# Pending verification\n")
        (self.track / "tasks.md").write_text("- [ ] implement feature\n")
        (self.track / "design.md").write_text("# Design\n")
        (self.track / "evidence").mkdir()
        (self.track / "evidence/oracle.py").write_text("assert answer == 1\n")
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "test")
        self.git("config", "user.email", "test@localhost")
        self.git("add", ".")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-qm", "baseline")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args])

    def write_decision(self):
        (self.track / "decision.json").write_text(json.dumps(self.decision) + "\n")

    def fingerprint(self, source="working", tree=None):
        from _review_delivery import delivery_fingerprint
        return delivery_fingerprint(self.repo, "example", source=source, tree=tree)

    def validate(self, source="working"):
        return subprocess.run([str(ROOT / "bin/track-record"), "validate", "--phase", "archive",
                               "--source", source, str(self.track)], capture_output=True, text=True)

    def install_review(self, *, bound=True):
        from _review_result import evidence_ref, sha256_file, sha256_bytes, subject_digest
        delivery = self.fingerprint()
        tree = self.git("rev-parse", "HEAD^{tree}").decode().strip()
        subject = {
            "manifest_version": 2 if bound else 1,
            "task_sha256": sha256_bytes(b"review example"),
            "source": {"git_object_format": "sha1",
                       "head_oid": self.git("rev-parse", "HEAD").decode().strip(),
                       "index_tree_oid": tree, "worktree_tree_oid": tree}, "digest": None,
        }
        if bound:
            subject["delivery"] = {"policy_version": 1, "track": "example", "digest": delivery}
        subject["digest"] = subject_digest(subject)
        log = Path(self.temp.name) / "review.log"
        log.write_text("Conclusion: PASS\n")
        legs = []
        for name, family, adapter, model in (
            ("submimo", "xiaomi", "submimo", "xiaomi/mimo-v2.5-pro"),
            ("subdeepseek", "deepseek", "subdeepseek-agent", "deepseek-v4-flash"),
        ):
            legs.append({
                "schema_version": 2, "review_contract_version": 1, "run_id": "review-1",
                "name": name, "family": family, "adapter": adapter,
                "process": {"state": "exited", "exit_code": 0},
                "model": {"requested": model, "invoked": model, "reported": None},
                "subject": copy.deepcopy(subject), "view": {"delivery_state": "complete", "mode": "full_snapshot"},
                "verdict": "PASS", "degraded": False,
                "evidence": {"completeness": "complete", "ref": evidence_ref(log), "digest": sha256_file(log)},
                "normalizer_version": 1, "duration_ms": 1, "failure_kind": "none",
                "usage": {"input_tokens": None, "output_tokens": None, "total_tokens": None,
                          "api_cost": None, "billing_mode": None},
            })
        obs = self.track / "observations"
        obs.mkdir(exist_ok=True)
        for controller, run, values in (("panel-review", "review-1", legs), ("runlog", "test-1", None)):
            event = {
                "schema_version": 2 if values else 1, "track": "example", "run_id": run,
                "controller": controller, "event": "execution_finished", "label": run,
                "started_at": "2026-09-09T00:00:00Z", "finished_at": "2026-09-09T00:00:01Z",
                "duration_ms": 1000, "exit_code": 0,
                "actual": {"adapter": controller, "model": None, "risk": "high" if values else None,
                           "degraded": False, "work_exit_code": 0, "legs": values},
                "usage": {"input_tokens": None, "output_tokens": None, "total_tokens": None,
                          "api_cost": None, "billing_mode": None},
            }
            (obs / (run + ".json")).write_text(json.dumps(event))
        self.decision["outcome"]["verdict"] = "PASS"
        self.write_decision()

    def test_views_equal_and_scan_does_not_change_source_index(self):
        before = (self.repo / ".git/index").read_bytes()
        self.assertEqual(self.fingerprint(), self.fingerprint("staged"))
        self.assertEqual(self.fingerprint(), self.fingerprint(tree="HEAD^{tree}"))
        self.assertEqual(before, (self.repo / ".git/index").read_bytes())
        self.assertEqual(self.git("status", "--porcelain"), b"")

    def test_source_and_oracle_changes_invalidate(self):
        baseline = self.fingerprint()
        for path in (self.repo / "source.py", self.track / "evidence/oracle.py", self.track / "design.md"):
            original = path.read_bytes()
            path.write_bytes(original + b"changed\n")
            self.assertNotEqual(baseline, self.fingerprint(), str(path))
            path.write_bytes(original)
        self.assertEqual(baseline, self.fingerprint())

    def test_add_delete_rename_mode_and_symlink_are_content_changes(self):
        baseline = self.fingerprint()
        added = self.repo / "new file.py"
        added.write_bytes(b"new\x00bytes")
        self.assertNotEqual(baseline, self.fingerprint())
        added.unlink()
        original = self.repo / "source.py"
        original.rename(added)
        self.assertNotEqual(baseline, self.fingerprint())
        added.rename(original)
        original.chmod(0o755)
        self.assertNotEqual(baseline, self.fingerprint())
        original.chmod(0o644)
        data = original.read_bytes()
        original.unlink()
        self.assertNotEqual(baseline, self.fingerprint())
        original.symlink_to("tracks/example/verify.md")
        self.assertNotEqual(baseline, self.fingerprint())
        original.unlink()
        original.write_bytes(data)
        self.assertEqual(baseline, self.fingerprint())

    def test_closeout_and_archive_relocation_are_free(self):
        baseline = self.fingerprint()
        (self.track / "verify.md").write_text("# Final review\n")
        (self.track / "tasks.md").write_text("- [x] implement feature\n")
        self.decision["outcome"]["verdict"] = "PASS"
        self.write_decision()
        (self.track / "observations").mkdir()
        (self.track / "observations/run.json").write_text("{}\n")
        receipt = self.track / "evidence/20260909T010203Z-01-test.txt"
        receipt.write_text("# runlog receipt —— fixture\nrunlog: test rc=0\n")
        self.assertEqual(baseline, self.fingerprint())
        archive = self.repo / "tracks/archive/example"
        archive.parent.mkdir()
        self.track.rename(archive)
        self.track = archive
        self.assertEqual(baseline, self.fingerprint())
        self.git("add", "-A")
        self.assertEqual(baseline, self.fingerprint("staged"))

    def test_risk_task_text_and_fake_receipt_cannot_hide(self):
        baseline = self.fingerprint()
        self.decision["impact"]["factors"].append("permissions")
        self.write_decision()
        self.assertNotEqual(baseline, self.fingerprint())
        self.decision["impact"]["factors"].pop()
        self.write_decision()
        (self.track / "tasks.md").write_text("- [ ] different feature\n")
        self.assertNotEqual(baseline, self.fingerprint())
        (self.track / "tasks.md").write_text("- [ ] implement feature\n")
        fake = self.track / "evidence/20260909T010203Z-01-test.txt"
        fake.write_text("assert False\n")
        self.assertNotEqual(baseline, self.fingerprint())

    def test_closeout_symlink_or_executable_does_not_get_excluded(self):
        baseline = self.fingerprint()
        path = self.track / "verify.md"
        path.chmod(0o755)
        self.assertNotEqual(baseline, self.fingerprint())
        path.unlink()
        path.symlink_to("../../source.py")
        self.assertNotEqual(baseline, self.fingerprint())

    def test_other_tracks_are_not_masked(self):
        baseline = self.fingerprint()
        other = self.repo / "tracks/other"
        other.mkdir()
        (other / "verify.md").write_text("new content\n")
        self.assertNotEqual(baseline, self.fingerprint())

    def test_archive_rejects_stale_review_and_accepts_closeout(self):
        self.install_review()
        self.assertEqual(self.validate().returncode, 0, self.validate().stdout)
        (self.track / "verify.md").write_text("final arbitration\n")
        self.assertEqual(self.validate().returncode, 0)
        (self.repo / "source.py").write_text("answer = 2\n")
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("review_delivery", result.stdout + result.stderr)

    def test_staged_and_working_cannot_answer_for_each_other(self):
        self.install_review()
        self.git("add", "-A")
        (self.repo / "source.py").write_text("answer = 2\n")
        self.assertNotEqual(self.validate().returncode, 0)
        self.assertEqual(self.validate("staged").returncode, 0)
        self.git("add", "source.py")
        (self.repo / "source.py").write_text("answer = 1\n")
        self.assertEqual(self.validate().returncode, 0)
        self.assertNotEqual(self.validate("staged").returncode, 0)

    def test_unbound_historical_review_does_not_authorize_v2(self):
        self.install_review(bound=False)
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("review_delivery", result.stdout + result.stderr)

    def test_new_track_scaffold_requires_binding(self):
        # 模板决定"以后每一个新 track 有没有这道闸"。它停在 v1 时，闸对新交付
        # 永远是 legacy-unbound —— 实现全绿、机制却一次都不会生效。
        project = Path(self.temp.name) / "project"
        project.mkdir()
        created = subprocess.run([str(ROOT / "bin/track"), "new", "scaffolded", str(project)],
                                 capture_output=True, text=True)
        self.assertEqual(created.returncode, 0, created.stderr)
        result = subprocess.run([str(ROOT / "bin/track-record"), "validate", "--phase", "shape",
                                 str(project / "tracks/scaffolded")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("delivery=required", result.stdout)

    def test_delivery_cannot_be_downgraded(self):
        self.decision["schema_version"] = 1
        self.write_decision()
        result = subprocess.run([str(ROOT / "bin/track-record"), "validate", "--phase", "shape",
                                 str(self.track)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("downgrade", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

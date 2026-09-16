#!/usr/bin/env python3
"""track preflight 的判据(主 agent 亲写;规格在 tracks/review-convergence-and-preflight/design.md)。

判的是:最终评审之前跑一遍归档检查里能提前查的部分 ——
  · 分清「现在就挡(BLOCK)」「要等最终评审/收尾(PENDING)」「通过(OK)」「检查本身没跑成(ERROR)」;
  · 一项挡住不短路其余各项;
  · **零持久副作用**(不搬目录、不删树、不暂存、不写 decision/observation、不刷 index);
  · 不是归档凭据:预检之后照跑 archive,该拒照拒。

锁死的假绿路线:
  ① 输出说"没动"其实动了 ⇒ 每一幕先比盘上快照(HEAD/refs/逻辑 index/index 字节/worktree 列表/
     仓内全部文件含未跟踪/.git/objects 清单/worktree 根下全部文件),再看分类。
  ② 首错即停,把后面能查的项吞掉 ⇒ P2/P3 同时摆两类问题,要求都点名。
  ③ 把检查本身出错降格成 PENDING/OK ⇒ P7 用崩溃桩,要求 rc=2。
  ④ 把"verdict 已写 PASS 却缺执行收据"当成 PENDING(以为是"还没到时候")⇒ P10 要求 BLOCK。
  ⑤ 预检里复用了归档的 worktree 清理、顺手把干净的树删了 ⇒ P8/P8b 要求树还在。
  ⑥ 预检过了留下什么缓存/标记让 archive 免检 ⇒ P9 预检后照跑 archive,要求拒。
  ⑦ 新 phase 泄进旧 phase(archive 也开始把 null verdict 当 PENDING)⇒ P14。

Run:  python3 /root/aiwork/tests/test_track_preflight.py
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import copy  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import re  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(os.environ.get("TRACK_BIN", ROOT / "bin"))
sys.path.insert(0, str(ROOT / "bin"))

LINE = re.compile(r"^\s+(OK|BLOCK|PENDING|ERROR)\s+([a-z-]+)\b", re.M)
QUIET_GIT = dict(os.environ, GIT_OPTIONAL_LOCKS="0")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Fixture:
    """一个 dispatch 合法、还没做最终评审的 typed high track。"""

    def __init__(self, base: Path, name: str = "example"):
        self.base = base
        self.repo = base / "repo"
        self.wt_root = base / "worktrees"
        self.wt_root.mkdir()
        self.name = name
        self.track = self.repo / "tracks" / name
        self.track.mkdir(parents=True)
        self.decision = {
            "schema_version": 2, "track": name,
            "impact": {"level": "high", "factors": ["judging_control"]},
            "design": {"uncertainty": "low", "premise_attack": {"status": "not_required", "evidence": []}},
            "execution_plan": {"adapter": "main", "model": None},
            "outcome": {"verdict": None},
        }
        self.write_decision()
        (self.repo / "source.py").write_text("answer = 1\n")
        (self.track / "proposal.md").write_text("# Proposal\n\n- goal: example\n")
        (self.track / "design.md").write_text("# Design\n\n- approach: example\n")
        (self.track / "tasks.md").write_text("- [ ] implement\n")
        (self.track / "verify.md").write_text("# Verify\n\n- 无机器证据:判据夹具,不跑真判据。\n")
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "t")
        self.git("config", "user.email", "t@localhost")
        self.commit_all("baseline")

    # ---- git / files -------------------------------------------------------
    def git(self, *args, cwd=None) -> bytes:
        return subprocess.check_output(["git", "-C", str(cwd or self.repo), *args], env=QUIET_GIT)

    def commit_all(self, msg):
        self.git("add", "-A")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-qm", msg)

    def write_decision(self):
        (self.track / "decision.json").write_text(json.dumps(self.decision) + "\n")

    def add_tree(self, job: str, dirty: bool) -> Path:
        tree = self.wt_root / self.name / job
        tree.parent.mkdir(parents=True, exist_ok=True)
        self.git("worktree", "add", "-q", "-b", f"delegate/{self.name}/{job}", str(tree), "HEAD")
        if dirty:
            (tree / "only-copy.txt").write_text("唯一一份改动\n")
        return tree

    # ---- commands ----------------------------------------------------------
    def env(self, bin_dir: Path = BIN):
        return dict(os.environ, DELEGATE_WORKTREE_ROOT=str(self.wt_root), PATH=f"{bin_dir}:{os.environ['PATH']}")

    def preflight(self, *args, bin_dir: Path = BIN, name=None):
        argv = ["bash", str(bin_dir / "track"), "preflight"]
        if name is not False:
            argv.append(name or self.name)
        argv += [str(self.repo), *args] if name is not False else []
        run = subprocess.run(argv, capture_output=True, text=True, env=self.env(bin_dir), cwd=str(self.repo))
        return run.returncode, run.stdout + run.stderr

    def archive(self):
        run = subprocess.run(["bash", str(BIN / "track"), "archive", self.name, str(self.repo)],
                             capture_output=True, text=True, env=self.env(), cwd=str(self.repo))
        return run.returncode, run.stdout + run.stderr

    def record(self, phase: str):
        run = subprocess.run([str(BIN / "track-record"), "validate", "--phase", phase, str(self.track)],
                             capture_output=True, text=True, env=self.env(), cwd=str(self.repo))
        return run.returncode, run.stdout + run.stderr

    # ---- snapshot ----------------------------------------------------------
    def _walk(self, top: Path, skip_git_dir: bool):
        rows = []
        if not top.exists():
            return rows
        for dirpath, dirnames, filenames in os.walk(top):
            rel_dir = Path(dirpath).relative_to(top).as_posix()
            if skip_git_dir and (rel_dir == ".git" or rel_dir.startswith(".git/")):
                dirnames[:] = []
                continue
            dirnames.sort()
            rows.append(("dir", rel_dir, ""))
            for name in sorted(filenames):
                p = Path(dirpath) / name
                rel = p.relative_to(top).as_posix()
                if skip_git_dir and rel.startswith(".git/"):
                    continue
                if p.is_symlink():
                    rows.append(("link", rel, os.readlink(p)))
                else:
                    rows.append(("file", rel, sha(p.read_bytes())))
        return rows

    def snapshot(self):
        git_dir = self.repo / ".git"
        objects = sorted(p.relative_to(git_dir).as_posix() for p in (git_dir / "objects").rglob("*") if p.is_file())
        wt_meta = []
        if (git_dir / "worktrees").exists():
            for p in sorted((git_dir / "worktrees").rglob("*")):
                if p.is_file():
                    wt_meta.append((p.relative_to(git_dir).as_posix(), sha(p.read_bytes())))
        return {
            "head": self.git("rev-parse", "HEAD"),
            "refs": self.git("for-each-ref"),
            "index_logical": self.git("ls-files", "-s", "-z"),
            "index_bytes": sha((git_dir / "index").read_bytes()),
            "worktree_list": self.git("worktree", "list", "--porcelain"),
            "files": self._walk(self.repo, skip_git_dir=True),
            "objects": objects,
            "worktree_meta": wt_meta,
            "worktree_root": self._walk(self.wt_root, skip_git_dir=False),
        }


def statuses(output: str):
    return [(m.group(1), m.group(2)) for m in LINE.finditer(output)]


class PreflightTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="aiwork-preflight-")
        self.addCleanup(self.tmp.cleanup)
        self.fx = Fixture(Path(self.tmp.name))

    # 每一幕都走这一步:先比盘上,再看分类
    def run_unchanged(self, *args, **kw):
        before = self.fx.snapshot()
        rc, out = self.fx.preflight(*args, **kw)
        after = self.fx.snapshot()
        for key in before:
            self.assertEqual(before[key], after[key], f"预检改了盘上状态:{key}\n--- 输出 ---\n{out}")
        return rc, out

    def assertHas(self, out, status, check):
        self.assertIn((status, check), statuses(out), f"缺一行 {status} {check}\n--- 输出 ---\n{out}")

    def assertNone(self, out, status):
        hits = [c for s, c in statuses(out) if s == status]
        self.assertEqual(hits, [], f"不该有 {status}:{hits}\n--- 输出 ---\n{out}")

    # ------------------------------------------------------------------ P1
    def test_p1_before_final_review_is_pending_not_blocked(self):
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 3, out)
        self.assertHas(out, "PENDING", "decision")
        self.assertIn("outcome.verdict", out)
        self.assertNone(out, "BLOCK")
        self.assertNone(out, "ERROR")
        for check in ("views", "verify", "receipts", "ephemeral", "destination", "worktrees"):
            self.assertHas(out, "OK", check)
        self.assertNotIn("status=valid phase=archive", out, "预检输出不许长得像归档凭据")

    # ------------------------------------------------------------------ P2
    def test_p2_ephemeral_ref_blocks_and_does_not_short_circuit(self):
        design = self.fx.track / "design.md"
        design.write_text(design.read_text() + "- 完整输出见 `/tmp/claude-0/x/plan.log`\n")
        self.fx.commit_all("design cites tmp")
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 1, out)
        self.assertHas(out, "BLOCK", "ephemeral")
        self.assertRegex(out, r"design\.md:4\b")
        self.assertHas(out, "PENDING", "decision")

    # ------------------------------------------------------------------ P3
    def test_p3_decision_block_and_other_block_both_reported(self):
        self.fx.decision["impact"]["level"] = "standard"
        self.fx.write_decision()
        prop = self.fx.track / "proposal.md"
        prop.write_text(prop.read_text() + "- 草稿在 scratchpad/notes.md\n")
        self.fx.commit_all("bad decision + scratchpad")
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 1, out)
        self.assertHas(out, "BLOCK", "decision")
        self.assertIn("impact.high_factor", out)
        self.assertHas(out, "BLOCK", "ephemeral")
        self.assertIn("proposal.md:", out)

    # ------------------------------------------------------------------ P4
    def test_p4a_uncited_red_receipt_is_pending(self):
        ev = self.fx.track / "evidence"
        ev.mkdir()
        rel = f"tracks/{self.fx.name}/evidence/20260916T000000Z-01-probe.txt"
        (ev / "20260916T000000Z-01-probe.txt").write_text(
            f"# receipt\nrunlog: probe rc=1 commit=abc1234 dirty=no at=2026-09-16T00:00:00Z file={rel}\n")
        self.fx.commit_all("red receipt")
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 3, out)
        self.assertHas(out, "PENDING", "receipts")
        self.assertIn("5b", out)
        self.assertNone(out, "BLOCK")

    def test_p4b_pasted_receipt_without_evidence_blocks(self):
        verify = self.fx.track / "verify.md"
        verify.write_text(verify.read_text()
                          + "\n```\nrunlog: ghost rc=0 commit=abc1234 dirty=no at=2026-09-16T00:00:00Z "
                            f"file=tracks/{self.fx.name}/evidence/20260916T000000Z-01-ghost.txt\n```\n")
        self.fx.commit_all("ghost receipt")
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 1, out)
        self.assertHas(out, "BLOCK", "receipts")
        self.assertIn("5a", out)

    # ------------------------------------------------------------------ P5
    def test_p5_view_difference_blocks_and_file_stays_untracked(self):
        (self.fx.repo / "stray-notes.txt").write_text("没提交的东西\n")
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 1, out)
        self.assertHas(out, "BLOCK", "views")
        self.assertIn("stray-notes.txt", out)
        self.assertEqual(self.fx.git("ls-files", "stray-notes.txt"), b"")

    # ------------------------------------------------------------------ P6
    def test_p6_existing_archive_destination_blocks(self):
        dest = self.fx.repo / "tracks" / "archive" / self.fx.name
        dest.mkdir(parents=True)
        (dest / "leftover.txt").write_text("上次取回留下的\n")
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 1, out)
        self.assertHas(out, "BLOCK", "destination")
        self.assertEqual((dest / "leftover.txt").read_text(), "上次取回留下的\n")

    # ------------------------------------------------------------------ P7
    def test_p7_checker_crash_is_error_not_pending(self):
        fake = Path(self.tmp.name) / "fakebin"
        fake.mkdir()
        for entry in BIN.iterdir():
            if entry.name != "track-record":
                (fake / entry.name).symlink_to(entry)
        stub = fake / "track-record"
        stub.write_text("#!/bin/sh\necho 'Traceback (most recent call last): boom' >&2\nexit 1\n")
        stub.chmod(0o755)
        rc, out = self.run_unchanged(bin_dir=fake)
        self.assertEqual(rc, 2, out)
        self.assertHas(out, "ERROR", "decision")

    # ------------------------------------------------------------------ P8
    def test_p8_worktree_checks_never_remove_trees(self):
        clean = self.fx.add_tree("job-clean", dirty=False)
        dirty = self.fx.add_tree("job-dirty", dirty=True)
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 1, out)
        self.assertHas(out, "BLOCK", "worktrees")
        self.assertTrue(clean.is_dir() and dirty.is_dir(), out)
        self.assertEqual((dirty / "only-copy.txt").read_text(), "唯一一份改动\n")
        self.assertIn(b"delegate/example/job-clean", self.fx.git("branch", "--list"))

    def test_p8b_clean_merged_tree_is_ok_and_still_there(self):
        clean = self.fx.add_tree("job-clean", dirty=False)
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 3, out)
        self.assertHas(out, "OK", "worktrees")
        self.assertTrue(clean.is_dir(), "预检把 archive 才该收的树删了")

    # ------------------------------------------------------------------ P9
    def test_p9_archive_still_refuses_after_preflight(self):
        rc, out = self.fx.preflight()
        self.assertEqual(rc, 3, out)
        arc_rc, arc_out = self.fx.archive()
        self.assertNotEqual(arc_rc, 0, arc_out)
        self.assertTrue(self.fx.track.is_dir(), arc_out)
        self.assertFalse((self.fx.repo / "tracks" / "archive" / self.fx.name).exists(), arc_out)

    # ------------------------------------------------------------------ P10
    def test_p10_decided_pass_without_execution_is_block_not_pending(self):
        self.fx.decision["outcome"]["verdict"] = "PASS"
        self.fx.write_decision()
        self.fx.commit_all("premature PASS")
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 1, out)
        self.assertHas(out, "BLOCK", "decision")
        self.assertIn("observation.required", out)
        arc_rc, arc_out = self.fx.archive()
        self.assertNotEqual(arc_rc, 0, arc_out)
        self.assertTrue(self.fx.track.is_dir(), arc_out)

    # ------------------------------------------------------------------ P11
    def install_bound_review(self):
        from _review_delivery import delivery_fingerprint
        from _review_result import evidence_ref, sha256_bytes, sha256_file, subject_digest
        repo, name = self.fx.repo, self.fx.name
        delivery = delivery_fingerprint(repo, name, source="working")
        tree = self.fx.git("rev-parse", "HEAD^{tree}").decode().strip()
        subject = {
            "manifest_version": 2, "task_sha256": sha256_bytes(b"review example"),
            "source": {"git_object_format": "sha1", "head_oid": self.fx.git("rev-parse", "HEAD").decode().strip(),
                       "index_tree_oid": tree, "worktree_tree_oid": tree},
            "delivery": {"policy_version": 1, "track": name, "digest": delivery},
            "digest": None,
        }
        subject["digest"] = subject_digest(subject)
        log = Path(self.tmp.name) / "review.log"
        log.write_text("Conclusion: PASS\n")
        legs = []
        for leg, family, adapter, model in (
            ("submimo", "xiaomi", "submimo", "xiaomi/mimo-v2.5-pro"),
            ("subdeepseek", "deepseek", "subdeepseek-agent", "deepseek-v4-flash"),
        ):
            legs.append({
                "schema_version": 2, "review_contract_version": 1, "run_id": "review-1",
                "name": leg, "family": family, "adapter": adapter,
                "process": {"state": "exited", "exit_code": 0},
                "model": {"requested": model, "invoked": model, "reported": None},
                "subject": copy.deepcopy(subject), "view": {"delivery_state": "complete", "mode": "full_snapshot"},
                "verdict": "PASS", "degraded": False,
                "evidence": {"completeness": "complete", "ref": evidence_ref(log), "digest": sha256_file(log)},
                "normalizer_version": 1, "duration_ms": 1, "failure_kind": "none",
                "usage": {"input_tokens": None, "output_tokens": None, "total_tokens": None,
                          "api_cost": None, "billing_mode": None},
            })
        obs = self.fx.track / "observations"
        obs.mkdir(exist_ok=True)
        for controller, run, values in (("panel-review", "review-1", legs), ("runlog", "test-1", None)):
            event = {
                "schema_version": 2 if values else 1, "track": name, "run_id": run,
                "controller": controller, "event": "execution_finished", "label": run,
                "started_at": "2026-09-16T00:00:00Z", "finished_at": "2026-09-16T00:00:01Z",
                "duration_ms": 1000, "exit_code": 0,
                "actual": {"adapter": controller, "model": None, "risk": "high" if values else None,
                           "degraded": False, "work_exit_code": 0, "legs": values},
                "usage": {"input_tokens": None, "output_tokens": None, "total_tokens": None,
                          "api_cost": None, "billing_mode": None},
            }
            (obs / (run + ".json")).write_text(json.dumps(event))

    def test_p11_bound_review_leaves_only_outcome_then_drift_is_pending_review(self):
        self.install_bound_review()
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 3, out)
        self.assertHas(out, "PENDING", "decision")
        self.assertIn("outcome.verdict", out)
        self.assertNotIn("observation.review_delivery", out, "评审已绑定当前内容,不该再要求重审")
        self.assertNone(out, "BLOCK")

        design = self.fx.track / "design.md"
        design.write_text(design.read_text() + "- 评审之后又改了一句\n")
        self.fx.commit_all("drift after review")
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 3, out)
        self.assertHas(out, "PENDING", "decision")
        self.assertIn("observation.review_delivery", out)
        self.assertNone(out, "BLOCK")

    # ------------------------------------------------------------------ P12
    def test_p12_legacy_track_placeholder_is_pending(self):
        (self.fx.track / "decision.json").unlink()
        (self.fx.track / "verify.md").write_text("# Verify\n\n- Verdict: <PASS|BLOCK>\n- 无机器证据:判据夹具。\n")
        self.fx.commit_all("legacy")
        rc, out = self.run_unchanged()
        self.assertEqual(rc, 3, out)
        self.assertHas(out, "OK", "decision")
        self.assertHas(out, "PENDING", "verify")
        self.assertNone(out, "BLOCK")

    # ------------------------------------------------------------------ P13
    def test_p13_usage_errors(self):
        rc, out = self.fx.preflight(name=False)
        self.assertEqual(rc, 2, out)
        rc, out = self.run_unchanged(name="no-such-track")
        self.assertEqual(rc, 2, out)

    # ------------------------------------------------------------------ P14
    def test_p14_new_phase_does_not_leak_into_old_phases(self):
        rc, out = self.fx.record("archive")
        self.assertEqual(rc, 1, out)
        self.assertIn("rule=field.decided", out)
        self.assertIn("verdict=BLOCK", out)
        self.assertNotIn("PENDING", out)
        rc, out = self.fx.record("dispatch")
        self.assertEqual(rc, 0, out)
        rc, out = self.fx.record("preflight")
        self.assertEqual(rc, 3, out)
        self.assertIn("verdict=PENDING", out)
        self.assertNotIn("status=valid", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)

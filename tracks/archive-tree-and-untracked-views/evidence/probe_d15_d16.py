#!/usr/bin/env python3
"""主裁亲跑的探针:不信账本自述,现场复现 D15 / D16。

复用 tests/test_review_delivery.py 的真夹具(同一套 setUp),只加两个观察点。
"""
import json, subprocess, sys, unittest
from pathlib import Path

sys.path.insert(0, "/root/aiwork/tests")
from test_review_delivery import DeliveryTest, ROOT  # noqa: E402


class Probe(DeliveryTest):
    def commit(self, msg):
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-qm", msg)

    def validate_at(self, path, source="staged"):
        return subprocess.run([str(ROOT / "bin/track-record"), "validate", "--phase", "archive",
                               "--source", source, str(path)], capture_output=True, text=True)

    # ---------- D16 ----------
    def test_probe_d16_untracked_splits_the_two_views(self):
        print("\n===== D16:评审时仓里有未跟踪文件 ⇒ 归档那次 commit 必然 BLOCK =====")
        print("干净树:  working == staged ?", self.fingerprint() == self.fingerprint("staged"))
        # 真实顺序:未跟踪文件(任务书)在**评审之前**就躺在仓里
        (self.repo / "任务书.md").write_text("这是一份还没入库的任务书\n")   # 未跟踪
        self.install_review()          # 评审绑定的 = 含未跟踪的 working 视图
        self.git("add", "tracks"); self.commit("track 收口(任务书仍未入库)")
        w, s = self.fingerprint(), self.fingerprint("staged")
        print("有未跟踪:working =", w[:23], "...")
        print("          staged  =", s[:23], "...")
        print("          相等?", w == s)
        r_work = self.validate_at(self.track, "working")
        r_stag = self.validate_at(self.track, "staged")
        print("validate --source working  rc =", r_work.returncode)
        print("validate --source staged   rc =", r_stag.returncode)
        print("---- staged 那条的原话 ----")
        print((r_stag.stdout + r_stag.stderr).strip())
        print("---------------------------")
        # 它给的药方是"重跑 panel-review"。照做一次,看能不能出这个坑。
        self.install_review()                       # = 重跑评审,重新绑定当前 working 视图
        self.git("add", "tracks"); self.commit("重跑评审后的收口")
        again = self.validate_at(self.track, "staged")
        print("照药方重跑 panel-review 之后 validate --source staged rc =", again.returncode,
              "(1 = 药方无效,而每转一圈烧掉一整轮 panel)")

    # ---------- D15 ----------
    def test_probe_d15_rearchive_checks_the_first_tree(self):
        print("\n===== D15:re-archive 后复验取的是第一次归档那棵树 =====")
        self.install_review()
        self.git("add", "-A"); self.commit("收口")
        archived = self.repo / "tracks/archive/example"
        archived.parent.mkdir(parents=True, exist_ok=True)
        self.git("mv", "tracks/example", "tracks/archive/example"); self.commit("归档 #1")
        print("第一次归档后 validate(staged) rc =", self.validate_at(archived).returncode, "(应为 0)")

        # 业主级手工操作:取回 → 改内容 → 再归档。中间没有任何新评审。
        self.git("mv", "tracks/archive/example", "tracks/example"); self.commit("手工取回")
        (self.repo / "source.py").write_text("answer = 2\n")     # 交付内容变了
        self.git("add", "-A"); self.commit("改了被交付的源码,没有重跑评审")
        self.git("mv", "tracks/example", "tracks/archive/example"); self.commit("归档 #2")

        r = self.validate_at(archived)
        print("改内容后再归档 validate(staged) rc =", r.returncode, "(期望 !=0;若为 0 = 旧评审授权了新交付)")
        print("输出:", (r.stdout + r.stderr).strip())
        hist = subprocess.run(["git", "-C", str(self.repo), "log", "--no-renames", "--reverse",
                               "--diff-filter=A", "--format=%H %s", "--",
                               "tracks/archive/example/decision.json"],
                              capture_output=True, text=True).stdout.strip()
        print("---- --diff-filter=A 回溯到的提交(实现取的是第一行) ----")
        print(hist)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0], "-v", "Probe"], exit=False)

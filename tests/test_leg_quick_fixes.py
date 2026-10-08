#!/usr/bin/env python3
"""Oracle for track legs-quick-fixes (main agent written; offline, never calls a provider).

Each test pins one observed failure of a real review leg:
  A1  a leg wrote a full report but no verdict line (MiMo 09-14 round two: submimo's
      message never states the contract; GLM 09-07 drifted to `结论：通过 (PASS)` with the
      contract placed before a long task body).
  A2  Kimi's `403 You've reached your 5-hour usage limit` was recorded as failure_kind
      runtime (09-09): the CLI's error line lives in the leg log, not in our diagnostic,
      and `403` would have matched auth before any limit wording anyway.
  A3  self-healing window limits must not push a leg toward the dead streak.
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import http.server
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin"
CONTRACT = "Conclusion: PASS | BLOCK | NEEDS_MORE_INFO"
TASK_MARKER = "UNIQUE_TASK_BODY_7f3a91"
# Both lines are verbatim kimi-code CLI output from real review legs, not fabricated shapes:
# logs/panel-delivery-r3-20260909T040119Z.subkimi.log (09-09) and logs/panel-rcpycache.subkimi.log (08-08).
KIMI_LIMIT = ("error: failed to run prompt: provider.auth_error: 403 You've reached your "
              "5-hour usage limit. Your quota will reset when the current 5-hour window ends.")
KIMI_BILLING_CYCLE = ("error: failed to run prompt: provider.api_error: 403 You've reached your usage "
                      "limit for this billing cycle. Your quota will be refreshed in the next cycle. To "
                      "continue now, purchase extra usage or upgrade your plan: https://www.kimi.com/code/#pricing")
SCRUB = ("KIMI_", "ZHIPU_", "DEEPSEEK_", "MIMO_",
         "OPENCODE_", "GROK_")


class LegCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.d = Path(self.tmp.name)
        self.bin = self.d / "bin"
        self.bin.mkdir()
        for helper in BIN.glob("_*"):
            if helper.is_file():
                shutil.copy2(helper, self.bin / helper.name)
        shutil.copy2(BIN / "aiwork-config", self.bin / "aiwork-config")
        self.repo = self.d / "repo"
        self.repo.mkdir()
        for args in (("init", "-q"), ("config", "user.email", "t@t"), ("config", "user.name", "t")):
            subprocess.run(["git", "-C", str(self.repo), *args], check=True)
        (self.repo / "a.txt").write_text("base\n")
        subprocess.run(["git", "-C", str(self.repo), "add", "-A"], check=True)
        subprocess.run(["git", "-C", str(self.repo), "commit", "-qm", "base"], check=True)
        self.task = self.d / "task.md"
        self.task.write_text("# review\n" + ("context line\n" * 40) + TASK_MARKER + "\n")

    def copy(self, *names):
        for name in names:
            shutil.copy2(BIN / name, self.bin / name)

    def fake(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)

    def env(self, **extra):
        env = {k: v for k, v in os.environ.items() if not k.startswith(SCRUB)}
        env.update(PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                   REVIEW_WORKSPACE_BASE=str(self.d / "workspaces"))
        env.update(extra)
        return env

    def run_cmd(self, argv, **extra):
        return subprocess.run(argv, env=self.env(**extra), capture_output=True, text=True, timeout=120)


ARGV_CAPTURE = """#!/usr/bin/env python3
import json, os, sys
json.dump({"argv": sys.argv[1:]}, open(os.environ["CAPTURE"], "w"))
print("stub review")
print("Conclusion: PASS")
"""


class VerdictContract(LegCase):
    """A1: every agent review leg states the verdict contract where the model reads it last."""

    def test_mimo_leg_message_states_contract(self):
        self.copy("submimo", "ro-repo-exec")
        self.fake("mimo", ARGV_CAPTURE)
        cap = self.d / "mimo.json"
        proc = self.run_cmd(["bash", str(self.bin / "submimo"), "review", str(self.task),
                             str(self.d / "m.log"), str(self.repo)],
                            CAPTURE=str(cap), MIMO_REVIEW_HOME=str(self.d / "mimohome"))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        argv = json.loads(cap.read_text())["argv"]
        message = argv[argv.index("--file") - 1]
        self.assertIn(CONTRACT, message)


class FailureKind(LegCase):
    """A2: provider limits are classified from the words the CLI actually printed."""

    def emit(self, diagnostic_text, log_text="partial output\n"):
        # One file set per call: emit publishes atomically and will not replace an existing result.
        tag = "leg%d" % len(list(self.d.glob("leg*.result.json")))
        log = self.d / (tag + ".log")
        log.write_text(log_text)
        diag = self.d / (tag + ".err")
        diag.write_text(diagnostic_text)
        result = self.d / (tag + ".result.json")
        proc = subprocess.run(
            [sys.executable, str(BIN / "_review_result.py"), "emit", "--result", str(result),
             "--run-id", "panel-quick-fixes", "--name", "subkimi", "--family", "moonshot",
             "--adapter", "subkimi", "--exit-code", "1", "--task-sha256", "sha256:" + "0" * 64,
             "--log", str(log), "--diagnostic", str(diag)],
            capture_output=True, text=True, check=False)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(result.read_text())["failure_kind"]

    def test_kimi_five_hour_window_is_a_rate_limit_not_auth_or_runtime(self):
        self.assertEqual(self.emit(KIMI_LIMIT + "\n"), "rate_limit")

    def test_real_kimi_billing_cycle_limit_is_a_rate_limit(self):
        # Review round two, DeepSeek F1: vetoing on the word "billing" turned this real, self-healing
        # message into auth (403) and counted it toward dead.
        self.assertEqual(self.emit(KIMI_BILLING_CYCLE + "\n"), "rate_limit")

    def test_billing_text_that_says_quota_will_reset_is_quota(self):
        # Review round one, Kimi F2: a payment failure can promise a reset "on the next billing
        # cycle". That needs a human (top up), so it must stay quota and keep counting toward dead.
        self.assertEqual(self.emit("HTTP 402: payment required. Your quota will reset on the next "
                                   "billing cycle.\n"), "quota")

    def test_window_words_in_model_prose_never_exempt_a_failure(self):
        # Review round one, Kimi F1: with our diagnostic empty the classifier falls back to the
        # model's report. Prose about "usage limit" (e.g. reviewing this very change) must not turn
        # a crash into a self-healing window limit.
        kind = self.emit("", log_text="The adapter maps a 5-hour usage limit to rate_limit.\n")
        self.assertEqual(kind, "runtime")  # review round two, DeepSeek F4: pin the right bucket, not just "not this one"

    def test_controls_balance_is_quota_and_bad_key_is_auth(self):
        self.assertEqual(self.emit("HTTP 402: Insufficient balance\n"), "quota")
        self.assertEqual(self.emit("Error: 401 unauthorized - invalid api key\n"), "auth")

    def test_subkimi_surfaces_the_cli_error_line_in_its_diagnostic(self):
        self.copy("subkimi", "ro-repo-exec")
        home = self.d / "review-home"
        (home / "hooks").mkdir(parents=True)
        (home / "credentials").mkdir()
        (home / "config.toml").write_text('default_model = "x"\n')
        shutil.copy2(ROOT / "kimi-review-home" / "hooks" / "guard.mjs", home / "hooks" / "guard.mjs")
        (home / "credentials" / "kimi-code.json").write_text("{}")
        self.fake("kimi", "#!/usr/bin/env python3\nprint(%r)\nraise SystemExit(1)\n" % KIMI_LIMIT)
        proc = self.run_cmd(["bash", str(self.bin / "subkimi"), "review", str(self.task),
                             str(self.d / "k.log"), str(self.repo)], KIMI_REVIEW_HOME=str(home))
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("5-hour usage limit", proc.stderr)

    def test_subkimi_copies_only_cli_error_lines(self):
        # Review round one, Kimi F5: copying the whole log would bring model prose back into the
        # diagnostic, reviving the F1 path through the front door.
        self.copy("subkimi", "ro-repo-exec")
        home = self.d / "review-home"
        (home / "hooks").mkdir(parents=True)
        (home / "credentials").mkdir()
        (home / "config.toml").write_text('default_model = "x"\n')
        shutil.copy2(ROOT / "kimi-review-home" / "hooks" / "guard.mjs", home / "hooks" / "guard.mjs")
        (home / "credentials" / "kimi-code.json").write_text("{}")
        prose = "PROSE_LINE_4d2e the reviewed code handles usage limit errors"
        self.fake("kimi", "#!/usr/bin/env python3\nprint(%r)\nprint(%r)\nraise SystemExit(1)\n"
                  % (prose, KIMI_LIMIT))
        proc = self.run_cmd(["bash", str(self.bin / "subkimi"), "review", str(self.task),
                             str(self.d / "k2.log"), str(self.repo)], KIMI_REVIEW_HOME=str(home))
        self.assertIn("5-hour usage limit", proc.stderr)
        self.assertNotIn("PROSE_LINE_4d2e", proc.stderr)


class ChineseVerdict(LegCase):
    """A6: GLM finished real reviews with `结论：通过 (PASS)` (09-07) and `结论：通过` (09-14, after A1's
    reminder), and both whole reports were discarded as having no verdict."""

    def normalize(self, text):
        log = self.d / "v.log"
        log.write_text(text)
        proc = subprocess.run([sys.executable, str(BIN / "_review_result.py"), "normalize", str(log)],
                              capture_output=True, text=True, check=False)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout.strip()

    def test_standalone_chinese_verdict_words_are_verdicts(self):
        for text, want in (("结论：通过\n", "PASS"), ("结论：通过 (PASS)\n", "PASS"),
                           ("结论：通过（PASS）\n", "PASS"), ("结论：阻断\n", "BLOCK"),
                           ("结论：不通过\n", "BLOCK"), ("结论: 需要更多信息\n", "NEEDS_MORE_INFO"),
                           ("**结论：通过**\n", "PASS")):
            with self.subTest(text=text):
                self.assertEqual(self.normalize(text), want)

    def test_chinese_verdicts_stay_strict(self):
        for text in ("结论：通过 (BLOCK)\n", "结论：通过但有疑问\n", "结论：基本通过\n",
                     "我认为结论：通过\n", "结论：通过 | 阻断\n"):
            with self.subTest(text=text):
                self.assertEqual(self.normalize(text), "UNKNOWN")
        self.assertEqual(self.normalize("结论：通过\n复查后\nConclusion: BLOCK\n"), "BLOCK")



if __name__ == "__main__":
    unittest.main()

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
  A4  opencode stops the whole round on the first denied tool call unless
      experimental.continue_loop_on_deny is true (GLM 09-10).
  A5  the OpenCode Go chat endpoint rejects requests without x-opencode-session
      (HTTP 400 MissingSessionID, GLM chat fallback 09-09).
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
SCRUB = ("PANEL_", "AIWORK_REVIEW_", "REVIEW_", "KIMI_", "ZHIPU_", "DEEPSEEK_", "MIMO_",
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
        env.update(PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}", REVIEW_NO_MY_REVIEW="1",
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

    def test_opencode_leg_restates_contract_after_task_body(self):
        self.copy("subglm-agent", "subdeepseek-agent", "subagent", "ro-repo-exec")
        self.fake("opencode", ARGV_CAPTURE)
        cap = self.d / "oc.json"
        proc = self.run_cmd(["bash", str(self.bin / "subglm-agent"), "review", str(self.task),
                             str(self.d / "g.log"), str(self.repo)],
                            CAPTURE=str(cap), OPENCODE_REVIEW_HOME=str(self.d / "ochome"),
                            ZHIPU_API_KEY="zk")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        prompt = next(a for a in json.loads(cap.read_text())["argv"] if TASK_MARKER in a)
        self.assertGreater(prompt.rfind(CONTRACT), prompt.find(TASK_MARKER),
                           "the last statement of the verdict contract must come after the task body")

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


LEG_STUB = """#!/usr/bin/env bash
name="$(basename "$0")"
case "$name" in subdeepseek-agent) name=subdeepseek ;; subglm-agent) name=subglm ;; esac
printf 'Conclusion: PASS\\n' > "$3"
if [[ "$name" == subkimi ]]; then
  printf '%s\\n' "${STUB_KIMI_ERR:?}" >&2
  exit 1
fi
exit 0
"""


class DeadStreak(LegCase):
    """A3: a self-healing window limit cools the leg down but never counts toward dead."""

    def rounds(self, err_text, count):
        self.copy("panel-review", "_panel-roster-lib.sh", "_review_result.py")
        for leg in ("submimo", "subdeepseek", "subdeepseek-agent", "subglm", "subglm-agent", "subkimi"):
            self.fake(leg, LEG_STUB)
        state = self.d / ("state-" + str(abs(hash(err_text))))
        state.mkdir()
        for n in range(count):
            proc = self.run_cmd(["bash", str(self.bin / "panel-review"), "--all", "--no-my-review",
                                 str(self.task), str(self.repo), str(self.d / f"r{n}-{state.name}")],
                                PANEL_STATE_DIR=str(state), PANEL_STAGGER_MAX="0",
                                PANEL_HEALTH_COOLDOWN_SEC="0", STUB_KIMI_ERR=err_text)
            self.assertIn("subkimi", proc.stdout + proc.stderr)
        rows = [line.split("\t") for line in (state / "health.tsv").read_text().splitlines()]
        return next(row for row in rows if row[0] == "subkimi")

    def test_window_limit_does_not_grow_the_streak(self):
        row = self.rounds(KIMI_LIMIT, 3)
        self.assertEqual(row[3], "0", row)
        # Review round one, Kimi F3: health.tsv must say which kind it was; "quota" means top up.
        self.assertEqual(row[1], "rate_limit", row)

    def test_control_balance_exhaustion_still_counts(self):
        # Review round one, Kimi F4: exempting quota along with rate_limit would pass the tests above.
        row = self.rounds("HTTP 402: Insufficient balance", 1)
        self.assertEqual(row[3], "1", row)
        self.assertEqual(row[1], "quota", row)

    def test_control_runtime_failure_still_counts(self):
        row = self.rounds("boom", 1)
        self.assertEqual(row[3], "1", row)


class OpencodeDeny(LegCase):
    """A4: a denied tool call must not end the GLM round."""

    def test_rendered_config_continues_loop_on_deny(self):
        self.copy("subglm-agent", "subdeepseek-agent", "subagent", "ro-repo-exec")
        self.fake("opencode", ARGV_CAPTURE)
        home = self.d / "ochome"
        proc = self.run_cmd(["bash", str(self.bin / "subglm-agent"), "review", str(self.task),
                             str(self.d / "g.log"), str(self.repo)],
                            CAPTURE=str(self.d / "oc.json"), OPENCODE_REVIEW_HOME=str(home),
                            ZHIPU_API_KEY="zk")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        config = json.loads((home / ".config" / "opencode" / "opencode.json").read_text())
        self.assertIs(config.get("experimental", {}).get("continue_loop_on_deny"), True)


class ChatSessionHeader(LegCase):
    """A5: the OpenCode Go chat leg sends one stable x-opencode-session per run."""

    def serve(self):
        seen = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                self.rfile.read(int(self.headers.get("Content-Length", "0")))
                seen.append({k.lower(): v for k, v in self.headers.items()})
                if len(seen) == 1:
                    body, code = b'{"error":"busy"}', 503
                else:
                    body = json.dumps({"choices": [{"message": {"content": "ok\nConclusion: PASS"}}]}).encode()
                    code = 200
                self.send_response(code)
                self.send_header("Retry-After", "0")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        return server.server_address[1], seen

    def test_glm_chat_leg_sends_stable_session_header_across_retry(self):
        self.copy("subglm", "subchat", "submimo-review")
        port, seen = self.serve()
        proc = self.run_cmd(["bash", str(self.bin / "subglm"), "review", str(self.task),
                             str(self.d / "c.log"), str(self.repo)],
                            ZHIPU_API_KEY="x", MIMO_RETRY_BASE_SECONDS="0",
                            ZHIPU_CHAT_COMPLETIONS_URL=f"http://127.0.0.1:{port}/v1/chat/completions")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(len(seen), 2, proc.stderr)
        sessions = [h.get("x-opencode-session") for h in seen]
        self.assertTrue(sessions[0], seen)
        self.assertEqual(sessions[0], sessions[1])

    def test_control_deepseek_chat_leg_sends_no_opencode_header(self):
        self.copy("subdeepseek", "subchat", "submimo-review")
        port, seen = self.serve()
        proc = self.run_cmd(["bash", str(self.bin / "subdeepseek"), "review", str(self.task),
                             str(self.d / "c.log"), str(self.repo)],
                            DEEPSEEK_API_KEY="x", MIMO_RETRY_BASE_SECONDS="0",
                            DEEPSEEK_API_BASE=f"http://127.0.0.1:{port}/v1")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(seen)
        self.assertNotIn("x-opencode-session", seen[-1])


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""One table: the five review legs finish the same way for the same outcome."""

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from _test_settings import write_settings

ROOT = Path(__file__).resolve().parents[1]
CASES = ("timeout", "nonzero", "blank", "no_verdict", "pass",
         "explore_ok", "review_timeout", "review_nonzero", "killed")


class LegFinish(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="leg-finish-"))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("aiwork-config", "_aiwork_config.py", "_review-workspace.sh",
                     "_review-home-guard.sh", "_review_result.py", "_cursor-stream.py",
                     "ro-repo-exec",
                     "subagent", "subkimi", "submimo", "subcodex", "subcursor"):
            shutil.copy(ROOT / "bin" / name, self.bin / name)
        self.repo = self.root / "repo"
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        (self.repo / "README").write_text("fixture\n")
        subprocess.run(["git", "-C", str(self.repo), "add", "README"], check=True)
        subprocess.run(
            ["git", "-C", str(self.repo), "-c", "user.email=t@example.com",
             "-c", "user.name=t", "commit", "-qm", "init"], check=True)
        (self.root / "task.md").write_text("brief\n")
        write_settings(self.root / "settings")
        self._claude()
        self._kimi()
        self._mimo()
        self._codex()
        self._cursor()

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _env(self):
        env = os.environ.copy()
        env["PATH"] = f"{self.bin}:{env.get('PATH', '')}"
        env["AIWORK_CONFIG_DIR"] = str(self.root / "settings")
        env["HOME"] = str(self.root / "home")
        env["DEEPSEEK_TIMEOUT"] = "1"
        env["KIMI_TIMEOUT"] = "1"
        env["MIMO_CLI_TIMEOUT"] = "1"
        env["SUBCODEX_TIMEOUT"] = "1"
        env["CURSOR_TIMEOUT"] = "1"
        env["DEEPSEEK_API_KEY"] = "test-key"
        env["KIMI_REVIEW_HOME"] = str(self.root / "kimi-home")
        env["MIMO_REVIEW_HOME"] = str(self.root / "mimo-home")
        env["CURSOR_AUTH_FILE"] = str(self.root / "home" / ".config" / "cursor" / "auth.json")
        env.pop("CURSOR_API_KEY", None)
        env.pop("XDG_CONFIG_HOME", None)
        return env

    def _write(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)

    def _claude(self):
        self._write("claude", """#!/usr/bin/env python3
import os, sys, time
case = os.environ["FINISH_CASE"]
if case in ("timeout", "review_timeout"):
    time.sleep(30)
if case == "killed":
    raise SystemExit(137)
if case in ("nonzero", "review_nonzero"):
    sys.stderr.write("quota exceeded\\n" if os.environ.get("FINISH_QUOTA") else "")
    raise SystemExit(1)
text = {"blank": " \\t\\n", "no_verdict": "Review has evidence but no decision.\\n",
        "pass": "Conclusion: PASS\\n", "explore_ok": "Conclusion: PASS\\n"}[case]
print('{"type":"result","result":' + __import__("json").dumps(text) + "}")
""")

    def _kimi(self):
        home = self.root / "kimi-home"
        (home / "hooks").mkdir(parents=True)
        (home / "credentials").mkdir()
        (home / "hooks" / "guard.mjs").write_text("process.exit(2)\n")
        (home / "credentials" / "kimi-code.json").write_text("{}\n")
        (home / "config.toml").write_text('default_model = "x"\n')
        self._write("kimi", """#!/usr/bin/env python3
import json, os, sys, time
case = os.environ["FINISH_CASE"]
if case in ("timeout", "review_timeout"):
    time.sleep(30)
if case == "killed":
    raise SystemExit(137)
if case in ("nonzero", "review_nonzero"):
    raise SystemExit(1)
text = {"blank": " \\t\\n", "no_verdict": "Review has evidence but no decision.\\n",
        "pass": "Conclusion: PASS\\n", "explore_ok": "Conclusion: PASS\\n"}[case]
print(json.dumps({"role": "assistant", "content": text}))
""")

    def _mimo(self):
        (self.root / "mimo-home").mkdir()
        self._write("mimo", """#!/usr/bin/env python3
import json, os, sys, time
case = os.environ["FINISH_CASE"]
if case in ("timeout", "review_timeout"):
    time.sleep(30)
if case == "killed":
    raise SystemExit(137)
if case in ("nonzero", "review_nonzero"):
    raise SystemExit(1)
text = {"blank": " \\t\\n", "no_verdict": "Review has evidence but no decision.\\n",
        "pass": "Conclusion: PASS\\n", "explore_ok": "Conclusion: PASS\\n"}[case]
print(json.dumps({"type": "text", "part": {"id": "p", "messageID": "m", "text": text}}))
""")

    def _codex(self):
        self._write("codex", """#!/usr/bin/env python3
import json, os, sys, time
args = sys.argv[1:]
if args[:2] == ["debug", "models"]:
    print(json.dumps({"models": [{"slug": "gpt-6-sol"}]}))
    raise SystemExit(0)
if args[:2] == ["debug", "prompt-input"]:
    print("ok")
    raise SystemExit(0)
case = os.environ["FINISH_CASE"]
out = None
if "-o" in args:
    out = args[args.index("-o") + 1]
if case in ("timeout", "review_timeout"):
    time.sleep(30)
if case == "killed":
    raise SystemExit(137)
if case in ("nonzero", "review_nonzero"):
    raise SystemExit(1)
text = {"blank": " \\t\\n", "no_verdict": "Review has evidence but no decision.\\n",
        "pass": "Conclusion: PASS\\n", "explore_ok": "Conclusion: PASS\\n"}[case]
if out:
    open(out, "w").write(text)
print(json.dumps({"type": "thread.started", "model": args[args.index("-m") + 1]}))
""")

    def _cursor(self):
        auth_dir = self.root / "home" / ".config" / "cursor"
        auth_dir.mkdir(parents=True)
        (auth_dir / "auth.json").write_text('{"accessToken":"cursor-test-token"}\n')
        self._write("cursor-agent", r"""#!/usr/bin/env python3
import json, os, sys, time
case = os.environ["FINISH_CASE"]
if case in ("timeout", "review_timeout"):
    time.sleep(30)
if case == "killed":
    raise SystemExit(137)
if case in ("nonzero", "review_nonzero"):
    sys.stderr.write("quota exceeded\n")
    raise SystemExit(1)
text = {"blank": " \t\n", "no_verdict": "Review has evidence but no decision.\n",
        "pass": "Conclusion: PASS\n", "explore_ok": "Conclusion: PASS\n"}[case]
def emit(event):
    print(json.dumps(event), flush=True)
sid = "s1"
emit({"type": "system", "subtype": "init", "session_id": sid, "model": "grok-4.7-high"})
emit({"type": "assistant", "session_id": sid, "message": {
    "role": "assistant", "content": [{"type": "text", "text": text}]}})
emit({"type": "result", "subtype": "success", "is_error": False, "session_id": sid,
      "result": text})
""")

    def _run(self, leg, mode, case):
        log = self.root / f"{leg}-{case}.log"
        env = self._env()
        env["FINISH_CASE"] = case
        env["AIWORK_REVIEW_REPORT_PATH"] = str(self.root / f"{leg}-{case}.report")
        env["AIWORK_REVIEW_FACTS_PATH"] = str(self.root / f"{leg}-{case}.facts.json")
        env["AIWORK_REVIEW_RESULT_BIN"] = str(self.bin / "_review_result.py")
        argv = {
            "subagent": [str(self.bin / "subagent"), "deepseek", mode],
            "subkimi": [str(self.bin / "subkimi"), mode],
            "submimo": [str(self.bin / "submimo"), mode],
            "subcodex": [str(self.bin / "subcodex"), mode],
            "subcursor": [str(self.bin / "subcursor"), mode],
        }[leg]
        return subprocess.run(
            argv + [str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)

    def _facts(self, leg, case, result):
        path = self.root / f"{leg}-{case}.facts.json"
        self.assertTrue(
            path.is_file(),
            f"FAIL {leg} {case} rc={result.returncode} "
            f"stderr={result.stderr[-800:]!r} stdout={result.stdout[-400:]!r}")
        return json.loads(path.read_text())

    def _signature(self, result, facts, log):
        marker = str(log)
        finish = []
        for line in result.stderr.splitlines():
            text = re.sub(r"^[^ :]+: ", "", line.replace(marker, "{log}"))
            if text.startswith((
                "timed out after ",
                "exited rc=",
                "explore produced no final message (log: ",
                "model returned no verdict",
            )):
                finish.append(text)
        line = finish[-1] if finish else ""
        return (
            facts["process_state"],
            facts["evidence_completeness"],
            facts["failure_kind"],
            facts["verdict"],
            result.returncode,
            line,
            facts["model"]["reported"],
            facts["degraded"],
            facts["billing_mode"],
        )

    def _observed(self, leg, case):
        billing = "api" if leg == "subagent" else "subscription"
        degraded = False if leg == "subcursor" else None
        reported = None
        if leg == "subcodex" and case not in ("timeout", "review_timeout", "nonzero",
                                               "review_nonzero", "killed"):
            reported = "gpt-6-sol"
        return (reported, degraded, billing)

    def test_five_legs_share_one_finish(self):
        modes = {
            "timeout": "explore", "nonzero": "explore", "blank": "explore",
            "no_verdict": "review", "pass": "review",
            "explore_ok": "explore", "review_timeout": "review",
            "review_nonzero": "review", "killed": "explore",
        }
        seen = {case: {} for case in CASES}
        for case in CASES:
            for leg in ("subagent", "subkimi", "submimo", "subcodex", "subcursor"):
                result = self._run(leg, modes[case], case)
                seen[case][leg] = self._signature(
                    result, self._facts(leg, case, result), self.root / f"{leg}-{case}.log")
        for case in CASES:
            rows = seen[case]
            outcomes = {leg: row[:6] for leg, row in rows.items()}
            if len(set(outcomes.values())) != 1:
                print(f"FAIL detail {case}: {rows}")
            self.assertEqual(len(set(outcomes.values())), 1, f"{case}: {rows}")
            for leg, row in rows.items():
                self.assertEqual(row[6:], self._observed(leg, case), f"{case} {leg}: {row}")
        timeout = seen["timeout"]["subagent"]
        self.assertEqual(timeout[:6], (
            "timed_out", "partial", "timeout", None, 124,
            "timed out after 1s (log: {log})"))
        nonzero = seen["nonzero"]["subagent"]
        self.assertEqual(nonzero[:6], (
            "exited", "partial", None, None, 1, "exited rc=1 (log: {log})"))
        blank = seen["blank"]["subagent"]
        self.assertEqual(blank[:6], (
            "exited", "partial", None, None, 1,
            "explore produced no final message (log: {log})"))
        missing = seen["no_verdict"]["subagent"]
        self.assertEqual(missing[:5], ("exited", "partial", "no_verdict", "UNKNOWN", 1))
        self.assertIn("no verdict", missing[5])
        ok = seen["pass"]["subagent"]
        self.assertEqual(ok[:6], ("exited", "complete", None, "PASS", 0, ""))
        explore_ok = seen["explore_ok"]["subagent"]
        self.assertEqual(explore_ok[:6], ("exited", "complete", None, None, 0, ""))
        review_timeout = seen["review_timeout"]["subagent"]
        self.assertEqual(review_timeout[:6], (
            "timed_out", "partial", "timeout", "UNKNOWN", 124,
            "timed out after 1s (log: {log})"))
        review_nonzero = seen["review_nonzero"]["subagent"]
        self.assertEqual(review_nonzero[:6], (
            "exited", "partial", None, "UNKNOWN", 1, "exited rc=1 (log: {log})"))
        killed = seen["killed"]["subagent"]
        self.assertEqual(killed[:6], (
            "timed_out", "partial", "timeout", None, 124,
            "timed out after 1s (log: {log})"))

    def test_subagent_explore_quota_is_not_hardcoded_runtime(self):
        env = self._env()
        env["FINISH_CASE"] = "nonzero"
        env["FINISH_QUOTA"] = "1"
        log = self.root / "quota.log"
        report = self.root / "quota.report"
        facts = self.root / "quota.facts.json"
        env["AIWORK_REVIEW_REPORT_PATH"] = str(report)
        env["AIWORK_REVIEW_FACTS_PATH"] = str(facts)
        env["AIWORK_REVIEW_RESULT_BIN"] = str(self.bin / "_review_result.py")
        result = subprocess.run(
            [str(self.bin / "subagent"), "deepseek", "explore",
             str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)
        self.assertEqual(result.returncode, 1)
        produced = self.root / "produced.json"
        diagnostic = self.root / "diagnostic.txt"
        diagnostic.write_text(result.stderr)
        digest = "sha256:" + hashlib.sha256((self.root / "task.md").read_bytes()).hexdigest()
        emitted = subprocess.run(
            [sys.executable, str(self.bin / "_review_result.py"), "emit",
             "--result", str(produced), "--run-id", "explore-quota",
             "--name", "subdeepseek-agent", "--family", "deepseek",
             "--adapter", "subdeepseek-agent", "--exit-code", "1",
             "--task-sha256", digest, "--log", str(log),
             "--diagnostic", str(diagnostic), "--report", str(report),
             "--facts", str(facts), "--review-contract-version", "3"],
            capture_output=True, text=True)
        self.assertEqual(emitted.returncode, 0, emitted.stderr)
        self.assertEqual(json.loads(produced.read_text())["failure_kind"], "quota")

    def _emit(self, result, facts, report, log, name, family):
        produced = self.root / f"{name}-emitted.json"
        diagnostic = self.root / f"{name}-diagnostic.txt"
        diagnostic.write_text(result.stderr)
        digest = "sha256:" + hashlib.sha256((self.root / "task.md").read_bytes()).hexdigest()
        emitted = subprocess.run(
            [sys.executable, str(self.bin / "_review_result.py"), "emit",
             "--result", str(produced), "--run-id", f"explore-{name}",
             "--name", name, "--family", family, "--adapter", name,
             "--exit-code", str(result.returncode), "--task-sha256", digest,
             "--log", str(log), "--diagnostic", str(diagnostic),
             "--report", str(report), "--facts", str(facts),
             "--review-contract-version", "3"],
            capture_output=True, text=True)
        self.assertEqual(emitted.returncode, 0, emitted.stderr)
        return json.loads(produced.read_text())

    def test_review_normalize_error_exits_78(self):
        real = self.bin / "_review_result.py"
        helper = self.bin / "boom-normalize.py"
        helper.write_text(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            "if 'normalize' in sys.argv:\n"
            "    sys.stderr.write('normalize boom\\n')\n"
            "    raise SystemExit(1)\n"
            f"os.execv(sys.executable, [sys.executable, {str(real)!r}, *sys.argv[1:]])\n")
        helper.chmod(0o755)
        env = self._env()
        env["FINISH_CASE"] = "pass"
        env["AIWORK_REVIEW_RESULT_BIN"] = str(helper)
        log = self.root / "norm.log"
        env["AIWORK_REVIEW_REPORT_PATH"] = str(self.root / "norm.report")
        env["AIWORK_REVIEW_FACTS_PATH"] = str(self.root / "norm.facts.json")
        result = subprocess.run(
            [str(self.bin / "subagent"), "deepseek", "review",
             str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)
        self.assertEqual(result.returncode, 78, result.stderr)
        self.assertIn("normalize boom", result.stderr)

    def test_submimo_copies_real_erofs_lines_for_emit(self):
        sample = (ROOT / "tests/fixtures/mimo-erofs.txt").read_text(encoding="utf-8")
        self._write("mimo", """#!/usr/bin/env python3
import os, sys
sys.stdout.write(open(os.environ["MIMO_SAMPLE"], encoding="utf-8").read())
raise SystemExit(1)
""")
        env = self._env()
        env["FINISH_CASE"] = "nonzero"
        env["MIMO_SAMPLE"] = str(ROOT / "tests/fixtures/mimo-erofs.txt")
        log = self.root / "erofs.log"
        report = self.root / "erofs.report"
        facts = self.root / "erofs.facts.json"
        env["AIWORK_REVIEW_REPORT_PATH"] = str(report)
        env["AIWORK_REVIEW_FACTS_PATH"] = str(facts)
        env["AIWORK_REVIEW_RESULT_BIN"] = str(self.bin / "_review_result.py")
        result = subprocess.run(
            [str(self.bin / "submimo"), "explore",
             str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        for line in sample.splitlines():
            if line.strip():
                self.assertIn(line, result.stderr)
        recorded = self._emit(result, facts, report, log, "submimo", "xiaomi")
        self.assertEqual(recorded["failure_kind"], "runtime")

    def test_subcodex_copies_real_usage_limit_events_for_emit(self):
        sample = (ROOT / "tests/fixtures/codex-usage-limit.jsonl").read_text(encoding="utf-8")
        sentence = json.loads(sample.splitlines()[0])["message"]
        self._write("codex", """#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
if args[:2] == ["debug", "models"]:
    print(json.dumps({"models": [{"slug": "gpt-6-sol"}]}))
    raise SystemExit(0)
if args[:2] == ["debug", "prompt-input"]:
    print("ok")
    raise SystemExit(0)
sys.stdout.write(open(os.environ["CODEX_SAMPLE"], encoding="utf-8").read())
raise SystemExit(1)
""")
        env = self._env()
        env["CODEX_SAMPLE"] = str(ROOT / "tests/fixtures/codex-usage-limit.jsonl")
        log = self.root / "quota.log"
        report = self.root / "quota.report"
        facts = self.root / "quota.facts.json"
        env["AIWORK_REVIEW_REPORT_PATH"] = str(report)
        env["AIWORK_REVIEW_FACTS_PATH"] = str(facts)
        env["AIWORK_REVIEW_RESULT_BIN"] = str(self.bin / "_review_result.py")
        result = subprocess.run(
            [str(self.bin / "subcodex"), "explore",
             str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn(sentence, result.stderr)
        self.assertNotIn("usage_limit_exceeded", (self.root / "quota.stream.jsonl").read_text(encoding="utf-8"))
        recorded = self._emit(result, facts, report, log, "subcodex", "openai")
        self.assertEqual(recorded["failure_kind"], "rate_limit")

    def test_subcodex_does_not_copy_usage_limit_from_model_text(self):
        self._write("codex", """#!/usr/bin/env python3
import json, sys
args = sys.argv[1:]
if args[:2] == ["debug", "models"]:
    print(json.dumps({"models": [{"slug": "gpt-6-sol"}]}))
    raise SystemExit(0)
if args[:2] == ["debug", "prompt-input"]:
    print("ok")
    raise SystemExit(0)
print(json.dumps({
    "type": "item.completed",
    "item": {"type": "command_execution",
             "aggregated_output": "You've hit your usage limit. This is model text."}}))
raise SystemExit(1)
""")
        env = self._env()
        log = self.root / "body.log"
        report = self.root / "body.report"
        facts = self.root / "body.facts.json"
        env["AIWORK_REVIEW_REPORT_PATH"] = str(report)
        env["AIWORK_REVIEW_FACTS_PATH"] = str(facts)
        env["AIWORK_REVIEW_RESULT_BIN"] = str(self.bin / "_review_result.py")
        result = subprocess.run(
            [str(self.bin / "subcodex"), "explore",
             str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("usage limit", result.stderr)
        self.assertIsNone(json.loads(facts.read_text())["failure_kind"])

    def test_extra_mimo_header_line_stays_out_of_stderr(self):
        script = self.bin / "submimo"
        original = script.read_text(encoding="utf-8")
        needle = '    echo "model: $MODEL"\n    echo\n'
        self.assertIn(needle, original)
        script.write_text(original.replace(
            needle, '    echo "model: $MODEL"\n    echo "source_repo: HEADER_SENTINEL"\n    echo\n', 1),
            encoding="utf-8")
        self._write("mimo", """#!/usr/bin/env python3
import sys
sys.stdout.write("provider error line\\n")
raise SystemExit(1)
""")
        env = self._env()
        log = self.root / "header.log"
        env["AIWORK_REVIEW_REPORT_PATH"] = str(self.root / "header.report")
        env["AIWORK_REVIEW_FACTS_PATH"] = str(self.root / "header.facts.json")
        env["AIWORK_REVIEW_RESULT_BIN"] = str(self.bin / "_review_result.py")
        result = subprocess.run(
            [str(self.bin / "submimo"), "explore",
             str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("source_repo: HEADER_SENTINEL", log.read_text(encoding="utf-8"))
        self.assertNotIn("HEADER_SENTINEL", result.stderr)
        self.assertIn("provider error line", result.stderr)

    def test_mimo_json_events_and_log_header_stay_out_of_stderr(self):
        self._write("mimo", """#!/usr/bin/env python3
import json, sys
print(json.dumps({"type": "text", "part": {
    "id": "p", "messageID": "m", "text": "MODEL_BODY_SENTINEL"}}))
print(json.dumps({"type": "tool_use", "part": {
    "tool": "bash", "output": "TOOL_OUTPUT_SENTINEL"}}))
sys.stdout.write("provider error line\\n")
raise SystemExit(1)
""")
        env = self._env()
        log = self.root / "json.log"
        env["AIWORK_REVIEW_REPORT_PATH"] = str(self.root / "json.report")
        env["AIWORK_REVIEW_FACTS_PATH"] = str(self.root / "json.facts.json")
        env["AIWORK_REVIEW_RESULT_BIN"] = str(self.bin / "_review_result.py")
        result = subprocess.run(
            [str(self.bin / "submimo"), "explore",
             str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("MODEL_BODY_SENTINEL", result.stderr)
        self.assertNotIn("TOOL_OUTPUT_SENTINEL", result.stderr)
        self.assertNotIn("# submimo ", result.stderr)
        self.assertIn("provider error line", result.stderr)
        self.assertIn("MODEL_BODY_SENTINEL", log.read_text(encoding="utf-8"))

    def test_review_missing_helper_with_empty_report_exits_78(self):
        self._write("claude", "#!/usr/bin/env python3\nraise SystemExit(0)\n")
        env = self._env()
        env.pop("AIWORK_REVIEW_FACTS_PATH", None)
        env.pop("AIWORK_REVIEW_REPORT_PATH", None)
        env["AIWORK_REVIEW_RESULT_BIN"] = str(self.root / "missing-normalizer.py")
        log = self.root / "missing-helper.log"
        result = subprocess.run(
            [str(self.bin / "subagent"), "deepseek", "review",
             str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)
        self.assertEqual(result.returncode, 78, result.stderr)
        self.assertIn("normalizer missing", result.stderr)
        self.assertNotIn("no verdict", result.stderr)

    def test_kimi_copies_provider_error_on_timeout(self):
        self._write("kimi", """#!/usr/bin/env python3
import sys
sys.stderr.write("error: failed to run prompt: provider said usage limit\\n")
raise SystemExit(124)
""")
        env = self._env()
        log = self.root / "kimi-timeout.log"
        env["AIWORK_REVIEW_REPORT_PATH"] = str(self.root / "kimi-timeout.report")
        env["AIWORK_REVIEW_FACTS_PATH"] = str(self.root / "kimi-timeout.facts.json")
        env["AIWORK_REVIEW_RESULT_BIN"] = str(self.bin / "_review_result.py")
        result = subprocess.run(
            [str(self.bin / "subkimi"), "explore",
             str(self.root / "task.md"), str(log), str(self.repo)],
            capture_output=True, text=True, env=env, timeout=40)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn("error: failed to run prompt: provider said usage limit", result.stderr)

    def test_cursor_names_cli_stream_and_decoder_when_decoder_fails(self):
        self._write("cursor-agent", "#!/usr/bin/env python3\nprint('not-json')\n")
        result = self._run("subcursor", "explore", "pass")
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("cli=", result.stderr)
        self.assertIn("stream=", result.stderr)
        self.assertIn("decoder=", result.stderr)


if __name__ == "__main__":
    unittest.main()

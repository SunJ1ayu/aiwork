#!/usr/bin/env python3
"""One table: the five review legs finish the same way for the same outcome."""

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from _test_settings import write_settings

ROOT = Path(__file__).resolve().parents[1]
CASES = ("timeout", "nonzero", "blank", "no_verdict", "pass")


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
        env.pop("CURSOR_API_KEY", None)
        return env

    def _write(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)

    def _claude(self):
        self._write("claude", """#!/usr/bin/env python3
import os, sys, time
case = os.environ["FINISH_CASE"]
if case == "timeout":
    time.sleep(30)
if case == "nonzero":
    sys.stderr.write("quota exceeded\\n" if os.environ.get("FINISH_QUOTA") else "")
    raise SystemExit(1)
text = {"blank": " \\t\\n", "no_verdict": "Review has evidence but no decision.\\n",
        "pass": "Conclusion: PASS\\n"}[case]
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
if case == "timeout":
    time.sleep(30)
if case == "nonzero":
    raise SystemExit(1)
text = {"blank": " \\t\\n", "no_verdict": "Review has evidence but no decision.\\n",
        "pass": "Conclusion: PASS\\n"}[case]
print(json.dumps({"role": "assistant", "content": text}))
""")

    def _mimo(self):
        (self.root / "mimo-home").mkdir()
        self._write("mimo", """#!/usr/bin/env python3
import json, os, sys, time
case = os.environ["FINISH_CASE"]
if case == "timeout":
    time.sleep(30)
if case == "nonzero":
    raise SystemExit(1)
text = {"blank": " \\t\\n", "no_verdict": "Review has evidence but no decision.\\n",
        "pass": "Conclusion: PASS\\n"}[case]
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
if case == "timeout":
    time.sleep(30)
if case == "nonzero":
    raise SystemExit(1)
text = {"blank": " \\t\\n", "no_verdict": "Review has evidence but no decision.\\n",
        "pass": "Conclusion: PASS\\n"}[case]
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
if case == "timeout":
    time.sleep(30)
if case == "nonzero":
    sys.stderr.write("quota exceeded\n")
    raise SystemExit(1)
text = {"blank": " \t\n", "no_verdict": "Review has evidence but no decision.\n",
        "pass": "Conclusion: PASS\n"}[case]
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

    def _facts(self, leg, case):
        path = self.root / f"{leg}-{case}.facts.json"
        self.assertTrue(path.is_file(), f"{leg} {case} wrote no facts")
        return json.loads(path.read_text())

    def _signature(self, result, facts, log):
        line = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else ""
        line = line.replace(str(log), "{log}")
        return (
            facts["process_state"],
            facts["evidence_completeness"],
            facts["failure_kind"],
            facts["verdict"],
            result.returncode,
            line,
        )

    def test_five_legs_share_one_finish(self):
        modes = {
            "timeout": "explore", "nonzero": "explore", "blank": "explore",
            "no_verdict": "review", "pass": "review",
        }
        seen = {case: {} for case in CASES}
        for case in CASES:
            for leg in ("subagent", "subkimi", "submimo", "subcodex", "subcursor"):
                result = self._run(leg, modes[case], case)
                seen[case][leg] = self._signature(
                    result, self._facts(leg, case), self.root / f"{leg}-{case}.log")
        for case in CASES:
            rows = seen[case]
            self.assertEqual(len(set(rows.values())), 1, f"{case}: {rows}")
        timeout = seen["timeout"]["subagent"]
        self.assertEqual(timeout[:5], ("timed_out", "partial", "timeout", None, 124))
        self.assertEqual(timeout[5], "timed out (log: {log})")
        nonzero = seen["nonzero"]["subagent"]
        self.assertEqual(nonzero[:5], ("exited", "partial", None, None, 1))
        self.assertEqual(nonzero[5], "exited rc=1 (log: {log})")
        blank = seen["blank"]["subagent"]
        self.assertEqual(blank[:5], ("exited", "partial", None, None, 1))
        self.assertEqual(blank[5], "explore produced no final message (log: {log})")
        missing = seen["no_verdict"]["subagent"]
        self.assertEqual(missing[:5], ("exited", "partial", "no_verdict", "UNKNOWN", 1))
        self.assertIn("no verdict", missing[5])
        ok = seen["pass"]["subagent"]
        self.assertEqual(ok, ("exited", "complete", None, "PASS", 0, ""))

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


if __name__ == "__main__":
    unittest.main()

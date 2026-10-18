#!/usr/bin/env python3
"""跑完以后核 Kimi / MiMo 这次实际调用的工具。

派发前的钩子和配置挡不住：Kimi 的拦截钩子失败会放行，MiMo 找不到指定 agent
时会退回开着 Bash 的默认配置。下面这几条在改核实之前必须是红的：调用了清单
以外的工具，或者输出里看不出用了哪些工具，结果仍然被当成成功。
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import hashlib
import importlib.machinery
import importlib.util
import json
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

from _test_settings import write_kimi_config, write_settings

ROOT = Path(__file__).resolve().parents[1]

KIMI_WRITE = textwrap.dedent("""\
    {"role":"meta","type":"system.version","version":"0.36.1"}
    {"role":"assistant","content":"","tool_calls":[{"type":"function","id":"tool_write","function":{"name":"Write","arguments":"{}"}}]}
    {"role":"tool","tool_call_id":"tool_write","content":"permission denied"}
    {"role":"assistant","content":"Conclusion: PASS\\n"}
    """)

# Same flushAssistant shape as KIMI_TOOL_ONLY, with a tool outside the list.
KIMI_WRITE_TOOL_ONLY = (
    '{"role":"assistant","tool_calls":[{"type":"function","id":"tool_write",'
    '"function":{"name":"Write","arguments":"{}"}}]}\n'
    '{"role":"tool","tool_call_id":"tool_write","content":"permission denied"}\n'
    '{"role":"assistant","content":"Conclusion: PASS\\n"}\n'
)

KIMI_READ = textwrap.dedent("""\
    {"role":"meta","type":"system.version","version":"0.36.1"}
    {"role":"assistant","content":"","tool_calls":[{"type":"function","id":"tool_read","function":{"name":"Read","arguments":"{}"}}]}
    {"role":"tool","tool_call_id":"tool_read","content":"file"}
    {"role":"assistant","content":"Conclusion: PASS\\n"}
    """)

# kimi-code 0.36.1 dist/main.mjs PromptJsonWriter.flushAssistant:
# content is assistantText when it is non-empty, otherwise void 0.
# JSON.stringify omits undefined, so a tool-only turn has no content key.
# The tool_calls object is writeToolCall: type, id, function.name, function.arguments.
KIMI_TOOL_ONLY = (
    '{"role":"meta","type":"system.version","version":"0.36.1"}\n'
    '{"role":"assistant","tool_calls":[{"type":"function","id":"tool_read",'
    '"function":{"name":"Read","arguments":"{}"}}]}\n'
    '{"role":"tool","tool_call_id":"tool_read","content":"file"}\n'
    '{"role":"assistant","content":"Conclusion: PASS\\n"}\n'
)

# Same writer, writeToolResult: stringifyToolOutput returns a string unchanged,
# then writeJsonLine does JSON.stringify(message) + "\\n". Node 22 leaves U+2028
# inside that string (checked against the installed CLI on 2026-10-19). U+2029
# and U+0085 are the other separators splitlines() breaks that JSON allows
# unescaped. The assistant turn keeps "content":"" so this sample fails only
# because the tool-result record is split.
def kimi_line_separator(separator):
    return (
        '{"role":"meta","type":"system.version","version":"0.36.1"}\n'
        '{"role":"assistant","content":"","tool_calls":[{"type":"function","id":"tool_read",'
        '"function":{"name":"Read","arguments":"{}"}}]}\n'
        '{"role":"tool","tool_call_id":"tool_read","content":"a' + separator + 'b"}\n'
        '{"role":"assistant","content":"Conclusion: PASS\\n"}\n'
    )


KIMI_BAD_CONTENT = (
    '{"role":"assistant","content":["not a string"],"tool_calls":[{"type":"function",'
    '"id":"tool_read","function":{"name":"Read","arguments":"{}"}}]}\n'
    '{"role":"assistant","content":"Conclusion: PASS\\n"}\n'
)

KIMI_NOT_JSON = (
    '{"role":"assistant","content":"Conclusion: PASS\\n"}\n'
    'not json\n'
)

KIMI_UNKNOWN = textwrap.dedent("""\
    {"role":"assistant","content":"Conclusion: PASS\\n"}
    {"event":"tool","name":"Write"}
    """)

KIMI_WRITE_NO_VERDICT = textwrap.dedent("""\
    {"role":"assistant","content":"Review has evidence but no decision.\\n","tool_calls":[{"type":"function","id":"tool_write","function":{"name":"Write","arguments":"{}"}}]}
    """)

KIMI_LIMIT = (
    '{"role":"assistant","content":"Conclusion: PASS\\n","tool_calls":[{"type":"function","id":"tool_write","function":{"name":"Write","arguments":"{}"}}]}\n'
    "error: failed to run prompt: provider.auth_error: 403 You've reached your weekly (7-day) usage limit\n"
)

MIMO_BASH = textwrap.dedent("""\
    {"type":"tool_use","part":{"type":"tool","tool":"bash"}}
    {"type":"text","part":{"id":"p","messageID":"m","text":"Conclusion: PASS"}}
    """)

MIMO_READ = textwrap.dedent("""\
    {"type":"tool_use","part":{"type":"tool","tool":"read"}}
    {"type":"text","part":{"id":"p","messageID":"m","text":"Conclusion: PASS"}}
    """)

MIMO_UNKNOWN = textwrap.dedent("""\
    {"type":"text","part":{"id":"p","messageID":"m","text":"Conclusion: PASS"}}
    {"event":"tool","name":"bash"}
    """)

MIMO_PROVIDER = textwrap.dedent("""\
    {"type":"text","part":{"id":"p","messageID":"m","text":"partial"}}
    {"type":"tool_use","part":{"type":"tool","tool":"bash"}}
    provider error line
    """)


def _load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(ROOT / "bin" / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class ReaderToolAuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        subprocess.check_call(["git", "init", "-q", "-b", "main", str(self.repo)])
        subprocess.check_call(["git", "-C", str(self.repo), "config", "user.email", "t@example.com"])
        subprocess.check_call(["git", "-C", str(self.repo), "config", "user.name", "t"])
        (self.repo / "a.txt").write_text("a\n", encoding="utf-8")
        subprocess.check_call(["git", "-C", str(self.repo), "add", "-A"])
        subprocess.check_call(["git", "-C", str(self.repo), "commit", "-qm", "base"])
        self.config = write_settings(self.root / "settings")
        self.data = self.root / "data"
        self.data.mkdir()
        self.fake = self.root / "fake"
        self.fake.mkdir()
        self.task = self.root / "task.md"
        self.task.write_text("# brief\n", encoding="utf-8")
        self.home = self.root / "kimi-home"
        (self.home / "hooks").mkdir(parents=True)
        (self.home / "hooks" / "guard.mjs").write_text("process.exit(2)\n", encoding="utf-8")
        (self.home / "credentials").mkdir()
        (self.home / "credentials" / "kimi-code.json").write_text("{}\n", encoding="utf-8")
        write_kimi_config(self.home)

    def _stub(self, name, body):
        path = self.fake / name
        path.write_text(body, encoding="utf-8")
        path.chmod(0o755)

    def _env(self, **extra):
        env = dict(os.environ)
        env.update(
            PATH=str(self.fake) + os.pathsep + env.get("PATH", ""),
            AIWORK_CONFIG_DIR=str(self.config),
            AIWORK_DATA_DIR=str(self.data),
            KIMI_REVIEW_HOME=str(self.home),
            MIMO_REVIEW_HOME=str(self.root / "mimo-home"),
            AIWORK_REVIEW_RESULT_BIN=str(ROOT / "bin" / "_review_result.py"),
        )
        env.update(extra)
        return env

    def _run_leg(self, leg, stream, *, exit_code=0, mode="review"):
        slot = self.root / f"{leg}-{mode}-{hashlib.sha256(stream.encode()).hexdigest()[:8]}"
        slot.mkdir()
        log = slot / "leg.log"
        report = slot / "report.md"
        facts = slot / "facts.json"
        fixture = slot / "stream.txt"
        fixture.write_text(stream, encoding="utf-8")
        if leg == "subkimi":
            self._stub("kimi", textwrap.dedent(f"""\
                #!/usr/bin/env python3
                import os, pathlib, sys
                sys.stdout.write(pathlib.Path(os.environ["KIMI_STREAM_FIXTURE"]).read_text(encoding="utf-8"))
                raise SystemExit({exit_code})
                """))
        else:
            self._stub("mimo", textwrap.dedent(f"""\
                #!/usr/bin/env python3
                import os, pathlib, sys
                if "--format" not in sys.argv or sys.argv[sys.argv.index("--format") + 1] != "json":
                    raise SystemExit("review must request --format json")
                sys.stdout.write(pathlib.Path(os.environ["MIMO_JSON_FIXTURE"]).read_text(encoding="utf-8"))
                raise SystemExit({exit_code})
                """))
        fixture_env = {"KIMI_STREAM_FIXTURE": str(fixture)} if leg == "subkimi" else {"MIMO_JSON_FIXTURE": str(fixture)}
        result = subprocess.run(
            [str(ROOT / "bin" / leg), mode, str(self.task), str(log), str(self.repo)],
            env=self._env(
                **fixture_env,
                AIWORK_REVIEW_REPORT_PATH=str(report),
                AIWORK_REVIEW_FACTS_PATH=str(facts),
            ),
            capture_output=True, text=True)
        body = report.read_text(encoding="utf-8") if report.is_file() else ""
        recorded = json.loads(facts.read_text(encoding="utf-8")) if facts.is_file() else {}
        logged = log.read_text(encoding="utf-8") if log.is_file() else ""
        return result, body, recorded, logged, slot

    def _emit(self, leg, family, result, facts, report, log):
        diagnostic = facts.parent / "leg.stderr"
        diagnostic.write_text(result.stderr, encoding="utf-8")
        out = facts.parent / "result.json"
        task_sha = "sha256:" + hashlib.sha256(self.task.read_bytes()).hexdigest()
        command = [
            sys.executable, str(ROOT / "bin" / "_review_result.py"), "emit",
            "--result", str(out), "--run-id", "reader-tools", "--name", leg,
            "--family", family, "--adapter", leg, "--exit-code", str(result.returncode),
            "--task-sha256", task_sha, "--log", str(log), "--diagnostic", str(diagnostic),
            "--report", str(report),
        ]
        if facts.is_file():
            command += ["--facts", str(facts)]
        subprocess.run(command, check=True, capture_output=True, text=True)
        return json.loads(out.read_text(encoding="utf-8"))

    def test_kimi_write_tool_is_not_a_successful_review(self):
        for stream in (KIMI_WRITE, KIMI_WRITE_TOOL_ONLY):
            result, _body, facts, _log, slot = self._run_leg("subkimi", stream)
            self.assertNotEqual(result.returncode, 0, result.stderr)
            self.assertIn("只读清单以外的工具", result.stderr)
            self.assertIn("Write", result.stderr)
            self.assertNotIn("看不出这次调用了哪些工具", result.stderr)
            self.assertNotIn("no verdict", result.stderr)
            self.assertEqual(facts["failure_kind"], "readonly_tools")
            self.assertEqual(facts["verdict"], "PASS")
            emitted = self._emit(
                "subkimi", "moonshot", result, slot / "facts.json",
                slot / "report.md", slot / "leg.log")
            review = _load("review-pr")
            with self.assertRaises(review.ReviewError) as caught:
                review.publishable_model(emitted)
            self.assertEqual(str(caught.exception), "review leg failed: readonly_tools; verdict=PASS")

    def test_mimo_bash_is_not_a_successful_review(self):
        result, _body, facts, _log, slot = self._run_leg("submimo", MIMO_BASH)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("只读清单以外的工具", result.stderr)
        self.assertIn("bash", result.stderr)
        self.assertNotIn("no verdict", result.stderr)
        self.assertEqual(facts["failure_kind"], "readonly_tools")
        self.assertEqual(facts["verdict"], "PASS")
        emitted = self._emit(
            "submimo", "xiaomi", result, slot / "facts.json",
            slot / "report.md", slot / "leg.log")
        review = _load("review-pr")
        with self.assertRaises(review.ReviewError) as caught:
            review.publishable_model(emitted)
        self.assertEqual(str(caught.exception), "review leg failed: readonly_tools; verdict=PASS")

    def test_unrecognized_output_is_not_a_successful_review(self):
        cases = (
            ("subkimi", KIMI_UNKNOWN, "moonshot"),
            ("submimo", MIMO_UNKNOWN, "xiaomi"),
        )
        for leg, stream, family in cases:
            with self.subTest(leg=leg):
                result, _body, facts, _log, slot = self._run_leg(leg, stream)
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn("看不出这次调用了哪些工具", result.stderr)
                self.assertNotIn("no verdict", result.stderr)
                self.assertEqual(facts["failure_kind"], "readonly_tools")
                emitted = self._emit(
                    leg, family, result, slot / "facts.json",
                    slot / "report.md", slot / "leg.log")
                review = _load("review-pr")
                with self.assertRaises(review.ReviewError) as caught:
                    review.publishable_model(emitted)
                self.assertIn("readonly_tools", str(caught.exception))

    def test_reader_tools_stay_successful_and_are_listed(self):
        cases = (
            ("subkimi", KIMI_READ, "Read"),
            ("submimo", MIMO_READ, "read"),
        )
        for leg, stream, listed in cases:
            with self.subTest(leg=leg):
                result, body, facts, logged, _slot = self._run_leg(leg, stream)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Conclusion: PASS", body)
                self.assertIsNone(facts["failure_kind"])
                self.assertEqual(facts["verdict"], "PASS")
                self.assertIn(f"核实工具: {listed}", logged)

    def test_kimi_tool_only_turn_is_a_successful_review(self):
        result, body, facts, logged, _slot = self._run_leg("subkimi", KIMI_TOOL_ONLY)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("看不出这次调用了哪些工具", result.stderr)
        self.assertIn("Conclusion: PASS", body)
        self.assertIsNone(facts["failure_kind"])
        self.assertEqual(facts["verdict"], "PASS")
        self.assertIn("核实工具: Read", logged)

    def test_line_separator_inside_tool_result_stays_one_record(self):
        for separator in ("\u2028", "\u2029", "\u0085"):
            with self.subTest(separator=hex(ord(separator))):
                result, body, facts, logged, _slot = self._run_leg(
                    "subkimi", kimi_line_separator(separator))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("看不出这次调用了哪些工具", result.stderr)
                self.assertIn("Conclusion: PASS", body)
                self.assertIsNone(facts["failure_kind"])
                self.assertEqual(facts["verdict"], "PASS")
                self.assertIn("核实工具: Read", logged)

    def test_unknown_shape_still_fails(self):
        for stream in (KIMI_BAD_CONTENT, KIMI_NOT_JSON):
            with self.subTest(stream=stream.split("\n", 1)[0][:40]):
                result, _body, facts, _log, _slot = self._run_leg("subkimi", stream)
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn("看不出这次调用了哪些工具", result.stderr)
                self.assertEqual(facts["failure_kind"], "readonly_tools")

    def test_existing_failure_is_not_replaced(self):
        limited, _body, facts, _log, _slot = self._run_leg("subkimi", KIMI_LIMIT, exit_code=124)
        self.assertEqual(limited.returncode, 124, limited.stderr)
        self.assertIn("usage limit", limited.stderr)
        self.assertNotIn("只读清单", limited.stderr)
        self.assertEqual(facts["failure_kind"], "timeout")

        provider, _body, pfacts, _log, _slot = self._run_leg("submimo", MIMO_PROVIDER, exit_code=1)
        self.assertEqual(provider.returncode, 1, provider.stderr)
        self.assertIn("provider error line", provider.stderr)
        self.assertNotIn("只读清单", provider.stderr)
        self.assertNotIn("看不出", provider.stderr)
        self.assertIsNone(pfacts["failure_kind"])

        missing, _body, mfacts, _log, _slot = self._run_leg("subkimi", KIMI_WRITE_NO_VERDICT)
        self.assertNotEqual(missing.returncode, 0, missing.stderr)
        self.assertIn("no verdict", missing.stderr)
        self.assertNotIn("只读清单", missing.stderr)
        self.assertEqual(mfacts["failure_kind"], "no_verdict")

    def test_explore_names_this_failure(self):
        self._stub("kimi", textwrap.dedent("""\
            #!/usr/bin/env python3
            import os, pathlib, sys
            sys.stdout.write(pathlib.Path(os.environ["KIMI_STREAM_FIXTURE"]).read_text(encoding="utf-8"))
            """))
        brief = self.root / "brief.md"
        brief.write_text("目标：看这条腿怎么失败。\n", encoding="utf-8")
        result = subprocess.run(
            [str(ROOT / "bin" / "explore"), str(brief), "--repo", str(self.repo), "--leg", "subkimi"],
            env=self._env(KIMI_STREAM_FIXTURE=str(self._write_stream(KIMI_WRITE))),
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("explore: subkimi failed:", result.stderr)
        self.assertIn("readonly_tools", result.stderr)
        self.assertIn("Write", result.stderr)
        self.assertNotIn("subkimi.md", result.stdout)

    def _write_stream(self, text):
        path = self.root / "explore-stream.txt"
        path.write_text(text, encoding="utf-8")
        return path


if __name__ == "__main__":
    unittest.main()

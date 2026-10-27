#!/usr/bin/env python3
"""跑完以后核 Kimi / MiMo 这次实际调用的工具。

配置只读工具之外，还须核实实际调用；无法核实或清单外调用都不能当成成功。
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import hashlib
import importlib.machinery
import importlib.util
import json
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

from _test_settings import write_kimi_config, write_settings, write_programs

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
    {"role":"assistant","content":"","tool_calls":[{"type":"function","id":"tool_read","function":{"name":"Read","arguments":"{\\"path\\":\\"a.txt\\"}"}}]}
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
    '"function":{"name":"Read","arguments":"{\\"path\\":\\"a.txt\\"}"}}]}\n'
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
        '"function":{"name":"Read","arguments":"{\\"path\\":\\"a.txt\\"}"}}]}\n'
        '{"role":"tool","tool_call_id":"tool_read","content":"a' + separator + 'b"}\n'
        '{"role":"assistant","content":"Conclusion: PASS\\n"}\n'
    )


KIMI_BAD_CONTENT = (
    '{"role":"assistant","content":["not a string"],"tool_calls":[{"type":"function",'
    '"id":"tool_read","function":{"name":"Read","arguments":"{\\"path\\":\\"a.txt\\"}"}}]}\n'
    '{"role":"assistant","content":"Conclusion: PASS\\n"}\n'
)

KIMI_NOT_JSON = (
    '{"role":"assistant","content":"Conclusion: PASS\\n"}\n'
    'not json\n'
)

KIMI_WRITE_NO_VERDICT = textwrap.dedent("""\
    {"role":"assistant","content":"Review has evidence but no decision.\\n","tool_calls":[{"type":"function","id":"tool_write","function":{"name":"Write","arguments":"{}"}}]}
    """)

KIMI_LIMIT = (
    '{"role":"assistant","content":"Conclusion: PASS\\n","tool_calls":[{"type":"function","id":"tool_write","function":{"name":"Write","arguments":"{}"}}]}\n'
    "error: failed to run prompt: provider.auth_error: 403 You've reached your weekly (7-day) usage limit\n"
)

# Claude Code 2.1.301 / Xiaomi live probe; synthetic review prose.
MIMO_READ = (ROOT / "tests/fixtures/claude-mimo-stream.jsonl").read_text()
MIMO_BASH = MIMO_READ.replace('"name": "Read"', '"name": "Bash"')
MIMO_PROVIDER = "provider error line\n"
MIMO_CLAUDE_READ = MIMO_READ


def _load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(ROOT / "bin" / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


# Claude Code 2.1.301 / Xiaomi live probe, 2026-10-21. Content trimmed;
# event types, tool block and tool-result shapes retained from the real stream.
MIMO_CLAUDE_READ = '{"type": "system", "subtype": "init", "tools": ["Glob", "Grep", "Read"], "model": "mimo-v2.6-flash"}\n{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "call_06f378455dc747049614438c", "name": "Read", "input": {"file_path": "README.md"}}]}}\n{"type": "user", "message": {"role": "user", "content": [{"tool_use_id": "call_06f378455dc747049614438c", "type": "tool_result", "content": "1\\tSynthetic read-only probe.\\n2\\t"}]}}\n{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "Conclusion: PASS\\n"}]}}\n{"type": "result", "subtype": "success", "is_error": false, "result": "Conclusion: PASS\\n"}\n'


class ReaderToolAuditTests(unittest.TestCase):
    def test_kimi_reader_arguments_match_published_input_schemas(self):
        # Verbatim npm input definitions; provenance and extraction are beside
        # the excerpt. Derive keys here instead of restating the CLI contract.
        source = (ROOT / "tests/fixtures/kimi-code-0.36.1/reader-inputs.mjs").read_text()
        schemas = re.findall(r"^\t(\w+)InputSchema\$1 = object\(\{\n(.*?)^\t\}\);",
                             source, re.M | re.S)
        profile = self.root / "kimi-profile.md"
        subprocess.run([sys.executable, str(ROOT / "bin/_reader_tools.py"),
                        "kimi-profile", str(profile)], check=True)
        tools = json.loads(next(line.removeprefix("tools: ") for line in
                                profile.read_text().splitlines() if line.startswith("tools: ")))
        self.assertCountEqual([name for name, _ in schemas], tools)
        sys.path.insert(0, str(ROOT / "bin"))
        policy = _load("_reader_tools.py")

        def audit(name, arguments, expected):
            stream = self.root / "schema-stream.jsonl"
            stream.write_text(self._reader_stream("subkimi", name, arguments))
            result = subprocess.run(
                [sys.executable, str(ROOT / "bin/_reader_tools.py"),
                 "audit-kimi", str(stream), str(self.repo)], capture_output=True, text=True)
            self.assertEqual(result.returncode, expected,
                             f"{name} {arguments}: {result.stdout}{result.stderr}")

        for name, body in schemas:
            with self.subTest(tool=name):
                native_keys = {quoted or plain for quoted, plain in re.findall(
                    r'^\t\t(?:"([^"]+)"|(\w+)):', body, re.M)}
                self.assertEqual(policy.KIMI_TOOL_INPUTS[name], native_keys)
                fields = [(key, ".optional()" in modifiers, json.loads(description))
                          for key, modifiers, description in re.findall(
                              r'^\t\t(\w+): string\(\)(.*?)\.describe\((".*")\),?$', body, re.M)]
                path_fields = [(key, optional) for key, optional, description in fields
                               if description.startswith(("Path to ", "Directory to search.",
                                                          "File or directory to search."))]
                self.assertEqual(len(path_fields), 1, name)
                path_key, optional = path_fields[0]
                arguments = {key: "a.txt" for key, is_optional, _ in fields if not is_optional}
                audit(name, dict(arguments, **{path_key: "a.txt"}), 0)
                audit(name, dict(arguments, **{path_key: "../outside.txt"}), 3)
                without_path = {key: value for key, value in arguments.items() if key != path_key}
                audit(name, without_path, 0 if optional else 3)
                # A Glob pattern is itself a path; a Grep regex is not. Derive
                # the former's key from the upstream field description too.
                for key, _, description in fields:
                    if description.startswith("Glob pattern to match files."):
                        audit(name, dict(arguments, **{key: "../outside.txt"}), 3)

    def _claude_model_process_ran(self, leg, process):
        self.assertEqual(process.returncode, 0, process.stderr)
        return True

    def test_claude_reported_models_reach_publication_checks(self):
        # Captured from the real Claude Code MiMo/DeepSeek reviews; only
        # prose, file content, and session/accounting metadata were trimmed.
        review = _load("review-pr")
        result_contract = _load("_review_result.py")
        for leg, provider, family in (("submimo", "mimo", "xiaomi"),
                                      ("subdeepseek-agent", "deepseek", "deepseek")):
            stream = (ROOT / f"tests/fixtures/claude-{provider}-model-stream.jsonl").read_text()
            actual = json.loads(stream.split("\n", 1)[0])["model"]
            for requested in (actual, "mimo-v2.6-pro" if provider == "mimo" else "deepseek-pro"):
                with self.subTest(leg=leg, requested=requested):
                    process, _body, facts, _log, slot = self._run_leg(leg, stream, model=requested)
                    if not self._claude_model_process_ran(leg, process):
                        continue
                    emitted = self._emit(leg, family, process, slot / "facts.json",
                                         slot / "report.md", slot / "leg.log")
                    self.assertEqual(facts["model"]["reported"], actual)
                    self.assertEqual(emitted["model"]["reported"], actual)
                    reasons = result_contract.eligibility_reasons(emitted)
                    if requested == actual:
                        self.assertEqual(reasons, [])
                        self.assertEqual(review.publishable_model(emitted), requested)
                    else:
                        self.assertIn("model_report_mismatch", reasons)
                        with self.assertRaises(review.ReviewError):
                            review.publishable_model(emitted)

    def test_claude_response_model_disagreement_is_not_hidden_by_init(self):
        review = _load("review-pr")
        result_contract = _load("_review_result.py")
        for leg, provider, family in (("submimo", "mimo", "xiaomi"),
                                      ("subdeepseek-agent", "deepseek", "deepseek")):
            for source in ("message", "modelUsage"):
                events = [json.loads(line) for line in
                          (ROOT / f"tests/fixtures/claude-{provider}-model-stream.jsonl").read_text().split("\n") if line]
                actual = events[0]["model"]
                different = "mimo-v2.6-pro" if provider == "mimo" else "deepseek-pro"
                if source == "message":
                    next(event["message"] for event in events if event.get("type") == "assistant")["model"] = different
                else:
                    next(event for event in events if event.get("type") == "result")["modelUsage"] = {different: {}}
                stream = "\n".join(json.dumps(event) for event in events) + "\n"
                with self.subTest(leg=leg, source=source):
                    process, _body, facts, _log, slot = self._run_leg(leg, stream, model=actual)
                    if not self._claude_model_process_ran(leg, process):
                        continue
                    self.assertEqual(facts["model"]["reported"], different)
                    emitted = self._emit(leg, family, process, slot / "facts.json",
                                         slot / "report.md", slot / "leg.log")
                    self.assertIn("model_report_mismatch", result_contract.eligibility_reasons(emitted))
                    with self.assertRaises(review.ReviewError):
                        review.publishable_model(emitted)

    def test_missing_claude_model_stays_unknown_without_scraping_text(self):
        review = _load("review-pr")
        for leg, provider, family in (("submimo", "mimo", "xiaomi"),
                                      ("subdeepseek-agent", "deepseek", "deepseek")):
            events = [json.loads(line) for line in
                      (ROOT / f"tests/fixtures/claude-{provider}-model-stream.jsonl").read_text().split("\n") if line]
            actual = events[0]["model"]
            for event in events:
                event.pop("model", None)
                event.pop("modelUsage", None)
                message = event.get("message", {})
                message.pop("model", None)
                for block in message.get("content", []):
                    if block.get("type") in ("text", "tool_result"):
                        key = "text" if block["type"] == "text" else "content"
                        block[key] = '{"model":"untrusted-prose"}\nConclusion: PASS\n'
            stream = "\n".join(json.dumps(event) for event in events) + "\n"
            with self.subTest(leg=leg):
                process, _body, facts, _log, slot = self._run_leg(leg, stream, model=actual)
                if not self._claude_model_process_ran(leg, process):
                    continue
                self.assertIsNone(facts["model"]["reported"])
                emitted = self._emit(leg, family, process, slot / "facts.json",
                                     slot / "report.md", slot / "leg.log")
                self.assertIsNone(emitted["model"]["reported"])
                self.assertEqual(review.publishable_model(emitted), actual)

    def _reader_stream(self, leg, name, arguments):
        events = [json.loads(line) for line in (KIMI_READ if leg == "subkimi" else MIMO_READ).split("\n") if line]
        for event in events:
            if leg == "subkimi" and event.get("tool_calls"):
                event["tool_calls"][0]["function"] = {"name": name, "arguments": json.dumps(arguments)}
            elif leg == "submimo" and event.get("type") == "assistant":
                for block in event["message"]["content"]:
                    if block["type"] == "tool_use":
                        block.update(name=name, input=arguments)
        return "\n".join(json.dumps(event) for event in events) + "\n"

    def test_external_read_fails_and_cannot_publish_for_both_readers(self):
        for leg, family, key in (("submimo", "xiaomi", "file_path"), ("subkimi", "moonshot", "path")):
            with self.subTest(leg=leg):
                stream = self._reader_stream(leg, "Read", {key: str(self.root / "outside.txt")})
                result, _body, facts, _log, slot = self._run_leg(leg, stream)
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertEqual(facts["failure_kind"], "readonly_tools")
                emitted = self._emit(leg, family, result, slot / "facts.json", slot / "report.md", slot / "leg.log")
                review = _load("review-pr")
                with self.assertRaises(review.ReviewError):
                    review.publishable_model(emitted)

    def test_every_reader_accepts_working_directory_paths(self):
        (self.repo / "inner").mkdir()
        (self.repo / "alias").symlink_to("inner", target_is_directory=True)
        (self.repo / "inner" / "back").symlink_to("..", target_is_directory=True)
        for leg in ("submimo", "subkimi"):
            key = "file_path" if leg == "submimo" else "path"
            calls = [("Read", {key: "a.txt"}), ("Read", {key: "__REVIEW_CWD__/a.txt"}),
                     ("Glob", {"pattern": "**/*.txt"}), ("Grep", {"pattern": "a"}),
                     ("Read", {key: "alias/../a.txt"})]
            if leg == "subkimi":
                calls.append(("ReadMediaFile", {"path": "image.png"}))
            for name, arguments in calls:
                with self.subTest(leg=leg, name=name, arguments=arguments):
                    result, body, facts, _log, _slot = self._run_leg(leg, self._reader_stream(leg, name, arguments))
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("Conclusion: PASS", body)
                    self.assertIsNone(facts["failure_kind"])

    def test_retry_and_new_records_preserve_publishable_reviews(self):
        for fixture in ("claude-retry-stream.jsonl", "claude-new-records-stream.jsonl"):
            stream = (ROOT / "tests/fixtures" / fixture).read_text()
            # The local fake-API capture used Claude's default model. Replay
            # that same record shape with the MiMo model selected for this test.
            model = json.loads(MIMO_READ.split("\n", 1)[0])["model"]
            events = [json.loads(line) for line in stream.split("\n") if line]
            captured_model = next(e["message"]["model"] for e in events
                                  if e.get("type") == "assistant" and e["message"].get("model"))
            events = json.loads(json.dumps(events).replace(json.dumps(captured_model), json.dumps(model)))
            # Move a captured status record before init and after result too:
            # lifecycle position must not turn a non-tool record into a failure.
            status = next(e for e in events if e.get("subtype") in ("status", "api_retry"))
            text_delta = next((e for e in events if
                               e.get("event", {}).get("delta", {}).get("type") == "text_delta"), status)
            for before_init in (False, True):
                recorded = ([status, text_delta] + events + [status, text_delta]) if before_init else events
                for mode in ("review", "explore"):
                    with self.subTest(fixture=fixture, before_init=before_init, mode=mode):
                        result, body, facts, log, slot = self._run_leg(
                            "submimo", "\n".join(json.dumps(e) for e in recorded), mode=mode, model=model)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn("Conclusion: PASS", body)
                        self.assertIn("核实工具: Read", log)
                        emitted = self._emit("submimo", "xiaomi", result, slot / "facts.json",
                                             slot / "report.md", slot / "leg.log")
                        self.assertTrue(_load("review-pr").publishable_model(emitted))

    def test_calls_in_new_records_still_prevent_publication(self):
        base = [json.loads(line) for line in MIMO_READ.split("\n") if line]
        call = next(e["message"]["content"][0] for e in base
                    if e.get("type") == "assistant" and e["message"]["content"][0]["type"] == "tool_use")
        for where in (0, 1, len(base)):
            for name, arguments in (("Read", {"file_path": "../outside.txt"}),
                                    ("Read", {}), ("Bash", {"command": "true"})):
                # The outer record is opaque; the enclosed API call is not.
                injected = {"type": "new_record", "payload": dict(call, id="toolu_extra", name=name, input=arguments)}
                events = base[:where] + [injected] + base[where:]
                with self.subTest(where=where, name=name, arguments=arguments):
                    result, _body, facts, _log, slot = self._run_leg(
                        "submimo", "\n".join(json.dumps(e) for e in events))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(facts["failure_kind"], "readonly_tools")
                    emitted = self._emit("submimo", "xiaomi", result, slot / "facts.json",
                                         slot / "report.md", slot / "leg.log")
                    review = _load("review-pr")
                    with self.assertRaises(review.ReviewError):
                        review.publishable_model(emitted)

    def test_api_calls_can_use_new_envelopes(self):
        events = [json.loads(line) for line in MIMO_READ.split("\n") if line]
        for event in events:
            if event.get("type") in ("assistant", "user"):
                event["type"] = "new_record"
                event["payload"] = event.pop("message")
        result, _body, _facts, _log, slot = self._run_leg(
            "submimo", "\n".join(json.dumps(e) for e in events), model=events[0]["model"])
        self.assertEqual(result.returncode, 0, result.stderr)
        emitted = self._emit("submimo", "xiaomi", result, slot / "facts.json",
                             slot / "report.md", slot / "leg.log")
        self.assertTrue(_load("review-pr").publishable_model(emitted))

    def test_incomplete_or_inconsistent_tool_evidence_still_fails(self):
        events = [json.loads(line) for line in
                  (ROOT / "tests/fixtures/claude-new-records-stream.jsonl").read_text().split("\n") if line]
        variants = [events[:-1], [e for e in events if e.get("type") != "user"],
                    [dict(e, tools=["Read", "Bash"]) if e.get("subtype") == "init" else e for e in events],
                    [dict(e, event=dict(e["event"], delta={"type": "input_json_delta", "partial_json": "{"}))
                     if e.get("event", {}).get("delta", {}).get("type") == "input_json_delta" else e for e in events]]
        for index, recorded in enumerate(variants):
            with self.subTest(index=index):
                result, _body, facts, _log, slot = self._run_leg(
                    "submimo", "\n".join(json.dumps(e) for e in recorded))
                self.assertNotEqual(result.returncode, 0)
                emitted = self._emit("submimo", "xiaomi", result, slot / "facts.json",
                                     slot / "report.md", slot / "leg.log")
                review = _load("review-pr")
                with self.assertRaises(review.ReviewError):
                    review.publishable_model(emitted)

    def test_denied_mimo_read_still_prevents_publication(self):
        # Claude Code 2.1.301 live rejection, 2026-10-22. Public synthetic
        # paths/prose only; tool_result_meta and permission_denials retained.
        stream = (ROOT / "tests/fixtures/claude-mimo-denied-stream.jsonl").read_text()
        for recorded in (stream, "\n".join(line for line in stream.split("\n")
                                         if '"type": "assistant"' not in line)):
            with self.subTest(assistant_call_present=recorded == stream):
                result, _body, facts, _log, slot = self._run_leg("submimo", recorded)
                self.assertEqual(facts["failure_kind"], "readonly_tools")
                self.assertIn("路径越界", result.stderr)
                emitted = self._emit("submimo", "xiaomi", result, slot / "facts.json",
                                     slot / "report.md", slot / "leg.log")
                review = _load("review-pr")
                with self.assertRaises(review.ReviewError):
                    review.publishable_model(emitted)

    def test_external_read_remains_readonly_failure_without_successful_finish(self):
        for leg in ("submimo", "subkimi"):
            key = "file_path" if leg == "submimo" else "path"
            stream = self._reader_stream(leg, "Read", {key: str(self.root / "outside.txt")})
            events = [json.loads(line) for line in stream.split("\n") if line]
            if leg == "submimo":
                events = [e for e in events if e.get("type") != "result"]
            else:
                events = [e for e in events if e.get("tool_calls") or e.get("role") != "assistant"]
            incomplete = "\n".join(json.dumps(e) for e in events) + "\n"
            for exit_code in (0, 1, 124):
                with self.subTest(leg=leg, exit_code=exit_code):
                    result, _body, facts, _log, slot = self._run_leg(
                        leg, incomplete, exit_code=exit_code)
                    self.assertEqual(facts["failure_kind"], "readonly_tools", result.stderr)
                    emitted = self._emit(leg, "xiaomi" if leg == "submimo" else "moonshot",
                                         result, slot / "facts.json", slot / "report.md", slot / "leg.log")
                    review = _load("review-pr")
                    with self.assertRaises(review.ReviewError):
                        review.publishable_model(emitted)

    def test_subdirectory_search_ignores_unrelated_external_symlink(self):
        (self.repo / "docs").mkdir()
        (self.repo / "docs" / "guide.md").write_text("public guide\n")
        (self.repo / "external-data").symlink_to(self.root, target_is_directory=True)
        for leg in ("submimo", "subkimi"):
            for name in ("Glob", "Grep"):
                with self.subTest(leg=leg, name=name):
                    stream = self._reader_stream(leg, name, {"path": "docs", "pattern": "*.md"})
                    result, body, facts, _log, _slot = self._run_leg(leg, stream)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("Conclusion: PASS", body)
                    self.assertIsNone(facts["failure_kind"])

    def test_reader_path_escape_and_unprovable_inputs_fail_in_both_modes(self):
        (self.repo / "escape").symlink_to(self.root, target_is_directory=True)
        for leg in ("submimo", "subkimi"):
            key = "file_path" if leg == "submimo" else "path"
            calls = [("Read", {key: p}) for p in ("../outside.txt", "~/.config/aiwork/mimo.env",
                     "/proc/self/environ", "escape/outside.txt", "__REVIEW_CWD__-sibling/file")]
            calls += [("Read", args) for args in ({}, {key: None}, {key: []}, {key: ""}, {key: "a\0b"})]
            calls += [(name, {"path": "../", "pattern": "*"}) for name in ("Glob", "Grep")]
            calls += [("Glob", {"pattern": "../*"}), ("Glob", {"pattern": str(self.root / "*")})]
            if leg == "subkimi":
                calls.append(("ReadMediaFile", {"path": "../outside.png"}))
            for mode in ("review", "explore"):
                for name, arguments in calls:
                    with self.subTest(leg=leg, mode=mode, name=name, arguments=arguments):
                        result, _body, facts, _log, _slot = self._run_leg(
                            leg, self._reader_stream(leg, name, arguments), mode=mode)
                        self.assertNotEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(facts["failure_kind"], "readonly_tools")

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
        self.deployment = self.root / 'deployment'
        shutil.copytree(ROOT / 'bin', self.deployment)
        from _test_settings import write_platform_probe
        write_platform_probe(self.deployment, macos=False)
        wrapper = self.deployment / 'ro-repo-exec'
        wrapper.write_text('#!/bin/bash\nshift 2\nexec "$@"\n')
        wrapper.chmod(0o755)
        self.config = write_settings(self.root / "settings")
        self.data = self.root / "data"
        self.data.mkdir()
        self.fake = self.root / "fake"
        self.fake.mkdir()
        self.task = self.root / "task.md"
        self.task.write_text("# brief\n", encoding="utf-8")
        self.home = self.root / "kimi-home"
        (self.home / "hooks").mkdir(parents=True)
        shutil.copyfile(ROOT / "kimi-review-home/hooks/guard.mjs", self.home / "hooks/guard.mjs")
        (self.home / "credentials").mkdir()
        (self.home / "credentials" / "kimi-code.json").write_text("{}\n", encoding="utf-8")
        write_kimi_config(self.home, self.config)

    def _stub(self, name, body):
        path = self.fake / name
        path.write_text(body, encoding="utf-8")
        path.chmod(0o755)

    def _env(self, **extra):
        write_programs(self.config, self.fake)
        env = dict(os.environ)
        env.update(
            PATH=str(self.fake) + os.pathsep + env.get("PATH", ""),
            AIWORK_CONFIG_DIR=str(self.config),
            AIWORK_DATA_DIR=str(self.data),
            KIMI_REVIEW_HOME=str(self.home),
            AIWORK_REVIEW_RESULT_BIN=str(ROOT / "bin" / "_review_result.py"),
        )
        env.update(extra)
        return env

    def _run_leg(self, leg, stream, *, exit_code=0, mode="review", model=None):
        slot = self.root / f"{leg}-{mode}-{exit_code}-{model}-{hashlib.sha256(stream.encode()).hexdigest()[:8]}"
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
                sys.stdout.write(pathlib.Path(os.environ["KIMI_STREAM_FIXTURE"]).read_text(encoding="utf-8").replace("__REVIEW_CWD__", os.getcwd()))
                raise SystemExit({exit_code})
                """))
        else:
            self._stub("claude", textwrap.dedent(f"""\
                #!/usr/bin/env python3
                import os, pathlib, sys
                if "--output-format" not in sys.argv or sys.argv[sys.argv.index("--output-format") + 1] != "stream-json":
                    raise SystemExit("review must request --output-format stream-json")
                content = pathlib.Path(os.environ["MIMO_JSON_FIXTURE"]).read_text(encoding="utf-8").replace("__REVIEW_CWD__", os.getcwd())
                (sys.stdout if content.lstrip().startswith("{{") else sys.stderr).write(content)
                raise SystemExit({exit_code})
                """))
        fixture_env = {"KIMI_STREAM_FIXTURE": str(fixture)} if leg == "subkimi" else {"MIMO_JSON_FIXTURE": str(fixture)}
        if model is not None:
            fixture_env["MIMO_MODEL" if leg == "submimo" else "DEEPSEEK_MODEL"] = model
        if leg == "subdeepseek-agent":
            fixture_env["DEEPSEEK_API_KEY"] = "fixture-deepseek-key"
        result = subprocess.run(
            [str(self.deployment / leg), mode, str(self.task), str(log), str(self.repo)],
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
        self.assertIn("Bash", result.stderr)
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
            ("subkimi", KIMI_NOT_JSON, "moonshot"),
            ("submimo", MIMO_READ + 'not json\n', "xiaomi"),
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

    def test_kimi_auxiliary_records_do_not_hide_tool_calls(self):
        for tool in (None, "Read", "Write"):
            record = {"role": "new_status", "status": "ready"}
            if tool:
                record["tool_calls"] = [{"type": "function", "id": "extra", "function": {
                    "name": tool, "arguments": json.dumps({"path": "../outside.txt"})}}]
            stream = json.dumps(record) + "\n" + KIMI_READ
            result, _body, facts, _log, _slot = self._run_leg("subkimi", stream)
            self.assertEqual(result.returncode == 0, tool is None, result.stderr)
            if tool:
                self.assertEqual(facts["failure_kind"], "readonly_tools")

    def test_reader_tools_stay_successful_and_are_listed(self):
        cases = (
            ("subkimi", KIMI_READ, "Read"),
            ("submimo", MIMO_READ, "Read"),
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


class ClaudeMimoTests(unittest.TestCase):
    def setUp(self):
        import test_leg_finish as finish
        self.fixture = finish.LegFinish(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.root = self.fixture.root
        self.config = self.root / 'settings'
        self.settings = self.config / 'mimo.env'
        self.settings.write_text('MIMO_BASE_URL=https://token-plan-cn.xiaomimimo.com/anthropic\nMIMO_API_KEY=fixture-mimo-secret\n')
        self.capture = self.root / 'claude-call.json'
        self.stream = self.root / 'claude-stream.jsonl'
        self.stream.write_text(MIMO_CLAUDE_READ)
        self.fixture._write('claude', r"""#!/usr/bin/env python3
import json, os, pathlib, sys
pathlib.Path(os.environ['CLAUDE_CAPTURE']).write_text(json.dumps({
    'argv': sys.argv[1:], 'base_url': os.environ.get('ANTHROPIC_BASE_URL'),
    'model': os.environ.get('ANTHROPIC_DEFAULT_SONNET_MODEL'),
    'authenticated': os.environ.get('ANTHROPIC_AUTH_TOKEN') == 'fixture-mimo-secret',
    'settings': json.loads(pathlib.Path(sys.argv[sys.argv.index('--settings')+1]).read_text()) if '--settings' in sys.argv else None,
    'prompt': sys.stdin.read()}))
sys.stdout.write(pathlib.Path(os.environ['CLAUDE_STREAM']).read_text())
""")
        # The real Linux guard is exercised by the existing platform suites.
        self.fixture._write('ro-repo-exec', '#!/bin/bash\nshift 2\nexec "$@"\n')

    def run_leg(self, mode='review', macos=False, leg='submimo'):
        from _test_settings import write_platform_probe
        write_platform_probe(self.fixture.bin, macos=macos)
        env=self.fixture._env()
        env.update(CLAUDE_CAPTURE=str(self.capture), CLAUDE_STREAM=str(self.stream),
                   AIWORK_REVIEW_REPORT_PATH=str(self.root/'report.md'),
                   AIWORK_REVIEW_FACTS_PATH=str(self.root/'facts.json'))
        # A retired executable is neither installed nor available via PATH.
        self.assertFalse((self.config / 'programs/mimo').exists())
        args=[str(self.fixture.bin/leg)]
        if leg=='subagent':args+=['deepseek']
        return subprocess.run(args+[mode,str(self.root/'task.md'),str(self.root/'leg.log'),str(self.fixture.repo)],
                              env=env,capture_output=True,text=True,timeout=20)

    def test_mimo_uses_claude_xiaomi_and_only_reader_tools_in_both_modes(self):
        for mode in ('review','explore'):
            with self.subTest(mode=mode):
                result=self.run_leg(mode)
                self.assertEqual(result.returncode,0,result.stderr)
                call=json.loads(self.capture.read_text())
                self.assertEqual(call['base_url'],'https://token-plan-cn.xiaomimimo.com/anthropic')
                self.assertTrue(call['authenticated'])
                self.assertEqual(call['model'],'mimo-v2.6-pro')
                args=call['argv']
                self.assertEqual(set(args[args.index('--tools')+1].split(',')),{'Read','Glob','Grep'})
                self.assertEqual(args[args.index('--setting-sources')+1],'')
                self.assertIn('--strict-mcp-config',args)
                self.assertIn('--disable-slash-commands',args)
                self.assertIn('Shell and write tools are unavailable',call['prompt'])
                self.assertIn('核实工具: Read',(self.root/'leg.log').read_text())
                self.assertNotIn('fixture-mimo-secret',result.stdout+result.stderr+(self.root/'leg.log').read_text())

    def test_mimo_supplies_private_read_boundary_settings_without_project_sources(self):
        settings = self.fixture.repo / '.claude'
        settings.mkdir()
        for name in ('settings.json', 'settings.local.json'):
            (settings / name).write_text(json.dumps({'permissions': {
                'blockReadsOutsideWorkingDirectories': False, 'additionalDirectories': ['/']}}))
        for mode in ('review', 'explore'):
            with self.subTest(mode=mode):
                result = self.run_leg(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                call = json.loads(self.capture.read_text())
                self.assertIsNotNone(call['settings'], 'aiwork must supply its own settings file')
                self.assertIs(call['settings']['permissions']['blockReadsOutsideWorkingDirectories'], True)
                args = call['argv']
                self.assertEqual(args[args.index('--setting-sources') + 1], '')
                self.assertEqual(args[args.index('--permission-prompts') + 1], 'none')
                self.assertNotIn('--add-dir', args)
                self.assertFalse(Path(args[args.index('--settings') + 1]).is_relative_to(self.fixture.repo))

    def test_mimo_refuses_nonreader_or_unprovable_stream_in_both_modes(self):
        for stream in (MIMO_CLAUDE_READ.replace('"name": "Read"','"name": "Bash"'),
                       MIMO_CLAUDE_READ+'not json\n',
                       '{"type":"result","result":"Conclusion: PASS"}\n'):
            for mode in ('review','explore'):
                with self.subTest(mode=mode,stream=stream[:60]):
                    self.stream.write_text(stream)
                    result=self.run_leg(mode)
                    self.assertNotEqual(result.returncode,0,result.stderr)
                    facts=json.loads((self.root/'facts.json').read_text())
                    self.assertEqual(facts['failure_kind'],'readonly_tools')
                    diagnostic=self.root/'diagnostic'
                    diagnostic.write_text(result.stderr)
                    emitted=self.root/'result.json'
                    subprocess.run([str(self.fixture.bin/'_python'),str(self.fixture.bin/'_review_result.py'),
                        'emit','--result',str(emitted),'--run-id','claude-mimo',
                        '--name','submimo','--family','xiaomi','--adapter','submimo',
                        '--exit-code',str(result.returncode),'--task-sha256','sha256:'+hashlib.sha256((self.root/'task.md').read_bytes()).hexdigest(),
                        '--log',str(self.root/'leg.log'),'--diagnostic',str(diagnostic),
                        '--report',str(self.root/'report.md'),'--facts',str(self.root/'facts.json')],check=True,capture_output=True)
                    review = _load('review-pr')
                    with self.assertRaises(review.ReviewError):
                        review.publishable_model(json.loads(emitted.read_text()))

    def test_mac_both_providers_share_command_policy(self):
        sys.path.insert(0, str(ROOT / "bin"))
        from _claude_sandbox import TOOLS
        stream = self.stream.read_text()
        events = [json.loads(line) for line in stream.splitlines()]
        events[0]['tools'] = list(TOOLS)
        self.stream.write_text('\n'.join(json.dumps(event) for event in events) + '\n')
        for mode in ('review', 'explore'):
            for leg in ('submimo', 'subagent'):
                result = self.run_leg(mode, True, leg)
                self.assertEqual(result.returncode, 0, result.stderr)
                call = json.loads(self.capture.read_text())
                self.assertEqual(call['argv'][call['argv'].index('--tools') + 1], ','.join(TOOLS))
                self.assertTrue(call['settings']['sandbox']['enabled'])
                self.assertFalse(call['settings']['sandbox']['allowUnsandboxedCommands'])
                self.capture.unlink()

    def test_mimo_settings_fail_before_provider_and_name_bad_item(self):
        good=self.settings.read_text()
        for body,item in ((None,'MIMO_BASE_URL'),('', 'MIMO_BASE_URL'),
                          ('MIMO_BASE_URL=https://token-plan-cn.xiaomimimo.com/anthropic\n','MIMO_API_KEY'),
                          (good.replace('https://','bogus://'),'MIMO_BASE_URL'),
                          (good.replace('fixture-mimo-secret',''), 'MIMO_API_KEY'),
                          (good+'MIMO_API_KEY=another-secret\n','MIMO_API_KEY'),
                          (good.replace('MIMO_API_KEY=','MIMO_API_KEY ='),'MIMO_API_KEY')):
            for mode in ('review','explore'):
                with self.subTest(item=item,body=body,mode=mode):
                    self.capture.unlink(missing_ok=True)
                    if body is None:self.settings.unlink(missing_ok=True)
                    else:self.settings.write_text(body)
                    result=self.run_leg(mode)
                    self.assertNotEqual(result.returncode,0,result.stderr)
                    self.assertIn('mimo.env',result.stderr)
                    self.assertIn(item,result.stderr)
                    self.assertNotIn('fixture-mimo-secret',result.stderr)
                    self.assertFalse(self.capture.exists())



class KimiPreToolGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.repo / "inside.txt").write_text("inside\n")
        self.outside = self.root / "outside.txt"
        self.outside.write_text("outside\n")
        (self.repo / "escape.txt").symlink_to(self.outside)
        self.env = dict(os.environ, AIWORK_KIMI_READER_GUARD=json.dumps([
            sys.executable, str(ROOT / "bin/_reader_tools.py"),
            "kimi-hook", str(self.repo)]))

    def guard(self, tool, arguments, *, env=None):
        # Envelope and parameter names come from the installed 0.36.1 CLI's
        # externalHooks runner; the native local-provider probe checks wiring.
        event = {"hook_event_name": "PreToolUse", "cwd": str(self.repo),
                 "tool_name": tool, "tool_input": arguments}
        return subprocess.run(["node", str(ROOT / "kimi-review-home/hooks/guard.mjs")],
                              input=json.dumps(event), cwd=self.repo,
                              env=self.env if env is None else env,
                              text=True, capture_output=True)

    def test_readers_deny_outside_paths_before_execution(self):
        for tool in ("Read", "ReadMediaFile", "Glob", "Grep"):
            for path in (str(self.outside), "../outside.txt", "escape.txt"):
                with self.subTest(tool=tool, path=path):
                    arguments = {"path": path}
                    if tool in ("Glob", "Grep"):
                        arguments["pattern"] = "*"
                    result = self.guard(tool, arguments)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]
                                     ["permissionDecision"], "deny")

    def test_readers_allow_inside_paths_and_search_defaults(self):
        for tool, arguments in (("Read", {"path": "inside.txt"}),
                                ("ReadMediaFile", {"path": "inside.txt"}),
                                ("Glob", {"pattern": "*.txt"}),
                                ("Grep", {"pattern": "inside"})):
            with self.subTest(tool=tool):
                result = self.guard(tool, arguments)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unrecognized_reader_arguments_fail_closed_before_and_after(self):
        for tool in ("Read", "ReadMediaFile", "Glob", "Grep"):
            with self.subTest(tool=tool):
                arguments = {"path": "inside.txt", "pattern": "inside",
                             "renamed_path": str(self.outside)}
                if tool in ("Read", "ReadMediaFile"):
                    arguments.pop("pattern")
                with self.subTest(phase="before execution"):
                    self.assertEqual(self.guard(tool, arguments).returncode, 2)
                events = [json.loads(line) for line in KIMI_READ.split("\n") if line]
                call = events[1]["tool_calls"][0]["function"]
                call.update(name=tool, arguments=json.dumps(arguments))
                stream = self.root / "unknown-argument.jsonl"
                stream.write_text("\n".join(json.dumps(event) for event in events) + "\n")
                audit = subprocess.run([sys.executable, str(ROOT / "bin/_reader_tools.py"),
                                        "audit-kimi", str(stream), str(self.repo)],
                                       text=True, capture_output=True)
                self.assertEqual(audit.returncode, 3, audit.stdout + audit.stderr)

    def test_unknown_tools_and_unusable_policy_fail_closed(self):
        for tool in ("Bash", "Write", "ReadRenamed"):
            self.assertEqual(self.guard(tool, {}).returncode, 2)
        for command in (None, "invalid json", json.dumps(["/missing/python"])):
            with self.subTest(command=command):
                env = dict(self.env)
                if command is None:
                    env.pop("AIWORK_KIMI_READER_GUARD")
                else:
                    env["AIWORK_KIMI_READER_GUARD"] = command
                self.assertEqual(self.guard("Read", {"path": "inside.txt"}, env=env).returncode, 2)


if __name__ == "__main__":
    unittest.main()

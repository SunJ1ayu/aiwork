#!/usr/bin/env python3
"""Reader policies and tool trace checks.

Reader profiles, Kimi's execution-time hook and post-run checks share policy.
The Mac command inventory comes from _claude_sandbox.py.
"""

import json
import sys
from pathlib import Path

from _paths import inside

# An unknown input may be a renamed path. Reject it in both the hook and audit.
KIMI_TOOL_INPUTS = {
    "Read": frozenset(("path", "line_offset", "n_lines")),
    "ReadMediaFile": frozenset(("path", "region", "full_resolution")),
    "Glob": frozenset(("pattern", "path", "include_ignored", "include_dirs")),
    "Grep": frozenset(("pattern", "path", "glob", "type", "output_mode",
                       "-i", "-n", "-A", "-B", "-C", "head_limit", "offset",
                       "multiline", "include_ignored")),
}
KIMI_TOOLS = tuple(KIMI_TOOL_INPUTS)

# Claude Code's exact built-in tool selection and post-run allowlist.
CLAUDE_READER_TOOLS = ("Read", "Glob", "Grep")

OUTSIDE = "这次调用了只读清单以外的工具: {names} ⇒ 不发评审"
UNREADABLE = "输出里看不出这次调用了哪些工具 ⇒ 不发评审"


class ReaderScopeError(ValueError):
    pass


def check_reader_path(name, arguments, repo, read_key):
    """Audit the paths recorded in this call, without enumerating the repository.

    Execution-time protection owns search traversal; a post-run scan cannot
    undo reads and rejects unrelated links that the tool never visits.
    """
    if name not in KIMI_TOOLS and name not in CLAUDE_READER_TOOLS:
        return
    key = read_key if name == "Read" else "path"
    path = arguments.get(key, "." if name in {"Glob", "Grep"} else None)
    if not isinstance(path, str) or not path or "\0" in path:
        raise ReaderScopeError(name)

    def check(target):
        if inside(str(repo), str(target), literal=False)[0] != 0:
            raise ReaderScopeError(name)

    try:
        target = Path(repo) / Path(path).expanduser()
        check(target)
        if name == "Glob":
            pattern = arguments.get("pattern")
            if not isinstance(pattern, str) or not pattern or "\0" in pattern:
                raise ReaderScopeError(name)
            check(target / Path(pattern).expanduser())
    except (OSError, RuntimeError, ValueError) as exc:
        raise ReaderScopeError(name) from exc


def english_list(names):
    names = tuple(names)
    if len(names) == 1:
        return names[0]
    if len(names) == 2:
        return f"{names[0]} and {names[1]}"
    return ", ".join(names[:-1]) + ", and " + names[-1]


def check_kimi_reader_path(name, arguments, repo):
    if name not in KIMI_TOOL_INPUTS:
        return
    if arguments.keys() - KIMI_TOOL_INPUTS[name]:
        raise ReaderScopeError(name)
    check_reader_path(name, arguments, repo, "path")


def kimi_profile():
    tools = json.dumps(list(KIMI_TOOLS), ensure_ascii=False)
    return (
        "---\n"
        "name: aiwork-review\n"
        "description: Read-only repository reviewer\n"
        f"tools: {tools}\n"
        "subagents: []\n"
        "---\n"
        "Read the task and repository files. Shell and write tools are unavailable. "
        "Do not claim to have run tests.\n"
    )


def claude_prompt():
    tools = english_list(CLAUDE_READER_TOOLS)
    return (
        "Read the task below first. "
        f"Inspect the repository with {tools}. "
        "Shell and write tools are unavailable. Do not claim to have run tests. "
        "Git history and status are in aiwork-git-context.txt; read aiwork-review.diff "
        "when the task refers to it. Treat the task file as self-contained. "
        "Do not read or request paths outside the working directory, spawn sub-agents, "
        "or wait for input. Output the complete answer now as plain text. "
        "If context is insufficient, output NEEDS_MORE_INFO with the missing context."
    )


def _events(text):
    """JSON objects, one per newline. None means a line is not a JSON object.

    Records end with ``\\n``. ``splitlines()`` also splits on U+2028, U+2029,
    and U+0085, which kimi-code's ``JSON.stringify`` leaves inside a tool
    result string.
    """
    events = []
    for raw in text.split("\n"):
        line = raw.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            return None
        if not isinstance(event, dict):
            return None
        events.append(event)
    return events or None


def check_recorded_paths(text, repo, *, claude):
    """Check known calls even if the CLI subsequently fails or truncates output.

    This cannot prove the stream complete; the strict audit below still must
    do that. A known violation, including a native permission denial, is enough
    to reject the run regardless of its final verdict or process status.
    """
    for line in text.split("\n"):
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if claude:
            for block in claude_records(event):
                if block.get("type") in ("tool_use", "permission_denial") and isinstance(block.get("input"), dict):
                    check_reader_path(block.get("name"), block["input"], repo, "file_path")
        elif isinstance(event.get("tool_calls"), list):
            for call in event["tool_calls"]:
                function = call.get("function") if isinstance(call, dict) else None
                if not isinstance(function, dict):
                    continue
                try:
                    arguments = json.loads(function.get("arguments", ""))
                except (TypeError, json.JSONDecodeError):
                    continue
                if isinstance(arguments, dict):
                    check_kimi_reader_path(function.get("name"), arguments, repo)


def audit_kimi(text, repo):
    """Tool names in order, or None when recorded calls cannot be audited."""
    check_recorded_paths(text, repo, claude=False)
    events = _events(text)
    if events is None:
        return None
    tools = []
    for event in events:
        role = event.get("role")
        # flushAssistant omits content when the turn is only tool calls:
        # the value is undefined, and JSON.stringify drops the key.
        if role == "assistant" and "content" in event and not isinstance(event["content"], str):
            return None
        if role == "assistant" and "content" not in event and "tool_calls" not in event:
            return None
        if "tool_calls" not in event:
            continue
        calls = event["tool_calls"]
        if not isinstance(calls, list):
            return None
        for call in calls:
            if not isinstance(call, dict):
                return None
            function = call.get("function")
            name = function.get("name") if isinstance(function, dict) else None
            if not isinstance(name, str) or not name:
                return None
            try:
                arguments = json.loads(function.get("arguments", ""))
            except (json.JSONDecodeError, TypeError):
                return None
            if not isinstance(arguments, dict):
                return None
            tools.append(name)
    return tools


def claude_records(value):
    """Find API tool records independently of the CLI's enclosing event types.

    Streaming content blocks must be assembled before checking their inputs.
    Tool inputs and results are payloads, not more invocation records.
    """
    if isinstance(value, list):
        for item in value:
            yield from claude_records(item)
    elif isinstance(value, dict):
        kind = value.get("type")
        if kind in ("tool_use", "tool_result", "server_tool_use",
                    "content_block_start", "content_block_delta", "content_block_stop"):
            yield value
            return
        for key, child in value.items():
            if key == "permission_denials":
                if not isinstance(child, list):
                    yield {"type": "permission_denial"}  # Unprovable denial record.
                else:
                    for denial in child:
                        yield dict(type="permission_denial",
                                   name=denial.get("tool_name") if isinstance(denial, dict) else None,
                                   input=denial.get("tool_input") if isinstance(denial, dict) else None)
            else:
                yield from claude_records(child)


def audit_claude(text, repo, allowed=CLAUDE_READER_TOOLS):
    """Audit API calls, inventory and completion; other CLI records are opaque."""
    check_recorded_paths(text, repo, claude=True)
    events = _events(text)
    if events is None:
        return None
    initialized = finished = False
    calls, results, streaming = {}, set(), {}
    tools = []

    def result(block):
        ident = block.get("tool_use_id")
        if not isinstance(ident, str) or ident not in calls:
            raise ValueError
        results.add(ident)

    def call(block, source):
        name, ident, arguments = block.get("name"), block.get("id"), block.get("input")
        if not isinstance(name, str) or not name or not isinstance(arguments, dict):
            raise ValueError
        check_reader_path(name, arguments, repo, "file_path")
        tools.append(name)
        if source == "denial":
            return
        if not isinstance(ident, str) or not ident:
            raise ValueError
        if ident in calls:
            old, sources = calls[ident]
            if old != (name, arguments) or source in sources:
                raise ValueError
            sources.add(source)
        else:
            calls[ident] = ((name, arguments), {source})

    for event in events:
        kind = event.get("type")
        if kind == "system" and event.get("subtype") == "init":
            inventory = event.get("tools")
            if initialized or finished or not isinstance(inventory, list) or any(not isinstance(t, str) for t in inventory):
                return None
            if set(inventory) != set(allowed):
                return None
            initialized = True
        elif kind == "result":
            if not initialized or finished or streaming or event.get("subtype") != "success" or event.get("is_error") is not False or not isinstance(event.get("result"), str):
                return None
            finished = True

        try:
            for block in claude_records(event):
                typ = block.get("type")
                if finished and typ in ("tool_use", "tool_result", "server_tool_use"):
                    return None
                if typ == "tool_use":
                    call(block, "complete")
                elif typ == "permission_denial":
                    call(block, "denial")
                elif typ == "tool_result":
                    result(block)
                elif typ == "content_block_start":
                    index, content = block.get("index"), block.get("content_block")
                    if isinstance(content, dict) and content.get("type") == "tool_use":
                        if finished or not isinstance(index, int) or index in streaming:
                            return None
                        streaming[index] = (content, [])
                    elif isinstance(content, dict) and content.get("type") == "tool_result":
                        if finished:
                            return None
                        result(content)
                    elif isinstance(content, dict) and content.get("type") == "server_tool_use":
                        return None
                elif typ == "content_block_delta":
                    index, delta = block.get("index"), block.get("delta")
                    if isinstance(delta, dict) and delta.get("type") == "input_json_delta":
                        if not isinstance(index, int) or index not in streaming or not isinstance(delta.get("partial_json"), str):
                            return None
                        streaming[index][1].append(delta["partial_json"])
                elif typ == "content_block_stop":
                    index = block.get("index")
                    if not isinstance(index, int) or index not in streaming:
                        continue
                    content, fragments = streaming.pop(index)
                    if fragments:
                        content = dict(content, input=json.loads("".join(fragments)))
                    call(content, "stream")
                else:
                    return None
        except ReaderScopeError:
            raise
        except (ValueError, TypeError):
            return None
    return tools if initialized and finished and not streaming and results == calls.keys() else None


def _report(found, allowed):
    if found is None:
        print(UNREADABLE)
        return 1
    bad = []
    for name in found:
        if name not in allowed and name not in bad:
            bad.append(name)
    if bad:
        print(OUTSIDE.format(names=", ".join(bad)))
        return 1
    seen = []
    for name in found:
        if name not in seen:
            seen.append(name)
    print("（没有）" if not seen else ", ".join(seen))
    return 0


def main(argv):
    if len(argv) < 2:
        print("usage: _reader_tools.py <command> [args]", file=sys.stderr)
        return 2
    cmd = argv[1]
    try:
        if cmd == "kimi-tools":
            print(english_list(KIMI_TOOLS))
        elif cmd == "kimi-profile":
            Path(argv[2]).write_text(kimi_profile(), encoding="utf-8")
        elif cmd == "kimi-hook":
            event = json.load(sys.stdin)
            repo = Path(argv[2]).resolve(strict=True)
            if (not isinstance(event, dict) or Path.cwd().resolve() != repo
                    or event.get("tool_name") not in KIMI_TOOLS
                    or not isinstance(event.get("tool_input"), dict)):
                return 2
            check_kimi_reader_path(event["tool_name"], event["tool_input"], repo)
        elif cmd == "claude-tools":
            print(",".join(CLAUDE_READER_TOOLS))
        elif cmd == "claude-prompt":
            print(claude_prompt())
        elif cmd == "claude-settings":
            Path(argv[2]).write_text(json.dumps({"permissions": {
                "blockReadsOutsideWorkingDirectories": True}}) + "\n", encoding="utf-8")
        elif cmd == "audit-kimi":
            text = Path(argv[2]).read_text(encoding="utf-8", errors="replace") if Path(argv[2]).is_file() else ""
            return _report(audit_kimi(text, Path(argv[3])), frozenset(KIMI_TOOLS))
        elif cmd in ("audit-claude", "audit-claude-sandbox"):
            text = Path(argv[2]).read_text(encoding="utf-8", errors="replace") if Path(argv[2]).is_file() else ""
            allowed = CLAUDE_READER_TOOLS
            if cmd == "audit-claude-sandbox":
                from _claude_sandbox import TOOLS
                allowed = TOOLS
            return _report(audit_claude(text, Path(argv[3]), allowed), frozenset(allowed))
        else:
            print(f"unknown command {cmd}", file=sys.stderr)
            return 2
    except ReaderScopeError as exc:
        print(f"这次读工具的路径越界或无法核实在工作目录内: {exc} ⇒ 不发评审")
        # Distinguish observed scope violations from incomplete/unknown streams.
        return 3
    except (OSError, IndexError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

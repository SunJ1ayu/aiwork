#!/usr/bin/env python3
"""The reader-tool list for Kimi and MiMo.

The CLI configuration and the post-run check both read this file. A second
handwritten list would drift, and a run that called something else would still
look successful.
"""

import json
import os
import sys
from pathlib import Path

from _paths import inside

# Kimi's agent profile `tools` field, in the order the prompt names them.
KIMI_TOOLS = ("Read", "ReadMediaFile", "Glob", "Grep")

# Claude Code's exact built-in tool selection and post-run allowlist.
CLAUDE_READER_TOOLS = ("Read", "Glob", "Grep")

KIMI_ROLES = frozenset({"meta", "assistant", "tool"})

OUTSIDE = "这次调用了只读清单以外的工具: {names} ⇒ 不发评审"
UNREADABLE = "输出里看不出这次调用了哪些工具 ⇒ 不发评审"


class ReaderScopeError(ValueError):
    pass


def check_reader_path(name, arguments, repo, read_key):
    """Prove the complete read scope, including search patterns and symlinks.

    A directory search can follow links below its root. Conservatively reject
    that search if any reachable link escapes, even if a filter might skip it.
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
            # Glob traversal and brace alternatives cannot widen the root.
            if not isinstance(pattern, str) or not pattern or "\0" in pattern or ".." in pattern:
                raise ReaderScopeError(name)
            check(target / Path(pattern).expanduser())
        # An absolute Glob pattern can select a different in-repo subtree
        # from path, and wildcard components can select symlinks there.
        search_root = Path(repo) if name == "Glob" else target
        if name in {"Glob", "Grep"} and search_root.is_dir():
            seen = set()

            def unreadable(_error):
                raise ReaderScopeError(name)

            for directory, dirs, files in os.walk(search_root, followlinks=True, onerror=unreadable):
                stat = os.stat(directory)
                ident = (stat.st_dev, stat.st_ino)
                if ident in seen:
                    dirs.clear()
                    continue
                seen.add(ident)
                for entry in dirs + files:
                    child = Path(directory) / entry
                    if child.is_symlink():
                        check(child)
    except (OSError, RuntimeError, ValueError) as exc:
        raise ReaderScopeError(name) from exc


def english_list(names):
    names = tuple(names)
    if len(names) == 1:
        return names[0]
    if len(names) == 2:
        return f"{names[0]} and {names[1]}"
    return ", ".join(names[:-1]) + ", and " + names[-1]


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


def audit_kimi(text, repo):
    """Tool names in order, or None when the stream is not the known shape."""
    events = _events(text)
    if events is None:
        return None
    tools = []
    for event in events:
        role = event.get("role")
        if role not in KIMI_ROLES:
            return None
        if role != "assistant":
            continue
        # flushAssistant omits content when the turn is only tool calls:
        # the value is undefined, and JSON.stringify drops the key.
        if "content" in event and not isinstance(event["content"], str):
            return None
        if "content" not in event and "tool_calls" not in event:
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
            check_reader_path(name, arguments, repo, "path")
            tools.append(name)
    return tools


def audit_claude(text, repo):
    """Require a complete Claude stream with its tool inventory and every call.

    Shapes are from Claude Code 2.1.301 against Xiaomi's Anthropic API.
    Unknown records are evidence we cannot audit, never proof of no tools.
    """
    events = _events(text)
    if events is None:
        return None
    initialized = finished = False
    calls = {}
    tools = []
    for event in events:
        if finished:
            return None
        kind = event.get("type")
        if kind == "system":
            subtype = event.get("subtype")
            if subtype == "init":
                inventory = event.get("tools")
                if initialized or not isinstance(inventory, list) or any(not isinstance(t, str) for t in inventory):
                    return None
                if set(inventory) != set(CLAUDE_READER_TOOLS):
                    return None
                initialized = True
            elif not initialized or subtype not in {"thinking_tokens", "informational"}:
                return None
        elif not initialized:
            return None
        elif kind == "assistant":
            message = event.get("message")
            if not isinstance(message, dict) or not isinstance(message.get("content"), list):
                return None
            for block in message["content"]:
                if not isinstance(block, dict):
                    return None
                typ = block.get("type")
                if typ == "tool_use":
                    name, ident = block.get("name"), block.get("id")
                    if not isinstance(name, str) or not name or not isinstance(ident, str) or not ident:
                        return None
                    if not isinstance(block.get("input"), dict) or ident in calls:
                        return None
                    check_reader_path(name, block["input"], repo, "file_path")
                    calls[ident] = name
                    tools.append(name)
                elif typ not in {"text", "thinking", "redacted_thinking"}:
                    return None
        elif kind == "user":
            message = event.get("message")
            if not isinstance(message, dict) or not isinstance(message.get("content"), list):
                return None
            for block in message["content"]:
                if not isinstance(block, dict) or block.get("type") != "tool_result" or block.get("tool_use_id") not in calls:
                    return None
        elif kind == "result":
            if event.get("subtype") != "success" or event.get("is_error") is not False or not isinstance(event.get("result"), str):
                return None
            finished = True
        else:
            return None
    return tools if initialized and finished else None


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
        elif cmd == "claude-tools":
            print(",".join(CLAUDE_READER_TOOLS))
        elif cmd == "claude-prompt":
            print(claude_prompt())
        elif cmd == "audit-kimi":
            text = Path(argv[2]).read_text(encoding="utf-8", errors="replace") if Path(argv[2]).is_file() else ""
            return _report(audit_kimi(text, Path(argv[3])), frozenset(KIMI_TOOLS))
        elif cmd == "audit-claude":
            text = Path(argv[2]).read_text(encoding="utf-8", errors="replace") if Path(argv[2]).is_file() else ""
            return _report(audit_claude(text, Path(argv[3])), frozenset(CLAUDE_READER_TOOLS))
        else:
            print(f"unknown command {cmd}", file=sys.stderr)
            return 2
    except ReaderScopeError as exc:
        print(f"这次读工具的路径越界或无法核实在工作目录内: {exc} ⇒ 不发评审")
        return 1
    except (OSError, IndexError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

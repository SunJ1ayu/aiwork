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

# Kimi's agent profile `tools` field, in the order the prompt names them.
KIMI_TOOLS = ("Read", "ReadMediaFile", "Glob", "Grep")

# MiMo's agent `tools` map. True is enabled and allowed after the run.
# False stays in the config so the CLI cannot fall open on a missing key.
# Names come from `mimo debug agent` for the full set this CLI understands.
MIMO_TOOLS = {
    "write": False, "edit": False, "patch": False, "task": False,
    "webfetch": False, "websearch": False, "skill": False,
    "actor": False, "workflow": False, "memory": False,
    "change_directory": False, "history": False, "plan_exit": False,
    "question": False, "todowrite": False, "todoread": False, "invalid": False,
    "bash": False, "read": True, "glob": True, "grep": True,
}
MIMO_PERMISSION = {
    "read": "allow", "glob": "allow", "grep": "allow",
    "write": "deny", "edit": "deny", "patch": "deny", "task": "deny",
    "webfetch": "deny", "external_directory": "deny", "bash": "deny",
}

KIMI_ROLES = frozenset({"meta", "assistant", "tool"})
MIMO_TYPES = frozenset({"step_start", "tool_use", "text", "step_finish"})

OUTSIDE = "这次调用了只读清单以外的工具: {names} ⇒ 不发评审"
UNREADABLE = "输出里看不出这次调用了哪些工具 ⇒ 不发评审"


def enabled_mimo_tools():
    return tuple(name for name, enabled in MIMO_TOOLS.items() if enabled)


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


def mimo_prompt():
    tools = english_list(enabled_mimo_tools())
    return (
        "Read the attached task file first. "
        f"Review the repository with {tools}. "
        "Shell and write tools are unavailable. Do not claim to have run tests. "
        "Git history and status are in aiwork-git-context.txt; read aiwork-review.diff "
        "when the task refers to it. Treat the task file as self-contained. "
        "Do not read or request paths outside the working directory, spawn sub-agents, "
        "or wait for input. Output the complete answer now as plain text. "
        "If context is insufficient, output NEEDS_MORE_INFO with the missing context."
    )


def write_mimo_config(path: Path, agent: str) -> None:
    cfg = {"agent": {agent: {
        "description": "aiwork isolated review leg",
        "mode": "primary",
        "tools": MIMO_TOOLS,
        "permission": MIMO_PERMISSION,
    }}}
    # Atomic replace: a concurrent leg must not read a half-written config and
    # fall back to the built-in plan agent, which has bash and write enabled.
    tmpath = str(path) + ".tmp." + str(os.getpid())
    with open(tmpath, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2)
    os.replace(tmpath, path)


def _events(text):
    """Known-or-not is decided by the caller. None means a line is not a JSON object."""
    events = []
    for raw in text.splitlines():
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


def audit_kimi(text):
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
        if not isinstance(event.get("content"), str):
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
            tools.append(name)
    return tools


def audit_mimo(text):
    events = _events(text)
    if events is None:
        return None
    tools = []
    for event in events:
        kind = event.get("type")
        if kind not in MIMO_TYPES:
            return None
        if kind == "tool_use":
            part = event.get("part")
            name = part.get("tool") if isinstance(part, dict) else None
            if not isinstance(name, str) or not name:
                return None
            tools.append(name)
        elif kind == "text":
            part = event.get("part")
            if not isinstance(part, dict) or not isinstance(part.get("text"), str):
                return None
    return tools


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
        elif cmd == "mimo-prompt":
            print(mimo_prompt())
        elif cmd == "mimo-config":
            write_mimo_config(Path(argv[2]), argv[3])
        elif cmd == "audit-kimi":
            text = Path(argv[2]).read_text(encoding="utf-8", errors="replace") if Path(argv[2]).is_file() else ""
            return _report(audit_kimi(text), frozenset(KIMI_TOOLS))
        elif cmd == "audit-mimo":
            text = Path(argv[2]).read_text(encoding="utf-8", errors="replace") if Path(argv[2]).is_file() else ""
            return _report(audit_mimo(text), frozenset(enabled_mimo_tools()))
        else:
            print(f"unknown command {cmd}", file=sys.stderr)
            return 2
    except (OSError, IndexError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

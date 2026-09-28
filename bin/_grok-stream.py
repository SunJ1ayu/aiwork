#!/usr/bin/env python3
"""Extract Grok Build's top-level report; tool results are never verdict text."""
import json
from pathlib import Path
import sys


def consume(lines, report, expected):
    models = set()
    terminal = None
    malformed = False
    has_text = False
    for line in lines:
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                raise ValueError("non-object event")
            # Subagent messages cannot supply the parent's report or completion.
            if event.get("parent_tool_use_id") is not None:
                continue
            kind = event.get("type")
            if kind == "system" and event.get("subtype") == "init":
                if event.get("model"):
                    models.add(event["model"])
            elif kind == "assistant":
                message = event["message"]
                if message.get("model"):
                    models.add(message["model"])
                for block in message["content"]:
                    if block.get("type") == "text" and block.get("text", "").strip():
                        report.write(block["text"] + "\n")
                        report.flush()
                        has_text = True
            elif kind == "result":
                if terminal is not None:
                    malformed = True
                terminal = event
        except (ValueError, KeyError, TypeError, AttributeError):
            malformed = True
    terminal = terminal or {}
    identity_ok = models == {expected}
    success = (not malformed and has_text and identity_ok
               and terminal.get("subtype") == "success"
               and terminal.get("is_error") is False
               and terminal.get("stop_reason") == "end_turn")
    return {
        "success": success,
        "identity_ok": identity_ok,
        "models": sorted(models),
        "malformed": malformed,
        "has_text": has_text,
        "subtype": terminal.get("subtype"),
        "stop_reason": terminal.get("stop_reason"),
        "num_turns": terminal.get("num_turns"),
        "usage": terminal.get("usage"),
        "total_cost_usd": terminal.get("total_cost_usd"),
        "session_id": terminal.get("session_id"),
    }


if __name__ == "__main__":
    with Path(sys.argv[1]).open("a", encoding="utf-8") as report:
        result = consume(sys.stdin, report, sys.argv[3])
    Path(sys.argv[2]).write_text(json.dumps(result) + "\n", encoding="utf-8")
    sys.exit(0 if result["success"] else 1)

#!/usr/bin/env python3
"""Decode Cursor's non-partial stream; tool/user text never supplies a verdict."""
import json
from pathlib import Path
import re
import sys
from _review_result import cursor_model_family


def consume(lines, report, expected):
    models = set()
    terminal = None
    session = None
    malformed = False
    has_text = False
    for line in lines:
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                raise ValueError("non-object event")
            if event.get("parent_tool_use_id") is not None:
                continue
            if terminal is not None:
                raise ValueError("event after terminal result")
            kind = event.get("type")
            if kind == "system" and event.get("subtype") == "init":
                if session is not None:
                    raise ValueError("duplicate init")
                session = event.get("session_id")
                if not isinstance(session, str) or not session:
                    raise ValueError("missing session")
                models.add(event["model"])
            elif session is None or event.get("session_id") != session:
                raise ValueError("missing or mismatched session")
            elif kind == "assistant":
                message = event["message"]
                if message.get("role") != "assistant":
                    raise ValueError("wrong role")
                for block in message["content"]:
                    text = block.get("text")
                    if block.get("type") == "text" and isinstance(text, str):
                        # Blank blocks stay out of the process log. Whether the
                        # last message has content is decided later, on the report.
                        if text.strip():
                            report.write(text + "\n")
                            report.flush()
                        has_text = True
            elif kind == "result":
                terminal = event
        except (ValueError, KeyError, TypeError, AttributeError):
            malformed = True
    terminal = terminal or {}
    final = terminal.get("result") if isinstance(terminal.get("result"), str) else None
    # Init contains a human label, not an ID. Cursor's parameterized models even
    # have different labels in `models` and init. Check family without inventing
    # exact reported IDs; the shared result contract records the invoked --model.
    family = cursor_model_family(expected)
    family_ok = family is not None and len(models) == 1 and all(
        isinstance(value, str) and cursor_model_family(
            re.sub(r"[^a-z0-9._-]+", "-", value.lower()).strip("-")) == family
        for value in models)
    success = (not malformed and has_text and family_ok
               and terminal.get("subtype") == "success"
               and terminal.get("is_error") is False
               and isinstance(terminal.get("result"), str))
    return {
        "success": success, "family_ok": family_ok,
        "models": sorted(models), "malformed": malformed, "has_text": has_text,
        "reported_model": None,
        "subtype": terminal.get("subtype"), "session_id": session,
        "usage": terminal.get("usage"), "duration_ms": terminal.get("duration_ms"),
        "final_message": final,
    }


if __name__ == "__main__":
    with Path(sys.argv[1]).open("a", encoding="utf-8") as report:
        result = consume(sys.stdin, report, sys.argv[3])
    final = result.pop("final_message", None)
    Path(sys.argv[2]).write_text(json.dumps(result) + "\n", encoding="utf-8")
    if isinstance(final, str) and len(sys.argv) > 4:
        Path(sys.argv[4]).write_text(final)
    sys.exit(0 if result["success"] else 1)

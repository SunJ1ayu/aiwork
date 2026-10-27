"""Exercise the installed Kimi CLI against an isolated, local-only provider."""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import signal
import struct
import subprocess
import sys
import tempfile
import threading
import tomllib
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _reader_tools import KIMI_TOOL_INPUTS

PROBE_MODEL = "aiwork-local-probe"


def _schema(tools):
    found = {}
    for tool in tools:
        function = tool["function"]
        name = function["name"]
        if tool["type"] != "function" or name in found:
            raise ValueError("duplicate or unsupported native tool")
        found[name] = function["parameters"]
    if found.keys() != KIMI_TOOL_INPUTS.keys():
        raise ValueError("native reader tool list changed")
    for name, fields in KIMI_TOOL_INPUTS.items():
        schema = found[name]
        properties = schema["properties"]
        required = {"pattern"} if name in ("Glob", "Grep") else {"path"}
        if (set(properties) != fields or set(schema.get("required", [])) != required
                or properties["path"].get("type") != "string"):
            raise ValueError("native reader input schema changed: " + name)


def _png():
    def chunk(kind, data):
        return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\x01\x02\x03")) + chunk(b"IEND", b""))


def preflight(cli, home, profile, *, timeout=30):
    home, profile = Path(home), Path(profile)
    hooks = tomllib.loads((home / "config.toml").read_text())["hooks"]
    with tempfile.TemporaryDirectory(prefix="kimi-preflight-", dir=home.parent) as temporary:
        root = Path(temporary)
        repo, state = root / "repo", root / "home"
        repo.mkdir()
        state.mkdir()
        outside = root / "outside"
        outside.mkdir()
        inside_marker, outside_marker = "AIWORK_KIMI_PROBE_INSIDE", "AIWORK_KIMI_PROBE_OUTSIDE"
        (repo / "inside.txt").write_text(inside_marker)
        (outside / "outside.txt").write_text(outside_marker)
        for directory in (repo, outside):
            (directory / "image.png").write_bytes(_png())
        (repo / "escape").symlink_to(outside, target_is_directory=True)
        tag = secrets.token_hex(16)
        calls = []
        for name in KIMI_TOOL_INPUTS:
            for scope in ("inside", "outside"):
                directory = repo if scope == "inside" else outside
                arguments = {"path": str(directory)}
                if name == "Read":
                    arguments["path"] = str(directory / ("inside.txt" if scope == "inside" else "outside.txt"))
                elif name == "ReadMediaFile":
                    arguments["path"] = str(directory / "image.png")
                elif name == "Glob":
                    arguments["pattern"] = "**/*.txt"
                else:
                    arguments.update(pattern="AIWORK_KIMI_PROBE", output_mode="content")
                calls.append({"index": len(calls), "id": name + "-" + scope, "type": "function",
                              "function": {"name": name, "arguments": json.dumps(arguments)}})
        outcome = {"schema": False, "tools": False, "error": None}

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                try:
                    size = int(self.headers.get("Content-Length", "0"))
                    if not 0 < size <= 2 * 1024 * 1024:
                        raise ValueError("invalid local probe request size")
                    body = json.loads(self.rfile.read(size))
                    _schema(body["tools"])
                    outcome["schema"] = True
                    results = {message["tool_call_id"]: json.dumps(message.get("content"))
                               for message in body["messages"] if message.get("role") == "tool"}
                    if results:
                        if set(results) != {call["id"] for call in calls}:
                            raise ValueError("native reader probe results are incomplete")
                        for name in KIMI_TOOL_INPUTS:
                            if tag not in results[name + "-outside"] or tag in results[name + "-inside"]:
                                raise ValueError("native hook did not prove both boundaries: " + name)
                        if (inside_marker not in results["Read-inside"]
                                or inside_marker not in results["Grep-inside"]
                                or outside_marker in results["Grep-inside"]
                                or "inside.txt" not in results["Glob-inside"]
                                or "outside.txt" in results["Glob-inside"]
                                or "data:image/" not in json.dumps(body["messages"])):
                            raise ValueError("native reader positive or traversal control failed")
                        outcome["tools"] = True
                    delta = ({"role": "assistant", "content": "AIWORK_KIMI_PREFLIGHT_COMPLETE"} if results
                             else {"role": "assistant", "tool_calls": calls})
                except (ValueError, KeyError, TypeError) as exc:
                    outcome["error"] = str(exc)
                    delta = {"role": "assistant", "content": "AIWORK_KIMI_PREFLIGHT_INCOMPATIBLE"}
                payload = {"id": "aiwork-local-probe", "object": "chat.completion.chunk", "created": 1,
                           "model": PROBE_MODEL, "choices": [{"index": 0, "delta": delta, "finish_reason": None}]}
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                self.wfile.write(("data: " + json.dumps(payload) + "\n\n").encode())
                payload["choices"] = [{"index": 0, "delta": {},
                                       "finish_reason": "tool_calls" if "tool_calls" in delta else "stop"}]
                self.wfile.write(("data: " + json.dumps(payload) + "\n\ndata: [DONE]\n\n").encode())

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            hook = hooks[0]
            state.joinpath("config.toml").write_text(
                'default_model=' + json.dumps(PROBE_MODEL) + '\n[providers.probe]\ntype="kimi"\n'
                + 'api_key="local-probe-placeholder"\nbase_url='
                + json.dumps(f"http://127.0.0.1:{server.server_port}/v1")
                + '\n[models.' + json.dumps(PROBE_MODEL) + ']\nprovider="probe"\nmodel=' + json.dumps(PROBE_MODEL) + '\n'
                + 'max_context_size=65536\ncapabilities=["tool_use","image_in","video_in"]\n'
                + '[[hooks]]\nevent=' + json.dumps(hook["event"]) + '\nmatcher=' + json.dumps(hook["matcher"])
                + '\ncommand=' + json.dumps(hook["command"]) + '\ntimeout=' + str(hook["timeout"]) + '\n')
            env = {key: os.environ[key] for key in ("PATH", "TMPDIR", "LANG", "LC_ALL") if key in os.environ}
            env.update(HOME=str(state), KIMI_CODE_HOME=str(state), KIMI_CODE_NO_AUTO_UPDATE="1",
                       XDG_CONFIG_HOME=str(state / "config"), XDG_DATA_HOME=str(state / "data"),
                       XDG_CACHE_HOME=str(state / "cache"), NO_PROXY="*", no_proxy="*", RIPGREP_CONFIG_PATH="",
                       AIWORK_KIMI_GUARD_PROBE_TAG=tag,
                       AIWORK_KIMI_READER_GUARD=json.dumps([sys.executable,
                           str(Path(__file__).with_name("_reader_tools.py")), "kimi-hook", str(repo)]))
            with subprocess.Popen([str(cli), "--agent-file", str(profile), "--output-format", "stream-json",
                                   "-m", PROBE_MODEL, "-p", "Run the local reader compatibility probe."],
                                  cwd=repo, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  start_new_session=True) as process:
                try:
                    process.communicate(timeout=timeout)
                except subprocess.TimeoutExpired as exc:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()
                    raise ValueError("native Kimi preflight timed out") from exc
            if process.returncode or not outcome["schema"] or not outcome["tools"] or outcome["error"]:
                raise ValueError("native Kimi preflight refused: " + (outcome["error"] or "incomplete native evidence"))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    try:
        preflight(*sys.argv[1:4])
    except (ValueError, OSError, KeyError) as exc:
        print("subkimi: " + str(exc), file=sys.stderr)
        raise SystemExit(78)

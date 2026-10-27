"""Offline native-CLI request fixture; protocol schemas are captured from Kimi."""
import base64
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: F401,E402
import time
import tomllib
import urllib.request
import urllib.parse

def native_fixture():
    """The fake CLI speaks the captured request protocol and runs the real hook."""
    schemas, mode, capture = sys.argv[2:5]
    Path(capture).write_text(json.dumps({"keys": sorted(os.environ),
                                       "home": os.environ["HOME"],
                                       "ripgrep_config": os.environ.get("RIPGREP_CONFIG_PATH")}))
    if mode == "crash":
        return 1
    if mode == "hung":
        time.sleep(30)
    config = tomllib.loads((Path(os.environ["KIMI_CODE_HOME"]) / "config.toml").read_text())
    provider = next(iter(config["providers"].values()))
    url = provider["base_url"].rstrip("/") + "/chat/completions"
    if urllib.parse.urlsplit(url).hostname != "127.0.0.1":
        raise ValueError("offline Kimi fixture requires its local provider")
    tools = json.loads(Path(schemas).read_text())
    if mode == "renamed-path":
        tool = next(tool["function"] for tool in tools if tool["function"]["name"] == "Read")
        tool["parameters"]["properties"]["file_path"] = tool["parameters"]["properties"].pop("path")
        tool["parameters"]["required"] = ["file_path"]

    def request(messages):
        body = json.dumps({"messages": messages, "tools": tools}).encode()
        response = urllib.request.urlopen(urllib.request.Request(url, data=body,
                                            headers={"Content-Type": "application/json"}))
        return [json.loads(line[6:]) for line in response.read().decode().split("\n")
                if line.startswith("data: ") and line != "data: [DONE]"]

    chunks = request([])
    calls = [call for chunk in chunks for choice in chunk.get("choices", [])
             for call in choice.get("delta", {}).get("tool_calls", [])]
    messages = []
    for call in calls:
        function = call["function"]
        name, arguments = function["name"], json.loads(function["arguments"])
        event = {"tool_name": "Bash" if mode == "all-deny" else name,
                 "tool_input": arguments, "cwd": os.getcwd()}
        hook = subprocess.run(shlex.split(config["hooks"][0]["command"]),
                              input=json.dumps(event), text=True, capture_output=True)
        if hook.returncode and mode != "ignore-hook":
            content = hook.stderr or hook.stdout
        else:
            path = Path(arguments.get("path", "."))
            if name == "Read":
                content = path.read_text()
            elif name == "ReadMediaFile":
                content = "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()
            elif name == "Glob":
                content = "\n".join(str(p) for p in path.rglob("*.txt"))
            else:
                content = "\n".join(p.read_text() for p in path.rglob("*.txt"))
        messages.append({"role": "tool", "tool_call_id": call["id"], "content": content})
    request(messages)
    return 0


if __name__ == "__main__":
    raise SystemExit(native_fixture())

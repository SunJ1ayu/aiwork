#!/usr/bin/env python3
"""Oracle for the 429/5xx backoff in submimo-review.call_model.

Owned by the main agent (NOT submimo). Spins a local stub HTTP server that
returns a scripted sequence of statuses and asserts call_model's retry policy:
  1. 429 then 200            -> retries, succeeds, returns the 200 body content
  2. 429 honoring Retry-After-> sleeps ~Retry-After (capped), then succeeds
  3. persistent 429          -> bounded: exactly RETRY_ATTEMPTS calls, then fail()
  4. non-429 4xx (400)       -> NO retry, fails fast on attempt 1
  5. 5xx then 200            -> retries (5xx is transient), succeeds

Run: python3 /root/aiwork/tests/test_submimo_retry.py
Exit 0 = all pass (oracle GREEN). Non-zero = a property is violated.
"""
import http.server
import importlib.util
from importlib.machinery import SourceFileLoader
import os
import sys
import threading
import time
from pathlib import Path

# Importing the engine from bin/ would otherwise litter bin/__pycache__.
sys.dont_write_bytecode = True

ENGINE = Path("/root/aiwork/bin/submimo-review")

# Make retries instant + deterministic for the test.
os.environ["MIMO_API_KEY"] = "test-key"
os.environ["MIMO_MODEL"] = "stub"
os.environ["MIMO_RETRY_ATTEMPTS"] = "3"
os.environ["MIMO_RETRY_BASE_SECONDS"] = "0"
os.environ["MIMO_RETRY_CAP_SECONDS"] = "5"


def load_engine():
    loader = SourceFileLoader("submimo_review", str(ENGINE))
    spec = importlib.util.spec_from_loader("submimo_review", loader)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---- scriptable stub server -------------------------------------------------
class StubState:
    def __init__(self):
        self.script = []        # list of (status, headers_dict, body)
        self.calls = 0
        self.call_times = []


STATE = StubState()
OK_BODY = '{"choices":[{"message":{"content":"OK-RESULT"}}]}'


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        i = STATE.calls
        STATE.calls += 1
        STATE.call_times.append(time.monotonic())
        status, hdrs, body = STATE.script[min(i, len(STATE.script) - 1)]
        data = body.encode()
        self.send_response(status)
        for k, v in (hdrs or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def start_server():
    srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    port = srv.server_address[1]
    os.environ["MIMO_CHAT_COMPLETIONS_URL"] = f"http://127.0.0.1:{port}/v1/chat/completions"
    return srv


def reset(script):
    STATE.script = script
    STATE.calls = 0
    STATE.call_times = []


def expect(cond, msg):
    if not cond:
        raise AssertionError(msg)


def main():
    eng = load_engine()
    srv = start_server()
    try:
        # 1. 429 then 200 -> retries to success
        reset([(429, {}, '{"error":"tpm"}'), (200, {}, OK_BODY)])
        out = eng.call_model("hi", timeout=10)
        expect("OK-RESULT" in out, f"[1] expected success body, got {out!r}")
        expect(STATE.calls == 2, f"[1] expected 2 calls, got {STATE.calls}")

        # 2. honor Retry-After (capped). base=0 so any delay comes from Retry-After.
        reset([(429, {"Retry-After": "1"}, "{}"), (200, {}, OK_BODY)])
        t0 = time.monotonic()
        out = eng.call_model("hi", timeout=10)
        waited = time.monotonic() - t0
        expect("OK-RESULT" in out, "[2] expected success after Retry-After")
        expect(waited >= 0.9, f"[2] expected to honor Retry-After~1s, waited {waited:.2f}s")

        # 3. persistent 429 -> bounded to RETRY_ATTEMPTS, then fail()
        reset([(429, {}, '{"error":"tpm"}')])
        raised = False
        try:
            eng.call_model("hi", timeout=10)
        except SystemExit:
            raised = True
        expect(raised, "[3] persistent 429 should exit non-zero via fail()")
        expect(STATE.calls == 3, f"[3] expected exactly 3 attempts, got {STATE.calls}")

        # 4. non-429 4xx -> fail fast, NO retry
        reset([(400, {}, '{"error":"bad request"}')])
        raised = False
        try:
            eng.call_model("hi", timeout=10)
        except SystemExit:
            raised = True
        expect(raised, "[4] 400 should fail")
        expect(STATE.calls == 1, f"[4] 400 must NOT retry, got {STATE.calls} calls")

        # 5. 5xx then 200 -> retries (transient server error)
        reset([(503, {}, "upstream"), (200, {}, OK_BODY)])
        out = eng.call_model("hi", timeout=10)
        expect("OK-RESULT" in out, "[5] expected success after 503")
        expect(STATE.calls == 2, f"[5] expected 2 calls, got {STATE.calls}")

        print("ALL RETRY ORACLE CHECKS PASSED")
    finally:
        srv.shutdown()


if __name__ == "__main__":
    main()

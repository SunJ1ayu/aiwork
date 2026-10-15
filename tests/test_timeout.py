#!/usr/bin/env python3
"""The shared deadline command owns a process group and reports why it stopped."""

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import signal
import select
import subprocess
import tempfile
import time
import unittest
from contextlib import contextmanager
from pathlib import Path


TOOL = Path(__file__).resolve().parents[1] / "bin" / "aiwork-timeout"

# Three generations in one group. The grandchild refuses graceful shutdown;
# the leader handles INT/TERM by returning 0 to test the supervisor's status.
TREE = r'''
import os, signal, subprocess, sys, time
from pathlib import Path
root, role, mode = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
if role == "grandchild":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
else:
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
(root / role).write_text("%s %s" % (os.getpid(), os.getpgrp()))
if role != "grandchild":
    subprocess.Popen([sys.executable, "-c", (root / "tree.py").read_text(),
                      str(root), "child" if role == "leader" else "grandchild", mode])
if role == "leader" and mode == "exit":
    while not (root / "grandchild").exists():
        time.sleep(0.01)
    sys.exit(17)
while True:
    time.sleep(60)
'''


class Timeout(unittest.TestCase):
    def run_command(self, code):
        return subprocess.run(
            [sys.executable, str(TOOL), "5", sys.executable, "-c", code],
            capture_output=True, text=True, timeout=10)

    def test_exit_codes_and_signals_are_preserved_before_deadline(self):
        for code in (0, 23, 124, 137):
            with self.subTest(code=code):
                result = self.run_command("raise SystemExit(%d)" % code)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual(result.stderr, "")
        result = self.run_command("import os, signal; os.kill(os.getpid(), signal.SIGKILL)")
        self.assertEqual(result.returncode, 128 + signal.SIGKILL, result.stderr)
        self.assertEqual(result.stderr, "")

    @contextmanager
    def tree(self, limit="2", mode="wait", grace="0.2"):
        with tempfile.TemporaryDirectory(prefix="aiwork-timeout-test-") as folder:
            root = Path(folder)
            (root / "tree.py").write_text(TREE)
            command = [sys.executable, str(TOOL)]
            if grace is not None:
                command += ["-k", grace]
            process = subprocess.Popen(
                command + [limit, sys.executable, "-c", TREE, folder, "leader", mode],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                start_new_session=True)
            members = []
            try:
                until = time.monotonic() + 5
                while True:
                    paths = [root / name for name in ("leader", "child", "grandchild")]
                    if all(p.exists() and len(p.read_text().split()) == 2 for p in paths):
                        members = [tuple(map(int, p.read_text().split())) for p in paths]
                        break
                    if process.poll() is not None or time.monotonic() >= until:
                        self.fail("tree did not start: %r" % process.communicate(timeout=2))
                    time.sleep(0.01)
                self.assertEqual({group for _, group in members}, {members[0][0]})
                self.assertNotEqual(members[0][1], os.getpgrp())
                yield process, members
            finally:
                # Independent cleanup also runs when an assertion detects a leak.
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=5)
                for path in (root / "leader", root / "child", root / "grandchild"):
                    if path.exists() and path.read_text().strip():
                        _, group = map(int, path.read_text().split())
                        try:
                            os.killpg(group, signal.SIGKILL)
                        except ProcessLookupError:
                            pass

    def assert_stopped(self, members):
        # Orphans can briefly be zombies pending reaping by the system's init;
        # they cannot execute or hold open the command's pipes.
        until = time.monotonic() + 3
        while True:
            running = []
            for pid, _ in members:
                result = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)],
                                        capture_output=True, text=True, timeout=5)
                if result.stdout.strip() and not result.stdout.lstrip().startswith("Z"):
                    running.append(pid)
            if not running or time.monotonic() >= until:
                self.assertEqual(running, [], "surviving processes")
                return
            time.sleep(0.02)

    def test_deadline_kills_tree_including_term_ignoring_grandchild(self):
        with self.tree() as (process, members):
            _stdout, stderr = process.communicate(timeout=6)
            self.assertEqual(process.returncode, 124, stderr)
            self.assertEqual(stderr.splitlines(), [
                "aiwork-timeout: timed out after 2s; terminating process group"])
            self.assert_stopped(members)

    def test_deadline_returns_124_even_when_term_handler_exits_zero(self):
        code = ("import signal, sys, time; "
                "signal.signal(signal.SIGTERM, lambda *_: sys.exit(0)); time.sleep(60)")
        result = subprocess.run(
            [str(TOOL), "-k", "0.2", "1", sys.executable, "-c", code],
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertEqual(result.stderr.splitlines(), [
            "aiwork-timeout: timed out after 1s; terminating process group"])

    def test_external_int_and_term_clean_tree_and_override_child_success(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum), self.tree(limit="30") as (process, members):
                process.send_signal(signum)
                _stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 128 + signum, stderr)
                self.assertNotIn("timed out", stderr)
                self.assert_stopped(members)

    def test_successful_leader_does_not_leave_workers(self):
        with self.tree(limit="30", mode="exit") as (process, members):
            _stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 17, stderr)
            self.assertNotIn("timed out", stderr)
            self.assert_stopped(members)

    def test_unspecified_grace_is_ten_seconds(self):
        with self.tree(grace=None) as (process, members):
            ready, _, _ = select.select([process.stderr], [], [], 5)
            self.assertTrue(ready, "missing deadline diagnostic")
            diagnostic = process.stderr.readline()
            started = time.monotonic()
            _stdout, stderr = process.communicate(timeout=13)
            elapsed = time.monotonic() - started
            self.assertEqual(process.returncode, 124, stderr)
            self.assertIn("timed out after 2s", diagnostic)
            self.assertGreaterEqual(elapsed, 9.8)
            self.assertLess(elapsed, 12)
            self.assert_stopped(members)

    def test_stdin_stdout_and_stderr_are_inherited(self):
        result = subprocess.run(
            [str(TOOL), "5", sys.executable, "-c",
             "import sys; print(sys.stdin.read(), end=''); print('diagnostic', file=sys.stderr)"],
            input="task input\n", capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "task input\n")
        self.assertEqual(result.stderr, "diagnostic\n")


if __name__ == "__main__":
    unittest.main()

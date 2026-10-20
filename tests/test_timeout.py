#!/usr/bin/env python3
"""The shared deadline command owns a process group and reports why it stopped."""

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import resource
import signal
import select
import shutil
import subprocess
import tempfile
import time
import unittest
from contextlib import contextmanager
from pathlib import Path


TOOL = Path(__file__).resolve().parents[1] / "bin" / "aiwork-timeout"

# Three generations in one group. The grandchild refuses graceful shutdown;
# the leader handles INT/TERM by returning 0 to test the supervisor's status,
# unless mode "stubborn" makes the leader refuse it as well.
TREE = r'''
import os, signal, subprocess, sys, time
from pathlib import Path
root, role, mode = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
if role == "grandchild" or (role == "leader" and mode == "stubborn"):
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

# Holds descriptors 3..1029 open, then becomes the caller of aiwork-timeout.
# select() cannot watch descriptor numbers at or above FD_SETSIZE (1024).
HOLD_FDS = r'''
import os, resource, sys
_, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
resource.setrlimit(resource.RLIMIT_NOFILE, (int(sys.argv[1]), hard))
while True:
    fd = os.open(os.devnull, os.O_RDONLY)
    os.set_inheritable(fd, True)
    if fd >= 1029:
        break
os.execv(sys.argv[2], sys.argv[2:])
'''

# Only the supervisor's kernel boundary is replaced. The command tree and
# independent watchdog still run normally, including their real signals.
DENIED_GROUP_CALL = r'''
import errno, os, runpy, sys, time
from pathlib import Path
tool, audit, denied = sys.argv[1:4]
sys.argv = [tool] + sys.argv[4:]
real_killpg = os.killpg
def killpg(pgid, signum):
    with Path(audit).open("a") as output:
        output.write("%d %.9f\n" % (signum, time.monotonic()))
    if signum == int(denied):
        raise PermissionError(errno.EPERM, "Operation not permitted")
    return real_killpg(pgid, signum)
os.killpg = killpg
runpy.run_path(tool, run_name="__main__")
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
    def tree(self, limit="2", mode="wait", grace="0.2", nested=False, denied_signal=None):
        with tempfile.TemporaryDirectory(prefix="aiwork-timeout-test-") as folder:
            root = Path(folder)
            (root / "tree.py").write_text(TREE)
            command = [sys.executable, str(TOOL)]
            if denied_signal is not None:
                command = [sys.executable, "-c", DENIED_GROUP_CALL, str(TOOL),
                           str(root / "signals"), str(denied_signal)]
            if grace is not None:
                command += ["-k", grace]
            job = [sys.executable, "-c", TREE, folder, "leader", mode]
            if nested:
                job = [sys.executable, str(TOOL), "-k", "30", "0"] + job
            process = subprocess.Popen(
                command + [limit] + job,
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
                for path in (root / "leader", root / "child", root / "grandchild"):
                    if path.exists() and path.read_text().strip():
                        _, group = map(int, path.read_text().split())
                        try:
                            os.killpg(group, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                process.communicate(timeout=5)

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

    def test_denied_group_probe_preserves_status_and_bounded_cleanup(self):
        # A living stubborn leader makes skipping KILL observable even if the
        # watchdog could eventually rescue a supervisor that crashes.
        for case, limit, mode, signum, expected in (
                ("deadline", "2", "stubborn", None, 124),
                ("leader_exit", "30", "exit", None, 17),
                ("interrupt", "30", "stubborn", signal.SIGINT, 130),
                ("terminate", "30", "stubborn", signal.SIGTERM, 143)):
            with self.subTest(case=case), self.tree(
                    limit=limit, mode=mode, grace="0.3", denied_signal=0) as (process, members):
                if signum is not None:
                    process.send_signal(signum)
                _stdout, stderr = process.communicate(timeout=6)
                self.assertEqual(process.returncode, expected, stderr)
                self.assertNotIn("PermissionError", stderr)
                self.assertEqual("timed out" in stderr, case == "deadline", stderr)
                # Every generation inherits these pipes and never closes them:
                # communicate() reaching EOF proves no worker is still running.
                self.assertEqual(_stdout, "")
                events = [line.split() for line in Path(process.args[4]).read_text().splitlines()]
                signals = [int(event[0]) for event in events]
                self.assertEqual(signals[0], signum or signal.SIGTERM)
                self.assertIn(0, signals, "the denied probe must actually be reached")
                self.assertEqual(signals[-1], signal.SIGKILL, "supervisor must attempt KILL")
                elapsed = float(events[-1][1]) - float(events[0][1])
                self.assertGreaterEqual(elapsed, 0.29, "must retain the TERM grace period")
                self.assertLess(elapsed, 1.5, "unknown status must not extend the grace period")

    def test_denied_term_does_not_skip_kill_or_change_deadline_status(self):
        with self.tree(limit="2", mode="stubborn", grace="0.3",
                       denied_signal=signal.SIGTERM) as (process, members):
            _stdout, stderr = process.communicate(timeout=6)
            self.assertEqual(process.returncode, 124, stderr)
            self.assertNotIn("Traceback", stderr)
            self.assertEqual(_stdout, "")  # Inherited pipe EOF also covers workers.
            events = [line.split() for line in Path(process.args[4]).read_text().splitlines()]
            self.assertEqual(int(events[0][0]), signal.SIGTERM)
            self.assertEqual(int(events[-1][0]), signal.SIGKILL)
            elapsed = float(events[-1][1]) - float(events[0][1])
            self.assertGreaterEqual(elapsed, 0.29)
            self.assertLess(elapsed, 1.5)

    def test_watchdog_denied_kill_of_departed_group_does_not_crash(self):
        with tempfile.TemporaryDirectory() as folder:
            # The group has no running members. A denied signal must not turn
            # normal watchdog cleanup into a false tool failure (125).
            victim = subprocess.Popen(["sleep", "0"], start_new_session=True)
            victim.wait(timeout=5)
            alive_r, alive_w = os.pipe()
            identity_r, identity_w = os.pipe()
            ready_r, ready_w = os.pipe()
            os.write(identity_w, b"%d\n" % victim.pid)
            os.close(identity_w)
            os.close(alive_w)
            guard = subprocess.Popen(
                [sys.executable, "-c", DENIED_GROUP_CALL, str(TOOL),
                 str(Path(folder) / "signals"), str(signal.SIGKILL),
                 "--_watchdog", str(alive_r), str(identity_r), str(ready_w)],
                pass_fds=(alive_r, identity_r, ready_w),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            for fd in (alive_r, identity_r, ready_w):
                os.close(fd)
            try:
                self.assertEqual(os.read(ready_r, 1), b"")
                _stdout, stderr = guard.communicate(timeout=5)
                self.assertEqual(guard.returncode, 0, stderr)
                self.assertEqual(stderr, "")
                events = (Path(folder) / "signals").read_text().splitlines()
                self.assertEqual(len(events), 1)
                self.assertEqual(int(events[0].split()[0]), signal.SIGKILL)
            finally:
                os.close(ready_r)
                if guard.poll() is None:
                    guard.kill()
                    guard.communicate(timeout=5)

    def test_deadline_returns_124_even_when_term_handler_exits_zero(self):
        code = ("import signal, sys, time; "
                "signal.signal(signal.SIGTERM, lambda *_: sys.exit(0)); time.sleep(60)")
        result = subprocess.run(
            [str(TOOL), "-k", "0.2", "1", sys.executable, "-c", code],
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertEqual(result.stderr.splitlines(), [
            "aiwork-timeout: timed out after 1s; terminating process group"])

    def test_outer_deadline_bounds_nested_long_grace_and_closes_output(self):
        limit, grace = 2, 0.3
        started = time.monotonic()
        with self.tree(limit=str(limit), grace=str(grace), nested=True) as (process, members):
            process.wait(timeout=limit + grace + 2)
            _stdout, stderr = process.communicate(timeout=1)
            self.assertEqual(process.returncode, 124, stderr)
            # One second covers interpreter startup; the inner grace is 30s.
            self.assertLess(time.monotonic() - started, limit + grace + 1, stderr)
            self.assert_stopped(members)

    def test_killed_supervisor_does_not_leave_its_group_or_output_open(self):
        with self.tree(limit="30", grace="30") as (process, members):
            started = time.monotonic()
            process.kill()
            process.wait(timeout=2)
            self.assertEqual(process.returncode, -signal.SIGKILL)
            process.communicate(timeout=1)
            self.assertLess(time.monotonic() - started, 2)
            self.assert_stopped(members)

    def test_leader_ignoring_term_is_killed_after_grace_and_returns_124(self):
        grace = 0.5
        with self.tree(limit="1", grace=str(grace), mode="stubborn") as (process, members):
            ready, _, _ = select.select([process.stderr], [], [], 5)
            self.assertTrue(ready, "missing deadline diagnostic")
            diagnostic = process.stderr.readline()
            started = time.monotonic()
            _stdout, stderr = process.communicate(timeout=5)
            elapsed = time.monotonic() - started
            self.assertEqual(process.returncode, 124, diagnostic + stderr)
            self.assertIn("timed out after 1s", diagnostic)
            self.assertGreaterEqual(elapsed, grace - 0.05)
            self.assert_stopped(members)

    def test_command_runs_when_caller_holds_descriptors_past_1024(self):
        _, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        want = 4096 if hard == resource.RLIM_INFINITY else min(4096, hard)
        if want < 1100:
            self.skipTest("hard descriptor limit %d keeps every descriptor below 1024, "
                          "so the select() limit cannot be reached" % hard)
        result = subprocess.run(
            [sys.executable, "-c", HOLD_FDS, str(want),
             str(TOOL), "5", sys.executable, "-c", "print('ran')"],
            capture_output=True, text=True, timeout=10)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "ran\n", ""))

    def test_watchdog_accepts_only_while_supervisor_lives(self):
        # Drives the private watchdog mode: a supervisor dying between spawn
        # and registration cannot be timed from outside.
        for supervisor_alive in (True, False):
            with self.subTest(supervisor_alive=supervisor_alive):
                victim = subprocess.Popen(["sleep", "30"], start_new_session=True)
                alive_r, alive_w = os.pipe()
                identity_r, identity_w = os.pipe()
                ready_r, ready_w = os.pipe()
                os.write(identity_w, b"%d\n" % victim.pid)
                os.close(identity_w)
                if not supervisor_alive:
                    os.close(alive_w)
                guard = subprocess.Popen(
                    [sys.executable, str(TOOL), "--_watchdog",
                     str(alive_r), str(identity_r), str(ready_w)],
                    pass_fds=(alive_r, identity_r, ready_w))
                for fd in (alive_r, identity_r, ready_w):
                    os.close(fd)
                accepted = os.read(ready_r, 1)
                os.close(ready_r)
                if supervisor_alive:
                    os.close(alive_w)
                self.assertEqual(guard.wait(timeout=5), 0)
                self.assertEqual(accepted, b"1" if supervisor_alive else b"")
                self.assertEqual(victim.wait(timeout=5), -signal.SIGKILL)

    def watchdog_of(self, supervisor):
        listing = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,args="],
                                 capture_output=True, text=True, timeout=5).stdout
        pids = [int(fields[0]) for fields in (line.split(None, 2) for line in listing.splitlines())
                if len(fields) == 3 and int(fields[1]) == supervisor.pid
                and "--_watchdog" in fields[2]]
        self.assertEqual(len(pids), 1, listing)
        return pids[0]

    def test_watchdog_failure_returns_125_and_says_so(self):
        # INT makes the watchdog kill the group, then exit abnormally, as an
        # unexpected watchdog error does; KILL removes it without any cleanup.
        for signum in (signal.SIGINT, signal.SIGKILL):
            with self.subTest(signal=signum), self.tree(limit="30") as (process, members):
                os.kill(self.watchdog_of(process), signum)
                _stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 125, stderr)
                self.assertEqual(len(stderr.splitlines()), 1, stderr)
                self.assertIn("watchdog", stderr)
                self.assert_stopped(members)

    def test_zero_limit_disables_deadline(self):
        started = time.monotonic()
        result = subprocess.run(
            [str(TOOL), "0", sys.executable, "-c", "import time; time.sleep(0.2); exit(23)"],
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertGreaterEqual(time.monotonic() - started, 0.2)

    def test_invalid_arguments_return_two(self):
        for args in ([], ["1"], ["invalid"], ["-1"], ["nan"], ["inf"],
                     ["-k", "-1", "1"], ["-k", "nan", "1"], ["--unknown"]):
            with self.subTest(args=args):
                result = subprocess.run([str(TOOL)] + args, capture_output=True,
                                        text=True, timeout=5)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("usage:", result.stderr)

    def test_missing_and_nonexecutable_commands_return_127_and_126(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "command"
            for exists, expected in ((False, 127), (True, 126)):
                if exists:
                    path.write_text("#!/bin/sh\nexit 0\n")
                    path.chmod(0o600)
                result = subprocess.run([str(TOOL), "1", str(path)],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertIn("aiwork-timeout:", result.stderr)

    def test_total_runner_refuses_missing_timeout(self):
        with tempfile.TemporaryDirectory() as folder:
            bindir = Path(folder) / "bin"
            bindir.mkdir()
            runner = bindir / "rust-check-review-tooling"
            shutil.copy2(TOOL.parent / runner.name, runner)
            result = subprocess.run(["bash", str(runner)], capture_output=True,
                                    text=True, timeout=5)
            self.assertEqual(result.returncode, 78, result.stderr)
            self.assertEqual(result.stderr, "rust-check-review-tooling: 少了 %s ⇒ 拒绝派发\n"
                             % (Path(os.path.realpath(folder)) / "bin" / "aiwork-timeout"))

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

    def test_command_starts_with_default_sigpipe(self):
        # A producer behind a closed pipe must die quietly, as under exec.
        result = subprocess.run(
            [str(TOOL), "5", "bash", "-c",
             'yes | head -n 1 >/dev/null; exit "${PIPESTATUS[0]}"'],
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 128 + signal.SIGPIPE, result.stderr)
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()

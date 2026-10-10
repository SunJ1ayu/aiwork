#!/usr/bin/env python3
"""explore fans one brief out to selected legs and keeps each last message locally."""

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import importlib.machinery
import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch
import io

from _test_settings import write_settings


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "mimo-run-json.jsonl"
# Last message assembled from tests/fixtures/mimo-run-json.jsonl (see V46).
FIXTURE_LAST = "Shared fixture checked.\n\nConclusion: PASS"
NO_CONCLUSION = (
    "方向：每条腿只读 main 的一份快照。\n"
    "核心取舍：方案要求只写在 explore 发出的任务里。\n"
    "盲点：未提交的改动不在这份快照里。\n"
    "最小验证：没有结论行的回答仍然留下。\n"
)
REQUIREMENT = "提出一个方向，写清核心取舍、看到的盲点、最小的验证实验；不要写 PASS / BLOCK"


def load_script(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(ROOT / "bin" / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


STUB = textwrap.dedent(r'''
    #!/usr/bin/env python3
    import os, pathlib, subprocess, sys, time
    leg = pathlib.Path(sys.argv[0]).name
    task, repo = sys.argv[2], sys.argv[4]
    obs = pathlib.Path(os.environ["EXPLORE_OBS"])
    obs.mkdir(parents=True, exist_ok=True)
    (obs / (leg + ".task")).write_text(pathlib.Path(task).read_text(encoding="utf-8"), encoding="utf-8")
    head = subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], text=True).strip()
    names = sorted(p.name for p in pathlib.Path(repo).iterdir() if p.name != ".git")
    (obs / (leg + ".view")).write_text(head + "\n" + "\n".join(names) + "\n", encoding="utf-8")
    (obs / (leg + ".repo")).write_text(repo + "\n", encoding="utf-8")
    barrier = pathlib.Path(os.environ["EXPLORE_BARRIER"])
    barrier.mkdir(parents=True, exist_ok=True)
    (barrier / (leg + ".started")).write_text("1", encoding="utf-8")
    peers = [p for p in os.environ["EXPLORE_PEERS"].split() if p]
    deadline = time.time() + 5
    while time.time() < deadline:
        if all((barrier / (peer + ".started")).exists() for peer in peers):
            break
        time.sleep(0.05)
    else:
        sys.stderr.write("peer did not start\n")
        raise SystemExit(1)
    kind = os.environ.get("EXPLORE_STUB_" + leg, "fixture")
    if kind == "fail":
        sys.stderr.write("quota exceeded\n")
        raise SystemExit(1)
    report = os.environ["AIWORK_REVIEW_REPORT_PATH"]
    if kind == "plain":
        pathlib.Path(report).write_text(os.environ["EXPLORE_PLAIN"], encoding="utf-8")
    else:
        pathlib.Path(report).write_text(os.environ["EXPLORE_FIXTURE_LAST"], encoding="utf-8")
    raise SystemExit(0)
''').lstrip()


class ExploreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        shutil.copy2(ROOT / "bin" / "_review_result.py", self.bin / "_review_result.py")
        stub = self.bin / "leg-stub"
        stub.write_text(STUB, encoding="utf-8")
        stub.chmod(0o755)
        self.explore = load_script("explore")
        self.data = self.root / "data"
        self.obs = self.root / "obs"
        self.barrier = self.root / "barrier"
        self.repo = self.root / "source"
        self._git_repo()
        self.brief = self.root / "brief.md"
        self.brief.write_text(
            "目标：给没定方向的改动收几份独立方案。\n"
            "已有事实：main 上只有 on-main.txt。\n"
            "约束：方案不发到 GitHub。\n"
            "待核实：脏工作区不会进快照。\n",
            encoding="utf-8",
        )
        self.env = dict(os.environ)
        self.env.update(
            AIWORK_DATA_DIR=str(self.data),
            EXPLORE_OBS=str(self.obs),
            EXPLORE_BARRIER=str(self.barrier),
            EXPLORE_FIXTURE_LAST=FIXTURE_LAST,
            EXPLORE_PLAIN=NO_CONCLUSION,
        )
        raw = FIXTURE.read_text(encoding="utf-8")
        self.assertIn("Shared fixture checked.", raw)
        self.assertIn("Conclusion: PASS", raw)

    def _git(self, *args):
        subprocess.check_call(["git", "-C", str(self.repo), *args], stdout=subprocess.DEVNULL)

    def _git_repo(self):
        self.repo.mkdir()
        subprocess.check_call(["git", "init", "-q", "-b", "main", str(self.repo)])
        self._git("config", "user.email", "t@example.com")
        self._git("config", "user.name", "t")
        (self.repo / "on-main.txt").write_text("on main\n", encoding="utf-8")
        self._git("add", "-A")
        self._git("commit", "-qm", "main")
        self.main_sha = subprocess.check_output(
            ["git", "-C", str(self.repo), "rev-parse", "refs/heads/main"], text=True).strip()
        self._git("checkout", "-q", "-b", "side")
        (self.repo / "side.txt").write_text("side\n", encoding="utf-8")
        self._git("add", "-A")
        self._git("commit", "-qm", "side")
        self._git("checkout", "-q", "main")
        (self.repo / "dirty.txt").write_text("dirty\n", encoding="utf-8")

    def _link(self, *names):
        for name in names:
            os.symlink(self.bin / "leg-stub", self.bin / name)

    def _run(self, legs):
        return self._run_at(legs, str(self.repo), None)

    def _run_at(self, legs, repo_arg, cwd):
        stdout, stderr = io.StringIO(), io.StringIO()
        argv = ["explore", str(self.brief), "--repo", repo_arg]
        for leg in legs:
            argv += ["--leg", leg]
        previous = os.getcwd()
        if cwd is not None:
            os.chdir(cwd)
        try:
            with redirect_stdout(stdout), redirect_stderr(stderr), \
                    unittest.mock_argv(argv), \
                    patch_env(self.env), \
                    patch_bin(self.explore, self.bin):
                rc = self.explore.main()
        finally:
            if cwd is not None:
                os.chdir(previous)
        return rc, stdout.getvalue(), stderr.getvalue()

    def _saved(self):
        root = self.data / "explore"
        self.assertTrue(root.is_dir(), "explore did not create a result directory")
        dirs = [p for p in root.iterdir() if p.is_dir()]
        self.assertEqual(len(dirs), 1, dirs)
        self.assertTrue(dirs[0].name.startswith("brief-"), dirs[0].name)
        return dirs[0]

    def _view(self, leg):
        text = (self.obs / f"{leg}.view").read_text(encoding="utf-8")
        head, *names = text.splitlines()
        return head, names

    def test_parallel_legs_store_fixture_and_plain_answers_from_main(self):
        self._link("subcodex", "submimo")
        self.env["EXPLORE_PEERS"] = "subcodex submimo"
        self.env["EXPLORE_STUB_subcodex"] = "fixture"
        self.env["EXPLORE_STUB_submimo"] = "plain"
        rc, stdout, stderr = self._run(["subcodex", "submimo"])
        self.assertEqual(rc, 0, stderr)
        saved = self._saved()
        fixture_path = saved / "subcodex.md"
        plain_path = saved / "submimo.md"
        self.assertEqual(saved.stat().st_mode & 0o777, 0o700)
        self.assertEqual(saved.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(fixture_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(plain_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(fixture_path.read_text(encoding="utf-8"), FIXTURE_LAST)
        self.assertEqual(plain_path.read_text(encoding="utf-8"), NO_CONCLUSION)
        self.assertNotIn("Conclusion:", NO_CONCLUSION)
        self.assertEqual(stdout.splitlines(), [str(fixture_path), str(plain_path)])
        for leg in ("subcodex", "submimo"):
            head, names = self._view(leg)
            self.assertEqual(head, self.main_sha, leg)
            self.assertEqual(names, ["on-main.txt"], leg)
            task = (self.obs / f"{leg}.task").read_text(encoding="utf-8")
            self.assertIn("目标：给没定方向的改动收几份独立方案。", task)
            self.assertEqual(task.count(REQUIREMENT), 1)
        repos = {(self.obs / f"{leg}.repo").read_text(encoding="utf-8").strip()
                 for leg in ("subcodex", "submimo")}
        self.assertEqual(len(repos), 2)

    def test_one_leg_failure_keeps_the_other_result_and_exits_nonzero(self):
        self._link("subcodex", "subkimi")
        self.env["EXPLORE_PEERS"] = "subcodex subkimi"
        self.env["EXPLORE_STUB_subcodex"] = "fixture"
        self.env["EXPLORE_STUB_subkimi"] = "fail"
        rc, stdout, stderr = self._run(["subcodex", "subkimi"])
        self.assertNotEqual(rc, 0)
        saved = self._saved()
        kept = saved / "subcodex.md"
        self.assertEqual(kept.read_text(encoding="utf-8"), FIXTURE_LAST)
        self.assertFalse((saved / "subkimi.md").exists())
        self.assertEqual(stdout.splitlines(), [str(kept)])
        self.assertIn("subkimi", stderr)
        self.assertIn("quota", stderr)
        self.assertNotIn(FIXTURE_LAST, stderr)

    def test_repo_subdirectory_resolves_to_toplevel_and_snapshots_main(self):
        nested = self.repo / "nested"
        nested.mkdir()
        (nested / "note.txt").write_text("note\n", encoding="utf-8")
        self._git("add", "nested")
        self._git("commit", "-qm", "nested")
        self.main_sha = subprocess.check_output(
            ["git", "-C", str(self.repo), "rev-parse", "refs/heads/main"], text=True).strip()
        self._link("subcodex")
        self.env["EXPLORE_PEERS"] = "subcodex"
        self.env["EXPLORE_STUB_subcodex"] = "plain"
        rc, _stdout, stderr = self._run_at(["subcodex"], str(nested), None)
        self.assertEqual(rc, 0, stderr)
        head, names = self._view("subcodex")
        self.assertEqual(head, self.main_sha)
        self.assertEqual(names, ["nested", "on-main.txt"])

    def test_path_outside_a_git_repository_is_a_usage_error(self):
        outside = self.root / "notes"
        outside.mkdir()
        self._link("subcodex")
        self.env["EXPLORE_PEERS"] = "subcodex"
        rc, _stdout, stderr = self._run_at(["subcodex"], str(outside), None)
        self.assertEqual(rc, 2, stderr)
        self.assertIn("not a git repository", stderr)
        self.assertNotIn("Traceback", stderr)

    def test_taken_stamp_and_pid_still_creates_a_private_directory(self):
        self._link("subcodex")
        self.env["EXPLORE_PEERS"] = "subcodex"
        stamp = "20260102T030405Z"
        root = self.data / "explore"
        root.mkdir(parents=True)
        (root / f"brief-{stamp}").mkdir()
        (root / f"brief-{stamp}-{os.getpid()}").mkdir()
        class _FrozenDateTime(datetime):
            @classmethod
            def now(cls, tz=None):
                return datetime(2026, 1, 2, 3, 4, 5, tzinfo=timezone.utc)

        with patch.object(self.explore, "datetime", _FrozenDateTime):
            rc, stdout, stderr = self._run(["subcodex"])
        self.assertEqual(rc, 0, stderr)
        report = Path(stdout.strip())
        path = report.parent
        self.assertTrue(path.is_dir(), stdout)
        self.assertTrue(path.name.startswith("brief-"))
        self.assertNotIn(path.name, {f"brief-{stamp}", f"brief-{stamp}-{os.getpid()}"})
        self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        self.assertEqual(report.stat().st_mode & 0o777, 0o600)

    def test_relative_repo_dot_and_subdirectory_snapshot_local_main(self):
        self._link("subcodex")
        self.env["EXPLORE_PEERS"] = "subcodex"
        self.env["EXPLORE_STUB_subcodex"] = "fixture"
        rc, _stdout, stderr = self._run_at(["subcodex"], ".", self.repo)
        self.assertEqual(rc, 0, stderr)
        head, names = self._view("subcodex")
        self.assertEqual(head, self.main_sha)
        self.assertEqual(names, ["on-main.txt"])
        rc, _stdout, stderr = self._run_at(["subcodex"], f"./{self.repo.name}", self.repo.parent)
        self.assertEqual(rc, 0, stderr)
        head, names = self._view("subcodex")
        self.assertEqual(head, self.main_sha)
        self.assertEqual(names, ["on-main.txt"])

    def test_unexecutable_leg_fails_without_traceback_and_keeps_the_other(self):
        self._link("subcodex")
        blocked = self.bin / "subkimi"
        blocked.write_text("#!/usr/bin/env python3\nraise SystemExit(0)\n", encoding="utf-8")
        blocked.chmod(0o644)
        self.env["EXPLORE_PEERS"] = "subcodex"
        self.env["EXPLORE_STUB_subcodex"] = "fixture"
        rc, stdout, stderr = self._run(["subcodex", "subkimi"])
        self.assertNotEqual(rc, 0)
        self.assertIn("subkimi", stderr)
        self.assertNotIn("Traceback", stderr)
        saved = self._saved()
        self.assertEqual((saved / "subcodex.md").read_text(encoding="utf-8"), FIXTURE_LAST)
        self.assertFalse((saved / "subkimi.md").exists())
        self.assertEqual(stdout.splitlines(), [str(saved / "subcodex.md")])


class _Argv:
    def __init__(self, argv):
        self.argv = argv
        self.old = None

    def __enter__(self):
        self.old = sys.argv
        sys.argv = self.argv

    def __exit__(self, *exc):
        sys.argv = self.old


def unittest_mock_argv(argv):
    return _Argv(argv)


class _Env:
    def __init__(self, env):
        self.env = env
        self.old = None

    def __enter__(self):
        self.old = os.environ.copy()
        os.environ.clear()
        os.environ.update(self.env)

    def __exit__(self, *exc):
        os.environ.clear()
        os.environ.update(self.old)


def patch_env(env):
    return _Env(env)


class _Bin:
    def __init__(self, module, bin_dir):
        self.module = module
        self.bin_dir = bin_dir
        self.old = None

    def __enter__(self):
        self.old = self.module.BIN
        self.module.BIN = self.bin_dir

    def __exit__(self, *exc):
        self.module.BIN = self.old


def patch_bin(module, bin_dir):
    return _Bin(module, bin_dir)


# The name used above; defined here so the method body stays readable.
unittest.mock_argv = unittest_mock_argv


class MimoExploreTests(unittest.TestCase):
    """submimo explore must return the fixture's last message and not demand a conclusion."""

    def run_leg(self, fixture: Path, *, preseed: str | None = None):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        repo = root / "repo"
        repo.mkdir()
        subprocess.check_call(["git", "init", "-q", "-b", "main", str(repo)])
        subprocess.check_call(["git", "-C", str(repo), "config", "user.email", "t@example.com"])
        subprocess.check_call(["git", "-C", str(repo), "config", "user.name", "t"])
        (repo / "a.txt").write_text("a\n", encoding="utf-8")
        subprocess.check_call(["git", "-C", str(repo), "add", "-A"])
        subprocess.check_call(["git", "-C", str(repo), "commit", "-qm", "base"])
        config = write_settings(root / "settings")
        fake = root / "fake"
        fake.mkdir()
        (fake / "mimo").write_text(textwrap.dedent('''\
            #!/usr/bin/env python3
            import os, pathlib, sys
            pathlib.Path(os.environ["MIMO_ARGV"]).write_text("\\n".join(sys.argv[1:]), encoding="utf-8")
            if "--format" not in sys.argv or sys.argv[sys.argv.index("--format") + 1] != "json":
                raise SystemExit("explore must request --format json")
            sys.stdout.write(pathlib.Path(os.environ["MIMO_JSON_FIXTURE"]).read_text(encoding="utf-8"))
        '''), encoding="utf-8")
        (fake / "mimo").chmod(0o755)
        task = root / "task.md"
        task.write_text("# brief\n", encoding="utf-8")
        report = root / "report.md"
        if preseed is not None:
            report.write_text(preseed, encoding="utf-8")
        env = dict(os.environ)
        env.update(
            PATH=str(fake) + os.pathsep + env.get("PATH", ""),
            AIWORK_CONFIG_DIR=str(config),
            MIMO_REVIEW_HOME=str(root / "mimo-home"),
            MIMO_ARGV=str(root / "argv.txt"),
            MIMO_JSON_FIXTURE=str(fixture),
            AIWORK_REVIEW_REPORT_PATH=str(report),
            AIWORK_REVIEW_FACTS_PATH=str(root / "facts.json"),
            AIWORK_REVIEW_RESULT_BIN=str(ROOT / "bin" / "_review_result.py"),
        )
        result = subprocess.run(
            [str(ROOT / "bin" / "submimo"), "explore", str(task), str(root / "leg.log"), str(repo)],
            env=env, capture_output=True, text=True)
        argv = (root / "argv.txt").read_text(encoding="utf-8") if (root / "argv.txt").is_file() else ""
        body = report.read_text(encoding="utf-8") if report.is_file() else ""
        return result, argv, body, (root / "leg.log.report").exists()

    def test_explore_returns_the_fixture_last_message(self):
        result, argv, body, sidecar = self.run_leg(FIXTURE)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(body, FIXTURE_LAST)
        self.assertFalse(sidecar)
        self.assertNotIn("Do NOT use any tools", argv)
        self.assertNotIn("Direction / Core bet", argv)

    def test_explore_without_a_conclusion_line_is_success(self):
        kept = []
        for line in FIXTURE.read_text(encoding="utf-8").splitlines(keepends=True):
            if '"text":"Conclusion: PASS"' in line:
                continue
            kept.append(line)
        fixture = self._write("mimo-no-conclusion.jsonl", "".join(kept))
        result, _argv, body, sidecar = self.run_leg(fixture)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(body, "Shared fixture checked.\n\n")
        self.assertFalse(sidecar)
        self.assertNotIn("Conclusion:", body)

    def test_missing_last_message_fails_and_drops_the_previous_report(self):
        empty = self._write("mimo-empty.jsonl", "")
        result, _argv, body, sidecar = self.run_leg(empty, preseed="OLD\n")
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("no final message", result.stderr)
        self.assertEqual(body, "")
        self.assertFalse(sidecar)

    def _write(self, name, text):
        path = Path(self.id().replace(".", "_") + "-" + name)
        # Keep the trimmed sample next to the test's temp output, not in the repo.
        directory = Path(os.environ.get("TMPDIR", "/tmp"))
        target = directory / path.name
        target.write_text(text, encoding="utf-8")
        self.addCleanup(target.unlink, missing_ok=True)
        return target


def _git_repo(root: Path) -> Path:
    repo = root / "repo"
    repo.mkdir()
    subprocess.check_call(["git", "init", "-q", "-b", "main", str(repo)])
    subprocess.check_call(["git", "-C", str(repo), "config", "user.email", "t@example.com"])
    subprocess.check_call(["git", "-C", str(repo), "config", "user.name", "t"])
    (repo / "a.txt").write_text("a\n", encoding="utf-8")
    subprocess.check_call(["git", "-C", str(repo), "add", "-A"])
    subprocess.check_call(["git", "-C", str(repo), "commit", "-qm", "base"])
    return repo


class ExploreLegContractTests(unittest.TestCase):
    """Explore mode records timeout, fails without a last message, and writes one report."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = _git_repo(self.root)
        self.config = write_settings(self.root / "settings")
        self.fake = self.root / "fake"
        self.fake.mkdir()
        self.task = self.root / "task.md"
        self.task.write_text("# brief\n", encoding="utf-8")
        self.log = self.root / "leg.log"
        self.report = self.root / "report.md"
        self.facts = self.root / "facts.json"

    def _env(self, **extra):
        env = dict(os.environ)
        env.update(
            PATH=str(self.fake) + os.pathsep + env.get("PATH", ""),
            AIWORK_CONFIG_DIR=str(self.config),
            AIWORK_REVIEW_FACTS_PATH=str(self.facts),
            AIWORK_REVIEW_RESULT_BIN=str(ROOT / "bin" / "_review_result.py"),
        )
        env.pop("AIWORK_REVIEW_REPORT_PATH", None)
        env.update(extra)
        return env

    def _stub(self, name, text):
        path = self.fake / name
        path.write_text(text, encoding="utf-8")
        path.chmod(0o755)

    def _kimi_home(self):
        home = self.root / "kimi-home"
        (home / "hooks").mkdir(parents=True)
        (home / "hooks" / "guard.mjs").write_text("process.exit(2)\n", encoding="utf-8")
        (home / "credentials").mkdir()
        (home / "credentials" / "kimi-code.json").write_text("{}\n", encoding="utf-8")
        (home / "config.toml").write_text('default_model = "x"\n', encoding="utf-8")
        return home

    def _run(self, argv, env):
        return subprocess.run(argv, env=env, capture_output=True, text=True)

    def test_subagent_explore_timeout_is_timeout_not_runtime(self):
        self._stub("claude", "#!/usr/bin/env python3\nimport time\ntime.sleep(30)\n")
        result = self._run(
            [str(ROOT / "bin" / "subagent"), "deepseek", "explore",
             str(self.task), str(self.log), str(self.repo)],
            self._env(DEEPSEEK_API_KEY="fixture-key", DEEPSEEK_TIMEOUT="1"))
        self.assertEqual(result.returncode, 124, result.stderr)
        facts = json.loads(self.facts.read_text(encoding="utf-8"))
        self.assertEqual(facts["process_state"], "timed_out")
        self.assertEqual(facts["failure_kind"], "timeout")

    def test_subagent_explore_without_a_last_message_fails_and_writes_one_report(self):
        self._stub("claude", "#!/usr/bin/env python3\n")
        self.report.write_text("OLD\n", encoding="utf-8")
        result = self._run(
            [str(ROOT / "bin" / "subagent"), "deepseek", "explore",
             str(self.task), str(self.log), str(self.repo)],
            self._env(DEEPSEEK_API_KEY="fixture-key", AIWORK_REVIEW_REPORT_PATH=str(self.report)))
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("no final message", result.stderr)
        self.assertFalse(self.report.exists())
        self.assertFalse((self.root / "leg.log.report").exists())
        facts = json.loads(self.facts.read_text(encoding="utf-8"))
        self.assertIsNone(facts["failure_kind"])

    def test_subagent_explore_writes_the_report_only_at_the_requested_path(self):
        answer = "Direction noted.\n"
        self._stub("claude", textwrap.dedent(f'''\
            #!/usr/bin/env python3
            import json
            print(json.dumps({{"type": "result", "result": {answer!r}}}))
        '''))
        result = self._run(
            [str(ROOT / "bin" / "subagent"), "deepseek", "explore",
             str(self.task), str(self.log), str(self.repo)],
            self._env(DEEPSEEK_API_KEY="fixture-key", AIWORK_REVIEW_REPORT_PATH=str(self.report)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.report.read_text(encoding="utf-8"), answer)
        self.assertFalse((self.root / "leg.log.report").exists())

    def test_subagent_explore_without_a_report_path_writes_the_log_sidecar(self):
        answer = "Direction noted.\n"
        self._stub("claude", textwrap.dedent(f'''\
            #!/usr/bin/env python3
            import json
            print(json.dumps({{"type": "result", "result": {answer!r}}}))
        '''))
        result = self._run(
            [str(ROOT / "bin" / "subagent"), "deepseek", "explore",
             str(self.task), str(self.log), str(self.repo)],
            self._env(DEEPSEEK_API_KEY="fixture-key"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "leg.log.report").read_text(encoding="utf-8"), answer)
        self.assertFalse(self.report.exists())

    def test_subkimi_explore_without_a_last_message_fails_and_drops_the_old_report(self):
        self._stub("kimi", "#!/usr/bin/env python3\nprint('not-json')\n")
        self.report.write_text("OLD\n", encoding="utf-8")
        result = self._run(
            [str(ROOT / "bin" / "subkimi"), "explore", str(self.task), str(self.log), str(self.repo)],
            self._env(KIMI_REVIEW_HOME=str(self._kimi_home()), AIWORK_REVIEW_REPORT_PATH=str(self.report)))
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("no final message", result.stderr)
        self.assertFalse(self.report.exists())
        self.assertFalse((self.root / "leg.log.report").exists())

    def test_subkimi_explore_writes_one_report_and_does_not_normalize(self):
        answer = "Direction noted.\n"
        self._stub("kimi", textwrap.dedent(f'''\
            #!/usr/bin/env python3
            import json
            print(json.dumps({{"role": "assistant", "content": {answer!r}}}))
        '''))
        normalizer = self.root / "normalizer.py"
        real = ROOT / "bin" / "_review_result.py"
        normalizer.write_text(
            "import os, sys\n"
            "if 'normalize' in sys.argv[1:]:\n"
            "    sys.stderr.write('normalize must not run\\n')\n"
            "    raise SystemExit(1)\n"
            f"os.execv(sys.executable, [sys.executable, {str(real)!r}, *sys.argv[1:]])\n",
            encoding="utf-8")
        result = self._run(
            [str(ROOT / "bin" / "subkimi"), "explore", str(self.task), str(self.log), str(self.repo)],
            self._env(
                KIMI_REVIEW_HOME=str(self._kimi_home()),
                AIWORK_REVIEW_REPORT_PATH=str(self.report),
                AIWORK_REVIEW_RESULT_BIN=str(normalizer)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.report.read_text(encoding="utf-8"), answer)
        self.assertFalse((self.root / "leg.log.report").exists())
        self.assertNotIn("normalize must not run", result.stderr)

    def test_whitespace_only_last_message_fails_with_the_shared_sentence(self):
        blank = " \t\n"
        legs = (
            ("subagent", self._blank_subagent),
            ("subkimi", self._blank_subkimi),
            ("submimo", self._blank_submimo),
        )
        for name, prepare in legs:
            with self.subTest(leg=name):
                slot = self.root / name
                slot.mkdir()
                log = slot / "leg.log"
                report = slot / "report.md"
                facts = slot / "facts.json"
                report.write_text("OLD\n", encoding="utf-8")
                argv, env = prepare(log, report, facts)
                result = self._run(argv, env)
                self.assertEqual(result.returncode, 1, result.stderr)
                label = {"subagent": "subdeepseek-agent", "subkimi": "subkimi",
                         "submimo": "submimo"}[name]
                self.assertEqual(
                    result.stderr.strip(),
                    f"{label}: explore produced no final message (log: {log})",
                )
                self.assertTrue(report.is_file(), result.stderr)
                self.assertEqual(report.read_text(encoding="utf-8"), blank)
                self.assertFalse((slot / "leg.log.report").exists())
                recorded = json.loads(facts.read_text(encoding="utf-8"))
                self.assertEqual(recorded["process_state"], "exited")
                self.assertEqual(recorded["evidence_completeness"], "partial")
                self.assertIsNone(recorded["failure_kind"])
                self.assertIsNone(recorded["verdict"])

    def _blank_subagent(self, log, report, facts):
        self._stub("claude", textwrap.dedent('''\
            #!/usr/bin/env python3
            import json
            print(json.dumps({"type": "result", "result": " \\t\\n"}))
        '''))
        return (
            [str(ROOT / "bin" / "subagent"), "deepseek", "explore",
             str(self.task), str(log), str(self.repo)],
            self._env(
                DEEPSEEK_API_KEY="fixture-key",
                AIWORK_REVIEW_REPORT_PATH=str(report),
                AIWORK_REVIEW_FACTS_PATH=str(facts)),
        )

    def _blank_subkimi(self, log, report, facts):
        self._stub("kimi", textwrap.dedent('''\
            #!/usr/bin/env python3
            import json
            print(json.dumps({"role": "assistant", "content": " \\t\\n"}))
        '''))
        return (
            [str(ROOT / "bin" / "subkimi"), "explore", str(self.task), str(log), str(self.repo)],
            self._env(
                KIMI_REVIEW_HOME=str(self._kimi_home()),
                AIWORK_REVIEW_REPORT_PATH=str(report),
                AIWORK_REVIEW_FACTS_PATH=str(facts)),
        )

    def _blank_submimo(self, log, report, facts):
        payload = json.dumps({
            "type": "text",
            "part": {"id": "p", "messageID": "m", "text": " \t\n"},
        })
        self._stub("mimo", textwrap.dedent(f'''\
            #!/usr/bin/env python3
            print({payload!r})
        '''))
        return (
            [str(ROOT / "bin" / "submimo"), "explore", str(self.task), str(log), str(self.repo)],
            self._env(
                MIMO_REVIEW_HOME=str(self.root / "mimo-home"),
                AIWORK_REVIEW_REPORT_PATH=str(report),
                AIWORK_REVIEW_FACTS_PATH=str(facts)),
        )


if __name__ == "__main__":
    unittest.main()

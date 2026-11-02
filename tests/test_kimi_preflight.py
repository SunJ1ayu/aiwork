"""Native Kimi preflight: local provider only, no vendor credentials or quota."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: F401,E402

import importlib.util
import json
from pathlib import Path
import shlex
import shutil
import tempfile
import subprocess
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCHEMAS = ROOT / "tests/fixtures/kimi-code-0.36.1/reader-tools.json"




class KimiPreflight(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "runtime"
        (self.home / "hooks").mkdir(parents=True)
        self.guard = self.home / "hooks/guard.mjs"
        shutil.copyfile(ROOT / "kimi-review-home/hooks/guard.mjs", self.guard)
        node = shlex.quote(shutil.which("node"))
        self.home.joinpath("config.toml").write_text(
            '[[hooks]]\nevent="PreToolUse"\nmatcher=".*"\ncommand='
            + json.dumps(node + " " + shlex.quote(str(self.guard))) + '\ntimeout=10\n')
        self.profile = self.root / "profile.md"
        self.profile.write_text("---\nname: aiwork-review\ntools: [Read, ReadMediaFile, Glob, Grep]\n---\n")
        self.capture = self.root / "capture.json"

    def helper(self):
        path = ROOT / "bin/_kimi_preflight.py"
        spec = importlib.util.spec_from_file_location("kimi_preflight", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def cli(self, mode):
        path = self.root / "kimi"
        path.write_text("#!" + sys.executable + "\nimport os,sys\nos.execv("
                        + repr(sys.executable) + ", [" + repr(sys.executable) + ", "
                        + repr(str(ROOT / "tests/_kimi_cli.py")) + ", '--native-fixture', "
                        + repr(str(SCHEMAS)) + ", " + repr(mode) + ", "
                        + repr(str(self.capture)) + "] + sys.argv[1:])\n")
        path.chmod(0o755)
        return path

    def test_real_hook_and_captured_input_schema_pass(self):
        self.helper().preflight(self.cli("valid"), self.home, self.profile)
        self.assertEqual(sorted(p.name for p in self.root.iterdir()),
                         ["capture.json", "kimi", "profile.md", "runtime"])

    def test_changed_schema_and_ignored_or_broken_hook_refuse(self):
        helper = self.helper()
        for mode in ("renamed-path", "ignore-hook", "all-deny", "crash"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                helper.preflight(self.cli(mode), self.home, self.profile)

    def test_nested_and_enum_schema_drift_refuses(self):
        for mode in ("nested-schema", "enum-schema", "description-field"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.helper().preflight(self.cli(mode), self.home, self.profile)

    def test_denial_text_does_not_excuse_leaked_outside_content(self):
        with self.assertRaises(ValueError):
            self.helper().preflight(self.cli("deny-and-read"), self.home, self.profile)

    def test_search_that_follows_directory_links_refuses(self):
        for mode in ("follow-links", "glob-follow-links", "grep-follow-links"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.helper().preflight(self.cli(mode), self.home, self.profile)

    def test_cleanup_is_included_in_the_overall_deadline(self):
        copied = self.root / "bin"
        shutil.copytree(ROOT / "bin", copied)
        helper = copied / "_kimi_preflight.py"
        helper.write_text(helper.read_text().replace("server.shutdown()", "__import__('time').sleep(60)"))
        script = ("import sys; sys.path.insert(0, sys.argv[1]); "
                  "from _kimi_preflight import preflight\n"
                  "try: preflight(*sys.argv[2:5], timeout=1)\n"
                  "except ValueError as e: print(str(e)); sys.exit(0)\n"
                  "sys.exit(1)\n")
        started = time.monotonic()
        result = subprocess.run([sys.executable, "-c", script, str(copied), str(self.cli("valid")),
                                 str(self.home), str(self.profile)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("overall deadline", result.stdout)
        self.assertLess(time.monotonic() - started, 10)

    def test_probe_environment_has_no_inherited_credentials_or_search_config(self):
        from unittest.mock import patch
        with patch.dict(os.environ, {"ANTHROPIC_AUTH_TOKEN": "fixture-only",
                                    "KIMI_API_KEY": "fixture-only",
                                    "RIPGREP_CONFIG_PATH": "/not-used"}):
            self.helper().preflight(self.cli("valid"), self.home, self.profile)
        record = json.loads(self.capture.read_text())
        self.assertNotIn("ANTHROPIC_AUTH_TOKEN", record["keys"])
        self.assertNotIn("KIMI_API_KEY", record["keys"])
        self.assertEqual(record["ripgrep_config"], "")
        self.assertNotEqual(record["home"], os.environ["HOME"])

    def test_timeout_kills_probe_and_cleans_its_state(self):
        with self.assertRaises(ValueError):
            self.helper().preflight(self.cli("hung"), self.home, self.profile, timeout=0.3)
        self.assertFalse(list(self.root.glob("kimi-preflight-*")))


if __name__ == "__main__":
    unittest.main()

"""The total runner must reject omitted unittest instances, not just empty runs."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "import unittest\nimport _no_egress\n"
ONE = "class First(unittest.TestCase):\n    def test_first(self): pass\n"
MAIN = "if __name__ == '__main__': unittest.main()\n"


class SuiteAudit(unittest.TestCase):
    def run_suite(self, source, *, limit="20"):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            shutil.copytree(ROOT / "bin", root / "bin")
            tests = root / "tests"
            tests.mkdir()
            for helper in (ROOT / "tests").glob("_*.py"):
                shutil.copy2(helper, tests / helper.name)
            (tests / "test_probe.py").write_text(PREFIX + source)
            runner = root / "bin/rust-check-review-tooling"
            source = re.sub(r"SUITES=\(\n.*?\n\)",
                            'SUITES=(\n  "probe|python3|$ROOT/tests/test_probe.py"\n)',
                            runner.read_text(), count=1, flags=re.S)
            runner.write_text(source)
            return subprocess.run(["bash", str(runner)], text=True,
                                  capture_output=True, timeout=35,
                                  env=dict(os.environ, SUITE_TIMEOUT=limit))

    def assert_rejected(self, result, *messages):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        for message in messages:
            self.assertIn(message, result.stdout + result.stderr)

    def test_definition_after_main_is_reported_without_running_it(self):
        result = self.run_suite(ONE + MAIN +
            "class Late(unittest.TestCase):\n"
            "    def test_missing(self): raise AssertionError('MUST_NOT_RUN_LATE')\n")
        self.assert_rejected(result, "test_probe.py", "Late.test_missing")
        self.assertNotIn("MUST_NOT_RUN_LATE", result.stdout + result.stderr)

    def test_selection_cannot_hide_a_defined_test(self):
        result = self.run_suite(ONE +
            "class Hidden(unittest.TestCase):\n    def test_hidden(self): pass\n" +
            "if __name__ == '__main__': unittest.main(defaultTest='First')\n")
        self.assert_rejected(result, "Hidden.test_hidden")

    def test_inherited_instances_and_explicit_skip_are_accounted_for(self):
        result = self.run_suite(ONE +
            "class Child(First): pass\n"
            "class Skipped(unittest.TestCase):\n"
            "    @unittest.skip('fixture')\n    def test_skip(self): pass\n" + MAIN)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_custom_collection_is_ambiguous_instead_of_silently_accepted(self):
        result = self.run_suite(ONE +
            "class Hidden(unittest.TestCase):\n    def test_hidden(self): pass\n"
            "def load_tests(loader, tests, pattern):\n"
            "    return loader.loadTestsFromTestCase(First)\n" + MAIN)
        self.assert_rejected(result, "load_tests")

    def test_empty_failure_and_early_success_stay_red(self):
        for source in (MAIN, ONE.replace("pass", "self.fail('fixture')") + MAIN,
                       ONE + "raise SystemExit(0)\n"):
            with self.subTest(source=source):
                self.assert_rejected(self.run_suite(source))

    def test_inventory_and_execution_share_the_deadline(self):
        for source in ("import time\ntime.sleep(30)\n" + ONE + MAIN,
                       ONE.replace("pass", "__import__('time').sleep(30)") + MAIN):
            with self.subTest(source=source):
                self.assert_rejected(self.run_suite(source, limit="0.5"), "rc=124")

    def test_child_python_does_not_inherit_the_observer(self):
        result = self.run_suite(ONE.replace("pass",
            "__import__('subprocess').run([__import__('sys').executable, '-c', "
            "\"import unittest; unittest.main()\"], check=True)") + MAIN)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

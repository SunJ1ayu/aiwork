"""Compare full unittest discovery with the unchanged script's observed instances."""
import atexit
from collections import Counter
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import types
import unittest


def observe(target, receipt, pythonpath):
    # Import before consuming the startup hook: guard reexec must inherit it.
    import _no_egress  # noqa: F401
    if str(Path(sys.argv[0]).resolve()) != target:
        raise RuntimeError("observer started for a different script")
    hook = str(Path(sys.modules["sitecustomize"].__file__).parent)
    sys.path[:] = [p for p in sys.path if p != hook]
    if pythonpath is None:
        os.environ.pop("PYTHONPATH", None)
    else:
        os.environ["PYTHONPATH"] = pythonpath
    Path(receipt).write_text("")

    def record(event):
        with open(receipt, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(event) + "\n")

    install_case_observer(record)
    atexit.register(record, {"complete": True})


def install_case_observer(record):
    """Observe unittest dispositions; callers enforce isolation before loading suites."""
    original = unittest.TestResult.startTest

    def start(result, test):
        record({"test": test.id()})
        return original(result, test)

    unittest.TestResult.startTest = start
    fixture_skips = {}
    exception = unittest.TestSuite._createClassOrModuleLevelException
    module_setup = unittest.TestSuite._handleModuleFixture
    class_setup = unittest.TestSuite._handleClassSetUp

    def fixture_exception(suite, result, exc, method_name, parent, info=None):
        if isinstance(exc, unittest.SkipTest) and method_name in ("setUpClass", "setUpModule"):
            fixture_skips.setdefault(result, set()).add((method_name, parent))
        return exception(suite, result, exc, method_name, parent, info)

    def handle_module(suite, test, result):
        previous = getattr(result, '_previousTestClass', None)
        if test.__class__.__module__ != getattr(previous, '__module__', None):
            scopes = fixture_skips.setdefault(result, set())
            scopes.difference_update(scope for scope in tuple(scopes) if scope[0] == "setUpModule")
        return module_setup(suite, test, result)

    def handle_class(suite, test, result):
        scopes = fixture_skips.setdefault(result, set())
        if test.__class__ != getattr(result, '_previousTestClass', None):
            scopes.difference_update(scope for scope in tuple(scopes) if scope[0] == "setUpClass")
        value = class_setup(suite, test, result)
        module_skipped = (getattr(result, '_moduleSetUpFailed', False) and
                          ("setUpModule", test.__class__.__module__) in scopes)
        class_skipped = (getattr(test.__class__, '_classSetupFailed', False) and
                         ("setUpClass", unittest.util.strclass(test.__class__)) in scopes)
        # This hook is called for each selected leaf, including leaves bypassed
        # by failed fixtures. Record those leaves only, never exempt a name prefix:
        # unselected methods and definitions after main must remain missing.
        if module_skipped or class_skipped:
            record({"test": test.id(), "fixture_skip": True})
        return value

    unittest.TestSuite._createClassOrModuleLevelException = fixture_exception
    unittest.TestSuite._handleModuleFixture = handle_module
    unittest.TestSuite._handleClassSetUp = handle_class


def inventory(target, destination):
    import _no_egress  # noqa: F401
    sys.argv = [target]
    sys.path[0] = str(Path(target).parent)

    def refuse_run(*args, **kwargs):
        raise RuntimeError("inventory attempted to execute a test")

    # Load the whole file with its script semantics, but never run its tests.
    # In particular unittest.main must not exit before later definitions load.
    unittest.TestProgram.runTests = lambda self: None
    unittest.TestCase.run = refuse_run
    unittest.TestSuite.run = refuse_run
    namespace = runpy.run_path(target, run_name="__main__")
    if "load_tests" in namespace:
        raise RuntimeError("load_tests makes the complete inventory ambiguous")
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(types.SimpleNamespace(**namespace))
    if loader.errors:
        raise RuntimeError("; ".join(loader.errors))

    def identities(tests):
        for test in tests:
            if isinstance(test, unittest.TestSuite):
                yield from identities(test)
            elif isinstance(test, unittest.TestCase):
                yield test.id()
            else:
                raise RuntimeError("non-unittest instance in inventory")

    Path(destination).write_text(json.dumps(list(identities(suite))))


def audit(target):
    target = str(Path(target).resolve())
    helper = str(Path(__file__).resolve())
    with tempfile.TemporaryDirectory(prefix="suite-audit-") as folder:
        root = Path(folder)
        expected_path, receipt = root / "expected.json", root / "executed.jsonl"
        rc = subprocess.call([sys.executable, helper, "--inventory", target, str(expected_path)])
        if rc:
            print(f"FAIL Python suite audit {target}: cannot determine complete inventory (rc={rc})")
            return rc
        try:
            expected = Counter(json.loads(expected_path.read_text()))
        except (OSError, ValueError, TypeError) as exc:
            print(f"FAIL Python suite audit {target}: missing or invalid inventory: {exc}")
            return 1

        hook = root / "hook"
        hook.mkdir()
        pythonpath = os.environ.get("PYTHONPATH")
        # Only this direct script receives the startup hook. It removes itself
        # after guard enforcement so subprocess Python invocations stay ordinary.
        (hook / "sitecustomize.py").write_text(
            "import os, sys\ntry:\n"
            f"    sys.path.insert(0, {str(Path(helper).parent)!r})\n"
            "    from _suite_audit import observe\n"
            f"    observe({target!r}, {str(receipt)!r}, {pythonpath!r})\n"
            "except BaseException as exc:\n"
            "    print('FAIL Python suite audit startup:', exc, file=sys.stderr, flush=True)\n"
            "    os._exit(78)\n")
        env = dict(os.environ, PYTHONPATH=str(hook) + (os.pathsep + pythonpath if pythonpath else ""))
        rc = subprocess.call([sys.executable, target], env=env)
        if rc:
            return rc
        try:
            events = [json.loads(line) for line in receipt.read_text().splitlines()]
            if not events or events[-1] != {"complete": True}:
                raise ValueError("execution did not finish its audit")
            actual = Counter(event["test"] for event in events[:-1])
        except (OSError, ValueError, KeyError, TypeError) as exc:
            print(f"FAIL Python suite audit {target}: missing or invalid execution record: {exc}")
            return 1
        missing, unexpected = expected - actual, actual - expected
        if not expected or missing or unexpected:
            print(f"FAIL Python suite audit {target}: "
                  f"missing={dict(missing)}, unexpected={dict(unexpected)}, "
                  f"expected={sum(expected.values())}, observed={sum(actual.values())}")
            return 1
        return 0


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--inventory":
        test_file, destination = sys.argv[2:]
        try:
            inventory(test_file, destination)
        except Exception as exc:
            print(f"FAIL Python suite audit {test_file}: cannot determine complete inventory: {exc}")
            raise SystemExit(1)
    elif len(sys.argv) == 2:
        raise SystemExit(audit(sys.argv[1]))
    else:
        raise SystemExit("usage: _suite_audit.py TEST_FILE")

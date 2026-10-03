#!/usr/bin/env python3
"""Exercise the real token helper with fake signing and HTTP, never real keys."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: F401,E402

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AppTokenScopeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        fake = self.root / "bin"
        fake.mkdir()
        config = self.root / "apps"
        config.mkdir()
        key = config / "fake.pem"
        key.write_text("fake-key-used-only-by-fake-openssl")
        (config / "review.env").write_text(
            f"APP_ID=1\nINSTALLATION_ID=2\nKEY={key}\nREPOS='OpenDesign aiwork'\n"
            "PERMISSIONS='{" + '"contents":"read","pull_requests":"write"' + "}'\n")
        (fake / "openssl").write_text("#!/bin/sh\ncat >/dev/null\nprintf stub\n")
        (fake / "curl").write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv
data=args[args.index('--data-binary')+1][1:]
pathlib.Path(os.environ['FAKE_REQUEST']).write_text(pathlib.Path(data).read_text())
print(os.environ['FAKE_GRANT'])
print('201')
''')
        for p in fake.iterdir():
            p.chmod(0o755)
        self.request = self.root / "request.json"
        self.env = dict(os.environ, AIWORK_APPS_DIR=str(config), FAKE_REQUEST=str(self.request),
                        PATH=str(fake) + os.pathsep + os.environ["PATH"])

    def invoke(self, args, repos, permissions=None):
        grant = {"token": "fake-test-token", "expires_at": "2099-01-01T00:00:00Z",
                 "permissions": permissions or {"contents": "read", "pull_requests": "write", "metadata": "read"},
                 "repositories": [{"name": r.split('/')[1], "full_name": r} for r in repos]}
        env = dict(self.env, FAKE_GRANT=json.dumps(grant))
        return subprocess.run([str(ROOT / "bin/gh-app-token"), "review", *args], env=env,
                              capture_output=True, text=True, timeout=10)

    def test_task_token_contains_only_the_requested_repository(self):
        for target in ("SunJ1ayu/aiwork", "SunJ1ayu/OpenDesign"):
            with self.subTest(target=target):
                result = self.invoke(["--repo", target], [target])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(self.request.read_text())["repositories"], [target.split('/')[1]])
                self.assertEqual(result.stdout.strip(), "fake-test-token")

    def test_unconfigured_or_malformed_target_mints_no_token(self):
        for target in ("SunJ1ayu/unconfigured", "../aiwork", "owner/aiwork/other", "owner/aiwork\nother"):
            with self.subTest(target=target):
                result = self.invoke(["--repo", target], ["SunJ1ayu/aiwork"])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertFalse(self.request.exists(), "invalid scope must fail before HTTP")

    def test_overbroad_wrong_owner_and_wrong_permissions_grants_are_refused(self):
        cases = [(["SunJ1ayu/aiwork", "SunJ1ayu/OpenDesign"], None),
                 (["other-owner/aiwork"], None),
                 (["SunJ1ayu/aiwork"], {"contents": "write", "pull_requests": "write", "metadata": "read"})]
        for repos, permissions in cases:
            with self.subTest(repos=repos, permissions=permissions):
                result = self.invoke(["--repo", "SunJ1ayu/aiwork"], repos, permissions)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_existing_unscoped_grant_mode_is_compatible(self):
        result = self.invoke(["--grant"], ["SunJ1ayu/OpenDesign", "SunJ1ayu/aiwork"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(json.loads(self.request.read_text())["repositories"]), ["OpenDesign", "aiwork"])
        self.assertNotIn("fake-test-token", result.stdout)

    def test_scoped_grant_reports_the_single_target_without_the_token(self):
        result = self.invoke(["--repo", "SunJ1ayu/aiwork", "--grant"], ["SunJ1ayu/aiwork"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["repositories"], ["SunJ1ayu/aiwork"])
        self.assertNotIn("fake-test-token", result.stdout)


if __name__ == "__main__":
    unittest.main()

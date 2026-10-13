"""Canonicalize a possibly missing path the way GNU realpath -m does."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = [sys.executable, str(ROOT / 'bin' / '_canonicalize_missing.py')]


def gnu_realpath_m(path, cwd):
    """GNU realpath -m output, or None when this machine has no such option."""
    realpath = shutil.which('realpath')
    if not realpath:
        return None
    proc = subprocess.run([realpath, '-m', '--', path], cwd=cwd,
                          capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    return proc.stdout.rstrip('\n')


class CanonicalizeMissingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.real = self.root / 'realdir'
        (self.real / 'sub').mkdir(parents=True)
        (self.root / 'link').symlink_to(self.real)

    def canonicalize(self, path):
        result = subprocess.run(TOOL + ['--', path], cwd=self.root,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        got = result.stdout.rstrip('\n')
        gnu = gnu_realpath_m(path, self.root)
        if gnu is not None:
            self.assertEqual(got, gnu, path)
        return got

    def test_relative_path_becomes_absolute(self):
        got = self.canonicalize('realdir/sub/missing')
        self.assertTrue(os.path.isabs(got))
        self.assertEqual(got, str(self.real / 'sub' / 'missing'))

    def test_existing_symlink_parent_is_resolved(self):
        got = self.canonicalize('link/missing-tail')
        self.assertEqual(got, str(self.real / 'missing-tail'))

    def test_missing_tail_is_kept(self):
        got = self.canonicalize('realdir/sub/does/not/exist')
        self.assertEqual(got, str(self.real / 'sub' / 'does' / 'not' / 'exist'))

    def test_dotdot_in_the_middle(self):
        got = self.canonicalize('realdir/sub/../../realdir/nope')
        self.assertEqual(got, str(self.real / 'nope'))

    def test_missing_argument_exits_nonzero(self):
        result = subprocess.run(TOOL, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()

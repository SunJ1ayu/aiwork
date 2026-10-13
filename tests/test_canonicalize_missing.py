"""Canonicalize a possibly missing path the way GNU realpath does.

Default is realpath -m. --no-symlinks is realpath -s.
"""
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
_GNU_BIN = {}


def gnu_bin(flag):
    """GNU realpath when it accepts flag, else None.

    None means this machine has no such option. A comparison that then fails
    is a test failure, not a skip.
    """
    if flag not in _GNU_BIN:
        realpath = shutil.which('realpath')
        supported = False
        if realpath:
            probe = subprocess.run([realpath, flag, '--', '/'],
                                   capture_output=True, text=True)
            supported = probe.returncode == 0
        _GNU_BIN[flag] = realpath if supported else None
    return _GNU_BIN[flag]


class CanonicalizeMissingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.real = self.root / 'realdir'
        (self.real / 'sub').mkdir(parents=True)
        (self.root / 'link').symlink_to(self.real)

    def canonicalize(self, path, *, no_symlinks=False):
        flag = '-s' if no_symlinks else '-m'
        cmd = TOOL + (['--no-symlinks'] if no_symlinks else []) + ['--', path]
        result = subprocess.run(cmd, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        got = result.stdout.rstrip('\n')
        gnu = gnu_bin(flag)
        if gnu is not None:
            proc = subprocess.run([gnu, flag, '--', path], cwd=self.root,
                                  capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0,
                             f'GNU realpath {flag} failed for {path!r}: {proc.stderr}')
            self.assertEqual(got, proc.stdout.rstrip('\n'), path)
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

    def test_empty_argument_exits_nonzero(self):
        for extra in ([], ['--no-symlinks']):
            result = subprocess.run(TOOL + extra + ['--', ''], cwd=self.root,
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, extra)
            self.assertEqual(result.stdout, '')
        for flag in ('-m', '-s'):
            gnu = gnu_bin(flag)
            if gnu is None:
                continue
            proc = subprocess.run([gnu, flag, '--', ''], cwd=self.root,
                                  capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(proc.stdout, '')

    def test_no_symlinks_mode_does_not_resolve_links(self):
        nested = self.root / 'a' / 'b'
        nested.mkdir(parents=True)
        (self.root / 'deeplink').symlink_to(nested)
        (self.root / 'c').mkdir()
        literal = self.canonicalize('deeplink/../c', no_symlinks=True)
        self.assertEqual(literal, str(self.root / 'c'))
        resolved = self.canonicalize('deeplink/../c')
        self.assertEqual(resolved, str(self.root / 'a' / 'c'))


if __name__ == '__main__':
    unittest.main()

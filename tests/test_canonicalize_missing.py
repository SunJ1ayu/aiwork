"""Canonicalize a possibly missing path, and test directory containment.

Default canon is GNU realpath -m. --no-symlinks is GNU realpath -m -s.
inside asks whether one path is inside another by device and inode.
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
TOOL = [sys.executable, str(ROOT / 'bin' / '_paths.py')]
_GNU_BIN = {}


def gnu_bin(no_symlinks):
    """GNU realpath when it accepts the matching flags, else None.

    Default is -m. --no-symlinks is -m -s. None means this machine has no
    such option. A comparison that then fails is a test failure, not a skip.
    """
    flags = ('-m', '-s') if no_symlinks else ('-m',)
    if flags not in _GNU_BIN:
        realpath = shutil.which('realpath')
        supported = False
        if realpath:
            probe = subprocess.run([realpath, *flags, '--', '/'],
                                   capture_output=True, text=True)
            supported = probe.returncode == 0
        _GNU_BIN[flags] = realpath if supported else None
    return _GNU_BIN[flags]


class CanonicalizeMissingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.real = self.root / 'realdir'
        (self.real / 'sub').mkdir(parents=True)
        (self.root / 'link').symlink_to(self.real)

    def canonicalize(self, path, *, no_symlinks=False):
        flags = ['-m', '-s'] if no_symlinks else ['-m']
        cmd = TOOL + ['canon'] + (['--no-symlinks'] if no_symlinks else []) + ['--', path]
        result = subprocess.run(cmd, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        got = result.stdout.rstrip('\n')
        gnu = gnu_bin(no_symlinks)
        if gnu is not None:
            proc = subprocess.run([gnu, *flags, '--', path], cwd=self.root,
                                  capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0,
                             f'GNU realpath {" ".join(flags)} failed for {path!r}: {proc.stderr}')
            self.assertEqual(got, proc.stdout.rstrip('\n'), path)
        return got

    def inside(self, root, path, *, no_symlinks=False):
        cmd = TOOL + ['inside'] + (['--no-symlinks'] if no_symlinks else []) + ['--', root, path]
        return subprocess.run(cmd, cwd=self.root, capture_output=True, text=True)

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
        result = subprocess.run(TOOL + ['canon'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_empty_argument_exits_nonzero(self):
        for extra in ([], ['--no-symlinks']):
            result = subprocess.run(TOOL + ['canon'] + extra + ['--', ''], cwd=self.root,
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, extra)
            self.assertEqual(result.stdout, '')
        for no_symlinks in (False, True):
            gnu = gnu_bin(no_symlinks)
            if gnu is None:
                continue
            flags = ['-m', '-s'] if no_symlinks else ['-m']
            proc = subprocess.run([gnu, *flags, '--', ''], cwd=self.root,
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

    def test_leading_double_slash_collapses(self):
        path = '//' + str(self.real).lstrip('/') + '/missing'
        for no_symlinks in (False, True):
            got = self.canonicalize(path, no_symlinks=no_symlinks)
            self.assertFalse(got.startswith('//'), got)
            self.assertEqual(got, str(self.real / 'missing'))

    def test_double_slash_is_inside(self):
        repo = self.root / 'repo'
        (repo / 'keep').mkdir(parents=True)
        path = '//' + str(repo).lstrip('/') + '/keep'
        for no_symlinks in (False, True):
            result = self.inside(str(repo), path, no_symlinks=no_symlinks)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, 'keep\n')

    def test_committed_symlink_out_is_inside_only_literally(self):
        repo = self.root / 'repo'
        repo.mkdir()
        outside = self.root / 'outside'
        outside.mkdir()
        secret = outside / 'secret'
        secret.write_text('x\n')
        link = repo / 'attack-link.md'
        link.symlink_to(secret)
        literal = self.inside(str(repo), str(link), no_symlinks=True)
        self.assertEqual(literal.returncode, 0, literal.stderr)
        self.assertEqual(literal.stdout, 'attack-link.md\n')
        resolved = self.inside(str(repo), str(link))
        self.assertEqual(resolved.returncode, 1, resolved.stderr)
        self.assertEqual(resolved.stdout, '')

    def test_outside_symlink_into_repo_is_inside_once_resolved(self):
        repo = self.root / 'repo'
        (repo / 'keep').mkdir(parents=True)
        (repo / 'keep' / 'file').write_text('x\n')
        link = self.root / 'ext-link'
        link.symlink_to(repo / 'keep' / 'file')
        resolved = self.inside(str(repo), str(link))
        self.assertEqual(resolved.returncode, 0, resolved.stderr)
        self.assertEqual(resolved.stdout, 'keep/file\n')
        literal = self.inside(str(repo), str(link), no_symlinks=True)
        self.assertEqual(literal.returncode, 1, literal.stderr)
        self.assertEqual(literal.stdout, '')

    def test_missing_tail_under_root_prints_remainder(self):
        result = self.inside(str(self.real), str(self.real / 'no' / 'file'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'no/file\n')

    def test_path_equal_to_root_prints_empty_line(self):
        result = self.inside(str(self.real), str(self.real))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '\n')

    def test_sibling_with_shared_prefix_is_outside(self):
        parent = self.root / 'x'
        repo = parent / 'repo'
        sibling = parent / 'repo2'
        repo.mkdir(parents=True)
        sibling.mkdir()
        result = self.inside(str(repo), str(sibling))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, '')

    def test_missing_root_existing_path_elsewhere_is_outside(self):
        missing = self.root / 'no-such-root'
        result = self.inside(str(missing), str(self.real / 'sub'))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, '')

    def test_missing_root_path_under_it_prints_remainder(self):
        missing = self.root / 'no-such-root'
        result = self.inside(str(missing), str(missing / 'sub' / 'file'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'sub/file\n')

    def test_empty_root_exits_2(self):
        result = self.inside('', str(self.real))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')

    def test_case_difference_follows_the_filesystem(self):
        base = self.root / 'CaseDir'
        base.mkdir()
        alt = base.with_name('casedir')
        try:
            same = alt.exists() and os.stat(alt).st_ino == os.stat(base).st_ino \
                and os.stat(alt).st_dev == os.stat(base).st_dev
        except OSError:
            same = False
        if not same:
            print('跳过大小写: 这个文件系统区分大小写', flush=True)
            self.skipTest('这个文件系统区分大小写')
        result = self.inside(str(base), str(alt))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '\n')


if __name__ == '__main__':
    unittest.main()

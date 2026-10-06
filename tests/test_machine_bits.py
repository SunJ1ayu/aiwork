"""Repository tools must work without machine-specific paths or settings."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MachineBitsTests(unittest.TestCase):
    def test_bin_has_no_root_paths_on_non_comment_lines(self):
        hits = []
        for path in sorted((ROOT / 'bin').rglob('*')):
            if not path.is_file() or '__pycache__' in path.parts:
                continue
            try:
                lines = path.read_text(encoding='utf-8').splitlines()
            except UnicodeDecodeError:
                continue
            for number, line in enumerate(lines, 1):
                if not line.lstrip().startswith('#') and '/root/' in line:
                    hits.append(f'{path.relative_to(ROOT)}:{number}')
        self.assertEqual(hits, [], '\n'.join(hits))


if __name__ == '__main__':
    unittest.main()

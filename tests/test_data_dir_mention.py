#!/usr/bin/env python3
"""The default data directory is named once, in bin/_aiwork_config.py."""
import ast
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = ('bin', 'workflow', 'templates')


def default_from_source():
    """The relative default joined to Path.home() inside data_dir(), and its line."""
    path = ROOT / 'bin' / '_aiwork_config.py'
    tree = ast.parse(path.read_text(encoding='utf-8'))
    found = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef) or node.name != 'data_dir':
            continue
        for child in ast.walk(node):
            if not isinstance(child, ast.BinOp) or not isinstance(child.op, ast.Div):
                continue
            left, right = child.left, child.right
            if not isinstance(right, ast.Constant) or not isinstance(right.value, str):
                continue
            func = left.func if isinstance(left, ast.Call) else None
            if isinstance(func, ast.Attribute) and func.attr == 'home':
                found.append((right.value, right.lineno))
    if len(found) != 1:
        raise AssertionError(f'data_dir() should join Path.home() to one relative default, got {found!r}')
    relative, line = found[0]
    if not relative or Path(relative).is_absolute() or relative.startswith(('/', '~')):
        raise AssertionError(f'default data directory is not a relative path: {relative!r}')
    return relative, line


class DataDirMentionTests(unittest.TestCase):
    def test_default_path_is_written_only_on_its_definition_line(self):
        relative, definition_line = default_from_source()
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / 'home'
            (home / relative).mkdir(parents=True)
            sys.path.insert(0, str(ROOT / 'bin'))
            import _aiwork_config
            previous = os.environ.get('HOME'), os.environ.get('AIWORK_DATA_DIR')
            os.environ['HOME'] = str(home)
            os.environ.pop('AIWORK_DATA_DIR', None)
            try:
                resolved = _aiwork_config.data_dir()
            finally:
                if previous[0] is None:
                    os.environ.pop('HOME', None)
                else:
                    os.environ['HOME'] = previous[0]
                if previous[1] is None:
                    os.environ.pop('AIWORK_DATA_DIR', None)
                else:
                    os.environ['AIWORK_DATA_DIR'] = previous[1]
            self.assertEqual(resolved, (home / relative).resolve())
            self.assertEqual(resolved.relative_to(home.resolve()).as_posix(), Path(relative).as_posix())

        hits = []
        for name in SCAN_ROOTS:
            root = ROOT / name
            for path in root.rglob('*'):
                if not path.is_file() or '__pycache__' in path.parts:
                    continue
                text = path.read_text(encoding='utf-8', errors='replace')
                for number, line in enumerate(text.splitlines(), 1):
                    if relative in line:
                        hits.append(f'{path.relative_to(ROOT).as_posix()}:{number}')
        allowed = f'bin/_aiwork_config.py:{definition_line}'
        self.assertEqual(hits, [allowed])

    def test_readme_local_settings_matches_the_code_default(self):
        relative, _line = default_from_source()
        readme = (ROOT / 'README.md').read_text(encoding='utf-8')
        section = readme.split('## 本机设置', 1)[1].split('\n## ', 1)[0]
        self.assertIn('~/' + Path(relative).as_posix(), section)


if __name__ == '__main__':
    unittest.main()

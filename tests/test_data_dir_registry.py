#!/usr/bin/env python3
"""Data-directory children are named once, and bin/ only reaches them through data-path."""
import ast
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'bin'
CONFIG = BIN / '_aiwork_config.py'
KINDS = ('工作产物', '运行目录', '其他')
DATA_ROOT_NAME = re.compile(r'\bDATA_ROOT\b')
SHELL_DATA_PATH = re.compile(
    r'''data-path\s+(?:"([^"]+)"|'([^']+)'|([A-Za-z0-9._/-]+))''')
PY_DATA_PATH = re.compile(r'''data_path\(\s*(['"])(.+?)\1''')


def registry_entries():
    """The table in bin/_aiwork_config.py, not a second copy of the names."""
    sys.path.insert(0, str(BIN))
    import _aiwork_config
    entries = getattr(_aiwork_config, 'DATA_ENTRIES', None)
    if not isinstance(entries, tuple) or not entries:
        raise AssertionError('bin/_aiwork_config.py 里没有登记表 DATA_ENTRIES')
    return entries


def python_source(path: Path, text: str) -> bool:
    """A file is Python when its suffix is .py, or its first line is a python shebang."""
    if path.suffix == '.py':
        return True
    first = text.splitlines()[0] if text.splitlines() else ''
    return first.startswith('#!') and 'python' in first


def child_uses(directory: Path):
    """Literal data-directory children reached from directory, plus DATA_ROOT identifiers."""
    uses = []
    identifiers = []
    for path in sorted(directory.iterdir()):
        if not path.is_file():
            continue
        text = path.read_text(encoding='utf-8')
        rel = path.relative_to(directory).as_posix()
        for lineno, line in enumerate(text.splitlines(), 1):
            if DATA_ROOT_NAME.search(line):
                identifiers.append(f'{rel}:{lineno}')
            for match in SHELL_DATA_PATH.finditer(line):
                raw = next(group for group in match.groups() if group)
                if raw[0] in '>|;&':
                    continue
                uses.append((rel, lineno, raw.split('/', 1)[0]))
        if python_source(path, text):
            for match in PY_DATA_PATH.finditer(text):
                raw = match.group(2)
                line = text[:match.start()].count('\n') + 1
                uses.append((rel, line, raw.split('/', 1)[0]))
    return uses, identifiers


class DataDirRegistryTest(unittest.TestCase):
    def test_bin_reaches_data_children_only_through_registered_data_path(self):
        uses, identifiers = child_uses(BIN)
        self.assertEqual(identifiers, [], 'bin/ 里不许出现 DATA_ROOT')
        names = {entry['name'] for entry in registry_entries()}
        unknown = [
            f'{rel}:{lineno}:{name}'
            for rel, lineno, name in uses
            if name not in names
        ]
        self.assertEqual(unknown, [])

    def test_registry_is_the_only_definition(self):
        entries = registry_entries()
        seen = []
        for entry in entries:
            self.assertEqual(set(entry), {'name', 'purpose', 'kind', 'keep_days'})
            if entry['keep_days'] is not None:
                self.assertIs(type(entry['keep_days']), int)
                self.assertGreater(entry['keep_days'], 0)
            name = entry['name']
            self.assertIsInstance(name, str)
            self.assertTrue(name)
            self.assertNotIn('/', name)
            self.assertIsInstance(entry['purpose'], str)
            self.assertTrue(entry['purpose'].strip())
            self.assertIn(entry['kind'], KINDS)
            seen.append(name)
        self.assertEqual(len(seen), len(set(seen)))
        tree = ast.parse(CONFIG.read_text(encoding='utf-8'))
        assigned = [
            node for node in tree.body
            if isinstance(node, ast.Assign)
            and any(isinstance(target, ast.Name) and target.id == 'DATA_ENTRIES'
                     for target in node.targets)
        ]
        self.assertEqual(len(assigned), 1)

    def test_data_path_still_accepts_an_unregistered_name(self):
        sys.path.insert(0, str(BIN))
        import _aiwork_config
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp) / 'data'
            data.mkdir()
            old = os.environ.get('AIWORK_DATA_DIR')
            os.environ['AIWORK_DATA_DIR'] = str(data)
            try:
                got = _aiwork_config.data_path('not-a-registered-name')
            finally:
                if old is None:
                    os.environ.pop('AIWORK_DATA_DIR', None)
                else:
                    os.environ['AIWORK_DATA_DIR'] = old
        self.assertEqual(got, data / 'not-a-registered-name')

    def test_unsuffixed_python_shebang_is_scanned(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tool = root / 'tool'
            tool.write_text('#!/usr/bin/env python3\nvalue = data_path("not-registered")\n')
            uses, identifiers = child_uses(root)
        self.assertEqual(identifiers, [])
        self.assertIn(('tool', 2, 'not-registered'), uses)


if __name__ == '__main__':
    unittest.main()

"""Program bindings win over PATH, and invalid bindings fail before side effects."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: F401,E402

from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProgramPaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.config = self.root / 'settings'
        self.programs = self.config / 'programs'
        self.programs.mkdir(parents=True)
        self.data = self.root / 'data'
        self.data.mkdir()
        self.marker = self.root / 'used'
        self.bind('python3', sys.executable)
        self.env = dict(os.environ, AIWORK_CONFIG_DIR=str(self.config),
                        AIWORK_DATA_DIR=str(self.data))

    def bind(self, name, target):
        path = self.programs / name
        path.unlink(missing_ok=True)
        path.symlink_to(target)

    def script(self, name, body):
        path = self.root / name
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)
        return path

    def call(self, name, *args):
        return subprocess.run([str(ROOT / 'bin' / name), *map(str, args)],
                              env=self.env, capture_output=True, text=True, timeout=15)

    def test_python_binding_wins_over_path_including_symlink_entry(self):
        probe = 'import sys; sys.version_info=(3,11,0); sys.version="3.11.0"; exec(sys.argv[2])'
        selected = self.script('selected python', 'printf selected >> ' + shlex.quote(str(self.marker))
                               + '\nif [ "$1" = -c ]; then\nexec ' + shlex.quote(sys.executable)
                               + ' -c ' + shlex.quote(probe) + ' "$@"\nfi\nexec '
                               + shlex.quote(sys.executable) + ' "$@"\n')
        self.bind('python3', selected)
        wrong = self.root / 'wrong'
        wrong.mkdir()
        (wrong / 'python3').write_text('#!/bin/sh\necho wrong-python >&2\nexit 99\n')
        (wrong / 'python3').chmod(0o755)
        self.env['PATH'] = str(wrong) + os.pathsep + self.env['PATH']
        alias = self.root / 'config-alias'
        alias.symlink_to(ROOT / 'bin/aiwork-config')
        config_alias = self.root / 'settings-alias'
        config_alias.symlink_to(self.config, target_is_directory=True)
        for configured in (str(self.config), '~/settings', str(config_alias)):
            with self.subTest(configured=configured):
                result = subprocess.run([str(alias), 'data-path'],
                                        env=dict(self.env, AIWORK_CONFIG_DIR=configured, HOME=str(self.root)),
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), str(self.data))
                self.assertIn('selected', self.marker.read_text())
                reported = subprocess.run([str(alias), 'path', 'models.env'],
                                          env=dict(self.env, AIWORK_CONFIG_DIR=configured, HOME=str(self.root)),
                                          capture_output=True, text=True, timeout=15)
                self.assertEqual(reported.returncode, 0, reported.stderr)
                expected = self.config if configured == '~/settings' else Path(configured)
                self.assertEqual(reported.stdout.strip(), str(expected / 'models.env'))

    def test_invalid_python_refuses_all_executable_python_entries_before_help(self):
        entries = [p.name for p in (ROOT / 'bin').iterdir()
                   if p.is_file() and os.access(p, os.X_OK) and p.read_bytes().startswith((b'#!/usr/bin/env python3', b'#!/bin/sh\n"""exec"'))]
        self.assertTrue(entries)
        old = self.script('old-python', 'exec ' + shlex.quote(sys.executable)
                          + " -c 'import sys; sys.version_info=(3,9,6); sys.version=\"3.9.6\"; exec(sys.argv[2])' \"$@\"\n")
        old310 = self.script('old-python-310', 'exec ' + shlex.quote(sys.executable)
                             + " -c 'import sys; sys.version_info=(3,10,14); sys.version=\"3.10.14\"; exec(sys.argv[2])' \"$@\"\n")
        nonexec = self.root / 'not-executable'
        nonexec.write_text('broken')
        for target in (None, self.root / 'absent', nonexec, self.root, Path('/bin/true'), old, old310):
            for entry in entries:
                with self.subTest(target=target, entry=entry):
                    (self.programs / 'python3').unlink(missing_ok=True)
                    if target is not None:
                        self.bind('python3', target)
                    result = self.call(entry, '--help')
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn('programs/python3', result.stderr)
                    self.assertNotIn('Traceback', result.stderr)
                    if target in (old, old310):
                        self.assertIn('3.9.6' if target == old else '3.10.14', result.stderr)
                        self.assertIn('3.11', result.stderr)
        self.assertEqual(list(self.data.iterdir()), [])

    def leg_fixture(self):
        from test_leg_finish import LegFinish
        fixture = LegFinish(methodName='runTest')
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        # Use a disposable platform probe and execution wrapper so every named
        # program's dispatch is tested on both CI hosts, inside the real guard.
        for source in (ROOT / 'bin').iterdir():
            if source.is_file():
                shutil.copy2(source, fixture.bin / source.name)
        platform = fixture.bin / '_review-platform.sh'
        import re
        platform.write_text(re.sub(r'review_platform_is_macos\(\) \{[^}]*\}',
                                    'review_platform_is_macos() { return 1; }', platform.read_text()))
        fixture._write('ro-repo-exec', '#!/bin/sh\nshift 2\nexec "$@"\n')
        fixture._write('unshare', '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\nexec "$@"\n')
        return fixture

    def test_each_cli_binding_wins_over_path_and_codex_override(self):
        fixture = self.leg_fixture()
        for name, leg in (('codex', 'subcodex'), ('cursor-agent', 'subcursor'),
                          ('kimi', 'subkimi'), ('mimo', 'submimo'), ('claude', 'subagent')):
            with self.subTest(program=name):
                self.marker.unlink(missing_ok=True)
                target = self.script('selected-' + name, 'echo ' + name + ' > '
                                     + shlex.quote(str(self.marker)) + '\nexit 97\n')
                self.bind(name, target)
                self.bind('node', shutil.which('node'))
                wrong = fixture.bin / name
                wrong.write_text('#!/bin/sh\necho wrong-' + name + ' >&2\nexit 99\n')
                wrong.chmod(0o755)
                # Fixture credentials/hooks/models remain disposable too.
                shutil.copy2(fixture.root / 'settings/models.env', self.config / 'models.env')
                hook = fixture.root / 'kimi-home/config.toml'
                import re
                hook.write_text(re.sub(r'command = .*', 'command = ' + __import__('json').dumps(shlex.quote(str(self.programs / 'node')) + ' ' + shlex.quote(str(fixture.root / 'kimi-home/hooks/guard.mjs'))), hook.read_text()))
                env = dict(fixture._env(), AIWORK_CONFIG_DIR=str(self.config), AIWORK_DATA_DIR=str(self.data))
                env['PATH'] = str(fixture.bin) + os.pathsep + os.environ['PATH']
                env['CODEX_BIN'] = str(wrong)
                args = [str(fixture.bin / leg)] + (['deepseek'] if leg == 'subagent' else [])
                result = subprocess.run(args + ['review', str(fixture.root / 'task.md'),
                                               str(self.root / 'leg.log'), str(fixture.repo)],
                                        env=env, capture_output=True, text=True, timeout=20)
                self.assertTrue(self.marker.exists(), result.stdout + result.stderr)
                self.assertEqual(self.marker.read_text().strip(), name)
                self.assertNotIn('wrong-' + name, result.stderr)

    def test_invalid_cli_bindings_refuse_before_workspace_or_credentials(self):
        fixture = self.leg_fixture()
        nonexec = self.root / 'nonexec'
        nonexec.touch()
        for name, leg in (('codex', 'subcodex'), ('cursor-agent', 'subcursor'),
                          ('kimi', 'subkimi'), ('mimo', 'submimo'), ('claude', 'subagent'),
                          ('node', 'subkimi'), ('node', 'review-pr')):
            for target in (None, self.root / 'absent', nonexec):
                with self.subTest(program=name, target=target, entry=leg):
                    for other in ('codex', 'cursor-agent', 'kimi', 'mimo', 'claude', 'node'):
                        self.bind(other, '/bin/true')
                    (self.programs / name).unlink()
                    if target is not None:
                        self.bind(name, target)
                    env = dict(self.env, REVIEW_WORKSPACE_BASE=str(self.root / 'must-not-exist'))
                    result = subprocess.run([str(fixture.bin / leg), '--help'],
                                            env=env, capture_output=True, text=True, timeout=15)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('programs/' + name, result.stderr)
                    self.assertFalse((self.root / 'must-not-exist').exists())
                    self.assertEqual(list(self.data.iterdir()), [])


    def test_review_and_explore_check_selected_cli_before_other_work(self):
        for name in ('codex', 'node'):
            self.bind(name, '/bin/true')
        self.bind('codex', self.root / 'absent-codex')
        for entry, args in (('review-pr', ['1', '--repo', 'fixture/repo']),
                            ('explore', [str(self.root / 'absent-brief'), '--repo',
                                         str(self.root / 'absent-repo'), '--leg', 'subcodex'])):
            with self.subTest(entry=entry):
                result = self.call(entry, *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('programs/codex', result.stderr)
                self.assertEqual(result.stdout, '')
                self.assertEqual(list(self.data.iterdir()), [])

    def test_fixture_settings_survive_a_nested_temporary_directory(self):
        from _test_settings import write_settings
        write_settings(self.config)
        before = {p.name: os.readlink(p) for p in self.programs.iterdir() if p.is_symlink()}
        nested = self.root / 'nested-tmp'
        nested.mkdir()
        result = subprocess.run([sys.executable, str(ROOT / 'tests/_test_settings.py'),
                                 'run-with-programs', '/bin/true'],
                                env=dict(self.env, TMPDIR=str(nested),
                                         AIWORK_TEST_FIXTURE_ROOT=str(self.root)),
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({p.name: os.readlink(p) for p in self.programs.iterdir() if p.is_symlink()}, before)

    def test_ci_selector_uses_configured_node_over_path(self):
        node = self.script('selected node', 'echo selected > ' + shlex.quote(str(self.marker))
                           + '\nexec ' + shlex.quote(shutil.which('node')) + ' "$@"\n')
        self.bind('node', node)
        wrong = self.root / 'wrong'
        wrong.mkdir()
        (wrong / 'node').write_text('#!/bin/sh\nexit 99\n')
        (wrong / 'node').chmod(0o755)
        self.env['PATH'] = str(wrong) + os.pathsep + self.env['PATH']
        source = ('import sys;sys.path.insert(0,sys.argv[1]);import _review_ci;'
                  'print(_review_ci.select_run([], "a"*40, {}, 1, 10))')
        result = subprocess.run([sys.executable, '-c', source, str(ROOT / 'bin')],
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.marker.exists(), result.stdout)

    def test_env_shebang_uses_configured_node_and_relative_settings_survive_chdir(self):
        fixture = self.leg_fixture()
        node = self.script('selected node', 'echo selected > ' + shlex.quote(str(self.marker))
                           + '\nexec ' + shlex.quote(shutil.which('node')) + ' "$@"\n')
        self.bind('node', node)
        cli = self.root / 'javascript-cli'
        cli.write_text('''#!/usr/bin/env node
const args = process.argv.slice(2);
if (args[0] === "debug") {
  console.log(args[1] === "models" ? '{"models":[{"slug":"gpt-6-sol"}]}' : 'ok');
} else {
  const fs = require('node:fs');
  fs.writeFileSync(args[args.indexOf('-o') + 1], 'chosen CLI\\nConclusion: PASS\\n');
  console.log('{"type":"thread.started","model":"gpt-6-sol"}');
}
''')
        cli.chmod(0o755)
        self.bind('codex', cli)
        shutil.copy2(fixture.root / 'settings/models.env', self.config / 'models.env')
        env = dict(fixture._env(), AIWORK_CONFIG_DIR='settings', AIWORK_DATA_DIR=str(self.data),
                   FINISH_CASE='pass')
        result = subprocess.run([str(fixture.bin / 'subcodex'), 'review',
                                 str(fixture.root / 'task.md'), str(self.root / 'leg.log'), str(fixture.repo)],
                                cwd=self.root, env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('chosen CLI', (self.root / 'leg.log').read_text())
        self.assertTrue(self.marker.exists())


if __name__ == '__main__':
    unittest.main()

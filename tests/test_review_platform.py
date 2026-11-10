#!/usr/bin/env python3
"""Linux admission, source protection and Codex output isolation."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

from pathlib import Path
import json
import shutil
import subprocess
import unittest

import test_leg_finish as finish
from test_reader_tool_audit import KIMI_READ, MIMO_READ

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bin'))
from _paths import inside

LEGS = ('subcodex', 'subdeepseek-agent', 'subcursor', 'subkimi', 'submimo')


class PlatformRoutes(unittest.TestCase):
    def setUp(self):
        self.fixture = finish.LegFinish(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.root, self.bin = self.fixture.root, self.fixture.bin
        # Copy only production files: retain the provider CLI stubs from LegFinish.
        for source in (ROOT / 'bin').iterdir():
            if source.is_file():
                shutil.copy2(source, self.bin / source.name)
        self.marker = self.root / 'ro-called'
        self.fixture._write('ro-repo-exec', r'''#!/usr/bin/env python3
import os, pathlib, sys
pathlib.Path(os.environ['RO_MARKER']).write_text('\n'.join(sys.argv[1:]))
raise SystemExit(86)
''')
        for cli, stream in (('kimi', KIMI_READ), ('claude', MIMO_READ)):
            self.fixture._write(cli, '#!/usr/bin/env python3\nimport json,sys\nstream=' + repr(stream) + '\n' +
                "for line in stream.splitlines():\n e=json.loads(line)\n if e.get('type')=='system' and '--tools' in sys.argv:e['tools']=sys.argv[sys.argv.index('--tools')+1].split(',')\n print(json.dumps(e))\n")

    def run_leg(self, leg, mode, linux=True, **extra):
        from _test_settings import write_platform_probe
        write_platform_probe(self.bin, linux=linux)
        env = self.fixture._env()
        env.update(RO_MARKER=str(self.marker), FINISH_CASE='pass',
                   AIWORK_REVIEW_REPORT_PATH=str(self.root / 'report.md'),
                   AIWORK_REVIEW_FACTS_PATH=str(self.root / 'facts.json'),
                   AIWORK_REVIEW_RESULT_BIN=str(self.bin / '_review_result.py'))
        env.update(extra)
        return subprocess.run(
            [str(self.bin / leg), mode, str(self.root / 'task.md'),
             str(self.root / 'logs/leg.log'), str(self.fixture.repo)],
            capture_output=True, text=True, env=env, timeout=30)

    def test_codex_sandbox_only_work_copy_in_both_modes(self):
        for mode in ('review', 'explore'):
            with self.subTest(mode=mode):
                result = self.run_leg('subcodex', mode)
                self.assertTrue(self.marker.exists(), result.stderr)
                args = self.marker.read_text().splitlines()
                cwd = args[args.index('-C') + 1]
                self.assertEqual(args[args.index('-s') + 1], 'workspace-write')
                config = dict(arg.split('=', 1) for i, arg in enumerate(args)
                              if i and args[i - 1] == '-c')
                expected = {
                    'sandbox_workspace_write.writable_roots': '[]',
                    'sandbox_workspace_write.exclude_slash_tmp': 'true',
                    'sandbox_workspace_write.exclude_tmpdir_env_var': 'true',
                    'sandbox_workspace_write.network_access': 'false',
                    'approval_policy': 'never',
                }
                for key, value in expected.items():
                    self.assertEqual(config.get(key), value, key)
                self.assertEqual(json.loads(config['shell_environment_policy.set.TMPDIR']), cwd)
                self.assertNotIn('--add-dir', args)
                self.assertNotEqual(Path(cwd), self.fixture.repo.resolve())
                last_message = Path(args[args.index('-o') + 1])
                self.assertEqual(inside(cwd, str(last_message), literal=False)[0], 1)

    def test_nonlinux_legs_refuse_before_any_preparation(self):
        unexpected = self.root / 'prepared'
        poison = '''#!/usr/bin/env python3
import os, pathlib
pathlib.Path(os.environ['PREP_MARKER']).write_text('called')
raise SystemExit(95)
'''
        for name in ('git', 'mkdir', 'mktemp', 'cp', 'realpath', 'aiwork-config',
                     'codex', 'claude', 'cursor-agent'):
            self.fixture._write(name, poison)
        for leg in LEGS:
            for mode in ('review', 'explore'):
                with self.subTest(leg=leg, mode=mode):
                    result = self.run_leg(leg, mode, False, PREP_MARKER=str(unexpected),
                                          AIWORK_DATA_DIR=str(self.root / 'absent-data'))
                    self.assertEqual(result.returncode, 78, result.stderr)
                    self.assertIn('仅支持 Linux', result.stderr)
                    self.assertFalse(unexpected.exists())
                    self.assertFalse(self.marker.exists())
                    self.assertFalse((self.root / 'logs').exists())
                    self.assertFalse((self.root / 'absent-data').exists())

    def _codex_output_attack(self, attack):
        # The CLI is outside its command sandbox. Model actions below only
        # create links in the work copy; the later CLI write follows links.
        self.fixture._write('ro-repo-exec', r'''#!/usr/bin/env python3
import os, sys
args = sys.argv[sys.argv.index('--') + 1:]
os.execv(args[0], args)
''')
        self.fixture._write('codex', r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
args = sys.argv[1:]
if args[:2] == ['debug', 'models']:
    print(json.dumps({'models': [{'slug': 'gpt-6-sol'}]}))
    raise SystemExit(0)
if args[:2] == ['debug', 'prompt-input']:
    print('ok')
    raise SystemExit(0)
cwd = pathlib.Path.cwd()
out = pathlib.Path(args[args.index('-o') + 1])
config = dict(arg.split('=', 1) for i, arg in enumerate(args)
              if i and args[i - 1] == '-c')
scratch = pathlib.Path(json.loads(config.get('shell_environment_policy.set.TMPDIR',
                                           json.dumps(os.environ['TMPDIR']))))
sys.path.insert(0, str(pathlib.Path(sys.argv[0]).parent))
from _paths import inside
assert inside(str(cwd), str(scratch), literal=False)[0] == 0
attack = os.environ['OUTPUT_ATTACK']
if attack == 'clean':
    subprocess.run(['git', 'clean', '-fd'], check=True, stdout=subprocess.DEVNULL)
else:
    # Include a link to the output itself, and the original TMPDIR attack.
    # Neither link's target needs to be writable by the model.
    (cwd / 'cli-output-link').symlink_to(out)
    (scratch / 'last-message.md').symlink_to(os.environ['ATTACK_TARGET'])
    print(json.dumps({'model_link_created': True}))
if attack == 'read':
    raise SystemExit(1)  # CLI never wrote -o; wrapper must not read the link.
out.write_text('Conclusion: PASS\n')
''')
        target = self.root / 'outside-synthetic.txt'
        secret = 'SYNTHETIC_OUTSIDE_CONTENT_63\n'
        for mode in ('review', 'explore'):
            with self.subTest(attack=attack, mode=mode):
                target.write_text(secret)
                result = self.run_leg('subcodex', mode,
                                      OUTPUT_ATTACK=attack, ATTACK_TARGET=str(target),
                                      SUBCODEX_TIMEOUT='5')
                report = self.root / 'report.md'
                artifacts = [result.stdout, result.stderr]
                artifacts += [p.read_text() for p in (self.root / 'logs').iterdir()]
                if report.exists():
                    artifacts.append(report.read_text())
                if attack != 'clean':
                    self.assertIn('"model_link_created": true',
                                  (self.root / 'logs/leg.stream.jsonl').read_text())
                self.assertEqual(target.read_text(), secret, 'CLI overwrote outside file')
                self.assertTrue(all(secret.strip() not in text for text in artifacts),
                                'outside content leaked into logs/report')
                self.assertEqual(result.returncode, 1 if attack == 'read' else 0,
                                 result.stderr)
                if attack != 'read':
                    self.assertEqual(report.read_text(), 'Conclusion: PASS\n')

    def test_codex_output_cannot_overwrite_model_symlink_target(self):
        self._codex_output_attack('write')

    def test_codex_missing_output_cannot_read_model_symlink_target(self):
        self._codex_output_attack('read')

    def test_codex_output_survives_git_clean(self):
        self._codex_output_attack('clean')

    def test_linux_all_five_legs_use_ro_wrapper_in_both_modes(self):
        for leg in LEGS:
            for mode in ('review', 'explore'):
                with self.subTest(leg=leg, mode=mode):
                    self.marker.unlink(missing_ok=True)
                    result = self.run_leg(leg, mode)
                    self.assertTrue(self.marker.is_file(), result.stderr)
                    args = self.marker.read_text().splitlines()
                    self.assertEqual(args[:2], [str(self.fixture.repo.resolve()), '--'])
                    self.assertIn(str((self.bin / 'aiwork-timeout').resolve()), args)
                    self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()

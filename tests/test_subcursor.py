#!/usr/bin/env python3
"""Offline Cursor adapter/dispatch checks; never invoke a real provider."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import concurrent.futures
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from _test_settings import write_settings, set_model

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bin'))
spec = importlib.util.spec_from_file_location("cursor_stream", ROOT / "bin/_cursor-stream.py")
decoder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(decoder)

FAKE = r'''#!/usr/bin/env python3
import json, os, pathlib, sys, time
a = sys.argv[1:]
catalog = {
    'composer-2.5':'Composer 2.5', 'composer-2.6':'Composer 2.6',
    'composer-2.7':'Composer 2.7', 'opus-4.6':'Claude Opus 4.6',
    'gpt-5.6':'GPT-5.6', 'gemini-3.8-flash':'Gemini 3.8 Flash',
    'grok-4.6':'Grok 4.6', 'cursor-grok-4.6-high':'Cursor Grok 4.6 High',
    'gpt-5.6-sol-xhigh':'GPT-5.6 Sol 1M Extra High',
}
def arg(k): return a[a.index(k)+1]
model = arg('--model')
home = pathlib.Path(os.environ['HOME'])
cwd = pathlib.Path.cwd()
repo = pathlib.Path(arg('--add-dir'))
assert cwd == pathlib.Path(arg('--workspace'))
assert cwd != repo and cwd.parent == repo.parent == home.parent
assert {p.name for p in cwd.iterdir()} == {'review.diff'}
diff=(cwd/'review.diff').read_text()
assert '-original' in diff and '+changed' in diff and '+untracked' in diff
assert pathlib.Path(os.environ['CURSOR_CONFIG_DIR']) == home/'.cursor'
assert pathlib.Path(os.environ['XDG_CONFIG_HOME']) == home/'.config'
assert arg('--mode') == 'ask'
assert arg('--allowed-tools') == 'read_tool_call,grep_tool_call,glob_tool_call,ls_tool_call'
assert '--disable-auto-update' in a and '--disable-project-configs' in a
assert '--exclude-workspace-context' not in a and '--print' in a
assert '--force' not in a and '--approve-mcps' not in a
assert '--trust' in a  # disposable roots only; not tool auto-approval
assert arg('--output-format') == 'stream-json'
if 'CURSOR_API_KEY' not in os.environ:
    auth = home/'.config/cursor/auth.json'
    assert not auth.exists()
    assert os.environ.get('CURSOR_AUTH_TOKEN') == 'fake-access'
assert (repo/'tracked.txt').read_text() == 'changed\n'
assert (repo/'untracked.txt').read_text() == 'untracked\n'
try:
    (pathlib.Path(os.environ['FAKE_SOURCE'])/'SOURCE_LEAK').write_text('bad')
except OSError:
    pass
else:
    raise SystemExit('source repository was writable')
prompt = sys.stdin.read()
assert str(repo) in prompt
case = os.environ.get('FAKE_CASE', '')
if case in ('daemon', 'daemon_timeout'):
    import subprocess
    # Cursor's worker can outlive the CLI and write after workspace cleanup.
    # Detach so killing only the CLI's process group cannot pass this test.
    marker = str(pathlib.Path(os.environ['FAKE_RECORD']).with_suffix('.escaped'))
    release = str(pathlib.Path(os.environ['FAKE_RECORD']).with_suffix('.released'))
    child = ('import pathlib,time\n'
             + 'gate=pathlib.Path(' + repr(release) + ')\n'
             + 'for _ in range(2000):\n'
             + ' if gate.exists():\n'
             + '  pathlib.Path(' + repr(marker) + ').write_text("orphan"); break\n'
             + ' time.sleep(0.01)\n')
    subprocess.Popen([sys.executable, '-c', child], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)
record = {'model':model, 'cwd':str(repo), 'home':str(home), 'prompt':prompt,
          'cursor_env':{k:v for k,v in os.environ.items() if k.startswith('CURSOR_')}}
pathlib.Path(os.environ['FAKE_RECORD']).write_text(json.dumps(record))
def emit(e):
    e.setdefault('session_id','fixture-session')
    print(json.dumps(e), flush=True)
emit({'type':'system','subtype':'init','model':catalog[model] if case!='model' else 'Claude Opus'})
emit({'type':'tool_call','subtype':'completed','tool_call':{'readToolCall':{'result':{'success':{'content':'Conclusion: PASS'}}}}})
text = 'Verified tracked.txt:1 against the task.\nConclusion: BLOCK'
if 'Propose exactly ONE concrete direction' in prompt:
    text = '\n'.join(x+': concrete proposal' for x in ('Direction','Core bet','How it works',
        'Best at','Sacrifices','Blind spots in the brief','Smallest first step'))
if case=='empty': text=''
if case=='no_verdict': text='Review has evidence but no decision.'
if case=='bad_explore': text='Direction: only one section'
if case=='markdown_explore':
    text = '\n'.join('- **'+line.split(':',1)[0]+'**:'+line.split(':',1)[1]
                     for line in text.splitlines())
emit({'type':'assistant','message':{'role':'assistant','content':[{'type':'text','text':text}]}})
if case in ('timeout', 'daemon_timeout'): time.sleep(20)
if case=='truncated': raise SystemExit(0)
if case=='malformed': print('{broken',flush=True)
emit({'type':'result','subtype':'error' if case=='cancelled' else 'success',
      'is_error':case=='is_error','result':text,
      'session_id':'wrong' if case=='session' else 'fixture-session'})
if case=='duplicate': emit({'type':'result','subtype':'success','is_error':False,'result':text})
if case=='exit': raise SystemExit(42)
'''


class CursorTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.d = Path(self.tmp.name)
        self.config = write_settings(self.d / 'settings')
        self.bin = self.d/'bin'; self.bin.mkdir()
        for name in ('subcursor','aiwork-config', '_aiwork_config.py','_cursor-stream.py','_review-workspace.sh',
                     '_review_result.py','_my-review-gate.sh',
                     'ro-repo-exec','panel-explore','panel-review','_panel-roster-lib.sh'):
            shutil.copy2(ROOT/'bin'/name, self.bin/name)
        set_model(self.config, 'cursor', ('composer-2.5\n').strip())
        self.fake = self.d/'fake'; self.fake.mkdir()
        (self.fake/'cursor-agent').write_text(FAKE); (self.fake/'cursor-agent').chmod(0o755)
        self.repo = self.d/'source'; self.repo.mkdir()
        self.git('init','-q'); self.git('config','user.name','test')
        self.git('config','user.email','test@example.invalid')
        (self.repo/'tracked.txt').write_text('original\n')
        self.git('add','.'); self.git('commit','-qm','base')
        (self.repo/'tracked.txt').write_text('changed\n')
        (self.repo/'untracked.txt').write_text('untracked\n')
        self.task = self.d/'task.md'; self.task.write_text('Inspect tracked.txt and propose or review.\n')
        self.auth = self.d/'auth.json'; self.auth.write_text(json.dumps({'accessToken':'fake-access','refreshToken':'never-copy','apiKey':'never-copy'}))
        self.env = {k:v for k,v in os.environ.items()
                    if not k.startswith(('CURSOR_',)) and k != 'CURSOR_API_KEY'}
        self.env.update(AIWORK_CONFIG_DIR=str(self.config), PATH=str(self.fake)+os.pathsep+os.environ['PATH'],
            CURSOR_AUTH_FILE=str(self.auth), REVIEW_NO_MY_REVIEW='1',
            REVIEW_WORKSPACE_BASE=str(self.d/'workspaces'),
            AIWORK_REVIEW_RESULT_BIN=str(self.bin/'_review_result.py'),
            FAKE_SOURCE=str(self.repo), FAKE_RECORD=str(self.d/'record.json'),
            PANEL_STAGGER_MAX='0', PANEL_STATE_DIR=str(self.d/'state'))

    def git(self, *args):
        return subprocess.check_output(['git','-C',str(self.repo),*args],stderr=subprocess.DEVNULL).decode()

    def run_leg(self, mode='review', case='', tag='leg', extra=None):
        env = dict(self.env, FAKE_CASE=case,
                   FAKE_RECORD=str(self.d/(tag+'.record.json')),
                   AIWORK_REVIEW_FACTS_PATH=str(self.d/(tag+'.facts.json')))
        env.update(extra or {})
        result = subprocess.run([str(self.bin/'subcursor'),mode,str(self.task),
            str(self.d/(tag+'.log')),str(self.repo)],env=env,capture_output=True,text=True,timeout=35)
        self.assertFalse((self.repo/'SOURCE_LEAK').exists())
        self.assertEqual((self.repo/'tracked.txt').read_text(),'changed\n')
        return result

    def test_review_reads_dirty_snapshot_protects_source_and_cleans_home(self):
        result = self.run_leg()
        self.assertEqual(result.returncode,0,result.stderr)
        record = json.loads((self.d/'leg.record.json').read_text())
        self.assertFalse(Path(record['home']).exists())
        self.assertFalse(Path(record['cwd']).exists())
        report = (self.d/'leg.log').read_text()
        self.assertIn('Conclusion: BLOCK',report)
        self.assertNotIn('Conclusion: PASS',report)
        # review-pr separates the model's report at the end of this header.
        self.assertTrue(report.startswith('# subcursor review log\n'),report[:80])
        self.assertIn('Conclusion: BLOCK',report.split('\n\n',1)[1])
        facts = json.loads((self.d/'leg.facts.json').read_text())
        self.assertEqual(facts['verdict'],'BLOCK')
        self.assertEqual(facts['evidence_completeness'],'complete')
        self.assertEqual(facts['view']['delivery_state'],'complete')

    def test_caller_cursor_env_does_not_reach_cli(self):
        result = self.run_leg(extra={'CURSOR_API_ENDPOINT':'https://invalid.example',
            'CURSOR_AUTH_TOKEN':'never-copy', 'CURSOR_ENABLE_LOCAL_BEDROCK':'1',
            'CURSOR_STATSIG_OVERRIDES':'{}', 'CURSOR_CONFIG_DIR':'/nonexistent'})
        self.assertEqual(result.returncode,0,result.stderr)
        env = json.loads((self.d/'leg.record.json').read_text())['cursor_env']
        self.assertEqual(set(env), {'CURSOR_CONFIG_DIR','CURSOR_DATA_DIR','CURSOR_AUTH_TOKEN'})
        self.assertEqual(env['CURSOR_AUTH_TOKEN'], 'fake-access')

    def test_model_upgrade_changes_only_config_for_both_modes(self):
        set_model(self.config, 'cursor', ('composer-2.6\n').strip())
        for mode in ('review','explore'):
            result = self.run_leg(mode, tag=mode)
            self.assertEqual(result.returncode,0,result.stderr)
            record = json.loads((self.d/(mode+'.record.json')).read_text())
            self.assertEqual(record['model'],'composer-2.6')
        result = self.run_leg(extra={'CURSOR_MODEL':'composer-2.7'})
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads((self.d/'leg.record.json').read_text())['model'],'composer-2.7')

    def test_empty_or_failed_or_wrong_model_never_succeeds(self):
        for case in ('empty','no_verdict','session','duplicate','truncated','malformed','model','exit','cancelled','is_error'):
            with self.subTest(case=case):
                result = self.run_leg(case=case)
                self.assertNotEqual(result.returncode,0)
                facts = json.loads((self.d/'leg.facts.json').read_text())
                self.assertEqual(facts['evidence_completeness'],'partial')

    def test_background_workers_end_with_success_or_timeout(self):
        import time
        for case, expected in (('daemon', 0), ('daemon_timeout', 124)):
            with self.subTest(case=case):
                result = self.run_leg(case=case, tag=case,
                                      extra={'CURSOR_TIMEOUT': '1'})
                self.assertEqual(result.returncode, expected, result.stderr)
                (self.d/(case+'.record.released')).touch()
                time.sleep(0.3)
                self.assertFalse((self.d/(case+'.record.escaped')).exists(),
                                 'background worker survived the adapter')

    def test_timeout_preserves_report_without_coverage(self):
        result = self.run_leg(case='timeout',extra={'CURSOR_TIMEOUT':'1'})
        self.assertEqual(result.returncode,124,result.stderr)
        self.assertIn('Conclusion: BLOCK',(self.d/'leg.log').read_text())
        facts = json.loads((self.d/'leg.facts.json').read_text())
        self.assertEqual(facts['process_state'],'timed_out')
        self.assertEqual(facts['evidence_completeness'],'partial')

    def test_explore_requires_sections_but_no_verdict(self):
        result = self.run_leg('explore')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertNotIn('Conclusion:',(self.d/'leg.log').read_text())
        self.assertNotEqual(self.run_leg('explore',case='bad_explore').returncode,0)

    def test_explore_accepts_markdown_section_labels(self):
        result = self.run_leg('explore',case='markdown_explore')
        self.assertEqual(result.returncode,0,result.stderr)

    def test_gate_and_missing_isolation_stop_before_cli(self):
        result = self.run_leg(extra={'REVIEW_NO_MY_REVIEW':'0','REVIEW_MY_REVIEW':str(self.d/'absent')})
        self.assertNotEqual(result.returncode,0)
        self.assertFalse((self.d/'leg.record.json').exists())
        (self.bin/'ro-repo-exec').unlink()
        result = self.run_leg()
        self.assertEqual(result.returncode,78)
        self.assertFalse((self.d/'leg.record.json').exists())

    def test_concurrent_legs_do_not_share_home_or_clone(self):
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            futures=[pool.submit(self.run_leg,tag=tag) for tag in ('one','two')]
            for f in futures:
                result=f.result(); self.assertEqual(result.returncode,0,result.stderr)
        records=[json.loads((self.d/(tag+'.record.json')).read_text()) for tag in ('one','two')]
        self.assertNotEqual(records[0]['home'],records[1]['home'])
        self.assertNotEqual(records[0]['cwd'],records[1]['cwd'])

    def test_panel_review_records_xai_coverage(self):
        env=dict(self.env,PANEL_MIMO_LEG='off',PANEL_DEEPSEEK_LEG='off',PANEL_GLM_LEG='off',
                 PANEL_KIMI_LEG='off',PANEL_GEMINI_LEG='off',PANEL_CURSOR_LEG='agent',PANEL_GROK_LEG='off')
        prefix=self.d/'panel'
        result=subprocess.run([str(self.bin/'panel-review'),'--no-my-review',
            '--budget','1',str(self.task),str(self.repo),str(prefix)],env=env,
            capture_output=True,text=True,timeout=35)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        result_path=self.d/'panel.subcursor.result.json'
        data=json.loads(result_path.read_text())
        self.assertEqual(data['family'],'cursor')
        self.assertEqual(data['adapter'],'subcursor')
        sys.path.insert(0,str(ROOT/'bin'))
        from _review_result import coverage_eligible
        self.assertTrue(coverage_eligible(data),data)

    def test_explore_dispatch_success_failure_and_off(self):
        # Other providers intentionally fail: only Cursor can make this run succeed.
        for name in ('submimo','subdeepseek-agent','subdeepseek','subglm-agent','subglm','subgrok'):
            p=self.bin/name; p.write_text('#!/bin/sh\nexit 1\n'); p.chmod(0o755)
        for switch,case,expected in (('agent','',0),('agent','exit',1),('off','',1)):
            with self.subTest(switch=switch,case=case):
                prefix=self.d/('explore-'+switch+case)
                result=subprocess.run([str(self.bin/'panel-explore'),str(self.task),str(self.repo),str(prefix)],
                    env=dict(self.env,PANEL_CURSOR_LEG=switch,PANEL_GROK_LEG='off',FAKE_CASE=case),
                    capture_output=True,text=True,timeout=35)
                self.assertEqual(result.returncode,expected,result.stdout+result.stderr)
                if switch=='off': self.assertFalse(Path(str(prefix)+'.subcursor.log').exists())
                else: self.assertIn('subcursor rc=',result.stdout)

    def test_decoder_rejects_tool_and_child_verdicts(self):
        events=[{'type':'system','subtype':'init','model':'Composer 2.5'},
            {'type':'assistant','parent_tool_use_id':'child',
             'message':{'role':'assistant','content':[{'type':'text','text':'Conclusion: PASS'}]}},
            {'type':'tool_call','tool_call':{'result':'Conclusion: PASS'}},
            {'type':'result','subtype':'success','is_error':False,'result':'Conclusion: PASS'}]
        for event in events: event['session_id']='s'
        report=io.StringIO()
        summary=decoder.consume(map(json.dumps,events),report,'composer-2.5')
        self.assertFalse(summary['success'])
        self.assertEqual(report.getvalue(),'')

    def test_recorded_live_stream_checks_family_without_inventing_model_id(self):
        lines=(ROOT/'tests/fixtures/cursor-stream.jsonl').read_text().splitlines()
        report=io.StringIO()
        summary=decoder.consume(lines,report,'composer-2.5')
        self.assertTrue(summary['success'],summary)
        self.assertIsNone(summary['reported_model'])
        self.assertIn('Conclusion: BLOCK',report.getvalue())
        self.assertFalse(decoder.consume(lines,io.StringIO(),'gpt-5.6')['success'])

    def test_auto_unknown_and_bad_timeout_stop_before_cli(self):
        for model in ('auto','default','unknown-1','composer-2.5 --force','composer-2.5\ncomposer-3'):
            self.assertNotEqual(self.run_leg(extra={'CURSOR_MODEL':model}).returncode,0)
        self.assertNotEqual(self.run_leg(extra={'CURSOR_TIMEOUT':'0'}).returncode,0)
        self.assertFalse((self.d/'leg.record.json').exists())

    def test_switch_model_changes_both_modes_and_coverage_family(self):
        sys.path.insert(0,str(ROOT/'bin'))
        from _review_result import cursor_model_family, coverage_eligible
        for model, family in [('opus-4.6','anthropic'),('gpt-5.6','openai'),('gemini-3.8-flash','google'),('grok-4.6','xai'),('gpt-5.6-sol-xhigh','openai'),('cursor-grok-4.6-high','xai')]:
            set_model(self.config, 'cursor', (model+'\n').strip())
            self.assertEqual(cursor_model_family(model),family)
            for mode in ('review','explore'):
                result=self.run_leg(mode)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(json.loads((self.d/'leg.record.json').read_text())['model'],model)
        set_model(self.config, 'cursor', ('opus-4.6\n').strip())
        env=dict(self.env,PANEL_MIMO_LEG='off',PANEL_DEEPSEEK_LEG='off',PANEL_GLM_LEG='off',
                 PANEL_KIMI_LEG='off',PANEL_GEMINI_LEG='off',PANEL_GROK_LEG='off')
        result=subprocess.run([str(self.bin/'panel-review'),'--no-my-review','--budget','1',
            str(self.task),str(self.repo),str(self.d/'switched')],env=env,capture_output=True,text=True,timeout=35)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        data=json.loads((self.d/'switched.subcursor.result.json').read_text())
        self.assertEqual(data['family'],'anthropic')
        self.assertTrue(coverage_eligible(data),data)
        data['family']='cursor'
        self.assertFalse(coverage_eligible(data))

    def test_no_credentials_and_invalid_credentials_stop_before_cli(self):
        self.auth.unlink()
        self.assertNotEqual(self.run_leg().returncode,0)
        self.auth.write_text('{}')
        self.assertNotEqual(self.run_leg().returncode,0)
        self.assertFalse((self.d/'leg.record.json').exists())

    def test_duplicate_families_do_not_fill_budget_or_spare_but_all_runs_both(self):
        set_model(self.config, 'cursor', ('grok-4.6\n').strip())
        stub=self.bin/'subgrok'
        stub.write_text('#!/bin/sh\nprintf called > "$3"\nexit 1\n')
        stub.chmod(0o755)
        env=dict(self.env,PANEL_MIMO_LEG='off',PANEL_DEEPSEEK_LEG='off',PANEL_GLM_LEG='off',
                 PANEL_KIMI_LEG='off',PANEL_GEMINI_LEG='off',PANEL_SELECTION_START='6')
        for tag, options, case in [('budget',['--budget','2'],''),
                                   ('spare',['--budget','2'],'no_verdict'),
                                   ('all',['--all'],'')]:
            prefix=self.d/tag
            result=subprocess.run([str(self.bin/'panel-review'),'--no-my-review',
                *options,str(self.task),str(self.repo),str(prefix)],
                env=dict(env,FAKE_CASE=case),capture_output=True,text=True,timeout=35)
            self.assertTrue(Path(str(prefix)+'.subcursor.state').exists(),result.stdout+result.stderr)
            self.assertEqual(Path(str(prefix)+'.subgrok.state').exists(),tag=='all')

    def test_explicit_api_key(self):
        self.auth.unlink()
        result=self.run_leg(extra={'CURSOR_API_KEY':'fake-explicit-api-key'})
        self.assertEqual(result.returncode,0,result.stderr)
        facts=json.loads((self.d/'leg.facts.json').read_text())
        self.assertEqual(facts['billing_mode'],'api')


if __name__=='__main__': unittest.main()

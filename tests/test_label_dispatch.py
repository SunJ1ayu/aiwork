"""Admission and durable-delivery regressions for the label source."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import os
import subprocess
import fcntl
import sqlite3
from unittest.mock import patch
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import _no_egress  # noqa: E402,F401

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'bin'))
spec = importlib.util.spec_from_file_location('dispatch', ROOT/'bin/_label_dispatch.py')
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)

TASK,FIX = d.LABELS
PROJECT = {'repo':'example/project','owner':'owner','bot':'builder'}
def event(i, action='labeled', actor='owner', label=TASK):
    return {'id':i,'event':action,'actor':{'login':actor},'label':{'name':label}}
def item(n, events, labels=(TASK,), state='open', repo='example/project'):
    return {'project':dict(PROJECT,repo=repo), 'issue':{'number':n,'state':state,
        'labels':[{'name':x} for x in labels]}, 'events':events}
def state():
    # Existing persisted states must remain readable after upgrading.
    return {'sent':[], 'active':None, 'cutoffs':{}, 'stopped':[]}

class Admission(unittest.TestCase):
    def plan(self, items, s=None, busy=(), stops=()):
        return d.plan(items,s or state(),set(busy),set(stops))

    def active(self):
        return dict(state(),active={'subject':d.issue_subject(PROJECT['repo'],97),'event_id':10},sent=[d.event_key(PROJECT['repo'],10)])

    def test_trust_dedup_and_one_slot(self):
        self.assertIsNone(self.plan([item(1,[event(1,actor='outsider')])])['candidate'])
        self.assertIsNotNone(self.plan([item(1,[event(1,actor='BUILDER')])])['candidate'])
        s=state();s['sent']=[d.event_key(PROJECT['repo'],1)]
        self.assertIsNone(self.plan([item(1,[event(1)])],s)['candidate'])
        p=self.plan([item(2,[event(2)]),item(1,[event(1)])])
        self.assertEqual(p['candidate']['subject'],d.issue_subject(PROJECT['repo'],1))
        self.assertIsNone(self.plan([item(97,[event(10)]),item(124,[event(12)])],self.active())['candidate'])

    def test_trusted_removal_releases_97_for_124(self):
        for actor,allowed in [('owner',True),('builder',True),('outsider',False)]:
            p=self.plan([item(97,[event(10),event(11,'unlabeled',actor)],labels=()),
                         item(124,[event(12)])],self.active())
            self.assertEqual(bool(p['candidate']),allowed)
            if allowed:self.assertEqual(p['candidate']['subject'],d.issue_subject(PROJECT['repo'],124))

    def test_close_and_owner_stop(self):
        items=[item(97,[event(10)]),item(124,[event(12)])]
        for kind in ('closed','stop'):
            batch=copy.deepcopy(items)
            if kind=='closed':batch[0]['issue']['state']='closed'
            p=self.plan(batch,self.active(),stops=[d.issue_subject(PROJECT['repo'],97)] if kind=='stop' else [])
            self.assertEqual(p['candidate']['subject'],d.issue_subject(PROJECT['repo'],124))

    def test_busy_and_unknown_round_never_release(self):
        p=self.plan([item(97,[event(10),event(11,'unlabeled')],labels=()),item(124,[event(12)])],
                    self.active(),busy=[d.issue_subject(PROJECT['repo'],97)])
        self.assertIsNone(p['candidate'])
        self.assertIsNotNone(p['state']['active'])
        self.assertIsNone(self.plan([item(124,[event(12)])],busy=['another/repo#1'])['candidate'])

    def test_cycles_and_unrelated_label_removal(self):
        p=self.plan([item(97,[event(10),event(11,'unlabeled',label=FIX)])],self.active())
        self.assertIsNone(p['candidate'])
        self.assertIsNotNone(p['state']['active'])
        p=self.plan([item(97,[event(10),event(11,'unlabeled'),event(12)])],self.active())
        self.assertEqual(p['candidate']['event']['id'],12)

    def check_label_order(self, fix_id, removal_id):
        rows=[item(97,[event(10),event(fix_id,label=FIX),
                      event(removal_id,'unlabeled')],labels=(FIX,))]
        # A live round must finish before the queued fix can be delivered.
        busy=self.plan(rows,self.active(),busy=[d.issue_subject(PROJECT['repo'],97)])
        self.assertIsNone(busy['candidate'])
        self.assertEqual(busy['state']['active'],self.active()['active'])
        p=self.plan(rows,busy['state'])
        self.assertIsNotNone(p['candidate'])
        self.assertEqual(p['candidate']['event']['id'],fix_id)
        self.assertEqual(self.plan(rows,p['state'])['candidate']['event']['id'],fix_id)
        with tempfile.TemporaryDirectory() as td:
            saved=d.deliver(Path(td),p['state'],p['candidate'],lambda c:None,lambda c:True)
            self.assertIsNone(self.plan(rows,saved)['candidate'])
            self.assertIsNone(self.plan(rows,self.plan(rows,saved)['state'])['candidate'])

    def test_fix_before_task_removal(self):
        self.check_label_order(12,13)

    def test_fix_after_task_removal(self):
        self.check_label_order(13,12)



    def test_owner_stop_survives_request_removal(self):
        rows=[item(97,[event(10),event(12)])]
        stopped=self.plan(rows,self.active(),stops=[d.subject(rows[0])])
        self.assertIn(d.subject(rows[0]),stopped['state']['stopped'])
        self.assertIsNone(self.plan(rows,stopped['state'])['candidate'])

    def test_trusted_accounts_agree_on_admission_release_and_history(self):
        for login in (PROJECT['owner'].upper(),PROJECT['bot'].upper(),'outsider'):
            rows=[item(97,[event(10,actor=login)])]
            expected=login.lower() in d.trusted_accounts(PROJECT)
            self.assertEqual(bool(self.plan(rows)['candidate']),expected)
            rows[0]['events'].append(event(11,'unlabeled',actor=login))
            rows[0]['issue']['labels']=[]
            self.assertEqual(self.plan(rows,self.active())['state']['active'] is None,expected)
            class Fake:
                def observe(self,s):return rows
                def busy(self):return set()
            with tempfile.TemporaryDirectory() as td:
                record=d.poll({},Path(td),True,Fake())
                self.assertTrue(record['ok'])
                self.assertTrue(all(e['trusted']==expected for e in record['observed']))

    def test_global_slot_across_projects(self):
        p=self.plan([item(1,[event(1)],repo='a/repo'),item(2,[event(2)],repo='b/repo')])
        self.assertEqual(p['candidate']['subject'],'a/repo#1')

class Delivery(unittest.TestCase):
    def test_pending_survives_lost_response_and_reconciles(self):
        with tempfile.TemporaryDirectory() as td:
            folder=Path(td)
            calls=[]
            def post(candidate):
                calls.append(candidate['key'])
                raise TimeoutError('private diagnostic must never enter history')
            with self.assertRaises(TimeoutError):
                d.deliver(folder,state(),self_candidate(),post,lambda c:False)
            saved=json.loads((folder/d.FILES['state']).read_text())
            self.assertEqual(saved['pending']['key'],d.event_key(PROJECT['repo'],1))
            done=d.deliver(folder,saved,saved['pending'],post,lambda c:True)
            self.assertNotIn('pending',done)
            self.assertIn(d.event_key(PROJECT['repo'],1),done['sent'])
            self.assertEqual(len(calls),1)

    def test_atomic_and_history(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'history.jsonl'
            d.history(p,{'ok':False,'error':'TimeoutError'})
            d.history(p,{'ok':True})
            self.assertEqual(len(p.read_text().splitlines()),2)
            self.assertEqual(p.stat().st_mode & 0o777,0o600)

def self_candidate():
    return d.plan([item(1,[event(1)])],state(),set(),set())['candidate']

class Orchestration(unittest.TestCase):
    def test_legacy_migration_preserves_slot_stops_and_dedup(self):
        migrated=d.import_legacy({'sent':['10'],'active_issue':97,'active_event_id':'10',
            'released_through':{'96':9},'stopped_issues':[95]},'example/project')
        self.assertEqual(migrated['sent'],[d.event_key(PROJECT['repo'],10)])
        self.assertEqual(migrated['active']['subject'],d.issue_subject(PROJECT['repo'],97))
        self.assertNotIn('cutoffs',migrated)
        self.assertEqual(migrated['stopped'],['example/project#95'])
        with self.assertRaises(ValueError):d.import_legacy({'active_issue':97},'example/project')

    def test_old_cutoff_cannot_discard_queued_fix_on_import_and_poll(self):
        rows=[item(97,[event(10),event(12,label=FIX),event(13,'unlabeled')],
                   labels=(FIX,))]
        class Fake:
            accepted_keys=set()
            posted=[]
            def observe(self,s):return rows
            def busy(self):return set()
            def accepted(self,c):return c['key'] in self.accepted_keys
            def post(self,c):self.posted.append(c['key']);self.accepted_keys.add(c['key'])
        migrated=d.import_legacy({'sent':['10'],'active_issue':97,'active_event_id':10,
            'released_through':{'97':13},'stopped_issues':[95]},'example/project')
        for old in (migrated,dict(migrated,cutoffs={d.issue_subject(PROJECT['repo'],97):13})):
            with self.subTest(old=old),tempfile.TemporaryDirectory() as td:
                folder=Path(td);backend=Fake();backend.accepted_keys=set();backend.posted=[]
                d.atomic(folder/d.FILES['state'],old)
                self.assertTrue(d.poll({},folder,backend=backend)['ok'])
                self.assertEqual(backend.posted,['example/project:12'])
                saved=json.loads((folder/d.FILES['state']).read_text())
                self.assertNotIn('cutoffs',saved)
                self.assertEqual(saved['stopped'],['example/project#95'])
                self.assertIn(d.event_key(PROJECT['repo'],10),saved['sent'])
                self.assertTrue(d.poll({},folder,backend=backend)['ok'])
                self.assertEqual(backend.posted,['example/project:12'])

    def test_cli_invalid_settings_and_lock_contention_are_audited(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);config=root/'settings.json';config.write_text('private-canary invalid json')
            env=dict(os.environ,AIWORK_DATA_DIR=td)
            argv=[sys.executable,str(ROOT/'bin/_label_dispatch.py'),'--config',str(config)]
            run=subprocess.run(argv,env=env,capture_output=True,text=True)
            self.assertEqual(run.returncode,1)
            self.assertNotIn('private-canary',run.stdout+run.stderr)
            folder=root/'label-dispatch'
            self.assertEqual(json.loads((folder/d.FILES['history']).read_text())['error'],'JSONDecodeError')
            with (folder/d.FILES['lock']).open('a') as lock:
                fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                run=subprocess.run(argv,env=env,capture_output=True,text=True)
            self.assertEqual(run.returncode,0)
            lines=(folder/d.FILES['history']).read_text().splitlines()
            self.assertEqual(json.loads(lines[-1])['decisions'][0]['reason'],d.Reason.LOCKED)

    def test_query_failure_records_only_error_class(self):
        class Broken:
            def observe(self, s):raise RuntimeError('private-value')
        with tempfile.TemporaryDirectory() as td:
            folder=Path(td)
            record=d.poll({},folder,backend=Broken())
            self.assertFalse(record['ok'])
            self.assertEqual(record['error'],'RuntimeError')
            self.assertNotIn('private-value',(folder/d.FILES['history']).read_text())
            self.assertFalse((folder/d.FILES['state']).exists())

    def test_preview_and_full_delivery_then_dedup(self):
        class Fake:
            accepted_keys=set()
            posted=[]
            def observe(self,s):return [item(1,[event(1)])]
            def busy(self):return set()
            def accepted(self,c):return c['key'] in self.accepted_keys
            def post(self,c):self.posted.append(c['key']);self.accepted_keys.add(c['key'])
        with tempfile.TemporaryDirectory() as td:
            folder=Path(td);backend=Fake()
            self.assertTrue(d.poll({},folder,True,backend)['ok'])
            self.assertFalse((folder/d.FILES['state']).exists())
            self.assertEqual(backend.posted,[])
            self.assertTrue(d.poll({},folder,backend=backend)['ok'])
            self.assertTrue(d.poll({},folder,backend=backend)['ok'])
            self.assertEqual(backend.posted,[d.event_key(PROJECT['repo'],1)])
            self.assertEqual(len((folder/d.FILES['history']).read_text().splitlines()),3)




    def test_manual_file_paths_drive_stop_and_persisted_state(self):
        # Run the documented discovery command; use its result as an operator would.
        manual=(ROOT/'docs/mac-host.md').read_text()
        self.assertIn('--local-files',manual)
        with tempfile.TemporaryDirectory() as td:
            env=dict(os.environ,AIWORK_DATA_DIR=td)
            run=subprocess.run([sys.executable,str(ROOT/'bin/_label_dispatch.py'),'--local-files'],
                               env=env,capture_output=True,text=True,check=True)
            files={k:Path(v) for k,v in json.loads(run.stdout).items()}
            row=item(97,[event(10),event(12)])
            class Fake:
                def observe(self,s):return [row]
                def busy(self):return set()
                def post(self,c):raise AssertionError('stopped issue must not dispatch')
            folder=files['state'].parent
            folder.mkdir(parents=True,exist_ok=True)
            d.atomic(files['state'],Admission().active())
            d.atomic(files['stops'],[d.subject(row)])
            self.assertTrue(d.poll({},folder,backend=Fake())['ok'])
            self.assertIn(d.subject(row),json.loads(files['state'].read_text())['stopped'])
            d.atomic(files['stops'],[])
            self.assertTrue(d.poll({},folder,backend=Fake())['ok'])

    def test_observe_backfills_active_outside_open_labels(self):
        for status,labels in [('closed',()),('open',())]:
            with self.subTest(status=status):
                backend=d.Backend({'projects':[PROJECT]})
                calls=[]
                def api(project,path):
                    calls.append(path)
                    if path.startswith(d.ISSUES_ROUTE+'?'):return []
                    if path==d.issue_path(97):return item(97,[],labels,status)['issue']
                    if path.startswith(d.issue_path(97,d.EVENTS_SUFFIX)+'?'):
                        return [event(10),event(11,'unlabeled')]
                    self.fail('unexpected query '+path)
                backend.api=api
                rows=backend.observe(Admission().active())
                self.assertEqual(len(rows),1)
                self.assertIn(d.issue_path(97),calls)
                result=d.plan(rows,Admission().active(),set(),set())
                self.assertIsNone(result['state']['active'])

    def test_pagination_and_pr_fix_observation(self):
        backend=d.Backend({'projects':[PROJECT]})
        pr={'number':1,'state':'open','labels':[{'name':FIX}],'pull_request':{}}
        calls=[]
        def api(project,path):
            calls.append(path)
            if path.startswith(d.ISSUES_ROUTE+'?'):return [pr] if d.urllib.parse.quote(FIX,safe='') in path else []
            return [event(1,label=FIX)]
        backend.api=api
        rows=backend.observe(state())
        self.assertEqual(len(rows),1)
        self.assertIsNotNone(d.plan(rows,state(),set(),set())['candidate'])
        self.assertTrue(all('per_page=100' in path for path in calls))

    def test_hub_query_treats_unknown_and_queued_as_busy(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'hub.db'
            with sqlite3.connect(p) as db:
                db.execute('create table runs(lane text,state text)')
                db.executemany('insert into runs values(?,?)',[
                    ('a/repo#1','done'),('a/repo#2','unknown'),('b/repo#1','queued')])
            self.assertEqual(d.Backend({'hub_db':str(p)}).busy(),{'a/repo#2','b/repo#1'})

    def test_reference_written_before_event_and_stable_event_key(self):
        class Response:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def read(self):return b'{"routed":1}'
        with tempfile.TemporaryDirectory() as td:
            config=Path(td)/'hub.json'
            config.write_text(json.dumps({'url':'http://127.0.0.1:3350','source':{'key':'fixture'}}))
            backend=d.Backend({'hub_config':str(config)})
            backend.pages=lambda *args:[]
            c=self_candidate();c['project'].update(reference_root='/reference',reference_command=['writer'])
            actions=[]
            class Opener:
                def open(self,req,timeout):
                    payload=json.loads(req.data);actions.append(payload['id']);return Response()
            backend.open=Opener()
            with patch.object(d,'command',side_effect=lambda argv,payload:actions.append(payload['path'])):
                backend.post(c)
            self.assertEqual(actions,['/reference/'+d.issue_path(1)+'/'+d.REFERENCE_LABEL_PREFIX+'1'+d.REFERENCE_SUFFIX,d.event_key(PROJECT['repo'],1)])

if __name__=='__main__': unittest.main()

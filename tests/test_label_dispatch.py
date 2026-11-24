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

TASK,FIX = 'aiwork:task', 'aiwork:fix'
PROJECT = {'repo':'example/project','owner':'owner','bot':'builder','rule':'legacy'}
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

    def test_trust_dedup_and_default_capacity(self):
        self.assertIsNone(self.plan([item(1,[event(1,actor='outsider')])])['candidate'])
        self.assertIsNotNone(self.plan([item(1,[event(1,actor='BUILDER')])])['candidate'])
        s=state();s['sent']=[d.event_key(PROJECT['repo'],1)]
        self.assertIsNone(self.plan([item(1,[event(1)])],s)['candidate'])
        p=self.plan([item(2,[event(2)]),item(1,[event(1)])])
        self.assertEqual(p['candidate']['subject'],d.issue_subject(PROJECT['repo'],1))
        self.assertIsNone(self.plan([item(97,[event(10)]),item(124,[event(12)])],self.active())['candidate'])

    def test_family_labels_keep_the_same_trust_and_capacity(self):
        task = 'aiwork:task:deepseek'
        fix = 'aiwork:fix:deepseek'
        self.assertIsNone(self.plan([item(1, [event(1, actor='outsider', label=task)], (task,))])['candidate'])
        row = item(1, [event(1, label=task)], (task,))
        self.assertIsNone(self.plan([row])['candidate'])
        row['project']['builder_rules'] = {'deepseek': 'deepseek-builder'}
        result = self.plan([row])
        self.assertEqual(result['candidate']['event']['label']['name'], task)
        self.assertEqual(d.LABELS[task], 'issues.task.deepseek')
        self.assertEqual(d.LABELS[fix], 'issues.fix.deepseek')
        self.assertEqual(d.label_route(row['project'], fix), 'deepseek-builder')

    def test_legacy_and_family_labels_never_dispatch_twice(self):
        for base in (TASK, FIX):
            family = base + ':openai'
            row = item(1, [event(1, label=base), event(2, label=family)], (base, family))
            row['project']['builder_rules'] = {'openai': 'codex-builder'}
            for sent in ([], [d.event_key(PROJECT['repo'], 1)]):
                with self.subTest(base=base, sent=sent):
                    original = dict(state(), sent=sent)
                    result = self.plan([row], original)
                    self.assertIsNone(result['candidate'])
                    self.assertTrue(any(x['reason'] == d.Reason.CONFLICT
                                        for x in result['decisions']))
            # Removing the obsolete label enables the family route.
            row['issue']['labels'] = [{'name': family}]
            row['events'].append(event(3, 'unlabeled', label=base))
            self.assertEqual(self.plan([row])['candidate']['event']['id'], 2)

    def test_ineligible_peer_does_not_block_routed_label(self):
        for base in (TASK, FIX):
            for valid in (base, base + ':openai'):
                for peer, login, reason in (
                        (base + ':opneai', 'owner', d.Reason.UNROUTED),
                        (base + ':deepseek', 'owner', d.Reason.UNROUTED),
                        (base + ':xiaomi', 'outsider', d.Reason.UNTRUSTED)):
                    with self.subTest(valid=valid, peer=peer, login=login):
                        row = item(1, [event(1, label=valid),
                                      event(2, actor=login, label=peer)], (valid, peer))
                        row['project']['builder_rules'] = {
                            'openai': 'codex-builder', 'xiaomi': 'mimo-builder'}
                        result = self.plan([row])
                        self.assertIsNotNone(result['candidate'])
                        self.assertEqual(result['candidate']['event']['id'], 1)
                        self.assertIn({'subject': d.subject(row), 'event_id': 2,
                                       'reason': reason}, result['decisions'])
                        self.assertFalse(any(x['reason'] == d.Reason.CONFLICT
                                             for x in result['decisions']))

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
        self.assertTrue(p['state']['active'])
        self.assertIsNone(self.plan([item(124,[event(12)])],busy=['another/repo#1'])['candidate'])

    def test_cycles_and_unrelated_label_removal(self):
        p=self.plan([item(97,[event(10),event(11,'unlabeled',label=FIX)])],self.active())
        self.assertIsNone(p['candidate'])
        self.assertTrue(p['state']['active'])
        p=self.plan([item(97,[event(10),event(11,'unlabeled'),event(12)])],self.active())
        self.assertEqual(p['candidate']['event']['id'],12)

    def check_label_order(self, fix_id, removal_id):
        rows=[item(97,[event(10),event(fix_id,label=FIX),
                      event(removal_id,'unlabeled')],labels=(FIX,))]
        # A live round must finish before the queued fix can be delivered.
        busy=self.plan(rows,self.active(),busy=[d.issue_subject(PROJECT['repo'],97)])
        self.assertIsNone(busy['candidate'])
        self.assertEqual(busy['state']['active'],d.upgraded(self.active())['active'])
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
            self.assertEqual(self.plan(rows,self.active())['state']['active'] == {},expected)
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

class Capacity(unittest.TestCase):
    def test_configured_capacity_and_dedup(self):
        rows = [item(n, [event(n)]) for n in range(1, 5)]
        for limit in (1, 2, 3):
            with self.subTest(limit=limit), tempfile.TemporaryDirectory() as td:
                saved = state()
                for index in range(limit):
                    result = d.plan(rows, saved, set(), set(), limit)
                    self.assertEqual(result['candidate']['subject'], d.subject(rows[index]))
                    saved = d.deliver(Path(td), result['state'], result['candidate'],
                                      lambda c: None, lambda c: True)
                self.assertIsNone(d.plan(rows, saved, set(), set(), limit)['candidate'])
                self.assertEqual(len(saved['active']), limit)

    def test_unknown_stop_and_continuation_are_per_issue(self):
        rows = [item(1, [event(1), event(5, 'unlabeled')], labels=()),
                item(2, [event(2), event(6, label=FIX)], labels=(TASK, FIX)),
                item(3, [event(3)])]
        with tempfile.TemporaryDirectory() as td:
            saved = state()
            for row in rows[:2]:
                result = d.plan([item(row['issue']['number'], [row['events'][0]])], saved, set(), set(), 2)
                saved = d.deliver(Path(td), result['state'], result['candidate'],
                                  lambda c: None, lambda c: True)
            result = d.plan(rows, saved, {d.subject(rows[0])}, {d.subject(rows[0])}, 2)
            self.assertEqual(result['candidate']['event']['id'], 6)
            continued = d.deliver(Path(td), result['state'], result['candidate'],
                                  lambda c: None, lambda c: True)
            self.assertEqual(len(continued['active']), 2)
            self.assertIn(d.subject(rows[0]), continued['active'])
            self.assertIsNone(d.plan(rows, continued, {d.subject(rows[0])}, set(), 2)['candidate'])
            released = d.plan(rows, continued, set(), {d.subject(rows[0])}, 2)
            self.assertEqual(released['candidate']['subject'], d.subject(rows[2]))
            self.assertIn(d.subject(rows[0]), released['state']['stopped'])

    def test_legacy_slot_and_pending_upgrade_without_duplicate(self):
        legacy = Admission().active()
        rows = [item(97, [event(10)]), item(124, [event(12)])]
        result = d.plan(rows, legacy, set(), set(), 2)
        self.assertEqual(result['candidate']['event']['id'], 12)
        self.assertEqual(result['state']['active'][d.subject(rows[0])]['event_id'], 10)
        self.assertEqual(result['state']['sent'], legacy['sent'])
        self.assertEqual(legacy['active']['event_id'], 10)

    def test_pending_failure_keeps_slots_and_defers_admission(self):
        rows = [item(n, [event(n)]) for n in (1, 2, 3)]
        class Fake:
            posted = []
            def observe(self, s): return rows
            def busy(self): return set()
            def accepted(self, c): return c['subject'] == d.subject(rows[1])
            def post(self, c):
                self.posted.append(c['subject'])
                raise TimeoutError('private diagnostic')
        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            candidate = d.plan(rows, state(), set(), set())['candidate']
            with self.assertRaises(TimeoutError):
                d.deliver(folder, state(), candidate, Fake().post, lambda c: False)
            backend = Fake()
            first = d.poll({'max_active': 2}, folder, backend=backend)
            self.assertFalse(first['ok'])
            saved = json.loads((folder/d.FILES['state']).read_text())
            self.assertIn(d.subject(rows[0]), saved['pending'])
            self.assertNotIn(d.event_key(PROJECT['repo'], 2), saved['sent'])
            self.assertEqual(len(saved['active']), 1)
            d.poll({'max_active': 2}, folder, backend=backend)
            saved = json.loads((folder/d.FILES['state']).read_text())
            self.assertNotIn(d.event_key(PROJECT['repo'], 3), saved['sent'])

    def test_busy_union_lowering_and_independent_release(self):
        rows = [item(n, [event(n)]) for n in (1, 2, 3)]
        with tempfile.TemporaryDirectory() as td:
            saved = state()
            for row in rows[:2]:
                result = d.plan([row], saved, set(), set(), 3)
                saved = d.deliver(Path(td), result['state'], result['candidate'],
                                  lambda c: None, lambda c: True)
            # An active lane also in the hub counts once; an unrelated hub lane counts too.
            self.assertIsNotNone(d.plan(rows, saved, {d.subject(rows[0])}, set(), 3)['candidate'])
            self.assertIsNone(d.plan(rows, saved, {'other/repo#1'}, set(), 3)['candidate'])
            self.assertIsNone(d.plan(rows, saved, set(), set(), 1)['candidate'])
            self.assertEqual(len(saved['active']), 2)
            rows[1]['issue']['state'] = 'closed'
            released = d.plan(rows, saved, {d.subject(rows[0])}, set(), 2)
            self.assertEqual(released['candidate']['subject'], d.subject(rows[2]))
            self.assertEqual(set(released['state']['active']), {d.subject(rows[0])})

    def test_old_pending_is_preserved_on_preview_and_reconciled_once(self):
        c = self_candidate()
        old = dict(state(), active={'subject': c['subject'], 'event_id': 1}, pending=c)
        class Fake:
            def observe(self, s): return [item(1, [event(1)])]
            def busy(self): return set()
            def accepted(self, c): return True
            def post(self, c): raise AssertionError('already routed')
        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            path = folder/d.FILES['state']
            d.atomic(path, old)
            before = path.read_bytes()
            self.assertTrue(d.poll({}, folder, True, Fake())['ok'])
            self.assertEqual(path.read_bytes(), before)
            self.assertTrue(d.poll({}, folder, backend=Fake())['ok'])
            saved = json.loads(path.read_text())
            self.assertEqual(saved['pending'], {})
            self.assertEqual(saved['sent'], [c['key']])
            self.assertEqual(set(saved['active']), {c['subject']})
            self.assertTrue(d.poll({}, folder, backend=Fake())['ok'])
            self.assertEqual(json.loads(path.read_text()), saved)

    def test_invalid_capacity_never_changes_slots_or_delivers(self):
        class Fake:
            def observe(self, s): raise AssertionError('settings must fail before querying')
        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            path = folder/d.FILES['state']
            d.atomic(path, Admission().active())
            before = path.read_bytes()
            self.assertFalse(d.poll({'max_active': False}, folder, backend=Fake())['ok'])
            self.assertEqual(path.read_bytes(), before)

    def test_capacity_settings_fail_closed(self):
        self.assertEqual(d.capacity({}), d.DEFAULT_MAX_ACTIVE)
        for value in (0, -1, True, '3', 2.5, None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                d.capacity({'max_active': value})
        self.assertEqual(d.capacity({'max_active': 3}), 3)

class SlotFaults(unittest.TestCase):
    def test_missing_origin_is_isolated(self):
        original = Admission().active()
        result = d.plan([item(97, []), item(2, [event(20)])], original, set(), set(), 2)
        self.assertEqual(result['candidate']['subject'], 'example/project#2')
        self.assertTrue(any(x['reason'] == d.Reason.ACTIVE_EVENT_MISSING for x in result['decisions']))
        self.assertIn('example/project#97', result['state']['active'])

    def test_missing_project_is_reported_and_retained(self):
        result = d.plan([item(2, [event(20)])], Admission().active(), set(), set(), 2)
        self.assertTrue(any(x['reason'] == d.Reason.ACTIVE_OBSERVATION_MISSING for x in result['decisions']))
        self.assertIn('example/project#97', result['state']['active'])

    def test_pending_query_does_not_admit_in_either_mode(self):
        candidate = self_candidate()
        class Fake:
            def observe(self, s): return [item(1, [event(1)], state='closed'), item(2, [event(2)])]
            def busy(self): return set()
            def accepted(self, c): return True
            def post(self, c): raise AssertionError('must not post')
        for preview in (True, False):
            with self.subTest(preview=preview), tempfile.TemporaryDirectory() as td:
                folder = Path(td)
                original = d.upgraded(state())
                original['active'][candidate['subject']] = {'subject':candidate['subject'], 'event_id':1}
                original['pending'][candidate['subject']] = candidate
                d.atomic(folder/d.FILES['state'], original)
                result = d.poll({}, folder, preview, Fake())
                self.assertTrue(result['ok'])
                self.assertFalse(any(x['reason'] == d.Reason.ELIGIBLE for x in result['decisions']))

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
            self.assertEqual(saved['pending'][d.issue_subject(PROJECT['repo'],1)]['key'],d.event_key(PROJECT['repo'],1))
            done=d.deliver(folder,saved,saved['pending'][d.issue_subject(PROJECT['repo'],1)],post,lambda c:True)
            self.assertEqual(done['pending'], {})
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

    def test_observe_unrouted_family_labels_records_reason(self):
        for family in ('openai', 'opneai'):
            for base in (TASK, FIX):
                with self.subTest(family=family, base=base):
                    label = base + ':' + family
                    row = item(1, [event(1, label=label)], (label,))
                    backend = d.Backend({'projects': [PROJECT]})
                    def api(project, path):
                        if path.startswith(d.ISSUES_ROUTE + '?'):
                            return [row['issue']] if ('labels=' not in path or
                                d.urllib.parse.quote(label, safe='') in path) else []
                        return row['events']
                    backend.api = api
                    backend.busy = lambda: set()
                    with tempfile.TemporaryDirectory() as td:
                        record = d.poll({}, Path(td), True, backend)
                        self.assertTrue(record['ok'])
                        self.assertEqual(record['decisions'], [{
                            'subject': d.subject(row), 'event_id': 1,
                            'reason': d.Reason.UNROUTED}])
                        self.assertEqual(record['observed'][0]['label'], label)

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
                self.assertEqual(result['state']['active'], {})

    def test_observe_backfills_every_active_issue(self):
        backend = d.Backend({'projects': [PROJECT]})
        numbers = (7, 8, 9)
        saved = d.upgraded(state())
        saved['active'] = {d.issue_subject(PROJECT['repo'], n):
                           {'subject': d.issue_subject(PROJECT['repo'], n), 'event_id': n}
                           for n in numbers}
        def api(project, path):
            if path.startswith(d.ISSUES_ROUTE + '?'): return []
            n = int(path.split('/')[1].split('?')[0])
            if '/events?' in path: return [event(n)]
            return item(n, [], state='closed')['issue']
        backend.api = api
        rows = backend.observe(saved)
        self.assertEqual({r['issue']['number'] for r in rows}, set(numbers))
        self.assertEqual(d.plan(rows, saved, set(), set(), 3)['state']['active'], {})

    def test_pagination_and_pr_fix_observation(self):
        backend=d.Backend({'projects':[PROJECT]})
        pr={'number':1,'state':'open','labels':[{'name':FIX}],'pull_request':{}}
        unrelated={'number':2,'state':'open','labels':[{'name':'help wanted'}]}
        calls=[]
        def api(project,path):
            calls.append(path)
            if path.startswith(d.ISSUES_ROUTE+'?'):
                return ([unrelated] * 100 if '&page=1' in path else [pr])
            return [event(1,label=FIX)]
        backend.api=api
        rows=backend.observe(state())
        self.assertEqual(len(rows),1)
        self.assertTrue(any('page=2' in path for path in calls))
        self.assertFalse(any(d.issue_path(2, d.EVENTS_SUFFIX) in path for path in calls))
        self.assertIsNotNone(d.plan(rows,state(),set(),set())['candidate'])
        self.assertTrue(all('per_page=100' in path for path in calls))

    def test_hub_query_treats_unknown_and_queued_as_busy(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'hub.db'
            with sqlite3.connect(p) as db:
                db.execute("create table runs(lane text,state text,rule text default 'legacy')")
                db.executemany('insert into runs(lane,state) values(?,?)',[
                    ('a/repo#1','done'),('a/repo#2','unknown'),('b/repo#1','queued')])
            self.assertEqual(d.Backend({'hub_db':str(p),'projects':[PROJECT]}).busy(),{'a/repo#2','b/repo#1'})

    def test_other_rule_is_separate_and_empty_lane_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'hub.db'
            with sqlite3.connect(p) as db:
                db.execute('create table runs(rule text,lane text,state text)')
                db.executemany('insert into runs values(?,?,?)', [
                    ('legacy','example/project#1','queued'),
                    ('another','example/project#1','unknown')])
            backend=d.Backend({'hub_db':str(p),'projects':[PROJECT]})
            self.assertEqual(backend.busy(), {'example/project#1', ('other_rule','another','example/project#1')})
            with sqlite3.connect(p) as db:
                db.execute("insert into runs values('serial','','queued')")
            with self.assertRaisesRegex(ValueError, d.Reason.HUB_LANE_UNMAPPED): backend.busy()

    def test_family_delivery_is_acknowledged_only_by_its_configured_rule(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / 'hub.db'
            candidate = self_candidate()
            label = 'aiwork:task:xiaomi'
            candidate['event']['label']['name'] = label
            candidate['project']['builder_rules'] = {'xiaomi': 'mimo-builder'}
            backend = d.Backend({'hub_db': str(path), 'source': 'labels'})
            with sqlite3.connect(path) as db:
                db.execute('create table runs(id integer, rule text)')
                db.execute('create table run_events(run_id integer, event_id integer)')
                db.execute('create table events(id integer, source text, key text)')
                db.execute('insert into events values(1, ?, ?)', ('labels', candidate['key']))
                db.execute('insert into run_events values(1, 1)')
                db.execute('insert into runs values(1, ?)', ('legacy',))
            self.assertFalse(backend.accepted(candidate))
            with sqlite3.connect(path) as db:
                db.execute('update runs set rule = ?', ('mimo-builder',))
            self.assertTrue(backend.accepted(candidate))

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

class PollFaultReporting(unittest.TestCase):
    def test_candidate_read_failure_reports_subject_and_keeps_other_delivery(self):
        backend=d.Backend({'projects':[PROJECT]})
        backend.pages=lambda p,path: ([item(1,[])['issue'],item(2,[])['issue']]
            if path.startswith('issues?') else [event(2)] if path.startswith('issues/2/')
            else (_ for _ in ()).throw(TimeoutError('private diagnostic')))
        backend.busy=lambda:set()
        backend.post=lambda c:None
        backend.accepted=lambda c:True
        with tempfile.TemporaryDirectory() as td:
            result=d.poll({'max_active':2},Path(td),backend=backend)
            self.assertFalse(result['ok'])
            self.assertEqual(result['errors'][0]['subject'],'example/project#1')
            self.assertEqual(result['errors'][0]['error'],'TimeoutError')
            self.assertNotIn('private diagnostic',json.dumps(result))
            self.assertIn('example/project:2',json.loads((Path(td)/d.FILES['state']).read_text())['sent'])

    def test_active_faults_fail_poll_and_keep_slot(self):
        for rows,reason in (([], d.Reason.ACTIVE_OBSERVATION_MISSING),([item(97,[])], d.Reason.ACTIVE_EVENT_MISSING)):
            class Fake:
                def observe(self,s):return rows
                def busy(self):return set()
            with self.subTest(reason=reason),tempfile.TemporaryDirectory() as td:
                folder=Path(td);d.atomic(folder/d.FILES['state'],Admission().active())
                result=d.poll({},folder,backend=Fake())
                self.assertFalse(result['ok'])
                self.assertIn(reason,[x['reason'] for x in result['decisions']])
                self.assertIn('example/project#97',json.loads((folder/d.FILES['state']).read_text())['active'])

    def test_empty_lane_reason_survives_poll(self):
        backend=d.Backend({'projects':[PROJECT]})
        backend.observe=lambda s:[]
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/'hub.db';backend.config['hub_db']=str(path)
            with sqlite3.connect(path) as db:
                db.execute('create table runs(rule text,lane text,state text)')
                db.execute("insert into runs values('serial','','queued')")
            result=d.poll({},Path(td),backend=backend)
            self.assertFalse(result['ok'])
            self.assertEqual(result['reason'],d.Reason.HUB_LANE_UNMAPPED)

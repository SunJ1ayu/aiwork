#!/usr/bin/env python3
import os,sys
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import _no_egress
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'bin'))
import unittest
from _review_dispatch import dispatch

class DispatchTests(unittest.TestCase):
    def run_case(self, failures=(), minimum=2, target=3, families=None, changed=False):
        self.calls=[]
        state={'head':'a'*40,'policy_sha':'b'*40,
               'plan':{'tier':'high','target':target,'minimum':minimum,'order':['a','b','c','d']},
               'passes':[],'excluded':['anthropic'],'gate':{'title':'等业主批准'}}
        families=families or {'a':'deepseek','b':'moonshot','c':'xiaomi','d':'openai'}
        def identify(leg):return families[leg],None
        def run(leg,model,head):
            self.calls.append(leg)
            if leg in failures: return {'ok':False,'reason':'reported failure'}
            state['passes'].append(families[leg])
            if changed: state['head']='c'*40
            return {'ok':True,'url':'https://github.com/example/review'}
        return dispatch(lambda:state.copy(),identify,run,'openai')
    def test_failure_tries_next_in_fixed_order(self):
        r=self.run_case(failures=['a'],target=2)
        self.assertEqual(self.calls,['a','b','c'])
        self.assertTrue(r['minimum_met']);self.assertTrue(r['target_met'])
        self.assertEqual(r['attempts'][0]['reason'],'reported failure')
    def test_exhaustion_below_floor_is_owner_handoff(self):
        r=self.run_case(failures=['a','b'])
        self.assertEqual(self.calls,['a','b','c'])
        self.assertFalse(r['minimum_met']);self.assertEqual(r['next_step'],'交业主')
    def test_floor_met_missing_target_does_not_block(self):
        r=self.run_case(failures=['a'])
        self.assertEqual(self.calls,['a','b','c'])
        self.assertTrue(r['minimum_met']);self.assertFalse(r['target_met'])
        self.assertEqual(r['missing_target'],1)
    def test_same_family_and_builder_never_fill_budget(self):
        r=self.run_case(families={'a':'openai','b':'deepseek','c':'deepseek','d':'anthropic'})
        self.assertEqual(self.calls,['b']);self.assertFalse(r['minimum_met'])
    def test_head_change_stops_without_reviewing_other_head(self):
        with self.assertRaisesRegex(ValueError,'head'):
            self.run_case(changed=True)
        self.assertEqual(self.calls,['a'])
    def test_block_is_a_completed_review_but_not_a_pass(self):
        state={'head':'a'*40,'policy_sha':'b'*40,'plan':{'tier':'code','target':2,'minimum':1,'order':['a','b','c']},'passes':[],'excluded':[],'gate':{}}
        calls=[]
        def run(leg,model,head):
            calls.append(leg)
            if leg=='b':state['passes']=['moonshot']
            return {'ok':True,'url':'https://github.com/example/review'}
        r=dispatch(lambda:state.copy(),lambda l:({'a':'deepseek','b':'moonshot','c':'xiaomi'}[l],None),run,'openai')
        self.assertEqual(calls,['a','b']);self.assertTrue(r['target_met']);self.assertTrue(r['minimum_met'])
    def test_lost_publication_response_uses_actual_gate_passes_for_target(self):
        state={'head':'a'*40,'policy_sha':'b'*40,
               'plan':{'tier':'code','target':2,'minimum':1,'order':['a','b']},
               'passes':[],'excluded':[],'gate':{}}
        families={'a':'deepseek','b':'moonshot'}
        def run(leg,model,head):
            state['passes'].append(families[leg])
            return {'ok':False,'reason':'publication response lost'} if leg=='a' else {'ok':True,'url':'https://github.com/example/review'}
        result=dispatch(lambda:state.copy(),lambda leg:(families[leg],None),run,'openai')
        self.assertTrue(result['target_met'])
        self.assertEqual(result['missing_target'],0)
        self.assertFalse(result['attempts'][0]['ok'])

    def test_policy_change_stops(self):
        i=0
        def state():
            nonlocal i
            i+=1
            return {'head':'a'*40,'policy_sha':str(i),'plan':{'tier':'code','target':2,'minimum':1,'order':['a','b']},'passes':[],'excluded':[],'gate':{}}
        with self.assertRaisesRegex(ValueError,'policy'):
            dispatch(state,lambda l:('deepseek',None),lambda *a:{'ok':False,'reason':'failure'},'openai')

class PublisherIntegrationTests(unittest.TestCase):
    def test_auto_pins_head_and_cursor_model_and_keeps_logs_outside_repo(self):
        import importlib.util, importlib.machinery, tempfile, json, io, subprocess
        from unittest.mock import patch
        from contextlib import redirect_stdout,redirect_stderr
        root=Path(__file__).resolve().parents[1]
        loader=importlib.machinery.SourceFileLoader('dispatch_publisher',str(root/'bin/review-pr'))
        spec=importlib.util.spec_from_loader(loader.name,loader)
        publisher=importlib.util.module_from_spec(spec);loader.exec_module(publisher)
        state={'head':'a'*40,'policy_sha':'b'*40,
               'plan':{'tier':'documentation','target':1,'minimum':1,'order':['subcursor']},
               'passes':[],'excluded':[],'gate':{}}
        seen=[]
        def run(command,**kwargs):
            seen.append((command,kwargs))
            state['passes']=['moonshot']
            return subprocess.CompletedProcess(command,0,'https://github.com/example/review\n','')
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(publisher,'data_path',return_value=Path(directory)), \
             patch.object(publisher,'read_dispatch_state',side_effect=lambda *a:state.copy()), \
             patch.object(publisher._leg_session,'choose_leg',return_value=('moonshot','kimi-test')), \
             patch.object(publisher.subprocess,'run',side_effect=run), \
             patch.dict(os.environ,{'GH_TOKEN':'not-for-model'}), \
             redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO()):
            self.assertEqual(publisher.auto_dispatch('example/repo',1,'openai'),0)
            reports=list(Path(directory).glob('*/summary.json'));self.assertEqual(len(reports),1)
            self.assertEqual(json.loads(reports[0].read_text())['pass_families'],['moonshot'])
        command,kwargs=seen[0]
        self.assertEqual(command[-2:],['--expected-head','a'*40])
        self.assertEqual(kwargs['env']['CURSOR_MODEL'],'kimi-test')
        self.assertNotIn('GH_TOKEN',kwargs['env'])

if __name__=='__main__':unittest.main()

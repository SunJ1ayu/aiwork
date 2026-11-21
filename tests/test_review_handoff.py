import _no_egress
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
loader=importlib.machinery.SourceFileLoader('handoff',str(Path(__file__).resolve().parents[1]/'bin/review-auto-worker'))
spec=importlib.util.spec_from_loader(loader.name,loader)
worker=importlib.util.module_from_spec(spec)
loader.exec_module(worker)

class Handoff(unittest.TestCase):
    def test_failed_finished_retries_success_does_not(self):
        self.assertTrue(worker.retryable({'state':'finished','entry_exit':2}))
        self.assertFalse(worker.retryable({'state':'finished','entry_exit':0}))
        self.assertTrue(worker.retryable({'state':'started'}))

    def test_preflight_recovers_and_has_limit(self):
        with patch.object(worker.time,'sleep'), patch.object(worker.subprocess,'run',side_effect=[OSError('network'),'ok']) as run:
            self.assertEqual(worker.retry(run),'ok')
            self.assertEqual(run.call_count,2)
        with patch.object(worker.time,'sleep'), patch.object(worker.subprocess,'run',side_effect=OSError('network')) as run:
            with self.assertRaises(OSError):worker.retry(run)
            self.assertEqual(run.call_count,3)

    def test_argv_is_locally_constructed(self):
        self.assertEqual(worker.command_for(['tool','--repo','example/repo','--auto','--builder-family','unused'],1,'a'*40,'openai'),['tool','1','--repo','example/repo','--auto','--builder-family','openai','--expected-head','a'*40])

    def test_admission_rejects_event_commands_and_wrong_source(self):
        import json
        event={'source':'trusted','type':'reviews.request','subject':'example/repo#1',
               'detail':json.dumps({'repository':'example/repo','pr':1,'head':'a'*40,'builder_family':'openai','argv':['untrusted-command']})}
        number,requests=worker.requested_pr({'events':[event]},'example/repo','trusted')
        self.assertEqual(number,1)
        self.assertEqual(requests,{'a'*40:{'openai'}})
        with self.assertRaises(ValueError):worker.requested_pr({'events':[event]},'example/repo','other')
        policy={'builders':{'builder':'openai'}}
        self.assertEqual(worker.builder_for({'head':{'sha':'a'*40},'user':{'login':'builder'}},requests,policy)[2],'openai')
        with self.assertRaises(ValueError):worker.builder_for({'head':{'sha':'a'*40},'user':{'login':'builder'}},{'a'*40:{'other'}},policy)

    def test_settings_reject_relative_machine_paths(self):
        import tempfile,json
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'settings.json'
            path.write_text(json.dumps({'checkout':'relative','programs':'/programs','repository':'example/repo','event_source':'trusted'}))
            with self.assertRaises(ValueError):worker.load_settings(path)

    def test_interrupted_dispatch_can_retry(self):
        self.main_sequence(interrupted=True)

    def test_main_failed_head_can_retry_then_success_deduplicates(self):
        self.main_sequence(interrupted=False)

    def main_sequence(self, interrupted):
        import tempfile,json,sys,subprocess,os,io
        from contextlib import redirect_stdout,redirect_stderr
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            settings=root/'settings.json'
            settings.write_text(json.dumps({'checkout':str(root),'programs':str(root),'repository':'example/repo','event_source':'trusted'}))
            context=root/'context.json'
            context.write_text(json.dumps({'events':[{'source':'trusted','type':'reviews.request','subject':'example/repo#1','detail':json.dumps({'repository':'example/repo','pr':1,'head':'a'*40,'builder_family':'openai'})}]}))
            policy={'builders':{'builder':'openai'}}
            pr={'head':{'sha':'a'*40},'user':{'login':'builder'}}
            state={'head':'a'*40,'policy_sha':'blob','excluded':['openai'],'gate':{'summary':'✅ G1 current CI'}}
            from unittest.mock import Mock
            read_pr=Mock(side_effect=[OSError('network'),pr,pr,pr])
            api={'review_token':lambda repo:'token','pr_state':read_pr,'read_dispatch_state':lambda *args:state,'data_path':lambda name:root/'data','redact':lambda value:value}
            models=[]
            def command(argv,**kwargs):
                if argv[0].endswith('review-pr'):
                    models.append(argv)
                    if interrupted and len(models)==1:
                        raise OSError('dispatch start failed')
                    return subprocess.CompletedProcess(argv,2 if len(models)==1 else 0,'{}','')
                return subprocess.CompletedProcess(argv,0,'','')
            previous_umask=os.umask(0o077)
            try:
                with patch.object(sys,'argv',['worker',str(context),str(settings)]), patch.dict(os.environ), patch.object(worker.time,'sleep'), patch.object(worker.runpy,'run_path',return_value=api), patch.object(worker,'main_policy',return_value=(policy,'blob')), patch.object(worker.subprocess,'run',side_effect=command), patch.object(worker.subprocess,'check_output',return_value='commit'), redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO()):
                    if interrupted:
                        with self.assertRaises(OSError):worker.main()
                    else:
                        worker.main()
                    worker.main()
                    worker.main()
            finally:os.umask(previous_umask)
            self.assertEqual(len(models),2)
            self.assertEqual(read_pr.call_count,4)
            records=list((root/'data/review-auto-handoffs').glob('*.json'))
            self.assertEqual(len(records),1)
            self.assertEqual(json.loads(records[0].read_text())['entry_exit'],0)
            self.assertEqual(len(list((root/'data').rglob('previous.json'))),1)

    def test_target_policy_differs_from_tool_checkout(self):
        import base64,json,tempfile,subprocess
        with tempfile.TemporaryDirectory() as directory:
            repo=Path(directory)
            subprocess.run(['git','init','-q',str(repo)],check=True)
            (repo/'.aiwork').mkdir()
            (repo/'.aiwork/policy.json').write_text(json.dumps({'builders':{'builder':'local-family'}}))
            target={'builders':{'builder':'target-family'}}
            content=base64.b64encode(json.dumps(target).encode()).decode()
            blob='b'*40
            calls=[]
            def github(token,endpoint):
                calls.append(endpoint)
                return {'default_branch':'release/test'} if endpoint=='repos/example/project' else {'sha':blob,'content':content}
            policy,actual=worker.main_policy({'github':github},'token','example/project')
            self.assertEqual(policy,target)
            self.assertEqual(actual,blob)
            self.assertIn('ref=release%2Ftest',calls[-1])
            head='a'*40
            _,_,family,_=worker.builder_for({'head':{'sha':head},'user':{'login':'builder'}},{head:{'target-family'}},policy)
            worker.verify_dispatch_state({'head':head,'policy_sha':blob,'gate':{'summary':'✅ G1 CI'},'excluded':['target-family']},head,actual,family,policy)

if __name__=='__main__':unittest.main()

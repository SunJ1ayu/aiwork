import _no_egress
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest
import sys
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bin"))
import _leg_session
loader=importlib.machinery.SourceFileLoader('handoff',str(Path(__file__).resolve().parents[1]/'bin/review-auto-worker'))
spec=importlib.util.spec_from_loader(loader.name,loader)
worker=importlib.util.module_from_spec(spec)
loader.exec_module(worker)

class Handoff(unittest.TestCase):
    def test_preflight_reads_use_formal_network_retry(self):
        import tempfile, subprocess, io
        from contextlib import redirect_stdout, redirect_stderr
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); control=root/'control'; control.mkdir()
            token_calls=[]; state_calls=[]
            def token(repository):
                token_calls.append(repository)
                if len(token_calls)==1: raise OSError('temporary token failure')
                return 'fixture'
            def state(*args):
                state_calls.append(args)
                if len(state_calls)==1: raise OSError('temporary state failure')
                return {'head':'a'*40,'policy_sha':'blob','excluded':['openai'],'gate':{'summary':'✅ G1 CI'}}
            # Use the actual formal retry implementation, with its waits stubbed.
            import _leg_session
            api={'_leg_session':_leg_session,'review_token':token,'read_dispatch_state':state,
                 'pr_state':lambda *a,**k:{'head':{'sha':'a'*40},'user':{'login':'builder'}},'redact':lambda s:s}
            settings={'checkout':directory,'programs':directory,'repository':'example/repo'}
            with patch.object(worker,'prepare_checkout',return_value=root), patch.object(worker.runpy,'run_path',return_value=api), patch.object(worker,'main_policy',return_value=({'builders':{'builder':'openai'}},'blob')), patch.object(worker.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'{}','')) as dispatch, patch.object(worker.subprocess,'check_output',return_value='commit'), patch.object(_leg_session.time,'sleep'), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()), patch.dict(worker.os.environ):
                worker.dispatch_attempt(settings,{'a'*40:{'openai'}},1,root,control)
            self.assertEqual(len(token_calls),2)
            self.assertEqual(len(state_calls),2)
            dispatch.assert_called_once()

    def test_completed_request_skips_capacity_clone_and_network(self):
        self.receipt_sequence(late=False)

    def test_parent_reports_committed_result_after_deadline(self):
        self.receipt_sequence(late=True)

    def receipt_sequence(self, late):
        import tempfile,json,io
        import _aiwork_config
        from contextlib import redirect_stdout
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            repository='example/repo'; head='a'*40
            control=root/'review-handoffs'/(worker.hashlib.sha256(repository.encode()).hexdigest()+'-1')
            control.mkdir(parents=True)
            if not late:
                worker.write_record(control/(head+'.json'),{'pr':1,'head':head,'state':'finished','entry_exit':0})
            context=root/'context'; settings=root/'settings'
            context.write_text(json.dumps({'events':[{'source':'trusted','type':'reviews.request','subject':repository+'#1','detail':json.dumps({'repository':repository,'pr':1,'head':head,'builder_family':'openai'})}]}))
            settings.write_text(json.dumps({'checkout':directory,'programs':directory,'repository':repository,'event_source':'trusted'}))
            def dispatch(command,env,timeout,locks):
                import subprocess
                unit=Path(command[-1])
                facts={'pr':1,'head':head,'state':'finished','entry_exit':0,'attempt':unit.name}
                worker.write_record(control/(head+'.json'),facts)
                return subprocess.CompletedProcess(command,124,'','late timeout')
            from contextlib import nullcontext
            capacity = (lambda *a:nullcontext(None)) if late else (lambda *a: self.fail('must not acquire capacity'))
            with patch.object(worker.sys,'argv',['worker',str(context),str(settings)]), patch.object(_aiwork_config,'data_path',side_effect=lambda key:root/key), patch.object(worker,'capacity',side_effect=capacity), patch.object(worker,'prepare_checkout',side_effect=AssertionError('must not clone')), patch.object(worker,'run_dispatch',side_effect=dispatch if late else AssertionError('must not access GitHub')), redirect_stdout(io.StringIO()) as output:
                worker.main()
            self.assertIn('本轮已结束' if late else '已交接',output.getvalue())
            self.assertNotIn('未完成',output.getvalue())

    def test_early_dedup_requires_valid_success_for_every_requested_head(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); head='a'*40
            facts={'pr':1,'head':head,'state':'finished','entry_exit':0}
            for changes in ({'pr':2},{'head':'b'*40},{'entry_exit':True},{'entry_exit':1},{'state':'started'}):
                worker.write_record(root/(head+'.json'),dict(facts,**changes))
                self.assertFalse(worker.completed_requests(root,{head:{'openai'}},1))
            worker.write_record(root/(head+'.json'),facts)
            self.assertTrue(worker.completed_requests(root,{head:{'openai'}},1))
            self.assertFalse(worker.completed_requests(root,{head:{'openai'},'b'*40:{'openai'}},1))

    def test_committed_attempt_overrides_late_deadline_only_for_same_attempt(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); unit=root/'attempt';unit.mkdir();control=root/'control';control.mkdir()
            facts={'pr':1,'head':'a'*40,'state':'finished','entry_exit':0,'attempt':unit.name}
            worker.write_record(control/('a'*40+'.json'),facts)
            self.assertEqual(worker.committed_attempt(control,unit,{'a'*40:{'openai'}},1),facts)
            facts['attempt']='previous-attempt'
            worker.write_record(control/('a'*40+'.json'),facts)
            self.assertIsNone(worker.committed_attempt(control,unit,{'a'*40:{'openai'}},1))

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

    def test_corrupt_record_recovers_full_dispatch(self):
        self.main_sequence(interrupted=False, corrupt=True)

    def main_sequence(self, interrupted, corrupt=False):
        import tempfile,json,subprocess,os,io
        from contextlib import redirect_stdout,redirect_stderr
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            control=root/'control'
            control.mkdir()
            if corrupt:(control/('a'*40+'.json')).write_text('{')
            settings={'checkout':str(root),'programs':str(root),'repository':'example/repo','event_source':'trusted'}
            policy={'builders':{'builder':'openai'}}
            pr={'head':{'sha':'a'*40},'user':{'login':'builder'}}
            state={'head':'a'*40,'policy_sha':'blob','excluded':['openai'],'gate':{'summary':'✅ G1 current CI'}}
            api={'_leg_session':_leg_session,'review_token':lambda repo:'token','pr_state':lambda *args,**kw:pr,'read_dispatch_state':lambda *args:state,'redact':lambda value:value}
            models=[]
            def command(argv,**kwargs):
                models.append(argv)
                if interrupted and len(models)==1:
                    raise OSError('dispatch start failed')
                return subprocess.CompletedProcess(argv,2 if len(models)==1 else 0,'{}','')
            def attempt():
                unit=root/('attempt-'+str(len(list(root.glob('attempt-*')))))
                unit.mkdir()
                worker.dispatch_attempt(settings,{'a'*40:{'openai'}},1,unit,control)
            with patch.dict(os.environ), patch.object(worker,'prepare_checkout',return_value=root), patch.object(worker.runpy,'run_path',return_value=api), patch.object(worker,'main_policy',return_value=(policy,'blob')), patch.object(worker.subprocess,'run',side_effect=command), patch.object(worker.subprocess,'check_output',return_value='commit'), redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO()):
                if interrupted:
                    with self.assertRaises(OSError):attempt()
                else:
                    attempt()
                attempt()
                attempt()
            self.assertEqual(len(models),2)
            records=list(control.glob('*.json'))
            self.assertEqual(len(records),1)
            self.assertEqual(json.loads(records[0].read_text())['entry_exit'],0)
            self.assertEqual(len(list(root.rglob('previous.json'))),2 if corrupt else 1)

    def test_capacity_settings_and_invalid_values(self):
        import tempfile,json
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'settings'
            settings={'checkout':directory,'programs':directory,'repository':'example/repo','event_source':'trusted'}
            path.write_text(json.dumps(settings))
            self.assertEqual(worker.load_settings(path)['concurrency'],1)
            for value in (1,2,3,17):
                path.write_text(json.dumps(dict(settings,concurrency=value)))
                self.assertEqual(worker.load_settings(path)['concurrency'],value)
            for value in (0,-1,True,'2',2.5,None):
                path.write_text(json.dumps(dict(settings,concurrency=value)))
                with self.assertRaises(ValueError):worker.load_settings(path)
            path.write_text('{')
            with self.assertRaises(ValueError):worker.load_settings(path)
            path.unlink()
            with self.assertRaises(OSError):worker.load_settings(path)

    def test_real_process_capacity_and_queue(self):
        import tempfile,json,multiprocessing,time
        ctx=multiprocessing.get_context('fork')
        for limit in (1,2,3):
            with self.subTest(limit=limit), tempfile.TemporaryDirectory() as directory:
                root=Path(directory)
                settings=root/'settings'
                settings.write_text(json.dumps({'checkout':directory,'programs':directory,'repository':'example/repo','event_source':'trusted','concurrency':limit}))
                active=ctx.Value('i',0)
                peak=ctx.Value('i',0)
                gate=ctx.Event()
                admitted=ctx.Queue()
                def job():
                    with worker.capacity(root/'locks',settings):
                        with active.get_lock():
                            active.value+=1
                            peak.value=max(peak.value,active.value)
                        admitted.put(True)
                        gate.wait(10)
                        with active.get_lock():active.value-=1
                processes=[ctx.Process(target=job) for _ in range(limit+2)]
                try:
                    for process in processes:process.start()
                    for _ in range(limit):admitted.get(timeout=10)
                    import queue
                    with self.assertRaises(queue.Empty):admitted.get(timeout=0.4)
                    self.assertEqual(peak.value,limit)
                    gate.set()
                    for process in processes:
                        process.join(10)
                        self.assertEqual(process.exitcode,0)
                    self.assertLessEqual(peak.value,limit)
                finally:
                    gate.set()
                    for process in processes:
                        if process.is_alive():process.kill()
                        process.join()

    def test_atomic_record_and_corruption_recovery(self):
        import tempfile,json
        with tempfile.TemporaryDirectory() as directory:
            record=Path(directory)/'record.json'
            for value in ('', '{', '[]', '{}', '{"state":"finished"}'):
                record.write_text(value)
                self.assertIsNone(worker.read_record(record))
            old={'state':'started'}
            worker.write_record(record,old)
            with patch.object(worker.json,'dump',side_effect=OSError('disk full')):
                with self.assertRaises(OSError):worker.write_record(record,{'state':'finished','entry_exit':0})
            self.assertEqual(worker.read_record(record),old)
            self.assertEqual(list(Path(directory).glob('record-*')),[])
            worker.write_record(record,{'state':'finished','entry_exit':0})
            self.assertEqual(worker.read_record(record),{'state':'finished','entry_exit':0})

    def test_independent_real_git_checkouts(self):
        import tempfile,subprocess,os
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            upstream=root/'upstream'
            subprocess.run(['git','init','-q','-b','main',str(upstream)],check=True)
            subprocess.run(['git','-C',str(upstream),'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','initial'],check=True)
            source=root/'source'
            subprocess.run(['git','clone','-q',str(upstream),str(source)],check=True)
            first=root/'first';first.mkdir()
            second=root/'second';second.mkdir()
            one=worker.prepare_checkout(source,first,dict(os.environ))
            subprocess.run(['git','-C',str(upstream),'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','next'],check=True)
            two=worker.prepare_checkout(source,second,dict(os.environ))
            def head(path):return subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True)
            self.assertNotEqual(head(one),head(two))
            self.assertEqual(head(source),head(one))
            self.assertNotEqual((one/'.git').stat().st_ino,(two/'.git').stat().st_ino)
            (one/'private-attempt').write_text('one')
            self.assertFalse((two/'private-attempt').exists())

    def test_duplicate_concurrent_attempt_dispatches_once(self):
        import tempfile,multiprocessing,json,subprocess,os,io,time
        from contextlib import redirect_stdout,redirect_stderr
        ctx=multiprocessing.get_context('fork')
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);control=root/'control';control.mkdir()
            count=ctx.Value('i',0)
            def job(index):
                unit=root/str(index);unit.mkdir()
                settings={'checkout':directory,'programs':directory,'repository':'example/repo'}
                api={'_leg_session':_leg_session,'review_token':lambda r:'token','pr_state':lambda *a,**k:{'head':{'sha':'a'*40},'user':{'login':'builder'}},'read_dispatch_state':lambda *a:{'head':'a'*40,'policy_sha':'blob','excluded':['openai'],'gate':{'summary':'✅ G1 CI'}},'redact':lambda s:s}
                def run(argv,**kw):
                    with count.get_lock():count.value+=1
                    time.sleep(0.3)
                    return subprocess.CompletedProcess(argv,0,'{}','')
                with patch.dict(os.environ),patch.object(worker,'prepare_checkout',return_value=root),patch.object(worker.runpy,'run_path',return_value=api),patch.object(worker,'main_policy',return_value=({'builders':{'builder':'openai'}},'blob')),patch.object(worker.subprocess,'run',side_effect=run),patch.object(worker.subprocess,'check_output',return_value='commit'),redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO()):
                    worker.dispatch_attempt(settings,{'a'*40:{'openai'}},1,unit,control)
            processes=[ctx.Process(target=job,args=(i,)) for i in range(2)]
            try:
                for process in processes:process.start()
                for process in processes:
                    process.join(10);self.assertEqual(process.exitcode,0)
                self.assertEqual(count.value,1)
            finally:
                for process in processes:
                    if process.is_alive():process.kill()
                    process.join()

    def test_deadline_kills_descendants_with_separate_sessions(self):
        import tempfile,subprocess,sys,os,time
        probe=subprocess.run(['/usr/bin/unshare','--mount','--pid','--fork','--mount-proc','--','true'],capture_output=True)
        if probe.returncode:
            if os.environ.get('CI'):self.fail('CI must support the production PID namespace')
            self.skipTest('local environment does not permit PID/mount namespaces')
        with tempfile.TemporaryDirectory() as directory:
            heartbeat=Path(directory)/'heartbeat'
            child="import time;from pathlib import Path;p=Path("+repr(str(heartbeat))+");\nwhile True:p.write_text(str(time.monotonic()));time.sleep(0.02)"
            command=[sys.executable,'-c',"import subprocess,time,sys;subprocess.Popen([sys.executable,'-c',"+repr(child)+"],start_new_session=True);time.sleep(60)"]
            result=worker.run_dispatch(command,dict(os.environ),1,[])
            self.assertEqual(result.returncode,124)
            self.assertTrue(heartbeat.exists())
            last=heartbeat.read_text()
            time.sleep(0.15)
            self.assertEqual(heartbeat.read_text(),last)

    def test_legacy_success_is_preserved(self):
        import tempfile,json
        import _aiwork_config
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            legacy=root/'review-auto-handoffs';legacy.mkdir()
            record=root/'current.json'
            unit=root/'attempt';unit.mkdir()
            facts={'pr':1,'head':'a'*40,'state':'finished','entry_exit':0}
            (legacy/('1-'+'a'*40+'.json')).write_text(json.dumps(facts))
            with patch.object(_aiwork_config,'data_path',return_value=root):
                worker.preserve_legacy(record,unit,1,'a'*40)
            self.assertEqual(worker.read_record(record),facts)
            self.assertTrue((legacy/('1-'+'a'*40+'.json')).exists())

    def test_full_worker_parallel_receipts_and_retry_after_timeout(self):
        import tempfile,json,subprocess,sys,os,time
        probe=subprocess.run(['/usr/bin/unshare','--mount','--pid','--fork','--mount-proc','--','true'],capture_output=True)
        if probe.returncode:
            if os.environ.get('CI'):self.fail('CI must support the production PID namespace')
            self.skipTest('local environment does not permit PID/mount namespaces')
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            source=root/'source';source.mkdir();(source/'bin').mkdir()
            fake=source/'bin/review-pr'
            fake.write_text("""#!/usr/bin/python3
import base64,json,sys,time,os
from types import SimpleNamespace
_leg_session=SimpleNamespace(network_read=lambda operation:operation())
from pathlib import Path
policy={'builders':{'builder':'openai'}}
def review_token(repository):return 'fixture'
def github(token,endpoint):
    return {'sha':'b'*40,'content':base64.b64encode(json.dumps(policy).encode()).decode()} if '/contents/' in endpoint else {'default_branch':'main'}
def pr_state(*args,**kwargs):return {'head':{'sha':'a'*40},'user':{'login':'builder'}}
def read_dispatch_state(*args):return {'head':'a'*40,'policy_sha':'b'*40,'excluded':['openai'],'gate':{'summary':'✅ G1 CI'}}
def redact(value):return value
if __name__=='__main__':
    (Path(os.environ['FIXTURE_MARKERS'])/sys.argv[1]).write_text(str(time.monotonic()))
    time.sleep(float(os.environ.get('FIXTURE_SLEEP','0.4')))
    print('{}')
""")
            fake.chmod(0o755)
            subprocess.run(['git','init','-q','-b','main',str(source)],check=True)
            subprocess.run(['git','-C',str(source),'add','.'],check=True)
            subprocess.run(['git','-C',str(source),'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture'],check=True)
            subprocess.run(['git','-C',str(source),'remote','add','origin',str(source)],check=True)
            data=root/'data';data.mkdir()
            markers=root/'markers';markers.mkdir()
            settings=root/'settings'
            values={'checkout':str(source),'programs':str(root),'repository':'example/repo','event_source':'trusted','concurrency':2,'timeout_seconds':10}
            settings.write_text(json.dumps(values))
            env=dict(os.environ,AIWORK_DATA_DIR=str(data),FIXTURE_MARKERS=str(markers),FIXTURE_SLEEP='1.5')
            command=[sys.executable,str(Path(worker.__file__).resolve())]
            def context(number):
                path=root/('context-'+str(number))
                path.write_text(json.dumps({'events':[{'source':'trusted','type':'reviews.request','subject':'example/repo#'+str(number),'detail':json.dumps({'repository':'example/repo','pr':number,'head':'a'*40,'builder_family':'openai'})}]}))
                return path
            contexts=[context(1),context(2)]
            processes=[subprocess.Popen([*command,str(path),str(settings)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) for path in contexts]
            try:
                for process in processes:
                    out,err=process.communicate(timeout=20)
                    self.assertEqual(process.returncode,0,out+err)
                stamps=[float((markers/str(n)).read_text()) for n in (1,2)]
                self.assertLess(abs(stamps[0]-stamps[1]),1.5)
                before=(markers/'1').read_text()
                duplicate=subprocess.run([*command,str(contexts[0]),str(settings)],env=env,capture_output=True,text=True,timeout=20)
                self.assertEqual(duplicate.returncode,0,duplicate.stdout+duplicate.stderr)
                self.assertEqual((markers/'1').read_text(),before)
                units=list((data/'tasks').glob('review-handoff-*'))
                self.assertEqual(len(units),2)
                self.assertEqual(len({str(unit/'checkout') for unit in units}),2)
                self.assertEqual(len(list((data/'review-handoffs').rglob('*.json'))),2)
                values['timeout_seconds']=3
                settings.write_text(json.dumps(values))
                third=context(3)
                failed=subprocess.run([*command,str(third),str(settings)],env=dict(env,FIXTURE_SLEEP='60'),capture_output=True,text=True,timeout=15)
                self.assertNotEqual(failed.returncode,0)
                values['timeout_seconds']=30
                settings.write_text(json.dumps(values))
                recovered=subprocess.run([*command,str(third),str(settings)],env=env,capture_output=True,text=True,timeout=20)
                self.assertEqual(recovered.returncode,0,recovered.stdout+recovered.stderr)
                self.assertEqual(len(list((data/'tasks').rglob('previous.json'))),1)
            finally:
                for process in processes:
                    if process.poll() is None:process.kill()
                    process.wait()

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

    def test_gate_summary_and_family_contract_from_definitions(self):
        import subprocess,json,re
        root=Path(__file__).resolve().parents[1]
        bridge=(root/'bin/_review_dispatch.mjs').read_text()
        self.assertIn('/^'+worker.FAMILY_PATTERN+'$/',bridge)
        script="""import {decide} from './gate/decide.mjs';
import fs from 'node:fs';
const policy=JSON.parse(fs.readFileSync('tests/fixtures/gate-logic-policy.json'));
const f={pr:{number:1,state:'open',head_sha:'a'.repeat(40)},files:['file.txt'],reviews:[],ci:{state:'success',detail:'test'},pushes:{covers_head:true,actors:[]}};
console.log(JSON.stringify(decide(f,policy)));
"""
        result=json.loads(subprocess.check_output(['node','--input-type=module','-e',script],cwd=root,text=True))
        policy={'builders':{'builder':'openai'},'unknown_author_extra_families':[]}
        worker.verify_dispatch_state({'head':'a'*40,'policy_sha':'blob','gate':result,'excluded':['openai']},'a'*40,'blob',None,policy)

if __name__=='__main__':unittest.main()

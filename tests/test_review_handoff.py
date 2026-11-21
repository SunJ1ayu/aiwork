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
        self.assertFalse(worker.retryable({'state':'started'}))

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

if __name__=='__main__':unittest.main()

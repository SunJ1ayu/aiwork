import _no_egress
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0, str(ROOT / 'bin'))
loader = importlib.machinery.SourceFileLoader('notice_publisher', str(ROOT / 'bin/review-pr'))
spec = importlib.util.spec_from_loader(loader.name, loader)
publisher = importlib.util.module_from_spec(spec)
loader.exec_module(publisher)

class Notice(unittest.TestCase):
    def test_notice_is_comment_and_gate_unchanged(self):
        with patch.object(publisher, 'review_token', return_value='token'), patch.object(publisher._leg_session, 'run'), patch.object(publisher, 'github') as api:
            publisher.publish_dispatch_failure('example/repo', 1, 'a'*40, ['subkimi'])
        endpoint, payload = api.call_args.args[1:]
        self.assertEqual(endpoint, 'repos/example/repo/issues/1/comments')
        script = '''import {decide} from './gate/decide.mjs';
import fs from 'node:fs';
const notice=JSON.parse(fs.readFileSync(0,'utf8'));
const policy=JSON.parse(fs.readFileSync('tests/fixtures/gate-logic-policy.json'));
const head='a'.repeat(40);
const block={verdict:'PASS',head_sha:head,model:'test',family:'openai',completeness:'complete'};
const f={pr:{number:1,state:'open',head_sha:head},files:['web/src/a.ts'],ci:{state:'success',detail:'test'},pushes:{covers_head:true,actors:['SunJ1ayuBoT']},reviews:[{id:1,login:'aiwork-review[bot]',type:'Bot',state:'COMMENTED',commit_id:head,submitted_at:'2026-11-20T00:00:00Z',body:'```json\\n'+JSON.stringify(block)+'\\n```'}]};
const before=decide(f,policy); f.comments=[notice];
if(JSON.stringify(before)!==JSON.stringify(decide(f,policy)))process.exit(1);
if(before.blocks.length)process.exit(2);
'''
        subprocess.run(['node','--input-type=module','-e',script],input=json.dumps(payload),text=True,cwd=ROOT,check=True)

if __name__ == '__main__':
    unittest.main()

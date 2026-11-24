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
    def setUp(self):
        sleeper = patch("time.sleep")
        sleeper.start()
        self.addCleanup(sleeper.stop)

    def test_public_draw_record_is_privacy_checked_and_updated_in_same_comment(self):
        report = {'head': 'a'*40, 'draw': ['subkimi', 'submimo'],
                  'initial': ['subkimi'], 'reserve': ['submimo'],
                  'attempts': [{'leg': 'subkimi', 'ok': False, 'reason': 'timed out', 'failure_kind': 'timeout'}]}
        with patch.object(publisher, 'review_token', return_value='token'), \
             patch.object(publisher._leg_session, 'run') as privacy, \
             patch.object(publisher, 'github', return_value={'id': 123}) as api:
            identifier = publisher.publish_dispatch_record('example/repo', 1, report)
            self.assertEqual(identifier, 123)
            self.assertEqual(api.call_args.args[1], 'repos/example/repo/issues/1/comments')
            body = api.call_args.args[2]['body']
            self.assertNotIn('运行超时', body)
            public = json.loads(body.split('```json\n')[1].split('\n```')[0])
            self.assertEqual(public['draw'], report['draw'])
            self.assertNotIn('failure_kind', public['attempts'][0])
            publisher.publish_dispatch_record('example/repo', 1, report, identifier)
            self.assertEqual(api.call_args.args[1], 'repos/example/repo/issues/comments/123')
            self.assertEqual(api.call_args.kwargs, {'method': 'PATCH'})
            self.assertEqual(privacy.call_count, 2)
            self.assertTrue(all(call.args[0][1] == '--files' for call in privacy.call_args_list))

    def test_public_record_never_copies_diagnostics_or_unknown_fields(self):
        private = '/srv/fixture-user/review-failures/demo on fixture-user@fixture-host token: invalid'
        report = {'head': 'a'*40, 'draw': ['subkimi', private], 'initial': ['subkimi'], 'reserve': [private],
                  'gate': {'summary': private}, 'next_step': private,
                  'attempts': [{'leg': 'subkimi', 'ok': False, 'failure_kind': 'auth',
                                'reason': private, 'url': 'https://github.com/'+private}],
                  'extra': private}
        with patch.object(publisher, 'review_token', return_value='token'), \
             patch.object(publisher._leg_session, 'run'), \
             patch.object(publisher, 'github', return_value={'id': 123}) as api:
            publisher.publish_dispatch_record('example/repo', 1, report)
            publisher.publish_dispatch_failure('example/repo', 1, 'a'*40, ['subkimi'], report)
        for call in api.call_args_list:
            body = call.args[2]['body']
            for value in ('fixture-user', 'fixture-host', '/srv/', 'token: invalid'):
                self.assertNotIn(value, body)
        body = api.call_args.args[2]['body']
        for value in ('fixture-user', 'fixture-host', '/srv/', 'token: invalid'):
            self.assertNotIn(value, body)
        public = json.loads(body.split('```json\n')[1].split('\n```')[0])
        self.assertNotIn('failure_kind', public['attempts'][0])
        self.assertNotIn('gate', public)

    def test_timeout_is_not_public_failure_and_stop_preserves_started_legs(self):
        cases = [
            {'head': 'a'*40, 'attempts': [{'leg': 'subkimi', 'status': 'finished',
              'ok': False, 'confirmed': False, 'failure_kind': 'timeout', 'reason': 'review leg failed: timeout'}]},
            {'head': 'a'*40, 'stopped': 'head_changed', 'attempts': [{'leg': 'subkimi',
              'status': 'finished', 'ok': True, 'confirmed': True}]},
        ]
        with patch.object(publisher, 'review_token', return_value='token'), \
             patch.object(publisher._leg_session, 'run'), \
             patch.object(publisher, 'github', return_value={'id': 123}) as api:
            for report in cases:
                publisher.publish_dispatch_failure('example/repo', 1, 'a'*40, ['subkimi'], report)
                body = api.call_args.args[2]['body']
                public = json.loads(body.split('```json\n')[1].split('\n```')[0])
                for item in public['attempts']:
                    self.assertNotIn('ok', item)
                    self.assertNotIn('failure_kind', item)
                    self.assertNotIn('reason', item)
                    self.assertTrue(item['started'])
                if report.get('stopped'):
                    self.assertEqual(public['stopped'], 'head_changed')
                    self.assertNotIn('confirmed', public['attempts'][0])
                else:
                    self.assertFalse(public['attempts'][0]['confirmed'])

    def test_every_defined_stop_reason_is_public_and_unknown_stop_stays_stopped(self):
        unknown = '/srv/fixture-user on fixture-host: unknown stop'
        public = publisher.public_dispatch_report({'stopped': unknown})
        self.assertTrue(public['stopped'])
        self.assertTrue(public['stop_reason'])
        self.assertNotIn(unknown, json.dumps(public))

        from _review_dispatch import StopReason, DispatchStopped
        for reason in StopReason:
            with self.subTest(reason=reason):
                stop = DispatchStopped(reason)
                public = publisher.public_dispatch_report({'stopped': stop.reason,
                    'attempts': [{'leg': 'subkimi', 'confirmed': True}]})
                self.assertEqual(public['stopped'], reason.value)
                self.assertEqual(public['stop_reason'], reason.description)
                self.assertNotIn('confirmed', public['attempts'][0])

    def test_dispatch_producers_use_the_shared_stop_definition(self):
        from _review_dispatch import dispatch, DispatchStopped, StopReason
        from test_review_dispatch import view
        for field, expected in (('head', StopReason.HEAD_CHANGED),
                                ('policy_sha', StopReason.POLICY_CHANGED),
                                (None, StopReason.STATE_UNAVAILABLE)):
            with self.subTest(field=field):
                state = view(order=['subkimi'])
                reads = 0
                def read(_):
                    nonlocal reads
                    reads += 1
                    if reads > 1:
                        if field is None:
                            raise OSError('local diagnostic')
                        state[field] += 'x'
                    return state.copy()
                with self.assertRaises(DispatchStopped) as caught:
                    dispatch(read, lambda _: ('moonshot', None), lambda *a: {}, 'openai')
                public = publisher.public_dispatch_report({'stopped': caught.exception.reason})
                self.assertEqual(public['stopped'], expected.value)
                self.assertEqual(public['stop_reason'], expected.description)

    def test_privacy_failure_prevents_publication(self):
        with patch.object(publisher._leg_session, 'run', side_effect=publisher.ReviewError('privacy blocked')), \
             patch.object(publisher, 'github', return_value={'id': 123}) as api:
            with self.assertRaisesRegex(publisher.ReviewError, 'privacy blocked'):
                publisher.publish_dispatch_record('example/repo', 1, {'draw': []})
            api.assert_not_called()

    def test_notice_is_comment_and_gate_unchanged(self):
        with patch.object(publisher, 'review_token', return_value='token'), patch.object(publisher._leg_session, 'run'), patch.object(publisher, 'github', return_value={'id': 123}) as api:
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


class CommentNetworkTests(unittest.TestCase):
    def setUp(self):
        from contextlib import ExitStack
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.posts, self.comments = [], []
        self.failure = None
        self.login = 'project-review[bot]'
        self.accepted = False
        self.pending = {}
        self.reads = 0
        self.visible_after = 0
        for target, name, kwargs in (
            (publisher, 'review_token', {'return_value': 'fixture-token'}),
            (publisher, 'project_reviewer_bot', {'return_value': 'project-review[bot]'}),
            (publisher._leg_session, 'run', {}),
            (publisher, 'github', {'side_effect': self.api}),
        ):
            self.stack.enter_context(patch.object(target, name, **kwargs))
        self.stack.enter_context(patch('time.sleep'))

    def api(self, _token, endpoint, payload=None, **kwargs):
        if payload is None:
            self.reads += 1
            if self.reads <= self.visible_after:
                return '[]'
            if '/comments?' in endpoint:
                return json.dumps(self.comments)
            return self.comments[-1]
        self.posts.append((endpoint, payload, kwargs))
        item = {'id': 123, 'body': payload['body'],
                'user': {'login': self.login, 'type': 'Bot'}}
        if self.accepted or self.failure is None:
            self.comments[:] = [item]
        if self.failure:
            failure, self.failure = self.failure, None
            raise failure
        return item

    def publish(self, body='report', comment_id=None):
        return publisher.publish_dispatch_comment('fixture/project', 12, body,
                                                   comment_id, pending=self.pending)

    def test_proven_unsent_comment_is_retried(self):
        self.failure = publisher.UnsentWriteError('TLS handshake timeout')
        self.assertEqual(self.publish(), 123)
        self.assertEqual(len(self.posts), 2)
        self.assertEqual(self.posts[0][1], self.posts[1][1])

    def test_accepted_comment_recovers_delayed_id_without_duplicate(self):
        self.failure, self.accepted, self.visible_after = OSError('response EOF'), True, 2
        self.assertEqual(self.publish(), 123)
        self.assertEqual(len(self.posts), 1)
        self.assertGreater(self.reads, 2)

    def test_later_report_recovers_pending_creation_before_patch(self):
        self.failure, self.accepted = OSError('response EOF'), True
        self.visible_after = publisher._leg_session.RETRY_ATTEMPTS * 3
        with self.assertRaises(OSError):
            self.publish()
        with self.assertRaises(publisher.ReviewError):
            self.publish('new report')
        self.assertEqual(len(self.posts), 1)
        self.visible_after = 0
        self.assertEqual(self.publish('new report'), 123)
        self.assertEqual(len(self.posts), 2)
        self.assertEqual(self.posts[-1][2], {'method': 'PATCH'})
        self.assertEqual(self.pending, {})

    def test_ambiguous_patch_checks_same_comment_instead_of_reposting(self):
        self.publish()
        self.failure, self.accepted = publisher.ReviewError('read timeout'), True
        self.assertEqual(self.publish('new report', 123), 123)
        self.assertEqual(len(self.posts), 2)
        self.assertEqual(self.posts[-1][2], {'method': 'PATCH'})

    def test_other_bot_cannot_confirm_comment_receipt(self):
        self.failure, self.accepted = OSError('response EOF'), True
        self.login = 'other-review[bot]'
        with self.assertRaises(OSError):
            self.publish()
        self.assertEqual(len(self.posts), 1)

if __name__ == '__main__':
    unittest.main()

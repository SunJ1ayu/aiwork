#!/usr/bin/env python3
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bin'))
import unittest
import threading
from _review_dispatch import dispatch as real_dispatch

def dispatch(*args, **kwargs):
    kwargs.setdefault("shuffle", lambda items: None)
    return real_dispatch(*args, **kwargs)


def view(target=3, order=None):
    return {'head': 'a' * 40, 'policy_sha': 'b' * 40,
            'plan': {'tier': 'high', 'target': target, 'minimum': 2, 'order': order or ['a', 'b', 'c', 'd']},
            'pass_families': [], 'reviewed_families': [], 'excluded': ['anthropic', 'openai'],
            'minimum_met': False, 'target_met': False, 'missing_target': target,
            'next_step': '交业主', 'gate': {'title': '等业主批准'}}


def result_frame(state, passes, reviewed, minimum_met, target_met, missing_target):
    # Explicit gate response fixtures. Qualification itself is exercised by the
    # real JavaScript bridge in test_aiwork_gate_main.mjs, not mocked here.
    state.update(pass_families=passes, reviewed_families=reviewed,
                 minimum_met=minimum_met, target_met=target_met, missing_target=missing_target,
                 next_step='等汇总' if minimum_met else '交业主')


class DispatchTests(unittest.TestCase):
    def run_case(self, failures=(), target=3, families=None, changed=False):
        self.calls = []
        state = view(target)
        families = families or {'a': 'deepseek', 'b': 'moonshot', 'c': 'xiaomi', 'd': 'openai'}
        frames = iter([(False, False, 1), (True, True, 0)] if target == 2 else
                      [(False, False, 2), (True, False, 1), (True, True, 0)])
        lock = threading.Lock()
        def run(leg, model, head):
            with lock:
                self.calls.append(leg)
                if leg in failures:
                    return {'ok': False, 'reason': 'reported failure'}
                state['pass_families'].append(families[leg])
                state['reviewed_families'].append(families[leg])
                floor, goal, missing = next(frames)
                result_frame(state, state['pass_families'], state['reviewed_families'], floor, goal, missing)
                if changed:
                    state['head'] = 'c' * 40
                return {'ok': True, 'url': 'https://github.com/example/review'}
        return dispatch(lambda family: state.copy(), lambda leg: (families[leg], None), run, 'openai')

    def test_parallel_initial_slots_and_replacement_while_other_leg_runs(self):
        import threading
        state = view(target=2, order=['a', 'b', 'c', 'd'])
        started_b = threading.Event()
        replacement = threading.Event()
        lock = threading.Lock()
        calls = []
        def run(leg, model, head):
            with lock:
                calls.append(leg)
            if leg == 'a':
                self.assertTrue(started_b.wait(2), 'second slot must start concurrently')
                return {'ok': False, 'reason': 'failed'}
            if leg == 'b':
                started_b.set()
                self.assertTrue(replacement.wait(2), 'replacement must overlap running leg')
            if leg == 'c':
                replacement.set()
            with lock:
                reviewed = state['reviewed_families'] + [leg]
                result_frame(state, reviewed, reviewed, True, len(reviewed) == 2, 2-len(reviewed))
            return {'ok': True}
        report = dispatch(lambda _: state.copy(), lambda leg: (leg, None), run, 'openai')
        self.assertEqual(set(calls), {'a', 'b', 'c'})
        self.assertTrue(report['target_met'])

    def test_shuffle_once_after_exclusions_and_record_actual_draw(self):
        state = view(target=1, order=['author', 'a', 'b'])
        seen = []
        records = []
        def shuffle(items):
            seen.append(list(items))
            items.reverse()
        def run(leg, *args):
            result_frame(state, ['b'], ['b'], True, True, 0)
            return {'ok': True}
        report = dispatch(lambda _: state.copy(), lambda leg: ('openai' if leg == 'author' else leg, None),
                          run, 'openai', shuffle=shuffle, record=lambda value: records.append(value))
        self.assertEqual(len(seen), 1)
        self.assertEqual([item[0] for item in seen[0]], ['a', 'b'])
        self.assertEqual(report['draw'], ['b', 'a'])
        self.assertEqual(records[0]['draw'], ['b', 'a'])
        self.assertEqual(records[0]['initial'], ['b'])
        self.assertEqual(records[0]['reserve'], ['a'])

    def test_unconfirmed_success_and_child_exception_take_reserves(self):
        for outcome in ({'ok': True, 'url': 'https://github.com/example/review'}, OSError('child unavailable')):
            with self.subTest(outcome=outcome):
                state = view(target=1, order=['a', 'b'])
                calls = []
                records = []
                def run(leg, *args):
                    calls.append(leg)
                    if leg == 'a':
                        if isinstance(outcome, Exception):
                            raise outcome
                        return outcome
                    result_frame(state, ['b'], ['b'], True, True, 0)
                    return {'ok': True}
                result = dispatch(lambda _: state.copy(), lambda leg: (leg, None), run, 'openai',
                                  record=records.append)
                self.assertEqual(set(calls), {'a', 'b'})
                self.assertFalse(result['attempts'][0]['confirmed'])
                self.assertIn('confirmation_reason', result['attempts'][0])
                self.assertEqual(records[0]['attempts'], [])
                self.assertEqual(records[-1], result)

    def test_public_record_failure_stops_before_starting_any_model(self):
        from unittest.mock import Mock
        run = Mock()
        def fail(_):
            raise OSError('cannot publish draw')
        with self.assertRaisesRegex(OSError, 'publish draw'):
            dispatch(lambda _: view(), lambda leg: (leg, None), run, 'openai', record=fail)
        run.assert_not_called()

    def test_identification_failure_is_in_public_record_and_does_not_consume_slot(self):
        state = view(target=1, order=['bad', 'a'])
        def identify(leg):
            if leg == 'bad':
                raise ValueError('unsupported model')
            return leg, None
        def run(leg, *args):
            result_frame(state, ['a'], ['a'], True, True, 0)
            return {'ok': True}
        records = []
        report = dispatch(lambda _: state.copy(), identify, run, 'openai', record=records.append)
        self.assertEqual(records[0]['attempts'][0]['reason'], 'unsupported model')
        self.assertEqual(report['initial'], ['a'])
        self.assertTrue(report['target_met'])

    def test_gate_minimum_result_is_authoritative_even_if_local_count_disagrees(self):
        for minimum_met, passes in [(True, []), (False, ['deepseek', 'moonshot'])]:
            state = view(order=['a'])
            result_frame(state, passes, ['deepseek', 'moonshot'], minimum_met, True, 0)
            calls = []
            result = dispatch(lambda family: state.copy(), lambda leg: ('deepseek', None),
                              lambda *args: calls.append(args) or {'ok': False}, 'openai')
            self.assertEqual(result['minimum_met'], minimum_met)
            self.assertEqual(calls, [])

    def test_already_complete_block_is_not_dispatched_again(self):
        state = view(target=2, order=['a', 'b'])
        result_frame(state, [], ['deepseek'], False, False, 1)
        calls = []
        result = dispatch(lambda family: state.copy(),
                          lambda leg: ({'a': 'deepseek', 'b': 'moonshot'}[leg], None),
                          lambda leg, *args: calls.append(leg) or {'ok': False, 'reason': 'failure'}, 'openai')
        self.assertEqual(calls, ['b'])
        self.assertEqual(result['reviewed_families'], ['deepseek'])

    def test_failure_tries_next_in_draw_order(self):
        result = self.run_case(failures=['a'], target=2)
        self.assertEqual(set(self.calls), {'a', 'b', 'c'})
        self.assertTrue(result['minimum_met'])
        self.assertTrue(result['target_met'])
        self.assertEqual(result['attempts'][0]['reason'], 'reported failure')

    def test_exhaustion_below_floor_is_owner_handoff(self):
        result = self.run_case(failures=['a', 'b'])
        self.assertEqual(set(self.calls), {'a', 'b', 'c'})
        self.assertFalse(result['minimum_met'])
        self.assertEqual(result['next_step'], '交业主')

    def test_floor_met_missing_target_does_not_block(self):
        result = self.run_case(failures=['a'])
        self.assertEqual(set(self.calls), {'a', 'b', 'c'})
        self.assertTrue(result['minimum_met'])
        self.assertFalse(result['target_met'])
        self.assertEqual(result['missing_target'], 1)

    def test_same_family_and_builder_never_fill_budget(self):
        result = self.run_case(families={'a': 'openai', 'b': 'deepseek', 'c': 'deepseek', 'd': 'anthropic'})
        self.assertEqual(self.calls, ['b'])
        self.assertFalse(result['minimum_met'])

    def test_head_change_stops_without_reviewing_other_head(self):
        with self.assertRaisesRegex(ValueError, 'head'):
            self.run_case(changed=True, target=1)
        self.assertEqual(self.calls, ['a'])

    def test_block_is_a_completed_review_but_not_a_pass(self):
        state = view(target=2, order=['a', 'b', 'c'])
        calls = []
        first_done = threading.Event()
        def run(leg, model, head):
            calls.append(leg)
            if leg == 'a':
                result_frame(state, [], ['deepseek'], False, False, 1)
                first_done.set()
            else:
                self.assertTrue(first_done.wait(2))
                result_frame(state, ['moonshot'], ['deepseek', 'moonshot'], True, True, 0)
            return {'ok': True, 'url': 'https://github.com/example/review'}
        result = dispatch(lambda family: state.copy(),
                          lambda leg: ({'a': 'deepseek', 'b': 'moonshot', 'c': 'xiaomi'}[leg], None), run, 'openai')
        self.assertEqual(set(calls), {'a', 'b'})
        self.assertTrue(result['target_met'])
        self.assertTrue(result['minimum_met'])

    def test_lost_publication_response_uses_actual_gate_state(self):
        state = view(target=2, order=['a', 'b'])
        first_done = threading.Event()
        def run(leg, model, head):
            if leg == 'a':
                result_frame(state, ['deepseek'], ['deepseek'], True, False, 1)
                first_done.set()
                return {'ok': False, 'reason': 'publication response lost'}
            self.assertTrue(first_done.wait(2))
            result_frame(state, ['deepseek', 'moonshot'], ['deepseek', 'moonshot'], True, True, 0)
            return {'ok': True, 'url': 'https://github.com/example/review'}
        result = dispatch(lambda family: state.copy(),
                          lambda leg: ({'a': 'deepseek', 'b': 'moonshot'}[leg], None), run, 'openai')
        self.assertTrue(result['target_met'])
        self.assertEqual(result['missing_target'], 0)
        self.assertFalse(result['attempts'][0]['ok'])

    def test_policy_change_stops(self):
        state = view(order=['a', 'b'])
        def read(family):
            state['policy_sha'] += 'x'
            return state.copy()
        with self.assertRaisesRegex(ValueError, 'policy'):
            dispatch(read, lambda leg: ('deepseek', None), lambda *args: {'ok': False}, 'openai')


class PublisherIntegrationTests(unittest.TestCase):
    def load_publisher(self):
        import importlib.util
        import importlib.machinery
        root = Path(__file__).resolve().parents[1]
        loader = importlib.machinery.SourceFileLoader('dispatch_publisher', str(root / 'bin/review-pr'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        publisher = importlib.util.module_from_spec(spec)
        loader.exec_module(publisher)
        return publisher

    def test_auto_pins_head_and_cursor_model_and_keeps_logs_outside_repo(self):
        self.publisher_case(True)

    def test_partial_or_unconfirmed_publication_does_not_fill_target(self):
        for complete in (False, None):
            with self.subTest(complete=complete):
                self.publisher_case(complete)

    def test_notice_failure_preserves_report_and_exit(self):
        self.publisher_case(False, OSError('network unavailable'))

    def publisher_case(self, complete, notice_error=None):
        import tempfile, json, io, subprocess
        from unittest.mock import patch
        from contextlib import redirect_stdout, redirect_stderr
        publisher = self.load_publisher()
        state = view(target=1, order=['subcursor'])
        seen = []
        def run(command, **kwargs):
            seen.append((command, kwargs))
            result_frame(state, ['moonshot'] if complete else [], ['moonshot'] if complete else [],
                         bool(complete), bool(complete), 0 if complete else 1)
            return subprocess.CompletedProcess(command, 0, 'https://github.com/example/review\n', '')
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(publisher, 'publish_dispatch_failure', side_effect=notice_error) as failure_publication, \
             patch.object(publisher, 'publish_dispatch_record', return_value=123) as public_record, \
             patch.object(publisher, 'data_path', return_value=Path(directory)), \
             patch.object(publisher, 'read_dispatch_state', side_effect=lambda *args: state.copy()) as read, \
             patch.object(publisher._leg_session, 'choose_leg', return_value=('moonshot', 'kimi-test')), \
             patch.object(publisher.subprocess, 'run', side_effect=run), \
             patch.dict(os.environ, {'GH_TOKEN': 'not-for-model'}), \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(publisher.auto_dispatch('example/repo', 1, 'openai'), 0 if complete else 2)
            reports = list(Path(directory).glob('*/summary.json'))
            self.assertEqual(len(reports), 1)
            self.assertGreaterEqual(public_record.call_count, 2)
            self.assertIsNone(public_record.call_args_list[0].args[3])
            self.assertEqual(public_record.call_args_list[-1].args[3], 123)
            report = json.loads(reports[0].read_text())
            self.assertEqual(report['pass_families'], ['moonshot'] if complete else [])
            self.assertEqual(report['target_met'], bool(complete))
            self.assertEqual(failure_publication.call_count, 0 if complete else 1)
            self.assertTrue(all(call.args == ('example/repo', 1, 'openai') for call in read.call_args_list))
        command, kwargs = seen[0]
        self.assertEqual(command[-2:], ['--expected-head', 'a' * 40])
        self.assertEqual(kwargs['env']['CURSOR_MODEL'], 'kimi-test')
        self.assertNotIn('GH_TOKEN', kwargs['env'])

    def test_failed_child_diagnostics_stay_local_and_record_errors_do_not_stop_reserve(self):
        import tempfile, io, subprocess, json
        from unittest.mock import patch
        from contextlib import redirect_stdout, redirect_stderr
        publisher = self.load_publisher()
        state = view(target=1, order=['subkimi', 'submimo'])
        private = '/srv/fixture-user/failures/demo fixture-user@fixture-host token: invalid'
        calls, bodies = [], []
        def run(command, **kwargs):
            leg = command[command.index('--leg')+1]
            calls.append(leg)
            if leg == 'subkimi':
                return subprocess.CompletedProcess(command, 2, '', private)
            result_frame(state, ['xiaomi'], ['xiaomi'], True, True, 0)
            return subprocess.CompletedProcess(command, 0, 'https://github.com/example/review\n', '')
        def api(token, endpoint, payload, **kwargs):
            bodies.append(payload['body'])
            return {'id': 123}
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(publisher, 'data_path', return_value=Path(directory)), \
             patch.object(publisher, 'read_dispatch_state', side_effect=lambda *args: state.copy()), \
             patch.object(publisher._leg_session, 'choose_leg', side_effect=lambda leg, _: ('moonshot' if leg == 'subkimi' else 'xiaomi', None)), \
             patch.object(publisher.subprocess, 'run', side_effect=run), \
             patch.object(publisher._leg_session, 'run', side_effect=publisher.ReviewError('privacy: '+private)), \
             patch.object(publisher, 'github', side_effect=api), \
             patch('random.SystemRandom.shuffle', side_effect=lambda items: None), \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(publisher.auto_dispatch('example/repo', 1, 'openai'), 0)
            self.assertEqual(calls, ['subkimi', 'submimo'])
            self.assertEqual(bodies, [])
            self.assertIn('fixture-user@fixture-host', next(Path(directory).glob('*/subkimi.log')).read_text())
            report = json.loads(next(Path(directory).glob('*/summary.json')).read_text())
            self.assertTrue(report['target_met'])

    def test_private_child_error_is_published_only_as_category_and_replaced(self):
        import tempfile, io, subprocess
        from unittest.mock import patch
        from contextlib import redirect_stdout, redirect_stderr
        publisher = self.load_publisher()
        state = view(target=1, order=['subkimi', 'submimo'])
        private = '/srv/fixture-user/failures/demo fixture-user@fixture-host auth failed'
        calls, bodies = [], []
        def run(command, **kwargs):
            leg = command[command.index('--leg')+1]
            calls.append(leg)
            if leg == 'subkimi':
                return subprocess.CompletedProcess(command, 2, '', private)
            result_frame(state, ['xiaomi'], ['xiaomi'], True, True, 0)
            return subprocess.CompletedProcess(command, 0, 'https://github.com/example/review\n', '')
        def api(token, endpoint, payload, **kwargs):
            bodies.append(payload['body'])
            if len(bodies) == 2:
                raise OSError('comment temporarily unavailable '+private)
            return {'id': 123}
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(publisher, 'data_path', return_value=Path(directory)), \
             patch.object(publisher, 'read_dispatch_state', side_effect=lambda *args: state.copy()), \
             patch.object(publisher._leg_session, 'choose_leg', side_effect=lambda leg, _: ('moonshot' if leg == 'subkimi' else 'xiaomi', None)), \
             patch.object(publisher.subprocess, 'run', side_effect=run), \
             patch.object(publisher._leg_session, 'run'), \
             patch.object(publisher, 'review_token', return_value='token'), \
             patch.object(publisher, 'github', side_effect=api), \
             patch('random.SystemRandom.shuffle', side_effect=lambda items: None), \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(publisher.auto_dispatch('example/repo', 1, 'openai'), 0)
        self.assertEqual(calls, ['subkimi', 'submimo'])
        self.assertGreaterEqual(len(bodies), 3)
        for body in bodies:
            self.assertNotIn('fixture-user', body)
            self.assertNotIn('fixture-host', body)
            self.assertNotIn('/srv/', body)

    def test_published_leg_then_head_change_reports_stop_without_failure(self):
        import tempfile, io, subprocess, json
        from unittest.mock import patch
        from contextlib import redirect_stdout, redirect_stderr
        publisher = self.load_publisher()
        state = view(target=1, order=['subkimi', 'submimo'])
        reads, bodies, calls = [], [], []
        def read(*args):
            reads.append(None)
            value = state.copy()
            if calls:
                value['head'] = 'c'*40
            return value
        def run(command, **kwargs):
            calls.append(command[command.index('--leg')+1])
            return subprocess.CompletedProcess(command, 0, 'https://github.com/example/review\n', '')
        def api(token, endpoint, payload, **kwargs):
            bodies.append(payload['body'])
            return {'id': 123}
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(publisher, 'data_path', return_value=Path(directory)), \
             patch.object(publisher, 'read_dispatch_state', side_effect=read), \
             patch.object(publisher._leg_session, 'choose_leg', return_value=('moonshot', None)), \
             patch.object(publisher.subprocess, 'run', side_effect=run), \
             patch.object(publisher._leg_session, 'run'), \
             patch.object(publisher, 'review_token', return_value='token'), \
             patch.object(publisher, 'github', side_effect=api), \
             patch('random.SystemRandom.shuffle', side_effect=lambda items: None), \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            with self.assertRaises(ValueError):
                publisher.auto_dispatch('example/repo', 1, 'openai')
        public = json.loads(bodies[-1].split('```json\n')[1].split('\n```')[0])
        self.assertEqual(calls, ['subkimi'])
        self.assertEqual(public.get('stopped'), 'head_changed')
        self.assertEqual(public['attempts'], [{'leg': 'subkimi', 'started': True}])

    def test_facts_timeout_is_recorded_and_prints_its_directory(self):
        import tempfile, io, subprocess
        from unittest.mock import patch
        from contextlib import redirect_stderr
        publisher = self.load_publisher()
        with patch.object(publisher, 'review_token', return_value='read-token'), \
             patch.object(publisher, 'program', return_value=Path('/fake/node')), \
             patch.object(publisher.subprocess, 'run', side_effect=subprocess.TimeoutExpired('node', 300)):
            with self.assertRaisesRegex(publisher.ReviewError, 'timed out'):
                publisher.read_dispatch_state('example/repo', 1, 'openai')
        stderr = io.StringIO()
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(publisher, 'publish_dispatch_failure') as failure_publication, \
             patch.object(publisher, 'publish_dispatch_record', return_value=123) as public_record, \
             patch.object(publisher, 'data_path', return_value=Path(directory)), \
             patch.object(publisher, 'read_dispatch_state', side_effect=publisher.ReviewError('facts timed out')), \
             patch('time.sleep'), \
             redirect_stderr(stderr):
            with self.assertRaisesRegex(ValueError, 'state_unavailable'):
                publisher.auto_dispatch('example/repo', 1, 'openai')
            failures = list(Path(directory).glob('*/failure.txt'))
            self.assertEqual(len(failures), 1)
            failure_publication.assert_called_once()
            self.assertIn(str(failures[0].parent), stderr.getvalue())


if __name__ == '__main__':
    unittest.main()

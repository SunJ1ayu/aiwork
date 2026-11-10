#!/usr/bin/env python3
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bin'))
import unittest
from _review_dispatch import dispatch


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
        def run(leg, model, head):
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

    def test_failure_tries_next_in_fixed_order(self):
        result = self.run_case(failures=['a'], target=2)
        self.assertEqual(self.calls, ['a', 'b', 'c'])
        self.assertTrue(result['minimum_met'])
        self.assertTrue(result['target_met'])
        self.assertEqual(result['attempts'][0]['reason'], 'reported failure')

    def test_exhaustion_below_floor_is_owner_handoff(self):
        result = self.run_case(failures=['a', 'b'])
        self.assertEqual(self.calls, ['a', 'b', 'c'])
        self.assertFalse(result['minimum_met'])
        self.assertEqual(result['next_step'], '交业主')

    def test_floor_met_missing_target_does_not_block(self):
        result = self.run_case(failures=['a'])
        self.assertEqual(self.calls, ['a', 'b', 'c'])
        self.assertTrue(result['minimum_met'])
        self.assertFalse(result['target_met'])
        self.assertEqual(result['missing_target'], 1)

    def test_same_family_and_builder_never_fill_budget(self):
        result = self.run_case(families={'a': 'openai', 'b': 'deepseek', 'c': 'deepseek', 'd': 'anthropic'})
        self.assertEqual(self.calls, ['b'])
        self.assertFalse(result['minimum_met'])

    def test_head_change_stops_without_reviewing_other_head(self):
        with self.assertRaisesRegex(ValueError, 'head'):
            self.run_case(changed=True)
        self.assertEqual(self.calls, ['a'])

    def test_block_is_a_completed_review_but_not_a_pass(self):
        state = view(target=2, order=['a', 'b', 'c'])
        calls = []
        def run(leg, model, head):
            calls.append(leg)
            if leg == 'a':
                result_frame(state, [], ['deepseek'], False, False, 1)
            else:
                result_frame(state, ['moonshot'], ['deepseek', 'moonshot'], True, True, 0)
            return {'ok': True, 'url': 'https://github.com/example/review'}
        result = dispatch(lambda family: state.copy(),
                          lambda leg: ({'a': 'deepseek', 'b': 'moonshot', 'c': 'xiaomi'}[leg], None), run, 'openai')
        self.assertEqual(calls, ['a', 'b'])
        self.assertTrue(result['target_met'])
        self.assertTrue(result['minimum_met'])

    def test_lost_publication_response_uses_actual_gate_state(self):
        state = view(target=2, order=['a', 'b'])
        def run(leg, model, head):
            if leg == 'a':
                result_frame(state, ['deepseek'], ['deepseek'], True, False, 1)
                return {'ok': False, 'reason': 'publication response lost'}
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

    def publisher_case(self, complete):
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
             patch.object(publisher, 'data_path', return_value=Path(directory)), \
             patch.object(publisher, 'read_dispatch_state', side_effect=lambda *args: state.copy()) as read, \
             patch.object(publisher._leg_session, 'choose_leg', return_value=('moonshot', 'kimi-test')), \
             patch.object(publisher.subprocess, 'run', side_effect=run), \
             patch.dict(os.environ, {'GH_TOKEN': 'not-for-model'}), \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(publisher.auto_dispatch('example/repo', 1, 'openai'), 0 if complete else 2)
            reports = list(Path(directory).glob('*/summary.json'))
            self.assertEqual(len(reports), 1)
            report = json.loads(reports[0].read_text())
            self.assertEqual(report['pass_families'], ['moonshot'] if complete else [])
            self.assertEqual(report['target_met'], bool(complete))
            self.assertTrue(all(call.args == ('example/repo', 1, 'openai') for call in read.call_args_list))
        command, kwargs = seen[0]
        self.assertEqual(command[-2:], ['--expected-head', 'a' * 40])
        self.assertEqual(kwargs['env']['CURSOR_MODEL'], 'kimi-test')
        self.assertNotIn('GH_TOKEN', kwargs['env'])

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
             patch.object(publisher, 'data_path', return_value=Path(directory)), \
             patch.object(publisher, 'read_dispatch_state', side_effect=publisher.ReviewError('facts timed out')), \
             redirect_stderr(stderr):
            with self.assertRaisesRegex(publisher.ReviewError, 'timed out'):
                publisher.auto_dispatch('example/repo', 1, 'openai')
            failures = list(Path(directory).glob('*/failure.txt'))
            self.assertEqual(len(failures), 1)
            self.assertIn(str(failures[0].parent), stderr.getvalue())


if __name__ == '__main__':
    unittest.main()

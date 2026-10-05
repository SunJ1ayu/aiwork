#!/usr/bin/env python3
"""Exercise explicit selection through the real controllers, without providers."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: F401,E402

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from _test_settings import write_settings, set_model

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bin'))
from _review_result import coverage_eligible, summarize_results

FAKE = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
mode, task, log, repo = sys.argv[1:5]
adapter = pathlib.Path(sys.argv[0]).name
model = os.environ.get('CURSOR_MODEL') if adapter == 'subcursor' else os.environ.get('MIMO_CLI_MODEL', 'xiaomi/mimo-v2.5-pro')
p = pathlib.Path(log)
p.with_suffix('.called').write_text(json.dumps({'adapter': adapter, 'mode': mode, 'model': model}))
if os.environ.get('FAIL_MODEL') == model:
    print(os.environ.get('FAIL_DIAGNOSTIC', 'quota exhausted'), file=sys.stderr)
    sys.exit(9)
p.write_text('Direction: a bounded design\n' + ('Conclusion: PASS\n' if mode == 'review' or os.environ.get('EXPLORE_PASS') else ''))
actual = os.environ.get('WRONG_MODEL', model)
helper = os.environ['AIWORK_REVIEW_RESULT_BIN']
def git(*a): return subprocess.check_output(['git', '-C', repo, *a], text=True).strip()
args = [sys.executable, helper, 'facts', '--output', os.environ['AIWORK_REVIEW_FACTS_PATH'],
 '--requested-model', actual, '--invoked-model', actual,
 '--git-object-format', git('rev-parse', '--show-object-format'),
 '--head-oid', git('rev-parse', 'HEAD'), '--index-tree-oid', git('rev-parse', 'HEAD^{tree}'),
 '--worktree-tree-oid', git('rev-parse', 'HEAD^{tree}'),
 '--view-delivery-state', 'complete', '--view-mode', 'full_snapshot',
 '--evidence-completeness', 'complete']
track = os.environ.get('AIWORK_REVIEW_TRACK')
if track:
    digest = subprocess.check_output([sys.executable, str(pathlib.Path(helper).with_name('_review_delivery.py')),
       '--repo', repo, '--track', track, '--source', 'working'], text=True).strip()
    args += ['--delivery-track', track, '--delivery-digest', digest]
subprocess.check_call(args)
'''


class CandidateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.d = Path(self.temp.name)
        self.config = write_settings(self.d / 'settings')
        self.bin = self.d / 'bin'
        shutil.copytree(ROOT / 'bin', self.bin, ignore=shutil.ignore_patterns('__pycache__'))
        # Every callable adapter is replaced before any controller runs.
        for name in ('submimo', 'subcursor', 'subdeepseek-agent', 'subdeepseek',
                     'subglm-agent', 'subglm', 'subkimi', 'subgemini', 'subgrok', 'subcodex'):
            p = self.bin / name
            if p.is_symlink(): p.unlink()
            p.write_text(FAKE); p.chmod(0o755)
        self.fake = self.d / 'fake'; self.fake.mkdir()
        p = self.fake / 'cursor-agent'
        p.write_text('#!/bin/sh\nprintf "Available models\\ncomposer-2.5 - Composer 2.5\\ncursor-grok-4.6-high - Cursor Grok 4.6\\nauto - Auto\\n"\n')
        p.chmod(0o755)
        self.repo = self.d / 'repo'; self.repo.mkdir()
        for args in (('init', '-q'), ('config', 'user.name', 'test'),
                     ('config', 'user.email', 'test@example.invalid')):
            self.git(*args)
        (self.repo / 'app').write_text('baseline\n')
        self.git('add', '.'); self.git('commit', '-qm', 'base')
        self.task = self.d / 'task.md'; self.task.write_text('Inspect app.\n')
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(('PANEL_', 'CURSOR_', 'AIWORK_REVIEW_', 'REVIEW_', 'MIMO_'))}
        self.env.update(AIWORK_CONFIG_DIR=str(self.config), PATH=str(self.fake) + os.pathsep + os.environ['PATH'],
                        PANEL_STATE_DIR=str(self.d / 'state'), PANEL_STAGGER_MAX='0',
                        MIMO_CLI_MODEL='xiaomi/mimo-v2.5-pro')
        self.n = 0

    def git(self, *a):
        return subprocess.check_output(['git', '-C', str(self.repo), *a], stderr=subprocess.DEVNULL)

    def run_panel(self, members, mode='review', risk='high', env=None, flags=None):
        self.n += 1; prefix = self.d / f'run{self.n}'
        args = [str(self.bin / ('panel-' + mode)), '--members', members]
        if mode == 'review': args += ['--no-track', '--no-my-review', '--risk', risk]
        args += flags or []
        args += [str(self.task), str(self.repo), str(prefix)]
        result = subprocess.run(args, env=dict(self.env, **(env or {})),
                                capture_output=True, text=True, timeout=35)
        return result, prefix

    def results(self, prefix):
        return [json.loads(p.read_text()) for p in sorted(self.d.glob(prefix.name + '.*.result.json'))]

    def test_two_cursor_models_one_run_and_subject(self):
        r, p = self.run_panel('subcursor@cursor-grok-4.6-high,subcursor@composer-2.5')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        data = self.results(p)
        self.assertEqual(len(data), 2)
        self.assertEqual({x['adapter'] for x in data}, {'subcursor'})
        self.assertEqual({x['model']['requested'] for x in data}, {'cursor-grok-4.6-high', 'composer-2.5'})
        self.assertEqual(len({x['name'] for x in data}), 2)
        self.assertEqual(len({x['run_id'] for x in data}), 1)
        self.assertEqual(len({x['subject']['digest'] for x in data}), 1)
        self.assertEqual(summarize_results(data)['eligible_family_count'], 2)
        calls = [json.loads(f.read_text()) for f in self.d.glob(p.name + '.*.called')]
        self.assertEqual({x['model'] for x in calls}, {'cursor-grok-4.6-high', 'composer-2.5'})
        self.assertFalse((self.d / 'state/cursor').exists(), 'explicit choice must not rotate')

    def test_native_and_cursor_selection_no_automatic_spare_or_fallback(self):
        r, p = self.run_panel('submimo,subcursor@composer-2.5', env={'FAIL_MODEL': 'composer-2.5'})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(len(list(self.d.glob(p.name + '.*.called'))), 2)
        self.assertEqual(len(self.results(p)), 2)
        self.assertEqual(summarize_results(self.results(p))['eligible_family_count'], 1)

    def test_cursor_pool_supports_gpt_claude_glm_and_composer(self):
        models = ['gpt-5.6-sol-high', 'claude-opus-5-thinking-high', 'glm-5.2-high', 'composer-2.5']
        r, p = self.run_panel(','.join('subcursor@' + m for m in models))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        data = self.results(p)
        self.assertEqual({x['model']['requested'] for x in data}, set(models))
        self.assertEqual({x['family'] for x in data}, {'openai', 'anthropic', 'zhipu', 'cursor'})
        self.assertTrue(all(x['adapter'] == 'subcursor' for x in data))
        self.assertEqual(summarize_results(data)['eligible_family_count'], 4)

    def test_catalog_can_show_just_the_cursor_transport_pool(self):
        p = self.fake / 'cursor-agent'
        p.write_text('#!/bin/sh\nprintf "%s\\n" "gpt-5.6-sol-high - GPT" "claude-opus-5-thinking-high - Claude" "glm-5.2-high - GLM"\n')
        data = json.loads(subprocess.check_output([str(self.bin / 'panel-candidates'),
            '--adapter', 'subcursor', '--discover-cursor'], env=self.env, text=True))
        self.assertTrue(all(x['adapter'] == 'subcursor' for x in data['candidates']))
        self.assertTrue({'gpt-5.6-sol-high', 'claude-opus-5-thinking-high', 'glm-5.2-high'} <=
                        {x['model'] for x in data['candidates']})

    def test_same_family_does_not_fill_high_budget_but_can_add_evidence(self):
        members = 'subcursor@composer-2.5,subcursor@composer-2.6'
        r, p = self.run_panel(members)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('famil', r.stderr.lower())
        self.assertEqual(list(self.d.glob(p.name + '.*.called')), [])
        r, p = self.run_panel(members, risk='standard')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(summarize_results(self.results(p))['eligible_family_count'], 1)
        self.assertEqual(len(self.results(p)), 2)

    def test_invalid_disabled_and_conflicting_choices_never_dispatch(self):
        cases = [('subcursor@auto', {}, []), ('subcursor@unknown', {}, []),
                 ('subcursor@composer-2.5,subcursor@composer-2.5', {}, []),
                 ('subcursor@composer-2.5,', {}, []),
                 ('subcursor@composer-2.5', {'PANEL_CURSOR_LEG': 'off'}, []),
                 ('subcursor@composer-2.5', {}, ['--all']),
                 ('subcursor@composer-2.5', {}, ['--budget', '1']),
                 ('subcursor@composer-2.5', {}, ['--scoped-review', '--pin-leg', 'subcursor'])]
        for members, env, flags in cases:
            with self.subTest(members=members, env=env, flags=flags):
                r, p = self.run_panel(members, risk='standard', env=env, flags=flags)
                self.assertNotEqual(r.returncode, 0)
                self.assertFalse(list(self.d.glob(p.name + '.*.called')))

    def test_wrong_model_in_same_family_never_counts(self):
        r, p = self.run_panel('subcursor@composer-2.5', risk='standard', env={'WRONG_MODEL': 'composer-2.6'})
        data = self.results(p)
        self.assertEqual(len(data), 1, r.stdout + r.stderr)
        self.assertFalse(coverage_eligible(data[0]))
        self.assertEqual(data[0]['model']['requested'], 'composer-2.5')
        self.assertEqual(data[0]['model']['invoked'], 'composer-2.6')

    def test_native_model_is_pinned_and_reported_mismatch_is_ineligible(self):
        r, p = self.run_panel('submimo', risk='standard', env={'WRONG_MODEL': 'xiaomi/mimo-other'})
        data = self.results(p)
        self.assertEqual(len(data), 1, r.stdout + r.stderr)
        self.assertEqual(data[0]['model']['requested'], 'xiaomi/mimo-v2.5-pro')
        self.assertFalse(coverage_eligible(data[0]))

    def test_typed_track_records_dynamic_members_and_delivery(self):
        track = self.repo / 'tracks/choice'; track.mkdir(parents=True)
        (track / 'decision.json').write_text(json.dumps({
            'schema_version': 2, 'track': 'choice',
            'impact': {'level': 'high', 'factors': ['judging_control']},
            'design': {'uncertainty': 'low', 'premise_attack': {'status': 'not_required', 'evidence': []}},
            'execution_plan': {'adapter': 'main', 'model': 'gpt-6-astra'},
            'outcome': {'verdict': None}}))
        prefix = self.d / 'bound'
        r = subprocess.run([str(self.bin / 'panel-review'), '--members',
            'subcursor@composer-2.5,subcursor@cursor-grok-4.6-high', '--track', 'choice',
            '--no-my-review', str(self.task), str(self.repo), str(prefix)],
            env=self.env, text=True, capture_output=True, timeout=35)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn('OBSERVATION_WRITE_FAILED', r.stderr)
        events = list((track / 'observations').glob('*.json'))
        self.assertEqual(len(events), 1)
        legs = json.loads(events[0].read_text())['actual']['legs']
        self.assertEqual(len(legs), 2)
        self.assertTrue(all(x['subject']['delivery']['track'] == 'choice' for x in legs))

    def test_explore_shared_selection_cannot_supply_review_coverage(self):
        r, p = self.run_panel('subcursor@cursor-grok-4.6-high,subcursor@composer-2.5', mode='explore', env={'EXPLORE_PASS': '1'})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        data = self.results(p)
        self.assertEqual(len(data), 2)
        self.assertTrue(all(x['review_contract_version'] == 3 for x in data))
        self.assertTrue(all(not coverage_eligible(x) for x in data), 'even PASS text is not review coverage')
        calls = [json.loads(f.read_text()) for f in self.d.glob(p.name + '.*.called')]
        self.assertEqual({x['mode'] for x in calls}, {'explore'})
        r, p = self.run_panel('subkimi', mode='explore')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(list(self.d.glob(p.name + '.*.called')))

    def test_normal_explore_does_not_require_verdict_or_poison_health(self):
        for _ in range(2):
            r, p = self.run_panel('subcursor@composer-2.5', mode='explore')
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(self.results(p)[0]['failure_kind'], 'none')
            self.assertIn('EXPLORE(rc=0,coverage=none)', Path(str(p) + '.roster').read_text())
        r, p = self.run_panel('subcursor@composer-2.5', mode='explore', flags=['--track', 'choice'])
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(list(self.d.glob(p.name + '.*.called')))

    def test_roster_uses_frozen_members_after_config_changes(self):
        r, p = self.run_panel('subcursor@cursor-grok-4.6-high,subcursor@composer-2.5')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        before = Path(str(p) + '.roster').read_text().splitlines()[1:]
        set_model(self.config, 'cursor', ('gpt-5.6\n').strip())
        out = subprocess.check_output([str(self.bin / 'panel-roster'), str(p)], env=self.env, text=True)
        self.assertEqual(before, out.splitlines()[1:])
        data = self.results(p)
        Path(str(p) + '.' + data[0]['name'] + '.state').unlink()
        Path(str(p) + '.final').unlink()
        out = subprocess.check_output([str(self.bin / 'panel-roster'), str(p)], env=self.env, text=True)
        self.assertIn(data[0]['name'] + '=未收尾', out)

    def test_catalog_is_read_only_and_reports_unknown_quota(self):
        cli = self.bin / 'panel-candidates'
        self.assertTrue(cli.exists(), 'read-only model catalog is missing')
        out = subprocess.check_output([str(cli), '--mode', 'explore', '--discover-cursor'], env=self.env, text=True)
        data = json.loads(out)
        models = {x['model'] for x in data['candidates'] if x['adapter'] == 'subcursor'}
        self.assertIn('composer-2.5', models)
        self.assertIn('cursor-grok-4.6-high', models)
        self.assertNotIn('auto', models)
        self.assertTrue(all(x['quota_remaining'] is None for x in data['candidates']))
        self.assertFalse((self.d / 'state').exists())
        self.assertFalse(any(x['adapter'] == 'subkimi' for x in data['candidates']))

    def test_health_is_separate_for_cursor_models(self):
        r, p = self.run_panel('subcursor@composer-2.5', risk='standard', env={'FAIL_MODEL': 'composer-2.5'})
        self.assertNotEqual(r.returncode, 0)
        r, p = self.run_panel('subcursor@composer-2.6', risk='standard')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        r, p = self.run_panel('subcursor@composer-2.5', risk='standard')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(list(self.d.glob(p.name + '.*.called')))

    def run_legacy_cursor(self, model, env=None):
        # 旧入口(不带 --members)只开 Cursor 一条腿:它本轮跑的就是 CURSOR_MODEL。
        self.n += 1; prefix = self.d / f'run{self.n}'
        off = {k: 'off' for k in ('PANEL_MIMO_LEG', 'PANEL_DEEPSEEK_LEG', 'PANEL_GLM_LEG',
                                  'PANEL_KIMI_LEG', 'PANEL_GEMINI_LEG', 'PANEL_GROK_LEG')}
        result = subprocess.run([str(self.bin / 'panel-review'), '--no-track', '--no-my-review',
                                 '--risk', 'standard', str(self.task), str(self.repo), str(prefix)],
                                env=dict(self.env, **off, CURSOR_MODEL=model, **(env or {})),
                                capture_output=True, text=True, timeout=35)
        return result, prefix

    def test_legacy_cursor_leg_and_explicit_member_share_model_health(self):
        # 第 2 轮重试 Grok 的 BLOCK:旧轮换把 Cursor 失败记在通道名 subcursor 下、显式成员记在
        # subcursor.<model> 下 ⇒ 同一个模型在一边撞了额度,另一边照派。冷却/连败要按实际模型共用。
        r, p = self.run_legacy_cursor('composer-2.5', env={'FAIL_MODEL': 'composer-2.5'})
        self.assertTrue(list(self.d.glob(p.name + '.subcursor.called')), r.stdout + r.stderr)
        r, p = self.run_panel('subcursor@composer-2.5', risk='standard')
        self.assertNotEqual(r.returncode, 0, 'legacy quota on this model must cool the explicit member')
        self.assertFalse(list(self.d.glob(p.name + '.*.called')))
        # 反方向:显式成员撞额度,旧轮换跑同一个模型时要跳过它。
        r, p = self.run_panel('subcursor@composer-2.6', risk='standard', env={'FAIL_MODEL': 'composer-2.6'})
        self.assertTrue(list(self.d.glob(p.name + '.*.called')), r.stdout + r.stderr)
        r, p = self.run_legacy_cursor('composer-2.6')
        self.assertFalse(list(self.d.glob(p.name + '.*.called')),
                         'explicit quota on this model must cool the legacy leg running it')
        # 对照:没失败过的模型两边都照派 —— 不许修成「整个 Cursor 通道一起冷却」。
        r, p = self.run_legacy_cursor('composer-2.7')
        self.assertTrue(list(self.d.glob(p.name + '.subcursor.called')), r.stdout + r.stderr)
        r, p = self.run_panel('subcursor@composer-2.8', risk='standard')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_failure_before_model_facts_preserves_health_cause(self):
        for suffix, diagnostic, expected in (
                ('quota', 'quota exhausted', 'quota'),
                ('auth', '401 Unauthorized', 'auth'),
                ('window', 'rate limit exceeded', 'rate_limit')):
            model = 'composer-' + suffix
            with self.subTest(cause=expected):
                r, p = self.run_panel('subcursor@' + model, risk='standard', env={
                    'FAIL_MODEL': model, 'FAIL_DIAGNOSTIC': diagnostic})
                self.assertNotEqual(r.returncode, 0)
                result = self.results(p)[0]
                self.assertEqual(result['model']['requested'], model)
                self.assertIsNone(result['model']['invoked'])
                self.assertEqual(result['failure_kind'], expected)
                rows = [line.split('\t') for line in (self.d / 'state/health.tsv').read_text().splitlines()]
                row = next(row for row in rows if row[0] == 'subcursor.' + model)
                self.assertEqual(row[1], expected)
                if expected == 'rate_limit':
                    self.assertEqual(row[3], '0', 'a window limit must not count as a hard failure')


if __name__ == '__main__':
    unittest.main()

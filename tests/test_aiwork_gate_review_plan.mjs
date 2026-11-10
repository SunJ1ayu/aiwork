import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { reviewPlan, validateReviewPolicy } from '../gate/review-plan.mjs';
import { decide } from '../gate/decide.mjs';
import { validatePolicy } from '../gate/run.mjs';
const policy = JSON.parse(readFileSync(new URL('../.aiwork/policy.json', import.meta.url)));
const head = 'a'.repeat(40);
const review = (family, id = 1) => ({id, login:policy.reviewer_bot, type:'Bot', state:'COMMENTED', commit_id:head,
  submitted_at:'2026-11-10T00:00:00Z', body:'```json\n'+JSON.stringify({verdict:'PASS',head_sha:head,model:family+'-test',family,completeness:'complete'})+'\n```'});
const facts = (families, files=['bin/subcodex']) => ({pr:{number:1,state:'open',head_sha:head},files,
  ci:{state:'success'},pushes:{covers_head:true,actors:['SunJ1ayuBoT']},
  reviews:[...families.map((f,i)=>review(f,i+1)),{id:99,login:policy.owner,type:'User',state:'APPROVED',commit_id:head,submitted_at:'2026-11-10T01:00:00Z',body:''}]});
test('tiers use main policy: ordinary documents, code, judging documents, isolation', () => {
  for (const [files,tier,target,minimum] of [
    [['README.md'],'documentation',1,1], [['docs/linux-vm.md'],'documentation',1,1],
    [['bin/tool'],'code',2,1], [['workflow/CLAUDE.md'],'code',2,1],
    [['README.md','bin/tool'],'code',2,1], [['bin/subcodex'],'high',3,2],
    [['bin/_paths.py'],'high',3,2], [['bin/_kimi_preflight.py'],'high',3,2],
    [['bin/_review-workspace.sh'],'high',3,2], [[], 'code',2,1],
  ]) {
    const p=reviewPlan(files,policy);
    assert.deepEqual([p.tier,p.target,p.minimum],[tier,target,minimum],files.join(','));
  }
});
test('high minimum is independent of target and cannot be filled by duplicate family', () => {
  assert.equal(decide(facts(['deepseek']),policy).conclusion,'failure');
  assert.equal(decide(facts(['deepseek','deepseek']),policy).conclusion,'failure');
  assert.equal(decide(facts(['deepseek','moonshot']),policy).conclusion,'success');
  const r=decide(facts(['deepseek','moonshot']),policy);
  assert.match(r.summary,/目标.*3/);
  assert.match(r.summary,/底线.*2/);
});
test('shared policy changes affect both plan and gate, not just a hardcoded count', () => {
  const p=structuredClone(policy); p.high_min_families=3; p.review_dispatch.targets.high=4;
  assert.deepEqual([reviewPlan(['bin/subcodex'],p).target,reviewPlan(['bin/subcodex'],p).minimum],[4,3]);
  assert.equal(decide(facts(['deepseek','moonshot']),p).conclusion,'failure');
  assert.equal(decide(facts(['deepseek','moonshot','xiaomi']),p).conclusion,'success');
});
test('invalid targets and dispatch orders fail closed; legacy projects retain their gate', () => {
  validatePolicy(policy);
  for (const mutate of [
    p=>p.review_dispatch.minimum_families=0,
    p=>p.review_dispatch.targets.high=1,
    p=>p.review_dispatch.targets.code=0,
    p=>p.review_dispatch.targets.documentation=1.5,
    p=>p.review_dispatch.order.push(p.review_dispatch.order[0]),
    p=>p.review_dispatch.order=['../subcodex'],
    p=>p.review_dispatch.documentation_paths=[''],
  ]) {const p=structuredClone(policy); mutate(p); assert.throws(()=>validatePolicy(p));}
  const old=structuredClone(policy); delete old.review_dispatch;
  validatePolicy(old); assert.equal(validateReviewPolicy(old),undefined);
  assert.equal(reviewPlan(['anything'],old).minimum,1);
  assert.equal(decide(facts(['deepseek','moonshot']),old).conclusion,'success');
});

test('G3 bottom line also comes from the shared policy', () => {
  const p=structuredClone(policy); p.review_dispatch.minimum_families=2;
  p.review_dispatch.targets.documentation=2;
  const plan=reviewPlan(['README.md'],p);
  assert.equal(plan.minimum,2);
  assert.equal(decide(facts(['deepseek'],['README.md']),p).conclusion,'failure');
  assert.equal(decide(facts(['deepseek','moonshot'],['README.md']),p).conclusion,'success');
});

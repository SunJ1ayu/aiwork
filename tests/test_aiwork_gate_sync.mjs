import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { decide } from '../gate/decide.mjs';
const p = JSON.parse(readFileSync(new URL('./fixtures/gate-logic-policy.json', import.meta.url)));
const old = 'b'.repeat(40), head = 'a'.repeat(40);
const pass = (sha, verdict = 'PASS') => ({id:1, login:p.reviewer_bot,type:'Bot',state:'COMMENTED',commit_id:sha,
 submitted_at:'2026-11-23T00:00:00Z',body:'```json\n'+JSON.stringify({verdict,head_sha:sha,model:'model',family:'openai',completeness:'complete'})+'\n```'});
const facts = () => ({pr:{number:1,head_sha:head}, files:['web/a.ts'], ci:{state:'success'},
 pushes:{covers_head:true,actors:['SunJ1ayuBoT']},reviews:[pass(old)],
 synchronization:{review_heads:[old],note:`沿用 ${old}：关卡自动同步，main 未碰本单文件`}});
test('干净同步且文件不重叠：旧评审沿用，CI 仍须当前 head 通过',()=>{
 const f=facts(); assert.equal(decide(f,p).conclusion,'success');
 f.ci={state:'pending'}; assert.notEqual(decide(f,p).conclusion,'success');
});
test('重叠文件不同步评审来源，必须重新评审',()=>{
 const f=facts(); f.synchronization.review_heads=[];
 assert.notEqual(decide(f,p).conclusion,'success');
 f.reviews=[pass(head)]; assert.equal(decide(f,p).conclusion,'success');
});
test('沿用范围中的 BLOCK 不能被过滤掉',()=>{
 const f=facts();f.reviews=[pass(old,'BLOCK'),{...pass(head),id:2}];
 assert.notEqual(decide(f,p).conclusion,'success'); assert.equal(decide(f,p).blocks.length,1);
});

import { collect } from '../gate/collect.mjs';
import { prepareSynchronization, syncIntent, syncCheck, SYNC_CHECK } from '../gate/synchronize.mjs';
import { mergeBindingKey, MERGE_BINDING_CHECK } from '../gate/merge-request.mjs';
const base='c'.repeat(40), common='d'.repeat(40), newer='e'.repeat(40);
function environment(over={}) {
 const at='2026-11-22T00:00:00Z', actor='aiwork-gate[bot]';
 const key=mergeBindingKey(1,p.merge_label,old,p.owner);
 const intent=syncIntent(1,old,base,'main','builder/one',actor,key,[],over.overlap?['web/a.ts']:[],common);
 const pr={number:1,state:'open',changed_files:1,labels:[{name:p.merge_label}],mergeable:true,
  head:{sha:head,ref:'builder/one',repo:{full_name:'o/r'}},base:{sha:base,ref:'main'}};
 const activity=[{id:2,before:old,after:head,actor:{login:actor,type:'Bot'},activity_type:'push',timestamp:'2026-11-23'},
  {id:1,before:'0'.repeat(40),after:old,actor:{login:'SunJ1ayuBoT',type:'User'},activity_type:'branch_creation',timestamp:'2026-11-22'}];
 if(over.laterPush) {pr.head.sha=newer; activity.unshift({id:3,before:head,after:newer,actor:{login:'SunJ1ayuBoT',type:'User'},activity_type:'push',timestamp:'2026-11-24'});}
 if(over.restore) activity.unshift({id:3,before:newer,after:head,actor:{login:'SunJ1ayuBoT',type:'User'},activity_type:'force_push',timestamp:'2026-11-24'});
 if(over.foreignActor) activity[0].actor.login='untrusted[bot]';
 const record={...syncCheck(intent),app:{id:over.foreignApp?999:p.gate_app_id}};
 const binding={name:MERGE_BINDING_CHECK,head_sha:old,status:'completed',conclusion:'neutral',external_id:key,app:{id:p.gate_app_id}};
 const entries=names=>names.map((path,i)=>({path,mode:'100644',type:'blob',sha:String(i+1).repeat(40)}));
 // 路径对象保持相同的 blob id；同步不得移动 PR 自己的文件或改 blob。
 const files={ [common]:[],[old]:entries(['web/a.ts']),[base]:[{path:'other.ts',mode:'100644',type:'blob',sha:'2'.repeat(40)}],
  [head]:[...entries([over.changed?'moved/a.ts':'web/a.ts']),{path:'other.ts',mode:'100644',type:'blob',sha:'2'.repeat(40)}]};
 const requests=[];
 const api={async get(path){requests.push(path);
  if(path==='/repos/o/r') return {default_branch:'main'};
  if(path==='/repos/o/r/pulls/1') return structuredClone(pr);
  if(path.startsWith('/repos/o/r/git/commits/')) {const id=path.split('/').at(-1);return {sha:id,tree:{sha:id},parents:id===head?[{sha:over.wrongParent?common:old},{sha:base}]:[]};}
  if(path.includes('/git/trees/')) {const id=path.split('/').at(-1).split('?')[0];return {truncated:!!over.truncated,tree:files[id]};}
  throw Error('unexpected get '+path);
 },async getPage(path){requests.push(path);
  if(path.includes('/pulls/1/files'))return {data:[{filename:'web/a.ts'}]};
  if(path.includes('/pulls/1/reviews'))return {data:[{...pass(old),user:{login:p.reviewer_bot,type:'Bot'}}]};
  if(path.includes('/actions/runs'))return {data:{total_count:1,workflow_runs:[{id:1,path:p.ci.workflow_path,head_sha:pr.head.sha,event:p.ci.event,status:'completed',conclusion:'success',pull_requests:[{number:1}]}]}};
  if(path.includes('/issues/1/events'))return {data:[{id:1,event:'labeled',label:{name:p.merge_label},actor:{login:p.owner},created_at:at}]};
  if(path.includes('/activity?'))return {data:activity};
  if(path.includes('/check-runs?')){
   const records=path.includes(`/commits/${old}/`)?(path.includes(`check_name=${SYNC_CHECK}`)?[record]:[binding]):[];
   return {data:{total_count:records.length,check_runs:records}};
  }
  throw Error('unexpected page '+path);
 },async graphql(){return {repository:{pullRequest:{reviews:{totalCount:1,nodes:[{databaseId:1,submittedAt:'2026-11-23T00:00:00Z'}],pageInfo:{hasNextPage:false}}}}};}};
 return {api,pr,requests,record,intent};
}
test('收集与判定联测：关卡推送双亲与树差相同，作者仍是 Builder，旧标签及评审沿用',async()=>{
 const e=environment();const f=await collect(e.api,'o/r',1,p);const r=decide(f,p);
 assert.equal(r.conclusion,'success',r.summary);assert.equal(r.author.known,true);
 assert.equal(f.merge_request.bound,true);assert.deepEqual(f.synchronization.review_heads,[old]);
 assert.match(r.summary,/沿用提交/);
});
test('收集链：main 碰了同一文件，CI 通过仍缺新评审',async()=>{
 const e=environment({overlap:true});const f=await collect(e.api,'o/r',1,p);
 assert.equal(f.merge_request.bound,true);assert.equal(decide(f,p).conclusion,'failure');
 assert.match(f.synchronization.note,/须重新评审/);
});
test('同步后普通推送或推回同步 SHA 都截断标签和评审沿用',async()=>{
 for(const over of [{laterPush:true},{restore:true}]){
  const e=environment(over),f=await collect(e.api,'o/r',1,p);
  assert.equal(f.merge_request.bound,false);assert.deepEqual(f.synchronization.review_heads,[]);
  assert.notEqual(decide(f,p).conclusion,'success');
 }
});
test('其他 App、推送者或不匹配双亲不能冒充关卡同步',async()=>{
 for(const over of [{foreignApp:true},{foreignActor:true},{wrongParent:true}]){
  const e=environment(over),f=await collect(e.api,'o/r',1,p);
  assert.equal(f.merge_request.bound,false);assert.equal(decide(f,p).author.known,false);
 }
});
test('自动合并移动了 PR 文件仍不能沿用；树截断失败即拒',async()=>{
 const e=environment({changed:true}),f=await collect(e.api,'o/r',1,p);
 assert.equal(f.merge_request.bound,false);assert.deepEqual(f.synchronization.review_heads,[]);
 await assert.rejects(collect(environment({truncated:true}).api,'o/r',1,p),/tree 不完整/);
});
function planning(over={}) {
 const e=environment();e.pr.head.sha=old;
 if(over.conflict)e.pr.mergeable=false;
 const original=e.api.get.bind(e.api);
 e.api.get=async path=>{
  if(path.includes('/compare/'))return {total_commits:1,merge_base_commit:{sha:common}};
  return original(path);
 };
 const page=e.api.getPage.bind(e.api);
 e.api.getPage=async path=>{
  if(path.includes('/compare/'))return {data:{commits:over.incomplete?[]:[{sha:base}]}};
  if(path.includes(`/commits/${base}?`))return {data:{files:[{filename:over.overlap?'web/a.ts':'other.ts',previous_filename:over.rename?'web/a.ts':undefined}]}};
  return page(path);
 };
 return e;
}
const planningFacts=()=>({pr:{head_sha:old,base_sha:base,base_ref:'main'},files:['web/a.ts'],merge_request:{key:'frozen-label'}});
test('同步计划：冲突不同步；逐提交含重命名旧路径的交集决定是否沿用',async()=>{
 const a=await prepareSynchronization(planning().api,'o/r',1,planningFacts(),'aiwork-gate[bot]');
 assert.deepEqual(a.intent.review_heads,[old]);
 for(const over of [{overlap:true},{rename:true}]){
  const b=await prepareSynchronization(planning(over).api,'o/r',1,planningFacts(),'aiwork-gate[bot]');
  assert.deepEqual(b.intent.review_heads,[]);assert.deepEqual(b.intent.overlap,['web/a.ts']);
 }
 const conflict=await prepareSynchronization(planning({conflict:true}).api,'o/r',1,planningFacts(),'aiwork-gate[bot]');
 assert.equal(conflict.conflict,true);assert.equal(conflict.intent,undefined);
 await assert.rejects(prepareSynchronization(planning({incomplete:true}).api,'o/r',1,planningFacts(),'aiwork-gate[bot]'),/不完整/);
});

test('同步证明不足或后续有普通推送时，摘要写明为什么不能沿用',async()=>{
 for(const over of [{foreignApp:true},{wrongParent:true},{laterPush:true}]){
  const e=environment(over),f=await collect(e.api,'o/r',1,p);
  assert.match(decide(f,p).summary,/无法证明|普通推送/);
 }
});

test('同步前与文件核实后的 PR 快照改变均是瞬时状态，实际读取失败仍是错误',async()=>{
 for(const phase of [1,2]){
  const e=planning(),get=e.api.get.bind(e.api);let reads=0;
  e.api.get=async path=>{
   const result=await get(path);
   if(path==='/repos/o/r/pulls/1' && ++reads===phase)result.head.sha=newer;
   return result;
  };
  await assert.rejects(prepareSynchronization(e.api,'o/r',1,planningFacts(),'aiwork-gate[bot]'),
   error=>error.constructor.name==='TransientPrState');
 }
 const e=planning();e.api.get=async()=>{throw new Error('真实读取失败');};
 await assert.rejects(prepareSynchronization(e.api,'o/r',1,planningFacts(),'aiwork-gate[bot]'),
  error=>error.constructor.name==='Error' && error.message==='真实读取失败');
});

import { bindingFromEvent } from '../gate/merge-request.mjs';
function labelEnvironment(over={}) {
 const e=environment();e.pr.head.sha=old;
 const payload={action:'labeled',repository:{full_name:'o/r'},label:{name:p.merge_label},sender:{login:p.owner},
  pull_request:{number:1,head:{sha:old},base:{repo:{full_name:'o/r'}},updated_at:'2026-11-22T00:00:01Z'}};
 const binding={...bindingFromEvent('pull_request_target',payload,'o/r',p),app:{id:p.gate_app_id}};
 const creation={id:1,activity_type:'branch_creation',before:'0'.repeat(40),after:old,timestamp:'2026-11-21',actor:{login:'SunJ1ayuBoT'}};
 const activity=over.restore ? [{...creation,id:3,activity_type:'force_push',before:head,after:old,timestamp:'2026-11-24'},
  {...creation,id:2,activity_type:'push',before:old,after:head,timestamp:'2026-11-23'},creation] : [creation];
 const page=e.api.getPage.bind(e.api);
 e.api.getPage=async path=>{
  if(path.includes('/activity?'))return {data:over.incomplete?[]:activity};
  if(path.includes('/issues/1/events'))return {data:[{id:1,event:'labeled',created_at:'2026-11-22T00:00:00Z',label:{name:p.merge_label},actor:{login:over.unauthorized?'stranger':p.owner}},
   ...(over.relabel?[{id:2,event:'unlabeled',created_at:'2026-11-22T00:00:00Z',label:{name:p.merge_label},actor:{login:p.owner}},
    {id:3,event:'labeled',created_at:'2026-11-22T00:00:00Z',label:{name:p.merge_label},actor:{login:p.owner}}]:[])]};
  if(path.includes('/check-runs?'))return {data:{total_count:1,check_runs:[binding]}};
  return page(path);
 };
 return e;
}
test('D：通知与历史差一秒，同提交摘掉重贴可沿用可信授权',async()=>{
 for(const over of [{},{relabel:true}])assert.equal((await collect(labelEnvironment(over).api,'o/r',1,p)).merge_request.bound,true);
});
test('D：摘掉后推 B、重贴再强推回 A，不能借 A 的旧授权',async()=>{
 const f=await collect(labelEnvironment({restore:true,relabel:true}).api,'o/r',1,p);
 assert.equal(f.merge_request.bound,false);assert.match(f.merge_request.reason,/回到|连续/);
});
test('D：没有完整活动记录不合；无权限的最新申请不合且给出真实原因',async()=>{
 assert.equal((await collect(labelEnvironment({incomplete:true}).api,'o/r',1,p)).merge_request.bound,false);
 const f=await collect(labelEnvironment({unauthorized:true}).api,'o/r',1,p);
 assert.equal(f.merge_request.bound,false);assert.match(f.merge_request.reason,/权限|不算数/);
});

test('D：不同可信申请人保存的授权可沿用，伪造账号和旧时间键不能充数',async()=>{
 for(const variant of ['trusted','untrusted','legacy']){
  const e=labelEnvironment(),page=e.api.getPage.bind(e.api);
  e.api.getPage=async path=>{
   const result=await page(path);
   if(path.includes('/check-runs?'))result.data.check_runs[0].external_id=variant==='legacy'
    ? JSON.stringify([1,p.merge_label,'2026-11-22T00:00:00Z',p.owner])
    :mergeBindingKey(1,p.merge_label,old,variant==='trusted'?'merger':'stranger');
   return result;
  };
  assert.equal((await collect(e.api,'o/r',1,{...p,merge_requesters:['merger']})).merge_request.bound,variant==='trusted');
 }
});

import { cpSync, mkdtempSync, readdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
async function maintenanceGate(pattern,replacement,check) {
 const dir=mkdtempSync(join(tmpdir(),'gate-history-maintenance-'));
 try {
  cpSync(new URL('../gate/',import.meta.url),join(dir,'gate'),{recursive:true});
  const definitions=readdirSync(join(dir,'gate')).filter(n=>n.endsWith('.mjs')).map(n=>join(dir,'gate',n))
   .filter(path=>pattern.test(readFileSync(path,'utf8')));
  assert.equal(definitions.length,1,'被维护的概念只有一个定义');
  const path=definitions[0];
  writeFileSync(path,readFileSync(path,'utf8').replace(pattern,replacement));
  const {collectPushes}=await import(pathToFileURL(join(dir,'gate/collect.mjs')));
  const {retainsAuthorization}=await import(pathToFileURL(join(dir,'gate/merge-request.mjs')));
  await check(collectPushes,retainsAuthorization);
 } finally {rmSync(dir,{recursive:true,force:true});}
}
test('P1-1：只在活动定义增加一种推进类型，作者与授权连续性一起识别',async()=>{
 await maintenanceGate(/const PUSH_TYPES = new Set\(\[/,'const PUSH_TYPES = new Set(["maintenance_push", ',async(collectPushes,retainsAuthorization)=>{
  const acts=[{id:2,timestamp:'2026-11-23',activity_type:'maintenance_push',before:old,after:head,actor:{login:'builder'}},
   {id:1,timestamp:'2026-11-22',activity_type:'branch_creation',before:'0'.repeat(40),after:old,actor:{login:'builder'}}];
  const collected=await collectPushes({getPage:async()=>({data:acts})},'o/r','branch',head,true);
  assert.equal(collected.activities.length,2,'作者和同步证明读到新增活动');
  assert.equal(retainsAuthorization(collected.history,head,head,new Map()),true,'同一次维护也适用于授权连续性');
 });
});
test('P1-1：只改创建边界时，授权不能再使用旧边界补全历史',async()=>{
 await maintenanceGate(/if \((\w+)\.activity_type === (?:"branch_creation"|'branch_creation'|CREATION)\)/,
  "if ($1.activity_type === 'maintenance_creation')",async(collectPushes,retainsAuthorization)=>{
   const acts=[{id:3,timestamp:'2026-11-23',activity_type:'push',before:old,after:head,actor:{login:'builder'}},
    {id:2,timestamp:'2026-11-22',activity_type:'branch_creation',before:'0'.repeat(40),after:old,actor:{login:'builder'}},
    {id:1,timestamp:'2026-11-21',activity_type:'push',before:old,after:newer,actor:{login:'prior-builder'}}];
   const facts=await collectPushes({getPage:async()=>({data:acts})},'o/r','branch',head,true);
   assert.ok(facts.actors.includes('prior-builder'),'创建边界的维护已经影响作者识别');
   assert.equal(retainsAuthorization(facts.history,head,head,new Map()),false,'授权也必须采用维护后的边界');
  });
});

test('P1-1：删除屏障与重建分支共用边界，缺创建记录不能借上一世补齐',async()=>{
 const {collectPushes}=await import('../gate/collect.mjs');
 const {retainsAuthorization}=await import('../gate/merge-request.mjs');
 const creation={id:1,timestamp:'2026-11-20',activity_type:'branch_creation',before:'0'.repeat(40),after:old,actor:{login:'old-builder'}};
 const deletion={id:2,timestamp:'2026-11-21',activity_type:'branch_deletion',before:old,after:'0'.repeat(40)};
 const latest={id:4,timestamp:'2026-11-23',activity_type:'push',before:old,after:head,actor:{login:'new-builder'}};
 for(const rebuilt of [false,true]){
  const acts=[latest,...(rebuilt?[{...creation,id:3,timestamp:'2026-11-22',actor:{login:'new-builder'}}]:[]),deletion,creation];
  const facts=await collectPushes({getPage:async()=>({data:acts})},'o/r','branch',head,true);
  assert.ok(facts.actors.every(a=>a==='new-builder'));
  assert.equal(retainsAuthorization(facts.history,head,head,new Map()),rebuilt);
 }
});

test('P2：叉库的可信合并申请说明不支持自动合并，不要求无效重贴',async()=>{
 const e=labelEnvironment(),get=e.api.get.bind(e.api);
 e.api.get=async path=>{const value=await get(path);if(path==='/repos/o/r/pulls/1')value.head.repo.full_name='fork/r';return value;};
 const f=await collect(e.api,'o/r',1,p);
 assert.equal(f.merge_request.bound,false);assert.match(f.merge_request.reason,/叉库.*不支持/);
 assert.doesNotMatch(f.merge_request.reason,/重贴/);
});

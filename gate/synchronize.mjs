// 关卡写入的同步意向 + 实际推送活动 + 双亲提交共同证明来源。
// 意向先保存再调用带 expected_head_sha 的异步接口，进程中断也能由下一轮核实。
import { paginate } from './collect.mjs';
export class TransientPrState extends Error {}
export function assertPrSnapshot(pr, expected) {
  if (!sha(pr.head?.sha) || !sha(pr.base?.sha) || typeof pr.base?.ref !== 'string' ||
      !['open','closed'].includes(pr.state)) throw new Error('GitHub PR 快照缺失或不合法');
  if (pr.state !== 'open' || pr.head.sha !== expected.head_sha ||
      pr.base.sha !== expected.base_sha || pr.base.ref !== expected.base_ref) {
    throw new TransientPrState('PR 状态已改变，重新读取现状后再判定');
  }
}
export const SYNC_CHECK = 'aiwork-main-sync';
const sha = s => typeof s === 'string' && /^[0-9a-f]{40}$/.test(s);
export function syncIntent(number, head, base, ref, headRef, actor, binding, reviewHeads, overlap, mergeBase) {
  return {version:1,number,head,base,merge_base:mergeBase,ref,head_ref:headRef,actor,binding,
    review_heads:overlap.length ? [] : [head,...reviewHeads],overlap};
}
export function syncCheck(intent) {
  return {name:SYNC_CHECK,head_sha:intent.head,status:'completed',conclusion:'neutral',
    external_id:JSON.stringify([intent.number,intent.head,intent.base]),output:{title:'关卡自动同步意向',summary:`同步 ${intent.base} 到 ${intent.head}；结果由实际推送与提交双亲核实。`,text:JSON.stringify(intent)}};
}
async function tree(api,repo,commit) {
  const c=await api.get(`/repos/${repo}/git/commits/${commit}`);
  if (!sha(c.tree?.sha)) throw new Error('提交缺 tree');
  const t=await api.get(`/repos/${repo}/git/trees/${c.tree.sha}?recursive=1`);
  if (t.truncated !== false || !Array.isArray(t.tree)) throw new Error('Git tree 不完整');
  return new Map(t.tree.filter(e=>e.type !== 'tree').map(e=>[e.path,[e.mode,e.type,e.sha]]));
}
async function delta(api,repo,base,head) {
  const a=await tree(api,repo,base),b=await tree(api,repo,head);
  return JSON.stringify([...new Set([...a.keys(),...b.keys()])].sort()
    .filter(k=>JSON.stringify(a.get(k)) !== JSON.stringify(b.get(k)))
    .map(k=>[k,a.get(k) ?? null,b.get(k) ?? null]));
}
export async function proveSynchronizations(api, bindingApi, repo, pr, policy, activities) {
  const proven = new Map();
  for (const a of activities) {
    if (a.activity_type !== 'push' || a.actor?.type !== 'Bot' ||
        Object.hasOwn(policy.builders,a.actor.login) || !sha(a.before) || !sha(a.after)) continue;
    const records = await paginate(bindingApi,`/repos/${repo}/commits/${a.before}/check-runs?check_name=${SYNC_CHECK}&filter=all&per_page=100`,'check_runs');
    for (const r of records) {
      if (r.name !== SYNC_CHECK || r.app?.id !== policy.gate_app_id || r.head_sha !== a.before ||
          r.status !== 'completed' || r.conclusion !== 'neutral') continue;
      let v; try { v=JSON.parse(r.output?.text); } catch { continue; }
      if (v.version !== 1 || v.number !== pr.number || v.head !== a.before || !sha(v.base) ||
          v.ref !== pr.base.ref || v.head_ref !== pr.head.ref || v.actor !== a.actor.login ||
          !sha(v.merge_base) || !Array.isArray(v.review_heads) || !v.review_heads.every(sha) || !Array.isArray(v.overlap)) continue;
      const c=await api.get(`/repos/${repo}/git/commits/${a.after}`);
      if (c.sha !== a.after || c.parents?.length !== 2 || c.parents[0].sha !== v.head || c.parents[1].sha !== v.base) continue;
      const unchanged=await delta(api,repo,v.merge_base,v.head) === await delta(api,repo,v.base,a.after);
      proven.set(a.id,{...v,unchanged,review_heads:unchanged?v.review_heads:[]}); break;
    }
  }
  // 仅连续的关卡同步能延续绑定；普通推送，即使又推回旧 SHA，也会截断。
  const latest=activities[0];
  const v=latest?.after === pr.head.sha ? proven.get(latest.id) : null;
  const unknownBot = latest?.actor?.type === 'Bot' && !Object.hasOwn(policy.builders, latest.actor.login);
  const reason = v ? null : proven.size
    ? '关卡同步后又有普通推送，旧评审不沿用，须按当前 head 重新评审。'
    : unknownBot ? '无法证明当前推送是关卡的干净同步，须按当前 head 重新评审。' : null;
  return {proven, current:v ?? null, reason};
}

// compare 的提交列表逐页取全，再逐提交取文件；不能拿 300 个文件上限的首页猜“不重叠”。
async function commitsBetween(api,repo,base,head) {
  const path=`/repos/${repo}/compare/${base}...${head}?per_page=100`;
  const first=await api.get(path);
  const commits=await paginate(api,path,'commits');
  if (!Number.isInteger(first.total_commits) || commits.length !== first.total_commits)
    throw new Error('main 新提交列表不完整');
  return {first,commits};
}
export async function prepareSynchronization(api,repo,number,facts,actor) {
  const pr=await api.get(`/repos/${repo}/pulls/${number}`);
  assertPrSnapshot(pr, facts.pr);
  const metadata=await api.get(`/repos/${repo}`);
  // 本任务只同步 main/default branch，同仓库分支；不给叉库增加写权限。
  if (pr.base.ref !== metadata.default_branch || pr.head.repo?.full_name !== repo) return null;
  const {first,commits}=await commitsBetween(api,repo,pr.head.sha,pr.base.sha);
  if (!commits.length) return null;
  if (pr.mergeable === false) return {conflict:true,note:'main 与本单有冲突，关卡不同步、不解冲突，留给人处理。'};
  if (pr.mergeable === null) throw new TransientPrState('GitHub 还在计算能否干净同步');
  if (pr.mergeable !== true) throw new Error('GitHub 合并状态缺失或不合法');
  const touched=new Set();
  for (const c of commits) {
    const files=await paginate(api,`/repos/${repo}/commits/${c.sha}?per_page=100`,'files');
    for (const f of files) for (const name of [f.filename,f.previous_filename].filter(Boolean)) touched.add(name);
  }
  if (!sha(first.merge_base_commit?.sha) || !sha(pr.base.sha)) throw new Error('缺共同祖先或 main 提交');
  const overlap=facts.files.filter(f=>touched.has(f));
  const fresh=await api.get(`/repos/${repo}/pulls/${number}`);
  assertPrSnapshot(fresh, facts.pr);
  return {intent:syncIntent(number,pr.head.sha,pr.base.sha,pr.base.ref,pr.head.ref,actor,
    facts.merge_request.key,facts.synchronization?.review_heads ?? [],overlap,first.merge_base_commit.sha),
    note:overlap.length ? `关卡将自动同步 main；main 碰了本单文件（${overlap.join('、')}），同步后须重新评审。`
      :`关卡将自动同步 main；main 没有碰本单文件，同步后沿用 ${pr.head.sha} 的评审，仍须新 head 的 CI 通过。`};
}

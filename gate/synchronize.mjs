// 关卡写入的同步意向 + 实际推送活动 + 双亲提交共同证明来源。
// 意向先保存再调用带 expected_head_sha 的异步接口，进程中断也能由下一轮核实。
import { paginate } from './collect.mjs';
export class TransientPrState extends Error {}
export function assertPrSnapshot(pr, expected) {
  if (!sha(pr.head?.sha) || !sha(pr.base?.sha) || typeof pr.base?.ref !== 'string' ||
      !['open','closed'].includes(pr.state)) throw new Error('GitHub PR 快照缺失或不合法');
  if (pr.state !== 'open' || pr.head.sha !== expected.head_sha ||
      pr.base.ref !== expected.base_ref) {
    throw new TransientPrState('PR 状态已改变，重新读取现状后再判定');
  }
}
// PR 的 base.sha 是记录的基准；当前目标分支位置只从 Git ref 读取。
export async function baseTip(api, repo, ref) {
  const value=await api.get(`/repos/${repo}/git/ref/heads/${encodeURIComponent(ref)}`);
  if (!sha(value.object?.sha)) throw new Error('目标分支引用缺少合法提交');
  return value.object.sha;
}
export async function assertBaseTip(api, repo, ref, expected) {
  if (await baseTip(api,repo,ref) !== expected)
    throw new TransientPrState('main 在读取或写入期间已前进，重新读取现状后再判定');
}
export const SYNC_CHECK = 'aiwork-main-sync';
// 检查结果正文的接口上限是 65535 个字符；留一点余量，按 UTF-8 字节判断。
export const MAX_INTENT_BYTES = 60000;
const sha = s => typeof s === 'string' && /^[0-9a-f]{40}$/.test(s);
// overlap_unknown: main 某个提交的文件列表可能被接口截断（单个提交最多 300 个），
// 无法确认是否碰了本单文件；这种同步不能沿用评审或合并标签。
export function syncIntent(number, head, base, ref, headRef, actor, binding, reviewHeads, overlap, mergeBase, overlapUnknown = false) {
  const uncertain = overlapUnknown || overlap.length > 0;
  return {version:1,number,head,base,merge_base:mergeBase,ref,head_ref:headRef,actor,binding,
    overlap_unknown:!!overlapUnknown,
    review_heads:uncertain ? [] : [head,...reviewHeads],overlap};
}
// 意向必须能被下一轮完整读回。超长时只保留核心字段和尽量多的 overlap 样本，
// 明确标成截断；下一轮据此拒绝沿用评审和标签，而不是把半截意向当成干净同步。
export function encodeSyncIntent(intent) {
  const size = value => Buffer.byteLength(JSON.stringify(value), 'utf8');
  if (size(intent) <= MAX_INTENT_BYTES) return JSON.stringify(intent);
  const trimmed = {...intent,truncated:true,overlap_unknown:true,review_heads:[],overlap:[]};
  const overlap = [];
  for (const item of intent.overlap ?? []) {
    const trial = {...trimmed,overlap:[...overlap,item]};
    if (size(trial) > MAX_INTENT_BYTES) break;
    overlap.push(item);
  }
  trimmed.overlap = overlap;
  if (size(trimmed) > MAX_INTENT_BYTES) throw new Error('同步意向的核心字段超过检查结果正文上限');
  return JSON.stringify(trimmed);
}
export function syncCheck(intent) {
  return {name:SYNC_CHECK,head_sha:intent.head,status:'completed',conclusion:'neutral',
    external_id:JSON.stringify([intent.number,intent.head,intent.base]),output:{title:'关卡自动同步意向',summary:`同步 ${intent.base} 到 ${intent.head}；结果由实际推送与提交双亲核实。`,text:encodeSyncIntent(intent)}};
}
// 截断的 tree 不当作读取失败：提交双亲仍能证明这是关卡意向对应的推送，
// 只是无法证明 PR 自身改动未变，因此不沿用评审/标签，等重新评审。
async function tree(api,repo,commit) {
  const c=await api.get(`/repos/${repo}/git/commits/${commit}`);
  if (!sha(c.tree?.sha)) throw new Error('提交缺 tree');
  const t=await api.get(`/repos/${repo}/git/trees/${c.tree.sha}?recursive=1`);
  if (t.truncated !== false || !Array.isArray(t.tree)) return null;
  return new Map(t.tree.filter(e=>e.type !== 'tree').map(e=>[e.path,[e.mode,e.type,e.sha]]));
}
async function delta(api,repo,base,head) {
  const a=await tree(api,repo,base),b=await tree(api,repo,head);
  if (a === null || b === null) return null;
  return JSON.stringify([...new Set([...a.keys(),...b.keys()])].sort()
    .filter(k=>JSON.stringify(a.get(k)) !== JSON.stringify(b.get(k)))
    .map(k=>[k,a.get(k) ?? null,b.get(k) ?? null]));
}
// 列表接口可能不带完整 output.text；正文缺失或解析失败时按检查 id 重取一次，
// 还读不出就是数据不全（G8），不能当成「没有意向」。重取读的是检查，优先用有 checks 权限的读取器；
// workflow 的 GITHUB_TOKEN 没有 checks 权限，不能拿它做这次回退。
async function intentOf(api, lookupApi, repo, r) {
  const read = async () => {
    if (typeof r.output?.text === 'string') {
      try { return JSON.parse(r.output.text); } catch {}
    }
    if (!Number.isSafeInteger(r.id)) throw new Error(`同步意向检查缺少可重取的 id（提交 ${r.head_sha}）`);
    const getCheckRun = lookupApi?.get ? lookupApi.get.bind(lookupApi) : api.get.bind(api);
    const full=await getCheckRun(`/repos/${repo}/check-runs/${r.id}`);
    if (typeof full?.output?.text !== 'string') throw new Error(`同步意向检查 #${r.id} 读不到正文`);
    try { return JSON.parse(full.output.text); } catch {
      throw new Error(`同步意向检查 #${r.id} 的正文不是合法 JSON`);
    }
  };
  try { return await read(); } catch (e) {
    if (e instanceof SyntaxError) throw new Error(`同步意向检查 #${r.id} 的正文不是合法 JSON`);
    throw e;
  }
}
async function descends(api,repo,base,actual) {
  if (base === actual) return true;
  const cmp=await api.get(`/repos/${repo}/compare/${base}...${actual}`);
  return cmp?.status === 'ahead' || cmp?.status === 'identical';
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
      const v=await intentOf(api,bindingApi,repo,r);
      if (v.version !== 1 || v.number !== pr.number || v.head !== a.before || !sha(v.base) ||
          v.ref !== pr.base.ref || v.head_ref !== pr.head.ref || v.actor !== a.actor.login ||
          !sha(v.merge_base) || !Array.isArray(v.review_heads) || !v.review_heads.every(sha) ||
          !Array.isArray(v.overlap) || (v.overlap_unknown !== undefined && typeof v.overlap_unknown !== 'boolean') ||
          (v.truncated !== undefined && typeof v.truncated !== 'boolean')) continue;
      const c=await api.get(`/repos/${repo}/git/commits/${a.after}`);
      if (c.sha !== a.after || c.parents?.length !== 2 || c.parents[0].sha !== v.head) continue;
      // 写意向与 update-branch 之间 main 可能前进，GitHub 会用新的 main 生成合并提交。
      // 以实际第二双亲为合并基准核实，而不是让这次关卡自己的推送永远证明不了。
      const actualBase=c.parents[1].sha;
      if (!sha(actualBase) || !(await descends(api,repo,v.base,actualBase))) continue;
      const before=await delta(api,repo,v.merge_base,v.head);
      const after=await delta(api,repo,actualBase,a.after);
      const treeComplete=before !== null && after !== null;
      const unchanged=treeComplete && before === after;
      // 只有树差相同、main 未碰本单文件且意向没有被截断，才延续评审与合并标签。
      const retains=unchanged && !v.overlap_unknown && !v.truncated && v.overlap.length === 0;
      proven.set(a.id,{...v,base:actualBase,intent_base:v.base,base_advanced:actualBase!==v.base,
        tree_complete:treeComplete,unchanged,retains,review_heads:retains?v.review_heads:[]}); break;
    }
  }
  // 仅连续的关卡同步能延续绑定；普通推送，即使又推回旧 SHA，也会截断。
  const latest=activities[0];
  const v=latest?.after === pr.head.sha ? proven.get(latest.id) : null;
  const unknownBot = latest?.actor?.type === 'Bot' && !Object.hasOwn(policy.builders, latest.actor.login);
  const reason = v ? null
    : unknownBot ? (proven.size
      ? '关卡同步后又有无法核实的 bot 推送，旧评审不沿用，须按当前 head 重新评审。'
      : '无法证明当前推送是关卡的干净同步，须按当前 head 重新评审。')
    : proven.size ? '关卡同步后又有普通推送，旧评审不沿用，须按当前 head 重新评审。' : null;
  return {proven, current:v ?? null, reason};
}

// compare 的提交列表逐页取全，再逐提交取文件；不能拿 300 个文件上限的首页猜“不重叠”。
async function commitsBetween(api,repo,base,head) {
  const path=`/repos/${repo}/compare/${base}...${head}?per_page=100`;
  const first=await api.get(path);
  if (!Number.isInteger(first.total_commits)) throw new Error('main 新提交列表不完整');
  const commits=await paginate(api,path,'commits');
  // 比较范围是固定提交，main 前进不会改变结果；条数对不上是这次读取不完整（如分页缺失），
  // 重读同样的固定范围也不会自己变好，按数据不全（G8）拒绝，不能当成瞬时状态等下去。
  if (commits.length !== first.total_commits)
    throw new Error('读取 main 新提交时条数对不上，无法确认是否碰了本单文件');
  return {first,commits};
}
// GitHub 的单个提交文件列表最多 300 个，且没有可靠的截断标记；正好 300 个就不能声称已经看全。
const COMMIT_FILES_CAP = 300;
export async function prepareSynchronization(api,repo,number,facts,actor) {
  const pr=await api.get(`/repos/${repo}/pulls/${number}`);
  assertPrSnapshot(pr, facts.pr);
  const metadata=await api.get(`/repos/${repo}`);
  // 本任务只同步 main/default branch，同仓库分支；不给叉库增加写权限。
  if (pr.base.ref !== metadata.default_branch || pr.head.repo?.full_name !== repo) return null;
  const main=await baseTip(api,repo,pr.base.ref);
  const {first,commits}=await commitsBetween(api,repo,pr.head.sha,main);
  await assertBaseTip(api,repo,pr.base.ref,main);
  if (!commits.length) return null;
  if (pr.mergeable === false) return {conflict:true,note:'main 与本单有冲突，关卡不同步、不解冲突，留给人处理。'};
  if (pr.mergeable === null) throw new TransientPrState('GitHub 还在计算能否干净同步');
  if (pr.mergeable !== true) throw new Error('GitHub 合并状态缺失或不合法');
  const touched=new Set();
  let overlapUnknown=false;
  for (const c of commits) {
    const files=await paginate(api,`/repos/${repo}/commits/${c.sha}?per_page=100`,'files');
    if (files.length >= COMMIT_FILES_CAP) overlapUnknown=true;
    for (const f of files) for (const name of [f.filename,f.previous_filename].filter(Boolean)) touched.add(name);
  }
  if (!sha(first.merge_base_commit?.sha)) throw new Error('缺共同祖先提交');
  const overlap=facts.files.filter(f=>touched.has(f));
  const fresh=await api.get(`/repos/${repo}/pulls/${number}`);
  assertPrSnapshot(fresh, facts.pr);
  await assertBaseTip(api,repo,pr.base.ref,main);
  return {intent:syncIntent(number,pr.head.sha,main,pr.base.ref,pr.head.ref,actor,
    facts.merge_request.key,facts.synchronization?.review_heads ?? [],overlap,first.merge_base_commit.sha,overlapUnknown),
    note:overlapUnknown ? '关卡将自动同步 main；main 有提交的文件列表可能被接口截断（单个提交最多 300 个），无法确认是否碰了本单文件，同步后须重新评审并重贴合并标签。'
      :overlap.length ? `关卡将自动同步 main；main 碰了本单文件（${overlap.join('、')}），同步后须重新评审并重贴合并标签。`
      :`关卡将自动同步 main；main 没有碰本单文件，同步后沿用 ${pr.head.sha} 的评审，仍须新 head 的 CI 通过。`};
}

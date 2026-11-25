// 只接线：事实、评审资格和派发状态都由关卡提供。
import { readFileSync } from 'node:fs';
import { collect, paginate } from '../gate/collect.mjs';
import { decide } from '../gate/decide.mjs';
import { validatePolicy } from '../gate/run.mjs';
import { githubClient } from '../gate/github.mjs';

// PR 被关卡按本轮评审直接合并后就会关闭。派发器收尾时还会再读状态，
// 不能把这种预期内的关闭当成「读不到关卡状态」：先核对同一 head 上关卡
// 自己写下的成功检查，再从检查所属 App 的 slug 认出合并账号。
async function mergedByGate(api, repository, facts, policy) {
  if (facts.pr.state !== 'closed' || facts.pr.merged !== true || !facts.pr.merged_by) return false;
  const runs = await paginate(api,
    `/repos/${repository}/commits/${facts.pr.head_sha}/check-runs?check_name=${encodeURIComponent(policy.check_name)}&filter=all&per_page=100`,
    'check_runs');
  const own = runs.filter((r) => r.name === policy.check_name && r.app?.id === policy.gate_app_id &&
    r.head_sha === facts.pr.head_sha && r.status === 'completed' && r.conclusion === 'success');
  const slugs = new Set(own.map((r) => r.app?.slug).filter(Boolean));
  return slugs.size === 1 &&
    facts.pr.merged_by.toLowerCase() === `${[...slugs][0]}[bot]`.toLowerCase();
}

const { repository, number, builder_family } = JSON.parse(readFileSync(0, 'utf8'));
if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository) ||
    !Number.isSafeInteger(number) || number < 1 || !/^[a-z][a-z0-9-]*$/.test(builder_family ?? '')) {
  throw new Error('invalid repository/PR/builder family');
}
if (!process.env.GH_TOKEN) throw new Error('missing read token');
const api = githubClient().reader(process.env.GH_TOKEN);
const metadata = await api.get(`/repos/${repository}`);
if (!metadata.default_branch) throw new Error('repository default branch missing');
const source = await api.get(`/repos/${repository}/contents/.aiwork/policy.json?ref=${encodeURIComponent(metadata.default_branch)}`);
if (source.type !== 'file' || source.encoding !== 'base64') throw new Error('invalid default-branch policy');
const policy = JSON.parse(Buffer.from(source.content, 'base64').toString('utf8'));
validatePolicy(policy);
const facts = await collect(api, repository, number, policy);
const merged = await mergedByGate(api, repository, facts, policy);
if (!merged && facts.pr.state !== 'open') throw new Error('PR is not open');
// 合并后 GitHub 不再把 CI 运行关联到 PR；关卡能合并本身证明合并时 CI 是绿的。
// 其余直接合并条件仍按当前事实重算，没达到就不算「按本轮评审直接合并」。
const result = decide(merged
  ? { ...facts, ci: { state: 'success', detail: '关卡已按这个 head 合并（合并即证明当时 CI 通过）' } }
  : facts, policy);
if (merged && result.direct_merge?.ok !== true)
  throw new Error('PR closed without the direct-merge conditions for this head');
process.stdout.write(JSON.stringify({
  head: facts.pr.head_sha, policy_sha: source.sha, ...result.review_state,
  // 执行方只影响是否派腿，不能改写关卡对作者和评审的判断。
  excluded: [...new Set([...result.review_state.excluded, builder_family])],
  gate: { title: result.title, conclusion: result.conclusion, summary: result.summary },
}));

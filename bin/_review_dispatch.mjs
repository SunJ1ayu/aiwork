// 只接线：事实、评审资格和派发状态都由关卡提供。
import { readFileSync } from 'node:fs';
import { collect } from '../gate/collect.mjs';
import { decide } from '../gate/decide.mjs';
import { validatePolicy } from '../gate/run.mjs';
import { githubClient } from '../gate/github.mjs';

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
if (facts.pr.state !== 'open') throw new Error('PR is not open');
const result = decide(facts, policy);
process.stdout.write(JSON.stringify({
  head: facts.pr.head_sha, policy_sha: source.sha, ...result.review_state,
  // 执行方只影响是否派腿，不能改写关卡对作者和评审的判断。
  excluded: [...new Set([...result.review_state.excluded, builder_family])],
  gate: { title: result.title, conclusion: result.conclusion, summary: result.summary },
}));

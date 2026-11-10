// Read-only GitHub adapter for the same collector and qualification used by gate.
import { readFileSync } from 'node:fs';
import { collect } from '../gate/collect.mjs';
import { decide } from '../gate/decide.mjs';
import { validatePolicy } from '../gate/run.mjs';
import { reviewPlan } from '../gate/review-plan.mjs';
const { repository, number }=JSON.parse(readFileSync(0,'utf8'));
if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository) || !Number.isSafeInteger(number) || number<1) throw new Error('invalid repository/PR');
const token=process.env.GH_TOKEN;
if (!token) throw new Error('missing read token');
async function request(path, body) {
  const url=new URL(path,'https://api.github.com');
  if (url.origin!=='https://api.github.com') throw new Error('unexpected GitHub pagination host');
  const response=await fetch(url,{method:body?'POST':'GET',redirect:'error',
    headers:{Authorization:`Bearer ${token}`,Accept:'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28',
             ...(body?{'Content-Type':'application/json'}:{})},
    ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});
  if (!response.ok) throw new Error(`GitHub read failed (${response.status})`);
  return {data:await response.json(),link:response.headers.get('link')};
}
const api={
  async get(path) {return (await request(path)).data;},
  async getPage(path) {const {data,link}=await request(path);return {data,next:/<([^>]+)>;\s*rel="next"/.exec(link??'')?.[1]??null};},
  async graphql(query,variables) {const {data}=await request('/graphql',{query,variables});if (data.errors?.length) throw new Error('GitHub GraphQL read failed');return data.data;},
};
const source=await api.get(`/repos/${repository}/contents/.aiwork/policy.json?ref=main`);
if(source.type!=='file' || source.encoding!=='base64') throw new Error('invalid main policy');
const policy=JSON.parse(Buffer.from(source.content,'base64').toString('utf8'));
validatePolicy(policy);
const facts=await collect(api,repository,number,policy);
if(facts.pr.state!=='open') throw new Error('PR is not open');
const result=decide(facts,policy);
process.stdout.write(JSON.stringify({head:facts.pr.head_sha,policy_sha:source.sha,
  plan:reviewPlan(facts.files,policy),passes:result.passes.map(p=>p.family),
  excluded:result.author.known?[result.author.family]:Object.values(policy.builders),
  gate:{title:result.title,conclusion:result.conclusion,summary:result.summary}}));

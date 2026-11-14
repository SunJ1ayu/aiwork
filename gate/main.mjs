// aiwork 放行关卡入口:由调用方仓库的 aiwork-gate workflow 调用。代码在 SunJ1ayu/aiwork 的 gate/，永远是那边 main 上的这一份。
// 这里只管"接线":真实的 GitHub API、aiwork-gate App 的令牌、发 / 改检查。流程和失败处理在 run.mjs。
// 读数据用 GITHUB_TOKEN(权限见 templates/aiwork-gate.yml 的 permissions);发检查结果用 aiwork-gate App 的临时令牌 ——
// 分支规则只认这个 App 发的结果,PR 自己加的 workflow 用 GITHUB_TOKEN 发一个同名检查也冒充不了。
// 合并(run.mjs 第 4 步)另换一张 App 令牌,只在真要合并时才换:发检查的那张始终只有 checks: write。
import { createSign } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import { bindingFromEvent } from "./merge-request.mjs";
import { validatePolicy, gate } from "./run.mjs";
import { githubClient } from "./github.mjs";

const env = process.env;
const repo = env.GITHUB_REPOSITORY;
// 策略在调用方项目的检出里。路径只认 workflow 传入的 AIWORK_POLICY_PATH，不按本文件的位置去找。
// 读不出 / 不是合法 JSON 交给 gate() 的策略校验拒绝,不会判定或合并 PR
let policy = null;
try {
  const policyPath = env.AIWORK_POLICY_PATH;
  if (!policyPath) throw new Error("workflow 没有传入 AIWORK_POLICY_PATH");
  policy = JSON.parse(readFileSync(policyPath, "utf8"));
} catch (e) {
  console.log(`读不了策略:${e.message}`);
}

const { request, reader } = githubClient(env);
const api = reader(env.GITHUB_TOKEN);

const b64url = (x) => Buffer.from(x).toString("base64url");
// 按权限分开换、分开缓存:一张令牌只带这一类请求要的权限
const appTokens = new Map();
async function appToken(permissions) {
  const want = JSON.stringify(permissions);
  if (appTokens.has(want)) return appTokens.get(want);
  const key = env.AIWORK_GATE_PRIVATE_KEY;
  if (!key) throw new Error("缺 aiwork-gate App 的私钥(environment aiwork-gate 的 secret AIWORK_GATE_PRIVATE_KEY)");
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: String(policy.gate_app_id) }))}`;
  const jwt = `${unsigned}.${b64url(createSign("RSA-SHA256").update(unsigned).sign(key))}`;
  const inst = (await request("GET", `/repos/${repo}/installation`, jwt)).data;
  const tok = (
    await request("POST", `/app/installations/${inst.id}/access_tokens`, jwt, {
      repositories: [repo.split("/")[1]],
      permissions,
    })
  ).data;
  appTokens.set(want, tok.token);
  return tok.token;
}
const CHECKS = { checks: "write" };
// 合并接口要 contents + pull_requests;PR 改了 .github/workflows/ 的,GitHub 还要 workflows 才让 App 合
const MERGE = { contents: "write", pull_requests: "write", workflows: "write" };

const output = (r) => ({ title: r.title, summary: r.summary.slice(0, 60000) });
const poster = {
  async start(sha) {
    const res = await request("POST", `/repos/${repo}/check-runs`, await appToken(CHECKS), {
      name: policy.check_name,
      head_sha: sha,
      status: "in_progress",
      output: { title: "重算中", summary: "aiwork-gate 正在重新判定;没算完之前不放行。" },
    });
    return res.data.id;
  },
  async finish(sha, result, id) {
    const body = { status: result.status, output: output(result) };
    if (result.status === "completed") body.conclusion = result.conclusion;
    await request("PATCH", `/repos/${repo}/check-runs/${id}`, await appToken(CHECKS), body);
  },
};

// 带上判过的 head:判完之后又推了新提交,接口就拒(409),不会把没判过的提交合进去
const merger = {
  async merge(number, sha) {
    await request("PUT", `/repos/${repo}/pulls/${number}/merge`, await appToken(MERGE), { sha, merge_method: "merge" });
  },
};

// 只保存原始 labeled 载荷的冻结版本；从不拿随后查询到的 head 补记录。
validatePolicy(policy);
if (env.GITHUB_EVENT_NAME === "pull_request_target" && env.GITHUB_EVENT_PATH) {
  const binding = bindingFromEvent(env.GITHUB_EVENT_NAME,
    JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8")), repo, policy);
  if (binding) {
    try {
      await request("POST", `/repos/${repo}/check-runs`, await appToken(CHECKS), binding);
    } catch (e) {
      console.log(`合并申请记录保存失败，未记录的申请不会合并：${e.message}`);
    }
  }
}

await gate({
  repo,
  policy,
  api,
  poster,
  // 使用已有的检查令牌读取绑定，不增加 workflow 凭证权限。
  bindingApi: { async getPage(path) { return reader(await appToken(CHECKS)).getPage(path); } },
  merger,
  log: (line) => {
    console.log(line);
    if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${line}\n\n`);
  },
});

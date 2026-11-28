// aiwork 放行关卡入口 main.mjs 的整机冒烟:起一个假的 GitHub API,真跑 main.mjs 子进程。
// 钉住接线本身:JWT 用 App ID 签、公钥验得过;换令牌只要 checks:write;读数据用 GITHUB_TOKEN;
// 先发 in_progress 占位,再把同一条检查 PATCH 成结论;读 PR 出错时占位被改成 failure;
// 合并用另换的一张令牌(只在要合并时才换),带上判过的 head。
// 跑法:node --test tests/test_aiwork_gate_main.mjs
import { mergeBindingKey } from "../gate/merge-request.mjs";
import { test } from "node:test";
import { collect } from "../gate/collect.mjs";
import { decide } from "../gate/decide.mjs";
import { retryDelay } from "../gate/run.mjs";
import { githubClient } from "../gate/github.mjs";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { spawn } from "node:child_process";
import { cpSync, readdirSync, mkdirSync, mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const policy = JSON.parse(readFileSync(new URL("./fixtures/gate-logic-policy.json", import.meta.url), "utf8"));
const MAIN = new URL("../gate/main.mjs", import.meta.url).pathname;
const HEAD = "a".repeat(40);
const SYNC_BASE = "b".repeat(40);
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const PEM = privateKey.export({ type: "pkcs8", format: "pem" });

function fakeGitHub(opts = {}) {
  const log = [];
  const checks = new Map();
  if (opts.previousSuccess) checks.set(4241, { id: 4241, name: policy.check_name, status: "completed", conclusion: "success" });
  let nextCheck = 4242;
  let baseSha=SYNC_BASE;
  const numbers = opts.twoPrs ? [10, 11] : [10];
  let merged10 = false;
  const prFor = (number) => ({
    number, state: opts.closedPr ? "closed" : "open", changed_files: opts.files?.length ?? 1,
    ...(opts.closedPr ? { merged: opts.merged ?? true,
      merged_by: opts.merged === false ? null : { login: opts.mergedBy ?? "aiwork-gate[bot]", type: "Bot" } } : {}),
    ...(opts.draft ? { draft: true } : {}),
    labels: opts.mergeReady ? [{ name: policy.merge_label }] : [],
    mergeable: opts.conflict ? false : true,
    ...(opts.behindAlways || (opts.twoPrs && merged10 && number === 11) ? { mergeable_state: 'behind' } : {}),
    head: { sha: HEAD, ref: "claude/x", repo: { full_name: (opts.forkHead || (opts.forkAfterMerge && merged10)) && number === 11 ? "fork/r" : "o/r" } },
    base: { ref: "main", sha: opts.staleBase ?? baseSha },
  });

  const server = createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const auth = req.headers.authorization ?? "";
      const record = { method: req.method, url: req.url, auth, userAgent: req.headers["user-agent"], body: body ? JSON.parse(body) : null };
      log.push(record);
      const send = (code, data, headers = {}) => { res.writeHead(code, { "content-type": "application/json", ...headers }); res.end(JSON.stringify(data)); };
      const u = req.url;
      if (u === '/repos/o/r/git/ref/heads/main') return send(200,{object:{sha:baseSha}});
      if (u === '/repos/o/r') return send(200, {default_branch: opts.defaultBranch ?? 'main'});
      if (u.startsWith('/repos/o/r/contents/.aiwork/policy.json?ref=')) {
        return send(200, {type:'file', encoding:'base64', sha:'b'.repeat(40),
          content:Buffer.from(JSON.stringify(opts.dispatchPolicy ?? policy)).toString('base64')});
      }
      if (opts.pauseAt === u && (!opts.pausePermission || record.body?.permissions?.[opts.pausePermission])) {
        opts.onPause(); return;
      }
      if (u === '/app') return send(200,{id:policy.gate_app_id,slug:'aiwork-gate'});
      if (u.startsWith('/repos/o/r/compare/')) {
        const behind=(opts.sync || (opts.behindAfterMerge && merged10)) && u.includes('...'+baseSha);
        return send(200,{total_commits:behind?1:0,commits:behind?[{sha:baseSha}]:[],merge_base_commit:{sha:'c'.repeat(40)}});
      }
      if (u.startsWith(`/repos/o/r/commits/${baseSha}?`)) return send(200,{files:[{filename:opts.overlap?'web/a.ts':'main-only.ts'}]});
      if (/^\/repos\/o\/r\/pulls\/\d+\/update-branch$/.test(u) && req.method === 'PUT') {
        const number=Number(u.split('/').at(-2));
        const fails=opts.updateFails || opts.updateFailsNumber===number;
        if(opts.moveOnUpdate){opts.moveOnUpdate=false;baseSha='d'.repeat(40);return send(422,{message:'branch changed'});}
        return send(fails?422:202,{message:fails?'branch moved':'updating'});
      }
      if (u === "/repos/o/r/installation") return send(200, { id: 777 });
      // 按要的权限发不同的令牌,好分清哪个请求用的是哪张
      if (u === "/app/installations/777/access_tokens") return send(201, { token: JSON.parse(body).permissions.checks ? "app-check-token" : "app-merge-token" });
      if (/^\/repos\/o\/r\/pulls\/\d+\/merge$/.test(u) && req.method === "PUT") {
        const number=Number(u.split('/').at(-2));
        if(opts.twoPrs){
          if(number===10 && !merged10){merged10=true;baseSha='d'.repeat(40);return send(200,{merged:true});}
          if(number===11 && merged10)return send(405,{message:'Head branch is not up to date'});
          return send(200,{merged:true});
        }
        if(opts.moveOnMerge){opts.moveOnMerge=false;opts.sync=true;baseSha='d'.repeat(40);return send(409,{message:'base changed'});}
        return opts.mergeFails?send(405,{message:"Required status check aiwork-gate is expected"}):send(200, { merged: true });
      }
      if (u === "/repos/o/r/check-runs" && req.method === "POST") {
        if (opts.bindingFails && record.body.name === "aiwork-merge-request") return send(502, { message: "binding failed" });
        if (opts.syncRecordFails && record.body.name === 'aiwork-main-sync') return send(502,{message:'sync record failed'});
        if (opts.appStartFails) return send(502, { message: "App start failed" });
        if (opts.hang && auth === "Bearer app-check-token") return; // 一直不回
        const id = nextCheck++;
        const check = { ...record.body, id, auth, app: { id: policy.gate_app_id } };
        checks.set(id, check);
        record.checkId = id;
        return send(201, { id });
      }
      if (u.startsWith("/repos/o/r/check-runs/") && req.method === "PATCH") {
        const id = Number(u.split("/").at(-1));
        if (!checks.has(id)) return send(404, { message: "missing check" });
        if (checks.get(id).auth !== auth) return send(403, { message: "wrong check owner" });
        if (opts.appFinishFails && auth === "Bearer app-check-token") return send(502, { message: "App write failed" });
        Object.assign(checks.get(id), record.body);
        if (opts.appFinishResponseLost) { req.socket.destroy(); return; }
        return send(200, { id });
      }
      if (u.startsWith("/repos/o/r/statuses/") && req.method === "POST") {
        return send(422, { message: "status history already full" });
      }
      if (opts.prFails && u === "/repos/o/r/pulls/10") return send(502, { message: "bad gateway" });
      // mergeReady:有合格 PASS、业主贴了合并标签 → 放行并合并
      if (u === "/repos/o/r/pulls?state=open&per_page=100")
        return send(200, numbers.filter(number => !(opts.twoPrs && number === 10 && merged10)).map(prFor));
      const prRoute=/^\/repos\/o\/r\/pulls\/(\d+)$/.exec(u);
      if (prRoute && numbers.includes(Number(prRoute[1]))) {
        const number=Number(prRoute[1]), pr=prFor(number);
        // collect 和 prepare 都读取 PR；在 prepare 读取时才推进状态样本。
        if(opts.mergeableStates && number===10) {
          const readCount=log.filter(r=>r.url===u).length;
          pr.mergeable=opts.mergeableStates[Math.min(Math.floor((readCount-1)/2),opts.mergeableStates.length-1)];
        }
        return send(200, pr);
      }
      const filesRoute=/^\/repos\/o\/r\/pulls\/(\d+)\/files/.exec(u);
      if (filesRoute && numbers.includes(Number(filesRoute[1]))) {
        const files = (opts.files ?? ['web/a.ts']).map(filename=>({filename}));
        if (opts.paginateFiles && !u.includes('page=2')) {
          return send(200, files.slice(0,1), {link:`<http://127.0.0.1:${server.address().port}/repos/o/r/pulls/${filesRoute[1]}/files?per_page=100&page=2>; rel="next"`});
        }
        return send(200, opts.paginateFiles ? files.slice(1) : files);
      }
      const pass = "```json\n" + JSON.stringify({ verdict: "PASS", head_sha: HEAD, model: "gpt-x", family: "openai", completeness: "complete" }) + "\n```";
      const reviews = opts.reviews ?? (opts.mergeReady ? [{ id: 1, user: { login: policy.reviewer_bot, type: "Bot" }, state: "COMMENTED", commit_id: HEAD, submitted_at: "2026-09-29T09:00:00Z", body: pass }] : []);
      const reviewsRoute=/^\/repos\/o\/r\/pulls\/(\d+)\/reviews/.exec(u);
      if (reviewsRoute && numbers.includes(Number(reviewsRoute[1]))) return send(200, reviews);
      if (u.startsWith("/repos/o/r/actions/runs")) return send(200, { workflow_runs: numbers.map((number,i) => ({ id: i+1, path: ".github/workflows/ci.yml", head_sha: HEAD, status: "completed", conclusion: "success", created_at: "2026-09-29T08:00:00Z", pull_requests: opts.closedPr ? [] : [{ number }] })) });
      if (u.startsWith("/repos/o/r/activity")) return send(200, [{ id: 1, timestamp: "t", activity_type: "branch_creation", before: "0".repeat(40), after: HEAD, actor: { login: opts.actorLogin ?? "SunJ1ayuBoT" } }]);
      if (u.includes('/check-runs?')) {
        const requested = new URL(u, "http://fake").searchParams.get('check_name');
        if (requested === policy.check_name) {
          const records = opts.gateCheckRuns ?? [{
            id: 9001, name: policy.check_name, head_sha: HEAD, status: "completed",
            conclusion: opts.gateCheckConclusion ?? "success",
            app: { id: policy.gate_app_id, slug: opts.gateAppSlug ?? "aiwork-gate" },
          }];
          return send(200, { total_count: records.length, check_runs: records });
        }
        const saved = [...checks.values()].filter(c => c.head_sha === HEAD && c.name === 'aiwork-merge-request');
        const records = opts.bindingRecords ?? (opts.mergeReady ? numbers.map(number => ({ name: 'aiwork-merge-request',
          head_sha: HEAD, app: { id: policy.gate_app_id }, status: 'completed', conclusion: 'neutral',
          external_id: mergeBindingKey(number, policy.merge_label, HEAD, policy.owner) })) : []);
        return send(200, { total_count: records.length + saved.length, check_runs: [...records, ...saved] });
      }
      const events = opts.events ?? (opts.mergeReady ? [{ id: 1, event: "labeled", label: { name: policy.merge_label }, actor: { login: policy.owner }, created_at: "2026-09-29T10:00:00Z" }] : []);
      const eventsRoute=/^\/repos\/o\/r\/issues\/(\d+)\/events/.exec(u);
      if (eventsRoute && numbers.includes(Number(eventsRoute[1]))) return send(200, events);
      const nodes = reviews.map((r) => ({ databaseId: r.id, submittedAt: r.submitted_at, lastEditedAt: null }));
      if (u === "/graphql" && opts.graphqlErrors) return send(200, { errors: [{message:"unavailable"}] });
      if (u === "/graphql" && req.method === "POST") return send(200, { data: { repository: { pullRequest: { reviews: { totalCount: nodes.length, pageInfo: { hasNextPage: false }, nodes } } } } });
      send(404, { message: `fake: no route ${u}` });
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve({ server, log, checks, url: `http://127.0.0.1:${server.address().port}` })));
}

function runMain(apiUrl, extraEnv = {}, main = MAIN, event = { pull_request: { number: 10, head: { sha: HEAD } } }, onSpawn = () => {}) {
  const dir = mkdtempSync(join(tmpdir(), "gate-main-"));
  const eventPath = join(dir, "event.json");
  writeFileSync(eventPath, JSON.stringify(event));
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [main], {
      timeout: 20_000, // 卡住就杀掉,测试红而不是挂住
      env: {
        PATH: process.env.PATH, GITHUB_API_URL: apiUrl, GITHUB_REPOSITORY: "o/r",
        GITHUB_EVENT_NAME: "pull_request_target", GITHUB_EVENT_PATH: eventPath, GITHUB_TOKEN: "read_token",
        AIWORK_GATE_PRIVATE_KEY: PEM,
        AIWORK_POLICY_PATH: new URL("./fixtures/gate-logic-policy.json", import.meta.url).pathname,
        ...extraEnv,
      },
    });
    onSpawn(child);
    let out = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (out += d));
    child.on("close", (code, signal) => {
      rmSync(dir, { recursive: true, force: true });
      resolve({ code, signal, out });
    });
  });
}

// 不在替身里模拟 GitHub 的历史淘汰。平台保留规则见 README 的官方出处；
// 本测试钉住程序不借旧放行、不追加 status；绑定检查仅用于授权合并。
test("整机:不追加 status，合并时只读申请检查，每轮新建放行检查", async () => {
  const budget = readFileSync(new URL("../gate/README.md", import.meta.url), "utf8")
    .match(/即约 `(\d+) \+ (\d+)P` 次 REST 请求/);
  assert.ok(budget, "README 要给出 GITHUB_TOKEN 的单轮 REST 公式");
  // 每条路径都钉住实际 GITHUB_TOKEN REST 读数（P=1，基础公式 2+6P 从 README 读出）；
  // 各路径的加数不在这里复述，见 README「代价」。
  for (const { name, options, readCount: expected, merged } of [
    { name: "不合并", options: {}, readCount: 8, merged: 0 },
    { name: "放行并合并", options: { mergeReady: true }, readCount: 16, merged: 1 },
    { name: "同步后等新 head", options: { sync: true, mergeReady: true }, readCount: 19, merged: 0 },
    { name: "合并被拒并核实", options: { mergeReady: true, mergeFails: true }, readCount: 18, merged: 1 },
  ]) {
    const gh = await fakeGitHub(options);
    try {
      const beforeIds = new Set(gh.checks.keys());
      const { code, out } = await runMain(gh.url);
      assert.equal(code, 0, out);
      const round = gh.log;
      const readCount=round.filter((r) => r.auth === "Bearer read_token" && r.url !== "/graphql").length;
      assert.equal(readCount, expected, `${name}：README 账目要和实际请求数一致`);
      assert.equal(round.filter((r) => r.url === "/graphql").length, 1);
      assert.ok(round.filter((r) => r.auth === "Bearer read_token").every((r) =>
        r.method === "GET" || r.url === "/graphql"), "workflow 凭证只读事实，不写检查");
      assert.deepEqual(checkWrites(round).filter((r) => r.method === "POST").map((r) => r.body.name),
        options.sync ? [policy.check_name, "aiwork-main-sync"] : [policy.check_name], "每轮只新建本轮检查");
      const writes = appWrites(round).filter((r) => r.method === "PATCH" || r.body?.name === policy.check_name);
      // 合并成功后多改写一次，补上「实际合并路径」；合并被拒本来就多一次拒绝摘要。
      const mergeWrites = options.mergeFails ? 3 : options.mergeReady && !options.sync ? 3 : 2;
      assert.equal(writes.length, mergeWrites, "历史多少条都只创建/改写本轮检查，不扫描或重写历史");
      const [create, finish] = [writes[0], writes.at(-1)];
      assert.equal(create.method, "POST");
      assert.equal(create.body.head_sha, HEAD);
      assert.equal(create.body.status, "in_progress");
      assert.ok(!beforeIds.has(create.checkId), "新一轮不能复用上一轮的检查");
      assert.equal(finish.method, "PATCH");
      assert.equal(finish.url, `/repos/o/r/check-runs/${create.checkId}`);
      if (options.sync) assert.equal(finish.body.status, "in_progress", `${name}：最终状态`);
      else assert.equal(finish.body.conclusion, options.mergeReady ? "success" : "failure", `${name}：最终结论`);
      assert.equal(round.filter((r) => r.url === "/repos/o/r/pulls/10/merge").length, merged);
      assert.equal(round.filter((r) => r.url.includes("/statuses/")).length, 0, "旧 status 即使已满也不访问");
      assert.equal(round.filter((r) => r.method === "GET" && r.url.includes("check-runs")).length,
        options.mergeReady ? 1 : 0, "只有带标签的 PR 读取绑定记录；默认检查历史不参与放行");
    } finally {
      gh.server.close();
    }
  }
});

test("整机:JWT 验得过、只要 checks:write、读用 GITHUB_TOKEN、先占位再改成结论", async () => {
  const gh = await fakeGitHub();
  try {
    const { code, out } = await runMain(gh.url);
    assert.equal(code, 0, out);
    const inst = gh.log.find((r) => r.url === "/repos/o/r/installation");
    const jwt = inst.auth.replace(/^Bearer /, "");
    const [h, c, s] = jwt.split(".");
    assert.ok(createVerify("RSA-SHA256").update(`${h}.${c}`).verify(publicKey, Buffer.from(s, "base64url")), "JWT 签名验不过");
    const claims = JSON.parse(Buffer.from(c, "base64url").toString());
    assert.equal(claims.iss, String(policy.gate_app_id));
    assert.ok(claims.exp - claims.iat <= 600);
    const toks = gh.log.filter((r) => r.url === "/app/installations/777/access_tokens");
    assert.deepEqual(toks.map((t) => t.body), [{ repositories: ["r"], permissions: { checks: "write" } }], "不合并就不换合并用的令牌");
    const reads = gh.log.filter((r) => r.method === "GET" && r.url.startsWith("/repos/o/r/") && r.url !== "/repos/o/r/installation");
    assert.ok(reads.length >= 5 && reads.every((r) => r.auth === "Bearer read_token"), "读数据只用 GITHUB_TOKEN");
    const gql = gh.log.filter((r) => r.url === "/graphql");
    assert.ok(gql.length >= 1 && gql.every((r) => r.auth === "Bearer read_token"), "评审改写记录(GraphQL)也只用 GITHUB_TOKEN 读");
    const writes = appWrites(gh.log);
    assert.equal(writes[0].method, "POST");
    assert.equal(writes[0].body.status, "in_progress");
    assert.equal(writes[0].body.name, policy.check_name);
    assert.equal(writes[0].body.head_sha, HEAD);
    assert.ok(writes.every((w) => w.auth === "Bearer app-check-token"), "发检查只用 App 令牌");
    const firstWrite = gh.log.indexOf(writes[0]);
    const firstRead = gh.log.findIndex((r) => r.url.startsWith("/repos/o/r/pulls/"));
    assert.ok(firstWrite < firstRead, "先占位,后读 PR 的数据");
    const last = writes.at(-1);
    assert.equal(last.method, "PATCH");
    assert.equal(last.url, `/repos/o/r/check-runs/${writes[0].checkId}`);
    assert.equal(last.body.status, "completed");
    assert.equal(last.body.conclusion, "failure", "没有评审 ⇒ 不放行");
    assert.match(last.body.output.title, /缺合格评审/);
  } finally {
    gh.server.close();
  }
});

test("整机:定时事件没有 PR/head，仍用既有凭证读取开放 PR、重写 App 检查", async () => {
  const gh = await fakeGitHub();
  try {
    const { code, out } = await runMain(gh.url, { GITHUB_EVENT_NAME: "schedule" }, MAIN, { schedule: "scheduled" });
    assert.equal(code, 0, out);
    assert.ok(gh.log.some((r) => r.url === "/repos/o/r/pulls/10" && r.auth === "Bearer read_token"));
    const writes = appWrites(gh.log);
    assert.equal(writes[0].body.head_sha, HEAD);
    assert.equal(writes[0].body.status, "in_progress");
    assert.equal(writes.at(-1).body.conclusion, "failure");
    assert.match(writes.at(-1).body.output.title, /缺合格评审/);
    assert.deepEqual(gh.log.filter((r) => r.url === "/app/installations/777/access_tokens").map((r) => r.body),
      [{ repositories: ["r"], permissions: { checks: "write" } }]);
  } finally {
    gh.server.close();
  }
});

test("整机:读 PR 出错 → 占位被改成 failure(G8),进程正常结束", async () => {
  const gh = await fakeGitHub({ prFails: true });
  try {
    const { code, out } = await runMain(gh.url);
    assert.equal(code, 0, out);
    const last = appWrites(gh.log).at(-1);
    assert.equal(last.method, "PATCH");
    assert.equal(last.body.conclusion, "failure");
    assert.match(last.body.output.title, /G8/);
  } finally {
    gh.server.close();
  }
});

test("整机:没有私钥 → 进程失败,App 检查不发、PR 的数据一条都不读(只列了开着的 PR)", async () => {
  const gh = await fakeGitHub();
  try {
    const { code } = await runMain(gh.url, { AIWORK_GATE_PRIVATE_KEY: "" });
    assert.notEqual(code, 0);
    assert.equal(appWrites(gh.log).length + gh.log.filter((r) => r.url.startsWith("/repos/o/r/pulls/")).length, 0);
  } finally {
    gh.server.close();
  }
});

const checkWrites = (log) => log.filter((r) => r.url.startsWith("/repos/o/r/check-runs") && ["POST", "PATCH"].includes(r.method));
// 不按令牌过滤，误用 workflow 凭证的检查也必须被身份断言看到。
const appWrites = checkWrites;

test("整机:App 写回失败不合并；服务端已写但响应丢失时也不合并", async () => {
  for (const opts of [{ appFinishFails: true }, { appFinishResponseLost: true }]) {
    const gh = await fakeGitHub({ mergeReady: true, ...opts });
    try {
      const { code, out } = await runMain(gh.url);
      assert.notEqual(code, 0, out);
      const latest = [...gh.checks.values()].at(-1);
      if (opts.appFinishFails) assert.equal(latest.status, "in_progress");
      else assert.equal(latest.conclusion, "success");
      assert.equal(gh.log.filter((r) => r.url.endsWith("/merge")).length, 0);
    } finally {
      gh.server.close();
    }
  }
});

test("整机:策略文件不是合法 JSON → 不发 App 检查、不读 PR 的数据、不合并", async () => {
  const gh = await fakeGitHub({ mergeReady: true, previousSuccess: true });
  const root = mkdtempSync(join(tmpdir(), "gate-policy-"));
  const policyPath = join(root, "policy.json");
  try {
    writeFileSync(policyPath, '{ "check_name": "aiwork-gate-shadow", ');
    const { code, out } = await runMain(gh.url, { AIWORK_POLICY_PATH: policyPath });
    assert.notEqual(code, 0);
    assert.equal(gh.checks.size, 1);
    assert.equal([...gh.checks.values()][0].conclusion, "success");
    assert.ok(!gh.log.some((r) => r.url.endsWith("/merge")));
    assert.match(out, /policy\.json/);
    assert.equal(appWrites(gh.log).length + gh.log.filter((r) => r.url.startsWith("/repos/o/r/pulls/")).length, 0);
  } finally {
    gh.server.close();
    rmSync(root, { recursive: true, force: true });
  }
});

// 策略路径只认 workflow 传入的 AIWORK_POLICY_PATH。把入口放到旧的
// .github/aiwork-gate/ 深度，旁边放一份合法策略：没传路径也不许拿它来判。
test("整机:没传 AIWORK_POLICY_PATH → 不读 main.mjs 相对路径上的 policy.json", async () => {
  const gh = await fakeGitHub();
  const root = mkdtempSync(join(tmpdir(), "gate-rel-"));
  try {
    const gateDir = join(root, ".github", "aiwork-gate");
    mkdirSync(gateDir, { recursive: true });
    for (const name of readdirSync(new URL("../gate/", import.meta.url)).filter(name => name.endsWith(".mjs"))) {
      cpSync(new URL(`../gate/${name}`, import.meta.url), join(gateDir, name));
    }
    mkdirSync(join(root, ".aiwork"));
    writeFileSync(join(root, ".aiwork", "policy.json"), JSON.stringify({ ...policy, check_name: "from-relative" }));
    const { code, out } = await runMain(gh.url, { AIWORK_POLICY_PATH: "" }, join(gateDir, "main.mjs"));
    assert.notEqual(code, 0, out);
    assert.match(out, /AIWORK_POLICY_PATH/);
    const checks = appWrites(gh.log);
    assert.equal(checks.length, 0, out);
  } finally {
    gh.server.close();
    rmSync(root, { recursive: true, force: true });
  }
});

// aiwork-review[bot] 评审(PR #10 review 5362031164,@ a190849)第 3 个阻断点:一个请求卡住,整次运行被拖到超时。
test("整机:发占位的请求卡住 → 按单个请求的超时放弃,不读 PR 的数据、不合并,进程报错结束", async () => {
  const gh = await fakeGitHub({ hang: true });
  try {
    const started = Date.now();
    const { code } = await runMain(gh.url, { AIWORK_GATE_TIMEOUT_MS: "300" });
    assert.notEqual(code, 0);
    assert.ok(Date.now() - started < 10_000, "没被卡住的请求拖住");
    assert.ok(!gh.log.some((r) => r.url.startsWith("/repos/o/r/pulls/")), "未占位就不读数据或合并");
  } finally {
    gh.server.closeAllConnections();
    gh.server.close();
  }
});

test("整机:业主贴了合并标签、判为放行 → 结论写完之后,用另换的合并令牌、带着判过的 head 合并", async () => {
  const gh = await fakeGitHub({ mergeReady: true });
  try {
    const { code, out } = await runMain(gh.url);
    assert.equal(code, 0, out);
    const writes = appWrites(gh.log);
    const conclusion = writes.find((r) => r.method === "PATCH");
    assert.equal(conclusion.body.conclusion, "success", out);
    const merge = gh.log.filter((r) => r.url === "/repos/o/r/pulls/10/merge");
    assert.equal(merge.length, 1, out);
    assert.equal(merge[0].method, "PUT");
    assert.deepEqual(merge[0].body, { sha: HEAD, merge_method: "merge" });
    assert.equal(merge[0].auth, "Bearer app-merge-token");
    // 合并接口要 contents + pull_requests;改了 .github/workflows/ 的 PR 还要 workflows,否则 GitHub 拒绝 App 合并
    const tok = gh.log.find((r) => r.url === "/app/installations/777/access_tokens" && !r.body.permissions.checks);
    assert.deepEqual(tok.body, { repositories: ["r"], permissions: { contents: "write", pull_requests: "write", workflows: "write" } });
    assert.ok(checkWrites(gh.log).every((r) => r.auth !== "Bearer app-merge-token"), "发检查不用合并令牌");
    const written = gh.log.indexOf(conclusion);
    assert.ok(written >= 0 && written < gh.log.indexOf(merge[0]), "先写放行的结论,再合并");
    assert.match(writes.at(-1).body.output.summary, /实际合并路径：PR #10 按 SunJ1ayu 的合并标签合并/,
      "合并后补写的摘要要记实际走的标签路径");
  } finally {
    gh.server.close();
  }
});

test("整机:旧 success 在重算开始时被新占位压住，取消不会发合并请求", async () => {
  // 已写的 success 不会因取消而撤销，但合并不会复用上轮结论。
  for (const [pauseAt, expected, pausePermission] of [
    ["/repos/o/r/installation", "success"],
    ["/repos/o/r/pulls/10", "in_progress"],
    ["/repos/o/r/check-runs/4242", "in_progress"],
    ["/app/installations/777/access_tokens", "success", "contents"],
  ]) {
    const opts = { mergeReady: true, previousSuccess: true, pauseAt, pausePermission };
    const gh = await fakeGitHub(opts);
    try {
      const { signal, out } = await runMain(gh.url, {}, MAIN, {}, (child) => {
        opts.onPause = () => child.kill("SIGTERM");
      });
      assert.equal(signal, "SIGTERM", out);
      const latest = [...gh.checks.values()].at(-1);
      assert.equal(latest.status === "completed" ? latest.conclusion : latest.status, expected);
      assert.ok(!gh.log.some((r) => r.url.endsWith("/merge")), "未完成本轮写回就不能合并");
      assert.ok(!gh.log.some((r) => r.auth === "Bearer read_token" && r.method !== "GET" && r.url !== "/graphql"));
    } finally {
      gh.server.closeAllConnections();
      gh.server.close();
    }
  }
});

test("整机:App 发不出占位时旧 success 可能保留，但本轮不读事实、不合并", async () => {
  const gh = await fakeGitHub({ mergeReady: true, previousSuccess: true, appStartFails: true });
  try {
    const { code, out } = await runMain(gh.url);
    assert.notEqual(code, 0, out);
    assert.equal(gh.checks.size, 1);
    assert.equal([...gh.checks.values()][0].conclusion, "success");
    assert.ok(!gh.log.some((r) => r.url.startsWith("/repos/o/r/pulls/")), "占位失败的 head 不读事实或合并");
  } finally {
    gh.server.close();
  }
});


function runDispatchBridge(apiUrl, builderFamily='openai', extraEnv={}) {
  return new Promise(resolve=>{
    const child=spawn(process.execPath,[new URL('../bin/_review_dispatch.mjs',import.meta.url).pathname], {
      timeout:5000,env:{PATH:process.env.PATH,GITHUB_API_URL:apiUrl,GH_TOKEN:'read_token',...extraEnv},
    });
    let out='',err='';child.stdout.on('data',chunk=>out+=chunk);child.stderr.on('data',chunk=>err+=chunk);
    child.on('close',code=>resolve({code,out,err}));
    child.stdin.end(JSON.stringify({repository:'o/r',number:10,builder_family:builderFamily}));
  });
}
function dispatchReview(family, verdict='PASS', id=1, completeness='complete') {
  return {id,user:{login:policy.reviewer_bot,type:'Bot'},state:'COMMENTED',commit_id:HEAD,
    submitted_at:'2026-11-10T01:00:00Z',body:'```json\n'+JSON.stringify({family,verdict,completeness,
      model:family+'-test',head_sha:HEAD})+'\n```'};
}
const dispatchPolicy = () => ({...policy,review_dispatch:
  JSON.parse(readFileSync(new URL('../.aiwork/policy.json',import.meta.url),'utf8')).review_dispatch});

test('派发桥真跑共享 GitHub 读取、默认分支策略、分页和关卡评审状态', async()=>{
  const current=dispatchPolicy();current.review_dispatch.minimum_families=2;
  current.review_dispatch.targets.documentation=2;
  const gh=await fakeGitHub({dispatchPolicy:current,defaultBranch:'develop',files:['web/a.ts','web/b.ts'],paginateFiles:true,
    reviews:[dispatchReview('deepseek','PASS',1),dispatchReview('deepseek','PASS',2),
      dispatchReview('moonshot','BLOCK',3),
      dispatchReview('anthropic','PASS',5),dispatchReview('xiaomi','PASS',6,'partial')]});
  try {
    const result=await runDispatchBridge(gh.url);assert.equal(result.code,0,result.err);
    const state=JSON.parse(result.out);
    assert.equal(state.minimum_met,false,'同家族两条不填两家底线');
    assert.deepEqual(state.pass_families,['deepseek']);
    assert.deepEqual(state.reviewed_families,['deepseek','moonshot']);
    assert.deepEqual(state.excluded.sort(),['anthropic','openai']);
    assert.equal(state.target_met,true);
    assert.ok(gh.log.some(r=>r.url.endsWith('ref=develop')));
    assert.ok(gh.log.some(r=>r.url.includes('page=2')));
    assert.ok(gh.log.every(r=>r.auth==='Bearer read_token' && r.userAgent==='aiwork-gate'));
    assert.ok(gh.log.every(r=>r.method==='GET' || r.url==='/graphql'),'桥不写检查或合并');
  } finally {gh.server.close();}
});
test('派发桥的作者排除跟随关卡，已知作者与 UNKNOWN 都从关卡返回', async()=>{
  for (const actorLogin of ['SunJ1ayuBoT', 'unregistered-build']) {
    const current=dispatchPolicy();current.builders={...current.builders,'other-builder':'deepseek'};
    const gh=await fakeGitHub({dispatchPolicy:current,actorLogin,
      reviews:[dispatchReview('deepseek','PASS',1),dispatchReview('openai','PASS',2),dispatchReview('anthropic','PASS',3)]});
    try {
      const result=await runDispatchBridge(gh.url);assert.equal(result.code,0,result.err);
      const state=JSON.parse(result.out);
      assert.deepEqual(state.pass_families,actorLogin==='SunJ1ayuBoT'?['deepseek','openai']:['openai']);
      assert.ok(state.excluded.includes('anthropic'));assert.ok(state.excluded.includes('openai'));
      assert.equal(state.excluded.includes('deepseek'),actorLogin!=='SunJ1ayuBoT');
      assert.equal(state.minimum_met,true);
    } finally {gh.server.close();}
  }
});
test('执行方已有 PASS 时派发记录保留真关卡结论，只跳过执行方派腿',async()=>{
  const current=dispatchPolicy();
  const gh=await fakeGitHub({dispatchPolicy:current,actorLogin:'SunJ1ayuBoT',
    reviews:[dispatchReview('openai','PASS',1)]});
  try {
    const facts=await collect(githubClient({GITHUB_API_URL:gh.url}).reader('read_token'),'o/r',10,current);
    const official=decide(facts,current);
    const result=await runDispatchBridge(gh.url);assert.equal(result.code,0,result.err);
    const state=JSON.parse(result.out);
    assert.deepEqual(state.gate,{title:official.title,conclusion:official.conclusion,summary:official.summary});
    assert.deepEqual(state.pass_families,official.review_state.pass_families);
    assert.equal(state.minimum_met,official.review_state.minimum_met);
    assert.ok(state.excluded.includes('openai'));
    for (const field of ['reviewed_families','target_met','missing_target','next_step']) {
      assert.deepEqual(state[field],official.review_state[field],field);
    }
  } finally {gh.server.close();}
});
test('派发桥:最后一家交卷后关卡按本轮评审直接合并，PR 已关闭仍返回这一轮成功状态',async()=>{
  const current=dispatchPolicy();
  const gh=await fakeGitHub({dispatchPolicy:current,closedPr:true,files:['web/a.ts'],
    reviews:[dispatchReview('openai','PASS',1),dispatchReview('moonshot','PASS',2)]});
  try {
    const result=await runDispatchBridge(gh.url);assert.equal(result.code,0,result.err);
    const state=JSON.parse(result.out);
    assert.equal(state.minimum_met,true);
    assert.equal(state.target_met,true);
    assert.equal(state.missing_target,0);
    assert.equal(state.gate.conclusion,'success');
    assert.ok(gh.log.some(r=>r.url.includes(`check-runs?check_name=${policy.check_name}`)),'用关卡自己的检查确认合并者身份');
  } finally {gh.server.close();}
});

test('派发桥:改过目标分支的直接合并 PR 仍按这一轮成功收尾',async()=>{
  const current=dispatchPolicy();
  const gh=await fakeGitHub({dispatchPolicy:current,closedPr:true,files:['web/a.ts'],
    events:[{id:2,event:'base_ref_changed',created_at:'2026-09-01T00:00:00Z'}],
    reviews:[dispatchReview('openai','PASS',1),dispatchReview('moonshot','PASS',2)]});
  try {
    const result=await runDispatchBridge(gh.url);assert.equal(result.code,0,result.err);
    const state=JSON.parse(result.out);
    assert.equal(state.finalized,true);
    assert.equal(state.gate.conclusion,'success','合并后重算用的是这个 head 上 CI 的真实创建时间');
    assert.equal(state.target_met,true);
  } finally {gh.server.close();}
});

test('派发桥:按合并标签由关卡合并的 PR 也按这一轮成功收尾',async()=>{
  const current=dispatchPolicy();
  const gh=await fakeGitHub({dispatchPolicy:current,closedPr:true,mergeReady:true,files:['desktop/main.js'],
    reviews:[dispatchReview('moonshot','PASS',1),
      {id:2,user:{login:policy.owner,type:'User'},state:'APPROVED',commit_id:HEAD,
        submitted_at:'2026-09-29T09:30:00Z',body:''}]});
  try {
    const result=await runDispatchBridge(gh.url);assert.equal(result.code,0,result.err);
    const state=JSON.parse(result.out);
    assert.equal(state.finalized,true,'是否预期收尾只看这一条，不按合并路径另加条件');
    assert.equal(state.minimum_met,false,'high 路径只有一家 PASS');
    assert.equal(state.target_met,false);
  } finally {gh.server.close();}
});

test('派发桥:PR 被别的原因关闭，照旧报失败',async()=>{
  for (const options of [
    {name:'直接关掉没合并',closedPr:true,merged:false},
    {name:'不是关卡合并的',closedPr:true,mergedBy:'someone-else'},
    {name:'关卡没有成功检查',closedPr:true,gateCheckRuns:[]},
    {name:'关卡检查没成功',closedPr:true,gateCheckConclusion:'failure'},
  ]) {
    const gh=await fakeGitHub({dispatchPolicy:dispatchPolicy(),files:['web/a.ts'],
      reviews:[dispatchReview('openai','PASS',1),dispatchReview('moonshot','PASS',2)],...options});
    try {
      const result=await runDispatchBridge(gh.url);
      assert.notEqual(result.code,0,options.name);assert.equal(result.out,'',options.name);
    } finally {gh.server.close();}
  }
});

test('派发桥不吞 GraphQL 错误',async()=>{
  const gh=await fakeGitHub({dispatchPolicy:dispatchPolicy(),graphqlErrors:true});
  try {
    const result=await runDispatchBridge(gh.url);assert.notEqual(result.code,0);assert.match(result.err,/GraphQL/);
    assert.equal(result.out,'');
  } finally {gh.server.close();}
});

test('派发桥实际使用关卡共用的请求超时',async()=>{
  const gh=await fakeGitHub({dispatchPolicy:dispatchPolicy(),pauseAt:'/repos/o/r/pulls/10',onPause:()=>{}});
  try {
    const result=await runDispatchBridge(gh.url,'openai',{AIWORK_GATE_TIMEOUT_MS:'50'});
    assert.notEqual(result.code,0);assert.match(result.err,/Timeout|Abort/i);assert.equal(result.out,'');
  } finally {gh.server.closeAllConnections();gh.server.close();}
});

// Webhook 字段契约来自 GitHub pull_request/labeled 载荷；REST 标签历史样本见 #149。
const labelPayload = (sha = HEAD) => ({ action: 'labeled', repository: { full_name: 'o/r' },
  sender: { login: policy.owner }, label: { name: policy.merge_label },
  pull_request: { number: 10, updated_at: '2026-09-29T10:00:00Z',
    base: { repo: { full_name: 'o/r' } }, head: { sha } } });

test('整机:只保存贴标签载荷里的提交；到运行时已推新提交不能借旧标签合并', async () => {
  for (const sha of ['c'.repeat(40), HEAD]) {
    const gh = await fakeGitHub({ mergeReady: true, bindingRecords: [] });
    try {
      const { code, out } = await runMain(gh.url, {}, MAIN, labelPayload(sha));
      assert.equal(code, 0, out);
      assert.equal(gh.log.filter(r => r.url.endsWith('/merge')).length, sha === HEAD ? 1 : 0);
      const saved = gh.log.find(r => r.method === 'POST' && r.body?.name === 'aiwork-merge-request');
      assert.ok(saved, '必须自动保存原始事件');
      assert.equal(saved.auth, 'Bearer app-check-token');
      assert.equal(saved.body.head_sha, sha);
      if (sha !== HEAD) assert.match(out, /合并标签不对应当前提交.*摘掉重贴/);
    } finally { gh.server.close(); }
  }
});

test('整机:记录未保存或贴标签运行被顶掉，不能在后续门铃中补绑当前提交', async () => {
  for (const extra of [{}, { GITHUB_EVENT_NAME: 'schedule' }]) {
    const gh = await fakeGitHub({ mergeReady: true, bindingRecords: [] });
    try {
      const { code, out } = await runMain(gh.url, extra);
      assert.equal(code, 0, out);
      assert.equal(gh.log.filter(r => r.body?.name === 'aiwork-merge-request').length, 0);
      assert.equal(gh.log.filter(r => r.url.endsWith('/merge')).length, 0);
      assert.match(out, /合并标签不对应当前提交.*摘掉重贴/);
    } finally { gh.server.close(); }
  }
});

test('整机:绑定保存失败安全拒绝，仍完成 PR 重算', async () => {
  const gh = await fakeGitHub({ mergeReady: true, bindingRecords: [], bindingFails: true });
  try {
    const { code, out } = await runMain(gh.url, {}, MAIN, labelPayload());
    assert.equal(code, 0, out);
    assert.match(out, /记录保存失败/);
    assert.match(out, /合并标签不对应当前提交.*摘掉重贴/);
    assert.equal(gh.log.filter(r => r.url.endsWith('/merge')).length, 0);
  } finally { gh.server.close(); }
});

test('整机:从 GitHub 读持久绑定；同提交摘掉重贴及同秒操作沿用可信授权', async () => {
  const opts = { mergeReady: true, bindingRecords: [] };
  const gh = await fakeGitHub(opts);
  const event = (id, type, at) => ({ id, event: type, created_at: at,
    label: { name: policy.merge_label }, actor: { login: policy.owner } });
  try {
    assert.equal((await runMain(gh.url, {}, MAIN, labelPayload())).code, 0);
    let start = gh.log.length;
    let result = await runMain(gh.url, { GITHUB_EVENT_NAME: 'schedule' });
    assert.equal(result.code, 0, result.out);
    assert.equal(gh.log.slice(start).filter(r => r.url.endsWith('/merge')).length, 1, '下一运行读服务器记录');
    opts.events = [event(1, 'labeled', '2026-09-29T10:00:00Z'),
      event(2, 'unlabeled', '2026-09-29T10:01:00Z'), event(3, 'labeled', '2026-09-29T10:02:00Z')];
    start = gh.log.length;
    result = await runMain(gh.url, { GITHUB_EVENT_NAME: 'schedule' });
    assert.equal(result.code, 0, result.out);
    assert.equal(gh.log.slice(start).filter(r => r.url.endsWith('/merge')).length, 1, '同提交可沿用旧授权');
    const payload = labelPayload(); payload.pull_request.updated_at = '2026-09-29T10:02:00Z';
    start = gh.log.length;
    result = await runMain(gh.url, {}, MAIN, payload);
    assert.equal(result.code, 0, result.out);
    assert.equal(gh.log.slice(start).filter(r => r.url.endsWith('/merge')).length, 1, '重贴并保存后恢复');
    opts.events.push(event(4, 'unlabeled', '2026-09-29T10:02:00Z'), event(5, 'labeled', '2026-09-29T10:02:00Z'));
    start = gh.log.length;
    result = await runMain(gh.url, {}, MAIN, payload);
    assert.equal(result.code, 0, result.out);
    assert.equal(gh.log.slice(start).filter(r => r.url.endsWith('/merge')).length, 1, '同提交的授权不依赖事件时间');
  } finally { gh.server.close(); }
});

test('整机:其他事件、仓库、申请人、标签或坏载荷不能保存绑定', async () => {
  const variants = [
    p => { p.sender.login = Object.keys(policy.builders)[0]; },
    p => { p.repository.full_name = 'other/repo'; },
    p => { p.pull_request.base.repo.full_name = 'other/repo'; },
    p => { p.label.name = 'other'; },
    p => { p.pull_request.number = null; },
    p => { p.pull_request.head.sha = 'bad'; },
    p => { p.action = 'synchronize'; },
  ];
  for (const change of variants) {
    const gh = await fakeGitHub({ mergeReady: true, bindingRecords: [] });
    try {
      const payload = labelPayload(); change(payload);
      const { code, out } = await runMain(gh.url, {}, MAIN, payload);
      assert.equal(code, 0, out);
      assert.equal(gh.log.filter(r => r.body?.name === 'aiwork-merge-request').length, 0);
      assert.equal(gh.log.filter(r => r.url.endsWith('/merge')).length, 0);
    } finally { gh.server.close(); }
  }
});

test('整机：仅其他条件齐全时同步，先存意向，写权限只用于 update-branch，head 被锁定',async()=>{
 for(const opts of [{sync:true,mergeReady:true,staleBase:'c'.repeat(40)},{sync:true,mergeReady:true},{sync:true,mergeReady:false},{sync:true,mergeReady:true,conflict:true},
  {sync:true,mergeReady:true,syncRecordFails:true},{sync:true,mergeReady:true,updateFails:true}]){
  const gh=await fakeGitHub(opts);
  try {
   const {code,out}=await runMain(gh.url);assert.equal(code,0,out);
   const updates=gh.log.filter(r=>r.url.endsWith('/update-branch'));
   const expected=opts.mergeReady && !opts.conflict && !opts.syncRecordFails;
   assert.equal(updates.length,expected?1:0,out);
   assert.equal(gh.log.filter(r=>r.url.endsWith('/merge')).length,0,out);
   if(expected){
    assert.deepEqual(updates[0].body,{expected_head_sha:HEAD});
    assert.equal(updates[0].auth,'Bearer app-merge-token');
    const record=gh.log.find(r=>r.method==='POST' && r.body?.name==='aiwork-main-sync');
    assert.ok(record && gh.log.indexOf(record)<gh.log.indexOf(updates[0]));
    assert.equal(record.auth,'Bearer app-check-token');
    const intent=JSON.parse(record.body.output.text);
    assert.equal(intent.head,HEAD);assert.equal(intent.base,SYNC_BASE);assert.equal(intent.actor,'aiwork-gate[bot]');
   }
   const final=checkWrites(gh.log).filter(r=>r.method==='PATCH').at(-1);
   if(opts.conflict)assert.match(final.body.output.summary,/冲突/);
   if(opts.updateFails || opts.syncRecordFails){
    // 同步写失败只影响这一单：共享 head 的放行判定不变，摘要写明未同步、本轮不合并。
    assert.notEqual(final.body.conclusion,'failure',JSON.stringify(final.body.output));
    assert.equal(final.body.status,'in_progress',JSON.stringify(final.body.output));
    assert.match(final.body.output.title,/自动同步未完成/);
    assert.match(final.body.output.summary,/PR #10 自动同步未完成.*不合并/);
   }
   if(expected && !opts.updateFails)assert.equal(final.body.status,'in_progress');
  }finally{gh.server.close();}
 }
});

test('瞬时合并状态在同次运行重读：null 转 true 才同步，转 false 才报冲突',async()=>{
 for(const states of [[null,true],[null,false]]){
  const gh=await fakeGitHub({sync:true,mergeReady:true,mergeableStates:states});
  try{
   const {code,out}=await runMain(gh.url);assert.equal(code,0,out);
   const summaries=checkWrites(gh.log).filter(r=>r.method==='PATCH').map(r=>r.body.output);
   assert.ok(summaries.every(o=>!o.title.includes('G8')),JSON.stringify(summaries));
   assert.ok(summaries.some(o=>o.title.includes('重读')),JSON.stringify(summaries));
   const updates=gh.log.filter(r=>r.url.endsWith('/update-branch'));
   assert.equal(updates.length,states.at(-1)?1:0,out);
   if(!states.at(-1))assert.match(summaries.at(-1).summary,/冲突/);
  }finally{gh.server.close();}
 }
});

test('同步或合并写入时 main 刚推进，当次重读后用新 main 同步，不把竞争写成失败',async()=>{
 for(const opts of [{sync:true,mergeReady:true,moveOnUpdate:true},{mergeReady:true,moveOnMerge:true}]){
  const gh=await fakeGitHub(opts);
  try{
   const {code,out}=await runMain(gh.url);assert.equal(code,0,out);
   const patches=checkWrites(gh.log).filter(r=>r.method==='PATCH');
   assert.ok(patches.every(r=>r.body.conclusion!=='failure'),out);
   assert.ok(patches.some(r=>r.body.output.title.includes('重读')),out);
   const intents=gh.log.filter(r=>r.method==='POST' && r.body?.name==='aiwork-main-sync');
   assert.equal(JSON.parse(intents.at(-1).body.output.text).base,'d'.repeat(40));
   assert.equal(patches.at(-1).body.status,'in_progress');
  }finally{gh.server.close();}
 }
});

test('同 head 前一个 PR 合并推进 main 后，后一个「要跟上 main」在当次运行重读并同步',async()=>{
 const gh=await fakeGitHub({twoPrs:true,mergeReady:true,behindAfterMerge:true});
 try{
  const {code,out}=await runMain(gh.url);assert.equal(code,0,out);
  const patches=checkWrites(gh.log).filter(r=>r.method==='PATCH'&&r.body?.output);
  assert.ok(patches.every(r=>r.body.conclusion!=='failure'),out);
  assert.ok(patches.some(r=>r.body.output.title.includes('重读')),out);
  assert.equal(gh.log.filter(r=>r.url==='/repos/o/r/pulls/10/merge').length,1);
  const updates=gh.log.filter(r=>r.url.endsWith('/pulls/11/update-branch'));
  assert.equal(updates.length,1,out);
  assert.deepEqual(updates[0].body,{expected_head_sha:HEAD});
  const intents=gh.log.filter(r=>r.method==='POST'&&r.body?.name==='aiwork-main-sync');
  assert.equal(intents.length,1);
  assert.equal(JSON.parse(intents[0].body.output.text).base,'d'.repeat(40),'按合并后的新 main 同步');
  assert.equal(patches.at(-1).body.status,'in_progress');
  // 同一次运行内重读复用同一个占位检查，不再为同一个 head 新建第二条。
  const starts=gh.log.filter(r=>r.method==='POST'&&r.body?.name===policy.check_name);
  assert.equal(starts.length,1,out);
 }finally{gh.server.close();}
});

test('P1-2 合并被拒且分支落后、关卡不会自动同步时，写明真实原因且不重读重试',async()=>{
 for(const variant of [{defaultBranch:'develop'},{forkAfterMerge:true}]){
  const gh=await fakeGitHub({twoPrs:true,mergeReady:true,...variant});
  try{
   const {code,out}=await runMain(gh.url);assert.equal(code,0,out);
   const patches=checkWrites(gh.log).filter(r=>r.method==='PATCH'&&r.body?.output);
   assert.equal(patches.length,2,out);
   const final=patches.at(-1).body;
   assert.equal(final.conclusion,'success',out);
   assert.match(final.output.summary,/PR #11 合并被拒/);
   assert.match(final.output.summary,/分支落后于 main，但关卡不会自动同步/);
   assert.match(final.output.summary,JSON.stringify(variant).includes('forkAfterMerge')?/叉库/:/不是默认分支/);
   assert.match(final.output.summary,/405|Head branch is not up to date/);
   assert.equal(gh.log.filter(r=>r.url.endsWith('/pulls/11/update-branch')).length,0,out);
   assert.equal(gh.log.filter(r=>r.url==='/repos/o/r/pulls/11/merge').length,1,'只尝试合并一次');
   assert.equal(gh.log.filter(r=>r.method==='POST'&&r.body?.name===policy.check_name).length,1,'不新建占位重试');
  }finally{gh.server.close();}
 }
});

test('P1-2 同步写入被拒且 PR 仍落后时，保留原始拒绝原因，不改成「重读后自动同步」',async()=>{
 const gh=await fakeGitHub({sync:true,mergeReady:true,updateFails:true,behindAlways:true});
 try{
  const {code,out}=await runMain(gh.url);assert.equal(code,0,out);
  const patches=checkWrites(gh.log).filter(r=>r.method==='PATCH'&&r.body?.output);
  assert.equal(patches.length,2,out);
  const final=patches.at(-1).body;
  assert.equal(final.status,'in_progress');
  assert.match(final.output.title,/自动同步未完成/);
  assert.match(final.output.summary,/PR #10 自动同步未完成，这一轮不合并它/);
  assert.match(final.output.summary,/422|branch moved/);
  assert.doesNotMatch(final.output.summary,/重读后自动同步/);
  assert.equal(gh.log.filter(r=>r.url.endsWith('/update-branch')).length,1,out);
  assert.equal(gh.log.filter(r=>r.url.endsWith('/merge')).length,0);
 }finally{gh.server.close();}
});

test('自动同步只失败一个 PR 时，不改共享放行结论，也不挡同 head 其他 PR 的同步',async()=>{
 const gh=await fakeGitHub({twoPrs:true,mergeReady:true,sync:true,updateFailsNumber:10});
 try{
  const {code,out}=await runMain(gh.url);assert.equal(code,0,out);
  const patches=checkWrites(gh.log).filter(r=>r.method==='PATCH'&&r.body?.output);
  assert.ok(patches.every(r=>r.body.conclusion!=='failure'),out);
  const final=patches.at(-1).body;
  assert.equal(final.status,'in_progress');
  assert.match(final.output.title,/自动同步未完成/);
  assert.match(final.output.summary,/PR #10 自动同步未完成，这一轮不合并它/);
  const updates=gh.log.filter(r=>r.url.endsWith('/update-branch'));
  assert.deepEqual(updates.map(r=>r.url).sort(),['/repos/o/r/pulls/10/update-branch','/repos/o/r/pulls/11/update-branch'].sort(),out);
  assert.equal(gh.log.filter(r=>r.url.endsWith('/merge')).length,0,'同步未完成时不能先合并任何一单');
 }finally{gh.server.close();}
});

test('重读等待按指数退避且有上限；同一 head 的占位检查跨重读复用',async()=>{
 assert.deepEqual([0,1,4,5,10].map(retryDelay),[1000,2000,16000,30000,30000]);
 const gh=await fakeGitHub({mergeReady:true,sync:true,mergeableStates:[null,true]});
 try{
  const {code,out}=await runMain(gh.url);assert.equal(code,0,out);
  const starts=gh.log.filter(r=>r.method==='POST'&&r.body?.name===policy.check_name);
  assert.equal(starts.length,1,'重读不能为同一个 head 新建第二条占位');
  const patches=gh.log.filter(r=>r.method==='PATCH'&&r.url===`/repos/o/r/check-runs/${starts[0].checkId}`);
  assert.ok(patches.length>=2,'至少一次等待状态、一次最终结论');
 }finally{gh.server.close();}
});

test('独立保存任务只写通知授权；排队重算不重新保存且能读到授权',async()=>{
 const gh=await fakeGitHub({mergeReady:true,bindingRecords:[]});
 try {
  const payload=labelPayload();payload.pull_request.updated_at='2026-09-29T10:00:01Z';
  const saved=await runMain(gh.url,{AIWORK_GATE_PHASE:'binding'},MAIN,payload);
  assert.equal(saved.code,0,saved.out);
  assert.equal(gh.log.filter(r=>r.body?.name==='aiwork-merge-request').length,1);
  assert.ok(!gh.log.some(r=>r.url.includes('/pulls?') || r.url.endsWith('/merge')),'保存不读 PR 现状、不重算、不合并');
  const start=gh.log.length;
  const result=await runMain(gh.url,{AIWORK_GATE_PHASE:'recompute'},MAIN,payload);
  assert.equal(result.code,0,result.out);
  assert.equal(gh.log.slice(start).filter(r=>r.body?.name==='aiwork-merge-request').length,0);
  assert.equal(gh.log.slice(start).filter(r=>r.url.endsWith('/merge')).length,1,'保存独立于被取消的重算，之后的门铃可消费');
 } finally {gh.server.close();}
});

test('真实接线：合并被规则拒绝，原因写回检查摘要而非只留日志',async()=>{
 const gh=await fakeGitHub({mergeReady:true,mergeFails:true});
 try {
  const {code,out}=await runMain(gh.url);assert.equal(code,0,out);
  const final=checkWrites(gh.log).filter(r=>r.method==='PATCH').at(-1);
  assert.equal(final.body.conclusion,'success');
  assert.match(final.body.output.summary,/合并被拒.*405.*Required status check/);
 }finally{gh.server.close();}
});

// aiwork 放行关卡入口 main.mjs 的整机冒烟:起一个假的 GitHub API,真跑 main.mjs 子进程。
// 钉住接线本身:JWT 用 App ID 签、公钥验得过;换令牌只要 checks:write;读数据用 GITHUB_TOKEN;
// 先发 in_progress 占位,再把同一条检查 PATCH 成结论;读 PR 出错时占位被改成 failure;
// 保险丝检查只用 GITHUB_TOKEN 发,App 私钥坏了也拨得动;
// 合并用另换的一张令牌(只在要合并时才换),带上判过的 head。
// 跑法:node --test tests/test_aiwork_gate_main.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { spawn } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FUSE_CHECK_NAME } from "../gate/run.mjs";

const policy = JSON.parse(readFileSync(new URL("./fixtures/gate-logic-policy.json", import.meta.url), "utf8"));
const MAIN = new URL("../gate/main.mjs", import.meta.url).pathname;
const HEAD = "a".repeat(40);
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const PEM = privateKey.export({ type: "pkcs8", format: "pem" });

function fakeGitHub(opts = {}) {
  const log = [];
  const checks = new Map();
  const statuses = new Map();
  let nextCheck = 4242;
  const server = createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const auth = req.headers.authorization ?? "";
      const record = { method: req.method, url: req.url, auth, body: body ? JSON.parse(body) : null };
      log.push(record);
      const send = (code, data) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(data)); };
      const u = req.url;
      if (u === "/repos/o/r/installation") return send(200, { id: 777 });
      // 按要的权限发不同的令牌,好分清哪个请求用的是哪张
      if (u === "/app/installations/777/access_tokens") return send(201, { token: JSON.parse(body).permissions.checks ? "app-check-token" : "app-merge-token" });
      if (u === "/repos/o/r/pulls/10/merge" && req.method === "PUT") return send(200, { merged: true });
      if (u === "/repos/o/r/check-runs" && req.method === "POST") {
        if (opts.hang && auth === "Bearer app-check-token") return; // 一直不回
        const id = nextCheck++;
        const check = { ...record.body, id, auth };
        checks.set(id, check);
        record.checkId = id;
        // GitHub 对同一 suite/同名检查超过 1000 条时自动淘汰旧项，不拒绝创建。
        const same = [...checks.values()].filter((c) => c.auth === auth && c.head_sha === check.head_sha && c.name === check.name);
        if (same.length > 1000) checks.delete(same[0].id);
        return send(201, { id });
      }
      if (u.startsWith("/repos/o/r/check-runs/") && req.method === "PATCH") {
        const id = Number(u.split("/").at(-1));
        if (!checks.has(id)) return send(404, { message: "missing check" });
        if (checks.get(id).auth !== auth) return send(403, { message: "wrong check owner" });
        if (opts.appFinishFails && auth === "Bearer app-check-token") return send(502, { message: "App write failed" });
        Object.assign(checks.get(id), record.body);
        return send(200, { id });
      }
      if (u.startsWith("/repos/o/r/statuses/") && req.method === "POST") {
        const key = u + ":" + record.body.context;
        const count = statuses.get(key) ?? 0;
        if (count >= 1000) return send(422, { message: "1000 statuses per sha and context" });
        statuses.set(key, count + 1);
        return send(201, { id: count + 1 });
      }
      if (opts.prFails && u === "/repos/o/r/pulls/10") return send(502, { message: "bad gateway" });
      // mergeReady:有合格 PASS、业主贴了合并标签 → 放行并合并
      const labels = opts.mergeReady ? [{ name: policy.merge_label }] : [];
      const pr10 = { number: 10, state: "open", changed_files: 1, labels, head: { sha: HEAD, ref: "claude/x", repo: { full_name: "o/r" } }, base: { ref: "main" } };
      if (u === "/repos/o/r/pulls?state=open&per_page=100") return send(200, [pr10]);
      if (u === "/repos/o/r/pulls/10") return send(200, pr10);
      if (u.startsWith("/repos/o/r/pulls/10/files")) return send(200, [{ filename: "web/a.ts" }]);
      const pass = "```json\n" + JSON.stringify({ verdict: "PASS", head_sha: HEAD, model: "gpt-x", family: "openai", completeness: "complete", files_read: ["web/a.ts"] }) + "\n```";
      const reviews = opts.mergeReady ? [{ id: 1, user: { login: policy.reviewer_bot, type: "Bot" }, state: "COMMENTED", commit_id: HEAD, submitted_at: "2026-09-29T09:00:00Z", body: pass }] : [];
      if (u.startsWith("/repos/o/r/pulls/10/reviews")) return send(200, reviews);
      if (u.startsWith("/repos/o/r/actions/runs")) return send(200, { workflow_runs: [{ id: 1, path: ".github/workflows/ci.yml", head_sha: HEAD, status: "completed", conclusion: "success", pull_requests: [{ number: 10 }] }] });
      if (u.startsWith("/repos/o/r/activity")) return send(200, [{ id: 1, timestamp: "t", activity_type: "push", after: HEAD, actor: { login: "SunJ1ayuBoT" } }]);
      const events = opts.mergeReady ? [{ id: 1, event: "labeled", label: { name: policy.merge_label }, actor: { login: policy.owner }, created_at: "2026-09-29T10:00:00Z" }] : [];
      if (u.startsWith("/repos/o/r/issues/10/events")) return send(200, events);
      const nodes = reviews.map((r) => ({ databaseId: r.id, submittedAt: r.submitted_at, lastEditedAt: null }));
      if (u === "/graphql" && req.method === "POST") return send(200, { data: { repository: { pullRequest: { reviews: { totalCount: nodes.length, pageInfo: { hasNextPage: false }, nodes } } } } });
      send(404, { message: `fake: no route ${u}` });
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve({ server, log, checks, statuses, url: `http://127.0.0.1:${server.address().port}` })));
}

function runMain(apiUrl, extraEnv = {}, main = MAIN, event = { pull_request: { number: 10, head: { sha: HEAD } } }) {
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
    let out = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (out += d));
    child.on("close", (code) => {
      rmSync(dir, { recursive: true, force: true });
      resolve({ code, out });
    });
  });
}

test("整机:同一 head 重算超过 status 和同名检查上限后仍能判定并合并", async () => {
  const opts = {};
  const gh = await fakeGitHub(opts);
  try {
    for (let round = 0; round < 1001; round++) {
      const { code, out } = await runMain(gh.url);
      assert.equal(code, 0, `round=${round + 1}: ${out}`);
    }
    opts.mergeReady = true;
    const { code, out } = await runMain(gh.url);
    assert.equal(code, 0, out);
    assert.equal(gh.log.filter((r) => r.url === "/repos/o/r/pulls/10/merge").length, 1);
    assert.equal(gh.statuses.size, 0, "不再向只能追加的 status 写入");
    const names = new Set([...gh.checks.values()].map((c) => c.name));
    assert.equal(names.size, 2, "App 结论和独立保险丝都用检查");
    for (const name of names) {
      const checks = [...gh.checks.values()].filter((c) => c.name === name);
      assert.equal(checks.length, 1000, "自动淘汰旧检查后仍能写入新结论");
      assert.equal(checks.at(-1).conclusion, "success");
    }
  } finally {
    gh.server.close();
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

test("整机:定时事件没有 PR/head，仍用既有凭证读取开放 PR、拨保险丝、重写检查", async () => {
  const gh = await fakeGitHub();
  try {
    const { code, out } = await runMain(gh.url, { GITHUB_EVENT_NAME: "schedule" }, MAIN, { schedule: "scheduled" });
    assert.equal(code, 0, out);
    assert.ok(gh.log.some((r) => r.url === "/repos/o/r/pulls/10" && r.auth === "Bearer read_token"));
    assert.deepEqual(fuseStates(gh.log), ["in_progress", "failure"]);
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
    assert.equal(gh.log.filter((r) => appWrites([r]).length || r.url.startsWith("/repos/o/r/pulls/")).length, 0);
  } finally {
    gh.server.close();
  }
});

const checkWrites = (log) => log.filter((r) => r.url.startsWith("/repos/o/r/check-runs") && ["POST", "PATCH"].includes(r.method));
const appWrites = (log) => checkWrites(log).filter((r) => r.auth === "Bearer app-check-token");
const fuseWrites = (log) => checkWrites(log).filter((r) => r.auth === "Bearer read_token");
const fuseStates = (log) => fuseWrites(log).map((r) => r.body.conclusion ?? r.body.status);

test("整机:保险丝只用 GITHUB_TOKEN 发,先 pending、App 写回之后跟结论走", async () => {
  const gh = await fakeGitHub();
  try {
    const { code, out } = await runMain(gh.url, { GITHUB_SERVER_URL: "https://github.com", GITHUB_RUN_ID: "123" });
    assert.equal(code, 0, out);
    const fw = fuseWrites(gh.log);
    assert.deepEqual(fuseStates(gh.log), ["in_progress", "failure"]);
    assert.equal(fw[0].method, "POST");
    assert.equal(fw[0].body.head_sha, HEAD);
    assert.equal(fw[0].body.name, FUSE_CHECK_NAME);
    assert.equal(fw[1].method, "PATCH");
    assert.equal(fw[1].url, `/repos/o/r/check-runs/${fw[0].checkId}`);
    assert.ok(fw.every((r) => r.auth === "Bearer read_token"), "保险丝不靠 App 令牌");
    assert.ok(fw.every((r) => r.body.output.title && r.body.output.summary));
    assert.equal(fw[0].body.details_url, "https://github.com/o/r/actions/runs/123");
    assert.ok(gh.log.indexOf(fw[0]) < gh.log.findIndex((r) => r.url === "/repos/o/r/installation"), "先拨保险丝,再去换 App 令牌");
    assert.ok(gh.log.indexOf(fw[1]) > gh.log.indexOf(appWrites(gh.log).at(-1)), "App 写回之后才跟结论");
  } finally {
    gh.server.close();
  }
});

test("整机:没有私钥 → App 检查一条都发不出,但保险丝用 GITHUB_TOKEN 拨到 failure,旧 success 挡不住", async () => {
  const gh = await fakeGitHub();
  try {
    const { code } = await runMain(gh.url, { AIWORK_GATE_PRIVATE_KEY: "" });
    assert.notEqual(code, 0);
    assert.deepEqual(fuseStates(gh.log), ["in_progress", "failure"]);
    assert.ok(fuseWrites(gh.log).every((r) => r.auth === "Bearer read_token"));
  } finally {
    gh.server.close();
  }
});

test("整机:App 结论写不回时独立保险丝改为 failure，不能合并", async () => {
  const gh = await fakeGitHub({ mergeReady: true, appFinishFails: true });
  try {
    const { code, out } = await runMain(gh.url);
    assert.notEqual(code, 0, out);
    assert.deepEqual(fuseStates(gh.log), ["in_progress", "failure"]);
    assert.equal([...gh.checks.values()].find((c) => c.name === FUSE_CHECK_NAME).conclusion, "failure");
    assert.equal(gh.log.filter((r) => r.url.endsWith("/merge")).length, 0);
  } finally {
    gh.server.close();
  }
});

// aiwork-review[bot] 评审(PR #10 review 5354768826,@ ae8c58f)第 4 个阻断点:main 上的策略文件不是合法 JSON 时,
// 进程在进 gate() 之前就崩了,保险丝没被拨到 failure。
test("整机:策略文件不是合法 JSON → 不发 App 检查、不读 PR 的数据,但保险丝照样拨到 failure", async () => {
  const gh = await fakeGitHub();
  const root = mkdtempSync(join(tmpdir(), "gate-policy-"));
  const policyPath = join(root, "policy.json");
  try {
    writeFileSync(policyPath, '{ "check_name": "aiwork-gate-shadow", ');
    const { code, out } = await runMain(gh.url, { AIWORK_POLICY_PATH: policyPath });
    assert.notEqual(code, 0);
    assert.match(out, /policy\.json/);
    assert.deepEqual(fuseStates(gh.log), ["failure"]);
    assert.equal(gh.log.filter((r) => appWrites([r]).length || r.url.startsWith("/repos/o/r/pulls/")).length, 0);
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
    for (const name of ["main.mjs", "run.mjs", "collect.mjs", "decide.mjs"]) {
      cpSync(new URL(`../gate/${name}`, import.meta.url), join(gateDir, name));
    }
    mkdirSync(join(root, ".aiwork"));
    writeFileSync(join(root, ".aiwork", "policy.json"), JSON.stringify({ ...policy, check_name: "from-relative" }));
    const { code, out } = await runMain(gh.url, { AIWORK_POLICY_PATH: "" }, join(gateDir, "main.mjs"));
    assert.notEqual(code, 0, out);
    assert.match(out, /AIWORK_POLICY_PATH/);
    const checks = appWrites(gh.log);
    assert.equal(checks.length, 0, out);
    assert.deepEqual(fuseStates(gh.log), ["failure"]);
  } finally {
    gh.server.close();
    rmSync(root, { recursive: true, force: true });
  }
});

// aiwork-review[bot] 评审(PR #10 review 5362031164,@ a190849)第 3 个阻断点:一个请求卡住,整次运行被拖到超时。
test("整机:发占位的请求卡住 → 按单个请求的超时放弃,保险丝已先拨 pending、再拨 failure,进程报错结束", async () => {
  const gh = await fakeGitHub({ hang: true });
  try {
    const started = Date.now();
    const { code } = await runMain(gh.url, { AIWORK_GATE_TIMEOUT_MS: "300" });
    assert.notEqual(code, 0);
    assert.ok(Date.now() - started < 10_000, "没被卡住的请求拖住");
    assert.deepEqual(fuseStates(gh.log), ["in_progress", "failure"]);
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
    const last = appWrites(gh.log).at(-1);
    assert.equal(last.body.conclusion, "success", out);
    const merge = gh.log.filter((r) => r.url === "/repos/o/r/pulls/10/merge");
    assert.equal(merge.length, 1, out);
    assert.equal(merge[0].method, "PUT");
    assert.deepEqual(merge[0].body, { sha: HEAD, merge_method: "merge" });
    assert.equal(merge[0].auth, "Bearer app-merge-token");
    // 合并接口要 contents + pull_requests;改了 .github/workflows/ 的 PR 还要 workflows,否则 GitHub 拒绝 App 合并
    const tok = gh.log.find((r) => r.url === "/app/installations/777/access_tokens" && !r.body.permissions.checks);
    assert.deepEqual(tok.body, { repositories: ["r"], permissions: { contents: "write", pull_requests: "write", workflows: "write" } });
    assert.ok(checkWrites(gh.log).every((r) => r.auth !== "Bearer app-merge-token"), "发检查不用合并令牌");
    const fuseOk = gh.log.indexOf(fuseWrites(gh.log).find((r) => r.body.conclusion === "success"));
    assert.ok(fuseOk >= 0 && fuseOk < gh.log.indexOf(merge[0]), "先写放行的结论,再合并");
  } finally {
    gh.server.close();
  }
});

// aiwork 放行关卡的流程(gate/run.mjs):只有本轮 App 放行结论写回后才允许合并。
// 每次运行把所有开着的 PR 全重算一遍(事件只是门铃);同一时间只有一次运行(workflow 并发组,见 test_aiwork_gate_workflow.mjs)。
// 跑法:node --test tests/test_aiwork_gate_run.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const { gate, validatePolicy } = await import("../gate/run.mjs");
const policy = JSON.parse(readFileSync(new URL("./fixtures/gate-logic-policy.json", import.meta.url), "utf8"));
const HEAD = "a".repeat(40);
const OTHER = "c".repeat(40);
const MAIN = "e".repeat(40);

function recorder() {
  const calls = [];
  let n = 0;
  const poster = {
    async start(sha) { calls.push(["start", sha]); return ++n; },
    async finish(sha, result, id) { calls.push(["finish", sha, result.status, result.conclusion, result.title, id]); },
  };
  return { calls, poster };
}
const finishes = (calls) => calls.filter((c) => c[0] === "finish").map((c) => c.slice(1, 5));
const isPrData = (c) => c[0] === "graphql" || ((c[0] === "get" || c[0] === "getPage") && !c[1].startsWith("/repos/o/r/pulls?"));

const reviewBody = (sha, verdict) => "```json\n" + JSON.stringify({ verdict, head_sha: sha, model: "gpt-x", family: "openai", completeness: "complete" }) + "\n```";
// 假 GitHub:几个开着的 PR,各有自己的 head、改动文件和一条 aiwork-review 评审(verdict 为 null 就没有评审);
// CI、推送记录按各自的 head 给。readHead 让"读 PR 本身"时读到另一个 head(列出之后又推进了),state 同理。
// fail(path) 为真的请求一律报错;lists 依次给出每次"列开着的 PR"读到哪几个(读完了就一直是最后一个)。
function prsApi(calls, prs, { fail = () => false, lists = null } = {}) {
  const numbers = Object.keys(prs).map(Number);
  let listed = 0;
  const pr = (n, read = false) => ({
    number: n,
    state: read ? prs[n].readState ?? "open" : "open",
    changed_files: prs[n].files.length,
    labels: (prs[n].labels ?? []).map((name) => ({ name })),
    head: { sha: read ? prs[n].readHead ?? prs[n].head : prs[n].head, ref: `claude/pr${n}`, repo: { full_name: "o/r" } },
    base: { ref: "main" },
  });
  const check = (p) => {
    if (fail(p)) throw new Error(`HTTP 502 ${p}`);
  };
  return {
    async graphql(query, { number }) {
      calls.push(["graphql", number]);
      const nodes = [
        ...(prs[number].verdict === null ? [] : [{ databaseId: 1, submittedAt: "2026-09-29T09:00:00Z", lastEditedAt: null }]),
        ...(prs[number].summaries ?? []).map((r) => ({ databaseId: r.id, submittedAt: r.submitted_at, lastEditedAt: r.lastEditedAt ?? null })),
      ];
      return { repository: { pullRequest: { reviews: { totalCount: nodes.length, pageInfo: { hasNextPage: false }, nodes } } } };
    },
    async get(p) {
      calls.push(["get", p]);
      check(p);
      const m = /\/pulls\/(\d+)$/.exec(p);
      if (m && prs[m[1]]) return pr(Number(m[1]), true);
      throw new Error(`没料到的请求 ${p}`);
    },
    async getPage(p) {
      calls.push(["getPage", p]);
      check(p);
      if (p === "/repos/o/r/pulls?state=open&per_page=100") {
        const now = lists ? lists[Math.min(listed++, lists.length - 1)] : numbers;
        return { data: now.map((n) => pr(n)), next: null };
      }
      const m = /\/pulls\/(\d+)\/(files|reviews)/.exec(p);
      if (m && m[2] === "files") return { data: prs[m[1]].files.map((f) => ({ filename: f })), next: null };
      if (m && m[2] === "reviews") {
        const { head, verdict = "PASS" } = prs[m[1]];
        return { data: [
          ...(verdict === null ? [] : [{ id: 1, user: { login: "aiwork-review[bot]", type: "Bot" }, state: "COMMENTED", commit_id: head, submitted_at: "2026-09-29T09:00:00Z", body: reviewBody(head, verdict) }]),
          ...(prs[m[1]].summaries ?? []),
        ], next: null };
      }
      const ci = /\/actions\/runs\?head_sha=([0-9a-f]{40})/.exec(p);
      if (ci) {
        const on = numbers.filter((n) => prs[n].head === ci[1]).map((n) => ({ number: n }));
        return { data: { workflow_runs: [{ id: 1, path: ".github/workflows/ci.yml", head_sha: ci[1], status: "completed", conclusion: "success", pull_requests: on, created_at: "2026-09-29T08:00:00Z" }] }, next: null };
      }
      const act = /\/activity\?ref=refs%2Fheads%2Fclaude%2Fpr(\d+)/.exec(p);
      if (act) return { data: [{ id: 1, timestamp: "t", activity_type: "push", after: prs[act[1]].head, actor: { login: "SunJ1ayuBoT" } }], next: null };
      const ev = /\/issues\/(\d+)\/events/.exec(p);
      if (ev) return { data: prs[ev[1]].events ?? [], next: null };
      throw new Error(`没料到的请求 ${p}`);
    },
  };
}
const one = (over = {}) => ({ 10: { head: HEAD, files: ["web/a.ts"], verdict: null, ...over } });
const prtEvent = { pull_request: { number: 10, head: { sha: HEAD } } };
const run = (r, api, over = {}) => gate({ repo: "o/r", event: prtEvent, policy, api, poster: r.poster, ...over });

test("R4 策略缺 App ID(或其他必填项)→ 不读 PR 的数据、不发 App 检查,本次运行失败且不合并", async () => {
  assert.throws(() => validatePolicy({ ...policy, gate_app_id: null }), /gate_app_id/);
  assert.throws(() => validatePolicy({ ...policy, check_name: "" }), /check_name/);
  assert.throws(() => validatePolicy({ ...policy, builders: [] }), /builders/);
  assert.throws(() => validatePolicy({ ...policy, builders: {} }), /builders/);
  assert.doesNotThrow(() => validatePolicy(policy));
  const dropMin = { ...policy };
  delete dropMin.high_min_families;
  assert.throws(() => validatePolicy(dropMin), /high_min_families/);
  for (const value of [1, 0, 1.5, "3", null]) {
    assert.throws(() => validatePolicy({ ...policy, high_min_families: value }), /high_min_families/, String(value));
  }
  const r = recorder();
  const api = prsApi(r.calls, { 10: { head: HEAD, files: ["web/a.ts"] }, 11: { head: OTHER, files: ["web/b.ts"] } });
  await assert.rejects(run(r, api, { policy: { ...policy, gate_app_id: null }, merger: mergeRecorder(r) }), /gate_app_id/);
  assert.deepEqual(merges(r.calls), []);
  assert.ok(!r.calls.some(isPrData), "只列了 PR,没读任何 PR 的数据");
  assert.ok(!r.calls.some((c) => c[0] === "start" || c[0] === "finish"), "不发 App 检查");
});

test("R5 先在每个 head 上发 App in_progress 占位,再读任何 PR 的数据", async () => {
  const r = recorder();
  await run(r, prsApi(r.calls, { 10: { head: HEAD, files: ["web/a.ts"] }, 11: { head: OTHER, files: ["web/b.ts"] } }));
  const firstData = r.calls.findIndex(isPrData);
  for (const sha of [HEAD, OTHER]) {
    const start = r.calls.findIndex((c) => c[0] === "start" && c[1] === sha);
    assert.ok(start >= 0 && start < firstData, `${sha.slice(0, 1)}:App 占位在读任何 PR 数据之前`);
  }
  assert.deepEqual(finishes(r.calls).map((f) => [f[0], f[2]]), [[HEAD, "success"], [OTHER, "success"]]);
});

test("R5b 连开着的 PR 都列不出来 → 不读 PR 数据、不发检查、不合并,运行报错", async () => {
  const r = recorder();
  const api = prsApi(r.calls, one(), { fail: (p) => p.startsWith("/repos/o/r/pulls?") });
  const event = { workflow_run: { event: "pull_request_review", head_sha: MAIN, pull_requests: [{ number: 10, head: { sha: HEAD } }] } };
  await assert.rejects(run(r, api, { event, merger: mergeRecorder(r) }), /502/);
  assert.deepEqual(merges(r.calls), []);
  assert.ok(!r.calls.some(isPrData));
  assert.ok(!r.calls.some((c) => c[0] === "start"));
});

// 评审 5362031164 第 2 条:列表不是一次拍下的,翻页期间有 PR 关掉,后面的往前挪,一个仍开着的 PR 被漏掉。
test("R26 开着的 PR 连读两遍一致才算数:第一遍漏了的,第二、三遍读到了就照算;一直对不上 → 报错且不发检查", async () => {
  const r = recorder();
  const prs = { 10: { head: HEAD, files: ["web/a.ts"] }, 11: { head: OTHER, files: ["web/b.ts"], verdict: "BLOCK" } };
  await run(r, prsApi(r.calls, prs, { lists: [[10], [10, 11], [10, 11]] }));
  assert.deepEqual(finishes(r.calls).map((f) => [f[0], f[2]]), [[HEAD, "success"], [OTHER, "failure"]], "第一遍漏掉的 #11 也重算了");
  const r2 = recorder();
  await assert.rejects(run(r2, prsApi(r2.calls, prs, { lists: [[10], [10, 11], [10], [10, 11], [10]] }), { merger: mergeRecorder(r2) }), /对不上/);
  assert.ok(!r2.calls.some((c) => c[0] === "start" || c[0] === "finish"));
  assert.deepEqual(merges(r2.calls), []);
});

test("R5c 读某个 PR 的数据出错 → 它的 head 判 G8 failure,别的 head 照常", async () => {
  const r = recorder();
  const api = prsApi(r.calls, { 10: { head: HEAD, files: ["web/a.ts"] }, 11: { head: OTHER, files: ["web/b.ts"] } }, { fail: (p) => p.includes("/pulls/10/files") });
  await run(r, api);
  const [onHead, onOther] = finishes(r.calls);
  assert.deepEqual(onHead.slice(0, 3), [HEAD, "completed", "failure"]);
  assert.match(onHead[3], /G8/);
  assert.deepEqual(onOther.slice(0, 3), [OTHER, "completed", "success"]);
});

test("R5d App 发不出占位(私钥坏了)→ 不读该提交的数据、不合并;其余提交照算,运行最后报错", async () => {
  const r = recorder();
  const poster = { ...r.poster, async start(sha) { r.calls.push(["start", sha]); if (sha === HEAD) throw new Error("缺 aiwork-gate App 的私钥"); return 7; } };
  await assert.rejects(run(r, prsApi(r.calls, { 10: { head: HEAD, files: ["web/a.ts"] }, 11: { head: OTHER, files: ["web/b.ts"] } }), { poster }), /私钥/);
  assert.ok(!r.calls.some((c) => c[0] === "get" && c[1].endsWith("/pulls/10")), "不读它的数据");
  assert.deepEqual(finishes(r.calls).map((f) => f[0]), [OTHER]);
});

test("R5e 列出之后 PR 又推进 / 关了 → 这个提交判 failure(已不是 head),新 head 由它的事件叫醒的下一次运行算", async () => {
  for (const over of [{ readHead: OTHER }, { readState: "closed" }]) {
    const r = recorder();
    await run(r, prsApi(r.calls, one({ verdict: "PASS", ...over })));
    const [f] = finishes(r.calls);
    assert.deepEqual(f.slice(0, 3), [HEAD, "completed", "failure"]);
    assert.match(f[3], /已不是开着的 PR 的 head/);
  }
});

test("R14c App 写不回结论(PATCH 失败)→ 运行失败", async () => {
  const r = recorder();
  const poster = { async start() { return 1; }, async finish() { throw new Error("HTTP 401 Bad credentials"); } };
  await assert.rejects(run(r, prsApi(r.calls, one({ verdict: "PASS" })), { poster }), /401/);
});

// ── aiwork-review[bot] 补充评审(PR #10 review 5360728878,@ 0ce3f73)─────────────────────────────
// 同一提交可能同时是几个开着的 PR 的 head(目标分支不同 ⇒ 改动、要求都不同),而检查挂在提交上。
const sameHead = (files10, files11) => ({ 10: { head: HEAD, files: files10 }, 11: { head: HEAD, files: files11 } });

test("R20 同一提交上另一个开着的 PR 不放行 → 这个提交上的结论就是不放行,标题点名拦住它的 PR", async () => {
  const r = recorder();
  await run(r, prsApi(r.calls, sameHead(["web/a.ts"], [".github/workflows/ci.yml"])));
  const [f] = finishes(r.calls);
  assert.equal(f[2], "failure");
  assert.match(f[3], /#11/);
  assert.equal(r.calls.filter((c) => c[0] === "start").length, 1, "一个提交只占一次位、写一次");
});

test("R20b 同一提交上的 PR 都放行 → 放行;其中一个读不全 → G8", async () => {
  const r = recorder();
  await run(r, prsApi(r.calls, sameHead(["web/a.ts"], ["web/b.ts"])));
  assert.equal(finishes(r.calls)[0][2], "success", "对照:两个都放行");
  const r2 = recorder();
  await run(r2, prsApi(r2.calls, sameHead(["web/a.ts"], ["web/b.ts"]), { fail: (p) => p.includes("/pulls/11/reviews") }));
  const [f] = finishes(r2.calls);
  assert.equal(f[2], "failure");
  assert.match(f[3], /G8/);
});

// ── aiwork-review[bot] 评审(PR #10 review 5361623557,@ 8f010fa)第 4 个阻断点 ─────────────────────
// 以前从事件推"该算哪个 PR":workflow_run 没带 PR 时按提交、再按分支查,指向默认分支就查不到被评审的 PR。
// 现在事件只是门铃:同样的现状,不管谁叫醒,写下的结论都一样。
test("R25 事件只是门铃:PR、workflow_run、无 PR/head 的定时事件 → 所有开放 PR 的结论完全一样", async () => {
  const events = [
    prtEvent,
    { pull_request: { number: 10, head: { sha: OTHER } }, action: "labeled", label: { name: "随便一个标签" } },
    { workflow_run: { event: "pull_request_review", head_sha: HEAD, pull_requests: [{ number: 10 }] } },
    { workflow_run: { event: "pull_request_review", head_sha: MAIN, head_branch: "main", pull_requests: [], head_repository: { owner: { login: "o" } } } },
    { workflow_run: { event: "push", head_sha: MAIN, head_branch: "main", pull_requests: [] } },
    { schedule: "scheduled" },
  ];
  const seen = [];
  for (const event of events) {
    const r = recorder();
    await run(r, prsApi(r.calls, {
      10: { head: HEAD, files: ["web/a.ts"], verdict: "BLOCK" },
      11: { head: OTHER, files: ["web/b.ts"], verdict: "BLOCK" },
    }), { event });
    seen.push(JSON.stringify(r.calls.filter((c) => c[0] !== "get" && c[0] !== "getPage" && c[0] !== "graphql")));
  }
  assert.ok(seen.every((s) => s === seen[0]), "写下的东西与事件无关");
  for (const head of [HEAD, OTHER]) {
    assert.ok(JSON.parse(seen[0]).some((c) => c[0] === "finish" && c[1] === head && c[2] === "completed" && c[3] === "failure"),
      "每个开放 PR 的 head 都要重算成 failure(BLOCK)");
  }
});

// ── 合并那一刻再判一次(gate/README.md「合并」)──────────────────────────────────────
// 合并请求 = PR 上贴着 aiwork:merge,且最后一次贴它的是业主或 merge_requesters 里的人(以后是 OpenClaw)。
// 合并不另起一套判定:就在这次运行里,用刚读到的数据判完、结论写上之后,带着判过的 head 调合并接口
// (head 变了接口就拒);没放行就不合,请求留着,等哪次运行判为放行再合。
const MERGE = policy.merge_label;
const labeled = (login, at = "2026-09-29T10:00:00Z", event = "labeled") => ({ id: Date.parse(at), event, label: { name: MERGE }, actor: { login }, created_at: at });
function mergeRecorder(r, { fail = () => false } = {}) {
  return { async merge(number, sha) { r.calls.push(["merge", number, sha]); if (fail(number)) throw new Error("HTTP 409 Head branch was modified"); } };
}
const merges = (calls) => calls.filter((c) => c[0] === "merge").map((c) => [c[1], c[2]]);

test("M1 业主贴了 aiwork:merge、PR 放行 → 结论写完之后,带着判过的 head 合并;没贴的 PR 不合", async () => {
  const r = recorder();
  const api = prsApi(r.calls, {
    10: { head: HEAD, files: ["web/a.ts"], labels: [MERGE], events: [labeled(policy.owner)] },
    11: { head: OTHER, files: ["web/b.ts"] },
  });
  await run(r, api, { merger: mergeRecorder(r) });
  assert.deepEqual(merges(r.calls), [[10, HEAD]]);
  const merged = r.calls.findIndex((c) => c[0] === "merge");
  const wrote = r.calls.findIndex((c) => c[0] === "finish" && c[1] === HEAD && c[2] === "completed" && c[3] === "success");
  assert.ok(wrote >= 0 && wrote < merged, "先把放行的结论写到提交上,再合并");
});

test("M2 只认业主和 merge_requesters 里的人贴的标签:Builder 贴的不合", async () => {
  const builder = Object.keys(policy.builders)[0];
  for (const [who, expect] of [[builder, []], ["someone-else", []], ["aiwork-orchestrator[bot]", [[10, HEAD]]]]) {
    const r = recorder();
    const api = prsApi(r.calls, { 10: { head: HEAD, files: ["web/a.ts"], labels: [MERGE], events: [labeled(who)] } });
    await run(r, api, { merger: mergeRecorder(r), policy: { ...policy, merge_requesters: ["aiwork-orchestrator[bot]"] } });
    assert.deepEqual(merges(r.calls), expect, who);
  }
});

test("M3 贴了标签但没放行 → 不合、请求留着;之后某次运行判为放行 → 合", async () => {
  const r = recorder();
  const blocked = prsApi(r.calls, { 10: { head: HEAD, files: ["web/a.ts"], verdict: null, labels: [MERGE], events: [labeled(policy.owner)] } });
  await run(r, blocked, { merger: mergeRecorder(r) });
  assert.deepEqual(merges(r.calls), [], "缺评审不合");
  const r2 = recorder();
  const passed = prsApi(r2.calls, { 10: { head: HEAD, files: ["web/a.ts"], labels: [MERGE], events: [labeled(policy.owner)] } });
  await run(r2, passed, { merger: mergeRecorder(r2) });
  assert.deepEqual(merges(r2.calls), [[10, HEAD]]);
});

test("M4 标签已不在 PR 上、或最后一次动它是撤掉 → 不合;业主贴过、Builder 撤掉又重贴 → 按最后一次(Builder)算,不合", async () => {
  const builder = Object.keys(policy.builders)[0];
  const cases = [
    { labels: [], events: [labeled(policy.owner)] },
    { labels: [MERGE], events: [labeled(policy.owner, "2026-09-29T10:00:00Z"), labeled(policy.owner, "2026-09-29T11:00:00Z", "unlabeled")] },
    { labels: [MERGE], events: [] },
    { labels: [MERGE], events: [labeled(policy.owner, "2026-09-29T10:00:00Z"), labeled(builder, "2026-09-29T11:00:00Z", "unlabeled"), labeled(builder, "2026-09-29T12:00:00Z")] },
  ];
  for (const c of cases) {
    const r = recorder();
    await run(r, prsApi(r.calls, { 10: { head: HEAD, files: ["web/a.ts"], ...c } }), { merger: mergeRecorder(r) });
    assert.deepEqual(merges(r.calls), [], JSON.stringify(c));
  }
});

test("M5 同一提交还是另一个不放行的 PR 的 head → 这个提交上的结论不放行,贴了标签也不合", async () => {
  const r = recorder();
  const api = prsApi(r.calls, {
    10: { head: HEAD, files: ["web/a.ts"], labels: [MERGE], events: [labeled(policy.owner)] },
    11: { head: HEAD, files: ["web/b.ts"], verdict: "BLOCK" },
  });
  await run(r, api, { merger: mergeRecorder(r) });
  assert.deepEqual(merges(r.calls), []);
});

test("M6 合并接口出错(比如判完之后又推了新提交)→ 记下原因,不抛错,别的提交照常写结论", async () => {
  const r = recorder();
  const logs = [];
  const api = prsApi(r.calls, {
    10: { head: HEAD, files: ["web/a.ts"], labels: [MERGE], events: [labeled(policy.owner)] },
    11: { head: OTHER, files: ["web/b.ts"] },
  });
  await run(r, api, { merger: mergeRecorder(r, { fail: (n) => n === 10 }), log: (l) => logs.push(l) });
  assert.deepEqual(merges(r.calls), [[10, HEAD]]);
  assert.deepEqual(finishes(r.calls).map((f) => [f[0], f[2]]), [[HEAD, "success"], [OTHER, "success"]]);
  assert.ok(logs.some((l) => /PR #10/.test(l) && /409/.test(l)), logs.join("\n"));
});

test("M7 策略:merge_label 必须是非空字符串,merge_requesters 必须是字符串数组", () => {
  assert.throws(() => validatePolicy({ ...policy, merge_label: "" }), /merge_label/);
  assert.throws(() => validatePolicy({ ...policy, merge_requesters: "SunJ1ayu" }), /merge_requesters/);
  assert.throws(() => validatePolicy({ ...policy, merge_requesters: [1] }), /merge_requesters/);
  assert.throws(() => validatePolicy({ ...policy, merge_requesters: [Object.keys(policy.builders)[0]] }), /merge_requesters/, "Builder 不能在名单里");
  assert.equal(policy.merge_label, "aiwork:merge");
  assert.ok(!policy.merge_requesters.includes(policy.owner), "业主一直算,不在名单里再写一遍");
});

test("M8 App 放行结论写回失败 → 不合并;其余 head 照算,运行最后报错", async () => {
  const r = recorder();
  const poster = { ...r.poster, async finish(sha, result, id) {
    if (sha === HEAD) throw new Error("HTTP 502 checks");
    await r.poster.finish(sha, result, id);
  } };
  const api = prsApi(r.calls, {
    10: { head: HEAD, files: ["web/a.ts"], labels: [MERGE], events: [labeled(policy.owner)] },
    11: { head: OTHER, files: ["web/b.ts"] },
  });
  await assert.rejects(run(r, api, { poster, merger: mergeRecorder(r) }), /502/);
  assert.deepEqual(finishes(r.calls).map((f) => [f[0], f[2]]), [[OTHER, "success"]]);
  assert.deepEqual(merges(r.calls), []);
});

test("M9 贴着标签却不合并时,日志说清为什么:谁贴的不算数 / 找不到是谁贴的", async () => {
  const builder = Object.keys(policy.builders)[0];
  for (const [events, why] of [[[labeled(builder)], new RegExp(`${builder}.*不算数`)], [[], /找不到是谁/]]) {
    const r = recorder();
    const logs = [];
    await run(r, prsApi(r.calls, { 10: { head: HEAD, files: ["web/a.ts"], labels: [MERGE], events } }), { merger: mergeRecorder(r), log: (l) => logs.push(l) });
    assert.deepEqual(merges(r.calls), []);
    assert.ok(logs.some((l) => /PR #10/.test(l) && why.test(l)), logs.join("\n"));
  }
});

test("M10 只看合并标签自己的记录:业主贴了之后 Builder 又贴了别的标签(aiwork:recheck)→ 还是业主的请求,合", async () => {
  const builder = Object.keys(policy.builders)[0];
  const recheck = { ...labeled(builder, "2026-09-29T11:00:00Z"), label: { name: "aiwork:recheck" } };
  const r = recorder();
  await run(r, prsApi(r.calls, { 10: { head: HEAD, files: ["web/a.ts"], labels: [MERGE, "aiwork:recheck"], events: [labeled(policy.owner), recheck] } }), { merger: mergeRecorder(r) });
  assert.deepEqual(merges(r.calls), [[10, HEAD]]);
});

test("轮数显示复用既有读取和分页，不增接口；同 head 每个 PR 的信号都保留，不挡合并", async () => {
  const roundPolicy = { ...policy, modification_rounds: { limit: 1, summary_account: "summary-user" } };
  const summary = (head, id = 20, body = null) => ({ id, user: { login: "summary-user", type: "User" },
    state: "COMMENTED", commit_id: head, submitted_at: "2026-09-29T10:00:00Z",
    body: body ?? '```aiwork-summary\n' + JSON.stringify({ head_sha: head, next_step: "照单修", has_p1: true }) + '\n```\n\n修复问题' });
  const stopped = [summary(OTHER), summary(HEAD, 21, '```aiwork-summary\n' + JSON.stringify({ head_sha: HEAD, next_step: "交业主", has_p1: true }) + '\n```')];
  for (const variant of [[], [summary(HEAD)], stopped, [summary(HEAD, 21, '```aiwork-summary\ninvalid\n```')],
    [{ ...summary(HEAD), lastEditedAt: "2026-09-29T11:00:00Z" }]]) {
    const prs = {
      10: { head: HEAD, files: [], verdict: "PASS", summaries: variant, labels: [policy.merge_label],
        events: [{ event: "labeled", label: { name: policy.merge_label }, actor: { login: policy.owner }, created_at: "t", id: 2 }] },
      11: { head: HEAD, files: [], verdict: "PASS", summaries: [] },
    };
    const oldCalls = [], newCalls = [], merged = [];
    const before = await run(recorder(), prsApi(oldCalls, prs));
    const after = await run(recorder(), prsApi(newCalls, prs), { policy: roundPolicy, merger: { async merge(n) { merged.push(n); } } });
    assert.deepEqual(newCalls, oldCalls, "包括请求数量、路径、顺序都和旧策略相同");
    assert.equal(after[0].title, before[0].title);
    assert.match(after[0].summary, /PR #10[^\n]*轮数：/);
    assert.match(after[0].summary, /PR #11[^\n]*轮数：未知/);
    if (variant === stopped) assert.match(after[0].summary, /PR #10[^\n]*停：交业主/);
    else assert.doesNotMatch(after[0].summary, /停：交业主/);
    assert.deepEqual(merged, [10], "包括停信号和读不清都不挡原有的合并请求");
  }
});

test("同 head 的未选中 PR 停信号排在长详情之前，GitHub 摘要截断也不丢", async () => {
  const at = "2026-09-29T10:00:00Z";
  const prs = {
    10: { head: HEAD, files: [], verdict: "PASS", summaries: [{ id: 22, user: { login: policy.reviewer_bot, type: "Bot" },
      state: "COMMENTED", commit_id: HEAD, submitted_at: at, body: reviewBody(HEAD, "PASS").replace("gpt-x", "x".repeat(65000)) }] },
    11: { head: HEAD, files: [], verdict: "PASS", summaries: [{ id: 23, user: { login: "summary-user", type: "User" },
      state: "COMMENTED", commit_id: HEAD, submitted_at: at, body: '```aiwork-summary\n' + JSON.stringify({
        head_sha: HEAD, next_step: "照单修", has_p1: true,
      }) + '\n```\n\n修复问题' }, { id: 24, user: { login: "summary-user", type: "User" },
      state: "COMMENTED", commit_id: OTHER, submitted_at: "2026-09-29T11:00:00Z", body: '```aiwork-summary\n' + JSON.stringify({
        head_sha: OTHER, next_step: "交业主", has_p1: true,
      }) + '\n```' }] },
  };
  const result = await run(recorder(), prsApi([], prs), {
    policy: { ...policy, modification_rounds: { limit: 1, summary_account: "summary-user" } },
  });
  const posted = result[0].summary.slice(0, 60000);
  assert.match(posted, /PR #10[^\n]*轮数：未知/);
  assert.match(posted, /PR #11[^\n]*第 1 轮[^\n]*停：交业主/);
});

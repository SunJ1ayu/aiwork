import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { decide, DEFAULT_MODIFICATION_ROUND_LIMIT } from "../gate/decide.mjs";
import { validatePolicy } from "../gate/run.mjs";

const read = (p) => readFileSync(new URL(p, import.meta.url), "utf8");
const definition = JSON.parse(/```aiwork-summary-schema\n([\s\S]*?)\n```/.exec(read("../workflow/skills/summary/SKILL.md"))[1]);
const baseline = JSON.parse(read("./fixtures/gate-logic-policy.json"));
const rounds = { limit: 2, summary_account: "summary-user" };
const policy = { ...baseline, modification_rounds: rounds };
const HEAD = "a".repeat(40), OLD = "b".repeat(40), OLDER = "c".repeat(40);
const pass = { id: 1, login: baseline.reviewer_bot, type: "Bot", state: "COMMENTED", commit_id: HEAD,
  submitted_at: "2026-10-30T01:00:00Z", body: '```json\n' + JSON.stringify({
    verdict: "PASS", head_sha: HEAD, family: "openai", model: "test", completeness: "complete",
  }) + '\n```' };
const record = (head = HEAD, next_step = "照单修", has_p1 = true, modification_task = "修复已复现的问题") =>
  ({ head_sha: head, next_step, has_p1, modification_task });
const summary = (value = record(), over = {}) => {
  const { modification_task, ...metadata } = value;
  return {
    id: 20, login: rounds.summary_account, type: "User", state: "COMMENTED", commit_id: value.head_sha,
    submitted_at: "2026-10-30T02:00:00Z", edited_at: null,
    body: '```' + definition.title + '\n' + JSON.stringify(metadata) + '\n```\n\n' + modification_task, ...over,
  };
};
const facts = (reviews = [], over = {}) => ({
  pr: { number: 10, state: "open", head_sha: HEAD }, files: ["web/a.ts"],
  ci: { state: "success", detail: "ok" }, pushes: { covers_head: true, actors: ["SunJ1ayuBoT"] },
  reviews: [pass, ...reviews], ...over,
});
const run = (reviews, over) => decide(facts(reviews, over), policy);

test("轮数按修改单的不同 head 数，其他推送和评审不加轮；最新 P1 触发停信号", () => {
  const reviews = [summary(record(OLD)), summary(record(OLDER)), summary(record(HEAD, "交业主", true, ""))];
  const result = run(reviews);
  assert.match(result.summary, /第 2 轮 \/ 上限 2/);
  assert.match(result.summary, /停：交业主/);
  assert.match(run([summary(record(OLD)), summary(record(OLD), { id: 21 })]).summary, /第 1 轮/);
  assert.doesNotMatch(run([summary(record(OLD))]).summary, /停：交业主/);
  assert.doesNotMatch(run([...reviews.slice(0, 2), summary(record(HEAD, "合并", false, ""))]).summary, /停：交业主/);
  assert.match(run([summary(record(OLD))], { pr: { number: 10, head_sha: HEAD } }).summary, /第 1 轮/);
  assert.match(run([summary(record(HEAD, "合并", false, ""))]).summary, /第 0 轮/);
  // REST 返回次序不是“最新”；相同时刻按评审 id 排。
  assert.doesNotMatch(run([summary(record(HEAD, "合并", false, ""), { id: 30 }), ...reviews.slice(0, 2)]).summary, /停：交业主/);
});

test("迟到的重复修改单不改变最新汇总，输入次序也不改变停信号", () => {
  const tasks = [OLD, OLDER].map((head, i) => summary(record(head), {
    id: 20 + i, submitted_at: `2026-10-30T0${i + 1}:00:00Z`,
  }));
  const stopped = summary(record(HEAD, "交业主", true, ""), { id: 30, submitted_at: "2026-10-30T03:00:00Z" });
  const duplicate = { ...tasks[0], id: 40, submitted_at: "2026-10-30T04:00:00Z" };
  for (const reviews of [[...tasks, stopped, duplicate], [duplicate, stopped, ...tasks.toReversed()],
    [tasks[1], duplicate, stopped, tasks[0]]]) {
    assert.match(run(reviews).round_line, /第 2 轮 \/ 上限 2；停：交业主/);
  }
});

test("缩进或围栏名之前有空白的记录显示读不清，不当成没有记录", () => {
  const valid = summary();
  for (const opening of [" ```", "  ```", "   ```", "``` ", "```\t"]) {
    const body = valid.body.replace(/^```/, opening);
    assert.match(run([{ ...valid, body }]).round_line, /轮数：读不清/, opening);
  }
});

test("证据和修改单中的引用围栏不冒充真正的记录", () => {
  const example = summary(record(OLD)).body;
  for (const quoted of [example.split("\n").map((line) => `> ${line}`).join("\n"),
    `\`\`\`\`markdown\n${example}\n\`\`\`\``, `~~~markdown\n${example}\n~~~`]) {
    for (const body of [`核实证据\n${quoted}\n\n${summary().body}`, `${summary().body}\n\n举例\n${quoted}`]) {
      assert.match(run([summary(record(), { body })]).round_line, /第 1 轮/);
    }
    assert.match(run([summary(record(), { body: quoted })]).round_line, /轮数：未知/);
  }
});

test("summary skill 的引用示例直接交给关卡，引用前后和改写都不影响真记录", () => {
  const examples = [...read("../workflow/skills/summary/SKILL.md").matchAll(/^`````markdown\n([\s\S]*?)\n`````$/gm)];
  assert.ok(examples.length, "引用边界示例必须在 summary skill 定义");
  for (const [, example] of examples) {
    for (const body of [example, example.replaceAll("\n", "\r\n")]) {
      for (const edited_at of [null, "2026-10-30T03:00:00Z"]) {
        assert.match(run([summary(record(), { body, edited_at })]).round_line, /轮数：未知/);
      }
      for (const combined of [`${body}\n\n${summary().body}`, `${summary().body}\n\n${body}`]) {
        assert.match(run([summary(record(), { body: combined })]).round_line, /第 1 轮/);
      }
    }
  }
});

test("围栏扫描处理长围栏、不同标记、缩进、行尾空白和未结束的记录", () => {
  const valid = summary();
  for (const body of [valid.body, valid.body.replaceAll("\n", "\r\n"),
    valid.body.replaceAll("\n", " \t\n"), `${valid.body}\n\n`]) {
    assert.match(run([{ ...valid, body }]).round_line, /第 1 轮/);
  }
  for (const body of [valid.body.replace("\n```", "\n ```"),
    valid.body.replaceAll("```", "````"), valid.body.replaceAll("```", "~~~"),
    valid.body.slice(0, valid.body.indexOf("\n```")), `${valid.body}\n${valid.body}`]) {
    assert.match(run([{ ...valid, body }]).round_line, /轮数：读不清/);
  }
  const example = summary(record(OLD)).body;
  for (const body of [example.split("\n").map((line) => `    ${line}`).join("\n"),
    `  \`\`\`\`\`markdown\n\`\`\`\`\n~~~\n${example}\n  \`\`\`\`\`\``,
    `~~~markdown\n\`\`\`\n${example}\n  ~~~~`]) {
    assert.match(run([{ ...valid, body: `${body}\n\n${valid.body}` }]).round_line, /第 1 轮/);
  }
});

test("旧 PR 和冒充者是未知；改写、格式错误、同 head 冲突一律读不清", () => {
  for (const reviews of [[], [summary(record(), { login: "builder" })], [summary(record(), { body: "旧式汇总" })]]) {
    assert.match(run(reviews).summary, /轮数：未知/);
    assert.doesNotMatch(run(reviews).summary, /第 0 轮/);
  }
  const valid = summary();
  const malformed = [
    { ...valid, edited_at: "2026-10-30T03:00:00Z" },
    { ...valid, body: "```aiwork-summary\n{\n```" },
    { ...valid, body: valid.body + "\n" + valid.body },
    { ...valid, commit_id: OLD },
    { ...valid, state: "DISMISSED" },
    { ...valid, submitted_at: "" },
    summary({ ...record(), next_step: "随便" }),
    summary({ ...record(), has_p1: "true" }),
    summary({ ...record(), head_sha: "short" }),
    summary({ ...record(), modification_task: "" }),
    summary(record(HEAD, "合并", true, "")),
    summary(record(HEAD, "照单修", false)),
    summary({ ...record(), extra: true }),
  ];
  for (const r of malformed) assert.match(run([r]).summary, /轮数：读不清/, JSON.stringify(r));
  for (const value of [record(HEAD, "交业主", true, ""), record(HEAD, "合并", false, ""), { ...record(), modification_task: "另一张单" }]) {
    assert.match(run([valid, summary(value, { id: 21 })]).summary, /轮数：读不清/);
  }
});

test("所有汇总输入只追加显示，不改变任何 G1–G8 结果；未配置时整个返回值相同", () => {
  const cases = [[], [summary()], [summary(record(), { edited_at: "edited" })],
    [summary(record(OLD)), summary(record(OLDER))], [summary(record(HEAD, "合并", false, ""))],
    [summary(record(), { body: " " + summary().body })],
    [summary(record(), { body: `\`\`\`\`markdown\n${summary(record(OLD)).body}\n\`\`\`\`\n${summary().body}` })],
    [summary(record(OLD)), summary(record(OLDER)), summary(record(HEAD, "交业主", true, "")),
      summary(record(OLD), { id: 40, submitted_at: "2026-10-30T04:00:00Z" })]];
  for (const over of [{}, { ci: { state: "pending" } }, { ci: { state: "failure" } },
    { files: [".github/a.yml"] }, { files: ["desktop/main.js"] },
    { pushes: { covers_head: false, actors: [] } }]) {
    for (const reviews of cases) {
      const f = facts(reviews, over);
      const before = decide(f, baseline), after = decide(f, policy);
      assert.deepEqual({ ...after, summary: before.summary, round_line: undefined }, { ...before, round_line: undefined });
      assert.equal(after.summary.replace(`${after.round_line}\n\n`, ""), before.summary);
      assert.deepEqual(decide(f, { ...baseline }), before);
    }
  }
  for (const extra of [
    { ...pass, id: 2, body: pass.body.replace('"PASS"', '"BLOCK"') },
    { id: 3, login: baseline.owner, type: "User", state: "CHANGES_REQUESTED", commit_id: HEAD, submitted_at: "2026-10-30T03:00:00Z", body: "" },
    { id: 4, login: baseline.owner, type: "User", state: "APPROVED", commit_id: HEAD, submitted_at: "2026-10-30T03:00:00Z", body: "" },
  ]) {
    for (const reviews of cases) {
      const f = facts([...reviews, extra], { files: [".github/a.yml", "desktop/main.js"] });
      const before = decide(f, baseline), after = decide(f, policy);
      assert.deepEqual({ ...after, summary: before.summary, round_line: undefined }, { ...before, round_line: undefined });
    }
  }
});

test("策略保留 Builder 家族登记，轮数功能可选且必须完整", () => {
  assert.doesNotThrow(() => validatePolicy(baseline));
  for (const builders of [{}, []]) assert.throws(() => validatePolicy({ ...policy, builders }), /builders/);
  assert.doesNotThrow(() => validatePolicy({ ...policy, modification_rounds: { ...rounds, summary_account: "sunj1ayubot" } }));
  for (const modification_rounds of [null, {}, { ...rounds, limit: 0 }, { ...rounds, limit: 1.5 },
    { ...rounds, limit: "2" }, { ...rounds, summary_account: "" },
    { ...rounds, summary_account: baseline.reviewer_bot }]) {
    assert.throws(() => validatePolicy({ ...baseline, modification_rounds }), /modification_rounds/);
  }
  assert.throws(() => validatePolicy({ ...policy, merge_requesters: ["SUMMARY-USER"] }), /modification_rounds/);
  assert.throws(() => validatePolicy({ ...policy, modification_rounds: { ...rounds, summary_account: baseline.owner } }), /modification_rounds/);
});

test("summary skill 的唯一定义直接生成格式对照用例", () => {
  const skill = read("../workflow/skills/summary/SKILL.md");
  const match = /```aiwork-summary-schema\n([\s\S]*?)\n```/.exec(skill);
  assert.ok(match, "格式必须在 summary skill 定义");
  const schema = JSON.parse(match[1]);
  // 按定义解释 JSON Schema 的结构，和生产解析器逐个对照；没有第三份字段/枚举定义。
  function accepts(spec, value) {
    if (spec.type === "object" && (!value || typeof value !== "object" || Array.isArray(value))) return false;
    if (spec.type && spec.type !== "object" && typeof value !== spec.type) return false;
    if (Object.hasOwn(spec, "const") && value !== spec.const) return false;
    if (spec.enum && !spec.enum.includes(value)) return false;
    if (spec.pattern && (typeof value !== "string" || !new RegExp(spec.pattern).test(value))) return false;
    if (spec.required?.some((key) => !Object.hasOwn(value, key))) return false;
    if (spec.additionalProperties === false && Object.keys(value).some((key) => !Object.hasOwn(spec.properties, key))) return false;
    for (const [key, child] of Object.entries(spec.properties ?? {})) {
      if (Object.hasOwn(value, key) && !accepts(child, value[key])) return false;
    }
    if (spec.allOf?.some((child) => !accepts(child, value))) return false;
    if (spec.if && accepts(spec.if, value) && !accepts(spec.then, value)) return false;
    return true;
  }
  const candidates = [];
  for (const size of [0, 7, 39, 40, 41]) candidates.push({ ...record(), head_sha: "a".repeat(size) });
  for (const next of ["交业主", "照单修", "合并", "invalid"]) {
    for (const p1 of [true, false, "true"]) {
      for (const task of ["修改单\n完整正文", "", "   "]) candidates.push(record(HEAD, next, p1, task));
    }
  }
  for (const value of candidates) {
    const { modification_task, ...metadata } = value;
    const expected = accepts(schema, metadata) && (metadata.next_step !== "照单修" || !!modification_task.trim());
    assert.equal(!/读不清/.test(run([summary(value)]).summary), expected, JSON.stringify(value));
  }
  assert.deepEqual(schema.required.toSorted(), Object.keys(record()).filter((key) => key !== "modification_task").toSorted());
  for (const next_step of schema.properties.next_step.enum) {
    const value = record(HEAD, next_step, next_step !== "合并", next_step === "照单修" ? "修改单正文" : "");
    assert.doesNotMatch(run([summary(value)]).summary, /读不清|未知/);
  }
  for (const field of schema.required) {
    const value = record(); delete value[field];
    assert.match(run([summary(value)]).summary, /读不清/, field);
  }
  for (const [field, spec] of Object.entries(schema.properties)) {
    assert.equal(typeof record()[field], spec.type);
    if (spec.pattern) assert.ok(new RegExp(spec.pattern).test(record()[field]));
    const invalid = spec.type === "boolean" ? "true" : true;
    assert.match(run([summary({ ...record(), [field]: invalid })]).summary, /读不清/, field);
  }
  assert.equal(schema.additionalProperties, false);
  const current = JSON.parse(read("../.aiwork/policy.json"));
  assert.equal(DEFAULT_MODIFICATION_ROUND_LIMIT, 3);
  assert.equal(Object.hasOwn(current.modification_rounds, "limit"), false, "aiwork 直接使用共享默认值，不抄第二份数字");
  assert.equal(current.modification_rounds.summary_account, "SunJ1ayuBoT");
  assert.deepEqual(current.builders, { SunJ1ayuBoT: "anthropic" });
  validatePolicy(current);
});

test("真实策略保留 main 的 UNKNOWN 家族边界：Claude PASS 不能单独或在 high 凑数", () => {
  const current = JSON.parse(read("../.aiwork/policy.json"));
  const approval = { id: 90, login: current.owner, type: "User", state: "APPROVED", commit_id: HEAD,
    submitted_at: "2026-10-30T04:00:00Z", body: "" };
  const reviewed = (family, id) => ({ ...pass, id, body: pass.body.replace('"openai"', JSON.stringify(family)) });
  const unknown = { covers_head: true, actors: ["aiwork-build[bot]"] };
  const high = decide(facts([], { pushes: unknown, files: ["bin/gh-app-token"],
    reviews: [reviewed("anthropic", 1), reviewed("openai", 2), reviewed("deepseek", 3), approval] }), current);
  assert.equal(high.title, `不放行:high 路径要 ${current.high_min_families} 家不同家族都 PASS`);
  assert.deepEqual(high.passes.map((r) => r.family).sort(), ["deepseek", "openai"]);
  const ordinary = decide(facts([], { pushes: unknown, reviews: [reviewed("anthropic", 1), approval] }), current);
  assert.equal(ordinary.author.known, false);
  assert.equal(ordinary.title, "不放行:缺合格评审");
  assert.equal(decide(facts([], { pushes: unknown, reviews: [reviewed("openai", 2), approval] }), current).title, "放行");
  assert.deepEqual([...new Set(Object.values(current.builders))], ["anthropic"]);
});

test("真实策略仅删除轮数配置仍合法；汇总暂可保留 Builder 登记", () => {
  const current = JSON.parse(read("../.aiwork/policy.json"));
  const enabled = decide(facts([]), current);
  delete current.modification_rounds;
  const disabled = decide(facts([]), current);
  assert.deepEqual({ ...enabled, summary: disabled.summary, round_line: undefined }, { ...disabled, round_line: undefined });
  assert.doesNotThrow(() => validatePolicy(current));
  assert.doesNotThrow(() => validatePolicy({ ...current, builders: { SunJ1ayuBoT: "anthropic" },
    modification_rounds: { limit: 3, summary_account: "SunJ1ayuBoT" } }));
});

test("上限那张单刚发、修复中和新 head 等汇总时不停；修后仍有 P1 或超限派单才停", () => {
  const p = { ...policy, modification_rounds: { ...rounds, limit: 3 } };
  const tasks = [OLDER, OLD, HEAD].map((h, i) => summary(record(h), { id: 20 + i,
    submitted_at: `2026-10-30T0${i + 1}:00:00Z` }));
  for (const head of [HEAD, "d".repeat(40)]) {
    const result = decide(facts(tasks, { pr: { number: 10, head_sha: head } }), p);
    assert.match(result.round_line, /第 3 轮 \/ 上限 3/);
    assert.doesNotMatch(result.round_line, /停：交业主/);
  }
  for (const [next, p1, task, stopped] of [["交业主", true, "", true], ["合并", false, "", false],
    ["交业主", false, "", false], ["照单修", true, "违规派出的第 4 张单", true]]) {
    const after = summary(record("d".repeat(40), next, p1, task), { id: 30, submitted_at: "2026-10-30T04:00:00Z" });
    assert.equal(decide(facts([...tasks, after]), p).round_line.includes("停：交业主"), stopped);
  }
});

test("被改写的非记录评审不污染已有轮数，也不把未知变读不清", () => {
  for (const body of ["旧式汇总", "说明 aiwork-summary 的用途"]) {
    const old = summary(record(OLDER), { body, edited_at: "2026-10-30T03:00:00Z" });
    assert.match(run([old]).round_line, /轮数：未知/);
    assert.match(run([old, summary(record(OLD))]).round_line, /第 1 轮/);
  }
});

test("修改单只存一份 Markdown，PR 上直接显示换行、列表和代码块，机器按原文判冲突", () => {
  const task = "## 第 1 张修改单\n\n- 修复甲\n- 修复乙\n\n```sh\nnode tests/test_aiwork_gate_rounds.mjs\n```";
  const metadata = { head_sha: HEAD, next_step: "照单修", has_p1: true };
  const body = '核实证据\n\n```' + definition.title + '\n' + JSON.stringify(metadata) + '\n```\n\n' + task;
  const r = summary(record(), { body });
  assert.match(run([r]).round_line, /第 1 轮/);
  assert.doesNotMatch(run([r]).round_line, /读不清/);
  assert.match(run([r, { ...r, id: 21, body: body.replace("修复乙", "修复丙") }]).round_line, /读不清/);
  assert.match(run([{ ...r, body: body.slice(0, body.indexOf(task)) }]).round_line, /读不清/);
});

test("只配汇总账号时使用共享默认上限，项目覆盖值仍有效", () => {
  const defaults = { ...baseline, modification_rounds: { summary_account: rounds.summary_account } };
  assert.doesNotThrow(() => validatePolicy(defaults));
  const tasks = [OLDER, OLD, HEAD].map((h, i) => summary(record(h), { id: 20 + i }));
  const result = decide(facts(tasks), defaults);
  assert.match(result.round_line, /第 3 轮 \/ 上限 3/);
  assert.doesNotMatch(result.round_line, /停：交业主/);
  assert.match(decide(facts(tasks), { ...defaults, modification_rounds: { ...defaults.modification_rounds, limit: 2 } }).round_line, /停：交业主/);
});

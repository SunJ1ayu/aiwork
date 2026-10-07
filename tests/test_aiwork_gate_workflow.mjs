// 项目接入关卡只有一种方式：.aiwork/policy.json，加上与 templates/ 相同的两份 workflow。
// 跑法:node --test tests/test_aiwork_gate_workflow.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { matchAny } from "../gate/decide.mjs";
import { validatePolicy } from "../gate/run.mjs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

test("本仓库的两份 workflow 与模板逐字相同", () => {
  assert.equal(read(".github/workflows/aiwork-gate.yml"), read("templates/aiwork-gate.yml"));
  assert.equal(read(".github/workflows/aiwork-review-ping.yml"), read("templates/aiwork-review-ping.yml"));
});

test("aiwork-gate workflow：先检出调用方 main 的策略，再检出 aiwork main 的关卡，不检出 PR", () => {
  const text = read("templates/aiwork-gate.yml");
  assert.match(text, /^name: aiwork-gate$/m);
  assert.match(text, /types: \[opened, synchronize, reopened, closed, labeled, edited\]/);
  assert.match(text, /workflows: \[ci, aiwork-review-ping\]/);
  assert.match(text, /types: \[requested, in_progress, completed\]/);
  assert.doesNotMatch(text, /^ {2}pull_request:/m);
  assert.match(text, /contents: read/);
  assert.match(text, /pull-requests: read/);
  assert.match(text, /actions: read/);
  assert.match(text, /issues: read/);
  assert.match(text, /statuses: write/);
  assert.match(text, /group: aiwork-gate/);
  assert.match(text, /cancel-in-progress: false/);
  assert.match(text, /environment: aiwork-gate/);
  assert.equal(text.match(/persist-credentials: false/g)?.length, 2);
  assert.match(text, /ref: \$\{\{ github\.event\.repository\.default_branch \}\}/);
  assert.match(text, /path: caller/);
  assert.match(text, /repository: SunJ1ayu\/aiwork/);
  assert.match(text, /ref: main/);
  assert.match(text, /path: aiwork/);
  assert.match(text, /node-version: "22"/);
  assert.match(text, /working-directory: aiwork/);
  assert.match(text, /AIWORK_POLICY_PATH: \$\{\{ github\.workspace \}\}\/caller\/\.aiwork\/policy\.json/);
  assert.match(text, /^ {8}run: node gate\/main\.mjs$/m);
  assert.doesNotMatch(text, /github\.event\.pull_request\.head/);
  assert.doesNotMatch(text, /github\.sha/);
  const run = text.split(/^ {8}run: /m).slice(1).join("\n");
  assert.doesNotMatch(run, /\$\{\{/);
});

test("aiwork-review-ping：无权限，只敲门，不把事件内容拼进 shell", () => {
  const text = read("templates/aiwork-review-ping.yml");
  assert.match(text, /^name: aiwork-review-ping$/m);
  assert.match(text, /types: \[submitted, edited, dismissed\]/);
  assert.match(text, /^permissions: \{\}$/m);
  assert.match(text, /^ {6}- run: echo "有新评审,触发 aiwork-gate 重算"$/m);
  const run = text.split(/^ {6}- run: /m).slice(1).join("\n");
  assert.doesNotMatch(run, /\$\{\{/);
});

test("aiwork 自己的策略：只报不拦，不登记共用的 build 账号，罩住密钥、发布和判卷面", () => {
  const policy = JSON.parse(read(".aiwork/policy.json"));
  validatePolicy(policy);
  assert.equal(policy.check_name, "aiwork-gate-shadow");
  assert.equal(policy.builders["aiwork-build[bot]"], undefined);
  assert.equal(policy.builders.SunJ1ayuBoT, "anthropic");
  for (const path of [
    ".github/workflows/ci.yml",
    ".aiwork/policy.json",
    "gate/main.mjs",
    "REVIEW-RULES.md",
    "AGENTS.md",
    "CLAUDE.md",
    "workflow/CLAUDE.md",
    "bin/rust-check-review-tooling",
    "tests/_no-egress.sh",
    "tests/_no_egress.py",
    "templates/aiwork-gate.yml",
    "templates/aiwork-review-ping.yml",
  ]) {
    assert.equal(matchAny(policy.judging_surface, path), true, path);
  }
  for (const path of [
    "bin/gh-app-token",
    "bin/privacy-check",
    "bin/_secret-shapes",
    "bin/_secret_shapes.py",
    "bin/review-pr",
  ]) {
    assert.equal(matchAny(policy.high, path), true, path);
  }
});

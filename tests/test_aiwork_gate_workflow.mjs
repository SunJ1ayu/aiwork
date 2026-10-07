// 项目接入关卡只有一种方式：.aiwork/policy.json，加上与 templates/ 相同的两份 workflow。
// 跑法:node --test tests/test_aiwork_gate_workflow.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { matchAny } from "../gate/decide.mjs";
import { validatePolicy } from "../gate/run.mjs";

const ROOT = new URL("../", import.meta.url);
const read = (path) => readFileSync(new URL(path, ROOT), "utf8");
const exists = (path) => existsSync(new URL(path, ROOT));
const policy = () => JSON.parse(read(".aiwork/policy.json"));

// 判卷面不靠手抄：CI 实际跑的总入口、各套件 source/exec/import 拉进来的公共文件，从仓库走出来。
// 公共 = 至少两条套件的依赖链都会碰到，且本身不是套件入口。改这些文件能让多套判据一起空跑报绿。
function ciFramework() {
  const runners = [...new Set([...read(".github/workflows/ci.yml").matchAll(/\b(bin\/[A-Za-z0-9_.-]+)/g)].map((m) => m[1]))].filter(exists);
  assert.deepEqual(runners, ["bin/rust-check-review-tooling"]);
  const suites = [...read(runners[0]).matchAll(/\$ROOT\/(tests\/[^"|\s]+)/g)].map((m) => m[1]);
  assert.ok(suites.length >= 2 && suites.every(exists), "总跑清单里要有真实套件");
  const suiteSet = new Set(suites);
  const reachedBy = new Map();
  for (const suite of suites) {
    const seen = new Set();
    const queue = [suite];
    while (queue.length) {
      const current = queue.pop();
      if (seen.has(current)) continue;
      seen.add(current);
      for (const next of edges(current)) if (!seen.has(next)) queue.push(next);
    }
    for (const file of seen) {
      if (suiteSet.has(file)) continue;
      if (!reachedBy.has(file)) reachedBy.set(file, new Set());
      reachedBy.get(file).add(suite);
    }
  }
  const common = [...reachedBy.entries()].filter(([, suites]) => suites.size >= 2).map(([file]) => file).sort();
  assert.ok(common.includes("tests/_test_settings.py"), "量具:bash 守卫 exec、python 守卫 import 都会走到 tests/_test_settings.py");
  assert.ok(common.includes("tests/_no-egress.sh") && common.includes("tests/_no_egress.py"));
  return common;
}

function edges(path) {
  const text = read(path);
  return path.endsWith(".py") ? pythonEdges(text) : shellEdges(text, path);
}

function shellEdges(text, fromPath) {
  const found = new Set();
  const dir = fromPath.includes("/") ? fromPath.replace(/[^/]+$/, "") : "";
  for (const line of text.split("\n")) {
    if (!/^\s*(?:\.|source)\s+/.test(line)) continue;
    for (const match of line.matchAll(/(?:tests|bin)\/[A-Za-z0-9_./-]+\.sh/g)) found.add(match[0]);
    const base = line.match(/([A-Za-z0-9_.-]+\.sh)/);
    if (base && exists(dir + base[1])) found.add(dir + base[1]);
  }
  const assigned = new Map();
  for (const match of text.matchAll(/^([A-Za-z_][A-Za-z0-9_]*)=.*\/([A-Za-z0-9_.-]+\.(?:py|sh))/gm)) {
    if (exists(dir + match[2])) assigned.set(match[1], dir + match[2]);
  }
  for (const match of text.matchAll(/\bexec\s+[^\n]*\$\{?([A-Za-z_][A-Za-z0-9_]*)/g)) {
    if (assigned.has(match[1])) found.add(assigned.get(match[1]));
  }
  return [...found];
}

function pythonEdges(text) {
  const found = new Set();
  for (const match of text.matchAll(/^(?:import|from)\s+([A-Za-z_][A-Za-z0-9_]*)/gm)) {
    for (const prefix of ["tests/", "bin/"]) {
      const path = `${prefix}${match[1]}.py`;
      if (exists(path)) found.add(path);
    }
  }
  return [...found];
}

// high 同样不手列:bin 里真正碰私钥、令牌、git push、gh release 的文件。
const HIGH_RE = new RegExp([
  /PRIVATE KEY/.source,
  /openssl [^\n]*\s-sign\b/.source,
  /\bapp[-_]key\b/.source,
  /\/access_tokens\b/.source,
  /\bGH_TOKEN\s*=/.source,
  /\bload_shapes\b/.source,
  /\bgit push\b/.source,
  /\bgh release\b/.source,
].join("|"));

function highFiles() {
  const found = readdirSync(new URL("bin/", ROOT), { withFileTypes: true })
    .filter((entry) => entry.isFile() && !entry.name.endsWith(".pyc"))
    .map((entry) => `bin/${entry.name}`)
    .filter((path) => HIGH_RE.test(read(path)));
  for (const path of ["bin/gh-app-token", "bin/_secret-shapes", "bin/_secret_shapes.py", "bin/privacy-check", "bin/review-pr", "bin/aiwork-config", "bin/_aiwork_config.py"]) {
    assert.ok(found.includes(path), `量具:扫得到 ${path}`);
  }
  for (const path of ["bin/submimo", "bin/panel-review", "bin/_review_result.py", "bin/rust-check-review-tooling"]) {
    assert.ok(!found.includes(path), `对照:${path} 只在字面上碰到这些词,不算`);
  }
  assert.equal(HIGH_RE.test("git push origin HEAD"), true);
  assert.equal(HIGH_RE.test("gh release create v1"), true);
  assert.equal(HIGH_RE.test("模型发布当天"), false);
  return found;
}

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

test("CI 实际依赖的公共框架文件都在判卷面", () => {
  const current = policy();
  const missing = ciFramework().filter((path) => !matchAny(current.judging_surface, path));
  assert.deepEqual(missing, [], `这些框架文件改了不用业主批准:${missing.join("、")}`);
});

test("决定评审归属和家族的代码在判卷面或 high", () => {
  const current = policy();
  const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: new URL(".", ROOT) })
    .toString("utf8")
    .split("\0")
    .filter((path) => path && exists(path) && statSync(new URL(path, ROOT)).isFile());
  const files = tracked.filter((path) => /^ADAPTER_IDENTITIES\s*=/m.test(read(path)));
  assert.deepEqual(files, ["bin/_review_result.py"]);
  const missing = files.filter((path) => !matchAny(current.judging_surface, path) && !matchAny(current.high, path));
  assert.deepEqual(missing, [], `改家族登记表不用业主批准:${missing.join("、")}`);
});

test("high 清单从 bin 里碰私钥、令牌、推送、发布的文件推出来", () => {
  const current = policy();
  const missing = highFiles().filter((path) => !matchAny(current.high, path));
  assert.deepEqual(missing, [], `这些文件改了只要一家 PASS:${missing.join("、")}`);
});

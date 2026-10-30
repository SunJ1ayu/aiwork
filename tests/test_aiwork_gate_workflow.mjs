// 项目接入关卡只有一种方式：.aiwork/policy.json，加上与 templates/ 相同的两份 workflow。
// 跑法:node --test tests/test_aiwork_gate_workflow.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { globToRegExp, matchAny } from "../gate/decide.mjs";
import { FUSE_CHECK_NAME, validatePolicy } from "../gate/run.mjs";

const ROOT = new URL("../", import.meta.url);
const read = (path) => readFileSync(new URL(path, ROOT), "utf8");
const exists = (path) => existsSync(new URL(path, ROOT));
const policy = () => JSON.parse(read(".aiwork/policy.json"));

// 从 CI 总跑入口、tests/_* 和已保护的 bin 文件追踪框架依赖；
// 普通套件不作为入口，传给框架执行的被测命令也不展开。
// tests/ 里其余文件只能是总跑登记的套件、套件用 node --test 点名要跑的判据、fixtures/、mutation-*.sh。
function tracked(prefix) {
  return execFileSync("git", ["ls-files", "-z", "--", prefix], { cwd: new URL(".", ROOT) })
    .toString("utf8")
    .split("\0")
    .filter(Boolean);
}

function ciRunners() {
  const runners = [...new Set([...read(".github/workflows/ci.yml").matchAll(/\b(bin\/[A-Za-z0-9_.-]+)/g)].map((m) => m[1]))].filter(exists);
  assert.deepEqual(runners, ["bin/rust-check-review-tooling"]);
  return runners;
}

function ciSuites() {
  const runners = ciRunners();
  const suites = [...read(runners[0]).matchAll(/\$ROOT\/(tests\/[^"|\s]+)/g)].map((m) => m[1]);
  assert.ok(suites.length >= 2 && suites.every(exists), "总跑清单里要有真实套件");
  return suites;
}

function suiteExamFiles(suites) {
  const files = tracked("tests");
  const owned = new Set();
  for (const suite of suites) {
    for (const line of read(suite).split("\n")) {
      if (/^\s*#/.test(line) || !line.includes("node --test")) continue;
      for (const match of line.matchAll(/tests\/[A-Za-z0-9_.*?-]+/g)) {
        const re = globToRegExp(match[0]);
        for (const file of files) if (re.test(file)) owned.add(file);
      }
    }
  }
  return owned;
}

function judgingFramework() {
  const suites = new Set(ciSuites());
  const exam = suiteExamFiles([...suites]);
  const framework = [];
  const violations = [];
  for (const file of tracked("tests")) {
    if (suites.has(file) || exam.has(file) || file.startsWith("tests/fixtures/")) continue;
    if (/^tests\/mutation-[^/]+\.sh$/.test(file)) continue;
    if (/^tests\/_[^/]+$/.test(file)) {
      framework.push(file);
      continue;
    }
    violations.push(file);
  }
  assert.deepEqual(violations, [], `tests/ 里这些文件既不是套件也不是 tests/_* 框架:${violations.join("、")}`);
  for (const path of [
    "tests/_no-egress.sh",
    "tests/_no_egress.py",
    "tests/_test_settings.py",
  ]) {
    assert.ok(framework.includes(path), `量具:框架里有 ${path}`);
  }
  assert.ok(exam.has("tests/test_aiwork_gate.mjs"), "量具:总跑套件点名的判据文件不算框架");
  return framework.sort();
}

function frameworkRoots(current = policy()) {
  return [...new Set([
    ...judgingFramework(), ...ciRunners(),
    ...tracked("bin").filter((path) => matchAny(current.judging_surface, path)),
  ])].sort();
}

function sameDirectoryCalls(file, code) {
  const found = [];
  // Shell/Python shared launchers spell exec as """exec". A command or
  // source operand is an edge; an array, diagnostic or fixture string is not.
  const calls = /^\s*(?:(?:"""exec"|exec|source|\.)\s+)?(["'])(\$\([^\n]+?\)|\$(?:\{(?:BIN|BIN_DIR)\}|(?:BIN|BIN_DIR)))\/([A-Za-z0-9_.-]+)\1(?=\s|$)/gm;
  for (const match of code.matchAll(calls)) {
    const directory = match[2];
    if (directory.startsWith("$(") &&
        (!/\bdirname\b/.test(directory) || !/\$0|\$\{?BASH_SOURCE/.test(directory) ||
         [...directory.matchAll(/\bdirname\b/g)].length !== 1)) continue;
    found.push(file.slice(0, file.lastIndexOf("/") + 1) + match[3]);
  }
  return found;
}

function binCalledByFramework(framework, readSource = read) {
  const found = new Set();
  const visited = new Set(framework);
  const pending = [...framework];
  for (const file of pending) {
    const code = readSource(file).replace(/#.*$/gm, "");
    const references = [
      ...[...code.matchAll(/\bbin\/[A-Za-z0-9_.-]+/g)].map((match) => match[0]),
      ...sameDirectoryCalls(file, code),
    ];
    for (const path of references) {
      if (!exists(path) || !statSync(new URL(path, ROOT)).isFile()) continue;
      if (path.startsWith("bin/")) found.add(path);
      if (!visited.has(path)) {
        visited.add(path);
        pending.push(path);
      }
    }
  }
  return [...found].sort();
}

// high 同样不手列:bin 里真正碰私钥、令牌、git push、gh release 的文件。
const HIGH_RE = new RegExp([
  /PRIVATE KEY/.source,
  /openssl [^\n]*\s-sign\b/.source,
  /\bapp[-_]key\b/.source,
  /\/access_tokens\b/.source,
  /\bGH_TOKEN\s*=/.source,
  /\bGIT_ASKPASS\s*=/.source,
  /\bload_shapes\b/.source,
  /\bgit push\b/.source,
  /\bgh release\b/.source,
].join("|"));

function highFiles() {
  const found = tracked("bin").filter((path) => !path.endsWith(".pyc") && HIGH_RE.test(read(path)));
  for (const path of ["bin/gh-app-token", "bin/_secret-shapes", "bin/_secret_shapes.py", "bin/privacy-check", "bin/review-pr", "bin/aiwork-config", "bin/_aiwork_config.py"]) {
    assert.ok(found.includes(path), `量具:扫得到 ${path}`);
  }
  for (const path of ["bin/submimo", "bin/subkimi", "bin/_review_result.py", "bin/rust-check-review-tooling"]) {
    assert.ok(!found.includes(path), `对照:${path} 只在字面上碰到这些词,不算`);
  }
  assert.equal(HIGH_RE.test("git push origin HEAD"), true);
  assert.equal(HIGH_RE.test("gh release create v1"), true);
  assert.equal(HIGH_RE.test("GIT_ASKPASS=helper"), true);
  assert.equal(HIGH_RE.test("GIT_ASKPASS"), false);
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
  assert.deepEqual(text.match(/^permissions:\n((?: {2}[^\n]+\n)+)/m)?.[1].trim().split("\n").map((line) => line.trim()).sort(), [
    "actions: read", "checks: write", "contents: read", "issues: read", "pull-requests: read",
  ], "检查式保险丝只留所需权限，不再授权旧 status 写入");
  assert.ok(read("gate/README.md").includes(`check run \`${FUSE_CHECK_NAME}\``), "文档里的新保险丝名称要与实现一致");
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

test("关卡代码更新有定时门铃，间隔与文档一致，定时事件不被过滤", () => {
  const text = read("templates/aiwork-gate.yml");
  const cron = text.match(/^  schedule:\n    - cron: ['"]([^'"]+)['"]$/m)?.[1];
  assert.ok(cron, "不能只靠调用方事件等待关卡代码更新");
  const [minutes, ...rest] = cron.split(/\s+/);
  assert.deepEqual(rest, ["*", "*", "*", "*"], "每天每小时都要重算");
  const ticks = minutes.split(",").map(Number);
  assert.ok(ticks.length > 1 && ticks.every((n, i) => Number.isInteger(n) && n > 0 && n < 60 && (!i || n > ticks[i - 1])),
    "避开整点，分钟必须有序且不重复");
  const maxGap = Math.max(...ticks.map((n, i) => (ticks[(i + 1) % ticks.length] + (i === ticks.length - 1 ? 60 : 0)) - n));
  assert.ok(maxGap <= 15, "关卡代码变化后的计划等待不得超过 15 分钟");
  const row = read("gate/README.md").split("\n").find((line) => line.startsWith("| 关卡代码"));
  assert.ok(row, "门铃表要包含关卡代码本身");
  assert.equal(Number(row.match(/计划间隔 (\d+) 分钟/)?.[1]), maxGap, "文档不能另维护一个间隔");
  const readme = read("gate/README.md");
  const limit = Number(readme.match(/每仓库每小时 (\d+) 次/)?.[1]);
  const sample = Number(readme.match(/P=H=(\d+) 时 REST\/小时/)?.[1]);
  assert.ok(limit > 0 && sample > 0, "开销表要给出额度与示例规模");
  const perHour = ticks.length;
  const perDay = 24 * perHour;
  const eventExhaustion = Math.floor((limit / (perHour + 1) - 2) / 8) + 1;
  const scheduleExhaustion = Math.ceil((limit / perHour - 2) / 8);
  assert.equal(readme.split("\n").find((line) => line.startsWith("| 当前 cron |")),
    `| 当前 cron | ${perHour} | ${perDay} | ${perHour * (2 + 8 * sample)} | ${2 * perDay} | ${perDay} | ${eventExhaustion} | ${scheduleExhaustion} |`,
    "频率、用量和额度阈值都必须从模板 cron 推出，不能只改门铃间隔");
  assert.match(row, /延迟|丢弃/);
  assert.match(read("gate/README.md"), /60 天/);
  assert.doesNotMatch(text.split(/^jobs:/m)[1], /^\s+if:/m, "定时触发必须走完整关卡，不能依赖 PR 事件字段过滤");
});

test("aiwork 自己的策略：真拦截，不登记共用的 build 账号，罩住密钥、发布和判卷面", () => {
  const policy = JSON.parse(read(".aiwork/policy.json"));
  validatePolicy(policy);
  assert.equal(policy.check_name, "aiwork-gate");
  assert.equal(policy.builders["aiwork-build[bot]"], undefined);
  assert.equal(policy.modification_rounds.summary_account, "SunJ1ayuBoT");
  assert.equal(Object.hasOwn(policy.builders, policy.modification_rounds.summary_account), false);
  assert.equal(policy.high_min_families, 3);
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

test("关卡自己的测试在判卷面", () => {
  const current = policy();
  const gateTests = tracked("tests").filter((path) =>
    /^tests\/test_aiwork_gate[^/]*\.mjs$/.test(path) || path === "tests/test-aiwork-gate.sh");
  for (const path of [
    "tests/test_aiwork_gate.mjs",
    "tests/test_aiwork_gate_workflow.mjs",
    "tests/test_aiwork_gate_run.mjs",
    "tests/test_aiwork_gate_main.mjs",
    "tests/test-aiwork-gate.sh",
  ]) {
    assert.ok(gateTests.includes(path), path);
  }
  const missing = gateTests.filter((path) => !matchAny(current.judging_surface, path));
  assert.deepEqual(missing, [], `关卡自己的测试改了不用业主批准:${missing.join("、")}`);
  assert.equal(matchAny(current.judging_surface, "tests/test_review_pr.py"), false, "普通测试文件不算判卷面");
});

test("判卷框架及 CI 总跑入口调用的工具都在判卷面", (t) => {
  const current = policy();
  const roots = frameworkRoots(current);
  const required = [...roots, ...binCalledByFramework(roots)];
  t.diagnostic(`框架依赖:${[...new Set(required)].sort().join("、")}`);
  const missing = required.filter((path) => !matchAny(current.judging_surface, path));
  assert.deepEqual(missing, [], `这些框架文件改了不用业主批准:${missing.join("、")}`);
  assert.equal(matchAny(current.judging_surface, "tests/_future_harness.sh"), true, "tests/_* 是一条 glob，新框架文件也要罩住");
  assert.equal(matchAny(current.judging_surface, "tests/test_foo.py"), false, "普通测试文件不算判卷面");
  assert.equal(matchAny(current.judging_surface, "bin/subcodex"), false, "被测代码不进判卷面");
});

test("框架调用推导沿启动链找到解释器辅助，不纳入普通套件的被测代码", () => {
  const called = binCalledByFramework(frameworkRoots());
  for (const path of ["bin/_python", "bin/_programs.sh"]) {
    assert.ok(called.includes(path), `启动链必须推导到 ${path}`);
  }
  assert.equal(called.includes("bin/subcodex"), false, "套件调用的被测代码不是框架依赖");
});

test("同目录调用按执行位置追踪，递归遇环终止，不把命令数组当作已执行", () => {
  const sources = new Map([
    ["bin/aiwork-timeout", '"""exec" "$(dirname "$(realpath "$0")")/_python" "$0" "$@"\n' +
      'COMMAND=("$BIN/subcodex" "$@")\n# exec "$BIN/subcodex"\n'],
    ["bin/_python", 'source "${BIN_DIR}/_programs.sh"\n'],
    ["bin/_programs.sh", '. "$BIN/_python"\n'],
  ]);
  assert.deepEqual(binCalledByFramework(["bin/aiwork-timeout"], (file) => sources.get(file)),
    ["bin/_programs.sh", "bin/_python"]);
  assert.deepEqual(sameDirectoryCalls("bin/_python", 'exec "$BIN_DIR/_programs.sh"\n'),
    ["bin/_programs.sh"]);
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

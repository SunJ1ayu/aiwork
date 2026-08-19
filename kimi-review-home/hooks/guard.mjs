// Review-only guard for kimi-code PreToolUse. Default-DENY: anything not
// explicitly allowed is blocked, so new/unknown tools fail closed. The hook
// protocol is fail-open on non-2 exits, so every error path must end in exit 2.
import { readFileSync } from "node:fs";

function deny(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      permissionDecision: "deny",
      permissionDecisionReason: `[review-only sandbox] ${reason}`,
    },
  }));
  process.exit(2);
}

try {
  const ev = JSON.parse(readFileSync(0, "utf8"));
  const tool = ev.tool_name ?? "";

  const ALLOW = new Set([
    "Read", "ReadMediaFile", "Glob", "Grep",
    "TodoList", "TaskList", "TaskOutput", "TaskStop",
    "EnterPlanMode", "ExitPlanMode",
    "CreateGoal", "GetGoal", "UpdateGoal", "SetGoalBudget",
    "AskUserQuestion",
  ]);

  if (ALLOW.has(tool)) process.exit(0);

  if (tool === "Bash") {
    const cmd = String(ev.tool_input?.command ?? "").trim();
    // 这一格 08-18 收紧成"一律拒绝"、08-19 又放回白名单。两次的账都留着:
    //
    // **事实(仍然成立)**:这个白名单挡不住 git 自己的参数。实测:
    //   `git diff --output=pwned.txt HEAD`         → 放行,而它往仓里写出文件
    //   `git diff --no-index <仓外文件> /dev/null`  → 放行,而它把仓外文件打进 stdout
    // 两条都不含元字符、又匹配 ^git\s+diff,所以"禁元字符"对它们毫无作用。
    //
    // **08-18 我从这个事实推出"所以 Bash 一律拒绝",错的是这一步。**
    // 关掉之后腿读不了 git ⇒ 主 agent 得算好 diff 喂进提示词 ⇒ 那条链上长出
    // E2BIG(这条腿 rc=126 直接起不来)、SIGPIPE 静默暴毙、基线打错字静默变瞎,
    // 最坏形态是**腿根本没跑起来而 panel 照常出结论**——比腿写个文件危险得多。
    // 而评审腿**没有**"改判据让自己及格"的动机(那是执行腿的威胁模型)。
    //
    // **所以现在这道白名单的定位变了:它挡误伤,不挡对手。**
    // 挡得住的:rm、重定向、命令链、非 git 命令 —— 误伤的典型形态就长这样。
    // 挡不住的:上面那两条 git 参数。它们的防线是**跑完的写审计**
    // (track repo-write-audit,**还没上线**,窗口期是写下来的明账)。
    // 别再试图往这里加参数黑名单:对 git 这么灵活的程序做命令行白名单本身不成立,
    // 加了只会造出"这里安全了"的错觉。
    if (/[;&|><`$(){}\[\]\n]/.test(cmd)) {
      deny(`shell metacharacters are not permitted in review mode: ${cmd}`);
    }
    if (!/^git\s+(diff|log|show|status|blame|shortlog|rev-parse|ls-files|describe)\b/.test(cmd)) {
      deny(`only read-only git is permitted in review mode: ${cmd}`);
    }
    process.exit(0);
  }

  deny(`tool '${tool}' is not permitted in review mode`);
} catch (e) {
  deny(`guard error (fail closed): ${e?.message ?? e}`);
}

// Review-only guard for kimi-code PreToolUse. Default-DENY: anything not
// explicitly allowed is blocked, so new/unknown tools fail closed. The hook
// protocol is fail-open on non-2 exits, so every error path must end in exit 2.
import { readFileSync } from "node:fs";

function deny(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      permissionDecision: "deny",
      permissionDecisionReason: `[read-only sandbox] ${reason}`,
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
    // Bash runs inside a disposable writable clone. The original repository is
    // separately mounted read-only by the wrapper, so command-string filtering
    // is no longer treated as an isolation boundary. Tests/builds may write
    // caches and outputs in the clone.
    process.exit(0);
  }

  deny(`tool '${tool}' is not permitted in review mode`);
} catch (e) {
  deny(`guard error (fail closed): ${e?.message ?? e}`);
}

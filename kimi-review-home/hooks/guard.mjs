// Review-only guard for kimi-code PreToolUse. Default-DENY: anything not
// explicitly allowed is blocked, so new/unknown tools fail closed. The hook
// protocol is fail-open on non-2 exits, so every error path must end in exit 2.
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

function deny(reason) {
  const message = `[review-only sandbox] ${process.env.AIWORK_KIMI_GUARD_PROBE_TAG ?? ""} ${reason}`;
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      permissionDecision: "deny",
      permissionDecisionReason: message,
    },
  }));
  process.stderr.write(message + "\n");
  process.exit(2);
}

try {
  const command = JSON.parse(process.env.AIWORK_KIMI_READER_GUARD ?? "null");
  if (!Array.isArray(command) || command.length !== 4 ||
      command.some((value) => typeof value !== "string" || !value)) {
    deny("reader policy command is unavailable");
  }
  // subkimi supplies the trusted interpreter, shared policy and snapshot root.
  // The profile, hook and post-run audit use the same Python reader policy.
  const result = spawnSync(command[0], command.slice(1), {
    input: readFileSync(0, "utf8"),
    encoding: "utf8",
    timeout: 9000,
  });
  if (!result.error && result.status === 0) process.exit(0);
  deny("tool or path is not permitted, or reader policy failed");
} catch (e) {
  deny(`guard error (fail closed): ${e?.message ?? e}`);
}

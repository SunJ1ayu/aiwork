#!/usr/bin/env bash
# 唯一规范源 + 部署副本判据(workflow-control-plane T7)。
# Run: bash /root/aiwork/tests/test-workflow-docs.sh
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/workflow"
SYNC="$ROOT/bin/sync-workflow-docs"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

workflow_mappings() {
  local skill name
  printf '%s\n' 'CLAUDE.md|CLAUDE.md'
  for skill in "$SOURCE"/skills/*/SKILL.md; do
    [[ -f "$skill" ]] || continue
    name="$(basename "$(dirname "$skill")")"
    printf '%s\n' "skills/${name}/SKILL.md|.claude/skills/${name}/SKILL.md"
  done
}
mapfile -t MAPPINGS < <(workflow_mappings)

echo "=== workflow docs oracle ==="
# 家目录里那份部署副本是本机状态。同步器对临时目录的行为由下面 W2 问;
# 这台机器的副本是否跟上,不在仓库判据里。

echo "[W2] 同步器按 workflow/skills/*/SKILL.md 推导 skill，漂移默认拒绝、显式 force 才覆盖"
if [[ -x "$SYNC" ]]; then
  d="$(mktemp -d)"; outside="$(mktemp)"
  mkdir -p "$d/.claude/skills/track"
  printf 'retired deployed skill: cleanup after merge\n' > "$d/.claude/skills/track/SKILL.md"
  printf 'outside\n' > "$outside"
  "$SYNC" --target-root "$d" --check >/dev/null 2>&1; rc=$?
  check "W2: 空部署根 --check 必须报漂移" $([[ $rc -ne 0 ]]; echo $?)

  "$SYNC" --target-root "$d" >/dev/null 2>&1; rc=$?
  check "W2: 缺失的受管文件可安全首次安装" $([[ $rc -eq 0 ]]; echo $?)
  for spec in "${MAPPINGS[@]}"; do
    src="${spec%%|*}"; dst="${spec#*|}"
    cmp -s "$SOURCE/$src" "$d/$dst" || rc=1
  done
  check "W2: 首次安装后所有受管文件逐字节一致" "$rc"

  mkdir -p "$d/.claude"; printf 'settings-sentinel\n' > "$d/.claude/settings.json"
  printf 'local-edit\n' >> "$d/CLAUDE.md"
  "$SYNC" --target-root "$d" >/dev/null 2>&1; rc=$?
  check "W2: 已有副本漂移时默认拒绝覆盖" $([[ $rc -ne 0 ]]; echo $?)
  grep -q 'local-edit' "$d/CLAUDE.md"
  check "W2: 拒绝后现场改动仍在" $?

  "$SYNC" --target-root "$d" --force >/dev/null 2>&1; rc=$?
  check "W2: 显式 --force 才更新已漂移受管文件" $([[ $rc -eq 0 ]]; echo $?)
  cmp -s "$SOURCE/CLAUDE.md" "$d/CLAUDE.md"
  check "W2: force 后回到唯一源字节" $?
  grep -qx 'settings-sentinel' "$d/.claude/settings.json"
  check "W2: settings 等非清单现场零触碰" $?
  grep -qx 'retired deployed skill: cleanup after merge' "$d/.claude/skills/track/SKILL.md"
  check "W2: 退役 track 部署副本留给合并后清理，同步器不删除它" $?
  "$SYNC" --target-root "$d" --check >/dev/null 2>&1; rc=$?
  check "W2: 同步后的 --check 通过" $([[ $rc -eq 0 ]]; echo $?)

  rm -f "$d/CLAUDE.md"; ln -s "$outside" "$d/CLAUDE.md"
  "$SYNC" --target-root "$d" --force >/dev/null 2>&1; rc=$?
  check "W2: 受管目标是符号链接时即使 force 也拒绝" $([[ $rc -ne 0 ]]; echo $?)
  grep -qx 'outside' "$outside"
  check "W2: 不会沿链接覆盖清单外文件" $?
  rm -rf "$d"; rm -f "$outside"
else
  bad "W2: bin/sync-workflow-docs 存在且可执行"
fi

echo "[W3] 流程规则只有一个来源:说明文档指向 REVIEW-RULES.md,且没有任何文档要求自定风险等级或评审预算"
shopt -s nullglob
docs=("$ROOT/README.md" "$SOURCE/CLAUDE.md" "$SOURCE"/skills/*/SKILL.md "$SOURCE"/skills/*/references/*.md)
shopt -u nullglob
for f in "${docs[@]}"; do
  [[ -f "$f" ]] || continue
  grep -q 'REVIEW-RULES.md' "$f"
  check "W3: ${f#$ROOT/} 指向 REVIEW-RULES.md" $?
done
for f in "${docs[@]}"; do
  [[ -f "$f" ]] || continue
  ! grep -qE 'impact-risk|design-uncertainty|--risk |self/standard/high|self=0|standard=1|high=2|评审预算|decision\.json|lane:|必须挂.*track|--track NAME' "$f"
  check "W3: ${f#$ROOT/} 没有自定风险等级/评审预算的旧流程" $?
done
[[ ! -e "$SOURCE/skills/track/SKILL.md" ]] && ! grep -q 'skills/track' "$ROOT/bin/sync-workflow-docs"
check "W3: track skill 已退役,且不在 sync-workflow-docs 清单里" $?
echo "[W3] 留下的通道：文档与实现读同一份本机模型设置"
grep -q 'subdeepseek-agent' "$ROOT/README.md" \
  && grep -q 'subkimi' "$ROOT/README.md" \
  && grep -q 'submimo' "$ROOT/README.md" \
  && grep -q 'subcursor' "$ROOT/README.md" \
  && grep -q 'subcodex' "$ROOT/README.md"
check "W3: README 列出留下的五条评审命令" $?
grep -q 'Codex、Cursor、DeepSeek、Kimi、MiMo' "$SOURCE/CLAUDE.md" \
  && grep -q '每个通道都能写代码也能评审；同一个 PR 的评审要换一家，由关卡判断' "$SOURCE/CLAUDE.md"
check "W3: 主工作流只列留下的五家，并写明换评审由关卡判断" $?
grep -q 'DEFAULT_MAX_TURNS=200' "$ROOT/bin/subagent" \
  && bash "$ROOT/bin/subagent" -h 2>&1 | grep -q 'default ~/.config/deepseek/auth.json'
check "W3: DeepSeek 默认轮次是 200，帮助文本指向本机凭证" $?
grep -q 'KIMI_TIMEOUT:-1500' "$ROOT/bin/subkimi"
check "W3: Kimi 超时默认 1500 秒" $?
grep -q 'aiwork-config.*model mimo' "$ROOT/bin/submimo" \
  && ! grep -q 'DEFAULT_MODEL="xiaomi/' "$ROOT/bin/submimo"
check "W3: MiMo 默认模型来自本机设置，代码不复制版本号" $?
! grep -q 'skills/panel' "$ROOT/bin/sync-workflow-docs"
check "W3: 同步清单不再部署已删除的方案说明" $?

echo "[W4] 操作流程与保留的方法"
grep -q '最新 main' "$SOURCE/CLAUDE.md" \
  && grep -q 'tests/' "$SOURCE/CLAUDE.md" \
  && grep -q '机器人' "$SOURCE/CLAUDE.md" \
  && grep -q '停下' "$SOURCE/CLAUDE.md"
check "W4: 任务通过分支、实现、全测、机器人 PR 收尾" $?
grep -q '另一家族' "$SOURCE/CLAUDE.md" \
  && grep -q 'review-pr.*沙箱外' "$SOURCE/CLAUDE.md" \
  && grep -q 'review-pr' "$SOURCE/CLAUDE.md"
check "W4: 正式评审在 PR 上使用沙箱外 review-pr" $?
grep -q '不改考卷让自己及格' "$SOURCE/CLAUDE.md" \
  && grep -q '不信执行腿的自述' "$SOURCE/CLAUDE.md"
check "W4: 保留判据核实与收货方法" $?
grep -q -- '--receive' "$SOURCE/skills/delegate/SKILL.md" \
  && ! grep -q -- '--no-track' "$SOURCE/skills/delegate/SKILL.md" \
  && ! grep -q -- '--track' "$SOURCE/skills/delegate/SKILL.md"
check "W4: 委托保留隔离收货，不再挂 track" $?
grep -q '~/.config/aiwork/' "$SOURCE/CLAUDE.md" \
  && grep -q '~/.local/share/aiwork/' "$SOURCE/CLAUDE.md"
check "W4: 设置与运行数据的本机目录明确" $?
grep -q 'aiwork-config data-path worktrees' "$SOURCE/CLAUDE.md" \
  && grep -q '不在共享检出' "$SOURCE/CLAUDE.md" \
  && grep -q 'PR 合并后删掉这个工作树' "$SOURCE/CLAUDE.md"
check "W4: 开工先在本机数据目录建工作树，不在共享检出里改" $?

echo "[W5] 旧 track 流程不留在仓库里"
for gone in bin/track bin/track-guard bin/track-record bin/track-commit-msg \
            bin/runlog bin/_evidence.sh bin/_review_delivery.py bin/_ephemeral-refs.sh \
            track tracks WORKFLOW-DEBT.md WORKFLOW-MIGRATION-PLAN.md workflow-migration \
            tests/test-track-guard.sh tests/test-track-record.sh tests/test-track-links.sh \
            tests/test_track_preflight.py tests/test-ledger.sh tests/test-runlog.sh \
            tests/test_review_delivery.py tests/mutation-review-delivery.sh \
            tests/test-panel-round-discipline.sh tests/test-delegate-observation.sh \
            tests/test-worktree-sweep.sh tests/test-evidence-lifetime.sh; do
  [[ ! -e "$ROOT/$gone" ]]
  check "W5: 已删除 $gone" $?
done
! grep -q 'track-guard|bash' "$ROOT/bin/rust-check-review-tooling" \
  && ! grep -q 'track-record|bash' "$ROOT/bin/rust-check-review-tooling" \
  && ! grep -q 'runlog|bash' "$ROOT/bin/rust-check-review-tooling"
check "W5: 总跑不再登记 track / runlog 套件" $?
# 历史段只留一句指向，不复述过滤、归档仓库或提交个数。
hist="$(awk '/^## History/{flag=1;next} /^## /{flag=0} flag' "$ROOT/README.md")"
[[ "$(printf '%s\n' "$hist" | grep -cve '^[[:space:]]*$')" -eq 1 ]]
check "W5: README 历史部分只有一句" $?
printf '%s\n' "$hist" | grep -q 'git 历史' \
  && ! printf '%s\n' "$hist" | grep -q 'aiwork-archive' \
  && ! printf '%s\n' "$hist" | grep -q '639'
check "W5: 那一句指向 git 历史，不复述内容" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]

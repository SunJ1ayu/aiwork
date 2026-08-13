#!/usr/bin/env bash
# track evidence-lifetime-gate 的判据(主 agent 亲写)。
#
# 判的是:`track archive` 拒绝归档**引用了会话临时目录**的 track 工件 ——
# 除非那一行自带 `[仓外不承重]` 标记。规格在 tracks/evidence-lifetime-gate/design.md。
#
# 立足点:死链是「自述悄悄顶替工件」,而且**不报错** —— 句子还在、读起来正常,
# 只有真去查的那天才发现空了;临时目录被清是**不可逆**的。
#
# 锁死的假绿路线:
#   ① "报告说拒了"其实归档了 ⇒ 一律看**盘上目录在哪**,不看退出码也不看输出措辞。
#   ② 一句话打包放行(写个"我看过了"就全过)⇒ E6 造"甲行有标记乙行没有",要求仍然拒。
#   ③ helper 缺件时静默放行 ⇒ E9 把 helper 移走,要求 fail closed。
#   ④ 顺手把这条挪进 pre-commit,给活跃工作制造噪音 ⇒ E10 钉住"只在归档触发"。
#   ⑤ 误报(闸的死法):E5/E7 用不含引用的正常工件和真实收据行,要求一声不响。
#
# ⚠️ 断言顺序是刻意的:每一幕**第一条**断言都是「盘上目录在哪」这种行为断言,
#    不是「helper 存不存在」。否则红检只会红在"文件不存在"上 —— 那是浅红,
#    等于没红检过(2026-08-13 当天刚栽过一次)。
#
# Run:  bash /root/aiwork/tests/test-evidence-lifetime.sh
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退

BIN="${TRACK_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
MARK='[仓外不承重]'

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

# 一个能通过 track archive 既有那几道闸的项目仓(verify.md 有结论 + 零证据显式认账)
make_proj() {  # make_proj <dir> <track名>
  local p="$1" t="$2"
  mkdir -p "$p/tracks/$t"
  ( cd "$p"
    git init -q -b main; git config user.email t@t; git config user.name t
    printf 'x\n' > README.md
    cat > tracks/"$t"/verify.md <<'EOF'
# Verify: 判据夹具
- Verdict: PASS
- 无机器证据:这是判据里的临时仓,不跑真判据。
EOF
    git add -A; git commit -qm init )
}

archived_dir() { echo "$1/tracks/archive/$2"; }
active_dir()   { echo "$1/tracks/$2"; }

# ---------------------------------------------------------------- E1
e1_unmarked_scratchpad_refused() {
  echo "[E1] design.md 引 scratchpad/… 且无标记 ⇒ 拒绝归档"
  local d; d="$(mktemp -d)"; local p="$d/proj" rc
  make_proj "$p" t1
  cat > "$p/tracks/t1/design.md" <<'EOF'
# Design
- 规划双出: `scratchpad/dualplan/codex-plan.log`(外部腿的完整输出)
EOF
  ( cd "$p" && "$BIN/track" archive t1 "$p" ) >/dev/null 2>&1; rc=$?

  # 行为断言先开火:目录**不许**被搬走
  [[ ! -d "$(archived_dir "$p" t1)" ]]; check "没有归档成功(archive/ 下不该出现 t1)" $?
  [[ -d "$(active_dir "$p" t1)" ]];    check "原目录还在原地(不留半归档状态)" $?
  [[ "$rc" -ne 0 ]];                   check "退出码非零" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E2
e2_unmarked_tmp_refused() {
  echo "[E2] verify.md 引 /tmp/claude-0/… 且无标记 ⇒ 拒绝归档"
  local d; d="$(mktemp -d)"; local p="$d/proj" rc
  make_proj "$p" t2
  cat >> "$p/tracks/t2/verify.md" <<'EOF'
- 自审全文在 /tmp/claude-0/-root/abc-123/scratchpad/my-review.md
EOF
  ( cd "$p" && "$BIN/track" archive t2 "$p" ) >/dev/null 2>&1; rc=$?

  [[ ! -d "$(archived_dir "$p" t2)" ]]; check "没有归档成功" $?
  [[ -d "$(active_dir "$p" t2)" ]];    check "原目录还在原地" $?
  [[ "$rc" -ne 0 ]];                   check "退出码非零" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E3
e3_no_half_archived_state() {
  echo "[E3] 被拒之后,工件内容一字未动(不许出现半归档)"
  local d; d="$(mktemp -d)"; local p="$d/proj" before after
  make_proj "$p" t3
  printf '# Design\n- 见 scratchpad/probe.py\n' > "$p/tracks/t3/design.md"
  before="$(cat "$p/tracks/t3/design.md")"
  ( cd "$p" && "$BIN/track" archive t3 "$p" ) >/dev/null 2>&1
  after="$(cat "$p/tracks/t3/design.md" 2>/dev/null)"

  [[ "$before" == "$after" ]];          check "design.md 内容逐字未改" $?
  [[ ! -e "$p/tracks/archive/t3" ]];    check "archive/ 下连空壳都没建" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E4
e4_marked_line_passes() {
  echo "[E4] 同一行带 $MARK ⇒ 正常归档(放行方式生效)"
  local d; d="$(mktemp -d)"; local p="$d/proj" rc
  make_proj "$p" t4
  cat > "$p/tracks/t4/design.md" <<EOF
# Design
- 另一个会话在 /tmp/claude-0/xxx/wt-base 留了棵野树 $MARK
EOF
  ( cd "$p" && "$BIN/track" archive t4 "$p" ) >/dev/null 2>&1; rc=$?

  [[ -d "$(archived_dir "$p" t4)" ]];  check "归档成功" $?
  [[ "$rc" -eq 0 ]];                   check "退出码为零" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E5
e5_clean_track_passes() {
  echo "[E5] 不含临时目录引用的正常工件 ⇒ 一声不响地归档(防误报)"
  local d; d="$(mktemp -d)"; local p="$d/proj" rc out
  make_proj "$p" t5
  cat > "$p/tracks/t5/design.md" <<'EOF'
# Design
- 证据在 evidence/dualplan/codex-plan.log
- 实现落在 bin/track 的 archive 分支
EOF
  out="$( cd "$p" && "$BIN/track" archive t5 "$p" 2>&1 )"; rc=$?

  [[ -d "$(archived_dir "$p" t5)" ]];  check "归档成功" $?
  [[ "$rc" -eq 0 ]];                   check "退出码为零" $?
  ! grep -q "仓外不承重\|临时目录" <<< "$out"; check "没有多余告警(闸不许当噪音)" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E6
e6_marker_is_per_line() {
  echo "[E6] 甲行有标记、乙行没有 ⇒ 仍然拒绝,且只点名乙行(不许打包放行)"
  local d; d="$(mktemp -d)"; local p="$d/proj" out
  make_proj "$p" t6
  cat > "$p/tracks/t6/design.md" <<EOF
# Design
- 野树在 /tmp/claude-0/xxx/wt-base $MARK
- 规划双出全文见 scratchpad/brief-date.md
EOF
  out="$( cd "$p" && "$BIN/track" archive t6 "$p" 2>&1 )"

  [[ ! -d "$(archived_dir "$p" t6)" ]];        check "没有归档成功" $?
  grep -q "brief-date" <<< "$out";             check "点名了没标记的那一行" $?
  ! grep -q "wt-base" <<< "$out";              check "带标记的那一行不该被点名" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E7
e7_real_receipt_no_false_alarm() {
  echo "[E7] verify.md 里粘真实形状的收据行 ⇒ 不许因此报警(防误报)"
  local d; d="$(mktemp -d)"; local p="$d/proj" rc
  make_proj "$p" t7
  mkdir -p "$p/tracks/t7/evidence"
  local rl='runlog: green rc=0 commit=abc1234 dirty=no at=2026-08-13T03:26:05Z file=tracks/t7/evidence/20260813T032605Z-01-green.txt'
  printf '输出\n%s\n' "$rl" > "$p/tracks/t7/evidence/20260813T032605Z-01-green.txt"
  cat > "$p/tracks/t7/verify.md" <<EOF
# Verify: 判据夹具
- Verdict: PASS

\`\`\`
$rl
\`\`\`
EOF
  ( cd "$p" && "$BIN/track" archive t7 "$p" ) >/dev/null 2>&1; rc=$?

  [[ -d "$(archived_dir "$p" t7)" ]];  check "归档成功(收据行不该触发本闸)" $?
  [[ "$rc" -eq 0 ]];                   check "退出码为零" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E8
e8_message_names_file_and_line() {
  echo "[E8] 拒绝信息要可操作:含 文件:行号 与原文片段"
  local d; d="$(mktemp -d)"; local p="$d/proj" out
  make_proj "$p" t8
  printf '# Design\n\n\n- 全文在 scratchpad 的 my-review\n' > "$p/tracks/t8/design.md"
  out="$( cd "$p" && "$BIN/track" archive t8 "$p" 2>&1 )"

  grep -q "design.md:4" <<< "$out";      check "报出了 文件:行号(design.md:4)" $?
  grep -q "my-review" <<< "$out";        check "报出了原文片段" $?
  grep -q "仓外不承重" <<< "$out";       check "告诉了怎么放行(标记写法)" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E9
e9_fail_closed_without_helper() {
  echo "[E9] helper 缺件 ⇒ 拒绝归档(不许静默放行)"
  local d; d="$(mktemp -d)"; local p="$d/proj" fakebin rc
  make_proj "$p" t9
  printf '# Design\n- 见 scratchpad/x.log\n' > "$p/tracks/t9/design.md"
  # 造一份只缺 helper 的 bin/(track 本体和其它 helper 都在)
  fakebin="$d/bin"; mkdir -p "$fakebin"
  cp "$BIN"/* "$fakebin"/ 2>/dev/null
  rm -f "$fakebin/_ephemeral-refs.sh"
  ( cd "$p" && "$fakebin/track" archive t9 "$p" ) >/dev/null 2>&1; rc=$?

  [[ ! -d "$(archived_dir "$p" t9)" ]]; check "没有归档成功(fail closed)" $?
  [[ "$rc" -ne 0 ]];                    check "退出码非零" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E10
e10_archive_only_not_precommit() {
  echo "[E10] 只在归档触发:带未标记引用的 verify.md 照常提交得进去"
  local d; d="$(mktemp -d)"; local p="$d/proj" rc
  make_proj "$p" t10
  # 按**真实安装方式**装钩子:两行 wrapper exec 原路径。
  # (第一版这里 `cp` 了 track-guard 本体 ⇒ 它 source 同目录的 helper 时找不到、
  #  fail closed 拒绝提交,红检里表现为 E10 假红。夹具要照着真实装法造。)
  printf '#!/bin/sh\nexec %s\n' "$BIN/track-guard" > "$p/.git/hooks/pre-commit"
  chmod +x "$p/.git/hooks/pre-commit"
  cat >> "$p/tracks/t10/verify.md" <<'EOF'
- lane: self
- 派给: 主 agent
- 自审全文在 scratchpad/my-review.md
EOF
  ( cd "$p" && git add -A && git commit -qm "wip" ) >/dev/null 2>&1; rc=$?

  [[ "$rc" -eq 0 ]]; check "pre-commit 放行(干活期间引用 scratchpad 是正常的)" $?
  rm -rf "$d"
}

echo "=== test-evidence-lifetime ==="
e1_unmarked_scratchpad_refused
e2_unmarked_tmp_refused
e3_no_half_archived_state
e4_marked_line_passes
e5_clean_track_passes
e6_marker_is_per_line
e7_real_receipt_no_false_alarm
e8_message_names_file_and_line
e9_fail_closed_without_helper
e10_archive_only_not_precommit
echo "=== PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]]

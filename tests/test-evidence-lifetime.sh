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
#   ⑤ 误报(闸的死法):E5/E7 用不含引用的正常工件和真实收据正文,要求一声不响。
#   ⑥ 只扫 design/verify 两份 ⇒ E11 把引用放进 proposal.md 和嵌套子目录的 md。
#   ⑦ 只报第一条命中 ⇒ E6 摆两条未标记的,要求**两条都点名**。
#   ⑧ 标记只对 /tmp 生效、对 scratchpad 仍误拒 ⇒ E4 两种都摆一条带标记的。
#   ⑨ 扫的是整个 tracks/ 而不是本轮 ⇒ E5 旁边摆一个"脏"的兄弟 track,要求照常归档。
#
# 以上 ⑥⑦⑧⑨ 与 E7/E9 的重写,来自派活前的**攻题**(gpt-5.6-sol 只读攻这份考卷):
# 它指出原版里「把逻辑内联进 track、根本不建 helper」的实现能全绿(E9 不是单变量),
# 「只查 design+verify」能全绿,「只报第一条」能全绿。攻题记录在仓外。
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
  # 攻题指出:原版这行同时含 /tmp 和 scratchpad ⇒「完全不查 /tmp」也能全绿。
  # 单变量:这一幕只放 /tmp。
  cat >> "$p/tracks/t2/verify.md" <<'EOF'
- 基线数据在 /tmp/claude-0/-root/abc-123/due-baseline.txt
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
  # 攻题指出:只查 archive/t3 的话,「先 mkdir -p archive 再拒」看不出来
  [[ ! -d "$p/tracks/archive" ]];       check "archive/ 父目录也不该被提前建出来" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E4
e4_marked_line_passes() {
  echo "[E4] 同一行带 $MARK ⇒ 正常归档(放行方式生效)"
  local d; d="$(mktemp -d)"; local p="$d/proj" rc
  make_proj "$p" t4
  # 攻题指出:原版只摆了带标记的 /tmp ⇒「标记只对 /tmp 生效、对 scratchpad 仍误拒」
  # 也能全绿。两种命中各摆一条。
  cat > "$p/tracks/t4/design.md" <<EOF
# Design
- 另一个会话在 /tmp/claude-0/xxx/wt-base 留了棵野树 $MARK
- 早先的驱动脚本在 scratchpad/e2e_p6.py,当时没进仓 $MARK
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
  # 攻题指出:每个夹具只有一个 track ⇒「扫整个 tracks/ 而不是本轮」也能全绿。
  # 摆一个引用了临时目录的兄弟 track,它不该影响本轮归档。
  mkdir -p "$p/tracks/t5-sibling"
  printf '# Design\n- 见 scratchpad/other.log\n' > "$p/tracks/t5-sibling/design.md"
  out="$( cd "$p" && "$BIN/track" archive t5 "$p" 2>&1 )"; rc=$?

  [[ -d "$(archived_dir "$p" t5)" ]];  check "归档成功" $?
  [[ "$rc" -eq 0 ]];                   check "退出码为零" $?
  ! grep -q "仓外不承重\|临时目录" <<< "$out"; check "没有多余告警(闸不许当噪音)" $?
  ! grep -q "other.log" <<< "$out";    check "兄弟 track 的引用不该被扫进来" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E6
e6_marker_is_per_line() {
  echo "[E6] 甲行有标记、乙行没有 ⇒ 仍然拒绝,且只点名乙行(不许打包放行)"
  local d; d="$(mktemp -d)"; local p="$d/proj" out
  make_proj "$p" t6
  # 攻题指出:只有一条未标记时,「只报第一条命中就 return」也能全绿。摆两条。
  cat > "$p/tracks/t6/design.md" <<EOF
# Design
- 野树在 /tmp/claude-0/xxx/wt-base $MARK
- 规划双出全文见 scratchpad/brief-date.md
- 基线抄在 /tmp/claude-0/xxx/due-baseline.txt
EOF
  out="$( cd "$p" && "$BIN/track" archive t6 "$p" 2>&1 )"

  [[ ! -d "$(archived_dir "$p" t6)" ]];        check "没有归档成功" $?
  grep -q "brief-date" <<< "$out";             check "点名了第一条没标记的" $?
  grep -q "due-baseline" <<< "$out";           check "**第二条**也要点名(不许只报第一条)" $?
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
  # 攻题指出:原版收据正文压根不含 /tmp ⇒ 这一幕没锚住任何东西。
  # 真实 runlog 收据会写绝对 `cwd:`(runlog:91),判据仓在 mktemp -d 下 ⇒ 正文天然含 /tmp。
  # 照真实形状造,才问得出「只扫 *.md、不扫 evidence/*.txt」这件事。
  printf 'cmd:     bash tests/x.sh\ncwd:     %s(仓根)\n输出\n%s\n' \
    "$p" "$rl" > "$p/tracks/t7/evidence/20260813T032605Z-01-green.txt"
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
  # 攻题指出两处:① 只核对一个预先知道的行号,证明不了实现真在算行号
  #                ② `grep -q "design.md:4"` 是正则,`.` 会匹配任意字符 ⇒ 用 -F 定串。
  # 摆两个文件、两个不同行号。
  printf '# Design\n\n\n- 全文在 scratchpad 的 my-review\n' > "$p/tracks/t8/design.md"
  printf '# Proposal\n- 基线数据在 /tmp/claude-0/xyz/baseline.txt\n' > "$p/tracks/t8/proposal.md"
  out="$( cd "$p" && "$BIN/track" archive t8 "$p" 2>&1 )"

  grep -qF "design.md:4" <<< "$out";     check "报出了 design.md:4" $?
  grep -qF "proposal.md:2" <<< "$out";   check "报出了 proposal.md:2(行号是算的,不是写死的)" $?
  grep -q "my-review" <<< "$out";        check "报出了原文片段" $?
  grep -q "仓外不承重" <<< "$out";       check "告诉了怎么放行(标记写法)" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E9
e9_fail_closed_without_helper() {
  echo "[E9] helper 缺件 ⇒ 拒绝归档(不许静默放行)"
  local d; d="$(mktemp -d)"; local p="$d/proj" fakebin rc out
  make_proj "$p" t9
  # ⚠️ 攻题抓到的最致命一条:原版这里既缺 helper **又**放了危险引用 ⇒ 两个拒绝理由并存。
  # 那样的话「把逻辑内联进 track、根本不建 helper」的实现照样绿(它靠危险引用拒的)。
  # 单变量:track 必须是**干净的**,唯一的变量是 helper 不在。
  printf '# Design\n- 证据都在 evidence/ 里\n' > "$p/tracks/t9/design.md"
  fakebin="$d/bin"; mkdir -p "$fakebin"
  cp -a "$BIN"/. "$fakebin"/            # -a:含隐藏文件与子目录(攻题:`*` 会漏)
  rm -f "$fakebin/_ephemeral-refs.sh"
  out="$( cd "$p" && "$fakebin/track" archive t9 "$p" 2>&1 )"; rc=$?

  [[ ! -d "$(archived_dir "$p" t9)" ]]; check "没有归档成功(fail closed)" $?
  [[ -d "$(active_dir "$p" t9)" ]];     check "原目录还在(缺件不许变成破坏性失败)" $?
  [[ "$rc" -ne 0 ]];                    check "退出码非零" $?
  grep -q "_ephemeral-refs" <<< "$out"; check "报错点名了缺的那个件(不许任何失败都冒充 fail closed)" $?
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
  # 攻题指出:危险引用只放 verify.md 的话,「接进 pre-commit 但只扫 design.md」仍能全绿。
  cat >> "$p/tracks/t10/verify.md" <<'EOF'
- lane: self
- 派给: 主 agent
- 自审全文在 scratchpad/my-review.md
EOF
  printf '# Design\n- 探针在 /tmp/claude-0/xxx/probe.py\n' > "$p/tracks/t10/design.md"
  ( cd "$p" && git add -A && git commit -qm "wip" ) >/dev/null 2>&1; rc=$?

  [[ "$rc" -eq 0 ]]; check "pre-commit 放行(干活期间引用 scratchpad 是正常的)" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E11
e11_scans_all_md_including_nested() {
  echo "[E11] 扫描面 = track 下所有 *.md(含嵌套子目录),不是只扫 design/verify"
  local d; d="$(mktemp -d)"; local p="$d/proj" out
  make_proj "$p" t11
  # 攻题指出:原版没有 proposal/tasks/嵌套 md 的夹具 ⇒「只查 design+verify」能全绿。
  mkdir -p "$p/tracks/t11/notes/deep"
  printf '# Tasks\n- 驱动脚本在 scratchpad/e2e_driver.py\n' > "$p/tracks/t11/tasks.md"
  printf '# 深处\n- 探针输出在 /tmp/claude-0/xxx/probe.log\n' > "$p/tracks/t11/notes/deep/notes.md"
  out="$( cd "$p" && "$BIN/track" archive t11 "$p" 2>&1 )"

  [[ ! -d "$(archived_dir "$p" t11)" ]];   check "没有归档成功" $?
  grep -q "e2e_driver" <<< "$out";         check "tasks.md 里的引用被抓到" $?
  grep -q "probe.log" <<< "$out";          check "嵌套子目录的 md 也被抓到" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E12
e12_scratchpad_case_insensitive() {
  echo "[E12] scratchpad 大小写不敏感(散文里会写成 ScratchPad)"
  local d; d="$(mktemp -d)"; local p="$d/proj"
  make_proj "$p" t12
  printf '# Design\n- 全文见 ScratchPad/my-review.md\n' > "$p/tracks/t12/design.md"
  ( cd "$p" && "$BIN/track" archive t12 "$p" ) >/dev/null 2>&1

  [[ ! -d "$(archived_dir "$p" t12)" ]];  check "大小写不同也要拦" $?
  [[ -d "$(active_dir "$p" t12)" ]];      check "原目录还在原地" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E13
e13_tmpdir_variable_form() {
  echo "[E13] \$TMPDIR 变量形式(规格里写了却一直没测)"
  local d; d="$(mktemp -d)"; local p="$d/proj"
  make_proj "$p" t13
  # 单引号 heredoc:不许展开
  cat > "$p/tracks/t13/design.md" <<'EOF'
# Design
- 中间产物写在 $TMPDIR/dualplan/out.log
EOF
  ( cd "$p" && "$BIN/track" archive t13 "$p" ) >/dev/null 2>&1

  [[ ! -d "$(archived_dir "$p" t13)" ]];  check "TMPDIR 形式也要拦" $?
  [[ -d "$(active_dir "$p" t13)" ]];      check "原目录还在原地" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- E14
e14_fenced_code_block_is_scanned() {
  echo "[E14] 围栏代码块里的引用**照样扫**(两条评审腿独立指出的考卷洞)"
  local d; d="$(mktemp -d)"; local p="$d/proj" out
  make_proj "$p" t14
  # 四审 submimo 与 subdeepseek 各自独立指出:原版没有任何一幕锚住"围栏内要不要扫",
  # 于是「跳过围栏块」的实现能全绿。这一幕把**现行取舍**锁死:围栏内一样算引用。
  # (取舍本身有代价 —— 给逐字粘贴的终端记录加标记会改动原文;
  #  design 里已记为已知限制,真被咬到再考虑块级豁免。)
  cat > "$p/tracks/t14/design.md" <<'MD'
# Design
跑判据时的现场:

```
cmd:  bash tests/x.sh
cwd:  /tmp/tmp.abc123/proj(仓根)
```
MD
  out="$( cd "$p" && "$BIN/track" archive t14 "$p" 2>&1 )"

  [[ ! -d "$(archived_dir "$p" t14)" ]];  check "围栏内的 /tmp 也要拦" $?
  grep -q "tmp.abc123" <<< "$out";        check "点名了围栏里的那一行" $?
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
e11_scans_all_md_including_nested
e12_scratchpad_case_insensitive
e13_tmpdir_variable_form
e14_fenced_code_block_is_scanned
echo "=== PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]]

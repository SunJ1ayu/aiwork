#!/usr/bin/env bash
# runlog 的判据(2026-08-08 新建,track machine-evidence-gate)。
# 主 agent 拥有,执行腿不许改。
#
# runlog 是「把我说的换成机器打印的」那件事的写入端:判据不由我转述,由它跑、由它落盘。
# 所以这份判据里最要紧的两条,都是「它自己会不会撒谎」:
#
#   R2  **退出码必须原样透传**。runlog 要是把红的跑成绿的,它就成了本单要堵的
#       那种病本身(08-05 turn_id:汇总印 OK 而一整块被 SKIP)。
#   R3  **dirty 要在跑之前算**。收据文件自己会把工作树弄脏 —— 顺序反了的话
#       每份收据都写 dirty=yes,这个字段就永远是废话,而废话字段等于没有字段。
#
# Run:  bash /root/aiwork/tests/test-runlog.sh
set -uo pipefail

# 判卷面的不变量:**跑判据的进程不许有外网出口**(2026-08-10,track no-egress-judging)。
# 这一行把整个套件 exec 进一个没有出口的网络命名空间;做不到就拒跑。
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退

BIN="${TRACK_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
RUNLOG="$BIN/runlog"
GUARD="$BIN/track-guard"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

newrepo() {  # 干净仓 + 一个现成 track,**工作树全干净**(R3 靠这个)
  local d; d="$(mktemp -d)"
  ( cd "$d"
    git init -q; git config user.email t@t; git config user.name t
    mkdir -p tracks/t bin
    printf '# Verify: t\n\n- Verdict: **PASS**\n\n## Review\n\n- lane: **self**\n- 派给: **主 agent 直接干**\n' > tracks/t/verify.md
    git add -A >/dev/null; git commit -qm init )
  echo "$d"
}

receipt_of() {  # receipt_of <repo> -> 最新一份收据文件的路径
  ls -1 "$1"/tracks/t/evidence/*.txt 2>/dev/null | sort | tail -1
}

# ---------------------------------------------------------------- R1
r1_writes_a_receipt() {
  echo "[R1] 跑一条命令 ⇒ 收据落盘,输出和身份都在里面"
  local d; d="$(newrepo)"; local out f
  out="$(cd "$d" && "$RUNLOG" -t t -n hello -- bash -c 'echo 你好; echo 到 stderr 去 >&2' 2>&1)"

  f="$(receipt_of "$d")"
  [[ -n "$f" ]]; check "R1: evidence/ 里有收据文件" $?
  [[ "$(basename "$f")" == *hello* ]]; check "R1: 文件名带 slug" $?
  grep -q "你好" "$f"; check "R1: stdout 进了收据" $?
  grep -q "到 stderr 去" "$f"; check "R1: stderr 也进了收据(合并捕获)" $?
  grep -q "你好" <<<"$out"; check "R1: 输出同时还流到终端(不是闷头吞掉)" $?

  local sha; sha="$(cd "$d" && git rev-parse --short=7 HEAD)"
  grep -qE "^runlog: hello rc=0 commit=$sha dirty=no at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z file=tracks/t/evidence/.+\.txt$" "$f"
  check "R1: 收据末行 = 单行收据行,字段齐(slug/rc/commit/dirty/at/file)" $?

  local line; line="$(grep -a '^runlog: ' "$f" | tail -1)"
  grep -qxF "$line" <<<"$out"; check "R1: 同一行原样打印在终端上(给我粘)" $?
  grep -q "$(basename "$f")" <<<"$out"; check "R1: 终端还告诉我完整输出在哪个文件" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- R2
r2_exit_code_passthrough() {
  echo "[R2] 退出码原样透传 —— runlog 绝不许把红的跑成绿的"
  local d; d="$(newrepo)"; local rc f
  ( cd "$d" && "$RUNLOG" -t t -n red -- bash -c 'echo 炸了; exit 3' ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 3 ]]; check "R2: 命令 exit 3 ⇒ runlog 也 exit 3" $?
  f="$(receipt_of "$d")"
  grep -q 'rc=3' "$f"; check "R2: 收据行记的是 rc=3" $?
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d" && "$RUNLOG" -t t -n green -- true ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 0 ]]; check "R2: 命令成功 ⇒ runlog exit 0" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- R3
r3_dirty_is_measured_before_the_run() {
  echo "[R3] dirty 在跑之前算(收据文件自己不许把自己算脏)"
  local d; d="$(newrepo)"; local f
  ( cd "$d" && "$RUNLOG" -t t -n clean -- true ) >/dev/null 2>&1
  f="$(receipt_of "$d")"
  grep -q 'dirty=no' "$f"; check "R3: 干净仓里跑 ⇒ dirty=no(没被自己写的收据带脏)" $?
  rm -rf "$d"

  # 已跟踪文件被改
  d="$(newrepo)"
  ( cd "$d" && printf 'x\n' >> tracks/t/verify.md && "$RUNLOG" -t t -n m -- true ) >/dev/null 2>&1
  f="$(receipt_of "$d")"
  grep -q 'dirty=yes' "$f"; check "R3: 工作树改过 ⇒ dirty=yes" $?
  rm -rf "$d"

  # **未跟踪**文件也算脏:闸① 的教训 —— 未跟踪文件在 diff 里是隐形的,
  # 它恰恰是"这次跑的到底是什么代码"最容易失真的地方(tests/conftest.py 那一幕)。
  d="$(newrepo)"
  ( cd "$d" && printf 'x\n' > bin/sneaky.py && "$RUNLOG" -t t -n u -- true ) >/dev/null 2>&1
  f="$(receipt_of "$d")"
  grep -q 'dirty=yes' "$f"; check "R3: 只有未跟踪文件 ⇒ 照样 dirty=yes" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- R4
r4_filenames_sort_chronologically() {
  echo "[R4] 文件名字典序 = 时间序(规矩5b 取「最后一份」靠这个)"
  local d; d="$(newrepo)"; local n
  ( cd "$d" && "$RUNLOG" -t t -n a -- true ) >/dev/null 2>&1
  ( cd "$d" && "$RUNLOG" -t t -n b -- true ) >/dev/null 2>&1
  ( cd "$d" && "$RUNLOG" -t t -n c -- true ) >/dev/null 2>&1
  n="$(ls -1 "$d"/tracks/t/evidence/*.txt | wc -l)"
  [[ "$n" -eq 3 ]]; check "R4: 同一秒连跑三次 ⇒ 三份收据,谁也没覆盖谁" $?
  local last; last="$(ls -1 "$d"/tracks/t/evidence/*.txt | sort | tail -1)"
  grep -q 'runlog: c ' "$last"; check "R4: 字典序最后一份 = 最后跑的那次" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- R5
r5_refuses_bad_usage() {
  echo "[R5] 用法错误在开跑之前就拒,且用独立退出码 64(不和命令的 rc 撞车)"
  local d; d="$(newrepo)"; local rc
  ( cd "$d" && "$RUNLOG" -t nope -- true ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 64 ]]; check "R5: track 不存在 ⇒ rc=64" $?
  [[ ! -d "$d/tracks/nope" ]]; check "R5: 拒跑时不许顺手造目录" $?

  ( cd "$d" && "$RUNLOG" -t t -- ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 64 ]]; check "R5: 没给命令 ⇒ rc=64" $?

  ( cd "$d" && "$RUNLOG" -- true ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 64 ]]; check "R5: 没给 -t ⇒ rc=64" $?

  # **路径穿越**(2026-08-08 主 agent 自审时发现,不是 panel 提的):
  # track 名直接拼进路径 `tracks/$TRACK` —— `-t ../../tmp` 只要那个目录存在就通过
  # `[ -d ]` 检查,收据会写到**仓外**去。runlog 是本单新增的**写口**,
  # 写口的第一件事是把范围钉死:track 名里不许有斜杠、不许有 `..`。
  mkdir -p "$d/tracks/archive/../../escape"
  ( cd "$d" && "$RUNLOG" -t ../../escape -n x -- true ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 64 ]]; check "R5: track 名带 ../ ⇒ rc=64(不许写到仓外)" $?
  # 这一条第一版写成 `$d/../escape/evidence` —— 而 `tracks/archive/../../escape`
  # 解析出来是 `$d/escape`,断言指错了地方 ⇒ **恒真**,红检时它假绿了。
  # (我自己写的假绿断言,第 N 次;记在这儿别再犯:断言里的路径要照着代码解析一遍。)
  [[ ! -d "$d/escape/evidence" ]]; check "R5: 穿越被拒时 tracks/ 之外没被写进任何东西" $?
  ( cd "$d" && "$RUNLOG" -t 'a/b' -n x -- true ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 64 ]]; check "R5: track 名带斜杠 ⇒ rc=64" $?

  # 保留名(四审 subkimi F4 实测):`-t .` 让 `[ -d tracks/. ]` 恒真 ⇒ 收据写进
  # `tracks/evidence/`;`-t archive` 写进 `tracks/archive/evidence/`。两处都不属于
  # 任何 track,所有守卫(只 glob 各 track 自己的 evidence/)结构上看不见它们。
  # 写口的边界没钉在注释声称的地方。
  ( cd "$d" && "$RUNLOG" -t . -n x -- true ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 64 ]]; check "R5: -t . ⇒ rc=64" $?
  [[ ! -d "$d/tracks/evidence" ]]; check "R5: -t . 没在 tracks/ 底下留东西" $?
  ( cd "$d" && "$RUNLOG" -t archive -n x -- true ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 64 ]]; check "R5: -t archive ⇒ rc=64(那是归档目录,不是 track)" $?
  [[ ! -d "$d/tracks/archive/evidence" ]]; check "R5: -t archive 没在 archive/ 底下留东西" $?

  [[ -z "$(receipt_of "$d")" ]]; check "R5: 一连串拒跑,一份收据都没落下" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- R6
r6_works_on_archived_tracks() {
  echo "[R6] 已归档的 track 也能补跑(收尾常在归档前后来回)"
  local d; d="$(newrepo)"
  ( cd "$d" && mkdir -p tracks/archive/old && printf '# v\n' > tracks/archive/old/verify.md )
  ( cd "$d" && "$RUNLOG" -t old -n x -- true ) >/dev/null 2>&1
  [[ -n "$(ls -1 "$d"/tracks/archive/old/evidence/*.txt 2>/dev/null)" ]]
  check "R6: tracks/archive/<name> 也认" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- R7(集成)
r7_end_to_end_with_the_guard() {
  echo "[R7] 集成:runlog 打印的那一行粘进 verify.md ⇒ 守卫放行;改一个字 ⇒ 挡下"
  local d; d="$(newrepo)"; local line
  ( cd "$d" && "$RUNLOG" -t t -n suite -- bash -c 'echo 3 passed; exit 1' ) >/dev/null 2>&1
  line="$(grep -a '^runlog: ' "$(receipt_of "$d")" | tail -1)"

  ( cd "$d"
    { printf '\n## Mechanical checks\n\n```\n%s\n```\n' "$line"; } >> tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "R7: 原样粘 ⇒ 放行" $?

  ( cd "$d"
    sed -i 's/rc=1/rc=0/' tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "R7: 把 rc=1 改成 rc=0 ⇒ 当场挡下(这就是本单要堵的那一手)" $?
  rm -rf "$d"
}

echo "=== runlog oracle ==="
r1_writes_a_receipt
r2_exit_code_passthrough
r3_dirty_is_measured_before_the_run
r4_filenames_sort_chronologically
r5_refuses_bad_usage
r6_works_on_archived_tracks
r7_end_to_end_with_the_guard
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]

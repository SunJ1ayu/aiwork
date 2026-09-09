#!/usr/bin/env bash
# track-guard 的判据(2026-08-04 新建 —— 在此之前这个守卫**一条判据都没有**)。
# 主 agent 拥有,执行腿不许改。
#
# 为什么现在才写:08-04 的工作流体检发现,守卫**守错了门**,而没有任何东西会告诉我。
#
#   G1  规矩1(bump 版本必须挂 track)盯的是 `package.json` 里的 version,
#       而 design-studio 真正的版本号在 `bin/ds_web.py` 的 `VERSION = "..."`
#       —— `/api/health` 回显它、部署铁律核对它、记忆里所有版本号说的都是它。
#       `web/package.json` 自建仓起一直是 0.1.0,一次没动过。
#       实证:`41f8aa6`(0.69.0 → 0.70.0)提交时 tracks/ 零文件,**守卫一声没响**。
#       规矩是真的、守卫也真写了,只是**守在这个项目不用的位置**。
#
#   G2  「空着 = 没判过」的四个格子里,守卫只查 lane / 派给 两个。实测:那两个
#       有守卫的格子,7 份 verify.md 里**一次没空过**;而没守卫的 `Verdict:` 两个月
#       空了两次 —— stage-timer 已合并上线、记忆写着"全流程走完",**结论栏至今是模板
#       占位符**;上一次(todo-one-view)靠人工清理才发现。
#       这是守卫有没有用最干净的一次对照实验。
#       **但 Verdict 不能像 lane 那样每次提交都查**:verify.md 从 `track new` 起就带
#       占位符,结论按设计是最后才填的 ⇒ 中途每次提交都挡 = 误报 = 守卫被 `--no-verify`
#       绕过,比没有更糟。所以钉在**归档**那一刻(那时"做完了"没有歧义),
#       另配 `track list` 的软提示兜住"合并了但一直不归档"的那种漏网。
#
# Run:  bash /root/aiwork/tests/test-track-guard.sh
set -uo pipefail

# 判卷面的不变量:**跑判据的进程不许有外网出口**(2026-08-10,track no-egress-judging)。
# 这一行把整个套件 exec 进一个没有出口的网络命名空间;做不到就拒跑。
. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退

BIN="${TRACK_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
GUARD="$BIN/track-guard"
TRACK="$BIN/track"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

# 造一个干净的临时仓:**不留任何 verify.md 历史**,否则规矩1 的「近 7 天有 verify.md
# 改动」逃生分支会让所有用例假绿。
newrepo() {
  local d; d="$(mktemp -d)"
  ( cd "$d"
    git init -q; git config user.email t@t; git config user.name t
    mkdir -p bin web tracks
    printf 'VERSION = "0.1.0"\n' > bin/ds_web.py
    printf '{\n  "name": "x",\n  "version": "0.1.0"\n}\n' > web/package.json
    printf 'hello\n' > README.md
    git add -A >/dev/null; git commit -qm init )
  echo "$d"
}

verify_with() {  # verify_with <verdict 行内容>
  cat <<EOF
# Verify: t

- Date: 2026-08-04
- Verdict: $1

## Review

- lane: **self**
- 派给: **主 agent 直接干**
EOF
}

typed_decision() {  # typed_decision <level>
  cat <<EOF
{
  "schema_version": 1,
  "track": "t",
  "impact": {"level": $1, "factors": []},
  "design": {"uncertainty": "low", "premise_attack": {"status": "not_required", "evidence": []}},
  "execution_plan": {"adapter": "main", "model": null},
  "outcome": {"verdict": null}
}
EOF
}

# ---------------------------------------------------------------- G1
g1_version_lives_where_the_product_says() {
  echo "[G1] bump 必挂 track:守的门要对准这个项目真正的版本号"
  local d; d="$(newrepo)"

  # ① ds_web.py 的 VERSION 跳了,tracks/ 零文件 —— 必须挡下
  ( cd "$d"; printf 'VERSION = "0.2.0"\n' > bin/ds_web.py; git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G1: ds_web.py 的 VERSION 跳了却没挂 track → 挡下" $?

  # ② 同一次 bump,带上 track 工件 —— 必须放行
  ( cd "$d"; mkdir -p tracks/t; verify_with "**PASS**" > tracks/t/verify.md; git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  check "G1: 带着 track 工件的 bump → 放行" $?
  rm -rf "$d"

  # ③ 老规矩不许退化:package.json 的 bump 照样要挂 track
  d="$(newrepo)"
  ( cd "$d"; sed -i 's/"version": "0.1.0"/"version": "0.2.0"/' web/package.json; git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G1: package.json 的老规矩没退化" $?
  rm -rf "$d"

  # ④ 没 bump 就别叫:守卫误报会被 --no-verify 绕过,比没有更糟
  d="$(newrepo)"
  ( cd "$d"; printf 'hello world\n' > README.md; git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  check "G1: 没动版本号的普通提交 → 不误报" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- G2
g2_verdict_must_be_filled_at_archive() {
  echo "[G2] 归档那一刻,结论栏不许还是模板占位符"
  local d; d="$(newrepo)"

  # ① 归档一个结论栏还空着的 track —— 必须挡下
  ( cd "$d"; mkdir -p tracks/archive/t
    verify_with "<PASS | BLOCK | NEEDS_MORE_INFO>" > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G2: 归档时结论栏还是占位符 → 挡下" $?

  # ② 填了真结论再归档 —— 放行。
  #    2026-08-08 起夹具多了一行「无机器证据」:规矩5c 要求归档时要么有 runlog 收据、
  #    要么白纸黑字说明为什么没有。**断言一字没改**(填了结论就该放行),
  #    改的是夹具 —— 这一格考的是结论栏,不是机器证据,那一条由 G6 ③a 单独考。
  ( cd "$d"; { verify_with "**PASS**(主裁)"; printf -- '- 无机器证据:夹具\n'; } > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  check "G2: 归档时结论栏已填 → 放行" $?
  rm -rf "$d"

  # ③ **反误报**:track 还在进行中(没归档),结论栏空着是正常的
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    verify_with "<PASS | BLOCK | NEEDS_MORE_INFO>" > tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  check "G2: 进行中的 track 结论栏空着 → 不误报" $?
  rm -rf "$d"
}

g2_list_surfaces_unjudged_tracks() {
  echo "[G2] track list 要把「结论栏还空着」的 active track 标出来"
  local d; d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/open tracks/done tracks/archive/old
    verify_with "<PASS | BLOCK | NEEDS_MORE_INFO>" > tracks/open/verify.md
    verify_with "**PASS**" > tracks/done/verify.md
    verify_with "**PASS**" > tracks/archive/old/verify.md )
  local out; out="$("$TRACK" list "$d" 2>&1)"
  grep -qE "open.*(⚠|没判过|未判)" <<<"$out"; check "G2: 结论栏空着的 track 被标出来" $?
  if grep -qE "done.*(⚠|没判过|未判)" <<<"$out"; then
    bad "G2: 已判过的 track 不许被标"
  else ok "G2: 已判过的 track 不许被标"; fi
  rm -rf "$d"
}

# ---------------------------------------------------------------- G3
# 为什么加这一组(2026-08-04 晚,归档 workbench-p1 那单实战后发现的缺口):
#   规矩3 只钉在 `git commit` 那一步 —— `track archive` **命令本身照样把目录移进
#   archive/**,只有事后提交才被红字拦住。中间那段时间磁盘状态是「已归档但没结论」,
#   而归档是个**移动目录**的动作:被挡下之后要么手工 mv 回去,要么带着这个状态干别的。
#   守卫该守在动作发生那一刻,不是它的痕迹被提交那一刻。
# 现存 51 个已归档 track 实测:verify.md 无一缺失、Verdict 无一是占位符
#   ⇒ 把这两条都做成硬挡,不会误报到历史工件上。
g3_archive_command_itself_blocks() {
  echo "[G3] track archive 命令本身要挡,不能只靠 commit 那一步"
  local d; d="$(newrepo)"

  # ① 结论栏还是占位符 —— 命令必须失败,**且目录不许被移走**
  ( cd "$d"; mkdir -p tracks/t
    verify_with "<PASS | BLOCK | NEEDS_MORE_INFO>" > tracks/t/verify.md )
  "$TRACK" archive t "$d" >/dev/null 2>&1
  [[ $? -ne 0 ]]; check "G3: 结论栏是占位符 → archive 命令失败" $?
  [[ -d "$d/tracks/t" && ! -d "$d/tracks/archive/t" ]]
  check "G3: 被挡下时目录留在原地(没有半归档状态)" $?
  rm -rf "$d"

  # ② 填了真结论 —— 正常归档。
  #    **必须换一个干净的临时仓**:修复前 ① 会真把目录移走,② 若沿用同一个仓就成了
  #    "红在文件不存在上",而 ②-2 那条反而假绿 —— 那种红等于没红检过。
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    { verify_with "**PASS**(主裁)"; printf -- '- 无机器证据:夹具\n'; } > tracks/t/verify.md )
  "$TRACK" archive t "$d" >/dev/null 2>&1
  check "G3: 结论栏已填 → archive 正常放行" $?
  [[ -d "$d/tracks/archive/t" && ! -d "$d/tracks/t" ]]
  check "G3: 放行时目录确实移进了 archive/" $?
  rm -rf "$d"

  # ③ 压根没有 verify.md —— 同样是「没判过」,照挡
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t; printf '# proposal\n' > tracks/t/proposal.md )
  "$TRACK" archive t "$d" >/dev/null 2>&1
  [[ $? -ne 0 ]]; check "G3: 没有 verify.md → archive 命令失败" $?
  [[ -d "$d/tracks/t" ]]; check "G3: 没有 verify.md 时目录也留在原地" $?
  rm -rf "$d"
}

g8_track_new_rejects_path_names() {
  echo "[G8] track new 不许接受带路径分隔的名字(守卫的正则只认单层)"
  local d; d="$(newrepo)"
  "$TRACK" new 'foo/bar' "$d" >/dev/null 2>&1
  [[ $? -ne 0 ]]; check "G8: track new foo/bar ⇒ 拒绝" $?
  [[ ! -d "$d/tracks/foo" ]]; check "G8: 拒绝时不许留下半个目录" $?
  "$TRACK" new 'ok-name' "$d" >/dev/null 2>&1
  check "G8: 正常名字照常放行" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- 回归
r_existing_rules_still_hold() {
  echo "[R] 原有两条规矩不许退化"
  local d; d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    printf '# Verify: t\n\n- Date: 2026-08-04\n- Verdict: **PASS**\n\n## Review\n\n- lane: <full | fast | self>\n- 派给: **主 agent**\n' > tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "R: lane 空着仍然挡下" $?

  ( cd "$d"; printf '# Verify: t\n\n- Date: 2026-08-04\n- Verdict: **PASS**\n\n## Review\n\n- lane: **self**\n- 派给: <主 agent 直接干 | codex>\n' > tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "R: 派给 空着仍然挡下" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- G4(已知盲区)
g4_known_blind_spots() {
  echo "[G4] 版本号写成别的形状时,守卫认不认得出来(2026-08-05 实测钉下来的盲区)"
  local d

  # ① 真实形状复核:ds_web 那行是 `VERSION = "x"  # 一句话说明`,带行尾注释
  d="$(newrepo)"
  ( cd "$d"; printf 'VERSION = "0.2.0"  # 断线自愈\n' > bin/ds_web.py; git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G4: 带行尾注释的 VERSION 照样认得出来" $?
  rm -rf "$d"

  # ② 已知盲区:JS/TS 的 `export const VERSION = "…"` 认不出来。
  #    **故意不去放宽正则**:放宽就会连 `SCHEMA_VERSION: str = "2"` 这类无关赋值一起挡,
  #    而守卫一误报就会被 `--no-verify` 绕过 —— 那比没有守卫更糟(规矩3 的注释同理)。
  #    design-studio 的版本号真相源是 bin/ds_web.py,这个盲区当下不咬人;
  #    **哪天有项目把版本号放进 TS 常量,先加判据再改守卫。**
  d="$(newrepo)"
  ( cd "$d"; mkdir -p web/src; printf 'export const VERSION = "0.2.0";\n' > web/src/version.ts
    git add -A >/dev/null )
  ( cd "$d"; "$GUARD" >/dev/null 2>&1 )
  check "G4: (已知盲区,非期望行为)TS 常量形式的 bump 目前不会被挡" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- G5
# 规矩4:动了**评审/派活工具**也必须挂 track。
# 出处(2026-08-06 当天自查):规矩1 只在 bump 版本号时触发,而 `/root/aiwork` 这个仓
# **根本没有版本号** ⇒ 那个仓的改动结构上永远不会被要求挂 track。当天实证:
# 我改了 `bin/panel-review`(评审工具链本身、信任面)+ 建了两个新工具,
# 三条改动没有任何 track、没有 verify ⇒ **`lane:` 那道题从头到尾没被问过**,
# 而同一天我却因为"碰判卷防线"给另一单走了 full 四审。同性质两种待遇。
# 守卫守错门的第二例(第一例是 08-04:守在 package.json、而真版本号在 ds_web.py)。
g5_tooling_changes_need_a_track() {
  echo "[G5] 规矩4:改评审/派活工具(bin/panel-*, bin/sub*, bin/delegate-*, redcheck, track*)必须挂 track"
  local d; d="$(newrepo)"; local out rc
  ( cd "$d"; mkdir -p bin; printf '#!/bin/bash\necho v1\n' > bin/panel-review
    printf '#!/bin/bash\necho v1\n' > bin/redcheck
    printf '#!/bin/bash\necho v1\n' > bin/unrelated-tool
    git add -A >/dev/null; git commit -qm "工具就位" )

  # ① 改评审工具、不挂 track ⇒ 挡下
  ( cd "$d"; printf '#!/bin/bash\necho v2\n' > bin/panel-review; git add -A >/dev/null )
  out="$(cd "$d" && bash "$BIN/track-guard" 2>&1)"; rc=$?
  check "G5: 改 bin/panel-review 却没挂 track ⇒ 挡下" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "panel-review" <<<"$out"; check "G5: 挡下时点名是哪个工具" $?

  # ② 同一次提交带上 track 工件 ⇒ 放行(和规矩1 同款逃生口)
  ( cd "$d"; mkdir -p tracks/t; verify_with "PASS" > tracks/t/verify.md; git add -A >/dev/null )
  out="$(cd "$d" && bash "$BIN/track-guard" 2>&1)"; rc=$?
  check "G5: 同次提交带 track 工件 ⇒ 放行" $([[ $rc -eq 0 ]]; echo $?)
  ( cd "$d" && git commit -qm "带 track 的工具改动" )

  # ③ 改的是**不相干的**脚本 ⇒ 不许误报(误报的守卫活不过一周)
  ( cd "$d"; printf '#!/bin/bash\necho v2\n' > bin/unrelated-tool; git add -A >/dev/null )
  out="$(cd "$d" && bash "$BIN/track-guard" 2>&1)"; rc=$?
  check "G5: 改不相干脚本 ⇒ 放行(不误报)" $([[ $rc -eq 0 ]]; echo $?)
  ( cd "$d" && git commit -qm "无关脚本" )

  rm -rf "$d"

  # ④ 判据文件本身也算判卷防线(改判据不挂 track,和改守卫是同一类事)。
  #    **必须换干净仓**:上面第②幕提交过 verify.md,7 天逃生口会合法地放行 ——
  #    在那个仓里这一条根本问不出来(08-06 红检时先撞到的就是这个夹具 bug,不是实现)。
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tests; printf 'echo t\n' > tests/test-review-tooling.sh; git add -A >/dev/null )
  out="$(cd "$d" && bash "$BIN/track-guard" 2>&1)"; rc=$?
  check "G5: 新增/改动 tests/test-*.sh 判据 ⇒ 也要挂 track" $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  # ⑤ 四审(subkimi)点名的三处名单漏网 —— 每一处都是"判卷防线自己不在防线内":
  #    a) 反锚定闸文件本身(改弱闸逻辑竟然不用挂 track);
  #    b) `tests/test_*.py` —— 连字符匹配不到下划线,而它是总跑里的正式判据套件;
  #    c) `track/templates/*` —— 把模板里的 `lane:` 行删掉,规矩2 当场成空文。
  local f
  for f in bin/_my-review-gate.sh tests/test_submimo_retry.py track/templates/verify.md; do
    d="$(newrepo)"
    ( cd "$d"; mkdir -p "$(dirname "$f")"; printf 'x\n' > "$f"; git add -A >/dev/null )
    out="$(cd "$d" && bash "$BIN/track-guard" 2>&1)"; rc=$?
    check "G5: 动 $f ⇒ 也要挂 track" $([[ $rc -ne 0 ]]; echo $?)
    rm -rf "$d"
  done
}

# ---------------------------------------------------------------- G6
# 规矩5:verify.md 里粘的数,必须是 runlog 写下的那个数。
# 出处(2026-08-05 turn_id):我写「python 866/0」,听起来完美 —— 实际上回归用的
# 解释器没装 mcp,**一整块闸被整块 SKIP**,汇总照印 OK。汇总会撒谎,细节不会。
# 08-08 起我已经在粘机器输出了,但**靠自觉**:没有任何东西拦着我写一句「全绿」交差,
# 翻开 verify.md 也看不出那行字是机器吐的还是我编的。
# 这道闸堵的是**顺手四舍五入**,不是蓄意伪造(手改收据文件仍然能骗过它 ——
# 但那要多改一个进了 git 的文件,会出现在闸③亲读的 diff 里)。
mk_receipt() {  # mk_receipt <repo> <track路径> <文件名> <收据行>
  mkdir -p "$1/$2/evidence"
  printf '# runlog receipt\n跑了点什么\n%s\n' "$4" > "$1/$2/evidence/$3"
}
verify_ev() {  # verify_ev <verdict> [粘进 Mechanical checks 的行...]
  printf '# Verify: t\n\n- Date: 2026-08-08\n- Verdict: %s\n\n## Mechanical checks\n\n' "$1"
  shift
  local l; for l in "$@"; do printf '%s\n' "$l"; done
  printf '\n## Review\n\n- lane: **self**\n- 派给: **主 agent 直接干**\n'
}
L1='runlog: suite rc=0 commit=aaaaaaa dirty=no at=2026-08-08T01:00:00Z file=tracks/t/evidence/20260808T010000Z-suite.txt'
L2='runlog: suite rc=3 commit=bbbbbbb dirty=no at=2026-08-08T02:00:00Z file=tracks/t/evidence/20260808T020000Z-suite.txt'

g6_pasted_numbers_must_be_the_machines_numbers() {
  echo "[G6] 规矩5:粘进 verify.md 的收据行必须与收据文件逐字节相同"
  local d out rc

  # ①a 一致性:verify.md 里有收据行,evidence/ 里根本没有这份收据 ⇒ 挡下
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t; verify_ev "**PASS**" '```' "$L1" '```' > tracks/t/verify.md
    git add -A >/dev/null )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check "G6: 凭空写一行收据(没有对应收据文件)⇒ 挡下" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "runlog" <<<"$out"; check "G6: 挡下时点名是哪一行" $?
  rm -rf "$d"

  # ①b **本单的核心场景**:收据写着 rc=3,我粘成 rc=0 ⇒ 挡下
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    mk_receipt "$d" tracks/t 20260808T020000Z-suite.txt "$L2"
    verify_ev "**PASS**" '```' "${L2/rc=3/rc=0}" '```' > tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G6: 收据是 rc=3、粘成 rc=0 ⇒ 挡下(四舍五入的那一手)" $?
  rm -rf "$d"

  # ①c 逐字节相同 ⇒ 放行
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    mk_receipt "$d" tracks/t 20260808T020000Z-suite.txt "$L2"
    verify_ev "**PASS**" '```' "$L2" '```' > tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G6: 原样粘 ⇒ 放行" $?
  rm -rf "$d"

  # ①d 反误报:仓里现存 40 多份 verify.md 一条 runlog 行都没有,一个都不许被挡
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t; verify_with "**PASS**" > tracks/t/verify.md; git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G6: verify.md 里没有收据行 ⇒ 不误报(老工件全身而退)" $?
  rm -rf "$d"

  # ①e 反引号/列表符号包着粘也算数(markdown 里这么写很自然,不许因此误报)
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    mk_receipt "$d" tracks/t 20260808T020000Z-suite.txt "$L2"
    verify_ev "**PASS**" "- \`$L2\`" > tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G6: 用 \`- \\\`…\\\`\` 形式粘 ⇒ 放行" $?
  ( cd "$d"; sed -i 's/rc=3/rc=0/' tracks/t/verify.md; git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G6: 同样的形式改了数 ⇒ 照样挡下(不是靠形状放过去的)" $?
  rm -rf "$d"
}

g6_archive_needs_the_last_run() {
  echo "[G6] 规矩5b/5c/5d:归档时,最后一份收据必须被引用;没有收据要显式认账;收据必须进 git"
  local d out rc

  # ②a 跑了两遍,只贴早先那份好看的 ⇒ 归档时挡下
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    mk_receipt "$d" tracks/archive/t 20260808T010000Z-suite.txt "$L1"
    mk_receipt "$d" tracks/archive/t 20260808T020000Z-suite.txt "$L2"
    verify_ev "**PASS**" '```' "$L1" '```' > tracks/archive/t/verify.md
    git add -A >/dev/null )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check "G6: 归档时最后一份收据没被引用 ⇒ 挡下" $([[ $rc -ne 0 ]]; echo $?)
  grep -q "20260808T020000Z" <<<"$out"; check "G6: 挡下时点名缺的是哪一份" $?

  # ②b 两份都贴 ⇒ 放行
  ( cd "$d"; verify_ev "**PASS**" '```' "$L1" "$L2" '```' > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G6: 引用了最后一份 ⇒ 放行" $?
  rm -rf "$d"

  # ②c 反误报:同样两份收据,但 track **还没归档** ⇒ 中途只贴一份是正常的
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    mk_receipt "$d" tracks/t 20260808T010000Z-suite.txt "$L1"
    mk_receipt "$d" tracks/t 20260808T020000Z-suite.txt "${L2/tracks\/t/tracks\/t}"
    verify_ev "**PASS**" '```' "$L1" '```' > tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G6: 进行中的 track 只贴了一份 ⇒ 不误报(判据是一路补的)" $?
  rm -rf "$d"

  # ③a 归档、一份收据都没有、也没写理由 ⇒ 挡下
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    verify_ev "**PASS**" '- [x] tests pass —— 判据全绿' > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G6: 归档但零机器证据、零说明 ⇒ 挡下" $?

  # ③b 显式认账 ⇒ 放行(纯文档 track 本来就没什么可跑;要的是白纸黑字,不是沉默)
  ( cd "$d"; verify_ev "**PASS**" '- 无机器证据:纯文档 track,没有可跑的判据' > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G6: 写了「无机器证据:<理由>」⇒ 放行" $?

  # ③b2 认账行**缩进**着写也算数(markdown 里嵌在小节下面很自然)。
  #     误报的守卫会被 --no-verify 绕过,比没有守卫更糟 —— 这一条是防误报,不是放水:
  #     它仍然要求那句话真的在,只是不挑它顶不顶格。
  ( cd "$d"; verify_ev "**PASS**" '  - 无机器证据:纯文档 track,没有可跑的判据' > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G6: 认账行缩进着写 ⇒ 也放行(不误报)" $?

  # ③c 认账行必须真给理由,冒号后面空着不算
  ( cd "$d"; verify_ev "**PASS**" '- 无机器证据:' > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G6: 「无机器证据:」后面空着 ⇒ 仍然挡下(空着 = 没说)" $?
  rm -rf "$d"

  # ④ 5d 留痕:收据只躺在本地、既没跟踪也没暂存 ⇒ 归档时挡下。
  #    闸① 同款盲点:未跟踪文件在 diff 里是隐形的,证据不进 git 等于随手一删就没了。
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    verify_ev "**PASS**" '```' "$L2" '```' > tracks/archive/t/verify.md
    git add -A >/dev/null
    mk_receipt "$d" tracks/archive/t 20260808T020000Z-suite.txt "$L2" )   # 收据故意不 add
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check "G6: 收据文件未跟踪也未暂存 ⇒ 归档时挡下" $([[ $rc -ne 0 ]]; echo $?)
  grep -qE "未跟踪|没进 git|untracked" <<<"$out"; check "G6: 挡下时说清是「没进 git」这件事" $?
  ( cd "$d"; git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G6: 收据一起暂存 ⇒ 放行" $?
  rm -rf "$d"
}

# ---------------------------------------------------------------- G8
# 2026-08-08 四审修复轮。三条腿里**两条独立命中**同一处(F1/M3):
# 归档半边的触发条件按**路径**写(`^tracks/archive/…/verify\.md$`),区分不了
# 「这次提交在归档」和「早就归档了、这次只改了个错字」——仓里 8 份历史归档工件
# 全部零收据,一碰就被挡,报错还说「在归档」。任务书自己点名「误报比漏报更致命」,
# 这就是那一类。(实测复现过再修的,不是照单全收。)
g8_archive_mode_only_when_actually_archiving() {
  echo "[G8] 归档半边只在**真的归档**那一次触发,不许碰历史工件"
  local d out rc

  # ① 早已归档的 verify.md,这次只是改一行 ⇒ 放行(它零收据、零认账行)
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    verify_ev "**PASS**" '- [x] tests pass —— 两个月前的老工件' > tracks/archive/t/verify.md
    git add -A >/dev/null; git commit -qm "两个月前就归档了" )
  ( cd "$d"; printf '\n改个错字\n' >> tracks/archive/t/verify.md; git add -A >/dev/null )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check "G8: 改一份历史归档工件 ⇒ 不误报" $([[ $rc -eq 0 ]]; echo $?)
  rm -rf "$d"

  # ② 这一次真的在归档(git mv 进 archive/,状态 R)⇒ 照查不误
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    verify_ev "**PASS**" '- [x] tests pass' > tracks/t/verify.md
    git add -A >/dev/null; git commit -qm "进行中" )
  ( cd "$d"; mkdir -p tracks/archive; git mv tracks/t tracks/archive/t >/dev/null; git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G8: 这次提交真的在归档(rename 进 archive)⇒ 照挡" $?
  rm -rf "$d"
}

# 第二轮四审(subdeepseek)的两处,都是**误报**方向 —— 这道闸的死法就是误报。
g8_round2_false_positive_shapes() {
  echo "[G8] 第二轮:编号列表粘贴 / 归档目录内改名,都不许误报"
  local d

  # ① `1. \`runlog: …\`` —— 行首装饰只剥了 `-*>_` 和反引号,数字和点没剥 ⇒
  #    诚实的编号列表粘贴在 claimed 里是隐形的 ⇒ 归档时 5b 反过来说"你没贴"。
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    mk_receipt "$d" tracks/archive/t 20260808T020000Z-01-suite.txt "$L2"
    verify_ev "**PASS**" "1. \`$L2\`" > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G8: 编号列表 \`1. …\` 形式粘贴 ⇒ 放行" $?
  ( cd "$d"; sed -i 's/rc=3/rc=0/' tracks/archive/t/verify.md; git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G8: 编号列表形式改了数 ⇒ 照样挡下" $?
  rm -rf "$d"

  # ② 已归档目录内部改名(archive/old → archive/new):状态是 R、落点在 archive/ 下,
  #    按第一版逻辑会被当成"这次在归档" ⇒ 又一次误伤历史工件(和 F1 同根)。
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/old
    verify_ev "**PASS**" '- [x] tests pass —— 老工件,零收据' > tracks/archive/old/verify.md
    git add -A >/dev/null; git commit -qm "早就归档了" )
  ( cd "$d"; git mv tracks/archive/old tracks/archive/new >/dev/null; git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G8: 归档目录内部改名 ⇒ 不当成归档,不误报" $?
  rm -rf "$d"
}

# 5b'(DeepSeek M4):跑砸一遍之后补跑一条 `-- true`,最后一份就变绿了,
# 难看的那一遍从此不用贴 —— 全程没动任何收据文件,不属于「蓄意伪造」那条免责。
# 所以:**每一份 rc≠0 的收据都必须被引用**。红的那几遍才是这一单最值钱的部分。
g8_every_red_run_must_be_quoted() {
  echo "[G8] 归档时,rc≠0 的收据一份都不许藏"
  local d
  local RED='runlog: suite rc=1 commit=aaaaaaa dirty=no at=2026-08-08T01:00:00Z file=tracks/archive/t/evidence/20260808T010000Z-01-suite.txt'
  local GREEN='runlog: suite rc=0 commit=bbbbbbb dirty=no at=2026-08-08T02:00:00Z file=tracks/archive/t/evidence/20260808T020000Z-01-suite.txt'

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    mk_receipt "$d" tracks/archive/t 20260808T010000Z-01-suite.txt "$RED"
    mk_receipt "$d" tracks/archive/t 20260808T020000Z-01-suite.txt "$GREEN"
    verify_ev "**PASS**" '```' "$GREEN" '```' > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G8: 只贴绿的那一遍、把红的那一遍藏了 ⇒ 挡下" $?

  ( cd "$d"; verify_ev "**PASS**" '```' "$RED" "$GREEN" '```' > tracks/archive/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G8: 红的绿的都贴 ⇒ 放行" $?
  rm -rf "$d"
}

# L6(DeepSeek):行首装饰剥了、行尾只剥反引号和空白 ⇒ `**\`runlog: …\`**` 这种
# 老实粘贴反而被挡。误报,修。
g8_bold_wrapped_paste_is_fine() {
  echo "[G8] 粗体/强调包着粘也算数(诚实粘贴不许被挡)"
  local d; d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    mk_receipt "$d" tracks/t 20260808T020000Z-suite.txt "$L2"
    verify_ev "**PASS**" "**\`$L2\`**" > tracks/t/verify.md
    git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check "G8: **\`收据行\`** 形式 ⇒ 放行" $?
  ( cd "$d"; sed -i 's/rc=3/rc=9/' tracks/t/verify.md; git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  [[ $? -ne 0 ]]; check "G8: 同形式改了数 ⇒ 照样挡下" $?
  rm -rf "$d"
}

g9_typed_shape_uses_staged_decision() {
  echo '[G9] typed track 的 staged decision 必须过 shape；不能拿 working copy 替它应试'
  local d out rc
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    typed_decision '"medium"' > tracks/t/decision.json
    git add tracks/t
    typed_decision '"self"' > tracks/t/decision.json )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check 'G9: staged 非法、working 合法 ⇒ 仍按 staged 拒绝' $([[ $rc -ne 0 ]]; echo $?)
  grep -q 'path=impact.level' <<<"$out" && grep -q 'actual=.*medium' <<<"$out"
  check 'G9: staged shape 错误带 rule trace' $?

  ( cd "$d"; typed_decision '"self"' > tracks/t/decision.json; git add tracks/t/decision.json
    typed_decision '"medium"' > tracks/t/decision.json )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G9: staged 合法、working 非法 ⇒ guard 按 staged 放行' $([[ $rc -eq 0 ]]; echo $?)
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    git add tracks/t/verify.md )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G9: working 有新 decision 但没 staged ⇒ 不许降级成 legacy 放行' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    git add tracks/t; git commit -qm typed
    git rm -q tracks/t/decision.json
    printf '# changed\n' >> tracks/t/verify.md; git add tracks/t/verify.md )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G9: staged 删除已跟踪 decision ⇒ 不许伪装成 legacy' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"
}

g10_manual_typed_archive_uses_staged_facts() {
  echo '[G10] 手工 git mv 归档 typed track，也必须用 staged decision/observations 过 archive 闸'
  local d out rc
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    printf '# Verify\n- 无机器证据:fixture\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    git add tracks/t; git commit -qm typed
    mkdir -p tracks/archive; git mv tracks/t tracks/archive/t; git add -A )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check 'G10: outcome=null 的 typed track 手工搬进 archive ⇒ guard 拒绝' $([[ $rc -ne 0 ]]; echo $?)
  grep -q 'path=outcome.verdict' <<<"$out"
  check 'G10: 手工归档仍给 typed outcome trace' $?
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    printf '# Verify\n- 无机器证据:fixture\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    python3 - tracks/t/decision.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["outcome"]["verdict"]="PASS"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
    git add tracks/t; git commit -qm typed-pass
    mkdir -p tracks/t/observations
    cat > tracks/t/observations/working-only.json <<'JSON'
{"schema_version":1,"track":"t","run_id":"r1","controller":"runlog","event":"execution_finished","label":"r1","started_at":"2026-08-21T00:00:00Z","finished_at":"2026-08-21T00:00:01Z","duration_ms":1,"exit_code":0,"actual":{"adapter":"runlog","model":null,"risk":null,"degraded":null,"work_exit_code":0,"legs":null},"usage":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"api_cost":null,"billing_mode":null}}
JSON
    mkdir -p tracks/archive; git mv tracks/t tracks/archive/t; git add -u )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check 'G10: working 有绿 observation、index 没有 ⇒ staged archive 仍拒绝' $([[ $rc -ne 0 ]]; echo $?)
  grep -q 'rule=observation.required' <<<"$out"
  check 'G10: 未 staged observation 不能替本次提交应试' $?
  ( cd "$d"; git add tracks/archive/t/observations; "$GUARD" >/dev/null 2>&1 ); rc=$?
  check 'G10: decision/observation 都 staged 后手工归档才放行' $([[ $rc -eq 0 ]]; echo $?)
  ( cd "$d"; printf 'FULL_TRANSCRIPT\n' > tracks/archive/t/observations/transcript.txt
    git add tracks/archive/t/observations/transcript.txt; "$GUARD" >/dev/null 2>&1 ); rc=$?
  check 'G10: staged observations 目录夹带 transcript 文件 ⇒ 拒绝' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t/observations
    printf '# Verify\n- 无机器证据:fixture\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    python3 - tracks/t/decision.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["outcome"]["verdict"]="PASS"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
    cat > tracks/t/observations/ok.json <<'JSON'
{"schema_version":1,"track":"t","run_id":"r1","controller":"runlog","event":"execution_finished","label":"r1","started_at":"2026-08-21T00:00:00Z","finished_at":"2026-08-21T00:00:01Z","duration_ms":1,"exit_code":0,"actual":{"adapter":"runlog","model":null,"risk":null,"degraded":null,"work_exit_code":0,"legs":null},"usage":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"api_cost":null,"billing_mode":null}}
JSON
    git add tracks/t; git commit -qm complete
    mkdir -p tracks/archive; git mv tracks/t tracks/archive/t
    git rm -q -f tracks/archive/t/verify.md; git add -A )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check 'G10: 搬入 archive 同时删 verify ⇒ 仍按任意 archive 落点识别并拒绝' $([[ $rc -ne 0 ]]; echo $?)
  grep -q 'verify.md' <<<"$out"
  check 'G10: 缺 staged verify 的报警明确' $?
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t/observations
    printf '# Verify\n- 无机器证据:fixture\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    python3 - tracks/t/decision.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["outcome"]["verdict"]="PASS"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
    cat > tracks/t/observations/ok.json <<'JSON'
{"schema_version":1,"track":"t","run_id":"r1","controller":"runlog","event":"execution_finished","label":"r1","started_at":"2026-08-21T00:00:00Z","finished_at":"2026-08-21T00:00:01Z","duration_ms":1,"exit_code":0,"actual":{"adapter":"runlog","model":null,"risk":null,"degraded":null,"work_exit_code":0,"legs":null},"usage":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"api_cost":null,"billing_mode":null}}
JSON
    git add tracks/t; git commit -qm complete
    mkdir -p tracks/archive; git mv tracks/t tracks/archive/t
    git rm -q -f tracks/archive/t/decision.json; git add -A )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check 'G10: typed track 搬入 archive 同时删 decision ⇒ 不许降级 legacy' $([[ $rc -ne 0 ]]; echo $?)
  grep -q 'decision.json' <<<"$out"
  check 'G10: 搬入时缺 typed decision 的报警明确' $?
  rm -rf "$d"
}

g11_archived_machine_facts_stay_typed() {
  echo '[G11] typed 机器事实从 active 到 archive 都必须持续过白名单闸'
  local d rc

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t/observations
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    cat > tracks/t/observations/ok.json <<'JSON'
{"schema_version":1,"track":"t","run_id":"r1","controller":"runlog","event":"execution_finished","label":"r1","started_at":"2026-08-21T00:00:00Z","finished_at":"2026-08-21T00:00:01Z","duration_ms":1,"exit_code":0,"actual":{"adapter":"runlog","model":null,"risk":null,"degraded":null,"work_exit_code":0,"legs":null},"usage":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"api_cost":null,"billing_mode":null}}
JSON
    git add tracks/t; git commit -qm active
    python3 - tracks/t/observations/ok.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["transcript"]="FULL_TRANSCRIPT"
json.dump(p, open(sys.argv[1], "w"), separators=(",", ":"))
PY
    git add tracks/t/observations/ok.json )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G11: active observation 被 M 加 transcript 字段 ⇒ guard 当场拒绝' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t/observations
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    cat > tracks/t/observations/ok.json <<'JSON'
{"schema_version":1,"track":"t","run_id":"r1","controller":"runlog","event":"execution_finished","label":"r1","started_at":"2026-08-21T00:00:00Z","finished_at":"2026-08-21T00:00:01Z","duration_ms":1,"exit_code":0,"actual":{"adapter":"runlog","model":null,"risk":null,"degraded":null,"work_exit_code":0,"legs":null},"usage":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"api_cost":null,"billing_mode":null}}
JSON
    git add tracks/t; git commit -qm active
    python3 - tracks/t/observations/ok.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["transcript"]="FULL_TRANSCRIPT"
json.dump(p, open(sys.argv[1], "w"), separators=(",", ":"))
PY
    git add tracks/t/observations/ok.json; git rm -q tracks/t/verify.md )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G11: active M transcript + 同 commit 删除 verify ⇒ 仍不能跳过 typed shape' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t/observations
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    python3 - tracks/t/decision.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["outcome"]["verdict"]="PASS"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
    cat > tracks/t/observations/ok.json <<'JSON'
{"schema_version":1,"track":"t","run_id":"r1","controller":"runlog","event":"execution_finished","label":"r1","started_at":"2026-08-21T00:00:00Z","finished_at":"2026-08-21T00:00:01Z","duration_ms":1,"exit_code":0,"actual":{"adapter":"runlog","model":null,"risk":null,"degraded":null,"work_exit_code":0,"legs":null},"usage":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"api_cost":null,"billing_mode":null}}
JSON
    git add tracks/t; git commit -qm active
    mkdir -p tracks/archive; cp -R tracks/t tracks/archive/t
    python3 - tracks/t/observations/ok.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["transcript"]="FULL_TRANSCRIPT"
json.dump(p, open(sys.argv[1], "w"), separators=(",", ":"))
PY
    git add tracks/archive/t tracks/t/observations/ok.json; git rm -q tracks/t/verify.md )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check 'G11: copy-not-move 留下 active/archive 同名 ⇒ 生命周期唯一闸拒绝' $([[ $rc -ne 0 ]]; echo $?)
  grep -q '必须唯一' <<<"$out"
  check 'G11: copy-not-move 报警明确要求 move' $?
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t/observations
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    python3 - tracks/t/decision.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["outcome"]["verdict"]="PASS"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
    cat > tracks/t/observations/ok.json <<'JSON'
{"schema_version":1,"track":"t","run_id":"r1","controller":"runlog","event":"execution_finished","label":"r1","started_at":"2026-08-21T00:00:00Z","finished_at":"2026-08-21T00:00:01Z","duration_ms":1,"exit_code":0,"actual":{"adapter":"runlog","model":null,"risk":null,"degraded":null,"work_exit_code":0,"legs":null},"usage":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"api_cost":null,"billing_mode":null}}
JSON
    git add tracks/t; git commit -qm active
    mkdir -p tracks/archive; cp -R tracks/t tracks/archive/t
    python3 - tracks/t/observations/ok.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["transcript"]="FULL_TRANSCRIPT"
json.dump(p, open(sys.argv[1], "w"), separators=(",", ":"))
PY
    git add tracks/archive/t tracks/t/observations/ok.json
    git rm -q tracks/t/decision.json )
  out="$(cd "$d" && "$GUARD" 2>&1)"; rc=$?
  check 'G11: archive 副本 + 删除 active decision 但留 active 残件 ⇒ 仍拒绝' $([[ $rc -ne 0 ]]; echo $?)
  grep -q 'active 目录仍有残留' <<<"$out"
  check 'G11: decision 已删的 copy-not-move 仍点名 active 残件' $?
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t/observations
    printf '# Verify\n- 无机器证据:fixture\n' > tracks/archive/t/verify.md
    typed_decision '"self"' > tracks/archive/t/decision.json
    python3 - tracks/archive/t/decision.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["outcome"]["verdict"]="PASS"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
    cat > tracks/archive/t/observations/ok.json <<'JSON'
{"schema_version":1,"track":"t","run_id":"r1","controller":"runlog","event":"execution_finished","label":"r1","started_at":"2026-08-21T00:00:00Z","finished_at":"2026-08-21T00:00:01Z","duration_ms":1,"exit_code":0,"actual":{"adapter":"runlog","model":null,"risk":null,"degraded":null,"work_exit_code":0,"legs":null},"usage":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"api_cost":null,"billing_mode":null}}
JSON
    git add tracks/archive/t; git commit -qm archived
    python3 - tracks/archive/t/observations/ok.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["transcript"]="FULL_TRANSCRIPT"
json.dump(p, open(sys.argv[1], "w"), separators=(",", ":"))
PY
    git add tracks/archive/t/observations/ok.json )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G11: 已归档 observation 被 M 加 transcript 字段 ⇒ guard 拒绝' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t/observations
    printf '# Verify\n- 无机器证据:fixture\n' > tracks/archive/t/verify.md
    typed_decision '"self"' > tracks/archive/t/decision.json
    python3 - tracks/archive/t/decision.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["outcome"]["verdict"]="PASS"
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
    cat > tracks/archive/t/observations/ok.json <<'JSON'
{"schema_version":1,"track":"t","run_id":"r1","controller":"runlog","event":"execution_finished","label":"r1","started_at":"2026-08-21T00:00:00Z","finished_at":"2026-08-21T00:00:01Z","duration_ms":1,"exit_code":0,"actual":{"adapter":"runlog","model":null,"risk":null,"degraded":null,"work_exit_code":0,"legs":null},"usage":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"api_cost":null,"billing_mode":null}}
JSON
    git add tracks/archive/t; git commit -qm archived
    python3 - tracks/archive/t/decision.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p["outcome"]["verdict"]=None
json.dump(p, open(sys.argv[1], "w"), indent=2)
PY
    git add tracks/archive/t/decision.json )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G11: 已归档 decision outcome 改回 null ⇒ guard 拒绝' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"
}

# ---------------------------------------------------------------- G7
# 和 G3 同一个道理:守卫要守在**动作发生那一刻**,不是它的痕迹被提交那一刻。
# `track archive` 会把目录移走 —— 只靠 pre-commit 挡,中间那段时间磁盘上就是
# 「已归档但证据缺着」的半截状态。
g7_archive_command_checks_evidence_too() {
  echo "[G7] track archive 命令本身也要查机器证据,不能只靠 commit 那一步"
  local d

  # ① 最后一份收据没被引用 ⇒ 命令失败,且目录不许被移走
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    mk_receipt "$d" tracks/t 20260808T010000Z-suite.txt "$L1"
    mk_receipt "$d" tracks/t 20260808T020000Z-suite.txt "$L2"
    verify_ev "**PASS**" '```' "$L1" '```' > tracks/t/verify.md )
  "$TRACK" archive t "$d" >/dev/null 2>&1
  [[ $? -ne 0 ]]; check "G7: 最后一份收据没引用 ⇒ archive 命令失败" $?
  [[ -d "$d/tracks/t" && ! -d "$d/tracks/archive/t" ]]
  check "G7: 被挡下时目录留在原地(没有半归档状态)" $?
  rm -rf "$d"

  # ② 零收据、零说明 ⇒ 命令失败
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t; verify_ev "**PASS**" '- [x] tests pass' > tracks/t/verify.md )
  "$TRACK" archive t "$d" >/dev/null 2>&1
  [[ $? -ne 0 ]]; check "G7: 零机器证据、零说明 ⇒ archive 命令失败" $?
  rm -rf "$d"

  # ③ 补齐 ⇒ 正常归档(**换干净仓**:①② 修复前会真把目录移走,沿用同一个仓就成了
  #    "红在文件不存在上",那种红等于没红检过 —— G3 ② 已经栽过一次)
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    mk_receipt "$d" tracks/t 20260808T020000Z-suite.txt "$L2"
    verify_ev "**PASS**" '```' "$L2" '```' > tracks/t/verify.md )
  "$TRACK" archive t "$d" >/dev/null 2>&1
  check "G7: 引用齐了 ⇒ archive 正常放行" $?
  [[ -d "$d/tracks/archive/t" && ! -d "$d/tracks/t" ]]
  check "G7: 放行时目录确实移进了 archive/" $?
  rm -rf "$d"
}

# --------------------------------------------------------------- G12
# 为什么加这一组(2026-09-09,track archive-tree-and-untracked-views):
#   本单新加了"归档之后档案里的交付内容不许再改"这道比较,但它只在 track-record 被
#   叫起来时才生效。而 guard 挑要复验的归档目录时,只认 decision.json 和 observations/ ——
#   于是一个**只改 design.md / evidence 正文**的提交,压根不会触发复验,新比较等于没上线。
#   这一条钉的是"闸有没有被叫起来",不是"闸判得对不对"(后者在 test_review_delivery.py)。
g12_archived_prose_edits_get_revalidated() {
  echo '[G12] 只改归档件的正文(不碰 decision/observations)也必须触发归档复验'
  local d rc

  # ① typed 归档件、结论栏空着 ⇒ 复验必失败。只 stage design.md:
  #    复验被叫起来 = 红;没被叫起来 = 绿(那就是漏)。
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    { verify_with "**PASS**(主裁)"; printf -- '- 无机器证据:夹具\n'; } > tracks/archive/t/verify.md
    typed_decision '"self"' > tracks/archive/t/decision.json
    printf '# Design\n' > tracks/archive/t/design.md
    git add -A >/dev/null; git commit -qm archived >/dev/null
    printf '# Design\n\n归档之后又改了一句\n' > tracks/archive/t/design.md
    git add tracks/archive/t/design.md >/dev/null )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G12: 只改归档件 design.md ⇒ 归档复验被叫起来(拒绝)' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  # ② **反误报**:同样只改正文,但改的是**进行中**的 track ⇒ 归档复验不该介入
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    typed_decision '"self"' > tracks/t/decision.json
    printf '# Design\n' > tracks/t/design.md
    git add -A >/dev/null; git commit -qm active >/dev/null
    printf '# Design\n\n还在写\n' > tracks/t/design.md
    git add tracks/t/design.md >/dev/null )
  (cd "$d" && "$GUARD" >/dev/null 2>&1)
  check 'G12: 进行中 track 改 design.md ⇒ 不误报' $?
  rm -rf "$d"
}

# --------------------------------------------------------------- G13
# 为什么加这一组(2026-09-09 第二轮 panel,subdeepseek 实测复现):
#   G12 把"要复验的归档目录"从 decision/observations 加宽成"archive 下任何文件",
#   于是 `git mv tracks/archive/<t> tracks/<t>`(取回)时,那些文件在 staged diff 里
#   以"archive 路径被删除"的形式出现 ⇒ 目录被选进复验 ⇒ 闸要求
#   `:tracks/archive/<t>/decision.json` 仍在 index(它已经随 mv 到 active 路径)⇒ 拦,
#   而且报的是一句与实情无关的"不许删除或降级 legacy"。
#   **取回正是 archive_drift 那条 BLOCK 自己让人走的路** —— 闸在拦自己给的药方。
#   这单开单的理由就是"闸给的药方无效",所以这一条必须钉住:①放行合法取回,
#   ②③ 同时挡住它可能开出的两个洞(移动中降级 legacy / 真删除)。
g13_unarchiving_is_not_a_deletion() {
  echo '[G13] 取回(mv 出 archive)不是删除 —— 但降级和真删除仍要拦'
  local d rc

  # ① 合法取回:带着一笔就地改把整份档案搬回 active。这正是 archive_drift 的 BLOCK
  #    让操作者走的第一步,闸必须放行。
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    { verify_with "**PASS**(主裁)"; printf -- '- 无机器证据:夹具\n'; } > tracks/archive/t/verify.md
    typed_decision '"self"' > tracks/archive/t/decision.json
    printf '# Design\n' > tracks/archive/t/design.md
    git add -A >/dev/null; git commit -qm archived >/dev/null
    printf '# Design\n\n归档后发现要改正文\n' > tracks/archive/t/design.md
    git add tracks/archive/t/design.md >/dev/null
    git mv tracks/archive/t tracks/t >/dev/null 2>&1
    git add -A >/dev/null )
  (cd "$d" && "$GUARD" >/dev/null 2>&1)
  check 'G13: 带着就地改取回 ⇒ 放行(闸不许拦自己给的药方)' $?
  rm -rf "$d"

  # ② 洞一:借取回之名让 decision.json 消失(typed 降级成 legacy)。
  #    题面 2026-09-09 修正过一次:第一版写的是"active 路径放一份 schema_version=1",
  #    但夹具的 typed_decision 本来就是 schema 1,而这道闸判 typed 只看
  #    decision.json 在不在、不看版本 ⇒ 那一版里 ① 和 ② 的实际行为**完全相同**,
  #    ② 的绿是"豁免根本没生效"换来的假绿,不是"豁免挡住了降级"。
  #    真正的降级形状是:搬出 archive 的同时把 decision.json 删掉。
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    { verify_with "**PASS**(主裁)"; printf -- '- 无机器证据:夹具\n'; } > tracks/archive/t/verify.md
    typed_decision '"self"' > tracks/archive/t/decision.json
    git add -A >/dev/null; git commit -qm archived >/dev/null
    git mv tracks/archive/t tracks/t >/dev/null 2>&1
    git rm -qf tracks/t/decision.json >/dev/null
    git add -A >/dev/null )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G13: 取回时降级成 legacy ⇒ 仍然拦' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  # ③ 洞二:真删除 —— archive 里删掉 decision.json,active 路径也没有。
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/archive/t
    { verify_with "**PASS**(主裁)"; printf -- '- 无机器证据:夹具\n'; } > tracks/archive/t/verify.md
    typed_decision '"self"' > tracks/archive/t/decision.json
    git add -A >/dev/null; git commit -qm archived >/dev/null
    git rm -q tracks/archive/t/decision.json >/dev/null )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G13: 真删除 typed decision ⇒ 仍然拦' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"
}

# --------------------------------------------------------------- G14
# 为什么加这一组(2026-09-09 第三轮 panel,subkimi 提出,主裁亲手复现):
#   G13① 放行"取回"用的尺子是 `git cat-file -e ":tracks/<name>/decision.json"` ——
#   它查的是 **index 里有没有**,不是"本次 staged 真的在把整份档案搬出去"。
#   而 index 里装着**全部已提交文件**,不只是这次改的。于是:
#     ① 删掉 archive 的 decision.json + 在 active 路径摆一份同名的,就能在同一笔提交里
#        **顺手改掉归档正文**,豁免照样命中 ⇒ G12 的归档复验和 G13③ 的"不许删除"一起失效;
#     ② 这笔一旦落库,`tracks/<name>/decision.json` 就常驻 index ⇒ 此后**每一笔**改
#        `tracks/archive/<name>/**` 的提交都命中豁免,连往归档里塞一份伪造收据都放行。
#   正确的尺子要两个条件同时成立:archive 侧在 index 里**已经搬空**,且 active 侧有
#   decision.json。少任何一个都照旧拦(G13②③ 是那两侧的对照)。
#
# 🔴 夹具为什么必须把归档提交**改成 8 个月前**:规矩2 的 `verifies` 里有一条
#   `git log --since='7 days ago' -- 'tracks/*/verify.md'`,它会把**刚建的**归档
#   verify.md 也捞进来,于是攻击在到达豁免那段之前就被那张网拦下 —— 断言照样绿,
#   但绿的理由是"归档是新的",不是"豁免守住了"。真实归档都是旧的,那张网碰不到。
#   (主裁第一版夹具没改日期,攻击一 rc=1,差点把这个洞判成不成立。)
aged_archive() {  # aged_archive <repo> —— 造一份 8 个月前归档的 typed track
  # 🔴 夹具必须带 evidence/ observations/ 子目录:**每一个真实 track 都长这样**,
  #   而平铺的夹具会让 G14④ 那条"药方走得通"永远绿 —— 子目录在目标侧不存在时
  #   `git mv` 直接 rc=128 fatal(主裁 2026-09-09 第四轮派发前亲跑探针复现;
  #   这是本单第 5 句坏药方,前四句见 bin/track-guard 与本文件的注释)。
  ( cd "$1"; mkdir -p tracks/archive/t/evidence tracks/archive/t/observations
    { verify_with "**PASS**(主裁)"; printf -- '- 无机器证据:夹具\n'; } > tracks/archive/t/verify.md
    typed_decision '"self"' > tracks/archive/t/decision.json
    printf '# Design\n' > tracks/archive/t/design.md
    printf 'runlog: fixture rc=0\n' > tracks/archive/t/evidence/20260105T000000Z-01-suite.txt
    # 观测要用**合法事件**:随手写一个 {"schema_version":1} 会被 observation shape 那道闸
    # 拦下,红的理由就不是这一组要问的事了(主裁第一版夹具就是这样,G14③ 红在别处)。
    cat > tracks/archive/t/observations/20260105T000000Z-runlog-execution_finished-001.json <<'OBS'
{
  "schema_version": 1,
  "track": "t",
  "run_id": "20260105T000000Z-01-fixture",
  "controller": "runlog",
  "event": "execution_finished",
  "label": "fixture",
  "started_at": "2026-01-05T00:00:00Z",
  "finished_at": "2026-01-05T00:00:01Z",
  "duration_ms": 1000,
  "exit_code": 0,
  "actual": {"adapter": "runlog", "model": null, "risk": null, "degraded": null,
             "work_exit_code": 0, "legs": null},
  "usage": {"input_tokens": null, "output_tokens": null, "total_tokens": null,
            "api_cost": null, "billing_mode": null}
}
OBS
    git add -A >/dev/null
    GIT_AUTHOR_DATE="2026-01-05T10:00:00" GIT_COMMITTER_DATE="2026-01-05T10:00:00" \
      git commit -qm archived >/dev/null )
}

g14_exemption_cannot_shield_archive_tampering() {
  echo '[G14] 取回豁免不许被借来放行 archive 侧的篡改(index≠staged)'
  local d rc

  # ① 假取回:删 archive 的 decision + active 摆一份同名的 + 同一笔改掉归档正文。
  #    archive 侧还剩 design.md/verify.md ⇒ 根本不是"整份搬出",必须拦。
  d="$(newrepo)"; aged_archive "$d"
  ( cd "$d"
    printf '# Design\n\nTAMPERED:归档后改正文,没有任何新评审\n' > tracks/archive/t/design.md
    git rm -q --cached tracks/archive/t/decision.json >/dev/null; rm -f tracks/archive/t/decision.json
    mkdir -p tracks/t; typed_decision '"self"' > tracks/t/decision.json
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    git add -A >/dev/null )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G14①: 假取回(archive 侧有残留)借豁免改归档正文 ⇒ 仍然拦' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  # ② 永久化:①的状态一旦落库,active 的 decision.json 就常驻 index。此后再改归档
  #    (连伪造一份 evidence 收据)也必须拦 —— 豁免不能变成这个 track 名的永久通行证。
  d="$(newrepo)"; aged_archive "$d"
  ( cd "$d"
    git rm -q --cached tracks/archive/t/decision.json >/dev/null; rm -f tracks/archive/t/decision.json
    mkdir -p tracks/t; typed_decision '"self"' > tracks/t/decision.json
    printf '# Verify\n- findings: pending\n' > tracks/t/verify.md
    git add -A >/dev/null
    GIT_AUTHOR_DATE="2026-01-06T10:00:00" GIT_COMMITTER_DATE="2026-01-06T10:00:00" \
      git commit -qm 'fake unarchive' >/dev/null
    printf '# Design\n\nTAMPERED AGAIN:第二刀\n' > tracks/archive/t/design.md
    mkdir -p tracks/archive/t/evidence
    printf 'forged receipt: rc=0 PASS=999 FAIL=0\n' > tracks/archive/t/evidence/forged.txt
    git add -A >/dev/null )
  (cd "$d" && "$GUARD" >/dev/null 2>&1); rc=$?
  check 'G14②: 豁免落库后再改归档/塞伪造收据 ⇒ 仍然拦(豁免不是永久通行证)' $([[ $rc -ne 0 ]]; echo $?)
  rm -rf "$d"

  # ③ 反误报对照:同样是**旧**归档的合法取回(整份 git mv 出去 + 一笔就地改)。
  #    G13① 那份夹具是新归档,会被 7 天网顺手放过;这一条证明放行不靠那张网。
  d="$(newrepo)"; aged_archive "$d"
  ( cd "$d"
    printf '# Design\n\n归档后发现要改正文\n' > tracks/archive/t/design.md
    git add tracks/archive/t/design.md >/dev/null
    git mv tracks/archive/t tracks/t >/dev/null 2>&1
    git add -A >/dev/null )
  (cd "$d" && "$GUARD" >/dev/null 2>&1)
  check 'G14③: 旧归档的合法取回(整份搬出)⇒ 仍然放行' $?
  rm -rf "$d"

  # ④ 药方必须**走得通**:把闸自己打印的那几行 git mv 原样执行一遍,再跑一次闸,
  #    必须放行。这单的开单理由就是"闸给的药方无效",到这里已经写坏过三句;
  #    第一版这句写的是 `git mv tracks/archive/t tracks/t`,而目标目录已存在时
  #    git 会把整个目录塞成 tracks/t/t/ 并且 **rc=0**(主裁亲跑复现)——
  #    文案断言("消息里有没有出现某个词")照样绿,只有真执行才照得出来。
  #    夹具形状:归档正文改了一笔(**这才让 archive 目录进得了复验名单** —— 只搬走
  #    decision.json 的话,它在 staged 里以 R100 的**目标**路径出现,archive 侧一个
  #    路径都不进 staged,这段代码根本不会被叫起来;主裁第一版夹具就是这样,
  #    G14④ 红在"没给药方",而真相是压根没走到那里)。
  d="$(newrepo)"; aged_archive "$d"
  ( cd "$d"; mkdir -p tracks/t
    printf '# Design\n\n归档后发现要改正文\n' > tracks/archive/t/design.md
    git mv tracks/archive/t/decision.json tracks/t/decision.json >/dev/null 2>&1
    git add -A >/dev/null )
  local out advice broken crc
  out="$( cd "$d" && "$GUARD" 2>&1 )"; rc=$?
  check 'G14④前置: 半截取回(只搬走 decision)⇒ 拦' $([[ $rc -ne 0 ]]; echo $?)
  # 药方按**整行**抓、按整行执行 —— 上一版拿 `grep -oE 'git mv [^ ]+ [^ ]+'` 抠片段,
  # 等于替闸把它没写的部分(比如目标子目录还得先建)在判据里补齐了:闸写坏了也照样绿。
  advice="$(printf '%s\n' "$out" | sed -nE 's/^track-guard: +((mkdir -p|git mv) .*)$/\1/p')"
  if [[ -z "$advice" ]]; then
    bad 'G14④: BLOCK 里没给出可执行的 git mv 药方'
  else
    local broken=0 crc
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      ( cd "$d" && bash -c "$cmd" >/dev/null 2>&1 ); crc=$?
      [[ $crc -eq 0 ]] || { broken=$((broken+1)); echo "      (药方这一句 rc=$crc:$cmd)"; }
    done <<< "$advice"
    check 'G14④a: 药方每一句都真的执行得下去(rc=0,不是靠判据替它补齐)' $([[ $broken -eq 0 ]]; echo $?)
    ( cd "$d" && git add -A >/dev/null )
    ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
    check 'G14④: 照抄闸打印的药方执行一遍 ⇒ 闸放行(药方真走得通)' $?
    # 顺带钉住"别再写出会嵌套的那句":药方不许把整个目录搬到已存在的目标上
    if printf '%s\n' "$out" | grep -qE 'git mv tracks/archive/[^/ ]+ tracks/[^/ ]+$'; then
      bad 'G14④: 药方写成了整目录 mv(目标已存在时会静默嵌套成 tracks/<n>/<n>/)'
    else
      ok 'G14④: 药方不是整目录 mv(不会静默嵌套)'
    fi
  fi
  rm -rf "$d"

  # ⑤ 药方对**带空格 / 非 ASCII 的文件名**也必须照抄就能跑。
  #    这不是理论边角:本仓的正文全是中文,`设计文档.md` 这种名字完全现实,
  #    而 `git ls-files` 默认会把非 ASCII 路径 C-quote 成 "\346\224\266...",
  #    空格则原样输出 —— 两种都会让不加引号的药方当场断在 word-split 上。
  #    (2026-09-09 第四轮 subdeepseek 提出并实测,主裁逐条复现。)
  d="$(newrepo)"; aged_archive "$d"
  ( cd "$d"; mkdir -p tracks/t "tracks/archive/t/evidence"
    printf 'x\n' > "tracks/archive/t/evidence/我的 设计文档.md"
    git add -A >/dev/null
    GIT_AUTHOR_DATE="2026-01-05T11:00:00" GIT_COMMITTER_DATE="2026-01-05T11:00:00" \
      git commit -qm 'archived with a chinese filename' >/dev/null
    printf '# Design\n\n归档后发现要改正文\n' > tracks/archive/t/design.md
    git mv tracks/archive/t/decision.json tracks/t/decision.json >/dev/null 2>&1
    git add -A >/dev/null )
  out="$( cd "$d" && "$GUARD" 2>&1 )"
  advice="$(printf '%s\n' "$out" | sed -nE 's/^track-guard: +((mkdir -p|git mv|git checkout) .*)$/\1/p')"
  broken=0
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    ( cd "$d" && bash -c "$cmd" >/dev/null 2>&1 ); crc=$?
    [[ $crc -eq 0 ]] || { broken=$((broken+1)); echo "      (药方这一句 rc=$crc:$cmd)"; }
  done <<< "$advice"
  check 'G14⑤: 文件名带空格/非 ASCII 时,药方每一句照样跑得通' $([[ $broken -eq 0 && -n "$advice" ]]; echo $?)
  ( cd "$d" && git add -A >/dev/null )
  ( cd "$d" && "$GUARD" >/dev/null 2>&1 )
  check 'G14⑤: 执行完之后闸放行(中文文件名也真的搬过去了)' $?
  rm -rf "$d"

  # ⑥ 残件**在 index 里、工作树里已经没有**时,`git mv` 是 rc=128 "bad source"。
  #    闸列残件用的是 index 视图(条件② 同一把尺),所以它列得出、却搬不动 ——
  #    又一句走不通的药方,和本单开单理由同型。
  d="$(newrepo)"; aged_archive "$d"
  ( cd "$d"; mkdir -p tracks/t
    printf '# Design\n\n归档后发现要改正文\n' > tracks/archive/t/design.md
    git mv tracks/archive/t/decision.json tracks/t/decision.json >/dev/null 2>&1
    git add -A >/dev/null
    rm -f tracks/archive/t/verify.md )   # 工作树没了,index 里还在
  out="$( cd "$d" && "$GUARD" 2>&1 )"
  advice="$(printf '%s\n' "$out" | sed -nE 's/^track-guard: +((mkdir -p|git mv|git checkout) .*)$/\1/p')"
  broken=0
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    ( cd "$d" && bash -c "$cmd" >/dev/null 2>&1 ); crc=$?
    [[ $crc -eq 0 ]] || { broken=$((broken+1)); echo "      (药方这一句 rc=$crc:$cmd)"; }
  done <<< "$advice"
  check 'G14⑥: 残件只在 index、工作树已删时,药方仍然走得通' $([[ $broken -eq 0 && -n "$advice" ]]; echo $?)
  rm -rf "$d"
}

# --------------------------------------------------------------- G15
# 为什么加这一组(2026-09-09 第四轮,subdeepseek 提出,主裁在真实路径上复现):
#   `bin/track archive` 那一步是裸 `mv "$src" "tracks/archive/$name"`。POSIX mv 在
#   **目标目录已存在**时不是失败,而是把整个目录**塞进去** —— 落成
#   `tracks/archive/<n>/<n>/` 并且 rc=0。这和本单第 4 句坏药方是同一个陷阱,
#   只是触发者换成了"上一次取回留下的未跟踪残留"(git mv 只搬跟踪文件,
#   未跟踪的会留在原地 ⇒ 归档目录物理上还在,而 index 视图里它是空的)。
g15_archive_refuses_when_destination_exists() {
  echo '[G15] track archive 目标目录已存在时必须拒绝,不许静默嵌套'
  local d
  d="$(newrepo)"
  ( cd "$d"; mkdir -p tracks/t
    mk_receipt "$d" tracks/t 20260808T020000Z-suite.txt "$L2"
    verify_ev "**PASS**" '```' "$L2" '```' > tracks/t/verify.md
    mkdir -p tracks/archive/t; printf 'stale\n' > tracks/archive/t/leftover.txt )  # 未跟踪残留
  "$TRACK" archive t "$d" >/dev/null 2>&1
  check 'G15: 目标目录已存在 ⇒ archive 命令拒绝' $([[ $? -ne 0 ]]; echo $?)
  [[ ! -e "$d/tracks/archive/t/t" ]]
  check 'G15: 没有静默嵌套出 tracks/archive/t/t/' $?
  [[ -d "$d/tracks/t" ]]
  check 'G15: 被挡下时目录留在原地' $?
  rm -rf "$d"
}

echo "=== track-guard oracle ==="
g1_version_lives_where_the_product_says
g2_verdict_must_be_filled_at_archive
g2_list_surfaces_unjudged_tracks
g3_archive_command_itself_blocks
r_existing_rules_still_hold
g4_known_blind_spots
g5_tooling_changes_need_a_track
g6_pasted_numbers_must_be_the_machines_numbers
g6_archive_needs_the_last_run
g7_archive_command_checks_evidence_too
g8_archive_mode_only_when_actually_archiving
g8_every_red_run_must_be_quoted
g8_bold_wrapped_paste_is_fine
g8_round2_false_positive_shapes
g8_track_new_rejects_path_names
g9_typed_shape_uses_staged_decision
g10_manual_typed_archive_uses_staged_facts
g11_archived_machine_facts_stay_typed
g12_archived_prose_edits_get_revalidated
g13_unarchiving_is_not_a_deletion
g14_exemption_cannot_shield_archive_tampering
g15_archive_refuses_when_destination_exists
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]

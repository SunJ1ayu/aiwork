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
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]

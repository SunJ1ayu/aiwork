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

  # ② 填了真结论再归档 —— 放行
  ( cd "$d"; verify_with "**PASS**(主裁)" > tracks/archive/t/verify.md; git add -A >/dev/null )
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
  ( cd "$d"; mkdir -p tracks/t; verify_with "**PASS**(主裁)" > tracks/t/verify.md )
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

echo "=== track-guard oracle ==="
g1_version_lives_where_the_product_says
g2_verdict_must_be_filled_at_archive
g2_list_surfaces_unjudged_tracks
g3_archive_command_itself_blocks
r_existing_rules_still_hold
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# 红检:把 subgemini 的实现**故意改坏**,看 V46 咬不咬得住。
#
# 存在的理由:V46 十条全绿只说明"现在没红",不说明"改坏了会红"。
# 本机记过账的是一整族病:永远绿的瞎断言、锚点过期、拿文本位置冒充代码结构。
# 每个变异点名**它该打红哪一条**;打不红 = 那条断言是摆设,当场报漏网。
# **锚点没命中也算漏网** —— 锚点过期本身就是问题(本机记过 4 次)。
#
# ⚠️ 取舍:完整 oracle(tests/test-review-tooling.sh)跑一遍 ~5 分钟,十个变异点
# 就是 50 分钟。这里**只提取 V46 那一个函数**跑,单次几秒。代价是"提取出来的
# 跑法"可能和它在完整 oracle 里的跑法不一致 —— 所以基线那一步会检查:
# 提取版必须跑出十条 PASS、零 FAIL,与完整 oracle 里 V46 段一致,否则拒绝继续。
#
# 🔴 靶子用**断言编号**(V46①)而不是断言全文。第一版用了 PASS 那句的全文,
# 结果十条里七条被报成「漏网」,全是假的:V46 的 ok/bad 是**两套措辞**
# (失败时印更有用的信息),靶子取自 PASS 却拿去 FAIL 里找 ⇒ 永远匹配不上。
# 量具坏的方向是「把真咬住的报成漏网」—— 比反过来安全,但一样得修。
# 同族前科:08-23 靶子当正则(断言名里的 markdown 星号变量词)。
#
# 变异用 heredoc 喂给 python,不走 `python3 -c "..."` —— 后者的嵌套引号既容易
# 写坏,又会把注释里的反引号交给 shell 真执行(08-19 实证)。
set -uo pipefail
export ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORACLE_FILE="$ROOT/tests/test-review-tooling.sh"
TARGETS=("$ROOT/bin/subgemini" "$ROOT/bin/_panel-roster-lib.sh")

# ── 被砍也要还原,还原不成要留下痕迹 ───────────────────────────────────────
# 🔴 2026-08-26 实事故:这个脚本跑超时被外层 SIGTERM 砍掉,而 **bash 的 EXIT trap
# 在被信号打死时不执行** ⇒ M13 的变异(`write_agy_settings "$REPO_DIR"` 改成
# `"$SOURCE_REPO"`)**留在了工作树里**。我随后扫了一遍变异特征、恰好漏掉那一条,
# 于是写下"文件是干净的";接下来两次判据都是 25/2,我先怀疑并发、又怀疑锁,
# 查了三轮才发现红的是**我自己被污染的实现**。差一步就把它提交上去。
#
# ⇒ 两道:① INT/TERM/HUP 也还原(EXIT 一个不够);
#         ② 还原不成时留一份 inflight 痕迹,**下一次拒绝再跑**并说清楚 ——
#           不许让下一个人对着一份被变异过的实现去查判据。
STATE_DIR="${MUTATION_STATE_DIR:-$ROOT/.mutation-state}"
INFLIGHT="$STATE_DIR/mutation-subgemini.inflight"
mkdir -p "$STATE_DIR"
if [[ -e "$INFLIGHT" ]]; then
  echo "🔴 上一轮红检**没跑完就被砍了**(痕迹:$INFLIGHT)⇒ 拒绝再跑。"
  echo "   靶子文件可能还留着变异,而变异过的实现看起来只是"判据莫名其妙红了"。"
  echo "   先做这三件事:"
  echo "     1) 看 \`git diff\` 里的靶子文件,确认它们是**你自己写的那一版**;"
  echo "     2) 对不上就从痕迹里记的备份还原,或 git checkout;"
  echo "     3) 确认干净之后删掉 $INFLIGHT 再跑。"
  echo "   痕迹内容:"; sed 's/^/     /' "$INFLIGHT"
  exit 3
fi
# 只做上面那道自检就退出(判据 V46⑰ 用它,不必真跑一轮变异)
[[ -n "${MUTATION_SELFCHECK:-}" ]] && { echo "自检:没有未收尾的红检痕迹,可以跑。"; exit 0; }

declare -A BEFORE
for f in "${TARGETS[@]}"; do BEFORE["$f"]="$(sha256sum "$f" | cut -d' ' -f1)"; done
BACKUP="$(mktemp -d)"
for f in "${TARGETS[@]}"; do cp "$f" "$BACKUP/$(basename "$f")"; done
{ echo "started=$(date -Is) pid=$$"
  echo "backup=$BACKUP"
  for f in "${TARGETS[@]}"; do echo "pristine ${BEFORE[$f]} $f"; done
} > "$INFLIGHT"
restore() { for f in "${TARGETS[@]}"; do cp -f "$BACKUP/$(basename "$f")" "$f"; done; }
_finish() { restore; rm -f "$INFLIGHT"; rm -rf "$BACKUP"; }
trap '_finish' EXIT
# 信号那一路:还原之后**用信号本来的码退出**,别假装成功。
trap '_finish; trap - INT TERM HUP; kill -s INT $$' INT
trap '_finish; trap - INT TERM HUP; kill -s TERM $$' TERM
trap '_finish; trap - INT TERM HUP; kill -s HUP $$' HUP

run_oracle() {   # 只跑 V46 那一段
  { echo 'PASS=0; FAIL=0'
    echo 'ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }'
    echo 'bad(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }'
    echo 'check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }'
    awk '/^v46_subgemini_leg\(\) \{/,/^\}/' "$ORACLE_FILE"
    echo 'REVIEW_NO_MY_REVIEW=1 v46_subgemini_leg'
    echo 'echo "TOTALS $PASS $FAIL"'
  } | bash 2>&1
}

BIT=0; MISS=0
BASELINE="$(run_oracle)"
base_totals="$(grep '^TOTALS' <<<"$BASELINE" | tail -1)"
base_pass="$(awk '{print $2}' <<<"$base_totals")"
base_fail="$(awk '{print $3}' <<<"$base_totals")"
# 🔴 基线**只问"零红"**,不再写死条数(2026-08-26,四审两条腿各自命中)。
# 上一版硬编码 `TOTALS 17 0`:V46 从 17 条长到 19 条那天,红检就开始
# 「🔴 基线不是十七绿零红 ⇒ 拒绝跑红检」并退出 2 —— **16 个变异点一个都没再跑过**,
# 而 commit 里那句"16 咬 0 漏"在 HEAD 上已经不可复现。
# 条数是**另一处的事实的拷贝**(判据文件说了算),抄过来就会过期;
# 红检真正需要的前提只有一个:开跑时不许带着红(否则分不清「变异咬红的」和
# 「本来就红的」)。本机为"锚点过期本身就是问题"记过 4 次账,这次是它自己犯。
if [[ ! "$base_pass" =~ ^[0-9]+$ || ! "$base_fail" =~ ^[0-9]+$ ]]; then
  echo "🔴 基线跑不出 TOTALS 行($base_totals)⇒ 拒绝跑红检(提取版自己就坏了)。"
  printf '%s\n' "$BASELINE"; exit 2
fi
if [[ "$base_fail" -ne 0 || "$base_pass" -eq 0 ]]; then
  echo "🔴 基线不是零红($base_totals)⇒ 拒绝跑红检。"
  echo "   带着红跑红检,分不清「变异咬红的」和「本来就红的」。"
  printf '%s\n' "$BASELINE"; exit 2
fi
echo "基线: $base_totals(提取版 $base_pass 条断言全绿)"

mutate() {  # mutate <编号> <该打红的断言关键字>   (python 从 stdin 喂)
  local id="$1" target="$2" py out
  py="$(cat)"
  # 一律 grep -F(字面),不许把靶子当正则:断言名里的 markdown 星号会被 BRE
  # 读成量词 ⇒ 一条**真咬住了**的变异被报成漏网(08-23 实证,红检工具自己坏过)。
  if ! grep "PASS:" <<<"$BASELINE" | grep -qF -- "$target"; then
    echo "  [漏网] $id 的靶子「$target」在基线里压根不是一条断言 —— **靶子名过期**"
    MISS=$((MISS+1)); return
  fi
  restore
  if ! printf '%s' "$py" | python3 - ; then
    echo "  [漏网] $id 的锚点没命中 —— **锚点过期本身就是问题**"; MISS=$((MISS+1)); restore; return
  fi
  out="$(run_oracle)"
  if grep "FAIL:" <<<"$out" | grep -qF -- "$target"; then
    echo "  [咬住] $id ⇒ 「$target」"; BIT=$((BIT+1))
  else
    echo "  [漏网] $id 改坏了实现,但「$target」没红 —— 那条断言是摆设"
    MISS=$((MISS+1))
  fi
  restore
}

echo "── 红检开始 ──────────────────────────────────────────"

mutate M1 "V46①" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old="""case "$MODEL" in
  gemini-*) ;;"""
new="""case "$MODEL" in
  gemini-*|claude-*|gpt-*) ;;"""
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY

mutate M2 "V46②" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='DEFAULT_MODEL="gemini-3.7-flash-high"'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'DEFAULT_MODEL="gemini-3.1-pro-high"'))
PY

mutate M3 "V46③" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='cp "$OWNER_TOKEN" "$AGY_HOME_DIR/antigravity-oauth-token"'
new='ln -s "$OWNER_TOKEN" "$AGY_HOME_DIR/antigravity-oauth-token"'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY

mutate M4 "V46④" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='"enableTelemetry": false,'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'"enableTelemetry": true,'))
PY

mutate M5 "V46⑤" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old="""[[ $HAS_VERDICT -eq 1 ]] \\
  || die "model returned no verdict"""
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,"""[[ 1 -eq 1 ]] \\
  || die "model returned no verdict"""))
PY

mutate M6 "V46⑥" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='[[ "$MODE" == "review" ]] || { usage; exit 2; }'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'true'))
PY

mutate M7 "V46⑦" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='--add-dir "$REPO_DIR" \\\n    --output-format text'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'--output-format text'))
PY

mutate M8 "V46⑧a" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/_panel-roster-lib.sh'; s=open(p,encoding='utf-8').read()
old='  "subgemini|google|subgemini||PANEL_GEMINI_LEG"\n'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,''))
PY

# ── 08-26 新增:四审那六条发现各自配一个变异点 ────────────────────────────
# 它们都在修复前**真的红过**(收据 20260826T005701Z),这里是为了防**以后**回退。
mutate M16 "V46⑧c" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/_panel-roster-lib.sh'; s=open(p,encoding='utf-8').read()
old='"subgemini|google|subgemini||PANEL_GEMINI_LEG"'
new='"subgemini|gemini|subgemini||PANEL_GEMINI_LEG"'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY

mutate M17 "V46⑫" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='env HOME="$REVIEW_HOME" "${RO_EXEC[@]}" timeout "$TIMEOUT_SECONDS"'
new='env HOME="$REVIEW_HOME" timeout "$TIMEOUT_SECONDS"'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY

mutate M18 "V46⑬" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='_subgemini_wipe_token() { rm -f "$AGY_HOME_DIR/antigravity-oauth-token"; }'
new='_subgemini_wipe_token() { :; }'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY

mutate M19 "V46⑭" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='flock -n 9 || die "另一条 subgemini'
new='true || die "另一条 subgemini'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY

mutate M20 "V46⑮" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='[[ -f "$TASK_FILE" ]] || die "task file not found'
new='[[ -f "$TASK_FILE" ]] || true || die "task file not found'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY

mutate M21 "V46⑯" <<'PY'
import os,sys,re
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
# 锚点必须咬**超时那一支里**的横幅块。上一版只写"第一个 { echo ... } >> LOG_FILE",
# 而我后来在它前面加了"捞报告"块 ⇒ 变异删错了块,红检当场报 M21 漏网。
# 锚点漂移的第 N 次:锚点要认**它所在的那段逻辑**,不是认形状。
i = s.index('if [[ $RC -eq 124 ]]; then')
m = re.search(r'\n  \{ echo\n(?:.*\n)*?  \} >> "\$LOG_FILE"\n', s[i:])
if not m: sys.exit(1)
seg = s[i:][m.start():m.end()]
if 'TIMEOUT_SECONDS' not in seg: sys.exit(1)
open(p,'w',encoding='utf-8').write(s[:i+m.start()]+'\n'+s[i+m.end():])
PY
mutate M9a "V46⑨a" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='my_review_gate "$MODE" "$TASK_FILE" "$REPO_DIR" "subgemini" || exit 1'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'true'))
PY

mutate M9b "V46⑨b" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='review_home_guard subgemini "$REVIEW_HOME" "$SOURCE_REPO" AGY_REVIEW_HOME || exit 1'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'true'))
PY

mutate M10 "V46③" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='chmod 600 "$AGY_HOME_DIR/antigravity-oauth-token"'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'chmod 644 "$AGY_HOME_DIR/antigravity-oauth-token"'))
PY

mutate M11 "V46⑩a" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='"command(git log)",\n      "command(git diff)",'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,''))
PY

mutate M12 "V46⑪a" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='scoped="\\"read_file($ws)\\", \\"write_file($ws)\\", "'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'scoped="\\"read_file(*)\\", \\"write_file(*)\\", "'))
PY

mutate M13 "V46⑪b" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='write_agy_settings "$REPO_DIR"'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'write_agy_settings "$SOURCE_REPO"'))
PY

mutate M14 "V46⑩c" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='"command(git log)",\n      "command(git diff)",'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'"command(git (log|diff))",'))
PY

mutate M15 "V46⑩d" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old='"command(git log)",'
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,'"command(cat)", "command(git log)",'))
PY

mutate M23 "V46㉑" <<'PY'
import os,sys
p=os.environ['ROOT']+'/bin/subgemini'; s=open(p,encoding='utf-8').read()
old="- NO PIPES, NO REDIRECTS, NO CHAINING. 'git diff X | grep Y'"
new="- NO PIPES, NO REDIRECTS, NO CHAINING. \\`git diff X | grep Y\\`"
if s.count(old)!=1: sys.exit(1)
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY

echo "──────────────────────────────────────────────────────"
echo "红检结果: 咬住 $BIT 条,漏网 $MISS 条"
restore
rm -f "$INFLIGHT"
drift=0
for f in "${TARGETS[@]}"; do
  now="$(sha256sum "$f" | cut -d' ' -f1)"
  [[ "$now" == "${BEFORE[$f]}" ]] || { echo "🔴 $f 没还原回去!"; drift=1; }
done
[[ $drift -eq 0 ]] && echo "所有靶子文件逐字节还原 ✓"
[[ $MISS -eq 0 && $drift -eq 0 ]]

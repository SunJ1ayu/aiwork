#!/usr/bin/env bash
# 红检:把"评审证据绑定交付内容"这道闸逐条放松,看判据咬不咬得住。
#
# 存在的理由(2026-09-09,track review-delivery-binding):
# 实现是我接手前别人写的,11 条判据当时**全绿** —— 但那只证明"实现在场",
# 不证明"判据咬得动"。归档闸是判卷防线,放松一格的后果是旧评审继续授权新交付,
# 而它不会有任何症状。所以每条豁免/比较都要有一条判据单独钉住。
#
# 🔴 变异只许"放松一格",不许制造崩溃:红在 ERROR 上 = 红在别处 = 等于没红检过。
# 🔴 全程只动 $work 下的副本,绝不在仓里就地变异(靶子还原失败是本机踩过的坑)。
#
# 没放进来的两条,连同理由,记在 tracks/review-delivery-binding/verify.md:
# 双扫描稳定性检查、历史归档用原始提交树 —— 两者放松后都是**响亮失败**(归档全红),
# 不是静默放行;钉它们要造 PATH 里的 git 桩,收益不抵那份夹具的维护成本。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORACLE="$ROOT/tests/test_review_delivery.py"
PASS=0; FAIL=0
ok()  { printf '  PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/tests"
# 静默 cp 会把"少抄了一个文件"变成"守卫没生效但 judge 照跑" ⇒ 一律不吞错。
cp "$ROOT/bin/_review_delivery.py" "$ROOT/bin/_review_result.py" \
   "$ROOT/bin/track-record" "$ROOT/bin/track" \
   "$ROOT/bin/_evidence.sh" "$ROOT/bin/_ephemeral-refs.sh" "$work/bin/"
cp "$ORACLE" "$ROOT/tests/_no_egress.py" "$work/tests/"

if python3 "$work/tests/test_review_delivery.py" >"$work/base.log" 2>&1; then
  ok "基线(未变异)判据全绿"
else
  bad "基线就红了 ⇒ 本次红检无效($(tail -3 "$work/base.log" | tr '\n' ' '))"
  printf -- '---- 合计 PASS=%s FAIL=%s ----\n' "$PASS" "$FAIL"; exit 1
fi

mutate() {  # mutate <名字> <靶子文件> <该被打红的测试名> <old=>new>
  local name="$1" file="$2" target="$3" patch="$4" out
  cp "$ROOT/bin/$file" "$work/bin/$file"
  if ! MUT_PATCH="$patch" MUT_FILE="$work/bin/$file" python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ["MUT_FILE"]); s = p.read_text(encoding="utf-8")
old, new = os.environ["MUT_PATCH"].split("=>", 1)
if old not in s:
    raise SystemExit(3)
p.write_text(s.replace(old, new, 1), encoding="utf-8")
PY
  then
    bad "$name: 锚点没命中(实现改过、变异没生效)⇒ 这次红检什么都没证明"
    return
  fi
  out="$(python3 "$work/tests/test_review_delivery.py" 2>&1)"
  cp "$ROOT/bin/$file" "$work/bin/$file"
  if [[ "$out" == *"FAIL: $target"* ]]; then
    ok "$name ⇒ 打红了 $target"
  elif [[ "$out" == *"ERROR: $target"* ]]; then
    bad "$name ⇒ $target 红在异常上(ERROR),不是断言 —— 变异制造了崩溃,重写变异"
  elif [[ "$out" == *"OK"* && "$out" != *FAIL* ]]; then
    bad "$name ⇒ **判据全绿放行**:$target 没咬住这条"
  else
    bad "$name ⇒ 红了,但没红在 $target 上($(printf '%s' "$out" | grep -E '^(FAIL|ERROR):' | head -1))"
  fi
}

mutate "归档比较恒真(任何评审都算绑定)" track-record \
  "test_archive_rejects_stale_review_and_accepts_closeout" \
  '                if subject.get("delivery") == {"policy_version": 1, "track": data["track"], "digest": digest}:=>                if True:'

mutate "v2 也当 legacy 早退(整道闸静默关掉)" track-record \
  "test_unbound_historical_review_does_not_authorize_v2" \
  '    if data["schema_version"] == 1:
        return "legacy-unbound"=>    if True:
        return "legacy-unbound"'

mutate "整个 track 目录都不承重(前提探索否决过的宽豁免)" _review_delivery.py \
  "test_source_and_oracle_changes_invalidate" \
  '            if suffix == b"verify.md":=>            if suffix is not None:'

mutate "tasks.md 归一化连正文一起抹掉" _review_delivery.py \
  "test_risk_task_text_and_fake_receipt_cannot_hide" \
  'rb"(?m)^(\s*[-*] )\[[ xX]\]( )", rb"\1[ ]\2"=>rb"(?m)^(\s*[-*] )\[[ xX]\]( ).*", rb"\1[ ]\2"'

mutate "收据只看名字不看内容(塞什么都能豁免)" _review_delivery.py \
  "test_risk_task_text_and_fake_receipt_cannot_hide" \
  '                elif blob.startswith(b"# runlog receipt ") and any(
                        line.startswith(b"runlog: ") for line in blob.splitlines()):=>                elif True:'

mutate "收口豁免不看文件模式(可执行/符号链接也免检)" _review_delivery.py \
  "test_closeout_symlink_or_executable_does_not_get_excluded" \
  '        if suffix is not None and mode == b"100644":=>        if suffix is not None and mode in (b"100644", b"100755", b"120000"):'

# ---- track archive-tree-and-untracked-views(D15/D16)新增的四道行为 ----

mutate "归档复验退回锁第一次归档那棵树(D15 原样)" track-record \
  "test_t1_second_archive_is_not_authorized_by_the_first_archive_tree" \
  '            history = subprocess.run(["git", "-C", str(repo), "log", "--no-renames",
                                      "--diff-filter=A"=>            history = subprocess.run(["git", "-C", str(repo), "log", "--no-renames", "--reverse",
                                      "--diff-filter=A"'

mutate "已归档 track 干脆不钉树(拿今天的源复验历史)" track-record \
  "test_t9_unrelated_repo_changes_after_archiving_stay_green" \
  '            tree = history.stdout.splitlines()[0] + "^{tree}"=>            tree = None'

mutate "归档后漂移比较恒真(单次生命周期也被拦)" track-record \
  "test_t2_single_lifecycle_archive_still_validates" \
  'if archived_then is not None and archived_then != archived_now:=>if archived_then is not None:'

mutate "归档后漂移比较恒假(档案随便改)" track-record \
  "test_t3_delivered_content_edited_after_archiving_is_visible" \
  'if archived_then is not None and archived_then != archived_now:=>if archived_then is not None and archived_then != archived_then:'

mutate "归档后漂移比较扩成全仓(历史档案会自己变红)" _review_delivery.py \
  "test_t9_unrelated_repo_changes_after_archiving_stay_green" \
  '        if scope == "track" and suffix is None:=>        if False and suffix is None:'

mutate "归档漂移不再点名是哪份文件(只剩两个哈希)" track-record \
  "test_t10_archive_drift_names_the_changed_file_not_the_exempt_ones" \
  '            changed = tree_difference(repo, data["track"], tree, source=source)=>            changed = []'

mutate "视图不等的诊断关掉(退回那句错药方)" track-record \
  "test_t5_view_mismatch_names_the_real_cause" \
  '        if alternative is not None and bound(alternative):=>        if alternative is not None and False:'

mutate "诊断照样把那句无效药方粘上" track-record \
  "test_t5_view_mismatch_names_the_real_cause" \
  '                                "cannot close this gap")=>                                "cannot close this gap; rerun panel-review after content changes")'

mutate "track archive 不再拦视图不等(照旧先搬再炸)" track \
  "test_t6_cli_archive_refuses_before_moving_when_views_disagree" \
  '        if [ -n "$views" ]; then=>        if [ -n "" ]; then'

mutate "track archive 只看本 track 的子树(和另一处的答案对不上)" track \
  "test_t11_both_stations_name_the_same_files" \
  '--track "$name" --explain-views=>--track "$name" --scope track --explain-views'

mutate "track archive 见谁拦谁(干净仓也归不了档)" track \
  "test_t7_cli_archive_still_works_on_a_clean_repo" \
  '        if [ -n "$views" ]; then=>        if [ -z "$views" ]; then'

mutate "working 视图不再收未跟踪文件(两视图假装永远一致)" _review_delivery.py \
  "test_t8_two_views_differ_exactly_on_the_dirty_worktree" \
  '            if source == "working":=>            if False:'

mutate "收口记录 verify.md 也算交付内容(归档后补写就被拦)" _review_delivery.py \
  "test_t4_closeout_records_stay_editable_after_archiving" \
  '            if suffix == b"verify.md":
                continue=>            if False:
                continue'

# ---- 第二轮 BLOCK 的修复(2026-09-09):药方不许反着说 ----

mutate "view_mismatch 不分方向(stale 那侧药方就是反的)" track-record \
  "test_t16_stale_content_is_not_reported_as_a_view_mismatch" \
  '    if tree is None and source == "staged":
        other = "working"=>    if tree is None:
        other = "staged" if source == "working" else "working"'

# ---- 第二轮 panel(2026-09-09)挖出的缺口:只有反向断言的判据分不出红在哪 ----

# subdeepseek 的注入实验,原样钉进红检:一刀切拒绝任何第二次归档 ⇒ 合法路径永远
# 走不通,而在补 T12 之前**整套判据仍然全绿**(T1 照样红,只是红的理由换了个人)。
mutate "第二次归档一律拒(合法再归档也走不通)" track-record \
  "test_t12_re_archiving_after_a_fresh_review_is_authorized" \
  '            tree = history.stdout.splitlines()[0] + "^{tree}"=>            adds = history.stdout.splitlines()
            if len(adds) > 1:
                raise DecisionError("observation.review_delivery", "delivery.rearchive", None,
                                    "second archive refused outright")
            tree = adds[0] + "^{tree}"'

# 药方退回"只说 verify.md"那一版 —— 这单开单的病(D16:闸给的药方无效)的同型。
mutate "archive_drift 的药方退回只说 verify.md" track-record \
  "test_t13_archive_drift_block_names_the_legal_way_out" \
  '"place: unarchive it (git mv out of tracks/archive/), edit, rerun "=>"place: write the correction into verify.md instead of, "'

# track-guard 侧的变异器:判据用 TRACK_BIN 认 bin 目录,所以整份 bin 复制出去
# 变异,再让判据指向副本。**绝不在仓里就地变异**(靶子还原失败是本机踩过的坑)。
mutate_guard() {  # mutate_guard <名字> <该被打红的断言名> <old=>new>
  mutate_bin track-guard "$@"
}

# 有些防线不住在 track-guard 里(比如 `track archive` 那句裸 mv),但它们同样是判卷面。
# 变异的是**整份 bin/ 的副本**,判据靠 TRACK_BIN 指过去,所以换个文件名就够。
mutate_bin() {  # mutate_bin <bin 下的文件名> <名字> <该被打红的断言名> <old=>new>
  local file="$1" name="$2" target="$3" patch="$4" out gbin="$work/guardbin"
  rm -rf "$gbin"; cp -r "$ROOT/bin" "$gbin"
  if ! MUT_PATCH="$patch" MUT_FILE="$gbin/$file" python3 - <<'MUTPY'
import os, pathlib
p = pathlib.Path(os.environ["MUT_FILE"]); s = p.read_text(encoding="utf-8")
old, new = os.environ["MUT_PATCH"].split("=>", 1)
if old not in s:
    raise SystemExit(3)
p.write_text(s.replace(old, new, 1), encoding="utf-8")
MUTPY
  then
    bad "$name: 锚点没命中(实现改过、变异没生效)⇒ 这次红检什么都没证明"
    return
  fi
  out="$(TRACK_BIN="$gbin" bash "$ROOT/tests/test-track-guard.sh" 2>&1)"
  if [[ "$out" == *"FAIL: $target"* ]]; then
    ok "$name ⇒ 打红了 $target"
  elif [[ "$out" == *"$target"* ]]; then
    bad "$name ⇒ **判据全绿放行**:$target 没咬住这条"
  else
    bad "$name ⇒ 判据里找不到 $target(名字改过?)"
  fi
}

mutate_guard "取回豁免恒真(借取回之名删掉 decision.json 也放行)" \
  "G13: 取回时降级成 legacy ⇒ 仍然拦" \
  '  if git cat-file -e ":tracks/$name/decision.json" 2>/dev/null && [[ ${#archive_left_list[@]} -eq 0 ]]; then
    continue
  fi=>  if true; then
    continue
  fi'

# 2026-09-09 第三轮:豁免退回"只看 active 有没有 decision.json"那一版(index≠staged 的洞)。
mutate_guard "豁免退回只查 active decision(不管 archive 搬空没有)" \
  "G14①: 假取回(archive 侧有残留)借豁免改归档正文 ⇒ 仍然拦" \
  '  if git cat-file -e ":tracks/$name/decision.json" 2>/dev/null && [[ ${#archive_left_list[@]} -eq 0 ]]; then=>  if git cat-file -e ":tracks/$name/decision.json" 2>/dev/null; then'

# 药方退回"整目录 mv"那一版:目标已存在时 git 会静默嵌套成 tracks/<n>/<n>/ 且 rc=0。
# 文案断言看不出来,只有**真执行一遍**的 G14④ 照得出。
# (锚点 2026-09-09 第四轮随实现更新过一次 —— 变异锚点跟着实现漂是本机的老病,
#  好在锚点没命中时 mutate_guard 会自己喊,不会静默变成"这条红检什么都没证明"。)
mutate_guard "药方退回整目录 mv(目标已存在时静默嵌套)" \
  "G14④: 照抄闸打印的药方执行一遍 ⇒ 闸放行(药方真走得通)" \
  '      for left in "${archive_left_list[@]}"; do
        rel="${left#$dir/}"
        pre=""
        [ -e "$left" ] || pre="git checkout -- $(shq "$left") && "
        if [[ "$rel" == */* ]]; then
          say "     ${pre}mkdir -p $(shq "tracks/$name/${rel%/*}") && git mv $(shq "$left") $(shq "tracks/$name/$rel")"
        else
          say "     ${pre}git mv $(shq "$left") $(shq "tracks/$name/$rel")"
        fi
      done=>      say "     git mv $dir tracks/$name"'

# 2026-09-09 第四轮:药方退回"不带 mkdir"那一版。目标子目录不存在时 git mv 是
# rc=128 fatal —— 而真实 track 全带 evidence/ observations/。只有逐句断言 rc 的
# G14④a 照得出;"执行完再跑一次闸"那条也会跟着红,但它说不出是哪一句坏了。
mutate_guard "药方退回不带 mkdir(嵌套路径 git mv 直接 fatal)" \
  "G14④a: 药方每一句都真的执行得下去(rc=0,不是靠判据替它补齐)" \
  '        if [[ "$rel" == */* ]]; then
          say "     ${pre}mkdir -p $(shq "tracks/$name/${rel%/*}") && git mv $(shq "$left") $(shq "tracks/$name/$rel")"
        else
          say "     ${pre}git mv $(shq "$left") $(shq "tracks/$name/$rel")"
        fi=>        say "     ${pre}git mv $(shq "$left") $(shq "tracks/$name/$rel")"'

# 2026-09-09 第四轮评审(subdeepseek)挖出的三处,各配一条"放松一格"。

# 09-09 接手断线后重跑红检,这条第一版是"退回默认 core.quotepath" —— **它什么都没证明**:
# 实测 `ls-files -z` 在两种 quotepath 设置下输出逐字节相同(C-quote 只发生在不带 -z 时),
# 所以变异后判据当然全绿。承重的是 `-z` 本身,这一版咬它:退回修复前那种逐行读。
mutate_guard "残件列表退回逐行读(丢掉 -z:非 ASCII 被 C-quote、空格被切)" \
  "G14⑤: 文件名带空格/非 ASCII 时,药方每一句照样跑得通" \
  '  while IFS= read -r -d '"'"''"'"' left; do archive_left_list+=("$left"); done \
    < <(git ls-files -z -- "$dir" 2>/dev/null)=>  while IFS= read -r left; do [ -n "$left" ] && archive_left_list+=("$left"); done \
    < <(git ls-files -- "$dir" 2>/dev/null)'

mutate_guard "药方不再给路径加引号(空格当场 word-split)" \
  "G14⑤: 文件名带空格/非 ASCII 时,药方每一句照样跑得通" \
  '    *[!A-Za-z0-9._/-]*) printf=>    *[!A-Za-z0-9._/-]*) : printf'

mutate_guard "药方不再先把残件取回工作树(只在 index 时 git mv 必 fatal)" \
  "G14⑥: 残件只在 index、工作树已删时,药方仍然走得通" \
  '        [ -e "$left" ] || pre="git checkout -- $(shq "$left") && "=>        :'

mutate_bin track "track archive 退回裸 mv(目标已存在时静默嵌套)" \
  "G15: 目标目录已存在 ⇒ archive 命令拒绝" \
  '    if [ -e "$proj/tracks/archive/$name" ]; then=>    if false; then'

# 2026-09-09 主裁自审:拒绝的**位置**也是判卷面的一部分 —— 排在 worktree sweep 之后,
# 就会先不可逆地删树、再宣布"目录留在原地"。这条变异把 sweep 插到检查之前(单次
# old=>new 只能插不能搬;插进去 = 那条路径上 sweep 先跑了一遍,与旧顺序同效)。
mutate_bin track "拒绝挪到 sweep 之后(先删树再拒绝)" \
  "G15②: 目标已存在 ⇒ 拒绝发生在 sweep 之前,worktree 没被删" \
  '    if [ -e "$proj/tracks/archive/$name" ]; then=>    _track_archive_sweep_worktrees "$name" "$keep_trees" "$discard_ignored" "$proj"
    if [ -e "$proj/tracks/archive/$name" ]; then'

# 2026-09-10 第五轮之后:submimo 指出 `shq()` 本身没有任何变异咬着它 —— 现有两条咬的是
# `-z` 和"药方不加引号",而"shq 退回裸 printf"这条路没人测。`case "" in` 让空串永远落到
# 第二个分支(原样输出)= 把转义整个关掉,而文件里一个引号都不用碰。
mutate_bin track-guard "shq 退回裸输出(转义整个关掉)" \
  "G14⑤: 文件名带空格/非 ASCII 时,药方每一句照样跑得通" \
  '  case "$1" in=>  case "" in'

# 2026-09-10:名单看不见 rename 的源 ⇒ "只把文件搬出 archive/"那笔提交整段复验不被叫起来
# (G16①,判据先行时 3 红)。变异退回只看 staged 的目标路径。
mutate_bin track-guard "复验名单退回只看 staged 目标路径(看不见 rename 源)" \
  "G16①: 部分取回(archive 侧无 staged 路径)⇒ 拦下" \
  '  git diff --cached --name-only --no-renames -z=>  git diff --cached --name-only --find-renames -z'

# 第七轮：三个路径入口各自有变异；精度与完整取回另有反误报变异。
mutate_guard "active 路径退回展示文本(漏选特殊观测文件)" \
  "G17 active unicode: 非法观测确实触发结构检查" \
  '  done < <(git diff --cached --name-only -z) | sort -zu=>  done < <(git diff --cached --name-only) | sort -zu'

mutate_guard "archive 路径退回展示文本(漏选特殊正文文件)" \
  "G17 archive unicode: 正文修改确实触发归档复验" \
  '  git diff --cached --name-only --no-renames -z=>  git diff --cached --name-only --no-renames'

mutate_guard "归档状态退回展示文本(漏选特殊新增文件)" \
  "G17 archiving unicode: 特殊路径新增仍触发证据检查" \
  '  done < <(git diff --cached --name-status --find-renames -z) | sort -zu=>  done < <(git diff --cached --name-status --find-renames) | sort -zu'

mutate_guard "复验名单扩大到全部已跟踪路径(无关 rename 误报)" \
  "G18: 无关 rename 不复验无关的旧归档" \
  '  git diff --cached --name-only --no-renames -z=>  git ls-files -z'

mutate_guard "完整取回也不豁免(合法流程被拒)" \
  "G16②: 完整取回(整份搬出)⇒ 仍然放行" \
  '  if git cat-file -e ":tracks/$name/decision.json" 2>/dev/null && [[ ${#archive_left_list[@]} -eq 0 ]]; then=>  if false; then'

printf -- '---- 合计 PASS=%s FAIL=%s ----\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

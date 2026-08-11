#!/usr/bin/env bash
# track worktree-sweep 的判据(主 agent 亲写,执行腿逐字节 off-limits)。
#
# 判的是:`track archive` 收尾时清理**这一轮自己**的 worktree —— 而且**只删确认干净的**。
# 规格在 tracks/worktree-sweep/design.md。
#
# 这份判据的立足点只有一句:**删错的代价和留着的代价不对称**。
# 留着 = 占几兆盘;删错 = 丢掉唯一一份改动。所以判据里"不许删"的幕比"该删"的幕更多,
# 而且每一幕都**亲自去看盘上那棵树还在不在、里面的字还在不在**,不看脚本自己怎么说。
#
# 锁死的假绿路线:
#   ① "报告说收了"其实没收 / "报告说没动"其实删了 ⇒ 一律用 `[[ -d ]]` 和文件内容判,不看输出。
#   ② 安全判据只查一半(只查干净、不查合没合进主线)⇒ S3 专门造"干净但没合"的树。
#   ③ 偷偷加 `--force` 把 `git worktree remove` 的拒绝绕过去 ⇒ S2/S8 钉住。
#   ④ 手滑删了别人的树 ⇒ S4 在同一个根下摆了别轮的树和无主的树,断言它们**一个字节没动**。
#   ⑤ 主线判不出来时"猜一个"⇒ S6b 造一个没有 main/master 的仓,要求 fail closed。
#
# Run:  bash /root/aiwork/tests/test-worktree-sweep.sh
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78   # source 失败=裸跑,必须硬退

BIN="${TRACK_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"

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
    mkdir -p tracks/"$t"
    cat > tracks/"$t"/verify.md <<'EOF'
# Verify: 判据夹具
- Verdict: PASS
- 无机器证据:这是判据里的临时仓,不跑真判据。
EOF
    git add -A; git commit -qm init )
}

# 在 <root>/<sub> 下给 <repo> 建一棵 worktree,并把它的 HEAD 停在 <ref>
make_tree() {  # make_tree <repo> <root> <sub> <名字> <ref>
  local repo="$1" root="$2" sub="$3" name="$4" ref="$5"
  mkdir -p "$root/$sub"
  git -C "$repo" worktree add -q -b "delegate/$sub/$name" "$root/$sub/$name" "$ref" 2>/dev/null \
    || git -C "$repo" worktree add -q "$root/$sub/$name" "$ref"
  echo "$root/$sub/$name"
}

# ---------------------------------------------------------------- S1 该收的收掉
s1_clean_tree_swept() {
  echo "[S1] 干净 + 成果已在主线 ⇒ 归档时收树收分支,主仓一字未动"
  local d; d="$(mktemp -d)"; local p="$d/proj" root="$d/wt" rc
  make_proj "$p" mytrack
  local tree; tree="$(make_tree "$p" "$root" mytrack job-1 HEAD)"
  local head_before; head_before="$(git -C "$p" rev-parse HEAD)"

  DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/track" archive mytrack "$p" >"$d/o1" 2>&1; rc=$?
  check "S1: 归档成功(rc=0)" $([[ $rc -eq 0 ]]; echo $?)
  check "S1: 那棵树**从盘上没了**(不看它自己怎么说)" $([[ ! -d "$tree" ]]; echo $?)
  check "S1: git 也不再认它" \
    $(! git -C "$p" worktree list --porcelain | grep -qx "worktree $tree"; echo $?)
  check "S1: 分支也收了" \
    $(! git -C "$p" rev-parse --verify -q refs/heads/delegate/mytrack/job-1 >/dev/null; echo $?)
  check "S1: track 真的归档了" $([[ -d "$p/tracks/archive/mytrack" ]]; echo $?)
  check "S1: 主仓工作树一字未动" $([[ -z "$(git -C "$p" status --porcelain -uall)" ]]; echo $?)
  check "S1: 主仓 HEAD 没动" $([[ "$(git -C "$p" rev-parse HEAD)" == "$head_before" ]]; echo $?)
  grep -q "job-1" "$d/o1"; check "S1: 报告里说了收掉哪棵" $?
  rm -rf "$d"
}

# ------------------------------------------------- S2 有没保存的东西 ⇒ 不许删
s2_dirty_tree_blocks() {
  echo "[S2] 树里有没保存的改动 ⇒ 拦住归档,树原封不动"
  local d; d="$(mktemp -d)"; local p="$d/proj" root="$d/wt" rc
  make_proj "$p" mytrack
  local tree; tree="$(make_tree "$p" "$root" mytrack job-1 HEAD)"
  printf 'ONLY_COPY_OF_THIS\n' > "$tree/precious.txt"     # 未跟踪 = git diff 看不见它

  DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/track" archive mytrack "$p" >"$d/o2" 2>&1; rc=$?
  check "S2: 归档被拦(rc≠0)" $([[ $rc -ne 0 ]]; echo $?)
  check "S2: **树还在**" $([[ -d "$tree" ]]; echo $?)
  grep -q ONLY_COPY_OF_THIS "$tree/precious.txt"
  check "S2: 树里那份唯一的东西一个字节没动" $?
  check "S2: track **没有**被归档(不留半截状态)" $([[ -d "$p/tracks/mytrack" ]]; echo $?)
  grep -q "job-1" "$d/o2"; check "S2: 报告点名是哪棵树" $?
  grep -qi "没保存\|未提交\|未跟踪\|干净" "$d/o2"; check "S2: 说清卡在哪一条(树里有东西)" $?
  rm -rf "$d"
}

# ------------------------------------------- S3 干净、但成果没进主线 ⇒ 不许删
s3_unmerged_tree_blocks() {
  echo "[S3] 树干净、但它的提交还没进主线 ⇒ 不许删(这条最要命)"
  local d; d="$(mktemp -d)"; local p="$d/proj" root="$d/wt" rc
  make_proj "$p" mytrack
  local tree; tree="$(make_tree "$p" "$root" mytrack job-1 HEAD)"
  printf 'unique work\n' > "$tree/work.txt"
  git -C "$tree" add -A; git -C "$tree" commit -qm "腿交的活,还没合"   # 提交了 ⇒ 树是干净的
  check "S3: 前置 —— 树确实是干净的" $([[ -z "$(git -C "$tree" status --porcelain -uall)" ]]; echo $?)

  DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/track" archive mytrack "$p" >"$d/o3" 2>&1; rc=$?
  check "S3: 归档被拦(rc≠0)" $([[ $rc -ne 0 ]]; echo $?)
  check "S3: **树还在**(里面那个提交是唯一的一份)" $([[ -d "$tree" ]]; echo $?)
  check "S3: 那个提交还在" $(git -C "$p" cat-file -e "$(git -C "$tree" rev-parse HEAD)" 2>/dev/null; echo $?)
  grep -qi "主线\|没合\|未合并\|merge" "$d/o3"; check "S3: 说清卡在「没合进主线」这一条" $?

  # 合进主线之后,同样的树就该收得掉 —— 少了这一半,一个"永远拦"的实现也能让上面全绿
  git -C "$p" merge -q --no-ff -m "合并腿的活" "delegate/mytrack/job-1"
  DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/track" archive mytrack "$p" >"$d/o3b" 2>&1; rc=$?
  check "S3: 合进主线后 ⇒ 归档通过" $([[ $rc -eq 0 ]]; echo $?)
  check "S3: 这次树被收掉了" $([[ ! -d "$tree" ]]; echo $?)
  rm -rf "$d"
}

# ------------------------------------------------ S4 别人的树一个都不许碰
s4_only_my_track() {
  echo "[S4] 只收**这一轮自己**的树;别轮的、无主的一律不动,但要点名"
  local d; d="$(mktemp -d)"; local p="$d/proj" root="$d/wt" rc
  make_proj "$p" mytrack
  local mine other orphan
  mine="$(make_tree "$p" "$root" mytrack job-1 HEAD)"
  other="$(make_tree "$p" "$root" othertrack job-2 HEAD)"      # 别的轮次
  mkdir -p "$root/loose"; orphan="$(make_tree "$p" "$root" loose job-3 HEAD)"
  # 无主的那棵:直接挂在根下(今天真实世界里 mcp-registry 就是这形状)
  local bare; bare="$root/handmade"
  git -C "$p" worktree add -q -b handmade "$bare" HEAD

  DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/track" archive mytrack "$p" >"$d/o4" 2>&1; rc=$?
  check "S4: 归档成功" $([[ $rc -eq 0 ]]; echo $?)
  check "S4: 我这一轮的树收掉了" $([[ ! -d "$mine" ]]; echo $?)
  check "S4: **别轮的树一个字节没动**" $([[ -d "$other" ]]; echo $?)
  check "S4: 别轮的分支也没被删" \
    $(git -C "$p" rev-parse --verify -q refs/heads/delegate/othertrack/job-2 >/dev/null; echo $?)
  check "S4: 手工建的无主树也没动" $([[ -d "$bare" ]]; echo $?)
  check "S4: 挂在别的子目录下那棵也没动" $([[ -d "$orphan" ]]; echo $?)
  grep -q "othertrack" "$d/o4" && grep -q "handmade" "$d/o4"
  check "S4: 但报告把它们**点名**了(不然又变成没人收的树)" $?
  rm -rf "$d"
}

# ---------------------------------------------------------- S5 显式放行
s5_keep_trees() {
  echo "[S5] --keep-trees:脏树也照常归档,但一根手指头都不许碰,而且仍要点名"
  local d; d="$(mktemp -d)"; local p="$d/proj" root="$d/wt" rc
  make_proj "$p" mytrack
  local tree; tree="$(make_tree "$p" "$root" mytrack job-1 HEAD)"
  printf 'ONLY_COPY\n' > "$tree/precious.txt"

  DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/track" archive mytrack "$p" --keep-trees >"$d/o5" 2>&1; rc=$?
  check "S5: 归档通过(rc=0)" $([[ $rc -eq 0 ]]; echo $?)
  check "S5: 树原封不动" $([[ -d "$tree" && -f "$tree/precious.txt" ]]; echo $?)
  check "S5: track 归档了" $([[ -d "$p/tracks/archive/mytrack" ]]; echo $?)
  grep -q "job-1" "$d/o5"; check "S5: 仍然点名(放行不等于闭嘴)" $?

  # --keep-trees 也不许顺手把**干净**的树删了:它的语义是"别动树",不是"只跳过脏的"
  local d2; d2="$(mktemp -d)"; local p2="$d2/proj" root2="$d2/wt"
  make_proj "$p2" t2
  local clean; clean="$(make_tree "$p2" "$root2" t2 job-9 HEAD)"
  DELEGATE_WORKTREE_ROOT="$root2" bash "$BIN/track" archive t2 "$p2" --keep-trees >/dev/null 2>&1
  check "S5: --keep-trees 下连干净的树也不动" $([[ -d "$clean" ]]; echo $?)
  rm -rf "$d" "$d2"
}

# ---------------------------------------------------------- S6 跨仓 / 主线判不出来
s6_cross_repo_and_failclosed() {
  echo "[S6] 树属于**另一个仓** ⇒ 用它自己的仓判;主线判不出来 ⇒ fail closed"
  local d; d="$(mktemp -d)"; local p="$d/proj" root="$d/wt" rc
  make_proj "$p" mytrack
  # 另一个仓的树,躺在同一个 worktree 根、同一个轮次目录下(mcp-registry 就是这形状)
  local other="$d/otherrepo"; mkdir -p "$other"
  ( cd "$other"; git init -q -b main; git config user.email t@t; git config user.name t
    printf 'y\n' > f.txt; git add -A; git commit -qm init )
  local t2; t2="$(make_tree "$other" "$root" mytrack from-other-repo HEAD)"
  printf 'unmerged\n' > "$t2/z.txt"
  git -C "$t2" add -A; git -C "$t2" commit -qm "别的仓里没合的活"

  DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/track" archive mytrack "$p" >"$d/o6" 2>&1; rc=$?
  check "S6: 跨仓的树没合进**它自己仓**的主线 ⇒ 拦住" $([[ $rc -ne 0 ]]; echo $?)
  check "S6: 那棵树还在" $([[ -d "$t2" ]]; echo $?)

  # 主线判不出来(既没 main 也没 master,也没有 origin/HEAD)⇒ 不许猜"它合过了"
  local d3; d3="$(mktemp -d)"; local p3="$d3/proj" root3="$d3/wt"
  make_proj "$p3" t3
  local weird="$d3/weirdrepo"; mkdir -p "$weird"
  ( cd "$weird"; git init -q -b odd-name; git config user.email t@t; git config user.name t
    printf 'q\n' > f.txt; git add -A; git commit -qm init )
  local t3; t3="$(make_tree "$weird" "$root3" t3 no-mainline HEAD)"
  DELEGATE_WORKTREE_ROOT="$root3" bash "$BIN/track" archive t3 "$p3" >"$d3/o" 2>&1; rc=$?
  check "S6: 说不清主线是哪条 ⇒ 拒绝清理(fail closed,不许当它合过了)" $([[ $rc -ne 0 ]]; echo $?)
  check "S6: 那棵树也还在" $([[ -d "$t3" ]]; echo $?)
  grep -qi "主线\|默认分支" "$d3/o"; check "S6: 说清是「主线判不出来」" $?
  rm -rf "$d" "$d3"
}

# ---------------------------------------------------------- S7 归属写进路径
s7_track_in_path() {
  echo "[S7] delegate-codex --track:树落进 <根>/<track>/,分支带轮次;不给就是老样子"
  local d; d="$(mktemp -d)"; local b="$d/bin" rec="$d/rec" repo="$d/repo" root="$d/wt" rc
  mkdir -p "$b" "$rec" "$repo/tests" "$repo/src"
  cat > "$b/codex" <<EOF
#!/usr/bin/env bash
echo call >> "$rec/calls"
printf '%s\n' "\$@" > "$rec/argv.\$(wc -l < "$rec/calls" | tr -d ' ')"
exit 0
EOF
  chmod +x "$b/codex"
  ( cd "$repo"; git init -q -b main; git config user.email t@t; git config user.name t
    printf 'echo ok\n' > tests/oracle.sh; printf 'x\n' > src/impl.sh
    git add -A; git commit -qm init )
  printf '# 任务书\n干活\n' > "$d/task.md"
  printf '攻题记录\n' > "$d/attack.md"
  bash "$BIN/delegate-codex" --print-oracle-hash --repo "$repo" --protect tests/ >> "$d/attack.md"

  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" --track mytrack \
      --protect tests/ --log "$d/a.log" >"$d/o7" 2>&1; rc=$?
  check "S7: 带 --track 派活 rc=0" $([[ $rc -eq 0 ]]; echo $?)
  local cdir; cdir="$(awk '$0=="-C"{getline; print; exit}' "$rec/argv.1")"
  check "S7: 树落在 <根>/<track>/ 下面" $([[ "$cdir" == "$root/mytrack/"* ]]; echo $?)
  python3 - "$d/a.log.receipt.json" <<'EOF'
import json,sys
r=json.load(open(sys.argv[1]))
assert r.get("track") == "mytrack", r.get("track")
assert r["branch"].startswith("delegate/mytrack/"), r["branch"]
EOF
  check "S7: 回执记下 track,分支名带轮次" $?

  # 不给 --track ⇒ 老路径老分支(向后兼容,别把没挂轮次的活弄坏)
  env PATH="$b:$PATH" DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/delegate-codex" \
      --task "$d/task.md" --repo "$repo" --attack-log "$d/attack.md" \
      --protect tests/ --log "$d/b.log" >"$d/o7b" 2>&1; rc=$?
  check "S7: 不给 --track 照样派得出去" $([[ $rc -eq 0 ]]; echo $?)
  local cdir2; cdir2="$(awk '$0=="-C"{getline; print; exit}' "$rec/argv.2")"
  check "S7: 不给 --track ⇒ 树还在根下(老样子)" \
    $([[ "$cdir2" == "$root/"* && "$cdir2" != "$root/mytrack/"* ]]; echo $?)
  rm -rf "$d"
}

# ---------------------------------------------------------- S8 不许偷偷 --force
s8_no_force() {
  echo '[S8] 清理用的是 git worktree remove(不带 --force)—— 第二道免费保险不许拆' 
  local d; d="$(mktemp -d)"; local p="$d/proj" root="$d/wt" rc
  make_proj "$p" mytrack
  local tree; tree="$(make_tree "$p" "$root" mytrack job-1 HEAD)"
  # 造一个"安全判据看着干净、但 git 自己会拒绝删"的形状:被 ignore 的文件。
  # `status -uall` 看不见它(设计里写明的取舍),而 `git worktree remove` 不带 --force 会拒。
  printf 'junk/\n' > "$p/.gitignore"; git -C "$p" add -A; git -C "$p" commit -qm ignore
  mkdir -p "$tree/junk"; printf 'build artifact\n' > "$tree/junk/a.o"

  DELEGATE_WORKTREE_ROOT="$root" bash "$BIN/track" archive mytrack "$p" >"$d/o8" 2>&1; rc=$?
  # 不规定它拦不拦(git 拒了就该报出来),只钉死一件事:**没有偷偷加 --force**
  if [[ -d "$tree" ]]; then
    ok "S8: git 拒绝删就留着(没有偷偷 --force 绕过去)"
    grep -qi "remove\|拒\|失败" "$d/o8"; check "S8: 而且把 git 的拒绝报出来了" $?
  else
    bad "S8: 树被删了 —— 说明加了 --force,把 git 那道免费保险拆了"
    bad "S8: (同上)"
  fi
  rm -rf "$d"
}

echo "=== worktree-sweep oracle ==="
s1_clean_tree_swept
s2_dirty_tree_blocks
s3_unmerged_tree_blocks
s4_only_my_track
s5_keep_trees
s6_cross_repo_and_failclosed
s7_track_in_path
s8_no_force
echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]

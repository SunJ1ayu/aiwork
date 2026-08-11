# shellcheck shell=bash
# 判卷面内容摘要 —— **判据侧的独立实现**(track codex-worktree-delegation,2026-08-11)。
#
# 为什么要独立写一遍:被测的 `bin/delegate-codex` 用 python3 走 os.walk 算这个哈希。
# 判据要是回头调它自己那份来算期望值,两边一起错的时候判据全绿 ——
# 本机在 08-01 撞过同型(「改判据加锚断言防两边一起错」),这里从一开始就分开:
#   实现侧:python3 + os.walk;判据侧:find + sha256sum(下面这份)。
# 两份都按 design「十·10.1」那段规格写,不共享一行代码。
#
# 规格(逐字):
#   文件集 = ∪ 每条 protect 路径:是文件/符号链接 ⇒ 它自己;是目录 ⇒ 递归其下全部条目。
#            路径成分里含 __pycache__ 的一律排除。
#   每个条目一行(按相对路径字节序排序、去重):
#            普通文件: <相对路径>\0<内容 sha256>\n
#            符号链接: <相对路径>\0symlink:<链接目标原文>\n
#   摘要 = 整段字节流的 sha256。

# oracle_hash <repo> <protect...>  → stdout 打印 64 位十六进制
oracle_hash() {
  local repo="$1"; shift
  local rels; rels="$(mktemp)"
  local p full
  for p in "$@"; do
    # 实现侧用 python 的 `strip("/")`(剥掉**所有**首尾斜杠);这里原来只剥一个尾斜杠 ⇒
    # `--protect tests//` 两边算出不同的相对路径 = 判据假红(四审 subdeepseek 指出)。
    while [[ "$p" == */ ]]; do p="${p%/}"; done
    while [[ "$p" == /* ]]; do p="${p#/}"; done
    full="$repo/$p"
    if [[ -L "$full" || -f "$full" ]]; then
      case "/$p/" in */__pycache__/*) ;; *) printf '%s\n' "$p" >> "$rels" ;; esac
    elif [[ -d "$full" ]]; then
      # -printf '%P' = 相对 find 起点的路径;`-name __pycache__ -prune` 整棵剪掉
      find "$full" -name '__pycache__' -prune -o \( -type f -o -type l \) -printf '%P\n' \
        | while IFS= read -r r; do [[ -n "$r" ]] && printf '%s/%s\n' "$p" "$r"; done >> "$rels"
    fi
  done
  local out; out="$(mktemp)"
  local rel f
  while IFS= read -r rel; do
    f="$repo/$rel"
    if [[ -L "$f" ]]; then
      printf '%s\0symlink:%s\n' "$rel" "$(readlink "$f")" >> "$out"
    else
      printf '%s\0%s\n' "$rel" "$(sha256sum "$f" | cut -d' ' -f1)" >> "$out"
    fi
    # `LC_ALL=C`:实现侧是 python 的 `sorted()`(按码点,UTF-8 下等于字节序),
    # 而 `sort` 默认按 locale 排 —— 非 ASCII 路径下两边顺序会岔开(同上,判据假红)。
  done < <(LC_ALL=C sort -u "$rels")
  sha256sum < "$out" | cut -d' ' -f1
  rm -f "$rels" "$out"
}

# stamp_hash <攻题记录> <repo> <protect...>
#   把 `oracle-sha256: <当前哈希>` 写进攻题记录(**替换**已有的那行,不追加 ——
#   追加的话一份记录会攒着好几版哈希,判据自己就制造了"旧哈希也能过"的假象)。
#   仓里有 `.gitignore` 时自动并进清单:入口本来就会自动把它并进 protect
#   (腿改 .gitignore 就能藏文件),这里是模拟**调用方**,不是模拟被测逻辑 ——
#   "自动并进来的东西也在哈希里"这件事由 H2③ 单独钉,不靠这个函数。
stamp_hash() {
  local attack="$1" repo="$2"; shift 2
  set -- "$@" $([[ -f "$repo/.gitignore" ]] && echo .gitignore)
  local h; h="$(oracle_hash "$repo" "$@")"
  local tmp; tmp="$(mktemp)"
  grep -v '^oracle-sha256: ' "$attack" > "$tmp" 2>/dev/null || true
  printf 'oracle-sha256: %s\n' "$h" >> "$tmp"
  mv "$tmp" "$attack"
}

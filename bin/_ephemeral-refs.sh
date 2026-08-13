# shellcheck shell=bash
# 会话临时目录引用的归档闸 —— 只在 `track archive` 这一个动作上启用。
#
# 为什么不放进 pre-commit:干活途中把完整输出暂存在 scratchpad 或 /tmp 是正常工作流;
# 提交时就拦会把「活还没收口」和「宣布可长期保存」混在一起,噪音一多闸就没人信。
#
# 为什么只扫 Markdown:这道闸管的是会被人读到的工件叙述,不是机器收据正文。
# evidence/*.txt 里的真实 runlog 会记录绝对 cwd,临时夹具和 worktree 天然可能在 /tmp 下;
# 扫它只能制造误报。射程边界也因此很窄:非 md 的散文引用不在这里兜底。

eph_line_has_tmpdir_word() {  # <line>
  [[ "$1" =~ (^|[^[:alnum:]_])TMPDIR([^[:alnum:]_]|$) ]]
}

eph_line_has_ephemeral_ref() {  # <line>
  local line="$1"
  # /tmp/ 是 Linux 路径的字面事实,大小写不能扩张到 /TMP/;scratchpad 是散文词,
  # 大小写常随手写成 ScratchPad,这里才故意放宽。TMPDIR 只认词边界,挡 `$TMPDIR`
  # 和 `${TMPDIR:-/tmp}`,不挡 MYTMPDIR 这种不是该变量的拼接词。
  [[ "$line" == *"/tmp/"* ]] && return 0
  [[ "$line" =~ [sS][cC][rR][aA][tT][cC][hH][pP][aA][dD] ]] && return 0
  eph_line_has_tmpdir_word "$line"
}

eph_check() {  # <trackdir> [每行前缀]
  local dir="$1" tag="${2:-证据寿命}" bad=0 file rel line lineno

  [ -d "$dir" ] || return 0

  while IFS= read -r -d '' file; do
    rel="${file#$dir/}"
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
      lineno=$((lineno+1))
      [[ "$line" == *"[仓外不承重]"* ]] && continue
      if eph_line_has_ephemeral_ref "$line"; then
        bad=1
        printf '%s: 🔴 证据寿命:%s:%s 引用了会话临时目录:\n' "$tag" "$rel" "$lineno" >&2
        printf '%s:      %s\n' "$tag" "$line" >&2
        printf '%s:    若这行只是仓外背景、不是承重证据,请在同一行标注 [仓外不承重]。\n' "$tag" >&2
      fi
    done < "$file"
  done < <(find "$dir" -type f -name '*.md' -print0)

  [ "$bad" -eq 0 ]
}

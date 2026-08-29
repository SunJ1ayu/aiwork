#!/usr/bin/env bash
# 红检:把 coverage 谓词里的**单条理由**故意静音,看新加的那两条钉子咬不咬得住。
#
# 存在的理由(2026-08-30,track review-result-oracle-pins):
# 复核 P0 时我拿 10 个变异打这个谓词,8 个被判据咬住,2 个没有 ——
# `subject_unknown` 和 `evidence_incomplete` 删掉整套判据仍然全绿。
# 不是实现少了检查,是**判据里没人单独问过它们**:现实里它俩总和别的理由结伴出现,
# 结伴出现 = 谁都没被钉住 = 下一个人重构时它会安静消失。
#
# 🔴 变异只许"静音这条理由",不许制造崩溃:`if False:` 那种写法会让后面的
# `elif verify_evidence:` 拿着 None 去算摘要,红在 TypeError 上 —— 红在别处 = 等于没红检过。
# 所以这里改的是 `reasons.append(...)` 本身,红必须是 FAIL 不是 ERROR。
#
# 锚点没命中也算漏网(锚点过期本身就是问题,本机记过 4 次)。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORACLE="$ROOT/tests/test_review_result.py"
IMPL="$ROOT/bin/_review_result.py"
PASS=0; FAIL=0
ok()  { printf '  PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/tests"
# 静默 cp 会把"少抄了一个文件"变成"守卫没生效但judge照跑" ⇒ 一律不吞错。
cp "$IMPL" "$work/bin/"
cp "$ORACLE" "$ROOT/tests/_no_egress.py" "$work/tests/"

# 基线:没变异必须全绿。基线红了后面每条都会"红",红检就成了摆设。
if python3 "$work/tests/test_review_result.py" >"$work/base.log" 2>&1; then
  ok "基线(未变异)判据全绿"
else
  bad "基线就红了 ⇒ 本次红检无效($(tail -2 "$work/base.log" | tr '\n' ' '))"
  printf -- '---- 合计 PASS=%s FAIL=%s ----\n' "$PASS" "$FAIL"; exit 1
fi

mutate() {  # mutate <名字> <该被打红的测试名> <python 替换>
  local name="$1" target="$2" patch="$3" out
  cp "$IMPL" "$work/bin/_review_result.py"
  if ! MUT_PATCH="$patch" MUT_FILE="$work/bin/_review_result.py" python3 - <<'PY'
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
  out="$(python3 "$work/tests/test_review_result.py" 2>&1)"
  if [[ "$out" == *"FAIL: $target"* ]]; then
    ok "$name ⇒ 打红了 $target"
  elif [[ "$out" == *"ERROR: $target"* ]]; then
    bad "$name ⇒ $target 红在异常上(ERROR),不是断言 —— 变异制造了崩溃,重写变异"
  elif [[ "$out" == *"OK"* && "$out" != *FAIL* ]]; then
    bad "$name ⇒ **判据全绿放行**:$target 没咬住这条理由"
  else
    bad "$name ⇒ 红了,但没红在 $target 上($(printf '%s' "$out" | grep -E '^(FAIL|ERROR):' | head -1))"
  fi
}

mutate "静音 subject_unknown" \
  "test_a_review_of_an_unknown_object_is_never_coverage" \
  '        reasons.append("subject_unknown")=>        pass'

mutate "静音 evidence_incomplete" \
  "test_a_verdict_with_no_preserved_evidence_is_never_coverage" \
  '        reasons.append("evidence_incomplete")=>        pass'

printf -- '---- 合计 PASS=%s FAIL=%s ----\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

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
   "$ROOT/bin/track-record" "$ROOT/bin/track" "$work/bin/"
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
  '            if delivery == {"policy_version": 1, "track": data["track"], "digest": target}:=>            if True:'

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

printf -- '---- 合计 PASS=%s FAIL=%s ----\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

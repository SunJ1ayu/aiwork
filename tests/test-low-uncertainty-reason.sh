#!/usr/bin/env bash
# 填 low 不许零成本 —— track design-uncertainty-low-needs-reason(2026-09-19)。
#
# 由来:0.98.7 启动阻塞那一单 impact=high(外审预算 2 真的走了),
# design.uncertainty=low + not_required + 空 evidence ⇒ premise attack / 双出 /
# panel-explore 整条设计防线被一个自述字段全关掉。规格里"用户最坏等 35 秒"
# 两家外审都看过没人吭声 —— 评审问的是"实现对不对",只有发散才问"为什么不后台查"。
# 业主发现时已经发版。
set -uo pipefail
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tracks/t"
for f in proposal design tasks verify; do echo "# $f" > "$T/tracks/t/$f.md"; done
fail=0
mk() { # $1=uncertainty $2=status $3=evidence-json
  cat > "$T/tracks/t/decision.json" <<EOF
{"schema_version":2,"track":"t","impact":{"level":"high","factors":["new_write_surface"]},
 "design":{"uncertainty":"$1","premise_attack":{"status":"$2","evidence":$3}},
 "execution_plan":{"adapter":"main","model":"x"},"outcome":{"verdict":null}}
EOF
}
run() { (cd "$T" && /root/aiwork/bin/track-record validate --phase dispatch tracks/t >/dev/null 2>&1); echo $?; }
chk() { # $1=名字 $2=期望退出码 $3=实际
  if [ "$2" = "$3" ]; then echo "  [PASS] $1"; else echo "  [FAIL] $1 —— 期望退出码 $2,实得 $3"; fail=1; fi
}
echo "== 填 low 不许零成本 =="
mk low not_required '[]';            chk "low + 零理由 ⇒ 必须 BLOCK"            1 "$(run)"
mk low not_required '["design.md"]'; chk "low + 指向工件 ⇒ 放行"                0 "$(run)"
mk low not_required '["nope.md"]';   chk "low + 指向不存在的文件 ⇒ BLOCK"      1 "$(run)"
mk high done '["design.md"]';        chk "回归:high + 证据齐 ⇒ 放行"            0 "$(run)"
mk high done '[]';                   chk "回归:high + 空证据 ⇒ 仍 BLOCK"        1 "$(run)"
mk high not_required '["design.md"]';chk "回归:high 但没做攻击 ⇒ 仍 BLOCK"      1 "$(run)"
[ "$fail" = 0 ] && echo "全过" || echo "🔴 有红"
exit "$fail"

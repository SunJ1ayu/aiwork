#!/usr/bin/env bash
# 现场探针:前提实验 + 两条腿真跑。每一步打印 OK/BAD,任一 BAD ⇒ rc=1。
set -u
B=/root/aiwork/bin; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
bad=0; ok(){ echo "OK  $*"; }; no(){ echo "BAD $*"; bad=1; }
( cd "$W" && git init -q r && cd r && printf 'def add(a, b):\n    return a - b\n' > m.py \
  && git add m.py && git -c user.name=p -c user.email=p@p commit -qm add )
R="$W/r"; M="$(head -n1 "$B/mimo-model")"; C="$(head -n1 "$B/cursor-model")"
echo "mimo-model=$M cursor-model=$C"

# P1 服务端认这个 id(只看名字,不打印 key)
python3 - "$M" <<'PY' && ok "P1 服务端 /v1/models 列出 ${M#xiaomi/}" || no "P1 服务端未列出 $M"
import json,sys,urllib.request
a=json.load(open('/root/.local/share/mimocode/auth.json'))['xiaomi']
req=urllib.request.Request(a['metadata']['base_url'].rstrip('/')+'/models',headers={'Authorization':'Bearer '+a['key']})
ids=[m['id'] for m in json.load(urllib.request.urlopen(req,timeout=30))['data']]
sys.exit(0 if sys.argv[1].split('/',1)[1] in ids else 1)
PY
# P2 不登记 ⇒ CLI 不认(说明「只改名」这次跑不起来)
out="$(cd "$R" && env -u MIMOCODE_CONFIG_CONTENT timeout 120 mimo run -m "$M" "reply OK" 2>&1)"
[[ "$out" == *"Model not found"* ]] && ok "P2 未登记时 CLI 报 Model not found" || echo "INFO P2 CLI 已自带该模型(上游表已更新)"
# P3 登记假 id ⇒ 服务端拒(成功不是 CLI 自说自话)
cfg='{"provider":{"xiaomi":{"models":{"mimo-v9.9-bogus":{"name":"x","reasoning":true,"tool_call":true,"interleaved":{"field":"reasoning_content"},"temperature":true,"limit":{"context":1048576,"output":131072}}}}}}'
out="$(cd "$R" && MIMOCODE_CONFIG_CONTENT="$cfg" timeout 120 mimo run -m xiaomi/mimo-v9.9-bogus "reply OK" 2>&1)"
[[ "$out" == *"Unsupported model"* ]] && ok "P3 假 id 被服务端拒" || no "P3 假 id 未被拒:$(tail -c 300 <<<"$out")"
# P4 评审锁不因登记改变:同一锁配置,加/不加 submimo 的那段登记
mkdir -p "$W/lock/mimocode"; cp "$HOME/.cache/aiwork/mimo-review-home/mimocode/mimocode.json" "$W/lock/mimocode/"
reg="$(bash -c 'MODEL='"$M"'; eval "$(sed -n "/^MIMO_MODEL_CFG=\"\"/,/^fi/p" '"$B"'/submimo)"; printf %s "$MIMO_MODEL_CFG"')"
[[ -n "$reg" ]] || no "P4 从 submimo 取不到登记段"
( cd "$R" && XDG_CONFIG_HOME="$W/lock" env -u MIMOCODE_CONFIG_CONTENT timeout 60 mimo debug agent aiwork-review | sort ) > "$W/a"
( cd "$R" && XDG_CONFIG_HOME="$W/lock" MIMOCODE_CONFIG_CONTENT="$reg" timeout 60 mimo debug agent aiwork-review | sort ) > "$W/b"
[[ -s "$W/a" ]] && cmp -s "$W/a" "$W/b" && ok "P4 评审锁加/不加登记排序后逐字节一致($(wc -l < "$W/a") 行)" || no "P4 评审锁有差异"
grep -q '"write": false' "$W/b" && grep -q '"edit": false' "$W/b" && grep -q '"task": false' "$W/b" \
  && ok "P4 登记后 write/edit/task 仍关" || no "P4 写口不是关的"
# L1 MiMo 腿真跑 review
REVIEW_NO_MY_REVIEW=1 AIWORK_REVIEW_FACTS_PATH="$W/m.facts.json" AIWORK_REVIEW_RESULT_BIN="$B/_review_result.py" \
  timeout 900 "$B/submimo" review <(printf '# t\nReview the last commit: add(a,b) in m.py must return the sum. Report defects.\n') "$W/m.log" "$R" >/dev/null 2>&1
echo "--- submimo 日志关键行"; grep -E '^model:|^> aiwork-review|^Conclusion' "$W/m.log"
python3 -c "import json,sys;m=json.load(open('$W/m.facts.json'))['model'];print('facts',m);sys.exit(0 if m['requested']==m['invoked']=='$M' else 1)" \
  && grep -q "^> aiwork-review · ${M#xiaomi/}" "$W/m.log" && grep -q '^Conclusion: BLOCK' "$W/m.log" \
  && ok "L1 MiMo 腿以 $M 跑评审档并抓到减法" || no "L1 MiMo 腿真跑不符"
# L2 Cursor 腿真跑 explore,看它自己回报的模型
timeout 600 "$B/subcursor" explore <(printf '# Brief\nPropose one direction to validate inputs of add(a,b). Keep it short.\n') "$W/c.log" "$R" >/dev/null 2>&1
python3 - "$W/c.stream-summary.json" <<'PY' && ok "L2 Cursor 腿真跑成功且回报 Grok 4.7" || no "L2 Cursor 腿真跑不符"
import json,sys
s=json.load(open(sys.argv[1])); print('summary', {k:s.get(k) for k in ('success','family_ok','models')})
sys.exit(0 if s['success'] and s['family_ok'] and any('Grok 4.7' in m for m in s['models']) else 1)
PY
exit $bad

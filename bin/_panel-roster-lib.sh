#!/usr/bin/env bash
# 花名册的**唯一**渲染逻辑。panel-review(正常收尾)和 panel-roster(事后重建)
# 都 source 它 —— 两条路必须算出一模一样的东西,所以这里只许有一份。
#
# 为什么把它抽出来:`verdict_of` 在 panel-review 里有 4 处用到(轮换升级/健康/
# 花名册/observation),搬不走;而 panel-roster 又非有不可。抄第二份 =
# 「同一个事实存两处,只更新其中一个」,本机记过账的老毛病。
#
# 设计要点(track panel-roster-from-disk):
#   花名册 = f(<prefix>.plan, <prefix>.<leg>.state, <prefix>.final?)
#   —— **纯函数,读盘算出来**,不依赖任何进程还活着。
#   · .plan  控制器在**派发之前**写(那时选腿结果已全部已知)
#   · .state **腿自己在 setsid 出去的那个会话里**写(控制器死了它照样写得成)
#   · .final 控制器正常收尾才写;缺了不是错,只说明它没活到最后

PANEL_LEGS_ORDER=(submimo subdeepseek subglm subkimi)

verdict_of() {  # verdict_of <log>; PASS/BLOCK/NEEDS_MORE_INFO/UNKNOWN
  local found
  # 只认独立裁决行。提示词和推理日志都可能原样出现
  # "Conclusion: PASS | BLOCK | NEEDS_MORE_INFO"，子串匹配会把没交卷误记成 PASS。
  found="$(grep -Eio '^[[:space:]]*(Conclusion|Verdict|结论)[[:space:]]*[：:][[:space:]]*(PASS|BLOCK|NEEDS_MORE_INFO)[[:space:]]*$' "$1" 2>/dev/null \
    | tail -n 1 | sed -E 's/[[:space:]]+$//' \
    | grep -Eio '(PASS|BLOCK|NEEDS_MORE_INFO)$' || true)"
  [[ -n "$found" ]] && printf '%s\n' "${found^^}" || printf 'UNKNOWN\n'
}

_plan_kv() {  # _plan_kv <planfile> <key>
  awk -F= -v k="$2" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$1" 2>/dev/null
}
_plan_leg_field() {  # _plan_leg_field <planfile> <leg> <2=selected|3=health>
  awk -F'\t' -v n="$2" -v f="$3" '$1=="leg" && $2==n {print $(f+1); exit}' "$1" 2>/dev/null
}

# 一条腿的状态,全部读盘算出来
roster_entry_from_disk() {  # roster_entry_from_disk <prefix> <leg>
  local prefix="$1" name="$2" plan="$1.plan" state="$1.$2.state" log="$1.$2.log"
  local selected health rc state_txt verdict
  selected="$(_plan_leg_field "$plan" "$name" 2)"
  health="$(_plan_leg_field "$plan" "$name" 3)"
  if [[ "$selected" != "1" ]]; then
    if [[ "$health" == "off" ]]; then printf '%s=off' "$name"
    elif [[ "$health" == "healthy" ]]; then printf '%s=SKIP(rotation)' "$name"
    else printf '%s=SKIP(health:%s)' "$name" "${health:-unknown}"; fi
    return
  fi
  if [[ ! -s "$state" ]]; then
    # 派出去了、却没有任何退出码落盘 ⇒ 这条腿没收尾。
    # **绝不许印成 PASS,也绝不许整行消失** —— 那正是这道闸存在的理由。
    printf '%s=KILLED(未收尾,无 state)' "$name"
    return
  fi
  rc="$(_plan_kv "$state" rc)"
  if [[ "$rc" == "0" ]]; then
    verdict="$(verdict_of "$log")"
    state_txt="PASS(verdict=$verdict)"
  else
    state_txt="FAIL(rc=$rc)"
  fi
  # 底座腿死了、聊天腿顶上来的:结论可以旅行,资格要跟着走(同 V19 的降级横幅)
  if [[ -e "$prefix.$name.agent.log" || -e "$prefix.$name.agent.log.err" ]]; then
    if [[ "$rc" == "0" ]]; then state_txt="PASS(verdict=$verdict,降级:回落聊天腿,只看得见 diff)"
    else state_txt="FAIL(rc=$rc,降级:回落聊天腿也没成)"; fi
  fi
  printf '%s=%s' "$name" "$state_txt"
}

render_roster() {  # render_roster <prefix>
  local prefix="$1" plan="$1.plan" final="$1.final"
  local esc head_before head_after line name
  [[ -s "$plan" ]] || { echo "🔴 panel-roster: 没有 $plan —— 这一轮连派发都没走到,无从重建。" >&2; return 1; }
  head_before="$(_plan_kv "$plan" snapshot-head)"
  if [[ -s "$final" ]]; then
    esc="$(_plan_kv "$final" escalation)"; head_after="$(_plan_kv "$final" head-after)"
  else
    esc="unknown(控制器没活到收尾)"; head_after=""
  fi
  echo "# panel-review 花名册($(date '+%F %T'))task=$(_plan_kv "$plan" task)"
  echo "# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。"
  echo "# impact-risk=$(_plan_kv "$plan" impact-risk) requested-budget=$(_plan_kv "$plan" requested-budget) selected-count=$(_plan_kv "$plan" selected-count)"
  echo "# selected=$(_plan_kv "$plan" selected)"
  echo "# escalation=$esc"
  echo "# snapshot=head:$head_before"
  echo "# 日志:${prefix}.*.log"
  line=""
  for name in "${PANEL_LEGS_ORDER[@]}"; do line+="${line:+ }$(roster_entry_from_disk "$prefix" "$name")"; done
  echo "$line"
  if [[ -n "$head_before" && -n "$head_after" && "$head_before" != "$head_after" ]]; then
    echo "# ⚠️ 评审期间 HEAD 从 $head_before 移到 $head_after —— 各腿未必评的同一棵树。"
  fi
}

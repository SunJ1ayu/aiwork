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
#   —— **读盘算出来**,不依赖任何进程还活着。
#      (抬头那个渲染时间戳除外:它答的是"什么时候打印的",不是盘上状态的函数。)
#   · .plan  控制器在**派发之前**写(那时选腿结果已全部已知)
#   · .state **腿自己在 setsid 出去的那个会话里**写(控制器死了它照样写得成)
#   · .final 控制器正常收尾才写;缺了不是错,只说明它没活到最后

# ── 腿的身份表:**一条腿的全部身份只写在这一行里** ────────────────────────
# 字段:腿名 | 模型家族 | 底座腿二进制 | 聊天腿二进制(空=没有回落) | 开关变量
#
# 🔴 为什么是一张表(2026-08-26,track subgemini-review-leg 的四审):
# 加第五条腿时,这些事实在仓里散着**六份**拷贝,我改了两份、漏了四份:
#   ① panel-review 的 `launch_leg` case —— 漏 ⇒ 选中它时什么都不启动,而紧接着的
#      `LEG_PID[$name]=$!` 拿到上一条腿的 pid ⇒ **给它记一个假的 rc=0**;
#   ② `selected_identities` 的 family case —— 漏 ⇒ `local family` 在 set -u 下未赋值
#      ⇒ 整个函数崩,plan 里 `selected=` 变成空行(派了谁这件事当场丢失);
#   ③ observation 的 `_family` case —— 漏 ⇒ 归档闸数"覆盖了几个不同模型家族"时
#      这条腿静默不算数;
#   ④ 屏幕上那行 `family: ${_leg#sub}` —— 它印的"family"是**另一套词**(glm/gemini),
#      和归档闸用的(zhipu/google)对不上,读起来却像同一件事;
#   ⑤ HEAD 移动时给各腿日志追加横幅的那个循环 —— 漏 ⇒ 新腿的报告不带那条警告;
#   ⑥ tests/test-panel-observation.sh 的桩腿名单 —— 漏 ⇒ 判据永远问不到新腿。
# 「同一个事实存两处、只更新其中一个」是本机记账最多的一族毛病。修法不是"下次记得
# 改六处",是**让它只有一处**:下面这张表 + 几个取值函数,其余全部由它派生。
#
# 各腿开关的历史(理由要留着,免得下次当成偏好来回改):
#   subglm  `PANEL_GLM_LEG`:08-04 智谱欠费 ⇒ 默认 off;08-18 换成业主的 OpenCode Go
#           订阅,欠费这个理由消失 ⇒ 默认翻回 agent。同日默认档也翻了两次:
#           借 Claude Code 当壳时 Go 的 Anthropic 面对带工具的请求一律 400 ⇒ 只能 chat;
#           底座换成 opencode CLI 自己之后工具形状天然对得上 ⇒ 翻回 agent。
#   subdeepseek `PANEL_DEEPSEEK_LEG`:同形状,chat 强制走官方 chat API(空 diff 会瞎)。
#   submimo `PANEL_MIMO_LEG` / subkimi `PANEL_KIMI_LEG` / subgemini `PANEL_GEMINI_LEG`:
#           只有底座腿,没有聊天腿回落 —— 关掉就是少一条腿,不是降级。
PANEL_LEG_SPECS=(
  "submimo|xiaomi|submimo||PANEL_MIMO_LEG"
  "subdeepseek|deepseek|subdeepseek-agent|subdeepseek|PANEL_DEEPSEEK_LEG"
  "subglm|zhipu|subglm-agent|subglm|PANEL_GLM_LEG"
  "subkimi|moonshot|subkimi||PANEL_KIMI_LEG"
  "subgemini|google|subgemini||PANEL_GEMINI_LEG"
)

# 腿名单从表里长出来。**不许在别处再写第二份**(上面那六条就是这么来的)。
PANEL_LEGS_ORDER=()
for _panel_spec in "${PANEL_LEG_SPECS[@]}"; do
  PANEL_LEGS_ORDER+=("${_panel_spec%%|*}")
done
unset _panel_spec

# 取值函数一律 **fail-closed**:表里没有这条腿就返回非零、什么都不印。
# 调用方必须当场拒跑 —— 静默的空 family 会变成一句读起来完全正常的假话
# (「覆盖了两个不同模型家族」,而其中一条根本没被数进去)。
panel_leg_field() {  # panel_leg_field <腿名> <family|agent|chat|switch>
  local leg="$1" want="$2" spec name family agent chat switch
  for spec in "${PANEL_LEG_SPECS[@]}"; do
    IFS='|' read -r name family agent chat switch <<< "$spec"
    [[ "$name" == "$leg" ]] || continue
    case "$want" in
      family) printf '%s\n' "$family" ;;
      agent)  printf '%s\n' "$agent" ;;
      chat)   printf '%s\n' "$chat" ;;
      switch) printf '%s\n' "$switch" ;;
      *) return 2 ;;
    esac
    return 0
  done
  return 1
}
panel_leg_family() { panel_leg_field "$1" family; }
panel_leg_agent()  { panel_leg_field "$1" agent; }
panel_leg_chat()   { panel_leg_field "$1" chat; }
panel_leg_switch() { panel_leg_field "$1" switch; }

verdict_of() {  # verdict_of <log>; PASS/BLOCK/NEEDS_MORE_INFO/UNKNOWN
  local found
  # 只认独立裁决行。提示词和推理日志都可能原样出现
  # "Conclusion: PASS | BLOCK | NEEDS_MORE_INFO"，子串匹配会把没交卷误记成 PASS。
  #
  # 🔴 但**装饰要认**(2026-08-26 实事故):第三轮四审三条腿全记成 UNKNOWN、
  # 控制器据此多派了一条腿,而翻日志发现两条腿都下了结论 ——
  # submimo 写 `**Conclusion: PASS**`、subdeepseek 写带反引号的同一句。
  # 模型写 markdown 是常态,而那一行的内容仍然只有一个裁决值;
  # 真正要挡的歧义是**那行例子里的竖线**(PASS | BLOCK | NEEDS_MORE_INFO),
  # 它在任何写法下都过不了下面这条正则。契约钉在判据 R14(此前这个函数
  # **没有任何判据钉过它的行为**,而花名册/健康池/升级/observation 四处都用它)。
  # 允许的装饰:行首尾的 markdown 强调(**/__/*/_)和反引号,成对与否都不追究 ——
  # 追究配对只会让下一种写法再掉一次链子,而多认几个符号不引入歧义。
  found="$(grep -Eio '^[[:space:]]*[*_`]*[[:space:]]*(Conclusion|Verdict|结论)[[:space:]]*[：:][[:space:]]*(PASS|BLOCK|NEEDS_MORE_INFO)[[:space:]]*[*_`]*[[:space:]]*$' "$1" 2>/dev/null \
    | tail -n 1 | sed -E 's/[[:space:]*_`]+$//' \
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
  # **盘上有 state ⇒ 它真的跑过**,不管 plan 当初说没说要派它。
  # plan 是派发**之前**写的,升级追加的增补腿不在里面(控制器只翻了内存里的标志)。
  # 只信 plan 的话,一条真跑过的增补腿会被印成 SKIP(rotation),
  # 它要是跑失败了失败也一起消失 —— 正是这个功能存在要防的那种数据丢失。
  # (2026-08-23 评审腿 subdeepseek F1 在真控制器上复现的回归,判据 R9 守着。)
  [[ -s "$state" ]] && selected=1
  if [[ "$selected" != "1" ]]; then
    if [[ "$health" == "off" ]]; then printf '%s=off' "$name"
    elif [[ "$health" == "healthy" ]]; then printf '%s=SKIP(rotation)' "$name"
    else printf '%s=SKIP(health:%s)' "$name" "${health:-unknown}"; fi
    return
  fi
  if [[ ! -s "$state" ]]; then
    # 派出去了、却没有任何退出码落盘 ⇒ 这条腿没收尾。
    # **绝不许印成 PASS,也绝不许整行消失** —— 那正是这道闸存在的理由。
    #
    # ⚠️ 但也**不许断言它死了**:盘上的信息区分不了"被砍"和"还在跑"。
    # 2026-08-23 派全员评审时我用这命令查进行中的花名册,两条腿被印成 KILLED,
    # 而它们活得好好的、只是还没交卷 —— 这道闸自己犯了它要防的病:
    # **说了一句盘上证据支持不了的话**。
    # (不去区分在跑/被砍是**故意的**:那要引入 pid 或心跳,而 pid 会被复用,
    #  又是一个"看起来对"的方案。说不知道,比猜一个死因诚实。)
    printf '%s=未收尾(无 state:被砍或仍在跑)' "$name"
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
  local sel sel_count
  sel="$(_plan_kv "$plan" selected)"; sel_count="$(_plan_kv "$plan" selected-count)"
  if [[ -s "$final" ]]; then
    esc="$(_plan_kv "$final" escalation)"; head_after="$(_plan_kv "$final" head-after)"
    # 控制器活到收尾 ⇒ 它知道**升级之后**的选腿结果,优先用它(plan 是升级之前的)
    [[ -n "$(_plan_kv "$final" selected)" ]] && sel="$(_plan_kv "$final" selected)"
    [[ -n "$(_plan_kv "$final" selected-count)" ]] && sel_count="$(_plan_kv "$final" selected-count)"
  else
    # ⚠️ 缺 .final 只证明"**没有**收尾记录",不证明控制器死了 —— 它也可能**还在跑**。
    # 原话是 "unknown(控制器没活到收尾)",而 2026-08-23 第二轮评审**进行中**
    # 我用这命令看进度,它就把一个活得好好的控制器说成死了(评审腿 subdeepseek F4)。
    # 这道闸对腿守着 R7d(不许断言死因),对控制器自己却没守。判据 R12c/R12c2。
    esc="unknown(没有 .final:控制器没活到收尾,或仍在跑)"; head_after=""
    # 同理:plan 是**派发前**写的,升级追加的增补腿不在里面。腿那行靠盘上的 state
    # 补得齐(R9),但这两句头补不了 ⇒ 必须标明它是快照,不许读起来像事实(F2/R12d)。
    [[ -n "$sel" ]] && sel="$sel(派发前快照,.final 缺失时不含升级追加的腿)"
    [[ -n "$sel_count" ]] && sel_count="$sel_count(派发前快照)"
  fi
  echo "# panel-review 花名册($(date '+%F %T'))task=$(_plan_kv "$plan" task)"
  echo "# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。"
  echo "# impact-risk=$(_plan_kv "$plan" impact-risk) requested-budget=$(_plan_kv "$plan" requested-budget) selected-count=$sel_count"
  echo "# selected=$sel"
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

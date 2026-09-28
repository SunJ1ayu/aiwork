# Verify: legs-quick-fixes

- Date: 2026-09-14

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

## 主 agent 亲跑/亲读发现(读任何 panel 之前)

- **判据**:`tests/test_leg_quick_fixes.py` 十条(七目标 + 三对照)。首跑时 9 红,其中 2 条是我夹具的错
  (DeepSeek 对照没拷 `deepseek-model`;emit 复用同一结果文件 ⇒ 第二次读回第一次的 quota)⇒ 修夹具后
  **旧实现上恰好 7 红、3 对照绿**,提交 `9661023` 后留红收据;修复 `592a335` 后 10 绿。
- **在使用现场验证(16:09,主 agent 亲跑,非判据收据;tiny 仓 `add.py`)**,新旧各跑一次同一道题:
  - A4 GLM 底座腿,题面要求先读 `/etc/hostname`:
    - 旧 `subagent`(`9661023`):`! permission requested: external_directory (/etc/*); auto-rejecting` → `✗ Read /etc/hostname failed`
      → `Glob "add.py"` 后整轮结束 → `subglm-agent: model returned no verdict`,rc=1。
    - 新:同样被拒,之后 `Read add.py` → `Step 1: the /etc/hostname read was denied by the harness …` → `Conclusion: PASS`,rc=0。
  - A5 GLM 聊天回落腿(`subglm`):
    - 旧引擎:`HTTP 400 … "type":"MissingSessionID","message":"Error from provider (Console Go): Request is missing x-opencode-session …"`,rc=1(今天仍复现)。
    - 新:rc=0,正常返回(结论 NEEDS_MORE_INFO 是聊天腿在干净仓上「看不见代码」的已知限制,不是本单的事)。
  - A1 MiMo(`submimo`):真跑本地断言后 `Conclusion: PASS`,rc=0。
  - A2 subkimi 的抄错误行只走失败路径,真跑触发不了额度窗口 ⇒ 只有离线判据,如实记。
- **我自己的风险判断**:
  - A3 若某家把「余额耗尽」也写成 usage limit ⇒ 那条腿永不停轮换(每次冷却后再失败一次、有备用腿兜底)= 回到 08-25 前的行为,可接受。
  - A2b 只认 kimi-code 0.36.1 的 `^error: failed to run prompt:` 措辞;CLI 改措辞就退回「runtime」(只是归类变粗,不会假绿)。
  - A4 被拒后继续 ⇒ 模型可能反复撞被拒工具直到 `steps=40`,有上限。
  - A1 只改了 GLM/DeepSeek(subagent)和 MiMo;Kimi/Grok 的契约仍在任务书前但另有「先写裁决」指令,第三轮两家都按格式交卷,不动。
  - 这次评审的腿用的就是改过的提示词(自指),不影响判断:它们审的是代码,不是自己的输出。
  - **A2 回落扫正文的老路径**:`failure_text` 在我们的诊断为空时回落到模型正文。若某腿 rc≠0、stderr 为空、而正文恰好写到
    "usage limit"(例如正在审本单)⇒ 被归成 rate_limit、不计连败。与 08-28「正文 auth 误判」同类;窗口词比 auth 罕见,
    且各腿失败时 stderr 几乎总有我们自己的一行 ⇒ 接受,列为外审要攻的点。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [ ] build passes
- [ ] tests pass
- [ ] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t legs-quick-fixes -- <判据命令>
```

```
runlog: oracle-red-on-old-code rc=1 commit=9661023 dirty=no at=2026-09-14T07:58:05Z file=tracks/legs-quick-fixes/evidence/20260914T075805Z-01-oracle-red-on-old-code.txt
runlog: oracle-green rc=0 commit=592a335 dirty=no at=2026-09-14T07:59:51Z file=tracks/legs-quick-fixes/evidence/20260914T075951Z-01-oracle-green.txt
runlog: full-regression rc=0 commit=592a335 dirty=yes final=yes at=2026-09-14T07:59:58Z file=tracks/legs-quick-fixes/evidence/20260914T075958Z-01-full-regression.txt
```

- 红收据:旧实现上恰好 7 条目标红、3 条对照绿。
- 全量回归 27 组全绿(含新套件 `leg-quick-fixes`);`dirty=yes` 只是上一份未提交的 `oracle-green` 收据与 observation,实现与判据跑前已提交。 **第一轮外审后过期,见下。**

第一轮外审发现(Kimi F1~F5)→ 判据 `e75ae0a` 先红 → 修 `cc07024` → 绿 → 最终全量回归:

```
runlog: oracle-r1-findings-red rc=1 commit=e75ae0a dirty=yes at=2026-09-14T08:28:50Z file=tracks/legs-quick-fixes/evidence/20260914T082850Z-01-oracle-r1-findings-red.txt
runlog: oracle-r1-findings-green rc=0 commit=cc07024 dirty=no at=2026-09-14T08:30:24Z file=tracks/legs-quick-fixes/evidence/20260914T083024Z-01-oracle-r1-findings-green.txt
runlog: full-regression-r1 rc=0 commit=a2166ec dirty=no final=yes at=2026-09-14T08:30:33Z file=tracks/legs-quick-fixes/evidence/20260914T083033Z-01-full-regression-r1.txt
``` **第二轮外审后过期,见下。**

第二轮外审发现(DeepSeek F1~F4 + GLM 中文裁决)→ 判据 `233d681` 先红 → 修 `6d8cbf6` → 绿 → 最终全量回归:

```
runlog: oracle-r2-findings-red rc=1 commit=233d681 dirty=yes at=2026-09-14T09:00:52Z file=tracks/legs-quick-fixes/evidence/20260914T090052Z-01-oracle-r2-findings-red.txt
runlog: oracle-r2-findings-green rc=0 commit=6d8cbf6 dirty=no at=2026-09-14T09:02:01Z file=tracks/legs-quick-fixes/evidence/20260914T090201Z-01-oracle-r2-findings-green.txt
runlog: full-regression-r2 rc=0 commit=99a94ae dirty=no final=yes at=2026-09-14T09:02:11Z file=tracks/legs-quick-fixes/evidence/20260914T090211Z-01-full-regression-r2.txt
```

## Review

- 规格自查:规格=「腿交的活要算数、死因要记对」。若规格本身错,最可能错在 A3 的分界 ——「自愈的窗口」和「要人管的欠费」
  靠文案区分,文案是供应商写的、会变。第一轮 Kimi 正是从这里攻进来的(F2);我能做的是让豁免只来自我们自己的诊断、
  且遇付费词就不豁免,错的方向是「多踢一次好腿」而不是「永不踢坏腿」。
- 腿的花名册(第一轮,subject `f58ec51`):
  submimo=PASS(verdict=PASS) subdeepseek=SKIP(rotation) subglm=SKIP(rotation) subkimi=PASS(verdict=PASS) subgemini=SKIP(health:dead:FAIL:6) subgrok=off
- findings(第一轮,逐条核实):
  - **Kimi F2(MEDIUM)成立,已修。** 我加的 `quota will reset` 太宽:「402 payment required. Your quota will reset on the next billing cycle」
    被归 rate_limit ⇒ 欠费的腿永不停轮换。窗口词收窄为 `usage limit`,且同句有 billing/payment/balance/402 就不算窗口。
  - **Kimi F1(MEDIUM)成立,且比它说的更宽,已修。** 诊断为空回落到正文时,不只我新加的窗口词,**原有的 `rate.?limit` 也会匹配正文**
    (判据里我写的正文恰好含 `rate_limit`,修完 F1 仍红一条才暴露)。rate_limit 现在只从我们自己的诊断得出。
  - **Kimi F3(LOW)成立,已修。** health.tsv 把 rate_limit 记成 quota,运维分不清「等窗口」和「欠费」⇒ 记成 rate_limit(无代码依赖旧标签,已 grep)。
  - **Kimi F4(LOW)成立,已补判据。** 正文回落零覆盖、DeadStreak 无 quota 对照 ⇒ 补 `test_window_words_in_model_prose_never_exempt_a_failure`、
    `test_control_balance_exhaustion_still_counts`。「继承的 MIMO_SESSION_HEADER 被清」仍不可从外部观测,接受。
  - **Kimi F5(INFO)部分采纳。** 补 `test_subkimi_copies_only_cli_error_lines`(只抄错误行、不抄正文);
    契约判据只跑 GLM 不跑 DeepSeek:两者共用同一 `REVIEW_PROMPT` 变量,接受。
  - MiMo PASS:结论与我自审一致(回落路径是窄概率旧逻辑、会话头四项成立、A1/A4 无副作用、判据盲区已记),无新发现。
- 腿的花名册(第二轮,subject `b417a2d`):
  submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=BLOCK) subglm=FAIL(rc=1,降级:回落聊天腿也没成) subkimi=SKIP(rotation) subgemini=SKIP(health:dead:FAIL:6) subgrok=off
- findings(第二轮,逐条核实):
  - **DeepSeek F1(HIGH)成立,已修 —— 我上一轮修 F2 时打坏了一条真实文案。** `refs/ctxdiet-backup-20260726-210435/memory/subkimi-moonshot-wrapper.md:39`
    与 `logs/panel-rcpycache.subkimi.log` 原文 `error: failed to run prompt: provider.api_error: 403 You've reached your usage limit for this
    billing cycle. Your quota will be refreshed in the next cycle …`:下个周期自愈,但 `billing` 否决后被 `403` 认成 auth 并计连败。
    教训:**我拿一条假设的欠费文案(402 … next billing cycle)去收紧,打坏了一条真实出现过的文案** —— 收紧前该先去日志里搜真实措辞。
    否决词改为 `payment|balance|402`。
  - **DeepSeek F2(MEDIUM)成立,已补判据**:加真实 billing-cycle 原文 ⇒ rate_limit。
  - **DeepSeek F3(MEDIUM)部分不成立**:它说判据里 kimi 错误行是「按期望前缀捏造的」。实为两份真实腿日志逐字复制
    (09-09 `provider.auth_error`、08-08 `provider.api_error`,前缀都是 `error: failed to run prompt:`);判据里已注明出处。
    CLI 改措辞就退回 runtime 的风险仍在,已在风险判断里。
  - **DeepSeek F4(LOW)成立,已修判据**:F1 断言从「≠ rate_limit」改为「= runtime」。
  - **DeepSeek F5(LOW,旧有)成立,不在本单**:agent 腿(subagent)与 submimo 非零退出时 facts 写死 `failure_kind=runtime`,文本归类器根本不跑
    ⇒ A2/A3 只惠及 subkimi 与聊天腿。写死是有意的:subagent 的 stderr 里是底座工具轨迹(含被审代码里的 auth 等词),放开就回到 08-28 那类误判。
    要做需像 subkimi 一样只抽供应商错误行 —— 记账。
  - **GLM FAIL 查实不是腿坏了**:opencode DB 该会话 `finish=stop`、33 条消息,最后一段正文完整写完审查,收尾一行 `结论：通过`
    ⇒ 解析器不认中文值 ⇒ 整份作废,回落聊天腿又把工具调用当文本输出(`<tool_call>bash…`)无裁决。**A1 的「任务书后重申契约」没拦住它**
    (09-07 `结论：通过 (PASS)` 之后第二次)⇒ 设计里「不先放宽解析器」的前提被证伪:题面位置不够,中文值本身要认。
    判据先红:独占一行的 `通过/不通过/阻断/需要更多信息` 认;括号英文须一致;`通过但有疑问`/`基本通过`/行内提及/`通过 | 阻断` 仍 UNKNOWN。
  - MiMo PASS:与自审一致,无新发现。
- 腿的花名册(第三轮,subject `9fd6702`):
  submimo=PASS(verdict=PASS) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:cooldown:FAIL) subkimi=SKIP(rotation) subgemini=SKIP(health:dead:FAIL:6) subgrok=off
- findings(第三轮,逐条核实):
  - DeepSeek F1(MEDIUM)成立但**非本单引入**:`**结论**：通过`(只加粗标签)、`## 结论：通过`、`> 结论：通过`、`- 结论：通过`、`结论：通过（通过）` 仍 UNKNOWN。
    英文同样不认列表/标题/引用形态(09-03 Kimi 写成 `- Conclusion: PASS` / `• Conclusion: PASS` 整份被丢,见 memory panel-timeout-should-be-liveness)。
    本单 A6 覆盖的是 GLM **实际写出**的两种形态;其余形态进后续账,不阻断。
  - DeepSeek F2(LOW)成立、既有设计:「最后一行独立裁决算数」⇒ 真结论之后再引用别人的独立裁决行会覆盖(英文同理)。进后续账。
  - DeepSeek F3(LOW)成立:判据只锁「英文在后覆盖中文」,没锁反向;一个「有英文就优先英文」的错误实现能全绿。进后续账(补一条反向用例)。
  - DeepSeek INFO:中文「余额不足」不命中 `QUOTA_FAILURE_RE`(既有盲区,同句 429 兜底)。进后续账。
  - DeepSeek/MiMo 对 Q2(缩窄否决词后有无真实欠费文案翻成 rate_limit)各自搜 logs/refs 后都答**没有**,与我一致。
  - MiMo 表格里 Zhipu「1113 余额不足」「归 runtime」的推理有误(同句常有 429,归 rate_limit),不影响本单结论。
- arbitrated verdict (主裁): **PASS**。第三轮同一 subject 下 MiMo、DeepSeek 两个家族合格覆盖(high=2),无冲突。
  三轮外审里成立的发现:Kimi F1~F3、DeepSeek R2 F1/F2/F4 已修并先红后绿;其余为既有局限,列入下面的后续账。

## Accepted deviations

- **停滞检测(单 B)不做**:业主 09-14 定「先不做,观察一段时间」。墙钟上限照旧,大题仍可能被砍。
- **后续账(下一次动裁决/归类时一起做)**:① 裁决行认列表符号/标题/引用/只加粗标签(中英文同);② 判据补「中文在后覆盖英文」;
  ③ 中文「余额不足」归 quota;④ agent 腿与 submimo 非零退出写死 runtime ⇒ 需像 subkimi 那样只抽供应商错误行才能让 A2/A3 惠及它们;
  ⑤ 「最后一行算数」被正文引用覆盖(既有设计,要改需先定规则)。
- A2b 只认 kimi-code 0.36.1 两种已见措辞的 `error: failed to run prompt:` 前缀;CLI 改措辞 ⇒ 退回 runtime(归类变粗,不假绿)。
- A5 「继承的 MIMO_SESSION_HEADER 被清」不可从外部观测,只靠代码亲读。

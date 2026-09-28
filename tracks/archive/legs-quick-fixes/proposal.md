# Proposal: legs-quick-fixes

- Date: 2026-09-14
- Status: open

## Goal

把评审腿「写完了却不算数 / 死因记错」的五个小口子一次补上,每个都有真实出处:
A1 裁决契约没说或说在长任务书前面;A2 额度窗口被记成 runtime/auth;A3 自愈的额度窗口把腿推向停轮换;
A4 opencode 被拒一次就停整轮;A5 OpenCode Go 聊天回落腿缺 `x-opencode-session`。

## 真问题(第一性)

- 用户原话:「先把 glm 和 kimi 还有这些腿调试正常」「为什么不能每次都由你看一下这些腿还在不在写东西,
  现在这样超时直接杀已经出发很多次了」「kimi和glm还没修好吗」
- 真正要解决的是:腿交出来的活要算数,腿死了要知道真死因(该等的等、该人管的叫人)。
- 我在这中间翻译了什么:「调试正常」拆成两单 —— 本单是改动小、证据确凿的快修;
  「看腿还在不在写」(停滞检测替代墙钟)是第二单(设计不确定性高)。之前说过把它排第一项,
  09-14 下午我对业主改口为先做快修,理由是快修几小时内就能让 GLM/Kimi 更稳,停滞检测要半天以上设计。

## Scope

- in:A1~A5,每项先判据后修复;修完真跑一次 GLM/Kimi 冒烟。
- 证据:`logs/panel-grok-leg-kimi-model-review-r2-*.submimo.log`(无裁决行)、opencode DB 裁决行漂移、
  `logs/panel-delivery-r3-20260909T040119Z.subkimi.log`(5-hour usage limit → runtime)、
  `logs/panel-delivery-binding-20260909T030406Z.subglm.log.err`(MissingSessionID)、opencode 1.18.18 `continue_loop_on_deny`。

## Non-goals

- 停滞检测 / 被砍收尸(第二单)。GLM 断流重试(第二单一起设计)。Kimi 能力声明跟随 `/models`(K2,另单)。
- 放宽裁决解析器去认 `通过 (PASS)`:先治「契约说没说、说在哪」,不先改判卷去迁就。

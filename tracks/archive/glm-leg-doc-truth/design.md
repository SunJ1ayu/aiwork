# Design: glm-leg-doc-truth

- Change: glm-leg-doc-truth
- Status: accepted

> Panel hook — 仅当这是真·开放架构分叉(多个站得住的方向、风险=隧道视野)时,
> 先跑 `panel-explore`,把方向谱折叠进这里。否则直接写方向就行。
> 主 agent 在读任何 panel 输出之前,先落自己的方向(反锚定)。

- 规划双出: 不适用：没有新写面或开放架构分叉，只把已由运行代码证明的事实写准。
  > **只剩一个触发条件:新写面 / 开放方向且这单我自己干**(动档案格式、写口语义扩张、
  > 新增参数……即 `decision.json` 的 `impact.factors` 会含 `new_write_surface` 的同一批面)。
  > **"要外包给执行腿"那半句 08-06 退场** —— 它升级成了 `delegate-codex --attack-log`:
  > 派活时给不出攻题记录就发不出去,不再靠我在这一格里自评(08-05 我就是在这格里
  > 用一句括号把它绕过去的)。
  > 做法:主 agent **先落盘**,再让 `gpt-5.6-sol` 对**同一份需求**独立出一版
  > (明令不许读本 track 的工件),然后对差异。抓的是**"我以为理所当然"的地方** ——
  > 那正是"我出方案、它来审"照不到的死角(审查只会在我的框子里挑毛病)。
  > 史料:08-02 due-writer 单它点破了我判卷题的一个洞(`fef253c`);
  > 08-06 delegate-entry 单它点破三处(攻题记录会过期 / 闸①没给闸③底账 /
  > 红检没区分"红在 build 上")—— 两次都是**结构性的洞,不是措辞**。

## Approach

以运行时唯一源为判准：`subagent` 的 `AGENT_BASE`/`OC_BASE_URL`/`DEFAULT_MODEL`、
花名册的 agent/chat 映射和 panel 的默认选择。先在 `test-workflow-docs.sh` 加正反两面
契约并保存旧文字红检，再做最小文字修正；规范源改完通过同步器部署。

## Key trade-offs / risks

- 不把历史踩坑记录删掉，只把它明确放进历史语境；否则会丢失为什么不用 Claude 壳的依据。
- 文本 grep 只能守关键契约，不能证明整篇没有语义矛盾；最终仍需逐段人工复读。

## Alternatives considered

- 只改模型名：已完成，但不能修复默认腿/底座/端点的错误叙述。
- 从文档自动生成运行配置：范围过大，本单只做一致性修复。

## Test strategy (oracle)

新判据同时读取运行源与活文档：要求 opencode agent、`/zen/go/v1`、agent 默认和 chat
fallback 四个事实一致，并禁止已确认的旧断言；另检查 CLI help、README 和 Gemini 枚举。

**这个 oracle 能被什么骗过?**

断言可能被“同时存在一句正确话和另一句错误话”骗过，所以正向匹配之外还要禁止本轮已发现
的旧断言；仍可能漏掉新的同义矛盾，靠主 agent 对所有活 GLM 引用做全量搜索与人工分类兜底。

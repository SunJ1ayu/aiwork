# Design: review-result-v2

- Change: review-result-v2
- Status: accepted

> Panel hook — 仅当这是真·开放架构分叉(多个站得住的方向、风险=隧道视野)时,
> 先跑 `panel-explore`,把方向谱折叠进这里。否则直接写方向就行。
> 主 agent 在读任何 panel 输出之前,先落自己的方向(反锚定)。

- 规划双出: 不适用：前三轮源码审计与独立方案交叉检查已经完成，用户已确认 P0 实施边界。
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

1. `bin/_review_result.py` 是唯一 executable schema、verdict normalizer、terminal
   result producer 与 coverage predicate。
2. adapter 只交 invocation、process、snapshot、view 与 raw evidence 事实。
3. reader-first、shadow-sidecar-first；全部 adapter 能产 typed terminal 后才切 writer/consumer。
4. `subject_digest` 只含 task 原始字节和实际 Git snapshot；review contract 独立版本化。
5. evidence ref 定位原始文件，digest 验证内容，缺任一项都不计 coverage。

## Key trade-offs / risks

- v1 只读且不从 raw log 回填；旧 active track 需要新增 v2 panel 才能过新闸。
- 跨 run 只计算 shadow candidate；最终 outcome 未绑定 digest 前不放行。
- provider 未提供 attestation 时只能证明实际 CLI model 参数，不能声称证明服务端路由。

## Alternatives considered

- 立即拆 aiwork-core/adapter 层：拒绝；先集中语义，wrapper 会自然变薄。
- 用 run_id/name 猜 raw log：拒绝；自定义 prefix、fallback 和 controller death 都会歧义。
- timeout 有 verdict 即成功：拒绝；保留 partial evidence，但不得 coverage eligible。

## Test strategy (oracle)

新增 result contract 单测，并扩充 workspace、review-tooling、panel-roster、
panel-observation、track-record 判据。每个逻辑提交跑对应套件；最终跑完整
`bin/rust-check-review-tooling`。

**这个 oracle 能被什么骗过?**

桩可能全绿但生产 wrapper 没调用 producer，或 panel 与 archive 调了不同参数。
因此要有真实 wrapper sidecar 测试、controller-death 测试和同一 fixture 的 consumer parity 测试。

# Design: glm-5-3-default

- Change: glm-5-3-default
- Status: accepted

> Panel hook — 仅当这是真·开放架构分叉(多个站得住的方向、风险=隧道视野)时,
> 先跑 `panel-explore`,把方向谱折叠进这里。否则直接写方向就行。
> 主 agent 在读任何 panel 输出之前,先落自己的方向(反锚定)。

- 规划双出: 不适用:没有新写面或开放架构分叉，只是同 provider 内默认模型替换
  > **只剩一个触发条件:新写面 / 开放方向且这单我自己干**(动档案格式、写口语义扩张、
  > 新增参数……即 verify 那边会填 `lane: full` 的同一批面)。
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

同时把 `subagent` 的休眠/default 与 `OC_MODEL_ID`、`subchat` 的 fallback default 改为
`glm-5.3`；保留 `ZHIPU_MODEL` override。先把现有断言改成 5.3 并保存红收据，再改生产值。

## Key trade-offs / risks

- 模型已出现在当前 key 的 `/models`，但静态配置与 stub 测试仍可能掩盖真实工具调用不兼容；
  因此必须补一次真实 `subglm-agent` 冒烟。

## Alternatives considered

- 只在当前 shell 导出 `ZHIPU_MODEL=glm-5.3`:不持久，不能完成“切换默认值”。
- 只改 agent 腿:chat fallback 会继续退回 5.2，形成隐蔽的模型漂移。

## Test strategy (oracle)

- 修改前，5.3 默认断言必须对 5.2 实现跑红。
- 修改后，`tests/test-review-tooling.sh` 与总入口全绿。
- 用现有 Go 订阅真实运行一次 `subglm-agent`，日志必须回显 `model: go/glm-5.3` 并产出裁决。

**这个 oracle 能被什么骗过?**

stub 断言可在端点拒绝 5.3 时仍全绿；真实 Go 冒烟负责接住这种假绿。

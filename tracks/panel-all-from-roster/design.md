# Design: panel-all-from-roster

- Change: panel-all-from-roster
- Status: accepted

> Panel hook — 仅当这是真·开放架构分叉(多个站得住的方向、风险=隧道视野)时,
> 先跑 `panel-explore`,把方向谱折叠进这里。否则直接写方向就行。
> 主 agent 在读任何 panel 输出之前,先落自己的方向(反锚定)。

- 规划双出: 不适用：不存在开放架构分叉；稳定抽象只有“预算评审”和“全池评审”。
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

1. `_panel-roster-lib.sh` 的 `PANEL_LEGS_ORDER` 继续作为腿集合唯一源。
2. `--all` 在载入花名册后把预算设为当前池大小，并以显式 `--all`/最大预算决定是否绕过健康冷却；不写死 4 或 5。
3. `panel-review --help` 从同一张表渲染池成员，文档统一称“全池评审”。
4. `track-record` 删除腿数上限；compact 的真实边界已经是单 observation 64 KiB，重复的数字上限只会与花名册漂移。

## Key trade-offs / risks

- `--all` 仍排除显式 `off` 或二进制不存在的腿；“全池”指当前已启用且可执行的池，不是假装派出不可用构件。
- 历史叙事里的“四审”保留，因为它描述当时发生的事实；只移除现行契约里的固定数字。
- observation 接受任意数量的合法腿对象，但仍受严格字段白名单、标识符校验与 64 KiB 文件上限约束。

## Alternatives considered

- 把常量从 4 改成 5：拒绝；下次增删腿会再次漂移。
- 让 `track-record` 解析 shell 花名册：拒绝；会让通用证据 schema 反向依赖 panel 的 Bash 实现，字节上限已足够承担 compact 边界。

## Test strategy (oracle)

- `test-review-tooling`：`--all` 的调用数等于运行时花名册长度，帮助列出花名册全部成员。
- `test-panel-observation`：track-bound `--all` 派出并记录花名册全部腿。
- `test-track-record`：当前池大小的合法 observation 被接受，64 KiB 上限仍拒绝超大事件。
- `test-workflow-docs`：README 与 panel skill 使用“当前池/全池”语义。

**这个 oracle 能被什么骗过?**

如果测试自己手抄五条腿，新增第六条后仍会假绿。因此所有数量和期望名单必须在运行时从 `_panel-roster-lib.sh` 读取；行为测试检查真实桩调用和落盘 observation，而不是 grep 源码。

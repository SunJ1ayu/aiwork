# Design: glm-flash-single-source

- Change: glm-flash-single-source
- Status: accepted

> Panel hook — 仅当这是真·开放架构分叉(多个站得住的方向、风险=隧道视野)时,
> 先跑 `panel-explore`,把方向谱折叠进这里。否则直接写方向就行。
> 主 agent 在读任何 panel 输出之前,先落自己的方向(反锚定)。

- 规划双出: 不适用:没有新写面或开放架构分叉；同一 Go provider 内替换模型，并删除
  一个已有的重复事实源
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

`subagent` 已经通过统一的前缀查表把 `ZHIPU_MODEL` 解析为 `MODEL`；真正的 bug 是
opencode 分支随后绕开它，改用 `OC_MODEL_ID`。因此最小且完整的修法是：

1. GLM 的 `DEFAULT_MODEL` 改为 `glm-5.3-flash`。
2. 删除 `OC_MODEL_ID`，opencode 配置、provider model map、日志和 `-m` argv 全部使用
   已解析的 `MODEL`。
3. chat executor 的 standalone 默认值同步到 Flash；它现有的 `ZHIPU_MODEL` 解析不变。
4. 判据同时钉住默认值与 agent override，防止以后再次出现“环境变量看似支持、主路径忽略”。

这使日常/试验换模型只需设置一次 `ZHIPU_MODEL`。永久修改内建 fallback 仍需同步两个
独立 executor 的默认值、契约判据和文档；这些是可见的合同更新，不是隐藏的基础设施联动。

## Key trade-offs / risks

- 不为省掉两个 standalone fallback 字面量新增共享文件。两个脚本在大量隔离夹具中会被
  单独复制；新增必需运行时依赖会扩大部署/夹具耦合，收益小于成本。
- Flash 虽与 5.3 同协议，静态 stub 仍可能掩盖服务端工具调用不兼容，因此最终必须有
  真实 Go 工具调用和真实 wrapper 身份回显。
- 这是 `judging_control`：模型质量变化会影响外部评审证据，按 high 风险取两家独立评审。

## Alternatives considered

- 新建共享 `review-models.sh/json`：能把 fallback 字面量缩成一处，但给 `subagent`、
  `subchat` 及十余个隔离夹具新增必需依赖；这是为一行数据制造新的失效面。
- 只设全局 `ZHIPU_MODEL`：能临时切换，但当前 agent 正在忽略它，且不能交付新的内建默认。
- 只改 `OC_MODEL_ID`：Flash 能跑，却保留了导致这次问题的第二事实源。

## Test strategy (oracle)

- 红检先要求 agent/chat 默认均为 Flash，并新增 agent `ZHIPU_MODEL=glm-custom` 的配置、
  argv、日志三向断言；旧实现必须只红这些新合同。
- 实现后定向 `test-review-tooling.sh`、工作流文档判据和总入口全绿。
- 真实 OpenCode Go 请求必须返回 `model=glm-5.3-flash` 且产生工具调用；真实 wrapper
  必须在日志头回显 `model: go/glm-5.3-flash` 并产出裁决。
- 亲读 diff 确认端点、认证、权限、轮次和其他腿零变化。

**这个 oracle 能被什么骗过?**

stub 可以证明我们传了哪个字符串，却不能证明 Go 接受该模型或 Flash 会生成工具调用；
真实端点探针和 wrapper 冒烟接住这种假绿。反过来，真实默认冒烟不能证明 override 生效，
所以必须保留 `glm-custom` 的隔离行为断言。

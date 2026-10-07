---
name: panel
description: 可选的方案发散与第二意见工具用法。正式评审使用 PR 上的 review-pr。
---

# panel — 方案发散与第二意见

评审与修复规则见 [REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)，项目已接受风险见项目 main 的
`.aiwork/accepted-risks.md`，正式评审与合并条件见项目关卡策略。
正式评审在 PR 开好后使用 `review-pr`；panel 输出用于辅助分析。

## 选择工具

- 大改动开工前，方向尚未明确时，可选 `panel-explore` 发散方案。
- 有具体 diff，需要补充代码意见时，可选 `panel-review`。
- 较大改动能清楚划分职责时，`panel-slice` 提供切片分析。
- 局部明确的修改直接实现和验证。

先写自己的判断和最危险的前提，再阅读补充意见；用实际代码、复现或实验核实发现。
不要把自己的结论或同伴报告塞进独立输入，也不要用多份意见代替自己的检查。

## 候选与显式成员

```bash
panel-candidates --mode review
panel-candidates --adapter subcursor --discover-cursor --mode explore
panel-review --members submimo,subcursor@composer-2.5 TASK REPO PREFIX
panel-explore --members subcursor@grok-4.7-high BRIEF REPO PREFIX
```

候选描述模型、通道、可读仓能力及历史健康状态，余额与登录是否有效仍须核实。
需要核查源码时选择 `reads_repository=true` 的成员；MiMo explore 只读取题面。
`--members` 冻结本次模型、可在同一通道选择多个模型，不自动补人或回落。
自动路由与未知模型家族不可用。可选参数及兼容入口见各命令 `--help`。

## panel-review

```bash
panel-review --require-my-review SELF_REVIEW TASK REPO PREFIX
panel-review --all --require-my-review SELF_REVIEW TASK REPO PREFIX
panel-roster PREFIX
```

`--all` 是全池评审工具参数。成员来自共享登记表；新增或关闭通道以登记表和本机配置为准。
日志默认位于本机数据目录。自审文件通过 `--require-my-review` 指定，放在被读仓库之外；
未提供时工具按任务名查找默认自审文件。`--no-my-review` 是工具的显式例外参数。

`PANEL_ORACLE_CMD` 可记录本次客观检查；`PANEL_DIFF_BASE` 指定 diff 基线，
`PANEL_INCLUDE` 给聊天腿附加文件。聊天腿只有 diff 与附件，读仓腿才有完整源码视图。
程序返回码描述调用是否完成，报告中的意见需分别核实。

显式成员不自动回落；旧轮换入口的 DeepSeek/GLM 读仓腿可回落聊天腿，日志会标明变化。
各成员的 `.log`、`.err`、`.state`、`.result.json` 和整体 `.plan`、`.roster` 用于定位问题。
失败、超时或部分输出可保留有用发现，不能写成已完成调用。

健康记录在数据目录的 `logs/.panel-state/`。按实际模型记录冷却与连续失败；
确认故障处理后，可用 `PANEL_HEALTH_OVERRIDE=<member-name>=healthy` 明确重试。
断线后先看记录与进程，`panel-roster PREFIX` 可从盘上重建状态；日志不动不说明进程已死。

## panel-explore

这是大改动开工前可选的方案发散。brief 给用户目标、已有事实、约束和待核实前提，
让每个成员提出方向、取舍、盲点及最小验证实验。主 agent 再核实并比较方案。

```bash
panel-explore --members subcursor@grok-4.7-high BRIEF REPO PREFIX
```

显式选择本次成员；不带 `--members` 的兼容入口可能派多个默认通道。
探索输出是方案材料，正式评审仍在 PR 上通过 `review-pr` 完成。

## panel-slice

```bash
panel-slice run --require-my-review SELF_REVIEW MANIFEST REPO RUN_DIR
panel-slice status RUN_DIR --json
panel-slice verify RUN_DIR VERIFY_MANIFEST
panel-slice retry RUN_DIR ITEM --leg LEG
panel-slice abandon RUN_DIR ITEM#N --reason REASON
panel-slice decide RUN_DIR FINDING confirmed --reason REASON
```

manifest 指定目标、切片、整体分析及调用安排；字段与限制见 `panel-slice --help`。
运行目录放在被读仓库之外，每项使用共享的副本隔离与结果记录机制。
`status` 重建调用状态；登记问题时用具体尝试编号，避免漏掉先前尝试的发现。
`abandon` 用于排查没有终态的尝试，不掩盖后来出现的结果；有活进程时工具会拒绝。

## 正式 PR 评审

```bash
review-pr PR_NUMBER --repo owner/name --leg subdeepseek-agent
```

该命令在沙箱外运行，使用 PR 当前 head 的源码和 main 的规则，由 review 身份发布 PR 评审。
修改与合并判断读取规则入口，不从 panel 的本机状态推导。
各通道的认证、隔离、参数和故障定位见 [references/legs.md](references/legs.md)。

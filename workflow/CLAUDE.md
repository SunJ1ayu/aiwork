# Agent Instructions

本文件是 aiwork 源码 `workflow/CLAUDE.md` 的部署副本。工具位于源码的 `bin/`，可加入 PATH。
工作流 skill 的源码位于 `workflow/skills/`；`bin/sync-workflow-docs --check` 检查部署漂移。

## 规则入口

评审与修复规则：[aiwork main 的 REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)。
项目已接受风险见项目 main 的 `.aiwork/accepted-risks.md`；正式评审与合并条件见项目关卡策略。
需要判断时读取这些来源，说明文件只提供入口。

## 一个任务的走法

所有项目都不得放任何密钥和私人信息。密钥只保存在项目外的本机设置目录（aiwork 使用 `~/.config/aiwork/`），项目通过统一入口读取。推送前由 `privacy-check` 兜底，不许用 `--no-verify` 绕过；误报就改本机私人词表或测试夹具。

1. 从最新 main 拉分支。开工先在本机数据目录建自己的工作树，在里面拉分支干活，不在共享检出（如 /root/aiwork）里直接改。路径用 `aiwork-config data-path worktrees` 取。PR 合并后删掉这个工作树。
2. 改代码时，先写先红的测试，再实现（怎么算见 REVIEW-RULES 第一节第 3 条第 1 步）。
3. 全跑项目 `tests/`，核对结果及已明确允许的例外。
4. 用机器人提交和推送，以机器人身份开 PR，然后停下。
5. PR 开好、CI 绿了以后，用 `review-pr` 派评审腿。
   `review-pr` 必须在沙箱外运行；使用目标仓库当前 PR head 和 main 的规则来源。
   `review-pr` 从共享检出跑，跑之前先把共享检出更新到最新 main。
   改到项目策略 high 路径的 PR，所有能跑的腿都跑一遍；关卡要几家见项目策略的 `high_min_families`。
   各腿出结果后，由汇总处理（见 `summary` skill）。
6. 修改方怎么修，见 REVIEW-RULES 开头的「一轮」。
   合并由项目关卡或业主完成。合并后用 `sync-workflow-docs` 同步部署出去的工作流文档。

## 做事的方法

- 判据红了，先用具体输入复现，确认是实现问题还是测试题面的问题；不改考卷让自己及格。
- 自己写的判据也可能错；检查它能否区分正确和错误行为，必要时对旧实现或基线做对照。
- 收货不信执行腿的自述：看真实 diff 和未跟踪文件，自己跑检查，再读实际改动。
- 派 PR 任务的规则和格式见 `delegate` skill。
- 一轮评审出完结果后，用 `summary` skill 汇总。
- 部署验证看运行中的目标是否加载了预期版本；源码更新、部署副本和运行状态分别核对。
- 「全仓搜一遍」这类一次性的检查，用命令做完、结果写进 PR 说明就行，不写成手抄清单的永久测试；要长期钉住的，见 REVIEW-RULES 第一节「同类一起扫」。
- 外部工具的输出格式（比如各家 CLI 的 stream-json），测试样本从真实输出里截一段，不凭文档手写。
- 注释只写现在为什么这样，也就是这段代码防的是哪种真出过的问题；日期、第几轮评审、谁实测过，写进 PR 说明和提交说明。

## 本机设置与数据

本机设置位于 `~/.config/aiwork/`，包含 `models.env`、GitHub App 角色配置及私钥。
本机数据目录入口见 README「本机设置」，里面有哪些东西见 aiwork 仓库 bin/_aiwork_config.py 的登记表。
统一入口是 `bin/aiwork-config`；评审运行目录见 README「评审运行目录」。

可用通道包括 Codex、Cursor、DeepSeek、Kimi、MiMo。每个通道都能写代码也能评审；同一个 PR 的评审要换一家，由关卡判断。默认模型读取本机设置。
`review-pr` 的运行前提包括 node（CI 选择器使用），以及所选腿的程序路径和 Python 版本；配置与预检方法见 README「本机设置」。
正式评审入口是 `review-pr`。要多家评审就并行跑几次 `review-pr`。

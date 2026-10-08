# Agent Instructions

本文件是 aiwork 源码 `workflow/CLAUDE.md` 的部署副本。工具位于源码的 `bin/`，可加入 PATH。
工作流 skill 的源码位于 `workflow/skills/`；`bin/sync-workflow-docs --check` 检查部署漂移。

## 规则入口

评审与修复规则：[aiwork main 的 REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)。
项目已接受风险见项目 main 的 `.aiwork/accepted-risks.md`；正式评审与合并条件见项目关卡策略。
需要判断时读取这些来源，说明文件只提供入口。

## 一个任务的走法

所有项目都不得放任何密钥和私人信息。密钥只保存在项目外的本机设置目录（aiwork 使用 `~/.config/aiwork/`），项目通过统一入口读取。推送前由 `privacy-check` 兜底，不许用 `--no-verify` 绕过；误报就改本机私人词表或测试夹具。

1. 从最新 main 拉分支。开工先在本机数据目录建自己的工作树，在里面拉分支干活，不在共享检出（如 /root/aiwork）里直接改。路径用 `aiwork-config data-path worktrees` 取，和 delegate-codex 是同一个位置。PR 合并后删掉这个工作树。
2. 先写能够在旧实现上失败的测试，再实现。
3. 全跑项目 `tests/`，核对结果及已明确允许的例外。
4. 用机器人提交和推送，以机器人身份开 PR，然后停下。
5. PR 开好后，由主评审和 `review-pr` 派出的另一家族评审腿完成正式评审。
   `review-pr` 必须在沙箱外运行；使用目标仓库当前 PR head 和 main 的规则来源。
6. 修改时读取 `REVIEW-RULES.md`，按一轮修完、推一次的约定处理。
   合并由项目关卡或业主完成。

## 做事的方法

- 判据红了，先用具体输入复现，确认是实现问题还是测试题面的问题；不改考卷让自己及格。
- 自己写的判据也可能错；检查它能否区分正确和错误行为，必要时对旧实现或基线做对照。
- 收货不信执行腿的自述：看真实 diff 和未跟踪文件，自己跑检查，再读实际改动。
- 委托只给清晰的任务、文件范围和验证命令；判据留给主 agent，详见 `delegate` skill。
- 部署验证看运行中的目标是否加载了预期版本；源码更新、部署副本和运行状态分别核对。

## 本机设置与数据

本机设置位于 `~/.config/aiwork/`，包含 `models.env`、GitHub App 角色配置及私钥。
本机运行数据位于 `~/.local/share/aiwork/`，包含 tasks、logs、worktrees、运行期 home 和 archive。
统一入口是 `bin/aiwork-config`；凭证、配置备份、会话及原始日志留在本机。

可用通道包括 Codex、Cursor、DeepSeek、Kimi、MiMo。每个通道都能写代码也能评审；同一个 PR 的评审要换一家，由关卡判断。默认模型读取本机设置。
正式评审入口是 `review-pr`；实现委托见 `delegate` skill。要多家评审就并行跑几次 `review-pr`。

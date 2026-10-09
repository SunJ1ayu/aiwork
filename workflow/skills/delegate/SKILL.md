---
name: delegate
description: 派 PR 任务的任务单、有界实现委托、delegate-codex 副本隔离与收货用法。
---

# delegate — 实现委托与收货

评审与修复规则见 [REVIEW-RULES.md](https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md)，项目已接受风险见项目 main 的
`.aiwork/accepted-risks.md`，正式评审与合并条件见项目关卡策略。
任务的 PR 走法见 `workflow/CLAUDE.md`；这里提供委托工具的用法。

## 准备任务

主 agent 负责明确目标、编写测试和核实结果。任务给出允许修改的文件或窄模块、
输入输出行为、验证命令，并说明判据文件由主 agent 管理。
先确认测试在旧实现上会失败；执行方看到的是已提交的测试基线。
判据红了先复现，不删除断言、写死期望值或加 skip 让自己及格。
收货时不信执行腿的自述，查看真实改动并自己验证。

小且明确的编辑直接做。有界的小修可用 `submimo fix`；清晰的实现任务可用 `delegate-codex`。
大改动方向未定时可先做小实验。

## PR 任务单

把一整个 PR 任务派给另一个 agent 时用这个格式。对方按 `workflow/CLAUDE.md`「一个任务的走法」自己写测试、开 PR；上面「准备任务」讲的是主 agent 自己握着判据的有界委托。
对方可能断线或换了一个，没有之前的上下文，所以任务单要自己就能看懂；一次只派一个。

开头一段写：哪个仓库；从最新 main 拉新分支，还是接着改哪个 PR 的哪个分支；在对方自己的工作树里改。修评审时写明第几轮、评审在哪里看。

- 【目标】现在是什么样、哪里不对。只写问题，不写改法。
- 【已定的决定】已经定下、对方不用再选的：改在哪一处，哪些要删。几处都要做的事，写明放在哪一处、各处调用。只定行为和位置，不定代码形状：「现有测试原样通过」这类要求会逼对方多包一层（PR #22）。
- 【完成标准】要补哪些测试（先在当前代码上红）；全跑测试，CI 绿后推到哪个分支；跑哪几家评审；然后停下，把结果告诉业主。
- 【不做什么】这次不动的，比如评审里不拦的 P2、P3，关卡，历史注释。
- 【前提不成立时】哪种情况说明任务单的前提错了；遇到时停下来说明，不要另写一套绕过去。

## delegate-codex

```bash
delegate-codex --print-oracle-hash --repo REPO --protect tests/ >> ATTACK_LOG
delegate-codex --task TASK --repo REPO --attack-log ATTACK_LOG \
  --protect tests/ --log LOG
delegate-codex --receive RECEIPT.json
```

`TASK` 写明文件范围和检查方式；`--protect` 可重复，
包括测试、fixture 和期望输出等判据实际读取的文件。
`ATTACK_LOG` 放在仓库之外，记录对题面和测试的检查；用 `--print-oracle-hash` 写入当前判据哈希。
改过判据后重新检查哈希。工具在缺任务、记录、保护清单或哈希不符时拒绝派发。

默认从派发时的 HEAD 建独立 worktree 和执行分支，保存基线与保护清单到仓外回执。
目录默认在本机数据目录 `worktrees/`，`DELEGATE_WORKTREE_ROOT` 可覆盖。
`--no-isolate` 是在当前工作树执行的显式选择；`--dry-run` 只显示派发计划。
模型由 `~/.config/aiwork/models.env` 的 codex 行选择，`--model` 覆盖本次调用。
其他参数见 `delegate-codex --help`。

副本隔离便于归因，不是文件读取或凭证隔离的完整安全边界。
linked worktree 的 `.git` 指向共同仓；日志、回执及题面检查记录放在源仓和执行树之外。
执行任务限制文件范围、工具和网络出口，保持生产系统与密钥操作由授权入口执行。

## 收货

1. 用 `--receive` 比较派发基线和保护清单，并查看主树与执行树里的未提交及新增文件。
2. 自己跑测试与相关检查，再亲读 diff；留意 symlink 是否替代了真实目录。
3. 集成到目标分支后验证组合结果；不要只复用执行副本里的结果。

回执中的进程退出码、执行写集、收货结果分别核对。缺用量信息就是未知，不补造数字。
入口打印集成及清理建议，不自动合并或删除执行树；清理前确认成果和唯一未提交副本。

## submimo fix

```bash
submimo fix TASK LOG REPO --oracle 'TEST_COMMAND' --protect tests/
```

该工具运行有界实现循环，每次尝试后执行给定检查并保存 diff；次数和退出码见 `submimo --help`。
`--protect` 防止判据被执行方修改；`--no-oracle` 是不提供验证命令的显式选项。
主 agent 核查每次真实改动，不把退出码或模型自述当作收货结论。

## 红检与记录

```bash
redcheck --base BASE --impl IMPLEMENTATION --oracle 'TEST_COMMAND' --must-fail MARKER
```

`redcheck` 暂退实现到基线、运行检查并恢复，帮助确认判据能抓住目标行为。
先看失败是不是目标问题，再读恢复状态；测试本身可能错，需要用具体证据核实。
任务、自审、原始日志及回执留在 `~/.local/share/aiwork/`；配置与模型选择在 `~/.config/aiwork/`。

收货后实现仍通过机器人 PR 提交，正式评审使用沙箱外的 `review-pr`。

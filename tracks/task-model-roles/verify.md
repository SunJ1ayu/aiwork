# Verify: task-model-roles

实现由 Codex 完成，云 Claude 首轮审核已完成；文档修复后待复审，不归档为通过。

## Mechanical checks

由 runlog 记录，收据追加于下方。

## Review

第一性检查和已有独立方案挑战见 design.md。云 Claude 首轮代码审核与文档返工见下方；不把 explore 算作 PASS。

## 尚待验收

真实 App 安装范围、共享 build 身份模型来源、云平台接入和宿主隔离均未通过。

## 失败用例（实现前）

```
runlog: repo-oracle-red rc=1 commit=7ceea98 dirty=yes at=2026-10-03T06:47:44Z file=tracks/task-model-roles/evidence/20261003T064744Z-01-repo-oracle-red.txt
runlog: repo-oracle-red-clone rc=1 commit=7ceea98 dirty=yes at=2026-10-03T06:49:12Z file=tracks/task-model-roles/evidence/20261003T064912Z-01-repo-oracle-red-clone.txt
runlog: token-oracle-red rc=1 commit=7ceea98 dirty=yes at=2026-10-03T06:49:12Z file=tracks/task-model-roles/evidence/20261003T064912Z-02-token-oracle-red.txt
```

首次附加 worktree 的收据观测写入失败：现有控制器刻意将附加树的 track 路由回主仓库。已转为独立 clone，保留原收据，并重跑同一失败测试；后续观测正常写入本交付。没有为此修改控制器。

## 实现阶段回归结果（首轮代码审核前）

```
runlog: repo-green rc=0 commit=4733be9 dirty=yes at=2026-10-03T06:52:53Z file=tracks/task-model-roles/evidence/20261003T065253Z-01-repo-green.txt
runlog: token-green rc=0 commit=4733be9 dirty=yes at=2026-10-03T06:52:54Z file=tracks/task-model-roles/evidence/20261003T065254Z-01-token-green.txt
runlog: tooling-coverage rc=0 commit=c891116 dirty=yes at=2026-10-03T07:05:49Z file=tracks/task-model-roles/evidence/20261003T070549Z-01-tooling-coverage.txt
runlog: contract-regression rc=0 commit=c891116 dirty=yes at=2026-10-03T07:08:02Z file=tracks/task-model-roles/evidence/20261003T070802Z-01-contract-regression.txt
runlog: repo-final-green rc=0 commit=c891116 dirty=yes at=2026-10-03T07:24:44Z file=tracks/task-model-roles/evidence/20261003T072444Z-01-repo-final-green.txt
```

OpenDesign 完整关卡套件：78 通过、0 失败、0 跳过；原始输出在 `/root/aiwork-plans/role-audit-20261003/task-roles-gate-all-loopback-green.tap`。最初一项 git 子进程被外层沙箱拒绝；宿主断网重跑时整机假 API 的 loopback 未启用导致 7 项失败；随后仅在独立命名空间启用 loopback，原测试全部通过，未改测试或生产实现来避开失败。

新增 test suite 已登记到防锈入口，coverage-only 无孤儿套件；总跑有既有运维工具未列入判卷名单的提示，与本次变化无关。本次未宣称运行整个工具链总套件。

源码自查记录保存在仓库外，不喂给云 Claude 当评审输入。实现阶段当时没有外部代码审核结论，未写最终 PASS。正式启用时 review-pr 与 gh-app-token 必须一起升级；目标 main 的规范和 App 安装未补齐时仍拒绝运行。

## 云 Claude 首轮审核与文档修复（2026-10-03）

审核：[aiwork PR #5 的固定 HEAD 97f61b8 首轮意见](https://github.com/SunJ1ayu/aiwork/pull/5#pullrequestreview-5401397089)。代码部分通过，最终结论为 BLOCK：迁移计划 G6 将尚未合入 OpenDesign main 的作者家族排除写成已生效行为。

- 修前：G6 没有生效条件；OpenDesign main 仍排除全部 Builder 家族。
- 修后：G6 明确待 OpenDesign 关卡 PR 合并后生效，并保留此前的排除口径。计划顶部的本轮状态移到 proposal.md；审核任务书与发布 URL 统一使用目标仓库；阶段 C 删除重复的加 recheck 标签步骤，沿用计划中既有的 aiwork-review-ping 说明。
- 根因与修法：把提议的关卡行为和当前已部署行为混在一起；用明确的合并条件及 track 状态分开两者，未修改生产代码或另定义审核规则。
- 核查：逐项核对上述文档措辞、同类硬编码目标扫描、git diff --check；原 125 项离线检查属于前一固定代码树，本轮仅改文档，没有重复运行代码套件或冒称新 HEAD 已独立审核通过。

OpenDesign 的 `codex/task-model-roles` 分支已发布，固定审核 HEAD 为 `7963981e6b553671442805070644c61fb661d073`，完整树与本地实现一致。已有草稿 [PR #21](https://github.com/SunJ1ayu/OpenDesign/pull/21)，本轮不重复开 PR。它改动判卷面，按 high 走两家独立技术审核及业主批准；这里不代替技术结论或批准。正式验收仍待两边独立审核、相关 PR 合并和上述来源/隔离前提。

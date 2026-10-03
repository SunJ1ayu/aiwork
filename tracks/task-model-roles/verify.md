# Verify: task-model-roles

实现由 Codex 完成，代码审核留给云 Claude；当前尚未审核，不归档为通过。

## Mechanical checks

由 runlog 记录，收据追加于下方。

## Review

第一性检查和已有独立方案挑战见 design.md。代码审核未派发；不把 explore 算作 PASS。

## 尚待验收

真实 App 安装范围、共享 build 身份模型来源、云平台接入和宿主隔离均未通过。

## 失败用例（实现前）

```
runlog: repo-oracle-red rc=1 commit=7ceea98 dirty=yes at=2026-10-03T06:47:44Z file=tracks/task-model-roles/evidence/20261003T064744Z-01-repo-oracle-red.txt
runlog: repo-oracle-red-clone rc=1 commit=7ceea98 dirty=yes at=2026-10-03T06:49:12Z file=tracks/task-model-roles/evidence/20261003T064912Z-01-repo-oracle-red-clone.txt
runlog: token-oracle-red rc=1 commit=7ceea98 dirty=yes at=2026-10-03T06:49:12Z file=tracks/task-model-roles/evidence/20261003T064912Z-02-token-oracle-red.txt
```

首次附加 worktree 的收据观测写入失败：现有控制器刻意将附加树的 track 路由回主仓库。已转为独立 clone，保留原收据，并重跑同一失败测试；后续观测正常写入本交付。没有为此修改控制器。

## 回归结果（代码审核仍未派发）

```
runlog: repo-green rc=0 commit=4733be9 dirty=yes at=2026-10-03T06:52:53Z file=tracks/task-model-roles/evidence/20261003T065253Z-01-repo-green.txt
runlog: token-green rc=0 commit=4733be9 dirty=yes at=2026-10-03T06:52:54Z file=tracks/task-model-roles/evidence/20261003T065254Z-01-token-green.txt
runlog: tooling-coverage rc=0 commit=c891116 dirty=yes at=2026-10-03T07:05:49Z file=tracks/task-model-roles/evidence/20261003T070549Z-01-tooling-coverage.txt
runlog: contract-regression rc=0 commit=c891116 dirty=yes at=2026-10-03T07:08:02Z file=tracks/task-model-roles/evidence/20261003T070802Z-01-contract-regression.txt
runlog: repo-final-green rc=0 commit=c891116 dirty=yes at=2026-10-03T07:24:44Z file=tracks/task-model-roles/evidence/20261003T072444Z-01-repo-final-green.txt
```

OpenDesign 完整关卡套件：78 通过、0 失败、0 跳过；原始输出在 `/root/aiwork-plans/role-audit-20261003/task-roles-gate-all-loopback-green.tap`。最初一项 git 子进程被外层沙箱拒绝；宿主断网重跑时整机假 API 的 loopback 未启用导致 7 项失败；随后仅在独立命名空间启用 loopback，原测试全部通过，未改测试或生产实现来避开失败。

新增 test suite 已登记到防锈入口，coverage-only 无孤儿套件；总跑有既有运维工具未列入判卷名单的提示，与本次变化无关。本次未宣称运行整个工具链总套件。

源码自查记录保存在仓库外，不喂给云 Claude 当评审输入。没有任何外部代码审核结论，不写最终 PASS。正式启用时 review-pr 与 gh-app-token 必须一起升级；目标 main 的规范和 App 安装未补齐时仍拒绝运行。

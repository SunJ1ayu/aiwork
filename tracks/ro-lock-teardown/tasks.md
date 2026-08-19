# Tasks: ro-lock-teardown

- base-ref: 147412e(接管并重写规格时的 HEAD)
- 顺序不可换:**规格对抗 → oracle 红检 → helper → wrappers/能力 → 回归/四审**。

## S0 规格收敛

- [x] S0a 主 agent 独立重审旧 track，确认旧 O1 不完整、目标与 non-goals 冲突
- [x] S0b 写下主方向:每腿独立可写副本 + 原仓物理只读
- [ ] S0c 用不含主答案的 brief 跑 `panel-explore`
- [ ] S0d 主 agent 仲裁并把采纳/驳回依据写回 design

## S1 判据先行(单独 commit)

- [ ] S1a O1:副本包含 committed/modified/staged/deleted/untracked，排除 ignored，Git 元数据独立
- [ ] S1b O2:假腿写副本成功、写原仓失败，源仓内容/status/refs 不变
- [ ] S1c O3:两条并行假腿路径不同且互不可见
- [ ] S1d O4:三底座允许非 git 本地命令，Write/Edit/Task 仍关闭
- [ ] S1e O5:helper/挂载失败时模型调用计数为 0
- [ ] S1f 保存红收据；oracle commit 不含实现

## S2 独立 review workspace

- [ ] S2a 新增共享 helper:仓外安全建目录、shared clone、明确 HEAD checkout
- [ ] S2b 同步 tracked + untracked non-ignored 当前文件视图，处理 tracked deletion
- [ ] S2c gitlink/submodule 首版 fail-closed
- [ ] S2d cleanup 只接受 helper 自己创建且位于受控根下的路径
- [ ] S2e O1/O3 转绿 + 两个变异红检

## S3 wrapper 接入与执行能力

- [ ] S3a `submimo review`:模型 cwd/--dir 指向副本，`fix`/`explore` 语义不变
- [ ] S3b `subagent review`:OpenCode 与 Claude 两支共用同一个副本接入点
- [ ] S3c `subkimi review`:副本接入，guard 放行本地 Bash
- [ ] S3d 外层 `ro-repo-exec` 保护 SOURCE_REPO/common dir，不挂只读副本
- [ ] S3e 三底座放开本地 Bash，保留 Write/Edit/Task deny，并更新提示词边界
- [ ] S3f O2/O4/O5 转绿；变异“直接在 source 跑”必须红

## S4 收判据与回归

- [ ] S4a 逐条调整 V35/V36 等旧语义，不按编号/差值批量删除
- [ ] S4b 保留 `ro-repo-exec` unit coverage 与 V37/V38/V41
- [ ] S4c `tests/test-review-tooling.sh` 全量绿，最终收据在最后一次编辑之后
- [ ] S4d 三条 agent wrapper 各真跑一次 review，确认有裁决且原仓未变

## S5 收口

- [ ] S5a 主 agent 自审先落 `tasks/ro-lock-teardown-review-my-review.md`
- [ ] S5b `panel-review` full 四腿，花名册原样落 verify
- [ ] S5c 仲裁 → 必要返工 → 最后一次全量回归/收据
- [ ] S5d verify 填真实 verdict、接受偏差和资源边界
- [ ] S5e 归档

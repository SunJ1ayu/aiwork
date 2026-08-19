# Proposal: ro-lock-teardown

- Date: 2026-08-19
- Status: open

## Goal

把评审腿从“真实仓库只读”改成“**独立副本可写、真实仓库只读**”:

1. 每条 agent 评审腿各拿一份可丢弃的 review workspace，能运行本地判据、编译和诊断；
2. workspace 必须包含当前 HEAD 上的 tracked 内容、工作树修改、删除和未忽略的 untracked 文件；
3. 原仓工作树与 Git common dir 对腿仍物理只读，腿的副作用只能落在自己的副本；
4. 四腿并行时互相看不见对方的临时写入，主 agent 仍只接收文本裁决，不接收副本里的改动。

这不是“保留原锁不动”:锁不再焊住腿的工作现场。它只保护原仓，腿实际工作的副本是可写的。

## Motivation

业主要的是**增加评审腿的执行能力，同时不弄脏主仓**。上一版 track 把它拆成了两件互相
抵消的事:

- 本单只删原仓只读挂载；
- “给其他腿加执行能力”和“工作树隔离”却都列为 non-goal。

照那版做完，腿仍只有只读 git 白名单，执行能力一条没增加；与此同时唯一的物理写保护被删掉。
这是净退化，不是过渡方案。

上一版还把 `git diff --output` 当成白名单唯一要堵的洞。断线前的真探针已经证明:
`git log --output` 与 `git show --output` 同样能写；仓内既有注释还记录了 `--ext-diff`、
`--no-index` 等口子。**对 git 的参数做黑名单不是完整隔离边界**，所以本单不再把它当替代锁。

## 第一性不变量

- **能力落在副本**:评审腿运行本地命令造成的写必须成功，但只在自己的 workspace 成功。
- **原仓不承受副作用**:包括工作树、`.git`、linked-worktree common dir、ignored 文件。
- **评审视图不丢内容**:tracked 修改/删除、staged 内容和未忽略的 untracked 文件都要进入副本。
- **四腿不串味**:每腿独立副本，A 的临时写不能被 B 读到。
- **失败响亮**:副本建不出来或原仓保护挂不上就拒跑，不回退到直接在原仓执行。
- **不伪装成强敌沙箱**:本单防误伤和仓内提示注入导致的原仓污染；不声称能约束有动机的 root 对手。

## Scope

- in: 新增共享 review-workspace helper，创建/销毁每腿独立临时克隆
- in: 克隆使用独立 Git 元数据；从原仓同步 tracked + 未忽略 untracked 的当前文件系统视图
- in: 三个 agent 包装器(`submimo` / `subkimi` / `subagent`)在 `review` 模式改到副本运行
- in: 现有 `ro-repo-exec` 改为保护**原仓**，不再把腿的副本挂成只读
- in: 放开 review 模式的本地 Bash 执行，让腿能跑测试/构建/诊断；Write/Edit/Task 仍关闭
- in: 更新提示词，明确副本可写但不得 push、安装依赖、访问生产或把临时改动当交付
- in: 判据先行，覆盖视图完整性、原仓不变、每腿隔离、失败不降级和真实命令执行

## Non-goals

- 不把评审腿变成实现腿；副本里的改动不会合并、提交或交付
- 不让腿 push/merge、安装依赖、改密钥、跑迁移或访问生产系统
- 不复制 ignored 运行期目录(`logs/`、`out/`、`.mimocode/`、依赖缓存等)；它们不是待审源码，
  当前 aiwork 仓合计约 1GB，复制会把轻量隔离变成资源事故
- 不复用普通 linked worktree：它既漏主树未提交内容，又共享 Git common dir
- 不改聊天腿；聊天腿没有仓库工具，只继续消费 diff/include
- 不把临时 workspace 当长期证据；可追溯证据仍进 track/evidence 与腿日志

## Success criteria

- agent 腿看到的文件内容等价于派发瞬间的原仓源码视图(HEAD + tracked dirty + untracked non-ignored)
- 腿能在副本创建文件并运行会写生成物的本地判据
- 同一次命令写原仓绝对路径失败，原仓前后内容与 Git 状态不变
- 四条并行腿拿到四个不同路径，任一腿写入后其他腿不可见
- 副本/挂载任一前置失败时 wrapper 非零退出，模型命令没有运行
- 既有 V37/V38/V41 与 `ro-repo-exec` 的 unit coverage 保留，不按断言编号批量删除

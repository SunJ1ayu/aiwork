# Design: codex-worktree-delegation

- Change: codex-worktree-delegation
- Status: draft
- 方案作者: Codex（独立方向 v0，等待 Claude Code 对抗与合并）

> 这是新写面和开放架构分叉，最终 verify 必须走 `full`。
> 后续 Claude Code 应按 proposal 的接手协议先独立落方向，再读本文件。

- 规划双出: **进行中**
  - 第一份:本文件（Codex 方向，2026-08-11 已先落盘）；
  - 第二份:待 Claude Code 写
    `/root/aiwork/logs/codex-worktree-delegation-claude-independent.md`；
  - 合并结果:待写入本文末尾“Claude Code 对抗与合并”。

## 一句话方向

**不要先做 parallel runner；先把 `delegate-codex` 外面包成“一 job 一 worktree”的隔离层，
用同一套工件跑稳串行，再把调度器限制为最多两条、依赖独立的 job。**

并行是这个隔离模型的一个调度选项，不是另一套验收协议。

## 必须保持的不变量

1. **判断权不外包**：plan、oracle、attack、lane、闸②、闸③、集成、最终 verdict 仍由主 agent 做。
2. **oracle 先行**：oracle 先红检并单独 commit；worktree 从包含 oracle 的明确基线创建。
3. **一 job 一现场**：一个 job 只对应一个 worktree、一个基线、一个任务书快照、一个日志目录。
4. **执行腿不碰主工作树**：执行期间主工作树可以有用户自己的脏改动，但这些改动不会被
   静默复制进 job；任务如果依赖它们，必须先由主 agent 明确处理并形成可引用基线。
5. **protect 仍是硬边界**：隔离 worktree 不替代 `--protect` 和收货闸①。
6. **不自动接受范围漂移**：预期写范围之外的合理新文件可以保留现场，但 job 状态必须转为
   `SCOPE_DRIFT`，由主 agent 读后决定，不能静默算成功。
7. **集成永远串行**：候选可以并行生成，进入共同集成分支必须一个一个来。
8. **组合后重判**：单腿全绿只证明它在自己的基线上成立；所有候选组合后必须重跑完整判据。
9. **失败默认保留**：非零、超时、冲突、未知状态都保留 worktree；清理是单独的显式动作。
10. **安全姿态不变**：不新增网络、不装依赖、不让腿 push/merge/归档/迁移/改密钥。

## 分阶段交付

### Phase A：串行隔离（必要路径）

先实现一条 job 也走独立 worktree。目标不是提速，而是证明以下能力：

- 主工作树与执行腿物理隔离；
- diff 能唯一归到一条腿；
- 任务失败后可以保留、重跑、拒收或丢弃，不污染别的任务；
- 跨会话能从 manifest 和 `git worktree list --porcelain` 恢复；
- 现有 `delegate-codex` 的 attack/protect/receipt 逻辑原样复用。

Phase A 没有连续真实样本之前，不实现并行开关。

### Phase B：工件和恢复

在串行隔离之上补齐唯一 job id、状态机、预期写范围、候选 commit/patch hash、明确清理条件，
并让任何中断都能从磁盘重建，而不是相信上一轮聊天记录。

### Phase C：有界并行（可选加速器）

只有测量证明执行等待是显著瓶颈，并且 Phase A/B 的误归因和现场丢失为零，才开放：

- 默认并发 2，第一版硬上限也是 2；
- 只接受同一基线、无依赖边、声明写范围不相交的 job；
- 各 job 独立收货；主 agent 读完后串行生成候选 commit；
- 在一个干净集成 worktree 上按确定顺序逐个集成；
- 任意文本冲突或语义冲突信号出现即停止，不自动让第三条腿“解决冲突”。

如果收益账不成立，Phase C 可以永远不上线；Phase A/B 仍然是有效改进。

## 建议的工具边界

### 保留 `delegate-codex` 为低层原语

优先**不重写**现有 `/root/aiwork/bin/delegate-codex`。它已经承担：

- attack-log 前置检查；
- protect 清单和 `.gitignore` 防绕过；
- 任务书三件套注入；
- 派活时 HEAD 回执；
- 收货闸①及完整改动文件底账。

新工具暂名 `delegate-codex-job`，只负责生命周期和隔离，然后把 worktree 路径、显式日志路径
传给低层入口。这样能把新风险限制在“工作树编排”，不同时重写已经过审的判卷防线。

候选接口（名字和参数等待 Claude Code 对抗，不是最终 API）：

```text
delegate-codex-job prepare \
  --repo REPO --task TASK --attack-log ATTACK \
  --protect PATH... --expect-write PATH... --model gpt-5.5

delegate-codex-job run JOB_ID
delegate-codex-job receive JOB_ID
delegate-codex-job status JOB_ID
delegate-codex-job integrate JOB_ID --into INTEGRATION_WORKTREE
delegate-codex-job cleanup JOB_ID

# Phase C 才出现
delegate-codex-job batch --jobs JOB_ID,JOB_ID --max-parallel 2
```

`prepare` 与 `run` 分开是刻意的：主 agent 可以先检查 manifest、路径、基线和范围，再花额度。
`integrate` 与 `cleanup` 也必须分开：接受候选不等于可以删除唯一现场。

## Job identity 与控制面

### Job ID

不能继续依赖“任务名 + 秒级时间戳”。建议：

```text
<UTC年月日时分秒>-<短随机串>-<任务slug>
```

随机部分由系统安全随机源生成；创建 job 目录必须使用原子 `mkdir`，碰撞就重试，不能覆盖。

### Manifest

每个 job 至少记录：

```json
{
  "schema_version": 1,
  "job_id": "...",
  "state": "PREPARED",
  "source_repo": "realpath",
  "base_commit": "full sha",
  "worktree": "realpath",
  "branch": "refs/heads/delegate/...",
  "task_path": "...",
  "task_sha256": "...",
  "attack_log_path": "...",
  "attack_log_sha256": "...",
  "protect": ["..."],
  "expect_write": ["..."],
  "model": "gpt-5.5",
  "delegate_receipt": "...",
  "codex_rc": null,
  "candidate_commit": null,
  "candidate_diff_sha256": null,
  "created_at": "...",
  "updated_at": "..."
}
```

manifest 是**控制面证据，不放进被派 worktree**。建议运行态放在：

```text
/root/aiwork/logs/delegate-jobs/<job-id>/
```

这里默认不入 git，避免每次派活污染工具仓；最终需要长期留存的机器收据，由主 agent 在验收后
引用进对应 track 的 `evidence/`。准确目录仍需专门验证两种情况：普通外部仓、目标恰好是
`/root/aiwork` 本身。判定标准不是“看起来在仓外”，而是执行腿的 workspace-write 根不能
覆盖控制面目录，且低层入口的仓外检查能通过。

### 锁的粒度

- 用一个很短的 registry 锁保护 job id 分配、manifest 原子更新和 worktree 登记；
- **不能**用全局锁包住整个 Codex 运行，否则名义上支持并行、实际上仍串行；
- 每个 job 有自己的锁，防同一 job 被重复 `run/receive/cleanup`；
- 每个目标仓有 integration 锁，只保护串行集成，不阻止候选并行生成。

manifest 更新采用“写临时文件 → fsync/rename”一类原子替换，避免进程死在半个 JSON。

## Worktree 模型

### 创建

- 从显式 `base_commit` 创建，不从“现在分支大概在哪”创建；
- 基线必须包含已经单独 commit 的 oracle；
- main 工作树的未提交内容不自动带入。发现任务依赖脏改动时拒绝 prepare，并让主 agent 决定；
- 每个 job 使用独立分支或 detached worktree。当前倾向**独立短命分支**，因为候选提交和
  崩溃恢复更直观；但分支清理必须保守。

worktree 根目录需满足：路径可验证、不会与目标仓混淆、不会被执行腿越界写控制面。
可评估 `/root/aiwork/worktrees/codex/<repo-id>/<job-id>`，但目标仓就是 aiwork 时的嵌套语义
必须做真实 oracle，不能凭印象拍板。

### 执行

外层工具对低层入口显式传：

- `--repo <job-worktree>`；
- `--log <job-control-dir>/codex.log`，从结构上消灭默认日志碰撞；
- 原始 `--task / --attack-log / --protect / --model`；
- 不增加 `--add-dir`，不扩大 Codex 可写根；
- 不开启网络。

任务书与 attack-log 建议在 prepare 时记录 hash；如果 run 前输入变化，拒绝启动而不是悄悄
换题。oracle/protect 内容也应记录内容 hash，优先替代当前 attack 新鲜度只看 mtime 的弱点。

### 收货

先在 job worktree 上调用现有 `delegate-codex --receive`。然后外层增加两项归因检查：

1. 实际改动路径与 `expect_write` 对账；超出范围进入 `SCOPE_DRIFT`，保留现场；
2. 对完整候选 diff 计算 hash，并把实际改动清单写进 job manifest/receipt。

`expect_write` 不应直接删除“合理但没预见的新文件”。它的作用是让偏离**不能静默**，
最终仍由主 agent 亲读。Phase C 的 batch 预检则必须拒绝声明写范围相交，因为那是调度资格。

## 状态机

建议状态（Claude Code 应专门攻击是否过度设计）：

```text
PREPARED → RUNNING → RETURNED → RECEIVED → VERIFIED → CANDIDATE
    │          │          │          │          │
    └──────────┴──────────┴──────────┴──────────┴→ FAILED / BLOCKED / SCOPE_DRIFT

CANDIDATE → INTEGRATED → FINAL_VERIFIED → CLEANABLE → CLEANED
                         └──────────────→ INTEGRATION_BLOCKED
```

关键语义：

- `RETURNED` 只代表 Codex 进程结束，不代表正确；
- `RECEIVED` 只代表闸①和底账形成，不代表闸②/闸③通过；
- `VERIFIED` 必须由主 agent 亲跑、亲读之后显式写入；不能从 Codex rc=0 自动推导；
- `CANDIDATE` 是主 agent 在独立 worktree 内形成的候选 commit，不是 merge；
- `INTEGRATED` 后仍不能宣布完成，必须有 `FINAL_VERIFIED`；
- 未到 `CLEANABLE` 默认拒绝清理。拒收任务也要由主 agent明确标记为可丢弃。

是否真的需要这么多持久状态，应由实现 oracle 倒推；可以在不丢语义的前提下合并状态，
但不能把 `进程成功 / 单腿验收 / 已集成 / 集成后全绿`压成同一个“done”。

## 并行资格

第一版只有同时满足以下条件才允许两 job 并行：

- 同一个明确 base commit；
- 任务之间没有先后依赖；
- `expect_write` 无路径或 glob 交集；
- protect 文件已在共同基线，且两腿都无权修改；
- 不共享会产生写副作用的数据库、端口、缓存目录、生成目录或外部服务；
- 不需要一条腿读取另一条腿新产生的 API/类型/迁移；
- 主 agent 能为每条腿写出独立成功标准；
- 当前额度和本机资源允许。额度检查如果没有稳定机器接口，就明确保留为人工 preflight，
  不伪造一个“自动检查已完成”。

初版建议把以下形状排除在并行试点之外：同一核心文件、schema/migration、auth/权限/钱、
共享锁文件、同一生成物、需要真实服务状态的 E2E。以后可以用证据逐项放开，不能一开始全开。

即便文件不相交，也可能语义冲突，例如 A 改生产者、B 基于旧契约改消费者。因此“文件不相交”
只是必要条件，不是充分条件；最终由主 agent 在 prepare 前写依赖判断。

## 集成协议

1. 每条腿在自己的基线上分别走闸①、闸②、闸③；
2. 主 agent 在对应 worktree 内把已接受改动形成候选 commit；执行腿不自行 merge；
3. 建立/选择一个干净 integration worktree，记录 integration base；
4. 按 task 清单中的确定顺序逐个 cherry-pick/应用候选；
5. 文本冲突立即停止并标记 `INTEGRATION_BLOCKED`，不自动调用第三条腿解决；
6. 无文本冲突也要检查语义冲突：接口、类型、锁文件、生成物、测试夹具；
7. 全部组合后用 `runlog` 跑完整 oracle、回归和 build；
8. 再走对应 review lane。本单工具自身是新写口和 git 生命周期面，必须 `full`；
9. 主 agent 给最终 verdict；通过后才允许归档和清理。

主分支在任务运行期间可能前进。候选不能假设“创建时 base = 集成时 HEAD”；集成必须明确记录
两者，并把 rebase/cherry-pick 后的树当作一个**新的待验证对象**。

## 清理与恢复

清理是本设计最危险的动作之一，第一版宁可留垃圾也不能丢唯一工作：

- 只接受 manifest 中的精确路径，不接受未解析变量、glob、`~` 或宽目录；
- realpath 必须位于批准的 worktree 根，且 `git worktree list --porcelain` 能匹配；
- 有未跟踪文件、未提交 diff、未集成唯一 commit 或未知状态时默认拒绝；
- 先打印将删除的 worktree、分支和唯一 commits，显式执行 cleanup 才动作；
- 优先 `git worktree remove` 的可检查语义，不在脚本里裸 `rm -rf`；
- 清理失败保留 manifest，不能把 job 标成 CLEANED；
- 进程崩溃后以磁盘 manifest + git worktree 真状态重建，聊天记录只作提示。

## 可观测性与收益账

每个 job 记录机器时间：

- prepare/start/end；
- Codex wall-clock；
- 主 agent 闸②/闸③开始结束；
- 返工轮数；
- 等待集成时间；
- 冲突/范围漂移/失败；
- 集成后验证时间。

并行是否值得看的是：

```text
串行总 wall-clock
vs
并行执行 wall-clock + 主 agent 排队验收 + 集成/冲突/重跑成本
```

不得只报“两个 Codex 同时结束所以快了一倍”。至少用若干真实、可拆分任务记录原始事实，
再决定默认是否开放并行。样本只在各自 `verify.md` 写返工轮数/自身错误，不维护“第 N 单”副账。

## Alternatives considered

### 1. 同一工作树后台启动两个 `delegate-codex`

否决。最省代码，但两份 receipt 都把整个工作树当成自己的交付，归因、稳定输入和失败回收全坏。

### 2. 只要求两腿修改不同文件，不建 worktree

否决。声明不等于物理隔离；执行腿可以合理地新增文件或读取另一腿的半成品，且语义冲突照旧。

### 3. 直接给 `delegate-codex` 加 `--parallel TASK...`

暂缓。会把成熟的低层判卷入口与新调度状态机揉在一起，回归面过大。优先外层包装；
等接口稳定且重复真正成为维护成本，再考虑合并。

### 4. 每条腿用完整 `git clone`

隔离强，但复制成本、凭证/远端配置、对象存储和依赖目录处理更重；本机同仓场景 worktree 更自然。
可作为 worktree 在特定仓库不可靠时的后备，不做默认。

### 5. 让 Codex 自己 spawn sub-agent 并行

否决为工作流主干。那会把任务拆分、实现、内部验收和归并放进同一个黑箱，主 agent 只能收到
一份合并后的自述，违反“窄口子 + 分腿交货 + 主 agent 三道闸”。

### 6. 先优化 panel 或 oracle，不做 worktree

不是互斥项。oracle 质量仍是更高优先级；但串行默认 worktree 本身就提高归因和恢复，不依赖并行收益。
若资源只能做一项，应先做 oracle/隔离，不先做 batch。

## Test strategy (oracle)

主 agent 先写失败测试并单独 commit。用假 Codex、临时 git 仓和短进程，不消费真实额度：

### A. 单任务隔离

1. prepare 从指定 commit 建 worktree，主工作树任何文件都不变；
2. 主工作树有无关脏改动时，job 不会继承；若任务声明依赖脏改动则 fail-loud；
3. 任务、attack、protect 任一输入在 prepare 后变化，run 拒绝；
4. 低层 `delegate-codex` 收到的是 job worktree 和唯一显式日志路径；
5. protect 被改、目录新增未跟踪/ignored 文件、skip-worktree/assume-unchanged 仍被闸①抓住；
6. 实际改动超出 expect-write → `SCOPE_DRIFT`，现场保留；
7. Codex rc=0 只能到 RETURNED，不能自动变 VERIFIED/INTEGRATED。

### B. 并发隔离

8. 同任务同一时刻创建两个 job，job id、目录、日志、receipt 均不碰撞；
9. 两个假 Codex 同时修改相同相对路径，各自 worktree 只看到自己的内容；
10. batch 对声明写范围相交、依赖相连或超过并发 2 的输入在启动前拒绝；
11. 一腿失败不 kill、不覆盖、不清理另一腿；
12. registry 短锁不覆盖运行时长，两腿真实并发；同一 job 重复 run 被 per-job 锁拒绝。

### C. 集成与清理

13. 两候选串行集成；第二个产生文本冲突时停止，第一候选和两个原 worktree 都保留；
14. 文件不相交但组合 oracle 红 → FINAL_VERIFIED 失败，不能 CLEANABLE；
15. main 在运行期间前进时，集成记录新 base 并强制重跑，而不是复用旧绿收据；
16. dirty/untracked/有唯一未集成 commit/路径不在批准根的 cleanup 全部拒绝；
17. 模拟 manifest 写到一半或进程被 kill，status 能从原子文件和 git 真状态恢复；
18. cleanup 成功后 worktree 登记消失，但 job 最终收据仍可读。

### D. 变异测试

至少做以下变异，确认 oracle 真会红：

- 把 job id 随机部分去掉；
- 错把 `source_repo` 传给 Codex 而不是 job worktree；
- 删除 batch 的范围交集检查；
- 让 rc=0 自动标 VERIFIED；
- 集成后跳过最终 oracle；
- cleanup 忽略 untracked 或唯一 commits；
- manifest 原地覆盖而非原子替换。

### E. 真实试点

- 先跑若干**串行隔离**任务，确认错归因/丢现场为零；
- 再选两个天然独立、低风险、写集不交叉的任务做一次并行试点；
- 记录串行估算、并行实耗、主 agent 验收时间、返工和集成时间；
- full review 专门攻击“全绿但用户结果仍错”的路径；
- 未得到正收益证据前，不把并行设为默认。

**这个 oracle 能被什么骗过?**

- 临时仓证明工具隔离，不证明真实项目的依赖、构建缓存和生成物没有共享副作用；真实试点接。
- 文件范围不相交仍可能语义冲突；只有集成后完整 oracle + 主 agent 读代码能接一部分。
- Codex 服务端是否允许/适合并发、并发怎样影响订阅额度和限流，本地假腿问不出来；
  需要小规模真实试点和 `/usage` 前后账，不能凭 CLI 能启动两个进程就宣布支持。
- worktree 防的是写入混合，不自动阻止执行腿读取控制面绝对路径；要靠 workspace 根、任务书边界、
  控制面选址和真实 sandbox 探针验证。
- 自动化只能证明“工具按协议做”，不能证明主 agent 拆对了任务；并行资格最终仍含判断。

## Claude Code 对抗清单

Claude Code 合并方案前至少回答：

1. 隔离层应该扩展 `delegate-codex` 还是新增外层工具？证据是什么？
2. worktree 和控制面目录在“目标仓就是 `/root/aiwork`”时是否真的隔离？
3. manifest 状态机哪些是必要语义，哪些只是仪式？
4. expect-write 应是硬白名单、软漂移告警，还是两级策略？如何处理 rename/glob/symlink？
5. 两腿共享测试端口、缓存、数据库、锁文件和生成目录时如何判定依赖？
6. base 分支前进、oracle 在派活后变化、候选基线不同分别怎么处理？
7. 如何证明 job receipt 没把另一条腿或主 agent 的改动算进来？
8. 崩溃、超时、进程孤儿、半写 manifest、孤儿 worktree 怎么恢复？
9. cleanup 怎样做到保守、可查证且不靠危险的递归删除？
10. 并行收益的停止条件是什么？何时应只保留串行隔离？
11. 当前 Claude/Codex 额度和服务端并发限制有没有稳定机器接口，还是必须人工记账？
12. 哪些失败路径在本 oracle 结构上仍然问不出来？

## Claude Code 对抗与合并

- 独立方向日志:`/root/aiwork/logs/codex-worktree-delegation-claude-independent.md`
  —— 写于 08-11 15:24、**读本文件之前**;那一笔落盘撞上会话断线,15:57 从会话记录逐字节取回,
  没有在读过本文件之后回头润色。**`logs/` 是 gitignore 的**(它今天已经丢过一次),
  入库的那份在 `tracks/codex-worktree-delegation/claude-independent.md`,内容相同。
- 机器收据(runlog 行见 verify.md):
  - `evidence/20260811T085430Z-01-probe-design-assumptions.txt`(确定性探针 P1/P2/P3,
    可重跑:`tracks/codex-worktree-delegation/probe-isolation-assumptions.sh`)
  - `evidence/20260811T085459Z-01-live-gate1-on-real-run.txt`(今天真实派活的现场快照)

**一句话:隔离采纳,并行驳回 —— 但两边的理由都要换。** 隔离的理由不是"为并行铺路",
是**归因**;并行不成立的理由不是"收益小",是**上游供给被 oracle 铁律在结构上堵死**。
另外:**Phase A 按本文现在的写法跑不起来**,有一道闸会 100% 拒发。

### 一、三条机器验证的攻击

#### A1 致命 —— Phase A 的第一步就被自家的闸挡死(收据 P1)

本文「Worktree 模型 · 执行」要求给低层入口传 `--repo <job-worktree>`。但
`delegate-codex:199-215` 那道「攻题记录必须新过判卷」闸是按 **mtime** 判的,而 worktree 是
checkout 出来的 —— **判卷文件的 mtime 恒等于建树那一刻,因此恒新于任何攻题记录**。

实测(同一份判据、同一份攻题记录,只换 `--repo`):派主工作树 `rc=0` 放行,
派刚建的 worktree `rc=2` 拒发,两个 mtime 差 0.19 秒。**这不是偶发,是恒真。**

它只有两条出路,其中一条是自伤:

- 派活前顺手 `touch attack.md` —— 工具头部注释**自己写着**这道闸"弱在能被 `touch` 绕过"。
  于是隔离层会把「例行解除一道判卷防线」变成派活肌肉记忆。这正是本机反复记账的
  **调钝报警器**形状,和弱模型"改考卷让自己及格"是同一个动作,只是理由体面。
- 把新鲜度判据从 mtime 换成**内容哈希**。本文第 189-190 行已经想到了,但把它写成"建议"、
  排进了 Phase B 的工件层。

⇒ **改写:内容哈希是 Phase A 的前置条件,必须排在 worktree 之前落地,不是优化项。**
这条欠账的出处也说明它该还:`delegate-codex:194` 记着内容寻址是 gpt-5.6-sol 当初提的方案,
我当时取了"最便宜的等价物 mtime";隔离层现在把它逼到必须还。

#### A2 目标仓就是 `/root/aiwork` 时,今天根本派不出去(收据 P2)

本文第 152-154 行把这件事列为"需要专门验证的两种情况"。答案不必设计,跑一下就有:
`--repo /root/aiwork` + 默认日志 ⇒ 撞上「卷宗不许落在被派仓里」拒发闸 `exit 2`,
而且错误话术自相矛盾(它说"挪到仓外(默认就在 `/root/aiwork/logs/`)")。

⇒ 控制面选址(`logs/delegate-jobs/`)对**外部仓**成立,**采纳**;对 aiwork 自身必须显式
`--log` 到仓外,并把那句误导提示改掉。附带一条与本单 verify 已有判断一致的结论:
**本 track 自己的实现不能派给 codex 走这个入口** —— 被改的入口正是它的验收边界。

worktree 选址的争议其实不存在:`/root/aiwork/.gitignore:5` 早写着 `worktrees/`,
注释就是"别的仓的 worktree,不能嵌套进来",此刻里面正躺着 design-studio 的一个 worktree。

#### A3 两份方案都没有的那条 —— 闸① 对"派活后主 agent 改判据"零免疫(收据 P3 + 现场快照)

闸① 的基线是**派活时 HEAD**(`delegate-codex:42-44`),这只关掉了"派活**前**我自己的欠账"
那一半。派活**后**我在同一棵树上提交判据修复,`git diff <head> -- tests/` 立刻非空 ⇒
**闸① 判红,而红的是我自己。**

这不是假想,是**今天这单的实况**:note-source 派活基线 `3fe3aba`(15:12),之后
`6b41e58`(15:19)与 `8f2737c`(16:09)两笔判据修复都落在 `tests/`;此刻拿那份真回执跑
`--receive`,闸① ❌,列出的两个文件**一个都不是执行腿写的**。

而且这条路**高频**:15:19 那笔修的正是**执行腿在交付报告里指出来的**判据错(e05f/e05g)。
「腿告诉我考卷错了 ⇒ 我改考卷 ⇒ 闸① 从此对这一单失效」是一条常规路径,不是意外。

后果是本机最怕的形状:**一道会响的报警器变成经常误报的报警器**,而误报的守卫活不过一周。

⇒ 这是隔离的第三条理由,也是最硬的一条:worktree 的 HEAD 停在 base,我在主树修判据不再
污染腿的闸①。同时本文第 79 行说的"完整改动文件底账"要到隔离之后才真的成立 ——
今天那两句(`delegate-codex:112-115`)**不带路径限定、也不减去我自己的改动**。

### 二、Phase C 驳回:上游是干的(这条是拿去攻 Motivation 的)

派出一条腿的前置条件,是一份**已攻题、已红检、已单独 commit 的 oracle**;而 oracle 是铁律里
"主 agent 亲写、绝不外包"的东西 ⇒ **oracle 只能串行产出**。所以"同时存在两份可派的活"这个
状态在当前工作流里一次都没出现过,而且不是巧合,是被铁律在结构上排除的。要让它出现只有两条路:

- **连写两份 oracle 再一起派**:把主 agent 串行段拉长一倍,换执行段并行。
  今天这单的账:**派活前主 agent 段 100 分钟(13:32→15:12),执行腿段 4.5 分钟**;
  08-10 owner-consent 执行段合计 ≈12 分钟,而收货+四审+仲裁从 22:37 拖到次日 09:49;
  执行段占比最高的一单(08-05 anydoc)是 22 分钟执行 + 53 分钟收货。⇒ **净收益为负。**
- **放松 oracle 铁律** ⇒ 直接踩红线,不讨论。

⇒ **Phase C 不进本单,也不另开 track。** 这不是"以后再说":要重开,先得证明**供给约束变了**,
而不是证明调度器写得好。本文把它当成"等收益证据"的可选加速器,这个措辞会让它永远挂在那里
假装是个待办 —— 而它其实是一条被上游堵死的路。

**这也是我对 proposal 的主要攻击**:它把"能不能并行"当工具问题,它其实是工作流的形状问题。

### 三、采纳

1. 一 job 一 worktree、一基线、一日志、一回执(方向一致)。
2. 不重写闸① 那段已过审的判卷逻辑(理由一致);但见「四·1」,包装形态我驳回。
3. **失败默认保留、清理是显式单独动作**。我的补充理由:"忘了删"的代价是占盘,
   "自动删"的代价是丢掉唯一一份改动,**不对称**。反面证据也记上:手工用 worktree 时
   `/root/aiwork/worktrees/mcp-registry` 从 08-03 挂到今天,对应 track 早已归档
   ⇒ 隔离必须自带**打印出来的**回收路径,否则把"混 diff"换成"攒 worktree"。
4. 集成后必须重跑完整判据,worktree 里的绿一律不许复用(08-10 no-egress 那单的教训:
   绿收据之后判卷面又改过、没重跑,是孤腿抓出来的)。
5. `expect_write` **只用来让偏离不能静默,不做硬白名单**(本文自己也这么写)。
6. 主分支会前进,候选不能假设"创建时 base = 集成时 HEAD"。
7. 「文件不相交 ≠ 语义独立」。
8. 集成时**必须查 `create mode 120000`** —— 这条本文没有,补进来:worktree 里建的符号链接被
   merge 带回主仓会**覆盖掉真目录**,本机出过事故,`.gitignore` 带尾斜杠只匹配目录挡不住链接。

### 四、驳回

1. **驳回新增外层工具 `delegate-codex-job`,改为 `delegate-codex --isolate`。**
   本文的理由是"不同时重写已过审的判卷防线"——但 A1 已经证明**低层入口无论如何都得改**
   (mtime→内容哈希就在它里面),"不碰低层"这个收益并不存在。而代价是实打实的:
   本机教条是"补入口有效、补约定无效",**留两个入口 = 旧入口继续可达,而肌肉记忆走的就是旧的**。
   两个月的实证在工具头部注释里:有守卫的字段一次没空过,没守卫的两个月空两次。
2. **驳回 job registry / manifest / 十四态状态机 / per-job 锁 / registry 锁 / integration 锁。**
   并发度为 1 时,状态就是"worktree 在不在",**磁盘本身就是账**;锁没有对手。
   多一个 registry = 多一份会和磁盘对不上的第二账本,本机在"第二份账"上栽过。
   状态机里真正不能压扁的语义只有一条(**进程成功 ≠ 单腿验收 ≠ 已集成 ≠ 集成后全绿**),
   而这条今天靠收货三闸和 verify 模板已经在守,不需要持久化成十四个状态。
   ⇒ **改写:manifest 退化成回执里多三个键** `worktree` / `base` / `actual_write_set`。
3. **驳回新 job id 格式(UTC+随机串+slug)。** 秒级碰撞窗口是真的,但 worktree 目录名天然要求
   唯一 ⇒ 用 `mkdir` 的原子性直接兜住:撞了就 `exit 2` 让我改个名字。不需要随机源 + 登记表。
4. **驳回崩溃恢复状态机。** 崩了 worktree 就留在盘上,`git worktree list --porcelain` 本身
   就是恢复入口 —— 这正是本文自己第 47 行写的,那就不必再造第二个真相源。
5. **驳回 Phase C**(理由见二)。
6. **驳回"先做 worktree 再补哈希"的次序**(理由见 A1)。

### 五、改写后的选定方向(只有 Phase A)

`delegate-codex --isolate`(倾向默认开,`--no-isolate` 显式退出),四件事 + 一条前置:

- **P0(前置)**:攻题新鲜度闸 mtime → **内容哈希**(哈希 protect 清单里每个文件的内容,
  与攻题记录里记录的哈希比对)。没有它,`--isolate` 一次都派不出去。
- **① 建树**:`git worktree add /root/aiwork/worktrees/<job> <base>`,`<job>` 复用现有
  `<任务名>-<秒级时间戳>` 命名,`mkdir` 原子性兜碰撞。
- **② 回执**:多存 `worktree` / `base` / `actual_write_set` 三个键。
- **③ 收货**:闸① 四臂原样跑在 worktree 上;底账那两句(`delegate-codex:112-115`)**限定到
  worktree**,此时它天然只含腿的改动 —— A3 与"底账失真"两个洞一起关上。
- **④ 交回**:收货通过后**打印**集成命令与 `git worktree remove` 命令给主 agent 自己敲,
  **不自动 merge、不自动删**。

判卷面(oracle)由主 agent 亲写,lane = **full**(改的是判卷防线本身:闸①、攻题闸)。
实现**不派给 codex**(理由见 A2)。

### 六、对抗清单 12 条的回答

1. **扩展 `delegate-codex`**,不新增外层工具(四·1;A1 已证明低层必须改)。
2. **真隔离,但今天派不出去** —— 卡在日志路径而非嵌套语义(A2);worktree 选址 `.gitignore` 早已定。
3. 必要语义只有"进程成功 ≠ 单腿验收 ≠ 已集成 ≠ 集成后全绿"一条,其余是仪式(四·2)。
4. **软漂移**:只记录实际写集、只让偏离不能静默;rename/glob/symlink 一律靠闸③亲读 + `120000` 检查。
5. 共享端口/缓存/数据库/生成物 —— **本单不回答**,因为它只在 Phase C 才有意义,而 Phase C 驳回。
6. base 前进 ⇒ 集成时记新 base 并强制重跑;**oracle 在派活后变化 ⇒ 这正是 A3,由隔离解决**。
7. 靠 `git -C <worktree>` 而不是 `git -C <主树>`(五·③),这是唯一能机械证明的办法。
8. 崩溃 ⇒ 盘上 worktree + `git worktree list --porcelain`,不造第二真相源(四·4)。
9. 只打印命令、不自动删;`git worktree remove` 的可检查语义,不裸 `rm -rf`(采纳·3)。
10. 停止条件已经到了:**现在就停在串行隔离**(二)。
11. **没有稳定机器接口**,只能人工 preflight —— 但这条随 Phase C 一起搁置。
12. 结构上问不出来的:①"我拆对了任务没有";②真实项目的构建缓存/生成物共享副作用;
    ③**执行腿有没有往外发东西**(三道闸查的都是"它改了什么",没有一道查"它发了什么",
    所以沙箱网络必须保持关闭 —— 隔离层不许碰这条)。

### 七、仍需用户拍板(三条,我不替他决定)

1. **你问的是"能不能"还是"值不值得"?** 你原话是"是不是没办法并行",问的是**能力**;
   我这整份论证的是**收益**,结论是不值。如果你要的是"以后有这个选项"本身,那是另一件事。
2. **`--isolate` 默认开还是显式开?** 默认开更符合"入口有效"的教条;代价是每次派活多一棵树,
   而且"我改判据"和"腿改实现"分居两棵树,合并时多一步 —— 这一步多大,我没有数据。
3. **本单现在做不做。** 它改的是判卷防线本身,lane=full、oracle 我亲写、实现不外包 ⇒
   成本落在我身上;而它换来的是闸① 不再误报我自己。

### 八、这份对抗可能错在哪(先自证伪)

- **耗时账 n=2,且都是小活。** 即便按执行段最长的一单(22 分钟)算,结论方向不变、幅度会变。
- **A1 的严重性依赖"worktree 是 checkout 出来的"这一点**;若将来改用 `--no-checkout` 或
  硬链接方案,mtime 结论要重测(但内容哈希那条改写不受影响,它更强)。
- **我把"隔离"和"修 A3"绑在一起讲,但 A3 其实有更便宜的解法**:闸① 的基线不用 HEAD,
  改成"派活时 HEAD + 派活后主 agent 提交的判据修复也算进基线"。我认为它更脆(要区分
  "谁提交的"),但**这是一个真的备选,没有被我证伪**,只是被我判为更差。
- **驳回状态机建立在"并发度=1"上**,而并发度=1 又建立在 Phase C 驳回上。这一串若第一环
  被用户推翻(拍板 1),四·2 要重议。


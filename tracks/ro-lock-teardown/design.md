# Design: ro-lock-teardown

- Change: ro-lock-teardown
- Status: selected after independent exploration

- 规划双出:
  - 主 agent 方向:本文件(先落盘、先提交，避免看完 panel 后事后合理化)
  - 独立发散 brief:`tasks/ro-lock-teardown-isolation-explore.md`
  - panel 输出与仲裁:已回填本文第 8 节；MiMo/DeepSeek/Kimi 有效，GLM 无产出

## 0. 旧方案为什么 BLOCK

旧 tasks 的 O1 只问 `git diff --output`，但真探针显示 `git log --output`、
`git show --output` 也能写；代码自己的历史注释还列了 `--ext-diff`。因此“收紧 git 参数
白名单后拆物理锁”没有闭合。

更根本的一条:旧 proposal 说目标是给腿执行能力，却把“加执行能力”和“隔离工作树”同时
排除在本单之外。做完只会少一层保护，不会多一项能力。

## 1. 候选方向与主选择

### A. 原仓直接可写 + 参数白名单/事后 status

拒绝。参数面不完备；最终快照抓不到写后恢复、ignored、Git refs，也无法在四腿并行时归因。

### B. 普通 `git worktree`

拒绝。它不包含原工作树的未提交内容，而且 `.git` 指向主仓 common dir；仓内代码和 Git 状态
仍不是独立现场。现有 V39 已证明 linked worktree 的 commit/tag 会碰主仓。

### C. 完整文件系统副本

语义正确，但 aiwork 当前约 1GB，其中 `logs/` 444MB、`out/` 357MB、运行期 home 约 160MB。
四腿全量复制会制造新的磁盘/耗时风险。

### D. **独立轻量克隆 + 工作视图覆盖 + 原仓只读保护**(主选择)

每条 agent 腿:

1. 在仓外 `mktemp -d` 创建 workspace；
2. `git clone --shared --no-checkout` 建独立 refs/index/config，objects 只读借用原仓；
3. checkout 派发时的明确 HEAD；
4. 把源 index 条目导入 clone-owned 临时 index，再复制一份对源 worktree 做 `add -A -- :/`；
   前者保留 staged 内容，后者得到 tracked dirty/deleted + untracked non-ignored 的 worktree tree；
   连续做两遍，任一 tree id 不同就说明复制窗口里源视图变了，拒绝派发；
5. 为 worktree tree 建临时 commit并 `reset --hard` 物化文件，再把 HEAD 软复位到原 HEAD、安装
   第二遍捕获的 source-index；这样 clone 的 HEAD/index/worktree 分别对应原仓三层，staged-only
   不会被工作树内容覆盖；
6. 腿在副本 cwd 运行；外层 `ro-repo-exec` 挂的是**原仓及其 common dir**，副本不挂只读；
7. wrapper 退出时清理副本。清理失败只告警，不把一份已完成裁决改判为失败。

结果:

```text
真实仓(含 dirty/untracked) ──只读借源──> 每腿独立 clone + 覆盖当前视图
        ↑ 物理写保护                         ↑ 可写、可跑测试、用完即弃
```

## 2. 为什么用 clone，不用 copy 或 linked worktree

- clone 有自己的 `.git`，腿在副本 commit/tag 不会改主仓 refs；
- `--shared` 只通过 alternates 读原仓 objects，不复制对象库；原仓挂成只读后 push/repack 也写不回去；
- 临时 index 的 `git add -A` 只含 tracked + untracked non-ignored，能评当前源码，又不会复制 1GB
  运行产物；clone 还快照源 `.git/info/exclude` 与有效 `core.excludesFile`，避免在 clone 语境把
  源仓已忽略的运行物误收进来；
- 不复制可能含 split-index/fsmonitor 扩展的二进制 index；改为用 `ls-files --stage -z` 把条目
  导入 clone-owned index。这样保留 staged 内容和 staged/unstaged 分类，同时 Git 自己处理删除、
  symlink、文件模式和特殊路径；unmerged index 无法 `write-tree` 时响亮拒跑。

已知边界:首版遇到 gitlink/submodule 明确拒跑，不复制一个指回主仓 `.git/modules` 的半隔离现场。

## 3. 包装器接法

共享 helper 提供三个动作:

- `review_workspace_prepare <source> <leg>`:校验 Git 仓、workspace 根不在 source 内、记录 HEAD、建副本
- `review_workspace_repo`:返回本腿副本绝对路径
- `review_workspace_cleanup`:只清理 helper 自己在受控根下创建的路径

三个 agent wrapper 在所有现有 task/my-review/home 检查之后、真正模型命令之前调用。保留两个路径:

- `SOURCE_REPO`:原调用方给的仓，用于物理保护和最终“不变”判断；
- `REPO_DIR`:改成副本，传给模型 CLI 的 `--dir`/cwd。

`fix` 模式一个字不动；`explore` 仍不使用工具，不为它复制仓。聊天 fallback 不运行仓库工具，
继续读取源仓 diff，不建副本。

## 4. “执行能力”的精确定义

本单增加的是**本地执行/诊断能力**:

- Bash 可运行测试、lint、build、解释器和只读/诊断命令；
- 命令产生的缓存、编译物、临时文件允许写副本；
- Write/Edit/Task/Agent 工具仍关闭，避免把评审角色悄悄改成实现角色；
- 提示词明确禁止 push、merge、装依赖、生产操作、迁移和密钥改动。

放开 Bash 后不再声称命令行白名单是安全边界。真正承重的是原仓物理只读 + 副本可丢弃。
这与 `submimo fix` 一样依赖“腿不是有动机的强敌”前提；本单不伪造网络/主机级强沙箱。

## 5. 失败与清理语义

- clone/checkout/视图同步/原仓挂载任一步失败 ⇒ 模型不启动，wrapper 非零；
- helper 校验删除目标必须位于它创建的 workspace 根下，拒绝空路径、根目录和 source 路径；
- 正常、模型非零、timeout 都执行 cleanup；SIGKILL 可能留孤儿目录，属于可见资源债，不影响原仓；
- workspace 路径只写进运行日志作诊断，不进入归档工件作承重证据。
- `origin` 在物化后删除、`gc.auto=0`；对象读取仍经 alternates 指向只读原仓，refs/index/config
  全在副本。评审窗口内主 agent 不对原仓跑 prune/gc。
- workspace 根的 0700 只挡其他 uid；四腿同 uid。wrapper 不互传路径，足以防正常并发串味，
  但有动机的同 uid/root 腿可扫描其他临时目录，属于“不防强敌”边界。

## 6. Test strategy (oracle，主 agent 所有)

### O1 视图完整

临时仓构造 committed、tracked modified、staged+unstaged、staged-only、deleted、untracked，以及
`.gitignore` / `.git/info/exclude` / `core.excludesFile` 三路 ignored。副本必须:

- HEAD 与源一致；
- worktree 内容/缺失状态一致，clone index 仍能读到 staged-only 内容；
- 三路 ignored 都不出现；
- `.git` 是副本自己的目录，不是指向源仓的 gitfile/common dir。

### O2 写入边界

真 wrapper + 假模型在同一次运行里:

- 往 `REPO_DIR` 创建文件成功；
- 尝试往 `SOURCE_REPO` 创建文件失败；
- 源仓文件 hash、status、HEAD/refs 前后不变；
- 假模型确实运行并给出裁决，排除“根本没启动”的假绿。

### O3 每腿隔离

并行起两条假腿，各自在自己路径写唯一标记；断言路径不同、snapshot tree id 相同、互相看不见、
源仓看不见。复制窗口内改源文件时，两次 tree id 必须不一致并拒跑。

### O4 能力配置

三种底座解析后的配置/argv/guard 都允许一条非 git 本地诊断命令；Write/Edit/Task 仍关闭。

### O5 fail-closed 与变异

- helper 失败或 `ro-repo-exec` 失败时模型调用计数为 0；
- 变异 1:让 wrapper 直接把 source 当 `REPO_DIR`，O2 必须红；
- 变异 2:让两腿复用同一副本，O3 必须红；
- O4 元断言继续钉住 V37/V38/V41，不许清锁判据时误删独立防线。

### 回归与真实冒烟

- `tests/test-review-tooling.sh` 全量；
- 三条 agent wrapper 各真跑一次 review，日志必须有裁决；
- panel full 收口，并检查源仓在 panel 前后除主 agent 明确提交外无变化。

## 7. Trade-offs

- 比“直接删锁”多一个副本 helper，但它同时交付能力与隔离；旧方案只交付风险。
- `--shared` clone 在副本存活期间依赖源 objects；workspace 生命周期只覆盖一次 review，源仓又只读，
  这个依赖可接受。若未来要长期保留现场，必须改成非 shared clone。
- ignored 文件不复制意味着依赖只存在于 ignored 目录的测试可能跑不了；腿应如实报告环境缺件，
  不得在 review 中安装依赖。比复制 1GB 或偷偷装依赖更符合本机约束。
- 隔离只能证明原仓不被污染，不能证明腿没有在副本里“先修再评”。提示词要求裁决引用原始 diff；
  最终 panel 仍是第二意见，主 agent 必须亲读源仓与实现 diff。

## 8. Independent explore / arbitration

### 运行情况

- 第 1 轮:DeepSeek/GLM agent 底座启动失败，chat fallback 又被缺 my-review 闸拦；MiMo 无正文，
  约 7 分钟后主动停止。失败日志保留，不冒充方向。
- 第 2 轮:确认 chat 腿在默认沙箱内 DNS 被拦，停止并按权限流程转沙箱外重跑。
- 第 3 轮(作数):MiMo 与 DeepSeek 各有完整方向；GLM 超过 7 分钟无首字节，主动停止并记无产出。
- Kimi:现有 `panel-explore` 没有 Kimi 分支；用户点名后，用同一 brief 单独补跑一份完整方向。

### 三份有效方向

1. **MiMo:物化源码快照作 lower + 每腿 OverlayFS upper**。
   - 采纳:不能以 live 原仓冒充派发瞬间快照；`.git` 写面必须独立；ignored 产物默认不复制。
   - 驳回:源码只有几 MB 时再叠 OverlayFS 没有实质资源收益，却新增 mount/overlay 兼容与清理面。
2. **DeepSeek(chat):live 原仓只读 lower + 每腿 OverlayFS upper**。
   - 采纳:oracle 必须真改 tracked/refs、真跨腿找标记；四腿跑测试的 CPU/内存账独立存在。
   - 驳回:live lower 不是严格快照，要求主 agent 整个评审窗口冻结源仓；“挂载失败回退只读模式”
     也违反本单 fail-closed，不应静默换能力档。
3. **Kimi(补充):每腿物化源码快照 + shared clone**。
   - 采纳:方向与主选择一致；补充复制前后内容指纹、ignored 读依赖、shared clone 与原仓 gc 的
     生命周期风险，以及“腿在副本先修再评”的流程盲区。
   - 改写:不用 `rsync + cp source index`。首版由 Git 临时 index 生成 snapshot tree，连续两次
     tree id 对账；不复制 source index，因此承诺文件内容一致、不承诺 staged 位分类一致。

### 最终主裁

保留方向 D，但把“显式文件清单覆盖”升级为**Git 原生 snapshot tree 物化**。本机临时探针已证明:
modified、staged 后继续修改、deleted、untracked 均进入副本；ignored 缺席；副本 `.git` 独立；
副本 HEAD 回到源 HEAD；源 status/HEAD 不变。第一次探针曾因 no-checkout clone 的空 index +
缺少 `-- :/` 把全树做成删除，红得对；修正为临时 index `read-tree HEAD` 后才成立。这条失败经验
要进入正式 oracle，不能只留在会话叙述里。

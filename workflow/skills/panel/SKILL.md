---
name: panel
description: 多模型评审/发散的完整协议与工具用法(panel-review 健康池预算评审、panel-explore 发散、各评审腿的后端细节)。当要对一份 diff/设计做第二意见、按 impact-risk 取证、或面对开放架构分叉需要角度扩展时读它。主 agent 永远是唯一仲裁者。
---

# panel — 多模型评审与发散

两个工具,一个收敛一个发散。**都只负责派发,从不做判断——判断永远在主 agent。**

## 先选对工具(这一步错了,后面全白做)

两个 panel 都慢且烧 token,而模型的默认倾向是**收敛**(给个答案/给个裁决)。所以真正的
路由失误很少是"选错了 panel",而是**在本该发散的开放分叉上,默认去做了评审、或者干脆
直接回答**。发散是反直觉的那一档,必须刻意触发。

- **有具体 diff / 存在唯一正确答案**(这段代码对不对、安全不安全、这个说法真不真)
  → **panel-review**(收敛到一个裁决)
- **开放的方案/架构分叉,还没有 diff,几个答案都站得住,风险是钻牛角尖**
  → **panel-explore**(保住分歧;自己的方向必须先写下来)
- **两者都不是**(小、明显、或我已经有代码级验证过的判断)→ **直接做**,不要花 panel。
  panel 是第二意见,**永远不能替代主 agent 自己的第一遍工作**。

## panel-review — 收敛合议

触发条件同 `submimo review`:非平凡改动、安全/权限/auth/钱/订单/数据一致性/迁移/CI 风险、
不熟悉的代码区、实现后的测试缺口分析。

**顺序至关重要:主 agent 先审、独立审,评审员是对这份自审的复核,不是替代。**先审是为了
反锚定和防偷懒——不能躲在评审员的 "PASS" 后面。

### 0. 先跑 oracle,在派发之前
任务若有客观检查(test / lint / typecheck / 复现命令),**先跑、先记结果**,再去读、
更别说信任任何评审裁决。chat 评审员不能执行代码;07-04 有过三家一起给一份没人跑过的
坏 oracle 判 PASS。用 `PANEL_ORACLE_CMD=<cmd>` 传给 runner:它记录 `ORACLE: <cmd> rc=<N>`
+ 一份 `.oracle.log`,红了会喊但**不阻断**——红 oracle 意味着评审员的 PASS 一文不值,
而这个判断仍然是主 agent 的。

### 1. 主 agent 先审并落盘自己的发现
读真 diff/代码,写下 PASS/BLOCK/NEEDS_MORE_INFO + 具体条目,**在读任何评审报告之前**。
**这道闸在工具里是 DEFAULT-ON,不是要你记得加的 flag**:运行 `panel-review --track NAME TASK REPO PREFIX`
会自动找 `/root/aiwork/tasks/<taskname>-my-review.md`,**找不到就拒绝派发**(或它躺在被审
仓库里也拒——那会经 `collect_untracked` 泄漏)。非约定路径用 `--require-my-review PATH`;
`--no-my-review` 只作为清醒的例外(比如根本没有 diff 可自审的任务)。

**硬规矩:my-review 文件必须放在被审仓库之外。** 引擎会把仓库里每个未跟踪文件内联进评审
prompt,仓内自审 = 喂给评审员 = 反锚定作废。
> ⚠️ **审 aiwork 自己时,约定路径必然用不了**:约定路径是 `/root/aiwork/tasks/<name>-my-review.md`,
> 而被审的仓就是 `/root/aiwork` ⇒ 它必然在仓内 ⇒ 闸拒绝派发,**而它给的建议路径正是它拒绝的那个**。
> 这时只能 `--require-my-review /root/panel-my-reviews/<name>-my-review.md`(仓外),
> 正本仍可留在仓里当工件。08-23 在这上面卡过一次;拒绝时 `rc=1`(fail-closed 是对的,
> 别被 `| tail` 吃掉的 0 骗了)。

### 2. 评审员独立审
先分开判断两个轴:`impact-risk` 决定证据预算(self=0、standard=1、high=2)，
`design-uncertainty` 决定是否需要 premise attack / 双出 / `panel-explore`；二者不能互相代替。
`panel-review --track NAME --risk self|standard|high TASK_FILE [REPO_DIR] [LOG_PREFIX]` 默认 high=2，
从健康池轮换不同模型家族。失败、降级、没有裁决、NEEDS_MORE_INFO 或裁决冲突时只追加
一个健康 spare；`--all` 才是显式全审，留给判卷、沙箱、权限边界或二审无法收敛的特殊面。
**`--all` 会无视健康池的冷却**(选腿处显式跳过 healthy 判断)：冷却中的腿照派不误，
所以刚炸过一轮之后仍能立刻全审——代价是明知会失败的腿也会占一份等待时间。
(2026-08-23 读 `bin/panel-review` 选腿段确认;无机械判据守这句,是读代码读来的。)
`--track` 绑定 typed track 时，显式 `--budget` 只能增加证据，不能低于 self/standard/high 的
0/1/2 机械预算；要做无归属实验必须明确 `--no-track`，但无归属事件不能满足 typed track 的
PASS 归档。归档会再核对成功 panel observation 中是否有 0/1/2 个成功的不同外部模型家族腿。
仓里有 typed active track 时，派发前必须显式给 `--track NAME` 或 `--no-track`；前者会在
任何腿启动前校验 decision 已满足 dispatch 且 `impact.level == --risk`。实际腿、回落降级、
总耗时、rc 与真实可得 usage 在全部腿结束后写回主仓 track 的紧凑 observation；prompt 和
完整日志仍在仓外，不复制进 Git。单事件最多 64 KiB、panel 最多记录 4 条实际腿。
每条实际派出的腿各写各的
`<prefix>.<leg>.log`(默认前缀 `/root/aiwork/logs/panel-<task>-<ts>`)。一条腿失败不阻断
其他腿;只有所有实际派出的腿都失败才非零退出。主自审必须在派发前已落盘，DEFAULT-ON
闸会机械检查；不能为了省等待把顺序倒过来。

**断线之后先去看日志,别默认重跑。** 各腿自 2026-08-17 起用 `setsid --wait` 起在
自己的会话里(判据 V25),所以会话被砍时**腿会继续跑完并写完自己的日志**。
> 为什么立这条:08-16 / 08-17 两次断线都砍在四审中途,而每次没有结论的都是 kimi。
> 不是它最脆,是**它尾巴最长**(11~18 分钟),剪刀落下时只有它还在写。

**驱动死了,花名册也还在 —— 别再手工数日志(2026-08-23 起)。**
`<prefix>.plan` 在**派发之前**落盘、`<prefix>.<leg>.state` 由**腿自己在它那个会话里**写,
所以花名册是盘的函数,不依赖驱动活着:

```
panel-roster <日志前缀>        # 事后重建;与驱动自己写的 .roster **归一化后一致**(判据 R5b)
```

> 由来:08-19 驱动死因不明、08-23 我给它套了 `timeout 120`(活儿要十分钟),
> **两次都是整轮零记录**,而四条腿的日志完整躺在盘上。08-23 那次的花名册后来
> 就是用这条命令从盘上重建出来的(track panel-roster-from-disk)。
> 旧办法是手工翻日志重建,一次二十分钟 —— **那条老规矩已作废,别再照着做。**

**但花名册只回答"派了谁、谁跑完了、rc 多少",不回答"它说了什么"。**
`verdict` 按独立结论行严格匹配,匹配不上就印 `UNKNOWN`(宁可让你去开日志,
也不许把"看起来像 PASS"记成 PASS);缺 state 的腿印
`未收尾(无 state:被砍或仍在跑)` —— 盘上的信息区分不了"被砍"和"还在跑",所以它不猜死因。
**这两种都要开日志确认,不许当结论用。**
> ⚠️ **别把"日志不动"读成"腿死了"**(2026-08-23 自伤实录):底座腿(opencode/agent 底座)
> 写完日志头之后可能十几分钟一个字都不写 —— 它的输出到收尾才落盘。我那天看见
> `.log` 停在 460 字节、`.log.err` 0 字节、`.state` 没有、工作副本也不在了,
> **推断出一个"第三种死法"并把它写进了这份文档**;下一轮同样形状时我去 `ps` 查了活体,
> 它正在工作副本里跑判据 —— **就是"仍在跑",原文的二选一没错,我加的第三种才是错的。**
> 判"无 state"之前先 `ps` 看一眼进程还在不在;进程活着,就一个字都别说死因。

**三条护栏(2026-07-21,均有 oracle:tests/test-review-tooling.sh V14/V15)**
- **agent 腿失败自动回落 chat 腿**:失败产出留证在 `<prefix>.<leg>.agent.log(.err)`,
  控制台明说发生了回落(不静默)。
- **`PANEL_INCLUDE="tests/a.py tests/e2e/b.mjs"`**:chat 腿只吃增量 diff,**看不到基线
  commit 里的 oracle**(两家都报过"测试文件不在 diff 里没法评")→ 用它把 oracle 一并喂
  进去,会转成各腿的 `ZHIPU_INCLUDE`/`DEEPSEEK_INCLUDE`。有 chat 腿在跑却没给会出 HINT。
- **反锚定泄漏报警**:仓里存在 `verify.md` / `*my-review*` 时报 `WARNING: anchor leak`。
  **正确节奏是先派发、后写 verify.md**;07-21 就是先 commit 了 verify.md 才补发 chat 腿,
  DeepSeek 直接引用它当证据,那一腿的"独立"作废。报警只提醒不阻断。
  > 🔴 **「派发前把 verify.md 回退掉」挡不住它(2026-08-24 实证)。** 那天我照这条做了 ——
  > 派发前 `git checkout` 把 verify.md 回到 HEAD、自审正本放仓外 —— **两轮仍然都报 leak**。
  > 因为引擎内联的是**整份 diff**:`PANEL_DIFF_BASE..HEAD` 区间里**任何一版** verify.md
  > 都会进 prompt,`git checkout` 只管得住工作树那一份。
  > 想真干净只有两条路:**① 让 verify.md 在整个 diff 区间里都还没被写过**
  > (先派发、后落工件 —— 这才是那句"正确节奏"的完整含义);
  > ② 把 diff base 选在最后一次写 verify.md 之后(**通常不行,会漏掉实现**)。
  > 做不到就**如实记账**:泄漏了什么、影响多大。那比在 verify 里写"已反锚定"强。

### 3. 与自己那份逐条对账
他们是顾问,不是投票人;**主 agent 是唯一仲裁者。** 每条:
- **他们标了、我漏了 → 往死里查**(这是 panel 的主要价值:暴露我的盲点/假阴性)
- **我标了、他们没标 → 依然成立**,他们的沉默不是放行
- **他们标了但错 → 驳回**,用我自己对代码的理解

**每个接受/驳回都必须给依据**(如"已核 `file:line`,属实" / "已查 `file:line`,不成立")。
禁止"看报告都说没问题"——这种偷懒正是本协议要防的。

### 4. 出一个合并裁决
PASS / BLOCK / NEEDS_MORE_INFO + 存活的发现。**绝不能只凭评审员的说法定案,绝不能把他们
的结论取平均,绝不能因为一致 PASS 就降低自己的标准**——共同假阴性正是 panel 抓不到的失败
形态,多加一条腿也堵不上。主 agent 独立的、代码级验证过的判断压过所有腿。

### 5. 单腿回落
某个后端不可用(key 过期等)时只跑一条也行,但要注明是谁跑的。
**主 agent 自己的第一遍审,永远不是可选项。**

## panel-explore — 发散,panel-review 的孪生兄弟

用在**还没有 diff**的开放设计问题上:几个不同模型家族各自独立回答**同一份 brief**,各提
**一个**具体方向(Direction / Core bet / How it works / Best at / Sacrifices / Blind spots
in the brief / Smallest first step)。**故意没有裁决——分歧的铺开本身就是产出。**

`panel-explore BRIEF_FILE [REPO_DIR] [LOG_PREFIX]`,同样只派发不决策。

同样的反锚定纪律:**主 agent 先把自己的方向写下来**,再把三份读作角度扩展 + 盲点网,然后
**综合**。不要把分歧塌缩成一个答案,不要平均成假共识,不要让三份浅见洗成"很全面"。
**brief 要写得更精简**——过度规定"好答案应该覆盖哪些点",模型就会锚定、不再发散。

brief 放 `/root/aiwork/tasks/`,日志放 `/root/aiwork/logs/`。两个 `panel-*` 工具都做了
启动错峰,共享引擎对 429/5xx 有带上限的退避,并行扇出不会再静默丢腿。

## 各评审腿的后端细节

平时不需要;真要改模型、换 key、排查某条腿死了的时候再读:
**`references/legs.md`**

## 信任校准(反复被验证的三条)

- panel 是**盲点网**,不是裁决机。
- **孤腿 BLOCK 才是信号**(3 家 PASS + 1 家 BLOCK 且成立,发生过)。
- **真漏的根因反复是我自己的规格/夹具错**——oracle 是主 agent 写的、**可能本身就错**;
  过审只证明"合乎规格",不证明规格对。多腿的价值正在于对着设计意图/相邻代码查规格本身。
- **失败腿的日志也要读**(subkimi 超时无结论那次,最值钱的两条在它的思考日志里)。
- 评审员提出的"未知",要去读源码/发探针打成"已知",别直接写进 UNTESTED。

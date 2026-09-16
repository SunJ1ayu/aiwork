# Design: review-convergence-and-preflight

- Change: review-convergence-and-preflight
- Status: draft

- 规划双出: 不适用:方向由业主经 Codex 建的任务单定形(A/B/C 协议 + D 只读预检),不是开放分叉;
  `impact.factors` 不含 `new_write_surface`(预检零写入;归档写口的行为不变)。

## Approach

### A/B/C 协议 —— 一处权威,其余引用

`workflow/skills/panel/SKILL.md` 的 **4b 整节改写**为「收到报告之后:核实 → 处置 → 修复清单 → 复审或结束」,
吸收旧 4b 的 ①②③ 与轮次读数,不另起第二份规则。要点:

1. **处置四类**(每条发现一行,落 verify.md 的发现表):
   - **本单必须修**:本次验收不成立 / 本次引入的回归 / 安全·权限·数据风险 / 关键验证证明不了本次承诺(含考卷假绿)。
   - **延期**:成立、有价值、不阻断本次交付 ⇒ 写进归档 verify.md,**不自动开新单、不继续施工**。
     开新单要业主说开,或它后来真的硌到人。
   - **驳回**:代码/复现/反证核实不成立。
   - **尚未核实**:如实挂着;高影响的未核实项不许当作驳回,本单保持未完成。
   - 判准两句:「测试证明不了**当前**承诺」要处理;「测试挡不住**任意未来**错误实现」不自动扩大承诺。
     「用户暂时看不见」不能单独成为延期安全、数据一致性或真实验证缺口的理由。
     旧 ②「业主那边会长成什么样」自检保留为**延期**那一类的必填理由。
2. **修复清单**:一轮报告去重分类后定一份清单,一次修完再复审;不边读边修。
3. **轮次预算**(旧 ③ 改写):开工在 proposal 写,默认 **2 轮实质评审**;第 2 轮主要核验修复与影响面、仍可报新发现。
   verify.md 记总派发次数,分开「内容复审」与「基础设施重试」。预算用完:无真实阻断 + 机械门满足 ⇒ 结束;
   有阻断 ⇒ 保持未完成、缩范围或重看方案;追加评审前先写明阻断、目的、新的有限预算。
   **旧 ③「超出的进下一单」删掉** —— 它管住了轮数、没管住单数,正是「一单接一单」的来路。
4. **旧 ①「先别改」保留**,补一句新的出路:派评审**之前**跑 `track preflight`,
   把非豁免文件上的收尾问题在绑定之前修掉 —— 今天那一轮就是这么白花的。
5. **C 设计检查触发**(短段):关键假设缺证据 / 用户目标与技术保证有落差 ⇒ 先做聚焦前提检查或最小实验;
   **同一类问题连续第二次打补丁** ⇒ 先查抽象、数据关系、共同根因、验收边界,再决定是否继续补。不等于自动全池探索。
6. **收尾决定 ≠ 归档资格**:延期/驳回写得再有理,也不让旧覆盖重新有效;不许伪造 PASS、降 risk、改 observation 过闸。

`track/SKILL.md` 与 `CONVENTION.md` 只加:`track preflight` 的入口一段 + 指向 panel 4b。

### D:`track preflight <name> [project-dir]`

**七项检查,全部跑完再汇总**(一项挡不短路其余各项):

| 项 | 复用 | 分类 |
|---|---|---|
| decision | `track-record validate --phase preflight`(新 phase) | 见下 |
| views | `_review_delivery.py --explain-views`(typed、非 self、verdict 为 null 或 PASS 时) | 有差异 ⇒ BLOCK |
| verify | verify.md 在不在 / legacy 占位符 | 缺 ⇒ BLOCK;占位符 ⇒ PENDING |
| receipts | `ev_check … always`(5a)再 `ev_check … archive`(5b/5c) | 5a 红 ⇒ BLOCK;只 5b/5c 红 ⇒ PENDING(收尾记录,改它不作废绑定) |
| ephemeral | `eph_check` | 命中 ⇒ BLOCK |
| destination | `tracks/archive/<name>` 已存在 | ⇒ BLOCK |
| worktrees | `_track_archive_sweep_worktrees` 新增 `preflight` 模式:照样判,**绝不删** | 会挡归档 ⇒ BLOCK;只有 ignored 文件要 `--discard-ignored` ⇒ PENDING |

**`track-record validate --phase preflight`**(规则分类的唯一一份,住在规则旁边):
- shape / observation schema / dispatch 规则失败 ⇒ `verdict=BLOCK`,rc=1。
- `outcome.verdict` 为 null ⇒ **在内存里假设 PASS** 去跑归档的 observation 覆盖检查(不写盘):
  第一条失败若是 `observation.required|success_required|review_budget|review_delivery|main_required|delegate_required|received_required`
  ⇒ `verdict=PENDING`(最终评审/执行收据还没到),并注明其后同组检查未评估;
  `observation.duplicate`、`review_delivery.view_mismatch`、`review_delivery.archive_drift` 等 ⇒ BLOCK。
  最后必报一条 `rule=field.decided path=outcome.verdict … verdict=PENDING`。
- verdict 已写:PASS ⇒ 与 archive 同判,任何失败都是 BLOCK;BLOCK/NMI/SUPERSEDED ⇒ archive 不查 observation,preflight 也不查。
- rc:0 通过 / 1 BLOCK / 3 只有 PENDING。输出**永不**打印 `status=valid phase=archive`,避免被当成归档凭据。
- 旧 track(无 decision.json)⇒ `status=legacy phase=preflight`,rc=0。

**退出码(`track preflight`)**:`2` 有 ERROR 或用法错 > `1` 有 BLOCK > `3` 只有 PENDING > `0` 全部通过。
ERROR = 检查本身没跑成(helper 缺件、track-record 退出码不在约定里、或 rc=1 却没有 `verdict=BLOCK` 行),
**永不**降格成 PENDING 或 OK。汇总行写明「通过 ≠ 可归档,归档时全部重验」。

**零持久副作用**的手段:整条命令 `export GIT_OPTIONAL_LOCKS=0`(不让 git 顺手刷新 index);
不调 runlog/observe;delivery 指纹本来就在临时 index + 临时对象库里算(`_review_delivery.py:123-127`);
worktree 走 preflight 模式,移除/删分支/rmdir 的代码在该模式下不可达。

## Key trade-offs / risks

1. **假设 PASS 去跑覆盖检查**:只在内存里、只在 preflight phase;archive/dispatch/shape 行为一字不改。
   风险是 preflight 的「PENDING」被读成「快好了」—— 输出里把"未评估的后续检查"写明。
2. **`validate_archive_observations` 仍是首错即停**:同组后面的检查不评估。不重构成收集全部错误 ——
   那是 1667 行门禁的核心路径,本单不值得冒这个险;改为诚实打印"其后未评估"。
3. **worktree 清理函数加模式参数**:归档路径最危险(不可逆删除)。preflight 分支只在"判完之后、删之前"return,
   且 `test-worktree-sweep.sh` 全套回归照跑。
4. **5d(收据进没进 git)不做**:归档那次 commit 才判得出,提前报只是噪音(proposal non-goal)。
5. **协议是纪律不是闸**:轮次预算、处置分类都靠我执行,机器只给读数与预检。它会不会真的少绕圈,
   只有接下来的真实任务能回答 —— 所以留试行记录格式,不在本单宣称提效。

## Alternatives considered

- **预检做成 `track archive --dry-run`**:一个命令两种语义,且 archive 首错即停的结构要大改;
  预检的输出是「分类清单」不是「成败」,单开 `preflight` 更不容易被误读成放行。弃。
- **在 bin/track 里按 track-record 的输出文本分类**:规则名的语义住在两处,迟早漂。弃,分类放 track-record。
- **把轮次上限做成 panel-review 硬拦**:panel-round-discipline 已论证过会误伤正当轮次。弃。
- **给延期项自动建 proposal**:正是「一单接一单」的来路。弃。

## 案例走读(协议可执行性;不是提效证据)

| # | 真实案例 | 旧规矩下发生了什么 | 新协议下怎么走 |
|---|---|---|---|
| W1 | 09-16 查更新被限流,第 4~8 轮审的是我自己的判据措辞 | 每轮"再确认一下",八轮 | 措辞类发现 ⇒ **延期**或落在豁免文件就地改;预算 2 轮用完、无真实阻断 ⇒ 结束。第 3 轮起根本不派 |
| W2 | 09-16 e2e 守卫后续单:回环检查被 `NODE_OPTIONS` 污染而放行(本单引入) | 按旧 ② "不是业主可见也不是假绿" ⇒ 记账不修,进下一单候选 | **本次引入的回归 ⇒ 本单必须修**,进第 1 轮修复清单,第 2 轮核验。其余 8 条「挡不住未来错误实现」⇒ **延期,不开单** |
| W3 | 同一单:`design.md` 一行 `/tmp/…` 在第 1 轮之后被归档闸拦 | 改一行 ⇒ 绑定作废 ⇒ 白跑第 2 轮 | 派第 1 轮前 `track preflight` ⇒ ephemeral BLOCK ⇒ 先改 ⇒ 第 1 轮绑定的就是最终内容 |
| W4 | 假想:第 2 轮新报一条成立的数据一致性风险(如归档写口丢档案) | —— | 属本单必须修;预算已用完 ⇒ **保持未完成**,修复后要追加一轮必须先在 verify.md 写明阻断与新预算;不能因"预算到了"放行 |
| W5 | 09-15~16 e2e 卫生账:浏览器临时目录点名连修两单 | 第三单差点又开 | 第二次对"点名"打补丁时触发 **C**:先问点名这个抽象(按目录残留推断"没关干净")是否站得住 —— Kimi 报的带点目录误点名正是这层的问题 |

## Test strategy (oracle)

判据 `tests/test_track_preflight.py`(主 agent 亲写,进 `bin/rust-check-review-tooling`),真 git 夹具、真 `bin/track`、
不调任何模型。每一幕**先断言盘上状态没变**,再断言分类与退出码。快照 = HEAD、refs、`git ls-files -s` 逻辑 index、
`.git/index` 字节、worktree 列表、仓内所有文件(含未跟踪)的路径+内容哈希、`.git/objects` 文件清单、worktree 根下全部文件。

| id | 场景 | 断言 |
|---|---|---|
| P1 | typed high、dispatch 合法、verdict=null、无 observation、干净 | rc=3;有 PENDING(outcome.verdict);0 BLOCK 0 ERROR;ephemeral/receipts/destination/views 各有 OK;快照不变;没有新 observation |
| P2 | design.md 引 `/tmp/…` | rc=1;BLOCK 点名 `design.md:行号`;**仍报** outcome PENDING(不短路);快照不变 |
| P3 | decision 高危因子却 standard + proposal.md 引 scratchpad | rc=1;两条 BLOCK(`impact.high_factor` 与 `proposal.md`)同时出现 |
| P4a | evidence 有 rc=1 收据、verify.md 没引 | rc=3;PENDING 提到 5b;0 BLOCK |
| P4b | verify.md 粘了一行 evidence 里没有的收据 | rc=1;BLOCK 提到 5a |
| P5 | 仓根有未跟踪文件 | rc=1;BLOCK 点名该文件;文件仍未跟踪、index 不变 |
| P6 | `tracks/archive/<name>` 已存在 | rc=1;BLOCK;那份目录原样 |
| P7 | track-record 换成崩溃桩(rc=1 无 verdict 行) | rc=2;ERROR;不是 0/3 |
| P8 | worktree 根下本轮一棵干净已合并的树 + 一棵脏树 | rc=1;两棵树、脏文件、分支都还在(archive 会删掉干净那棵) |
| P8b | 只有一棵干净已合并的树 | worktrees OK;树仍在 |
| P9 | P1 之后照跑 `track archive` | 归档被拒、目录没搬 ⇒ 不存在"预检过了免检" |
| P10 | verdict 已写 PASS、无 observation | rc=1;BLOCK(observation.required),**不是** PENDING;归档同样拒 |
| P11 | 评审已绑定当前交付、runlog 成功、verdict=null | decision 只剩 outcome PENDING(覆盖已满足);随后改 design.md ⇒ PENDING `observation.review_delivery` |
| P12 | 无 decision 的旧 track、verify 占位符 | decision OK(legacy);verify PENDING;rc=3 |
| P13 | 用法:缺名字 / track 不存在 | rc=2 |
| P14 | `track-record validate --phase archive/dispatch` 在 P1 夹具上 | 输出与改动前一致(archive 仍 `field.decided` BLOCK rc=1)—— preflight phase 没泄进旧 phase |

**这个 oracle 能被什么骗过?**

1. **分类对、但我照样不跑它**:预检是入口不是闸。能接住的只有 panel 4b 里「派评审前先跑」那句话 + 下次真实任务的试行记录。
2. **分类表漏了一条会在归档时出现的新规则**:未知规则一律落 BLOCK(不是 PENDING),所以漏分类的方向是"多挡"不是"放行";
   P10/P11 钉住两个方向各一例。
3. **快照没覆盖到的副作用**:例如写到仓外(`/tmp`)的缓存。仓外写入不改变被检查仓库,本单只承诺后者;
   `.git` 下我快照了 index/refs/objects/worktree 元数据,没快照 `.git/logs` 以外的每个文件 —— 快照整棵 `.git` 会被
   git 自己的无害维护抖动,换来误报。
4. **协议文档写对、实际还是一单接一单**:文档断言接不住。留试行记录格式,接下来约五个自然任务回头看。

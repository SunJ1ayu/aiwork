# Verify: 填 low 不许零成本

## 收据(机器写的,逐字节粘)

runlog: low-uncertainty-reason-gate rc=0 commit=ffb73b5 dirty=yes final=yes at=2026-09-19T15:05:54Z file=tracks/design-uncertainty-low-needs-reason/evidence/20260919T150554Z-01-low-uncertainty-reason-gate.txt

## 红检(判据先行,commit 4ff9b22 的树里 bin/track-record 仍是有洞版)

在**未修复**的版本上跑同一份判据:
```
[FAIL] low + 零理由 ⇒ 必须 BLOCK        期望退出码 1,实得 0
[FAIL] low + 指向不存在的文件 ⇒ BLOCK    期望退出码 1,实得 0
[PASS] low + 指向工件 ⇒ 放行
[PASS] 回归:high + 证据齐 ⇒ 放行
[PASS] 回归:high + 空证据 ⇒ 仍 BLOCK
[PASS] 回归:high 但没做攻击 ⇒ 仍 BLOCK
```
红的正是新增那两条;四条回归在有洞版本上也绿 ⇒ **它们不是恒绿的摆设**。
修复后六条全过(上面那行 runlog 收据)。

🔴 **自查:第一次测退出码时我用了 `cmd | tail -3; echo $?`,取到的是 tail 的退出码、不是闸的**,
三个"退出码=0"全是假的。重测(不走管道)才拿到真值:BLOCK=1 / 放行=0。
判据脚本里已按不走管道的方式写。

## 这道闸挡不住什么

只强制"说得出理由",**不判断理由对不对**;写一行废话同样能过。
买到的是"填 low 这个动作从零成本变成要当众写一句"。

## 影响面(已扫,非推测)

在途被拦 3 个,全是 aiwork 自己的 track,下次派活各补一行:
cursor-review-explore / review-result-oracle-pins / panel-all-from-roster。
design-studio 侧 7 个带 design 字段的全部不受影响,7 个无该字段的走 legacy。

## 轮次记录

- 派发 1(基础设施重试,不算实质轮):轮到 subglm,`CreditsError: Insufficient balance` ⇒ 0 腿成功。
- 派发 2(基础设施重试,不算实质轮):轮到 subkimi,`403 weekly usage limit` ⇒ 0 腿成功。
  顺带捞到一条:chat 腿因 `git diff is empty`(改动已提交、未设 diff base)**会盲评**,第 3 次已设 `PANEL_DIFF_BASE=ffb73b5`。
- 派发 3(**实质评审第 1 轮**):`PANEL_{GLM,KIMI,DEEPSEEK,GEMINI,GROK}_LEG=off`,subcursor rc=0,**verdict=BLOCK**。
  花名册:`submimo=SKIP(rotation) subdeepseek=off subglm=off subkimi=off subgemini=off subgrok=off subcursor=PASS(verdict=BLOCK)`
  日志前缀 `/root/aiwork/logs/panel-low-uncertainty-reason-r3-20260919-2311.*`

🔴 **轮换器把 standard(预算 1)的唯一名额连续两次派给已知坏腿** —— 偏好"最久没用",
而最久没用的恰恰全是坏的。这是工具问题,不是运气,记在账上。

🔴 **反锚定泄漏(如实记账)**:本轮违反"先派发、后写 verify.md",派发时 verify.md 已提交;
闸也点名了 `tasks/opendesign-auto-update-countdown*my-review.md`(我当轮为修 views BLOCK 才 commit 进来的)。
这一腿的独立性因此打折 —— 但它仍然报出了我完全没想到的四条,泄漏没救下我。

## 发现处置表(第 1 轮,subcursor)

| # | 发现 | 核实 | 处置 |
|---|---|---|---|
| 1 | 新闸让**既有锁定判据**变红:`tests/test-track-record.sh` 的 `low_decision()` fixture 正是 `low`+`not_required`+`[]`,R3「完整 low/self 计划可 dispatch」必红;R4/R4b/R6/R7/R10 归档用例、`test_track_preflight.py` P1/P4a/P8b/P14、`test_review_delivery.py` 同 fixture 一并受影响 | **成立,我亲自跑过**:`bash tests/test-track-record.sh` → `FAIL: R3: 完整 low/self 计划可 dispatch`,rc=1。**我从头到尾只跑了自己新写的六条,一次都没跑既有那套** | **本单必须修**(本次引入的回归) |
| 2 | 新脚本是孤儿:不在 `bin/rust-check-review-tooling` 的 SUITES 里,孤儿检查会硬失败 ⇒ 写了没人跑 | 成立 | **本单必须修** |
| 3 | 六条断言可被「合规但错误」的实现骗过,给了 5 条路:① 硬编码绝对路径没钉住被测树 ② 全部 case 都是 `impact=high`,于是错误地把 level 写进条件也全绿(而规格是只看 uncertainty)③ 只查退出码不查 rule 名 ④ 缺 `high+done+缺文件`,把存在性检查挪进 low 分支照样过 ⑤ 缺 `low+done+[...]` | 成立。**我在自审里问的正是「六条够不够」,它给了五条具体绕过路径** | **本单必须修**(考卷假绿) |
| 4 | 影响面低估:`validate_dispatch` 被 archive/preflight/panel-review/delegate-codex/track-commit-msg/track-guard 共用,不是 dispatch 专用;design.md 只写了「3 个 active track 下次派活补一行」 | 成立 | **本单必须修**(文档错误会误导下一个人) |

发现 4 附带一条**支持保留**的意见:`if evidence:` 不要拆出去 —— 没有存在性检查,
`low + ["nope.md"]` 就能用假路径满足"非空",那正是本单要堵的。这条与我的判断一致。

## 本轮结论:BLOCK,本单未完成

`bin/track-record` 的改动已 revert(`7497cfa`);回退后既有判据 rc=0 绿、
新判据 rc=1 红(洞回来了,正是判据先行该有的状态)。判据脚本与 track 工件保留。

🔴 **最该记住的一条**:我自己写的六条判据**全绿**,而那个改动是坏的 ——
它破坏了既有契约、判据还是孤儿、断言还能被绕过。
"过审只证明合乎规格,不证明规格对",这次的规格是我自己写的,**绿的也是我自己写的**。

## 待办(返工清单,一次修完再复审)

1. 决定并明示**契约变更**:既有 R3「完整 low/self 计划可 dispatch」是被锁定的契约,
   而它锁的恰恰是这个洞。要改它必须单独 commit 并写清"这是契约变更,不是让判据迁就实现"。
2. 同步更新所有用 `low`+`[]` fixture 的既有判据(test-track-record.sh / test_track_preflight.py / test_review_delivery.py)。
3. 新脚本加进 SUITES。
4. 按发现 3 的五条路补强断言(至少:不同 impact level、查 rule 名、`high+done+缺文件`、`low+done`、被测树可注入)。
5. 修正 design.md 的影响面。
6. 全部做完跑一次**全套** review-tooling,再派第 2 轮复审。

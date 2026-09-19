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

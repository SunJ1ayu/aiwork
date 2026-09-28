# Design: 填 low 不许零成本

## 方向为什么是确定的

不新增字段、不改 schema、不动 high 那一侧;只把已有的 `premise_attack.evidence`
在 low 这一侧也要求非空。改动落在 `bin/track-record` 的一个分支上,
行为边界由 `tests/test-low-uncertainty-reason.sh` 六条钉死(两条新、四条回归)。
(本文件这一段即本 track 自己 `design.uncertainty=low` 所指的理由 —— 吃自己的狗粮。)

## 做法

```
if uncertainty == "low" and not evidence:  → BLOCK design.low_uncertainty_reason
if evidence:                               → 逐条查文件真实存在(原来只在 status=done 时查)
```
第二行是顺带收紧:原来 low + 指向不存在的文件也能过,那等于允许填一个假路径充数。

## 影响面(已扫)

会被拦下的在途 track 3 个,都是 aiwork 自己的:cursor-review-explore /
review-result-oracle-pins / panel-all-from-roster —— 下次派活时各补一行理由。
design-studio 侧 7 个带 design 字段的一个都不受影响;7 个无该字段的老 track 走 legacy。

## 这道闸挡不住什么(别高估它)

它只强制"你得说出理由",**不判断理由对不对**。我完全可以写一行废话骗过它。
它买到的是"填 low 这个动作从零成本变成要当众写一句" —— 按 09-19 三轮 jev 实验的结论,
"方案好不好"目前没有任何机械手段判得了,这道闸也不例外。

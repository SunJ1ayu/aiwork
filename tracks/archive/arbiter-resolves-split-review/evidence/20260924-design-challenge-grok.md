# 4c 方案挑战原文:Grok 4.7 High(经 Cursor,family=xai)

- 派发:`panel-explore --members subcursor@grok-4.7-high`,09-24 12:41:35 → 12:45:42,rc=0;题面 = 同目录 20260924-design-challenge-brief.md
- 读取核查:36 次工具调用只读了题面允许的文件;review.diff 前 200 行只含 tasks/ 下旧未跟踪文件,未见 design.md 内容(按 P4/split_resolutions 等字样核过)

```
I'll read the review diff and the files the brief allows, then check the archive gate and conflict rules against the owner's split-verdict case.
The proposal is in place. Next I’ll check the archive gate, conflict summary, and how a decision binds to a review run.
Direction: 分裂要算覆盖，只认主裁对每条合格 BLOCK 腿摘了它已被钉住的日志原文；不要做一份由主裁自己列「每条意见」的清单。

Core bet: 「每条意见」在评审契约里不存在，日志字节存在，而且归档时本来就要重新对上。`ReviewLegResult` 的字段只有一个 `verdict`（`bin/_review_result.py` 的 `TOP_KEYS`）；`normalize_verdict` 只取最后一行「结论：」。意见在仓外日志里，`evidence.ref` + `evidence.digest` 把它钉死，`coverage_eligible` 在归档时会重读这个文件、对不上就失去资格。能挡住「一句话加任意现存路径」的，是这截原文，不是多出来的 JSON 条目。

How it works: `summarize_results` 的 `conflict` 仍是「同一 run、同一 subject digest 的合格腿里同时有 PASS 和 BLOCK」。这样的组要进 `qualifying_review_groups`，`decision.json` 的 `outcome` 里必须另有一份裁决，并且 `_review_delivery.py` 在算交付指纹时把它和 `outcome.verdict` 一样抹掉（今天只把 `verdict` 置成 `null`，旁边任何新字段都会改 digest，评审后补写就会作废这一轮）。这份裁决要绑住该组的 `run_id`、`subject.digest`，以及每条合格 BLOCK 腿自己的 `evidence.digest`。每条这样的腿至少一条驳回：`quote` 必须是该日志的字面子串，`reason` 非空，`evidence_path` 必须出现在这次评审已经绑上的交付行里。多写不存在的腿、digest 对不上、摘录不在日志里、路径不在那次交付里，归档照旧挡，并打印缺的是哪一条。ledger 把这种组标成主裁裁过的分裂。两家都 BLOCK、超时、无结论、降级、跨 run、同家族凑数，谓词不动。

Best at: 09-24 那种空转。产品没改，一家 PASS，一家 BLOCK，阻断句写在 MiMo 日志里（「测试挡不住一种假想改法」「上一版就有的行为」）。主裁要归档，就得把那句原文摘进来，再写理由，并指向这份交付里已经有的文件或行。摘一句日志里没有的话过不了闸。

Sacrifices: 闸仍数不全意见。日志里摘一句无关的话，再指一个交付里本来就有的文件，结构上仍能过；机器不判断这句是不是那条阻断、理由对不对。两家都 BLOCK 今天就能归档：`conflict` 只在 PASS 与 BLOCK 同时出现时为真（`_review_result.py` 第 715 行），`qualifying_review_groups` 不看 verify.md，所谓「逐条驳回」只是 panel 抽屉第 3 节 / 4b 的散文，而 4b 写明收尾决定不等于归档资格。之后另开一轮、合格腿全部 PASS，仍可单独成组归档，先前的 BLOCK 留在影子里——重抽直到全 PASS 这条路，提案没有关。

Blind spots in the brief: 「覆盖每条意见」做不到。验收里的「漏腿」查得了，腿在 observation 里；「漏意见」查不了，意见不是字段。主裁可以只列一条稻草人，再配一条非空理由和一个现存路径，这就是 09-22 要挡的一句话推翻。证据「现在存在、且在仓库内」也会被豁免文件满足：`verify.md` 整份跳过，runlog 收据跳过，它们不在被审指纹里，评审后新写一份收据指向自己，存在性检查照过。`/root/CLAUDE.md` 写的「冲突就追加第三腿」也破不了冲突：同一组里多一条腿，集合里仍同时有 PASS 和 BLOCK；新的一次 run 不能与旧腿拼接（`panel_review_coverage` 把跨 run 只放进 shadow）。前提若假就要重做的，就是这一条，而且它已经为假：不先把意见做成腿产出的封闭清单，任何「漏了一条意见就挡」的闸都是在查主裁自己写的清单。

Smallest first step: 只扩 `tests/test-track-record.sh` 里已有的 R10 `conflict` 夹具，先不改 schema。给那条 BLOCK 腿一份假日志并钉上 digest。摘录不在日志里，归档仍失败；摘录是日志里的阻断句，且路径在该 subject 的交付行里，这一组才算覆盖。摘录检查若挡不住「任意一句日志原文」，就不要做意见清单——那只是把同一句话换了个字段。
```

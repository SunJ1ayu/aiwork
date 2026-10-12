# aiwork 关卡验收记录

aiwork 的共用关卡（gate/）在只报不拦期间的验收结果。判据见 gate/README.md「首次部署验收」；这里只记看到的结果和链接。

| # | 结果 | 看到的结果和链接 |
|---|---|---|
| S0 | 符合 | main `9f42f2d`（PR #28 合并后）的提交上只有 CI 自己的检查，没有 `aiwork-gate-shadow` |
| S1 | 符合 | PR #29 开出后 10 秒内出现「等 CI」，发出者 aiwork-gate App（5121026）：[检查](https://github.com/SunJ1ayu/aiwork/runs/114274697279) |
| S2 | 符合 | CI 跑完后「不放行:缺合格评审」，G4 作者 UNKNOWN（aiwork-build[bot]）：[检查](https://github.com/SunJ1ayu/aiwork/runs/114275292848) |
| S3 | 符合 | DeepSeek 评审发出 15 秒内经 aiwork-review-ping 重算：[检查](https://github.com/SunJ1ayu/aiwork/runs/114276028594)；业主批准后变为「放行」：PR #28 [检查](https://github.com/SunJ1ayu/aiwork/runs/114257479381) |
| S4 | 符合 | 同一提交上 DeepSeek PASS，再发一条 BLOCK：「等业主批准……有 BLOCK」[检查](https://github.com/SunJ1ayu/aiwork/runs/114509299221)；业主在 BLOCK 之后批准：「放行」[检查](https://github.com/SunJ1ayu/aiwork/runs/114510299765) |
| S5 | 符合 | 业主在网页上提交 `e65c4cb` 后，G4 列出「aiwork-build[bot]、SunJ1ayu」，有了 PASS 仍「等业主批准」：PR #30 [检查](https://github.com/SunJ1ayu/aiwork/runs/114697226188)；业主在新提交上批准后「放行」：[检查](https://github.com/SunJ1ayu/aiwork/runs/114698141202) |
| S6 | 符合 | G2：PR #26 [检查](https://github.com/SunJ1ayu/aiwork/runs/114226884461)；G6：PR #28 [检查](https://github.com/SunJ1ayu/aiwork/runs/114257479381) |
| S7 | 符合 | 加 `aiwork:recheck` 后重算一次，保险丝先变黄再给结论：[检查](https://github.com/SunJ1ayu/aiwork/runs/114393330015) |
| S8 | 符合 | 改标题后重算：[检查](https://github.com/SunJ1ayu/aiwork/runs/114490975996)；改目标分支后 G1「目标分支在这次 CI 之后改过」：[检查](https://github.com/SunJ1ayu/aiwork/runs/114491936483)；推新提交、CI 重跑后 G1 恢复：[检查](https://github.com/SunJ1ayu/aiwork/runs/114508022151) |
| S9 | 符合 | 保险丝每次先 pending、再与检查同结论，发出者 github-actions[bot]；连着触发时排队的被取消、下一次等上一次跑完才开始：[运行 1](https://github.com/SunJ1ayu/aiwork/actions/runs/38073647235)、[运行 2（取消）](https://github.com/SunJ1ayu/aiwork/actions/runs/38073650274)、[运行 3](https://github.com/SunJ1ayu/aiwork/actions/runs/38073653349) |
| S10 | 符合 | 业主贴 `aiwork:merge` 后 18 秒，关卡判「放行」，由 aiwork-gate[bot] 合并 PR #30 的 head `124883d`（合并提交 `039b6bb`）：[检查](https://github.com/SunJ1ayu/aiwork/runs/114698304807) |
| S11 | 符合 | aiwork-build[bot] 给已放行的 PR #31 贴 `aiwork:merge` 后，关卡两次判「放行」，但没有合并：[检查](https://github.com/SunJ1ayu/aiwork/runs/114707088119)、[运行](https://github.com/SunJ1ayu/aiwork/actions/runs/38217939200)。贴标签的 aiwork-build[bot] 不是登记的 Builder，这条证明的是「业主和 merge_requesters 以外的人贴的不算」；登记的 Builder（SunJ1ayuBoT）在这个环境里没有贴标签的权限，没有在线上测 |
| S12 | 符合 | PR #31 挂着业主的 `aiwork:merge`，合并 main 后的新提交 `33eae5b` 上缺评审时「不放行:缺合格评审」，没有合并：[检查](https://github.com/SunJ1ayu/aiwork/runs/114712141613)；补上 PASS 后「放行」，由 aiwork-gate[bot] 合并：[检查](https://github.com/SunJ1ayu/aiwork/runs/114713596225)。业主没有在新提交上重新批准：GitHub 把合并 main 之前的批准挪到了新提交上，见下面「发现」 |
| S13 | 符合 | 业主给 PR #31、#32 都贴 `aiwork:merge`，关卡合并了 #32；#31 落后于 main，没有合并，标签留着：[运行](https://github.com/SunJ1ayu/aiwork/actions/runs/38218861885) |

## 发现

- PR #31：业主 07:27:54（UTC）在 `83dcdb2` 上批准；07:41:27 推了合并 main 的 `33eae5b` 之后，GitHub 返回的这条批准的 `commit_id` 变成了 `33eae5b`。关卡按 `commit_id` 认定「当前 head 上的批准」，所以把它算成了新提交上的批准。评审机器人的 PASS 没有被挪。
- S14（PR #33）：业主 08:27:54（UTC）在 `a00c524` 上批准；08:32:37 推了改内容的 `7c10a55` 之后，这条批准仍挂在 `a00c524` 上，关卡判「G7 需要业主在当前 head 上批准：还没有」：[检查](https://github.com/SunJ1ayu/aiwork/runs/114728805386)。改了内容的推送不会挪批准。
- 业主接受上面第一条，见 `.aiwork/accepted-risks.md` 第 2 条。

## 影子样本

转真拦截前，关卡在下面这些真实 PR 上的结论和业主的判断一致。从 #27 起算：#26 改了关卡的判定规则，之前的不算。没有见过过时的「放行」。

| PR | 关卡在合并时的结论 | 业主的判断 |
|---|---|---|
| #27 | 放行 | 批准并合并 |
| #28 | 放行 | 批准并合并 |
| #29 | 放行 | 批准并合并 |
| #30 | 放行 | 批准，贴 `aiwork:merge` 由关卡合并 |
| #31 | 放行 | 批准，贴 `aiwork:merge` 由关卡合并（批准随合并 main 挪到新提交，见「发现」） |
| #32 | 放行 | 批准，贴 `aiwork:merge` 由关卡合并 |
| #33 | 放行 | 批准，贴 `aiwork:merge` 由关卡合并 |

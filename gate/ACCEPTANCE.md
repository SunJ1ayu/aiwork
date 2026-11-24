# aiwork 关卡验收记录

aiwork 的共用关卡（gate/）验收记录，包含只报不拦与真拦截阶段。判据见 gate/README.md「首次部署验收」；这里只记看到的结果和链接。

| # | 结果 | 看到的结果和链接 |
|---|---|---|
| S0 | 符合 | main `9f42f2d`（PR #28 合并后）的提交上只有 CI 自己的检查，没有 `aiwork-gate-shadow` |
| S1 | 符合 | PR #29 开出后 10 秒内出现「等 CI」，发出者 aiwork-gate App（5121026）：[检查](https://github.com/SunJ1ayu/aiwork/runs/114274697279) |
| S2 | 符合 | CI 跑完后「不放行:缺合格评审」，G4 作者 UNKNOWN（aiwork-build[bot]）：[检查](https://github.com/SunJ1ayu/aiwork/runs/114275292848) |
| S3 | 符合 | DeepSeek 评审发出 15 秒内经 aiwork-review-ping 重算：[检查](https://github.com/SunJ1ayu/aiwork/runs/114276028594)；业主批准后变为「放行」：PR #28 [检查](https://github.com/SunJ1ayu/aiwork/runs/114257479381) |
| S4 | 符合 | 同一提交上 DeepSeek PASS，再发一条 BLOCK：「等业主批准……有 BLOCK」[检查](https://github.com/SunJ1ayu/aiwork/runs/114509299221)；业主在 BLOCK 之后批准：「放行」[检查](https://github.com/SunJ1ayu/aiwork/runs/114510299765) |
| S5 | 符合 | 业主在网页上提交 `e65c4cb` 后，G4 列出「aiwork-build[bot]、SunJ1ayu」，有了 PASS 仍「等业主批准」：PR #30 [检查](https://github.com/SunJ1ayu/aiwork/runs/114697226188)；业主在新提交上批准后「放行」：[检查](https://github.com/SunJ1ayu/aiwork/runs/114698141202) |
| S6 | 符合 | G2：PR #26 [检查](https://github.com/SunJ1ayu/aiwork/runs/114226884461)；G6：PR #28 [检查](https://github.com/SunJ1ayu/aiwork/runs/114257479381) |
| S7 | 符合 | 加 `aiwork:recheck` 后重算一次：[检查](https://github.com/SunJ1ayu/aiwork/runs/114393330015) |
| S8 | 符合 | 改标题后重算：[检查](https://github.com/SunJ1ayu/aiwork/runs/114490975996)；改目标分支后 G1「目标分支在这次 CI 之后改过」：[检查](https://github.com/SunJ1ayu/aiwork/runs/114491936483)；推新提交、CI 重跑后 G1 恢复：[检查](https://github.com/SunJ1ayu/aiwork/runs/114508022151) |
| S9 | 符合 | 连着触发时排队的被取消、下一次等上一次跑完才开始：[运行 1](https://github.com/SunJ1ayu/aiwork/actions/runs/38073647235)、[运行 2（取消）](https://github.com/SunJ1ayu/aiwork/actions/runs/38073650274)、[运行 3](https://github.com/SunJ1ayu/aiwork/actions/runs/38073653349) |
| S10 | 符合 | 业主贴 `aiwork:merge` 后 18 秒，关卡判「放行」，由 aiwork-gate[bot] 合并 PR #30 的 head `124883d`（合并提交 `039b6bb`）：[检查](https://github.com/SunJ1ayu/aiwork/runs/114698304807) |
| S11 | 符合 | aiwork-build[bot] 给已放行的 PR #31 贴 `aiwork:merge` 后，关卡两次判「放行」，但没有合并：[检查](https://github.com/SunJ1ayu/aiwork/runs/114707088119)、[运行](https://github.com/SunJ1ayu/aiwork/actions/runs/38217939200)。贴标签的 aiwork-build[bot] 不是登记的 Builder，这条证明的是「业主和 merge_requesters 以外的人贴的不算」；登记的 Builder（SunJ1ayuBoT）在这个环境里没有贴标签的权限，没有在线上测 |
| S12 | 历史符合（旧版） | PR #31 挂着业主的 `aiwork:merge`，合并 main 后的新提交 `33eae5b` 上缺评审时「不放行:缺合格评审」，没有合并：[检查](https://github.com/SunJ1ayu/aiwork/runs/114712141613)；补上 PASS 后「放行」，由 aiwork-gate[bot] 合并：[检查](https://github.com/SunJ1ayu/aiwork/runs/114713596225)。业主没有在新提交上重新批准：GitHub 把合并 main 之前的批准挪到了新提交上，见下面「发现」 |
| S13 | 历史符合（旧版） | 业主给 PR #31、#32 都贴 `aiwork:merge`，关卡合并了 #32；#31 落后于 main，没有合并，标签留着：[运行](https://github.com/SunJ1ayu/aiwork/actions/runs/38218861885) |

## 管理员网页合并验收

| # | 结果 | 看到的结果和链接 |
|---|---|---|
| S15 | 待验收 | [#111 的规则补记](https://github.com/SunJ1ayu/aiwork/issues/111#issuecomment-6552923695)记录了规则已保存，尚无管理员网页合并被拒的实测链接；不能把配置记录当成此项验收通过。操作与预期见 README 的 S15。 |

## D 方案上线后待验收

判据与步骤见 README 的 S9、S10–S12d；以下均未在新版 main 的真实运行中验收，不把离线桩测试或旧记录当成通过。执行时记录 PR、完整 head、授权检查链接和任务运行链接。

| # | 结果 | 范围与证据 |
|---|---|---|
| S9 / S12d | 待验收 | binding 不排并发组、gate 仍串行；需观察重算被顶掉而授权保存保留的真实运行 |
| S10 / S12 | 待验收 | 单次贴标签保存通知 head、条件补齐后由关卡合并该 head；上表是旧版本历史样本 |
| S11 | 待验收 | 先查现登记 Builder 的贴标签权限，无权限就保持未验收，不临时加权限；旧样本仅证明当时非授权账号不合并，未证明新版摘要 |
| S12a | 待验收 | 旧提交标签不授权后来普通推送的新提交 |
| S12b | 待验收 | A → B → A 不复用 A 的旧授权，摘要说明连续性原因 |
| S12c | 待验收 | 同一提交摘掉重贴可沿用旧授权；字段时间不同也不影响。须在真实样本中记载时间，不能主动改 GitHub 时间 |

上表历史 S12 的“手工合并 main 后仍沿用”不是新版普通推送的通过证据；只有 README「合并」的自动干净同步例外适用。
历史 S13 只测到旧版落后停止，不是现行 S13 自动同步已经通过的证据；现行 S13–S13c 仍须按 README 验收。

## 发现

- PR #31：业主 07:27:54（UTC）在 `83dcdb2` 上批准；07:41:27 推了合并 main 的 `33eae5b` 之后，GitHub 返回的这条批准的 `commit_id` 变成了 `33eae5b`。关卡按 `commit_id` 认定「当前 head 上的批准」，所以把它算成了新提交上的批准。评审机器人的 PASS 没有被挪。
- S14（PR #33）：业主 08:27:54（UTC）在 `a00c524` 上批准；08:32:37 推了改内容的 `7c10a55` 之后，这条批准仍挂在 `a00c524` 上，关卡判「G7 需要业主在当前 head 上批准：还没有」：[检查](https://github.com/SunJ1ayu/aiwork/runs/114728805386)。改了内容的推送不会挪批准。
- 业主接受上面第一条，见 `.aiwork/accepted-risks.md` 第 2 条。

## 影子样本

验收(S0–S14)之后，下面 5 个真实 PR 上，关卡的结论都和业主的判断一致，没见过过时的放行。#38、#40 前几轮关卡没有放行，业主也没有批准。

| PR | 合并时的 head | 关卡结论 | 业主的判断 | 检查 |
|---|---|---|---|---|
| #35 | 405e472 | 放行 | 批准，贴 aiwork:merge,关卡合并 | https://github.com/SunJ1ayu/aiwork/runs/115088294097 |
| #36 | 4c681ff | 放行 | 批准，贴 aiwork:merge,关卡合并(落后于 main 后合并了 main、重审一次，批准随之挪到新提交) | https://github.com/SunJ1ayu/aiwork/runs/115092332435 |
| #37 | 35c15cc | 放行 | 批准，贴 aiwork:merge,关卡合并 | https://github.com/SunJ1ayu/aiwork/runs/115111857228 |
| #38 | 77756d6 | 放行(第 3 轮) | 批准，贴 aiwork:merge,关卡合并 | https://github.com/SunJ1ayu/aiwork/runs/115318171822 |
| #40 | 19cdacc | 放行(第 2 轮) | 批准，贴 aiwork:merge,关卡合并 | https://github.com/SunJ1ayu/aiwork/runs/115622166690 |

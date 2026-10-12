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
| S11 | 待测 | |
| S12 | 待测 | |
| S13 | 待测 | |

S11–S13 用两个测试 PR 同时测，结果见上表。

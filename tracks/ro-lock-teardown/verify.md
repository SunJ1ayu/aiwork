# Verify: ro-lock-teardown

- Date: 2026-08-19
- Verdict: <PASS | BLOCK | NEEDS_MORE_INFO>

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [ ] build passes
- [ ] tests pass
- [ ] no secrets / unsafe ops

**机器打印的**(不是我的转述)—— 判据用 `runlog` 跑,把它打印的收据行原样粘进来:

```
runlog -t ro-lock-teardown -- <判据命令>
```

```
runlog: oracle-red rc=1 commit=d20372b dirty=yes at=2026-08-19T15:11:30Z file=tracks/ro-lock-teardown/evidence/20260819T151130Z-01-oracle-red.txt
runlog: capabilities-red rc=1 commit=d20372b dirty=yes at=2026-08-19T15:11:42Z file=tracks/ro-lock-teardown/evidence/20260819T151142Z-01-capabilities-red.txt
runlog: implementation-green rc=1 commit=8b731a8 dirty=yes at=2026-08-19T15:37:57Z file=tracks/ro-lock-teardown/evidence/20260819T153757Z-01-implementation-green.txt
runlog: implementation-green-2 rc=0 commit=dc721fa dirty=yes at=2026-08-19T15:48:01Z file=tracks/ro-lock-teardown/evidence/20260819T154801Z-01-implementation-green-2.txt
```

红检归因:

- `oracle-red`:helper 尚不存在，且 wrapper 忽略故障 helper 后仍调用假模型，5/5 按预期红。
- `capabilities-red`:目标红点覆盖 Claude 裸 Bash、OpenCode/MiMo 整项 Bash、Kimi 本地测试命令、
  能力提示词和四条 wrapper 的“副本可写/原仓只读”。同一收据另含当前受限沙箱禁止本地 socket
  造成的旧 HTTP 夹具红；它们不冒充本单 oracle，最终全量绿在允许本地 namespace/socket 的环境取证。
- `implementation-green` 首次总跑红在两处测试接线:新 suite 的守卫引入缺 `|| exit 78`，以及 V27
  的假仓没有 HEAD、被新前置提前拒绝；均修夹具/守卫接法，没有放松生产 helper。
- `implementation-green-2`:总入口全绿，含 review-tooling 425/0 与 review-workspace 20/0。

## Review

- lane: **full** —— 动的是**权限/写口防线本身**(拆掉一层内核级隔离、同时收紧命令白名单)。
  CLAUDE.md 的硬规矩:碰新写口/权限 ⇒ full,针孔再薄也不打折。
  这一单还多一条理由:它**推翻的是同一天刚归档的另一单**,而那一单三轮四审全票 PASS ——
  正说明"腿只验合不合规格、规格错了验不出来"。这次要请腿明确挑战**规格本身**。
  > **碰了新写口 / 权限 / auth / 钱 / 数据一致性 → full,针孔再薄也不打折**(硬规矩,别在这降档)。
  > fast = 主+1,中等风险;self = 主自审(闸③ + 截图 + 全量回归),
  > 限纯前端/纯观感、后端一字未动、只新增已过审针孔的调用方。
- 派给: **主 agent 直接干**(开工前判断,收口时回填返工数)—— 这一单的活几乎全是
  **取舍判断**(哪条判据依赖的前提没了、白名单收到多紧算够、净防护力下降到哪里可接受),
  不是"照着红判据写绿"的打字活;而判据(oracle)本来就不许外包。
  执行腿在这里省不下什么,反而要我把取舍写成任务书 —— 比自己干贵。返工数待收口回填。
- 规格自查(读任何 panel 输出之前先答):最可能错成“副本看起来隔离，实际漏 dirty/untracked，
  或 shared clone 仍能反写原仓”；由 O1 的内容视图对账、O2 的同进程双向写探针、O3 的并行
  串味探针证明。另一个规格风险是“允许 Bash”扩大了外部副作用面；本单只以原仓物理保护
  承重，不把提示词/参数白名单写成强敌沙箱。panel 需要专门挑战这两个前提。
- 腿的花名册: <把 `<日志前缀>.roster` 里那一行**原样粘过来**,别手写>
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - <...>
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): <...>
  > **归档时这一条和顶部的 `Verdict:` 都不许还是占位符**,`track-guard` 规矩3 会挡;
  > 没归档但已经合并上线的,`track list` 会打 ⚠️(stage-timer 就这么漏了两个月)。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>

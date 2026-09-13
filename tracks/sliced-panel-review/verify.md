# Verify: sliced-panel-review

- Date: 2026-09-13

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再按 impact-risk 预算跑 panel-review；只有特殊控制面
> 才显式 `--all` 做全池评审。最后仍由主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes(bash -n / python 语法随判据跑)
- [x] tests pass:全量离线总闸 25 套件全绿(最后一次改代码之后跑的,见最后一行收据)
- [x] no secrets / unsafe ops:runlog 前后扫秘密形状;判据断网跑;真跑只在仓外一次性小仓

**机器打印的**(逐字节,红的一份不藏):

```
runlog: redcheck-review-result rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:22:36Z file=tracks/sliced-panel-review/evidence/20260913T142236Z-01-redcheck-review-result.txt
runlog: redcheck-subcodex rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:22:37Z file=tracks/sliced-panel-review/evidence/20260913T142237Z-01-redcheck-subcodex.txt
runlog: redcheck-subcodex rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:25:03Z file=tracks/sliced-panel-review/evidence/20260913T142503Z-01-redcheck-subcodex.txt
runlog: redcheck-panel-slice rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:25:03Z file=tracks/sliced-panel-review/evidence/20260913T142503Z-02-redcheck-panel-slice.txt
runlog: redcheck-panel-slice rc=1 commit=eaaea75 dirty=yes at=2026-09-13T14:26:09Z file=tracks/sliced-panel-review/evidence/20260913T142609Z-01-redcheck-panel-slice.txt
runlog: redcheck-subcodex-catalog rc=1 commit=74f39d5 dirty=yes at=2026-09-13T15:31:52Z file=tracks/sliced-panel-review/evidence/20260913T153152Z-01-redcheck-subcodex-catalog.txt
runlog: mutation-panel-slice rc=1 commit=60480ee dirty=yes at=2026-09-13T15:35:33Z file=tracks/sliced-panel-review/evidence/20260913T153533Z-01-mutation-panel-slice.txt
runlog: mutation-panel-slice rc=0 commit=eca7b4a dirty=yes at=2026-09-13T15:52:31Z file=tracks/sliced-panel-review/evidence/20260913T155231Z-01-mutation-panel-slice.txt
runlog: full-regression rc=0 commit=eca7b4a dirty=yes at=2026-09-13T16:07:37Z file=tracks/sliced-panel-review/evidence/20260913T160737Z-01-full-regression.txt
```

每份红收据是什么:
- 前五份:判据先行对 base `eaaea75` 红检(review-result 2 红;subcodex 30 红 1 绿;panel-slice 两轮,
  第二轮收紧了「零调用拒绝」要求 `REFUSED <rule>` 标记 —— 二进制不存在时 rc≠0 且零调用会空转成绿)。判据 commit `74f39d5`。
- `redcheck-subcodex-catalog rc=1`:V2 真跑证伪 `--disable multi_agent` 后补的 C5,对第一版实现红 5 条 / 绿 32。
  同一份判据对仓外候选修复 37/0。判据 commit `60480ee`。
- `mutation-panel-slice rc=1`(咬住 30 / 漏网 1):漏网的 M4 报「靶子名不在基线里」,**实际在**。
  量具自己的毛病:pipefail 下 `grep PASS | grep -qF` 吃 SIGPIPE,200 次随机漏 2~3 次(关 pipefail 0/200)。
  改成单条 grep 后 300 次零漏零误中,单独 commit `eca7b4a`,第二轮 31/0。
  **同一写法还在** mutation-dead-leg-streak / mutation-panel-roster / mutation-subgemini 里(方向都是误报漏网,不会假绿),不在本单修。

真跑(不是 runlog 收据,原始报告与事件流入库):
- V2 subcodex 三次:`evidence/v2-live-subcodex/`(README 里有表)。第一版不合格(子 agent 工具 + web__run 在),
  修后两次各去掉一个开关做归因。仓内修复与验证过的副本逐行一致(注释行除外,只差一句报错文案)。

## Review

- 规格自查(读任何 panel 输出之前先答):<如果规格本身就是错的,会错成什么样、我怎么发现?
  panel 只验"实现合不合规格",验不了"规格对不对" —— 全池一致 PASS 也不等于题是对的。>
- 腿的花名册: <把 `<日志前缀>.roster` 里那一行**原样粘过来**,别手写>
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > **控制器没活到收尾时它压根不存在** —— 那时跑 `panel-roster <日志前缀>` 从盘上重建,
  > 与控制器自己写的**归一化后一致**(判据 R5b 守着;抬头有渲染时间戳,不是字面逐字节)。**一轮零记录的评审也粘得出这一行**,
  > 所以"那轮被砍了所以没有花名册"不再是理由(2026-08-23,track panel-roster-from-disk)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - <...>
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): <...>
  > 这里写理由；最终枚举写进 `decision.json.outcome.verdict`。归档时仍为空会被
  > `track-record validate --phase archive` 挡住，`track list` 也会打 ⚠️。

## Accepted deviations

- <接受的非关键偏差 + 原因 + 影响范围,或 None>

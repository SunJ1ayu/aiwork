# 验证记录

尚处设计阶段；没有实现或完成结论。机器裁决字段仅在 decision.json。

## 基线

第一遍因沙箱禁止 unshare，各套件在执行测试前拒跑。第二遍在宿主跑，但我同时运行了真实 panel-explore，改动了 MiMo 评审配置；V45 正确发现环境变化，该次回归不能作为干净基线。外审结束后单独重跑受影响套件。

runlog: baseline rc=1 commit=553e7ba dirty=yes at=2026-09-09T02:02:25Z file=tracks/review-delivery-binding/evidence/20260909T020225Z-01-baseline.txt

runlog: baseline-host rc=1 commit=553e7ba dirty=yes at=2026-09-09T02:03:31Z file=tracks/review-delivery-binding/evidence/20260909T020331Z-01-baseline-host.txt

## 新判据红检

旧实现没有交付指纹 API，10 条新行为测试在缺模块处红；另 1 条直接证明 decision v2 可被降回 v1、旧 shape 校验仍返回成功。实现后还需对归档比较做变异红检，不能把缺模块当成逻辑闸有效的证明。

runlog: delivery-red rc=1 commit=553e7ba dirty=yes at=2026-09-09T02:12:53Z file=tracks/review-delivery-binding/evidence/20260909T021253Z-01-delivery-red.txt

## 接手后补的判据(主裁换人:第 3~5 步由 Claude 接手,GPT 腿额度耗尽停在实现中途)

前一轮的红检只证明"模块不在"(缺件红),证明不了"闸咬得动",也没有任何判据问过
**这道闸有没有接上线**。补三条行为级判据 + 一份变异红检,并先证明它们此刻是红的:

- P9a/P9b(tests/test-panel-observation.sh):派发端。panel-review 必须把归属 track
  传进腿的环境,否则每条腿都产 v1 subject、归档闸的比较永远走不到。**此刻红。**
- 模板端(tests/test_review_delivery.py):`track new` 出来的 track 必须要求绑定。
  **此刻红**(实测打印 `delivery=legacy-unbound`)。
- RW8(tests/test-review-workspace.sh):喂料端整链(workspace→facts→subject),
  外加**两套扫描实现同解**的对账。这段实现已在,**此刻绿 = 锚断言**;
  第 4 段用副本把 delivery 段拆掉,证明它咬得动(2 条转红)。
- tests/mutation-review-delivery.sh:6 个变异逐条放松闸,证明判据咬得住。
  与 mutation-review-result.sh 同形态(只动仓外副本、不就地变异),同样是手动红检工具。

第一份收据里 RW8 有一条红在别处(我自己判据的 bug:`--task-sha256` 少写 `sha256:` 前缀),
已修;以 v2 那份为准。**两份都留着,不删。**
⚠️ 两份收据行的 `rc` 是外层 bash 的退出码,不是"判据全绿"的意思 —— 红在正文里逐条列着。

runlog: wiring-pins-red rc=1 commit=a91a65d dirty=yes at=2026-09-09T02:43:17Z file=tracks/review-delivery-binding/evidence/20260909T024317Z-01-wiring-pins-red.txt

runlog: wiring-pins-red-v2 rc=0 commit=a91a65d dirty=yes at=2026-09-09T02:44:23Z file=tracks/review-delivery-binding/evidence/20260909T024423Z-01-wiring-pins-red-v2.txt

runlog: baseline-review-tooling-serial rc=0 commit=553e7ba dirty=yes at=2026-09-09T02:10:42Z file=tracks/review-delivery-binding/evidence/20260909T021042Z-01-baseline-review-tooling-serial.txt

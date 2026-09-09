# 验证记录

尚处设计阶段；没有实现或完成结论。机器裁决字段仅在 decision.json。

## 基线

第一遍因沙箱禁止 unshare，各套件在执行测试前拒跑。第二遍在宿主跑，但我同时运行了真实 panel-explore，改动了 MiMo 评审配置；V45 正确发现环境变化，该次回归不能作为干净基线。外审结束后单独重跑受影响套件。

runlog: baseline rc=1 commit=553e7ba dirty=yes at=2026-09-09T02:02:25Z file=tracks/review-delivery-binding/evidence/20260909T020225Z-01-baseline.txt

runlog: baseline-host rc=1 commit=553e7ba dirty=yes at=2026-09-09T02:03:31Z file=tracks/review-delivery-binding/evidence/20260909T020331Z-01-baseline-host.txt

## 新判据红检

旧实现没有交付指纹 API，10 条新行为测试在缺模块处红；另 1 条直接证明 decision v2 可被降回 v1、旧 shape 校验仍返回成功。实现后还需对归档比较做变异红检，不能把缺模块当成逻辑闸有效的证明。

runlog: delivery-red rc=1 commit=553e7ba dirty=yes at=2026-09-09T02:12:53Z file=tracks/review-delivery-binding/evidence/20260909T021253Z-01-delivery-red.txt

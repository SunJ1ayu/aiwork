# Verify: rules-single-source

## 检查记录

基线 review-pr 22 项通过。新测试定稿在最新 main 上真实失败：旧实现仍读项目规则，忽略 aiwork main，来源失败时仍会发布。最初一次测试被沙箱的网络隔离权限阻止；另一次独立 checkout 尚未对齐最新 main，后续已校正并重新红检。这些尝试不计作有效基线证明，保留收据。

runlog: source-red rc=1 commit=00a78a9 dirty=yes at=2026-10-04T15:34:56Z file=tracks/rules-single-source/evidence/20261004T153456Z-01-source-red.txt
runlog: source-red rc=1 commit=00a78a9 dirty=yes at=2026-10-04T15:35:16Z file=tracks/rules-single-source/evidence/20261004T153516Z-01-source-red.txt
runlog: source-red rc=1 commit=50e6adb dirty=yes at=2026-10-04T15:36:38Z file=tracks/rules-single-source/evidence/20261004T153638Z-01-source-red.txt
runlog: source-red-main rc=1 commit=00a78a9 dirty=yes at=2026-10-04T15:38:05Z file=tracks/rules-single-source/evidence/20261004T153805Z-01-source-red-main.txt
runlog: source-red-final rc=1 commit=00a78a9 dirty=yes at=2026-10-04T15:39:08Z file=tracks/rules-single-source/evidence/20261004T153908Z-01-source-red-final.txt
runlog: source-green rc=0 commit=121c434 dirty=yes at=2026-10-04T15:40:26Z file=tracks/rules-single-source/evidence/20261004T154026Z-01-source-green.txt
runlog: related-tests rc=0 commit=121c434 dirty=yes at=2026-10-04T15:41:21Z file=tracks/rules-single-source/evidence/20261004T154121Z-01-related-tests.txt
runlog: token-tests rc=0 commit=121c434 dirty=yes at=2026-10-04T15:41:31Z file=tracks/rules-single-source/evidence/20261004T154131Z-01-token-tests.txt
runlog: suite-coverage rc=0 commit=121c434 dirty=yes at=2026-10-04T15:41:32Z file=tracks/rules-single-source/evidence/20261004T154132Z-01-suite-coverage.txt

## 提交前检查

review 相关测试共 74 项通过（其中 review-pr 23 项）；App 令牌范围测试 5 项通过；套件注册覆盖检查通过。规则比对恰好两个差异块，反向替换后与源提交原文逐字节相同。tests/test_review_pr.py 自判据提交之后未改。

## 评审

设计挑战已完成，核实结论见 design.md。实现评审尚未派发。

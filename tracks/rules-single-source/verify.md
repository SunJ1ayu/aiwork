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

设计挑战已完成，核实结论见 design.md。实现评审第 1 轮完成：两个独立家族均有完整、未降级的合格结论，未发现可复现的 P1；主 agent 核实后认为本次技术交付可开 PR。机器枚举和覆盖见 decision.json / observations。

| 轮 | 类型 | 派发前预检 | 结果 |
|---|---|---|---|
| 1 | 实质 | rc=3，BLOCK=0，ERROR=0，仅评审/仲裁待定 | 两家完成，无新增 P1 |

主 agent 的第一遍自审在派发前已落盘于仓外本机资料目录，包含真实 diff、源规则字节核对和测试结果；未放进评审题面。原始模型日志不提交。

| 发现 | 核实 | 处置及理由 |
|---|---|---|
| DeepSeek P2：匿名规则 API 配额影响可用性 | 源读取 HTTP 错误按失败关闭，代码和测试一致 | 延期。高频评审者可能遇到拒绝评审；当前用户明确要求不可读就拒绝，未新增备用来源或扩大令牌权限。 |
| Grok P2：历史决定的已被取代标记可能被误读为新来源作废 | 192 行标的是原决定，正文及 phase-c 均指向现行来源，满足用户要求 | 延期。以后阅读历史决定的人可能误解日期标记，当前实际来源没有歧义，不因此新增评审轮。 |
| Grok P3：缺失风险的任务书断言可能匹配到标题里的无 | 现有 main_document 缺失风险的测试精确等于无，main 直接拼接返回值；正文拼接在当前实现正确 | 延期。以后改动任务书拼接时，这条辅助断言可能漏报；属于未来测试加固，本次目标风险来源由实际 main() 测试钉住。 |
| DeepSeek P3：规则读取在快照后 | 仅获取令牌及只读快照；读取失败发生在派腿与发布之前 | 延期。源不可读时多做一次只读获取，不影响零派发零发布，符合当前接口。 |
| DeepSeek P3：风险路径两处字面量 | 属于原有代码，用户本次只要求规则来源常量单处定义 | 延期。以后若改风险路径需要同步标题，本次没有新增或改变该概念。 |
| DeepSeek P3：README 的全局 AGENTS 路径 | README 指 /root/AGENTS.md，本次新增的是仓库根目录 AGENTS.md | 驳回。路径不同，原文字面仍属实。 |

花名册（机器原文）：
# panel-review 花名册(2026-10-04 23:57:29)task=rules-single-source-review
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=high requested-budget=2 selected-count=2
# selected=subdeepseek(deepseek/subdeepseek-agent),subcursor.grok-4.7-high(xai/subcursor)
# escalation=none
# snapshot=head:bf94cbf
# 日志:/root/aiwork/logs/rules-single-source-r1.*.log
subdeepseek=PASS(verdict=PASS) subcursor.grok-4.7-high=PASS(verdict=PASS)


runlog: commit-audit rc=0 commit=bf94cbf dirty=yes final=yes at=2026-10-04T16:00:20Z file=tracks/rules-single-source/evidence/20261004T160020Z-01-commit-audit.txt

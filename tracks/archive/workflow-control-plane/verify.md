# Verify: workflow-control-plane

- Date: 2026-08-20
- Verdict: PASS

## Mechanical checks

- [x] build passes
- [x] tests pass
- [x] no secrets / unsafe ops

Final machine evidence (exact line printed by `runlog --final`):

```
runlog: final-green rc=0 commit=6e386d4 dirty=yes final=yes at=2026-08-20T14:16:38Z file=tracks/workflow-control-plane/evidence/20260820T141638Z-01-final-green.txt
```

The receipt binds full HEAD `6e386d4c2c719f8079d0e5028b9e17454709f291`; before/after source view is
`sha256:a9999be434a2180d9a84929227253ebd3b0eafc00d22846d403708729ceed204`,
`source-stable: yes`, and `command-rc: 0`.

## Review

- lane: high
  - impact-risk: high (review/evidence/archive control plane)
  - design-uncertainty: low (owner-approved direction; implementation and edge cases under review)
- 派给: 主 agent 直接实现与主裁；外腿只读复核。
- 规格自查: 最可能的规格错误是“为省额度一并删掉独立覆盖”或“为证据身份额外重跑一次慢测试”。实现保留主审、跨家族健康池、条件第三腿和显式 `--all`；final 收据复用原有最后一遍全量回归。
- 腿的花名册: submimo=SKIP(health:quota) subdeepseek=PASS(verdict=BLOCK) subglm=FAIL(rc=1,降级:回落聊天腿也没成) subkimi=SKIP(health:quota)
- findings:
  - 主审在首次 panel 前发现并修复了 ignored cache 白名单语义偏差与 submodule HEAD 漏哈希。
  - 首次 panel 发现 non-final 秘密输出可入收据；进一步证明当时 DeepSeek/GLM 的名义裁决均是提示词/推理回声。已用红测试统一所有 runlog 输出扫描，并改为只认独立裁决行。
  - 本地最小实验确认 merge commit 会被历史审计漏掉；已改为显式对第一父提交比较并有 merge-only 红测试。
  - 有效复审 DeepSeek BLOCK 指出尾随空白裁决误判、降级+不完整状态丢维、`mktemp` 失败未 fail-closed；三项均先红后绿。
  - 复审过程又暴露 panel 控制变量污染 oracle；已加污染父环境探针并在判据入口一次性清理。
  - DeepSeek 声称嵌套 `package.json` 因 `diff-tree` 缺 `-r` 而漏审；该候选红测试在未修实现上即为绿，显式 pathspec 会产出嵌套 patch，因此驳回。
- arbitrated verdict (主裁): PASS。不以腿数投票；所有可复现 finding 均已有对应红测试和修复，驳回项在原实现上即不会失败，最终绑定源码视图的全套机械判据全绿。

## Accepted deviations

- 高风险复审只取得一条有效外部裁决：MiMo 上轮超时、Kimi 明确额度不足，GLM agent 失败后 chat 回落遇上游 HTTP 503。它们均如实记在 roster，没有冒充 PASS。影响是缺少第二家族的最终确认；用主审仲裁、每项 finding 的红-绿判据和全套 final 收据补偿，不额外烧第三家额度。
- Final 收据的 `dirty=yes` 来自用户原有未跟踪 `tasks/lock-teardown-adversarial.md`。runlog 将它纳入前后源码视图且摘要稳定；本轮未修改、未删除该文件。
- 输出扫描为了“回显前拒绝秘密”需要在仓外完整缓冲，未设内容尺寸上限。缓冲创建/权限失败已 fail-closed；极大输出仍可耗尽临时空间，影响限于本次判据失败，不会将未扫描内容写入收据或回放到终端。

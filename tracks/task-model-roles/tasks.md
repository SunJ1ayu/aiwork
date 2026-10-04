# Tasks: task-model-roles

- base-ref: 7ceea985e3b6cae1d34a5faece43f96db732074b
- [x] 复核独立挑战与 GitHub 作者机制，固定非重叠 PR 基线。
- [x] 主 agent 写失败测试并单独提交。
- [x] 修改 OpenDesign 本次任务的审核排除、aiwork 仓库路由和令牌收窄。
- [x] 运行针对变更的回归，留下两仓库精确差异与说明。
- [x] 云 Claude 独立审核，按唯一规范收敛发现。结果：
  - aiwork PR #5（已合并 c864a93）：两轮。第 1 轮 1 条 P1（计划文档说法与关卡不一致）已修，第 2 轮 PASS。
  - OpenDesign PR #21：云 Claude 两轮 PASS；#21 因用业主个人账号开、业主无法批准，改由 PR #23 重开（同一提交）。
  - OpenDesign PR #23（已合并 718bd36）：DeepSeek 两轮 PASS（第 2 轮是同步 main 后在新提交上重审）。

## 评审遗留待办（只记不修；下次改到对应位置时一并处理）

- [ ] P2：policy.json 规定 builders 只登记单一模型专用账号，但只有一句说明，validatePolicy 和测试都不检查。出处：[OpenDesign PR #21 评审](https://github.com/SunJ1ayu/OpenDesign/pull/21#pullrequestreview-5401699623)、[OpenDesign PR #23 评审](https://github.com/SunJ1ayu/OpenDesign/pull/23#pullrequestreview-5401928769)。
- [ ] P2：已知作者时 high 路径的「两家」可以都是其他 Builder 家族，独立性从「Builder 圈外」变为「作者家族之外」；这是本改动的本意，要业主知情。出处：[OpenDesign PR #23 评审](https://github.com/SunJ1ayu/OpenDesign/pull/23#pullrequestreview-5401835080)。
- [ ] P3：policy.json 写「模型」，decide.mjs、README 写「家族」，用词不统一；同一条规则在 decide.mjs 文件头、policy.json、README 三处各写一遍。出处：[OpenDesign PR #23 评审](https://github.com/SunJ1ayu/OpenDesign/pull/23#pullrequestreview-5401928769)、[OpenDesign PR #23 评审](https://github.com/SunJ1ayu/OpenDesign/pull/23#pullrequestreview-5401835080)。
- [ ] P3：tests/test_aiwork_gate.mjs 里两条测试名说得比实际测的多；第 476 行注释还写「Builder 家族」。出处：[OpenDesign PR #23 评审](https://github.com/SunJ1ayu/OpenDesign/pull/23#pullrequestreview-5401928769)、[OpenDesign PR #23 评审](https://github.com/SunJ1ayu/OpenDesign/pull/23#pullrequestreview-5401835080)。

正式启用另需：共享 build 账号的可信任务来源、实际平台接口与隔离验收。代码已发布供审核，当前不安装或合并。

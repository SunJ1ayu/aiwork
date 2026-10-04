# Proposal: rules-single-source

- Date: 2026-10-04
- 用户原话：评审规则以 aiwork 为唯一来源；分两个 PR，先 aiwork、合并后再 OpenDesign。
- 目标：项目共用 aiwork main 的唯一规则，评审任务书标明规则提交；项目风险仍由各项目 main 提供。
- 范围：规则原文迁入（只改开头位置/治理段和末尾使用表）、review-pr 与测试、根目录指向、现行文档同步。
- 非目标：合并 PR、修改规则实质内容、改变 App 权限、提前发布 OpenDesign PR。
- 验收：先独立提交真实红测试；规则不可读时不跑腿、不发布；本地/项目规则不能影响口径；风险来自目标项目 main。
- 实质评审预算：2 轮，第二轮只在有本单阻断时使用；每轮之前运行 track preflight。

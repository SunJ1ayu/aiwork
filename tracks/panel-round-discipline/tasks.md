# Tasks: panel-round-discipline

- base-ref: 8b3520c00a500a9286aee4d2e0c282c9a51cda92

> 本单不外包:散文那半是我自己的工作纪律,机器那半是评审派活器本体(判卷防线)。

- [ ] 判据先行:`tests/test-panel-round-discipline.sh` R1~R6(在现有代码上跑出红,单独 commit)
- [ ] 实现 ①:`bin/panel-review` 绑定 track 时打印「第 N 轮 + 上一轮以来改动三桶(含文件名)」
- [ ] 实现 ②:`workflow/skills/panel/SKILL.md` 三条规矩(含机制修正)+ 同步部署副本
- [ ] 红检(变异咬住 R2/R3/R5 的关键断言)
- [ ] `sync-workflow-docs --check` 零漂移 + aiwork 判据总跑
- [ ] panel-review(impact high:判卷控制面)→ 仲裁

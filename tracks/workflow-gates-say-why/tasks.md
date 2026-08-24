# Tasks: workflow-gates-say-why

- base-ref: 9b2d750

- [x] 判据先行:A1~A5 加进 tests/test-runlog.sh 的 R8 组,先红(79/3,红的正是 A1×2+A5)
- [x] `bin/runlog`:source-stable=no 时向 stderr 打人话(四要素:什么事/为什么不算数/怎么办/常见元凶)
- [x] `bin/runlog` --help 补一句「--final 期间不许并发写入」
- [x] `workflow/skills/panel/SKILL.md`:反锚定补完(回退 verify.md 挡不住 diff 区间里的旧版本)
- [x] 两份 skill 副本同步 + 逐字节核对
- [x] 判据全绿(runlog 套件 82/0)
- [x] aiwork 全部 19 个套件总跑(最终收据,跑时无并发写入)

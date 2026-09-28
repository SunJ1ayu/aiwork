# Tasks: gate-backdoor-coverage

- base-ref: 5bb1500

- [x] 判据 V24(修复前红):env 不再能过闸 / 命令行标记才行 / 漏网报告点名
- [x] 后门改造:`gate_strip_flags` + 四条躯干 + panel-review 命令行传
- [x] 名单抽成 `bin/_tooling-paths.sh` **唯一一份**(track-guard 与漏网报告共用)
- [x] 漏网报告接进总跑 + `--coverage-only` 快速模式
      (第一版把开关放在跑完套件之后 ⇒ 加了开关却还要等 10 分钟,等于没加;已挪到前面)
- [x] verify(lane: fast,submimo PASS + 两条 LOW 已改)

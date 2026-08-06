# Tasks: delegate-entry-redcheck

- base-ref: a97014a287dbb17c9b36ebb69494cbc85c90491e

> 本单**主 agent 自己干**(判卷防线 = 信任面,不外包)。判据先行、每条修复前先红检。

- [x] 判据 `tests/test-delegate-entry.sh`(实现前 18 处红)—— `516c774`
- [x] 规划双出:`gpt-5.6-sol` 独立出一版(`logs/delegate-entry-dualplan.md`),
      我的方向先落盘再派 —— 点破三处结构性洞,判据先补再实现(`a9e5e1c`)
- [x] `bin/delegate-codex`:拒发闸(攻题记录 非空/仓外/**新过判卷**、判卷清单必给)
      + 三件套注入 + 回执 + `--receive` 闸①(diff **且** status -uall)+ 改动底账 —— `212d1d7`
- [x] `bin/redcheck`:退回 → build → 判据必须红;仍绿=恒真断言;build 没过=红检无效;
      `--must-fail` 认目标断言;trap 恢复 + 自证 —— `212d1d7`
- [x] `bin/rust-check-review-tooling` 改清单驱动(`test-track-guard.sh` 与本单判据
      此前**谁都没被总跑调用过**)—— `212d1d7`
- [x] 抽屉与模板:`delegate/SKILL.md` 指向入口 + 攻题必填 + 退回红检;
      design 模板「规划双出」退掉「外包」那半句(升级进 `--attack-log`)—— `212d1d7`
- [x] **拿 redcheck 红检 redcheck 自己**(真仓、非桩):撞出两条真缺口,各自先红后修 ——
      基线上不存在的新文件退回=删掉它、`--impl` 变长写法(用法与解析对不上)
- [x] **在 design-studio 上真跑一次真 build**(design 里写明这条不真跑不算数):
      `--base 611dd49 --impl web/src/chat/… web/dist --build 'cd web && npm run build'`
      ⇒ 抓到 vite 产物按内容改名导致恢复不干净(**是恢复自证闸响的**,不是静默留下),
      先补判据再修成 checkout+reset+clean 三步,同一条命令复验干净 —— `70d2a6e`
- [ ] verify(lane: full)+ 归档

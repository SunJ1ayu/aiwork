# Tasks: machine-evidence-gate

- base-ref: `6f7f5f8`(开工时 HEAD)

- [ ] **T1 判据先行,单独 commit** —— `tests/test-runlog.sh`(新)+ `tests/test-track-guard.sh`
      新增 G6/G7。落盘时的红检基线:**runlog 20 红 / track-guard 13 红**。
- [ ] **T2 `bin/runlog`** —— 收据落盘 + 收据行 + 退出码透传 + dirty 跑前算。
- [ ] **T3 `bin/_evidence.sh`** —— 收据读取/校验逻辑的**唯一一份**
      (`track-guard` 与 `track archive` 共用;两份拷贝总有一份会落下,这是本机反复记账的债)。
- [ ] **T4 `track-guard` 规矩5(a/b/c/d)** + `track archive` 命令内同款检查(G3 的道理)。
- [ ] **T5 模板** —— `track/templates/verify.md` 的 Mechanical checks 换成 runlog 口径。
- [ ] **T6 说明书** —— `track/CONVENTION.md` 记一句;`CLAUDE.md` 随身规矩加不加**先想清楚**
      (总量不许只进不出;能做成常驻护栏就别写成条文)。
- [ ] **T7 退回红检** —— 用 `redcheck` 把实现真退回基线,要求判据真的红,
      且红在该红的地方(桩红不算数)。
- [ ] **T8 全量回归** —— aiwork 五套判据全跑,**用 runlog 跑**(自己吃自己的狗粮)。
- [ ] **T9 lane:full 四审 + 主裁 + 归档**。

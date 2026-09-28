# Tasks: redcheck-pycache

- base-ref: 60915a41ecc1e392eeb0ad44b296bc76a38609f8

第一轮(修复本体)

- [x] 判据先行:`tests/test-delegate-entry.sh` 加"缓存不许骗过红检"那一幕,
      **单独 commit**(`60915a4`),提交时是红的(2 条)。
- [x] `bin/redcheck` 加 `purge_pycache()`,两处调用(退回后 / 恢复后)—— `fddb08d`。
- [x] 红检:换回 HEAD 那版 redcheck ⇒ 69/2 红;装上修复 ⇒ 71/0 绿。
- [x] 全量回归六套件。
- [x] 闸③ 亲读 diff。

第二轮(四审修复轮)

- [x] full lane 四审(roster 见 verify.md;subkimi 撞额度上限,半截日志照读)。
- [x] 判据先行:三条发现各配一幕 + 两条分支锁,**单独 commit**(`21ff9ab`),红 3 条。
- [x] ⑭ 那一幕对现版本天生是绿的 ⇒ **单独红检**(摘掉 restore 里的 purge)⇒ 红。
- [x] 修 F1/F2/F3/F5(`fb8dc6d`);F6 记录不改。
- [x] 红检第二轮:两个工具换回旧版 ⇒ 76/3;修复后 79/0。
- [x] 全量回归六套件(机器输出粘在 verify.md)。
- [x] 主裁 PASS,归档。

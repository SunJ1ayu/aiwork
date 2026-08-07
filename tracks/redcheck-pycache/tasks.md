# Tasks: redcheck-pycache

- base-ref: 60915a41ecc1e392eeb0ad44b296bc76a38609f8

- [x] 判据先行:`tests/test-delegate-entry.sh` 加"缓存不许骗过红检"那一幕,
      **单独 commit**(`60915a4`),提交时是红的(2 条)。
- [x] `bin/redcheck` 加 `purge_pycache()`,两处调用(退回后 / 恢复后)。
- [x] 红检:换回 HEAD 那版 redcheck ⇒ 69/2 红;装上修复 ⇒ 71/0 绿。
- [x] 全量回归(六套件,见 verify.md 的机器输出)。
- [x] 闸③ 亲读 diff。
- [x] full lane 评审 + 主裁。
- [x] 归档。

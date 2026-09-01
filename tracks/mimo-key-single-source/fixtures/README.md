# 对照组靶子

`switch-model.sh.pre-atomic` = 2026-09-01 第三轮评审**修复之前**那一版
(第一轮已把字面 key 改成运行时读源头,所以这份里没有任何 key;已核)。

留它是因为 `../switch-model-atomic-check.sh` 的红检需要一个**能跑的对照组**:
```
SWITCH_MODEL_SH=tracks/mimo-key-single-source/fixtures/switch-model.sh.pre-atomic \
  bash tracks/mimo-key-single-source/switch-model-atomic-check.sh
```
预期 **4 红**(⑤两条 + ⑥两条),而 ①②③④ 全绿 —— 这正是这次收紧的意义:
"写完之后内容对不对"那几条**看不见** truncate-then-write,只有 ⑤⑥ 看得见。
靶子放仓里而不是 scratchpad,是因为 scratchpad 会随会话消失,那样红检就没法复现。

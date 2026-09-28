# 任务

- [x] T1 确认 3.8 真存在:`agy models` 列出 `gemini-3.8-flash-high/medium/low`
- [x] T2 换档前先冒烟(不改代码,用 `AGY_MODEL` 覆盖):
      日志回显 `model: gemini-3.8-flash-high`、读得到仓库、两问答对、`Conclusion: PASS`
      收据 `/root/aiwork/logs/gemini38-smoke-20260904.log`
- [x] T3 `bin/subgemini` 默认档 3.7 → 3.8(含 usage 与 die 提示里的示例档同步)
- [x] T4 V46② 从"钉版本"改成"钉家族 + 真的传了"
- [x] T5 mutation M2 换靶:删掉 `--model "$MODEL"`(不含版本号,不会过期)
- [x] T6 🔴 变异红检:证明放松之后闸**仍然咬得住**
      —— 这一条是本单唯一的立身之本,没有它这单就是放水。
      ⚠️ 必须等 panel 的 gemini 腿跑完再跑:红检会改 `bin/subgemini` 本体,
      而改一个正在被执行的 bash 脚本会让它读到半截新半截旧。
- [x] T7 完整 `tests/test-review-tooling.sh` 全绿
- [x] T8 外部评审 2 腿(high)
- [x] T9 verify.md 收尾 + 归档

## 敞着

- `tests/test-track-record.sh:72` 的 `"google": ("subgemini", "gemini-3.7-flash-high")`
  **不改**:那是构造假 observation 的夹具数据,不是对真实默认档的钉子,
  换档不会让它过期。(查过才这么说的,不是推的。)
- ~~假 agy 的 models 输出仍只列 3.7~~ —— **已过期**:第一轮 DeepSeek F3 指出
  同一个文件里留着 3.7 字面量会让下个人误读成断言,已改成同时列 3.8 与 3.7。

# Tasks: panel-dead-leg-streak

- base-ref: 9dbf097b634e79d58030dd20d41302f000ef8eaa

- [x] 判据先行:连续硬失败要累计、跨阈值停止轮换(`9d48c17`,此刻 8 红)
- [x] 实现 + 文档(`d48e429`,V44 十一条转绿,红检 6 咬 0 漏)
- [x] panel 第一轮(subdeepseek 出 6 条;subglm 无裁决;控制器没活到收尾)
- [x] 判据先行第二轮 → 实现(`6ebc0e1` 7 红 → `e8c35cb`)
      🔴 其中最重的一条是**我自己把冷却弄死了**:health.tsv 从 3 列长到 6 列,
      而 `read -r _ status at` 会把多余字段连分隔符吞进 `at` ⇒ 冷却整个失效
- [x] panel 第二轮(四腿全审;submimo/subdeepseek/subglm 三个家族成功;subkimi 仍挂)
- [x] 判据先行第三轮 → 实现(`9c81553` 4 红 → `be1d08c`)
- [x] 红检补 M11–M15,并换掉两个过期锚点(M1/M2)
- [x] 两份最终收据:全量 476 条 0 红 / 红检 15 咬 0 漏(都在最后一次编辑之后)
- [x] verify + 主裁 PASS
- [ ] 归档

后续单(已开,不在本单做):
- `panel-kimi-credential-wipe` —— 有东西在反复清空 Kimi 凭证,根因不明
- `panel-my-review-path-lies` —— my-review 路径约定三处各写各的,两处会说假话

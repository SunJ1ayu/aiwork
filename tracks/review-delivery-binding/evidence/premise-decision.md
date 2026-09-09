# 前提探索与主裁决策

2026-09-09：三条真实外部腿均 rc=0。原始日志前缀 /root/aiwork/logs/explore-review-delivery-binding-host-20260909；此文件保存承重结论，不依赖流水日志存续。

- MiMo：可复算内容指纹，窄收口文件豁免；提醒收据形状未定义。接受指纹，拒绝宽泛 glob 和未知字段宽容解析。
- GLM：保存完整 path/mode/blob 清单，并固定工件声明。接受文件模式/增删必须承重；完整清单会重复每条腿且挤占 64 KiB 事件上限，本刀仅保留可复算摘要，不新增任意豁免清单。
- DeepSeek：规范化 track 移动位置、用同一实现生成和比较摘要。接受当前 track 的位置规范化；拒绝它提出的整个 evidence/、decision.json 排除（判据/风险决策可以藏在那里）。该腿自行读了本 track 的初步方向，独立性有限；两条其它腿提供独立对照。

选定：版本化、整仓内容指纹（不是 HEAD）。保留完整旧 subject，另增加绑定在其摘要内的 delivery 字段。只有本 track 的 verify.md、tasks.md 的勾选状态、decision.json 的 outcome，以及严格命名的机器收据/observation 属收口内容。设计/方案、风险字段、普通 evidence 文件和 track 内 oracle 均承重；模式/符号链接不得靠文件名豁免。当前 track 归档移动规范化，其它 track 不豁免。

迁移：新建 track 使用 decision v2；旧 v1 保留明确 legacy-unbound 历史语义，下一次真实 panel dispatch 升级到 v2。v2 不得回退 v1，归档必须有新 subject 的实际内容绑定。旧历史不会按今天源码重判。不能宣称 v1 历史具备新的绑定保证。

已知取舍：整仓任何非收口变化（包括其它任务）都会让绑定过期。没有依赖图，不猜“无关文件”；将来若实测重审成本过高，再设计显式交付范围。本刀不增加状态机、不跨 run 拼票。

自检反例：相同历史评审 + 修改 src 或 track 内 oracle 必须拒绝；只补机器收据/仲裁和归档移动必须保持；staged 不能拿 working 代答；缺绑定不能补预算；历史成功不能因为今天代码变化被改判。

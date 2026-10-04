# Design: rules-single-source

当前 review-pr 从目标项目快照的 refs/aiwork/main 读取规则和风险。新行为只把规则来源切到 GitHub 的 aiwork main，风险读取保持原样。

主 agent 的初始方向：用一个来源常量定义仓库和路径。先解析 aiwork main 的提交，再按这个提交读文件，任务书附完整 SHA，避免 main 两次读取间移动。通过 GitHub 公共只读 API 读取公开的规则，避免扩大现有 review App 的权限。读取失败立即退出，无备用规则。本地根目录规则不参与评审任务生成。

已核实：aiwork 是公开仓库；build 令牌覆盖两仓库，review 角色配置只覆盖目标项目，因此不能假定 scoped review token 可读 aiwork。公开 API 读规则不携带令牌；API 限流也须 fail closed。OpenDesign 原文源提交 498dc3cdd679a7855315159b3d1350a85b8a2a41。

这是跨仓库信任契约改变，先做不同家族的独立方案挑战。最危险前提：公开 API 可读性、规则和 SHA 的绑定、Project main 与 aiwork main 混淆。PR A 合并前线上 aiwork main 尚无规则；PR B 必须等其合并，不能在此前移除项目旧文件。

测试策略：对真实 main() 边界拦截 GitHub 公共 GET，保留来源读取实现；用临时 Git 仓库存项目 main 和 PR 的风险差异，捕获真实传给腿的任务书；断言来源 URL/ref/SHA/原文、目标仓库无旧规则、工作区诱饵无效和所有失败零派发/零发布。保留原有发布/模型归属/HEAD 检查。

独立挑战已完成：subcursor / grok-4.7-high，xai 家族。核实 refs/aiwork/main 是目标项目 main，不能复用为规则来源；公开读取不携带 review token，先固定提交再取普通文件的 base64 内容，验证解码及长度。公开 main 读取探针已通过。原始报告位于 Git 忽略目录，设计意见的可核实结论保留在此，不复制私人日志。保留当前任务书带 SHA 的约定；评审正文额外增加来源字段不属于本次要求，未引入新发布格式。

公开 Contents API 探针通过：按 aiwork main 提交读取普通文件，base64 解码字节长度等于 GitHub size。正式实现只接收普通文件、完整内容和有效 UTF-8；不携带 Authorization。

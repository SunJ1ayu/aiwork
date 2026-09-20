# Design: model-selection

## 主 agent 初始方向(独立意见之前)

调用通道和一次派发成员分离。建立可列出的候选目录,每项包含稳定ID、adapter、具体模型、支持模式、读仓能力、独立性分组与可得健康状态;额度未知保留null。
主裁选具体成员,派发时冻结名单与每成员参数。两个 Cursor 模型走相同 adapter,拥有不同成员ID和文件前缀。
复用 panel-review 的会话/结果/覆盖路径,不另造一套评审执行器。explore 从同一目录选能力匹配的项。
旧默认轮换保留兼容;显式选择不擅自替换或追加没选中的模型。现有归档0/1/2规则不变。
公司/通道/模型家族不同概念;本次不因为 Composer 与 Grok 名称不同而新增独立性承诺。

## 待查关键假设

1. 实际结果校验是否把 name 绑死 adapter?冻结模型能否防止同一家族换模型仍算成功?
2. 健康以通道为键,换模型是否误继承失败?共享额度未知是否会误报可用?
3. 旧roster重建、observation、slice是否依赖静态名单?动态成员必须仍能断线重建。
4. explore复用方式怎样最小且不把发散结果冒充review覆盖?
5. 能否在独立仓验收并合回,保留主仓其他会话的未跟踪文件?

独立挑战与最小实验完成后补最终设计和正式判据策略,此刻不开始实现。

## 独立挑战与核实

初始方向 commit=e9fafc8。Cursor/Grok(xai)读主仓快照,没有本track方向文件;首派沙箱unshare失败(rc78),宿主保留只读隔离重试成功。报告 evidence/design-challenge-grok.txt,brief同目录。
采纳:成员参数要冻结到本轮;旧roster不能用新名单改写历史;同家族多会话不增加覆盖;额度/模型可选不能混为一谈。
驳回:固定subcursor2和最多两个槽位仍违背任意选成员的用户目标;无需这个新限制。
驳回:所有Cursor quota失败一律传播到全部模型——Cursor存在不同额度池,没有足够事实支持这个动作。记录精确模型失败和通道历史提示,不猜共享余额。
纠正:现有predicate只比较facts自己的requested/invoked,不能发现同家族跑错目标模型。需把冻结expected model传入producer,不一致则不计覆盖。
实验证据:result-contract-probe.json验证不同name可共享adapter,两个同家族合格结果仍只算一个家族。现有20条result测试通过。

## 最终最小方案

- 新增只读panel-candidates CLI,从已有唯一roster读取adapter身份,补唯一能力元数据;按review/explore过滤。可选--discover-cursor查询CLI可选模型,不调用生成、不读取凭证、不宣称余额或成功登录。
- 新入口panel-review/panel-explore --members逗号名单。native使用现有名字/当前配置;Cursor使用subcursor@精确模型ID,同轮任意多个(上限由实际名单和证据尺寸限制,不造第二固定数字)。subcursor无@是当前配置的别名。每模型得到稳定成员名subcursor.<model>。
- 冻结选择产生spec与逐成员模型参数,复用review的独立会话/结果/observation。旧命令轮换/--all保持兼容;显式名单不与--all/--budget/scoped混用,不自动spare/chat回落。禁用/缺能力/缺可执行文件/预算家族不足在派发前拒绝。
- 显式explore经同一调度内核,独立contract=3,禁止track绑定,结果永不能冒充review覆盖。旧explore无--members保留兼容;新流程只使用目录+明确名单。
- roster优先用本轮plan的成员列表,老格式仍可读;plan标明mode与模型。动态Cursor健康按精确模型键,legacy通道历史只作提示不假定归属。
- 候选余额始终null,能力由adapter事实决定;不以公司名重定义现有家族predicate。Composer/Kimi等可能共享底座,现有family是粗粒度去重不是统计独立性保证,主裁仍判断。

## Oracle策略

主 agent 编写端到端桩测试:一个panel两个Cursor模型且相同subject/不同family、实际model不串、只选这些成员不轮换/补人、失败不替换、关停/坏选择派前拒绝、同族预算不虚增、explore隔离review覆盖、历史roster不依赖当前配置、只读目录不污染状态、未知quota不伪造、伪造同家族model事实不能计数。结合既有Cursor隔离、roster断线、observation/track/slice兼容判据。
完整runner当前基线已有test-low-uncertainty-reason.sh孤儿失败(旧撤回单);本单不伪造全绿、不顺带恢复旧闸,新套件正常注册。

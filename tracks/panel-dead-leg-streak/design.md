# Design: 连续硬失败计数 + 跨阈值停止轮换

## 改哪里

`bin/panel-review` 三处:

1. **`record_health()`** —— 现在写 `<leg>\t<status>\t<epoch>`,改成
   `<leg>\t<status>\t<epoch>\t<streak>\t<first_fail_epoch>`。
   - 读旧行拿到 prior streak(缺列 ⇒ 0);
   - `rc≠0`(status ∈ FAIL/quota/auth)⇒ `streak = prior + 1`,首次失败时间沿用或写当前;
   - 否则(PASS / DEGRADED / DEGRADED_INCOMPLETE / INCOMPLETE)⇒ `streak = 0`,首次失败时间清空。
2. **`recent_health()`** 旁边加 `dead_health()`:读第 4 列,`>= DEAD_STREAK` 就返回
   `dead:<status>:<streak>`。**它不看冷却**(冷却过了照样死)。
3. **选腿循环**:`dead_health` 命中 ⇒ `LEG_HEALTH[leg]="dead:…"`(于是不被选中,
   花名册按现有逻辑记 `SKIP(health:…)`),并在选择打印段落里输出一行 🔴 提示。

## 为什么阈值是 3 而不是 1

1 次失败就停轮换 = 把抖动当结构性故障,那会天天要人清,**变成新的噪音源**。
3 次连续同样失败,横跨至少两次冷却窗口(6h×2),已经不像抖动了。
阈值可调:`PANEL_HEALTH_DEAD_STREAK`(默认 3;设 0 关掉整个机制)。

## `--all` 怎么办

`--all` 现在会无视健康池冷却(显式全审)。**dead 也一并无视** ——
`--all` 的语义就是"我知道会失败,照派"。保持一致,不额外发明规则。

## 不做什么

- **不新造清除命令**:`PANEL_HEALTH_OVERRIDE=<leg>=healthy` 已经能强行放回,
  跑成功后 streak 自动清零。多一个命令就多一处要维护、要写文档、要写判据。
- **不做失败分类**(区分"结构性 vs 瞬时"):那要读错误文本猜意图,猜错就是误报。
  **重复次数本身就是最可靠的信号**,不需要猜。

## 最容易做错的地方(判据必须盯住)

🔴 `INCOMPLETE` 是 **rc=0** —— 腿产出了东西,只是裁决行没匹配上。
把它计入连续失败,会踢掉正在干活的腿(submimo 08-25 当轮就是 INCOMPLETE)。
判据 V44g 专门盯这一条。

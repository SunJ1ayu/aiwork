# Design: review-result-oracle-pins

- Change: review-result-oracle-pins
- Status: accepted

- 规划双出: 不适用(不是新写面;两条断言的形状由变异实验直接决定,没有方向分叉)。

## Approach

在 `ReviewResultTest` 里加两条测试,各自只改一个字段、其余保持完整合格:

1. `subject.source = None` / `digest = None`(其它一律完整)⇒ 断言
   `eligibility_reasons(...) == ["subject_unknown"]`。
2. `evidence = {completeness: none, ref: None, digest: None}`(其它一律完整)⇒ 断言
   `eligibility_reasons(...) == ["evidence_incomplete"]`。

两条都先过 `validate_result`(证明这不是一份非法记录,而是一份**合法但不该计数**的记录)。

## Key trade-offs / risks

- 用**相等**而不是 `assertIn`:代价是将来谓词加新理由时这两条会红,好处是它们再也搭不了便车。
  这个代价是想要的 —— 谓词加理由本来就该让人重新看一眼这两个场景。
- 不改实现 ⇒ 本单不可能改变归档放行行为;唯一风险是断言写错方向,由红检排除。

## Test strategy (oracle)

判据自己就是交付物。证明它咬得动只能靠**变异**:把被钉的那条理由从谓词里拿掉,
新测试必须红,而且红在新测试上、不是别处。

**这个 oracle 能被什么骗过?**

- 制造崩溃的变异会红在 TypeError 上 = 等于没红检过。所以红检要用"只静音这条理由、
  不制造崩溃"的公道变异(`reasons.append(...)` → `pass`),看它红成 FAIL 而不是 ERROR。
- 两条测试如果彼此的场景重叠(例如 subject 缺失顺带把 view 也弄没了),就会互相顶替。
  所以断言用相等而不是包含。

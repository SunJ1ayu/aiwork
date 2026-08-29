# Proposal: review-result-oracle-pins

- Date: 2026-08-30
- Status: open

## Goal

给 coverage 谓词补两条**单独钉住**的判据:`subject_unknown` 与 `evidence_incomplete`。
这一单不动任何生产代码。

## Motivation

2026-08-30 我对 P0(`review-result-v2`,GPT 代工)做独立复核时,拿 10 个变异打共享谓词,
8 个被判据咬住,**2 个没有**:把这两条理由从 `eligibility_reasons` 里删掉,整套判据仍然全绿。

## 真问题(第一性)

- 用户原话:「1可以补」(问的是"那 2 处考卷没盯住的地方,要不要现在补两个小测试")。
- 真正要解决的是:这两条不变量在实现里**是在的**,在判据里**是搭便车的** ——
  现实里 subject 缺失总和 view 不全结伴出现,证据不全总和进程失败结伴出现,
  于是任何一条被单独删掉都没人报警。搭便车的断言 = 下一个人重构时会安静消失的断言。
- 我在这中间翻译了什么:把"补两个测试"翻成"补两个**只可能因为这一条**而红的测试" ——
  断言要求 `eligibility_reasons` 恰好等于那一条,而不是"包含"。包含式断言会再次搭便车。

## Scope

- in: `tests/test_review_result.py` 新增两条单测;变异红检证明它们咬得动。
- in: 在已归档的 `review-result-v2/verify.md` 上补一段复核与署名说明(业主要求 2)。

## Non-goals

- 不动 `bin/_review_result.py` 或任何消费者:这两条检查本来就在,不是 bug 修复。
- 不动 P0 裁决:复核结论仍是 ACCEPT。
- 不扩 reviewer、不开 P1、不做跨-run 放行。

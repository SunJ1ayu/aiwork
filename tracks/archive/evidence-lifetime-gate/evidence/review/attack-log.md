# 攻题记录:evidence-lifetime-gate(gpt-5.6-sol 只读,派活前跑)

攻题任务书:attack-evidence-lifetime.md;完整输出:attack-console.log / attack-out.log
结论:我那 5 条自攻一条没命中真洞;它找出 9 条假绿路线 + 1 处规格错,全部已修进判据 v2(423a3eb)。
最致命:E9 非单变量 ⇒ 内联实现不建 helper 也能全绿;E7 收据正文不含 /tmp ⇒ 什么都没锚住。

oracle-sha256: 29acbfe27a4a1a7f5d89caf34fe8a22818f2590a9b5a8623f55b114f750cfbb1

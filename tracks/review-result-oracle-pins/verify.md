# Verify: review-result-oracle-pins

- Date: 2026-08-30

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

## Mechanical checks

- [x] build passes(本仓无独立编译产物;入口由总闸逐项加载执行)
- [x] tests pass
- [x] no secrets / unsafe ops(只动 tests/,零生产代码)

**机器打印的**(不是我的转述):

```
runlog: redcheck-mutation rc=0 commit=1beaa17 dirty=no at=2026-08-29T16:24:02Z file=tracks/review-result-oracle-pins/evidence/20260829T162402Z-01-redcheck-mutation.txt
runlog: full-regression-final rc=0 commit=8f00689 dirty=no final=yes at=2026-08-29T16:24:22Z file=tracks/review-result-oracle-pins/evidence/20260829T162422Z-01-full-regression-final.txt
```

红检那份是**变异**红检,不是"跑一遍看它绿不绿":两条新钉子各自被单独静音时,
必须打红**它自己那条测试**;基线未变异必须全绿(基线红了红检就是摆设)。
三项都印在收据里。

## Review

- 规格自查(先答):这一单的规格最可能错在哪?**断言用相等(`== ["subject_unknown"]`)
  而不是包含。** 代价是:将来谓词新增一条理由、或改一个理由的拼写,这两条会红,
  而红的原因跟被测的不变量无关。我仍然选相等,因为**搭便车这件事已经真发生了** ——
  实现里两条检查一直都在,判据却证明不了它们存在,正是因为"包含"允许它们躲在
  别的理由后面。真出现那种红时,正确的修法是**重新看一眼这两个场景还成不成立**,
  不是把断言放松回包含;这句话写在测试的注释里,不只写在这儿。
- 腿的花名册:**这一单没派外部腿**。业主的指令是 P0 复核完就进观测期、不额外派 panel,
  所以本轮零外审是**故意的**,不是漏了。它的后果是机械的:`impact.level=high` 要 2 个
  coverage-eligible 家族,归档闸现在就会 BLOCK —— 见 tasks.md 的 T4(归档押后)。
- findings(自审,做的过程中抓到的):
  - **我写的第一版变异红在 TypeError 上**:把 `if …: reasons.append("evidence_incomplete")`
    整段换成 `if False:`,后面那个 `elif verify_evidence:` 就拿着 `ref=None` 去算摘要 ⇒
    ERROR 而不是 FAIL。**红在崩溃上 = 等于没红检过**。改成只把 `reasons.append(...)`
    换成 `pass`(只静音这条理由、不制造崩溃),红这才落在断言上。红检工具里现在
    显式区分 FAIL 与 ERROR,后者当失败报。
  - **我自己的红检工具第一次自测是坏的**:我把脚本复制到仓外去跑"锚点故意写错"的
    反向对照,而脚本的 `ROOT` 是按自身位置算的 ⇒ 它抄不到任何文件、红在"基线就红了"
    上,根本没测到锚点那条路径。放回仓内重跑才真验到:锚点写错 ⇒ 报"锚点没命中",
    rc≠0。**两个方向都验过才算量具没坏。**
  - **我的红检工具里有一行 `cp … 2>/dev/null`**:它会把"少抄了 no-egress 守卫"
    变成"守卫没生效但判据照跑"——正是本机记过账的那种 fail-open。已去掉吞错。
  - 这一单**不动 `bin/_review_result.py`**:那两条检查本来就在实现里,不是 bug 修复。
    所以本单结构上不可能改变归档放行行为。
- arbitrated verdict (主裁): **PASS**。理由:交付物就是判据本身,而判据"有没有用"
  只有变异能回答 —— 两条钉子各自被单独静音都打红了自己那条测试(机器收据在上面),
  全量回归在干净树上 rc=0。**没有外部腿参与,这个 PASS 只到"这两条断言咬得动"为止,
  不是对 P0 的第二次背书。**

## Accepted deviations

- 本轮零外部评审(业主指令:观测期不额外派 panel)。后果已机械化:归档闸会拦,
  T4 明写押后,不靠人记。
- 复核 P0 用的另外 18 条对抗探针与 10 条谓词变异跑在仓外,只有其中"补钉子"这两条
  被固化进仓里(`tests/mutation-review-result.sh`)。仓外那些**不承重**:
  本单的结论只靠上面两份收据。

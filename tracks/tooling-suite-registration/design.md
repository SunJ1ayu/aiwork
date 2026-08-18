# Design: tooling-suite-registration

- Change: tooling-suite-registration
- Status: draft

- 规划双出: **不适用** —— 不是新写面,也不是开放方向。改动形态是"往一张已有的注册表里
  加一行",方向唯一;文件头自己写着「新增判据套件 = 往下面这张表里加一行」。
  verify 那边填的是 `self`,与该触发条件的口径一致。

## Approach

`bin/rust-check-review-tooling` 的 `SUITES=()` 数组末尾加一行:

```
  "evidence-lifetime|bash|/root/aiwork/tests/test-evidence-lifetime.sh"
```

格式与相邻十行完全一致(`名字|解释器|绝对路径`),不新增任何机制。

## Key trade-offs / risks

- **风险:名字进了名单 ≠ 它真的在跑。** 这是本单唯一实质风险,也是判据要问的唯一一件事。
  一条判据可以因为解释器不对、路径不存在、内部整块 SKIP 而"挂在名单上但什么都没验",
  而总跑汇总照样印一行绿 —— 老教训「汇总会撒谎,细节不会」。
  **所以验收口径不是"总跑 rc=0",是"总跑输出里点得到 evidence-lifetime 这一条,
  且它自己报了非零条数的用例"。**

- **取舍:不修"名单靠手列"这个结构病。** 见 proposal 的 Non-goals。
  额外记一笔在那儿没展开的:文件头那个漏网报告扫的是 `bin/` 里的可执行文件,
  而判据住在 `tests/` ⇒ **它结构上不可能报出本单这种空窗**。
  这不是它坏了,是它守的门本来就不是这扇。要堵得另起一单(触发器该是
  "`tests/` 里有可执行判据不在任何 SUITES 名单里"),本单不做。

- **本单不引入外网出口**:加的这条判据是离线桩判据,总跑文件头写明"只跑桩/离线套件,
  不做真供应商探活(不烧额度)",与 [[judging-must-have-no-egress]] 的不变量一致。

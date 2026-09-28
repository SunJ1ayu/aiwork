# Tasks: tooling-suite-registration

- base-ref: b033029

> 本单**没有委托**:改的是判卷防线的注册表,
> 硬规矩「oracle 永远由主 agent 亲自写,绝不外包」。

- [x] 1. `SUITES` 加一行 evidence-lifetime(08-17 就改在工作区里了,一直没提交)
- [x] 2. 亲跑 `bin/rust-check-review-tooling`,**在输出里点名**看到 evidence-lifetime
      这一条被跑到、且报了非零条数(不是整块 SKIP,不是只看 rc=0)
- [x] 3. 收据入 verify.md,commit `6425614`(track-guard 规矩4 放行:本提交带了 tracks/ 工件)
- [x] 4. 归档

# Tasks: review-result-oracle-pins

- base-ref: 7257520b2b357936a137b69f48adebab6e80c1b0

- [x] T1:写两条只可能因为单一理由而红的测试。
- [x] T2:变异红检(公道变异,红必须落在新测试上)。
- [x] T3:全量回归 + 归档说明补记。
- [ ] T4:归档 —— **故意押后**。这一单是 high/judging_control,归档要 2 个 coverage-eligible
      家族,而业主的指令是先进入观测期、不额外派 panel。等观测期里有一次真 panel 时再归。

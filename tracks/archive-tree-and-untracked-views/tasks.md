# Tasks: archive-tree-and-untracked-views

- base-ref: c503d046dd9d67dcdcc79c0742bbea5a7bc8b95c

> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。
> **本单不外包实现**:改的是判卷防线本身(`impact.factors=judging_control`),
> 而外部腿最可能的失败方式正是动判卷面。外部模型只在收口处以评审身份进场。

- [x] 亲跑探针复现 D15 / D16(不采信账本自述)→ `evidence/20260909T065614Z-01-probe-d15-d16.txt`
- [ ] 判据先行:T1~T8 写进 `tests/test_review_delivery.py`,**单独 commit**,并留红收据
- [ ] 实现 A:归档复验取"本次归档那棵树"(`bin/track-record`)
- [ ] 实现 B:归档后档案内交付内容变动可见(`bin/_review_delivery.py` 加 `scope`)
- [ ] 实现 C-1:`bin/track archive` 在 mv 之前拒绝"两视图不等",并列出差异路径
- [ ] 实现 C-2:`validate_review_delivery` 的 BLOCK 说真原因,删掉那句错药方
- [ ] 红检:`tests/mutation-review-delivery.sh` 每条新判据配一条"放松一格"的变异,
      基线先绿、变异红在被指名的判据上
- [ ] 回归:`tests/` 全跑一遍(不只是 delivery 那一份),收据入 evidence
- [ ] **真实路径亲验**:本单自己归档时走一遍 `track archive` + commit hook,
      把真实输出贴进 verify(夹具绿 ≠ 真实路径绿 —— 09-09 那次两条腿都没走到)
- [ ] ⚠️ 归档前确认仓里**无未跟踪文件**,否则本单自己会撞上 D16(它就是这么被发现的)
- [ ] panel-review(high ⇒ 2 个不同模型家族),主裁先落自审再读腿的输出
- [ ] 主裁仲裁写入 `decision.json`,PASS 则 `track archive`

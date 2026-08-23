# Tasks: panel-roster-from-disk

- base-ref: 0d68e7a

> 本单主 agent 自己干(`decision.json.execution_plan.adapter = main`)。
> 没派执行腿:难点全在进程组/会话语义上(哪一层被杀、哪一层活着),
> 而**最容易踩的那个坑正是"看起来对"的方案②** —— 弱腿极可能把写入点放回控制器,
> 判据能咬住,但返工成本比我自己写高。判据当然还是我亲自写。

## 立项

- [x] proposal:两次真事故(08-23 timeout / 08-19 死因不明),后果都是零记录
- [x] design:根因定位到 `panel-review:541`(退出码只活在控制器内存里)
- [x] 三个被否决方案写清楚,重点是**方案②「增量写」看起来对但修不好**
      —— 用 08-23 真实时间线证伪(控制器死在第一条腿交卷之前)
- [x] **前提探针**:两种杀法都验过,腿确实活得比控制器久
      `evidence/premise-probe-setsid-survival.md`
- [x] decision.json:impact=high(judging_control)/ uncertainty=low / adapter=main
      + `track-record validate --phase dispatch` 通过

## 判据先行(红着先单独 commit)

- [ ] 写 `tests/test-panel-roster.sh`,承重两条 + 防回归五条
- [ ] **R1 必须覆盖 `run_leg` 那条路**(subglm/subdeepseek)——08-23 真实挂掉的
      就是这条;只测 submimo 那条直路会漏掉半个 bug
- [ ] 红着 commit(此刻实现还不存在,必须全红)
- [ ] 挂进 `tests/test-review-tooling.sh` 总跑

## 实现

- [ ] `<prefix>.plan`:控制器**在派发前**落盘(选腿逻辑已经跑在 launch_leg 之前)
- [ ] `<prefix>.<leg>.state`:写入点塞进**每一次 `setsid --wait` 里面**
      (两条路径:`launch_leg` 直路 + `run_leg` 回落路,后者两份 state)
- [ ] `panel-roster <prefix>`:纯函数,读盘算花名册;控制器正常收尾时也走它
- [ ] 缺 state ⇒ 印"未收尾",**不许印 PASS、不许整行消失**

## 收口

- [ ] 红检:每条断言至少一个变异(删写入点 / 挪回控制器 / 缺失读成 PASS)
- [ ] 最终收据(跑在最后一次编辑之后,用 `runlog`)
- [ ] **`panel-review --all` 全员评审**(控制面,不是 high 的默认 2 腿)
      ⚠️ 讽刺但绕不开:要评审这个修复,得用这个正在坏的工具
- [ ] 主裁 + 归档

## 明确不做

- [ ] 不查 08-19 控制器的死因(本单做完之后它会自己留下证据)
- [ ] 不加 trap、不给控制器焊 setsid(见 design 的 ①③)
- [ ] 不改花名册**格式**(verify.md 里粘的那行必须逐字节还是老样子,判据 R5 守着)

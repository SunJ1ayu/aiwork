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

- [x] 写 `tests/test-panel-roster.sh`,承重两条 + 防回归五条
- [x] **R1 必须覆盖 `run_leg` 那条路**(subglm/subdeepseek)——08-23 真实挂掉的
      就是这条;只测 submimo 那条直路会漏掉半个 bug
- [x] 红着 commit(`9a5e832`,11 红 2 绿;收据 `evidence/…T051218Z-01-oracle-red-before-impl.txt`)
- [x] 挂进 `tests/test-review-tooling.sh` 总跑

## 实现

- [x] `<prefix>.plan`:控制器**在派发前**落盘(选腿逻辑已经跑在 launch_leg 之前)
- [x] `<prefix>.<leg>.state`:写入点塞进**每一次 `setsid --wait` 里面**
      (两条路径:`launch_leg` 直路 + `run_leg` 回落路,后者两份 state)
- [x] `panel-roster <prefix>`:读盘算花名册(**抬头的渲染时间戳除外**,它不是盘的函数
      —— 原话写的"纯函数"不准确,已在四处改准);控制器正常收尾时也走它
- [x] 缺 state ⇒ 印"未收尾",**不许印 PASS、不许整行消失**

## 第一轮评审之后补的(四条腿的发现 → 判据 → 修复)

- [x] **R9 增补腿不许隐身**(subdeepseek F1,HIGH,真回归):`.plan` 是派发前的快照,
      升级追加的腿只改了内存 ⇒ 真跑过的腿被印成 `SKIP(rotation)`,它的失败也一起消失。
      两头修:盘上有 state 即认定跑过 + 控制器往 `.final` 补最终 selected。
- [x] **R4 抹渲染时间戳**(subdeepseek F2):原版直接比原文,跨秒边界自己红 ——
      我那份"19 套件全绿"的收据是运气。
- [x] **state 原子落盘**(F3/A-2):`> $st.tmp && mv -f`。
- [x] **R10 全 off 那条路**(F4):实测本来就对,纯粹没人守 ⇒ 补守卫。
- [x] **R7d 不许断言死因**:这道闸自己犯了它要防的病 —— 把两条**活着的**腿印成
      `KILLED`。盘上信息区分不了"被砍"和"还在跑"。
- [x] **R11 组信号那条路**(线索来自 subglm agent 腿超时被砍前的日志):
      判据只测了"只杀控制器",没测"杀整个进程组";一个错误改法在旧判据下
      **21 条全绿放行**(对照组已复现)。红检 M11 咬它。
- [x] **红检工具自己坏了**:`mutate()` 把靶子当正则,`**整组**` 的 `*` 变量词 ⇒
      真咬住的变异被报成漏网。改 `grep -F` + 加"靶子名过期"自检(自身红检过)。
- [x] **判据去掉固定 sleep 改轮询**(subglm 指出;本机"判据自己会造抖动"的老账)。
- [x] **删死代码** `LEG=(setsid --wait)`(subglm 指出,零引用)。
- [x] ~~收紧 R5 的 norm~~ —— **对照组证伪**:整行替换只在匹配旧格式时发生,
      键名一改就不匹配、直接红,两种写法检出能力相同 ⇒ **已回退**,
      只留下它逼出来的红检 M12。

## 收口

- [x] 红检:每条断言至少一个变异(12 条,0 漏网)
- [ ] 最终收据(跑在最后一次编辑之后,用 `runlog`)
- [ ] **第二轮 `panel-review --all`**(第一轮跑过:控制器被 `timeout 120` 砍,
      零 observation、零 roster —— **正是本单要修的病,发生在评审本单的那一轮**;
      归档闸要的 exit_code=0 的 panel 运行因此不成立,必须重跑)
      ⚠️ 第一轮**跳过了 my-review 闸**;第二轮补了 `tasks/panel-roster-from-disk-my-review.md`
- [ ] 主裁 + 归档

## 明确不做

- [ ] 不查 08-19 控制器的死因(本单做完之后它会自己留下证据)
- [ ] 不加 trap、不给控制器焊 setsid(见 design 的 ①③)
- [ ] 不改花名册**格式**(verify.md 里粘的那行必须逐字节还是老样子,判据 R5 守着)

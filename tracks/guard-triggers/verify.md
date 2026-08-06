# Verify: guard-triggers

- Date: 2026-08-06
- Verdict: PASS(修复轮之后)

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes(纯 shell,`bash -n` 全过)
- [x] tests pass(六套件:260/17/retry/27/66/4,全绿)
- [x] no secrets / unsafe ops

## Review

- lane: full
  > **碰了新写口 / 权限 / auth / 钱 / 数据一致性 → full,针孔再薄也不打折**(硬规矩,别在这降档)。
  > fast = 主+1,中等风险;self = 主自审(闸③ + 截图 + 全量回归),
  > 限纯前端/纯观感、后端一字未动、只新增已过审针孔的调用方。
- 派给: 主 agent 直接干 —— 改的是守卫和反锚定闸本身(判卷防线),外包等于让考生改考场规则;
  判卷要造临时 git 仓 + 拷贝三条躯干,窄范围也说不清。
- 规格自查(读任何 panel 输出之前先答,全文在 scratchpad 的 my-review):
  规矩4 的名单是**手列**的,强度只等于这份清单(和 `--protect` 同病);
  7 天逃生口在本仓事实上常开(track 中心制,verify.md 几乎每个工作日都被碰)——
  所以规矩4 的真实强度**远低于它的字面语义**,它抓的是"连续多日零 track 活动还在改工具"
  那种气味,不是"每次改工具都必须挂 track"。这条我认,写在这儿而不是等腿来说。
- 腿的花名册: `submimo=PASS subdeepseek=PASS subglm=off subkimi=PASS`
  (原样粘自 `logs/panel-guard-triggers.roster`;**PASS 只表示进程 rc=0** —— 实际裁决是
  submimo BLOCK / subkimi BLOCK / deepseek PASS,这正是花名册那行注释警告过的读法陷阱。)
  > panel-review 收尾自己写这个文件(off / FAIL(rc) / 降级 都在里面)。
  > 08-06 立这条的理由:08-05 我在这里手写了"三条腿一致 PASS",而 Kimi 根本没出结论
  > (同一页第 90 行我自己还写着它没出报告)—— 手抄一份终端上的东西,抄错那次没人会发现。
- findings:
  - **我自审就写下的**(读腿之前):subkimi 没接闸"难看"、`realpath` 那处 fail-open 与
    别处 fail-closed 不一致、`PANEL_DISPATCH` 是伪装成机制的后门、规矩4 清单是手列的。
  - **四审把第一条顶成 HIGH 并判 BLOCK**(submimo + subkimi 两腿独立命中):
    commit 自称"盖住每一条评审路径"而默认开着的第四腿没接 = 目标与实现的实质落差。
    **我把它当"覆盖不全"、腿把它当"名不副实",腿是对的** —— 已修 + V23 覆盖 subkimi。
  - **subkimi 独家**:规矩4 名单漏了三处判卷防线自己(`bin/_my-review-gate.sh`、
    `tests/test_*.py`、`track/templates/*`)。第三处最狠:删掉模板里的 `lane:` 行,
    规矩2 当场成空文,而守卫一声不响。已补。
  - **subkimi 独家(真回归)**:`realpath` 的 fail-open 是我**下沉共享件时改松的** ——
    `panel-review` 原来那层没有这个洞。已改成 fail-closed。
  - submimo:老判据全局 `export REVIEW_NO_MY_REVIEW=1` 是脚枪 ⇒ 退成 26 个调用点各自关。
  - subkimi:`test-hooks-installed.sh` 在"一个仓都没查到"时 0/0 判绿。已修。
  - **判据自己的坑**:V23 那组在闸装上之前会真把 subkimi CLI 跑起来,判据卡了 10 分钟 ——
    卡住比红更糟(会拖死总跑)。已给每次调用套 `timeout 25`(卡住=红)。
  > 只写发现。腿的身份/降级不在这儿抄第二遍:日志自带身份牌(降级横幅 + 视野边界),
  > 花名册在上一格,查工件不查自述。
- arbitrated verdict (主裁): **PASS**。两腿 BLOCK 的理由全部成立且已修,判据同步补强
  (修复前红);六套件全绿。DeepSeek 那条 PASS **不作为通过依据** —— 它没命中 HIGH,
  说明这次是"孤腿(其实是两腿)对、单腿松"的老形状。
  > **归档时这一条和顶部的 `Verdict:` 都不许还是占位符**,`track-guard` 规矩3 会挡;
  > 没归档但已经合并上线的,`track list` 会打 ⚠️(stage-timer 就这么漏了两个月)。

## Accepted deviations

- **7 天逃生口常开**:本仓 track 中心制,verify.md 几乎每天被碰 ⇒ 规矩4 实际只在
  "连续 7 天零 track 活动"时硬挡。收窄成"本提交涉及的 track"会在同一 track 连改几次时
  误报,而误报的守卫会被 `--no-verify` 绕过 —— 现在这版是知情取舍,不是没想到。
- **`PANEL_DISPATCH=1` 仍是零成本后门**(未文档化的内部标记)。已加一行留痕:
  用它跳过闸、而自审文件确实不存在时,stderr 会说一句。它是自律件不是安全边界。
- **explore 当 review 用可以软绕过**(闸只认 review 模式);`panel-explore` 那条路
  完全没有闸 —— 既有状态,不在本单范围。
- **规矩4 的名单仍是手列的**,新起一个不匹配前缀的工具名照样漏。做成"凡 bin/ 可执行文件"
  会把运维脚本拖进来 ⇒ 误报。这是清醒的取舍,也是这条规矩最可能失效的地方。

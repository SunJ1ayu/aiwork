# Verify: panel-dead-leg-streak

- Date: 2026-08-25

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明,不复制枚举。

## Mechanical checks

- [x] build passes(纯 bash 工具,无构建步骤)
- [x] tests pass —— 全量 476 条 0 红
- [x] no secrets / unsafe ops(runlog 自带密钥形状扫描;本单不碰网络/凭证/权限)

**机器打印的**(不是我的转述):

```
runlog: oracle-full rc=0 commit=d48e429 dirty=yes final=yes at=2026-08-25T06:19:59Z file=tracks/panel-dead-leg-streak/evidence/20260825T061959Z-01-oracle-full.txt
runlog: redcheck rc=0 commit=d48e429 dirty=yes final=yes at=2026-08-25T06:23:01Z file=tracks/panel-dead-leg-streak/evidence/20260825T062301Z-01-redcheck.txt
runlog: oracle-full-r2 rc=143 commit=e8c35cb dirty=yes final=yes at=2026-08-25T06:46:25Z file=tracks/panel-dead-leg-streak/evidence/20260825T064625Z-01-oracle-full-r2.txt
runlog: redcheck-r3 rc=0 commit=30eb506 dirty=yes final=yes at=2026-08-25T08:50:25Z file=tracks/panel-dead-leg-streak/evidence/20260825T085025Z-01-redcheck-r3.txt
runlog: oracle-full-r3 rc=0 commit=30eb506 dirty=yes final=yes at=2026-08-25T08:52:30Z file=tracks/panel-dead-leg-streak/evidence/20260825T085230Z-01-oracle-full-r3.txt
```

**最后跑的那一遍** = `oracle-full-r3`(commit `30eb506`,即最后一次编辑之后),
`476 passed, 0 failed`,`source-stable: yes`。红检最终一遍 `redcheck-r3`
`咬住 15,漏网 0`、被变异文件逐字节还原、`source-stable: yes`。

### 🔴 跑红的那一遍,逐字节贴在这儿(规矩 5b,不许四舍五入成散文)

```
---------------- 输出开始 ----------------
command-rc: 143
head-after: e8c35cba1e7d9ea2152975fdb30ff65ea6fb7fb5
source-view-after:  sha256:bfb536e582b73fb000ce0966ccae2bdcccc1cfe115af20ca95850aa3e507b00b
source-stable: yes
---------------- 输出结束 ----------------
runlog: oracle-full-r2 rc=143 commit=e8c35cb dirty=yes final=yes at=2026-08-25T06:46:25Z file=tracks/panel-dead-leg-streak/evidence/20260825T064625Z-01-oracle-full-r2.txt
```

`rc=143` = SIGTERM,断线正砍在这一遍中间;输出区**一行测试结果都没有**。
而 commit `e8c35cb` 的标题写着「V44 二十条全绿,红检 10 咬 0 漏」——
**当时树里没有任何收据支持那句话**。今天重跑亲证那两个数字属实
(subdeepseek 与 submimo 两条腿也各自独立复跑确认),
但那不改变"当时那句话是无凭的"这件事。半截收据不当绿用,**也一份不许藏**。

### - 无机器证据:三次「判据先行、此刻 N 红」的红态没有 runlog 收据

`9d48c17`(8 红)/`6ebc0e1`(7 红)/`9c81553`(4 红)三次红态,我是用裸
`bash` 跑的,没走 `runlog` ⇒ **git 历史里证明不了"红过"**,只有 commit 标题在自述。
这正是本仓立 `runlog` 要治的那种病(汇总会撒谎,细节不会),而我在自己这一单里犯了三次。
**下一单起:判据先行那一遍也走 runlog。** 这条已记进结论栏的工艺账。

## Review

### 规格自查(读任何 panel 输出之前先答)

如果规格本身就是错的,会错成什么样?最可能的两种:
① **把"要人动手"和"会自愈"混为一谈** —— quota / 429 连续 3 轮也会被判死,
而它本来 6 小时就好了。我当时的缓解是"提示里印最早一次的时间,人一眼分得出"。
② **阈值 3 的理由是编的** —— 我写的是"横跨至少两个冷却窗口,已经不像抖动"。
**这一条后来真的被打穿了**(见 F1):它只在普通轮换下成立,`--all` 路径上整个是假的。
我自己没发现,是 subdeepseek 量出来的 —— **规格里那句"因为"是我推出来的,不是量出来的**。

### 腿的花名册(原样粘自 `.roster`,没手写)

```
# panel-review 花名册(2026-08-25 16:28:33)task=panel-dead-leg-streak-r2
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=high requested-budget=4 selected-count=4
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent),subglm(zhipu/subglm-agent),subkimi(moonshot/subkimi)
# escalation=none
# snapshot=head:e8c35cb
# 日志:logs/panel-dead-leg-streak-r2-20260825T081344Z.*.log
submimo=PASS(verdict=UNKNOWN) subdeepseek=PASS(verdict=PASS) subglm=PASS(verdict=NEEDS_MORE_INFO,降级:回落聊天腿,只看得见 diff) subkimi=FAIL(rc=1)
```

**第一轮(`panel-panel-dead-leg-streak-20260825-142417`)没有花名册文件** ——
控制器没活到收尾(腿焊了 `setsid`,控制器没有),用 `panel-roster <前缀>` 从盘上重建;
observation **重建不出来**,所以第一轮那份不存在。第二轮给外层套了 `setsid --wait`,
控制器活到最后,`.final` / `.roster` / observation 三样齐全。

### findings

**落地的(都先有红判据,再有实现):**

- **F1 [MEDIUM,subdeepseek]`--all` 压缩掉了定阈的全部依据。**
  `--all` 绕过冷却,而 `record_health` 对任何被派发的失败都 +1 ⇒
  「连续 3 轮横跨至少两个冷却窗口」在这条路上整个是假的。我亲手复现:
  冷却 3600s,三轮 `--all` 在 **1 秒**内把 streak 顶到 3,第四轮普通轮换当场判死。
  ⇒ 改成"第 n 次计入要求距最早那次已过 (n-1) 个冷却窗口"。V44r + 对照组 V44s。
  **这是本轮最值钱的一条:它打穿的正是我自己写在设计里的那句"因为"。**
- **F2 [三方独立命中] 派不满风险预算这件事从来没被说出来过。**
  (我自审 M1 / submimo「无人值守 CI 只看 rc」/ subglm「高风险欠配额静默放行」)
  ⇒ `selected < RISK_BUDGET` 时打一段 🔴「家族覆盖不足」。V44u。
  用 `RISK_BUDGET` 而不是 `REVIEW_BUDGET`:`--all` 顶到 4 之后一条腿 off 就报"不足"
  是误报,**而误报会逼出绕开它的习惯**。
- **F3 [我 M2 + subdeepseek F3 独立命中] 已经 override 放回了,它还在叫你去 override。**
  打印段直接读 health 文件、不看 override。⇒ 改口。V44w。
- **F4 [四方独立命中:我 M5 + subdeepseek F2 + submimo + subglm] 回滚会静默废掉所有冷却。**
  旧版 `read` 写法读 6 列行 ⇒ 冷却对每条腿失效,不崩、没声音。
  ⇒ SKILL.md 写明「回滚前先清空 health.tsv」。**只改文档,不为它加代码。**
- **F5 [subdeepseek F4] 红检缺一个变异:选腿循环那道健康闸本身。**
  M1–M10 变异过计数器/冷却/阈值/显示/日志路径,唯独没变异过它。⇒ 新增 M15。
- **F6 [subdeepseek F5 + subglm 独立命中] 树里的收据不支持 commit 标题。**
  已按规矩 5b 逐字节入库并在上面认账,两份最终收据重跑。

**读了但没照做的(写下理由,不躲):**

- **submimo「把 auth/quota 写进死腿提示」—— 已经是这样了。** 代码印的就是
  `最近一次:$_dstatus`,它在自己的桩里只见到 `FAIL` 就以为只有 FAIL。**不改。**
- **subglm「改成按错误签名相同才计数」** —— 是个像样的替代方案,不做。理由:
  错误串普遍带时间戳/路径/request-id,要"逐字相同"就得先归一化,而归一化=猜,
  猜错就是误报 —— 那正是这版刻意避开的东西。而 F1 的修法(按时间摊开)**不看文本、
  照样挡住共模瞬态**,把它想解决的问题解掉了大半。
- **subglm「空池会怎样?会不会静默跑 0 条腿」** —— 我量了:**现状已经是 rc≠0 + 0 条腿
  + 四条 🔴 提示**。它看不到代码(降级成聊天腿、diff 又是空的),问得合理但答案是"没这回事"。
  加了 V44t 把这个现状钉住。
- **并发写 `health.tsv` 无锁**(我第一轮 F-B):存量问题,丢失方向是 streak 变小 ⇒
  只会让机制变迟钝,**不会误踢腿**。不在本单修。
- **打印段 `dead_health` 调了两次**(submimo):纯冗余,不改。

### 🔴 我自己被抓到的两处

1. **我在自审 M1 里把话说过头了。** 我写「三条腿被判死时屏幕上唯一的痕迹是
   `requested-budget=2 selected=1` 这行数字」,而我自己那次实测**四条 🔴 提示全打了** ——
   是我引用时把它们截掉了。subdeepseek 和 subglm **各自独立**指出这处不自洽
   (subglm 的原话:"两句话必有一句不真")。真正缺的不是"任何痕迹",
   而是**"这轮没凑够 high 要的家族数"这句话本身** —— F2 修的是后者。
   ⇒ 自检句:**我引用自己实测输出的时候,截掉的那几行是不是正好是反驳我的那几行?**
2. **proposal 里有一句假话:**「subkimi 08-25 业主一问、两分钟就修好了」。
   实测不成立:业主 13:56 登录过,**16:06 那个文件又变回 `{}`**,16:13 那轮仍是同一句报错。
   不是"忘了登录一次",是**有东西在反复清空它**,根因不明。已改写 proposal 并开
   后续单 `panel-kimi-credential-wipe`(附证据与已排除项)。

### arbitrated verdict(主裁)

**PASS。** 理由:

- 机制本身经三轮打磨,**最后一轮打穿的是我自己设计里那句没被量过的"因为"** ——
  这正是 panel 该抓而我抓不到的东西(规格错的时候,四腿齐 PASS 也不证明题是对的;
  这次它没齐 PASS,它把题面的一个前提证伪了)。
- 家族覆盖:high 要 2 个不同家族成功,实际 **3 个成功**(mimo / deepseek / zhipu-降级),
  kimi 那条 FAIL 已按上面认账并单独开单。
- 判据 476 条 0 红、红检 15 咬 0 漏且两份都是最后一次编辑之后跑的、`source-stable: yes`。
- **这套机制的第一个真实客户当场就出现了**:16:28 那轮收尾后 `health.tsv` 里
  subkimi 第一次真的记上 `FAIL … streak=1`,而同轮 INCOMPLETE 的 submimo 与
  DEGRADED 的 subglm 都是 `0` —— 设计里最怕做错的那一条,在真实数据上是对的。

## Accepted deviations

- **控制器被砍那一轮,整轮健康账不落地。** `record_health` 在所有腿 `wait` 完之后
  由控制器顺序调用;控制器死了就一条都不写。**本单自己就是活例**:14:24 那轮
  subglm rc=1,而 health.tsv 里它至今是那轮之前的状态。
  不修的理由:本单要治的病(subkimi 7 秒失败、控制器活得好好的)不受影响;
  "控制器为什么会死"是本仓另一笔敞着的账(08-19 / 08-23 各记过一次),
  在这儿顺手修等于把两件事搅在一起。**但它不许被默认成"没有"。**
- **`auth` 分类正则过宽**(`|auth|` 会命中任何含 auth 的日志,例如 subdeepseek
  那句无关的 `another auth source is set`)。存量行为,但新提示第一次把这个标签
  **当成给人的诊断**印出来。低优先,记在这儿,没开单。
- **`quota` 也计数**:额度会自愈,连续 3 轮 quota 会被停轮换。缓解:提示印最早一次时间,
  且 F1 之后这三轮至少摊开两个冷却窗口(不再是几分钟内的三连发)。有意保留。
- **并发写 `health.tsv` 无锁**:存量,丢失方向只会让机制迟钝,不会误踢腿。

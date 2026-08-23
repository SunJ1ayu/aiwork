# Verify: panel-roster-doc-sync

- Date: 2026-08-23

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录
> `decision.json`；这里保留检查、理由、发现与主 Agent 仲裁说明，不复制枚举。

## Mechanical checks

- [x] build passes(纯 shell,无构建)
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述):

```
runlog: bash rc=0 commit=2d9b076 dirty=yes at=2026-08-23T11:11:17Z file=tracks/panel-roster-doc-sync/evidence/20260823T111117Z-01-bash.txt
runlog: bash rc=0 commit=2d9b076 dirty=yes at=2026-08-23T11:11:39Z file=tracks/panel-roster-doc-sync/evidence/20260823T111139Z-01-bash.txt
runlog: tooling-suite-after-docfix rc=0 commit=2d9b076 dirty=yes at=2026-08-23T11:18:21Z file=tracks/panel-roster-doc-sync/evidence/20260823T111821Z-01-tooling-suite-after-docfix.txt
```

- 第 1 行 = 判据 `tests/test-panel-roster.sh`:**PASS=34 FAIL=0**
- 第 2 行 = 红检 `tests/mutation-panel-roster.sh`:**咬住 17 条 / 漏网 0 条**
- 第 3 行 = 全套件 `bin/rust-check-review-tooling`:19 个套件全绿(workflow-docs 32、
  evidence-lifetime 41、review-tooling 449 …)

**跑红/作废的那几遍,一份都没藏**(规矩 5b):

- `20260823T103256Z-01-redcheck-with-r12f.txt` —— R12f 落地那一遍的红检(16 条)。**已过期**:
  本轮把 R12f 断言名改准、M17 靶子同步,现为 17 条,以上面第 2 行为准。
- `20260823T103909Z-01-tooling-suite-r12f.ABORTED.txt` —— **半截收据,不作数**。
  断线砍在正中间,保留不删(半截是线索不是垃圾),重跑见下一份。
- `20260823T104145Z-01-tooling-suite-r12f-rerun.txt` —— 上面那份的重跑,全绿。
  **已过期**(跑在本轮文档修正之前),以上面第 3 行为准。

## Review

- **规格自查(读任何 panel 输出之前先答)**:本单的规格是"把这一单改变的事实,在它被复制到的
  每一处都改准"。**它最可能错成这样:我声称的"全盘扫描"根本没盖住全盘。**
  事前它已经错过一次 —— 第一轮用 `grep --include=*.md --include=*.sh`,而 `bin/` 下的工具
  全是无扩展名脚本 ⇒ 半个仓没进搜索范围。第二轮改用零过滤 `git grep` 才捞回三处。
  **怎么发现:对每一处"已改准"的措辞,反过来再全仓搜一次它的旧写法,搜到 0 条才算完。**
  (这一条自查在本轮真的兑现了,见 F1/F2/F3 与我自己捞出的第四处。)

- **腿的花名册**(这一轮控制器没活到收尾、`.roster` 压根不存在,以下是
  `panel-roster /root/aiwork/logs/panel-docsync2-0823` 从盘上**事后重建**的,不是手写):

```
# panel-review 花名册(2026-08-23 19:03:20)task=panel-roster-doc-sync
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=high requested-budget=4 selected-count=4(派发前快照)
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent),subglm(zhipu/subglm-agent),subkimi(moonshot/subkimi)(派发前快照,.final 缺失时不含升级追加的腿)
# escalation=unknown(没有 .final:控制器没活到收尾,或仍在跑)
# snapshot=head:2d9b076
# 日志:/root/aiwork/logs/panel-docsync2-0823.*.log
submimo=PASS(verdict=UNKNOWN) subdeepseek=PASS(verdict=BLOCK) subglm=未收尾(无 state:被砍或仍在跑) subkimi=FAIL(rc=1)
```

  > **这一行本身就是上一单的验收在真实场景里的第一次兑现**:本轮控制器被断线砍死,
  > 整轮零记录,而四条腿的日志完整躺在盘上 —— 一条命令重建出了花名册。
  > 按新规矩,`PASS` 只是 rc=0:`verdict=UNKNOWN` 与"未收尾"两种**都开日志确认过了**,
  > 没有当结论用。
  > 第一轮(`panel-docsync-0823`)另有花名册:三条腿在健康冷却里被 SKIP,只有
  > subdeepseek 真跑;第二轮用 `--all` 才把四条全推出去(`--all` 无视冷却)。

### findings

**评审腿提的(逐条对代码验证过,不取自述):**

- **F1(HIGH,subdeepseek)成立 —— 已修。git 索引与工作树对同一事实各持一份。**
  索引里 `workflow/skills/panel/SKILL.md:83` 与 `track/templates/verify.md:38` 还是第一轮的
  "逐字节一致",工作树才是修正后的"归一化后一致";而 `bin/panel-review` 三处修正、R12f、M17
  全都只在工作树。**裸 `git commit` 会提交旧版并丢掉整个第二轮。**
  我亲验了两份 `git show :<path>` 与工作树的差异,腿说的属实。
  > 它还答对了"为什么重扫没抓到":零过滤 `git grep` 查的是工作树,**索引里的旧版对它隐形**。
  > 这是第三种漏法,前两种是 `--include` 过滤和 untracked 文件。
- **F2(MEDIUM)成立 —— 已修**:`tracks/panel-roster-doc-sync/verify.md` 从模板复制时把旧措辞
  带了进来(本轮整份重写,已消失)。**修这个病的单子自己又生了一份副本。**
- **F3(MEDIUM)成立 —— 已修**:`tracks/archive/panel-roster-from-disk/verify.md:95` 的结论句
  改准为"归一化后一致",并注明是 2026-08-23 的更正。
- **F4(LOW)成立 —— 已修**:R12f 的门是**日期邻近**,不是**时态**。断言名原本自称
  "现在时陈述=过期文档",而它实测放行带日期的现在时陈述、误伤不带日期的历史陈述。
  已改名为"bin/ 里的 KILLED 行,上下两行内必须有四位年份",并在注释里写明它是
  **启发式代理指标**。别让闸许诺它给不了的东西。
- **F5(LOW)成立 —— 已修**:`design.md` 把边界说大了一半。四处里有两处(roster 重建那句)
  其实由 R5b 守着,真正裸奔的只有 my-review 路径与 `--all` 冷却两句。已改准并记为明账。
- **F6(LOW)成立 —— 已修**:`tests/test-panel-roster.sh:117` 注释引用了**不存在的**断言名
  R7a/R7c。
- **submimo 的建议(可追溯)采纳一半**:`--all` 那句补了出处日期与"读代码读来的、无机械判据"。
  不新建标签体系 —— 那会再造一份要同步的副本,正是本单在治的病。

**腿没提、我自己扫出来的(所以腿的清单也不是全的):**

- **第四份副本长在判据的断言名里。** `tests/test-panel-roster.sh:150/152`:R5 自称
  "与格式基线**逐字节一致**"、R5b 自称"与控制器当场写的**完全一样**",而两条的实现
  `diff <(norm …) <(norm …)` **两边都过 `norm`**。三条腿一条都没点它。
  最该准的地方(判据的断言名)反而错着 —— 已改准。
- **归档 design.md 里还留着被推翻的合格写法**:`archive/panel-roster-from-disk/design.md:130`
  写着 R7 "必须印成'未收尾/**KILLED**'",而同一单后半程加的 R7d **专门禁止** KILLED。
  归档工件我**不改写正文**(那是当时的决定,改了就毁掉"当时想的是什么"),就地加更正注。
- **"被砍或仍在跑"不是穷举 —— 今天当场撞见第三种。** 见下面 subglm。

### subglm 那条"未收尾"的腿:查到哪儿为止

花名册印的是"无 state:被砍或仍在跑",而**两种都不是**。盘上证据锁住的区间:
它 18:46:33 写完日志头,之后零输出、`.log.err` 0 字节、既无 `.state` 也无 `.agent.state`;
它的工作副本已不在 `aiwork-review-workspaces` 下;`opencode` 自己的 HOME 最后写入停在 13:51,
**本次零痕迹** ⇒ 它死在"印完日志头之后、opencode 启动之前"那一段,压根没走到
`session_run` 的落盘。

**死因仍未定,我不写进结论。** 已排除的三条(都是我先提出、又被我自己证伪的):
OOM(dmesg 最近一次 8-21)、磁盘满(77%,余 11G)、disk-watch 杀进程(它根本不含 kill)。
> 这条留成**敞账**。上一单的敞账"控制器为什么死"至今也没结 —— 不假装它结了。

### 撞出来的新账:observation 不能从盘上重建

上一单把**花名册**变成了盘的函数,但 `panel-review` 的 **observation**(归档闸据以核对
"high 覆盖了 2 个不同模型家族"的那份 JSON)**仍然是控制器内存的函数** —— 控制器死了就没有。
本轮真实发生:第二轮 submimo(xiaomi)+ subdeepseek(deepseek)两条腿都 rc=0,
盘上 state 俱在、花名册重建得出来,但 observation 只有第一轮那份**单腿**的。
**同一个病治好了一半。** 已记为明账,单独开单,不在本单夹带。

## Accepted deviations

- **本单的家族覆盖靠第一轮 + 第二轮合起来看**:第一轮 observation 只有 subdeepseek 一条腿
  (另三条在健康冷却里被 SKIP),第二轮的两条成功腿因控制器被砍没有 observation。
  花名册与四条腿的日志是完整的,**证据本身不缺,缺的是那份 JSON**。
- 两句裸奔文档(my-review 路径 / `--all` 冷却)可机械化但本单不做 —— 会再开两处断言副本。
- `logs/` 553MB / 1107 文件无人清:既存账,删文件是危险操作,要业主点头,另开一单。

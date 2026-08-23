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
runlog: oracle-final rc=0 commit=debf862 dirty=yes at=2026-08-23T11:48:27Z file=tracks/panel-roster-doc-sync/evidence/20260823T114827Z-01-oracle-final.txt
runlog: redcheck-final rc=0 commit=debf862 dirty=yes at=2026-08-23T11:48:40Z file=tracks/panel-roster-doc-sync/evidence/20260823T114840Z-01-redcheck-final.txt
runlog: suite-final rc=0 commit=debf862 dirty=yes at=2026-08-23T11:54:43Z file=tracks/panel-roster-doc-sync/evidence/20260823T115443Z-01-suite-final.txt
```

- 判据 `tests/test-panel-roster.sh`:**PASS=34 FAIL=0**
- 红检 `tests/mutation-panel-roster.sh`:**咬住 17 条 / 漏网 0 条**
- 全套件 `bin/rust-check-review-tooling`:**19 个套件全绿**

> 最终收据之后我只改过**一个仓外文件**(`/root/panel-my-reviews/` 下的 my-review 副本,
> 见 F7)。仓内判据一行都读不到它,所以没有重跑 —— 这句话本身可被推翻:
> 若认为它承重,重跑一遍即可。

**跑红 / 作废 / 已过期的那几份,一份都没藏**(规矩 5b):

- `20260823T103256Z-01-redcheck-with-r12f.txt` —— **已过期**(16 条,当时 R12f 刚落地)。
- `20260823T103909Z-01-tooling-suite-r12f.ABORTED.txt` —— **半截收据,不作数**。
  断线砍在正中间,保留不删(半截是线索不是垃圾)。
- `20260823T104145Z-01-tooling-suite-r12f-rerun.txt` —— 上面那份的重跑,全绿,**已过期**。
- `20260823T111117Z / 111139Z / 111821Z` 三份 —— 全绿,但跑在本轮最后三次修正之前,**已过期**。
- 以上每一份都被上面那三行**最终收据**取代;数字以最终那三份为准。

## Review

### 规格自查(读任何 panel 输出之前先答)

本单的规格是"把这一单改变的事实,在它被复制到的每一处都改准"。
**它最可能错成这样:我声称的『全盘扫描』根本没盖住全盘。**

**这个预判在本单里兑现了四次**,每次漏法都不同:

1. `grep --include=*.md --include=*.sh` 漏掉 `bin/` 下的无扩展名脚本(第一轮,评审腿抓到);
2. **git 索引与工作树各持一份** —— `git grep` 查的是工作树,索引里的旧版对它隐形(F1);
3. untracked 文件不在 `git grep` 范围(F2);
4. **仓外的副本** —— `/root/panel-my-reviews/` 下那份,前三次搜索全都只扫了 `/root/aiwork`(F7)。

**结论:"我搜过了"和"我搜的范围盖住了要找的东西"是两件事,而前者读起来像后者。**
本单之后仍然没有机械闸守这件事(R12f 只守 `KILLED` 一个词、`bin/` 一个目录),
这是本单**没有治好**根因的诚实交代,不是"已解决"。

### 腿的花名册

**第二轮**(`panel-docsync2-0823`):控制器被断线砍死,`.roster` 压根不存在,
以下由 `panel-roster` 从盘上**事后重建**,不是手写:

```
# panel-review 花名册(2026-08-23 19:03:20)task=panel-roster-doc-sync
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# impact-risk=high requested-budget=4 selected-count=4(派发前快照)
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent),subglm(zhipu/subglm-agent),subkimi(moonshot/subkimi)(派发前快照,.final 缺失时不含升级追加的腿)
# escalation=unknown(没有 .final:控制器没活到收尾,或仍在跑)
# snapshot=head:2d9b076
submimo=PASS(verdict=UNKNOWN) subdeepseek=PASS(verdict=BLOCK) subglm=未收尾(无 state:被砍或仍在跑) subkimi=FAIL(rc=1)
```

> **这是上一单的交付物在真实场景里的第一次兑现**:整轮零记录,一条命令重建出了花名册。

**第三轮**(`panel-docsync3-0823`,为补齐 observation 家族覆盖而跑,控制器活到了收尾,
以下是它自己写的 `.roster`):

```
# panel-review 花名册(2026-08-23 19:45:05)task=panel-roster-doc-sync-r3
# impact-risk=high requested-budget=4 selected-count=4
# escalation=none
# snapshot=head:5c3b4d8
submimo=PASS(verdict=UNKNOWN) subdeepseek=PASS(verdict=NEEDS_MORE_INFO,降级:回落聊天腿,只看得见 diff) subglm=PASS(verdict=NEEDS_MORE_INFO,降级:回落聊天腿,只看得见 diff) subkimi=FAIL(rc=1)
# ⚠️ 评审期间 HEAD 从 5c3b4d8 移到 debf862 —— 各腿未必评的同一棵树。
```

### ⚠️ 第三轮有两处污染,是我自己造成的,先声明再引用它的结论

1. **anchor leak**:控制器开跑时就警告了 —— 我的 `verify.md` 会随整份 diff 内联进每条腿。
   ⇒ 腿的"同意"要打折,**只有它们的新发现才算数**。
2. **评审期间我 commit 了**(HEAD 5c3b4d8 → debf862,就是那次撤回)。控制器明说
   "受影响就重跑,别拿它当 finding"。submimo 跑在旧树上、两条降级腿跑在新树上。
3. **两条 agent 腿都 900s 超时后回落聊天腿**,而改动已经 commit ⇒ 它们看到的
   `git diff vs HEAD` 是**空的**。它们如实答"证据不足,无法回答"(NEEDS_MORE_INFO)
   而不是装懂 —— **这是正确行为**,但对本轮实质贡献为零。

⇒ **第三轮真正有视野的腿只有 submimo 一条。** 它抓到了一处真漏网(F7)。

### findings

**评审腿提的(逐条对代码验证过,不取自述):**

- **F1(HIGH,subdeepseek)成立 —— 已修。git 索引与工作树对同一事实各持一份。**
  索引里 `SKILL.md:83` 与 `verify.md` 模板还是旧的"逐字节一致",工作树才是修正版;
  `bin/panel-review` 三处修正、R12f、M17 全都只在工作树。
  **断线把工作区停在这个状态,我接上时一次裸 `git commit` 就会提交旧版并丢掉整个第二轮。**
  我亲验了 `git show :<path>` 与工作树的差异,属实。**这是本轮拦下的唯一一次真事故。**
- **F2(MEDIUM)成立 —— 已修**:新 track 的 `verify.md` 从模板复制时把旧措辞带了进来。
  **修这个病的单子自己又生了一份副本。**
- **F3(MEDIUM)成立 —— 已修**:归档 `verify.md:95` 的结论句改准并注明更正日期。
- **F4(LOW)成立 —— 已修**:R12f 的门是**日期邻近**不是**时态**,断言名与注释改准,
  并写明它是**启发式代理指标**。别让闸许诺它给不了的东西。
- **F5(LOW)成立 —— 已修**:`design.md` 把边界说大了一半 —— 四处里两处其实由 R5b 守着。
- **F6(LOW)成立 —— 已修**:判据注释引用了不存在的断言名 R7a/R7c。
- **F7(第三轮 submimo)成立 —— 已修,而且它抓的是第四种漏法**:
  `tasks/panel-roster-doc-sync-my-review.md:10` 还写着"逐字节一致"。
  它的点评一针见血:**"文档作者自己的草稿也需要被搜索覆盖"**。
  我顺着它往下查,发现同一份文档在**仓外**(`/root/panel-my-reviews/`)还有一份物理副本,
  同样是旧的 —— 那份 `git grep` 和我前面所有搜索都够不着。两份都已改准并逐字节对齐。
- **submimo 的可追溯建议采纳一半**:`--all` 那句补了出处日期与"读代码读来的、无机械判据";
  不新建标签体系(那会再造一份要同步的副本)。

**腿没提、我自己扫出来的:**

- **第四份副本长在判据的断言名里**:R5 自称"与格式基线**逐字节一致**"、R5b 自称"**完全一样**",
  而两条实现 `diff <(norm …) <(norm …)` **两边都过 `norm`**。三轮、七条腿次,一条都没点它。
  最该准的地方反而错着 —— 已改准。
- **归档 design.md 里留着被推翻的合格写法**:R7 那句"必须印成'未收尾/**KILLED**'",
  而同一单后半程的 R7d **专门禁止** KILLED。归档工件**不改写正文**(那是当时的决定),
  就地加更正注。

**我自己犯了本单要治的病(最值钱的一条):**

见下一节。三轮评审都抓不到它 —— 它是我在评审之后写的。

### subglm 那条"未收尾"的腿:我先写错了,然后被活体证伪

**结论:它就是"仍在跑",花名册原本那句二选一没错,是我给它加错了第三种。**

第二轮我看见:写完日志头后零输出、`.log.err` 0 字节、无 `.state`、工作副本已不在、
`opencode` 自己的 HOME 本次零痕迹。我据此**推断**它"死在建工作副本那一段",
并把这句话写进了 `SKILL.md`、`verify.md` 和 commit `5c3b4d8`。

第三轮同样形状时我去 `ps` 查了活体:它**活着**,正在自己的工作副本里跑我的判据
(进程 3994492,`…/repo/tests/test-panel-roster.sh`)。[仓外不承重]
第三轮收尾更给了机器证据:两条 agent 腿都是 `timed out after 900s` —— **超时,不是崩溃**。

底座腿的输出到收尾才落盘,**"日志不动"根本不是死亡信号**。

**为什么这条最值钱**:本单的原则是"不许说盘上证据支持不了的话",
而我为了把一句话**说得更准**,自己造了一句盘上证据支持不了的话,还写进了文档和 commit。
已撤回(commit `debf862`),护栏改成:
**判"无 state"之前先 `ps` 看一眼进程还在不在;进程活着,就一个字都别说死因。**

> 顺带纠正一条我差点写进结论的事:**subglm 不是"一直失败"**(业主问出来的)。
> 08-23 05:56 那轮 `rc=0`;09:05 那轮 `rc=1`,`.log.err` 里是
> `HTTP 503 from https://opencode.ai/zen/go/v1`(后端 503,重试三次仍 503),不是我们配置错。

## 撞出来的三笔新账(都记明账,一笔都不夹带进本单)

1. **observation 不能从盘上重建。** 上一单把花名册变成了盘的函数,但归档闸据以核对
   "high 覆盖了 2 个不同模型家族"的那份 JSON **仍是控制器内存的函数**。本轮真实撞上:
   第二轮两条腿 rc=0、state 与日志俱在、花名册重建得出来,归档照样 BLOCK。
   **同一个病治好了一半。**
2. **降级腿能满足家族覆盖 —— 这是判卷防线上的洞。** 第三轮两条腿超时回落聊天腿,
   看到的 diff 是空的、自陈"无法回答",但 `rc=0 state=completed` ⇒ **家族覆盖照算**。
   也就是说"两个不同家族审过"这条机器保证,**可以被两条什么都没看见的腿满足**。
3. **R5b 疑似接近恒真。** submimo 建议给 R5b 补红检;我去读了实现,发现控制器写花名册用的是
   `render_roster "$LOG_PREFIX" > "$ROSTER_FILE"` —— 与 `panel-roster` 命令**调用同一个函数、
   读同一份盘上状态**,两边天然相等,几乎不可能单独红。
   **在收口阶段仓促给它补一条咬不动的红检,正是本单在防的病**(给防线加构件却没验证它咬得动),
   所以不补,记账。

## arbitrated verdict(主裁):PASS

七条评审发现全部成立并已落地;我自己另扫出两处腿没发现的(其中一处长在判据的断言名里);
我自己造的一句错话已被活体证伪并撤回。判据 34/34、红检 17 咬 0 漏、19 套件全绿。

**我对这个 PASS 的信心边界**:第三轮有两处我自己造成的污染(anchor leak + 评审中 commit),
真正有视野的腿只有 submimo 一条 —— 所以这不是"四腿齐 PASS"那种强证据。
本单是纯文档同步 + 判据措辞收紧,**没有产品行为改动**,风险面窄,我据此判 PASS。
三笔新账都留在明处。

## Accepted deviations

- **家族覆盖靠第三轮补齐**,而第三轮的两条降级腿实际零视野(见新账 2)。
  机器口径满足 high=2(xiaomi/deepseek/zhipu 三家 rc=0),**但我不假装那是三条实审**。
- 两句裸奔文档(my-review 路径 / `--all` 冷却)可机械化但本单不做 —— 会再开两处断言副本。
- `logs/` 553MB / 1107 文件无人清:既存账,删文件是危险操作,要业主点头,另开一单。

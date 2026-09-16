# Design: panel-round-discipline

- Change: panel-round-discipline
- Status: draft

- 规划双出: 不适用:无新写面、无开放方向(散文规矩 + 一段只打印的读数);
  `impact.factors` 不含 `new_write_surface`。

## 机制修正(拍板后量出来的,必须写进规矩本身)

业主批的 ① 原话是「产品代码不动的改动不再触发新一轮评审,只记账」。**这条不能照字面做。**
`bin/_review_delivery.py` 的 POLICY_VERSION 1 交付投影覆盖整个仓库,但**本 track 自己的收尾
记录是豁免的**:`verify.md` / `observations/*.json` / `evidence/` 里的 runlog 收据整份 skip,
`decision.json` 的 `outcome.verdict` 与 `tasks.md` 勾选位被归一化。**除此之外**动任何文件
(判据里一句注释、任何未跟踪文件)指纹就变,归档闸按 `subject digest` 核覆盖时就不认那次 panel。
🔴 初稿我写的是"动仓里任何一个文件",**说大了** —— 09-16 第 1 轮评审(subdeepseek)对着
`_review_delivery.py:66-89` 当场证伪。这是本机"我给的保证比实际大"的第三次复发,
所以豁免清单在这里逐项列出、不许再含糊带过。由此得到一条**窄第三条路**:
措辞修正只落在豁免清单里的,就地改、不作废绑定(射程一个字没动)。

⇒ 「不再触发新一轮评审」只有一种做得成的形态:**先别改,把它记进下一单**。
把它写成"改了但免审"会逼出两条坏路——要么归档时被闸挡住、要么我去放宽指纹射程。
**后者就是"改考卷让自己及格"的体面版本,本单明确拒绝。**

## Approach

**(a) 散文三条** → `workflow/skills/panel/SKILL.md`,插在「### 4. 出一个合并裁决」之后、
「### 5. 单腿回落」之前(轮次纪律属于裁决之后"还要不要再来一轮"那一步)。
放抽屉不放 CLAUDE.md:派评审前本来就要开这个抽屉,而 CLAUDE.md 有"总量不许只进不出"的约束。

**(b) 机器读数** → `bin/panel-review`,插在 `--track` 已解析且 dispatch 校验通过之后
(现有 `if [[ -n "$TRACK_NAME" ]]` 块尾)。数据源是**已经在写的机器事实**,不是新发明的:
- 轮数 N = `tracks/<name>/observations/*panel-review*.json` 的份数(每次成功 panel 落一份);
- 上一轮的 commit = 其中最新一份的 `actual.legs[].subject.source.head_oid`;
- 打印 `git diff --name-only <head_oid>..HEAD` 并按三桶分类:`tests/` / `tracks/` / 其它。

**为什么打印分类而不是打印结论**:什么算"产品代码"是仓库相关的(本机两个仓就不一样),
我不敢让守卫替我定义。打印三桶的**数量与文件名**,结论由我下——
这台机器上"守卫守错门"已经栽过三次(守在 package.json 而版本号在 ds_web.py;
漏网报告只扫 bin/ 而判据住 tests/;规矩1 只认 bump 而 aiwork 没有版本号)。
读数摆出事实、不替我判,是这三次的共同解法。

## Key trade-offs / risks

- **只打印不阻断**:见 proposal 的 non-goal。风险是我照样忽略它;接受,因为散文那半
  规定了看到它之后该做什么,而硬拦会误伤正当的第 4 轮。
- **N 数的是"落了盘的 panel 轮次"**:控制器没活到收尾(被砍/超时)那一轮不落 observation
  ⇒ 读数会**低估**真实轮数;而腿全死但控制器收尾了的那一轮**照样计数**(R4b 钉住)。
  打印用的就是这句话("数的是这个 track 已落盘的 panel 轮次"),不写"只数成功轮" ——
  初稿那个措辞会让人以为死掉的轮次不算,与实现相反。
- **head_oid 取自腿的 subject**:多腿同一 run 共享同一 subject,取第一条即可;
  取不到就打印"上一轮的 commit 读不出来"而不是静默跳过(fail loud,不 fail closed——它不阻断)。

## Alternatives considered

- **按日志文件名数轮次**(`logs/panel-<task>-r<N>-*`):task 名是我自由起的,`-r8` 是我打的字。
  用自述当机器事实 = [[self-narrated-fields-dont-guard]] 那条老病,弃。
- **放宽交付指纹,让判据改动不作废评审绑定**:见上"机制修正"。这是调钝报警器,弃。
- **硬阻断第 N 轮以上**:见 non-goal,弃。
- **写进 CLAUDE.md 随身规矩**:抽屉每次派评审必开,已经在使用点上;CLAUDE.md 要瘦。弃。

## Test strategy (oracle)

判据 `tests/test-panel-round-discipline.sh`(我写,不外包),用**造出来的假 track + 假 observation**
跑真 `panel-review` 的早期路径(不起任何腿),断言:
- R1 零份 observation(第一轮)⇒ **不打印**轮次读数(第一轮没有"上一轮"可比,打了就是噪音);
- R2 一份 observation 且其后只改了 `tests/` ⇒ 打印「第 2 轮」且三桶计数为 `tests/=1 tracks/=0 其它=0`;
- R3 一份 observation 且其后改了产品文件 ⇒ 三桶里"其它"非零,且列出该文件名;
- R4 observation 里 `head_oid` 缺失/不是本仓对象 ⇒ 打印"读不出来"那一句,**不影响退出码**;
- R5 `--no-track` ⇒ 一个字都不打印(没有 track 就没有轮次这回事);
- R6 读数走 stderr 且**不改变 panel-review 的退出码**(它是读数不是闸)。
另:`sync-workflow-docs --check` 必须零漂移(散文那半的唯一机械判据)。

**这个 oracle 能被什么骗过?**

断言全绿、但真实使用里仍然失控,会错成这样:**读数打印了,我照样开第 5 轮**——
因为读数出现在派活的那一刻,而"要不要再来一轮"的决定是我在**读完腿的报告之后**做的,
中间隔着我最想再确认一次的那段时间。断言接不住这件事;能接住它的只有**下一次真实多轮单的账**
(下一单如果又超过三轮,就回来看这条规矩是不是放错了位置)。
第二种骗法:三桶分类把"产品"漏进 `tests/` 桶(例:判据里搬了一段产品逻辑),
读数显示"其它=0"而实际动了行为 ⇒ 我据此停手。这靠 R3 列**文件名**而不只给计数来兜一半,
另一半只能靠我自己看那份文件名清单。

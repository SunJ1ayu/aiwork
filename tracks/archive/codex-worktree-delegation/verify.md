# Verify: codex-worktree-delegation

- Date: 2026-08-11
- Verdict: **PASS**(主裁;四审只有 2/4 腿真给了裁决,见花名册)

## Mechanical checks

- [x] build passes(bash 语法检查 + 工具自身跑得起来)
- [x] tests pass
- [x] no secrets / unsafe ops

**机器打印的**(不是我的转述):

```
runlog: suite-all-final rc=0 commit=5fd7cab dirty=yes at=2026-08-11T13:41:39Z file=tracks/codex-worktree-delegation/evidence/20260811T134139Z-01-suite-all-final.txt
runlog: redcheck-isolate-final2 rc=0 commit=5fd7cab dirty=yes at=2026-08-11T13:52:41Z file=tracks/codex-worktree-delegation/evidence/20260811T135241Z-01-redcheck-isolate-final2.txt
runlog: mutation-test-r4 rc=0 commit=5fd7cab dirty=yes at=2026-08-11T13:40:20Z file=tracks/codex-worktree-delegation/evidence/20260811T134020Z-01-mutation-test-r4.txt
runlog: smoke-real-codex rc=0 commit=5bc2510 dirty=yes at=2026-08-11T13:05:49Z file=tracks/codex-worktree-delegation/evidence/20260811T130549Z-01-smoke-real-codex.txt
runlog: probe-real-sandbox rc=0 commit=5bc2510 dirty=yes at=2026-08-11T13:16:44Z file=tracks/codex-worktree-delegation/evidence/20260811T131644Z-01-probe-real-sandbox.txt
```

**跑红/跑坏的那几遍也贴在这儿**(不许只贴好看的):

```
runlog: redcheck-entry rc=5 commit=88e47b4 dirty=yes at=2026-08-11T12:36:38Z file=tracks/codex-worktree-delegation/evidence/20260811T123638Z-01-redcheck-entry.txt
runlog: mutation-test rc=1 commit=88e47b4 dirty=yes at=2026-08-11T12:44:41Z file=tracks/codex-worktree-delegation/evidence/20260811T124441Z-01-mutation-test.txt
runlog: mutation-test-r3 rc=1 commit=5fd7cab dirty=yes at=2026-08-11T13:33:14Z file=tracks/codex-worktree-delegation/evidence/20260811T133314Z-01-mutation-test-r3.txt
runlog: redcheck-isolate-final rc=5 commit=5fd7cab dirty=yes at=2026-08-11T13:41:35Z file=tracks/codex-worktree-delegation/evidence/20260811T134135Z-01-redcheck-isolate-final.txt
runlog: redcheck-isolate rc=0 commit=88e47b4 dirty=yes at=2026-08-11T12:35:53Z file=tracks/codex-worktree-delegation/evidence/20260811T123553Z-01-redcheck-isolate.txt
runlog: suite-all rc=0 commit=88e47b4 dirty=yes at=2026-08-11T12:40:06Z file=tracks/codex-worktree-delegation/evidence/20260811T124006Z-01-suite-all.txt
runlog: mutation-test-r2 rc=0 commit=88e47b4 dirty=yes at=2026-08-11T12:46:28Z file=tracks/codex-worktree-delegation/evidence/20260811T124628Z-01-mutation-test-r2.txt
```

四份红/坏收据分别是什么、为什么不算数:

- **`redcheck-entry` rc=5**(红了但没红在目标断言上):把实现退回后,老套件 `test-delegate-entry.sh`
  **整套**红在"不认识的参数 `--no-isolate`"上 ⇒ 那次红检**不算数**,我没拿它当证据。
  本单的红检以 `redcheck-isolate-final2` 为准(49 过 / 53 红,且红在 `I1` 那条目标断言上)。
- **`redcheck-isolate-final` rc=5**:同一个病、我自己犯的 —— 我把 `--must-fail` 指到
  「腿越界改主树」那条,而那条在**旧实现下本来就成立**(洞是隔离引入的)。换回 `I1` 重跑才对。
- **`mutation-test` rc=1**:M5 报"判据没咬住"。追下去**不是判据的事**:实现里有两道冗余的
  `__pycache__` 排除,我的变异只拆了一道 ⇒ 行为没变,判据当然不该红。拆全了就红了(r2)。
- **`mutation-test-r3` rc=1**:两处"漏网"又都是**变异脚本自己坏了** —— M6 打的那段代码在
  第二轮已被我删掉(没靶子了),M11 的名字里带 `/` 导致输出文件根本没写成、grep 空手而归。
  现在脚本对"套件输出为空"**硬报错**,不再把自己的故障说成"判据没咬住"。

机器结果汇总(最终态 `5fd7cab`):总跑 9 个套件全绿(`delegate-isolate: 102/0`、
`delegate-entry: 80/0`)、退回红检红在目标断言、变异 **10/10 全被咬住**、
**真 codex 端到端冒烟 10/10**、真沙箱探针跑完并**证伪了我 design 里的一条前提**。

## Review

- lane: **full**(改的是判卷防线本身:攻题闸 + 收货闸①)
- 派给: **主 agent 亲写,不外包** —— 被改的入口正是执行腿的验收边界(design A2 实测:
  `--repo /root/aiwork` + 默认日志被"卷宗不许进仓"闸拒发,派不出去)。
- 规格自查(读任何 panel 输出之前先答的,原文在
  `/tmp/.../codex-worktree-isolate-my-review.md`,已入库为 `my-review.md`):
  我当时写下的最大风险是"卷宗规则的放宽依赖『腿的沙箱 = 那棵树』这个前提"(F3),
  但我把它记成了**接受的偏差**,没去验。**这就是规格本身错的地方** ——
  panel 只验"实现合不合规格",验不了"规格对不对";这一次是评审腿把我按回去验的。
- 腿的花名册(原样粘,`.roster` 文件):

```
submimo=PASS subdeepseek=PASS subglm=off subkimi=FAIL(rc=1)
```

  ⚠️ **只有 2/4 腿真给了裁决**:subglm 欠费默认 off,subkimi 403
  「You've reached your usage limit for this billing cycle」。别把这轮读成"四审过了"。
  另:派发时有 `anchor leak` 警告,泄的是**别的 track** 的三份 my-review
  (note-clear / note-source / owner-consent),与本单无关,不影响独立性。

- findings:
  - **[subdeepseek,孤腿,采纳 —— 本轮最值钱的一条]** 卷宗放宽押在"真 codex 沙箱 = `-C` 目录"
    这个**从没被机器验证过**的前提上;判据里的 codex 是假的,只会往 `-C` 里写,证不了这件事。
    ⇒ 我发探针去验,**当场证伪**:`-s workspace-write` 能往**主仓**写、改主仓文件(它把项目根
    向上解析到了主仓,因为 worktree 的 `.git` 是文件),`/tmp` 也敞;写沙箱**管不了读**,
    腿把主仓里一份未跟踪的"秘密攻题记录"原文贴了回来。
    ⇒ 卷宗放宽**整条撤回**(禁区 = 仓 ∪ worktree 根),**A2 的死结没解开**,design 10.3 原文
    留成墓碑。收据 `*probe-real-sandbox*`。
  - **[主 agent 独有,两条腿都没提,由上一条逼出来]** 隔离把闸① 从主树挪到那棵树之后,
    **主树的判卷文件没人看了**,而腿够得着主树 ⇒ 腿伸手改主树的判据、闸① 全绿,
    我随后在主树上跑的就是被改过的考卷。⇒ 闸① 补一条**主树臂**(只问"有没有没提交的动静",
    我自己提交过的判据修复照旧放行,不许把 A3 的误报请回来)。变异 M9 钉住。
  - **[subdeepseek,采纳]** 判据 H2④「空清单 ⇒ 拒发」**绿在错误的原因上**:`.gitignore` 被自动
    并进 protect ⇒ 文件集不空,那次 rc≠0 其实来自哈希对不上;把空清单那道 die 删掉它照样绿。
    ⇒ 已修(撤掉 .gitignore + 给空清单那版盖哈希),并加变异 **M8** 钉住那道闸。
  - **[subdeepseek,采纳]** 直通参数 `-- -C <别处>` / `-- -s <别的沙箱>` 排在工具给的 `-C/-s`
    **后面**、last-wins ⇒ 能静默撤销隔离,而回执上还写着 `isolate=true`。
    ⇒ 隔离下直接拒发(要传就显式 `--no-isolate`)。变异 M11 钉住。
  - **[submimo + subdeepseek 各自独立命中,采纳为已知边界]** 哈希只覆盖 protect 清单里的
    路径**本身**:符号链接只记 `symlink:<目标>`,目标的**内容**在清单外就在闸外。
    这是规格选择(跟进链接会跑出仓、还会成环),不改行为,但**钉一幕**免得哪天悄悄变,
    并在文档里写清"要覆盖就把目标一起列进 `--protect`"。
  - **[subdeepseek,采纳]** 判据侧哈希实现有两处会造**假红**(与实现侧算不出同一个值):
    路径规范化(`tests//`)、`sort` 没锁 `LC_ALL=C`(非 ASCII 路径)。已修。
  - **[subdeepseek,采纳]** `delegate` skill 过时(还写着旧用法、旧 mtime 话术、旧卷宗规则)。
    ⇒ 已更新;README 也补了 delegation entry / redcheck / runlog / 总跑那一段。
  - **[subdeepseek,确认无问题;submimo 独立同结论]** 收货写回 `actual_write_set` 不破坏
    "回执 = 派活时快照"的语义(派活时字段只读不改,写回的是闸① 的**输出**,且幂等)。
  - **[主 agent 自审 F1,腿没提]** `--dry-run` 的回执拿去收货,话术把"从没建过"说成"现场没了";
    红检时还撞出更难看的一半:dry-run 不走撞名挪位,算出的树名可能**正好是上一发真建的那棵**
    ⇒ 会一本正经地"收货成功"(收的是别人的树)。⇒ 回执记 `dry_run`,收货第一句就答它。
  - **[主 agent,判据自己的 bug ×2]** 空清单那幕断言了**累计**调用数(老套件两个月前就写过这条
    教训,我又踩);D/F 冲突的失败注入**顺序相关**,前面成功派过一发就注入不上 ——
    它"红在实现头上",其实错在我的夹具。两处都已修。
  - **[主 agent,挖出老套件一处两个月的假绿]** `test-delegate-entry.sh` D4② 只写了 `.gitignore`、
    没造出被 ignore 的文件 ⇒ `git status --ignored` 恒空,那道闸**从来没被真考过**;
    它一直绿是因为旧 mtime 闸先拒了,而那句话里的 "**.gitignore**" 恰好被 `grep -i ignore` 命中。
    换成内容哈希后遮挡没了,当场露馅。
- arbitrated verdict (主裁): **PASS**。
  两条腿的发现我逐条对着代码验过,**没有一条不成立**;最值钱的那条(未验证的沙箱前提)
  直接改掉了设计,并顺带逼出一个两条腿都没看见的真洞(主树臂)。
  改动全部落地并被机器钉住:总跑全绿、红检红在目标断言、变异 10/10、真 codex 端到端 10/10。
  剩下的都是**写进文档的已知边界**,不是待修缺陷。

## Accepted deviations

- **隔离不是沙箱边界**,买到的是**归因**。腿仍然写得到主仓(实测)、读得到任何地方。
  威胁模型照旧是"忘了/手滑",不是蓄意 —— 这一条已如实写进工具头部、design 和 delegate skill。
- **A2 的死结没解开**:派 `/root/aiwork` 自己的活时,`/root/aiwork/logs/` 也在禁区里,
  必须显式 `--log` 到 `/root/aiwork` 之外。
- **`--protect ../x` 能穿越出仓**(老问题,本单没引入也没恶化):哈希会覆盖仓外文件,
  而 `git status -- ../x` 的报错走 stderr、stdout 为空 ⇒ "判卷路径干净"那道检查静默通过。
  protect 清单是主 agent 自己敲的,不是腿给的 ⇒ 危险度低。**记进 backlog**。
- **撞名自动挪名字**(`-2`、`-3`)会让"我不小心派了两次"静默成功;换来的是"连续两发不被堵死"。
  树路径在终端和回执里都印了,可查。
- **树会攒**:回收路径只在收货时打印(派完不收货就没人提醒)。`worktrees/mcp-registry`
  从 08-03 挂到今天就是反面证据。
- 四审**只有 2/4 腿**给了裁决(智谱欠费 / Kimi 额度)。这不是"四审过了"。

# Verify: evidence-lifetime-gate

- Date: 2026-08-13
- Verdict: **PASS**

## Mechanical checks

- [x] build passes(纯 shell,无 build;`bash -n bin/track bin/_ephemeral-refs.sh` 通过)
- [x] tests pass — **39/39**(判据),回归 `test-track-guard` 62/0、
      `test-worktree-sweep` 61/0、`test-runlog` 31/0
- [x] no secrets / unsafe ops — 判据零外网(`_no-egress.sh`,source 失败即硬退);
      全部夹具在 `mktemp -d` 里,不碰真 tracks/

**机器打印的**(不是我的转述),按时间顺序,红的绿的一份不藏(规矩 5b):

```
runlog: bash rc=1 commit=639237b dirty=yes at=2026-08-13T04:46:47Z file=tracks/evidence-lifetime-gate/evidence/20260813T044647Z-01-bash.txt
runlog: bash rc=1 commit=639237b dirty=yes at=2026-08-13T04:49:21Z file=tracks/evidence-lifetime-gate/evidence/20260813T044921Z-01-bash.txt
runlog: bash rc=1 commit=25c5394 dirty=yes at=2026-08-13T05:02:41Z file=tracks/evidence-lifetime-gate/evidence/20260813T050241Z-01-bash.txt
runlog: bash rc=0 commit=86e7e4d dirty=yes at=2026-08-13T05:10:50Z file=tracks/evidence-lifetime-gate/evidence/20260813T051050Z-01-bash.txt
runlog: bash rc=0 commit=86e7e4d dirty=yes at=2026-08-13T05:29:18Z file=tracks/evidence-lifetime-gate/evidence/20260813T052918Z-01-bash.txt
runlog: bash rc=0 commit=8cf5a51 dirty=yes at=2026-08-13T05:29:54Z file=tracks/evidence-lifetime-gate/evidence/20260813T052954Z-01-bash.txt
```

三份红的分别是:判据 v1 红检(15 红 9 绿,**含一处夹具假红**见下)、
v1 修夹具后重跑(15 红 9 绿)、判据 v2 红检(27 红 10 绿,四个对照组全绿)。

**变异测试(不在收据里,单独记账)**:E14 是四审之后补的,补进来时**实现已经满足它**
⇒ 上来就绿的断言证明不了任何事。所以把 helper 临时改成「跳过围栏代码块」跑了一遍:
**只有 E14 变红(37/2)**,其余全绿,还原后 39/0 且 helper 逐字节回原样。
这才证明这一幕咬得动。

## Review

- lane: **full**
  > 碰的是**判卷防线本身**(一道能拒绝归档的闸)。误报会卡死归档 ⇒ 人会绕过它,
  > 那比没有这道闸更坏。硬规矩不降档。
- **仓内证据**(全部由仓外搬入,这正是本 track 立的规矩的第一次自我应用):
  - 主 agent 自审全文(写于读任何腿之前):`evidence/review/my-review.md`
  - 派活前攻题的题面与结论:`evidence/review/attack-brief.md`、`evidence/review/attack-log.md`
    (含 `oracle-sha256`,`delegate-codex` 用它验"攻完题之后没再改判据")
- 派给: **codex/gpt-5.5**(隔离 worktree)—— 边界清楚(一个新 helper + archive 分支挂一行)、
  判据已写完且对它逐字节 off-limits、判卷不用起服务。这是分层里最典型的可外包形状;
  "自己顺手干了"正是 [[self-narrated-fields-dont-guard]] 记过账的惯性。
  **返工 0 轮,自身错误 0 处**(闸①机械核过判卷零改动;闸③亲读 diff 无符号链接、
  改动面正好是允许的两个文件;闸②我自己跑 —— 合并后在主树重跑,不复用 worktree 里的绿)。
- 规格自查(读任何 panel 输出之前先答):
  **如果规格本身错了,会错成什么样?** 最可能是**误报**——把大量正常叙述拖进"必须表态",
  归档摩擦变大,然后我自己开始习惯性贴标记 ⇒ 闸退化成仪式。
  怎么发现:**已实测**。对两个真实 track 跑 `eph_check`,各命中 1 条,
  且都是真正的"叙述里提一嘴"(墓碑句),一行标记即可。不是噪音。
  第二个规格风险:**标记本身是自述**,贴满就能全过,闸挡不住蓄意滥用 ——
  已在 design 与 CONVENTION 里写明射程,不假装它防得住。
- 腿的花名册:
  ```
  # panel-review 花名册(2026-08-13 13:23:06)task=evidence-lifetime-review
  # PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
  # 日志:/root/aiwork/logs/panel-evidence-lifetime-review-20260813-131625.*.log
  submimo=PASS subdeepseek=PASS subglm=off subkimi=FAIL(rc=1)
  ```
  > **又是 2/4 腿**(智谱欠费未派、Kimi 撞 Moonshot 额度 403)。**连续第四轮**。
  > 别把这一轮读成"四审过了"。
  > `PANEL_ORACLE_CMD` 已记录派活前的判据实跑:`39 passed`(`.oracle.log`),
  > 堵的是 07-04 那次"三个评审员一致通过一份没人跑过的考卷"。
- findings:
  - **[攻题 · 派活前,9 条,全部已修]** 见 design.md「攻题结果」表。最值钱两条:
    ① **E9 不是单变量**(同时注入"缺 helper"和"有危险引用")⇒
    **把逻辑内联进 `track`、根本不建 helper 的实现照样全绿**;
    ② **E7 什么都没锚住**(我造的收据正文压根不含 `/tmp`)。
    外加一处**规格错**:笼统写"大小写不敏感",但 `/TMP/` 在 Linux 上不是 `/tmp/`。 [仓外不承重]
  - **[两腿独立命中 · 已修] 考卷没锚住"围栏代码块要不要扫"** ⇒ 跳过围栏的实现能全绿。
    补 E14 + 变异测试证明它咬得动。**两条腿各自独立指到同一处,是本轮最强的信号。**
  - **[subdeepseek F5 · 已修] 我在 design 里承诺写进 CONVENTION.md 的东西没写。**
    这是"给防线加构件却没把构件放进防线"的同型自伤(machine-evidence-gate 那单记过一次)。
    已补 `track/CONVENTION.md` 一节。
  - **[subdeepseek F1 · 低危 · 不修] `/tmp/` 是子串匹配**,`/var/tmp/`、`project/tmp/` [仓外不承重]
    也会命中。判:`/var/tmp` 本就是临时目录、命中是对的;仓内叫 `tmp` 的目录
    **当前语料零出现**,为想象中的形状加路径边界判定不值。记为射程边界。
  - **[subdeepseek F2 + 主 agent 自审 · 低危 · 不修] 裸 `/tmp`(无尾斜杠)抓不到。**
    承重引用几乎必然带路径成分;放宽会把大量叙述句拖进"必须表态",而**误报是这道闸的死法**。
  - **[subdeepseek F4 · 低危 · 接受] markdown 表格行只能把标记塞进单元格里**(会渲染出来)。
    本 track 自己的 design.md 就有这么一行 —— 归档时按此处理。
  - **[subdeepseek F6 · 低危 · 不修] helper 存在但语法坏掉时,报错文案仍说"找不到"**
    (`2>/dev/null` 吞掉了真实错误)。仍然 fail closed,只是诊断不精确;
    与 `_evidence.sh` 现有写法一致,单独改会让两处不一样。
  - **[subdeepseek F7 · 低危 · 接受] 符号链接的 `.md` 不扫、`*.MD` 大写扩展名不匹配。**
  - **[subdeepseek F8 · INFO · 接受] 贴在没有引用的行上的标记会被静默接受**
    (可以用来发现"整片贴标记")。兜底是闸③亲读 diff,已写进 CONVENTION。
  - **[主 agent 自审 · 低危 · 不修] `rel="${file#$dir/}"` 的模式未加引号**,
    track 名含 glob 元字符时相对路径会算错。`track new` 生成 kebab-case,现实不可达。
  - **[主 agent 自审 · 设计张力 · 已按本 track 规矩自解] 自审落哪儿。**
    "先落盘后读腿"要求独立性 ⇒ 落仓内会被评审腿读到;落仓外就是死链。
    解法即本 track 的规矩:**先落仓外,归档前搬进 `evidence/` 并改为仓内引用**。
    历史上那 4 处「全文在 scratchpad 的 my-review」正是卡在这个张力上然后永久丢失的。 [仓外不承重]
    `panel-review --require-my-review` 本来就要求该文件在被审仓之外,与此一致。
- arbitrated verdict (主裁): **PASS**。
  两条出结论的腿都判 PASS,8 条发现无一触及正确性:F5 是我没兑现的承诺(已补)、
  围栏那条是我考卷的洞(已补并变异验证)、其余是射程边界与文案。
  我自己独立核过接线位置(在 `ev_check` 之后、`mv` 之前)、`set -e` 下不会静默死、
  fail closed 为真、以及**真实语料的噪音量(各 1 条)**。
  **记账:这一轮仍只有 2/4 腿给了裁决**,不是四审全票。

## Accepted deviations

- **不进 pre-commit**:干活期间引用 scratchpad 是正常工作流,提交时也查=给活跃工作制造噪音, [仓外不承重]
  而噪音多的闸没人信。只在"宣布做完"那一刻成立。
- **不追溯已归档的 51+ 个 track**:闸够不着,死链已成事实。
- **不 resolve 路径**:`$(mktemp -d)`、URL 编码、经符号链接间接指向临时目录一律抓不到。
  解析散文里的路径是误报的温床 —— 改成"提到就要表态",而正确修法(搬进仓)会自己消除触发条件。
- **围栏代码块内也要标记**,会改动逐字粘贴的终端记录。当前语料无此形状(唯一的表格行不是围栏),
  **真被咬到再做块级豁免**,不为想象中的形状预付复杂度。
- **本轮 full 审只有 2/4 腿出裁决**(连续第四轮)。不重跑:两腿结论方向一致且我已逐条对代码验证。

## 工艺账(这一单自己犯的)

1. 🔴 **我第一版把这条规矩判成「够不上硬规矩」,是给它降了档** —— 按准入标准
   信任类 = 查工件不查自述 + 防不可逆损害,它够得上。是用户追问「用第一性原理了吗」才重判的。
2. 🔴 **`; echo rc=$?` 又一次把失败退出码吃掉**:`panel-review` 参数传错、
   压根没跑起来,后台却报 exit 0。**08-11 记过账(一天两次),今天第三次。**
   这已经不是"注意一下"能解决的,记在这里等下一次决定要不要上机械防线。
3. **我 5 条自攻一条没命中真洞,9 条真洞全是攻题腿找的** —— 印证
   [[panel-review-trust-calibration]]:真漏的根因反复是我自己的规格/夹具错。
4. **判据 v1 的红检里有一处夹具假红**(E10 把 track-guard 本体 `cp` 进 `.git/hooks`,
   它 source 同目录 helper 时找不到 ⇒ fail closed 拒绝提交)。**夹具要照着真实装法造**
   (真实是两行 wrapper `exec` 原路径),否则红检会红在夹具自己身上。

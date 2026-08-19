# Verify: deepseek-leg-bash-hole

- Date: 2026-08-18 → 2026-08-19
- Verdict: **PASS**

> **这一单的形状**:08-18 我给三条评审腿关掉了 Bash(理由是"白名单挡不住
> `git diff --output=` 和 `--no-index`,那就整个关掉更安全")。四审当场把它推翻 ——
> 关掉的代价不是理论上的:**腿静默起不来,而 panel 照常出结论**,那比"腿可能写个文件"
> 危险得多。于是转向:恢复只读 git、写口全关、白名单的**定位**从"挡对手"改成
> **"挡误伤"**;"腿真写了仓怎么办"改用**检测**接住,单开 track `repo-write-audit`。

## Mechanical checks

- [x] tests pass —— **367 passed / 0 failed**,且这一遍在最后一次代码编辑之后。
      收据里两处"跑不了/没装"字样是**断言文案本身**(测的正是"依赖缺失要拒跑、
      不许静默跳过"),不是整块 SKIP —— 逐条看过,不是拿汇总糊过去的。
- [ ] build passes —— **不适用**:这仓是 bash 脚本 + 判据,没有 build 步骤。
      不适用就写不适用,不打勾糊过去(打勾的第 11 项是假的,08-18 栽过)。
- [x] no secrets / unsafe ops —— 判据里"key 不进 argv / 不进日志 / 文件 600"三条全绿;
      本单未新增任何网络出口;`.mimocode/plans/` 9 份运行期产物已撤出版本控制。

**机器打印的**(下面每一行都是脚本从 `evidence/` 里逐字节抄出来的,我没有手打):

### 最后一遍(5b:归档要求它必须在这儿)

```
runlog: green-final-atomic rc=0 commit=58de5a6 dirty=yes at=2026-08-19T05:53:46Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T055346Z-01-green-final-atomic.txt
```

### 跑红的每一遍(5b′:红的一份都不许藏 —— 它们是这一单最值钱的部分)

```
runlog: green-after-impl rc=1 commit=7e848de dirty=yes at=2026-08-18T14:47:44Z file=tracks/deepseek-leg-bash-hole/evidence/20260818T144744Z-01-green-after-impl.txt
runlog: green-kimi rc=1 commit=2abd965 dirty=yes at=2026-08-18T15:08:20Z file=tracks/deepseek-leg-bash-hole/evidence/20260818T150820Z-01-green-kimi.txt
runlog: green-kimi rc=1 commit=2abd965 dirty=yes at=2026-08-18T15:24:16Z file=tracks/deepseek-leg-bash-hole/evidence/20260818T152416Z-01-green-kimi.txt
runlog: red-v30-argv rc=1 commit=3face49 dirty=yes at=2026-08-19T01:18:26Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T011826Z-01-red-v30-argv.txt
runlog: red-v30-argv-fixed rc=1 commit=3face49 dirty=yes at=2026-08-19T01:23:35Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T012335Z-01-red-v30-argv-fixed.txt
runlog: red-v30-argv-real rc=1 commit=3face49 dirty=yes at=2026-08-19T01:27:31Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T012731Z-01-red-v30-argv-real.txt
runlog: red-v31-f2f4 rc=1 commit=a31967f dirty=yes at=2026-08-19T01:57:51Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T015751Z-01-red-v31-f2f4.txt
runlog: red-v32-artifacts rc=1 commit=a31967f dirty=yes at=2026-08-19T02:09:28Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T020928Z-01-red-v32-artifacts.txt
runlog: red-v32-artifacts-real rc=1 commit=a31967f dirty=yes at=2026-08-19T02:13:06Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T021306Z-01-red-v32-artifacts-real.txt
runlog: green-v32-artifacts rc=1 commit=62a0e6f dirty=yes at=2026-08-19T02:17:43Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T021743Z-01-green-v32-artifacts.txt
runlog: red-v33-submimo-lock rc=1 commit=d3e2e5a dirty=yes at=2026-08-19T03:09:37Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T030937Z-01-red-v33-submimo-lock.txt
runlog: red-after-teardown rc=1 commit=578f6af dirty=yes at=2026-08-19T03:52:43Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T035243Z-01-red-after-teardown.txt
runlog: green-after-teardown rc=1 commit=cb56690 dirty=yes at=2026-08-19T04:02:58Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T040258Z-01-green-after-teardown.txt
runlog: red-bash-allowlist rc=1 commit=833a01b dirty=yes at=2026-08-19T04:45:21Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T044521Z-01-red-bash-allowlist.txt
runlog: red-mimo-floor rc=1 commit=0643ac1 dirty=yes at=2026-08-19T04:56:12Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T045612Z-01-red-mimo-floor.txt
runlog: red-atomic-write rc=1 commit=0a5777e dirty=yes at=2026-08-19T05:49:20Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T054920Z-01-red-atomic-write.txt
```

### 其余绿的

```
runlog: green-final rc=0 commit=7e848de dirty=yes at=2026-08-18T14:57:03Z file=tracks/deepseek-leg-bash-hole/evidence/20260818T145703Z-01-green-final.txt
runlog: green-final rc=0 commit=2abd965 dirty=yes at=2026-08-18T15:28:07Z file=tracks/deepseek-leg-bash-hole/evidence/20260818T152807Z-01-green-final.txt
runlog: green-worktree-diff rc=0 commit=f92503c dirty=yes at=2026-08-18T15:36:26Z file=tracks/deepseek-leg-bash-hole/evidence/20260818T153626Z-01-green-worktree-diff.txt
runlog: green-v30-argv rc=0 commit=3face49 dirty=yes at=2026-08-19T01:51:43Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T015143Z-01-green-v30-argv.txt
runlog: green-v31-f2f4 rc=0 commit=a31967f dirty=yes at=2026-08-19T02:02:12Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T020212Z-01-green-v31-f2f4.txt
runlog: green-v32-artifacts-real rc=0 commit=62a0e6f dirty=yes at=2026-08-19T02:22:14Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T022214Z-01-green-v32-artifacts-real.txt
runlog: panel-full-0819 rc=0 commit=d3e2e5a dirty=yes at=2026-08-19T02:29:04Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T022904Z-01-panel-full-0819.txt
runlog: probe-mimo-plan-agent rc=0 commit=d3e2e5a dirty=yes at=2026-08-19T02:55:52Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T025552Z-01-probe-mimo-plan-agent.txt
runlog: green-teardown-final rc=0 commit=cb56690 dirty=yes at=2026-08-19T04:07:33Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T040733Z-01-green-teardown-final.txt
runlog: green-final-teardown rc=0 commit=343aa30 dirty=yes at=2026-08-19T04:13:38Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T041338Z-01-green-final-teardown.txt
runlog: green-bash-allowlist rc=0 commit=5539a6a dirty=yes at=2026-08-19T04:49:37Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T044937Z-01-green-bash-allowlist.txt
runlog: red-mimo-floor2 rc=0 commit=0643ac1 dirty=yes at=2026-08-19T04:59:33Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T045933Z-01-red-mimo-floor2.txt
runlog: panel-full-0819c rc=0 commit=c5b96ed dirty=yes at=2026-08-19T05:04:27Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T050427Z-01-panel-full-0819c.txt
runlog: redcheck-panel3 rc=0 commit=0a5777e dirty=no at=2026-08-19T05:44:51Z file=tracks/deepseek-leg-bash-hole/evidence/20260819T054451Z-01-redcheck-panel3.txt
```

### 三份**没有收据行**的文件(不是收据,别当收据用)

```
20260818T154121Z-01-panel-full.txt
20260819T041834Z-01-panel-full-0819b.txt
20260819T053341Z-01-TRUNCATED-断线砍断-作废.txt
```

- 前两份是 panel 收据:`panel-review` 派发完就没再收尾(收据停在 `running all in
  parallel...`,`logs/` 里也没有对应的 `.roster`)⇒ **那两轮的结论不是从花名册来的,
  是我直接读腿日志读出来的**,如实记在这儿,不假装它们是完整的四审。
- 第三份是 08-19 13:33 那遍判据:**断线把它砍在半路**(273 条 PASS,完整跑是 367;
  停在 V23 中间、没有 `输出结束` 行、没有 `rc=` 行)。已改名 `-TRUNCATED-断线砍断-作废`
  并在文件尾加注理由 —— **半截收据留着装完整比没有更坏,但悄悄删掉就是藏收据。**

## Review

- lane: **full** —— 碰权限(评审腿能不能写被评审的仓)、且**动的是判卷防线本身**:
  这条腿能写 `tests/*` 就等于能改考卷。针孔再薄也不打折。
  > **碰了新写口 / 权限 / auth / 钱 / 数据一致性 → full,针孔再薄也不打折**(硬规矩,别在这降档)。
- 派给: **主 agent 直接干** —— ① 验证要打真端点、真腿,执行腿沙箱断网跑不了;
  ② 这一单的核心判断是"这层守卫到底管什么",要当场设计探针、看实际行为,
  不是照单执行的活;③ 改动集中在一处 allowlist + 一段 diff 注入。
  **返工 0 轮(没有外部执行腿)/ 自身错误:见下面"我自己错在哪"一节,数得出的有 8 处。**
- 规格自查(读任何 panel 输出之前先答):规格错的话会错成什么样 ——
  **"关掉 bash 更安全"这条规格本身就是错的**,而且它当时看起来无懈可击。
  它错的方式正是 panel 验不出来的那种:实现完全合规格(bash 确实关掉了),
  但规格问错了问题(把"腿可能写文件"当成最坏形态,而真正的最坏形态是
  **腿根本没跑起来、panel 照常出结论**)。发现它的不是断言,是**真跑一次看腿的日志**。
- 腿的花名册(原样粘,没手写):
  - 第二轮 `logs/panel-dsbash-0819.roster`:
    `submimo=FAIL(rc=124) subdeepseek=PASS subglm=PASS subkimi=PASS`
  - 第四轮 `logs/panel-dsbash-0819c.roster`:
    `submimo=PASS subdeepseek=PASS subglm=PASS subkimi=FAIL(rc=1)`
  - 第一轮(0818)与第三轮(0819b)**没有 roster** —— 见上面"没有收据行"那节。
  > **`PASS` = 进程 rc=0,不等于给了裁决**:第四轮 subglm 的 rc=0,它的结论
  > (`Conclusion: PASS`)是我到日志第 65 行亲眼确认的,不是从 rc 推的。
  > subkimi 的 `FAIL(rc=1)` 分型 = **Kimi 会员额度耗尽(403 usage limit)**,
  > 不是被断线砍(`.err` 里是 403 正文,不是 0 字节)。

### findings(第四轮四审 0819c;逐条对代码验过,不是抄腿的话)

**已落地的:**

1. `[MEDIUM]` submimo F1 / subdeepseek #1 —— `bin/subkimi:6,15-16` 头部注释还停在
   08-18「Bash 一律拒绝,diff 由 wrapper 喂」,而同文件的守卫、提示词、墓碑都已是
   转向后的版本。**同一件事写两处、只更新一处**。→ 已改(`0a5777e`)。
2. `[MEDIUM]` subdeepseek #2 —— V33「隔离不许换 HOME」查的是 stub 的 **argv**,而
   `env HOME=x cmd` 的赋值只进子进程环境、**永远不进 argv** ⇒ 实现真换了 HOME 也照样绿。
   **结构上永远绿的断言 = 这一单最该被抓的东西。** → 改成 stub 落自己的环境再比对(`2297f96`)。
3. `[LOW]` subdeepseek #3 —— claude 壳 / subkimi 的"有只读 git"没有任何反向断言
   (V28⑮ 只钉了 opencode 腿)。→ 两条新断言(`2297f96`),红检命中的就是它。
4. `[LOW]` subdeepseek #4 —— V9「不许裸 Bash」偏松,`Bash(git:*)` 能过(它比
   diff/log/status/show 宽,会放行 `git config` 这类写)。→ 钉到具体只读子命令(`2297f96`)。
5. `[LOW]` subdeepseek #5 —— `design.md` 的 Test strategy 整段在讲 V34,而同一份文件
   文末已把 V34 划出本 track。→ 标注下线并写明本单真正的 oracle(`0a5777e`)。
6. `[LOW]` subdeepseek #6 —— 任务书把 claude 壳写成裸 `Bash`(第二轮中间态)。
   任务书是喂给评审腿的文档,自相矛盾会污染下一轮四审。→ 订正(`0a5777e`)。
7. `[LOW]` subdeepseek #7 —— `.mimocode/plans/` 有 9 份运行期产物入库,**正是"腿往被
   评审的仓里写文件"的实物证据**。→ 加 `.gitignore` + `git rm --cached`(盘上和 git
   历史里都还在,证据不丢)(`0a5777e`)。
8. `[INFO→已修]` subdeepseek #8 —— V28 查的是**我自己写进去的那份 JSON**。
   → 改用 `opencode debug config` 让底座自己解析(`2297f96`)。**查工件不查自述**,
   而 plan 档骗过我的正是"写的和解析出来的不一样"。
9. `[LOW]` **subkimi 挂掉前留下的**(它没出结论,但日志里这两条是实的)——
   ① submimo 只读档配置是 `json.dump(cfg, open(cfgpath,"w"))`,truncate 后逐步写,
   两个 agent 并发跑 review 时共享同一份配置 ⇒ 可能读到半截 JSON;
   ② `bin/submimo:24` 的 usage 还写着 "Uses MiMoCode plan agent" —— **本单整单推翻的
   正是这个 plan 档**,而且这行比头部注释更外显。→ 判据先行红过(`58de5a6`)、
   实现改 `tmp + os.replace`(`e08a2e3`)。**失败腿的日志也要读**,这条本仓记过账,今天又兑现一次。

**明账(不阻断,写下来不是"以后再说"):**

10. `[INFO]` submimo F2 / subdeepseek #2(明账)—— 白名单挡不住 `git diff --output=<path>`
    (能写)和 `--no-index <仓外文件>`(能读仓外),三条腿都一样。**这是本单公开承认
    挡不住的部分**,防线在 track `repo-write-audit`(检测,不是预防)。
11. `[INFO]` submimo F3 —— kimi 守卫比 opencode/submimo 多放行几个只读 git 子命令
    (blame/shortlog/rev-parse/ls-files/describe),而提示词只宣称 diff/log/show。
    方向安全(都是只读),但三条腿的清单不完全一致。见 Accepted deviations。
12. `[INFO]` subdeepseek #8 残余 —— 无网环境下"让底座自己解析"已是能做到的最强检查;
    opencode 若对 `permission.bash` 的运行时解释与 `debug config` 的输出不一致,判据仍看不出来。

### 我自己错在哪(数得出的 8 处,这一单的真实成本)

1. **方向错**:08-18 关掉 bash —— 被四审推翻,白花一天半。错因是我只问"白名单挡不住什么",
   没问"它挡住的是什么"(答案:误伤,而误伤才是评审腿的真实失败形态)。
2. 判据 V33「不许换 HOME」查 argv ⇒ **结构上永远绿**(subdeepseek 抓到)。
3. 判据 V9「不许裸 Bash」偏松,`Bash(git:*)` 能过(subdeepseek 抓到)。
4. 判据 V28 查我自己写的 JSON,不是底座解析出来的(subdeepseek 抓到)。
5. `bin/subkimi` 头部注释没跟着转向改(**同一件事写两处、只更新一处**,第 1 处)。
6. `bin/submimo:24` usage 行同上(第 3 处 —— 中间还有一处是 08-19 已改的)。
7. 08-18 给 opencode 立了兜底桩、**mimo 漏了**(同一份清单漏一个 ⇒ 判据跑一次留 5 组
   真 mimo 遗孤,而"内存不够 ⇒ 判据随机红"是本机记过的账)。
8. 这次断线后自己抓住的:判据里写了个 `$SELF_DIR` —— **凭空造的变量**,脚本里根本没有。
   跑之前查出来了(仓根变量是 `$BIN`)。

### 收据名字会撒谎(这一单新记的一条)

`evidence/` 里 **5 份名字带 `green-` 的收据其实 `rc=1`**(如 `green-after-impl`、
两份 `green-kimi`、`green-v32-artifacts`、`green-after-teardown`),
而 `red-mimo-floor2` 实际 `rc=0`。slug 是**我起的名字**(起名时我以为它会绿),
rc 是**机器写的**。归档闸查的是 rc(对的),但人扫一眼文件名会被带偏。
**和"行号不是断言的身份"是同一族**:别拿自己起的名字当身份。

### arbitrated verdict (主裁): **PASS**

三条出了结论的腿全 PASS,而**我不拿全票当降低标准的理由**(全票 PASS 也可能一起错,
本仓记过账)。我自己复核的结论:

- 拆得干净(`_prompt-budget.sh` 文件与引用全清,只剩会说话的墓碑);
- 恢复得一致(三条腿都是"写口全关 + bash 只读 git 白名单",逐腿核过);
- 删 V29~V32 成立(它们测的机制已整体拆除,留着只会永远绿/永远红),
  **真问题不在删除,在两条永远绿的反向断言**(已修);
- 转向的论证链没有被推翻的地方,而且**窗口期是明账**(拆完到 `repo-write-audit`
  上线之前 = 08-18 之前那个状态,不是本次新增的风险)。

红检(退回旧实现)证明这份判据确实在问本轮的改动:**80 条当场变红,且命中目标断言**
(`redcheck-panel3`,rc=0 = 红检通过);原子写那三条里,唯一真红过的是第三条
(`red-atomic-write`:366 passed / 1 failed),另两条(权限 600、无 tmp 残留)
**现在就是绿的** —— 它们是防回退的反向断言,不是这次改动的验证,**照实写,不冒充红检**。

## Accepted deviations

- **三条腿的只读 git 清单不完全一致**(submimo F3):kimi 守卫多放行 blame/shortlog/
  rev-parse/ls-files/describe。方向安全(全是只读),统一它需要动三处白名单 + 三处提示词
  + 对应判据,收益是"清单整齐"而不是"更安全"。**本单不做**,理由写在这儿而不是留空。
- **原子性本身没有机械验证**:三条断言里那条"必须 tmp + os.replace"是**字面断言** ——
  原子性只在写的那一瞬间存在,从产物里观察不到。它挡的是"未来改回直写",
  证明不了原子性。(与 #8「查自己写的东西」的区别:那条查**配置内容**,该让底座解析;
  这条查**写入机制**,机制不在产物里。)
- **`repo-write-audit` 未上线**:评审腿仍有能力写被评审的仓,且 panel 跑完没人检查。
  这不是本单新增的风险(08-18 之前一直如此),但它现在是**写下来的明账**,
  proposal 已落盘,不是"以后有空再说"。

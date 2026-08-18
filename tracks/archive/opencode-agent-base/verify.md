# Verify: opencode-agent-base

- Date: 2026-08-18
- Verdict: PASS(经一轮 BLOCK 修复后)

## Mechanical checks

- [x] build passes(纯 bash/python,`bash -n` 全过)
- [x] tests pass —— **339 passed / 0 failed**,且这一遍**在最后一次编辑之后**
- [x] no secrets / unsafe ops —— key 走 env 不走 argv、配置 umask 077 创建即 600、仓外;
      V26 ⑤ 查全仓被跟踪文件无 key 形状字符串

**机器打印的**(不是我的转述):

```
runlog: redcheck-v28 rc=1 commit=9e129d8 dirty=yes at=2026-08-18T11:03:38Z file=tracks/opencode-agent-base/evidence/20260818T110338Z-01-redcheck-v28.txt
runlog: redcheck-retarget rc=1 commit=2715c3b dirty=yes at=2026-08-18T11:30:33Z file=tracks/opencode-agent-base/evidence/20260818T113033Z-01-redcheck-retarget.txt
runlog: green-final rc=0 commit=171f29f dirty=yes at=2026-08-18T11:34:09Z file=tracks/opencode-agent-base/evidence/20260818T113409Z-01-green-final.txt
runlog: green-stdin-fix rc=0 commit=224a1e7 dirty=yes at=2026-08-18T12:00:40Z file=tracks/opencode-agent-base/evidence/20260818T120040Z-01-green-stdin-fix.txt
runlog: smoke-real-leg rc=0 commit=a39e8b0 dirty=yes at=2026-08-18T12:04:06Z file=tracks/opencode-agent-base/evidence/20260818T120406Z-01-smoke-real-leg.txt
runlog: green-trace rc=0 commit=65159e1 dirty=yes at=2026-08-18T12:16:15Z file=tracks/opencode-agent-base/evidence/20260818T121615Z-01-green-trace.txt
runlog: green-default-agent rc=0 commit=cdfbacf dirty=yes at=2026-08-18T12:34:37Z file=tracks/opencode-agent-base/evidence/20260818T123437Z-01-green-default-agent.txt
runlog: green-no-ambient rc=0 commit=076478a dirty=yes at=2026-08-18T12:56:16Z file=tracks/opencode-agent-base/evidence/20260818T125616Z-01-green-no-ambient.txt
runlog: panel-full rc=0 commit=7d189bd dirty=yes at=2026-08-18T13:02:08Z file=tracks/opencode-agent-base/evidence/20260818T130208Z-01-panel-full.txt
runlog: green-after-panel rc=1 commit=207b8d6 dirty=yes at=2026-08-18T13:37:56Z file=tracks/opencode-agent-base/evidence/20260818T133756Z-01-green-after-panel.txt
runlog: green-final-panel rc=0 commit=207b8d6 dirty=yes at=2026-08-18T13:42:51Z file=tracks/opencode-agent-base/evidence/20260818T134251Z-01-green-final-panel.txt
runlog: green-prompt-truth rc=0 commit=fb3dd49 dirty=yes at=2026-08-18T13:57:43Z file=tracks/opencode-agent-base/evidence/20260818T135743Z-01-green-prompt-truth.txt
runlog: green-final-receipt rc=0 commit=0916670 dirty=yes at=2026-08-18T14:04:58Z file=tracks/opencode-agent-base/evidence/20260818T140458Z-01-green-final-receipt.txt
runlog: smoke-final-receipt rc=0 commit=0916670 dirty=yes at=2026-08-18T14:08:19Z file=tracks/opencode-agent-base/evidence/20260818T140819Z-01-smoke-final-receipt.txt
```

**两份跑红的、和两份没有收尾行的,一份都没藏**(5b):

| 收据 | 什么情况 | 算不算数 |
|---|---|---|
| `redcheck-v28` rc=1 | 判据先行的红检(7 红) | **算** |
| `redcheck-retarget` rc=1 | 搬家后的红检,只剩 steps 上限那条红 | **算** |
| `green-after-panel` rc=1 | 四审修复后仍 1 红:V17 那条"explore 下 bash 仍是白名单"—— 因为 bash 已整个关掉,断言跟着收紧 | **算** |
| `20260818T110927Z-01-green-after-impl.txt`(**无收尾行**) | 我中途 kill 掉的。它就是**第一个 bug 的证据**:判据里的老用例去调**真** opencode,断网闸下变成每处干等 900 秒,判据被拖死 | **不算判卷结果,算故障证据** |
| `20260818T114214Z-01-smoke-real-leg.txt`(**无收尾行**) | 我中途 kill 掉的。**第二个 bug 的证据**:opencode 在 stdin 是开着的管道时一直等输入,挂死 12 分钟、一次模型调用都没发,而日志头已写好、从外面看像在跑 | **不算判卷结果,算故障证据** |

> 另有一份收据被我**删除**并如实记在这里:第一次真跑我把 `ZHIPU_API_KEY=sk-...`
> 写在命令行上,而 `runlog` 会原样记录命令 ⇒ 真 key 进了 evidence 文件。
> 已删除,并在工作树 + git 全历史确认没有扩散(两处 grep 均无命中)。
> 规矩:**secret 不许出现在会被收据工具记录的命令行上**。

## Review

- lane: **full** —— 碰 auth、碰钱,而且**换的是评审腿本身**(判卷防线),不打折。
- 派给: **主 agent 直接干** —— key/认证;验证必须打真端点而执行腿沙箱断网;
  每一步都要当场判"这是机械锁还是模型自觉"。
  返工 1 轮(四审 BLOCK 后)/ **自身错误 6 处**(见下)
- 规格自查(原文在 `my-review.md`,读任何腿的输出之前写的):
  规格可能错在「我把"能读仓库"当成了"读得对"」——被 40 步掐断在半路的腿,输出仍像正经评审。
  **收货时我亲自看了轨迹**:真跑那次它跑了 5 次工具调用(git status/log/Read/Glob/show)
  才下结论;最终版(bash 关掉后)2 次(Glob/Read),对 7 行的仓库够。
- 腿的花名册(原样粘自 `logs/panel-ocbase-0818.roster`):

```
# panel-review 花名册(2026-08-18 21:21:12)task=opencode-agent-base
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# 日志:logs/panel-ocbase-0818.*.log
submimo=PASS subdeepseek=PASS subglm=PASS subkimi=PASS
```

  > 裁决行:submimo PASS / **subdeepseek BLOCK** / subglm PASS / subkimi PASS。
  > (我第一遍 grep `^Conclusion:` 时以为 kimi 没给裁决 —— 它的输出有缩进,grep 没匹配到。
  > 当场更正过;花名册这一格从来只说进程 rc,判裁决要读日志。)
  > **这一轮四审本身就是新腿的实战**:subglm 是用本单刚换好的 opencode 底座跑的,
  > 日志头写着 `agent base: opencode CLI headless`,它交出了真发现(见下)。

- findings(主裁后的处置):
  - **[BLOCK,成立] 我那句"只读锁机械成立"是假的** —— subdeepseek 给的 BLOCK,
    kimi 和 subglm 也各自点到。bash 白名单 `git diff*` 挡不住 git 自己的参数:
    **我亲手复现了两条** —— `git diff --output=<path>` 写出任意文件;
    `git diff --no-index <仓外文件> /dev/null` 把任意可读文件全文打进 stdout ⇒ 进腿日志
    ⇒ **一个恶意仓可以让这条腿把订阅 key 印出来**。
    我当初的"实测"只证明了**链式**命令被拒,从没验过单条命令的参数 ——
    subglm 那条腿的原话最准:**"那是声称,不是判据验的"**。
    处置:**bash 整个关掉**(不是再拉黑几个参数 —— diff 选项在 git log -p / git show 上
    一样吃,还有 --ext-diff 之类口子,对 git 做命令行白名单本身就不成立)。
    已在真环境复验:同一条攻击命令,现在写不出文件,腿如实回答"我没有 shell"。
  - **[MEDIUM,成立] `command -v claude` 查错了对象**(subdeepseek 与 subglm 独立命中)
    —— opencode 底座不依赖 claude。已按底座查。
  - **[LOW,成立] key 经 argv + chmod 前有 644 窗口** —— 已改 env 传 key + umask 077。
  - **[LOW,成立] 日志头 `model:` 印裸名字** —— 已印完整 `go/glm-5.2`。
  - **[LOW,成立] 两处注释还提"顶部 export"**(那行已删)—— 已清。
  - **[真跑挖到,腿之外] 提示词在宣称一个它没有的工具** —— bash 关掉后,提示词仍写着
    "read-only git commands"。真跑时这条腿当场顶回来:"The task's premise that I have
    'read-only git commands' is incorrect",并为此白花了几轮。已按底座给能力清单。
- arbitrated verdict (主裁): **PASS**(修复后)。
  BLOCK 那条我没有按票数处理,而是**自己复现了两条攻击路径**才认;
  另外五条逐条验过后全部落地并配了断言;最终 339/0 跑在最后一次编辑之后,
  真端点冒烟 rc=0 拿到裁决行。

## 我自己犯的 6 处错(不摊进"这事本来就难")

1. **把真 key 打进收据文件**(已清理,规矩已立)。
2. **"只读锁机械成立"言过其实** —— 我把"链式绕法被拒"当成了"参数级也安全",
   还把这句话写进了代码注释和文档。四审推翻。
3~6. **四条假绿判据**,而且是同一天里的第 2~5 条:
   - `check "..." $([[ $? -ne 0 ]]; echo $?)` —— 命令替换里的 `$?` 不是上一条的退出码;
   - 单行 grep 找 argv —— 参数在**续行**上,永远匹配不到;
   - "不含某串"的否定断言插在生成输入的用例**之前** —— 输入缺席 ⇒ 报绿;
   - (前一单已记)问"默认档"却在被污染的环境里问。
   **根因我这次拔掉了**(删掉判据顶部那行全局 export),但假绿的另一半形状 ——
   **"输入缺席时否定断言会假绿"** —— 本文件里早有注释警告过,我还是又踩了一次。

## Accepted deviations / 敞着的账

- **这条腿看不了 git 历史/diff 了**(bash 整个关掉的代价)。核心能力(自己读仓库)
  由 read/glob/grep 提供,一条没丢;要 diff 就由主 agent 用 PANEL_INCLUDE 喂。
- **⚠️ 同一个洞很可能也在 DeepSeek 那条腿上**:它走 claude 壳,白名单是
  `Bash(git diff:*)` —— 形状一模一样,`git diff --output=` 大概率同样能写。
  **本单没有验、也没有修**(不在范围内),**这是一笔敞着的安全账,应当立刻起一单**。
- `invalid` 这个 opencode 内部工具没关也没研究过它是什么。
- 首次在全新隔离 home 里跑会下 ~156M 运行时,慢一次;opencode 升级可能改配置 schema,
  目前没有防线,只有"下次真跑时会当场发现"。

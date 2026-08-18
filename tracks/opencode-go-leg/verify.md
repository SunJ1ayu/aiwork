# Verify: opencode-go-leg

- Date: 2026-08-18
- Verdict: PASS

> Panel hook — 软判断(correctness/security/edge/spec-drift)走 panel-review:
> 主 agent 先独立审并落 findings,再跑 panel-review 的全部评审腿,主 agent 主裁。
> build/test 跑通是机械检查。

## Mechanical checks

- [x] build passes(纯 bash/python 脚本,`bash -n` 全过)
- [x] tests pass —— **311 passed / 0 failed**,且这一遍**在最后一次编辑之后**
- [x] no secrets / unsafe ops —— key 在仓外 600;V26 ⑤ 查全仓被跟踪文件无 key 形状字符串

**机器打印的**(不是我的转述):

```
runlog: redcheck-before-impl rc=1 commit=da5d244 dirty=yes at=2026-08-18T07:51:17Z file=tracks/opencode-go-leg/evidence/20260818T075117Z-01-redcheck-before-impl.txt
runlog: redcheck-mutant-bearer rc=1 commit=cd1c356 dirty=yes at=2026-08-18T08:05:24Z file=tracks/opencode-go-leg/evidence/20260818T080524Z-01-redcheck-mutant-bearer.txt
runlog: mutant-baseurl-v1 rc=1 commit=5b250c9 dirty=yes at=2026-08-18T09:21:17Z file=tracks/opencode-go-leg/evidence/20260818T092117Z-01-mutant-baseurl-v1.txt
runlog: mutant-no-ua rc=1 commit=5b250c9 dirty=yes at=2026-08-18T09:24:23Z file=tracks/opencode-go-leg/evidence/20260818T092423Z-01-mutant-no-ua.txt
runlog: mutant-default-agent rc=1 commit=5b250c9 dirty=yes at=2026-08-18T09:29:54Z file=tracks/opencode-go-leg/evidence/20260818T092954Z-01-mutant-default-agent.txt
runlog: redcheck-v27 rc=1 commit=5b250c9 dirty=yes at=2026-08-18T10:03:31Z file=tracks/opencode-go-leg/evidence/20260818T100331Z-01-redcheck-v27.txt
runlog: panel-full rc=0 commit=5b250c9 dirty=yes at=2026-08-18T09:42:31Z file=tracks/opencode-go-leg/evidence/20260818T094231Z-01-panel-full.txt
runlog: smoke-final rc=0 commit=5b250c9 dirty=yes at=2026-08-18T09:34:49Z file=tracks/opencode-go-leg/evidence/20260818T093449Z-01-smoke-final.txt
runlog: green-final rc=0 commit=3256e60 dirty=yes at=2026-08-18T10:16:10Z file=tracks/opencode-go-leg/evidence/20260818T101610Z-01-green-final.txt
runlog: smoke-after-final rc=0 commit=3256e60 dirty=yes at=2026-08-18T10:21:35Z file=tracks/opencode-go-leg/evidence/20260818T102135Z-01-smoke-after-final.txt
```

### 跑红的每一份(5b:一份都不许藏)

上面那段原本是散文式的"另有 6 份收敛过程中的收据",**归档闸当场把它拒了** ——
规矩 5b 要的是每一份红收据的**收据行在场**,不是我的转述。闸是对的:我贴了好看的、
把红的总结掉了,而红的那几遍才是这一单最值钱的部分。逐份补上,每份一句它红在什么上:

```
runlog: oracle-after-impl rc=1 commit=cd1c356 dirty=yes at=2026-08-18T07:59:09Z file=tracks/opencode-go-leg/evidence/20260818T075909Z-01-oracle-after-impl.txt
runlog: smoke-real-endpoint rc=1 commit=b411638 dirty=yes at=2026-08-18T08:14:49Z file=tracks/opencode-go-leg/evidence/20260818T081449Z-01-smoke-real-endpoint.txt
runlog: smoke-chat-leg rc=1 commit=b411638 dirty=yes at=2026-08-18T08:21:18Z file=tracks/opencode-go-leg/evidence/20260818T082118Z-01-smoke-chat-leg.txt
runlog: smoke-chat-leg-2 rc=1 commit=b411638 dirty=yes at=2026-08-18T08:23:38Z file=tracks/opencode-go-leg/evidence/20260818T082338Z-01-smoke-chat-leg-2.txt
runlog: redcheck-three-new rc=1 commit=b411638 dirty=yes at=2026-08-18T08:44:49Z file=tracks/opencode-go-leg/evidence/20260818T084449Z-01-redcheck-three-new.txt
runlog: redcheck-default-chat rc=1 commit=b411638 dirty=yes at=2026-08-18T08:48:27Z file=tracks/opencode-go-leg/evidence/20260818T084827Z-01-redcheck-default-chat.txt
runlog: redcheck-default-chat-2 rc=1 commit=b411638 dirty=yes at=2026-08-18T08:52:23Z file=tracks/opencode-go-leg/evidence/20260818T085223Z-01-redcheck-default-chat-2.txt
runlog: redcheck-default-chat-3 rc=1 commit=b411638 dirty=yes at=2026-08-18T08:56:27Z file=tracks/opencode-go-leg/evidence/20260818T085627Z-01-redcheck-default-chat-3.txt
runlog: green-after-impl rc=1 commit=66f4d2d dirty=yes at=2026-08-18T09:12:54Z file=tracks/opencode-go-leg/evidence/20260818T091254Z-01-green-after-impl.txt
runlog: panel-full rc=1 commit=5b250c9 dirty=yes at=2026-08-18T09:41:50Z file=tracks/opencode-go-leg/evidence/20260818T094150Z-01-panel-full.txt
runlog: green-final rc=1 commit=03a1f49 dirty=yes at=2026-08-18T10:08:00Z file=tracks/opencode-go-leg/evidence/20260818T100800Z-01-green-final.txt
```

| 收据 | 红在什么上 | 算不算数 |
|---|---|---|
| `oracle-after-impl` | 头一版实现之后仍有 2 条红(默认档那两处) | **算** —— 判据在正确地咬 |
| `smoke-real-endpoint` | 真端点第一次:**404 被 CLI 报成「模型 glm-5.2 不存在」**。地址多了一层 `/v1` | **算** —— 这条红逼出了"base URL 不带 /v1"那条判据 |
| `smoke-chat-leg` / `-2` | 聊天腿被 Cloudflare **403(code 1010)**,urllib 默认 UA 被按指纹挡 | **算** —— 逼出了 User-Agent 那条判据 |
| `redcheck-three-new` | 5 红:含两条真红 + **判据自己没跑起来**(stub 用 /dev/tcp 探活,把 `handle_request()` 唯一那次服务用掉了) | **算,但其中 1 条是量具坏了**,已在判据注释里写明 |
| `redcheck-default-chat` 1/2/3 | 4→3→2 红,是我修**判据自己的 bug** 的过程(第二个坑:拿本节自造的桩去问"请求带没带 UA",问的是空气) | **算** —— 这三份记录的是判据被修好的过程,不是实现被改到及格 |
| `green-after-impl` | 只剩 1 红:`panel: GLM leg defaults to chat leg` | **算,且是这单最值钱的一条红** —— 我先隔离复现(拿到 CHAT-LEG,实现是对的)才判定是量具坏了(顶部全局 `export PANEL_GLM_LEG=agent` 污染),**没有顺着"改实现迁就判据"走** |
| `panel-full`(094150Z) | 四审第一次被**反锚定闸**拦下:我那份 my-review 放在了被评审的仓内(这次被审的就是 /root/aiwork 自己),引擎会把它内联进腿的提示词 = 喂标准答案 | **不算判据结果**,是闸正确拦下我。挪到仓外重跑 = 094231Z 那份 rc=0 |
| `green-final`(100800Z) | 1 红:`subchat -h 不许还写着 bigmodel 端点` | **算,但断言本身写糙了** —— 它把"从智谱 bigmodel 换来"这句沿革句也禁了。已把断言**搬到问得出的地方并加强**(禁主机名 + 正面钉死全址),并重新红检过(3256e60) |

全部随本 track 入库(5d)。

**这两条最值钱**:
- `green-final` rc=0 是**最后一次编辑之后**那一遍(本机三次栽在"给的绿是过期的")。
- `smoke-after-final` 跑在最终 commit 上,**且在卸掉 opencode CLI 之后** ——
  它同时证明"腿还活着"和"卸载没弄坏它"。

## 红检 / 变异(这单的重点)

三条新判据是**先踩坑、事后补**的,"红过"不能靠时间顺序 ⇒ 逐条变异证明它咬得动:

| 变异 | 结果 | 基线(deepseek 组) |
|---|---|---|
| base URL 改回带 `/v1` | 3 条红(V9 + V26×2) | 32 条全绿 ⇒ 精确咬中,不是整片红 |
| 删掉 `User-Agent` 那行 | 恰好 1 条红 | 绿 |
| 默认档改回 `agent` | 2 条红(同一件事的两处写法) | 绿 |
| (V27)挖空 `AUTH_ENV` | 3 条红,**且前置"这一刀真切中了"是绿的** | 绿 |
| (V27)`-h` 塞回旧端点 | 2 条红 | 绿 |

## Review

- lane: **full** —— 碰 auth(认证 header 风格 + key 落位)和钱(付费订阅入口),
  硬规矩不打折。针孔薄不是降档的理由。
- 派给: **主 agent 直接干** —— ① key 落盘 =「改密钥」,外部执行腿硬禁;真跑冒烟要打
  付费端点,而执行腿沙箱断网**跑不了这份考卷**。② 改动 <20 行、全在供应商表里。
  ③ 判卷不需要起服务。
  返工 0 轮 / **自身错误 4 处**(见下 F3/F5 与"判据自己坏过"两条)
- 规格自查(读任何 panel 输出之前答的,原文在 `my-review.md`):
  规格若错,会错成「我把"腿能出报告"当成了"腿有用"」——聊天腿看不见仓库,
  四审第三腿从此是个只看 diff 的评审,**满编但含金量下降,而花名册上它是 PASS**。
  判断:仍值得开(三腿→四腿,带 `PANEL_INCLUDE` 时有效),但**代价必须写进文档**
  (已写进 legs.md / design.md / subchat 注释三处),这条腿的结论要按"只看得见我喂给它的
  东西"来读。**本单的冒烟本身就是这条自查的实证**:第一次没喂 `bin/panel-review`,
  它诚实地回了 `NEEDS_MORE_INFO`。
- 腿的花名册(原样粘自 `logs/panel-opencodego-0818.roster`):

```
# panel-review 花名册(2026-08-18 17:57:32)task=opencode-go-leg
# PASS = 进程 rc=0,**不等于给了裁决**;off = 这条腿压根没派(不许读成通过)。
# 日志:logs/panel-opencodego-0818.*.log
submimo=FAIL(rc=124) subdeepseek=PASS subglm=PASS subkimi=PASS
```

  > 花名册上 **subkimi=PASS 但它没给裁决行**(rc=0 ≠ 给了结论,花名册头一行自己就写着)——
  > 读日志才知道它其实给了完整报告和 `Conclusion: PASS`,只是收尾格式没被 grep 到。
  > **submimo=FAIL(rc=124) 是超时**;读它的日志时发现它在复述第一份收据时把
  > `282 passed, 13 failed` 写成了 `18 failed` ⇒ **超时腿的数字一律不作数**。

- findings:
  - **[MEDIUM] `panel-explore` 的 GLM 默认档漏改** —— kimi 与 deepseek **两腿独立命中,
    我自审漏了**。行为级复现过(它真的派 subglm-agent)。底座腿在 Go 上必 400 ⇒
    每轮先白撞一次再降级。已修 + 两条断言(默认走 chat / 仍能强制 agent)。
  - **[MEDIUM] `AUTH_ENV` 无守卫(我的 F1)** —— 表驱动自己的失败模式没人管。
    **两条评审腿(deepseek/glm)都断言这里是 fail-closed —— 实测证明它们都错了**:
    GNU coreutils 9.4 下 `env '=key' cmd` **rc=0、不报错**,子进程拿到一个空名变量,
    真正的认证变量一个没设 ⇒ 腿活着、每次 401,日志只显示"模型没回话"。
    这正是本单要根治的病。已加守卫 + 3 条断言(硬失败 / claude 不许被调起 / 报错点名)。
    **全票 PASS 不降低我自己的标准;腿说的话我自己验过才算。**
  - **[LOW] `subchat` 注释"默认腿是底座腿 subglm-agent"(我的 F2)** —— GLM 自己也挑出来了。
    这句话**在写下的那一刻就是错的**,而且恰好写在聊天腿自己的供应商表里。已修。
  - **[LOW] `-h` 帮助文本是化石** —— deepseek 与 glm 都翻出来:`glm-4.6v`、bigmodel 端点、
    旧 auth 路径。只在 `-h` 时打印 ⇒ 没人跑得到 ⇒ 仓里最容易变成化石的地方。已修 + 断言。
  - **[INFO] 行号引用(我的 F3,我自己引入的)** —— 我写的注释里有"下面第 207 行那条 HINT",
    **实际是 221 行,写下时就已经错了**(行号从改动前的文件抄的,我加的注释自己把它推下去)。
    而且我把同一个错数字**又抄进了 design.md**(deepseek 指出)。两处都已改成按内容描述。
    行号不是身份 —— 本机第 N 次。
  - **[INFO] V26 UA stub 用固定端口 8791(我的 F4,deepseek 同)** —— 端口被占就误红,
    本机刚吃过"断线遗孤占端口"。已改成绑 0 让内核挑端口。**误报和假绿一样坏。**
  - **[INFO] 反锚定闸在"自审本仓"时提示词是错的** —— 闸拦住我之后建议
    「Move it outside, e.g. /root/aiwork/tasks/<name>-my-review.md」,而那正是被拦的目录
    (默认路径写死在 `panel-review:79`)。审 aiwork 自己时必须 `--require-my-review`
    指到仓外。本单没改它(不在范围内),**记在这儿当欠账**。
  - **[INFO] 各腿 `.err` 都印了「--panel-dispatch 跳过了反锚定闸,而 …my-review.md 并不存在」**
    —— 外层其实走了 `--require-my-review`,只是那个路径没往下透传给各腿。误导性提示,
    同一笔欠账。

- arbitrated verdict (主裁): **PASS**。
  三条给了裁决的腿都是 PASS,但我不是因为票数判的:每条发现我都自己验过,
  其中**最重要的一条(AUTH_ENV)两条腿都判错了方向,是我实测推翻的**;
  另一条(panel-explore)是两腿命中、我自审漏的。四条 findings 全部已修并配了断言,
  最终 311/0 跑在最后一次编辑之后,真端点冒烟在最终 commit 上 rc=0 拿到裁决行。

## Accepted deviations

- **GLM 这条腿从"能自己读仓库的底座腿"降级成"只看得见我喂的东西的聊天腿"**。
  不是等价替换,是"能用的腿"换掉"跑不起来的腿"(Go 不做工具格式转换)。
  代价已写进三处文档,`PANEL_GLM_LEG=agent` 一个环境变量就能切回去。
- **`ZHIPU_*` 这套 env 变量名留着没改**,尽管它现在打的是 OpenCode Go 不是智谱。
  改名要动供应商表、判据、文档三处,本单不做;`legs.md` 里已写明"它是第三条腿的前缀,
  不是智谱的缩写"。
- **`legs.md` 在仓外**(`/root/.claude/skills/panel/references/legs.md`),
  本仓 diff 验证不到它 —— deepseek 专门点了这一条。我确认改了(端点/UA/默认档/代价四处),
  但**这份工件的证据不在本仓**,如实记在这儿。
- **panel 四审跑在 `5b250c9`**,此后的两个 commit(`03a1f49` 实现 + `3256e60` 判据搬家)
  正是在落地这些腿的发现,没有再引入新面;这些改动由 V27 的 10 条断言 + 最终 311/0 兜住。

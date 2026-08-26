# Tasks: subgemini-review-leg

**判据先行**:每组都是「先 commit 判据(此刻红) → 再 commit 实现」。判据由主 agent 亲自写,不外包。

## A. 判据(先行,先红)

- [x] A1 `tests/test-subgemini.sh` 骨架 + 夹具(假 agy 桩,不烧真额度;真链冒烟单独一条)
- [x] A2 **模型闸**:`AGY_MODEL=claude-opus-4-6-thinking` 拒跑且说出真因;
      `gemini-3.6-flash-high` 放行;默认值确为 `gemini-3.7-flash-high`
- [x] A3 **隔离闸**:整轮跑完业主 `~/.gemini/antigravity-cli/` 无一文件被改(mtime+sha 双比)
- [x] A4 **凭证形态闸**:评审 home 的 token 是**普通文件非 symlink**、权限 600
- [x] A5 **遥测闸**:评审 home 的 `settings.json` 必须 `enableTelemetry: false`
      (业主已明确选择关闭;隔离 home 默认无此文件 = 走默认值 = 绕过他的选择)
- [x] A6 **仓外闸**:运行期 home 落在被评审仓内 ⇒ 拒跑(复用 `_review-home-guard.sh`)
- [x] A7 **响亮失败**:凭证缺失/失效 ⇒ 非零退出 + 明确错误,不许挂死、不许静默 PASS
- [x] A8 **rc 不可信**:构造「rc=0 但输出无裁决行」⇒ 必须判失败
- [x] A9 **裁决 gate**:三种结论都认得出;全角冒号不误判
- [x] A10 **fix 拒绝**:`subgemini fix` 拒绝
- [x] A11 **花名册**:`PANEL_LEGS_ORDER` 含 subgemini;`panel-roster` 从盘上渲染得出

## B. 实现

- [x] B1 `bin/subgemini`:review 模式,`env HOME=$AGY_REVIEW_HOME agy -p ... --model ... --add-dir <副本>`
- [x] B2 隔离 home 准备:建目录、**复制**(非链接)token 600、写死 `enableTelemetry:false`
- [x] B3 模型硬闸(`^gemini-` 不匹配即拒跑)
- [x] B4 预检:派发前确认凭证有效(轻量 `agy models`),失效则响亮失败
- [x] B5 裁决 gate + 硬超时(`AGY_TIMEOUT`,并带 `--print-timeout`)
- [x] B6 接 `_my-review-gate.sh`(反锚定)与 `_review-home-guard.sh`,缺件即拒跑
- [x] B7 接现行「可丢弃副本 + 原仓只读」:workspace 只指副本

## C. 收口

- [x] C1 红检(变异测试):证明 A2 / A3 / A5 / A8 改坏实现时真的会红
- [x] C2 挂进 `_panel-roster-lib.sh` 的 `PANEL_LEGS_ORDER` + `panel-review` 健康池
- [x] C3 `skills/panel/references/legs.md` 补 subgemini 一节(唯一源),
      并同步 `sync-workflow-docs --check` 零漂移
- [x] C4 真链冒烟:真跑一次评审,裁决行解析正确、业主 home 未被碰
      (08-26 00:21 第五轮成功,腿第一次真交卷;**接上 ro-repo-exec 之后要再跑一次**)
- [x] C5 四审(high ⇒ 2 条不同家族的健康腿)—— subdeepseek / subglm **双 BLOCK**,
      11 条发现,我自己逐条去核(见下面 F 段)
- [x] C4b 接上只读挂载 + 上锁 + 删凭证之后再跑真链冒烟:
      `evidence/subgemini-smoke7.log` 由活的 `gemini-3.7-flash-high` 完整交卷并给出 BLOCK；
      它提出的 P7 / V22 缺口均已落地，凭证副本跑后不存在
- [x] C7 第二轮及收口轮四审均已完成；最终可恢复裁决为 submimo PASS / subdeepseek PASS，
      subglm 虽未写可解析裁决，但其中两项中等发现与一项低项均已复现并修复
- [x] C6 verify + 主裁完成；最终机器收据三套判据 523/0 + 62/0 + 41/0，
      本次提交执行归档

## F. 四审(第一轮)双 BLOCK 的落地情况

两条腿各自独立命中同一批要害;我自己造探针逐条去核,**没有一条不成立**,
而且量到两条腿都没说的东西(`selected_identities` 在 set -u 下崩掉、plan 的
`selected=` 变空行)。落地:

- [x] F1 派发根本没接上(选中它 ⇒ 什么都不启动 ⇒ `$!` 拿到上一条腿的 pid ⇒
      **给一条从没跑过的腿记 rc=0**)⇒ 腿的身份改成一张表 + 唯一派发路径
- [x] F2 专防 F1 的那条断言是假绿(`grep -q subgemini bin/panel-review`)⇒
      换成行为级、且对**每条腿**各问一遍(tests/test-panel-observation.sh 的 P7)
- [x] F3/F6 红检基线写死 `TOTALS 17 0`,判据长到 19 条那天起**整套变异一次都没跑过**
      ⇒ 基线改成"只问零红",不再抄条数
- [x] F4/F5 `ro-repo-exec` 只写在注释里、代码一个字没接 ⇒ 真接上(判据 V46⑫ 试写实测)
- [x] F7 并发串味(固定 home + 每轮不同的副本路径)⇒ 非阻塞 flock,撞上响亮拒跑
- [x] F8 任务文件缺失被静默吞掉 ⇒ 拒跑
- [x] F9 凭证副本长期留盘 ⇒ 跑完即删(trap 装在拷贝之后立刻,中途 die 也擦)
- [x] F10 家族记账两处漏了它(还多两处:屏幕上那行 family 印的是另一套词、
      HEAD 移动横幅的日志循环)⇒ 全部由表派生
- [x] F11 超时但有裁决 ⇒ 收下,但报告里追加"这是部分运行"横幅

## G. 修的过程中**自己造出来**的两个洞(都已判据先行 + 修好)

- [x] G1 红检被 SIGTERM 砍掉时 **EXIT trap 不执行** ⇒ M13 的变异留在了工作树里,
      而我扫特征那一遍恰好漏掉它 ⇒ 之后两次判据 25/2,我先怀疑并发、再怀疑锁,
      第三轮才发现红的是**被污染的实现**。修:INT/TERM/HUP 也还原 + 留 inflight 痕迹,
      下一轮拒绝再跑(V46⑰/⑰b)。**差一步就把一个被变异过的 wrapper 提交上去。**
- [x] G2 评审 home 那把锁的 fd 被整棵子进程树继承 ⇒ 腿被砍留下的孤儿替它举着锁 ⇒
      之后每一轮都被判成"撞车",而根本没有腿在跑(**对着幻影报警的闸比没有闸更坏**)。
      我自审写下过这条疑虑但第一次探针太弱没复现,换 setsid 孤儿一次就复现。
      修:模型那一支 `9>&-`(V46⑱)。
- [x] G3 红检当场照出我自己一条**假绿**:⑧a 一直是 `grep -q subgemini <花名册文件>`,
      而我把腿名单换成表之后,表上面的注释里全是这几个字母 ⇒ 整条腿删掉它照样绿。
      改成问数据(名单里到底有没有它)。

## 本单中途新长出来的账(记在这里,不许悄悄消失)

- [x] E1 headless 权限:命令白名单 + read_file 限定副本(真链冒烟连抓四轮才收敛)
- [x] E2 `bin/subgemini-diag`:agy 的失败信息从不说是哪个命令,这个工具把它挖出来
- [ ] E3 **腿目前不能跑判据/测试**。`ro-lock-teardown` 的 proposal 写着评审腿应当
      "能运行本地判据、编译和诊断",而本腿的白名单只给只读 git —— 真链冒烟里它
      确实想跑 `bash tests/mutation-subgemini.sh` 被拒。放行 bash 等于放弃
      "只看得见副本"这条边界(bash 能读 ~/.ssh),所以本单**故意不做**,
      单开一单想清楚(可能的方向:在副本里跑但整体套 sandbox/namespace)。
- [ ] E4 一次 soft-deny 就让整个 run 零产出。本单靠"把沙箱边界写进提示词"绕开,
      那是**引导不是保证** —— 模型仍可能去调被拒的工具。真正的修法要么是
      agy 改行为,要么我们能在派发前枚举它会用的工具。

## 敞账(不在本单做,单开)

- [ ] D1 闭源二进制**后台自我更新** ⇒ 判卷防线上有会自己变的构件
- [ ] D2 `--mode plan` 是机械锁还是模型自觉(本单不依赖它,但迟早要量)
- [ ] D3 **仓外的读还敞着,而且四条 agent 腿都一样**:`ro-repo-exec` 只把被评审的
      原仓变只读,管不住 `git diff --no-index /root/.ssh/id_rsa` 这类把任意可读文件
      打进评审日志的路子(08-19 已实证)。命令白名单是前缀匹配,挡不住 git 自己的
      参数 —— 它从来不是边界。要堵得给 `ro-repo-exec` 加"遮住敏感路径"的能力,
      跨四条腿的改动,单开一单。**本单不假装已经解决**(legs.md 与代码注释都照实写)。

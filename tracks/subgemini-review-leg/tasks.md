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
- [ ] C4 真链冒烟:真跑一次评审,裁决行解析正确、业主 home 未被碰
- [ ] C5 四审(high ⇒ 2 条不同家族的健康腿)
- [ ] C6 verify + 主裁 + 归档

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

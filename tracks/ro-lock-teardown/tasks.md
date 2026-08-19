# Tasks: ro-lock-teardown

- base-ref: 0813d81(本单开工时的 HEAD)
- 顺序不可换:**先堵洞(S1)→ 钉落点(S2)→ 拆锁(S3)→ 收判据(S4)**。
  反了就有一段"洞还在、锁已走"的净变弱窗口。

## S1 堵住 bash 白名单的写出洞(拆锁的前置条件)

- [ ] S1a 判据先行:O1 —— 三条腿的 git 白名单**不许**放行 `git diff --output=…`
      (含 `--output=x` 与 `--output x` 两种写法)。**此时必须红**,红收据入 evidence。
- [ ] S1b 堵 mimo:`bin/submimo` 生成的 `mimocode.json` 里 bash permission 收紧
- [ ] S1c 堵 claude 壳(deepseek/glm):`bin/subagent` 的 `--allowedTools` 收紧
- [ ] S1d 堵 kimi:`kimi-review-home/hooks/guard.mjs` 收紧
- [ ] S1e O1 转绿 + 变异红检(把任一腿的收紧拆掉,O1 必须红)

## S2 腿的产出落点钉到仓外

- [ ] S2a 判据先行:O3 —— 跑一轮 review 之后,仓内不出现 `.mimocode/`
      (**必须用 `git status --porcelain --ignored`**;`.mimocode` 在 `.gitignore:46`,
      不带 `--ignored` 看不见 —— 这正是我最初方案对真实案例是瞎的地方)
- [ ] S2b 让 mimo 的 plan 落在仓外(配置项优先;没有配置项就改 cwd/环境变量)
- [ ] S2c O3 转绿

## S3 拆掉只读锁

- [ ] S3a 摘 `bin/subkimi`(148-149 的 fail-closed 检查、149 的 `RO_EXEC=`、226 的调用)
- [ ] S3b 摘 `bin/submimo`(133-135、257)—— 注意它本来就对 `fix` 模式免锁,别把那个分支删花
- [ ] S3c 摘 `bin/subagent`(290-291、357、385)
- [ ] S3d 删 `bin/ro-repo-exec`
- [ ] S3e 三条腿各真跑一次 review 冒烟(不是看代码,是看它真出裁决)

## S4 逐条收判据(不许按区间删)

- [ ] S4a 逐条列出"仅在仓被挂只读时才成立"的断言,每条写明依据
      (候选:V35 主体 / V36 的 BLOCKED 断言 / V39 / V40④⑤ / V42 全部)
- [ ] S4b **保留**:V37(argv 写口为零)、V38(运行期 home 在仓外)、V41(判据不许把注释交给 shell)
- [ ] S4c 判据先行:O4 元断言 —— V37/V38/V41 三个函数必须仍在调用列表里
- [ ] S4d 变异红检:故意摘掉 V38 的调用,O4 必须变红(证明它不是永远绿)
- [ ] S4e 删除 S4a 列出的断言,跑全量,收最终绿收据

## S5 收口

- [ ] S5a verify.md:lane = **full**(碰的是权限/写口防线,针孔再薄也不打折)
- [ ] S5b 主 agent 先自审并落盘,再跑 `panel-review` 四腿
- [ ] S5c 仲裁 → 落地 → 最终收据跑在**最后一次编辑之后**
- [ ] S5d 归档

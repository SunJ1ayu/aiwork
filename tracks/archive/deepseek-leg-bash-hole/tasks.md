# Tasks: deepseek-leg-bash-hole

- base-ref: ef5272a6f8aa5a74c45394615cc62aece725f879

> 全程**主 agent 直接干**,没有外部执行腿(理由见 verify.md 的「派给」)。
> 所以下面这条委托纪律本单没用上,留着是模板原文:
> 委托 submimo fix 时:主 agent 先写失败测试(oracle)并 commit,再把窄范围实现
> 交给它;oracle/测试文件对它 off-limits;~2 次红了收回主 agent。

## 做完的

- [x] **T1 查清 DeepSeek 腿是不是同一个洞**(记忆里欠的那一单):是 —— 三条腿形状相同。
- [x] **T2 08-18 方向:三条腿一律关掉 Bash** —— **被四审推翻**,已整体退回。
      推翻理由:关掉 bash 后腿静默起不来,而 panel 照常出结论;
      "腿没跑起来还出结论"比"腿可能写个文件"危险得多。
- [x] **T3 拆掉 diff 注入那一整套**:`bin/_prompt-budget.sh` 整个文件 + 两处 wrapper
      的注入段 + 判据 V29~V32(留会说话的墓碑)。
- [x] **T4 恢复只读能力、不恢复写口**(三条腿一个规格):
      写口(write/edit/patch/task/webfetch/websearch/skill)全关;
      bash 留着但必须是**只读 git 白名单**(`*` deny + git 只读子命令 allow)。
- [x] **T5 白名单定位改写**:从"挡对手"改成**"挡误伤"** —— 它确实挡不住
      `git diff --output=` / `--no-index`(明账),但 08-19 实证它挡得住误伤:
      没有白名单的那条腿当场去 `cat` 仓外文件、还跑了判据;有白名单的 kimi 腿被拦 7 次。
- [x] **T6 submimo 不再用内置 `plan` 档**(上一轮 subkimi 孤腿 BLOCK 抓出来的):
      实测 plan 档自称 "Disallows all edit tools",实际 bash/write/edit/task 全开
      + 权限 `*` allow。改用自建 `aiwork-review` 档,隔离走 **XDG_CONFIG_HOME 不是 HOME**
      (换 HOME 会把 mimo 凭证一起换掉 ⇒ 腿只会"没回话")。`fix` 一个字没动。
- [x] **T7 判据兜底桩**:opencode 和 mimo 两层都要有(08-18 只给了 opencode,
      mimo 漏了 ⇒ 跑一次判据留 5 组真 mimo 遗孤)。`debug` 子命令放行真二进制,
      因为 V28/V33 靠它取证 —— 拿桩验锁 = 验我自己写了什么。
- [x] **T8 第四轮四审的 8 条发现全部落地**(逐条见 verify.md findings)。
- [x] **T9 subkimi 挂掉前留下的 2 条也落地**:配置原子落盘(tmp + os.replace)、
      usage 行不再宣传被推翻的 plan 档。
- [x] **T10 红检**:退回旧实现 80 条当场变红且命中目标断言(`redcheck-panel3`);
      原子写那条单独红过(`red-atomic-write` 366/1)。
- [x] **T11 最终收据**:367 passed / 0 failed,**在最后一次编辑之后**跑的那一遍。

## 划出范围的(不是忘了)

- [ ] **V34「panel 跑完查工作树」→ 挪去 track `repo-write-audit`**。
      它是一个独立工程,塞进这个已经跑偏一天半的 track 会把两件事一起拖垮。
      **窗口期是明账**:拆完到它上线之前,状态 = 08-18 之前那样
      (腿有 bash、能写仓、没人查)—— 不是本次新增的风险,但现在写下来了。

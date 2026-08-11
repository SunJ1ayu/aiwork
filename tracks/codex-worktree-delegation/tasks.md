# Tasks: codex-worktree-delegation

- base-ref: a6d65f088544e3a27bb5b8efa22ba88787ba5693
- lane: **full**(改的是判卷防线本身:攻题闸 + 收货闸①)
- 派给: **主 agent 亲写,不外包** —— 理由不是"我想自己干":被改的入口正是执行腿的验收边界
  (design A2 实测:`--repo /root/aiwork` + 默认日志被「卷宗不许进仓」闸拒发,派不出去)。

## Design convergence(已完成)

- [x] T0 Claude Code 按 proposal 接手协议:先不读 design 的技术方案,独立落一版方向。
      (08-11 15:24 写,断线丢盘,15:57 从会话记录逐字节取回;独立性成立。)
- [x] T1 重新检查现有 `delegate-codex`、delegate skill、track 约定和最近真实工件,
      对 design 的 12 条攻击清单逐条给代码/行为依据。(12 条见 design「六」;三条攻击有机器收据。)
- [x] T2 合并回 design 的「Claude Code 对抗与合并」,与用户收敛范围。
      (08-11 傍晚用户「开始实现吧」⇒ Status: selected,三条拍板记在 design「九」;
      第 2 条 `--isolate` 默认开是**我替他定的**,已在 design 里标明。)
- [x] T3 耗时基线:note-source 主 agent 段 100 分钟 / 执行段 4.5 分钟;owner-consent 执行 ≈12
      分钟、收货跨夜;anydoc 22 分钟执行 / 53 分钟收货。⇒ Phase C 净收益为负,驳回。

> **范围已改写**:只剩 Phase A + 一条前置 P0,规格在 design「十」。
> Codex 原方案的 T7–T21(含 Phase C)已作废,不再是选定方向。

## Oracle first(判据先行,单独 commit,先红检)

- [ ] T4 主 agent 亲写 `tests/test-delegate-isolate.sh`,按 design「十」逐条:
      P0 内容哈希(含 `__pycache__` 例外、符号链接、只覆盖 protect)、`--isolate` 建树/默认开/
      判卷必须干净/嵌套必须被 ignore/dry-run 不建树、卷宗改判"腿能写的树"、回执三键、
      闸①跑在 worktree 上、**A3 那一幕**(派活后主树提交判据修复 ⇒ 隔离下放行、非隔离下红)、
      交回只打印不动手。摘要算法在判据里**独立实现一遍**,不许调用被测代码算。
- [ ] T5 攻我自己的题:回答"全绿但闸其实没咬住会怎样",至少覆盖
      ①哈希算法两边一起错 ②"默认开"被写成"只要不传 --no-isolate 就当隔离但没建树"
      ③闸①在 worktree 上跑了但底账还留在主树 ④卷宗规则放松过头(落进 worktree 也放行)。
- [ ] T6 判据单独 commit,并把新套件加进总跑 `SUITES`(孤儿套件闸会硬红)。
- [ ] T7 红检:`redcheck --impl bin/delegate-codex --must-fail <目标断言>`,
      红必须落在目标断言上,不是 build/环境错误;老套件 `test-delegate-entry.sh` 的
      mtime 那一幕同步改写(它断言的正是被替换掉的闸)。

## 实现(主 agent 亲写)

- [ ] T8 P0:`--print-oracle-hash` + 派活时的内容哈希闸(替换 mtime 那段)。
- [ ] T9 `--isolate`(默认开)/`--no-isolate`:建树、分支、拒发条件、dry-run 不建树。
- [ ] T10 卷宗位置规则换成"腿能写的树";把 A2 那句自相矛盾的提示改掉。
- [ ] T11 回执三键 + `--receive` 全面改跑 worktree + 写回 `actual_write_set`。
- [ ] T12 交回打印:集成命令、`create mode 120000` 自查、`worktree remove`、旧树盘点。

## 判卷(闸②/闸③ 自己走一遍)

- [ ] T13 亲跑:新套件 + 总跑 `bin/rust-check-review-tooling` 全绿,收据用 `runlog` 落盘。
- [ ] T14 变异测试:证明判据咬得动(至少 4 处变异,每处必须有断言红)。
- [ ] T15 亲读 diff(盯 `create mode 120000`)。

## Verify and documentation

- [ ] T16 主 agent 独立自审先落盘,再走 `full` panel;失败腿/降级/off 状态从 roster 原样引用
      (08-11 三轮都只有 2/4 腿,别当四审过了)。
- [ ] T17 对所有发现逐条仲裁;尤其审清卷宗规则放松、worktree 选址、清理语义。
- [ ] T18 更新 `delegate` skill 与 `/root/aiwork/README.md`(只描述已经存在的机械能力);
      `/root/CLAUDE.md` 只有形成新硬规矩才改。
- [ ] T19 部署验证:从 PATH 调到的真实入口打印新用法,并**真跑一次隔离 job**
      (假 codex 也算真跑:树建出来、回执三键在、闸①跑在 worktree 上、交回命令印出来),
      PASS 后归档 track。

# Proposal: deepseek-leg-bash-hole

## 问题(已实测证实,不是推测)

上一单(opencode-agent-base)发现 opencode 底座的 bash 白名单挡不住 git 自己的参数,
于是把 bash 整个关掉。当时我记了一笔敞账:**DeepSeek 腿走 claude 壳,白名单形状一模一样
(`Bash(git diff:*)`),很可能同一个洞**。本单去验,**验实了**。

两个探针(真腿、真端点):

1. **写:得手。** `git diff --output=pwned_ds2.txt HEAD` —— 文件真的出现在被评审的仓里。
2. **读仓外:没得手。** `git diff --no-index calc.py /dev/null` 被 Claude Code 按**路径**拦下
   (`git in '/dev/null' was blocked ... may only access files with git from the allowed
   working directories`),连 GNU `diff` 和 `touch` 也一并拦。`rm` 也被拦。

**所以 claude 壳这层守卫比前缀匹配聪明(按路径管),但它不管 `--output=` 这种
"写在工作目录内"的写。** 另外实测发现:`pwd` / `ls -la` / `cat` 这些**不在
`--allowedTools` 里的命令照样跑得起来** —— 说明这层是"拦危险的"而不是"只放行列出的",
我原来把它当白名单理解是错的。

## 为什么这条比泄 key 更要命

评审腿能往**被评审的仓**里写文件 ⇒ 它能写 `tests/*`,也就是**能动判据**。
那正是本机整套规矩的头号假想敌(「弱模型最可能的失败方式是改考卷让自己及格」)。
闸①(判据先单独 commit + byte-diff)是**事后检测**,而这条是**事前预防**该管的事。

影响面:`subdeepseek-agent` 是 panel 四审的默认腿之一,已经这样跑了几周。

## 提议

1. **claude 壳的评审腿去掉 Bash**,和 opencode 底座那条对齐:只留 Read/Glob/Grep。
2. **但不能就这么把能力砍掉** —— 这条腿的价值有一半来自"自己看 git 历史/差异"。
   第一性原理:**它需要的是那份 diff,不是一个 shell**。
   所以同时给底座腿补上"把 diff 算好放进提示词"(`PANEL_DIFF_BASE` 已经有了,
   聊天腿一直是这么拿 diff 的,底座腿反而没有)。

## 不做什么

- 不去黑名单 `--output`:上一单已经证明这条路是打地鼠(diff 选项在 `git log -p`/
  `git show` 上一样吃),而且这里的守卫还不是严格白名单,黑名单更靠不住。

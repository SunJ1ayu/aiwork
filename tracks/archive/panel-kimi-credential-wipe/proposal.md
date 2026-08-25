# Proposal: 有东西在反复清空 subkimi 的凭证(6 天,根因不明)

**开单日:2026-08-25。从 `panel-dead-leg-streak` 里分出来的 —— 那一单治的是
"状态不会变",这一单治的是"为什么会死"。两件事,不许搅在一起。**

## 数出来的事实

`subkimi` 从 08-20 到 08-25 跨 **10 轮 panel**,每轮死在**逐字相同**的一句:

```
error: failed to run prompt: provider managed:kimi-code has no credential configured
```

凭证文件 `/root/.kimi-code/credentials/kimi-code.json` 的内容是 **`{}`(3 字节)**。
`/root/.cache/aiwork/kimi-review-home/credentials` 是指向它的符号链接,所以评审腿和
业主用的是同一份凭证。

## 🔴 关键:它不是"忘了登录一次"

- 业主 **08-25 13:56** 跑过一次登录(目录 mtime 为证)。
- **16:06:55** 那个文件又变回了 `{}`(文件 mtime 为证)。
- **16:13** 那轮 panel 的 subkimi 仍然是同一句报错,10 秒失败。

也就是说:**有东西在反复把它清空**,而且清空发生在**没有任何 kimi 进程在跑**的时候 ——
`/root/.cache/aiwork/kimi-review-home/logs/kimi-code.log` 在 16:06 前后一条记录都没有
(最近的一条是 16:13:56,正是那次派发)。

## 已经排除 / 还没查的

已排除:
- 不是 `subkimi` 包装脚本自己删的(它只在 `subkimi:172` 做 `-e` 存在性检查,不写)。
- 不是 crontab 里那四条(stargate / cleanup-sessions / tmp-sweeper / disk-watch),
  时间都对不上,且都不碰这个路径。

还没查:
- token 过期 → 刷新失败 → **把空对象写回去**(最像的一条:能解释"没有进程在跑时被改",
  如果是某个常驻进程在后台刷新);
- OpenClaw gateway(那台 codex app-server 已经连着跑了 4 天)有没有碰 kimi 凭证;
- `kimi` CLI 自己的后台刷新/心跳。

## 为什么值得单独一单

1. panel 的全部价值是**模型家族多样性**。少一个家族=永久损失,而它已经少了 6 天。
2. 这类"写回空凭证"的故障会**沉默地**扩散到任何共用这份凭证的地方。
3. 它是 `panel-dead-leg-streak` 那个机制的**第一个真实客户**:16:28 那轮收尾后
   `health.tsv` 里 subkimi 第一次真的记上了 `FAIL … streak=1`。再死两轮它就会被
   停止轮换并打出响亮提示 —— 那时**必须有人真的动手**,而不是又把提示当背景噪音。

## 第一步(还没做)

写一个探针:盯住那个文件的 mtime + 内容,记下**是哪个 pid 写的**
(`inotifywait` 或 `fanotify`),抓一次现行再谈修法。**不许在没抓到写入者之前猜修法。**

# 阶段 B 第 4 步:本机评审改用 `aiwork-review` App(给本机 agent 的执行单)

计划见同分支的 `WORKFLOW-MIGRATION-PLAN.md` 阶段 B。本步只做两件事:**把 App 私钥装好并验收**,**盘点本机的 SunJ1ayu 凭证**。
不撤销任何凭证(那是第 5 步),不改评审流程(阶段 C 的 `bin/review-pr` 再做)。

| 项 | 值(都不是机密) |
|---|---|
| App | `aiwork-review`,在 GitHub 上显示为 `aiwork-review[bot]` |
| App ID | `5116249` |
| installation ID | `165993669`(只装在 SunJ1ayu/OpenDesign) |
| 应有权限 | Contents 只读、Pull requests 读写、Metadata 只读(自动) |

## 铁律

1. **私钥内容不许出现在任何输出里**:不 `cat`、不 `head`、不 `grep` 它,不贴进聊天、日志、提交、仓库。对它只做 `mv` / `chown` / `chmod` / `stat` / `openssl pkey -noout`(不输出内容)。
2. **令牌不许打印**:不 `echo $GH_TOKEN`,不用 `gh auth status --show-token`。令牌只经环境变量传给命令。
3. 除了 A3 那一次**本应被拒**的推送,这一步不往 GitHub 推任何东西,不改 GitHub 上的任何设置。
4. **任何一项结果和"预期"不一样:停下,原样报告,不要自己想办法绕过。**

## 0. 前置(业主做)

业主用自己登录服务器的方式,把 GitHub 下载的私钥文件(名字形如 `aiwork-review.2026-09-29.private-key.pem`)传到服务器的 `/root/` 下。

本机需要:`openssl`、`curl`(7.55 以上)、`jq`、`gh`、`git`。

## 1. 放私钥

```sh
ls -l /root/*.pem                      # 应只看到业主刚传上来的那一个;名字不是下面这种形式就用实际的名字
install -d -m 700 -o root -g root /etc/aiwork /etc/aiwork/apps
mv /root/aiwork-review.*.private-key.pem /etc/aiwork/apps/aiwork-review.pem
chown root:root /etc/aiwork/apps/aiwork-review.pem
chmod 600 /etc/aiwork/apps/aiwork-review.pem
openssl pkey -in /etc/aiwork/apps/aiwork-review.pem -noout && echo "私钥能解析"
```

为什么不另建系统用户:本机 agent 现在都以 root 运行,另建用户挡不住 root。现在的保护是:私钥不在任何仓库里、只有 root 能读、云端 Builder 碰不到这台机器;本机 agent 在过渡期只评审不推代码,没有伪造评审的动机。真正把私钥和 agent 隔开,要等计划 §6 的"agent 降为普通用户",在本机 agent 当 Builder 之前做。

## 2. 角色配置

```sh
cat > /etc/aiwork/apps/review.env <<'EOF'
APP_ID=5116249
INSTALLATION_ID=165993669
KEY=/etc/aiwork/apps/aiwork-review.pem
REPOS="OpenDesign"
PERMISSIONS='{"contents":"read","pull_requests":"write"}'
EOF
chmod 600 /etc/aiwork/apps/review.env
```

以后换 App、收窄权限、加仓库,只改这个文件;换评审用的模型不碰它。

## 3. 装适配器 `gh-app-token`

脚本和本文件在同一个分支、同一个目录。直接从 GitHub 取原文,不要手抄:

```sh
cd /root/aiwork
git fetch https://github.com/SunJ1ayu/aiwork.git claude/exciting-johnson-w8a35g
git show FETCH_HEAD:workflow-migration/gh-app-token > /usr/local/bin/gh-app-token
chmod 755 /usr/local/bin/gh-app-token
sha256sum /usr/local/bin/gh-app-token
```

**预期 sha256:`201d9853282fa1adb946b4748ffa3061d8060283de3540cf7d6800e21d8d2fe8`**,对不上就停。

它做的事:用私钥签一个 10 分钟的 JWT → 向 GitHub 换一个 1 小时的 installation token,并且在请求里**只要** `review.env` 写的仓库和权限;GitHub 给回来的只要和要的不一致,就不用这个令牌、报错退出。标准输出只有令牌本身;`--grant` 只打印权限、仓库、到期时间,不打印令牌。

先装在 `/usr/local/bin`,阶段 C 做 `bin/review-pr` 时按 aiwork 本机的正常流程收进 aiwork 仓库。

## 4. 验收(逐条跑,按最后的模板报告)

**A1 权限与范围**

```sh
gh-app-token review --grant
```

预期:`permissions` 恰好是 `contents: read`、`metadata: read`、`pull_requests: write`;`repositories` 只有 `SunJ1ayu/OpenDesign`;`expires_at` 约为一小时后(UTC)。

**A2 能发评论,署名是 App**

在已关闭的探针 PR #8 上发一条评论(不影响任何东西):

```sh
GH_TOKEN="$(gh-app-token review)" gh api repos/SunJ1ayu/OpenDesign/issues/8/comments \
  -f body='aiwork-review 身份自检(阶段 B 第 4 步验收):这条评论应署名 aiwork-review[bot]。' \
  --jq '.user.login + " " + .html_url'
```

预期:`aiwork-review[bot] https://github.com/SunJ1ayu/OpenDesign/pull/8#issuecomment-…`

**A3 推代码被拒**

忽略本机全局 git 配置(否则 `insteadOf` 或凭证助手可能改用 SunJ1ayu 的 SSH 密钥或令牌,测的就不是 App 了):

```sh
export GH_TOKEN="$(gh-app-token review)"
tmp=$(mktemp -d) && cd "$tmp" && git init -q
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.name=probe -c user.email=probe@invalid \
  commit -q --allow-empty -m "aiwork-review 推送自检(应被拒)"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 git \
  -c credential.helper='!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f' \
  push https://github.com/SunJ1ayu/OpenDesign.git HEAD:refs/heads/probe/aiwork-review-push-denied
echo "push rc=$?"
unset GH_TOKEN; cd /; rm -rf "$tmp"
```

预期:推送失败(`push rc` 不是 0),报错里有 403,以及 `denied to aiwork-review[bot]` 或 `Write access to repository not granted`。
**如果推送成功了:隔离失败。立刻停下报告业主**(分支 `probe/aiwork-review-push-denied` 需要业主删掉,App 权限要重查)。

**A4 私钥只有一份、不在仓库里**

```sh
stat -c '%a %U:%G %n' /etc/aiwork /etc/aiwork/apps /etc/aiwork/apps/*
ls /root/*.pem 2>/dev/null
git -C /etc/aiwork/apps rev-parse --show-toplevel 2>/dev/null || echo "不在任何 git 仓库里"
k=$(sha256sum < /etc/aiwork/apps/aiwork-review.pem)
find /root /home /tmp -xdev -type f -name '*.pem' ! -path /etc/aiwork/apps/aiwork-review.pem \
  -exec sh -c 'for f; do [ "$(sha256sum < "$f")" = "$0" ] && echo "多一份:$f"; done' "$k" {} +
```

预期:两个目录 `700`、两个文件 `600`,全部 `root:root`;`/root/*.pem` 没有输出;"不在任何 git 仓库里";没有"多一份"。

**A5 盘点 SunJ1ayu 凭证(只读,给第 5 步用;不许撤销、不许改)**

只报告**在哪里、属于哪个账号、谁在用**,不报告凭证本身:

```sh
gh auth status 2>&1 | sed -E 's/(gh[pousr]_)[A-Za-z0-9_]+/\1***/g'
git config --show-origin --get-all credential.helper
[ -f ~/.git-credentials ] && sed -E 's#//[^:/@]+:[^@]+@#//***:***@#' ~/.git-credentials
timeout 15 ssh -T -o BatchMode=yes git@github.com 2>&1 | head -1
grep -rlE 'GH_TOKEN|GITHUB_TOKEN|GITHUB_PAT|gh[pousr]_[A-Za-z0-9]{20,}' \
  /root/.bashrc /root/.profile /root/.config /etc/environment /etc/systemd/system /etc/cron* /var/spool/cron 2>/dev/null
for r in /root/*/; do [ -d "$r.git" ] && echo "$r → $(git -C "$r" remote get-url --push origin 2>/dev/null | sed -E 's#//[^@/]+@#//***@#')"; done
```

再用你自己的话补充:本机有哪些流程在用这些凭证(例如 aiwork 同步 GitHub 镜像、OpenClaw、各评审腿、打包发布),各自用的是哪一样。

## 5. 从现在起的过渡规则

- 本机往 OpenDesign 的 PR 上发评审或评论,一律用 `GH_TOKEN="$(gh-app-token review)"`,不再用 SunJ1ayu 身份发。
- 本机不往 OpenDesign 推代码,不合并 PR,不发版(发版改由 GitHub 上的 `release` workflow,业主批准)。

## 6. 报告模板(贴回给业主;不含任何私钥或令牌)

```
第 4 步结果
1 放私钥:        OK / 不符(原样贴输出)
3 sha256:        OK / 不符
A1 权限与范围:    <gh-app-token review --grant 的输出>
A2 评论署名:      <输出的那一行>
A3 推送被拒:      push rc=<n>;报错里的关键一行:<…>
A4 私钥只有一份:  <stat 输出>;其余三项:OK / 不符
A5 SunJ1ayu 凭证盘点:
   - <位置> | <账号> | <谁在用>
   - …
```

业主收到报告后,可以把自己电脑"下载"文件夹里的那份私钥删掉:服务器上已经有一份,丢了也能在 GitHub 的 App 设置页重新生成(再把旧的删掉)。

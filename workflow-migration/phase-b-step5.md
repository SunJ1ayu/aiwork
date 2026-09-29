# 阶段 B 第 5 步:撤掉本机的 SunJ1ayu 凭证(执行单)

目标:SunJ1ayu 只给人用。本机仍要用 GitHub 的流程,先换上 `aiwork-sync` / `aiwork-orchestrator` App 并**用真跑验证**,
再由业主在 GitHub 上吊销旧凭证,最后本机**证明旧凭证已失效**后删掉。顺序不能反:先撤后换会让备份和镜像同步断掉。

第 4 步已知(Codex 盘点):本机 `gh` 登录是 SunJ1ayu;`/root/.git-credentials` 两条都是 SunJ1ayu,git 默认用第一条;
OpenClaw 备份脚本从 `gh` 登录取令牌;SSH 身份因 `Host key verification failed` 没核成。

**铁律同第 4 步**:不打印任何私钥、令牌、密码;结果和预期不一样就停下原样报告,不绕过。
每一部分做完都**停下报告**,业主确认后再做下一部分。

---

## 甲 盘点写入流程 + 核 SSH 身份(本机 agent,只读,不改任何东西)

**甲1 写入流程表**:列出本机所有会往 GitHub **写**东西的流程(推代码、建 PR、发评论、建 release、改设置……):

| 流程 | 怎么触发(手动 / cron / systemd / OpenClaw) | 写哪个仓库、哪些分支 | 做什么操作(git push / 哪些 API) | 现在用哪样凭证 |
|---|---|---|---|---|

至少要覆盖:aiwork 镜像更新(推 SunJ1ayu/aiwork)、OpenClaw 备份脚本(推到哪个仓库、推什么)、`crontab -l` 与 `systemctl list-timers` 里碰 github.com 的任务、各 agent 配置里要求用 `gh` 的地方。
**OpenClaw 作为总管对 GitHub 做的所有事也要列**(读 PR / CI 状态、加标签、评论、触发 workflow、开 PR、合并……),**只读的也列上**,并注明读的是公开仓库(OpenDesign)还是私有仓库(aiwork)。
备份脚本另外说明一句:**备份内容里有没有密钥类文件**(API key、.env、私钥),只报类别和文件名,不打印内容。

**甲2 SSH 身份**:用 GitHub 官方公布的主机公钥(经 HTTPS 取)临时核,不改 `~/.ssh/known_hosts`:

```sh
curl -fsS https://api.github.com/meta | jq -r '.ssh_keys[] | "github.com " + .' > /tmp/github_known_hosts
timeout 15 ssh -T -o BatchMode=yes -o UserKnownHostsFile=/tmp/github_known_hosts git@github.com 2>&1 | head -1
for f in ~/.ssh/*.pub; do [ -f "$f" ] && ssh-keygen -lf "$f"; done
rm -f /tmp/github_known_hosts
```

读法:`Hi SunJ1ayu!` = 本机有把 SSH 钥匙登记在业主账号上(报它的 SHA256 指纹,第丁步删);
`Hi SunJ1ayu/<仓库>!` = 它是那个仓库的 deploy key;`Permission denied (publickey)` = 本机的 SSH 钥匙没登记在 GitHub 上。

**停下,报告甲1 表格 + 甲2 的输出。**

---

## 乙 建两个替代身份(业主,在浏览器里)

甲的结果(2026-09-29,Codex):

| 流程 | 触发 | 仓库 | 操作 | 现在的凭证 |
|---|---|---|---|---|
| aiwork 镜像 | 手动 | `/root/aiwork-web` 的 main → SunJ1ayu/aiwork 的 main | git push | 全局 git 凭证存储(第一条,SunJ1ayu) |
| OpenClaw 备份 | OpenClaw cron 每天 03:00 | `/root/.openclaw/workspace` → SunJ1ayu/lt-workspace 的 main | git 提交并推送 | `gh auth token`(SunJ1ayu,**已失效**) |
| GitHub-Watch | OpenClaw cron 每天 09:00 | 只读:openclaw/openclaw、anthropics/claude-code、openai/codex 的 Release(公开仓库) | 读 API | `gh auth token`(同上,**已失效**) |
| OpenClaw 的 GitHub 技能 | 按任务 | 只读:PR、CI、Issue | 读 API | `gh` 登录(同上) |

没有定时写 OpenDesign 的流程;没有加标签、评论、触发 workflow、开 / 合并 PR、建 Release 的固定任务。
SSH:本机钥匙 `/root/.ssh/new_key`(SHA256:ihFzbw3W5CRJSxGY2sGT9qKlecs67Q3FQR7l+QWN4xo)没有登记在 GitHub 上,不用处理。
**`gh` 登录的令牌已经失效 ⇒ 03:00 的备份和 09:00 的 GitHub-Watch 现在就跑不通**,换上下面的身份后恢复。

按用途建两个 App,建法和 `aiwork-review` 一样(https://github.com/settings/apps/new;Homepage 填 `https://github.com/SunJ1ayu/aiwork`;Webhook 取消 Active;Only on this account;建完生成私钥;Install App 选 Only select repositories):

**`aiwork-sync`**(备份与镜像):
- Repository permissions:**Contents = Read and write**,其余全部 No access
- 安装到:**aiwork** 和 **lt-workspace** 两个仓库(不选 OpenDesign)

**`aiwork-orchestrator`**(OpenClaw 总管;业主决定以后由 OpenClaw 主控):
- Repository permissions **全部只读**:Actions、Checks、Commit statuses、Contents、Issues、Pull requests = `Read-only`,其余 No access
- 安装到:**OpenDesign**
- 现在只给读:甲1 里 OpenClaw 没有固定的写操作。以后 OpenClaw 接手加标签、评论、触发发版等工作时再加对应权限(改完要去安装页点 Accept,和第 4 步一样)。
  它代表业主调度,但**不拿业主账号**:业主账号能删仓库、改或关掉规则和检查,且记录分不出人和程序。发版前由 OpenClaw 用一句大白话问业主批不批,业主在 GitHub 上点一下(计划 §7)。

两个私钥都传到服务器 `/root/`;把两个 App ID、两个 installation ID 发给 Claude(不是机密)。

---

## 丙 换上新身份并真跑验证(本机 agent)

**丙1 装私钥与配置**(同第 4 步;App ID 与 installation ID 已按业主给的填好):

```sh
mv /root/aiwork-sync.*.private-key.pem /etc/aiwork/apps/aiwork-sync.pem
mv /root/aiwork-orchestrator.*.private-key.pem /etc/aiwork/apps/aiwork-orchestrator.pem
chown root:root /etc/aiwork/apps/*.pem && chmod 600 /etc/aiwork/apps/*.pem
for k in aiwork-sync aiwork-orchestrator; do openssl pkey -in /etc/aiwork/apps/$k.pem -noout && echo "$k 私钥能解析"; done
cat > /etc/aiwork/apps/sync.env <<'CONF'
APP_ID=5118560
INSTALLATION_ID=166057171
KEY=/etc/aiwork/apps/aiwork-sync.pem
REPOS="aiwork lt-workspace"
PERMISSIONS='{"contents":"write"}'
CONF
cat > /etc/aiwork/apps/orchestrator.env <<'CONF'
APP_ID=5118664
INSTALLATION_ID=166058398
KEY=/etc/aiwork/apps/aiwork-orchestrator.pem
REPOS="OpenDesign"
PERMISSIONS='{"actions":"read","checks":"read","contents":"read","issues":"read","pull_requests":"read","statuses":"read"}'
CONF
chmod 600 /etc/aiwork/apps/*.env
gh-app-token sync --grant
gh-app-token orchestrator --grant
```

预期:sync 恰好 `contents: write` + `metadata: read`,仓库恰好 aiwork、lt-workspace;orchestrator 恰好那六项 read + `metadata: read`,仓库只有 OpenDesign。

**丙2 改用新身份**:

- aiwork 镜像(git):只改 `/root/aiwork-web` 自己的 git 配置,不动全局:
  ```sh
  git -C /root/aiwork-web config --local credential.helper ''
  git -C /root/aiwork-web config --local --add credential.helper '!f() { test "$1" = get || exit 0; echo username=x-access-token; echo "password=$(gh-app-token sync)"; }; f'
  ```
- OpenClaw 备份:备份脚本里取令牌的那一处由 `gh auth token` 改成 `gh-app-token sync`;推送方式照旧。
- GitHub-Watch 与 OpenClaw 的 GitHub 技能:取令牌改成 `gh-app-token orchestrator`(用 `gh` 的,执行前设 `GH_TOKEN="$(gh-app-token orchestrator)"`)。

**丙3 真跑验证**(屏蔽旧凭证,证明真的只靠新身份;下面每条单独执行,`<…>` 换成实际命令):

1. aiwork 镜像:在 `/root/aiwork-web` 里推一个探针分支再删掉(不动 main):
   ```sh
   GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 git -C /root/aiwork-web push origin HEAD:refs/heads/probe/aiwork-sync-check
   GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 git -C /root/aiwork-web push origin --delete probe/aiwork-sync-check
   ```
2. OpenClaw 备份:照 OpenClaw 平时的方式手动触发一次,触发时屏蔽 `gh` 登录(`env -u GH_TOKEN GH_CONFIG_DIR="$(mktemp -d)" <触发备份的命令>`)。跑完核 lt-workspace 的 main 与本地 HEAD 一致:`git ls-remote` 要**带上 sync 令牌**(同第 1 条的凭证助手写法,用 `git -c credential.helper=...`);lt-workspace 是私有仓库,不带身份访问时 GitHub 一律回 `Repository not found`,那不代表权限有问题。
3. GitHub-Watch:同样屏蔽 `gh` 登录后手动跑一次,应拿到三个仓库的最新 Release。
4. orchestrator 读得到、写不了:
   ```sh
   GH_TOKEN="$(gh-app-token orchestrator)" GH_CONFIG_DIR="$(mktemp -d)" gh pr list -R SunJ1ayu/OpenDesign --state all -L 1
   GH_TOKEN="$(gh-app-token orchestrator)" GH_CONFIG_DIR="$(mktemp -d)" gh api repos/SunJ1ayu/OpenDesign/issues/8/comments -f body='orchestrator 只读自检(应被拒)'; echo "rc=$?"
   ```
   预期:第一条有输出;第二条被拒(403,rc≠0)。
5. sync 碰不到 OpenDesign:用 sync 令牌往 OpenDesign 推探针分支应被拒(403),做法同第 4 步 A3,只把 `review` 换成 `sync`。

另报:lt-workspace 上一次成功备份是哪天(main 最新提交的时间),好知道备份断了多久。

**停下,报告丙1 输出、丙3 每一条的结果。**

---

## 丁 业主在 GitHub 上吊销旧凭证(业主,在浏览器里)

丙全部通过后才做:

1. https://github.com/settings/applications → Authorized OAuth Apps → **GitHub CLI** → Revoke。这会让所有 `gh` 登录的 SunJ1ayu 令牌失效(包括本机那个)。
2. https://github.com/settings/tokens 与 https://github.com/settings/personal-access-tokens → 删掉 agent 用过的令牌。**分不清的全删**:业主自己在浏览器里用 GitHub 不需要它们。
3. https://github.com/settings/keys → 本机的 SSH 钥匙没登记(甲2);这里有不认识的钥匙就删,没有就不用动。
4. 不用动:`aiwork-review`、`aiwork-sync`、`aiwork-orchestrator`(它们是"安装"不是"授权");claude.ai 的授权之前已经撤过了。

---

## 戊 证明旧凭证已失效,再从本机删掉(本机 agent)

**戊1 先证明失效**(删之前测,测的是真的旧凭证):

```sh
gh api user --jq .login                                          # 预期:401 / Bad credentials
GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/SunJ1ayu/aiwork >/dev/null; echo "rc=$?"   # 预期:rc≠0,认证失败(aiwork 是私有仓库)
```

**戊2 删掉**:

```sh
gh auth logout --hostname github.com                             # 只删本机登录记录
```

把 `/root/.git-credentials` 里 SunJ1ayu 的两条删掉(文件里只有这两条就删整个文件);全局 `credential.helper` 如果只为它服务,一并去掉;甲1 里发现的环境变量、配置里的旧令牌一并清掉。**不打印这些内容。**

**戊3 验收**:

```sh
gh auth status 2>&1 | head -3                                    # 预期:没有登录任何账号
grep -c 'github.com' /root/.git-credentials 2>/dev/null || echo "没有 .git-credentials"
```

再把丙3 的镜像推送、备份、GitHub-Watch **照常方式**(不加屏蔽)各跑一次,预期都成功。

**停下,报告戊1–戊3。** 至此阶段 B 的"本机 `gh auth status` 已不是 SunJ1ayu"验收完成。

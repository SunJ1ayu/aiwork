# 阶段 B 第 5 步:撤掉本机的 SunJ1ayu 凭证(执行单)

目标:SunJ1ayu 只给人用。本机仍要往 GitHub 写的流程,先换上 `aiwork-sync` App 并**用真跑验证**,
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

## 乙 建替代身份(业主,在浏览器里)

按甲1 的结果**按用途**建 App,不把不同用途的权限合进一个:

- **`aiwork-sync`**:备份、镜像这类只往 aiwork 和备份仓库写的流程(下面的步骤)。
- **`aiwork-orchestrator`**:OpenClaw 当总管用的身份(业主决定:以后由 OpenClaw 主控、管理日常)。权限按甲1 列出的操作给,装在 OpenDesign(需要时加 aiwork)。
  它代表业主调度,但**不拿业主账号**:业主账号能删仓库、改或关掉分支规则和检查,而且操作记录分不出是人还是程序。
  发版和高风险改动的最后确认:默认仍由业主在 GitHub 上点一下批准(OpenClaw 先写好一句大白话说明);业主以后可以改成交给 OpenClaw,改法是去掉 `release` 环境的审批人并给它触发权限,见计划 §7。

`aiwork-sync` 的建法和建 `aiwork-review` 同样的步骤(https://github.com/settings/apps/new),只有这些不同:

- 名字:`aiwork-sync`
- Repository permissions:**Contents = Read and write**,其余全部 No access(甲1 里如果有流程要用别的 API,按报告再加,只加它要的)
- 安装:Only select repositories,**只选甲1 表格里要写的那几个仓库**(例如 aiwork 和备份仓库)。**不选 OpenDesign**:过渡期本机不往 OpenDesign 推代码。
- 生成私钥,传到服务器 `/root/`(同第 4 步)
- 把 App ID 和 installation ID 发给 Claude(不是机密)

`aiwork-orchestrator` 的权限清单和第丙步的对应做法,Claude 按甲1 的报告另给。

---

## 丙 换上 `aiwork-sync` 并真跑验证(本机 agent)

**丙1 装私钥与配置**(同第 4 步的做法):

```sh
mv /root/aiwork-sync.*.private-key.pem /etc/aiwork/apps/aiwork-sync.pem
chown root:root /etc/aiwork/apps/aiwork-sync.pem && chmod 600 /etc/aiwork/apps/aiwork-sync.pem
openssl pkey -in /etc/aiwork/apps/aiwork-sync.pem -noout && echo "私钥能解析"
cat > /etc/aiwork/apps/sync.env <<'EOF'
APP_ID=<业主给的 App ID>
INSTALLATION_ID=<业主给的 installation ID>
KEY=/etc/aiwork/apps/aiwork-sync.pem
REPOS="<甲1 里要写的仓库名,空格分隔,例如 aiwork 备份仓库名>"
PERMISSIONS='{"contents":"write"}'
EOF
chmod 600 /etc/aiwork/apps/sync.env
gh-app-token sync --grant
```

预期:`permissions` 恰好 `contents: write` + `metadata: read`;`repositories` 恰好是 REPOS 那几个。

**丙2 把每个写入流程改用它**:

- 走 git 推送的:只在**那个仓库自己的** git 配置里加凭证助手(不动全局配置),每次推送现取令牌:
  ```sh
  git -C <仓库目录> config --local credential.helper ''
  git -C <仓库目录> config --local --add credential.helper '!f() { test "$1" = get || exit 0; echo username=x-access-token; echo "password=$(gh-app-token sync)"; }; f'
  ```
- 走 `gh` 或 API 的(如 OpenClaw 备份):把取令牌的那一处改成 `GH_TOKEN="$(gh-app-token sync)"`,不再读 `gh` 登录。

**丙3 真跑验证**:每个流程在**不依赖旧凭证**的条件下真跑一次:

```sh
GIT_CONFIG_GLOBAL=/dev/null <照常执行该流程>      # git 推送类:屏蔽全局配置里的 SunJ1ayu 凭证
env -u GH_TOKEN GH_CONFIG_DIR=$(mktemp -d) <照常执行该流程>   # gh 类:屏蔽 gh 登录
```

预期:都成功;GitHub 上这次推送 / 写入的署名是 `aiwork-sync[bot]`(或推送记录里是它)。
再核一条**范围**:用 sync 令牌往 OpenDesign 推一个探针分支,应被拒(403),做法同第 4 步 A3,只把 `review` 换成 `sync`。

**停下,报告丙1 输出、每个流程的真跑结果、范围探针的 rc 和报错行。**

---

## 丁 业主在 GitHub 上吊销旧凭证(业主,在浏览器里)

丙全部通过后才做:

1. https://github.com/settings/applications → Authorized OAuth Apps → **GitHub CLI** → Revoke。这会让所有 `gh` 登录的 SunJ1ayu 令牌失效(包括本机那个)。
2. https://github.com/settings/tokens 与 https://github.com/settings/personal-access-tokens → 删掉 agent 用过的令牌。**分不清的全删**:业主自己在浏览器里用 GitHub 不需要它们。
3. https://github.com/settings/keys → 如果甲2 显示 `Hi SunJ1ayu!`,删掉指纹对得上的那把 SSH 钥匙。
4. 不用动:`aiwork-review`、`aiwork-sync`(它们是"安装"不是"授权");claude.ai 的授权之前已经撤过了。

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

再把丙3 的每个流程**照常方式**(不加屏蔽)真跑一次,预期都成功、署名 `aiwork-sync[bot]`。

**停下,报告戊1–戊3。** 至此阶段 B 的"本机 `gh auth status` 已不是 SunJ1ayu"验收完成。

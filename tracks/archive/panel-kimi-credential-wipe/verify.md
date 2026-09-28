# Verify: panel-kimi-credential-wipe

- Date: 2026-08-25

> 机器消费的 impact / uncertainty / execution plan / outcome 只写在同目录 `decision.json`。

## Mechanical checks

- [x] 判据全绿(最终:479 passed / 0 failed,rc=0,source-stable: yes)
- [x] 判据先行:三轮"先红后修",红收据一份不藏(见下)
- [x] 无密钥/危险操作:未 push、未删文件、未装依赖、未碰生产

**机器打印的收据行(原样,别改数)** —— 时间顺序,`rc` 才是机器写的,收据名字不作数:

```
runlog: redcheck-v45-before-fix rc=1 commit=0d8b860 dirty=yes at=2026-08-25T09:55:33Z file=tracks/panel-kimi-credential-wipe/evidence/20260825T095533Z-01-redcheck-v45-before-fix.txt
runlog: oracle-full-after-fix rc=0 commit=35a7e93 dirty=yes final=yes at=2026-08-25T09:59:49Z file=tracks/panel-kimi-credential-wipe/evidence/20260825T095949Z-01-oracle-full-after-fix.txt
runlog: redcheck-v45-widened rc=1 commit=39f9bab dirty=yes at=2026-08-25T10:20:59Z file=tracks/panel-kimi-credential-wipe/evidence/20260825T102059Z-01-redcheck-v45-widened.txt
runlog: oracle-full-r2 rc=0 commit=fdd7306 dirty=yes final=yes at=2026-08-25T10:25:24Z file=tracks/panel-kimi-credential-wipe/evidence/20260825T102524Z-01-oracle-full-r2.txt
runlog: redcheck-v45-r3 rc=1 commit=e5dcc44 dirty=yes at=2026-08-25T10:59:25Z file=tracks/panel-kimi-credential-wipe/evidence/20260825T105925Z-01-redcheck-v45-r3.txt
runlog: redcheck-v38-channel rc=1 commit=ffa7a17 dirty=yes at=2026-08-25T11:03:09Z file=tracks/panel-kimi-credential-wipe/evidence/20260825T110309Z-01-redcheck-v38-channel.txt
runlog: oracle-full-r3 rc=1 commit=0b3d3af dirty=yes final=yes at=2026-08-25T11:07:11Z file=tracks/panel-kimi-credential-wipe/evidence/20260825T110711Z-01-oracle-full-r3.txt
runlog: oracle-full-r4 rc=0 commit=284d68e dirty=yes final=yes at=2026-08-25T11:12:05Z file=tracks/panel-kimi-credential-wipe/evidence/20260825T111205Z-01-oracle-full-r4.txt
```

🔴 **`oracle-full-r3` 是一份 `final=yes` 但 `rc=1` 的收据,不许当绿用。** 我当时以为
"补了 V36② 就完了",而红的正是同族剩下四处(V23 / V36④ / V37×2)。留着它,因为
**收据名字会撒谎、`--final` 也会撒谎,只有 rc 是机器写的** —— 本仓为这条记过账,今天又撞一次。

四条红各自红在哪(逐份):

- `redcheck-v45-before-fix` 476/1 —— `V45 ... before=[... mtime=2026-08-25 16:55:09.296103050 ...]
  after=[... mtime=2026-08-25 17:58:15.901160644 ...]`(inode/sha 不变,**只有 mtime 变**:
  内容本来就是被洗空的 `{}`,又被写了一遍)。
- `redcheck-v45-widened` 476/1 —— 凭证目录这次没动,红在运行期 home:
  `config.toml:1103962:...18:02:33... → :1103970:...18:23:46...`(**连 inode 都换了** = 被重建)。
- `redcheck-v45-r3` 476/1 —— `变的是:mimo/mimocode.json=1104045:...18:41:27... /
  =1104158:...19:02:00...`(同族第三处,写的是业主真实 mimo home)。
- `redcheck-v38-channel` 476/**3** —— 一次红三条:
  `FAIL: V38: 问一句默认 home **不许**把种子里的 credentials 链接抄进夹具(通道)` /
  `FAIL: V38: 问一句默认 home **不许**整份抄种子(夹具实测 100MB,要 <5MB)` /
  `FAIL: V45: ... mimo/mimocode.json ...`。前两条是**我自己在修这个 bug 时造出来的**。

## Review

- **规格自查(读任何 panel 输出之前落盘,正本在仓外
  `/root/panel-my-reviews/panel-kimi-credential-wipe-my-review.md`)**:我自己写下了六条
  "最可能站不住的地方",其中第 1 条(V45 只盯一个文件 = 照着这次的坑只堵一边)和第 6 条
  (没有独立变异测试)**被后续三轮全部命中**。第 4 条我推理"提前 exit 不构成假绿"——
  两条腿各自复核后同意,成立。
  **规格本身错在哪**:我把题目定成"别写穿凭证",而正确的题目是
  **"判据不许改业主真实环境里的任何东西"** —— 窄了一圈,于是 runtime home、mimo home
  这两族都不在第一版视野里,全靠 panel 补回来。

- **腿的花名册**(三轮,原样粘;另有一轮被我主动砍掉,见末节):

```
# impact-risk=high requested-budget=2 selected-count=1
# selected=subdeepseek(deepseek/subdeepseek-agent)
submimo=SKIP(health:cooldown:INCOMPLETE) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:cooldown:DEGRADED) subkimi=SKIP(health:cooldown:FAIL)
# impact-risk=high requested-budget=2 selected-count=2
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent)
submimo=PASS(verdict=UNKNOWN) subdeepseek=PASS(verdict=PASS) subglm=SKIP(health:cooldown:DEGRADED) subkimi=SKIP(health:cooldown:FAIL)
# impact-risk=high requested-budget=2 selected-count=3
# selected=submimo(xiaomi/submimo),subdeepseek(deepseek/subdeepseek-agent),subglm(zhipu/subglm-agent)
submimo=PASS(verdict=UNKNOWN) subdeepseek=PASS(verdict=PASS) subglm=PASS(verdict=PASS) subkimi=SKIP(health:cooldown:FAIL)
```

  > 第一轮 `selected-count=1` 是**家族覆盖不足**,当场被昨天刚上的那段提示逮住(V44u 的
  > 第一个真实客户)。原因是冷却 21600s(6h)对 `INCOMPLETE`/`DEGRADED` 一视同仁 ——
  > 见「敞账 ②」。第二、三轮用 `PANEL_HEALTH_OVERRIDE` 把它们放回来才凑够家族数。
  > `subkimi` 三轮全 SKIP:它正是本单要救的那条腿,凭证此刻仍是 `{}`。

- **findings(逐条对账,接受/驳回都给依据)**:

  接受并已修:
  1. **修法不够根本**(r1 subdeepseek F6 + r2 submimo Q1,**两个家族独立命中**)——
     `find -type l -delete` 是"先造通道再斩断"。改成零件拼装(`cp -f` config + hooks,
     自建 credentials),`cp -a` 与 `find` **都删掉**。已核:仓内 `_mk_kimi_home` 和
     V40⑦ 本来就是这么写的,① 段是唯一异类,而 ⑦ 段 150 行外就写着"种子造小份"。
  2. **判据在写业主真实 runtime home**(r1 F1)—— 已核比腿说的更具体:种子同步在
     `bin/subkimi:100-110`,而 `REVIEW_PRINT_HOME` 早退在第 136 行,**同步先跑**。
     实测 config.toml mtime 18:02:33 落在收据窗口内。
  3. **我自己造出的 100MB 通道**(r3b subglm + r3b subdeepseek F1,两家独立命中)——
     假 HOME 让 runtime home 不存在 ⇒ `subkimi:104` 整份 `cp -a`。**探针实测 100MB,
     且 `credentials -> /root/.kimi-code/credentials` 又被造了一遍**。
     采纳 subglm 的修法(把查询挪到同步之前)而不是我原打算的"预建目录骗过 `[[ ! -d ]]`":
     **查询不该有副作用**,一处修两个洞(V38① / V40⑥),且改的是生产代码不是夹具。
  4. **V45 看不见 link-to-dir**(r3b subglm)—— `[[ -f ]]` 对指向目录的链接为假,
     "把链接换成假目录"恰是原始病状而闸不响。已核实测,改成先判 `-L`。
  5. **V45 误报面过大**(r3b subglm + r3b subdeepseek F2)—— 上一版把
     `session_index.jsonl`/`workspaces.json` 也纳进指纹,那些业主用一次 kimi 就会变。
     收窄到"判据没有理由碰的四样",并在失败消息里写明"你若刚 login 过就是误报"
     **+ 去哪找漏隔离的调用点**。
  6. **指纹被打进要入库的收据**(r3b subdeepseek F3 + subglm)—— 改成 PASS 时不打,
     FAIL 时只打变了的那几项。
  7. **`OWNER_CRED_PATH` env 旁路**(r1 F3)—— 我自己留的后门,删。
  8. **同族第三处:判据写业主真实 mimo home**(r3b subglm)—— 实测 mimocode.json
     mtime 落在评审腿跑判据的窗口内。**修了一处不够**:V45 再红一次才逼出全部五处
     (V36② / V23 / V36④ / V37×2)。

  驳回(用我自己对代码的核实):
  9. **"`bin/subkimi:104` 目前安全,因为 `.gitignore` 排除了 credentials"**(r2 submimo Q2)
     —— **错**。`git ls-files` 里确实没有,但 `subkimi` 和判据用的都是**活仓工作树路径**,
     而 `ls -la kimi-review-home/` 里那条链接一直在(Jul 17 建的)。两条腿都在 git 快照
     副本里工作,**这个 bug 恰好活在它们看不见的那一层**;第三轮我把这句话直接写进了题面。
  10. **"不再把 101MB 抄进 /tmp"**(r3b submimo)—— **探针证伪**(100MB)。而这句话
      是我自己写在 commit message 和任务书里的,**它附和了我的作业**。
      自检句:附和我的腿,是在独立判断,还是在读我写的东西?

  记账不修(见敞账):11 V40 夹具缺 `_review-workspace.sh`、12 `probe.sh` 硬编码写仓、
  13 V27① opencode home 未隔离、14 V45 靠"排在最后"的约定。

- **arbitrated verdict(主裁):PASS。**
  写穿通道从源头消失(不产生通道,而不是产生后斩断),判据不再改业主真实环境的任何一样,
  479/0 且 `source-stable: yes`。三轮外部评审跨 **三个模型家族**(deepseek / xiaomi / zhipu)
  全部 PASS,其中两条独立命中的"修法不够根本"和"100MB 通道"都已落地。
  **但这个 PASS 不含"kimi 能登录了"** —— 凭证此刻仍是 `{}`,只有业主本人跑一次
  `kimi login` 才能恢复,那不是我能验的。

## Accepted deviations / 敞账

1. **业主的登录尚未恢复**(唯一影响他的一条):凭证仍是 `{}`,要他本人 `kimi login`。
   `health.tsv` 里 subkimi streak=1(未判死),登录后自动回到轮换,不需要 override。
2. **冷却 6h 对软失败一视同仁**(本单实测撞到):`cooldown_health()` 里
   `case "$status" in PASS|healthy) return 1` —— 除 PASS 外全冷却 6 小时,而昨天刚上的
   dead-streak 机制**特意区分了** rc≠0 与 `INCOMPLETE`/`DEGRADED`(理由:别把正在干活的腿
   踢掉)。**同一个道理,冷却这侧漏了**,直接后果就是本单第一轮 high 只派出 1 条腿。
   **昨天那一单只修了一半。** 未开单。
3. **V40 夹具没拷 `_review-workspace.sh`**(r3b subglm,已用 `bash -x` 实证)⇒ subkimi
   落到 `bin/subkimi:183` 的硬编码回退 `/root/aiwork/bin/_review-workspace.sh`,
   **在业主机上测的是活仓那份,不是受测版本**。不同族(判据测错了对象,不是污染环境),
   不在本单顺手改,免得越滚越大。未开单。
4. **`kimi-review-home/hooks/probe.sh` 硬编码往仓里写** `logs/probe.jsonl`;当前
   `config.toml` 只挂 `guard.mjs`,没有任何东西执行它 = 死文件。潜伏,未处理。
5. **V27① 跑真 subglm-agent 未隔离 HOME**(r3b subdeepseek F6):现在只因
   `AUTH_ENV=""` 在写配置之前就 die 才没落地,是**运气不是设计**。V45 也不盯 opencode home。
6. **V45 靠"排在调用列表最后"的约定**(r1 F2 + r2):新增 v46 追加在它后面就会缩小覆盖。
   不改成 `trap EXIT` 是**刻意的**:trap 在汇总行和 `[[ $FAIL -eq 0 ]]` **之后**才响,
   那才是真的"闸说了话但不改判"。接受为已知限制。
7. **第一份收据里已入库了凭证文件的完整 64 位 sha256**(r3b subglm 指出)。那是空
   `{}` 的哈希、不是 token,且**不改 git 历史**(本仓为"改历史会毁掉收据引用"记过账)。
8. **被我主动砍掉的那一轮 panel**:`logs/ABORTED-题面过期-panel-kimi-cred3-*`。
   派发后我发现任务书还停在第一轮实现(描述 `find -type l -delete`,而代码已换成零件拼装),
   **题面是错的**,当场砍掉、改名标作废**不删**,更新题面后重派。submimo 那份已写了 21KB。
   说得出是谁砍的:我。
9. **判据自身的膨胀**(业主当场问出来的):主判据文件 07-27 建仓时 969 行 → 今天 4532 行,
   一个月 4.7 倍;`tests/` 22 个文件共 11090 行。CLAUDE.md 对硬规矩写着"总量不许只进不出"
   且真退过场,**而判据 V1..V45 一条没退过**。今天的代价具体可数:全量跑一遍 3 分钟、
   本单跑了 8 遍;**且有整整一轮是在修 V45 自己的毛病** —— 判据成了需要被判据保护的东西。
   建议单独开一单,先量"哪些判据防的 bug 在当前代码里已不可能复发",**先量再删**。未开单。

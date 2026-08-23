# 前提探针:setsid 出去的腿,会不会跟着控制器一起死?
# 2026-08-23,主 agent 亲手跑的。脚本与原始输出都在本文件里,不引用仓外路径。

## 为什么要探:设计压着这个前提,而当天的证据看起来跟它矛盾
08-23 r1 里 subglm 的日志停在 11:49:09 再没长过(像是腿也死了),
而 08-19 那轮四条腿都活到跑完。同一个机制两种结果 ⇒ 不许当既成事实。

## 假腿(每秒写一行,活 12 秒,退出码 3)
```
#!/usr/bin/env bash
# 假腿:每秒往日志里写一行,活 12 秒
for i in $(seq 1 12); do echo "leg alive t=$i pid=$$ sid=$(ps -o sid= -p $$ | tr -d ' ')" >> "$LEGLOG"; sleep 1; done
echo "leg finished rc=3" >> "$LEGLOG"; exit 3
```
## 假控制器(和 panel-review:526 一样 setsid --wait 起腿,然后 wait)
```
#!/usr/bin/env bash
# 假控制器:和 panel-review 一样用 setsid --wait 起腿,然后 wait
echo "ctl start pid=$$ pgid=$(ps -o pgid= -p $$ | tr -d ' ')" >> "$CTLLOG"
setsid --wait "$LEGCMD" 2>/dev/null &
LEGPID=$!
wait $LEGPID; rc=$?
echo "ctl saw leg rc=$rc" >> "$CTLLOG"
```
## 实验 A:timeout 3(SIGTERM 只打控制器)
```
腿日志 13 行:
leg alive t=1 pid=2526321 sid=2526321
leg alive t=2 pid=2526321 sid=2526321
leg alive t=3 pid=2526321 sid=2526321
leg alive t=4 pid=2526321 sid=2526321
leg alive t=5 pid=2526321 sid=2526321
leg alive t=6 pid=2526321 sid=2526321
leg alive t=7 pid=2526321 sid=2526321
leg alive t=8 pid=2526321 sid=2526321
leg alive t=9 pid=2526321 sid=2526321
leg alive t=10 pid=2526321 sid=2526321
leg alive t=11 pid=2526321 sid=2526321
leg alive t=12 pid=2526321 sid=2526321
leg finished rc=3
控制器日志:
ctl start pid=2526317 pgid=2526316
```
**结论 A:腿活着跑完(写到 leg finished rc=3),控制器死在 wait 返回之前 ⇒ 退出码永久丢失。**

## 实验 B:kill -TERM -<pgid>(SIGTERM 打整个进程组)
```
腿日志 13 行:
leg alive t=1 pid=2527012 sid=2527012
leg alive t=2 pid=2527012 sid=2527012
leg alive t=3 pid=2527012 sid=2527012
leg alive t=4 pid=2527012 sid=2527012
leg alive t=5 pid=2527012 sid=2527012
leg alive t=6 pid=2527012 sid=2527012
leg alive t=7 pid=2527012 sid=2527012
leg alive t=8 pid=2527012 sid=2527012
leg alive t=9 pid=2527012 sid=2527012
leg alive t=10 pid=2527012 sid=2527012
leg alive t=11 pid=2527012 sid=2527012
leg alive t=12 pid=2527012 sid=2527012
leg finished rc=3
控制器日志:
ctl start pid=2527008 pgid=2527008
```
**结论 B:组信号也够不着 setsid 出去的腿,它照样跑完。**

## 前提裁决
「腿活得比控制器久、而退出码只活在控制器内存里」—— **成立,两种杀法都验过。**

## 仍然敞着(不阻塞本单)
08-23 r1 里 subglm 的日志为什么没继续长,本探针**没有解释**。
两种可能:(a) 那条腿确实也死了(死因另说);(b) 它活着但在等模型回话、正文最后才落盘。
**这不影响本设计**:plan 在派发前就落盘,所以即使腿也死了,
花名册仍然答得出「派了谁」,只是那条腿标成未收尾 —— 见判据 R7。

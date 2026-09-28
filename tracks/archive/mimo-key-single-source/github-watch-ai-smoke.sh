#!/usr/bin/env bash
# GitHub-Watch 的 AI 摘要:**在使用现场**验一次(2026-09-01,track mimo-key-single-source)。
#
# 为什么要有它:本单顺手声称"删掉 cron 提示词里那段 `export LLM_API_KEY=***` 之后,
# watch.py 自然回落读配置文件 ⇒ 那份日报的 AI 摘要修好了"。而那句话当时只有
# **机制推演 + 一次 import 实测** —— 盘上改了不等于运行时好了(本机在这上面栽过两次:
# 浏览器里跑旧版脚本、gateway 内存里跑旧版 dist)。
#
# 这里用 `env -i` 造一个和 cron 一样干净的环境(不继承 ~/.bashrc 的 LLM_* 导出),
# 走**真实代码路径**要一次摘要:拿到非空中文摘要才算修好。
# ⚠️ 它会真的调一次 mimo,**不许挂进判据总跑**(判卷面不许有外网出口)。
set -uo pipefail
cd /root/.openclaw/workspace/skills/github-watch/scripts || exit 1
env -i HOME=/root PATH=/usr/bin:/bin python3 -c '
import sys,importlib.util
spec=importlib.util.spec_from_file_location("w","watch.py"); w=importlib.util.module_from_spec(spec)
sys.argv=["watch.py"]; spec.loader.exec_module(w)
print("resolved base :", w.LLM_API_BASE)
print("resolved model:", w.LLM_MODEL)
print("key present   :", bool(w.LLM_API_KEY), "len", len(w.LLM_API_KEY))  # 不印任何前缀:工件要进 git
body="## Changes\n- Add --json flag to the CLI\n- Fix crash on empty config\n"
out=w.summarize_release_with_llm(body,"demo/repo")
print("summary len:", len(out))
print(out if out else "(EMPTY)")
sys.exit(0 if out.strip() else 1)
'

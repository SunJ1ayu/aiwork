# shellcheck shell=bash
# mimo key 的位置清单 —— **全机唯一一份**(2026-09-01,track mimo-key-single-source)。
#
# 谁 source 它:
#   - bin/rotate-mimo-key            换 key 时按这张表写
#   - tests/test-mimo-key-single-source.sh   判据按这张表查
#
# **不许在别处再抄一份位置。** 这正是本单要治的病:09-01 换 key 时那把钥匙抄在 9 处、
# 没有源头,我手工换漏 3 处;而我当时留下的"防漏"是记忆里一张手抄清单 —— 手抄清单会腐烂。
# 表在这里、工具和判据都读它,清单漂了两边一起漂,判据当场红。

# ── 唯一源头 ──────────────────────────────────────────────────────────────
# 刻意**不新建**一个 `secrets/mimo-key` 文件:那只会变成第 10 处。
# `/root/.local/share/mimocode/auth.json` 已经是 mimo CLI 的规范凭证位置,而且
# `submimo-iso` 每次跑都从它 re-seed 到隔离树 —— 它本来就是事实上的源头,
# 本单做的是**承认它、让别人都指向它**,不是另起炉灶。
MIMO_KEY_SOURCE="/root/.local/share/mimocode/auth.json"
MIMO_KEY_SOURCE_SELECTOR="xiaomi.key"

# ── 必须存字面量的副本(格式是别人定的,只能存一份拷贝)────────────────────
# 格式:类型|路径|取值路径
#   json  = JSON 文件,取值路径用 . 分隔
#
# 这些副本**由 rotate-mimo-key 写**,人不要手动碰。
# 隔离树那两份(mimo-home/{claude,codex})故意**不在表里**:它们由 submimo-iso
# 每次跑时从源头 re-seed,自愈。把自愈的东西写进表里,等于给自己派一份不必要的活,
# 而且会在"刚跑过一次派活"和"还没跑过"之间制造假红。
MIMO_KEY_COPIES=(
  "json|/root/.openclaw/secrets.json|models.providers.xiaomi-coding.apiKey"
  "json|/root/.openclaw/secrets.json|models.providers.xiaomi-token.apiKey"
  "json|/root/.openclaw/secrets.json|messages.tts.providers.xiaomi.apiKey"
  "json|/root/.github-watch-config.json|api_key"
)

# ── 有条件的副本:**在的时候**必须与源头一致,不在也合法 ──────────────────
# `~/.claude/settings.json` 是 `switch-model.sh` 生成的:切到 mimo 档时里面有 key,
# 切回 claude 档时压根没有这个字段。所以它既不能进 MIMO_KEY_COPIES(会在 claude 档假红),
# 也不能进 MIMO_KEY_FORBIDDEN(它就是要带 key 才能工作)。
# 正确的不变量是**条件式**的:有就必须对。
MIMO_KEY_CONDITIONAL_COPIES=(
  "/root/.claude/settings.json"
)

# ── 决定"这把 key 打到哪去"的字段 ─────────────────────────────────────────
# 光钉住 key 一致是不够的:`watch.py` 的取值顺序是「环境变量优先,空了才读配置文件」,
# 而**回落只在 api_key 为空时发生** —— 配置文件里 api_base/model 一旦缺席,
# 它会**静默**用回 OpenAI 的默认端点和 gpt-4o-mini,拿着小米的 key 去打 OpenAI ⇒ 401,
# 而 `except Exception: return ""` 把这一切吞掉。
# 那正是本单起因(GitHub-Watch 的 AI 摘要坏了不知道多久)的同一个形状:
# **一个 key 对了,但它被送错了地方,而且没有任何东西会红。**
# 格式:路径|字段1|字段2…(都必须非空,且不许在带小米 key 时指向 OpenAI)
MIMO_KEY_ENDPOINT_FIELDS=(
  "/root/.github-watch-config.json|api_base|model"
)

# ── 明令禁止内嵌 key 的位置 ───────────────────────────────────────────────
# 这些地方**做得到运行时去源头读**,所以存字面量没有任何正当理由。
#   ~/.bashrc                  09-01 全盘搜过:`LLM_API_KEY` 没有任何消费者,已删
#   ~/.claude/switch-model.sh  已改成运行时从源头读
MIMO_KEY_FORBIDDEN=(
  "/root/.bashrc"
  "/root/.claude/switch-model.sh"
)

# ── 游离副本扫描面 ────────────────────────────────────────────────────────
# 只扫**活配置**会去的地方。刻意不扫整个 `/` :那会把会话记录、shell 快照、
# 历史备份全扫进来 —— 它们确实有旧 key,但那是历史证据,不是活副本,
# 每周红一次就等于把报警器调成噪音。
MIMO_KEY_SCAN_DIRS=(
  "/root/.bashrc"
  "/root/.profile"
  "/root/.claude"
  "/root/.config"
  "/root/.openclaw/secrets.json"
  "/root/.openclaw/openclaw.json"
  "/root/.openclaw/workspace/skills"
  "/root/.github-watch-config.json"
  "/root/.local/share/mimocode/auth.json"
  "/root/aiwork/bin"
  "/root/aiwork/tests"
)

# 排除:备份、日志、会话记录、缓存 —— 有旧 key 是正常的,它们不是活配置。
MIMO_KEY_SCAN_EXCLUDES=(
  "*.bak"
  "*.bak.*"
  "*.keyswap-*"
  "*.pre-update*"
  "*.jsonl"
  "*.log"
  "*.migrated"
)
MIMO_KEY_SCAN_EXCLUDE_DIRS=(
  "backups"
  "node_modules"
  ".git"
  "sessions"
  "shell_snapshots"
  "transcript-cache"
  "config-cache"
  "file-history"
  "projects"
  "plugins"
  "history"
)

# ── key 的形状 ────────────────────────────────────────────────────────────
# 小米的 token-plan key:tp- 前缀 + 小写字母数字。长度实测是 51(tp- + 48),
# 但写成区间而不是写死 51 —— 写死一个观测到的常数,厂商改一位就假红。
mimo_key_shape_ok() { [[ "${1:-}" =~ ^tp-[a-z0-9]{40,60}$ ]]; }

# 从源头读出当前 key(读不到就打印空串,由调用方判断)。
mimo_key_read_source() {
  python3 -c '
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    for k in sys.argv[2].split("."):
        d=d[k]
    print(d)
except Exception:
    pass' "$MIMO_KEY_SOURCE" "$MIMO_KEY_SOURCE_SELECTOR" 2>/dev/null
}

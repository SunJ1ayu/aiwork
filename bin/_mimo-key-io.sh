# shellcheck shell=bash
# mimo key 的**写/恢复原语**(2026-09-01,track mimo-key-single-source 第二轮)。
#
# 为什么单独成一个文件 —— 只有一个理由,但它够硬:**回滚路径必须能被单独测**。
# 原来这三段逻辑长在 rotate-mimo-key 肚子里,而那条路径在自动化里永远走不到:
# dry-run 跳过写、真跑要联网+网关+cron,而判卷面不许有外网出口。
# 于是"回滚是对的"就只剩我一句话。拆出来之后,判据 ⑦ 在 /tmp 上把它跑一遍:
# 原子写 → 权限保留 → 逐字节恢复 → **空快照拒绝恢复**。
#
# 谁 source 它:bin/rotate-mimo-key、tests/test-mimo-key-single-source.sh(⑦)。

# 值走**环境变量**不走 argv:/proc/<pid>/cmdline 是全局可读的,而 environ 只有属主读得到。
# 这是凭证,不是路径。
mimo_key_write_json() {   # 路径 取值路径 新值
  MIMO_KEY_IO_VALUE="$3" python3 -c '
import json,os,sys,tempfile
path,sel=sys.argv[1],sys.argv[2]
val=os.environ["MIMO_KEY_IO_VALUE"]
d=json.load(open(path))
node=d
keys=sel.split(".")
for k in keys[:-1]:
    node=node[k]
node[keys[-1]]=val
st=os.stat(path)
dirn=os.path.dirname(path) or "."
fd,tmp=tempfile.mkstemp(dir=dirn, prefix=".rotate-", suffix=".tmp")
try:
    with os.fdopen(fd,"w") as f:
        json.dump(d,f,ensure_ascii=False,indent=2)
        f.write("\n")
        f.flush(); os.fsync(f.fileno())
    os.chmod(tmp, st.st_mode & 0o7777)   # 别把 600 的凭证写成 644
    os.replace(tmp, path)
except BaseException:
    try: os.unlink(tmp)
    except OSError: pass
    raise' "$1" "$2"
}

# 取快照。**读不出来就非零退出,绝不返回空串** —— 空串正是把好文件截成 0 字节的那条路。
mimo_key_snapshot() {     # 路径 → base64(stdout)
  local b
  [[ -f "$1" ]] || { echo "mimo_key_snapshot: 文件不在:$1" >&2; return 1; }
  b="$(base64 -w0 < "$1")" || { echo "mimo_key_snapshot: 读不出:$1" >&2; return 1; }
  [[ -n "$b" ]] || { echo "mimo_key_snapshot: 内容是空的:$1(恢复一份空的没有意义)" >&2; return 1; }
  printf '%s' "$b"
}

# 恢复。和前进路径**同一套原子写**:临时文件 + fsync + os.replace + 权限保留。
# 老版本是 `printf '%s' "$snap" | base64 -d > "$f"` —— truncate-then-write,
# 正是前进路径白纸黑字要避免的那一种,而这里还是**恢复**路径:断在这儿更难看。
mimo_key_restore() {      # 路径 base64
  local path="$1" snap="${2:-}"
  [[ -n "$snap" ]] || { echo "mimo_key_restore: 空快照,拒绝恢复(那会把好文件截成 0 字节)" >&2; return 1; }
  printf '%s' "$snap" | python3 -c '
import base64,os,sys,tempfile
path=sys.argv[1]
data=base64.b64decode(sys.stdin.read())
if not data:
    sys.exit("mimo_key_restore: 解出来是空的,拒绝写")
dirn=os.path.dirname(path) or "."
try:
    mode=os.stat(path).st_mode & 0o7777
except FileNotFoundError:
    mode=0o600
fd,tmp=tempfile.mkstemp(dir=dirn, prefix=".rotate-", suffix=".tmp")
try:
    with os.fdopen(fd,"wb") as f:
        f.write(data)
        f.flush(); os.fsync(f.fileno())
    os.chmod(tmp, mode)
    os.replace(tmp, path)
except BaseException:
    try: os.unlink(tmp)
    except OSError: pass
    raise' "$path"
}

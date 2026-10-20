# Shared program bindings. Symlinks in programs/ are the machine's only choices.
aiwork_program() {
  case "$1" in python3|codex|cursor-agent|kimi|mimo|claude|node) ;; *)
    printf 'aiwork: 未登记的程序 %s\n' "$1" >&2; return 78;; esac
  local_path="$AIWORK_PROGRAMS/$1"
  if [ ! -f "$local_path" ] || [ ! -x "$local_path" ]; then
    printf 'aiwork: programs/%s: %s 缺失、路径不存在或不能执行；请设置本机程序路径\n' "$1" "$local_path" >&2
    return 78
  fi
  printf '%s\n' "$local_path"
}

aiwork_init() {
  aiwork_config="${AIWORK_CONFIG_DIR:-$HOME/.config/aiwork}"
  case "$aiwork_config" in
    '~') aiwork_config="$HOME" ;;
    '~/'*) aiwork_config="$HOME/${aiwork_config#\~/}" ;;
  esac
  # Keep relative overrides stable across the provider's later chdir.
  case "$aiwork_config" in
    /*) ;;
    *) aiwork_config="$(pwd)/$aiwork_config" ;;
  esac
  AIWORK_CONFIG_DIR="$aiwork_config"
  AIWORK_PROGRAMS="$aiwork_config/programs"
  export AIWORK_CONFIG_DIR
  aiwork_python="$(aiwork_program python3)" || return 78
  aiwork_probe="$("$aiwork_python" -c 'import sys
if sys.version_info < (3, 11):
    sys.exit("aiwork: programs/python3: %s: Python %s 低于 3.11" % (sys.executable, sys.version.split()[0]))
from pathlib import Path
print("aiwork-python-ok:" + str(Path(sys.argv[-1])))' "$aiwork_config")" || {
    printf 'aiwork: programs/python3: %s: Python 启动或版本检查失败（要求 >= 3.11）\n' "$aiwork_python" >&2
    return 78
  }
  case "$aiwork_probe" in
    aiwork-python-ok:/*)
      AIWORK_CONFIG_DIR="${aiwork_probe#aiwork-python-ok:}"
      AIWORK_PROGRAMS="$AIWORK_CONFIG_DIR/programs" ;;
    *)
      printf 'aiwork: programs/python3: %s: 不是可用的 Python 3.11+ 解释器\n' "$aiwork_python" >&2
      return 78 ;;
  esac
  # Bind env-python/node shebangs as well as our explicit calls.
  PATH="$AIWORK_PROGRAMS:$PATH"
  export AIWORK_PROGRAMS PATH
  case "$1" in
    subcodex) aiwork_needed='codex node' ;;
    subkimi) aiwork_needed='kimi node' ;;
    submimo) aiwork_needed='mimo node' ;;
    subcursor) aiwork_needed='cursor-agent node' ;;
    subagent|subdeepseek-agent) aiwork_needed='claude node' ;;
    review-pr) aiwork_needed=node ;;
    *) aiwork_needed= ;;
  esac
  for aiwork_name in $aiwork_needed; do
    aiwork_program "$aiwork_name" >/dev/null || return 78
  done
}

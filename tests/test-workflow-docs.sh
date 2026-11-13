#!/usr/bin/env bash
# 唯一规范源 + 部署副本判据(workflow-control-plane T7)。
# Run: bash /root/aiwork/tests/test-workflow-docs.sh
set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_no-egress.sh" || exit 78

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/workflow"
SYNC="$ROOT/bin/sync-workflow-docs"
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

workflow_mappings() {
  local skill name
  printf '%s\n' 'CLAUDE.md|CLAUDE.md'
  for skill in "$SOURCE"/skills/*/SKILL.md; do
    [[ -f "$skill" ]] || continue
    name="$(basename "$(dirname "$skill")")"
    printf '%s\n' "skills/${name}/SKILL.md|.claude/skills/${name}/SKILL.md"
  done
}
MAPPINGS=()
while IFS= read -r mapping; do
  MAPPINGS+=("$mapping")
done < <(workflow_mappings)

echo "=== workflow docs oracle ==="
# 家目录里那份部署副本是本机状态。同步器对临时目录的行为由下面 W2 问;
# 这台机器的副本是否跟上,不在仓库判据里。

echo "[W2] 同步器按 workflow/skills/*/SKILL.md 推导 skill，漂移默认拒绝、显式 force 才覆盖"
if [[ -x "$SYNC" ]]; then
  d="$(test_mktemp -d)"; outside="$(test_mktemp)"
  mkdir -p "$d/.claude/skills/track"
  printf 'retired deployed skill: cleanup after merge\n' > "$d/.claude/skills/track/SKILL.md"
  printf 'outside\n' > "$outside"
  "$SYNC" --target-root "$d" --check >/dev/null 2>&1; rc=$?
  check "W2: 空部署根 --check 必须报漂移" $([[ $rc -ne 0 ]]; echo $?)

  "$SYNC" --target-root "$d" >/dev/null 2>&1; rc=$?
  check "W2: 缺失的受管文件可安全首次安装" $([[ $rc -eq 0 ]]; echo $?)
  for spec in "${MAPPINGS[@]}"; do
    src="${spec%%|*}"; dst="${spec#*|}"
    cmp -s "$SOURCE/$src" "$d/$dst" || rc=1
  done
  check "W2: 首次安装后所有受管文件逐字节一致" "$rc"

  mkdir -p "$d/.claude"; printf 'settings-sentinel\n' > "$d/.claude/settings.json"
  printf 'local-edit\n' >> "$d/CLAUDE.md"
  "$SYNC" --target-root "$d" >/dev/null 2>&1; rc=$?
  check "W2: 已有副本漂移时默认拒绝覆盖" $([[ $rc -ne 0 ]]; echo $?)
  grep -q 'local-edit' "$d/CLAUDE.md"
  check "W2: 拒绝后现场改动仍在" $?

  "$SYNC" --target-root "$d" --force >/dev/null 2>&1; rc=$?
  check "W2: 显式 --force 才更新已漂移受管文件" $([[ $rc -eq 0 ]]; echo $?)
  cmp -s "$SOURCE/CLAUDE.md" "$d/CLAUDE.md"
  check "W2: force 后回到唯一源字节" $?
  grep -qx 'settings-sentinel' "$d/.claude/settings.json"
  check "W2: settings 等非清单现场零触碰" $?
  grep -qx 'retired deployed skill: cleanup after merge' "$d/.claude/skills/track/SKILL.md"
  check "W2: 退役 track 部署副本留给合并后清理，同步器不删除它" $?
  "$SYNC" --target-root "$d" --check >/dev/null 2>&1; rc=$?
  check "W2: 同步后的 --check 通过" $([[ $rc -eq 0 ]]; echo $?)

  rm -f "$d/CLAUDE.md"; ln -s "$outside" "$d/CLAUDE.md"
  "$SYNC" --target-root "$d" --force >/dev/null 2>&1; rc=$?
  check "W2: 受管目标是符号链接时即使 force 也拒绝" $([[ $rc -ne 0 ]]; echo $?)
  grep -qx 'outside' "$outside"
  check "W2: 不会沿链接覆盖清单外文件" $?
  rm -rf "$d"; rm -f "$outside"
else
  bad "W2: bin/sync-workflow-docs 存在且可执行"
fi

echo "[W3] 流程规则只有一个来源:说明文档指向 REVIEW-RULES.md,且没有任何文档要求自定风险等级或评审预算"
shopt -s nullglob
docs=("$ROOT/README.md" "$SOURCE/CLAUDE.md" "$SOURCE"/skills/*/SKILL.md "$SOURCE"/skills/*/references/*.md)
shopt -u nullglob
for f in "${docs[@]}"; do
  [[ -f "$f" ]] || continue
  grep -q 'REVIEW-RULES.md' "$f"
  check "W3: ${f#$ROOT/} 指向 REVIEW-RULES.md" $?
done
for f in "${docs[@]}"; do
  [[ -f "$f" ]] || continue
  ! grep -qE 'impact-risk|design-uncertainty|--risk |self/standard/high|self=0|standard=1|high=2|评审预算|decision\.json|lane:|必须挂.*track|--track NAME' "$f"
  check "W3: ${f#$ROOT/} 没有自定风险等级/评审预算的旧流程" $?
done
[[ ! -e "$SOURCE/skills/track/SKILL.md" ]] && ! grep -q 'skills/track' "$ROOT/bin/sync-workflow-docs"
check "W3: track skill 已退役,且不在 sync-workflow-docs 清单里" $?
echo "[W3] 留下的通道：文档与实现读同一份本机模型设置"
grep -q 'subdeepseek-agent' "$ROOT/README.md" \
  && grep -q 'subkimi' "$ROOT/README.md" \
  && grep -q 'submimo' "$ROOT/README.md" \
  && grep -q 'subcursor' "$ROOT/README.md" \
  && grep -q 'subcodex' "$ROOT/README.md"
check "W3: README 列出留下的五条评审命令" $?
grep -q 'Codex、Cursor、DeepSeek、Kimi、MiMo' "$SOURCE/CLAUDE.md" \
  && grep -q '每个通道都能写代码也能评审；同一个 PR 的评审要换一家，由关卡判断' "$SOURCE/CLAUDE.md"
check "W3: 主工作流只列留下的五家，并写明换评审由关卡判断" $?
[[ "$(env -u DEEPSEEK_MAX_TURNS "$ROOT/bin/aiwork-config" runtime subdeepseek-agent max_turns)" == 200 ]] \
  && bash "$ROOT/bin/subagent" -h 2>&1 | grep -q 'deepseek.env'
check "W3: DeepSeek 默认轮次是 200，帮助文本指向本机凭证" $?
[[ "$(env -u KIMI_TIMEOUT "$ROOT/bin/aiwork-config" runtime subkimi timeout)" == 1500 ]]
check "W3: Kimi 超时默认 1500 秒" $?
grep -q 'MODEL_LEG=mimo' "$ROOT/bin/subagent" \
  && grep -Fq 'model "$MODEL_LEG"' "$ROOT/bin/subagent" \
  && ! grep -q 'DEFAULT_MODEL="mimo-' "$ROOT/bin/subagent"
check "W3: MiMo 默认模型来自本机设置，代码不复制版本号" $?
! grep -q 'skills/panel' "$ROOT/bin/sync-workflow-docs"
check "W3: 同步清单不再部署已删除的方案说明" $?

echo "[W4] 操作流程与保留的方法"
grep -q '最新 main' "$SOURCE/CLAUDE.md" \
  && grep -q 'tests/' "$SOURCE/CLAUDE.md" \
  && grep -q '机器人' "$SOURCE/CLAUDE.md" \
  && grep -q '停下' "$SOURCE/CLAUDE.md"
check "W4: 任务通过分支、实现、全测、机器人 PR 收尾" $?
grep -q 'CI 绿了以后' "$SOURCE/CLAUDE.md" \
  && grep -q '见 `summary` skill' "$SOURCE/CLAUDE.md" \
  && ! grep -q 'skills/summary/SKILL.md' "$SOURCE/CLAUDE.md" \
  && ! grep -q '另一家族' "$SOURCE/CLAUDE.md" \
  && grep -q 'review-pr.*沙箱外' "$SOURCE/CLAUDE.md" \
  && grep -q 'review-pr' "$SOURCE/CLAUDE.md"
check "W4: CI 绿后用沙箱外 review-pr 派评审，各腿出结果后由汇总处理" $?
grep -q 'review-pr` 从共享检出跑，跑之前先把共享检出更新到最新 main' "$SOURCE/CLAUDE.md" \
  && ! grep -q '从共享检出跑，跑之前先把共享检出更新到最新 main；合并后用' "$SOURCE/CLAUDE.md" \
  && grep -q '合并由项目关卡或业主完成。合并后用 `sync-workflow-docs` 同步部署出去的工作流文档。' "$SOURCE/CLAUDE.md"
check "W4: review-pr 从更新过的共享检出跑，合并后同步工作流文档" $?
grep -q '不改考卷让自己及格' "$SOURCE/CLAUDE.md" \
  && grep -q '不信执行腿的自述' "$SOURCE/CLAUDE.md"
check "W4: 保留判据核实与收货方法" $?
grep -q 'PR 任务单' "$SOURCE/skills/delegate/SKILL.md" \
  && grep -q '派 PR 任务的任务单格式' "$SOURCE/skills/delegate/SKILL.md" \
  && ! grep -q -- '--receive' "$SOURCE/skills/delegate/SKILL.md" \
  && ! grep -q 'delegate-codex' "$SOURCE/skills/delegate/SKILL.md" \
  && ! grep -q 'redcheck' "$SOURCE/skills/delegate/SKILL.md" \
  && ! grep -q -- '--no-track' "$SOURCE/skills/delegate/SKILL.md" \
  && ! grep -q -- '--track' "$SOURCE/skills/delegate/SKILL.md"
check "W4: 任务单只留 PR 任务单格式，不再写旧委托入口" $?
grep -q '~/.config/aiwork/' "$SOURCE/CLAUDE.md" \
  && grep -q 'README「本机设置」' "$SOURCE/CLAUDE.md" \
  && grep -q '里面有哪些东西见 aiwork 仓库 bin/_aiwork_config.py 的登记表' "$SOURCE/CLAUDE.md" \
  && ! grep -q '包含 tasks、logs、worktrees、运行期 home 和 archive' "$SOURCE/CLAUDE.md"
check "W4: 设置目录写明，运行数据指向登记表" $?
grep -q 'aiwork-config data-path worktrees' "$SOURCE/CLAUDE.md" \
  && grep -q '不在共享检出' "$SOURCE/CLAUDE.md" \
  && grep -q 'PR 合并后删掉这个工作树' "$SOURCE/CLAUDE.md"
check "W4: 开工先在本机数据目录建工作树，不在共享检出里改" $?

python3 - "$ROOT" <<'PY'
from pathlib import Path
import os
import re
import shlex
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
workflow = (root / 'workflow/CLAUDE.md').read_text()
assert 'workflow/CLAUDE.md#机器人推送与开-pr' in (root / 'AGENTS.md').read_text(), 'AGENTS 缺少指向'

# 防的是把认证数据放进命令参数，或直接打印到日志的示例。
unsafe = re.compile(
    r'http(?:\.[^\s=]+)?\.extraheader\s*='
    r'|https?://[^\s/]+@'
    r'|\benv\s+[^\n]*\b(?:GH_TOKEN|GITHUB_TOKEN)='
    r'|(?:--header|-H)\s+[\'"]?Authorization:'
    r'|--(?:token|password|oauth-token)(?:[ =]|$)'
    r'|\b(?:echo|printf|printenv)\b[^\n]*\$\{?(?:GH_TOKEN|GITHUB_TOKEN|token)\b',
    re.I,
)
safe_statement = re.compile(r'(?<=;)\s*printf\s+[^;]+;')
safe_output = safe_statement.search(workflow).group(0).strip().removesuffix(';')

def shell_blocks(text):
    return [block.replace('\\\n', ' ') for block in
            re.findall(r'^```(?:bash|sh|shell)\n(.*?)^```', text, re.M | re.S)]


def check_workflow(text):
    assert text.count('\n## 机器人推送与开 PR\n') == 1, '机器人推送说明须只有一个入口'
    commands = []
    for block in shell_blocks(text):
        for line in block.splitlines():
            if line.lstrip().startswith('git config '):
                commands.append(shlex.split(line))
    for block in shell_blocks(text):
        for line in block.splitlines():
            words = shlex.split(line) if line.strip().startswith('git ') else []
            if 'push' in words:
                assert words[1] == 'push', '推送不得携带覆盖凭证设置的命令选项'
    helpers = [words[-1] for words in commands if words[-1].startswith('!')]
    assert len(helpers) == 1, '文档须包含一个可执行凭证助手配置'
    helper = helpers[0]
    # 只放过交给 Git 的这一句 stdout，助手其余内容仍受原有扫描约束。
    remaining = safe_statement.sub('', helper)
    assert not unsafe.search(remaining), '助手含不安全的认证示例'
    remaining = remaining.replace('test -n "$token"', '')
    assert not re.search(r'\$\{?(?:token|GH_TOKEN|GITHUB_TOKEN)\b', remaining), '助手把令牌用于凭证输出以外的位置'
    for block in shell_blocks(text):
        assert not unsafe.search(block.replace(helper, safe_statement.sub('', helper))), '命令含不安全的认证示例'

    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        tool = directory / 'gh-app-token'
        home = directory / 'home'
        (home / '.config').mkdir(parents=True)
        calls = directory / 'token-calls'
        tool.write_text('#!/bin/sh\nprintf called >> "$TOKEN_CALLS"\nprintf "%s\\n" fixture-credential\n')
        tool.chmod(0o700)
        env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        env.update(PATH=str(directory) + os.pathsep + os.environ.get('PATH', os.defpath),
                   HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
                   GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=str(home / '.gitconfig'),
                   GIT_TERMINAL_PROMPT='0', TOKEN_CALLS=str(calls))

        def run(args, **kwargs):
            result = subprocess.run(args, cwd=directory, env=env, text=True,
                                    capture_output=True, **kwargs)
            assert 'fixture-credential' not in result.stderr, '凭证泄漏到标准错误'
            return result

        run(['git', 'init', '-q'], check=True)
        credential_key = 'credential.https://github.com.helper'
        run(['git', 'config', '--local', credential_key, 'store'], check=True)
        expected_config = [('credential.helper', ''), (credential_key, ''), (credential_key, helper)]
        for _ in range(2):
            for command in commands:
                result = run(command)
                assert result.returncode == 0 or ('--unset-all' in command and result.returncode == 5)
            output = run(['git', 'config', '--null', '--get-regexp', r'^credential\.'], check=True).stdout
            actual_config = [tuple(entry.split('\n', 1)) for entry in output.rstrip('\0').split('\0')]
            assert actual_config == expected_config, '最终凭证设置须恰为清空项和文档助手，不许多项或缺项'
        credential = 'protocol=https\nhost=github.com\nusername=x-access-token\n\n'
        result = run(['git', 'credential', 'fill'], input=credential, check=True)
        assert 'password=fixture-credential\n' in result.stdout
        filled_credential = result.stdout

        def files():
            return {str(path.relative_to(directory)): path.read_bytes()
                    for path in directory.rglob('*') if path.is_file()}

        before = files()
        run(['git', 'credential', 'approve'], input=filled_credential, check=True)
        assert files() == before, 'approve 调用了取令牌程序或写出了凭证文件'
        for operation in ('get', 'store', 'erase'):
            before = files()
            result = run(['sh', '-c', helper[1:] + ' ' + operation],
                         input=credential if operation == 'get' else filled_credential, check=True)
            expected = 'username=x-access-token\npassword=fixture-credential\n' if operation == 'get' else ''
            assert result.stdout == expected
            if operation != 'get':
                assert files() == before, '非 get 操作取了令牌或写入了文件'
        for url in ('https://github.com.evil.com', 'https://evil.com', 'http://github.com'):
            result = run(['git', 'credential', 'fill'], input='url=' + url + '\n\n')
            assert result.returncode != 0 and 'fixture-credential' not in result.stdout
        for script in ('#!/bin/sh\nexit 1\n', '#!/bin/sh\nexit 0\n'):
            tool.write_text(script)
            result = run(['git', 'credential', 'fill'], input=credential)
            assert result.returncode != 0 and not result.stdout
            result = run(['sh', '-c', helper[1:] + ' get'])
            assert result.returncode != 0 and not result.stdout
    return helper


helper = check_workflow(workflow)
equivalent = workflow.replace(safe_output, r'printf "username=%s\npassword=%s\n" x-access-token "$token"')
check_workflow(equivalent)
try:
    check_workflow(workflow.replace('git push --set-upstream', 'git -c credential.helper=store push --set-upstream'))
except AssertionError:
    pass
else:
    raise AssertionError('命令行覆盖凭证设置未被拦截')
# 这些只检查助手自身的令牌输出行为；配置增删统一由完整结果核对覆盖。
behavior_mutations = {
    'stderr': workflow.replace(helper, helper.replace('; printf ', '; echo "$token" >&2; printf ')),
    'argv': workflow.replace(helper, helper.replace('; printf ', '; sh -c : "$token"; printf ')),
    'external_printf': workflow.replace(helper, helper.replace(safe_output, 'env ' + safe_output)),
    'redirect': workflow.replace(helper, helper.replace(safe_output, safe_output + ' >&2')),
    'pipe': workflow.replace(helper, helper.replace(safe_output, safe_output + ' | tee /dev/stderr')),
}
for name, changed in behavior_mutations.items():
    assert changed != workflow, f'{name}: 变异未命中'
    try:
        check_workflow(changed)
    except (AssertionError, subprocess.CalledProcessError):
        pass
    else:
        raise AssertionError(f'{name}: 不安全或不完整的文档仍被接受')

docs = [root / 'AGENTS.md', root / 'README.md', *sorted((root / 'workflow').rglob('*.md'))]
for path in docs:
    if path == root / 'workflow/CLAUDE.md':
        continue
    for command in shell_blocks(path.read_text()):
        assert not unsafe.search(command), f'{path.relative_to(root)} 有不安全的认证示例'
PY
check "W4: 机器人推送说明有唯一入口，命令示例不把令牌放进参数或日志" $?

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
rules = (root / 'REVIEW-RULES.md').read_text()
definitions = re.findall(r'^### ([^\n]+五级证据)\n(.*?)(?=^## |^### |\Z)', rules, re.M | re.S)
assert len(definitions) == 1, '五级证据应只有一处定义'
heading, definition = definitions[0]
levels = re.findall(r'^([1-5])\. \*\*(.+?)\*\*', definition, re.M)
assert [int(n) for n, _ in levels] == list(range(1, 6)), '定义应含五个有序等级'
assert f'至少到「{levels[3][1]}」' in definition and '待业主确认' in definition
assert 'ci.workflow_path' in definition and '新测试先红' in definition
assert '业主决定' in definition and '已接受风险' in definition and '逐个打开' in definition
slug = re.sub(r'[^\w\s-]', '', heading.lower()).replace(' ', '-')
target = 'https://github.com/SunJ1ayu/aiwork/blob/main/REVIEW-RULES.md#' + slug
summary = (root / 'workflow/skills/summary/SKILL.md').read_text()
delegate = (root / 'workflow/skills/delegate/SKILL.md').read_text()
references = [next(line for line in summary.splitlines() if line.startswith('2. 核实：')),
              next(line for line in delegate.splitlines() if line.startswith('- 【完成标准】'))]
for reference in references:
    assert target in reference, '核实和完成标准应指向实际定义标题'
    assert not any(label in reference for _, label in levels), '引用不应复述证据等级'
for path in (root / 'workflow').rglob('*.md'):
    assert not any(re.search(r'^\s*[1-5]\. \*\*' + re.escape(label) + r'\*\*', path.read_text(), re.M)
                   for _, label in levels), f'{path.relative_to(root)} 重复定义证据等级'
PY
check "W4: 五级证据只有一处定义，核实与完成标准指向实际定义且不复述等级" $?

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

rules = (Path(sys.argv[1]) / 'REVIEW-RULES.md').read_text()
opening = rules.split('\n---\n', 1)[0]
assert '以关卡算出的数为准' not in opening, '开头不应无条件要求关卡读数'
assert '读数口径、上限与停的定义见第三节第 1 条' in opening
rounds = next(line for line in rules.splitlines() if line.startswith('1. **修改轮数上限**'))
assert '启用轮数显示时' in rounds and '未启用时' in rounds
assert 'DEFAULT_MODIFICATION_ROUND_LIMIT' in rounds
assert '2026-09-28' in rounds
assert 'https://github.com/SunJ1ayu/aiwork/commit/bf94cbf98e100a30f0202a3db0c4a63a1d060979' in rounds, '丢失既有决定的历史出处'
PY
check "W4: 轮数读数按启用情况区分，默认上限保留共享定义及既有历史出处" $?

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
summary = (root / 'workflow/skills/summary/SKILL.md').read_text()
checklist = summary.split('## 汇总核对清单\n', 1)[1].split('\n## ', 1)[0]
assert '此前' in checklist and '已核实的坑' in checklist
assert '第一次' in checklist and '为空' in checklist
explore = (root / 'workflow/skills/explore/SKILL.md').read_text()
assert '不按票数评判' in explore and '不按票数采纳' not in explore
delegate = (root / 'workflow/skills/delegate/SKILL.md').read_text()
assert '写单前' in re.search(r'^description: (.+)$', delegate, re.M).group(1)
assert 'diff 原文' in delegate and '不能只给 PR 号' in delegate
PY
check "W4: PR #60 遗留的清单来源、首轮可空、方案评判和题面要求明确" $?

echo "[W5] 旧 track 流程不留在仓库里"
for gone in bin/track bin/track-guard bin/track-record bin/track-commit-msg \
            bin/runlog bin/_evidence.sh bin/_review_delivery.py bin/_ephemeral-refs.sh \
            track tracks WORKFLOW-DEBT.md WORKFLOW-MIGRATION-PLAN.md workflow-migration \
            tests/test-track-guard.sh tests/test-track-record.sh tests/test-track-links.sh \
            tests/test_track_preflight.py tests/test-ledger.sh tests/test-runlog.sh \
            tests/test_review_delivery.py tests/mutation-review-delivery.sh \
            tests/test-panel-round-discipline.sh tests/test-delegate-observation.sh \
            tests/test-worktree-sweep.sh tests/test-evidence-lifetime.sh \
            bin/delegate-codex bin/redcheck bin/submimo-iso bin/triage \
            triage templates/fix-task.md tests/test-delegate-entry.sh \
            tests/test-delegate-isolate.sh tests/test-submimo-fix-oracle.sh \
            tests/_oracle_hash.sh; do
  [[ ! -e "$ROOT/$gone" ]]
  check "W5: 已删除 $gone" $?
done
! grep -q 'track-guard|bash' "$ROOT/bin/rust-check-review-tooling" \
  && ! grep -q 'track-record|bash' "$ROOT/bin/rust-check-review-tooling" \
  && ! grep -q 'runlog|bash' "$ROOT/bin/rust-check-review-tooling" \
  && ! grep -q 'fix-oracle|bash' "$ROOT/bin/rust-check-review-tooling" \
  && ! grep -q 'delegate-entry|bash' "$ROOT/bin/rust-check-review-tooling" \
  && ! grep -q 'delegate-isolate|bash' "$ROOT/bin/rust-check-review-tooling"
check "W5: 总跑不再登记 track / runlog / 旧委托套件" $?
# 历史段只留一句指向，不复述过滤、归档仓库或提交个数。
hist="$(awk '/^## History/{flag=1;next} /^## /{flag=0} flag' "$ROOT/README.md")"
[[ "$(printf '%s\n' "$hist" | grep -cve '^[[:space:]]*$')" -eq 1 ]]
check "W5: README 历史部分只有一句" $?
printf '%s\n' "$hist" | grep -q 'git 历史' \
  && ! printf '%s\n' "$hist" | grep -q 'aiwork-archive' \
  && ! printf '%s\n' "$hist" | grep -q '639'
check "W5: 那一句指向 git 历史，不复述内容" $?

echo "=== total: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]

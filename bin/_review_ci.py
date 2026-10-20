"""Bounded, advisory CI context; never a gate or a prerequisite for dispatch."""
from __future__ import annotations

from dataclasses import dataclass
import json
import re
import time
import subprocess
from _aiwork_config import program
from pathlib import Path
from urllib.parse import quote
from urllib.error import HTTPError

MAX_BYTES = 4096
MAC_PATH = '.github/workflows/ci-macos.yml'
STEPS = {
    'linux': 'Run the offline suite inside a real network namespace',
    'mac': 'All offline suites (report only for now)',
}
NO_EGRESS_STEP = 'No-egress suite (must pass)'


def workflow_paths(policy):
    return {'linux': (policy or {}).get('ci', {}).get('workflow_path', '策略 CI（路径没取到）'),
            'mac': MAC_PATH}


def select_run(runs, head, policy, number, timeout):
    result = subprocess.run([str(program('node')), str(Path(__file__).with_suffix('.mjs'))],
                            input=json.dumps(dict(runs=runs, head=head, policy=policy, number=number)),
                            text=True, capture_output=True, timeout=timeout, check=True)
    return json.loads(result.stdout)['run']



@dataclass
class Result:
    state: str = '没取到'
    reason: str = ''
    red: set[str] | None = None
    network: str = '没取到'


def error_reason(exc: Exception) -> str:
    # API diagnostics can include response bodies. Keep only the error category.
    code = exc.code if isinstance(exc, HTTPError) else None
    match = re.search(r'HTTP\s*(\d{3})', str(exc))
    if match:
        code = int(match[1])
    if code:
        return f'HTTP {code}' + ('，权限不足' if code in (401, 403) else '')
    if isinstance(exc, TimeoutError) or 'rc=124' in str(exc):
        return '查询超时'
    return '接口出错或返回格式异常'


def state(item: dict) -> str:
    if item.get('status') != 'completed':
        return '还在跑'
    conclusion = item.get('conclusion')
    if conclusion == 'success':
        return '通过'
    if conclusion == 'skipped':
        return '没有运行（skipped）'
    if conclusion in ('failure', 'cancelled', 'timed_out', 'action_required', 'neutral', 'stale', 'startup_failure'):
        return '失败（' + conclusion + '）'
    return '没取到（GitHub 未给出结论）'


def parse_red(log: str, expected: str) -> set[str]:
    """Only runner summary lines become names; no log prose enters the task."""
    if len(log.encode('utf-8')) > 4 * 1024 * 1024:
        raise ValueError('log too large')
    outcome = None
    red = set()
    for raw in log.splitlines():
        line = re.sub(r'^\d{4}-\d{2}-\d{2}T\S+Z\s+', '', raw).strip()
        if line.startswith('✅ 工具链防锈通过'):
            outcome, red = 'success', set()
        elif line.startswith('❌ 工具链防锈失败'):
            outcome, red = 'failure', set()
        elif outcome == 'failure':
            match = re.fullmatch(r'--- ([A-Za-z0-9][A-Za-z0-9_.-]{0,63}) \(rc=([1-9][0-9]*)\) ---', line)
            if match:
                red.add(match[1])
    if outcome != expected or (outcome == 'failure' and not red):
        raise ValueError('no complete, consistent suite summary')
    return red


def render(head: str, main: str, results: dict, *, policy=None, gate='关卡结论没取到（未查询）') -> str:
    paths = workflow_paths(policy)
    lines = [
        '## CI 结果',
        f'当前 head：{head}；main 当前提交：{main}。',
        '可信度：状态和结论来自 GitHub 接口；Linux 的 G1 原样引用关卡自己的检查，不从工作流 success 推断。'
        '套件名单从日志解析，日志由 PR 自己的代码打印，只能参考，不能证明测到了点子上。未列出日志原文。',
        '正式测试套件在评审环境触发断网守卫拒跑（78）是正常环境限制，不是 PR 的问题；'
        '要看测试结果请看本节，不必在腿自己的环境重跑正式套件。Mac CI 只报不拦；'
        '多出来的红套件是否构成问题，由评审按 REVIEW-RULES 判断。',
        '红名单仅与查询时 main 当前提交比较，不说明因果；不在红名单不等于通过，也可能未运行或被删除。',
    ]
    baseline = results.get(('main', 'linux'), Result(reason='未查询'))
    lines.append(f'- {paths["linux"].rsplit("/", 1)[-1]}（Linux，关卡要求通过）：当前 head {gate}；main 工作流 {baseline.state}。')
    current = results.get(('head', 'linux'), Result())
    lines.append(f'  本 PR 关联的工作流运行状态（不代替 G1）：{current.state}。')
    current, baseline = (results.get((side, 'mac'), Result()) for side in ('head', 'main'))
    lines.append(f'- ci-macos.yml（Mac，只报不拦）：当前 head {current.state}；main {baseline.state}。')
    lines.append(f'Mac 断网判据：{current.network}；main：{baseline.network}。')
    for kind, path in paths.items():
        current = results.get(('head', kind), Result(reason='未查询'))
        baseline = results.get(('main', kind), Result(reason='未查询'))
        lines.append(path.rsplit('/', 1)[-1] + ' 套件（仅日志参考）：')
        for label, result in (('当前 head', current), ('main', baseline)):
            names = json.dumps(sorted(result.red), ensure_ascii=False) if result.red is not None else '没取到'
            reason = ('（' + result.reason + '）') if result.reason else ''
            lines.append(f'- {label} 红套件：{names}{reason}')
        if current.red is None or baseline.red is None:
            lines.append('- 对比没取到：一侧还在跑、没有运行或套件名单没取到；不推断红名单差异。')
        else:
            for label, names in (
                ('相对 main 当前提交，多出来的红套件', current.red - baseline.red),
                ('两边都有的红套件', current.red & baseline.red),
                ('不再出现在红名单里的套件', baseline.red - current.red),
            ):
                lines.append('- ' + label + '：' + json.dumps(sorted(names), ensure_ascii=False))
    text = '\n'.join(lines) + '\n'
    notice = '\n（CI 结果超过 4 KiB，已截断；未展示的名单和对比请勿推断。）\n'
    raw = text.encode('utf-8')
    if len(raw) > MAX_BYTES:
        text = raw[:MAX_BYTES - len(notice.encode('utf-8'))].decode('utf-8', 'ignore') + notice
    return text


def gate_g1(checks, policy, head, number):
    mine = [c for c in checks if c.get('name') == policy['check_name'] and c.get('head_sha') == head
            and c.get('app', {}).get('id') == policy['gate_app_id']]
    if not mine:
        return '关卡还没判（该 head 没有关卡自己的检查）'
    check = max(mine, key=lambda c: c['id'])
    if check['status'] != 'completed':
        return '关卡还没判（检查仍在运行）'
    output = check.get('output') or {}
    prs = [p['number'] for p in check.get('pull_requests', [])]
    # 多 PR 共用 head 时，关卡只为挑中的一个 PR 展开 G1，其他 PR 不能借用它。
    title_pr = re.match(r'PR #(\d+):', output.get('title', ''))
    attributable = (int(title_pr[1]) == number if title_pr else prs == [number])
    if not attributable:
        return '关卡结论没取到（检查未明确给出本 PR 的 G1）'
    lines = re.findall(r'^[✅❌] G1 [^\r\n]*$', output.get('summary', ''), re.M)
    if len(lines) != 1:
        return '关卡结论没取到（检查没有唯一的 G1 结论）'
    return lines[0][:512]


def context(api, *, repository: str, head: str, main: str | None, number: int, policy) -> str:
    deadline = time.monotonic() + 45
    results = {}
    paths = workflow_paths(policy)

    def remaining():
        seconds = deadline - time.monotonic()
        if seconds <= 0:
            raise TimeoutError('CI reference budget exhausted')
        return min(10, seconds)

    def get(endpoint, **kwargs):
        return api(endpoint, timeout=remaining(), **kwargs)

    def pages(endpoint, key):
        items = []
        for page in range(1, 11):
            data = get(endpoint + f'&page={page}')
            batch, total = data[key], data['total_count']
            if not isinstance(batch, list) or not isinstance(total, int):
                raise ValueError('invalid pagination')
            items.extend(batch)
            if len(items) == total:
                return items
            if not batch or len(items) > total:
                break
        raise ValueError('incomplete pagination')

    if not policy:
        return render(head, main or '没取到', {}, gate='关卡结论没取到（项目 main 的策略没取到）')
    try:
        checks = pages(f'repos/{repository}/commits/{head}/check-runs?per_page=100', 'check_runs')
        gate = gate_g1(checks, policy, head, number)
    except Exception as exc:
        gate = '关卡结论没取到（' + error_reason(exc) + '）'
    for side, sha in (('head', head), ('main', main)):
        try:
            if sha is None:
                raise ValueError('main SHA unavailable')
            event = policy['ci']['event'] if side == 'head' else 'push'
            query = f'repos/{repository}/actions/runs?head_sha={sha}&event={quote(event, safe="")}&per_page=100'
            if side == 'main':
                query += '&branch=main'
            runs = pages(query, 'workflow_runs')
        except Exception as exc:
            for kind in paths:
                results[side, kind] = Result(reason=error_reason(exc))
            continue
        for kind, path in paths.items():
            result = Result()
            results[side, kind] = result
            try:
                selection_policy = {'ci': {**policy['ci'], 'workflow_path': path}}
                run = select_run(runs, sha, selection_policy, number if side == 'head' else None, remaining())
                if not run:
                    result.state = result.network = '没有运行'
                    result.reason = '没有关联到本 PR 编号的同一工作流运行' if side == 'head' else '没有 main 当前提交的同一工作流运行'
                    continue
                result.state = state(run)
                result.reason = result.state if result.state != '通过' else ''
                rid, attempt = run['id'], run['run_attempt']
                if type(rid) is not int or type(attempt) is not int or min(rid, attempt) < 1:
                    raise ValueError('invalid run identity')
                jobs = pages(f'repos/{repository}/actions/runs/{rid}/attempts/{attempt}/jobs?per_page=100', 'jobs')
                network = [state(step) for job in jobs for step in job.get('steps', []) if step['name'] == NO_EGRESS_STEP]
                result.network = (next((v for v in network if v != '通过'), '通过') if network else
                                  '还在跑' if run['status'] != 'completed' else '没有运行')
                if run['status'] != 'completed':
                    continue
                offline = [(job, step) for job in jobs for step in job.get('steps', []) if step['name'] == STEPS[kind]]
                if not offline:
                    result.reason = '没有全部离线套件步骤，名单没取到'
                    continue
                red = set()
                for job, step in offline:
                    if step['status'] != 'completed' or step['conclusion'] not in ('success', 'failure'):
                        raise ValueError('offline suites did not finish')
                    log = get(f'repos/{repository}/actions/jobs/{job["id"]}/logs', raw=True)
                    red.update(parse_red(log, step['conclusion']))
                result.red, result.reason = red, ''
            except Exception as exc:
                result.reason = error_reason(exc) + '，套件名单没取到'
    return render(head, main or '没取到', results, policy=policy, gate=gate)

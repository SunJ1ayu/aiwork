"""Bounded, advisory CI context; never a gate or a prerequisite for dispatch."""
from __future__ import annotations

from dataclasses import dataclass
import json
import re
import time
from urllib.error import HTTPError

MAX_BYTES = 4096
WORKFLOWS = {
    '.github/workflows/ci.yml': ('Linux，关卡要求通过', 'Run the offline suite inside a real network namespace'),
    '.github/workflows/ci-macos.yml': ('Mac，只报不拦', 'All offline suites (report only for now)'),
}
NO_EGRESS_STEP = 'No-egress suite (must pass)'


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


def render(head: str, main: str, results: dict) -> str:
    lines = [
        '## CI 结果',
        f'当前 head：{head}；main 当前提交：{main}。',
        '可信度：状态和结论来自 GitHub 接口；套件名单从日志解析，日志由 PR 自己的代码打印，'
        '只能参考，不能证明测到了点子上。未列出日志原文。',
        '正式测试套件在评审环境触发断网守卫拒跑（78）是正常环境限制，不是 PR 的问题；'
        '要看测试结果请看本节，不必在腿自己的环境重跑正式套件。Mac CI 只报不拦；'
        '“本 PR 新变红”是否构成问题，由评审按 REVIEW-RULES 判断。',
    ]
    for path, (label, _step) in WORKFLOWS.items():
        current = results.get(('head', path), Result(reason='未查询'))
        baseline = results.get(('main', path), Result(reason='未查询'))
        lines.append(f'- {path.rsplit("/", 1)[1]}（{label}）：当前 head {current.state}；main {baseline.state}。')
    mac = '.github/workflows/ci-macos.yml'
    lines.append('Mac 断网判据：' + results.get(('head', mac), Result()).network
                 + '；main：' + results.get(('main', mac), Result()).network + '。')
    for path in WORKFLOWS:
        current = results.get(('head', path), Result(reason='未查询'))
        baseline = results.get(('main', path), Result(reason='未查询'))
        lines.append(path.rsplit('/', 1)[1] + ' 套件（仅日志参考）：')
        for label, result in (('当前 head', current), ('main', baseline)):
            names = json.dumps(sorted(result.red), ensure_ascii=False) if result.red is not None else '没取到'
            reason = ('（' + result.reason + '）') if result.reason else ''
            lines.append(f'- {label} 红套件：{names}{reason}')
        if current.red is None or baseline.red is None:
            lines.append('- 对比没取到：一侧还在跑、没有运行或套件名单没取到；不推断红绿变化。')
        else:
            for label, names in (
                ('本 PR 新变红', current.red - baseline.red),
                ('原本就红', current.red & baseline.red),
                ('本 PR 变绿', baseline.red - current.red),
            ):
                lines.append('- ' + label + '：' + json.dumps(sorted(names), ensure_ascii=False))
    text = '\n'.join(lines) + '\n'
    notice = '\n（CI 结果超过 4 KiB，已截断；未展示的名单和对比请勿推断。）\n'
    raw = text.encode('utf-8')
    if len(raw) > MAX_BYTES:
        text = raw[:MAX_BYTES - len(notice.encode('utf-8'))].decode('utf-8', 'ignore') + notice
    return text


def context(api, *, repository: str, head: str, main: str | None, branch: str) -> str:
    deadline = time.monotonic() + 45
    results = {}

    def get(endpoint, **kwargs):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('CI reference budget exhausted')
        return api(endpoint, timeout=min(10, remaining), **kwargs)

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

    for side, sha, event, ref in (('head', head, 'pull_request', branch), ('main', main, 'push', 'main')):
        try:
            if sha is None:
                raise ValueError('main SHA unavailable')
            runs = pages(f'repos/{repository}/actions/runs?head_sha={sha}&event={event}&per_page=100', 'workflow_runs')
        except Exception as exc:
            for path in WORKFLOWS:
                results[side, path] = Result(reason=error_reason(exc))
            continue
        for path, (_label, offline_step) in WORKFLOWS.items():
            result = Result()
            results[side, path] = result
            try:
                matches = [r for r in runs if r['head_sha'] == sha and r['event'] == event
                           and r['head_branch'] == ref and r['path'].split('@', 1)[0] == path]
                if not matches:
                    result.state, result.reason = '没有运行', 'GitHub 未返回该提交及分支的同一工作流运行'
                    result.network = '没有运行'
                    continue
                # A rerun keeps its id; run_started_at, not id, defines recency.
                run = max(matches, key=lambda r: (r['run_started_at'], r['id']))
                result.state = state(run)
                result.reason = result.state if result.state != '通过' else ''
                rid, attempt = run['id'], run['run_attempt']
                if type(rid) is not int or type(attempt) is not int or min(rid, attempt) < 1:
                    raise ValueError('invalid run identity')
                jobs = pages(f'repos/{repository}/actions/runs/{rid}/attempts/{attempt}/jobs?per_page=100', 'jobs')
                network = [state(step) for job in jobs for step in job.get('steps', []) if step['name'] == NO_EGRESS_STEP]
                if network:
                    result.network = next((v for v in network if v != '通过'), '通过')
                else:
                    result.network = '还在跑' if run['status'] != 'completed' else '没有运行'
                if run['status'] != 'completed':
                    continue
                offline = [(job, step) for job in jobs for step in job.get('steps', []) if step['name'] == offline_step]
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
                # Preserve a workflow state already read from GitHub even if logs fail.
                result.reason = error_reason(exc) + '，套件名单没取到'
    return render(head, main or '没取到', results)

#!/usr/bin/env python3
"""panel-slice core: manifest → plan → budget reservations → findings ledger → status.

Track sliced-panel-review (2026-09-13). The bash controller `panel-slice` owns
process launching (one pinned `panel-review --scoped-review` per work item);
this module owns every decision that must be reproducible from disk alone.

Invariants (each has an oracle in tests/test-panel-slice.sh):
  * plan.json is written before any leg starts; every attempt's reserved.json is
    written (O_EXCL, under the run lock) before its controller starts.
  * initial items get pairwise-distinct model families; the overall leg's family
    is not used by any slice; nothing silently duplicates a family.
  * extra sessions (retry + verify) are checked as a whole batch before anything
    is recorded; a refusal launches nothing and writes nothing.
  * findings.jsonl is append-only; status never lets a later PASS hide an
    earlier BLOCK; "unknown" is never reported as "failed".
  * refusals print `panel-slice: REFUSED <rule>: <why>` and exit 3.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _review_result import (  # noqa: E402
    SCOPED_REVIEW_CONTRACT_VERSION,
    ReviewResultError,
    eligibility_reasons,
    load_result,
)

PLAN_SCHEMA = "aiwork-panel-slice-plan/v1"
VERIFY_SCHEMA = "aiwork-panel-slice-verify/v1"
ITEM_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
FINDING_ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9._-]{0,31}$")
RESERVED_IDS = frozenset({"overall", "main", "probe", "verify", "items", "input"})
SEVERITIES = ("critical", "high", "medium", "low")
DECISIONS = ("confirmed", "rejected", "accepted-risk", "inconclusive")
CLOSED_DECISIONS = frozenset({"rejected", "accepted-risk"})
MAX_SLICES = 8
MAX_TEXT_BYTES = 64 * 1024
DEFAULT_EXTRA = 2
MAX_EXTRA = 10
MAX_CONCURRENCY = 16
DEFAULT_OVERALL_LEG = "subcodex"
UNACKNOWLEDGED_VERDICTS = ("BLOCK", "NEEDS_MORE_INFO")
COVERED_STATE = "done"


class Refused(Exception):
    def __init__(self, rule: str, message: str):
        super().__init__(message)
        self.rule = rule
        self.message = message


# ── small io helpers ──────────────────────────────────────────────────────
def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def dump_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


class RunLock:
    """Serialize every mutation of one run directory (reservations, ledger)."""

    def __init__(self, run_dir: Path):
        self.path = run_dir / ".lock"

    def __enter__(self) -> "RunLock":
        self.handle = open(self.path, "a+")
        fcntl.flock(self.handle, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc: Any) -> None:
        fcntl.flock(self.handle, fcntl.LOCK_UN)
        self.handle.close()


# ── legs table + health probe ─────────────────────────────────────────────
def load_legs_table(path: Path) -> tuple[dict[str, dict[str, str]], list[str], list[str]]:
    """Lines `pool|name|family|agent|chat|switch` or `role|...`, dumped from _panel-roster-lib.sh."""

    legs: dict[str, dict[str, str]] = {}
    pool: list[str] = []
    role: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        kind, name, family, agent, chat, switch = line.split("|")
        legs[name] = {"kind": kind, "family": family, "agent": agent, "chat": chat, "switch": switch}
        (pool if kind == "pool" else role).append(name)
    return legs, pool, role


def load_probe_health(path: Path) -> dict[str, str]:
    health: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) == 4 and parts[0] == "leg":
            health[parts[1]] = parts[3]
    return health


def rotated(names: list[str], start: int) -> list[str]:
    if not names:
        return []
    k = start % len(names)
    return names[k:] + names[:k]


# ── source fingerprint (read-only; never writes objects or the index) ─────
def git(repo: Path, *args: str) -> bytes:
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    proc = subprocess.run(["git", "-C", os.fspath(repo), *args], capture_output=True, env=env, check=False)
    if proc.returncode != 0:
        raise Refused("source", f"git {' '.join(args)} failed: {proc.stderr.decode(errors='replace').strip()}")
    return proc.stdout


def source_identity(repo: Path) -> dict[str, str]:
    head = git(repo, "rev-parse", "--verify", "HEAD").decode().strip()
    digest = hashlib.sha256()
    digest.update(b"aiwork-panel-slice-source-v1\0" + head.encode() + b"\0")
    digest.update(git(repo, "diff", "--cached", "--binary", "--no-ext-diff", "--no-textconv") + b"\0")
    digest.update(git(repo, "diff", "--binary", "--no-ext-diff", "--no-textconv") + b"\0")
    untracked = sorted(p for p in git(repo, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0") if p)
    for rel in untracked:
        path = repo / os.fsdecode(rel)
        digest.update(rel + b"\0")
        if path.is_symlink():
            digest.update(b"link\0" + os.fsencode(os.readlink(path)) + b"\0")
        elif path.is_file():
            digest.update(b"file\0" + hashlib.sha256(path.read_bytes()).digest() + b"\0")
        else:
            digest.update(b"other\0")
    return {"head": head, "fingerprint": "sha256:" + digest.hexdigest()}


# ── validation helpers ────────────────────────────────────────────────────
def exact_keys(value: Any, where: str, required: tuple[str, ...], optional: tuple[str, ...] = ()) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise Refused("manifest", f"{where} must be an object")
    missing = [key for key in required if key not in value]
    if missing:
        raise Refused("manifest", f"{where}.{missing[0]} is required")
    unknown = sorted(set(value) - set(required) - set(optional))
    if unknown:
        raise Refused("manifest", f"{where}.{unknown[0]} is not a known field")
    return value


def bounded_int(value: Any, where: str, low: int, high: int) -> int:
    if type(value) is not int or not low <= value <= high:
        raise Refused("manifest", f"{where} must be an integer in {low}..{high}, got {value!r}")
    return value


def text_field(value: Any, where: str, limit: int = 4000, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str) or (not allow_empty and not value.strip()) or len(value.encode()) > limit:
        raise Refused("manifest", f"{where} must be a non-empty string of at most {limit} bytes")
    return value


def read_brief(base: Path, value: Any, where: str) -> tuple[str, bytes]:
    if not isinstance(value, str) or not value:
        raise Refused("manifest", f"{where} must be a file path")
    path = Path(value)
    if not path.is_absolute():
        path = base / path
    if not path.is_file():
        raise Refused("manifest", f"{where}: file not found: {path}")
    data = path.read_bytes()
    if not data.strip() or len(data) > MAX_TEXT_BYTES:
        raise Refused("manifest", f"{where}: must be non-empty and at most {MAX_TEXT_BYTES} bytes: {path}")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise Refused("manifest", f"{where}: not UTF-8: {path}") from exc
    return os.fspath(path), data


def inside(child: str, parent: str) -> bool:
    return child == parent or child.startswith(parent.rstrip("/") + "/")


# ── task rendering ────────────────────────────────────────────────────────
COMMON_RULES = """- 只凭你亲自读到、跑到的证据下结论;没跑过的检查不许写成跑过。
- 不许再派子 agent / subagent,不许在 shell 里调用其他模型或 AI CLI,不许联网查资料。
- 不许修改源文件、push、merge、装依赖、碰生产系统、改密钥。
- 上下文不够就写清缺了什么,并给 `Conclusion: NEEDS_MORE_INFO`。"""

OUTPUT_RULES = """## 输出
- 每条发现:严重程度(critical/high/medium/low)、`file:line` 证据、触发条件、为什么是缺陷。
- 列出你**实际检查过**的关键路径(读了哪些文件、跑了什么)。
- 最后单独一行写结论,三选一:
  `Conclusion: PASS` / `Conclusion: BLOCK` / `Conclusion: NEEDS_MORE_INFO`"""


def render_slice_task(goal: str, slice_: dict[str, Any], brief: str, total: int) -> str:
    return f"""# 切片评审 · {slice_['title']}(slice: {slice_['id']})

## 你的角色
你是一次**切片评审**里的一名独立评审员。同一份改动被切成 {total} 片,每片由一个不同的模型家族审;
另有一名评审员独立审整体。你看不到其他人的报告,也不要去找。

- 你负责下面「本片范围」。为了查清调用方、数据流和测试,你可以读仓库里任何文件。
- 在本片范围之外发现的缺陷**照样报**,标 `OUT-OF-SLICE`;不许因为「不归我管」就不报。
{COMMON_RULES}

## 改动目标(所有评审员共用)
{goal.rstrip()}

## 本片范围
{brief.rstrip()}

{OUTPUT_RULES}
- 本片范围外的发现标 `OUT-OF-SLICE`。
"""


def render_overall_task(goal: str, extra: str | None, slices: list[dict[str, Any]], briefs: dict[str, str],
                        show_plan: bool) -> str:
    extra_block = f"\n## 补充说明\n{extra.rstrip()}\n" if extra else ""
    plan_block = ""
    if show_plan:
        rows = "\n\n".join(
            f"### {s['title']}(slice: {s['id']})\n{briefs[s['id']].rstrip()}" for s in slices
        )
        plan_block = f"""
## 切片清单(**做完你自己的端到端审查之后**再看,只用来查「没人负责的缺口」)
{rows}
"""
    return f"""# 切片评审 · 独立整体审查

## 你的角色
同一份改动被切成 {len(slices)} 片,分别由不同模型家族审。你**不看**任何切片报告,
从改动目标、完整改动和系统约束出发,**独立**审整体。你的价值是找到「各片单看都对、连起来是错的」。

必查:
- 需求有没有漏实现、做多了或做偏了;
- 各部分之间的输入输出、数据契约、共享状态接不接得上;
- 异常、超时、重试、清理、进程中途被杀时的整体行为;
- 兼容性:旧数据、旧调用方、旧配置;
- 有没有改动**不归任何一片负责**。
{COMMON_RULES}

## 改动目标
{goal.rstrip()}
{extra_block}
{OUTPUT_RULES}
{plan_block}"""


def source_label(source: str, items: dict[str, dict[str, Any]]) -> str:
    if source == "main":
        return "主 agent 自己的审查"
    item = items.get(source)
    if item is None:
        return source
    if item["role"] == "slice":
        return f"切片「{item['title']}」的评审"
    if item["role"] == "overall":
        return "独立整体审查"
    return "另一轮定点复核"


def render_verify_task(goal: str, check: dict[str, Any], findings: list[dict[str, Any]],
                       items: dict[str, dict[str, Any]]) -> str:
    blocks = []
    for f in findings:
        evidence = f"\n证据:{f['evidence']}" if f.get("evidence") else ""
        blocks.append(
            f"### {f['id']}(severity: {f['severity']};出处:{source_label(f['source'], items)})\n{f['claim']}{evidence}"
        )
    note = f"\n## 补充上下文\n{check['note'].rstrip()}\n" if check.get("note") else ""
    ids = ", ".join(f["id"] for f in findings)
    return f"""# 切片评审 · 定点复核(check: {check['id']})

## 你的角色
另一名评审员报了下面的问题。你来自**不同的模型家族**,任务是**尽力复现或反驳**,不是附和。
- 每条问题都要读相关代码;能跑就跑最小复现。判断触发条件、实际影响、是否本次改动引入。
- 每条单独一行给判定:`<问题 id>: CONFIRMED|REFUTED|INCONCLUSIVE — 理由`(本次:{ids})。
- 结论行:任一条 CONFIRMED ⇒ `Conclusion: BLOCK`;全部 REFUTED ⇒ `Conclusion: PASS`;
  其余 ⇒ `Conclusion: NEEDS_MORE_INFO`。
{COMMON_RULES}

## 改动目标
{goal.rstrip()}

## 待复核的问题
{chr(10).join(blocks)}
{note}
## 输出
- 逐条判定行 + 你读过/跑过的证据。
- 最后单独一行写结论(规则见上)。
"""


# ── run directory model ───────────────────────────────────────────────────
def load_plan(run_dir: Path) -> dict[str, Any]:
    path = run_dir / "plan.json"
    try:
        plan = read_json(path)
    except (OSError, json.JSONDecodeError) as exc:
        raise Refused("run-dir", f"not a panel-slice run (no readable plan.json): {run_dir}") from exc
    if plan.get("schema") != PLAN_SCHEMA:
        raise Refused("run-dir", f"unknown plan schema in {path}: {plan.get('schema')!r}")
    return plan


def load_rounds(run_dir: Path) -> list[dict[str, Any]]:
    rounds = []
    verify_dir = run_dir / "verify"
    if verify_dir.is_dir():
        for path in sorted(verify_dir.glob("round-*.json"), key=lambda p: int(p.stem.split("-")[1])):
            rounds.append(read_json(path))
    return rounds


def all_items(plan: dict[str, Any], rounds: list[dict[str, Any]]) -> list[dict[str, Any]]:
    items = [dict(item) for item in plan["items"]]
    for rnd in rounds:
        for check in rnd["checks"]:
            items.append({"id": check["id"], "role": "verify", "title": f"check {check['id']}",
                          "leg": check["leg"], "family": check["family"], "task": check["task"],
                          "task_sha256": check["task_sha256"], "findings": check["findings"],
                          "round": rnd["round"]})
    return items


def read_ledger(run_dir: Path) -> list[dict[str, Any]]:
    path = run_dir / "findings.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def append_ledger(run_dir: Path, events: list[dict[str, Any]]) -> None:
    if not events:
        return
    path = run_dir / "findings.jsonl"
    with open(path, "a", encoding="utf-8") as handle:
        for event in events:
            handle.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def attempt_dirs(run_dir: Path, item_id: str) -> list[tuple[int, Path]]:
    base = run_dir / "items" / item_id
    found = []
    if base.is_dir():
        for child in base.iterdir():
            match = re.fullmatch(r"attempt-([1-9][0-9]*)", child.name)
            if match and (child / "reserved.json").is_file():
                found.append((int(match.group(1)), child))
    return sorted(found)


def reservations(run_dir: Path) -> dict[str, int]:
    counts = {"initial": 0, "extra": 0}
    items_dir = run_dir / "items"
    if items_dir.is_dir():
        for path in items_dir.glob("*/attempt-*/reserved.json"):
            try:
                counts[read_json(path)["category"]] += 1
            except (OSError, KeyError, json.JSONDecodeError):
                counts["extra"] += 1  # unreadable reservation still spent a slot
    return counts


def plan_leg_selected(panel_plan: Path, leg: str) -> tuple[str | None, str | None]:
    try:
        for line in panel_plan.read_text(encoding="utf-8").splitlines():
            parts = line.split("\t")
            if len(parts) == 4 and parts[0] == "leg" and parts[1] == leg:
                return parts[2], parts[3]
    except OSError:
        pass
    return None, None


def classify_attempt(n: int, path: Path) -> dict[str, Any]:
    reserved = read_json(path / "reserved.json")
    leg = reserved["leg"]
    prefix = path / "panel"
    result_path = Path(f"{prefix}.{leg}.result.json")
    state_path = Path(f"{prefix}.{leg}.state")
    panel_plan = Path(f"{prefix}.plan")
    exit_path = path / "controller.exit"
    info: dict[str, Any] = {"n": n, "leg": leg, "family": reserved["family"],
                            "category": reserved["category"], "verdict": None, "state": "unknown",
                            "detail": None, "source": None}
    if result_path.is_file():
        try:
            result = load_result(result_path)
        except (ReviewResultError, OSError) as exc:
            info.update(state="result_invalid", detail=str(exc)[:200])
            return info
        info["verdict"] = result["verdict"]
        info["source"] = result["subject"]["source"]
        process = result["process"]
        reasons = eligibility_reasons(result)
        other = [reason for reason in reasons if reason != "review_contract_unsupported"]
        if result["review_contract_version"] != SCOPED_REVIEW_CONTRACT_VERSION:
            info.update(state="contract_violation", detail=f"review_contract_version={result['review_contract_version']}")
        elif process["state"] != "exited" or process["exit_code"] != 0:
            info.update(state="failed", detail=result["failure_kind"])
        elif result["degraded"]:
            info.update(state="degraded")
        elif result["verdict"] == "NEEDS_MORE_INFO":
            info.update(state="needs_more_info")
        elif result["verdict"] == "UNKNOWN":
            info.update(state="no_verdict")
        elif other:
            info.update(state="ineligible", detail=",".join(other))
        else:
            info.update(state=COVERED_STATE)
        return info
    if state_path.is_file():
        info.update(state="result_missing", detail=state_path.read_text(encoding="utf-8").split("\n", 1)[0])
        return info
    if panel_plan.is_file():
        selected, health = plan_leg_selected(panel_plan, leg)
        if selected == "0":
            info.update(state="not_dispatched", detail=f"health:{health}")
        elif exit_path.is_file():
            info.update(state="lost", detail="controller exited without a leg terminal state")
        return info
    if exit_path.is_file():
        info.update(state="launch_failed", detail=f"controller rc={exit_path.read_text().strip()}")
    return info


def build_status(run_dir: Path) -> dict[str, Any]:
    plan = load_plan(run_dir)
    rounds = load_rounds(run_dir)
    items = all_items(plan, rounds)
    ledger = read_ledger(run_dir)
    finding_events = [e for e in ledger if e["event"] == "finding"]
    decisions: dict[str, list[str]] = {}
    for event in ledger:
        if event["event"] == "decision":
            decisions.setdefault(event["finding"], []).append(event["status"])
    checks_by_finding: dict[str, list[str]] = {}
    for event in ledger:
        if event["event"] == "check":
            for fid in event["findings"]:
                checks_by_finding.setdefault(fid, []).append(event["id"])
    acknowledged_sources = {e["source"] for e in finding_events}

    out_items = []
    incomplete: list[str] = []
    attention: list[str] = []
    sources: set[str] = set()
    unacknowledged = []
    for item in items:
        attempts = [classify_attempt(n, path) for n, path in attempt_dirs(run_dir, item["id"])]
        covered = any(a["state"] == COVERED_STATE for a in attempts)
        for a in attempts:
            if a["state"] == COVERED_STATE and a["source"] is not None:
                sources.add(json.dumps(a["source"], sort_keys=True))
            if a["state"] == "unknown":
                incomplete.append(f"{item['id']}#{a['n']} unknown(没有终态:被砍或仍在跑)")
            if a["state"] == "contract_violation":
                incomplete.append(f"{item['id']}#{a['n']} contract_violation({a['detail']})")
            if (item["role"] != "verify" and a["verdict"] in UNACKNOWLEDGED_VERDICTS
                    and item["id"] not in acknowledged_sources):
                unacknowledged.append({"item": item["id"], "attempt": a["n"], "verdict": a["verdict"]})
        if not covered:
            if item["role"] == "verify":
                attention.append(f"check {item['id']} 没有完成的复核")
            else:
                incomplete.append(f"{item['id']} 没有 done 的尝试")
        out_items.append({
            "id": item["id"], "role": item["role"], "title": item["title"], "covered": covered,
            "attempts": [{k: a[k] for k in ("n", "leg", "family", "category", "state", "verdict", "detail")}
                         for a in attempts],
            **({"findings": item["findings"]} if item["role"] == "verify" else {}),
        })
    source_mismatch = len(sources) > 1
    if source_mismatch:
        incomplete.append("done 的尝试之间源码快照不一致(评审期间仓库变过)")

    findings = []
    for event in finding_events:
        history = decisions.get(event["id"], [])
        latest = history[-1] if history else None
        status = "closed" if latest in CLOSED_DECISIONS else "open"
        if status == "open":
            attention.append(f"finding {event['id']} 未处置({latest or '无决定'})")
        findings.append({"id": event["id"], "source": event["source"], "severity": event["severity"],
                         "status": status, "decision": latest, "decision_history": history,
                         "checks": checks_by_finding.get(event["id"], [])})
    for entry in unacknowledged:
        attention.append(f"{entry['item']}#{entry['attempt']} 给了 {entry['verdict']},没有登记成 finding")

    counts = reservations(run_dir)
    state = "incomplete" if incomplete else ("attention" if attention else "clean")
    return {
        "schema": "aiwork-panel-slice-status/v1",
        "run_id": plan["run_id"],
        "run_state": state,
        "budget": {"initial_sessions": plan["budget"]["initial_sessions"],
                   "extra_sessions": plan["budget"]["extra_sessions"],
                   "max_concurrency": plan["budget"]["max_concurrency"],
                   "initial_used": counts["initial"], "extra_used": counts["extra"]},
        "items": out_items,
        "unacknowledged": unacknowledged,
        "findings": findings,
        "source_mismatch": source_mismatch,
        "problems": {"incomplete": incomplete, "attention": attention},
    }


def render_status_md(status: dict[str, Any], run_dir: Path) -> str:
    lines = [
        f"# panel-slice 状态 · {status['run_id']}",
        "",
        f"- run_state: **{status['run_state']}** —— 事实汇总,**不是裁决**(not a verdict);主 agent 仍须亲读每份报告再仲裁。",
        f"- 预算:初始 {status['budget']['initial_used']}/{status['budget']['initial_sessions']},"
        f" extra {status['budget']['extra_used']}/{status['budget']['extra_sessions']}(retry 与 verify 共用)",
        f"- run 目录:{run_dir}",
        "- 切片结果契约版本=2:**永不计入**任何 track 的归档覆盖。",
        "",
        "| 项 | 角色 | 尝试 | 腿/家族 | 状态 | 裁决 |",
        "|---|---|---|---|---|---|",
    ]
    for item in status["items"]:
        if not item["attempts"]:
            lines.append(f"| {item['id']} | {item['role']} | - | - | 未派发 | - |")
        for a in item["attempts"]:
            detail = f"({a['detail']})" if a["detail"] else ""
            lines.append(f"| {item['id']} | {item['role']} | #{a['n']} {a['category']} | {a['leg']}/{a['family']}"
                         f" | {a['state']}{detail} | {a['verdict'] or '-'} |")
    lines += ["", "## 报告位置", ""]
    for item in status["items"]:
        for a in item["attempts"]:
            lines.append(f"- {item['id']}#{a['n']}: items/{item['id']}/attempt-{a['n']}/panel.{a['leg']}.log")
    if status["findings"]:
        lines += ["", "## Findings(只追加的问题账 findings.jsonl)", ""]
        for f in status["findings"]:
            lines.append(f"- {f['id']} [{f['severity']}] 出处 {f['source']} → {f['status']}"
                         f"(决定历史:{' → '.join(f['decision_history']) or '无'};复核:{', '.join(f['checks']) or '无'})")
    for title, key in (("未收齐(incomplete)", "incomplete"), ("要处理(attention)", "attention")):
        if status["problems"][key]:
            lines += ["", f"## {title}", ""] + [f"- {p}" for p in status["problems"][key]]
    return "\n".join(lines) + "\n"


def write_status(run_dir: Path) -> dict[str, Any]:
    status = build_status(run_dir)
    atomic_write(run_dir / "status.md", render_status_md(status, run_dir))
    return status


# ── commands ──────────────────────────────────────────────────────────────
def launch_line(item: str, attempt: int, leg: str, family: str, task: Path, prefix: Path, category: str) -> str:
    return "\t".join(("launch", item, str(attempt), leg, family, os.fspath(task), os.fspath(prefix), category))


def check_my_review(my_review: str, repo: str) -> str | None:
    if not my_review:
        return None
    path = Path(my_review)
    if not path.is_file() or not path.read_bytes().strip():
        raise Refused("my-review", f"my-review file missing or empty: {my_review} "
                                   "(write your OWN review first, or pass --no-my-review consciously)")
    repo_real = os.path.realpath(repo)
    for candidate in (os.path.realpath(my_review), os.path.abspath(my_review)):
        if inside(candidate, repo_real):
            raise Refused("my-review", f"my-review file is inside the repo under review: {candidate}")
    return os.path.realpath(my_review)


def cmd_check(args: argparse.Namespace) -> None:
    """Pre-probe checks: nothing is created on refusal."""

    repo_real = os.path.realpath(args.repo)
    run_real = os.path.realpath(args.run_dir)
    if inside(run_real, repo_real) or inside(os.path.abspath(args.run_dir), repo_real):
        raise Refused("run-dir", f"run directory must live outside the repo under review: {run_real}")
    run_dir = Path(args.run_dir)
    if run_dir.exists() and (not run_dir.is_dir() or any(run_dir.iterdir())):
        raise Refused("run-dir", f"run directory already exists and is not empty (never overwrite evidence): {run_dir}")
    check_my_review(args.my_review, args.repo)
    parse_manifest(Path(args.manifest))


def parse_manifest(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
        manifest = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Refused("manifest", f"cannot read manifest JSON: {path}: {exc}") from exc
    exact_keys(manifest, "manifest", ("version", "goal", "slices"), ("overall", "budget"))
    if manifest["version"] != 1:
        raise Refused("manifest", f"manifest.version must be 1, got {manifest['version']!r}")
    base = path.parent
    goal_path, goal = read_brief(base, manifest["goal"], "manifest.goal")
    slices = manifest["slices"]
    if not isinstance(slices, list) or not 2 <= len(slices) <= MAX_SLICES:
        raise Refused("manifest", f"manifest.slices must list 2..{MAX_SLICES} slices "
                                  "(one slice is a normal panel-review)")
    parsed_slices = []
    seen: set[str] = set()
    for index, raw_slice in enumerate(slices):
        where = f"manifest.slices[{index}]"
        exact_keys(raw_slice, where, ("id", "title", "brief"), ("leg",))
        sid = raw_slice["id"]
        if not isinstance(sid, str) or not ITEM_ID_RE.fullmatch(sid) or sid in RESERVED_IDS:
            raise Refused("manifest", f"{where}.id must match {ITEM_ID_RE.pattern} and not be reserved: {sid!r}")
        if sid in seen:
            raise Refused("manifest", f"{where}.id duplicated: {sid}")
        seen.add(sid)
        title = text_field(raw_slice["title"], f"{where}.title", 200)
        brief_path, brief = read_brief(base, raw_slice["brief"], f"{where}.brief")
        leg = raw_slice.get("leg")
        if leg is not None and (not isinstance(leg, str) or not leg):
            raise Refused("manifest", f"{where}.leg must be a leg name")
        parsed_slices.append({"id": sid, "title": title, "brief_path": brief_path, "brief": brief, "leg": leg})
    overall = manifest.get("overall", {})
    exact_keys(overall, "manifest.overall", (), ("brief", "leg", "show_slice_plan"))
    overall_brief = None
    overall_brief_path = None
    if "brief" in overall:
        overall_brief_path, overall_brief = read_brief(base, overall["brief"], "manifest.overall.brief")
    overall_leg = overall.get("leg", DEFAULT_OVERALL_LEG)
    if not isinstance(overall_leg, str) or not overall_leg:
        raise Refused("manifest", "manifest.overall.leg must be a leg name or 'auto'")
    show_plan = overall.get("show_slice_plan", True)
    if type(show_plan) is not bool:
        raise Refused("manifest", "manifest.overall.show_slice_plan must be true or false")
    budget = manifest.get("budget", {})
    exact_keys(budget, "manifest.budget", (), ("extra_sessions", "max_concurrency"))
    extra = bounded_int(budget.get("extra_sessions", DEFAULT_EXTRA), "manifest.budget.extra_sessions", 0, MAX_EXTRA)
    initial = len(parsed_slices) + 1
    concurrency = bounded_int(budget.get("max_concurrency", initial), "manifest.budget.max_concurrency",
                              1, MAX_CONCURRENCY)
    return {"raw": raw, "goal_path": goal_path, "goal": goal, "slices": parsed_slices,
            "overall_leg": overall_leg, "overall_brief": overall_brief, "overall_brief_path": overall_brief_path,
            "show_slice_plan": show_plan, "extra": extra, "initial": initial, "concurrency": concurrency}


def healthy(legs: dict[str, dict[str, str]], health: dict[str, str], name: str) -> bool:
    return name in legs and health.get(name) == "healthy"


def describe_health(pool: list[str], role: list[str], legs: dict[str, dict[str, str]], health: dict[str, str]) -> str:
    return ", ".join(f"{name}({legs[name]['family']}:{health.get(name, 'unknown')})" for name in pool + role)


def assign(manifest: dict[str, Any], legs: dict[str, dict[str, str]], pool: list[str], role: list[str],
           health: dict[str, str], start: int) -> tuple[dict[str, str], str]:
    health_text = describe_health(pool, role, legs, health)
    used: dict[str, str] = {}  # family -> owner
    assignment: dict[str, str] = {}
    for s in manifest["slices"]:
        if s["leg"] is None:
            continue
        if s["leg"] not in legs:
            raise Refused("families", f"slice {s['id']} pins unknown leg {s['leg']!r}")
        if not healthy(legs, health, s["leg"]):
            raise Refused("families", f"slice {s['id']} pins {s['leg']} but it is {health.get(s['leg'], 'unknown')}; legs: {health_text}")
        family = legs[s["leg"]]["family"]
        if family in used:
            raise Refused("families", f"slice {s['id']} pins family {family} already used by {used[family]}")
        used[family] = s["id"]
        assignment[s["id"]] = s["leg"]
    overall_leg = manifest["overall_leg"]
    if overall_leg != "auto":
        if overall_leg not in legs:
            raise Refused("overall-leg", f"overall leg {overall_leg!r} is not a known leg")
        if not healthy(legs, health, overall_leg):
            raise Refused("overall-leg", f"overall leg {overall_leg} is {health.get(overall_leg, 'unknown')} "
                                         "(not silently replaced; set manifest.overall.leg explicitly or 'auto'); "
                                         f"legs: {health_text}")
        family = legs[overall_leg]["family"]
        if family in used:
            raise Refused("families", f"overall leg family {family} is already used by slice {used[family]}")
        used[family] = "overall"
    candidates = [name for name in rotated(pool, start) if healthy(legs, health, name)]
    for s in manifest["slices"]:
        if s["id"] in assignment:
            continue
        pick = next((name for name in candidates if legs[name]["family"] not in used), None)
        if pick is None:
            need = len(manifest["slices"])
            raise Refused("families", f"need {need} distinct healthy model families for slices"
                                      f"{' plus the overall leg' if overall_leg != 'auto' else ''}, "
                                      f"not enough; merge slices or pin legs. legs: {health_text}")
        used[legs[pick]["family"]] = s["id"]
        assignment[s["id"]] = pick
    if overall_leg == "auto":
        pick = next((name for name in candidates + [r for r in role if healthy(legs, health, r)]
                     if legs[name]["family"] not in used), None)
        if pick is None:
            raise Refused("families", f"no healthy leg left with an unused family for the overall review; legs: {health_text}")
        overall_leg = pick
    return assignment, overall_leg


def cmd_plan(args: argparse.Namespace) -> None:
    cmd_check(args)
    manifest = parse_manifest(Path(args.manifest))
    legs, pool, role = load_legs_table(Path(args.legs_table))
    health = load_probe_health(Path(args.probe_plan))
    assignment, overall_leg = assign(manifest, legs, pool, role, health, args.assign_start)
    source = source_identity(Path(args.repo))
    my_review = check_my_review(args.my_review, args.repo)

    run_dir = Path(args.run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "input" / "slices").mkdir(parents=True, exist_ok=True)
    atomic_write(run_dir / "manifest.json", manifest["raw"].decode("utf-8"))
    goal = manifest["goal"].decode("utf-8")
    atomic_write(run_dir / "input" / "goal.md", goal)
    briefs = {}
    for s in manifest["slices"]:
        briefs[s["id"]] = s["brief"].decode("utf-8")
        atomic_write(run_dir / "input" / "slices" / f"{s['id']}.md", briefs[s["id"]])
    overall_extra = manifest["overall_brief"].decode("utf-8") if manifest["overall_brief"] else None
    if overall_extra is not None:
        atomic_write(run_dir / "input" / "overall.md", overall_extra)

    items = []
    total = len(manifest["slices"])
    for s in manifest["slices"]:
        text = render_slice_task(goal, s, briefs[s["id"]], total)
        items.append({"id": s["id"], "role": "slice", "title": s["title"], "leg": assignment[s["id"]],
                      "family": legs[assignment[s["id"]]]["family"], "text": text})
    overall_text = render_overall_task(goal, overall_extra, manifest["slices"], briefs, manifest["show_slice_plan"])
    items.append({"id": "overall", "role": "overall", "title": "独立整体审查", "leg": overall_leg,
                  "family": legs[overall_leg]["family"], "text": overall_text})
    for item in items:
        task = run_dir / "items" / item["id"] / "task.md"
        atomic_write(task, item.pop("text"))
        item["task"] = f"items/{item['id']}/task.md"
        item["task_sha256"] = sha256_bytes(task.read_bytes())

    plan = {
        "schema": PLAN_SCHEMA,
        "run_id": args.run_id,
        "created_at": now_utc(),
        "manifest_sha256": sha256_bytes(manifest["raw"]),
        "repo": os.path.realpath(args.repo),
        "source": source,
        "my_review": my_review,
        "assign_start": args.assign_start,
        "budget": {"initial_sessions": manifest["initial"], "extra_sessions": manifest["extra"],
                   "max_concurrency": manifest["concurrency"]},
        "items": items,
    }
    atomic_write(run_dir / "plan.json", dump_json(plan))
    print(f"concurrency\t{manifest['concurrency']}")
    for item in items:
        print(launch_line(item["id"], 1, item["leg"], item["family"], run_dir / item["task"],
                          run_dir / "items" / item["id"] / "attempt-1" / "panel", "initial"))


def require_same_source(plan: dict[str, Any], repo: Path) -> None:
    current = source_identity(repo)
    if current != plan["source"]:
        raise Refused("source-changed", "the repo changed since this run was planned "
                                        f"(HEAD {plan['source']['head'][:12]} → {current['head'][:12]}, "
                                        "or worktree/index/untracked content differs); start a new run "
                                        "instead of stitching reviews of different code")


def item_families(run_dir: Path, item_id: str, items: dict[str, dict[str, Any]]) -> set[str]:
    families = {items[item_id]["family"]} if item_id in items else set()
    for _n, path in attempt_dirs(run_dir, item_id):
        try:
            families.add(read_json(path / "reserved.json")["family"])
        except (OSError, KeyError, json.JSONDecodeError):
            pass
    return families


def pick_leg(candidates: list[str], legs: dict[str, dict[str, str]], health: dict[str, str],
             excluded: set[str], preferred_unused: set[str]) -> str | None:
    usable = [n for n in candidates if healthy(legs, health, n) and legs[n]["family"] not in excluded]
    fresh = [n for n in usable if n not in preferred_unused]
    return (fresh or usable or [None])[0]


def cmd_verify(args: argparse.Namespace) -> None:
    run_dir = Path(args.run_dir)
    plan = load_plan(run_dir)
    rounds = load_rounds(run_dir)
    items_list = all_items(plan, rounds)
    items = {item["id"]: item for item in items_list}
    legs, pool, role = load_legs_table(Path(args.legs_table))
    health = load_probe_health(Path(args.probe_plan))
    try:
        manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Refused("manifest", f"cannot read verify manifest: {exc}") from exc
    exact_keys(manifest, "verify", ("version",), ("findings", "checks"))
    if manifest["version"] != 1:
        raise Refused("manifest", "verify.version must be 1")
    raw_findings = manifest.get("findings", [])
    raw_checks = manifest.get("checks", [])
    if not isinstance(raw_findings, list) or not isinstance(raw_checks, list):
        raise Refused("manifest", "verify.findings and verify.checks must be arrays")

    with RunLock(run_dir):
        ledger = read_ledger(run_dir)
        recorded = {e["id"]: e for e in ledger if e["event"] == "finding"}
        new_events: list[dict[str, Any]] = []
        manifest_findings: dict[str, dict[str, Any]] = {}
        for index, raw in enumerate(raw_findings):
            where = f"verify.findings[{index}]"
            exact_keys(raw, where, ("id", "source", "severity", "claim"), ("evidence",))
            fid = raw["id"]
            if not isinstance(fid, str) or not FINDING_ID_RE.fullmatch(fid):
                raise Refused("finding", f"{where}.id must match {FINDING_ID_RE.pattern}: {fid!r}")
            if fid in manifest_findings:
                raise Refused("finding", f"{where}.id duplicated in this manifest: {fid}")
            if raw["source"] != "main" and raw["source"] not in items:
                raise Refused("finding", f"{where}.source {raw['source']!r} is not an item of this run (or 'main')")
            if raw["severity"] not in SEVERITIES:
                raise Refused("finding", f"{where}.severity must be one of {', '.join(SEVERITIES)}")
            try:
                claim = text_field(raw["claim"], f"{where}.claim")
                evidence = text_field(raw["evidence"], f"{where}.evidence") if raw.get("evidence") is not None else None
            except Refused as exc:
                raise Refused("finding", exc.message) from exc
            event = {"event": "finding", "id": fid, "source": raw["source"], "severity": raw["severity"],
                     "claim": claim, "evidence": evidence}
            if fid in recorded:
                old = {k: recorded[fid].get(k) for k in ("id", "source", "severity", "claim", "evidence")}
                new = {k: event.get(k) for k in ("id", "source", "severity", "claim", "evidence")}
                if old != new:
                    raise Refused("finding", f"finding {fid} is already recorded with different content "
                                             "(the ledger is append-only; use a new id or `decide`)")
            else:
                new_events.append(dict(event, round=len(rounds) + 1, at=now_utc()))
            manifest_findings[fid] = event
        known = dict(recorded)
        known.update(manifest_findings)

        counts = reservations(run_dir)
        remaining = plan["budget"]["extra_sessions"] - counts["extra"]
        if len(raw_checks) > remaining:
            raise Refused("budget", f"{len(raw_checks)} checks need {len(raw_checks)} extra sessions but only "
                                    f"{remaining} of extra_sessions={plan['budget']['extra_sessions']} remain; "
                                    "nothing was recorded or launched")
        if raw_checks:
            require_same_source(plan, Path(plan["repo"]))

        checks = []
        used_this_round: set[str] = set()
        seen_ids = set(items)
        for index, raw in enumerate(raw_checks):
            where = f"verify.checks[{index}]"
            exact_keys(raw, where, ("id", "findings"), ("leg", "note"))
            cid = raw["id"]
            if not isinstance(cid, str) or not ITEM_ID_RE.fullmatch(cid) or cid in RESERVED_IDS or cid in seen_ids:
                raise Refused("manifest", f"{where}.id must be a new item id matching {ITEM_ID_RE.pattern}: {cid!r}")
            seen_ids.add(cid)
            fids = raw["findings"]
            if not isinstance(fids, list) or not fids or any(f not in known for f in fids):
                raise Refused("finding", f"{where}.findings must list recorded finding ids: {fids!r}")
            note = raw.get("note")
            if note is not None:
                text_field(note, f"{where}.note")
            excluded: set[str] = set()
            for fid in fids:
                src = known[fid]["source"]
                if src != "main":
                    excluded |= item_families(run_dir, src, items)
            if raw.get("leg") is not None:
                leg = raw["leg"]
                if leg not in legs:
                    raise Refused("family-exclusion", f"{where}.leg {leg!r} is not a known leg")
                if legs[leg]["family"] in excluded:
                    raise Refused("family-exclusion", f"{where}.leg {leg} is family {legs[leg]['family']}, "
                                                      f"the same family that raised {', '.join(fids)}; "
                                                      "a verifier must come from a different family")
                if not healthy(legs, health, leg):
                    raise Refused("family-exclusion", f"{where}.leg {leg} is {health.get(leg, 'unknown')}")
            else:
                leg = pick_leg(rotated(pool, args.assign_start) + role, legs, health, excluded, used_this_round)
                if leg is None:
                    raise Refused("family-exclusion", f"{where}: no healthy leg outside families {sorted(excluded)}; "
                                                      f"legs: {describe_health(pool, role, legs, health)}")
            used_this_round.add(leg)
            checks.append({"id": cid, "findings": fids, "leg": leg, "family": legs[leg]["family"], "note": note})

        goal = (run_dir / "input" / "goal.md").read_text(encoding="utf-8")
        round_no = len(rounds) + 1
        round_checks = []
        for check in checks:
            text = render_verify_task(goal, check, [known[f] for f in check["findings"]], items)
            task = run_dir / "items" / check["id"] / "task.md"
            atomic_write(task, text)
            round_checks.append({"id": check["id"], "findings": check["findings"], "leg": check["leg"],
                                 "family": check["family"], "task": f"items/{check['id']}/task.md",
                                 "task_sha256": sha256_bytes(task.read_bytes())})
            new_events.append({"event": "check", "id": check["id"], "findings": check["findings"],
                               "leg": check["leg"], "family": check["family"], "round": round_no, "at": now_utc()})
        if round_checks:
            atomic_write(run_dir / "verify" / f"round-{round_no}.json", dump_json({
                "schema": VERIFY_SCHEMA, "run_id": plan["run_id"], "round": round_no,
                "manifest_sha256": sha256_bytes(Path(args.manifest).read_bytes()), "checks": round_checks}))
        append_ledger(run_dir, new_events)
    print(f"concurrency\t{max(1, min(plan['budget']['max_concurrency'], len(round_checks) or 1))}")
    for check in round_checks:
        print(launch_line(check["id"], 1, check["leg"], check["family"], run_dir / check["task"],
                          run_dir / "items" / check["id"] / "attempt-1" / "panel", "extra"))


def cmd_retry(args: argparse.Namespace) -> None:
    run_dir = Path(args.run_dir)
    plan = load_plan(run_dir)
    rounds = load_rounds(run_dir)
    items_list = all_items(plan, rounds)
    items = {item["id"]: item for item in items_list}
    if args.item not in items:
        raise Refused("item", f"no item {args.item!r} in this run (items: {', '.join(items)})")
    item = items[args.item]
    legs, pool, role = load_legs_table(Path(args.legs_table))
    health = load_probe_health(Path(args.probe_plan))
    attempts = attempt_dirs(run_dir, args.item)
    if attempts:
        latest = classify_attempt(*attempts[-1])
        if latest["state"] == "unknown":
            raise Refused("unknown-attempt", f"{args.item}#{latest['n']} has no terminal state yet "
                                             "(it may still be running); retrying would spend a second session")
    counts = reservations(run_dir)
    if counts["extra"] + 1 > plan["budget"]["extra_sessions"]:
        raise Refused("budget", f"extra_sessions={plan['budget']['extra_sessions']} already used "
                                f"({counts['extra']}); retry refused")
    require_same_source(plan, Path(plan["repo"]))

    excluded: set[str] = set()
    if item["role"] == "verify":
        ledger = {e["id"]: e for e in read_ledger(run_dir) if e["event"] == "finding"}
        for fid in item["findings"]:
            src = ledger.get(fid, {}).get("source")
            if src and src != "main":
                excluded |= item_families(run_dir, src, items)
    else:
        for other in plan["items"]:
            if other["id"] == item["id"]:
                continue
            if item["role"] == "slice" or other["role"] == "slice":
                excluded |= item_families(run_dir, other["id"], items)
    current_leg = read_json(attempts[-1][1] / "reserved.json")["leg"] if attempts else item["leg"]
    if args.leg:
        leg = args.leg
        if leg not in legs or not healthy(legs, health, leg):
            raise Refused("families", f"retry leg {leg!r} is not a healthy known leg; "
                                      f"legs: {describe_health(pool, role, legs, health)}")
        if legs[leg]["family"] in excluded:
            raise Refused("families", f"retry leg {leg} family {legs[leg]['family']} collides with another item")
    elif healthy(legs, health, current_leg) and legs[current_leg]["family"] not in excluded:
        leg = current_leg
    else:
        leg = pick_leg(rotated(pool, args.assign_start) + role, legs, health, excluded, set())
        if leg is None:
            raise Refused("families", f"no healthy leg with an unused family for {args.item}; "
                                      f"legs: {describe_health(pool, role, legs, health)}")
    n = (attempts[-1][0] + 1) if attempts else 1
    category = "initial" if (n == 1 and item["role"] != "verify") else "extra"
    print("concurrency\t1")
    print(launch_line(item["id"], n, leg, legs[leg]["family"], run_dir / item["task"],
                      run_dir / "items" / item["id"] / f"attempt-{n}" / "panel", category))


def cmd_reserve(args: argparse.Namespace) -> None:
    run_dir = Path(args.run_dir)
    plan = load_plan(run_dir)
    attempt_dir = run_dir / "items" / args.item / f"attempt-{args.attempt}"
    with RunLock(run_dir):
        counts = reservations(run_dir)
        limit = plan["budget"]["initial_sessions"] if args.category == "initial" else plan["budget"]["extra_sessions"]
        if counts[args.category] + 1 > limit:
            label = "initial_sessions" if args.category == "initial" else "extra_sessions"
            raise Refused("budget", f"{label}={limit} already used ({counts[args.category]}); not launching "
                                    f"{args.item}#{args.attempt}")
        attempt_dir.mkdir(parents=True, exist_ok=True)
        path = attempt_dir / "reserved.json"
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        except FileExistsError as exc:
            raise Refused("budget", f"{args.item}#{args.attempt} is already reserved") from exc
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(dump_json({"item": args.item, "attempt": args.attempt, "leg": args.leg,
                                    "family": args.family, "category": args.category,
                                    "run_id": plan["run_id"], "reserved_at": now_utc()}))
            handle.flush()
            os.fsync(handle.fileno())


def cmd_decide(args: argparse.Namespace) -> None:
    run_dir = Path(args.run_dir)
    load_plan(run_dir)
    if args.status not in DECISIONS:
        raise Refused("decision", f"status must be one of {', '.join(DECISIONS)}")
    if not args.reason or not args.reason.strip():
        raise Refused("reason", "a decision needs --reason (the ledger records why, not just what)")
    with RunLock(run_dir):
        recorded = {e["id"] for e in read_ledger(run_dir) if e["event"] == "finding"}
        if args.finding not in recorded:
            raise Refused("finding", f"finding {args.finding!r} was never recorded in this run")
        append_ledger(run_dir, [{"event": "decision", "finding": args.finding, "status": args.status,
                                 "reason": args.reason.strip(), "at": now_utc()}])


def cmd_status(args: argparse.Namespace) -> None:
    run_dir = Path(args.run_dir)
    status = write_status(run_dir)
    if args.json:
        sys.stdout.write(dump_json(status))
    else:
        sys.stdout.write(render_status_md(status, run_dir))


def cmd_run_rc(args: argparse.Namespace) -> None:
    """Exit 0 if the given attempts produced at least one rc=0 leg result, else 1."""

    run_dir = Path(args.run_dir)
    ok = False
    for spec in args.attempt:
        item, n = spec.rsplit("#", 1)
        path = run_dir / "items" / item / f"attempt-{n}"
        if (path / "reserved.json").is_file():
            info = classify_attempt(int(n), path)
            if info["state"] not in ("failed", "unknown", "launch_failed", "lost", "not_dispatched", "result_invalid",
                                     "result_missing"):
                ok = True
    raise SystemExit(0 if ok else 1)


def parser() -> argparse.ArgumentParser:
    top = argparse.ArgumentParser(prog="_panel_slice.py")
    sub = top.add_subparsers(dest="command", required=True)

    def run_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--run-dir", required=True)

    p = sub.add_parser("check"); run_common(p)
    p.add_argument("--manifest", required=True); p.add_argument("--repo", required=True)
    p.add_argument("--my-review", default="")
    p = sub.add_parser("plan"); run_common(p)
    p.add_argument("--manifest", required=True); p.add_argument("--repo", required=True)
    p.add_argument("--my-review", default=""); p.add_argument("--legs-table", required=True)
    p.add_argument("--probe-plan", required=True); p.add_argument("--assign-start", type=int, default=0)
    p.add_argument("--run-id", required=True)
    p = sub.add_parser("verify"); run_common(p)
    p.add_argument("--manifest", required=True); p.add_argument("--legs-table", required=True)
    p.add_argument("--probe-plan", required=True); p.add_argument("--assign-start", type=int, default=0)
    p = sub.add_parser("retry"); run_common(p)
    p.add_argument("--item", required=True); p.add_argument("--leg")
    p.add_argument("--legs-table", required=True); p.add_argument("--probe-plan", required=True)
    p.add_argument("--assign-start", type=int, default=0)
    p = sub.add_parser("reserve"); run_common(p)
    p.add_argument("--item", required=True); p.add_argument("--attempt", type=int, required=True)
    p.add_argument("--leg", required=True); p.add_argument("--family", required=True)
    p.add_argument("--category", choices=("initial", "extra"), required=True)
    p = sub.add_parser("decide"); run_common(p)
    p.add_argument("--finding", required=True); p.add_argument("--status", required=True)
    p.add_argument("--reason", default="")
    p = sub.add_parser("status"); run_common(p)
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("run-rc"); run_common(p)
    p.add_argument("--attempt", action="append", default=[])
    p = sub.add_parser("repo-of"); run_common(p)
    return top


def main() -> int:
    args = parser().parse_args()
    handlers = {"check": cmd_check, "plan": cmd_plan, "verify": cmd_verify, "retry": cmd_retry,
                "reserve": cmd_reserve, "decide": cmd_decide, "status": cmd_status, "run-rc": cmd_run_rc}
    try:
        if args.command == "repo-of":
            print(load_plan(Path(args.run_dir))["repo"])
            return 0
        handlers[args.command](args)
        return 0
    except Refused as exc:
        print(f"panel-slice: REFUSED {exc.rule}: {exc.message}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())

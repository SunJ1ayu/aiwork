#!/usr/bin/env python3
"""ReviewLegResult v2 contract and shared review-result semantics.

This module is both importable and executable.  Shell adapters may provide raw
facts, but they must not independently interpret verdicts or coverage.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sys
from typing import Any, Iterable
from urllib.parse import unquote, urlparse


SCHEMA_VERSION = 2
SUBJECT_MANIFEST_VERSION = 1
NORMALIZER_VERSION = 1
REVIEW_CONTRACT_VERSION = 1
# 契约 2 = scoped review(track sliced-panel-review):切片/整体/复核腿只对分派给它的那部分负责,
# 不是契约 1 的「整任务全量评审」。它**故意不在** SUPPORTED_REVIEW_CONTRACTS 里 ⇒ 旧覆盖谓词
# 一律 review_contract_unsupported。要让切片结果承担放行资格,得另立新策略,不是往这里加一个数。
SCOPED_REVIEW_CONTRACT_VERSION = 2
# Exploration emits terminal facts, but can never supply review coverage.
EXPLORE_CONTRACT_VERSION = 3
EMITTABLE_REVIEW_CONTRACTS = (REVIEW_CONTRACT_VERSION, SCOPED_REVIEW_CONTRACT_VERSION, EXPLORE_CONTRACT_VERSION)
SUPPORTED_REVIEW_CONTRACTS = frozenset({REVIEW_CONTRACT_VERSION})

VERDICTS = frozenset({"PASS", "BLOCK", "NEEDS_MORE_INFO", "UNKNOWN"})
PROCESS_STATES = frozenset({"exited", "timed_out", "signaled", "launch_error", "lost"})
DELIVERY_STATES = frozenset({"complete", "partial", "none"})
VIEW_MODES = frozenset({"full_snapshot", "diff_bundle"})
EVIDENCE_COMPLETENESS = frozenset({"complete", "partial", "none"})
FAILURE_KINDS = frozenset(
    {
        "none",
        "auth",
        "quota",
        "rate_limit",
        "timeout",
        "no_verdict",
        "runtime",
        "identity_mismatch",
        "snapshot",
        "unknown",
    }
)
BILLING_MODES = frozenset({"subscription", "api", "local"})

IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/+:-]*$")
SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
VERDICT_WORDS = {"通过": "PASS", "不通过": "BLOCK", "阻断": "BLOCK", "需要更多信息": "NEEDS_MORE_INFO"}
# 裁决值认中文(GLM 真评审两次整份作废:09-07 `结论：通过 (PASS)`、09-14 `结论：通过`),
# 但仍要求独占一行、值是完整一个词;括号里再写一遍英文时两者必须一致。
VERDICT_LINE_RE = re.compile(
    r"^[\t ]*[*_`]*[\t ]*(?:Conclusion|Verdict|结论)[\t ]*[：:][\t ]*"
    r"(PASS|BLOCK|NEEDS_MORE_INFO|NMI|通过|不通过|阻断|需要更多信息)"
    r"(?:[\t ]*[(（][\t ]*(PASS|BLOCK|NEEDS_MORE_INFO|NMI)[\t ]*[)）])?"
    r"[\t ]*[*_`]*[\t ]*$",
    re.IGNORECASE,
)
AUTH_FAILURE_RE = re.compile(r"unauthori[sz]ed|forbidden|invalid.{0,20}key|\bauth\b|\b401\b|\b403\b", re.I)
RATE_LIMIT_RE = re.compile(r"rate.?limit|too many requests|\b429\b", re.I)
QUOTA_FAILURE_RE = re.compile(r"quota|额度|balance|billing", re.I)
# 会自己恢复的窗口限额(Kimi 09-09 原话 "403 You've reached your 5-hour usage limit. Your quota will
# reset …")。它带着 403 和 quota 两个词,按旧顺序先被 auth 认走;真实含义是「等窗口过去」,归 rate_limit。
WINDOW_LIMIT_RE = re.compile(r"usage limit", re.I)
# 同一句里有付费/余额措辞就不算窗口:「402 payment required. Your quota will reset on the next billing
# cycle」要人充值,得留在 quota 继续计连败(外审第一轮 Kimi F2)。**不认 billing 这个词**:Kimi 真实的
# 「usage limit for this billing cycle」会在下个周期自愈,按 billing 否决就被 403 认成 auth(外审第二轮 DeepSeek F1)。
BILLING_FAILURE_RE = re.compile(r"payment|balance|\b402\b", re.I)

TOP_KEYS = (
    "schema_version",
    "review_contract_version",
    "run_id",
    "name",
    "family",
    "adapter",
    "process",
    "model",
    "subject",
    "view",
    "verdict",
    "degraded",
    "evidence",
    "normalizer_version",
    "duration_ms",
    "usage",
    "failure_kind",
)
FACT_KEYS = (
    "model",
    "source",
    "view",
    "process_state",
    "verdict",
    "evidence_completeness",
    "failure_kind",
    "billing_mode",
    "degraded",
)

ADAPTER_IDENTITIES = {
    "submimo": ("xiaomi", "xiaomi/"),
    "subdeepseek-agent": ("deepseek", "deepseek-"),
    "subdeepseek": ("deepseek", "deepseek-"),
    "subglm-agent": ("zhipu", "go/glm-"),
    "subglm": ("zhipu", "glm-"),
    "subkimi": ("moonshot", "kimi-code/"),
    "subgemini": ("google", "gemini-"),
    "subcodex": ("openai", "gpt-"),
    "subgrok": ("xai", "grok-"),
}


def cursor_model_family(model: str | None) -> str | None:
    """Cursor is a transport; coverage follows the explicitly selected model."""
    if not isinstance(model, str) or not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", model):
        return None
    for family, prefixes in (
        ("cursor", ("composer-",)),
        ("anthropic", ("claude-", "opus-", "sonnet-", "haiku-")),
        ("openai", ("gpt-", "codex-", "o1-", "o3-", "o4-")),
        ("google", ("gemini-",)),
        ("xai", ("grok-", "cursor-grok-")),
        ("moonshot", ("kimi-",)),
        ("deepseek", ("deepseek-",)),
        ("zhipu", ("glm-",)),
    ):
        if model.startswith(prefixes):
            return family
    return None


def leg_identity(adapter: str, model: str | None) -> tuple[str, str] | None:
    """(family, required model prefix) of one leg run; None when it cannot be attributed.

    A fixed adapter serves one family. Cursor serves whichever model was selected,
    so its family follows that model and the invoked model must be exactly it.
    """
    if adapter == "subcursor":
        family = cursor_model_family(model)
        return None if family is None else (family, model)
    return ADAPTER_IDENTITIES.get(adapter)


class ReviewResultError(ValueError):
    """A stable contract or integrity rule was violated."""

    def __init__(self, rule: str, path: str, actual: Any, expected: Any):
        super().__init__(f"rule={rule} path={path} actual={actual!r} expected={expected!r}")
        self.rule = rule
        self.path = path
        self.actual = actual
        self.expected = expected


def _exact_object(value: Any, path: str, keys: tuple[str, ...]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ReviewResultError("field.type", path, value, "object")
    missing = [key for key in keys if key not in value]
    if missing:
        raise ReviewResultError("field.required", f"{path}.{missing[0]}", None, "present")
    extra = sorted(set(value) - set(keys))
    if extra:
        raise ReviewResultError("field.unknown", f"{path}.{extra[0]}", value[extra[0]], "no unknown fields")
    return value


def _identifier(value: Any, path: str) -> str:
    if not isinstance(value, str) or not IDENTIFIER_RE.fullmatch(value):
        raise ReviewResultError("field.type", path, value, "safe identifier")
    return value


def _nullable_token(value: Any, path: str) -> str | None:
    if value is not None and (not isinstance(value, str) or not TOKEN_RE.fullmatch(value)):
        raise ReviewResultError("field.type", path, value, "null or safe token")
    return value


def _nullable_nonnegative_int(value: Any, path: str) -> int | None:
    if value is not None and (type(value) is not int or value < 0):
        raise ReviewResultError("field.type", path, value, "null or non-negative integer")
    return value


def _sha256(value: Any, path: str, *, nullable: bool = False) -> str | None:
    if value is None and nullable:
        return None
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        raise ReviewResultError("field.type", path, value, "sha256:<64 lowercase hex>")
    return value


def normalize_verdict(text: str) -> str:
    """Return the last standalone verdict line, or UNKNOWN."""

    found = "UNKNOWN"
    for line in text.splitlines():
        match = VERDICT_LINE_RE.fullmatch(line)
        if not match:
            continue
        value = _canonical_verdict(match.group(1))
        echo = match.group(2)
        if echo is not None and _canonical_verdict(echo) != value:
            continue
        found = value
    return found


def _canonical_verdict(word: str) -> str:
    value = VERDICT_WORDS.get(word, word.upper())
    return "NEEDS_MORE_INFO" if value == "NMI" else value


def sha256_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def evidence_ref(path: Path) -> str:
    return path.expanduser().resolve().as_uri()


def evidence_path(ref: str) -> Path:
    parsed = urlparse(ref)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost") or not parsed.path:
        raise ReviewResultError("evidence.ref", "evidence.ref", ref, "absolute file:// locator")
    path = Path(unquote(parsed.path))
    if not path.is_absolute():
        raise ReviewResultError("evidence.ref", "evidence.ref", ref, "absolute file:// locator")
    return path


def canonical_subject_bytes(subject: dict[str, Any]) -> bytes:
    manifest = {
        "manifest_version": subject["manifest_version"],
        "task_sha256": subject["task_sha256"],
        "source": subject["source"],
    }
    if subject["manifest_version"] == 2:
        manifest["delivery"] = subject["delivery"]
    return json.dumps(
        manifest,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
        allow_nan=False,
    ).encode("ascii")


def subject_digest(subject: dict[str, Any]) -> str:
    return sha256_bytes(b"aiwork-review-subject-v1\0" + canonical_subject_bytes(subject))


def _validate_source(value: Any, path: str) -> dict[str, Any] | None:
    if value is None:
        return None
    source = _exact_object(
        value,
        path,
        ("git_object_format", "head_oid", "index_tree_oid", "worktree_tree_oid"),
    )
    object_format = source["git_object_format"]
    if object_format not in ("sha1", "sha256"):
        raise ReviewResultError("field.enum", f"{path}.git_object_format", object_format, "sha1|sha256")
    oid_len = 40 if object_format == "sha1" else 64
    oid_re = re.compile(rf"^[0-9a-f]{{{oid_len}}}$")
    for key in ("head_oid", "index_tree_oid", "worktree_tree_oid"):
        if not isinstance(source[key], str) or not oid_re.fullmatch(source[key]):
            raise ReviewResultError("field.type", f"{path}.{key}", source[key], f"full lowercase {object_format} oid")
    return source


def validate_result(value: Any) -> dict[str, Any]:
    root = _exact_object(value, "result", TOP_KEYS)
    if root["schema_version"] != SCHEMA_VERSION:
        raise ReviewResultError("schema.version", "result.schema_version", root["schema_version"], SCHEMA_VERSION)
    contract = root["review_contract_version"]
    if type(contract) is not int or contract < 1:
        raise ReviewResultError("field.type", "result.review_contract_version", contract, "positive integer")
    for key in ("run_id", "name", "family"):
        _identifier(root[key], f"result.{key}")
    _identifier(root["adapter"], "result.adapter")

    process = _exact_object(root["process"], "result.process", ("state", "exit_code"))
    if process["state"] not in PROCESS_STATES:
        raise ReviewResultError("field.enum", "result.process.state", process["state"], sorted(PROCESS_STATES))
    exit_code = _nullable_nonnegative_int(process["exit_code"], "result.process.exit_code")
    if process["state"] == "exited" and exit_code is None:
        raise ReviewResultError("process.exit_code", "result.process.exit_code", exit_code, "integer when state=exited")

    model = _exact_object(root["model"], "result.model", ("requested", "invoked", "reported"))
    for key in ("requested", "invoked", "reported"):
        _nullable_token(model[key], f"result.model.{key}")

    subject_version = root["subject"].get("manifest_version") if isinstance(root["subject"], dict) else None
    subject = _exact_object(
        root["subject"],
        "result.subject",
        ("manifest_version", "task_sha256", "source", "digest") + (("delivery",) if subject_version == 2 else ()),
    )
    if type(subject["manifest_version"]) is not int or subject["manifest_version"] not in (1, 2):
        raise ReviewResultError(
            "subject.version",
            "result.subject.manifest_version",
            subject["manifest_version"],
            "1|2",
        )
    _sha256(subject["task_sha256"], "result.subject.task_sha256")
    source = _validate_source(subject["source"], "result.subject.source")
    if subject_version == 2:
        _validate_delivery(subject["delivery"], "result.subject.delivery")
        if source is None:
            raise ReviewResultError("subject.source", "result.subject.source", None, "source required for delivery binding")
    digest = _sha256(subject["digest"], "result.subject.digest", nullable=True)
    if source is None and digest is not None:
        raise ReviewResultError("subject.digest", "result.subject.digest", digest, "null when source is null")
    if source is not None and digest != subject_digest(subject):
        raise ReviewResultError("subject.digest", "result.subject.digest", digest, subject_digest(subject))

    view = _exact_object(root["view"], "result.view", ("delivery_state", "mode"))
    if view["delivery_state"] not in DELIVERY_STATES:
        raise ReviewResultError("field.enum", "result.view.delivery_state", view["delivery_state"], sorted(DELIVERY_STATES))
    if view["mode"] is not None and view["mode"] not in VIEW_MODES:
        raise ReviewResultError("field.enum", "result.view.mode", view["mode"], [None, *sorted(VIEW_MODES)])
    if view["delivery_state"] == "none" and view["mode"] is not None:
        raise ReviewResultError("view.mode", "result.view.mode", view["mode"], "null when delivery_state=none")

    if root["verdict"] not in VERDICTS:
        raise ReviewResultError("field.enum", "result.verdict", root["verdict"], sorted(VERDICTS))
    if type(root["degraded"]) is not bool:
        raise ReviewResultError("field.type", "result.degraded", root["degraded"], "boolean")

    evidence = _exact_object(root["evidence"], "result.evidence", ("completeness", "ref", "digest"))
    if evidence["completeness"] not in EVIDENCE_COMPLETENESS:
        raise ReviewResultError(
            "field.enum",
            "result.evidence.completeness",
            evidence["completeness"],
            sorted(EVIDENCE_COMPLETENESS),
        )
    ref = evidence["ref"]
    evidence_digest = _sha256(evidence["digest"], "result.evidence.digest", nullable=True)
    if evidence["completeness"] == "none":
        if ref is not None or evidence_digest is not None:
            raise ReviewResultError("evidence.none", "result.evidence", evidence, "null ref and digest")
    else:
        if not isinstance(ref, str):
            raise ReviewResultError("field.type", "result.evidence.ref", ref, "absolute file:// locator")
        evidence_path(ref)
        if evidence_digest is None:
            raise ReviewResultError("field.required", "result.evidence.digest", None, "sha256 when evidence exists")

    if root["normalizer_version"] != NORMALIZER_VERSION:
        raise ReviewResultError(
            "normalizer.version",
            "result.normalizer_version",
            root["normalizer_version"],
            NORMALIZER_VERSION,
        )
    _nullable_nonnegative_int(root["duration_ms"], "result.duration_ms")
    usage = _exact_object(
        root["usage"],
        "result.usage",
        ("input_tokens", "output_tokens", "total_tokens", "api_cost", "billing_mode"),
    )
    for key in ("input_tokens", "output_tokens", "total_tokens"):
        _nullable_nonnegative_int(usage[key], f"result.usage.{key}")
    cost = usage["api_cost"]
    if cost is not None and (type(cost) not in (int, float) or isinstance(cost, bool) or cost < 0):
        raise ReviewResultError("field.type", "result.usage.api_cost", cost, "null or non-negative number")
    if usage["billing_mode"] is not None and usage["billing_mode"] not in BILLING_MODES:
        raise ReviewResultError("field.enum", "result.usage.billing_mode", usage["billing_mode"], sorted(BILLING_MODES))
    if root["failure_kind"] not in FAILURE_KINDS:
        raise ReviewResultError("field.enum", "result.failure_kind", root["failure_kind"], sorted(FAILURE_KINDS))
    return root


def load_result(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ReviewResultError("result.read", os.fspath(path), str(exc), "readable UTF-8 ReviewLegResult JSON") from exc
    return validate_result(value)


def write_result_no_clobber(path: Path, value: dict[str, Any]) -> bool:
    """Atomically publish one terminal result; an existing result always wins."""

    result = validate_result(value)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp.{os.getpid()}.{secrets.token_hex(4)}")
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(result, handle, sort_keys=True, separators=(",", ":"), allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(tmp, path)
        except FileExistsError:
            load_result(path)
            return False
        return True
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


def _validate_delivery(value: Any, path: str) -> dict[str, Any]:
    delivery = _exact_object(value, path, ("policy_version", "track", "digest"))
    if type(delivery["policy_version"]) is not int or delivery["policy_version"] != 1:
        raise ReviewResultError("delivery.policy", path + ".policy_version", delivery["policy_version"], 1)
    _identifier(delivery["track"], path + ".track")
    _sha256(delivery["digest"], path + ".digest")
    return delivery


def _validate_facts(value: Any) -> dict[str, Any]:
    keys = FACT_KEYS + (("delivery",) if isinstance(value, dict) and "delivery" in value else ())
    facts = _exact_object(value, "facts", keys)
    if "delivery" in facts:
        _validate_delivery(facts["delivery"], "facts.delivery")
    model = _exact_object(facts["model"], "facts.model", ("requested", "invoked", "reported"))
    for key in ("requested", "invoked", "reported"):
        _nullable_token(model[key], f"facts.model.{key}")
    _validate_source(facts["source"], "facts.source")
    view = _exact_object(facts["view"], "facts.view", ("delivery_state", "mode"))
    if view["delivery_state"] not in DELIVERY_STATES:
        raise ReviewResultError("field.enum", "facts.view.delivery_state", view["delivery_state"], sorted(DELIVERY_STATES))
    if view["mode"] is not None and view["mode"] not in VIEW_MODES:
        raise ReviewResultError("field.enum", "facts.view.mode", view["mode"], [None, *sorted(VIEW_MODES)])
    if view["delivery_state"] == "none" and view["mode"] is not None:
        raise ReviewResultError("view.mode", "facts.view.mode", view["mode"], "null when delivery_state=none")
    if facts["process_state"] is not None and facts["process_state"] not in PROCESS_STATES:
        raise ReviewResultError("field.enum", "facts.process_state", facts["process_state"], sorted(PROCESS_STATES))
    if facts["verdict"] is not None and facts["verdict"] not in VERDICTS:
        raise ReviewResultError("field.enum", "facts.verdict", facts["verdict"], sorted(VERDICTS))
    if facts["evidence_completeness"] is not None and facts["evidence_completeness"] not in EVIDENCE_COMPLETENESS:
        raise ReviewResultError(
            "field.enum", "facts.evidence_completeness", facts["evidence_completeness"], sorted(EVIDENCE_COMPLETENESS)
        )
    if facts["failure_kind"] is not None and facts["failure_kind"] not in FAILURE_KINDS:
        raise ReviewResultError("field.enum", "facts.failure_kind", facts["failure_kind"], sorted(FAILURE_KINDS))
    if facts["billing_mode"] is not None and facts["billing_mode"] not in BILLING_MODES:
        raise ReviewResultError("field.enum", "facts.billing_mode", facts["billing_mode"], sorted(BILLING_MODES))
    if facts["degraded"] is not None and not isinstance(facts["degraded"], bool):
        raise ReviewResultError("field.type", "facts.degraded", facts["degraded"], "boolean or null")
    return facts


def write_facts(path: Path, value: dict[str, Any]) -> None:
    facts = _validate_facts(value)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp.{os.getpid()}.{secrets.token_hex(4)}")
    try:
        with tmp.open("x", encoding="utf-8") as handle:
            json.dump(facts, handle, sort_keys=True, separators=(",", ":"), allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


def _facts_from_args(args: argparse.Namespace) -> dict[str, Any]:
    source_values = (args.git_object_format, args.head_oid, args.index_tree_oid, args.worktree_tree_oid)
    if any(value is not None for value in source_values) and not all(value is not None for value in source_values):
        raise ReviewResultError("subject.source", "facts.source", source_values, "all source fields or none")
    source = None
    if all(value is not None for value in source_values):
        source = {
            "git_object_format": args.git_object_format,
            "head_oid": args.head_oid,
            "index_tree_oid": args.index_tree_oid,
            "worktree_tree_oid": args.worktree_tree_oid,
        }
    view_mode = args.view_mode
    if args.view_delivery_state == "none":
        view_mode = None
    result = {
        "model": {
            "requested": args.requested_model,
            "invoked": args.invoked_model,
            "reported": args.reported_model,
        },
        "source": source,
        "view": {"delivery_state": args.view_delivery_state, "mode": view_mode},
        "process_state": args.process_state,
        "verdict": args.verdict,
        "evidence_completeness": args.evidence_completeness,
        "failure_kind": args.failure_kind,
        "billing_mode": args.billing_mode,
        "degraded": None if args.degraded is None else args.degraded == "true",
    }
    if args.delivery_track is not None or args.delivery_digest is not None:
        result["delivery"] = _validate_delivery({"policy_version": 1, "track": args.delivery_track,
                                                  "digest": args.delivery_digest}, "facts.delivery")
    return result


def _emit_result(args: argparse.Namespace) -> dict[str, Any]:
    facts = None
    if args.facts is not None:
        try:
            facts = _validate_facts(json.loads(args.facts.read_text(encoding="utf-8")))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            raise ReviewResultError("facts.read", os.fspath(args.facts), str(exc), "readable UTF-8 facts JSON") from exc
    source_values = (args.git_object_format, args.head_oid, args.index_tree_oid, args.worktree_tree_oid)
    if any(value is not None for value in source_values) and not all(value is not None for value in source_values):
        raise ReviewResultError("subject.source", "emit.source", source_values, "all source fields or none")
    source = None
    if all(value is not None for value in source_values):
        source = {
            "git_object_format": args.git_object_format,
            "head_oid": args.head_oid,
            "index_tree_oid": args.index_tree_oid,
            "worktree_tree_oid": args.worktree_tree_oid,
        }
    if facts is not None:
        source = facts["source"]
    subject = {
        "manifest_version": SUBJECT_MANIFEST_VERSION,
        "task_sha256": args.task_sha256,
        "source": source,
        "digest": None,
    }
    if facts is not None and "delivery" in facts:
        subject["manifest_version"] = 2
        subject["delivery"] = facts["delivery"]
    if source is not None:
        subject["digest"] = subject_digest(subject)

    evidence = {"completeness": "none", "ref": None, "digest": None}
    evidence_text = ""
    verdict = facts["verdict"] if facts is not None and facts["verdict"] is not None else args.verdict
    if args.log is not None and args.log.is_file() and args.log.stat().st_size:
        evidence_text = args.log.read_text(encoding="utf-8", errors="replace")
        facts_completeness = facts["evidence_completeness"] if facts is not None else None
        if facts_completeness is not None or args.evidence_completeness is not None:
            completeness = facts_completeness or args.evidence_completeness
        else:
            completeness = "complete" if args.process_state == "exited" and args.exit_code == 0 else "partial"
        evidence = {
            "completeness": completeness,
            "ref": evidence_ref(args.log),
            "digest": sha256_file(args.log),
        }
        if verdict is None:
            verdict = normalize_verdict(evidence_text)
    if verdict is None:
        verdict = "UNKNOWN"

    diagnostic_text = ""
    if args.diagnostic is not None and args.diagnostic.is_file():
        diagnostic_text = args.diagnostic.read_text(encoding="utf-8", errors="replace")
    # 谁写的这行字,决定它算不算证据:`--diagnostic` 是**我们自己**的 stderr
    # (wrapper 与 provider CLI),`--log` 是**模型写的评审正文**。正文里出现
    # "auth" / "403" 通常只说明它在评审认证代码 —— 2026-08-28 这一单的最终
    # panel 就是这样把一条活着的 DeepSeek 腿记成"凭证坏了"(真因是没交裁决行)。
    # 所以先只读我们自己的诊断;只有我们一个字都没说时才回落到正文
    # (agent 底座会把 401 打在 stdout 上,那种真报警不能漏)。
    failure_text = diagnostic_text if diagnostic_text.strip() else evidence_text
    process_state = facts["process_state"] if facts is not None and facts["process_state"] is not None else args.process_state
    failure_kind = facts["failure_kind"] if facts is not None and facts["failure_kind"] is not None else args.failure_kind
    if failure_kind is None:
        if process_state == "timed_out":
            failure_kind = "timeout"
        elif process_state != "exited" or args.exit_code != 0:
            # 窗口限额只认**我们自己的诊断**里的原话:回落到模型正文时,正文里谈到 "usage limit"
            # (比如正在审这段代码)不许把一次崩溃变成「会自己恢复、不计连败」(外审第一轮 Kimi F1)。
            # rate_limit 在健康池里意味着「只冷却、不计连败」,所以它**只能**来自我们自己的诊断;
            # 正文回落时连原有的 `rate.?limit` 也不认(否则审到这段代码的腿一崩就被豁免)。
            diagnostic_backed = bool(diagnostic_text.strip())
            if (diagnostic_backed and WINDOW_LIMIT_RE.search(failure_text)
                    and not BILLING_FAILURE_RE.search(failure_text)):
                failure_kind = "rate_limit"
            elif AUTH_FAILURE_RE.search(failure_text):
                failure_kind = "auth"
            elif diagnostic_backed and RATE_LIMIT_RE.search(failure_text):
                failure_kind = "rate_limit"
            elif QUOTA_FAILURE_RE.search(failure_text):
                failure_kind = "quota"
            else:
                failure_kind = "runtime"
        elif verdict == "UNKNOWN" and args.review_contract_version != EXPLORE_CONTRACT_VERSION:
            failure_kind = "no_verdict"
        else:
            failure_kind = "none"
    view_delivery_state = facts["view"]["delivery_state"] if facts is not None else args.view_delivery_state
    view_mode = facts["view"]["mode"] if facts is not None else args.view_mode
    if view_delivery_state == "none":
        view_mode = None
    model = facts["model"] if facts is not None else {
        "requested": args.requested_model,
        "invoked": args.invoked_model,
        "reported": args.reported_model,
    }
    if getattr(args, "expected_model", None) is not None:
        model = dict(model, requested=args.expected_model)
        # A failure before invocation has no model facts; preserve its provider
        # cause so a temporary rate limit cannot become a permanent dead leg.
        if model["invoked"] is not None and model["invoked"] != args.expected_model:
            failure_kind = "identity_mismatch"
    billing_mode = facts["billing_mode"] if facts is not None else args.billing_mode
    return {
        "schema_version": SCHEMA_VERSION,
        "review_contract_version": args.review_contract_version,
        "run_id": args.run_id,
        "name": args.name,
        "family": args.family,
        "adapter": args.adapter,
        "process": {"state": process_state, "exit_code": args.exit_code},
        "model": model,
        "subject": subject,
        "view": {"delivery_state": view_delivery_state, "mode": view_mode},
        "verdict": verdict,
        "degraded": facts["degraded"] if facts is not None and facts["degraded"] is not None else args.degraded == "true",
        "evidence": evidence,
        "normalizer_version": NORMALIZER_VERSION,
        "duration_ms": args.duration_ms,
        "usage": {
            "input_tokens": None,
            "output_tokens": None,
            "total_tokens": None,
            "api_cost": None,
            "billing_mode": billing_mode,
        },
        "failure_kind": failure_kind,
    }


def eligibility_reasons(value: dict[str, Any], *, verify_evidence: bool = True) -> list[str]:
    result = validate_result(value)
    reasons: list[str] = []
    if result["review_contract_version"] not in SUPPORTED_REVIEW_CONTRACTS:
        reasons.append("review_contract_unsupported")
    if result["process"] != {"state": "exited", "exit_code": 0}:
        reasons.append("process_not_successful")
    if result["verdict"] not in ("PASS", "BLOCK"):
        reasons.append("verdict_not_decisive")
    if result["degraded"]:
        reasons.append("degraded")
    requested = result["model"]["requested"]
    invoked = result["model"]["invoked"]
    reported = result["model"]["reported"]
    identity = leg_identity(result["adapter"], requested)
    if identity is None or result["family"] != identity[0]:
        reasons.append("adapter_family_unknown")
    if requested is None or invoked is None or requested != invoked:
        reasons.append("model_invocation_unverified")
    elif identity is not None and not requested.startswith(identity[1]):
        reasons.append("model_family_mismatch")
    if reported is not None and invoked is not None and reported != invoked:
        reasons.append("model_report_mismatch")
    if result["subject"]["digest"] is None:
        reasons.append("subject_unknown")
    if result["view"] != {"delivery_state": "complete", "mode": "full_snapshot"}:
        reasons.append("view_incomplete")
    evidence = result["evidence"]
    if evidence["completeness"] != "complete" or evidence["ref"] is None or evidence["digest"] is None:
        reasons.append("evidence_incomplete")
    elif verify_evidence:
        path = evidence_path(evidence["ref"])
        try:
            current = sha256_file(path)
        except OSError:
            reasons.append("evidence_missing")
        else:
            if current != evidence["digest"]:
                reasons.append("evidence_digest_mismatch")
    return reasons


def coverage_eligible(value: dict[str, Any], *, verify_evidence: bool = True) -> bool:
    return not eligibility_reasons(value, verify_evidence=verify_evidence)


def summarize_results(
    values: Iterable[dict[str, Any]],
    *,
    run_id: str | None = None,
    subject: str | None = None,
    verify_evidence: bool = True,
) -> dict[str, Any]:
    validated = [validate_result(value) for value in values]
    if run_id is not None:
        validated = [value for value in validated if value["run_id"] == run_id]
    if subject is not None:
        validated = [value for value in validated if value["subject"]["digest"] == subject]
    eligible = [value for value in validated if coverage_eligible(value, verify_evidence=verify_evidence)]
    families = sorted({value["family"] for value in eligible})
    verdicts = sorted({value["verdict"] for value in eligible})
    contracts = sorted({value["review_contract_version"] for value in eligible})
    return {
        "eligible_count": len(eligible),
        "eligible_families": families,
        "eligible_family_count": len(families),
        "verdicts": verdicts,
        "conflict": "PASS" in verdicts and "BLOCK" in verdicts,
        "review_contract_versions": contracts,
    }


def _error(error: ReviewResultError) -> int:
    print(
        "review-result: "
        f"rule={error.rule} path={error.path} actual={error.actual!r} expected={error.expected!r}",
        file=sys.stderr,
    )
    return 1


def parser() -> argparse.ArgumentParser:
    top = argparse.ArgumentParser(prog="_review_result.py")
    commands = top.add_subparsers(dest="command", required=True)
    family = commands.add_parser("cursor-family", help="resolve a Cursor model's coverage family")
    family.add_argument("model")
    normalize = commands.add_parser("normalize", help="normalize a raw reviewer log")
    normalize.add_argument("log", type=Path)
    validate = commands.add_parser("validate", help="validate a ReviewLegResult v2 file")
    validate.add_argument("result", type=Path)
    eligible = commands.add_parser("eligible", help="test the shared coverage predicate")
    eligible.add_argument("result", type=Path)
    eligible.add_argument("--no-verify-evidence", action="store_true")
    describe = commands.add_parser("describe", help="print validated terminal fields as TSV")
    describe.add_argument("result", type=Path)
    describe.add_argument("--no-verify-evidence", action="store_true")
    emit = commands.add_parser("emit", help="atomically publish one ReviewLegResult v2")
    emit.add_argument("--result", type=Path, required=True)
    emit.add_argument("--facts", type=Path)
    emit.add_argument("--run-id", required=True)
    emit.add_argument("--name", required=True)
    emit.add_argument("--family", required=True)
    emit.add_argument("--adapter", required=True)
    emit.add_argument("--process-state", choices=sorted(PROCESS_STATES), default="exited")
    emit.add_argument("--exit-code", type=int, required=True)
    emit.add_argument("--task-sha256", required=True)
    emit.add_argument("--expected-model", help="controller-frozen choice; overrides adapter self-report of request")
    emit.add_argument("--requested-model")
    emit.add_argument("--invoked-model")
    emit.add_argument("--reported-model")
    emit.add_argument("--git-object-format")
    emit.add_argument("--head-oid")
    emit.add_argument("--index-tree-oid")
    emit.add_argument("--worktree-tree-oid")
    emit.add_argument("--view-delivery-state", choices=sorted(DELIVERY_STATES), default="none")
    emit.add_argument("--view-mode", choices=sorted(VIEW_MODES))
    emit.add_argument("--verdict", choices=sorted(VERDICTS))
    emit.add_argument("--degraded", choices=("true", "false"), default="false")
    emit.add_argument("--log", type=Path)
    emit.add_argument("--diagnostic", type=Path)
    emit.add_argument("--evidence-completeness", choices=sorted(EVIDENCE_COMPLETENESS))
    emit.add_argument("--duration-ms", type=int)
    emit.add_argument("--failure-kind", choices=sorted(FAILURE_KINDS))
    emit.add_argument("--billing-mode", choices=sorted(BILLING_MODES))
    emit.add_argument("--review-contract-version", type=int, choices=EMITTABLE_REVIEW_CONTRACTS,
                      default=REVIEW_CONTRACT_VERSION)
    facts = commands.add_parser("facts", help="atomically publish adapter facts for the terminal producer")
    facts.add_argument("--output", type=Path, required=True)
    facts.add_argument("--requested-model")
    facts.add_argument("--invoked-model")
    facts.add_argument("--reported-model")
    facts.add_argument("--git-object-format")
    facts.add_argument("--head-oid")
    facts.add_argument("--index-tree-oid")
    facts.add_argument("--worktree-tree-oid")
    facts.add_argument("--delivery-track")
    facts.add_argument("--delivery-digest")
    facts.add_argument("--view-delivery-state", choices=sorted(DELIVERY_STATES), default="none")
    facts.add_argument("--view-mode", choices=sorted(VIEW_MODES))
    facts.add_argument("--process-state", choices=sorted(PROCESS_STATES))
    facts.add_argument("--verdict", choices=sorted(VERDICTS))
    facts.add_argument("--evidence-completeness", choices=sorted(EVIDENCE_COMPLETENESS))
    facts.add_argument("--failure-kind", choices=sorted(FAILURE_KINDS))
    facts.add_argument("--billing-mode", choices=sorted(BILLING_MODES))
    facts.add_argument("--degraded", choices=("true", "false"))
    return top


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "cursor-family":
            family = cursor_model_family(args.model)
            if family is None:
                print("review-result: unknown/automatic Cursor model; select an explicit model ID", file=sys.stderr)
                return 1
            print(family)
            return 0
        if args.command == "normalize":
            print(normalize_verdict(args.log.read_text(encoding="utf-8", errors="replace")))
            return 0
        if args.command == "validate":
            load_result(args.result)
            return 0
        if args.command == "eligible":
            result = load_result(args.result)
            reasons = eligibility_reasons(result, verify_evidence=not args.no_verify_evidence)
            if reasons:
                print(json.dumps({"eligible": False, "reasons": reasons}, separators=(",", ":")))
                return 1
            print('{"eligible":true,"reasons":[]}')
            return 0
        if args.command == "describe":
            result = load_result(args.result)
            reasons = eligibility_reasons(result, verify_evidence=not args.no_verify_evidence)
            print("\t".join((
                result["process"]["state"], str(result["process"]["exit_code"]), result["verdict"],
                str(result["degraded"]).lower(), result["failure_kind"], str(not reasons).lower(),
            )))
            return 0
        if args.command == "emit":
            result = _emit_result(args)
            written = write_result_no_clobber(args.result, result)
            print(json.dumps({"path": os.fspath(args.result), "written": written}, separators=(",", ":")))
            return 0
        if args.command == "facts":
            write_facts(args.output, _facts_from_args(args))
            return 0
    except (OSError, ReviewResultError) as exc:
        if isinstance(exc, ReviewResultError):
            return _error(exc)
        return _error(ReviewResultError("io", "input", str(exc), "readable input"))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

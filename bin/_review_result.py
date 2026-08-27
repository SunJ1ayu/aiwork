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
import sys
from typing import Any, Iterable
from urllib.parse import unquote, urlparse


SCHEMA_VERSION = 2
SUBJECT_MANIFEST_VERSION = 1
NORMALIZER_VERSION = 1
REVIEW_CONTRACT_VERSION = 1
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
VERDICT_LINE_RE = re.compile(
    r"^[\t ]*[*_`]*[\t ]*(?:Conclusion|Verdict|结论)[\t ]*[：:][\t ]*"
    r"(PASS|BLOCK|NEEDS_MORE_INFO|NMI)[\t ]*[*_`]*[\t ]*$",
    re.IGNORECASE,
)

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

ADAPTER_IDENTITIES = {
    "submimo": ("xiaomi", "xiaomi/"),
    "subdeepseek-agent": ("deepseek", "deepseek-"),
    "subdeepseek": ("deepseek", "deepseek-"),
    "subglm-agent": ("zhipu", "glm-"),
    "subglm": ("zhipu", "glm-"),
    "subkimi": ("moonshot", "kimi-code/"),
    "subgemini": ("google", "gemini-"),
}


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
        found = match.group(1).upper()
        if found == "NMI":
            found = "NEEDS_MORE_INFO"
    return found


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

    subject = _exact_object(
        root["subject"],
        "result.subject",
        ("manifest_version", "task_sha256", "source", "digest"),
    )
    if subject["manifest_version"] != SUBJECT_MANIFEST_VERSION:
        raise ReviewResultError(
            "subject.version",
            "result.subject.manifest_version",
            subject["manifest_version"],
            SUBJECT_MANIFEST_VERSION,
        )
    _sha256(subject["task_sha256"], "result.subject.task_sha256")
    source = _validate_source(subject["source"], "result.subject.source")
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
    identity = ADAPTER_IDENTITIES.get(result["adapter"])
    requested = result["model"]["requested"]
    invoked = result["model"]["invoked"]
    reported = result["model"]["reported"]
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
    normalize = commands.add_parser("normalize", help="normalize a raw reviewer log")
    normalize.add_argument("log", type=Path)
    validate = commands.add_parser("validate", help="validate a ReviewLegResult v2 file")
    validate.add_argument("result", type=Path)
    eligible = commands.add_parser("eligible", help="test the shared coverage predicate")
    eligible.add_argument("result", type=Path)
    eligible.add_argument("--no-verify-evidence", action="store_true")
    return top


def main() -> int:
    args = parser().parse_args()
    try:
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
    except (OSError, ReviewResultError) as exc:
        if isinstance(exc, ReviewResultError):
            return _error(exc)
        return _error(ReviewResultError("io", "input", str(exc), "readable input"))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

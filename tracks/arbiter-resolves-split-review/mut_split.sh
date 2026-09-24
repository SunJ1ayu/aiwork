#!/usr/bin/env bash
# 变异自检:每个变异都必须让 tests/test-track-record.sh 红(rc≠0)。跑完还原。
set -u
cd "$(git rev-parse --show-toplevel)"
survived=0
mut() { # 名字 文件 原文 替换
  cp "$2" "$2.orig"
  if ! python3 - "$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  then echo "BROKEN   $1(原文找不到,变异没打上 —— 不许当成存活或被杀)"; survived=$((survived+1)); mv "$2.orig" "$2"; return; fi
  if timeout 600 bash tests/test-track-record.sh >/dev/null 2>&1; then echo "SURVIVED $1"; survived=$((survived+1))
  else echo "killed   $1"; fi
  mv "$2.orig" "$2"
}
R=bin/track-record
mut M1-resolved-never-counts $R 'if (not item["conflict"] or (item["run_id"], item["subject_digest"]) in resolved)' 'if (not item["conflict"])'
mut M2-no-quote-check $R 'if not quote or quote not in text:' 'if not quote:'
mut M3-quote-any-log $R '                text = review_evidence_path(leg["evidence"]["ref"]).read_bytes().decode("utf-8", "replace")' '                text = "".join(review_evidence_path(x["evidence"]["ref"]).read_bytes().decode("utf-8", "replace") for x in eligible.get(key, []))'
mut M4-legs-subset $R 'if sorted(names) != sorted(blocks):' 'if not set(names) <= set(blocks):'
mut M5-no-log-digest $R 'if entry["log_digest"] != leg["evidence"]["digest"]:' 'if False:'
mut M6-closeout-allowed $R 'if inner is not None and (inner in SPLIT_CLOSEOUT_RECORDS or inner.startswith("observations/")):' 'if False:'
mut M7-receipt-no-observation $R 'if receipt is not None and _is_runlog_receipt(blob) and receipt.group(1) not in runlog_runs:' 'if False:'
mut M8-no-line-bounds $R 'if not start <= end <= lines:' 'if False:'
mut M9-ignored-file-ok $R 'if (listed.returncode != 0 or rel.encode() not in listed.stdout.split(b"\0")
                or candidate.is_symlink() or not candidate.is_file()):' 'if (candidate.is_symlink() or not candidate.is_file()):'
mut M10-null-not-pop bin/_review_delivery.py 'outcome.pop("split_resolutions", None)' 'outcome["split_resolutions"] = None'
mut M11-no-exemption bin/_review_delivery.py 'outcome.pop("split_resolutions", None)' 'pass'
mut M12-ledger-ignores $R 'qualifying_review_groups(review_coverage, required_reviews, resolved_splits)' 'qualifying_review_groups(review_coverage, required_reviews)'
mut M13-any-group $R 'if key not in conflicting or key in resolved:' 'if key in resolved:'
mut M14-staged-symlink-ok $R 'startswith((b"100644 ", b"100755 "))' 'startswith((b"100644 ", b"100755 ", b"120000 "))'
mut M17-working-symlink-ok $R 'or candidate.is_symlink() or not candidate.is_file()):' 'or not candidate.is_file()):'
mut M15-empty-reason-ok $R 'if not rebuttal["reason"].strip():' 'if False:'
mut M16-disposition-free $R 'if rebuttal["disposition"] not in SPLIT_DISPOSITIONS:' 'if False:'
mut M18-no-archive-mapping $R 'if track_rel == f"tracks/archive/{track_dir.name}" and rel.startswith(active_prefix):' 'if False:'
mut M19-ledger-hides-bad-record $R 'if split_error is not None:
            missing.append(f"split_resolution:{split_error}")' 'if False:
            pass'
mut M20-authoritative-ignores-resolved $R 'if not item["conflict"] or (item["run_id"], item["subject_digest"]) in resolved_splits),' 'if not item["conflict"]),'
echo "survived=$survived"; exit $survived

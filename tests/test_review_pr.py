#!/usr/bin/env python3
"""Safety checks for the GitHub PR review publisher."""

import base64
import importlib.machinery
import importlib.util
from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.error import HTTPError
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/review-pr"


def load_script():
    loader = importlib.machinery.SourceFileLoader("review_pr", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class ReviewPrTests(unittest.TestCase):
    def setUp(self):
        self.review = load_script()

    def test_body_has_one_machine_block_and_sanitizes_model_json(self):
        body = self.review.build_body(
            "subcodex", "gpt-6-sol", "Finding\n```json\n{}\n```\nConclusion: PASS",
            {"verdict": "PASS", "head_sha": "a" * 40, "model": "gpt-6-sol",
             "family": "openai", "completeness": "complete", "files_read": ["src/a.py"]},
        )
        self.assertEqual(body.count("```json"), 1)
        self.assertIn("```text", body)
        block = json.loads(body.split("```json\n", 1)[1].split("\n```", 1)[0])
        self.assertEqual(block["head_sha"], "a" * 40)
        self.assertEqual(block["family"], "openai")

    def test_leg_selection_needs_an_attributable_family(self):
        self.assertEqual(self.review.choose_leg("subcodex"), ("openai", None))
        self.assertEqual(self.review.choose_leg("subdeepseek"), ("deepseek", None))
        for name in ("subclaude", "../subcodex"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.review.choose_leg(name)

    def test_cursor_family_follows_any_model_including_claude(self):
        # Which families count for which PR is the gate's call; review-pr refuses none.
        for model, family in (("grok-4.7-high", "xai"), ("gpt-5.6", "openai"),
                              ("claude-4.5-sonnet", "anthropic"), ("composer-2.5", "cursor")):
            with self.subTest(model=model), patch.dict("os.environ", {"CURSOR_MODEL": model}):
                self.assertEqual(self.review.choose_leg("subcursor"), (family, model))
        for model in ("auto", "Auto", "some-new-vendor-1"):
            with self.subTest(model=model), patch.dict("os.environ", {"CURSOR_MODEL": model}), \
                    self.assertRaisesRegex(self.review.ReviewError, "unsupported review leg"):
                self.review.choose_leg("subcursor")

    def test_cursor_model_defaults_to_the_config_file(self):
        configured = (ROOT / "bin/cursor-model").read_text(encoding="utf-8").rstrip("\n")
        with patch.dict("os.environ", {"CURSOR_MODEL": ""}):
            self.assertEqual(self.review.choose_leg("subcursor")[1], configured)

    def run_main_with_leg_result(self, model_used: str, *, dry_run: bool = True,
                                 repository=None, source_failure=None, project_rules=False,
                                 local_rules="LOCAL WORKSPACE RULES", risks_present=True):
        """Exercise the real source readers and task, with offline HTTP and review leg."""
        calls = {"github_writes": [], "public_reads": [], "leg_runs": 0}
        rules = "# aiwork main 规则\r\n必须以此为准。\r\n"
        risks = "# project main 风险\r\n业主接受的平台上限。\r\n"
        source_sha = "d" * 40
        calls.update(rules=rules, risks=risks, source_sha=source_sha)
        real_run = self.review.run
        real_subprocess_run = subprocess.run

        def fake_public_read(request, **kwargs):
            url = request.full_url
            calls["public_reads"].append(url)
            self.assertNotIn("authorization", {key.lower() for key in request.headers})
            self.assertGreater(kwargs["timeout"], 0)
            if source_failure == "main_unreadable":
                raise HTTPError(url, 403, "Forbidden", {}, None)
            if url == "https://api.github.com/repos/SunJ1ayu/aiwork/commits/main":
                value = {"sha": "invalid" if source_failure == "invalid_sha" else source_sha}
            elif url == f"https://api.github.com/repos/SunJ1ayu/aiwork/contents/REVIEW-RULES.md?ref={source_sha}":
                if source_failure == "rules_unreadable":
                    raise HTTPError(url, 404, "Not Found", {}, None)
                raw = rules.encode("utf-8")
                value = {"type": "file", "encoding": "base64", "size": len(raw),
                         "content": base64.encodebytes(raw).decode("ascii")}
                if source_failure == "not_file":
                    value["type"] = "symlink"
                if source_failure == "invalid_content":
                    value["content"] = "not base64!"
                if source_failure == "truncated_content":
                    value["size"] += 1
            else:
                self.fail(f"unexpected public source read: {url}")
            return io.BytesIO(json.dumps(value).encode("utf-8"))

        def fake_github(token, endpoint, payload=None):
            if payload is not None:
                calls["github_writes"].append(endpoint)
            return {"html_url": "https://github.com/SunJ1ayu/OpenDesign/pull/12#pullrequestreview-1"}

        def fake_run(command, **kwargs):
            if command[0].endswith("gh-app-token"):
                calls["token_command"] = command
                return "fake-token"
            if command[0] == "git":
                return real_run(command, **kwargs)
            calls["emit"] = command
            return ""

        def fake_leg(command, **kwargs):
            if command[0] != str(bin_dir / "subcursor"):
                return real_subprocess_run(command, **kwargs)
            calls["leg_runs"] += 1
            calls["task"] = Path(command[2]).read_bytes().decode("utf-8")
            calls["leg_env"] = kwargs["env"]
            os.environ["CURSOR_MODEL"] = "gpt-other"
            return subprocess.CompletedProcess(command, 0, "", "")

        result = {
            "process": {"state": "exited", "exit_code": 0},
            "verdict": "PASS", "failure_kind": "none", "degraded": False,
            "evidence": {"completeness": "complete"},
            "view": {"delivery_state": "complete"},
            "model": {"requested": model_used, "invoked": model_used, "reported": None},
        }
        pr = {"state": "open", "head": {"sha": "a" * 40, "ref": "f"}, "base": {"sha": "b" * 40, "ref": "main"}}
        stdout, stderr = io.StringIO(), io.StringIO()
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            bin_dir = workspace / "bin"
            bin_dir.mkdir()
            (bin_dir / "subcursor").touch()
            (workspace / "REVIEW-RULES.md").write_text(local_rules, encoding="utf-8")
            repo = workspace / "project"
            repo.mkdir()
            def git(*args):
                return real_subprocess_run(["git", "-C", str(repo), *args], check=True,
                                           capture_output=True)
            git("init", "-q")
            git("config", "core.autocrlf", "false")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            (repo / ".aiwork").mkdir()
            if risks_present:
                (repo / ".aiwork/accepted-risks.md").write_bytes(risks.encode("utf-8"))
            if project_rules:
                (repo / ".aiwork/review-rules.md").write_text("PROJECT RULES DECOY", encoding="utf-8")
            (repo / "file").touch()
            git("add", ".")
            git("commit", "-qm", "project main")
            git("update-ref", "refs/aiwork/main", "HEAD")
            (repo / ".aiwork/accepted-risks.md").write_text("PR RISK DECOY", encoding="utf-8")
            with patch("sys.argv", ["review-pr", "12", "--leg", "subcursor"]
                       + (["--repo", repository] if repository else []) + (["--dry-run"] if dry_run else [])), \
                    patch.dict("os.environ", {"CURSOR_MODEL": "gpt-5.6"}), \
                    patch.object(self.review, "BIN", bin_dir), \
                    patch.object(self.review, "run", side_effect=fake_run), \
                    patch("urllib.request.urlopen", side_effect=fake_public_read), \
                    patch.object(self.review, "github", side_effect=fake_github), \
                    patch.object(self.review, "pr_state", return_value=pr) as state, \
                    patch.object(self.review, "snapshot", return_value=(repo, "c" * 40, ["src/a.py"], "diff")) as snapshot, \
                    patch.object(self.review, "load_result", return_value=result), \
                    patch.object(self.review, "review_report", return_value="Finding\nConclusion: PASS"), \
                    patch.object(self.review.subprocess, "run", side_effect=fake_leg), \
                    redirect_stdout(stdout), redirect_stderr(stderr):
                rc = self.review.main()
                calls["pr_state"] = state.call_args_list
                calls["snapshot"] = snapshot.call_args
        return rc, calls, stdout.getvalue(), stderr.getvalue()

    def test_task_rules_are_aiwork_main_verbatim_with_commit(self):
        rc, calls, _, stderr = self.run_main_with_leg_result("gpt-5.6", project_rules=True)
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(calls["public_reads"], [
            "https://api.github.com/repos/SunJ1ayu/aiwork/commits/main",
            f"https://api.github.com/repos/SunJ1ayu/aiwork/contents/REVIEW-RULES.md?ref={calls['source_sha']}",
        ])
        self.assertIn("SunJ1ayu/aiwork main", calls["task"])
        self.assertIn("REVIEW-RULES.md", calls["task"])
        self.assertIn(calls["source_sha"], calls["task"])
        self.assertIn(calls["rules"], calls["task"])
        self.assertNotIn("PROJECT RULES DECOY", calls["task"])

    def test_project_without_rules_is_reviewed_and_published(self):
        rc, calls, _, stderr = self.run_main_with_leg_result("gpt-5.6", dry_run=False)
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(calls["leg_runs"], 1)
        self.assertEqual(calls["github_writes"], ["repos/SunJ1ayu/OpenDesign/pulls/12/reviews"])

    def test_unreadable_aiwork_rules_never_run_or_publish(self):
        for failure in ("main_unreadable", "rules_unreadable", "invalid_sha",
                        "not_file", "invalid_content", "truncated_content"):
            with self.subTest(failure=failure):
                rc, calls, stdout, stderr = self.run_main_with_leg_result(
                    "gpt-5.6", dry_run=False, source_failure=failure, project_rules=True)
                self.assertEqual(rc, 1)
                self.assertEqual(calls["leg_runs"], 0)
                self.assertEqual(calls["github_writes"], [])
                self.assertEqual(stdout, "")
                self.assertTrue(stderr)
                self.assertTrue(calls["public_reads"])

    def test_modified_local_rules_do_not_change_task(self):
        rc, calls, _, stderr = self.run_main_with_leg_result(
            "gpt-5.6", local_rules="MODIFIED LOCAL REVIEW RULES")
        self.assertEqual(rc, 0, stderr)
        self.assertIn(calls["rules"], calls["task"])
        self.assertNotIn("MODIFIED LOCAL REVIEW RULES", calls["task"])

    def test_task_risks_are_project_main_and_missing_risks_are_none(self):
        for present in (True, False):
            with self.subTest(present=present):
                rc, calls, _, stderr = self.run_main_with_leg_result("gpt-5.6", risks_present=present)
                self.assertEqual(rc, 0, stderr)
                section = calls["task"].split("## 项目 main 的 .aiwork/accepted-risks.md", 1)[1].split("## 改动文件", 1)[0]
                self.assertIn(calls["risks"] if present else "无", section)
                self.assertNotIn("PR RISK DECOY", section)

    def test_repository_routes_reads_snapshot_token_and_publication_together(self):
        target = "SunJ1ayu/aiwork"
        rc, calls, _, stderr = self.run_main_with_leg_result("gpt-5.6", dry_run=False, repository=target)
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(calls["github_writes"], [f"repos/{target}/pulls/12/reviews"])
        self.assertEqual(calls["token_command"][1:], ["review", "--repo", target])
        for call in calls["pr_state"]:
            self.assertEqual(call.kwargs["repository"], target)
        self.assertEqual(calls["snapshot"].kwargs["repository"], target)
        self.assertTrue(calls["task"].startswith("# SunJ1ayu/aiwork PR #12"))

    def test_invalid_repository_is_rejected_before_getting_credentials(self):
        for target in ("../aiwork", "owner/repo/extra", "https://github.com/owner/repo", "owner/repo\nother", "owner/.."):
            with self.subTest(target=target), patch("sys.argv", ["review-pr", "12", "--repo", target]), \
                    patch.object(self.review, "run") as run, redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as exit:
                    self.review.main()
                self.assertNotEqual(exit.exception.code, 0)
                run.assert_not_called()

    def test_pr_response_from_another_repository_is_rejected(self):
        pr = {"state": "open", "head": {"sha": "a" * 40, "ref": "f"},
              "base": {"sha": "b" * 40, "ref": "main", "repo": {"full_name": "SunJ1ayu/OpenDesign"}}}
        with patch.object(self.review, "github", return_value=pr) as api:
            with self.assertRaisesRegex(self.review.ReviewError, "repository"):
                self.review.pr_state("fake-token", 12, repository="SunJ1ayu/aiwork")
            self.assertEqual(api.call_args.args[1], "repos/SunJ1ayu/aiwork/pulls/12")

    def test_snapshot_fetches_the_selected_repository_and_its_main(self):
        pr = {"head": {"sha": "a" * 40}, "base": {"sha": "b" * 40}}
        commands = []

        def fake_git(command, **kwargs):
            commands.append(command)
            if command[-2:] == ["rev-parse", "HEAD"]:
                return "a" * 40
            if "merge-base" in command:
                return "c" * 40
            if "--binary" in command:
                return "patch"
            return ""

        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(self.review, "run", side_effect=fake_git), \
                patch.object(self.review.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"src/a.py\0", b"")):
            _, base, files, _ = self.review.snapshot("fake-token", pr, Path(temporary),
                                                   repository="SunJ1ayu/aiwork")
        fetch = next(command for command in commands if "fetch" in command)
        self.assertIn("https://github.com/SunJ1ayu/aiwork.git", fetch)
        self.assertNotIn("https://github.com/SunJ1ayu/OpenDesign.git", fetch)
        self.assertIn("refs/heads/main:refs/aiwork/main", fetch)
        self.assertEqual((base, files), ("c" * 40, ["src/a.py"]))

    def test_cursor_model_is_frozen_for_leg_and_result(self):
        rc, calls, body, stderr = self.run_main_with_leg_result("gpt-5.6")
        self.assertEqual(rc, 0, stderr)
        emit = calls["emit"]
        self.assertEqual(calls["leg_env"]["CURSOR_MODEL"], "gpt-5.6")
        self.assertEqual(emit[emit.index("--expected-model") + 1], "gpt-5.6")
        self.assertEqual(emit[emit.index("--family") + 1], "openai")
        self.assertIn("**aiwork-review · subcursor · gpt-5.6**", body)
        block = json.loads(body.split("```json\n", 1)[1].split("\n```", 1)[0])
        self.assertEqual((block["model"], block["family"]), ("gpt-5.6", "openai"))

    def test_cursor_result_from_another_model_is_not_published(self):
        rc, _, body, stderr = self.run_main_with_leg_result("claude-4.5-sonnet")
        self.assertEqual(rc, 1)
        self.assertEqual(body, "")
        self.assertIn("does not match selected family", stderr)

    def test_publishing_writes_only_the_review(self):
        # The review itself wakes the gate (OpenDesign aiwork-review-ping); a second write
        # such as a recheck label is a second doorbell, and its failure would turn a posted
        # review into exit 1.
        rc, calls, stdout, stderr = self.run_main_with_leg_result("gpt-5.6", dry_run=False)
        self.assertEqual(rc, 0, stderr)
        self.assertEqual(calls["github_writes"], ["repos/SunJ1ayu/OpenDesign/pulls/12/reviews"])
        self.assertEqual(stdout.strip(), "https://github.com/SunJ1ayu/OpenDesign/pull/12#pullrequestreview-1")

    def test_report_is_separated_only_at_the_leg_log_header(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "review.log"
            log.write_text("# subcursor review log\nmodel: gpt-5.6\n\nFirst paragraph.\n\n"
                           "Conclusion: PASS\n", encoding="utf-8")
            self.assertEqual(self.review.review_report(log), "First paragraph.\n\nConclusion: PASS")
            # Without the header, cutting at the first empty line would drop the report's opening.
            log.write_text("First paragraph.\n\nConclusion: PASS\n", encoding="utf-8")
            with self.assertRaisesRegex(self.review.ReviewError, "header"):
                self.review.review_report(log)

    def test_stale_head_is_refused_before_post(self):
        with self.assertRaises(ValueError):
            self.review.check_current_head("a" * 40, {"state": "open", "head": {"sha": "b" * 40}})

    def test_risks_come_from_project_main_even_when_pr_changes_them(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.run(["git", "-C", str(repo), *args], check=True,
                                      capture_output=True)
            git("init", "-q")
            git("config", "core.autocrlf", "false")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            documents = {".aiwork/accepted-risks.md": "# main 风险\r\n业主接受的平台上限。\r\n"}
            (repo / ".aiwork").mkdir()
            for path, trusted in documents.items():
                (repo / path).write_bytes(trusted.encode("utf-8"))
            git("add", ".")
            git("commit", "-qm", "main risks")
            git("update-ref", "refs/aiwork/main", "HEAD")
            for path in documents:
                (repo / path).write_text("PR 自行改写口径和豁免风险", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "untrusted PR risks")
            for path, trusted in documents.items():
                self.assertEqual(self.review.main_document(repo, path), trusted)
            git("rm", "-q", ".aiwork/accepted-risks.md")
            git("commit", "-qm", "main without risks")
            git("update-ref", "refs/aiwork/main", "HEAD")
            self.assertEqual(self.review.main_document(repo, ".aiwork/accepted-risks.md", required=False), "无")

    def test_failed_risk_lookup_is_not_treated_as_absence(self):
        with patch.object(self.review, "run", side_effect=self.review.ReviewError("fetch failed")):
            with self.assertRaises(self.review.ReviewError):
                self.review.main_document(Path("unused"), ".aiwork/accepted-risks.md", required=False)

    def test_unreadable_document_is_not_treated_as_absence(self):
        with patch.object(self.review, "run", return_value="100644 blob " + "a" * 40 + "\tfile"), \
                patch.object(self.review.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, b"", b"error")):
            for required in (True, False):
                with self.subTest(required=required), self.assertRaises(self.review.ReviewError):
                    self.review.main_document(Path("unused"), "file", required=required)

    def test_non_regular_document_is_refused(self):
        with patch.object(self.review, "run", return_value="120000 blob " + "a" * 40 + "\tfile"):
            with self.assertRaisesRegex(self.review.ReviewError, "not a regular file"):
                self.review.main_document(Path("unused"), "file", required=False)

    def test_failed_or_incomplete_leg_cannot_publish(self):
        result = {
            "process": {"state": "exited", "exit_code": 0},
            "verdict": "PASS", "failure_kind": "none", "degraded": False,
            "evidence": {"completeness": "complete"},
            "view": {"delivery_state": "complete"},
            "model": {"requested": "gpt-6-sol", "invoked": "gpt-6-sol", "reported": None},
        }
        self.assertEqual(self.review.publishable_model(result), "gpt-6-sol")
        for change in (
            {"process": {"state": "exited", "exit_code": 1}},
            {"verdict": "UNKNOWN"},
            {"failure_kind": "quota"},
            {"evidence": {"completeness": "none"}},
            {"model": {"requested": "gpt-6-sol", "invoked": "gpt-other", "reported": None}},
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.review.publishable_model(result | change)


if __name__ == "__main__":
    unittest.main()

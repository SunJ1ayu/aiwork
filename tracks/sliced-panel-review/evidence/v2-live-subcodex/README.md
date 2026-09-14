# V2 live subcodex probes (2026-09-13, codex-cli 0.154.0, gpt-6-astra)

Fixture: one-commit repo, `maths.py` `add` returns `a - b` (docstring says sum).

| run | subcodex version | sub-agent tools | web tool | report |
|---|---|---|---|---|
| 1 (23:19) | first implementation: `--disable multi_agent --disable multi_agent_v2` | **present** (`collaboration.spawn_agent` …) | **present** (`web__run`) | run1-subcodex.log |
| 2 (23:27) | out-of-repo copy: catalog override + `-c web_search="disabled"` | absent | absent | run2-subcodex.log |
| 3 (23:28) | same copy, `web_search` key removed (attribution) | absent | **present** | run3-subcodex.log |

Tool lists are the model's own statement (task asked for it). The sub-agent part is
corroborated independently by `codex debug prompt-input` (prompt-input-offline.txt).
Commands actually run are in each `*.stream.jsonl`. All three runs read
`/root/.codex/skills/karpathy-guidelines/SKILL.md` (skill list still visible).
Run 1 appended a `[projects."/tmp/aiwork-review-workspaces/subcodex.Bkm9LPoB/repo"]`
trust entry to `~/.codex/config.toml`. Checked again 2026-09-14: the file holds exactly
four such entries (`subcodex.Bkm9LPoB`, `.dbVjclUI`, `.oUrQLf8I`, `.0mUmKSP0`) = runs 1-3
here plus the V3 overall leg, so every live `codex exec` so far appended one.

The repo `bin/subcodex` after the fix differs from the run-2 copy only in one error
message string (comment lines excluded).

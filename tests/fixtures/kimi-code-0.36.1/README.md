# Kimi reader input evidence

Verbatim input definitions from the published npm package
`@moonshot-ai/kimi-code@0.36.1`, `package/dist/main.mjs`.
The archive was downloaded from the npm registry, its SHA-512 integrity was
verified against the version metadata, and its main.mjs bytes match the
server's installed 0.36.1 file. No Kimi/model invocation was used.

- Metadata: https://registry.npmjs.org/@moonshot-ai%2Fkimi-code/0.36.1
- Tarball: https://registry.npmjs.org/@moonshot-ai/kimi-code/-/kimi-code-0.36.1.tgz
- npm integrity: `sha512-dAYvA0qIZ/nPOtf+8X0axRP3Supa06oP9xK/JlY/DsrID5IVmDRc2fKTdASNBvSs1XPUbPFwD1cDNXMoEDQfEA==`
- `dist/main.mjs` SHA-256: `e1ca88960c1e09c40e09ef43a6ac180eef20449aa4528b0ee36105aa7b83bba6`

`reader-inputs.mjs` contains the first assignment to each of the following
schema symbols, including the whole `object({ ... });` expression. No fields,
descriptions, optional markers, indentation, or symbol names were changed.
Only unrelated code between these definitions was omitted. It is source
evidence, not a runnable module or a synthetic stream capture.

| Symbol | Original main.mjs lines (1-based) |
|---|---|
| ReadInputSchema$1 | 159695–159699 |
| ReadMediaFileInputSchema$1 | 160098–160107 |
| GlobInputSchema$1 | 158882–158887 |
| GrepInputSchema$1 | 159404–159423 |

To reproduce after downloading/unpacking the pinned archive:

```python
import re
from pathlib import Path

source = Path("package/dist/main.mjs").read_text()
parts = []
for tool in ("Read", "ReadMediaFile", "Glob", "Grep"):
    match = re.search(r"^\t" + tool + r"InputSchema\$1 = object\(\{", source, re.M)
    end = source.index("\n\t});", match.start()) + len("\n\t});")
    parts.append(source[match.start():end] + "\n")
Path("reader-inputs.mjs").write_text("\n".join(parts))
```

The npm package's MIT notice is retained in [LICENSE](LICENSE).
The consumer check is
`ReaderToolAuditTests.test_kimi_reader_arguments_match_published_input_schemas`
in `tests/test_reader_tool_audit.py`: it derives string argument names and
optionality from this evidence, passes them through the production
`audit-kimi` command, and checks both in-repository acceptance and outside
path rejection. It does not require an installed Kimi package or network.
This evidence pins 0.36.1; it makes no claim about later CLI versions or
execution-time guards.

`reader-tools.json` retains the tool names and JSON input schemas captured from
the real installed 0.36.1 CLI against a local HTTP provider on 2026-10-27.
Only descriptions outside the parameter schemas and unrelated request data
were omitted. The provider used harmless temporary files and no real
credentials; the existing no-egress test guard blocked external traffic.
This captures the CLI request contract, not a vendor model response.

`empty-grep-rejection.mjs` contains verbatim excerpts from the same installed
0.36.1 `main.mjs` (SHA-256 above), inspected on 2026-11-23. Line ranges are
recorded above each excerpt. `GrepTool$1.resolveExecution` resolves an explicitly
provided path before returning the search closure; `resolvePathAccessPath$1`
passes it to `resolvePathAccess$1`, then `canonicalizePath$1`, which throws
`PathSecurityError$1("PATH_INVALID", "", "", "Path cannot be empty")` without
filesystem I/O. `prepareToolCall` catches that setup error and settles an error
result with exactly `error.message`, before authorization or starting execution.
`makeErrorToolResult$1` preserves that output. These are source evidence
(level: located in code), not a captured CLI stream or a reviewer-machine run.
The native rejection text used by regression tests is taken from this code.

`empty-grep-results.json` preserves the empty Grep tool messages captured on
2026-11-23 by running the installed 0.36.1 CLI against the production local-only
preflight provider (temporary files, placeholder credential, no vendor call).
`stream` is the stdout JSONL tool event; `provider` is the subsequent HTTP
request's tool message. The provider projector wraps error outputs with the
fixed status prefix; the stream preserves the raw error. No paths, credentials
or unrelated messages are included. Both contents are verbatim. The probe
passed when its empty-result check matched the exact provider rendering;
other schema, positive-reader, outside-boundary and traversal checks were
unchanged. This is a coding-host CLI run, not reviewer-machine acceptance.

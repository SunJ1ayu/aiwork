# Kimi saved-result read attempts

These two excerpts come from the server's preserved `review-pr` failure artifacts:

- PR #108, head `0a98344c27964351c5b928a9e393f34e76c88472`, second review round.
- PR #112, head `af7d76292ff6b4015b554366d4521e495ae17105`, first review round.

Both streams report CLI version 0.36.1. Each excerpt retains the first Read call,
its truncated-result notice, the subsequent Read of the advertised saved result,
and the guard's denial. The first outputs were 50,337 and 56,206 characters.
The CLI advised `Use Read with output_path to page through the full output.`
That saved-result path was under the CLI runtime home, outside the repository
snapshot. Both attempts returned only the guard denial, not file contents.
They were real outside-path attempts, not incorrect containment decisions.

Sanitization replaces the temporary task filename and runtime-home/session path,
removes repository text and assistant prose, and retains tool names, argument
keys, call IDs, output sizes, record shapes and the denial text. These are trace
excerpts, not complete reviews or new model runs. Neither original artifact nor
credentials are copied into the repository.

`KimiPreToolGuardTests.test_historical_outside_spill_reads_still_refuse_before_and_after`
replays both excerpts with a disposable runtime-home location. The execution
hook and post-run audit must continue refusing the outside Read. The Kimi reader
profile's paging guidance lives in `bin/_reader_tools.py::kimi_profile`.

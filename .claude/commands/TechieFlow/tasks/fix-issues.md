# fix-issues

`*fix-issues {App} {folder}` is the one command the owner hands a pile of evidence to: a folder of screenshots with an optional notes file. It reproduces each bug, logs it, fixes it through the builders, re-verifies the touched rows and closes the misses with the cost of the fix. The owner never calls a builder. If the owner's words ask only to analyse or log, this is `*triage-issues`, not a fix. It honours YOLO.

First: `bash .tfcore/utils/tf-phase.sh start fix-issues {App}` prints the start time; keep it. The marker is what lets a migration run from this command.

## Steps

1. Triage first, as `.tfcore/tasks/triage-issues.md` steps 1 to 4: read the evidence, boot (`tf-verify-boot.sh start`), reproduce each issue on its screen with the screens script, map it to its row, and log it with `tf-triage.sh demote` or `new`. Then `bash .tfcore/utils/tf-triage.sh {App} close --started <the step-0 time> --cmd fix-issues` writes the escaped gate records and the misses with the discovery cost. A defect nobody logged has no miss to close, so this step is never skipped.
2. `bash .tfcore/utils/tf-build-list.sh {App} --prompts` now prints FIX mode with the demoted rows, their clusters and one builder prompt each. Spawn every cluster in one turn, exactly as `.tfcore/tasks/build-phase.md` step 2 says: `[trblazeui]` through `/trblazeui`, `[techierag]` through `/techierag`, the rest through the builder sub-agent. A library gap goes into the library's feedback file and the row becomes `Blocked`; never a workaround.
3. `bash .tfcore/utils/tf-build.sh` until PASS, then smoke every fixed screen with `tf-verify-screens.sh --screen …` (`.tfcore/tasks/_smoke-test-policy.md`); a screen that still fails re-enters step 2 for its rows.
4. Execute `.tfcore/tasks/verify-phase.md` inline, scoped to the touched rows. Only that run writes `Verified`.
5. `bash .tfcore/utils/tf-verify-boot.sh stop`, then `bash .tfcore/utils/tf-fix-close.sh {App} --started <the step-0 time> --subagents <what was fanned out> --build <pass|fail>`: the fix-issues run record first, then one miss-fix per touched row with the verifier's verdict from the ledger. A row the verifier left below `Verified` stays open with that verdict on its miss-fix.
6. Run the status gate (`.tfcore/tasks/_status-update-gate.md`); the run record is the one step 5 wrote. When this run is the last step of a goal, write the sentinel (`.tfcore/tasks/_yolo-mode.md`).
7. Report: evidence read, issues by kind, rows fixed and now `Verified`, rows still open and why, library gaps logged, and the next command from the gate.

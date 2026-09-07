# triage-issues

`*triage-issues {App} {evidence} [verify]` is the analyse-only front door for bugs a person found by running the application: UAT feedback, a production report, an owner test session. The evidence is a folder of screenshots with an optional notes file, a written list, or both. The deliverable is the checklist and the telemetry, never code: nothing under `src/`, `source/` or `tests/` changes, and no builder is spawned. Fixing is the owner's next decision, `*fix-issues`. It honours YOLO.

First: `bash .tfcore/utils/tf-phase.sh start triage-issues {App}` prints the start time; keep it.

## Steps

1. Read every screenshot and the notes; from a written list take one issue per symptom in the reporter's words. Build the issue list: screen, role, symptom, evidence path, a first guess of kind (`layout`, `render-empty`, `data-logic`, `rag`).
2. `bash .tfcore/utils/tf-verify-boot.sh start` boots the application (dependent services first, from their own configuration). Sign in as a UsageGuide test user (`.tfcore/tasks/_smoke-test-policy.md`). NONE means the issues are logged from the evidence alone and the report says the app was not booted.
3. Reproduce each issue on its screen; `bash .tfcore/utils/tf-verify-screens.sh --screen <name>=<route> … --base <url>` gives the render and visual evidence and a screenshot. Settle the kind from what you see and map the issue to its row in the checklist (the acceptance line's screen; the DevGuide's screen list). Print the triage table: issue, row, kind, action.
4. Log each issue with `bash .tfcore/utils/tf-triage.sh {App} …`: `demote <REQ> "<symptom>" --kind … --evidence <path>` for a defect inside a row's scope, whatever its status; `new "<title>" "<When … on <screen>, then …>" --section "<screen>"` for a defect no row covers (a Not Started row with `BRD-pending`; new scope rather than a defect is still logged, and the report names `*amend-docs`); `note <REQ> "<what was tried>"` when it could not be reproduced. `--source production` for a live report. Whose gap it was is recorded as `--sort` (the four questions of `.tfcore/tasks/log-miss.md` step 1); without it a demoted row is `weak-check` (its line existed and the check let it through) and a new row is `spec`.
5. With `verify`: execute `.tfcore/tasks/verify-phase.md` inline, scoped to the demoted rows' siblings on the same screens and any scope the owner named. Without it, the verifier does not run and nothing is re-checked informally.
6. `bash .tfcore/utils/tf-verify-boot.sh stop`, then `bash .tfcore/utils/tf-triage.sh {App} close --started <the step-0 time>`: one escaped gate record per row (no check caught it), one miss per row in the reporter's words with the discovery cost, the run record, and a warning plus a miss if any code file changed during the run.
7. Run the status gate (`.tfcore/tasks/_status-update-gate.md`); the run record is the one step 6 wrote. The next command is `*fix-issues {App} {evidence}` naming the rows.
8. Report: evidence read, issues reproduced and logged (rows demoted, rows added), could-not-reproduce with the question for the owner, the verify scope if it ran, "no code changed", and the next command.

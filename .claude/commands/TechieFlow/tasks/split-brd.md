# split-brd

Turns the BRD ledger into the one checklist, `docs/{App}-Checklist.md`. The prefix of a row routes its work: `REQ-UI-` to the UI sub-agent from the mockups, `REQ-RAG-` to the RAG sub-agent, `REQ-FN-` and `REQ-NFR-` to the build phase. Called by both day-1 tasks; the owner never types it. Never edit source code here.

First: `bash .tfcore/utils/tf-phase.sh start split-brd {App}` prints the start time and marks the command running.

## Steps

1. `bash .tfcore/utils/tf-split-brd.sh {App}` writes the checklist draft from `docs/{App}-BRD.md`: one row per BRD item in the template shape, one section per screen, acceptance and perf-budget lines copied verbatim, the class guessed. An item with no acceptance line gets a TODO line that the checker refuses. On a re-run use `--force`; `*amend-docs` uses `--add-missing`. A Large project has one checklist per phase: `--all-phases` writes them all from `docs/{App}-Phases.md`; without a flag the script takes the phase from `appPhase` in `core-config.yaml`.
2. Read the draft and correct the class where the guess is wrong: UI is anything a user sees on a screen; RAG is anything with a model, embeddings, vectors, prompts or chat; NFR is speed, security, accessibility, observability or compliance; FN is everything else. Split a BRD item into two rows when it holds both a screen and a rule (a settings page and the save that persists it). Renumber only the rows you changed, within their prefix.
3. Fill every TODO acceptance line in the form "When <actor> <does what> on <screen>, then <observable result>"; an NFR row names the measurement instead of a screen.
4. If a phased plan is among the harvested documents (a file named like a development plan or roadmap, or content in phases with statuses), carry it in: tag each row with its phase, copy the plan's percentage and remark verbatim into the row, mark completed items `Done (pre-existing)` with the plan reference in Remarks, and add the note "> Migrated from {plan-file} on {date}" under the Goal. Then move the plan to `docs/OldDocs/` with `bash .tfcore/utils/tf-day1-files.sh --archive <file>`.
5. `bash .tfcore/utils/tf-doc-check.sh --app {App}`: it refuses a BRD item without a row, a row without its acceptance line, a UI row without its mockup and a duplicate id. Fix every FAIL.
6. When run on its own (not inside a day-1 task), run the status gate (`.tfcore/tasks/_status-update-gate.md`) with `"cmd":"split-brd"`; the next command is `*build-phase {App}`.
7. Report the row counts per prefix and any class you changed.

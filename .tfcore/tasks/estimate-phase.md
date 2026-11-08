# estimate-phase

`*estimate-phase {App} [/path/to/FamilyRepo ...]` estimates what the phase in progress will cost, in output tokens and in wall time, to build and to pass machine QA (verify plus fix), from this repo's own run history. Run it **before `*build-phase`** for the `appPhase` phase. The script does all the arithmetic and writes the records; **the agent's only judgement is a Remark on each row that has no precedent.** Never type a figure the script did not print.

First: `bash .tfcore/utils/tf-phase.sh start estimate-phase {App}` prints the start time and marks the command running.

## Read

`.tfcore/core-config.yaml` for `appPhase` (the phase, N; 1 when absent). Nothing else: the script reads the checklist and the run records itself.

## Steps

1. Run the estimate, naming every family repo the owner passed (other apps built with this framework, used only where this repo has fewer than three runs of a kind):

   ```bash
   bash .tfcore/telemetry/tf-estimate.sh . --phase N --app {App} [--family /path/to/FamilyRepo ...]
   ```

   `--app {App}` names the app's checklist, as the verifier is given it; without it the script reads `customTechnicalDocuments.brd` in core-config.yaml, then the one checklist with its own BRD, and otherwise stops and asks, never taking the first `*-Checklist.md` it finds (a `Prod-Deploy-Checklist.md` was once read as the app). When runs on the phase's own rows already exist, the estimate is printed **ESTIMATED AFTER THE FACT** and its records carry `basis_note: "retro"`: say so in the report, because hindsight is not a forecast.

   It reads phase N's checklist rows (`docs/{App}-Checklist.md` for phase 1, `docs/{App}-P<N>-Checklist.md` otherwise) and this repo's live run records of `build-phase`, `verify-phase`, `fix-issues` and the after-handoff step (`triage-and-fix` + `triage-issues`, pooled, never inside `fix-issues`) that touched at least one row. Per cmd and per row prefix (REQ-UI, REQ-FN, REQ-RAG, REQ-NFR …) it gives each row the first quartile, median and third quartile of the per-row tokens and time of earlier runs: low, mid, high. A run that touched one of this phase's rows is left out, so a phase is never estimated from itself. Fewer than three runs here: the family's runs are added (basis `family`). Still fewer than three: **no precedent**, never a number. It writes one record per row per cmd and one per phase total per cmd to `docs/metrics/estimates.jsonl` through `tf-emit.sh` (SCHEMA.md §2.8). `--dry-run` writes nothing; use it only when the owner asks for a look without a record.

2. For every row the table prints as **no precedent** (for any of build, verify, fix or after handoff), add a dated Remark to that row of the phase checklist with the Write tool (never by shell, so the guards can see it):

   `YYYY-MM-DD estimate: no precedent for <cmd> on <prefix> rows (<n> run(s) here, <m> with the family); left out of the phase figure. Closest in kind: <one plain sentence: what this row is most like, and why>.`

   That last sentence is the judgement, and it is words, never a number. Change nothing else on the row: not its Status, not its %.

3. Emit the run record as `.tfcore/tasks/_metrics-emit-gate.md` shows, with `"cmd":"estimate-phase"`, `reqs_touched` empty (an estimate acts on no row) and `files_written` 1 when step 2 edited the checklist, else 0. The estimate itself is already on its own stream; it is never copied into this record.

4. Report, then stop. Do not run the status gate: an estimate does not advance the project, and PROJECT-STATUS is not where estimates go.

   ```
   # Estimate — {App} phase N
   {the table exactly as tf-estimate.sh printed it}
   Rows with no precedent: {REQ ids, or "none"} — Remark added to each
   Owner UAT time: not measured
   Next: *build-phase {App}
   ```

## Hard rules

- **An estimate never pools with a measurement** (SCHEMA.md §6, fourth separation). Never write an estimate into `runs.jsonl`, the checklist's Status or %, or PROJECT-STATUS. The reconciliation, estimate beside actual, is `tf-metrics.sh --estimates`; `*handoff-phase` prints it.
- **No precedent is a result, not a gap to fill.** Never put a number on such a row, never borrow another prefix's figure, and never invent a family repo the owner did not name.
- A row figure is an input to the phase total, not a per-feature forecast (SCHEMA.md §0 non-goal). Quote the phase line; never quote "REQ-UI-004 will take 20 minutes".
- Never run git.

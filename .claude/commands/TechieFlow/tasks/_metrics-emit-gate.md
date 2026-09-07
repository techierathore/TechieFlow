# _metrics-emit-gate (shared rule — every task that emits telemetry)

Every command ends by appending one `runs.jsonl` record, right after the status gate. A verify pass appends one `gates.jsonl` record per requirement it graded. Telemetry never blocks: if an emit fails, the phase still succeeded; do not retry, diagnose or report it.

## Who writes what

| Stream | Written by | When |
|---|---|---|
| `runs.jsonl` | the task itself | once, at completion, after the status gate |
| `gates.jsonl` | `verify-phase` · `triage-issues` | one record per requirement graded or demoted |
| `misses.jsonl` | `verify-phase` · `build-phase` · `triage-issues` · `fix-issues` · `amend-docs` · `log-miss` | `miss` when something was missed; `miss-fix` when repaired; `miss-amend` to complete a null field |
| `misses.jsonl`, kind `review` | the run that applies an owner's corrections (`day1-greenfield --stage2`, `amend-docs`; build, verify and handoff reviews follow in 4c) | after its own run record: `phase` (`day1-review` …), `reviewed_run_id` (the `started` of the run that produced the reviewed output), `correction_run_id` (this run's `started`), `corrections` (how many the owner gave), `what` (one sentence). The emitter copies the two runs' tokens in as the cost to produce and the cost to correct (FR-36) |
| `sessions.jsonl` | `.tfcore/hooks/metrics-session.sh` | automatically, never by an agent |
| `commits.jsonl` | the owner's pre-commit hook | automatically, never by an agent |

## How to emit

Step 0 of every task is `bash .tfcore/utils/tf-phase.sh start <command> {App}`: it prints the start time and marks the command running. The emitter takes `started` from that marker when the record leaves it out, and replaces an `ended` that lies in the future with the moment of writing. A start time cannot be reconstructed at the end.

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","cmd":"build-phase","mode":"build",
 "started":"2026-08-08T03:41:02Z","ended":"2026-08-08T04:12:33Z",
 "reqs_touched":["REQ-UI-004","REQ-FN-011"],"reqs_count":2,
 "subagents":["trblazeui"],"files_written":14,"build_result":"pass"}
JSON
```

The script fills in everything else (harness, model, tokens, cost, app, time stamp) and refuses a record with a field the schema does not define, a miss without an id, or a value outside a vocabulary. It prints the reason. Fields: `.tfcore/telemetry/SCHEMA.md`.

## Misses

- Get the id first: `bash .tfcore/utils/tf-emit.sh --next-miss-id`.
- One defect is one miss. Before emitting, run `bash .tfcore/utils/tf-emit.sh --open-miss REQ-UI-014`; if it prints an open miss of the same class, emit nothing.
- On a miss found by the owner, fill `why_missed`.
- Every miss carries `sort`, whose gap it was: `spec`, `unsaid`, `weak-check` or `ignored` (the four questions of `log-miss.md` step 1). The scripts fill it; a hand-written record names it.
- Complete a null field later with `bash .tfcore/utils/tf-emit.sh --amend <miss_id> <field> <value>` (`why_missed` or `sort`).
- `what` is one sentence in the owner's words. Nothing else in a record is free text: no requirement text, file content or secret. The emitter rewrites `docs/<App>-Misses.md` from the stream after every miss record; never edit that file.

## Do not

- Do not estimate a number that was not measured; `null` is the honest value.
- Do not emit a run for work you did not do: a phase that halted emits `build_result: "not-run"`.
- Do not change `docs/.last-verify.json`; the verify guard depends on it.
- Do not mention telemetry in your report unless something was genuinely notable.

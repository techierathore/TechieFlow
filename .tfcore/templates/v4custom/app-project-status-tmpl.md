<!-- tf-schema
doc: project-status
file: PROJECT-STATUS.md
header: project, last_updated, current_phase, last_verified_build, last_verified_date
section: Where I am | required | max 80
section: Next command to run | required | max 60
section: Open requirements | required | max 200
section: Known blockers | required | max 150
section: Verification log | required | max 250
section: Library feedback summary | required | max 60
section: Standards compliance | required | max 60
section: Deferred / future | required | max 100
max-lines: 120
target-lines: 60
rule: next-command-blocks
rule: verification-log
rule: open-requirements-max-10
-->
<!-- Authoring notes (agent only; never visible text).
     A one-page snapshot of the CURRENT state, overwritten in place, never appended to. Exactly the
     eight sections above, in this order, with their word limits; guard-status.sh refuses any other
     heading and any write over 120 lines; tf-doc-check.sh refuses over-long sections. What a run did
     is not written here: a run adds ONE Verification-log row (at most five kept) and updates the
     checklist Remarks; the rest lives in the telemetry streams.
     Next command to run: exactly two code blocks, one line each, labelled Claude Code then OpenCode,
     so either can be copied on its own. No prose about the technical work. -->

---
project: {App}
last_updated: {YYYY-MM-DD}
current_phase: {Day-1 | Build | Verify | UAT | Handoff | Released} — {at most a half-line qualifier}
last_verified_build: {PASS | FAIL | not-run}
last_verified_date: {YYYY-MM-DD}
---

# {App} — Status

## Where I am

{At most 80 words: which phase, what is built and verified, what is open. State, not story.}

## Next command to run

Claude Code:
```
/TechieFlow:agents:flow-master *build-phase {App}
```
OpenCode:
```
/flow-master *build-phase {App}
```
{Optional one line naming the target REQ ids.}

## Open requirements

| Status | Count |
|---|---|
| Not Started | {n} |
| In Progress | {n} |
| Implemented | {n} |
| Needs re-verify | {n} |
| Blocked | {n} |

- [ ] REQ-UI-001 — {short name} (at most ten named rows)

## Known blockers

- None

## Verification log

Last five passes; older passes live in `docs/metrics/gates.jsonl`.

| Date | Phase | Result | Status table |
|---|---|---|---|
| {YYYY-MM-DD} | {verify all} | {14/14 Verified} | docs/{App}-Checklist.md#requirements-status |

## Library feedback summary

- {Library}: {n} open — docs/{App}-{Library}-Feedback.md

## Standards compliance

- Last check {YYYY-MM-DD}: {n} findings, see the checklist Remarks.

## Deferred / future

- {parked ideas, one line each}

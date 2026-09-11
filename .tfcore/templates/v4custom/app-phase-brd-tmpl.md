<!-- tf-schema
doc: brd
file: docs/{App}-P{n}-BRD.md
header: App, Kind, Size, Status, Date
section: Summary | required | max 200
section: Screens and flow | required
section: Requirements | required
section: Non-functional requirements | optional
section: Development status | required
section: Where the rest lives | required
budget: S 6000 8000 | M 10000 15000 | L 10000 15000
rule: brd-ledger
rule: screens-table
rule: mockup-links
rule: phase-pointer
-->
<!-- Authoring notes (agent only; never visible text).
     A phase BRD is phase 2 onward of a Large project. Phase 1 is docs/{App}-BRD.md, written from
     app-brd-tmpl.md, and it holds everything that belongs to the whole application: Scope, Users and
     roles, the Non-functional requirements that apply everywhere, the Context diagram, Constraints and
     assumptions, and Risks. A phase BRD never repeats them: two copies of the same fact become two
     answers the day one of them is amended (TfLens TF-024, 2026-09-11). It holds this phase's screens,
     this phase's requirements, and a "Where the rest lives" table that links back to phase 1.
     "Non-functional requirements" is here only when this phase adds its own, for example a speed
     budget on one of its screens; its ids run on like every other item.
     The header carries "| Phase | n of m |" (the checker refuses the file without it). Size is the
     phase's own size, Small or Medium. BRD-N runs on from the previous phase's last id and is never
     renumbered. Sections and order are fixed by the schema above; the order is the whole-project
     BRD's, with the sections a phase does not carry left out. -->

# {App} — Business Requirements — Phase {n}: {Phase name}

| | |
|---|---|
| App | {App} |
| Kind | app or library |
| Size | Small or Medium (this phase on its own) |
| Phase | {n} of {m} |
| Status | Draft, Approved |
| Date | {YYYY-MM-DD} |

## 1. Summary

{What this phase adds, for whom, and why it comes at this point. At most 200 words.}

## 2. Screens and flow

One row per routed page this phase adds; dialogs are written exactly as in the phase-1 BRD.

| Screen | Route | Role | Mockup | Fields |
|---|---|---|---|---|
| {Screen name} | `/route` | {Role} | [mockup](mockups/{screen-slug}.html) | {field, field, field} |

**Primary journey:**
1. {The user opens … and …}

## 3. Requirements

One item per thing the verifier will test, grouped under a `###` heading per screen. Same rules as the phase-1 BRD: an acceptance line is at most 30 words, target 20, and holds one behaviour.

### {Screen name}

{One plain sentence: what this screen does, for whom.}

- **BRD-{N}** — {Title}. *Screen:* {Screen name} · *Mockup:* [mockup](mockups/{screen-slug}.html)
  - *Acceptance:* When {actor} {does what} on {screen}, then {a result a browser robot can observe}.

## 4. Non-functional requirements

Only what this phase adds. The ones that apply to the whole application are in the phase-1 BRD.

| Id | Area | Requirement | Measure |
|---|---|---|---|
| BRD-{N} | Performance | {…} | perf-budget: p95 load <= 2000ms @ concurrency 1 |

## 5. Development status

Written by the status gate after every build, verify and handoff; not by hand.

**Snapshot as of {YYYY-MM-DD}.** Live per-requirement status: `PROJECT-STATUS.md` and the Requirements Status table in `docs/{App}-P{n}-Checklist.md`.

| Screen | Requirements | Verified | Open | Status |
|---|---|---|---|---|
| {Screen} | {n} | {n} | {n} | Planned, In progress, Partial, Done |

## 6. Where the rest lives

| What | Where |
|---|---|
| Scope, users and roles, the context diagram | [phase 1 BRD]({App}-BRD.md) |
| Non-functional requirements for the whole application | [phase 1 BRD]({App}-BRD.md) |
| Constraints, assumptions and risks | [phase 1 BRD]({App}-BRD.md) |
| Every phase, its screens and its BRD range | [{App}-Phases.md]({App}-Phases.md) |
| This phase's work list | [{App}-P{n}-Checklist.md]({App}-P{n}-Checklist.md) |

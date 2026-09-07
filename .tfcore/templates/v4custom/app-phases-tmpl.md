<!-- tf-schema
doc: phases
file: docs/{App}-Phases.md
header: App, Kind, Size, Date
section: Phases | required
budget: S 300 600 | M 300 600 | L 300 600
rule: phases-table
-->
<!-- Authoring notes (agent only; never visible text).
     Large projects only. One row per phase; each phase fits Medium on its own (at most 20 screens,
     100 requirements). Phase 1 keeps the plain file names (docs/{App}-BRD.md, -Checklist, -UIDesign,
     -DevGuide); phase 2 onward are docs/{App}-P2-BRD.md and so on. BRD-N and REQ- ids run on across
     phases and are never reused, so the ranges never overlap. An item added to an earlier phase after a
     later phase exists takes the next free id and the row gets a second range: "BRD-1 to BRD-73, BRD-111 to BRD-118". Every screen sits in exactly one phase;
     the screens of a phase are exactly the "### Screen:" entries of that phase's UIDesign.
     Status is planned, building or done. The phase being worked is appPhase in core-config.yaml
     (bash .tfcore/utils/tf-day1-files.sh {App} --phase N); handoff moves it on.
     tf-doc-check.sh --app {App} refuses a screen in two phases, an id in two phases, a BRD id outside
     its phase's range, and a phase row without its BRD file. -->

# {App} — Phases

| | |
|---|---|
| App | {App} |
| Kind | app |
| Size | Large |
| Date | {YYYY-MM-DD} |

## Phases

| Phase | Name | Screens | BRD range | Status |
|---|---|---|---|---|
| 1 | {Name} | {Screen, Screen, Screen} | BRD-1 to BRD-{N} | planned |
| 2 | {Name} | {Screen, Screen} | BRD-{N+1} to BRD-{M} | planned |

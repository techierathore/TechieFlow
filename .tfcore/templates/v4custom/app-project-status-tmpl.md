---
project: {AppName}
stack: .NET 9 / Blazor [Server|WASM|Auto] / TrBlazeUI / TechieRag / [MAUI]
last_updated: {YYYY-MM-DD}
current_phase: Discovery | UI build | UI verify | Functional build | Functional verify | Handoff | Released
last_verified_build: PASS | FAIL | not-run
last_verified_date: {YYYY-MM-DD}
---

# {AppName} — Status

<!--
  ============================================================================
  THIS FILE IS A CRISP, FIXED-SHAPE SNAPSHOT — OVERWRITE IT, NEVER APPEND TO IT.
  It has exactly the sections below and NO others. It should stay well under
  ~60 lines — a human reads it in ten seconds.

  When you update status you REPLACE the content of these sections in place.
  Do NOT add a new dated section per run. The following are BANNED (they are
  what turns this file into an unreadable 280-line append-log):
    - A per-run prose H2 like "## *verify all — formal coverage matrix (DATE)",
      "## *fix-issues — …", "## *build-phase — …". A run records its outcome as
      ONE row in "## Verification log" + updated Remarks IN THE CHECKLIST. Period.
    - A paragraph crammed into `current_phase:` or "## Where I am". `current_phase`
      is ONE short line. The blow-by-blow lives in the checklist Remarks + .verify/.
  See .tfcore/tasks/_status-update-gate.md §"CRISP, FIXED-SHAPE snapshot".
  ============================================================================
-->

## Where I am
<one short paragraph — the current STATE only: which phase, what is built/verified, what is open.
 This is a status snapshot, NOT a technical to-do list. Do not narrate the implementation work
 still to be done (how to wire a service, fix a binding, etc.) — that lives in the checklist REQ rows.>

## Next command to run
<!--
  Express the next step ONLY as a command pointed at a checklist/scope. NOT a prose description of
  the technical work. The "what to do" already lives in the checklist's REQ rows — here we just say
  WHICH COMMAND to run against WHICH checklist/REQs. At most one line naming the target checklist or
  REQ IDs may accompany the command block.

  GOOD:
    ```
    /TechieFlow:agents:verifier *verify ui      (OpenCode: /flow-verifier *verify ui)
    ```
    Resumes FAILed REQ-UI-007, REQ-UI-012 in docs/{AppName}-Checklist.md.

  BAD (do not do this — technical narrative belongs in the checklist, not here):
    Next, wire the AstroData service into the dashboard, fix the empty ruling-planet
    table binding, add validation to the onboarding form, then re-run verification...
-->
```
/<agent> <exact prompt>      (OpenCode: <exact prompt>)
```
<one optional line naming the target checklist or REQ IDs>

## Open requirements
- [ ] REQ-UI-013 — <desc>
- [ ] REQ-FN-007 — <desc>

## Known blockers
- None / <list>
<!--
  Known blockers are PROJECT-level issues — broken code, missing tests, real compile errors, hardcoded secrets, etc.
  They are NOT environment / wrong-rung issues. Banned entries (these go in WORKFLOW.html §0 territory, not here):
    - "MAUI build cannot run on WSL"
    - "NETSDK1178 — iOS/Android/MacCatalyst workload missing"
    - "Microsoft.iOS.Sdk / Microsoft.Android.Sdk / Microsoft.MacCatalyst.Sdk missing"
    - "dotnet not in PATH"
    - Anything that means "I used the wrong build invocation ladder rung"
  If you wrote one of those, you skipped .tfcore/templates/v4custom/build-invocation-ladder.md.
  Switch rungs and rebuild.
-->


## Verification log
<!-- Status detail lives in the checklist's "Requirements Status" table (the single
     source of truth). This log is just a dated index of verification passes. -->
| Date | Phase | Result | Status table |
|------|-------|--------|--------------|
| {YYYY-MM-DD} | UI verify | 14/14 Verified | docs/{AppName}-Checklist.md#requirements-status |

## Library feedback summary
- TrBlazeUI: 0 major, 0 minor — docs/{AppName}-TrBlazeUI-Feedback.md
- TechieRag: 0 major, 0 minor — docs/{AppName}-TechieRag-Feedback.md

<!-- One feedback file PER library (separate teams). Files are created on first issue. -->

## Standards compliance (last verifier check)
- Underscore fields: not yet run
- Test method underscores: not yet run
- Mis-prefixed fields: not yet run

## Deferred / future
- <parked ideas>

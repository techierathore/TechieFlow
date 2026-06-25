---
project: {AppName}
stack: .NET 9 / Blazor [Server|WASM|Auto] / TrBlazeUI / TechieRag / [MAUI]
last_updated: {YYYY-MM-DD}
current_phase: Discovery | UI build | UI verify | Functional build | Functional verify | Handoff | Released
last_verified_build: PASS | FAIL | not-run
last_verified_date: {YYYY-MM-DD}
---

# {AppName} — Status

## Where I am
<one paragraph>

## Next command to run
```
/<agent> <exact prompt>
```

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
<!-- Status detail lives in each checklist's "Requirements Status" table (the single
     source of truth). This log is just a dated index of verification passes. -->
| Date | Phase | Result | Status table |
|------|-------|--------|--------------|
| {YYYY-MM-DD} | UI verify | 14/14 Verified | docs/{AppName}-UI-Checklist.md#requirements-status |

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

# triage-and-fix

`*triage-and-fix {App} {evidence}` runs the owner's whole bug sequence in one go, in YOLO: compare every screen to its mockup, triage the reported bugs, log every root cause with its discovery cost, fix, log every fix with its cost, refresh the metrics, and end with one summary per step. The separate commands stay for when only one of them is wanted. Evidence is a folder of screenshots with an optional notes file, a written list, or nothing (then the screens comparison is the evidence).

First: `bash .tfcore/utils/tf-phase.sh start triage-and-fix {App}` prints the start time; keep it. `bash .tfcore/utils/tf-yolo.sh on --source triage-and-fix` unless YOLO is already on.

## Steps

1. Compare. `bash .tfcore/utils/tf-verify-list.sh {App} all`, `tf-verify-boot.sh start`, then `tf-verify-screens.sh --list … --base <url>` and `tf-mockup-parity.sh --base <url> --screen … --json-out tests/.artifacts/verify/parity.json` over every screen. Every screen that renders empty, looks broken or drifts from its mockup is an issue, added to the owner's evidence with its screenshot.
2. Triage. `.tfcore/tasks/triage-issues.md` steps 3 and 4 on the combined issue list, then `tf-triage.sh {App} close --started <the step-0 time> --cmd fix-issues`.
3. Fix. `.tfcore/tasks/fix-issues.md` steps 2 to 5 on the demoted rows (the builders, the build, the smoke, the verify, `tf-fix-close.sh`).
4. Metrics. Execute `.tfcore/tasks/metrics-report.md`.
5. Run the status gate (`.tfcore/tasks/_status-update-gate.md`) with `"cmd":"triage-and-fix"` and the rows touched. When this run is the last step of a goal, write the sentinel (`.tfcore/tasks/_yolo-mode.md`).
6. Summary, one short section per step: screens compared and what the comparison found; root causes found and logged, each with its miss id and discovery cost; fixes made and logged, each with its verdict and fix cost; rows re-verified by status; metrics refreshed, the report's path; the next command from the gate.

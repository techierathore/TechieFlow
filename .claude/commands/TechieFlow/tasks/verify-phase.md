# verify-phase

`*verify {scope} {App}` proves every checklist row in scope against the running application and writes the verdicts. Scope is `ui`, `functional`, `all` or a list of ids; a caller that chains this task passes its scope and nothing is asked. YOLO is its default mode. The application runs on this machine, never on a cloud host. This task never edits source, the BRD or the mockups. It writes tests under `tests/verify/`, evidence under `tests/.artifacts/verify/`, the ledger `docs/.last-verify.json`, and the checklist cells through the verdict script only: a `Verified` written by hand is refused by the hook.

First: `bash .tfcore/utils/tf-phase.sh start verify-phase {App}` prints the start time; keep it. Then `bash .tfcore/utils/tf-yolo.sh on --source verify` unless YOLO is already on.

## The seven checks

Applied to every row in this order; the first that fails is the row's verdict.

| Check | Question | Tool |
|---|---|---|
| build | does the application build and boot | `tf-verify-boot.sh` |
| acceptance | does the test carrying the row's id pass | `tf-verify-tests.sh` |
| render | does every control the mockup anchors show something, no header-only table, no blank page, no error | `tf-verify-screens.sh` |
| assets | did every stylesheet and script the screen declares arrive | `tf-assets.sh` |
| visual | nothing overlaps, nothing clipped or off-screen, no sideways scroll, a stylesheet loaded | `tf-verify-screens.sh` |
| mockup | does the built screen carry the structure its mockup draws | `tf-mockup-parity.sh` |
| speed | within the row's `perf-budget:` line, only when the row declares one | `tf-perf.sh`, `tf-perf-grade.sh` |

Standards has no script yet and is never listed as run. A row is `Verified` only when every check that ran passed. A check that could not run is absent from the record, never a pass: an unreachable head, a mockup the parity tool could not grade, an auth wall, a Debug build, a thin sample are all written down as "not measured", and the row is never `Verified` on that check's grounds.

## Read

The phase's checklist, UIDesign and `docs/mockups/` (`appPhase` in `core-config.yaml` names the phase); the UsageGuide's test users.

## Steps

1. `bash .tfcore/utils/tf-verify-list.sh {App} {scope}` prints the rows to grade with their acceptance line, screen, route, mockup and perf budget, the screens to drive, and the test users; it writes `tests/.artifacts/verify/list.json`. Every row in scope is graded whatever its status; only N/A is skipped, so a `Verified` row is re-confirmed and an old `Done` claim is tested. NOTHING means run the status gate and stop. A row without an acceptance line cannot be graded: fix the checklist first. A dialog is listed under its parent screen and checked there; never give a dialog a route so it can be tested.
2. `bash .tfcore/utils/tf-verify-env.sh` prints READY, or the one command the owner must run once.
3. `bash .tfcore/utils/tf-verify-boot.sh start` boots the head it finds (`--head` or `--project` when there are several) and prints BOOTED with a URL, or a CDP URL for an embedded-browser desktop head, which the browser tools attach to. A dependent service (database, API) is yours to start first, from its own configuration, in order. NONE `kind=build-error`: every row fails the build check; go to step 6. NONE `kind=host` or `kind=no-driver` (an Android, iOS or Mac head): go to step 6 as well; those rows are written "not verified" with the reason. Never a static-only pass, never "the owner should start it".
4. Tests. Every UI and functional row has one test whose title starts with its id, written from the acceptance line, black box, under `tests/verify/`; an NFR row without a screen has a unit test carrying its id in the test project, or is not observable. Reuse a test that exists. Fan out one test-writer sub-agent per screen group in one turn, each with its rows, their acceptance lines, the URL and the test user; a test writer touches no source. Sign in as a UsageGuide test user (`.tfcore/tasks/_smoke-test-policy.md`).
5. Run the checks, with `<url>` from step 3 and, on a signed-in app, the session cookie from the test login for the tools that take `--cookie`:
   - `bash .tfcore/utils/tf-verify-tests.sh --base <url>`
   - `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --base <url>` (or `--cdp <url>`; `--login-path /login --user … --password …` when the app has a sign-in page)
   - `bash .tfcore/utils/tf-assets.sh --base <url> --paths "<every screen route, comma-separated>" --json-out tests/.artifacts/verify/assets.json`
   - `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen <name>=<route> … --json-out tests/.artifacts/verify/parity.json` (one `--screen` per screen with a mockup; skip on a project with none)
   - for each row with a `perf-budget:` line: `bash .tfcore/utils/tf-perf.sh --base <url> --paths "<its screen's route>" --levels <its concurrency> --requests 24 --build-config <Release or Debug, as booted> --json-out tests/.artifacts/verify/perf/<REQ>.json`
   Open every failing screenshot under `tests/.artifacts/verify/screens/` and look at it before step 6.
6. `bash .tfcore/utils/tf-verify-verdict.sh {App} --apply --started <the step-0 time>` applies the seven checks in order, writes the ledger and rewrites the Status, % and Remarks cells of every graded row, and prints the verdict table. Then `bash .tfcore/utils/tf-verify-emit.sh {App} --started <the step-0 time>` appends the gate records, one miss per newly failing row, and this run's record.
7. `bash .tfcore/utils/tf-verify-boot.sh stop`.
8. Run the status gate (`.tfcore/tasks/_status-update-gate.md`); its run record is the one step 6 wrote. A head that could not be driven is named under "Known blockers". When this run is the last step of a goal, write the sentinel (`.tfcore/tasks/_yolo-mode.md`). When the verifier was chained by a build or a fix, that caller runs the gate.
9. Report: what was booted (head, rung, URL); rows by verdict; the first-failing-check counts; screens driven and screenshots; the parity coverage line (screens graded, failed, ungradeable, without a mockup); the speed lines only for rows that carry a budget; every not-verified row with its reason; the evidence folder; the next command from the gate.

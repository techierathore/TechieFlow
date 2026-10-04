# TechieFlow feedback — found while building Chatur

| | |
|---|---|
| App | Chatur |
| Upstream | TechieFlow |
| Updated | 2026-10-03 |

## Summary

7 entries: 0 open, 1 fixed upstream and waiting to be re-checked here (TF-007), 6 closed (TF-001 to TF-006).

TF-007 is fixed upstream; the TF-006 fix caused it. With the update, Start, Workbench, Prerequisites, Providers and Corrections pass mockup parity on this project's own data.

TF-006 was re-checked here on 2026-10-03: after the seed, neither table box reports a finding at either width. The three Repository rows still will not reach Verified on mockup parity, though. The rows themselves are paired with the mockup's sample rows by position, and the seeded rows come in a different order of process and hand check-ins than the mockup draws. The TechieFlow side tracks that as MISS-TechieFlow-20261003-02 (see the TF-006 reply).

## Entries

### TF-001 — A control marked as another screen state is still counted against the box around it

> ✅ **Closed 2026-10-02** — re-checked here: Ran tf-mockup-parity.sh on prerequisites=/prerequisites (no newer release, web head, 2026-10-02 14:5x): the 'icon on this-chatur > div[1]' finding is gone at 1280 and 390, and the Workbench 'icon on editor' finding is gone too. A side effect is filed as TF-005.

- **Severity:** major
- **Blocks:** yes — REQ-FN-011, 013, REQ-UI-017, 018 (Prerequisites) and the 34 Workbench rows cannot reach Verified
- **Repro:** `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen prerequisites=/prerequisites` against an app with no newer release
- **Expected:** the download icon inside the banner row marked `data-tf-state="newer-build"` is left out, as the tool's own help says
- **Actual:** the icon is reported on the parent box: `icon on this-chatur > div[1]: mockup carries an icon here; the app does not`. The same happens for `editor` on the Workbench, whose note is marked `data-tf-state="change-proposed"`
- **Encountered in:** `*build-phase Chatur`, chained verify, 2026-10-02
- **Workaround:** none; rows left Implemented with a `⚠ parity-state:` Remark
- **Suggested fix:** when counting icons for a box, skip every descendant inside an element carrying `data-tf-state`

### TF-002 — The mockup comparison grades an empty first view against a mockup full of sample data

> ✅ **Closed 2026-10-03** — re-checked here: 2026-10-03: tf-verify-list found tests/verify/seed/repository.sh and tf-verify-screens ran it before /repository (render OK, 136 anchors). Parity listed the mockup's data-tf-sample rows the app has no data for (commit-row-6, process-branch-row-3) under coverage.not_measured instead of as missing.

- **Severity:** major
- **Blocks:** yes — REQ-UI-042, 043, 044, REQ-FN-047, 048 (Repository) and the Workbench conversation rows cannot reach Verified
- **Repro:** boot a fresh web head, run `tf-mockup-parity.sh --screen repository=/repository` and `--screen main=/`
- **Expected:** a way to put the screen in the state the mockup draws before it is compared (a seed step per screen), or the sample-only parts graded as "not measured"
- **Actual:** icons that exist only on sample rows (process-branch rows, message avatars) are reported missing; with a run-branch commit seeded by hand the same Repository screen gives 0 findings
- **Encountered in:** `*build-phase Chatur`, chained verify, 2026-10-02
- **Workaround:** none; rows left Implemented with a `⚠ parity-state:` Remark
- **Suggested fix:** a per-screen `seed:` command in the UIDesign that the verifier runs before the comparison, and a "not measured" outcome when a finding sits only on sample data

### TF-003 — A screen whose route takes a value is never driven, so its rows are Verified without a screen check

> ✅ **Closed 2026-10-02** — re-checked here: Ran tf-verify-list.sh Chatur ui: Settings / providers, agents, corrections, measurements and appearance listed as separate screens with their own routes and mockups, a Mockup parity: line printed, no SKIP Settings. tf-verify-screens drove all five tabs; the verdict demoted the 10 Settings rows whose tab lacks mockup controls.

- **Severity:** major
- **Blocks:** no — six misses were logged (MISS-Chatur-20261002-03 to -08) and the run carried on
- **Repro:** `tf-verify-screens.sh --list tests/.artifacts/verify/list.json` prints `SKIP Settings (/settings/{tab}) — not driven`; with `--route-value tab=measurements` the one screen is checked against every Settings tab's controls at once
- **Expected:** each tab of `/settings/{tab}` is its own screen with its own mockup (`settings-agents.html` and so on), and a row whose screen was not driven is never Verified
- **Actual:** the Settings rows were Verified on their tests alone; driven per tab, six of seven tabs are missing controls their mockups draw
- **Encountered in:** `*build-phase Chatur`, chained verify, 2026-10-02
- **Workaround:** each tab driven by hand as `--screen settings-<tab>=/settings/<tab>`, results in `tests/.artifacts/verify/screens-settings-tabs.json`
- **Suggested fix:** split a parameterised route into one screen per mockup file in `tf-verify-list.sh`, and grade "screen not driven" as not verified

### TF-004 — The build list gives one screen's defect to two builders at once

> ✅ **Closed 2026-10-03** — re-checked here: 2026-10-03: tf-build-list.sh Chatur --prompts printed 'One builder for Settings (/settings/{page}): it carries a defect, so its UI and backend rows go to trblazeui together' and gave Settings one cluster.

- **Severity:** minor
- **Blocks:** no — the fix cycle used one builder per screen instead, and the run carried on
- **Repro:** `bash .tfcore/utils/tf-build-list.sh Chatur --prompts` with a mockup defect on the Workbench: clusters for the backend rows and the UI rows both carry the same defect line
- **Expected:** a defect on a screen goes to one builder
- **Actual:** both builders edited the same files in parallel, one left `EditorArea.razor` half-written, and every other builder's boot failed for about an hour
- **Encountered in:** `*build-phase Chatur`, 2026-10-02
- **Workaround:** fix cycle 1 used one builder per screen
- **Suggested fix:** when backend and UI clusters share a screen and a defect, merge them into one cluster

### TF-005 — Since the TF-001 fix, a list the app fills with real rows fails as "app carries an icon the mockup does not"

> ✅ **Closed 2026-10-03** — re-checked here: 2026-10-03: on a fresh web head, opened the Repository fixture, ran tests/verify/seed/repository.sh, then tf-mockup-parity.sh --screen repository=/repository: no 'app carries an icon the mockup does not' finding on history-table at 1280 or 390. The app's rows had to carry the mockup's commit-row-N anchors first (added to Repository.razor).

- **Severity:** major
- **Blocks:** yes — 29 screen rows on Register, Start, Workbench, Prerequisites and Repository cannot reach Verified
- **Repro:** `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen repository=/repository` after `tests/verify/seed/repository.sh` ran (a real run-branch check-in exists)
- **Expected:** the app's real rows are graded against the mockup's sample rows, as TF-002 says: "when the app does draw it, it is graded as before"
- **Actual:** `icon on history-table: app carries an icon the mockup does not`, with mockup text empty. The same on `recent-list`, `file-tree`, `files-panel`, `tools-table`, `process-branches-table`, `field-password`. Every sample row in these mockups is marked `data-tf-state="sample-data"`, and the TF-001 change now drops everything inside a `data-tf-state` box from the mockup's count
- **Encountered in:** `*verify ui Chatur`, 2026-10-02, after the TF-001 to TF-004 update
- **Workaround:** none; the rows stay Needs re-verify
- **Suggested fix:** leave a `data-tf-state="sample-data"` box out only when the app draws nothing in its place, the same rule as `data-tf-sample`, or treat `sample-data` as `data-tf-sample`

#### Detail

This also keeps TF-002 from being confirmed: with the seed in place the Repository screen draws the process row, and that row's icon is now the finding. Six mockups carry `data-tf-state="sample-data"` rows: main (16), repository (16), start (6), settings-providers (5), prerequisites (1), settings-corrections (1). The Register finding is the rules box marked `data-tf-state="password-typed"`, which the app shows before typing.

### TF-006 — A table still counts the app's row icons against a mockup count that has lost its sample-row icons

> ✅ **Closed 2026-10-03** — re-checked here: 2026-10-03 11:3x: fresh web head, Repository fixture opened by repository.spec.ts, tests/verify/seed/repository.sh seeded run/BRD-96-101 and run/BRD-88-95, then tf-mockup-parity.sh --screen repository=/repository: no finding on history-table or process-branches-table at 1280 or 390 (tests/.artifacts/verify/parity-tf006.json). Left: three commit-row-N > td[4] findings per width from row order, tracked upstream as MISS-TechieFlow-20261003-02.

- **Severity:** minor
- **Blocks:** yes — REQ-UI-042, 043, 044 (Repository) cannot reach Verified on mockup parity alone; every other check passes
- **Repro:** run `tests/verify/seed/repository.sh` (two run-branch check-ins), then `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen repository=/repository`
- **Expected:** with the app's rows anchored like the mockup's sample rows (`commit-row-N`, `process-branch-row-N`), the icons are graded row by row and the table box around them adds no finding of its own
- **Actual:** the rows are compared one by one, and `history-table` and `process-branches-table` still report `app carries an icon the mockup does not` at 1280 and 390. The finding's mockup text holds only part of the sample rows
- **Encountered in:** `*verify ui Chatur` and the fix cycle, 2026-10-03, after the TF-005 update
- **Workaround:** none; rows left with a `⚠ parity-state:` Remark
- **Suggested fix:** when a box's children are sample rows that were matched to app rows, leave their icons out of the box's own count on both sides, or count them on both sides

#### Detail

On a fresh fixture with one seeded check-in the `history-table` box finding did not appear (this is what closed TF-005). It comes back once the app draws more rows than the mockup's first sample rows hold, or a different mix of process and owner rows. Evidence: `tests/.artifacts/verify/parity-fix-repo.json`.

### TF-007 — Since the TF-006 fix, a list whose sample rows are named after sample data fails as "app carries an icon the mockup does not"

- **Severity:** major
- **Blocks:** yes — 55 screen rows on Start, Workbench, Prerequisites, Providers and Corrections cannot reach Verified; every other check passes
- **Repro:** `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen start=/start?all=1` with any real projects listed
- **Expected:** the app's real rows stand in for the mockup's sample rows; when they cannot be paired, both sides' row icons are left out of the list box, as on 2026-10-03 at 04:42 and 06:38, when Start passed with 0 findings
- **Actual:** `recent-list: app carries an icon the mockup does not` at 1280 and 390. The mockup's rows (`recent-tflens`, `recent-astrolyfe` …) are listed as not measured and their icons dropped, while the app's rows, named after real projects, keep theirs. The same on `file-tree`, `tools-table`, `providers-table`, `corrections-table`
- **Encountered in:** `*verify all Chatur`, 2026-10-03 11:28, after the TF-006 update; Start's code did not change in between
- **Workaround:** none; the rows stay Needs re-verify
- **Suggested fix:** when a list box's sample rows are not measured, leave out the app's rows in their place from the box's count too, the way TF-006 does for anchored rows

## Replies from TechieFlow

### Resolution status (TechieFlow team, 2026-10-02)

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream. `tf-mockup-parity` leaves out the icons, badges and text inside a box marked `data-tf-state` (or `data-state-testid`) when it counts the box around it. | `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen prerequisites=/prerequisites` against an app with no newer release: no `icon on this-chatur > div[1]` finding. |
| TF-002 | Fixed upstream, two ways. (1) A screen gets a seed: `tests/verify/seed/<mockup name>.sh` (for example `repository.sh`, `main.sh`). `tf-verify-list` finds it, and `tf-verify-screens` runs it once with `$TF_BASE` set, before it opens the screen. A seed that fails is that screen's finding. (2) In the mockup, mark each sample row or sample message with `data-tf-sample`. When the app draws nothing in its place, that box is reported under `coverage.not_measured`, not as missing, and its icons are taken off the boxes around it. When the app does draw it, it is graded as before. | Write `tests/verify/seed/repository.sh` (it makes a run-branch commit) and add `data-tf-sample` to the sample rows in `repository.html` and the sample messages in `main.html`. Then run `*verify ui Chatur`. Repository and Workbench should have no finding about a sample-only icon. |
| TF-003 | Fixed upstream. `tf-verify-list` makes a route with one `{value}` whose UIDesign entry links one mockup per value into one screen per mockup: `Settings / agents` at `/settings/agents` with `settings-agents.html`, and so on. Each row goes to the tab whose mockup it names. Step 1 also prints a ready `Mockup parity:` line. `tf-verify-verdict` no longer passes a row whose screen was not driven, even when its test passed: the row is NOT-DRIVEN. | `bash .tfcore/utils/tf-verify-list.sh Chatur ui` lists `Settings / providers (/settings/providers)` through `Settings / appearance`, and no `SKIP Settings`. |
| TF-004 | Fixed upstream. `tf-build-list` gives every row on a page to one cluster when any of that page's rows carries a defect. That cluster goes to the UI builder when a UI row has the defect. A page with no defect still splits by builder. | `bash .tfcore/utils/tf-build-list.sh Chatur --prompts` with a Workbench defect prints `One builder for Workbench …` and one Workbench cluster. |
| TF-005 | Fixed upstream; the TF-001 fix caused it. `tf-mockup-parity` now reads `data-tf-state="sample-data"` as sample data, the `data-tf-sample` rule, not as another state of the screen. When the app draws rows in its place, they are compared with the mockup's sample rows, icons included. When the app draws none, the box is listed under `coverage.not_measured`. Any other `data-tf-state` value keeps the TF-001 rule. Proved on this project's own six mockups: with the sample rows shown as an app would draw them, the old script gives your seven `app carries an icon the mockup does not` findings (`history-table`, `recent-list`, `files-panel`, `tools-table` …) and the new one passes all six. Not fixed, because it is not a framework fault: Register's rules box is marked `data-tf-state="password-typed"`, but the app shows it before anything is typed. Either the mockup should drop that mark or the app should hide the box until typing starts. That choice is yours. | After the framework update, run `tests/verify/seed/repository.sh`, then `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen repository=/repository`: no `app carries an icon the mockup does not` finding on `history-table`. Then run `*verify ui Chatur`. |

### Resolution status (TechieFlow team, 2026-10-03)

| ID | Fix | Check it here |
|---|---|---|
| TF-006 | Fixed upstream. `tf-mockup-parity` now leaves the icons of the mockup's sample rows (`commit-row-N`, `process-branch-row-N`) out of every box around them, in the mockup and in the app. It also leaves out app rows with more of the same anchor (for example `commit-row-7` when the mockup draws six). Those rows are still compared one by one. An icon that belongs to the box itself, outside its rows, is still counted. Proved on this project's Repository screen, signed in, after `tests/verify/seed/repository.sh`: the old script reports `process-branches-table: app carries an icon the mockup does not` at 1280 and 390, and the new one reports neither. **Not fixed, and it still blocks REQ-UI-042 to 044:** five `commit-row-N > td[4]` findings at each width. Row N of the app is compared with row N of the mockup, and the mockup's rows 3 and 5 are process check-ins where the seeded app's rows 1, 2 and 6 are. That is the order of the data, not the design. It is logged upstream as MISS-TechieFlow-20261003-02, a framework fault. Until it is fixed, a seed that makes the check-ins in the mockup's order (hand, hand, process, hand, process, hand) clears it. | After the framework update, run `tests/verify/seed/repository.sh`, then `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen repository=/repository`: no finding on `history-table` or `process-branches-table` at either width. |

### Resolution status (TechieFlow team, 2026-10-03, TF-007)

| ID | Fix | Check it here |
|---|---|---|
| TF-007 | Fixed upstream; the TF-006 fix caused it, and an older rule did the same for rows without their own anchor. When the mockup's sample rows in a list box are not measured, `tf-mockup-parity` now takes their icons off every box around them. It does the same on the app's side for the rows the app draws in their place: what the mockup does not have under that box and is the same kind of element (a `tbody` for a `tbody`), or, when there is none of that kind, the box's own children and anchors the mockup lacks, such as the `project-scroll` area holding your `project-N` items. A button or link inside a row keeps its own icon, and an icon that belongs to the box itself is still counted. Proved on this project: a web head with the data of your 11:28 verify run, signed in as the YOLO test user, all twelve screens with the old and the new script. Start, Workbench (`main`), Prerequisites, Providers and Corrections go from FAIL to PASS, and no screen gains a finding. Still failing, and not TF-007: `auto-routing-switch` border (Routing), `misses-refused` and `sessions-refused` colour (Measurements), both design differences for you to settle; and the Repository row order (MISS-TechieFlow-20261003-02, ours). | After the framework update, run `*verify ui Chatur`. Start, Workbench, Prerequisites, Providers and Corrections have no `app carries an icon the mockup does not` finding on `recent-list`, `file-tree`, `tools-table`, `providers-table` or `corrections-table`. |

# TechieFlow feedback — found while building Chatur

| | |
|---|---|
| App | Chatur |
| Upstream | TechieFlow |
| Updated | 2026-11-10, later (TF-023, TF-024 and TF-025 fixed upstream, in `.tfcore/` from the framework update of the same day) · 2026-11-10 (TF-023 to TF-025 filed; TF-022 re-checked and closed) · 2026-11-10 (five stale `Status: open` lines corrected: TF-008, TF-009, TF-018, TF-019, TF-021; no new fix) · 2026-11-05 (TF-022 fixed upstream, ships in TechieFlow v1.3.0) |

## Summary

25 entries: 0 open, 13 fixed upstream and not yet re-checked (TF-008, TF-010, TF-013 to TF-019, TF-021, TF-023 to TF-025), 12 closed (TF-001 to TF-007, TF-009, TF-011, TF-012, TF-020, TF-022). 0 blocking.

TF-007 was re-checked here on 2026-10-03: no list box on Start, Workbench, Prerequisites, Providers or Corrections reports "app carries an icon the mockup does not" at either width, and Start, Prerequisites, Providers and Corrections now pass mockup parity outright.

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

> ✅ **Closed 2026-10-03** — re-checked here: 2026-10-03 15:2x, *verify ui Chatur on a fresh web head (App Manager restarted on 32769 after it went down mid-run): tf-mockup-parity.sh with the verify list's 11 screens gave no 'app carries an icon the mockup does not' finding on recent-list (start), file-tree (main), tools-table (prerequisites), providers-table (settings-providers) or corrections-table (settings-corrections) at 1280 or 390. Start, Prerequisites, Providers and Corrections now pass parity with 0 findings (tests/.artifacts/verify/parity.json).

- **Severity:** major
- **Blocks:** yes — 55 screen rows on Start, Workbench, Prerequisites, Providers and Corrections cannot reach Verified; every other check passes
- **Repro:** `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen start=/start?all=1` with any real projects listed
- **Expected:** the app's real rows stand in for the mockup's sample rows; when they cannot be paired, both sides' row icons are left out of the list box, as on 2026-10-03 at 04:42 and 06:38, when Start passed with 0 findings
- **Actual:** `recent-list: app carries an icon the mockup does not` at 1280 and 390. The mockup's rows (`recent-tflens`, `recent-astrolyfe` …) are listed as not measured and their icons dropped, while the app's rows, named after real projects, keep theirs. The same on `file-tree`, `tools-table`, `providers-table`, `corrections-table`
- **Encountered in:** `*verify all Chatur`, 2026-10-03 11:28, after the TF-006 update; Start's code did not change in between
- **Workaround:** none; the rows stay Needs re-verify
- **Suggested fix:** when a list box's sample rows are not measured, leave out the app's rows in their place from the box's count too, the way TF-006 does for anchored rows

### TF-008 — A screen whose route takes a value is graded Verified with its mockup comparison silently left out

- **Status:** fixed upstream 2026-10-08, already in this project's `.tfcore/` (its regression case passes against that copy, 2026-11-10); not yet re-checked here. Filed 2026-10-07.
- **Severity:** major
- **Blocks:** no — giving the comparison each screen's checklist name (`--screen "Process run=/processes/6/run"` with `--list`) makes it count, and Chatur now runs it that way; the danger is a false Verified for anyone who does not.
- **Repro:** `tf-mockup-parity.sh --screen process-run=/processes/6/run --screen agent-workspace=/workspace/verifier …`, then `tf-verify-verdict.sh Chatur --apply`, with the verify list's routes `/processes/{id}/run` and `/workspace/{agent}`
- **Expected:** the verdict matches a filled-in route to its `{id}` pattern, or refuses to grade a screen row whose comparison it cannot find
- **Actual:** 2026-10-07 13:01 run: both screens' comparisons said FAIL (16 and 2 findings), yet all 11 of their rows were written Verified, because the verdict looks parity up by screen name or by the literal route and neither matched; no note was written. Re-run keyed by name, all 11 went to Needs re-verify.
- **Encountered in:** `*verify all Chatur`, phase 2, rows REQ-FN-052..055, 058..060, REQ-UI-047, 048, 053, 054
- **Workaround:** pass each screen to the comparison by its checklist name together with `--list`
- **Suggested fix:** in `tf-verify-verdict.py`, match a parity route against the row's route pattern (`{…}` = one path segment), and write "mockup-parity not found" as a failing check for a driven screen row with no comparison

### TF-009 — A progress bar is always reported empty by the screen check

> ✅ **Closed 2026-10-09** — re-checked here: 2026-10-09 06:05 verify of phase 3: tf-verify-screens.sh on End-to-end run (/auto) with seed auto-run.sh gave render OK at 1280 and 390 (no progress-bar empty finding); the bar is TrBlazeUI Progress (role=progressbar, aria-valuenow). All 10 End-to-end run rows Verified.

- **Status:** fixed upstream 2026-10-09 and closed here the same day (the mark above). Filed 2026-10-08.
- **Severity:** major
- **Blocks:** yes — all 8 End-to-end run rows (REQ-FN-061..066, REQ-UI-055, REQ-UI-056) are written RENDER-FAIL and cannot reach Verified while the bar is drawn correctly.
- **Repro:** `tf-verify-screens.sh --list tests/.artifacts/verify/list.json …` on `/auto` with a run going (seed `tests/verify/seed/auto-run.sh`); the mockup's `progress-bar` is a track `div` holding a fill `div`, and the app's is TrBlazeUI `Progress` (`role="progressbar"`, `aria-valuenow`) at 50%.
- **Expected:** a progress bar counts as filled, as the mockup's own bar does; e.g. an element with `role="progressbar"` and an `aria-valuenow`, or a box with a child of non-zero width, is not blank.
- **Actual:** `anchored control "progress-bar" (div) is empty` at 1280 and 390 — `tf-verify-screens.mjs` line ~335 counts a control filled only for text, a form field, an image/svg/canvas, a button or a link.
- **Encountered in:** `*verify all Chatur`, phase 3, 2026-10-08 03:30
- **Workaround:** none; adding text the mockup does not draw would be a fake.
- **Suggested fix:** in `tf-verify-screens.mjs`, treat `[role=progressbar][aria-valuenow]`, `progress`, `meter`, and a box whose child has a measured non-zero width, as filled.

### TF-010 — On a Mac, the zoom keys only reach the last window opened

- **Status:** fixed upstream 2026-10-12, filed 2026-10-11
- **Severity:** minor
- **Blocks:** no — Chatur copied `blazor-zoom.cs.txt` unchanged as §9b says, and wired it on all three of its windows; Windows is unaffected (each WebView2 gets its own script). The work carried on.
- **Repro:** `.tfcore/standards/blazor-zoom.cs.txt`, Mac Catalyst branch: `Attach` stores the web view in one static field (`objWebView`), and `ZoomBy`/`Reset` set `PageZoom` on that field only. Chatur has three windows, each with its own `BlazorWebView` (start, main, secondary), so each `Attach` replaces the one before.
- **Expected:** Cmd+=, Cmd+- and Cmd+0 zoom the window that has focus (or every open window, since the level is one saved value).
- **Actual:** By reading the code (not yet run on a Mac): they zoom whichever window was opened last; the others keep the level they opened at until they are reopened.
- **Encountered in:** wiring §9b into Chatur, `*build-phase Chatur`, 2026-10-11
- **Workaround:** none; the file is to be copied, not rewritten.
- **Suggested fix:** keep a list of weak references to every attached `WKWebView` and apply the level to all of them (dropping the dead ones), or zoom the key window's web view.

### TF-011 — Verify passes screens that are placeholders: no gate opens a menu or follows the way in

> ✅ **Closed 2026-10-19** — re-checked here: 2026-10-19 *verify all Chatur: tf-verify-screens and tf-mockup-parity opened every menu on the 12 screens of phase 1 and the 7 of phases 2 and 3 (tests/.artifacts/verify/screens-p1.json, parity-p1.json). Workbench reports File, Edit and View items; no 'Nothing to do yet' anywhere. The findings are the three kinds the reply named: Account > Licence, Project > Build/Run/Stop and the run targets, Help > Send feedback, Appearance > Follow the machine missing; and the unmarked sample choices in the branch, history and model drop-downs. 53 phase-1 rows and 19 phase-3 rows went to Needs re-verify on them.

- **Status:** fixed upstream 2026-10-14 (ships in v1.2.0), filed 2026-10-13
- **Severity:** critical
- **Blocks:** no — Chatur's own tests now click every menu item; the gates are unchanged.
- **Repro:** the 12 Oct nightly, with phases 1 to 3 Verified. File, Edit and View showed only "Nothing to do yet" (`MenuBar.razor` lines 48, 54, 60). Settings, Prerequisites and Repository opened nothing in the desktop app, so the chat could never answer, yet REQ-FN-025 was Verified. 51 rows were reopened.
- **Expected:** a placeholder screen or menu fails verify, and a screen is reached through the menu item that opens it.
- **Actual:** `tf-verify-screens` and `tf-mockup-parity` load each route directly and compare the closed page with its mockup. A closed menu bar matches, and a route that loads passes even when no click reaches it.
- **Encountered in:** `*fix-issues Chatur docs/screenshots/NightlyBuildIssues`, 2026-10-13
- **Workaround:** hand-written menu tests (REQ-UI-073, REQ-FN-106) on both heads.
- **Suggested fix:** in the visual and mockup-parity gates, open every menu and drop-down the mockup marks `data-tf-state="popup-open"`, click every item, and fail on:
  - a missing item;
  - a disabled item the mockup draws enabled;
  - placeholder text from a deny list ("Nothing to do yet", "Coming soon", "Not built yet", "TODO");
  - an item with no effect.

  On a desktop head, reach each screen through its menu item, and mark it UNREACHABLE when no click gets there. Also: `tf-triage.sh new` should count the next free id across every checklist; it gave REQ-UI-055 twice.

### TF-012 — Verify counts a row as tested when its id appears in another test's sample data

> ✅ **Closed 2026-10-19** — re-checked here: 2026-10-19 *verify all Chatur: tf-verify-tests merged 14 parts (tests/.artifacts/verify/tests.json). REQ-FN-051 passes on its own test 'REQ-FN-051 a process names the project own documents and leaves the folder as it was'; REQ-FN-053 and REQ-FN-055 pass on process-run-progress.spec.ts and their unit tests. The five sample ids of the ResultParser theory (REQ-FN-901, 951, 953, 955, REQ-UI-948) are printed as NO TEST and credited to no row.

- **Status:** fixed upstream 2026-10-14 (ships in v1.2.0), filed 2026-10-13
- **Severity:** critical
- **Blocks:** no. Chatur now has real tests for the two rows, and none of its other rows was passed this way.
- **Repro:** the xUnit theory `[Theory(DisplayName = "REQ-UI-048 requirement ids are found in test names")]` in `tests/unit/Chatur.Tests/ProcessRuns/ResultParserTests.cs:63` takes sample test names as `InlineData`, and two of them contain `REQ-FN-053` and `REQ-FN-055`. The reported name of each case then reads `REQ-UI-048 requirement ids are found in test names(aName: "REQ-FN-053 …")`.
- **Expected:** a test proves only the ids at the start of its own name, before any parameter list.
- **Actual:** the 2026-10-07 verify marked REQ-FN-053 ("It waits for the owner") and REQ-FN-055 ("Carry on later") Verified on that test. Neither had ever been tested.
- **Encountered in:** checking phase 2 by hand after the 12 Oct nightly, 2026-10-13
- **Workaround:** Chatur added `tests/verify/process-run-progress.spec.ts`, which really tests REQ-FN-052, REQ-FN-053 and REQ-FN-055, the last one across a real restart.
- **Suggested fix:** in `tf-verify-tests`, read ids only from the leading run of `REQ-…` tokens of a test's name, and drop everything from the first `(` of a theory case's arguments. Also flag a row whose only passing test's name is about another row.

### TF-013 — An all-phase verify turns the Not Started rows of an unbuilt phase into Needs re-verify

- **Status:** fixed upstream 2026-10-21, ships in TechieFlow v1.2.1; not yet re-checked here (re-checked upstream 2026-10-29: already in this project's `.tfcore/`, which is v1.2.1).
- **Severity:** minor
- **Blocks:** no — the rows are listed under Known blockers in PROJECT-STATUS as not built, and the work carried on.
- **Repro:** `bash .tfcore/utils/tf-verify-list.sh Chatur all --phase 4` on a phase whose five routes do not exist yet, then `tf-verify-screens.sh` (every route answers 404) and `tf-verify-verdict.sh Chatur --apply`.
- **Expected:** a row that was Not Started and whose screen does not exist stays Not Started, with a Remark saying the route answered 404; nothing was built, so there is nothing to re-verify.
- **Actual:** all 19 rows of `docs/Chatur-P4-Checklist.md` are rewritten to Needs re-verify (first failing check: render, "/feedback answered HTTP 404"), and 19 misses are recorded against work nobody has started.
- **Encountered in:** `*verify all Chatur --phase all`, 2026-10-19
- **Workaround:** none in the checklist; the status page says the phase is unbuilt.
- **Suggested fix:** in `tf-verify-verdict`, keep Not Started when the row's prior status was Not Started and the only failing check is a route that answered 404 or was never built; write the reason in the Remark and emit no miss.
- **Reply (TechieFlow team, 2026-10-29):** Checked again, as asked: the fix is in v1.2.1, and this project's `.tfcore/` is v1.2.1 (`tf-verify-verdict.py` matches the v1.2.1 file). Case `ch_013` still holds. Nothing new ships for it. The 19 rows of `docs/Chatur-P4-Checklist.md` still read Needs re-verify from the 2026-10-19 run; one verify puts them back. **Check it here:** `/TechieFlow:agents:verifier *verify all Chatur --phase 4`. The 19 rows go back to Not Started with the 404 reason, and no miss is written.

### TF-014 — The database guard blocks any command that contains the word "dbup", even when nothing runs a migration

- **Status:** fixed upstream 2026-10-21, ships in TechieFlow v1.2.1; not yet re-checked here (re-checked upstream 2026-10-29: already in this project's `.tfcore/`, which is v1.2.1).
- **Severity:** minor
- **Blocks:** no — the sentence was passed to `tf-log-miss.sh` from a file (`--what "$(cat <file>)"`), and the search was done under a `fix-issues` marker; the work carried on.
- **Repro:** with the marker at `log-miss`, run `bash .tfcore/utils/tf-log-miss.sh Chatur --what "the DbUp console logger throws …" --sort weak-check --req REQ-NFR-004`, or a read-only search such as `grep -n -i "dbup" docs/Chatur-Checklist.md`.
- **Expected:** the guard blocks only a command that runs a migration; a word inside a quoted argument or a search pattern is a mention, as the guard's own header says ("What counts is what RUNS, not what a command mentions").
- **Actual:** `BLOCKED by TechieFlow policy: a database migration runs only from *build-phase, *fix-issues or *triage-and-fix, and the marker says log-miss`. `MIGRATORS` in `.tfcore/hooks/guard-db.sh` line 47 holds a bare `\bdbup\b`, and line 174 searches the whole command text, so `*log-miss` could not take a sentence naming DbUp. The same command form blocked three searches of this repository.
- **Encountered in:** `*log-miss Chatur` for MISS-Chatur-20261020-01, 2026-10-20
- **Workaround:** pass the sentence from a file; search for the code without the word.
- **Suggested fix:** match `dbup` only as the command word of a segment (the `SEG` prefix `CLIENT_AT` already uses), and drop quoted arguments and `grep`/`rg` patterns before the `MIGRATORS` search.
- **Reply (TechieFlow team, 2026-10-29):** Checked again on this project's own hook (v1.2.1), with the marker at `amend-docs`: `grep -n -i "dbup" docs/Chatur-Checklist.md` and your `tf-log-miss.sh … --what "the DbUp console logger throws"` both pass (exit 0); `dotnet run --project src/ChaturDb` is still refused (exit 2). Case `ch_014` holds. Nothing new ships for it. **Check it here:** run your two repro commands outside a build or fix: neither is blocked.

### TF-015 — `tf-verify-verdict.py` crashes when the first graded screen is unreachable on a Blazor Hybrid Mac head

- **Status:** fixed upstream 2026-10-29, ships in TechieFlow v1.2.2; not yet re-checked here.
- **Severity:** major
- **Blocks:** yes — phases 2, 3 and 4 of an all-phase Mac Catalyst verify cannot produce a verdict when the first screen in the checklist is unreachable (the app is stuck on Sign in)
- **Repro:** boot the Mac Catalyst head (`--head maccatalyst`) with a Blazor Hybrid app that opens on Sign in. Run `bash .tfcore/utils/tf-verify-list.sh Chatur all --phase 2`, then `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --appium http://localhost:4723` (screens report UNREACHABLE), then `bash .tfcore/utils/tf-verify-verdict.sh Chatur --apply --started <ts>`.
- **Expected:** the verdict grades every row, marking unreachable-screen rows as NOT-DRIVEN or RENDER-FAIL, and writes the checklist.
- **Actual:** Python raises `UnboundLocalError: cannot access local variable 'bad' where it is not associated with a value` at line 215 of `.tfcore/utils/tf-verify-verdict.py`. The variable `bad` is defined only in the `else` branch of the render check (line 209), but line 215 references it unconditionally when `anchors_not_measured` is true — which is always true for a web-view Mac head.
- **Encountered in:** `*verify-phase Chatur --scope all --head maccatalyst`, 2026-10-21
- **Workaround:** none without editing `.tfcore/`; the phase-2..4 checklists remain ungraded.
- **Suggested fix:** initialize `bad = []` before the `if scr.get("render") == "UNREACHABLE"` branch, or move the `anchors_not_measured` note inside the `else` branch.
- **Reply (TechieFlow team, 2026-10-29):** Reworked as you asked. The 2026-10-21 fix still holds: `bad` is set before the branch, so nothing crashes. What changed: on a Mac web-view head an unreachable screen's rows were RENDER-FAIL; they are now written as not driven (status kept, the Remark says not measured and why), the checklist is still written, and every other row is graded. A web head's unreachable screen still fails. Regression case `ch_015`, changed to the new rule; it fails on v1.2.1. Same change as TF-016. **Check it here:** on the Mac, `*verify all Chatur --phase all --head maccatalyst`: phases 2 to 4 get a verdict table, and no row behind Sign in is RENDER-FAIL.

### TF-016 — The Mac Catalyst head cannot sign in, so only the Sign in screen is measurable

- **Status:** fixed upstream 2026-10-29, ships in TechieFlow v1.2.2; not yet re-checked here.
- **Severity:** major
- **Blocks:** no — the web head graded the rows (2026-10-24). The Mac window stays not measured.
- **Repro:** `tf-verify-boot.sh start --head maccatalyst`, then `tf-verify-screens.sh --list tests/.artifacts/verify/list.json --appium http://localhost:4723 --login-path /sign-in --user <owner> --password <pw>`. Dump the element tree with `tf-appium.mjs` (`s.source()`).
- **Expected:** the head signs in, or reports every screen behind the sign-in as not measured, and no row is failed for it.
- **Actual:** Appium mac2 shows the BlazorWebView's content as one empty element (an empty scroll view), so no field or button inside it can be found. The maccatalyst head has no sign-in step, and `--login-path`, `--user` and `--password` are ignored (`login: null` in `tf-verify-native.mjs`). Only Sign in is measurable: 1 screen OK, 11 `UNREACHABLE`. Typing by screen position would be global input, which hard rule 4 forbids, so it was not tried.
- **Encountered in:** `*verify all Chatur --phase 1 --head maccatalyst`, 2026-10-24
- **Workaround:** the 73 rows that were not Verified were graded on the web head. The 25 Verified rows were left as they were. The verdict was not applied from the Mac run, because unreachable screens would have failed them.
- **Suggested fix:** when a head cannot sign in, write every screen behind the sign-in as not measured, never as a failed render, and say so in the Remark. Add a sign-in step for a web view head if it can be driven by the app's own window.
- **Reply (TechieFlow team, 2026-10-29):** Fixed with one change, shared with Sevak TF-014. **Sign-in step:** with `--user` and `--password`, the Mac head now looks for the user and password fields inside the app's own window, types into them the way a Blazor Hybrid form takes text (`s.type`, Lekhak TF-026), and clicks "Sign in" or "Log in". Nothing is typed by screen position. **Where it cannot:** a web view that shows Appium one empty element, or controls with no label, has no field to find. The head then prints `LOGIN not driven — the Mac head cannot sign in: Appium sees the web view as one empty element …`, writes that to `screens.json` (`login`), and marks every screen it could not reach `NOT-MEASURED`, never `UNREACHABLE`. The verdict grades those rows as not driven: the status is kept, the Remark says `not measured — … (grade it on the web or Windows head)`, and no gate record or miss is written. A web view the head can see into (Lekhak's) is unchanged: a screen no link reaches is still UNREACHABLE. Proved on a stand-in Appium that serves saved element trees (`tests/maccatalyst/fake-appium.mjs`), with your shape and with a sign-in form the head can see. **Not run on a real Mac yet.** Regression cases `ch_015`, `ch_016`, `sv_014`. Miss `MISS-TechieFlow-20261029-02`. On this app the web view is opaque, so the Mac head will report the sign-in as not driven and the 11 screens behind it as not measured. Signing in on the Mac needs the web view's content to be visible to Appium. **Check it here:** on the Mac, `/TechieFlow:agents:verifier *verify all Chatur --phase 1 --head maccatalyst`. Sign in is graded; the screens behind it print `NOT … not measured`, and no row fails on them.

### TF-017 — The verdict writes Verified on a row whose every test was skipped

- **Status:** fixed upstream 2026-10-29, ships in TechieFlow v1.2.2; not yet re-checked here.
- **Severity:** critical
- **Blocks:** yes — REQ-FN-106 (Settings and the other pages open from the main window) reads `Verified` at 100% in `docs/Chatur-P3-Checklist.md`, while its own Remark says "not verified — every test named REQ-FN-106 was skipped; acceptance not measured".
- **Repro:** `bash .tfcore/utils/tf-verify-verdict.sh Chatur --apply --started <ts>` on phase 3, where the only tests naming REQ-FN-106 are skipped (10 skipped, none ran). The verdict table prints `REQ-FN-106 | NOT-TESTED | - | Verified`.
- **Expected:** a row is `Verified` only when every check that ran passed. A row with no test that ran is not Verified, and its Status stays at its previous value or goes to Needs re-verify.
- **Actual:** the verdict's own table shows `NOT-TESTED` as the verdict, and the Status cell is written `Verified` with a Remark that says not verified.
- **Encountered in:** `*build-phase Chatur` chained verify, phase 3, 2026-10-25
- **Workaround:** none; the Status cell was left as the verdict script wrote it. The checklist is not hand-edited because the verdict script owns those cells.
- **Suggested fix:** in `tf-verify-verdict.py`, write the Status from the verdict, and treat NOT-TESTED as a failed check for the row's Status, not as a pass.
- **Reply (TechieFlow team, 2026-10-29):** Fixed in `tf-verify-verdict.py`. A row this run could not measure (every test skipped, no test ran, or its screen was not driven) is never written Verified on that run's word. It keeps Verified only when an earlier PASS is on record: its Remark says `verify: PASS`, or the ledger's last verdict for it is PASS. The Remark then names it, for example `not measured — every test named REQ-FN-106 was skipped; Verified on 2026-10-19 stands, not re-measured`, and the next run finds the date there. With no earlier PASS on record the row goes to Needs re-verify at 75%. The Remark word for these rows is now "not measured", never "not verified" beside a Verified status. Regression case `ch_017`. Miss `MISS-TechieFlow-20261029-05`. **For REQ-FN-106 here:** its Remark reads `2026-10-28 verify: not verified — no test named REQ-FN-106 ran` and the ledger's last verdict is NOT-TESTED, so its 2026-10-19 PASS is no longer on record. The next verify of phase 3 writes it Needs re-verify, until a test named for it runs and passes. **Check it here:** `/TechieFlow:agents:verifier *verify functional Chatur --phase 3`. REQ-FN-106 reads Needs re-verify with the reason, not Verified.

### TF-018 — Verify on WSL cannot boot the head, so verdicts are written without a boot record

- **Status:** fixed upstream 2026-11-01, already in this project's `.tfcore/` (its regression case passes against that copy, 2026-11-10); not yet re-checked here. Filed 2026-10-25.
- **Severity:** major
- **Blocks:** yes — every verdict written from this machine on 2026-10-25 came from a head the tooling did not boot. The verdict header prints `booted: not booted`, and rows whose checks need the boot record fail with `ENOENT '/proc/undefined/cmdline'` (REQ-FN-055, REQ-FN-061).
- **Repro:** `bash .tfcore/utils/tf-verify-boot.sh start` on WSL with the published harness on `http://localhost:5280`. It prints `NONE head=web kind=host reason=the published copy … did not answer on http://localhost:5280/ within 120 s although its log says it is listening`. The log shows `Application started`.
- **Expected:** the boot step reaches the published copy on WSL, or it runs the WSL copy when the Windows-side copy is unreachable, and writes a boot record the verdict can use.
- **Actual:** the boot script chooses its runner from the build rung (`via cmd.exe`), and no environment switch forces the WSL runner. The Windows-side copy never answers from WSL. A head started by hand has no pid record, so the process checks read `/proc/undefined`.
- **Encountered in:** `*build-phase Chatur` chained verify, phase 3, 2026-10-25
- **Workaround:** the published harness was started by hand under WSL dotnet (`~/.dotnet/dotnet Chatur.WebHarness.dll --urls http://localhost:5280`) and stopped by hand afterwards. Its verdicts are recorded as "not booted".
- **Suggested fix:** an environment variable (for example `TF_BOOT_RUNNER=wsl`) that forces the WSL runner, and a fallback to it when the cmd.exe copy does not answer within the wait. Also record the pid of a hand-started head so the process checks can read it.
- **Seen again 2026-10-29, another form (Blocks: no, the workaround worked):** this time the cmd.exe copy did answer from WSL, so the boot kept it. The tests run in WSL and type WSL fixture paths (`/mnt/c/…/fixtures/workbench-a`) into Project folders, and a Windows process cannot read them: the project never appears in Open recent, and every spec that opens a fixture project fails (14 phase-3 rows and the phase-1 workbench-files rows). The fix is the same switch: when the tests run in WSL, run the web harness in WSL too. Workaround used: stop the cmd.exe copy, start the same published copy with `~/.dotnet/dotnet <absolute path>/Chatur.WebHarness.dll --contentRoot … --webroot …` on a fresh `harness-data`, and write its pid into `boot-5280.json`.
- **Also seen 2026-10-29 (Blocks: no):** `tf-verify-tests.sh --merge` with no file arguments runs the whole suite instead of refusing. And `tf-verify-boot.sh start --head windows` boots the desktop head on the owner's real database (`%LOCALAPPDATA%\Techie Rathore\com.techierathore.chatur\Data\chatur.db`): desktop-head.spec.ts sent a test message in the owner's real project chat and changed its model picker. The desktop head should get its own data folder for tests.

### TF-019 — The screen check's default sign-in path is /login, but this app signs in at /sign-in

- **Status:** fixed upstream 2026-11-01, already in this project's `.tfcore/` (its regression case passes against that copy, 2026-11-10); not yet re-checked here. Filed 2026-10-25.
- **Severity:** minor
- **Blocks:** no — passing `--login-path /sign-in` by hand works, and the screens were then driven.
- **Repro:** `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --base http://localhost:5280 --login-path /login --user chatur-owner@techierathore.com`, against an app whose sign-in page is `/sign-in`. The run ends `LOGIN failed … no user or email field found on the sign-in page`.
- **Expected:** the sign-in path is read from the app's own configuration, or the tool tries `/sign-in` when `/login` has no sign-in form.
- **Actual:** the tool signs in at the path it was given and stops after the first failure.
- **Encountered in:** `*build-phase Chatur` chained verify, phase 3, 2026-10-25
- **Workaround:** pass `--login-path /sign-in`.
- **Suggested fix:** probe `/login` then `/sign-in` when the first has no sign-in form, or take the path from `core-config.yaml`.

### TF-020 — Picking the branch you are already on is reported as "does nothing when clicked"

> ✅ **Closed 2026-10-29** — re-checked here: 2026-10-29 *verify all Chatur --phase 3: tf-verify-screens.sh drove End-to-end run, Run queue and Run report in light and dark; render and visual OK on all 3, no screen reported '› main does nothing'; the 19 rows are Verified.

- **Status:** fixed upstream 2026-10-29, ships in TechieFlow v1.2.2; not yet re-checked here.
- **Severity:** minor
- **Blocks:** yes — the render check fails all 19 rows on End-to-end run, Run queue and Run report on this one finding, once the sample menu items are marked.
- **Repro:** open a project whose repository has one branch (`main`). Run `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --base <url> --login-path /sign-in --user chatur-owner@techierathore.com --password <pw>`. The branch menu holds `main` (ticked, the current branch) and "Open the repository…".
- **Expected:** a choice that is already the state, with no sibling choice to move the state first, is noted and not reported. The menu-walk rule for Light in a light app already says this.
- **Actual:** `"main2 to push › main" does nothing when clicked`, a render finding on every screen that shows the toolbar.
- **Encountered in:** `*build-phase Chatur` chained verify, phase 3, 2026-10-28
- **Workaround:** none in the app. Switching to the current branch has nothing to do.
- **Suggested fix:** in `tf-menus.mjs`, treat a ticked item (a check mark, `aria-checked="true"` or `data-state="checked"`) with no unticked sibling choice as "already the state", not as an item that does nothing.
- **Reply (TechieFlow team, 2026-10-29):** Fixed as you suggested. The cause: the walk already skipped a ticked item, but it knew a tick only by a named icon (`svg[class*="check"]`, `data-icon`). TrBlazeUI's `LucideIcon` draws `<svg class="lucide-icon">` with the check path alone, so your ticked `main` was never seen as ticked. `tf-menus.mjs` now also knows a tick by its shape (one stroke of three points, the middle one lowest), as well as `aria-checked="true"` and `data-state="checked"`, and records the click as "already the state (ticked)". An unticked item that does nothing still fails. Regression case `ch_020`. Miss `MISS-TechieFlow-20261029-01`. **Re-run on this project's phase 3** (the web head as on 28 Oct: the WSL copy of the published harness on :5280, signed in as chatur-owner, the three screens that hold the 19 rows): v1.2.1 gives render EMPTY on End-to-end run, Run queue and Run report with `"main2 to push › main" does nothing when clicked`; the fix gives render OK on all three. **Not ours, for you:** a second run on the same data fails visual on all three screens: `text "build failed" in span[data-testid=output-status] is 2.8 : 1 against its background (rgb(252,252,252) on rgb(246,109,103); 3 : 1 is the minimum)`. That is the app's badge colour. Also, the Windows-side copy (what `tf-verify-boot.sh start` chose today) shows "No branches found" in the branch menu, so this fault does not show there. **Check it here:** paste into Chatur's agent `/TechieFlow:agents:verifier *verify ui Chatur --phase 3`. No screen reports `› main" does nothing`.

### TF-021 — tf-triage.sh new hands out four-digit ids that the test mapping cannot read

- **Status:** fixed upstream 2026-11-01, already in this project's `.tfcore/` (its regression case passes against that copy, 2026-11-10); not yet re-checked here. Filed 2026-10-30.
- **Severity:** major
- **Blocks:** no — the four rows were renumbered by hand to free three-digit ids (REQ-UI-079 to REQ-UI-082), and the run went on.
- **Repro:** on Chatur, whose highest UI id is REQ-UI-078, run `bash .tfcore/utils/tf-triage.sh Chatur new "<title>" "<When … then …>" --prefix UI --section "Workbench"` four times. The rows come back as REQ-UI-1000, REQ-UI-1001, REQ-UI-1002 and REQ-UI-1003. Then run `tf-verify-tests.sh` over specs whose tests are titled `REQ-UI-1001 …`, `REQ-UI-1002 …`.
- **Expected:** the next free id in the prefix, REQ-UI-079 onward, in the three-digit form every other script reads.
- **Actual:** `tf-req-ids.py` matches `REQ-(UI|FN|NFR|RAG)-\d{3}`, so all seven tests of the four rows were filed in `tests.json` under one row, `REQ-UI-100`, which does not exist, and the four rows would have been graded as having no test.
- **Encountered in:** `*triage-and-fix Chatur docs/screenshots/2026-10-29-first-use`, 2026-10-30
- **Workaround:** the rows, their tests and the code comments were renumbered to REQ-UI-079 to REQ-UI-082 before the verify.
- **Suggested fix:** in `tf-triage.py` `new`, take the next free number after the highest existing id; and in `tf-req-ids.py`, read `\d{3,}` with a word boundary, so a longer id is never cut to its first three digits.

### TF-022 — The menu walk reports a submenu row (▸) as "does nothing when clicked"

> ✅ **Closed 2026-11-10** — re-checked here: Re-checked 2026-11-10 in *triage-and-fix Chatur: tf-verify-screens.sh over phase 1 with no --no-click options, signed in as chatur-owner on the WSL web head :5290. screens.json records 'File › Recent projects ▸' as 'opened its submenu' and walks its rows (DefaultApp changed the page; Project list navigated to /start?all=1); no screen reports a ▸ row as 'does nothing when clicked'. The branch menu's sample items no longer fail Workbench render.

- **Status:** fixed upstream 2026-11-05, ships in TechieFlow v1.3.0; not yet re-checked here.
- **Severity:** minor
- **Blocks:** no, with a workaround (updated 2026-11-05). Left alone, it fails render on every main-window screen, about 90 rows in phases 1 to 3. The 5 Nov verify passed `--no-click "Recent projects" --no-click "Zoom"` to the screen and mockup checks, so those two rows are not measured. The JSON wrongly gives the reason as "ends the session or deletes".
- **Repro:** TrBlazeUI 2.2.2, Chatur's main window with File ▸ Recent projects ▸ and View ▸ Zoom ▸ built as `MenubarSub` (TR-020). Run `bash .tfcore/utils/tf-mockup-parity.sh --base http://localhost:5280 --screen main=/ --mockup-dir docs/mockups --login-path /sign-in --user chatur-owner@techierathore.com --password <pw> --json-out tests/.artifacts/verify/parity-main.json`.
- **Expected:** a row with `aria-haspopup="menu"` that opens a list (`aria-expanded` goes to `true`, a `role="menu"` appears beside it) is an item that did its job, and the walk goes on into that list.
- **Actual:** `"File › Recent projects ▸" does nothing when clicked` and `"View › Zoom ▸" does nothing when clicked`. A probe on the same app shows a mouse click on either row opens its list at once and keeps it open (`aria-expanded="true"`, the list in the page after 100 ms, 400 ms and 1 s).
- **Encountered in:** `*fix-issues Chatur` (TR-020 re-check), 2026-11-04
- **Workaround:** `--no-click` on the two submenu rows (see Blocks).
- **Suggested fix:** in `tf-menus.mjs`, count `aria-expanded` turning `true` on an `aria-haspopup` item as an effect, and walk the list it opened as a nested menu.
- **Reply (TechieFlow team, 2026-11-05):** Fixed as you suggested. The cause: the walk judges a click by what changes outside the menus (address, text, dialogs, zoom, theme), and a submenu opening changes none of those. In `tf-menus.mjs`, a row with `aria-haspopup="menu"` or `"true"`, or a label ending in ▸, is now graded by its submenu appearing: `aria-expanded` turning `true`, or another menu showing beside it. Its child rows are then opened through it, one at a time from a freshly opened menu, and clicked and graded like any item. A dead child still fails, as `"File › Recent projects ▸ › <name>" does nothing when clicked`. It goes one level deep. Also fixed: a row skipped with `--no-click` now reads `not clicked (--no-click)` in the JSON, not "ends the session or deletes". Regression case `ch_022`. **Proved on your web head** (`tf-verify-boot.sh start --head web --port 5280`, signed in as chatur-owner, main window at 1280, light). v1.2.4 gives `"File › Recent projects ▸" does nothing when clicked` and `"View › Zoom ▸" does nothing when clicked`. The fix gives neither: Recent projects opened its submenu and DefaultApp opened, and Zoom opened with Zoom in and Zoom out zooming and Actual size acting. **Not ours, for you:** render still reads EMPTY on this screen for two other findings, in both runs: `the menu "main2 to push" has no "feature/board" item` and the same for `run/BRD-96-101`. Those are sample branches the mockup draws in the branch menu without `data-tf-sample` (the TF-011 reply named this). Mark them, or the app's branches will never match. **Check it here:** paste into Chatur's agent: `/TechieFlow:agents:verifier *verify ui Chatur --phase 1`, without the two `--no-click` options. No screen reports `Recent projects ▸" does nothing` or `Zoom ▸" does nothing`.

### TF-023 — A screen reached through a submenu row is reported UNREACHABLE

> ✅ **Closed 2026-11-13** — re-checked here: 2026-11-13 triage-and-fix: tf-verify-screens.sh over the phase 1 list on http://localhost:5290: OK Start (/start?all=1) — render OK, visual OK, 26 anchors, light + dark; reached through File › Recent projects ▸. The six Start rows were graded on their other checks.

- **Status:** fixed upstream 2026-11-10, in this project's `.tfcore/` since the framework update of 2026-11-10; not yet re-checked here. Filed 2026-11-10.
- **Severity:** minor
- **Blocks:** no — the Start window is reached in the app (File ▸ Recent projects ▸ Project list lands on `/start?all=1`, and File ▸ Close project does too, proven by the REQ-UI-073 test). Only the six Start rows (REQ-UI-005 to REQ-UI-009, REQ-FN-006) are held below Verified on render.
- **Repro:** Chatur, `docs/mockups/main.html` draws `<a href="start.html">Recent projects ▸</a>` and `<a href="start.html">Close project</a>` in the File menu. The app builds Recent projects as a `MenubarSub` (TR-020) whose last row, Project list, opens `/start?all=1`. Run `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --base http://localhost:5290 --login-path /sign-in --user chatur-owner@techierathore.com --password <pw>` (phase 1 list).
- **Expected:** Start is reached: a child row of the ▸ row that carries the mockup's link landed on Start's route (`screens.json` → `menus.clicks`: `"menu": "File › Recent projects ▸", "label": "Project list", "effect": "navigated", "landed": {"url": "…/start?all=1"}`).
- **Actual:** `FAIL Start (/start?all=1) — render UNREACHABLE … no menu click reaches /start?all=1: File › Recent projects ▸ (opened its submenu)`. `reachability()` in `tf-menus.mjs` takes only the clicks whose own `href` is the screen's mockup; the ▸ row "opened its submenu" and landed nowhere, and its children carry no `href`, so they are never looked at. Close project, the other way in, is never clicked by design.
- **Encountered in:** `*triage-and-fix Chatur`, 2026-11-10 (TF-022's re-check)
- **Workaround:** none in the app; the rows stay below Verified with this reason.
- **Suggested fix:** in `reachability()`, when a way-in click opened a submenu, count any click in `submenu` (or any click whose `menu` starts with that row's `menu › label`) that landed on the route; or treat a way in whose only effect was opening a submenu as left unclicked, so the screen is not judged, as for Sign out.
- **Reply (TechieFlow team, 2026-11-10):** Fixed in the framework, the first way you suggested, and in this project's `.tfcore/` from today's update. In `tf-menus.mjs`, `reachability()` now lets a way in that "opened its submenu" stand for the rows of that submenu: the screen is reached when any of them lands on its route, or draws half of its own controls. The line then names the whole path, `File › Recent projects ▸ › Project list`. When every row of the submenu lands somewhere else the screen is still UNREACHABLE and each row is named with where it landed. A submenu none of whose rows is clicked (all of them of the Sign out kind) leaves the screen unjudged, as a way in that is never clicked already did. Regression case `ch_023`, built from the click records in your entry; it fails on the script you had (Start not reached). **Proved on those records, not on your running app.** **Check it here:** paste into Chatur's agent: `/TechieFlow:agents:verifier *verify REQ-UI-005,REQ-UI-006,REQ-UI-007,REQ-UI-008,REQ-UI-009,REQ-FN-006 Chatur --phase 1`. Start is no longer UNREACHABLE and the six rows are graded on their other checks.

### TF-024 — The WSL build fails with Razor parse errors on files that build on Windows, until the compiler server is shut down

- **Status:** fixed upstream 2026-11-10, in this project's `.tfcore/` since the framework update of 2026-11-10; not yet re-checked here. Filed 2026-11-10.
- **Severity:** minor
- **Blocks:** no — `~/.dotnet/dotnet build-server shutdown` cleared it and the same files built at once.
- **Repro:** Chatur on WSL, in one session: `tf-build.sh build` (Windows rung, PASS), several `tf-verify-boot.sh start --port 5290` (WSL publish, PASS), a `tf-build.sh test` on the Windows rung, then `tf-verify-boot.sh start --port 5290` again.
- **Expected:** the WSL publish builds the files it built twenty minutes earlier.
- **Actual:** `NONE kind=build-error … 122 error line(s), first: src/ChaturUI/Pages/AutoRun.razor(110,232): error RZ1021`, plus RZ1009 on `ConversationPanel.razor(23,51)` at a valid `@(…)`. None of the six files had changed since October; the Windows rung built them. Twice in a row, then a PASS straight after `~/.dotnet/dotnet build-server shutdown` (log `tests/.artifacts/build/20261110T065659Z-publish-40608.log`).
- **Encountered in:** `*triage-and-fix Chatur`, 2026-11-10, twice; each time straight after a `tf-build.sh test` or `build` on the Windows rung (cmd.exe) over the same tree. It cost about 4 minutes the first time.
- **Workaround:** `~/.dotnet/dotnet build-server shutdown`, then the same command.
- **Suggested fix:** in `tf-build.sh`, when a WSL rung fails only with RZ errors (or with CS errors in files unchanged since the last PASS), shut the build servers down and try once more before reporting FAIL; say so in the verdict line.
- **Reply (TechieFlow team, 2026-11-10):** Fixed in the framework, the first half of your suggestion, and in this project's `.tfcore/` from today's update. In `tf-build.sh`, on WSL, a WSL-side rung (`dotnet`, `~/.dotnet/dotnet`) that fails with any Razor error (`error RZ…`) runs `<that dotnet> build-server shutdown` and then the same build, test or publish once more, before anything is reported. When the second try passes, the verdict line says so: `PASS … the first try failed on 122 Razor error line(s) from a stale compiler server, and it passed once the build servers were shut down`. When the errors are still there they are real, and the line says that too: `FAIL real errors … still there after the build servers were shut down and the build was run again`. `tf-verify-boot.sh start` publishes through `tf-build.sh`, so the boot gets the same retry. A build that fails on C# errors alone is reported at once, with no shutdown. Regression case `ch_024`, three checks; two fail on the script you had. **Proved with a stand-in `dotnet` that gives your two errors until its servers are shut down; the real stale server was not reproduced here.** **Not done:** the second half, C# errors in files unchanged since the last PASS. Telling those from a real break needs a record of what each PASS built, and a wrong guess would hide a real error behind a retry; file it again if you meet that shape. A real Razor error now costs one extra build before it is reported. **Check it here:** nothing to run; the next time it happens the build passes on its own and the PASS line carries the sentence above.

### TF-025 — The menu walk switches the project's branch, so a later screen is compared against a state its seed did not make

- **Status:** fixed upstream 2026-11-10, in this project's `.tfcore/` since the framework update of 2026-11-10; not yet re-checked here. Filed 2026-11-10.
- **Severity:** minor
- **Blocks:** no — Repository passes when compared on its own straight after `tests/verify/seed/repository.sh`; the run used that measurement.
- **Repro:** Chatur, phase 1 list. `tf-verify-screens.sh` runs `seed/repository.sh` (hand check-ins on main, two `run/…` branches), then walks every menu. On the main window the branch picker (`branch-pop`) lists main, feature/board and the run branches, and the walk clicks each, which checks the branch out in the fixture repository. `tf-mockup-parity.sh` over the same list then compares Repository with HEAD on the last branch clicked.
- **Expected:** a screen is compared in the state its seed made.
- **Actual:** `repository FAIL {'icon': 12}`: the history shows the two process check-ins at rows 1 and 2 and none of the hand check-ins, because HEAD is on feature/board; the mockup draws them at rows 3 and 5.
- **Encountered in:** `*triage-and-fix Chatur`, 2026-11-10
- **Workaround:** remove the fixture's `.git`, run the seed, then `tf-mockup-parity.sh --screen repository=/repository` alone.
- **Suggested fix:** run a screen's seed again right before that screen is compared, in both scripts; or have the walk put a pick-list choice back (as it already does for the theme) after clicking it.
- **Reply (TechieFlow team, 2026-11-10):** Fixed in the framework, the second way you suggested, and in this project's `.tfcore/` from today's update. In `tf-menus.mjs`, when a menu opens with exactly one ticked item that is not a checkbox (the branch checked out), and a click on another item took effect, the walk opens the menu again at the end; if the tick has moved, it chooses the item that was ticked at the start. `screens.json` records it under that menu as `put_back` (the label, what was ticked instead, and what the click did). So the walk still clicks every branch, and the project is back on `main` when it has finished with the picker. Regression case `ch_025`: the fixture's app reports every checkout to its server; the walk checks out `feature/board` and `run/BRD-96-101`, and the last checkout is `main`. On the script you had the last checkout is the run branch. **Proved on that fixture, not on your repository.** **Not done:** running a screen's seed again before each comparison. A seed is not always safe to run twice (yours needed the fixture's `.git` removed first), so the walk now leaves the state as it found it instead. A one-of choice inside a submenu is not put back yet; none of your menus has one. **Check it here:** paste into Chatur's agent: `/TechieFlow:agents:verifier *verify all Chatur --phase 1`. After the screen check the branch picker on the main window still shows `main` ticked, and Repository is compared with the hand check-ins in place.

### TF-026 — The menu walk opens other projects from File ▸ Recent projects ▸, so later screens and their seeds run on a project they were not made for

- **Status:** fixed upstream 2026-11-14, fixed in Chatur's `.tfcore/` by the framework update of 2026-11-14; not yet re-checked here.
- **Severity:** minor
- **Blocks:** no — each affected screen passes when compared alone on the project its seed prepares (Repository: PASS after `seed/repository.sh` on WbAFilesApp; the branch picker was put back on `main`, so TF-025's fix holds there).
- **Repro:** Chatur, phase 1 list, `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --base http://localhost:5290 --login-path /sign-in --user chatur-owner@techierathore.com --password <pw>`. Since TF-023's fix the walk reaches Start through `File › Recent projects ▸` and clicks the rows of that submenu (AlphaApp, BetaTool, workbench-b, …); each click opens that project.
- **Expected:** a screen is compared on the project that was open when the walk began, as TF-025 now does for the branch picker.
- **Actual:** after the walk the open project is AlphaApp (`Setting.SelectedProjectId` = 10, a folder with no repository). `FAIL Repository (/repository) — render EMPTY … the menu "main2 to push" has no "feature/board" item`, and the branch menus list only `main`, although `seed/repository.sh` had seeded the branches in WbAFilesApp a moment before.
- **Encountered in:** `*triage-and-fix Chatur`, 2026-11-13 (the re-check of TF-023 and TF-025)
- **Workaround:** compare the screen alone after selecting its project and running its seed.
- **Suggested fix:** treat `Recent projects ▸` rows like the one-of pick-lists TF-025 covers: after the walk has clicked them, open again the project that was open at the start (or stop clicking rows whose effect is "opened a project" once one has shown the submenu works).
- **Reply (TechieFlow team, 2026-11-14):** Fixed upstream in `tf-menus.mjs`, the way TF-025 puts a branch back. Before the walk clicks the rows of a submenu, it notes the one row whose label the page itself shows outside the menus: in Chatur, the open project's name in the menu bar (`project-switch-name`). After the rows, if the page no longer shows that name, the walk opens the submenu again and clicks that row, so it ends on the project it found. Every recent project is still clicked once, and so is Project list, so Start keeps its way in (TF-023). When the open project is not in the list, or several rows' names are on the page (a screen that lists every project), nothing is put back; the screen check's JSON names `put_back` on the submenu row only when it happened. Case `ch_026` in `tests/faults/run.sh` (File › Recent projects ▸ whose rows open WbA, AlphaApp and BetaTool, then Project list) fails on the script you had, which left the app on BetaTool, and passes now: the last project opened is WbA and Project list is still clicked. Its control half: the menu cases of TF-011, TF-020, TF-022, TF-023 and TF-025 pass unchanged. Proved on a fixture, not on the Chatur app. **Fixed in Chatur's `.tfcore`:** deployed with `update-framework.sh` on 2026-11-14, when no Chatur run was in progress. **Check it here:** the screen check in the Repro; after the walk the open project is still WbAFilesApp, and Repository passes after its seed with the branch menus listing `feature/board`.

### TF-027 — The mockup check says a Select picker has no icon, because an icon inside `[role="combobox"]` is never counted

- **Status:** fixed upstream 2026-11-14, fixed in Chatur's `.tfcore/` by the framework update of 2026-11-14; not yet re-checked here.
- **Severity:** minor
- **Blocks:** yes for Verified on 32 rows whose tests all pass, on every screen with a TrBlazeUI Select picker: Settings ▸ Routing (REQ-FN-018 to REQ-FN-023), Settings ▸ Appearance (REQ-UI-037, REQ-UI-038), Requirements board's filters and status pickers (REQ-UI-049 to REQ-UI-052, REQ-FN-056, REQ-FN-057), End-to-end run's project picker (REQ-FN-061 to REQ-FN-066, REQ-UI-055, REQ-UI-056, REQ-FN-089, REQ-FN-091, REQ-UI-084) and Run report's run picker (REQ-UI-058 to REQ-UI-061, REQ-UI-088, REQ-FN-115, REQ-UI-089); no for the run, which carried on. These screens passed the same check on 2026-11-10 with the same pickers.
- **Repro:** Chatur, `bash .tfcore/utils/tf-mockup-parity.sh --base http://localhost:5290 --screen settings-routing=/settings/routing --screen settings-appearance=/settings/appearance --login-path /sign-in --user chatur-owner@techierathore.com --password <pw>`.
- **Expected:** the picker matches: the mockup's `<div class="popwrap" data-testid="analyst-tier"><button class="pick">… <svg><use href="#i-chevron"/></svg></button>` and the app's TrBlazeUI Select, `<div data-testid="analyst-tier"><button role="combobox" …><span>Tier 3</span><svg class="ms-2 h-4 w-4 opacity-50">…chevron…</svg></button>`, both carry one visible chevron.
- **Actual:** `icon on analyst-tier @1280: mockup carries an icon here; the app does not`, the same for every tier picker and for `mode-choices`. In `tf-mockup-parity.mjs`, `PAINTED` includes `[role="combobox"]`, and `own()` drops every icon under `PAINTED`, so the app's chevron is never counted; the mockup's picker is a plain button, so its chevron is. The icon clause is skipped only when the compared element itself is a select (`m.select || a.select`), not when a select sits inside it.
- **Encountered in:** `*triage-and-fix Chatur`, 2026-11-13
- **Workaround:** none in the app: the chevron is drawn and visible. The rows stay below Verified with this reason.
- **Suggested fix:** skip the icon clause (as for a select) when either side's element contains a select or a `[role="combobox"]`, or count a mockup icon under a `button.pick`/`[data-value]` trigger as painted too.
- **Reply (TechieFlow team, 2026-11-14):** Fixed upstream in `tf-mockup-parity.mjs`. **The rule that now decides a picker's own arrow, on both sides:** everything a picker draws inside its trigger (the arrow of a native select or a `[role="combobox"]`, the calendar of a date box) belongs to the picker and counts as an icon on neither side, nor on any box around it; the side that draws a real picker never counts it, and on the other side a trigger paired with that picker (a button, or a box holding one button, as your mockup's `button.pick` in its `popwrap`) gives up its icons too. A plain element that is no trigger, such as a `<span>` with a chevron where the mockup draws a select, is still compared (TfLens TF-046's case). Before, only the app side's arrow was left out, so your mockup's chevron always counted. The date-box rule of Sevak's TF-027 is the same rule and now runs through the same lines. **Against the fixes of 12 Nov (Sevak's numbering):** TF-028 decides which icons are seen at all (none inside a hidden panel), TF-029 which clauses compare a sample pill (its colour only when it shows the sample's text), TF-032 which rows' icons come off a box. None of them reads a picker, and this rule takes icons off only where a picker is paired with a non-picker, so they do not pull against each other: `sv_025`, `sv_027`, `sv_028`, `sv_029` and `sv_032` pass unchanged beside `ch_027`. Case `ch_027` (your tier picker as a `button.pick` against a combobox, a second against a native select) fails on the script you had (`analyst-tier` and `tester-tier`: mockup carries an icon here; the app does not) and passes now. Its control half: a plain button whose chevron the app does not draw, and an icon beside the picker in the same box, are still reported at 1280 and 390. This can only take findings away. Proved on a fixture, not on the Chatur app. **Fixed in Chatur's `.tfcore`:** deployed with `update-framework.sh` on 2026-11-14, when no Chatur run was in progress. **Check it here:** the mockup check in the Repro on Settings ▸ Routing and Appearance: no `analyst-tier`, `mode-choices` or other picker icon finding; then a verify of the 32 rows.

### TF-028 — A verify's run record cannot say which provider and model the app under test called

- **Status:** fixed upstream 2026-11-14, fixed in Chatur's `.tfcore/` by the framework update of 2026-11-14; not yet re-checked here.
- **Severity:** minor
- **Blocks:** no — the provider and model are written in the Verification log row of the project status page and in the run summary instead.
- **Repro:** Chatur's browser tests call a real model through the provider in `tests/verify/test-settings.json` (`testProvider`: Anthropic, `claude-sonnet-5-5`). The owner asked for that provider and model in the run record of `*triage-and-fix Chatur` on 2026-11-13.
- **Expected:** a run record field for the model service the checks themselves exercised (for example `checks_provider` and `checks_model`), next to `model`, which is the agent's own.
- **Actual:** `.tfcore/telemetry/SCHEMA.md` has `model` only, observed from the agent's transcript; `tf-verify-emit.sh` and `tf-fix-close.sh` take no option for it, and an unknown field is refused.
- **Encountered in:** `*triage-and-fix Chatur`, 2026-11-13
- **Workaround:** written in the status page's Verification log row.
- **Suggested fix:** read `testProvider.name` and `.model` from the project's test settings when a verify emits its run record, and keep them in two optional fields.
- **Reply (TechieFlow team, 2026-11-14):** Fixed upstream as you suggested, the framework's own way: two optional fields added to the schema (`.tfcore/telemetry/SCHEMA.md` §2.5c) and written by script, never by an agent. `checks_provider` and `checks_model` are read by the new `tf-checks-model.py` from `tests/verify/testsettings.Local.json`, `testsettings.json` or your `test-settings.json` (`testProvider.name` and `.model`; `Verify:TestProvider:Name` and `:Model` also work), and go on the run record of every verify (`tf-verify-emit.sh`) and on the first run record of a fix (`tf-fix-close.sh`, so `*fix-issues` and `*triage-and-fix`). Only the name and the model are read: the key beside them never reaches a record or the screen. `model` stays the agent's own. **Old records stay readable:** both fields are optional, the emitter accepts them now, and a record without them (every record before today) means "not recorded", never "none". **What TfLens must read:** in `docs/metrics/runs.jsonl`, on `kind: "run"` records, the string fields `checks_provider` and `checks_model`, shown beside `model` and never added to its tokens or cost (the app's calls are not the agent's); absent means not recorded. Case `ch_028` fails on the scripts you had (no field on either record) and passes now. Its control half: a project that names no provider gets its run records without either field, as before. Proved on a fixture. **Fixed in Chatur's `.tfcore`:** deployed with `update-framework.sh` on 2026-11-14, when no Chatur run was in progress. **Check it here:** after the next verify, the last `verify-phase` record in `docs/metrics/runs.jsonl` carries `"checks_provider":"Anthropic"` and `"checks_model":"claude-sonnet-5-5"`.

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

### Resolution status (TechieFlow team, 2026-10-08, TF-008)

| ID | Fix | Check it here |
|---|---|---|
| TF-008 | Fixed upstream, both ways you suggested. `tf-verify-verdict` now finds a row's mockup comparison by the screen's name, by its mockup's file name (`process-run`), or by its route, where `{id}` in the row's route stands for any one path segment. So `/processes/6/run` counts for `/processes/{id}/run`, and `/start?all=1` counts for `/start`. When several comparisons match, the worst one counts. A screen that was driven, has a mockup and has no comparison now fails the mockup check with "mockup-parity not found", and the Remark names the `--screen` to add. A comparison that could not open its screen fails it too. A screen with no mockup is not held to one. Proved on this project's own phase-2 evidence (the verify list's Process run and Agent workspace rows, `screens-213.json`, `parity-p2fix2.json`). The old script gives all 11 rows PASS. The new one fails the 6 Process run rows on the comparison's icon finding and passes the 5 Agent workspace rows, whose comparison passed in that file. Regression case `ch_008` fails against the script you had and passes now. | After the framework update, run the comparison as the repro does (`--screen process-run=/processes/6/run --screen agent-workspace=/workspace/verifier`, without the checklist names), then `tf-verify-verdict.sh Chatur --apply`. Rows on a screen whose comparison FAILed go to Needs re-verify. Leave one screen out of the comparison: its rows fail with "mockup-parity not found" instead of passing. |

### Resolution status (TechieFlow team, 2026-10-09, TF-009)

| ID | Fix | Check it here |
|---|---|---|
| TF-009 | Fixed upstream, as you suggested. `tf-verify-screens` now counts an anchored control as filled when it is, or holds, a `role="progressbar"` with an `aria-valuenow`, a `progress` or a `meter`, or when one of its children has a width and a height and paints something (a background colour, a background image or a border). An empty track, whose child has no size or paints nothing, is still `empty`, so a bar that draws nothing is still caught. A second fault was found while proving it: a native `progress` or `meter` crashed the screen check, because its value is a number. That is fixed too. Proved on the bar's two shapes: the mockup's track holding a fill, and TrBlazeUI's `role="progressbar"` at 50%. The old script reports `anchored control "progress-bar" (div) is empty` on both; the new one passes both. Regression case `ch_009` fails against the script you had and passes now. | After the framework update, start a run (`tests/verify/seed/auto-run.sh`), then run `*verify ui Chatur`. `/auto` has no `progress-bar ... is empty` finding at 1280 or 390, and the 8 End-to-end run rows are graded on their other checks. |

### Resolution status (TechieFlow team, 2026-10-12, TF-010)

| ID | Fix | Check it here |
|---|---|---|
| TF-010 | Fixed upstream, the first way you suggested. On the Mac, `blazor-zoom.cs.txt` now keeps a weak reference to every web view handed to `Attach`, and each zoom key sets the level on all of them, dropping any whose window is gone. The level is one saved value, so every open window shows it. Windows is unchanged. Proved by compiling the real file for Mac Catalyst against stand-in Mac types: three windows attached, one Cmd+=. The old file gives 100%, 100%, 110%; the new one gives 110% in all three. Regression case `ch_010` fails against the file you have and passes now. Miss `MISS-TechieFlow-20261012-03`. Not run on a real Mac yet. | Chatur's `src/Chatur/BlazorZoom.cs` is already re-copied from the new file, with its header and namespace kept (not committed; the owner commits). On the Mac, open all three windows and press Cmd+=: every window grows, not only the last one opened. |

### Resolution status (TechieFlow team, 2026-10-14, TF-011 and TF-012)

Both fixes ship in **TechieFlow v1.2.0**, the next release after v1.1.0. They are already in this project's `.tfcore/` through the framework update.

| ID | Fix | Check it here |
|---|---|---|
| TF-011 | Fixed upstream. Both the screen check (`tf-verify-screens`) and the mockup comparison (`tf-mockup-parity`) now open every menu and drop-down your mockups draw open (`data-tf-state="popup-open"`) and click every item, one at a time, putting the screen back after each. The shared code is the new `.tfcore/utils/tf-menus.mjs`. A screen fails when one of its menus is missing an item the mockup draws, shows placeholder text ("Nothing to do yet", "Coming soon", "Not built yet", "Not implemented yet", "TODO"; add your own with `--placeholder-text`), has an item that does nothing when clicked, or has every item disabled where the mockup draws them enabled. A single disabled item is only noted, because that is the state the app is in (no file open). Placeholder text anywhere on a screen fails it too, unless the mockup itself draws that text. A screen that a menu item links to (`<a href="prerequisites.html">`) fails as UNREACHABLE when no click reaches it. Items that end the session or the work (Exit, Sign out, Close project, Delete …; add your own with `--no-click`) are checked but never clicked. Pick-lists are checked but not clicked. `--no-menus` turns the walk off. Also fixed: `tf-triage.sh new` now takes the next id free across every checklist of the app (`REQ-UI-076` on your four checklists today, where the old script gave `REQ-UI-075`, which phase 2 already holds). Measured on a copy of your web head as it stood on 13 Oct, signed in as Owner, with all 16 screens of phases 1 to 3. The screen check goes from 14 screens passing to 6, and the mockup comparison from 11 to 5. Every new failure is one of three kinds. (1) The app lacks what the mockup draws: Account › Licence; Project › Build, Run, Stop and the four run targets; Help › Send feedback…; Appearance › "Follow the machine". (2) **File › Recent projects: clicking any of the five recent projects changes nothing and leaves the menu open.** We believe that is a real defect in the app (seen by hand too). (3) Things the walk cannot tell apart without your help. The sample choices in the branch, chat-history, model and project drop-downs are not marked `data-tf-sample` in the mockups, so they are reported missing. And "Automatic" in the model menu and the active chat in the history menu, which are the current choice, carry no `aria-checked`, so choosing them again is reported as doing nothing. Not fixed upstream: TrBlazeUI's disabled menu items carry no `aria-disabled` (filed as TrBlazeUI TR-004); the walk copes with it. Regression cases `ch_011a` to `ch_011c` fail against the scripts you had and pass now. Misses `MISS-TechieFlow-20261013-01` and `-02`. | Run `*verify ui Chatur`. Workbench should report File, Edit and View items, never "Nothing to do yet". For Prerequisites, Repository and every Settings tab, the screen check's report names the menu item that reached it. The findings in kinds (1) to (3) above will be on the report until the app or the mockups change. |
| TF-012 | Fixed upstream, as you suggested. `tf-verify-tests` now takes a row's id only from the start of a test's name: the run of `REQ-…` ids it opens with, after at most one short capital tag such as `FIX`, and before any argument list. Each describe title of a browser test is read on its own. An argument named for the row (`row: "REQ-RAG-125"`) still counts, which TechieRag's per-row tests rely on. A row whose id appears only inside another row's passing test is printed as `NO TEST` and listed as untested in the report; it is not tested. `--merge` applies the same rule to parts written by the old script. The rule lives in the new `.tfcore/utils/tf-req-ids.py`. Replayed on every test name your verify runs recorded: REQ-FN-053 and REQ-FN-055 now pass only on your new `process-run-progress` tests. **REQ-FN-051 loses its only passing "test"**: it was the same theory's sample `"REQ-UI-048 and REQ-FN-051 and REQ-UI-048"`. Across the other projects the same replay drops TfLens REQ-UI-001 (named inside REQ-FN-111's test) and Sevak REQ-UI-050 (named in a localization theory's `decision:` argument). Neither of those has a test of its own either. Regression case `ch_012` fails against the script you had and passes now. Miss `MISS-TechieFlow-20261013-03`. | Run `*verify functional Chatur`. REQ-FN-051 reads `NO TEST`, not Verified, until it has a test whose name starts with its id. REQ-FN-053 and REQ-FN-055 stay Verified on `process-run-progress.spec.ts`. |

### Resolution status (TechieFlow team, 2026-10-21, TF-013 to TF-015)

All three fixes ship in **TechieFlow v1.2.1**, the next release after v1.2.0. They are already in this project's `.tfcore/` through the framework update.

| ID | Fix | Check it here |
|---|---|---|
| TF-013 | Fixed upstream in `tf-verify-verdict.py`, as you suggested. A row that was Not Started keeps Not Started when every check that fails on it is its route answering 404. That is the render check, and the mockup check, which could not open the route for the same reason. Its Remark reads `not built — /feedback answered HTTP 404: the screen is not built yet, nothing to re-verify`, and it emits no gate record and no miss. A row that was built and answers 404 still goes to Needs re-verify, and so does a Not Started row with any other failure. Regression case `ch_013` fails on the script you had. Miss `MISS-TechieFlow-20261021-04`. | **Replayed on your phase-4 evidence** (`list-p4.json`, `screens-p4.json`, `parity-p4.json`, `assets-p4.json`), in a copy, so nothing here was written. Old script: 19 rows RENDER-FAIL, Needs re-verify, 19 misses. New script: 19 rows Not Started, no miss. **One thing for you:** the 19 rows of `docs/Chatur-P4-Checklist.md` still read Needs re-verify from the 2026-10-19 run. Paste into Chatur's agent: `/TechieFlow:agents:verifier *verify all Chatur --phase 4`. The verdict puts them back to Not Started, each with the 404 reason. |
| TF-014 | Fixed upstream in `guard-db.sh`, as you suggested. "dbup" counts only when it runs: as the command word of a segment (`dbup upgrade`, `./Chatur.DbUp.exe`, `dotnet Chatur.DbUp.dll`) or through `dotnet run --project …Db` / `…DbUp`. A quoted argument is a mention (a `--what` sentence, a `grep` pattern), unless a shell runs it (`bash -c "dotnet run --project src/ChaturDb"`) or it is the `--project` path. Regression case `ch_014` holds 12 command shapes; the guard you had gets 5 of them wrong. Miss `MISS-TechieFlow-20261021-05`. | Proved on your two repro commands, with the marker at `log-miss`: your guard refuses both, the new one allows both. `dotnet run --project src/ChaturDb` is still refused outside `*build-phase`, `*fix-issues` and `*triage-and-fix`. After the framework update, `*log-miss` takes a sentence naming DbUp, and `grep -n -i "dbup" docs/Chatur-Checklist.md` runs. You no longer need the file workaround. |
| TF-015 | Fixed upstream in `tf-verify-verdict.py`, as you suggested: `bad` is set before the render branch. A row on an UNREACHABLE screen is RENDER-FAIL on a Mac head as on any other, with the screen check's reason, and every other row is graded. Regression case `ch_015` builds your shape: a Mac (appium) boot, `anchors_not_measured`, the first screen UNREACHABLE. It fails on the script you had with exit 1 and `UnboundLocalError`, and passes now. Miss `MISS-TechieFlow-20261021-06`. | Proved on that fixture only: the Mac run's evidence is on the Mac, not on this machine. On the Mac, paste into Chatur's agent: `/TechieFlow:agents:verifier *verify all Chatur --phase all --head maccatalyst`. Phases 2 to 4 get a verdict table. Rows whose screen stays behind Sign in read RENDER-FAIL with the screen check's reason. |

### Resolution status (TechieFlow team, 2026-10-29)

Ships in **TechieFlow v1.2.2**, the next release after v1.2.1. Already in this project's `.tfcore/` through the framework update.

| ID | Fix | Check it here |
|---|---|---|
| TF-020 | Fixed upstream. The reply is under the entry. | paste into Chatur's agent `/TechieFlow:agents:verifier *verify ui Chatur --phase 3`. No screen reports `› main" does nothing`. |
| TF-017 | Fixed upstream. The reply is under the entry. | `/TechieFlow:agents:verifier *verify functional Chatur --phase 3`. REQ-FN-106 reads Needs re-verify with the reason, not Verified. |
| TF-016 | Fixed upstream. The reply is under the entry. | on the Mac, `/TechieFlow:agents:verifier *verify all Chatur --phase 1 --head maccatalyst`. Sign in is graded; the screens behind it print `NOT … not measured`, and no row fails on them. |
| TF-015 | Fixed upstream. The reply is under the entry. | on the Mac, `*verify all Chatur --phase all --head maccatalyst`: phases 2 to 4 get a verdict table, and no row behind Sign in is RENDER-FAIL. |
| TF-013 | Fixed upstream. The reply is under the entry. | `/TechieFlow:agents:verifier *verify all Chatur --phase 4`. The 19 rows go back to Not Started with the 404 reason, and no miss is written. |
| TF-014 | Fixed upstream. The reply is under the entry. | run your two repro commands outside a build or fix: neither is blocked. |

### Resolution status (TechieFlow team, 2026-11-05)

Ships in **TechieFlow v1.3.0**, the next release after v1.2.4. Already in this project's `.tfcore/` through the framework update of 2026-11-06. The regression case fails against the v1.2.4 script and passes now.

| ID | Fix | Check it here |
|---|---|---|
| TF-022 | Fixed upstream. The reply is under the entry. | `/TechieFlow:agents:verifier *verify ui Chatur --phase 1` without `--no-click`. No screen reports `Recent projects ▸" does nothing` or `Zoom ▸" does nothing`. |

### Resolution status (TechieFlow team, 2026-11-01)

Ships in **TechieFlow v1.2.4**, the next release after v1.2.3; already in this project's `.tfcore/` through the framework update of 2026-11-01. Each fix has a regression case in `tests/regression/run.sh` that fails against the v1.2.3 script and passes now.

| ID | Fix | Check it here |
|---|---|---|
| TF-018 | Fixed upstream in `tf-verify-boot.sh`, `tf-build.sh` and `tf-verify-tests.sh`. On WSL a web project with no MAUI target of its own is published and run on WSL, so the tests can hand it WSL paths. `TF_BOOT_RUNNER=wsl|windows` forces a side. `tf-verify-boot.sh adopt --port N [--pid P]` gives a head started by hand a boot record with its pid. `--merge` with no part files refuses. The `/proc/undefined` read is in your `tests/verify/support/restart.ts` (`pids[0]` of a record without pids); with a real or adopted record it does not happen. The desktop head's real database is only partly answered: `--env` reaches the Windows head, but the app must name its data-folder variable. Case `ch_018`. | After the framework update: `bash .tfcore/utils/tf-verify-boot.sh start`: expect `BOOTED … side=wsl` and the fixture projects opening. |
| TF-019 | Fixed upstream in `tf-login.mjs`. The sign-in tries the path it was given, then `/login`, `/sign-in`, `/signin` and `/account/login`, and says which worked: "LOGIN signed in at /sign-in: /login has no sign-in form". Case `ch_019`. | After the framework update: the screen check with `--login-path /login`: expect "LOGIN signed in at /sign-in" and the screens driven. |
| TF-021 | Fixed upstream in `tf-checklist-edit.py` and `tf-req-ids.py`. `tests/verify/process-run.spec.ts` holds `REQ-UI-999` as sample data; the TechieRag TF-008 scan counted it into the highest id, so the next was 1000. Ids in code and tests now only rule an id out and never raise the count, and a four-digit id is read whole. On a copy of your repo: `REQ-UI-1000` → `REQ-UI-083`. Case `ch_021`. | After the framework update: `bash .tfcore/utils/tf-triage.sh Chatur new …` on a copy: expect the next three-digit id. |

### Resolution status (TechieFlow team, 2026-11-10)

No new fix for Chatur today. Five entries still carried the line `Status: open` although each was answered in the tables above, so they read as unfixed to anyone who looked at the entry and not at the reply. The fixes are in the framework and already in this project's `.tfcore/`: on 2026-11-10 each regression case below was run against Chatur's own copy of the scripts and passed. Only the five Status lines were changed; nothing else in this file was touched. `bash .tfcore/utils/tf-feedback.sh Chatur` will name any entry left in that state from the next release on.

| ID | State | Regression case, run against Chatur's `.tfcore/` on 2026-11-10 |
|---|---|---|
| TF-008 | Fixed upstream 2026-10-08, waiting for your re-check | `ch_008`, 2 checks pass |
| TF-009 | Fixed upstream 2026-10-09, closed by Chatur the same day | `ch_009` passes |
| TF-018 | Fixed upstream 2026-11-01, waiting for your re-check | `ch_018`, 3 checks pass |
| TF-019 | Fixed upstream 2026-11-01, waiting for your re-check | `ch_019`, 2 checks pass |
| TF-021 | Fixed upstream 2026-11-01, waiting for your re-check | `ch_021`, 2 checks pass |

### Resolution status (TechieFlow team, 2026-11-10, TF-023 to TF-025)

In this project's `.tfcore/` through the framework update of 2026-11-10; the other projects get them at the next release. Each fix has a regression case in `tests/regression/run.sh` that fails against the scripts this project had before the update. None was run on the Chatur app.

| ID | Fix | Check it here |
|---|---|---|
| TF-023 | Fixed upstream. The reply is under the entry. | the verify of the six Start rows in the reply; Start is not UNREACHABLE. |
| TF-024 | Fixed upstream. The reply is under the entry. | nothing to run; a stale-server failure now passes on its own and the PASS line says so. |
| TF-025 | Fixed upstream. The reply is under the entry. | `*verify all Chatur --phase 1`; the branch picker still shows `main` ticked after the screen check. |

### Resolution status (TechieFlow team, 2026-11-14, TF-026 to TF-028)

**Fixed in Chatur's `.tfcore`** through the framework update of 2026-11-14. Each has a case in `tests/faults/run.sh` that fails on the scripts this project had and passes now, with a control half that shows a real finding is still reported. Proved on fixtures, not on the Chatur app.

| ID | Fix | Check it here |
|---|---|---|
| TF-027 | Fixed upstream. A picker's own arrow counts on neither side. The reply is under the entry. | the mockup check on Settings ▸ Routing: no `analyst-tier` icon finding; then verify the 32 rows. |
| TF-026 | Fixed upstream. The walk ends on the project it found. The reply is under the entry. | the phase 1 screen check: the open project is still WbAFilesApp after the walk. |
| TF-028 | Fixed upstream. `checks_provider` and `checks_model` on the run records. The reply is under the entry. | the next verify's run record carries both. |

# TechieFlow feedback — found while building Chatur

| | |
|---|---|
| App | Chatur |
| Upstream | TechieFlow |
| Updated | 2026-10-29 (TF-015 to TF-017 and TF-020 fixed upstream, ship in TechieFlow v1.2.2; TF-013 and TF-014 re-checked upstream) |

## Summary

20 entries: 2 open (TF-018, TF-019), 8 fixed upstream and not yet re-checked (TF-008, TF-010, TF-013 to TF-015 in v1.2.1; TF-015 reworked, TF-016, TF-017 and TF-020 in v1.2.2, fixed 2026-10-29), 10 closed (TF-001 to TF-007, TF-009, TF-011, TF-012). 0 blocking now: TF-020 and TF-017, the two that blocked, are fixed upstream.

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

- **Status:** open, filed 2026-10-07
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

- **Status:** open, filed 2026-10-08
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

- **Status:** open, filed 2026-10-25
- **Severity:** major
- **Blocks:** yes — every verdict written from this machine on 2026-10-25 came from a head the tooling did not boot. The verdict header prints `booted: not booted`, and rows whose checks need the boot record fail with `ENOENT '/proc/undefined/cmdline'` (REQ-FN-055, REQ-FN-061).
- **Repro:** `bash .tfcore/utils/tf-verify-boot.sh start` on WSL with the published harness on `http://localhost:5280`. It prints `NONE head=web kind=host reason=the published copy … did not answer on http://localhost:5280/ within 120 s although its log says it is listening`. The log shows `Application started`.
- **Expected:** the boot step reaches the published copy on WSL, or it runs the WSL copy when the Windows-side copy is unreachable, and writes a boot record the verdict can use.
- **Actual:** the boot script chooses its runner from the build rung (`via cmd.exe`), and no environment switch forces the WSL runner. The Windows-side copy never answers from WSL. A head started by hand has no pid record, so the process checks read `/proc/undefined`.
- **Encountered in:** `*build-phase Chatur` chained verify, phase 3, 2026-10-25
- **Workaround:** the published harness was started by hand under WSL dotnet (`~/.dotnet/dotnet Chatur.WebHarness.dll --urls http://localhost:5280`) and stopped by hand afterwards. Its verdicts are recorded as "not booted".
- **Suggested fix:** an environment variable (for example `TF_BOOT_RUNNER=wsl`) that forces the WSL runner, and a fallback to it when the cmd.exe copy does not answer within the wait. Also record the pid of a hand-started head so the process checks can read it.

### TF-019 — The screen check's default sign-in path is /login, but this app signs in at /sign-in

- **Status:** open, filed 2026-10-25
- **Severity:** minor
- **Blocks:** no — passing `--login-path /sign-in` by hand works, and the screens were then driven.
- **Repro:** `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --base http://localhost:5280 --login-path /login --user chatur-owner@techierathore.com`, against an app whose sign-in page is `/sign-in`. The run ends `LOGIN failed … no user or email field found on the sign-in page`.
- **Expected:** the sign-in path is read from the app's own configuration, or the tool tries `/sign-in` when `/login` has no sign-in form.
- **Actual:** the tool signs in at the path it was given and stops after the first failure.
- **Encountered in:** `*build-phase Chatur` chained verify, phase 3, 2026-10-25
- **Workaround:** pass `--login-path /sign-in`.
- **Suggested fix:** probe `/login` then `/sign-in` when the first has no sign-in form, or take the path from `core-config.yaml`.

### TF-020 — Picking the branch you are already on is reported as "does nothing when clicked"

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
| TF-013 | Fixed upstream in `tf-verify-verdict.py`, as you suggested. A row that was Not Started keeps Not Started when every check that fails on it is its route answering 404. That is the render check, and the mockup check, which could not open the route for the same reason. Its Remark reads `not built — /feedback answered HTTP 404: the screen is not built yet, nothing to re-verify`, and it emits no gate record and no miss. A row that was built and answers 404 still goes to Needs re-verify, and so does a Not Started row with any other failure. Regression case `ch_013` fails on the script you had. Miss `MISS-TechieFlow-20261021-04`. | **Replayed on your phase-4 evidence** (`list-p4.json`, `screens-p4.json`, `parity-p4.json`, `assets-p4.json`), in a copy, so nothing here was written. Old script: 19 rows RENDER-FAIL, Needs re-verify, 19 misses. New script: 19 rows Not Started, no miss. **One thing for you:** the 19 rows of `docs/Chatur-P4-Checklist.md` still read Needs re-verify from the 2026-10-19 run. After the framework update, paste into Chatur's agent: `/TechieFlow:agents:verifier *verify all Chatur --phase 4`. The verdict puts them back to Not Started, each with the 404 reason. |
| TF-014 | Fixed upstream in `guard-db.sh`, as you suggested. "dbup" counts only when it runs: as the command word of a segment (`dbup upgrade`, `./Chatur.DbUp.exe`, `dotnet Chatur.DbUp.dll`) or through `dotnet run --project …Db` / `…DbUp`. A quoted argument is a mention (a `--what` sentence, a `grep` pattern), unless a shell runs it (`bash -c "dotnet run --project src/ChaturDb"`) or it is the `--project` path. Regression case `ch_014` holds 12 command shapes; the guard you had gets 5 of them wrong. Miss `MISS-TechieFlow-20261021-05`. | Proved on your two repro commands, with the marker at `log-miss`: your guard refuses both, the new one allows both. `dotnet run --project src/ChaturDb` is still refused outside `*build-phase`, `*fix-issues` and `*triage-and-fix`. After the framework update, `*log-miss` takes a sentence naming DbUp, and `grep -n -i "dbup" docs/Chatur-Checklist.md` runs. You no longer need the file workaround. |
| TF-015 | Fixed upstream in `tf-verify-verdict.py`, as you suggested: `bad` is set before the render branch. A row on an UNREACHABLE screen is RENDER-FAIL on a Mac head as on any other, with the screen check's reason, and every other row is graded. Regression case `ch_015` builds your shape: a Mac (appium) boot, `anchors_not_measured`, the first screen UNREACHABLE. It fails on the script you had with exit 1 and `UnboundLocalError`, and passes now. Miss `MISS-TechieFlow-20261021-06`. | Proved on that fixture only: the Mac run's evidence is on the Mac, not on this machine. On the Mac, after the framework update, paste into Chatur's agent: `/TechieFlow:agents:verifier *verify all Chatur --phase all --head maccatalyst`. Phases 2 to 4 get a verdict table. Rows whose screen stays behind Sign in read RENDER-FAIL with the screen check's reason. |

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

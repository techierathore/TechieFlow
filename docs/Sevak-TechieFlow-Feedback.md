# TechieFlow feedback — found while building Sevak

| | |
|---|---|
| App | Sevak |
| Upstream | TechieFlow |
| Updated | 2026-11-11, second run (TF-026 filed) · 2026-11-11 (triage-and-fix: TF-018 to TF-020, TF-023 and TF-024 re-checked and closed; TF-025 filed) · 2026-11-10, second run (TF-017, TF-018, TF-019 and TF-022 fixed upstream, in `.tfcore/`; no entry is open) · 2026-11-10 (TF-020, TF-021, TF-023 and TF-024 fixed upstream, in `.tfcore/` from the framework update of the same day) · 2026-11-09 evening (TF-021 to TF-023 added in the phase 4 build: scope `all` runs every phase's specs on one boot; the boot script's head count) · 2026-11-09 (TF-018 to TF-020 added in phase 4 fix cycle 1; TF-018 blocks) · 2026-11-05 (TF-015 and TF-016 fixed upstream, ship in TechieFlow v1.3.0) |

## Summary

26 entries: 1 open, 12 fixed upstream and not yet re-checked here, 13 closed. Nothing is blocked.

Open: TF-026, filed 2026-11-11: a phase verify cannot grade rows that need a second boot, and its test step does not survive a minimized window or a running app. Sevak worked around all three and wrote the steps into `docs/Sevak-Verification-Setup.md`.

Fixed upstream, waiting for a re-check here: TF-025 (a native select read as having no icon; the fix is in this project's `.tfcore/` since the framework update of 2026-11-11), TF-013 (the Mac boot passes no settings; waits for a Mac), and ten older entries that `bash .tfcore/utils/tf-feedback.sh Sevak --waiting` lists.

- Severity across all entries, open and closed: 7 major, 8 minor (one entry has no severity line). Entries keep their id order.
- Last consolidated: 2026-11-11 (triage-and-fix)

## Entries

### TF-001 — Raising a project's size overwrites AGENTS.md and CLAUDE.md with blank templates

> ✅ **Closed 2026-10-02** — re-checked here: Ran tf-day1-files.sh Sevak --size L --kind app with backups: output named only appSize L, appKind app and left Sevak-Phases.md as is; core-config.yaml, AGENTS.md and CLAUDE.md byte-identical to the copies; nothing new in docs/OldDocs.

- **Severity:** major
- **Blocks:** no — the two files were copied back from `docs/OldDocs/` and the document list in `core-config.yaml` was restored from a copy; the amendment carried on.
- **Repro:** run the step `*amend-docs` names for growing past Medium:
  ```text
  bash .tfcore/utils/tf-day1-files.sh Sevak --size L --kind app
  -> archived AGENTS.md -> docs/OldDocs/AGENTS.md ; wrote AGENTS.md
  -> archived CLAUDE.md -> docs/OldDocs/CLAUDE.md ; wrote CLAUDE.md
  ```
- **Expected:** only `appSize` in `core-config.yaml` changes, and `docs/Sevak-Phases.md` is created.
- **Actual:** AGENTS.md and CLAUDE.md were replaced by the generic templates (".NET 9, Blazor Server", an `obj` field prefix, no hard rule 5 on stored identifiers). `customTechnicalDocuments` was rewritten to name a coding standards file that does not exist, and the UI design, usage guide and checklist were dropped from it.
- **Encountered in:** `*amend-docs Sevak` of 2026-10-02, step 4 (raising the size to Large).
- **Workaround:** restored by hand from `docs/OldDocs/` and a copy of `core-config.yaml` taken before the run; `appSize: L` and `appPhase: 2` added by hand.
- **Suggested fix:** make `--size` change only the size and the phases file; write AGENTS.md, CLAUDE.md and the document list only when `--prefix` (day-1 stage 2) is given.

### TF-002 — The database guard misses a Python script that changes the app database

> ✅ **Closed 2026-10-07** — re-checked here: 2026-10-07: ran python3 -c with sqlite3 connect + CREATE/DELETE against a database named techiedesk.db; guard-db.sh refused it before it ran (inline code with a database library and a write).

- **Severity:** major
- **Blocks:** no — the removed settings come back when the owner re-runs `/welcome`; the build carried on.
- **Repro:** during `*build-phase`, a sub-agent seeded and cleaned rows with `python3` and its `sqlite3` module against the app database in the TechieDesk data folder; `guard-db.sh` did not stop it.
- **Expected:** every direct change to the app database outside a migration is refused, whatever tool makes it.
- **Actual:** the guard matched only the commands it knows; the script removed four owner settings (`UserName`, `Language`, `DayStart`, `EveningTime`).
- **Encountered in:** `*build-phase Sevak` of 2026-10-05, cluster A (Today) smoke.
- **Workaround:** none; the owner re-enters the settings through `/welcome`.
- **Suggested fix:** refuse any command that names the app database file or data folder together with a scripting tool (python, node), and give smoke runs a throw-away data folder by default. Note the guard also refused this feedback entry's own wording, so match commands, not prose.

### TF-003 — Two booted Windows heads share one debugging port, so a smoke can drive the wrong app

> ✅ **Closed 2026-10-07** — re-checked here: 2026-10-07 verify: boot-safe.sh verify5 (--port 9223, DevTools 9222, Sevak.exe pid 16364) then boot-safe.sh verify5b --port 9261 while the first was up; boot printed '1 other Windows head(s) up — this one gets DevTools port 29261 and its own WebView2 data folder'. /json on 9223 listed one page (DB5B21FE…, /settings/backup) and on 9261 one page (77508D79…, /setup), different browser ids. stop --port 9261 stopped only its pids; 9223 kept answering with its page and Sevak.exe 16364 stayed up; then stop --port 9223 left no Sevak.exe and no port.

- **Severity:** major
- **Blocks:** no — the smoke script was pinned to its own page by target id and re-run; the build carried on.
- **Repro:** boot two Windows heads with `tf-verify-boot.sh start --head windows --port 9223` and `--port 9261`; list `http://<host>:9223/json` — pages from both apps appear, because the embedded browser's debugging port is fixed and the `--port` value is only a relay.
- **Expected:** each boot exposes only its own app, or the boot refuses a second head while one is up.
- **Actual:** a parallel agent's script drove the other agent's window (it may have opened a native dialog there); earlier, boots also stopped each other's apps with `taskkill`.
- **Encountered in:** `*build-phase Sevak` of 2026-10-05 (repair pass and cluster smokes).
- **Workaround:** one booted head at a time; drivers pin the page by its target id.
- **Suggested fix:** give each boot its own WebView2 debugging port (pass it to the head) and its own process filter for `stop`; or take the repository lock for the whole boot-to-stop span so a second head waits.

### TF-004 — The verdict counts a unit test as on-app acceptance for a row whose app test was skipped

> ✅ **Closed 2026-10-07** — re-checked here: 2026-10-07 verify: tf-verify-tests.sh --base <cdp> --spec tests/verify/p3/sevak-p3.spec.ts WITHOUT --no-unit (unit tests ran, 1878 passed). tests.json source browser+unit: REQ-FN-055, FN-056, UI-068, RAG-056, RAG-057, RAG-058, RAG-059 (and FN-057) are NOT-TESTED with the skip reason plus 'a unit test does not measure on-app acceptance', although each has passing unit tests carrying its id (e.g. REQ-UI-068 4 passed, REQ-RAG-059 8 passed). tf-verify-verdict wrote NOT-TESTED / not Verified for each.

- **Severity:** major
- **Blocks:** no — the verifier graded from the app-only results file and kept the merged one for comparison; the run carried on.
- **Repro:** a row's browser test calls `test.skip()` (its acceptance cannot be observed on this host) while a unit test carries the same id; merge both result files and run `tf-verify-verdict.sh --apply`.
- **Expected:** a row whose on-app test was skipped is "not measured" on acceptance, whatever unit tests say.
- **Actual:** the merge has no notion of "skipped on the app", so 8 Sevak rows (REQ-FN-055, FN-056, UI-065, UI-068, RAG-056, RAG-057, RAG-058, RAG-059) would have scored acceptance PASS on unit tests alone and could reach Verified once render and parity pass.
- **Encountered in:** `*build-phase Sevak` re-verify of 2026-10-05.
- **Workaround:** grade from the app-only `tests.json`; keep `tests-with-unit.json` aside.
- **Suggested fix:** in the merge, a skipped on-app result for a UI or FN row wins over any unit result and is reported as not measured, naming the skip reason.

### TF-005 — `*verify all` grades only the appPhase checklist, so earlier phases are never graded

- **Severity:** major
- **Blocks:** no — phase 3's verify finished; the 86 built rows of phases 1 and 2 stayed ungraded.
- **Repro:** with `appPhase: 3`, run `*verify all Sevak`, as the status advised for the phase 1 and 2 rows.
  ```text
  bash .tfcore/utils/tf-verify-list.sh Sevak all
  -> # tf-verify-list — Sevak — docs/Sevak-P3-Checklist.md — phase 3 — scope all
  ```
- **Expected:** a way to grade phase 1 and phase 2, and a suggested command that says which phase it grades.
- **Actual:** `verify-phase.md` reads the checklist `appPhase` names and never passes `--phase` to `tf-verify-list.sh`, so only `Sevak-P3-Checklist.md` was graded. Phases 1 and 2 hold 50 Needs re-verify and 36 built-not-verified rows.
- **Encountered in:** `*verify all Sevak` of 2026-10-10 and 2026-10-11.
- **Workaround:** none through the command.
- **Suggested fix:** let `*verify` take `--phase N` and `--phase all`; make the verdict, the ledger and the telemetry follow the phase graded; name the phase in the status's next command.

### TF-006 — The menu check reports the theme menu on Login as "does nothing when clicked" although it switches the theme

> ✅ **Closed 2026-10-21** — re-checked here: 2026-10-21 tf-verify-screens.sh --screen welcome=/welcome --cdp on the Windows head: render OK, visual OK, light + dark themes, no menu finding (the workspace switcher no longer reads as opening nothing).

> Filed by Sevak as TF-005 on 2026-10-14; renumbered TF-006 by the TechieFlow team because TF-005 is the `--phase` entry above.

- **Severity:** minor
- **Blocks:** no — it fails one row's render check (Sevak REQ-FN-036) on a working control; every other check ran.
- **Repro:** Sevak Windows head over CDP, AppManager mode, 2026-10-14. `tf-verify-screens.sh --list … --cdp <url>` on `/login` reports `"Change theme › Light" does nothing when clicked` (also Dark and Match system), and says "the app has no dark theme" on every screen. Driving the same menu by hand over CDP: "Dark" sets `<html class="dark" data-theme="dark">` and repaints the page dark.
- **Expected:** a menu item that changes the document's theme class and repaints the page counts as doing something; "no dark theme" is not reported for an app whose own toggle switches to dark.
- **Actual:** the check in `tf-menus.mjs` reports the three items as doing nothing on `/login`, and the screen fails render.
- **Encountered in:** the Sevak phase-1 fix run, 2026-10-14. The same check also reports the workspace switcher on `/welcome` as "opens nothing when clicked" (Sevak REQ-RAG-054, REQ-RAG-055), while by hand it opens its panel (`aria-expanded="true"`) and closes again.
- **Workaround:** none in the app; the rows stay below Verified with this finding named.
- **Suggested fix:** in `tf-menus.mjs`, compare the document's class and `data-theme` attributes and the painted background before and after the click, after the menu has closed, and treat a change in any of them as an effect.

### TF-007 — The mockup check reads a mockup's colours in the middle of its CSS fade, so dark mode is graded against the light colour

> ✅ **Closed 2026-10-22** — re-checked here: 2026-10-22 tf-mockup-parity.sh --cdp on the Windows head, --screen setup-wizard=/setup?step=2, light and dark at 1280 and 390: 0 findings; wizard-provider-builtin no longer reads mockup neutral, app accent. REQ-UI-022, REQ-FN-009, REQ-FN-050 Verified.

- **Status:** fixed upstream 2026-10-21, ships in TechieFlow v1.2.1; not yet re-checked here.
- **Severity:** minor
- **Blocks:** yes — for three rows only (Sevak REQ-UI-022, REQ-FN-009, REQ-FN-050): their screen's mockup check fails on this alone, so they cannot reach Verified. Every other check passes, and the run carried on.
- **Repro:** Sevak Windows head over CDP, 2026-10-20. `tf-mockup-parity.sh --cdp <url> --screen setup-wizard=/setup?step=2 --list tests/.artifacts/verify/list.json` reports `semantic colour differs — mockup neutral, app accent` on `wizard-provider-builtin`, in dark mode only (1280 and 390). The mockup row is `.radio-row.selected`, and `.radio-row` has `transition: all .12s`. Read in headless Chromium:
  ```text
  light                      rgb(238, 242, 255)   -> neutral
  dark, read at once         rgb(238, 242, 255)   -> neutral (still the light colour)
  dark, read after 400 ms    rgb(35, 42, 77)      -> accent (the settled dark colour)
  ```
  The app's row settles to the same `#232a4d` in dark mode.
- **Expected:** the mockup is read after its theme change has finished painting, so the settled dark colour is compared.
- **Actual:** the mockup is read straight after `data-theme="dark"` is set, while the fade is still running, so the light colour is compared with the app's dark one.
- **Encountered in:** Sevak `*fix-issues` for the 2026-10-20 amendment (the setup wizard's model step).
- **Workaround:** none in the app; the app is right. The three rows stay `Implemented` with this finding named.
- **Suggested fix:** in `tf-mockup-parity.mjs`, after putting a theme on the mockup, turn transitions off (`*{transition:none!important}`) or wait for `getAnimations()` to finish before reading styles. The app side may need the same.

### TF-008 — The self-check says `tf-split-brd` reads 52 of 55 BRD items on Sevak

- **Severity:** minor
- **Blocks:** no — no command of this run reads the split; the other two BRDs read fully (75 of 75, 23 of 23).
- **Repro:** `bash .tfcore/utils/tf-phase.sh start fix-issues Sevak`, 2026-10-20, prints `FAIL  tf-split-brd  Sevak: reads 52 of 55 BRD items`; `bash .tfcore/utils/tf-selfcheck.sh --report` prints the same line.
- **Expected:** every BRD item is read, or the line names the three it skipped.
- **Actual:** three items are not read, and the line does not say which file or which items. The three BRDs hold 87, 63 and 23 `**BRD-n**` bullets as written (struck-out ones included), so the count of 55 is the checker's own.
- **Encountered in:** the start of Sevak `*fix-issues`, 2026-10-20.
- **Workaround:** none needed for this run.
- **Suggested fix:** have the self-check print the file and the ids it could not read.

### TF-009 — The verdict says "no unit test carrying its id" for a row whose unit tests ran and passed

- **Status:** fixed upstream 2026-10-21, ships in TechieFlow v1.2.1; not yet re-checked here.
- **Severity:** minor
- **Blocks:** no — the row stays `Implemented` by the TF-004 rule either way; only the reason written into the checklist is wrong.
- **Repro:** Sevak REQ-NFR-010, 2026-10-20. Two unit tests named `REQ-NFR-010 …` passed and its on-app test was skipped as not measurable. `tests.json` holds `"result": "NOT-TESTED", "passed": 2`. `tf-verify-verdict.sh --apply` writes `not observable — NFR row with no perf-budget and no unit test carrying its id`.
- **Expected:** the Remark says the unit tests passed but do not count while the on-app test was skipped (TF-004).
- **Actual:** the Remark says no unit test exists.
- **Encountered in:** Sevak `*fix-issues` for the 2026-10-20 amendment.
- **Workaround:** the row's Remark was extended by hand with the two tests' names.
- **Suggested fix:** in the verdict, test `NOT-TESTED` with `passed > 0` before the NOT-OBSERVABLE branch and write the TF-004 reason.

### TF-010 — `data-tf-sample` does not exempt a badge whose colour follows the app's real data

> ✅ **Closed 2026-10-22** — re-checked here: 2026-10-22 *fix-issues verify, Windows head: tasks, welcome and backup each 0 mockup findings in light and dark; the data-tf-sample badges are no longer graded on colour. REQ-RAG-054, REQ-RAG-055, REQ-UI-066, REQ-UI-074 Verified (the remaining nav finding was the app's, fixed in MainLayout.razor.css).

- **Status:** fixed upstream 2026-10-21, ships in TechieFlow v1.2.1; not yet re-checked here.
- **Blocks:** yes — for four Sevak phase 3 rows only (REQ-UI-066, REQ-RAG-054, REQ-RAG-055, REQ-UI-074): every other check passes, and the run carried on.
- **Severity:** minor
- **Repro:** Sevak `*verify all Sevak --phase 3`, 2026-10-21. The owner marked `tasks-state-badge` (tasks.html), `setup-model-can-run` (welcome.html), `backup-gdrive-badge` and `backup-onedrive-badge` (backup.html) `data-tf-sample`. `tf-mockup-parity.sh` still reports, for example, `semantic colour differs — mockup positive, app negative` on `setup-model-can-run`: the mockup draws "Yes, it can run" and this PC truthfully shows "No".
- **Expected:** a box the mockup marks as sample data is not graded on what its sample says (its colour, text or state), only on whether the app draws the control there.
- **Actual:** `diff()` in `tf-mockup-parity.mjs` exempts a `data-tf-sample` box only when the app draws nothing at its place; when it draws the box, colour is compared like any other.
- **Encountered in:** the Sevak phase 3 verify after `*amend-docs` marked those boxes, 2026-10-21.
- **Workaround:** none taken. Marking the boxes `data-tf-state="variant-…"` instead would leave them out of the comparison, but that says "another state of the screen", which is not what they are.
- **Suggested fix:** for a `data-tf-sample` box the app does draw, compare presence and size, and skip the colour, text and badge clauses.

### TF-011 — A minimized Windows app window draws no frames, so every click in a check or test times out

- **Blocks:** no — restoring the window and running again passes; on 2026-10-22 it cost one failed test (REQ-RAG-059) and a wrong lead on three wizard rows.
- **Severity:** minor
- **Repro:** Sevak Windows head over CDP, 2026-10-22, during `*verify all Sevak --phase 3`. With the app's window minimized (and the Windows lock screen showing), in the page: `requestAnimationFrame` fired 0 times in 3000 ms while `document.visibilityState` was `visible` and `document.hasFocus()` was `true`. Every `locator.click` then fails with `Timeout … exceeded … waiting for element to be visible, enabled and stable` (here `#primary-source` on `/llm-settings`, REQ-RAG-059). `ShowWindow(hwnd, SW_RESTORE)` on the app's own window: 5 frames in 142 ms, and the same test passed. The wizard's `"Change theme › Light" could not be clicked (locator.click: Timeout 3000ms exceeded.)` in the 2026-10-21 reply has the same signature; the menu works on a window that draws (2026-10-22, steps 1 and 2, light and dark).
- **Expected:** the boot or each check notices a window that draws no frames, restores it (its own window only) or stops with "the app window is minimized, nothing can be clicked", instead of reporting each control as not clickable.
- **Actual:** each click is reported as a defect of the screen, in the app's rows.
- **Encountered in:** Sevak `*verify all Sevak --phase 3`, 2026-10-22.
- **Workaround:** before each test chunk, restore the app's own window (`ShowWindow` on its handle; no keyboard or mouse input) and check that frames are drawn.
- **Suggested fix:** in `tf-verify-boot.sh` (and before each screen in `tf-verify-screens.sh` / `tf-mockup-parity.sh`), count `requestAnimationFrame` callbacks for one second; on 0, restore the head's window by its recorded process id, count again, and if still 0, write a "not measured: window not drawing" result instead of click findings.

### TF-012 — The DevGuide work list finds no screens in an app whose code lives under `apps/`

- **Blocks:** no — the phase 3 DevGuide was written by reading the code directly; only the automatic list and its `--update` change detection are lost.
- **Severity:** minor
- **Repro:** Sevak, 2026-10-22, `*handoff-phase Sevak`. `bash .tfcore/utils/tf-devguide-list.sh Sevak --phase 3` (and with no `--phase`) prints `NOTHING: no routed page found in the code (no @page, [Route], or path: declaration outside samples and tests). Build first.` The app has 9 phase 3 pages, e.g. `apps/Sevak/Components/Pages/Life/Today.razor` carries `@page "/today"`.
- **Expected:** every `@page` in the app's projects is listed, wherever the solution keeps them.
- **Actual:** `tf-devguide-list.py` searches only `CODE_ROOTS = ("src", "source")` and lists `apps` in `SAMPLE_DIRS`, so a solution laid out as `apps/<App>/…` (Sevak's `Sevak.slnx`: `apps/Sevak`, `apps/Sevak.Core`, `apps/SevakDb`) has no code at all to the script.
- **Encountered in:** Sevak `*handoff-phase`, 2026-10-22.
- **Workaround:** the guide's entries were read at file and line by hand.
- **Suggested fix:** take the code roots from the solution file's project paths (`*.slnx` / `*.sln`), or from a `codeRoots:` key in `core-config.yaml`, and treat `apps/` as samples only on a library.

### TF-013 — A Mac Catalyst boot cannot pass the verification settings to the app, so it would open the owner's real data

- **Blocks:** yes for the Mac head — a boot would run on `~/Library/Application Support/TechieDesk` and, outside verification mode, install the `com.techiedesk.scheduler` launchd agent. Not blocking for the Windows head.
- **Severity:** major
- **Repro:** Sevak, 2026-10-25, `*verify all Sevak --phase all --head maccatalyst`. Read, not run: `tf-verify-boot.sh` starts the app with `open -n`, and `tf-appium.mjs` `openSession()` opens the mac2 session with `appium:appPath` and `appium:skipAppKill` only. Neither carries an environment variable, so `SEVAK_VERIFICATION_MODE` and `AppDb__DataDirectory` cannot reach the app.
- **Expected:** a Mac head can start on a throw-away data folder, as the Windows head can.
- **Actual:** the boot controls no environment for the app.
- **Encountered in:** Sevak `*verify`, 2026-10-25.
- **Workaround:** `tests/verify/boot-safe-mac.sh`. It writes `appsettings.Production.json` into the built bundle with `AppDb:DataDirectory` and `Sevak:VerificationMode`, and refuses to go on unless the app's log names the fresh folder. First run 2026-10-25 (`boot-safe-mac.sh verify-all`): the build passed, the app's log named `tests/.artifacts/smoke-data/20261025T101257Z-verify-all/data`, and the real database and launchd agent were unchanged. AppManager and IMAP settings still cannot reach the app this way.
- **Suggested fix:** let `tf-verify-boot.sh start --head maccatalyst` take `--env NAME=VALUE` (repeatable). Pass each pair to `open` as `--env NAME=VALUE`, and to `openSession()` as `appium:environment` (a mac2 session relaunches the app, so both need it). Also let a project name a pre-launch hook script in `core-config.yaml` that the boot runs after the build and before the first launch.

### TF-014 — On a Mac Blazor Hybrid head no screen past the first can be reached, and the verdict grades that as a render failure

- **Status:** fixed upstream 2026-10-29, ships in TechieFlow v1.2.2; not yet re-checked here.
- **Blocks:** no — the run went on; the rows were written "not driven" instead. Every UI row on the Mac head stays unproven until this is fixed.
- **Severity:** major
- **Repro:** Sevak, 2026-10-25, `*verify all Sevak --phase all --head maccatalyst`. The app booted on the First-run wizard. `tf-verify-screens.sh --appium` printed `render UNREACHABLE` for all 17 fixed-route screens, `/setup` included, though it was on screen. In the mac2 page source the web view's buttons carry no `label`, `title` or `value`, so "Set up later" cannot be found. The dry-run verdict then gave 17 Verified phase 1 rows `RENDER-FAIL` (REQ-UI-022, REQ-FN-036 …).
- **Expected:** a screen the tool could not reach is "not measured" (verify-phase.md: "a check that could not run is absent from the record"), and the screen already in the window is graded as reached.
- **Actual:** `tf-verify-verdict.py` (render check, `scr.get("render") == "UNREACHABLE"`) adds a failing render check, so a tool limit becomes a product defect.
- **Encountered in:** Sevak `*verify`, 2026-10-25.
- **Workaround:** the screens results were moved to `tests/.artifacts/verify/mac-unreachable/screens-p{1,2,3}.json` before each `--apply`, so the rows were graded on build and acceptance only.
- **Suggested fix:** grade UNREACHABLE as not measured when the boot is `mode=appium webview=yes`, and compare the first screen with the window before calling it unreachable. To drive the pages themselves, attach through the WKWebView's inspector (`isInspectable`, Safari remote automation) or have the app expose an in-process test bridge in verification mode.
- **Reply (TechieFlow team, 2026-10-29):** Fixed with one change, shared with Sevak TF-014. **Sign-in step:** with `--user` and `--password`, the Mac head now looks for the user and password fields inside the app's own window, types into them the way a Blazor Hybrid form takes text (`s.type`, Lekhak TF-026), and clicks "Sign in" or "Log in". Nothing is typed by screen position. **Where it cannot:** a web view that shows Appium one empty element, or controls with no label, has no field to find. The head then prints `LOGIN not driven — the Mac head cannot sign in: Appium sees the web view as one empty element …`, writes that to `screens.json` (`login`), and marks every screen it could not reach `NOT-MEASURED`, never `UNREACHABLE`. The verdict grades those rows as not driven: the status is kept, the Remark says `not measured — … (grade it on the web or Windows head)`, and no gate record or miss is written. A web view the head can see into (Lekhak's) is unchanged: a screen no link reaches is still UNREACHABLE. Proved on a stand-in Appium that serves saved element trees (`tests/maccatalyst/fake-appium.mjs`), with your shape and with a sign-in form the head can see. **Not run on a real Mac yet.** Regression cases `ch_015`, `ch_016`, `sv_014`. Miss `MISS-TechieFlow-20261029-02`. Two parts of your suggestion were not done. Grading the screen already in the window as reached: on an opaque web view the head cannot tell which screen is showing, and grading whatever is on view passed a wrong screen before (Lekhak TF-027), so only a screen whose route is `/` is graded that way. Attaching through the WKWebView inspector or an in-app test bridge needs a change in the app and a new driver; it is not in this fix. **Check it here:** on the Mac, `/TechieFlow:agents:verifier *verify all Sevak --phase all --head maccatalyst`. The screens it cannot reach print `NOT … not measured`, none `UNREACHABLE`, and no phase 1 row goes to RENDER-FAIL for them.

### TF-015 — The verify harness reads its settings from environment variables and a `.env.local` file, not from an appsettings-style file

> ✅ **Closed 2026-11-10** — re-checked here: Ran the reply's prompt 2026-11-09: tests/verify/testsettings.json carries the framework keys with empty values, testsettings.Local.json holds the test users and mailbox, boot-safe.sh and the specs read them through tf-testsettings.py / testsettings.ts, the Usage Guide's Test users table names TestUsers:<n>:Password; .env.local, .env.example and tests/verify/register-test-users.mjs deleted. grep -rn env.local tests docs/Sevak-UsageGuide.md finds only the test that asserts none is committed; *verify all Sevak --phase 1 signed in as test user 1 from the Local file (64 rows PASS).

- **Status:** fixed upstream 2026-11-05, ships in TechieFlow v1.3.0; not yet re-checked here.
- **Blocks:** no — the tests run; Sevak's own specs moved their values to a JSON settings file.
- **Severity:** minor
- **Repro:** Sevak, 2026-11-03, read not run: the harness takes its settings (test mailbox, AppManager test users, data folder, debugging address) from environment variables and `tests/verify/.env.local`, and the specs read them with `process.env`.
- **Expected:** stack rule Q1 and Q11.2 in `TechieFlow-Stack-Defaults-DotNet.md`: configuration lives in appsettings-style files with no second mechanism. For tests: a committed JSON file with every key and empty values, and a git-ignored local JSON file laid over it.
- **Actual:** a second mechanism (environment variables plus a `.env` file) holds the test settings.
- **Encountered in:** Sevak public-readiness clean-up, 2026-11-03 (a Qdrant key had been put in `QDRANT_API_KEY`).
- **Workaround:** Sevak's spec values live in `tests/verify/testsettings.json` and the git-ignored `testsettings.Local.json`, read by `tests/verify/testsettings.ts`. The harness's own settings stay where the harness reads them.
- **Suggested fix:** let the harness read the same two JSON files and drop `.env.local` and the environment variables. The library fixes it on its own schedule.
- **Reply (TechieFlow team, 2026-11-05):** Fixed in the framework. One thing first: no framework script reads `.env.local`. In this repo it is read by Sevak's own `tests/verify/boot-safe.sh`, `tests/verify/register-test-users.mjs`, `tests/verify/p3/verify-env.ts` and the specs' `process.env` lines, so moving those is yours (prompt below). What the framework changed:
  1. **One settings reader.** New `.tfcore/utils/tf-testsettings.py` (for shell scripts) and `tf-testsettings.mjs` (for Node and specs) read `tests/verify/testsettings.json` with the git-ignored `tests/verify/testsettings.Local.json` laid over it key by key, the way your `testsettings.ts` does. Keys are written with colons, as in user secrets: `Verify:Runner`, `TestUsers:1:Password`. Your own keys (`QdrantApiKey` and the rest) stay as they are; the framework's keys sit beside them. The list is in `.tfcore/templates/verify/testsettings.json`.
  2. **The boot.** `tf-verify-boot.sh` reads `Verify:Runner`, `Verify:BootWaitSeconds`, `Verify:WindowsAppData` and `Verify:AppEnv` from those files. `Verify:AppEnv` is handed to the app as `--env NAME=VALUE`, so `SEVAK_VERIFICATION_MODE` and `AppDb__DataDirectory` can live there. For this release `TF_BOOT_RUNNER`, `TF_BOOT_WAIT` and `TF_WIN_APPDATA` still work, and each prints which key in which file to move it to.
  3. **The screen and mockup checks** take their sign-in from `Verify:Login` (or `Verify:Login:TestUser: "1"`, meaning test user 1's email and password) when the command line names none.
  4. **The register-test-users script.** New `.tfcore/utils/tf-register-test-users.mjs`, built from yours. It registers each `TestUsers:<n>` that has an email and no password yet, through AppManager's public-key and register calls, and writes the new password into `testsettings.Local.json` only. It never prints a password, skips a user that already has one, and refuses to run while a verify is running. AppManager's address and key come from `AppManager:*` in the settings or from `--appsettings apps/Sevak/appsettings.Development.json`.
  5. **The rules.** The usage-guide template's Test users table, stack rule Q4a and the smoke-test policy now name `TestUsers:<n>:Password` in `testsettings.Local.json`. The framework's `.gitignore` block adds that file.

  Regression case `sv_015`. **Proved** on a stand-in AppManager: one user registered, the other skipped, the password only in the Local file, the committed file unchanged. **Read only on your repo:** `tf-testsettings.py show` reads your two files, and `TF_BOOT_RUNNER=windows tf-verify-boot.sh start --dry-run` prints the move-it warning. Not run against the real AppManager: that would create accounts. **Check it here:** paste into Sevak's agent: `Move Sevak's verify settings off tests/verify/.env.local: add the keys of .tfcore/templates/verify/testsettings.json to tests/verify/testsettings.json with empty values, move each value from .env.local into tests/verify/testsettings.Local.json (test users under TestUsers:1 to 3, the mailbox under Sevak's own keys), make the specs, verify-env.ts and boot-safe.sh read them through .tfcore/utils/tf-testsettings.mjs or tf-testsettings.py, use node .tfcore/utils/tf-register-test-users.mjs --appsettings apps/Sevak/appsettings.Development.json in place of tests/verify/register-test-users.mjs, point the Test users table's Password column at testsettings.Local.json, then delete .env.local and .env.example.` Done when `grep -rn env.local tests docs/Sevak-UsageGuide.md` finds nothing and `*verify all Sevak --phase 1` signs in as before.

### TF-016 — The test-users rule allows a Register submit with test user 1's address, which creates that user when AppManager no longer holds it

- **Status:** fixed upstream 2026-11-05, ships in TechieFlow v1.3.0; not yet re-checked here.
- **Blocks:** no — Sevak's REQ-UI-006 test now signs in as test user 1 first and never submits Register unless that sign-in works.
- **Severity:** major
- **Repro:** Sevak, 2026-11-03. `tf-test-users-check.py` and `verify-phase.md` step 4 say the automated Register row checks "the email already in use path using test user 1", and the check passes a Register submit whose only address is a Test users address. On 2026-11-03 test user 1 (`sevak-owner@techierathore.com`) no longer signed in on the production AppManager (`INVALID_CREDENTIALS` from the first attempt). The REQ-UI-006 test, written to that rule, submitted Register with that address and its password, and AppManager created the account (it is now user 14).
- **Expected:** no automated test can create an account on a shared AppManager, whatever the state of the Test users on the server.
- **Actual:** the rule assumes test user 1 exists. When it does not, the "email already in use" path becomes "register creates an account", and the check still passes.
- **Encountered in:** Sevak `*fix-issues`, 2026-11-03, `tests/verify/p1/a-setup-shell-auth.spec.ts` (REQ-UI-006).
- **Workaround:** the test signs in as test user 1 first and skips, never submitting Register, when that sign-in is refused.
- **Suggested fix:** in `verify-phase.md` step 4 and the check's docstring, require a successful sign-in as test user 1 in the same test before any Register submit; have `tf-test-users-check.py` flag a Register submit with a Test users address that no sign-in with the same address comes before.
- **Reply (TechieFlow team, 2026-11-05):** Fixed as you suggested. `tf-test-users-check.py` now allows a Register submit (or a register call) that uses a Test users address only when the same test signs in with that address earlier and stops between the sign-in and the submit. A stop is a skip, a return, a throw or an assertion. The address may be written out, kept in a constant, or typed by name (`OWNER_EMAIL`). Anything else fails: `register: submits Register with a test user's address with no successful sign-in as that user before it …`. A sign-in form's own submit button is not counted as a Register submit. The same sentence is now in verify-phase step 4, the verifier, the check's own text and the usage-guide template. Stack rule Q4a now says the owner-run register-test-users script is the only place a test user is ever registered, never a verify test. Regression case `sv_016`: your 3 Nov test shape fails, today's passes, and a sign-in with no stop after it still fails. **On your repo:** the check passes. REQ-UI-006 signs in at line 397, stops at line 399 when the sign-in is refused, and submits at line 408. **Across the other projects** one new finding, in TfLens (`tests/verify/ui-auth-shell.spec.ts:129`); the owner has a prompt for TfLens's agent. **Not ours, for you:** AppManager user 14, created on 3 Nov, is still on the production AppManager unless someone has deleted it. **Check it here:** paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase 1`. REQ-UI-006 does not fail on gate test-users.

### TF-024 — The screen check grades a control inside a `display: none` ancestor as visible with zero width

> ✅ **Closed 2026-11-11** — re-checked here: 2026-11-10 triage-and-fix: visibility hidden taken off the chat-pane column (display none kept); tf-verify-screens --screen document-library=/workspace/default/documents --widths 1280,1024: visual OK, no 'has zero width' (render EMPTY only because that boot had no documents seeded).

- **Status:** fixed upstream 2026-11-10, in this project's `.tfcore/` since the framework update of 2026-11-10; not yet re-checked here.
- **Blocks:** no — Sevak adds `visibility: hidden` beside `display: none` on its hidden chat-pane column, which every control inside inherits.
- **Severity:** minor
- **Repro:** `tf-verify-screens.sh` on a screen whose mockup hides a region at one width (Sevak's chat pane at a phone or narrow width) and whose app hides it the same way with `display: none` on the region. `inspect()`'s `vis(el)` reads only the control's own computed style, so each anchored control inside reads `visible: true` with `w = 0`, and the visual check fails with `anchored control "assistant-pane-model" has zero width` — while `hiddenByWidth` already excused the same anchors for that width.
- **Expected:** a control whose ancestor is not rendered is not visible (`el.checkVisibility()` or an `offsetParent` test, as `hiddenByWidth` already uses), so the excuse for that width applies.
- **Actual:** visual FAIL on a control that is correctly hidden.
- **Encountered in:** Sevak verify of Document library at `--widths 1280,1024`, 2026-11-09.
- **Workaround:** above.
- **Suggested fix:** in `vis(el)`, use `el.checkVisibility({ visibilityProperty: true, opacityProperty: true })` when present.
- **Reply (TechieFlow team, 2026-11-10):** Fixed, with TF-020: one fault, one change. In `tf-verify-screens.mjs`, `vis(el)` now also looks at every box around the control and returns not visible when one of them has `display: none`. The controls in your chat pane's hidden column are then present and not visible, so nothing is graded on them: no `has zero width`, and no "not on the page" either. Your suggestion was `el.checkVisibility(...)`. We walk the parents instead, because `checkVisibility` also answers false for a `display: contents` wrapper and for a box inside a fade that has not finished, and either would hide real controls from the check on other projects. `visibility: hidden` on a box was already seen, since it is inherited. Regression case `sv_024`: a pane hidden at 1024 px in the mockup and the app reads OK at 1280 and 1024; a control on view that really has no width is still reported. Both checks fail on the script you had (`assistant-pane-model has zero width` at 1024). **Proved on a fixture, not on your running app.** **Not changed:** a control the app hides where its mockup shows it at that width is not a finding of this check, as before for a control hidden by its own style. **Check it here:** paste into Sevak's agent: `Take visibility: hidden off the chat-pane column, leaving display: none, then run tf-verify-screens.sh on Document library at --widths 1280,1024 as on 2026-11-09 and report its screen line.` The line carries no `has zero width` finding at 1024.


### TF-017 — The verdict rewrites a Blocked row to "Needs re-verify" when its screen fails a check

- **Status:** fixed upstream 2026-11-10, fixed in Sevak's `.tfcore/` by the framework update of 2026-11-10; not yet re-checked here.
- **Blocks:** no — the verifier put the two rows back to Blocked by hand, with their library reason.
- **Severity:** minor
- **Repro:** Sevak `*verify all Sevak --phase 4`, 2026-11-09. REQ-RAG-116 and REQ-UI-087 are Blocked (they wait for TechieRag 1.1.9, TR-RAG-056 and TR-RAG-057) and have no test. Their screen, Assistant, failed the render check (mockup sidebar items absent). `tf-verify-verdict.sh Sevak --apply` wrote both rows as `Needs re-verify` and replaced their Remarks, so the library reason was lost.
- **Expected:** verify-phase step 5 says "a `Blocked` row stays `Blocked` whatever its tests say" (TechieRag TF-009); the same should hold for every check. The verdict keeps Status `Blocked` and the reason, and only appends what this run found.
- **Actual:** Status and Remarks are rewritten from the first failing check.
- **Workaround:** the Status and the reason restored by hand after `--apply` (Blocked is not a `Verified`, so the hook allows it).
- **Suggested fix:** in `tf-verify-verdict.py`, read the row's Status first; for `Blocked`, keep it and its reason, and append this run's finding.
- **Reply (TechieFlow team, 2026-11-10):** Fixed in Sevak's `.tfcore/`, as you suggested. `tf-verify-verdict.py` reads the row's Status first. A `Blocked` row keeps Status `Blocked`, its % and its reason whatever the run found: a failing check, a failing test, no test at all, or a pass (TechieRag TF-009). What the run found is appended after the reason: `<your reason> · 2026-11-10 verify: still Blocked; this run found ⚠ render — <the finding>`. The reason is kept whole up to 35 words, and the next run replaces the appended part, so the Remark does not grow. No gate record and no miss is written for the row. Regression case `sv_017`, three checks; two fail on the script you had (it wrote `Needs re-verify` and dropped the reason). **Proved on a fixture, not on your checklist.** **Check it here:** paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase 4`. REQ-RAG-116 and REQ-UI-087 stay `Blocked` with their TechieRag reason first, and need no hand repair.

### TF-018 — A mockup control that belongs to a later phase can only be excused by editing the mockup, which a build may not do

> ✅ **Closed 2026-11-11** — re-checked here: 2026-11-10 triage-and-fix: data-tf-state="phase-5" (and its class show) replaced by data-tf-phase="5" on 286 elements in 35 mockups; the phase 4 screen and mockup checks of Assistant, Memory, Plan, Routines and Import read OK/PASS with no later-phase anchor owed.

- **Status:** fixed upstream 2026-11-10, fixed in Sevak's `.tfcore/` by the framework update of 2026-11-10; not yet re-checked here.
- **Blocks:** no (since 2026-11-09, `*amend-docs` marked these controls `data-tf-state="phase-5"` plus class `show`). Before that, every phase 4 screen fails the render check on `nav-ideas`, `nav-senders`, `nav-content` and `nav-browser` (phase 5 screens), and Memory, Plan and Routines also on `assistant-pane-member` (phase 5, BRD-292, REQ-UI-116).
- **Severity:** major
- **Repro:** `*verify all Sevak --phase 4`, 2026-11-09. `docs/mockups/assistant.html` draws the whole sidebar, phase 5 items included, with a `data-testid` on each; `docs/Sevak-Phases.md` puts Ideas, Senders, Content and Browser in phase 5. `tf-verify-screens.mjs` `grade()` reports each absent anchor as `blank-data`.
- **Expected:** a supported way to say "this anchor is owed from phase N", read by `tf-verify-screens.mjs` and `tf-mockup-parity.mjs` without touching the mockup: a `data-tf-phase="5"` mark that the mockups task writes, or a per-phase list (for example `tests/verify/later-phase-anchors.json`, or the phase's UIDesign naming the anchors it adds), so a later-phase anchor is not owed while the graded phase is earlier.
- **Actual:** the only excuses are `data-tf-state`, `data-state-testid` and `data-tf-sample` on the mockup itself, and the build and fix tasks may not edit `docs/mockups/`. The fix builder has no move left but faking the anchors in the app.
- **Workaround:** none. The anchors were not faked in the app; the spec side is MISS-Sevak-20261109-54 and -55.
- **Suggested fix:** `data-tf-phase="<n>"` on a control or a box around it, treated like `data-tf-state` when the list's `phase` is lower; and the mockups task writes it for every control whose BRD item belongs to a later phase.
- **Reply (TechieFlow team, 2026-11-10):** Fixed in Sevak's `.tfcore/`, the first way you suggested. A mockup control that a later phase builds carries `data-tf-phase="<n>"`, on the control or on a box around it. The screen check (`tf-verify-screens`), the mockup check (`tf-mockup-parity`) and the menu walk read it: while the phase being graded is lower than n the control is treated like another state of the screen, so it is not owed, and when the app does draw it, it is graded like any other. From phase n on the mark means nothing and the control is owed. The phase graded comes from `--phase N`, else from `list.json`, else from `appPhase`. The mockups task now writes the mark for every control that `docs/<App>-Phases.md` gives to a later phase. Regression case `sv_018`: graded as phase 4, controls marked `data-tf-phase="5"` pass both checks; graded as phase 5, both report them missing. On the scripts you had, phase 4 fails both. **Proved on a fixture, not on your app.** **Not done:** a per-phase list file (`later-phase-anchors.json`); one mark in the mockup is enough and keeps the mockup the one place that says it. **Your mockups today** carry `data-tf-state="phase-5"` on these controls, which still works and is left alone. To say it properly, paste into Sevak's agent: `/TechieFlow:agents:analyst *amend-docs Sevak` with the request `In every file under docs/mockups, replace data-tf-state="phase-5" (and the class show added with it) by data-tf-phase="5" on the same elements.` Then `*verify all Sevak --phase 4` reads the same as now, and in phase 5 the controls become owed without another mockup edit.

### TF-019 — The overlap check has no way to mark a deliberate edge handle or overlay, so the library's SidebarRail fails every screen

> ✅ **Closed 2026-11-11** — re-checked here: 2026-11-10 triage-and-fix: data-tf-overlay on sidebar-rail in 35 mockups and aria-hidden taken off the app's SidebarRail; tf-verify-screens on the five phase 4 screens at 1280 and 390: visual OK, no 'sidebar overlaps sidebar-rail'.

- **Status:** fixed upstream 2026-11-10, fixed in Sevak's `.tfcore/` by the framework update of 2026-11-10; not yet re-checked here.
- **Blocks:** no — Sevak marks the rail `aria-hidden="true"` (a pointer-only duplicate of `sidebar-trigger`, tabindex -1), which the check's `vis()` skips; the rail still works by mouse.
- **Severity:** minor
- **Repro:** any Sevak screen at 1280 px. TrBlazeUI's `SidebarRail` is `absolute inset-y-0 w-4 -translate-x-1/2 -right-4`: a 16 px hit area centred on the sidebar's edge, half of it over the sidebar, exactly as the mockup's `.sidebar-rail` (6 px, `right:-3px`) is drawn. `grade()` reports "sidebar overlaps sidebar-rail at 1280px" because half the rail's box is inside the sidebar (over the 25 % floor) and the rail is not the sidebar's descendant in the measured list.
- **Expected:** a control drawn the same way in its mockup is not an overlap; or a supported mark (`data-tf-overlay`) for a control that sits on another by design.
- **Actual:** only `aria-hidden="true"`, an ancestor relation, or more than 90 % containment excuse it.
- **Workaround:** `aria-hidden="true"` on the rail, as above. It is right for assistive technology here, but it is not a general answer: a focusable overlay cannot take it.
- **Suggested fix:** compare the pair against the mockup at the same width and skip an overlap the mockup also draws; or honour `data-tf-overlay` on the mockup control.
- **Reply (TechieFlow team, 2026-11-10):** Fixed in Sevak's `.tfcore/`, the second way you suggested. A control the mockup marks `data-tf-overlay`, on the control's own tag, is left out of the overlap check and still graded on everything else (present, filled, not off screen, not zero size). The mockups task now says when to write it: a control drawn over its neighbour on purpose, such as an edge grab handle or a floating button. Regression case `sv_019`: a 16 px rail half over the sidebar, marked in the mockup, is no finding; two unmarked buttons on top of each other on the same screen are still reported, and only that pair. On the script you had, the rail fails (`sidebar overlaps sidebar-rail at 1280px`). **Proved on a fixture, not on your app.** **Not done:** comparing every overlap with the mockup at the same width; a mockup is not drawn to the pixel, and that would excuse real overlaps a mockup happens to share. **Check it here:** paste into Sevak's agent: `/TechieFlow:agents:analyst *amend-docs Sevak` with the request `Add data-tf-overlay to the sidebar-rail button in every file under docs/mockups, and take aria-hidden="true" off the app's SidebarRail.` Then a verify of any screen at 1280 carries no `sidebar overlaps sidebar-rail` finding.

### TF-020 — `vis()` does not look at ancestors, so the controls inside a `display: none` column are reported as having zero width

> ✅ **Closed 2026-11-11** — re-checked here: Same change and check as TF-024 (2026-11-10): no zero-width finding for controls inside the display:none pane column.

- **Status:** fixed upstream 2026-11-10, in this project's `.tfcore/` since the framework update of 2026-11-10; not yet re-checked here.
- **Blocks:** no — Sevak no longer renders the chat pane's column on a phone-width window (it opens as a sheet from "Ask Sevak").
- **Severity:** minor
- **Repro:** Sevak Memory at 390 px before fix cycle 1: the pane column had `display: none`; the screen reported "anchored control assistant-pane-model has zero width" and eight more, for controls nobody can see.
- **Expected:** a control whose ancestor is `display: none` is not visible, so it is neither "visible with zero width" nor owed (the mockup hides the same pane at that width).
- **Actual:** `vis()` reads only the element's own `display`, `visibility` and `opacity`.
- **Suggested fix:** use `el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })`, or test `offsetParent === null` for a non-fixed element.
- **Reply (TechieFlow team, 2026-11-10):** Fixed by the same change as TF-024; the reply is under that entry. Regression case `sv_024`. The 390 px case you met on Memory is the same path: a control inside a `display: none` box is not visible, so it is neither "visible with zero width" nor owed when the mockup hides it at that width.


### TF-021 — A verify with scope `all` runs every phase's browser specs on one boot, and the earlier phases' specs break the state the graded phase's specs need

- **Status:** fixed upstream 2026-11-10, in this project's `.tfcore/` since the framework update of 2026-11-10; not yet re-checked here.
- **Blocks:** no — the phase 4 verify ran its browser specs with `--spec tests/verify/p4`, merged with one unit run, as the task's part-and-merge procedure allows; the work carried on.
- **Severity:** minor
- **Repro:** `*build-phase Sevak` chains the verifier with scope `all` on `--phase 4`. `tf-verify-tests.sh` sees scope `all` and runs every spec under `tests/verify/` (192 tests, 72 minutes). The phase 1 specs expect a fresh install, the phase 2 specs change the theme and the language and restore a backup, a phase 3 spec expects the first sign-in; when the phase 4 specs run, the shell is on another page and the pane's Send is disabled, so 50 of 80 phase 4 rows fail on `toBeVisible` (two runs, 2026-11-09). The morning fix cycle passed because an id-list scope `--grep`s only those rows' tests.
- **Expected:** with `--phase N`, the browser run covers the specs carrying that phase's row ids, as an id-list scope does; `--phase all` grades the phases one boot each.
- **Actual:** `ui`, `functional` and `all` always run the whole tree.
- **Encountered in:** Sevak `*build-phase` phase 4, 2026-11-09 08:37Z and 09:53Z runs (`tests/.artifacts/verify/playwright.json`).
- **Workaround:** `--spec tests/verify/p4` for the browser part, merged with the unit run.
- **Suggested fix:** when `--phase N` is given with a word scope, grep the specs by the phase's row ids and print which specs ran.
- **Reply (TechieFlow team, 2026-11-10):** Fixed as you suggested, in three places. (1) `tf-verify-list.py` writes the phases that have a checklist into `list.json` (`"phases": [1, 2, 3, 4, 5]` here). (2) `tf-verify-tests.sh`: on a project with more than one phase checklist, scope `ui`, `functional` or `all` passes Playwright `--grep` with the row ids of the phase in `list.json`, the way a list of ids already did. It prints `browser tests: ran only the tests carrying the 80 row id(s) of phase 4 …` and then `browser tests: specs run (N file(s)): …` with each spec file and its test count. `--all-specs` still runs every phase's specs. A project with one checklist runs everything, as before. The unit tests are not filtered. (3) `--phase all`: `verify-phase.md` and the line `tf-verify-list.sh … --phase all` prints now say each phase is graded on its own boot (steps 1 and 3 to 7 once per phase), no longer every phase on one boot. Regression case `sv_021`, five checks; three fail on the scripts you had. **Read only on your repo:** phase 4's 80 ids keep 47 of the tests under `tests/verify/p4` and none of the 145 under `p1`, `p2` and `p3`. One thing to know: a test whose title carries no row id is no longer run by a phase verify. Here that is two tests. `tests/verify/p4/ready.spec.ts` ("phase 4 app is set up and signed in"): every phase 4 spec calls `ready()` itself, so nothing waits on it. And "ChatPane in Pane mode on another screen …" in `assistant-screen.spec.ts`: with no id it never counted for a row; put its row's id at the start of the title if it should. `--spec <file>` still runs either by name. **Not run on your app.** A test whose title mentions a phase 4 id while it sits in another phase's spec is still kept: the filter reads titles, not folders. **Check it here:** paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase 4`. The `specs run` line names only files under `tests/verify/p4`, and the `--spec tests/verify/p4` workaround can go.


### TF-022 — `tf-verify-boot.sh` says "10 other Windows head(s) up" when one Sevak.exe is running

- **Status:** fixed upstream 2026-11-10, fixed in Sevak's `.tfcore/` by the framework update of 2026-11-10; not yet re-checked here.
- **Blocks:** no — the boot worked and the verify carried on; the message was checked against the process list and ignored.
- **Severity:** minor
- **Repro:** `bash tests/verify/boot-safe.sh p4-verify --port 9333` on a machine where `Get-CimInstance Win32_Process -Filter "Name='Sevak.exe'"` lists one process prints `tf-verify-boot: 10 other Windows head(s) up — this one gets DevTools port 29333`.
- **Expected:** the count names this app's running heads, or says what it counted (other apps' WebView2 DevTools ports, stale `boot.json` records).
- **Actual:** a number no process list matches, so a reader looks for ten orphaned apps that are not there.
- **Encountered in:** Sevak phase 4 verify boots, 2026-11-09 (`tests/.artifacts/verify/boot.json`).
- **Workaround:** none needed.
- **Suggested fix:** count processes of the head's image name from `boot.json`, or name the source of the count in the message.
- **Reply (TechieFlow team, 2026-11-10):** Fixed in Sevak's `.tfcore/`, both parts of your suggestion. The count was every `boot-*.json` in `tests/.artifacts/verify/` not marked stopped, and an app that is closed by hand or killed never passes through `stop`. `tf-verify-boot.sh` now asks Windows once (`tasklist.exe`) and counts a record only while a process it names is still running under the same program name. A record whose app is gone is marked stopped, with the reason. The line names what it counted: `1 other Windows head(s) up, by this folder's boot records: port 9341 (Sevak.exe, pid 16764) …`. When Windows cannot be asked, the records are counted as before and the line says they were not checked. New command: `bash .tfcore/utils/tf-verify-boot.sh heads` prints the count on its own. Regression case `sv_022`, three checks; all fail on the script you had. **Run on your real records, 2026-11-10:** ten records said up; nine apps were gone, and the tenth's process id (17636) now belonged to `msedge.exe`, which is why the program name is compared too. Result: `0 other Windows head(s) up`. Those ten records are now marked stopped in your `tests/.artifacts/verify/`; nothing else there was changed. **Check it here:** `bash .tfcore/utils/tf-verify-boot.sh heads` with one Sevak window open prints `0 other` from another port's point of view, or names that one window by port.

### TF-023 — The mockup-parity check reads a native checked checkbox as "no fill, no icon", so a component library's checkbox fails the icon and colour clauses on every screen that draws one

> ✅ **Closed 2026-11-11** — re-checked here: 2026-11-10 triage-and-fix: tf-mockup-parity on Import (/tools/import) at 1280 and 390, light and dark: PASS, 0 findings, no import-tick finding; the nine Import rows are Verified.

- **Status:** fixed upstream 2026-11-10, in this project's `.tfcore/` since the framework update of 2026-11-10; not yet re-checked here.
- **Blocks:** no — the nine Import rows stay below Verified on this one finding and everything else carried on; the control itself is right.
- **Severity:** minor
- **Repro:** `docs/mockups/import.html` draws `import-tick` as `<input type="checkbox" checked>`; Chromium paints its fill and tick glyph itself, so the computed style the tool reads is transparent with no icon. The app's TrBlazeUI `Checkbox` draws the same checked box as DOM (primary fill, an svg tick). `tf-mockup-parity.sh` then reports `import-tick` icon ("app carries an icon the mockup does not") and colour ("mockup neutral, app accent") at 1280 and 390, light and dark — 8 findings, the only ones left on Import after the phase 4 fix cycle.
- **Expected:** a toggle is compared as a toggle: checked state and size, not the paint Chromium does for a native input.
- **Actual:** TF-035's toggle exemption covers the stroke clause only; icon and colour still compare computed styles.
- **Encountered in:** Sevak phase 4 verify, Import (`/tools/import`), `tests/.artifacts/verify/parity.json`, 2026-11-09.
- **Workaround:** none taken; a raw `<input type="checkbox">` is forbidden by the trblazeui persona, and hiding the tick to satisfy the measurement would make a worse control.
- **Suggested fix:** extend the toggle exemption to the icon and colour clauses (or compare `:checked` state and box size for inputs of type checkbox and radio).
- **Reply (TechieFlow team, 2026-11-10):** Fixed as you suggested, in `tf-mockup-parity.mjs`. A checkbox, radio or switch (`input[type=checkbox]`, `input[type=radio]`, `role="checkbox"`, `role="switch"`, `role="radio"`), on either side, is no longer compared by its icon, its colour or its badge shape, as it already was not by its border (Lekhak TF-035). What is drawn inside a toggle, the svg tick or a switch's thumb, is also no longer counted as an icon or a badge of the boxes around it; without that the finding would have moved from `import-tick` to the table cell. **Not done:** the checked state is not compared. The tick follows the app's data (your rows are ticked or not by what the user chose), so comparing it with the mockup's sample would fail honest screens. A toggle the app does not draw at all is still the screen check's finding. Regression case `sv_023`: your shape (a native checked checkbox in the mockup, a filled `role="checkbox"` button with an svg tick in the app) gives no finding on the toggle or on the card around it, a switch beside a native checkbox gives none either, and an icon added to an ordinary control is still reported. On the script you had, the same fixture gives your two findings word for word (`app carries an icon the mockup does not`, `mockup neutral, app accent`). **Proved on a fixture, not on your running app.** **Check it here:** paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase 4`. Import carries no `import-tick` finding at 1280 or 390, light or dark, and the nine Import rows are graded on their other checks.


### TF-025 — The mockup-parity check reads a native `<select>` as having no icon, so a component library's Select fails the icon clause wherever the mockup draws a plain select

- **Status:** fixed upstream 2026-11-11, fixed in Sevak's `.tfcore/` by the framework update of 2026-11-11 (evening); not yet re-checked here.
- **Blocks:** no — the control is right; Sevak's Support row stays below Verified for another reason (test user 1 has no issue), and the finding is noted beside it.
- **Severity:** minor
- **Repro:** `docs/mockups/support.html` draws `support-status-filter` as `<select class="input">`; Chromium paints its chevron itself, so the computed style shows no icon. The app's TrBlazeUI `SelectTrigger` (a `button` with `role="combobox"`) draws the same chevron as an svg. `tf-mockup-parity.sh --list … --cdp …` on Support reports `support-status-filter: app carries an icon the mockup does not` at 1280 and 390, light and dark (4 findings).
- **Expected:** a select is compared as a select, the way TF-023 now compares a checkbox: not by the chevron the browser paints for a native control.
- **Actual:** the icon clause compares a native select's computed style with the library's DOM.
- **Encountered in:** Sevak triage-and-fix of 2026-11-10, Support (`/support`), REQ-UI-033.
- **Workaround:** none taken; a raw `<select>` is forbidden by the trblazeui persona.
- **Suggested fix:** extend the TF-023 toggle exemption to `select` and `role="combobox"` for the icon clause (and the svg chevron inside the trigger is not an icon of the boxes around it).
- **Reply (TechieFlow team, 2026-11-11):** Fixed as you suggested, in `tf-mockup-parity.mjs`. A select (`<select>` or `role="combobox"`), on either side, is no longer compared by its icon, and the chevron drawn inside one is not counted as an icon of the boxes around it; without that the finding would have moved from `support-status-filter` to the filter bar. Only the icon clause changed: a select's colour, border and badge are still compared, because your mockup styles those itself. An icon the app adds to an ordinary control is still reported. Measured on the mockups of all 13 projects that have any: none draws a select as a styled box with an icon inside, so no project gains a finding from this. Case `sv_025` in `tests/faults/run.sh` (your shape: a native select in the mockup, a `role="combobox"` button with an svg chevron in the app) fails against the script you have and passes now. Proved on that fixture, not on the Sevak app. **Fixed in Sevak's `.tfcore/`:** deployed with `update-framework.sh` on 2026-11-11 (evening), once no Sevak run was in progress; all 169 framework files here match the framework repository. Check it: `bash .tfcore/utils/tf-mockup-parity.sh --list tests/.artifacts/verify/list.json --cdp <url>` on Support carries no `support-status-filter` finding.

### TF-026 — A phase verify cannot grade rows that need a second boot, and its test step neither survives a minimized window nor a running app

- **Blocks:** no — Sevak ran the parts by hand and merged them; every step is written in `docs/Sevak-Verification-Setup.md`.
- **Severity:** major
- **Repro:** `*verify all Sevak --phase 2` on 2026-11-11, Windows head over CDP. Three things, one cause (the test step assumes one boot it can leave alone):
  ```text
  1. seven rows are about the app in Hindi (the language applies at the next launch) and one about "restores on
     another install": on the one boot the task makes they can only skip, so they never get a verdict.
  2. the owner minimized the app window mid-run: tf-verify-screens.sh restores it (TF-011), tf-verify-tests.sh
     does not, and every test of the last spec file timed out on "waiting for element to be stable".
  3. tf-verify-tests.sh --base runs the unit tests while the app is up: MSB3027, Sevak.Core.dll "is locked by Sevak",
     ten retries per rung; the run took over ten minutes and reported nothing new.
  ```
- **Expected:** the task names a way to run a part of the rows on another boot (a relaunch on the same data folder, a second fresh install) and merge it; the test step restores the window before each spec file, as the screens step does; the unit tests run before the boot.
- **Actual:** each had to be worked out during the run.
- **Encountered in:** Sevak *triage-and-fix 2026-11-11, phase 2.
- **Workaround:** id lists (`tf-verify-list.sh … --json-out`, then `tf-verify-tests.sh --list`) per boot and `--merge`; `ensureDrawing` in `tests/verify/p3/cdp.ts`; `--no-browser` before the boot and `--no-unit` after it.
- **Suggested fix:** a `needs-boot:` note on a row (relaunch, second install, language) that the list prints as its own part; `tf-verify-tests.sh` calling the TF-011 restore before each spec file; unit tests first, before `tf-verify-boot.sh start`.

## Resolution status (TechieFlow team, 2026-11-11)

**Fixed in Sevak's `.tfcore/`** through the framework update of 2026-11-11 (evening). The same update carries the other fixes of that day (the changelog entry "Code review of 2026-11-10"): none is an entry of yours. Proved on a fixture, not on the Sevak app.

| ID | Fix | Check it here |
|---|---|---|
| TF-025 | Fixed upstream. The reply is under the entry. | a verify of Support; no `support-status-filter` icon finding at 1280 or 390, light or dark. |

## Resolution status (TechieFlow team, 2026-11-10, second run)

Fixed in Sevak's `.tfcore/` through the second framework update of 2026-11-10. With these four, no Sevak entry is open. All four were proved on fixtures; TF-022 was also run on this project's own boot records. Two more changes of the same day touch this project and are not entries of yours: a phase verify now prints every test it leaves out for having no row id (`NOT RUN (no row id) …`; here `p1/c-documents-data.spec.ts` "Data and storage buttons …", `p4/assistant-screen.spec.ts` "ChatPane in Pane mode …" and `p4/ready.spec.ts`), and the framework update no longer removes `.codex/agents/techierag.toml` and `trblazeui.toml`, which the library packages install.

| ID | Fix | Check it here |
|---|---|---|
| TF-017 | Fixed upstream. The reply is under the entry. | `/TechieFlow:agents:verifier *verify all Sevak --phase 4`. REQ-RAG-116 and REQ-UI-087 stay `Blocked` with their reason. |
| TF-018 | Fixed upstream. The reply is under the entry. | the `*amend-docs` prompt in the reply, then the same verify. |
| TF-019 | Fixed upstream. The reply is under the entry. | the `*amend-docs` prompt in the reply, then a verify of any screen; no `sidebar overlaps sidebar-rail`. |
| TF-022 | Fixed upstream. The reply is under the entry. | `bash .tfcore/utils/tf-verify-boot.sh heads`. |

## Resolution status (TechieFlow team, 2026-11-10)

Already in this project's `.tfcore/` through the framework update of 2026-11-10. They go out to the other projects with the next TechieFlow release. Each fix has a regression case in `tests/regression/run.sh` that fails against the scripts this project had before today's update and passes now. All three were proved on fixtures; none was run on the Sevak app.

| ID | Fix | Check it here |
|---|---|---|
| TF-020 | Fixed upstream with TF-024. The reply is under the entry. | as TF-024. |
| TF-021 | Fixed upstream. The reply is under the entry. | `/TechieFlow:agents:verifier *verify all Sevak --phase 4`. The `browser tests: specs run` line names only files under `tests/verify/p4`. |
| TF-023 | Fixed upstream. The reply is under the entry. | the same verify. Import carries no `import-tick` finding. |
| TF-024 | Fixed upstream. The reply is under the entry. | the prompt in the reply; Document library carries no `has zero width` finding at 1024. |

## Resolution status (TechieFlow team, 2026-11-05)

Ships in **TechieFlow v1.3.0**, the next release after v1.2.4. Already in this project's `.tfcore/` through the framework update of 2026-11-06. Each fix has a regression case in `tests/regression/run.sh` that fails against the v1.2.4 scripts and passes now.

| ID | Fix | Check it here |
|---|---|---|
| TF-015 | Fixed upstream. The reply is under the entry. | paste the prompt in the reply into Sevak's agent; then `grep -rn env.local tests docs/Sevak-UsageGuide.md` finds nothing. |
| TF-016 | Fixed upstream. The reply is under the entry. | `/TechieFlow:agents:verifier *verify all Sevak --phase 1`. REQ-UI-006 does not fail on gate test-users. |

## Resolution status (TechieFlow team, 2026-11-01)

Ships in **TechieFlow v1.2.4**, the next release after v1.2.3; already in this project's `.tfcore/` through the framework update of 2026-11-01. Each fix has a regression case in `tests/regression/run.sh` that fails against the v1.2.3 script and passes now.

| ID | Fix | Check it here |
|---|---|---|
| TF-008 | Fixed upstream in `tf-split-brd.py` and `tf-selfcheck.sh`. Your phase-2 BRD writes three items as `**BRD-171** (was BRD-49) — …`; the reader needed the dash right after the id. It now accepts a bracket there, and the self-check line names the BRD file and any id it could not read. On your docs: 52 of 55 → all 55. Case `sv_008`. | After the framework update: `bash .tfcore/utils/tf-selfcheck.sh --report`: expect "reads all 55 BRD items". |
| TF-011 | Fixed upstream in `tf-verify-screens.mjs` and `tf-mockup-parity.mjs`. On a desktop head both count animation frames before measuring. On none, they restore the head's own window once (ShowWindow by the process id the boot recorded). If it still draws none, the screen is NOT-MEASURED ("the app window is not drawing"), and the verdict grades its rows as not driven, never as click failures. Case `sv_011`. The restore was proved on a fixture, not on a real minimized window. | After the framework update: `*verify all Sevak --phase 3` on the Windows head with the window minimized: the window comes back and is graded, or the rows say not measured. |
| TF-012 | Fixed upstream in `tf-devguide-list.py`. The folders of the projects a root `*.slnx` / `*.sln` lists are code, and `apps/` is a samples folder only on a library. On your repo, phase 3: NOTHING → all 9 screens. The other 16 projects list what they did. Case `sv_012`. | After the framework update: `bash .tfcore/utils/tf-devguide-list.sh Sevak --phase 3`: expect the 9 phase-3 screens. |
| TF-013 | Fixed upstream in `tf-verify-boot.sh`, `tf-appium.mjs` and `tf-verify-native.mjs`. `start --env NAME=VALUE` (repeatable, any head) is kept in the boot record. It is passed to `open --env` on the Mac and to the mac2 session as `appium:environment`, since the session relaunches the app. The `core-config.yaml` pre-launch hook was not added. Case `sv_013`. Not proved on a Mac. | After the framework update: `bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst --env SEVAK_VERIFICATION_MODE=1 --env AppDb__DataDirectory=<a throw-away folder>` in place of `boot-safe-mac.sh`, then check the app's log names that folder. |

## Resolution status (TechieFlow team, 2026-10-29)

Ships in **TechieFlow v1.2.2**, the next release after v1.2.1. Already in this project's `.tfcore/` through the framework update.

| ID | Fix | Check it here |
|---|---|---|
| TF-014 | Fixed upstream. The reply is under the entry. | on the Mac, `/TechieFlow:agents:verifier *verify all Sevak --phase all --head maccatalyst`. The screens it cannot reach print `NOT … not measured`, none `UNREACHABLE`, and no phase 1 row goes to RENDER-FAIL for them. |

## Resolution status (TechieFlow team, 2026-10-21)

All three fixes ship in **TechieFlow v1.2.1**, the next release after v1.2.0. They are already in this project's `.tfcore/` through the framework update.

| ID | Fix | Check it here |
|---|---|---|
| TF-007 | Fixed upstream in `tf-theme.mjs`, as you suggested, plus one rule in `tf-mockup-parity.mjs` that the fix brought to light. (1) After a theme is put on a page, every fade and every animation that ends is run to its end before anything is read (`getAnimations()`, then `finish()`). A spinner, which never ends, keeps running. The mockup used to be read with no wait at all, so `.radio-row.selected` gave its light colour in dark mode. (2) With the mockup read in its settled dark colours, every nav item on Tasks, Welcome and Backup read "mockup accent, app neutral" at 1280. Your mockup's dark nav text is `#a6adc5`, a grey with a slight blue tint, and the app's is a near-white grey, `oklch(0.935 0.015 274)`. The colour check called the mockup's grey "accent". A colour under 25% saturation now counts as neutral. Measured on the mockups of 14 projects: tinted greys change class only in Sevak, TrBlazeUI and MyDiary-Kimi. Regression case `sv_007`: each of its two parts fails on the scripts you had. Miss `MISS-TechieFlow-20261021-01`. | **Proved on your app**, Windows head, 2026-10-21, old scripts then new on the same running app. `--screen setup-wizard=/setup?step=2`: old gives `wizard-provider-builtin: semantic colour differs — mockup neutral, app accent`; new gives no colour finding. **Still failing, and not TF-007:** both runs report `menu "Change theme › Light" could not be clicked (locator.click: Timeout 3000ms exceeded.)`, and the same for Dark and Match system, on this screen at 1280. So REQ-UI-022, REQ-FN-009 and REQ-FN-050 lose the colour finding but stay below Verified on this one. We have not found out whether the walk or the wizard is at fault. If the menu works by hand on the wizard, please file it as a new entry. Paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase 1`. The wizard rows no longer carry the dark-mode colour finding on `wizard-provider-builtin`. |
| TF-009 | Fixed upstream in `tf-verify-verdict.py`, as you suggested. A row whose unit tests passed while its on-app test was skipped is now checked before the "not observable" branch. Its Remark reads, for example, `2 unit test(s) named REQ-NFR-010 passed but do not count while its on-app test was skipped: <the skip's reason>`. The row's status is unchanged: it stays `Implemented` by the TF-004 rule. Regression case `sv_009` fails on the script you had. Miss `MISS-TechieFlow-20261021-02`. | Proved on a fixture built from your entry's numbers (`NOT-TESTED`, `passed: 2`). The tests file from your 2026-10-20 run is no longer in `tests/.artifacts/verify/`, so it was not replayed. On your next verify, REQ-NFR-010's Remark names the two passing unit tests instead of saying none exists, as long as its on-app test is still skipped. You can drop the hand-written extension. |
| TF-010 | Fixed upstream in `tf-mockup-parity.mjs`, as you suggested. A box the mockup marks `data-tf-sample` that the app does draw is graded only on being there with a size. Its colour, text and badge are not compared, and that holds for everything inside the box too. A sample box the app draws with no size is a finding. When the app draws nothing there, it is still "not measured", as before. Regression case `sv_010` fails on the script you had. It also proves that a badge without the mark is still graded. Miss `MISS-TechieFlow-20261021-03`. | **Proved on your app**, Windows head, 2026-10-21, `--screen tasks=/tasks --screen welcome=/welcome --screen backup=/settings/backup`, light and dark, old scripts then new. **Welcome: FAIL → PASS.** `setup-model-can-run` is gone. **Backup:** both badge findings are gone, but it still FAILs on one finding: `nav-backup` in dark mode, "mockup accent, app neutral". **Tasks:** `tasks-state-badge` did not appear in either run today. It still FAILs on `nav-tasks` in dark mode, the same as Backup, and on `tasks-card > div[1]: mockup carries an icon here; the app does not`, which the old script also reports. The nav finding is a real difference: the mockup draws the active nav item indigo in dark mode (`rgba(99,102,241,.22)`), and the app draws it grey. Either the app or the mockup changes; that choice is yours. So REQ-RAG-054 and REQ-RAG-055 (Welcome) can reach Verified. REQ-UI-066 (Tasks) and REQ-UI-074 (Backup) stay below Verified until the active nav colour is settled, and Tasks' icon finding too. Paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase 3`. |

## Resolution status (TechieFlow team, 2026-10-14)

| ID | Fix | Check it here |
|---|---|---|
| TF-006 | Fixed upstream in `tf-menus.mjs` and `tf-theme.mjs`. Three faults, all the checker's. (1) A menu click was judged by the address, the text, dialogs and zoom only. It now also compares the theme: the light/dark classes and `data-*theme` attributes on `<html>` and `<body>`, and the colour they paint. "Dark" now reads "changed the theme". (2) A choice that is already the current state (Light, in a light window) changes nothing when clicked. When another item of the same menu has moved the state, the walk clicks that item first and then looks at the choice again. Only a choice that still changes nothing is a finding. Afterwards the walk puts the theme back as it found it, because the attached window is your app. (3) The workspace switcher is a popover (`role="group"`), not a menu, so the walk never found it open. It now opens the box the trigger's `aria-controls` names. Also fixed: `tf-theme.mjs` read colours with a pattern for `rgb()` only. Sevak's colours are `oklch()`, so every surface read as white in both themes, which is why every screen said "the app has no dark theme". The text-contrast check was skipping every `oklch()` colour for the same reason. Colours are now converted by the browser itself, as `tf-mockup-parity.mjs` already did (TF-027). Regression case `sv_006`; all three of its checks fail on the scripts you have now. Miss `MISS-TechieFlow-20261014-02`. | Proved on your app, Windows head, 2026-10-14, old scripts then new on the same running app. Phase-1 list: old gave "the app has no dark theme" on all 5 screens and the three "Change theme" findings on Login. New: no menu findings, and every screen is graded in light and dark, with visual OK in both, so no new contrast finding. `/welcome`: old FAIL with "switch workspace opens nothing" plus the three theme findings. New: OK, light and dark; the switcher opened, and its workspace, "New workspace…" and "Workspace settings…" items were each clicked and did something. Paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase 1`. Login (REQ-FN-036) and Welcome (REQ-RAG-054, REQ-RAG-055) no longer carry a menu finding, and the screen lines read "light + dark themes". |

## Resolution status (TechieFlow team, 2026-10-11)

| ID | Fix | Check it here |
|---|---|---|
| TF-005 | Fixed upstream. (1) `*verify {scope} Sevak --phase N` grades phase N's checklist; `--phase all` grades every phase in turn, phase 1 first, on one boot. `tf-verify-list.sh Sevak all --phase all` prints `PHASES 1 2 3`, and a phase with no checklist is refused, naming the phases that have one. (2) The verdict writes only into the checklist of the phase graded. The ledger `docs/.last-verify.json` keeps every row's phase, so phase 2's scope-all pass no longer wipes phase 1's verdicts. (3) Each pass writes its own run record and gate records with `app_phase`; the second pass starts where the first ended, so it is not refused as an overlap (it was before). (4) `tf-status-facts.sh` and flow-master name the phase: `--phase 3` for this phase, `--phase N` for one earlier phase, `--phase all` for several; a build of this phase still comes first. Regression case `sv_005`; four of its five checks fail on the scripts you have now. Miss `MISS-TechieFlow-20261011-01`. | Proved here on your files, read only: the new status reads "86 to verify across phases 1, 2" (phase 1: 52, phase 2: 34) and gives the command below. Paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase all`. The verdict table heads each pass with its phase and checklist, phases 1 and 2's checklists get their Status cells, and `docs/metrics/runs.jsonl` gains three `verify-phase` records with `app_phase` 1, 2 and 3. |

## Resolution status (TechieFlow team, 2026-10-06)

| ID | Fix | Check it here |
|---|---|---|
| TF-002 | Fixed upstream in `guard-db.sh`. It now judges what runs, not what a command mentions. (1) When python, node, deno, bun, ruby, perl or pwsh runs code, the guard reads that code: inline (`-c`, `-e`), a heredoc, a file written earlier in the same command (`printf … > s.py && python3 s.py`, `cat > s.py <<EOF`), or a script file, found from the working folder or a folder the command `cd`s into. It refuses the run when the code uses a database library (sqlite3, better-sqlite3, psycopg, mysql2, pg, SQLAlchemy, Microsoft.Data.Sqlite, MongoDB and others) and holds a SQL write (INSERT INTO, UPDATE … SET, DELETE FROM, DROP/CREATE/ALTER TABLE, TRUNCATE). (2) It allows that only when every database path the code names is a throw-away one: under `tests/.artifacts/`, under `/tmp`, or `:memory:`. That is the throw-away data folder for smokes: name it literally in the script. A path the code builds at run time (your `APPDATA`/`TechieDesk` one) counts as the app's database and is refused. (3) A database client counts only when it is the command being run, so a `grep` for those words, or a note written to a file that names them, is no longer refused. Direct client writes and migrations are handled as before. Regression case `sv_002` holds 13 real command shapes. Miss `MISS-TechieFlow-20261006-01`. | Proved here: your copy of the guard got 5 of the 13 wrong (it missed `python3 tools/seed.py`, the same after `cd`, and the `printf` form, and it refused the grep and the feedback note). The new one gets all 13 right, and none of the framework's own scripts or your test scripts is refused. One of yours would be: `tests/verify/req-nfr-010-appmanager-outage.spec.ts` runs `update LicenseCache set ValidatedAt = …` on `apps/Sevak/data/techiedesk.db`. That is the same kind of direct write. It runs through `npx playwright test`, which the guard does not open, so nothing changes for it today; a copy under `tests/.artifacts/` would keep the real data safe. To check: in YOLO, write a small python script that opens your app database and deletes a row, then run it; it is refused, naming the script. The same script pointed at `tests/.artifacts/smoke/app.db` runs. |
| TF-003 | Fixed upstream in `tf-verify-boot.sh`. (1) Each Windows head now starts its embedded browser on its own debugging port, worked out from its relay port: `--port 9223` keeps 9222, and any other port uses relay + 20000 (9261 → 29261). (2) When another Windows head is already up, the new one also gets its own WebView2 data folder under `tests/.artifacts/verify/webview-<port>/`. Two copies of one app would otherwise share one browser process and one list of pages. (3) The boot records the Windows process ids of its own app (the copies of the program that appeared during its start), and `stop --port <n>` kills those alone. It used to kill every copy with `taskkill /IM`. A state file written before this fix is still stopped by name, unless another start of the same program is still up. Regression case `sv_003`. Miss `MISS-TechieFlow-20261006-02`. | Proved on this machine with two copies of MyDiary at once. `--port 9281` booted on debugging port 29281. `--port 9283` printed "1 other Windows head(s) up — this one gets DevTools port 29283 and its own WebView2 data folder". Each relay listed one page, with different target and browser ids. `stop --port 9283` left the first app running and answering; stopping it left no app and no port behind. Here: boot two heads with different `--port` values, list `http://<host>:<port>/json` for each (one page each), then stop one; the other keeps running. You can drop the "one head at a time" rule. Pinning the page by target id is still good practice. |
| TF-004 | Fixed upstream in `tf-verify-tests.sh`, in one run and in `--merge`. Each test's outcome now records where it ran. A row with on-app tests that were all skipped, and none failed, is NOT-TESTED, whatever its unit tests say. The reason names the skip and says a unit test does not measure on-app acceptance. This covers every row class, so your four RAG rows too. A row with no on-app test is graded on its unit tests as before, and a failure on either side still makes the row FAIL. Result files written before the fix get the source from their row. Regression case `sv_004`. Miss `MISS-TechieFlow-20261006-03`. | Proved on your files: `--merge tests/.artifacts/verify/tests-browser.json tests/.artifacts/verify/tests-unit2.json`, old script then new. Old: 24 PASS, 1 NOT-TESTED. New: 16 PASS, 9 NOT-TESTED. Exactly your eight rows changed (REQ-FN-055, FN-056, UI-065, UI-068, RAG-056, RAG-057, RAG-058, RAG-059), each with its skip reason, e.g. "this Windows host has no Hindi (hi-IN)". You can grade from the merged file again; `tests-with-unit.json` no longer needs to be kept aside. |

## Resolution status (TechieFlow team, 2026-10-02)

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream. In `tf-day1-files.sh`, `--size`, `--kind` and `--phase` now set only `appSize`, `appKind` and `appPhase`, plus `docs/<App>-Phases.md` for Large. AGENTS.md, CLAUDE.md, `.editorconfig` and the document list are written only with `--prefix` (day-1 stage 2). Even then, the document list only gains missing entries and keeps every entry already there. Run with no flag, the script refuses rather than rewriting everything. | Copy `.tfcore/core-config.yaml`, then run `bash .tfcore/utils/tf-day1-files.sh Sevak --size L --kind app`. The output names only `appSize L, appKind app` (and the Phases file, which is left as is because it exists). AGENTS.md and CLAUDE.md are unchanged, nothing new is in `docs/OldDocs/`, and the config differs from the copy in `appSize` only. |

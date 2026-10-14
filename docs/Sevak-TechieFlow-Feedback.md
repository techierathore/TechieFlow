# TechieFlow feedback — found while building Sevak

| | |
|---|---|
| App | Sevak |
| Upstream | TechieFlow |
| Updated | 2026-10-14 |

## Summary

6 entries: 0 blocking now, 0 open, 2 fixed upstream and not yet re-checked (TF-005, fixed 2026-10-11; TF-006, fixed 2026-10-14), 4 closed (TF-001 to TF-004).

Nothing is blocked. TF-005 is fixed upstream: `*verify` takes `--phase N` or `--phase all`, so phases 1 and 2 can be graded, and the status names the phase in the command it gives. TF-006 is fixed upstream: a theme switch counts as a click doing something, a popover switcher is opened through the control it names, and the dark theme of an app coloured in `oklch()` is seen and graded. TF-001 to TF-004 are closed.

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

> Filed by Sevak as TF-005 on 2026-10-14; renumbered TF-006 by the TechieFlow team because TF-005 is the `--phase` entry above.

- **Severity:** minor
- **Blocks:** no — it fails one row's render check (Sevak REQ-FN-036) on a working control; every other check ran.
- **Repro:** Sevak Windows head over CDP, AppManager mode, 2026-10-14. `tf-verify-screens.sh --list … --cdp <url>` on `/login` reports `"Change theme › Light" does nothing when clicked` (also Dark and Match system), and says "the app has no dark theme" on every screen. Driving the same menu by hand over CDP: "Dark" sets `<html class="dark" data-theme="dark">` and repaints the page dark.
- **Expected:** a menu item that changes the document's theme class and repaints the page counts as doing something; "no dark theme" is not reported for an app whose own toggle switches to dark.
- **Actual:** the check in `tf-menus.mjs` reports the three items as doing nothing on `/login`, and the screen fails render.
- **Encountered in:** the Sevak phase-1 fix run, 2026-10-14. The same check also reports the workspace switcher on `/welcome` as "opens nothing when clicked" (Sevak REQ-RAG-054, REQ-RAG-055), while by hand it opens its panel (`aria-expanded="true"`) and closes again.
- **Workaround:** none in the app; the rows stay below Verified with this finding named.
- **Suggested fix:** in `tf-menus.mjs`, compare the document's class and `data-theme` attributes and the painted background before and after the click, after the menu has closed, and treat a change in any of them as an effect.

## Resolution status (TechieFlow team, 2026-10-14)

| ID | Fix | Check it here |
|---|---|---|
| TF-006 | Fixed upstream in `tf-menus.mjs` and `tf-theme.mjs`. Three faults, all the checker's. (1) A menu click was judged by the address, the text, dialogs and zoom only. It now also compares the theme: the light/dark classes and `data-*theme` attributes on `<html>` and `<body>`, and the colour they paint. "Dark" now reads "changed the theme". (2) A choice that is already the current state (Light, in a light window) changes nothing when clicked. When another item of the same menu has moved the state, the walk clicks that item first and then looks at the choice again. Only a choice that still changes nothing is a finding. Afterwards the walk puts the theme back as it found it, because the attached window is your app. (3) The workspace switcher is a popover (`role="group"`), not a menu, so the walk never found it open. It now opens the box the trigger's `aria-controls` names. Also fixed: `tf-theme.mjs` read colours with a pattern for `rgb()` only. Sevak's colours are `oklch()`, so every surface read as white in both themes, which is why every screen said "the app has no dark theme". The text-contrast check was skipping every `oklch()` colour for the same reason. Colours are now converted by the browser itself, as `tf-mockup-parity.mjs` already did (TF-027). Regression case `sv_006`; all three of its checks fail on the scripts you have now. Miss `MISS-TechieFlow-20261014-02`. | Proved on your app, Windows head, 2026-10-14, old scripts then new on the same running app. Phase-1 list: old gave "the app has no dark theme" on all 5 screens and the three "Change theme" findings on Login. New: no menu findings, and every screen is graded in light and dark, with visual OK in both, so no new contrast finding. `/welcome`: old FAIL with "switch workspace opens nothing" plus the three theme findings. New: OK, light and dark; the switcher opened, and its workspace, "New workspace…" and "Workspace settings…" items were each clicked and did something. After the framework update, paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase 1`. Login (REQ-FN-036) and Welcome (REQ-RAG-054, REQ-RAG-055) no longer carry a menu finding, and the screen lines read "light + dark themes". |

## Resolution status (TechieFlow team, 2026-10-11)

| ID | Fix | Check it here |
|---|---|---|
| TF-005 | Fixed upstream. (1) `*verify {scope} Sevak --phase N` grades phase N's checklist; `--phase all` grades every phase in turn, phase 1 first, on one boot. `tf-verify-list.sh Sevak all --phase all` prints `PHASES 1 2 3`, and a phase with no checklist is refused, naming the phases that have one. (2) The verdict writes only into the checklist of the phase graded. The ledger `docs/.last-verify.json` keeps every row's phase, so phase 2's scope-all pass no longer wipes phase 1's verdicts. (3) Each pass writes its own run record and gate records with `app_phase`; the second pass starts where the first ended, so it is not refused as an overlap (it was before). (4) `tf-status-facts.sh` and flow-master name the phase: `--phase 3` for this phase, `--phase N` for one earlier phase, `--phase all` for several; a build of this phase still comes first. Regression case `sv_005`; four of its five checks fail on the scripts you have now. Miss `MISS-TechieFlow-20261011-01`. | Proved here on your files, read only: the new status reads "86 to verify across phases 1, 2" (phase 1: 52, phase 2: 34) and gives the command below. After the framework update, paste into Sevak's agent: `/TechieFlow:agents:verifier *verify all Sevak --phase all`. The verdict table heads each pass with its phase and checklist, phases 1 and 2's checklists get their Status cells, and `docs/metrics/runs.jsonl` gains three `verify-phase` records with `app_phase` 1, 2 and 3. |

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

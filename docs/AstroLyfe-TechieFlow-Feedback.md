# TechieFlow feedback — found while building AstroLyfe

| | |
|---|---|
| App | AstroLyfe |
| Upstream | TechieFlow |
| Updated | 2026-11-21 (TF-065 fixed upstream, in `.tfcore/` from the framework update of the same day) · 2026-11-19 (TF-062 filed from the owner's report of the develop run of 19 Nov, fixed upstream, in `.tfcore/`; TF-001 from the run of 13 Nov) |

Defects found in the **TechieFlow framework itself** (`.tfcore/`) while building AstroLyfe. `.tfcore/` is the TechieFlow team's and `update-framework.sh` overwrites it, so nothing in it is fixed here; this file is the hand-off. `bash .tfcore/utils/tf-feedback.sh AstroLyfe` reads it.

## Summary

3 entries copied here (TF-063 and TF-064 are in AstroLyfe's own file, not answered yet): 0 open, 3 fixed upstream and not yet re-checked (TF-001, TF-062, and on 2026-11-21 TF-065, in `.tfcore/` from the update of the same day), 0 closed. 0 blocking.

## Entries

### TF-065 — `tf-theme` grades a light-only app in dark mode once its UI library ships a `.dark` token block

- **Status:** fixed upstream 2026-11-21 (filed the same day); in AstroLyfe's `.tfcore/` from the framework update of 2026-11-21; not yet re-checked here.
- **Filed by:** the flow-master, in AstroLyfe's build-phase of 2026-11-21 (phase 3 verify).
- **Blocks:** no — the screens were graded in light only (`--themes light`), as the app has no dark theme, and the run carried on.
- **Severity:** minor
- **Repro:** AstroLyfe on TrBlazeUI 2.2.6, whose `trblazeui.css` defines its colours again under `:where(.dark)`. The app sets `<meta name="color-scheme" content="light">` and never puts the class `dark` anywhere. `tf-verify-screens.sh --list … ` on `/Testing/Run`.
- **Expected:** "the app has no dark theme": no user can reach a dark page.
- **Actual:** the tool adds the class `dark`, the library's dark colours turn on under the app's own white header, and every screen fails the visual check in dark mode. The same build graded phases 1 and 2 as "no dark theme" an hour earlier, so the answer also differs between runs.
- **Encountered in:** `*build-phase AstroLyfe`, chained verify of phase 3, 2026-11-21.
- **Workaround:** `--themes light` on the screen and mockup checks, recorded in the run.
- **Suggested fix:** treat a page whose `color-scheme` meta (or CSS `color-scheme`) is `light` only as having no dark theme, and add the class `dark` only when the app itself shows a way to set it.
- **Reply (TechieFlow team, 2026-11-21):** Fixed upstream in `tf-theme.mjs`, with one line each in `tf-verify-screens.mjs` and `tf-mockup-parity.mjs`; the first part of your suggestion. When the screen check puts the dark theme on, it now reads the page's colour scheme: the `color-scheme` meta and the CSS `color-scheme` of `<html>` and `<body>`. If they still say light and nothing says dark, the page has no dark theme. It is put back as it was, reads "(the app has no dark theme)", and gets no dark pass. That holds in the default mode and also under `--themes light,dark`. The mockup check does the same (`themes_not_offered: dark`). An app with a real dark theme is not touched: its own dark switch (`.dark { color-scheme: dark }`, `[data-theme=dark]`) changes the scheme when dark is put on. The answer no longer depends on which screen was asked first, so phase 3 now reads like phases 1 and 2. **Not done:** the second part, adding the class `dark` only when the app shows a way to set it. An app that says `color-scheme: light` but has a dark mode that never changes the scheme would lose its dark pass. Of the projects read, none is built that way [Likely, read in their CSS, not run]. **Rule that changed:** whether a screen gets a dark pass. It can only take dark findings away, from a page that says light only. Read across the projects (read only): only AstroLyfe's app says so (`<meta name="color-scheme" content="light">` and `:root { color-scheme: light }`). No project's mockups do. The "light only" lines in TfLens, TrStudio, TrSetup and XVault are on `#blazor-error-ui`, not the page. **Proved** by case `as_065` (`tests/faults/n21-cases.sh`), shaped like your app: the meta and `:root` say light, and a library sheet re-colours `.dark`. On the scripts you have, that page was graded in dark. Now it is not, in auto mode or under `--themes light,dark`, and the mockup check reports dark as not offered. Control half: an app whose `.dark` sets `color-scheme: dark`, and a page whose meta says `light dark`, are still graded in dark. Not run on AstroLyfe's own head. **Check it here:** the screen check on `/Testing/Run` with no `--themes` prints "(the app has no dark theme)" and no screen fails in dark mode, so the `--themes light` workaround can go.

### TF-001 — The booted app's address reaches the browser tests only as an environment variable, and the test-users check does not read the TestNUsageDoc

- **Status:** fixed upstream 2026-11-14, fixed in AstroLyfe's `.tfcore/` by the framework update of 2026-11-14; not yet re-checked here.
- **Filed by:** the TechieFlow team, from the owner's report of AstroLyfe's run of 13 Nov.
- **Blocks:** no — `_settings.ts` falls back to `process.env.BASE_URL`, so the tests reach the app; the owner rule of 11 Nov (every test setting from the settings files, never the environment) cannot be met fully.
- **Severity:** minor
- **Repro:** `bash .tfcore/utils/tf-verify-tests.sh --base <boot address>` hands the address to `npx playwright test` as `BASE_URL` (and `CDP_URL`) only. AstroLyfe's tests read every setting from `tests/verify/testsettings.json` with `testsettings.Local.json` laid over it. Separately, `tf-test-users-check.py` reads the Test users of `docs/<App>-UsageGuide.md` only; AstroLyfe keeps them in `docs/AstroLyfe-TestNUsageDoc.md` under "## 2. Test User Accounts", so the check found 0 test users.
- **Expected:** the address arrives through `tests/verify/testsettings.Local.json`, with the old variable still set for one release so no project breaks; the check reads the TestNUsageDoc's Test users too.
- **Reply (TechieFlow team, 2026-11-14):** Fixed upstream in `tf-verify-tests.sh`, a new `tf-verify-settings.py` and `tf-test-users-check.py`. For each browser run the address is written into `tests/verify/testsettings.Local.json` as `Verify:BaseUrl` (and `Verify:CdpUrl` for a desktop head); after the run the two keys are put back as they were (a file the run created is removed), and nothing else in the file is read out or printed. `BASE_URL` and `CDP_URL` are still set, for one release (until v1.5), so a suite that reads them keeps working; a suite that reads `BaseUrl` from its settings is no longer refused as "nothing reads BASE_URL". The test-users check now also reads `docs/<App>-TestNUsageDoc.md`, and a "Test users" or "Test User Accounts" section runs to the next heading of its own level, so the table under "### Account Setup" counts: on this project's documents it now finds the 9 accounts (before: 0) and its verdict is unchanged. Case `as_001` in `tests/faults/run.sh` fails on the scripts you had and passes now. Its control halves: the Local file is the same after the run, its own BaseUrl and sign-in kept; an address built at run time is still a finding. Proved on a fixture, not on the AstroLyfe app. **Fixed in AstroLyfe's `.tfcore`:** deployed with `update-framework.sh` on 2026-11-14, when no AstroLyfe run was in progress. **Check it here:** the next verify's browser run reads `Verify:BaseUrl` = the boot address, and `testsettings.Local.json` is unchanged afterwards; `python3 .tfcore/utils/tf-test-users-check.py --app AstroLyfe` says `9 test user(s) in docs/AstroLyfe-TestNUsageDoc.md`. When the env fallback in `_settings.ts` is no longer needed, it can go before v1.5.

### TF-062 — A develop run cannot be followed, checked or stopped, and it ran on Sonnet from an Opus window

- **Status:** fixed upstream 2026-11-19, fixed in AstroLyfe's `.tfcore/` by the framework update of 2026-11-19 (evening); not yet re-checked here. The run of 19 Nov is not resumed (the owner resumes it after the AppManager sign-in fix).
- **Filed by:** the owner, 19 Nov 2026, from the `*develop-end-to-end` run started on AstroLyfe at 17:48.
- **Blocks:** yes — the owner could not tell where the run was, whether it was alive, or that it had ended.
- **Severity:** blocker
- **Repro:** `*develop-end-to-end AstroLyfe` with no `--model`, from an Opus session. The launching window started `tf-develop.sh --detach` and ended its turn, so it never heard that the run stopped (blocked, 19:31). `.tfcore/.session/develop.log` had one line per step and nothing for 45 minutes inside the build step. No command said whether the supervisor was alive. Every goal cycle ran on `claude-sonnet-5-5`, the routing default the supervisor picked when no `--model` was given. There was no way to stop the run and everything it had started.
- **Expected:** the launching window follows the run to its end and says how it ended; `*develop-status {App}` from any window, with the run's liveness checked; progress inside a step in `develop.log`; `--model` honoured on every step, and the launching session's model when none is given; `--stop` that ends the supervisor and everything it started, and `--resume` from where it stopped.
- **Reply (TechieFlow team, 2026-11-19, evening):** Fixed upstream in `tf-develop.sh` and a new `tf-develop-watch.py`. The flow-master's `develop-end-to-end.md` says how they are used. Each case below is in `tests/develop/run.sh`; each fails on the scripts you had and passes now.
  1. **The launching window follows the run.** After the launch it runs `tf-develop.sh . --follow` as a background command the harness reports back on: the Monitor tool in Claude Code; in OpenCode a background command with `--next`, started again after each report. Each step's start and end, each goal cycle, each verify's result and the rows built and verified reach that window with their times. When the run ends, the same window gives the Build Report's result, the time, the tokens, the blocker if any and the next command. A follow that is started again goes on from where the last one stopped reading. Cases `dev_follow`, `dev_follow_next`.
  2. **`*develop-status AstroLyfe`, from any window** (`tf-develop.sh . --status`) shows: running or stopped, checked rather than assumed (the pid on its host, and that the process still belongs to this run); the harness and model; the step and phase; when it started; elapsed time; last activity; rows; tokens so far; where the log and the report are. Case `dev_status`: a run killed with `kill -9` reads "stopped", never "running".
  3. **Progress inside a step.** `develop.log` now gets each goal cycle's start and end, each verify's result (rows graded, with their verdicts) and each change in rows built and verified, every line with its time. Case `dev_progress`.
  4. **The model.** `--model` reaches every goal cycle of every step, with `--no-fallback`: a usage limit waits for the reset and does not move to another model. With no `--model`, the run uses the launching session's model, read from its Claude Code transcript or its OpenCode session. If that cannot be read, the run is refused, never routed to a default. The model is printed at launch, in `develop.log` and in every status line. Case `dev_model`.
  5. **`*develop-end-to-end AstroLyfe --stop`.** Every process the run starts carries the run's mark (`TF_DEVELOP_RUN`), including one the agent starts in a session of its own. `--stop` records the stop and ends the supervisor first, then every marked process (TERM, then KILL after ten seconds). It writes down the step it stopped in, and `--resume` continues from that step. A database container is kept, so its data is there on resume. Case `dev_stop`.
  Proved for real in both harnesses on a scaffolded fixture app, with the real goal runner and a stand-in agent command:
  - Claude Code, launched from an Opus session with no `--model`, ran on `claude-opus-5-5` and was followed with the Monitor tool. `--stop` ended its 5 processes, and it was then resumed and followed to "Ready for UAT".
  - OpenCode, launched by an OpenCode agent, read `venice/openai-gpt-54-mini` from its own session. It was followed with a background `--next`, stopped, resumed, and followed to the end.
  A real, paid build was not run.
  **About your run of 19 Nov:** every goal cycle ran on `claude-sonnet-5-5`. The cycles' own output counts 29,314 tokens out; the Build Report says 4,763 (open, MISS-TechieFlow-20261119-03). One process of the run was still alive at 19:41: `AstroBlazeWeb.dll` on port 5201, started by the agent at 18:36. The TechieFlow team stopped it; no process of the run is left. The run recorded no pid (it started before this fix), so `--status` reads it as stopped, and reads its model from the cycles' output.
  **Fixed in AstroLyfe's `.tfcore`:** deployed with `update-framework.sh` on 2026-11-19 (evening). The run is not resumed.
  **Check it here:** `*develop-status AstroLyfe` reads "stopped: build-p1 blocked" with the blocker. After the AppManager sign-in fix, `*develop-end-to-end AstroLyfe --resume --model claude-opus-5-5`; the window then follows it to its end.

## Replies from TechieFlow

### Resolution status (TechieFlow team, 2026-11-21)

From `/mnt/c/1MyCode/AstroLyfe/docs/AstroLyfe-TechieFlow-Feedback.md`, read on 2026-11-21 (read only). TF-063 and TF-064 are not answered here.

**Fixed in AstroLyfe's `.tfcore`** through the framework update of 2026-11-21. The reply was written in the TechieFlow repository's copy of this file and merged into AstroLyfe's at the update. Nothing of AstroLyfe's was run for it.

| ID | Fix | Case | Check it here |
|---|---|---|---|
| TF-065 | A page whose `color-scheme` meta, `<html>` and `<body>` still say light only once dark is put on has no dark theme: no dark pass in the screen or mockup check, in auto mode or under `--themes light,dark`. | `as_065` | the screen check on `/Testing/Run` with no `--themes`: "(the app has no dark theme)", no dark-mode failure. |

**Rules that changed, and which way they move a finding.** `tf-theme.mjs`: a light-only page loses its dark pass, so its dark-mode findings go; of the projects read, only yours says light only. `tf-menus.mjs` (Chatur TF-049): "does nothing when clicked" can only go away, from a tickable menu item whose tick moves. `tf-dropdowns.mjs` (Chatur TF-051): an overlap caused by a dialog the walk left open goes away, or reads "not measured" where the dialog will not close. `tf-verify-tests.sh` (Chatur TF-050): two new switches; a run without them behaves as before.

**The table** (`measure-projects.py --base deployed`), your row: rows whose verdict moves: not measured for 16 row(s) with a screen; 0 of 1 without one (the last verify covered 17 of the project's 161 rows; the others are not measured); tests a phase verify stops running: 0 of 189 stop; findings that appear or go: none; build list and next command: same. The screen and mockup checks changed, so a row with a screen reads "not measured" there: the saved records were written by the old checks. The rows that can move are the ones whose screens a verify graded in dark mode.

### Resolution status (TechieFlow team, 2026-11-20)

**Fixed in AstroLyfe's `.tfcore`** through the framework update of 2026-11-20. Two follow-ups to TF-062, both found after its reply; no new entry. The develop run of 19 Nov is still not resumed.

| ID | Fix | Check it here |
|---|---|---|
| TF-062 (develop mode) | While your stopped run waited, its `develop.json` put every new agent session in this app into develop mode, with no questions to you (MISS-TechieFlow-20261119-04). Develop mode now holds only in the run's own processes, which carry its `TF_DEVELOP_RUN` mark. Case `dev_mode`. | `bash .tfcore/utils/tf-develop.sh . --mode` in a session you open says `off`. Checked on 2026-11-20 with the stopped run waiting: `off`. |
| TF-062 (tokens) | The reply said the Build Report's token count was still open (MISS-TechieFlow-20261119-03). It is fixed: the report counts each attempt's tokens from the goal cycles' own output, not from the run records. On a copy of this run the report reads 29,314 tokens out, where yours says 4,763. Case `dev_tokens`. | Your Build Report changes when the run is resumed, or after `bash .tfcore/utils/tf-develop.sh . --report`. Keep `.tfcore/.session/goal-cycle-*.out` until then: the first attempt's tokens are read from those files. |

**The table** (`measure-projects.py --base deployed`): rows whose verdict moves: 0 of 42; tests a phase verify stops running: 0 of 78; findings that appear or go: none; build list and next command: same; no browser-side script changed.

### Resolution status (TechieFlow team, 2026-11-19, evening)

**Fixed in AstroLyfe's `.tfcore`** through the framework update of 2026-11-19 (evening). AstroLyfe is the only project updated with this fix. Its develop run of 19 Nov is not resumed.

| ID | Fix | Check it here |
|---|---|---|
| TF-062 | Fixed upstream. The launching window follows the run to its end; `*develop-status AstroLyfe` from any window; each goal cycle and verify in `develop.log`; `--model`, else the launching session's model, on every step; `--stop`, then `--resume`. The reply is under the entry. | `*develop-status AstroLyfe` reads "stopped: build-p1 blocked". After the AppManager sign-in fix: `*develop-end-to-end AstroLyfe --resume --model claude-opus-5-5`. |

**The table** (`measure-projects.py --base deployed`, your copy of this morning against tonight's): rows whose verdict moves: 0 of 42 (the last verify covered 42 of the project's 157 rows; the others are not measured); tests a phase verify stops running: 0 of 78; findings that appear or go: none; build list and next command: same; no browser-side script changed. The fix changes only how a develop run is started, watched and stopped.

### Resolution status (TechieFlow team, 2026-11-19)

From `/mnt/c/1MyCode/AstroLyfe/docs/AstroLyfe-TechieFlow-Feedback.md`, read on 2026-11-19. **No entry is open.** TF-001 is fixed upstream and waits for your re-check; `as_001` still passes on tonight's scripts, so nothing about them changed. TechieFlow v1.4.0 (in this project's `.tfcore/` from the framework update of 2026-11-19 (morning)) changes the screen and mockup checks, the token counts of Claude Code runs and the estimates; its notes are `docs/TechieFlow-Release-Notes-v1.4.0.md` in TechieFlow.

**One change that reaches your verify (TfLens TF-060).** A row of a later phase that no screen of its own phase owns is now resolved against the earlier phases' screens. On your documents (read only), 7 rows gain a screen (phase 3: 6, phase 4: 1), for example REQ-UI-060 on `/ShowKundali/{id}`.

**The table** (`measure-projects.py --base v1.3.1`), your row: rows whose verdict moves: 0 of 96 (the last verify covered 96 of the project's 157 rows; the others are not measured); tests a phase verify stops running: 0 of 67 stop (32 left out in all, in 21 file(s)); 12 file(s) name no row id at all; findings that appear or go: none; build list and next command: same. The screen and mockup checks changed, so a row with a screen reads "not measured" there: the saved records were written by the old checks. What they now do is in the cases above, and the earlier-phase screens (TfLens TF-060) are counted from your documents, not from a verify.

### Resolution status (TechieFlow team, 2026-11-14)

**Fixed in AstroLyfe's `.tfcore`** through the framework update of 2026-11-14.

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream. The address goes through `testsettings.Local.json`; `BASE_URL` stays one release; the TestNUsageDoc's test users are read. The reply is under the entry. | the next verify's browser run; `tf-test-users-check.py --app AstroLyfe` finds 9 test users. |

# TechieFlow feedback — found while building Lekhak

| | |
|---|---|
| App | Lekhak |
| Upstream | TechieFlow |
| Updated | 2026-10-10 |

## Summary

27 entries: 0 blocking now, 1 open and not blocking (TF-003), 5 fixed upstream and not yet re-checked here (TF-008, TF-022, TF-023, TF-025, TF-027), 21 closed after a re-check here (TF-001, TF-002, TF-004, TF-005, TF-006, TF-007, TF-009, TF-010, TF-011, TF-012, TF-013, TF-014, TF-015, TF-016, TF-017, TF-018, TF-019, TF-020, TF-021, TF-024, TF-026).

Nothing is blocked.

- 0 blockers, 9 majors, 18 minors, 0 nice-to-haves.
- Last consolidated: 2026-10-10.

## Entries

### TF-001 — The verify boot runs the web head outside Development, so user-secrets never load

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: ran bash .tfcore/utils/tf-verify-boot.sh start --head web --project source/Lekhak/Lekhak.csproj with no secrets exported, three times (stop/start between). Each printed 'user-secrets lekhak-web-4f2b8c1e are in the Windows store only' and BOOTED mode=base url=http://localhost:59689. app-59689.log: 'Now listening on: http://localhost:59689', 'Hosting environment: Development', no missing-secret error; the process has ASPNETCORE_ENVIRONMENT=Development and APPDATA=/mnt/c/Users/srkra/AppData/Roaming; GET / returns 200. run-web-verify.cmd is no longer used.

- **Severity:** major
- **Blocks:** no — the web head was started with its own `dotnet run` in Development on all interfaces, and the verify carried on.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-boot.sh start --head web
  ```
- **Expected:** The web head boots the way `dotnet run` with the project's launch profile does, including the Development environment that loads user-secrets.
- **Actual:** The published copy starts without an environment and stops at start-up: `Required configuration value(s) not set: LekhakJwtSigningKey`. Setting `ASPNETCORE_ENVIRONMENT` in the calling shell does not reach it.
- **Encountered in:** build-phase → verify-phase, 2026-09-26
- **Workaround:** `tests/.artifacts/harness/run-web-verify.cmd` runs `dotnet run --no-build` in Development, bound to `0.0.0.0` so WSL can reach it. On 2026-09-27 the boot ran the published copy in WSL, which cannot see the Windows user-secrets store; the owner's existing secrets were exported as environment variables for that one boot.
- **Suggested fix:** Give `tf-verify-boot.sh` an `--environment` option (or honour the project's launch profile) and bind the published copy to all interfaces when it runs Windows-side.

### TF-002 — The screen check cannot open an HTTPS development head

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: ran tf-verify-screens.sh --list list-web.json --base https://172.18.144.1:7374 (Lekhak in Development on the Windows dev certificate) with the reader login. It graded 8 screens: render 8 OK, visual 8 OK, 0 unreachable (Reset Password skipped: its route needs a token). Evidence tests/.artifacts/verify/recheck/screens-https.json.

- **Severity:** minor
- **Blocks:** no — the web head was restarted on plain HTTP only, which the checker can open.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --base https://172.18.144.1:5454
  ```
- **Expected:** The screens open, as they do for the Playwright specs, whose config sets `ignoreHTTPSErrors`.
- **Actual:** Every screen is `UNREACHABLE` with `net::ERR_CERT_AUTHORITY_INVALID`; a plain-HTTP base is redirected back to HTTPS and fails the same way.
- **Encountered in:** build-phase → verify-phase, 2026-09-26
- **Workaround:** web head started with `--urls http://0.0.0.0:5455` only, so it has no HTTPS port to redirect to.
- **Suggested fix:** Create the browser context with `ignoreHTTPSErrors: true` in `tf-verify-screens.mjs` and `tf-mockup-parity`, or add an `--insecure` option.

### TF-003 — The verifier has no Mac Catalyst driver, so a Mac head cannot get a verdict

- **Severity:** major
- **Blocks:** no — the Mac head was driven by hand-written Appium mac2 scripts and the results written to the Remarks cells; Status was left to the verdict script.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst
  ```
- **Expected:** The Mac head is built, launched and driven over the `runtimeVerification.appium.maccatalyst` endpoint, feeding the render and visual checks like the Windows head.
- **Actual:** `NONE ... no driver for the maccatalyst head ships in this framework version`; without `--head` the script picks the web head even when the owner asked for the Mac head.
- **Encountered in:** verify-phase, 2026-09-27
- **Workaround:** Appium mac2 with `appium:appPath` (the bundle id alone was "not found" for a copy outside /Applications), `AXEnhancedUserInterface` set on the app process so the BlazorWebView content shows in the element tree, typing through `macos: keys` bound to the element (a plain `setValue` drops characters or replaces the field), and element screenshots of the app window.
- **Suggested fix:** Add a `maccatalyst` head to `tf-verify-boot.sh` and a mac2-based screen driver that applies the steps above.

### TF-004 — The 7-day artifact clean-up deletes test fixtures the specs depend on

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: dry run of .tfcore/hooks/sweep-artifacts.sh (TF_SWEEP_DRY_RUN=1, 1-day window, nothing deleted) built the keep list tests/.artifacts/harness/{cdp-relay.cjs, hindi-src, run-blogadmin.cmd, serials-seed.mjs} and ended 'kept 3 old file(s) a test names by path'; 649 other old files would go.

- **Severity:** major
- **Blocks:** no — the Hindi crawl page was rebuilt under `tests/verify/fixtures/hindi-src/` and the two rows re-graded Verified.
- **Repro:**
  ```
  start a session more than 7 days after tests/.artifacts/harness/hindi-src was written
  ```
- **Expected:** The clean-up removes run output (screenshots, logs, published copies) and leaves hand-made fixtures alone.
- **Actual:** It removed `tests/.artifacts/harness/hindi-src`, so REQ-RAG-002 and REQ-FN-134 failed with "the crawl produced no result" on a working product.
- **Encountered in:** verify-phase, 2026-09-27
- **Workaround:** Fixture moved to `tests/verify/fixtures/hindi-src/`, outside the swept folder.
- **Suggested fix:** Exclude `tests/.artifacts/harness/` from the sweep, or have the sweep skip any folder a spec names as a prerequisite.

### TF-005 — The screen check cannot fill route values or reach a screen's other states

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: tf-verify-screens.sh --cdp with --route-value ProviderId=21 opened /admin/llm-signin/21 (without it: 'SKIP … pass --route-value ProviderId=<a real ProviderId>'). With a scratch copy of the Connection settings mockup marking conn-reason, conn-env-override and conn-result data-tf-state (--mockups tests/.artifacts/verify/recheck/mockups-tfstate), the screen graded render OK, visual OK, 15 anchors on its first view. Evidence tests/.artifacts/verify/recheck/screens-tf005.json.

- **Severity:** minor
- **Blocks:** no — LLM sign-in was driven with a real provider id; Connection settings is left at Needs re-verify for the owner to decide.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --cdp http://172.18.144.1:9334
  ```
- **Expected:** `/admin/llm-signin/{ProviderId:long}` is opened with a real id, and anchors that only show in another state (database unreachable, after Test) are not required on the first view.
- **Actual:** The literal placeholder URL gives a 404, and Connection settings is marked empty because `conn-reason` and `conn-result` only appear when the database is down or after a click.
- **Encountered in:** verify-phase, 2026-09-27
- **Workaround:** `--screen "LLM sign-in=/admin/llm-signin/21"`; the Connection settings states are covered by its acceptance tests, which pass.
- **Suggested fix:** Let the list or the mockup give sample route values, and let a mockup mark an anchor as state-only.

### TF-006 — The asset and mockup checks cannot attach to a desktop head

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: with BlogAdmin booted by tf-verify-boot.sh --head windows (CDP http://172.18.144.1:9223), tf-assets.sh --cdp graded all 11 desktop screens (16 declared files each, 0 failed) and tf-mockup-parity.sh --cdp graded them: 5 FAIL on real drift (Connection settings, AI Story Studio, Prompt Manager, AI Setup, LLM sign-in), 6 UNGRADEABLE (mockups without anchors). Evidence tests/.artifacts/verify/recheck/assets-cdp.json and parity-cdp.json.

- **Severity:** minor
- **Blocks:** no — those two checks are recorded as not measured for the 11 desktop screens.
- **Repro:**
  ```
  bash .tfcore/utils/tf-mockup-parity.sh --cdp http://172.18.144.1:9334 --screen ai-setup=/admin/ai-setup
  ```
- **Expected:** Both scripts accept `--cdp` like `tf-verify-screens.sh`.
- **Actual:** Neither has a CDP mode, so desktop screens are never graded for missing stylesheets or mockup structure.
- **Encountered in:** verify-phase, 2026-09-27
- **Workaround:** None; not measured.
- **Suggested fix:** Add `--cdp` to `tf-assets.sh` and `tf-mockup-parity.sh`, reusing the screen checker's attach code.

### TF-007 — A re-run cannot clear a failure caused by the test set-up, and a targeted run replaces the full ledger

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: phase8-admin.spec.ts ran with the LLM stub off (REQ-UI-136 FAIL) and again with it on (15/15); tf-verify-tests.sh --merge of the two read REQ-UI-136 PASS and printed '1 test(s) ran again in a later part, and the later run stands'. Then a targeted *verify REQ-UI-140 left docs/.last-verify.json at 395 rows: REQ-UI-140 re-graded at run 2026-09-28T13:11:29Z, the other 394 kept with run 2026-09-28T11:19:35Z (row_dates/row_runs).

- **Severity:** minor
- **Blocks:** no — the failed rows were re-graded by a separate targeted verify with their own evidence.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-tests.sh --merge tests-3of4.json tests-rerun.json --json-out tests.json
  ```
- **Expected:** A later run of the same test, after its missing service is started, can stand for that row, and `docs/.last-verify.json` keeps the rows a targeted run did not touch.
- **Actual:** The merge always keeps the first failure, and each targeted verify rewrites the ledger with only its own rows (395 rows became 1).
- **Encountered in:** verify-phase, 2026-09-27
- **Workaround:** A separate `*verify` for each re-graded group.
- **Suggested fix:** Let a merge prefer the newest run of the same test, and update the ledger row by row.

### TF-008 — The document checker fails working mockup links that point into a subfolder

- **Severity:** minor
- **Blocks:** no — the links open correctly; the FAILs are left in place and the documents were not changed to satisfy the checker.
- **Repro:**
  ```
  bash .tfcore/utils/tf-doc-check.sh --app Lekhak
  ```
- **Expected:** `docs/mockups/index.html` linking to `admin/connection-settings.html` passes, because `docs/mockups/admin/connection-settings.html` exists.
- **Actual:** Every `admin/…` and `web/…` link in the index is a FAIL ("does not open from docs/mockups/"), about 150 lines that hide real findings.
- **Encountered in:** amend-docs, 2026-09-28
- **Workaround:** None needed; the FAILs are ignored for this project.
- **Suggested fix:** Resolve a mockup link against the linking file's folder and accept it when the target file exists.

### TF-009 — The TF-001 fix did not boot the web head: it still stops on a missing secret

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: not reproducible with the current script. The 11:23 UTC failure came from the boot script before the TF-001 fix reached this repo (second reply). The same command at 12:45-12:46 UTC booted three times out of three on http://localhost:59689 in Development with no missing-secret error (see TF-001).

- **Severity:** major
- **Blocks:** no — both heads were started Windows-side with the project's own `run-web-verify.cmd` and `run-blogadmin.cmd`, and the verify ran against them.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-boot.sh start --head web --project source/Lekhak/Lekhak.csproj
  ```
- **Expected:** Lekhak boots, as the TF-001 reply says; its secrets are in `%APPDATA%\Microsoft\UserSecrets\lekhak-web-4f2b8c1e`.
- **Actual:** `NONE head=web kind=host` after 120 s; the app log says `Required configuration value(s) not set: LekhakJwtSigningKey` (tests/.artifacts/verify/app-59689.log). The published copy likely runs outside Development, where ASP.NET Core does not read user-secrets at all, so pointing APPDATA at the Windows store is not enough.
- **Encountered in:** verify-phase, 2026-09-28
- **Workaround:** Start the web head with `tests/.artifacts/harness/run-web-verify.cmd` and write `boot.json` by hand.
- **Suggested fix:** Run the published copy with `ASPNETCORE_ENVIRONMENT=Development` by default (as the `dotnet run` path at line 406 already does), and keep the APPDATA pointer.

### TF-010 — The mockup check grades the app in whatever theme the viewer last picked

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: with BlogAdmin on its saved minimal dark theme (html data-site-theme=minimal data-theme=dark), ran tf-mockup-parity.sh --cdp http://172.18.144.1:9223 --screen admin/connection-settings=/connection-settings and no theme workaround. PASS, 0 findings: no 'mockup accent, app neutral' and no 'border style differs'. widths[].theme recorded mockup fluent-modern/light vs app_had minimal/dark, and BlogAdmin was still minimal dark afterwards. Evidence tests/.artifacts/verify/recheck/tf010-conn.json.

- **Severity:** minor
- **Blocks:** no — the verify switched the app to the mockup's theme for the comparison and restored the owner's choice afterwards.
- **Repro:**
  ```
  bash .tfcore/utils/tf-mockup-parity.sh --cdp http://172.18.144.1:9223 --screen admin/connection-settings=/connection-settings
  ```
- **Expected:** The app and the mockup are compared in the same theme (the mockup's `data-site-theme` / `data-theme`).
- **Actual:** BlogAdmin kept the owner's saved `minimal` dark theme (localStorage), the mockup renders `fluent-modern` light, and every primary button and link was reported "mockup accent, app neutral". With the app on `fluent-modern` light those findings were gone.
- **Encountered in:** build-phase (TF-006 re-check), 2026-09-28
- **Workaround:** Set `techieblog-theme` / `techieblog-dark-mode` in the app to the mockup's theme before the check, restore after.
- **Suggested fix:** Read the mockup's theme attributes and apply them to the app page (or report a theme mismatch as "not graded") before comparing.

### TF-011 — A state-only box at the top of a mockup shifts the mockup check's positional comparison

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: ran the same check with --mockups on a scratch copy whose three state-only messages are div elements marked only data-state-testid (tests/.artifacts/verify/recheck/mockups-tf011): PASS, 0 findings, no 'conn-card > div[1] > div[0] border style differs'. Control: the same copy with the mark removed from conn-reason gives exactly that finding (tf011-ctrl.json), so the fix is what removes it.

- **Severity:** minor
- **Blocks:** no — the one finding it causes is named as a false positive in the row's Remarks.
- **Repro:**
  ```
  bash .tfcore/utils/tf-mockup-parity.sh --cdp http://172.18.144.1:9223 --screen admin/connection-settings=/connection-settings
  ```
- **Expected:** A box marked state-only (`data-state-testid`, or `data-tf-state` per TF-005) is left out before children are numbered, as the screen check already does for anchors.
- **Actual:** `conn-card > div[1] > div[0] border style differs — mockup solid, app none`: in the mockup the first child is the state-only database-down alert, in the app's first view it is the Host/Port row.
- **Encountered in:** build-phase, 2026-09-28
- **Workaround:** None needed; the finding is ignored for Connection settings.
- **Suggested fix:** Skip state-only elements in the mockup when building `div[n]` paths.

### TF-012 — The document checker fails a Remark the verdict script wrote, because a test title says "Not found"

> ✅ **Closed 2026-09-28** — re-checked here: Closed 2026-09-28: ran a targeted *verify REQ-UI-133 (phase8-admin spec, screen/assets/mockup checks on AI Setup over CDP 9223). Verdict PASS; the Remark reads 'test `REQ-UI-133 AI Setup embedding card shows Found/Not found and`; AI Setup renders and looks right @1280/390; matches its mockup'. bash .tfcore/utils/tf-doc-check.sh docs/Lekhak-Checklist.md: 0 FAIL, no rewording.

- **Severity:** minor
- **Blocks:** no — the Remark was reworded by hand and the checklist passes.
- **Repro:**
  ```
  bash .tfcore/utils/tf-doc-check.sh docs/Lekhak-Checklist.md
  ```
- **Expected:** A Remark written by `tf-verify-verdict.sh` passes `tf-doc-check.sh`.
- **Actual:** The verdict copies the test title "REQ-UI-133 AI Setup embedding card shows Found/Not found …" into the Remark, and the checker fails it as "says something is not present without naming the path that was tried". It will return after every verify.
- **Encountered in:** build-phase, 2026-09-28
- **Workaround:** Reword the phrase in the Remark after each verify.
- **Suggested fix:** Apply the "not present" rule only to text an agent wrote, not to a quoted test title, or have the verdict quote titles in backticks and skip those.

### TF-013 — The TF-010 theme switch leaves the app's `class="dark"` on, so dark-mode colours still apply

> ✅ **Closed 2026-09-29** — re-checked here: Closed 2026-09-29: with BlogAdmin on its saved minimal dark theme (html data-site-theme=minimal data-theme=dark class=dark) and no workaround, ran tf-mockup-parity.sh --cdp http://172.18.144.1:9223 --screen admin/ai-setup=/admin/ai-setup: PASS, 0 findings (no 'color reembed-note — mockup neutral, app accent'). BlogAdmin was still minimal dark with class=dark afterwards. Evidence tests/.artifacts/verify/recheck/tf013b.json.

- **Severity:** minor
- **Blocks:** no — the verify switched BlogAdmin fully to light (theme and dark flag) for the comparison and restored the owner's dark theme afterwards.
- **Repro:**
  ```
  bash .tfcore/utils/tf-mockup-parity.sh --cdp http://172.18.144.1:9223 --screen admin/ai-setup=/admin/ai-setup
  ```
- **Expected:** With BlogAdmin on its saved minimal dark theme, AI Setup compares in the mockup's light theme and passes, as it does when the app is switched to light by hand.
- **Actual:** `color reembed-note — mockup neutral, app accent` at 1280 and 390. The tool set `data-site-theme` and `data-theme` but left `class="dark"` on `<html>`, so the info note kept its dark-mode background (oklch 0.26 0.045 250). Switched to light fully (which also drops `class="dark"`), the same check passes with 0 findings. Connection settings passes either way, which is why the TF-010 re-check did not show it.
- **Encountered in:** verify-phase (TF-012 re-check), 2026-09-28
- **Workaround:** Set the app's saved theme to the mockup's (`techieblog-theme`, `techieblog-dark-mode`) before the check, restore after.
- **Suggested fix:** Also carry a `dark`/`light` class on `<html>`/`<body>` (a class token whose name is a theme mode), or read the mockup's light/dark and toggle the app's class to match.

### TF-014 — The DevGuide lister crashes on the `.tfbuild` folder, so `*devguide --update` cannot run

> ✅ **Closed 2026-09-29** — re-checked here: Closed 2026-09-29: bash .tfcore/utils/tf-devguide-list.sh Lekhak --update exits 0 and prints the work list (65 routes in code, 41 UIDesign screens); its --update part names the five files in docs/devguides/ and says to carry their entries into docs/Lekhak-DevGuide.md. No .tfbuild crash.

- **Severity:** major
- **Blocks:** no — at handoff the DevGuide entries for the screens changed or added in this phase were written by hand from the code at file and line.
- **Repro:**
  ```
  bash .tfcore/utils/tf-devguide-list.sh Lekhak --update
  ```
- **Expected:** The work list of screens with files newer than the guide.
- **Actual:** `tf-devguide-list: [Errno 2] No such file or directory: 'tfbuild/AdminChk/Debug/net10.0/.playwright/package/cli.js'`. `walk()` in `tf-devguide-list.py` descends into `.tfbuild` (not in `PRUNE`) and `.lstrip("./")` strips the leading dot, so `.tfbuild/…` becomes `tfbuild/…`, which does not exist.
- **Encountered in:** handoff-phase, 2026-09-29
- **Workaround:** Update the DevGuide by hand.
- **Suggested fix:** Add `.tfbuild` to `PRUNE`, and replace `.lstrip("./")` with removing a leading `./` prefix only (`p[2:] if p.startswith("./") else p`).

### TF-015 — The HTML renderer keeps links to sibling `.md` files, so a split guide's index opens raw markdown

> ✅ **Closed 2026-09-29** — re-checked here: Closed 2026-09-29: re-rendered the five docs/productguides/*.md with no post-render edit; the index links to ./Lekhak-ProductGuide-{Admin,Author,Editor,Reader}.html and no .md href remains in the five HTML files. The DevGuide index links came out as .html too. Scratch test: [./c.md#part] with c.html present -> ./c.html#part; [./b.md] with no HTML copy -> stays ./b.md; https link and #anchor unchanged.

- **Severity:** minor
- **Blocks:** no — the product guide's generated HTML was corrected to link `.html` after rendering.
- **Repro:**
  ```
  bash .tfcore/utils/tf-render-html.sh docs/productguides/Lekhak-ProductGuide.md
  ```
- **Expected:** `[Admin](./Lekhak-ProductGuide-Admin.md)` renders as a link to `./Lekhak-ProductGuide-Admin.html` when that sibling is also rendered.
- **Actual:** The HTML keeps `href="./Lekhak-ProductGuide-Admin.md"`, so a reader clicking through the index in a browser lands on raw markdown. The split DevGuide index has the same shape.
- **Encountered in:** productguide, 2026-09-29
- **Workaround:** Replace the `.md` hrefs with `.html` in the rendered files after each render.
- **Suggested fix:** Rewrite relative links to `*.md` as `*.html` when the target has (or will get) a rendered sibling.

### TF-016 — `*amend-docs` never runs the unit tests, so it can delete a paragraph a test guards and only CI notices

> ✅ **Closed 2026-09-30** — re-checked here: Closed 2026-09-30: bash .tfcore/utils/tf-doc-tests.sh docs/Lekhak-UsageGuide.md printed PASS naming tests/Lekhak.Tests/Common/VerificationRuleDocTests.cs (plus AppSecretsTests.cs and tests/verify/_phase8-db.ts), unit tests PASS, exit 0; the same on docs/Lekhak-BRD.md printed 'NONE no test reads docs/Lekhak-BRD.md; nothing to run'.

- **Severity:** major
- **Blocks:** no — the paragraph was restored in `triage-and-fix` on 2026-09-30 and the suite passes 855/855.
- **Repro:**
  ```
  # after an *amend-docs that edits docs/Lekhak-UsageGuide.md
  cmd.exe /c "cd /d C:\3AIGenCode\Lekhak && dotnet test tests\Lekhak.Tests\Lekhak.Tests.csproj --configuration Release"
  ```
- **Expected:** a command that edits a document which a unit test reads (here `VerificationRuleDocTests` reads the UsageGuide) runs the unit suite before it closes, and fails its phase when a test fails.
- **Actual:** `*amend-docs` on 2026-09-29 (Mac deferral, ADR-021) removed the quoted REQ-NFR-042 paragraph from the UsageGuide. Neither `amend-docs.md` nor `_status-update-gate.md` runs any test, so the phase closed green and CI run 36612916084 failed on `REQ-NFR-042 UsageGuideStatesBothHeadsRule`. Logged as a miss sorted `unsaid`.
- **Encountered in:** triage-and-fix, 2026-09-30
- **Workaround:** run the unit suite by hand after any document edit.
- **Suggested fix:** in the status gate, when the command wrote a file under `docs/`, run `tf-build.sh test` (unit only) and fail on a red test. Or have `*amend-docs` run it as its last step.

### TF-017 — A scoped verify of one no-screen NFR row runs the whole browser suite and hits the 30-minute limit

> ✅ **Closed 2026-09-30** — re-checked here: Closed 2026-09-30: tf-verify-list.sh Lekhak REQ-NFR-042, then tf-verify-tests.sh --base http://localhost:59689 without --no-browser printed 'browser tests: skipped — no row in scope (REQ-NFR-042) has a screen and no file under tests/verify/ names one'; finished in 139 s (unit build included, against 30+ min before) with REQ-NFR-042 PASS.

- **Severity:** minor
- **Blocks:** no — re-ran with `--no-browser`, which graded the row from its unit test.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-list.sh Lekhak REQ-NFR-042
  bash .tfcore/utils/tf-verify-tests.sh --base http://localhost:59689
  ```
- **Expected:** `tf-verify-tests.sh` runs only the tests carrying the ids in `list.json`, and skips Playwright when no row in scope has a screen. `verify-phase.md` step 5 names `--no-browser` for that case.
- **Actual:** it runs every spec under `tests/verify/` for a single row whose only test is a unit test; the command was stopped after 30 minutes with no output.
- **Encountered in:** triage-and-fix (chained verify), 2026-09-30
- **Workaround:** `--no-browser` for a scope with no screen.
- **Suggested fix:** filter the Playwright run by the scope's ids (`--grep`), and skip it entirely when `list.json` has no screen.

### TF-018 — `tests.json` writes "unit test skipped" as the reason for a unit test that passed

> ✅ **Closed 2026-09-30** — re-checked here: Closed 2026-09-30: in that run's tests/.artifacts/verify/tests.json, reqs['REQ-NFR-042'].outcomes reads {"REQ-NFR-042 UsageGuideStatesBothHeadsRule": {"outcome": "pass", "reason": "", "screenshot": ""}}.

- **Severity:** minor
- **Blocks:** no — the outcome field is right (`pass`), and the verdict reads the outcome.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-tests.sh --no-browser
  # tests/.artifacts/verify/tests.json → reqs["REQ-NFR-042"].outcomes
  ```
- **Expected:** a passing test has an empty reason.
- **Actual:** `{"outcome": "pass", "reason": "unit test skipped: REQ-NFR-042 UsageGuideStatesBothHeadsRule"}` — the same for every unit row.
- **Encountered in:** triage-and-fix, 2026-09-30
- **Workaround:** none needed; read `outcome`.
- **Suggested fix:** set `reason` only when the outcome is `skip` or `fail`.

### TF-019 — Nothing says to reproduce a CI failure with an empty package cache, so a local "pass" can hide the real error

> ✅ **Closed 2026-09-30** — re-checked here: Closed 2026-09-30: bash .tfcore/utils/tf-ci-repro.sh --list planned steps 6-9 (Restore, Build, Locate test project, Test) with empty caches and skipped the uses:/secret/setup steps; bash .tfcore/utils/tf-ci-repro.sh printed 'PASS job build: 4 run step(s) passed on a clean copy with empty caches' in 240 s (logs tests/.artifacts/ci-repro/20260930T162834Z).

- **Severity:** minor
- **Blocks:** no — the failure was reproduced with an empty cache and fixed on 2026-09-30.
- **Repro:**
  ```
  set NUGET_PACKAGES=<empty folder> && dotnet restore Lekhak.slnx && dotnet build Lekhak.slnx --configuration Release --no-restore
  ```
- **Expected:** when a task reproduces a CI workflow locally, it runs the restore against an empty package folder, as a fresh runner does.
- **Actual:** `triage-and-fix` ran the workflow's steps with the developer's warm NuGet cache. The win-x64 runtime pack was already cached, so the NETSDK1112 failure CI hits never appeared. The run reported the CI failure fixed; the owner's next CI run still failed (MISS-Lekhak-20260930-02).
- **Encountered in:** triage-and-fix, 2026-09-30
- **Workaround:** set `NUGET_PACKAGES` to an empty folder for the reproduction.
- **Suggested fix:** a `tf-ci-repro.sh` that reads the workflow's `run:` steps and runs them with an empty `NUGET_PACKAGES` (and the npm equivalent), named by `triage-issues` when the evidence is a CI run.

### TF-020 — The metrics script counts suite-level gate records as failures

> ✅ **Closed 2026-10-04** — re-checked here: Closed 2026-10-04: ran bash .tfcore/telemetry/tf-metrics.sh --report . --json and --report . on this stream. gate_distribution_n is now 68 (was 72) and build is 3 (was 4); gates_malformed_n is 4. The text report prints '4 gate record(s) carry no req_id or no verdict' and names them by date and gate: 2026-08-17T14:45:30Z verify-suite/unit-tests/build and 2026-08-18T07:24:18Z verify-suite (gates.jsonl lines 76-79). They are left out of every figure. METRICS.md no longer describes the defect as open.

- **Severity:** minor
- **Blocks:** no — only the gate-catch table in METRICS.md is off by four records; nothing in the build or verify depends on it.
- **Repro:**
  ```
  bash .tfcore/telemetry/tf-metrics.sh --report . --json
  # docs/metrics/gates.jsonl lines 76-79 (2026-08-17/18): no req_id, no verdict, gate "verify-suite" / "unit-tests"
  ```
- **Expected:** a record without a `req_id` and verdict is skipped or reported as malformed. A pass is never counted as a failure.
- **Actual:** all four count as failures (72 in all), and three of them recorded a pass. One lands in the `build` row. The other three use gate names outside the schema, so they appear in no row.
- **Encountered in:** triage-and-fix, 2026-10-04 (metrics step)
- **Workaround:** METRICS.md §2 and §7 name the four records.
- **Suggested fix:** in `tf-metrics.sh`, count a gate record as a failure only when it carries a `req_id` and a verdict other than `Verified`, and list the rest as malformed.

### TF-021 — The test runner does not pass the booted desktop app's debugging address to the browser tests

> ✅ **Closed 2026-10-04** — re-checked here: Closed 2026-10-04: tf-verify-tests.sh --base http://172.18.144.1:9223 (desktop head) exported CDP_URL; with tests/verify/_admin-transport.ts reading CDP_URL first, phase8-admin.spec.ts ran 19/19 tests against the booted app with no ADMIN_CDP set.

- **Severity:** minor
- **Blocks:** no — setting `ADMIN_CDP` by hand makes the same run pass.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-boot.sh start --head windows        # BOOTED … url=http://172.18.144.1:9223
  ADMIN_TRANSPORT=cdp bash .tfcore/utils/tf-verify-tests.sh --base http://172.18.144.1:9223 --spec tests/verify/all-admin.spec.ts
  ```
- **Expected:** the tests reach the app on the address the boot printed.
- **Actual:** every desktop test fails with `connectOverCDP: connect ECONNREFUSED 172.18.144.1:9334`, the test helper's built-in default, and the run took more than ten minutes to fail.
- **Encountered in:** triage-and-fix, 2026-10-04 (verify step)
- **Workaround:** `export ADMIN_CDP=<the boot URL>` before `tf-verify-tests.sh`.
- **Suggested fix:** when `--base` (or `boot.json`) is a CDP address, `tf-verify-tests.sh` exports it to the test process under a documented name.

### TF-022 — The mockup check looks for `docs/mockups/<screen>.html` only, so a mockup in a subfolder is reported as missing

- **Severity:** minor
- **Blocks:** no — passing `--mockups docs/mockups/admin` grades the screen.
- **Repro:**
  ```
  bash .tfcore/utils/tf-mockup-parity.sh --cdp http://172.18.144.1:9223 --screen prompt-manager=/admin/prompt-manager --json-out parity.json
  # the scoped list.json names docs/mockups/admin/prompt-manager.html
  ```
- **Expected:** the check uses the mockup path that `tf-verify-list.sh` resolved for the screen.
- **Actual:** verdict `NO-MOCKUP` ("no docs/mockups/<screen>.html"), so the design comparison silently does not run.
- **Encountered in:** triage-and-fix, 2026-10-04 (verify step)
- **Workaround:** pass `--mockups` with the subfolder, one screen group at a time.
- **Suggested fix:** accept `--list list.json` and read each screen's mockup path from it.

### TF-023 — The document baseline covers only two files, so `*amend-docs` sees ~130 old findings as new

- **Severity:** minor
- **Blocks:** no — the amendment's own text was checked line by line; the old findings are about the pre-template shape of the 2026-08 documents.
- **Repro:**
  ```
  bash .tfcore/utils/tf-phase.sh start amend-docs Lekhak      # "baseline written for 2 file(s)"
  bash .tfcore/utils/tf-doc-check.sh --app Lekhak             # 131 FAIL not marked OLD (BRD, Architecture, UIDesign, Coding Standards, mockups index)
  ```
- **Expected:** a command that owns every document (`*amend-docs`, day-1) baselines every document it may check, so only findings it introduced block it.
- **Actual:** only `docs/Lekhak-Checklist.md` and `PROJECT-STATUS.md` are baselined; header, section-name, word-count and size-cap findings that pre-date the run print as new FAILs.
- **Encountered in:** amend-docs, 2026-09-26 and 2026-10-04
- **Workaround:** compare against a check run before editing and fix only new findings.
- **Suggested fix:** `tf-phase.sh start amend-docs` baselines every file `tf-doc-check.sh --app` reads.

### TF-024 — The screen and mockup checks only ever look at the light theme, so a dark mode that is unusable passes verify

> ✅ **Closed 2026-10-09** — re-checked here: 2026-10-09: tf-verify-screens.sh graded every screen in light + dark themes with a 3:1 contrast rule and a dark light-panel rule (it caught the header avatar at 2.56:1 and two light panels on the desktop head), and tf-mockup-parity.sh graded colour in dark mode. Fixed.

- **Severity:** major
- **Blocks:** no — Lekhak now carries its own two-theme contrast test (`tests/verify/theme-contrast.spec.ts`), which the verify runs as a normal acceptance test.
- **Repro:**
  ```
  bash .tfcore/utils/tf-verify-screens.sh --cdp http://172.18.144.1:9223 --screen ai-story-studio=/admin/ai-story-studio   # light theme only; no option for dark
  ```
- **Expected:** for an app with a light/dark switch, the render, visual and mockup checks run in both themes, and the visual check measures text contrast (text against the colour actually painted behind it) and flags large light surfaces in dark mode.
- **Actual:** every screen was graded in light mode only. On 2026-10-07 the owner found 20 of 20 desktop admin screens with unreadable text in dark mode (contrast down to 1.03 : 1, white panels inside a dark shell). All of them were `Verified`.
- **Encountered in:** triage-and-fix, 2026-10-07 (UAT)
- **Workaround:** the project-level Playwright test named above.
- **Suggested fix:** `tf-verify-screens.sh --themes light,dark` (default: both when the app declares a theme switch in its UIDesign), a contrast rule in the visual check (3.0 : 1 minimum, disabled controls exempt), and the mockup parity check run per theme.

### TF-025 — The mockup check compares the app in the user's site theme against the mockup in its own, so a themed colour reads as a mismatch

- **Severity:** minor
- **Blocks:** no — for the 2026-10-09 verify the desktop app's stored site theme was switched to the mockup's (`fluent-modern`) for the comparison and restored to `minimal` after; the comparison then passed.
- **Repro:**
  ```
  # desktop app with localStorage techieblog-theme = minimal; mockup <html data-site-theme="fluent-modern">
  bash .tfcore/utils/tf-mockup-parity.sh --cdp http://172.18.144.1:9223 --screen story-crawler=/admin/story-crawler --list tests/.artifacts/verify/list.json
  ```
- **Expected:** the check renders the app and the mockup in the same site theme (the mockup's `data-site-theme`), or grades colour per site theme.
- **Actual:** `color on crawler-auto-save @1280 in dark mode: semantic colour differs — mockup accent, app neutral` — the minimal theme's dark primary is grey, the mockup's is blue. Three rows failed for a theme choice, not a defect.
- **Encountered in:** fix-issues, 2026-10-09 (REQ-UI-051, REQ-FN-065, REQ-FN-137)
- **Workaround:** switch the app's stored site theme to the mockup's for the comparison, then restore it.
- **Suggested fix:** have `tf-mockup-parity.sh` set the app's `data-site-theme` (and any stored theme key the UIDesign names) to the mockup's before comparing, and put it back after.

### TF-026 — The Mac boot says BOOTED without reaching the app, and the Mac driver cannot run on a fresh macOS 27 / Xcode 27 machine

> ✅ **Closed 2026-10-10** — re-checked here: Closed 2026-10-10: on this Mac (macOS 27.0, Xcode 27.0) tf-verify-boot.sh start --head maccatalyst printed BOOTED ... window=tests/.artifacts/verify/boot-4723-window.png and the picture shows BlogAdmin's Dashboard (signed in as Tharak Chand). stop left no app or Appium process; the second start opened one window with no reopen-windows dialog and no Don't Reopen line. After touch Platforms/MacCatalyst/Info.plist the build log line 3 read 'note ... Info.plist is newer than the built app ...; cleared bin/... and obj/...'.

- **Severity:** major
- **Blocks:** no, since 2026-10-10. Before the driver was reinstalled and Automation Mode was switched on, it blocked every automated check of BlogAdmin's Mac screens; the Mac sign-in has since been driven to the Dashboard.
- **Repro:**
  ```
  bash .tfcore/utils/tf-maccatalyst-check.sh        # OK after the Lekhak fixes
  bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst
  ```
- **Expected:** `BOOTED` means the app's first screen is on view and a mac2 session can drive it.
- **Actual (macOS 27.0, Xcode 27.0, Appium 3.5.2, .NET MacCatalyst pack 26.5.10315):**

| Problem | What it affects | Does it block or break anything |
|---|---|---|
| `start --head maccatalyst` printed `BOOTED … mode=appium` while no mac2 session could be opened, and once while the app's only window was macOS's "unexpectedly quit while reopening windows" dialog. The boot only checks that the process and Appium are up. | Every Mac verify: a boot that reached nothing reads as a good boot. | Breaks: a false pass is possible. Does not block. |
| `stop` kills the app instead of quitting it, so the next start opens behind the "reopen windows" dialog. Quitting through `osascript -e 'tell application id "<bundle>" to quit'` avoids it. | Every Mac start after the first in a run. | Blocks the first-screen check until someone clicks **Don't Reopen**. |
| The installed mac2 driver (4.0.4) cannot build WebDriverAgentMac under Xcode 27: `MACOSX_DEPLOYMENT_TARGET 10.15` is below Xcode 27's 12.0 minimum (xcodebuild exit 65). `appium driver update mac2` to 4.3.6 then left the driver unloadable (`Cannot find package 'appium'`); `appium driver uninstall mac2` + `appium driver install mac2` fixed it. | Any Mac driven over Appium on Xcode 27. | Blocked every Mac session until fixed by hand (done on this Mac, 2026-10-10). |
| macOS 27 needs Automation Mode switched on once (`sudo automationmodetool enable-automationmode-without-authentication`, admin password). Without it every mac2 session fails with "Timed out while enabling automation mode". The boot neither checks nor reports it. | Every mac2 session on a machine where it was never switched on. | Blocked until the owner switched it on (done 2026-10-10). |
| Typing into a Blazor Hybrid form on the Mac: setting a field's value through Accessibility, keyboard events posted to the app's process, and mac2's element "set value" all left Blazor's `@bind` empty or partly filled (`The text must have valid value`). What worked: mac2 click on the field, then W3C key actions (`POST /session/{id}/actions`, key down/up per character). | Any Mac check that fills a form: sign-in first of all. | Broke the first automated sign-in tries. Not blocking once key actions are used: user 1 signed in to the Dashboard on 2026-10-10. |
| After `Platforms/MacCatalyst/Info.plist` changed, an incremental `dotnet build` refreshed the DLLs but left the `.app`'s Info.plist from 2026-10-07, so the app still crashed for want of the scene manifest the source already had. Only a clean build (`rm -rf bin obj`) produced the right bundle. | A Mac fix that lives in Info.plist or entitlements looks as if it failed. | Breaks: a false failure (crash at first window) until a clean build. |

- **Encountered in:** Mac set-up for UAT, 2026-10-10.
- **Workaround:** driver reinstalled as above; app quit through `osascript`, never killed; first screen proved with a window-only screenshot (`screencapture -l <window id>`); the Mac build cleaned after any Info.plist or entitlements change.
- **Suggested fix:** `BOOTED` only after a mac2 session opens and a screenshot of the app's window shows no system dialog; `stop` quits through AppleScript first and kills only on timeout; the boot checks `automationmodetool` and the mac2 driver version against the Xcode version, and names the exact fix; `tf-build.sh` cleans the Mac head when `Platforms/MacCatalyst/*.plist` is newer than the built bundle.

### TF-027 — The Mac screen check passes a website screen on BlogAdmin's Dashboard, and reaches only screens whose menu label equals the screen name

- **Severity:** major
- **Blocks:** no for UAT (TF-003 stays open); yes for closing TF-003. A Mac screen verdict cannot be trusted yet: one OK is false and 13 of 18 screens are not graded.
- **Repro (macOS 27.0, Xcode 27.0, framework as of the 2026-10-10 reply):**
  ```
  bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst
  bash .tfcore/utils/tf-verify-list.sh Lekhak ui
  bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --appium http://localhost:4723
  ```
- **Expected:** every BlogAdmin screen in the list is reached and graded at 1280 and 390 px; a screen BlogAdmin does not serve (a website page) is skipped as "other head", never graded.
- **Actual:** exit 5. The exact summary and the lines that matter:
  ```
  OK   Search results (/search) — render OK, visual OK, names not measured (web view)
  FAIL Category archive (/category/{slug}) — render UNREACHABLE, visual n/a, names not measured (web view) — no control reaches Category archive: give its tab, flyout item, link or button AutomationId="nav-category-archive", or the label "Category archive"
  FAIL Connection settings (/connection-settings) — render UNREACHABLE, visual n/a, names not measured (web view) — no control reaches Connection settings: give its tab, flyout item, link or button AutomationId="nav-connection-settings", or the label "Connection
  FAIL Manage Images (/admin/images) — render UNREACHABLE, visual n/a, names not measured (web view) — no control reaches Manage Images: give its tab, flyout item, link or button AutomationId="nav-manage-images", or the label "Manage Images"
  FAIL Manage Profile (/admin/profile) — render UNREACHABLE, visual n/a, names not measured (web view) — no control reaches Manage Profile: give its tab, flyout item, link or button AutomationId="nav-manage-profile", or the label "Manage Profile"
  FAIL LLM sign-in (/admin/llm-signin/{ProviderId:long}) — render UNREACHABLE, visual n/a, names not measured (web view) — no control reaches LLM sign-in: give its tab, flyout item, link or button AutomationId="nav-llm-sign-in", or the label "LLM sign-in"
  OK   Story Crawler (/admin/story-crawler) — render OK, visual OK, names not measured (web view)
  screens 18: render 5 OK / 0 failed / 13 unreachable; visual 5 OK / 0 failed; control names not measured (web view); screenshots tests/.artifacts/verify/screens; JSON tests/.artifacts/verify/screens.json
  ```
  `screens.json` for Search results: `"reached": "the screen the app opens on (no control named it)"`, and `search-results-mac.png` is BlogAdmin's Dashboard.

| Problem | What it affects | Does it block or break anything |
|---|---|---|
| A screen no control reaches is graded on whatever screen the app opened on. "Search results" is a website page (`source/Lekhak`), and it passed on BlogAdmin's Dashboard. | Any Mac verdict: a screen can pass without ever being shown. | Breaks: a false pass. |
| The list does not say which head serves a screen, so 9 website pages (Category archive, Tag archive, Access denied, Login, Forgot Password, Reset Password, My Favorites, Author Profile, and Search results above) are driven on BlogAdmin. | Every Mac run for an app with a web head and a desktop head. | Breaks: 8 false UNREACHABLE failures and the false pass above. |
| A screen is reached only through a control whose label equals the screen's name, or an `AutomationId`. BlogAdmin's menu says "Images" and "My Profile" (screens "Manage Images", "Manage Profile"); Add User is a button on Users; Connection settings is a link on the sign-in screen; LLM sign-in needs a provider id. A Blazor Hybrid page cannot carry an `AutomationId` that the Mac driver reads (coding-standards-dotnet.md §9), so the fix the message suggests is impossible here. | 5 real BlogAdmin screens are never graded on the Mac. | Blocks grading them; does not block UAT. |
| Each screen is measured once, at the window's own size (1715 × 1121), not at 1280 and 390 px. | Every Mac screen verdict. | Breaks: the narrow-width checks never run on the Mac. |
| The screenshots, and `boot-4723-window.png`, are a crop of the screen, not the window alone: a Chrome notification banner is in the top-right corner of each. | The visual check and the evidence pictures. | Could break: an overlapping system banner is graded as part of the app. |
| `tf-verify-list.py` keeps stray Markdown backticks in the test users it reads from the UsageGuide, e.g. password ``admin_password` `` and email ``Tharki@tksories.com` ``. | Any check that signs in with those users. | Breaks a scripted sign-in that uses them as printed. |
| With no `list.json` (none had been made on this Mac), `tf-verify-screens.sh --appium` crashed with a Node stack trace (`Error: ENOENT: no such file or directory, open 'tests/.artifacts/verify/list.json'` at `tf-verify-native.mjs:51:33`) instead of naming `tf-verify-list.sh`. | First Mac run on a new machine. | Does not block; confusing. |

- **Encountered in:** TF-026 / TF-003 re-check on the Mac, 2026-10-10.
- **Workaround:** none for a verdict. The four BlogAdmin screens reached through their menu label (Story Crawler, AI Story Studio, Prompt Manager, AI Setup) were graded correctly; their screenshots show the right screens.
- **Suggested fix:** grade a screen only when the driver reached it, otherwise mark it UNREACHABLE; carry the serving head in `list.json` (from the project that holds the `@page`) and skip other-head screens; let the list name a navigation path per screen for a Blazor Hybrid head (menu label, then button), and route-only screens as not drivable; resize the window to 1280 and 390 px; capture the window by its window id; strip Markdown from test-user fields; a missing list prints which script makes it.

## Replies from TechieFlow

<!-- The upstream team's answers, newest block first. Left in full: this is the record. -->

### Resolution status (TechieFlow team, 2026-10-10, second reply)

| ID | Fix | Check it here |
|---|---|---|
| TF-027 | Fixed upstream, one change per problem in your table. (1) A screen the check did not reach is never graded. Only a screen whose route is `/` may be the one the app opens on. Any other screen nothing reached is `UNREACHABLE`, and the line says why. (2) `tf-verify-list.sh` now reads, from the code, which project serves each screen: the project holding the `@page` for its route. A screen served by a project the booted head does not include is skipped as another head's (`SKIP … served by source/Lekhak`). The verdict writes those rows as not driven, with that reason. (3) The list also reads, from the code, how each screen is reached: the links and buttons whose `href`/`Href` names its route, with their visible text. A link in the layout or menu is on every screen; a link on a page is only on that page. So "Manage Images" is reached by clicking "Images", and "Add User" by "Users" then "+ Add New User". You don't need to add anything to the app. A route that takes a value, with no link that reaches it, is skipped and says so. (4) Each screen is measured at 1280 and 390 px. macOS resizes the window, and the width it really took is recorded: BlogAdmin stops at 616 px, so its line reads `@1280/616 (asked 390)`. (5) Screenshots, and `boot-4723-window.png`, are the window alone, taken by macOS by its window number, so no banner gets in. Each width has its own picture (`<screen>-1280-mac.png`, `<screen>-390-mac.png`). (6) Test users are plain text: `Tharki@tksories.com`, password source `admin_password — seed 003-SeedData.sql`. (7) With no `list.json`, the check says to run `tf-verify-list.sh` first, without a stack trace. Regression case `lk_027` fails 3 of 3 against the scripts you have and passes now. The Mac self-test now covers a screen reached by a menu label, another head's screen, a screen nothing links to, and both widths. Miss `MISS-TechieFlow-20261010-04`. | Proved here on BlogAdmin, on this Mac, signed in as Tharak Chand. The 9 website pages are `SKIP`. LLM sign-in is `SKIP` (its route takes a value). Add User, Manage Images, Manage Profile, Story Crawler, AI Story Studio, Prompt Manager and AI Setup are all `OK` at 1280 and 616, and each picture shows the right screen. Connection settings is `UNREACHABLE`: the code reaches it through "Go to Sign in", which only shows when signed out. It is not graded as some other screen. Nothing passed on the wrong screen. To re-check, update the framework, then run `bash .tfcore/utils/tf-verify-list.sh Lekhak ui`, boot with `bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst`, and run `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --appium http://localhost:4723`. Expect the same lines. |

TF-003 stays open until it is re-checked here. The run above grades 7 of BlogAdmin's 8 Mac screens; Connection settings needs a signed-out start, which this check does not do yet.

### Resolution status (TechieFlow team, 2026-10-10)

| ID | Fix | Check it here |
|---|---|---|
| TF-025 | Fixed upstream in `tf-mockup-parity`. The cause was the order of the two passes. The TF-010 fix put the mockup's site theme (`data-site-theme="fluent-modern"`) on the app for the first pass, then took it off before the dark pass that TF-024 added. So the dark pass drew the app in your stored `minimal` theme, whose dark primary is grey, against the mockup's blue. The mockup's site theme now stays on the app through both passes, and comes off once both are done. For the dark pass the app also gets its own light/dark class back (BlogAdmin's `class="dark"`), so it is switched to dark the way your toggle does it. The app is left in the theme you had. Regression case `lk_025` builds your exact case: it fails against the script you have, with your finding (`semantic colour differs — mockup accent, app neutral`), and passes now. Miss `MISS-TechieFlow-20261010-01`. | After the framework update, with the desktop app on its stored `minimal` theme and no workaround, run `bash .tfcore/utils/tf-mockup-parity.sh --cdp <the boot url> --screen story-crawler=/admin/story-crawler --list tests/.artifacts/verify/list.json`. Expect PASS with no `crawler-auto-save … in dark mode` finding, and the app still on `minimal` afterwards. Then re-grade REQ-UI-051, REQ-FN-065 and REQ-FN-137 with a normal `*verify`. You no longer need to switch the stored site theme by hand. |
| TF-026 | Fixed upstream, one change per problem in your table. (1) `tf-verify-boot.sh start --head maccatalyst` says `BOOTED` only after a mac2 session has opened and found the app's own window on view, not a dialog. That window is saved as `tests/.artifacts/verify/boot-4723-window.png`, and the `BOOTED` line names it. Otherwise it prints `NONE` with the reason, and stops the app. (2) `stop` now quits the app the way Cmd-Q does, and kills it only if it has not quit within 15 seconds. The app is also started with `-ApplePersistenceIgnoreState YES`, so macOS never offers to reopen old windows. If that dialog shows anyway, the boot answers **Don't Reopen** and says so. (3) Before the build, the boot checks the mac2 driver against Xcode. Under Xcode 27, a driver older than 4.1.1 stops it with the fix: `appium driver uninstall mac2; appium driver install mac2`. (The driver's own change log says 4.1.1 is the first that builds with Xcode 27.) (4) It also checks Automation Mode. When macOS would ask for a password, the boot stops and names `sudo automationmodetool enable-automationmode-without-authentication`. (5) `tf-appium.mjs` has `s.type(el, text)`: a click on the field, then W3C key actions, one key down and up per character. That is the way you found works. Your own Mac tests can import it. (6) `tf-build.sh` checks a Mac Catalyst build before it starts. When a `.plist` or `.entitlements` file in `Platforms/MacCatalyst/` is newer than the built app, it clears that target's `bin/` and `obj/` folders first, and says so in a `note` line. Regression case `lk_026` fails against the scripts you have and passes now, for (3), (4) and (6). (1) and (2) were proved by the framework's Mac self-test on two fixture apps, one native and one Blazor Hybrid, on macOS 27 with Xcode 27: each boot opened a mac2 session and saved its window, and each `stop` left nothing running. They were not proved on BlogAdmin itself. Miss `MISS-TechieFlow-20261010-02`. | After the framework update: `bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst`. Expect `BOOTED … window=tests/.artifacts/verify/boot-4723-window.png`, and that picture shows BlogAdmin's first screen. Then run `bash .tfcore/utils/tf-verify-boot.sh stop`, then `start` again. The second start opens with no "reopen windows" dialog and no "answered Don't Reopen" line. To check (6), touch `Platforms/MacCatalyst/Info.plist` and boot again. The build log starts with `note … is newer than the built app`. |
| TF-008 | Fixed upstream in `tf-doc-check`. A link in a mockup is now read from that mockup's own folder, as a browser reads it. It passes when the file exists anywhere inside `docs/mockups/`. A missing file still fails, and so do a link that starts with `/` and a link that leads out of `docs/mockups/`. Each of those failures now says which of the three it is. This entry went unanswered from 2026-09-28; sorry for the wait. Regression case `lk_008` fails against the script you have and passes now. Miss `MISS-TechieFlow-20261010-03`. | Proved here on your own `docs/`. Your script: 687 FAIL, 60 of them `does not open from docs/mockups/`. New script: 627 FAIL, none of those, and no new ones. After the framework update, `bash .tfcore/utils/tf-doc-check.sh --app Lekhak` prints no `admin/…` or `web/…` link failure. |

TF-003 stays open, but it is closer. Since 2026-10-07 the framework drives a Mac head (`tf-verify-boot.sh --head maccatalyst`, `tf-verify-screens.sh --appium`). With TF-026 above, a `BOOTED` now means a mac2 session really reached the first screen. What is left is one real run on BlogAdmin. Once TF-026 checks out, boot as above, then run `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --appium http://localhost:4723`. When the Mac screens are graded, re-check TF-003 here.

### Resolution status (TechieFlow team, 2026-10-08)

| ID | Fix | Check it here |
|---|---|---|
| TF-024 | Fixed upstream. `tf-verify-screens` grades every screen in light mode, then in dark mode. In the default (auto), dark runs once a screen shows the app has a dark theme: what it paints changes when dark is put on it. `--themes light,dark`, `light` or `dark` forces the choice. A theme is put on the page the way your toggle does it, through the light/dark value of `data-theme` on `<html>` (any `data-*theme`, `data-*mode` or `data-*scheme` attribute, and a `dark` or `light` class). The browser's colour scheme is set too. Both are put back after each screen, so the desktop app is left in the theme you had. The visual check now measures every visible piece of text, and every field's value, against the colour actually painted behind it, layers blended. Below 3.0 : 1 is a `low-contrast` finding (`--min-contrast` changes the floor). Disabled controls are exempt, and text over an image or a gradient is not measured. In dark mode, a box over 2% of the window painted lighter than 0.8 luminance is a `light-surface` finding. Each finding says "in dark mode", and dark screenshots are saved as `<screen>-<width>-dark.png`. `tf-mockup-parity` compares each screen a second time in the other theme. When the mockup has no dark styles, the app's dark screen is compared with the mockup as drawn, colour left out. Proved here on BlogAdmin over CDP, signed in as the admin: AI Story Studio, Dashboard, LLM Providers and Prompt Manager were graded in light and dark, all four pass, the dark screenshots are really dark, and the app was back in light afterwards. A planted white panel in dark mode could not be tried on the live app, because the database on port 5550 was down by then. It was tried in regression case `lk_024`: a white card and pale text in dark mode fail, light passes, and a disabled button is exempt. The case fails against the scripts you had and passes now. | After the framework update, boot the desktop head and run `bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --cdp <the boot url>`. Each screen's line reads `light + dark themes`, and `tests/.artifacts/verify/screens/` holds a `-dark.png` per screen. Your own `tests/verify/theme-contrast.spec.ts` can stay as REQ-NFR-027's acceptance test. |

### Resolution status (TechieFlow team, 2026-10-04, second reply)

| ID | Fix | Check it here |
|---|---|---|
| TF-023 | Fixed upstream, with three changes. (1) `tf-phase.sh start` now baselines every file `tf-doc-check.sh --app <App>` reads, as well as the checklists and `PROJECT-STATUS.md`. (2) The baseline now also keeps findings filed under a name that is not one of those files, such as the mockup-folder checks on `docs/mockups/index.html`. Before, those 60 were never kept, even for a file that was baselined. (3) A size finding has its count in its text (`20,677 words; the Small maximum is 8,000`), so any edit to an over-limit document, even a cut, made it read as new. The same finding now stays old while the count has not grown. A document that grows past its maximum still FAILs, and so does any finding the command adds. A command started inside another one still keeps the outer command's baseline (TrBlazeUI TF-002). Regression case `lk_023` fails against the scripts you had and passes now. Miss `MISS-TechieFlow-20261004-05`. | Proved on a copy of your `docs/` (without `PROJECT-STATUS.md`). Your scripts: `baseline written for 2 file(s)`, then 128 FAIL. New: `baseline written for 12 file(s)`, then 0 FAIL and 691 OLD. Adding a section the template does not have printed one FAIL, and adding 1,200 words to the BRD printed the size FAIL; cutting a line printed none. Here: `bash .tfcore/utils/tf-phase.sh start amend-docs Lekhak` reports about 12 files, then `bash .tfcore/utils/tf-doc-check.sh --app Lekhak` prints only OLD lines until you change something. |

### Resolution status (TechieFlow team, 2026-10-04)

| ID | Fix | Check it here |
|---|---|---|
| TF-020 | Fixed upstream, in two places. `tf-metrics.sh` now scores a gate record only when it carries both a `req_id` and a `verdict`. Any other record is left out of every figure, and the report names it under "gate record(s) carry no req_id or no verdict". The emitter (`tf-emit.sh gates`) now refuses such a record, so a suite result can no longer be written to `gates.jsonl`; it belongs in the run record. Your four records stay in the stream as they are (it is append-only) and are simply not counted. Regression case `lk_020` fails against the scripts you had and passes now. Miss `MISS-TechieFlow-20261004-02`. | Proved on your stream here. Old: 72 failures, `build` 4. New: 68 failures, `build` 3, and the four records from 2026-08-17/18 listed by date and gate name. Run `bash .tfcore/telemetry/tf-metrics.sh --report .` and look for the "4 gate record(s) carry no req_id or no verdict" lines. The note about the four records in METRICS.md §2 and §7 can go at the next `*metrics`. |
| TF-021 | Fixed upstream in `tf-verify-tests.sh`. When `--base` is a desktop app's debugging address (it answers `/json/version`), or there is no `--base` and `boot.json` says `mode: cdp`, the tests now get that address as `CDP_URL`, beside `BASE_URL`. `CDP_URL` is the documented name. If no test file reads `process.env.CDP_URL`, the browser run is refused at once with a line saying so, instead of failing after ten minutes. A web `--base` gets no `CDP_URL`. Regression case `lk_021` fails against the script you had and passes now. Miss `MISS-TechieFlow-20261004-03`. | **Your tests need one change first.** Two lines read `ADMIN_CDP` only: `tests/verify/_admin-transport.ts:66` and `tests/verify/connection-settings.spec.ts:28`. Make each read `process.env.CDP_URL ?? process.env.ADMIN_CDP ?? 'http://172.18.144.1:9334'`. Until then the framework refuses the desktop run (the refusal names `CDP_URL`). Then boot with `bash .tfcore/utils/tf-verify-boot.sh start --head windows` and run `ADMIN_TRANSPORT=cdp bash .tfcore/utils/tf-verify-tests.sh --base <the boot url> --spec tests/verify/all-admin.spec.ts` with no `export ADMIN_CDP`. The tests reach the app on the boot's address. |
| TF-022 | Fixed upstream, on both sides. `tf-verify-list.sh` now ends its `Mockup parity:` line with `--list tests/.artifacts/verify/list.json`. `tf-mockup-parity.sh --list <list.json>` takes each screen's mockup path from the list, matched by the mockup's file name or the screen's name. With `--list` and no `--screen`, it drives every listed screen whose route needs no value. Without a list, a mockup missing at the top of `docs/mockups/` is looked for in its subfolders and used when exactly one file has that name. Two files with one name in different folders are never guessed between: that screen stays `NO-MOCKUP`. Regression case `lk_022` fails against the script you had and passes now. Miss `MISS-TechieFlow-20261004-04`. | On your checklist, `tf-verify-list.sh Lekhak REQ-UI-134` now prints `Mockup parity: --screen prompt-manager=/admin/prompt-manager --list tests/.artifacts/verify/list.json`. With the desktop head booted, run `bash .tfcore/utils/tf-mockup-parity.sh --cdp <the boot url> --screen prompt-manager=/admin/prompt-manager --list tests/.artifacts/verify/list.json --json-out tests/.artifacts/verify/parity.json`. Prompt Manager is graded against `docs/mockups/admin/prompt-manager.html` and no longer reads `NO-MOCKUP`. You no longer need `--mockups docs/mockups/admin`. |


### Resolution status (TechieFlow team, 2026-09-30, second reply)

| ID | Fix | Check it here |
|---|---|---|
| TF-019 | Fixed upstream. New script `tf-ci-repro.sh [<workflow>] [--job <id>]`. It copies the repository to a temp folder outside it, leaving out everything `.gitignore` ignores (no `bin/`, `obj/`, `node_modules/`), as a fresh checkout has none. It points every package cache it knows at an empty folder: NuGet (`NUGET_PACKAGES` and its HTTP cache), npm, yarn, pnpm, pip, Go, Gradle and Maven. Then it runs the job's `run:` steps in the runner's shell, and a Windows job runs on the Windows side from WSL. It stops at the first failing step and prints `PASS`, `FAIL` (exit 1, with the first error) or `NOT-RUN`. It skips `uses:` steps (the copy stands in for the checkout, and the cache action is left out on purpose), steps that need a secret (your machine's credentials stand in), and steps that only install tools on the machine, such as the MAUI workload (`--run-setup` runs them). Step outputs, `env:` and simple `if:` conditions work, so your Locate test project → Test pair runs. `--list` prints the plan and runs nothing. `triage-issues` now counts a failed CI run as evidence and reproduces it only with this script. `fix-issues` does not call a CI failure fixed until the script prints PASS, and even then the report says your next CI run is the final check. `triage-and-fix` uses both steps. Regression case `lk_019` fails against the framework you had and passes now. | Proved on your repo here. With your workflow as it was before your fix (`dotnet restore Lekhak.slnx`, no `-p:Configuration=Release`), the script printed `FAIL job build: step 7 "Build" failed (exit 1) with empty caches — … error NETSDK1112: The runtime pack for Microsoft.NETCore.App.Runtime.win-x64 was not downloaded`, the same error as CI run 36711733872, in 4 min. With your current workflow it printed `PASS job build: 4 run step(s) passed …` in 6 min 40 s: restore, build, then 855 tests passed. To re-check, run `bash .tfcore/utils/tf-ci-repro.sh --list`, then `bash .tfcore/utils/tf-ci-repro.sh`. Expect PASS. The first run downloads every package, so it takes as long as a cold CI restore. |

### Resolution status (TechieFlow team, 2026-09-30)

| ID | Fix | Check it here |
|---|---|---|
| TF-016 | Fixed upstream. New script `tf-doc-tests.sh <doc>…`. It looks for test files that name a changed document (by file name, or by name without `.md`). When one does, it runs the unit tests and prints `PASS`, or `FAIL` with exit 1. When no test reads the document it prints `NONE` and runs nothing. The status gate now runs it (step 4) on every document the command changed, and so does `*amend-docs` (step 11). A `FAIL` keeps the phase open: put the guarded text back, or, when the change is meant, the report names the test for `*triage-and-fix`, since a document command never edits code. Two limits: the Stop hook does not check this step, and only .NET test projects are run (any other stack prints `NOT-RUN`). Regression case `lk_016` fails against the framework you had and passes now. | `bash .tfcore/utils/tf-doc-tests.sh docs/Lekhak-UsageGuide.md` prints `PASS 3 test file(s) read docs/Lekhak-UsageGuide.md (…AppSecretsTests.cs, …VerificationRuleDocTests.cs, tests/verify/_phase8-db.ts)`, run here in 36 s. `bash .tfcore/utils/tf-doc-tests.sh docs/Lekhak-BRD.md` prints `NONE`. Your next `*amend-docs` runs it by itself. |
| TF-017 | Fixed upstream in `tf-verify-tests.sh`. It now reads `tests/.artifacts/verify/list.json`. When the verify was given a list of ids, Playwright runs only the tests carrying those ids (`--grep`). When no row in scope has a screen and no file under `tests/verify/` names one of the ids, the browser run is skipped and says why. A verify of `ui`, `functional` or `all`, a run with `--spec`, and a run with the new `--all-specs` still run every spec. Regression case `lk_017` fails against the script you had and passes now. | `bash .tfcore/utils/tf-verify-list.sh Lekhak REQ-NFR-042` then `bash .tfcore/utils/tf-verify-tests.sh --base http://localhost:59689` (no `--no-browser`). It prints `browser tests: skipped — no row in scope (REQ-NFR-042) has a screen …` and finishes in about a minute and a half (1 m 19 s here), with REQ-NFR-042 PASS. You no longer need `--no-browser` for such a scope. |
| TF-018 | Fixed upstream in `tf-verify-tests.sh`. A passing unit test now has an empty reason. A skipped one keeps "unit test skipped: …" and a failed one keeps "unit test failed: …". Regression case `lk_018` fails against the script you had, with your exact text, and passes now. | In the same run's `tests/.artifacts/verify/tests.json`, `reqs["REQ-NFR-042"].outcomes` reads `{"outcome": "pass", "reason": ""}`. |

### Resolution status (TechieFlow team, 2026-09-29, third reply)

| ID | Fix | Check it here |
|---|---|---|
| TF-015 | Fixed upstream in `tf-render-html`. A relative link to a `.md` file is now written as `.html` in two cases: when that page's HTML is already next to the page being rendered, or when the same render run writes it. An `#anchor` on the link is kept. Other links stay exactly as written: a link to a markdown file that has no HTML copy (an agent document, the checklist, a feedback file), a web link, and a link that is only an `#anchor`. The rule is also written into the renderer's spec, `html-render-shell.md`. Regression case `lk_015` fails 3 of 3 against the script you had and passes now. On a copy of your `docs/productguides/`, all six index links came out as `.html`. | Render the index and its pages in one run: `bash .tfcore/utils/tf-render-html.sh docs/productguides/*.md`. In `Lekhak-ProductGuide.html` the Admin, Author, Editor and Reader links end in `.html`. Do the same for `docs/devguides/*.md`. You no longer need to fix the hrefs by hand after a render. |

### Resolution status (TechieFlow team, 2026-09-29, second reply)

| ID | Fix | Check it here |
|---|---|---|
| TF-014 | Fixed upstream, with three changes to `tf-devguide-list.py`. It no longer goes into hidden folders such as `.tfbuild`, `.vs` or `.playwright`, which hold tool output and never a page. It strips only a leading `./` from a path, so a hidden folder keeps its dot. With `--update`, it counts changed files under `source/` as well as `src/`: Lekhak's code is in `source/`, so before the fix `--update` would have reported no changes even without the crash. There is one more thing you would have hit next. Your guide is five files in `docs/devguides/`, one per role, written before the framework's layout. The framework's `*devguide` keeps one file, `docs/Lekhak-DevGuide.md`, with a "Verified on" row, so `--update` finds no guide there. It now names the five files it found and says to carry their entries over rather than start from nothing. Regression case `lk_014` fails 3 of 3 against the script you had and passes now. | `bash .tfcore/utils/tf-devguide-list.sh Lekhak --update` exits 0 and prints the work list (65 routes, 41 UIDesign screens). Its `--update` part names the five files in `docs/devguides/`. The next `*devguide Lekhak --update` carries them into `docs/Lekhak-DevGuide.md`. Hand-writing the entries is no longer needed. |

### Resolution status (TechieFlow team, 2026-09-29)

| ID | Fix | Check it here |
|---|---|---|
| TF-013 | Fixed upstream. The theme switch from TF-010 now also carries a light or dark class on `<html>` and `<body>`: `dark`, `light`, and names like `theme-dark` or `dark-mode`. A utility class such as `bg-light` is not touched. When the mockup declares a theme, the app's own mode classes are replaced by the mockup's for the comparison. The AI Setup mockup has no mode class, so BlogAdmin's `class="dark"` is taken off. Afterwards the app gets its own classes back, so BlogAdmin is still dark when the check ends. A mockup that declares no theme at all still leaves the app as it is. Regression case `lk_013` fails against the script you had, with your finding ("semantic colour differs — mockup accent"), and passes now. | With BlogAdmin on its saved minimal dark theme and no workaround, run the repro. AI Setup reads PASS with no `color reembed-note — mockup neutral, app accent` at 1280 or 390, and `<html>` still has `class="dark"` afterwards. The `techieblog-theme` / `techieblog-dark-mode` workaround can go. |

### Resolution status (TechieFlow team, 2026-09-28, fourth reply)

| ID | Fix | Check it here |
|---|---|---|
| TF-012 | Fixed upstream, on both sides. `tf-verify-verdict.sh` now writes a test's own words, its title or its failure message, into the Remark in backticks, so they read as a quote. `tf-doc-check.sh` no longer applies its "not present" rule to backtick-quoted text. The rule still holds for anything written outside backticks: a Remark saying "model file not found" with no path still fails. | After your next `*verify`, the REQ-UI-133 Remark reads ``test `REQ-UI-133 AI Setup embedding card shows Found/Not found …` `` and `bash .tfcore/utils/tf-doc-check.sh docs/Lekhak-Checklist.md` passes it. No more rewording by hand. |

### Resolution status (TechieFlow team, 2026-09-28, third reply)

| ID | Fix | Check it here |
|---|---|---|
| TF-010 | Fixed upstream. Before comparing, `tf-mockup-parity` reads the theme the mockup declares: the `data-*` attributes on `<html>` and `<body>` whose name contains theme, mode or scheme (here `data-site-theme="fluent-modern"` and `data-theme="light"`). It sets them on the app page, compares, then puts the app's own values back. An attached BlogAdmin is left in the viewer's saved theme. When the themes differed, the JSON records both under `widths[].theme`. `--keep-app-theme` compares the theme the app is showing, if you ever want that. | Run the repro with BlogAdmin on the saved `minimal` dark theme. The "mockup accent, app neutral" findings on buttons and links are gone, and the app is still dark afterwards. The localStorage workaround can go. |
| TF-011 | Fixed upstream. The mockup check now leaves out any box marked as another state, before the boxes around it are numbered. Both marks count: your `data-state-testid="<id>"` and the framework's `data-tf-state="<state>"`. The screen check also accepts `data-state-testid` as a state-only mark now. | The Connection settings repro no longer reports `conn-card > div[1] > div[0] border style differs`, so that false positive can come out of the row's Remarks. |

### Resolution status (TechieFlow team, 2026-09-28, second reply)

| ID | Fix | Check it here |
|---|---|---|
| TF-009 | No change needed; the TF-001 fix works on Lekhak. The failure quoted (`boot-59689.json`, started 2026-09-28T11:23:19Z) came from the script as it was before the fix reached this repository, about 11:45 UTC. The boot run here at 12:45 UTC with the current script started Lekhak on `http://localhost:59689`, with "Hosting environment: Development" in its log. The running process had `ASPNETCORE_ENVIRONMENT=Development` and `APPDATA=/mnt/c/Users/srkra/AppData/Roaming`, and there was no missing-secret error. The guess in the entry is also off: the published copy has run in Development by default since before TF-001, reading the launch profile, so the only missing piece was the secrets store, which TF-001 added. | `tests/.artifacts/verify/boot-59689.json` reads `"mode": "base"`, and `app-59689.log` says "Now listening on: http://localhost:59689". Close TF-009 and TF-001 once your next `*verify` boots the same way, and drop `run-web-verify.cmd`. |

### Resolution status (TechieFlow team, 2026-09-28)

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream. The web head did start in Development; the cause was the side it ran on. The copy ran on the WSL side, which looks for user-secrets in `~/.microsoft/usersecrets`, while `dotnet user-secrets set` on Windows writes them to `%APPDATA%\Microsoft\UserSecrets` (Lekhak's are there, under `lekhak-web-4f2b8c1e`). When only the Windows store holds the project's secrets, the boot now points the app at that store and prints one line saying so. New `--environment <Name>` sets the environment when you need another one. | `bash .tfcore/utils/tf-verify-boot.sh start --head web` boots Lekhak with no exported secrets and prints "user-secrets lekhak-web-4f2b8c1e are in the Windows store only". The `run-web-verify.cmd` workaround can go. |
| TF-002 | Fixed upstream. The screen check now accepts a development certificate, as the mockup and asset checks already did. The same change covers the redirect from plain HTTP to HTTPS. | `tf-verify-screens.sh --base https://…:<port>` grades the screens instead of reporting `UNREACHABLE`. |
| TF-004 | Fixed upstream. The weekly clean-up now keeps any file under `tests/.artifacts/` that a file under `tests/` names by path (for example `tests/.artifacts/harness/hindi-src`), at any age, and says how many it kept. Output folders are still cleaned: the framework's own, and any folder a test only writes into with a built-up name such as `` `shots/${name}.png` ``. On Lekhak it now keeps `hindi-src`, `run-blogadmin.cmd`, `cdp-relay.cjs` and `serials-seed.mjs`. The last three would have been deleted on 2026-10-03. `tests/verify/fixtures/` is still the right home for a fixture. | On the next session start, the clean-up line ends "kept N old file(s) a test names by path" whenever it keeps something. |
| TF-005 | Fixed upstream. `--route-value ProviderId=21` (repeatable), or `"route_values": {"ProviderId": 21}` in the list (for the whole list or for one screen), fills `/admin/llm-signin/{ProviderId:long}`. A screen whose route still needs a value is not opened: it prints `SKIP … pass --route-value ProviderId=<a real ProviderId>`, and its rows read "not driven: its route needs --route-value". A mockup can now mark a control that only shows in another state with `data-tf-state="<state>"`, on the control or on a box around it. Such a control is not required on the first view, and is graded when the page shows it. | Add `data-tf-state="database down"` around `conn-reason` and `data-tf-state="after Test"` on `conn-result` in the Connection settings mockup (that mockup is the owner's, so ask first). Connection settings then grades OK on its first view. |
| TF-006 | Fixed upstream. `tf-assets.sh --cdp <url>` and `tf-mockup-parity.sh --cdp <url>` attach to a running desktop head the way `tf-verify-screens.sh --cdp` does, and open each screen through the app's own router. The asset check fetches each declared stylesheet and script from inside the app, because nothing outside the embedded browser can reach them. The app is left running when the check ends. | `bash .tfcore/utils/tf-assets.sh --cdp http://172.18.144.1:9334 --paths /admin/ai-setup` and `bash .tfcore/utils/tf-mockup-parity.sh --cdp http://172.18.144.1:9334 --screen ai-setup=/admin/ai-setup` grade the 11 desktop screens. |
| TF-007 | Fixed upstream. Every test result now records each test's own outcome and when it ran. `--merge` reads the parts oldest first, and a later run of the same test replaces the earlier one. A later skip never replaces a run that happened, and a failure nothing re-ran stays. `docs/.last-verify.json` is now updated row by row: a targeted verify replaces only its own rows and keeps the rest, each with the date and run it was graded in. A full (`all`) verify still starts it afresh. A `Verified` is still unlocked only by a row graded today. | Re-run the failed test after starting its service, then `--merge tests-3of4.json tests-rerun.json`. The row reads PASS, and the merge line says "1 test(s) ran again in a later part, and the later run stands". After a targeted `*verify`, the ledger still holds all 395 rows. |

TF-003 stays open. A Mac Catalyst driver has to be built and proved on a Mac, and this pass ran on the Windows machine. The steps in your workaround (open the app by `appium:appPath`, set `AXEnhancedUserInterface`, type with `macos: keys`, take element screenshots) are the plan for it. On picking the head: `tf-verify-boot.sh` takes the head it is given, so when the owner asks for the Mac head, the agent has to pass `--head maccatalyst`. The script then says plainly that no driver ships yet, and the rows read "not verified".

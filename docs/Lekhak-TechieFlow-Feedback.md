# TechieFlow feedback — found while building Lekhak

| | |
|---|---|
| App | Lekhak |
| Upstream | TechieFlow |
| Updated | 2026-09-28 |

## Summary

12 entries: 0 blocking now, 2 open and not blocking (TF-003, TF-008), 3 fixed upstream and not yet re-checked here (TF-010, TF-011, TF-012), 7 closed after a re-check here on 2026-09-28 (TF-001, TF-002, TF-004, TF-005, TF-006, TF-007, TF-009).

Nothing is blocked.

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

## Replies from TechieFlow

<!-- The upstream team's answers, newest block first. Left in full: this is the record. -->

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

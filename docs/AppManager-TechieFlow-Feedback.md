# TechieFlow feedback — found while building AppManager

| | |
|---|---|
| App | AppManager |
| Upstream | TechieFlow |
| Updated | 2026-09-16 |

## Summary

16 entries: 0 blocking now, 0 open, 1 fixed upstream and waiting to be re-checked here (TF-016, fixed 2026-09-16), 15 closed here after a re-check: TF-001 to TF-006 on 2026-09-13, TF-007 to TF-014 on 2026-09-14, TF-015 on 2026-09-16.

Nothing is blocked. Once TF-016 is re-checked, a verify of a UI row here drives its page from the checklist's Page heading, so the row is credited with every check that ran on it.

## Entries

### TF-001 — `tf-split-brd.sh --add-missing` re-appended a row for every BRD item, not just the new ones, and emitted stray markup

> ✅ **Closed 2026-09-13** — re-checked here: Copied docs/AppManager-Checklist.md aside and ran tf-split-brd.sh AppManager --add-missing: it printed 'every BRD item already has a row; nothing to add', exit 0, and diff against the copy showed no change.

- **Severity:** major
- **Blocks:** no — the 88 bad rows were removed by hand and the 12 genuine rows were written manually; the amendment completed.
- **Repro:** `bash .tfcore/utils/tf-split-brd.sh AppManager --add-missing` on a checklist whose rows were migrated from a pre-existing dev plan (so REQ rows carry no `BRD-N` back-reference in the expected form), after appending BRD-81…BRD-88 to the BRD.
- **Expected:** rows appended for the 8 new BRD items only.
- **Actual:** 88 rows appended — one for BRD-1…BRD-88 — duplicating every already-tracked requirement as `REQ-FN-043`…`REQ-FN-123`, `REQ-UI-025`…`REQ-UI-031`. It also wrote a literal `</content>` / `</invoke>` / `## Page: Other` block into the middle of the detail section.
- **Encountered in:** `*amend-docs AppManager` step 7.
- **Workaround:** deleted the appended status rows and detail blocks, then hand-wrote the 12 correct rows.
- **Suggested fix:** two things. (1) Before appending, resolve existing coverage by reading the detail entries' `(BRD-N)` / `*(BRD-N)*` markers as well as the status table, and skip any BRD item already covered — a checklist migrated from an older plan is the normal brownfield case, not an edge case. (2) The `</content></invoke>` / `## Page: Other` emission looks like an unescaped template fragment leaking into output; it should never reach a project file.

#### Detail

The damage is silent and large: without a careful read of the script's own summary line, 88 duplicate requirements would have entered the single source of truth and the next verifier pass would have graded them. Recovering needed a line-range delete, which is only safe because the appended block happened to be contiguous.

### TF-002 — `tf-doc-check.py` truncates a checklist entry when a `### ` heading sits between its anchor and its content

> ✅ **Closed 2026-09-13** — re-checked here: Ran tf-doc-check.sh docs/AppManager-Checklist.md: REQ-UI-001 to 009, whose Page heading sits under the anchor, are now read (their acceptance lines are graded for wording, no 'found 0'). The 'found 0' lines left for REQ-UI-010 to 019 are real: those entries have no acceptance line. BRD-73 is no longer reported as unmapped.

- **Severity:** major
- **Blocks:** no — the three new UI entries were rewritten with the heading above the anchor and now pass; 24 pre-existing entries were left in their original shape.
- **Repro:** any checklist entry written as `<a id="d-req-ui-025"></a>` then `### Page: …` then the `- **REQ-UI-025**` list item.
- **Expected:** the entry is read, so its acceptance line, BRD reference and mockup link are all found.
- **Actual:** three false failures per entry — "must have exactly one acceptance line; found 0", "detail entry does not name its BRD-N item", "is a UI row without a mockup link".
- **Encountered in:** `*amend-docs AppManager` step 11, REQ-UI-025 / 026 / 027.
- **Workaround:** move the `### Page:` heading above the anchor.
- **Suggested fix:** at `tf-doc-check.py:1041`, the entry is sliced from the anchor to the next match of `\n\s*(?:[-*]\s*)?<a id=|\n## |\n### `. Stop at the next **anchor or `##`** only, or skip a `###` on the line immediately after the anchor.

#### Detail

The effect is silent under-checking, which is worse than a false alarm: 24 pre-existing `REQ-UI-*` entries in this checklist have never been validated, and `BRD-73` has shown as unmapped since before this session for exactly this reason. Every `REQ-FN-*` entry passes because none of them carries a `### ` heading.

### TF-003 — `tf-build-list.sh` puts `Done (pre-existing)` rows on the working list, then refuses them for having no acceptance line

> ✅ **Closed 2026-09-13** — re-checked here: Ran tf-build-list.sh AppManager: 14 rows to build, 73 terminal, no 'Done (pre-existing)' row in the working list, 2 'no acceptance line' warnings. tf-brd-status.sh AppManager wrote the BRD table as 73 of 87 done.

- **Severity:** major
- **Blocks:** no — the 18 affected rows were recognised as terminal from the checklist legend and left alone; the genuine open rows were built.
- **Repro:** `bash .tfcore/utils/tf-build-list.sh AppManager --prompts` on a checklist carrying rows at status `Done (pre-existing)`.
- **Expected:** 28 open rows on the working list. `Done (pre-existing)` is terminal — the checklist's own legend says so in as many words: "migrated from an earlier dev plan as already complete — build agents must NOT rebuild; terminal like `Verified`".
- **Actual:** 54 rows, including all 18 `Done (pre-existing)` rows, each rendered as `— done  ⚠ no acceptance line: fix the checklist first`. The header counted only 33 terminal, so `Verified` is recognised as terminal and `Done (pre-existing)` is not.
- **Encountered in:** `*build-phase AppManager` step 1.
- **Workaround:** built the genuinely open rows only, and did not add acceptance lines to terminal rows purely to silence the warning.
- **Suggested fix:** add `Done (pre-existing)` to the terminal-status set in `tf-build-list.sh` alongside `Verified` and `N/A`. The two failure modes compound: because build-phase step 1 says "a row without an acceptance line is refused: fix the checklist first", the literal reading of the tool's output is to go and write acceptance criteria for 18 requirements that shipped before this checklist existed, or to rebuild them.

#### Detail

The pressure this creates points the wrong way. An agent following build-phase step 1 to the letter either rebuilds 18 completed requirements or edits 18 terminal rows to quiet a warning — both of which churn a source of truth that was correct. The status legend and the build list disagree about what `Done (pre-existing)` means, and only the legend is right.

### TF-004 — `tf-verify-boot.sh` cannot start a Web API: its readiness probe demands 2xx/3xx from `/`, and it kills the app that is already up

> ✅ **Closed 2026-09-13** — re-checked here: Ran tf-verify-boot.sh start --project src/AppManagerApi/AppManagerApi.csproj --port 5100: BOOTED on rung 2 (WSL dotnet) from its own copy; / answered 404 and /healthz 200. AppManagerWeb also booted the same way on 5099 with no Windows-path startup crash. Both stopped cleanly.

- **Severity:** major
- **Blocks:** no — worked around with a run-local Playwright `webServer` config pointing at the health endpoint that does exist.
- **Repro:** `bash .tfcore/utils/tf-verify-boot.sh start --head web --project src/AppManagerApi/AppManagerApi.csproj --port 5100` against any ASP.NET Core Web API with no route at `/`.
- **Expected:** BOOTED, since the app starts correctly and serves `/healthz`.
- **Actual:** `NONE head=web kind=host reason=no rung brought … up on http://localhost:5100 within 120 s`. The app log for the same run shows the opposite: `Now listening on: http://localhost:5100` / `Application started`. `poll_http` (line 71) accepts only `^[23]`, and the probe URL is the bare base URL, so a pure API answers 404 for the full 120 s and is then killed.
- **Encountered in:** `*build-phase AppManager`, re-checking TfLens AM-001/AM-002 against the rewritten `AuthSvcController`.
- **Workaround:** a Playwright `webServer` block with `url: http://localhost:5100/healthz`.
- **Suggested fix:** add a `--probe-path` option (default `/`) and treat **any** HTTP response, including 404, as "the port is serving" — a 404 from the framework is proof the host is up, which is exactly what this check is for. A `--probe-path /healthz` would have made this a one-line invocation.

#### Detail

Two things make this worse than a wrong verdict. First, the reason string blames the rungs — "no rung brought it up" — when every rung brought it up and the probe was wrong; an agent reading that goes off to debug the build ladder. Second, the script then **stops the working process**, so the next command finds nothing listening and the evidence of the successful start survives only in `tests/.artifacts/verify/app-5100.log`.

A second, smaller trap sits behind it: on WSL the `cmd.exe` rung binds Windows-side `localhost`, which WSL cannot reach, so even a correct probe fails for that rung. Non-MAUI projects must run on rung 2 (`~/.dotnet/dotnet`). Worth encoding in the script rather than leaving to each caller.

A third, hit independently by another builder in the same pass, makes the WSL rung fail too: **Windows and WSL builds share `bin/`**, so a static-web-assets manifest generated Windows-side carries `C:\…` paths, and the Linux host then dies at startup with `The path must be absolute (Parameter 'root')`. The workaround is `-t:Rebuild` on the WSL dotnet before running, or launching the prebuilt DLL directly. Between them the two traps mean that on WSL *neither* rung starts a web app reliably in a repo that has been built from both sides — which is the normal state of this repo, since the MAUI head must build Windows-side. A `--rebuild` or separate per-side output paths would close it.

### TF-005 — `tf-verify-tests.sh` can never map a unit test to a row when the test project runs on Microsoft.Testing.Platform

> ✅ **Closed 2026-09-13** — re-checked here: Ran tf-verify-tests.sh --no-browser --target tests/unit/AppManager.UnitTests/AppManager.UnitTests.csproj: unit tests PASS on rung 2, one TRX report read, REQ-NFR-007 mapped as PASS in tests.json, no ./Detailed folder. The bare command without --target skipped the unit tests because it did not find the test project; that is a separate problem, filed as TF-007.

- **Severity:** major
- **Blocks:** no — REQ-NFR-007 is graded through a browser-side spec that runs the unit test project and reads its summary line.
- **Repro:** `bash .tfcore/utils/tf-verify-tests.sh` on a repo whose test project uses xunit.v3 with `TestingPlatformDotnetTestSupport=true` (AppManager: 286 tests), with one test declared as `[Fact(DisplayName = "REQ-NFR-007 …")]`.
- **Expected:** the row picks up that test's result.
- **Actual:** the console shows only `Passed! - Failed: 0, Passed: 286, Skipped: 0, Total: 286`. The `--logger "console;verbosity=normal"` argument the script passes is ignored on this platform, so no `Passed <name>` line exists and the parser maps nothing. Per-test lines do exist, but only in `TestResults/<assembly>_<tfm>_<arch>.log`, only for failed tests, and in lower case (`failed REQ-NFR-007 … (133ms)`), which the case-sensitive regex would miss anyway.
- **Encountered in:** `*verify all AppManager`, step 4.
- **Workaround:** `tests/verify/req-nfr-007-unit-tests.spec.ts` runs `dotnet test` on the project and asserts zero failures.
- **Suggested fix:** for a Testing Platform project, ask for a TRX report (xunit.v3 offers `--report-xunit-trx`) and map from each result's test name and outcome, matching outcomes case-insensitively.

#### Detail

A trap sits next to it: `--output Detailed`, the platform's own verbosity switch, is read by `dotnet test` as the build output folder, so it silently builds the whole test project into `./Detailed/` at the repo root. Any test that locates its sources relative to its binaries then fails for a reason unrelated to the code.

### TF-006 — `tf-verify-screens.sh` reads every signed-in screen of a Blazor Server app with in-circuit authentication as unreachable

> ✅ **Closed 2026-09-13** — re-checked here: Booted AppManagerWeb on 5099 and ran tf-verify-screens.sh --base http://localhost:5099 --screen user-devices='/users/66?tab=devices' --login-path /login with the usage guide's admin: render OK and visual OK at 1280 and 390, 0 unreachable; screens.json records reached = 'answered HTTP 401, then drew the screen signed in' at both widths, and the 1280 screenshot shows the signed-in User Details page on its Devices tab.

- **Severity:** major
- **Blocks:** no — this checklist ties no row to a screen, so no verdict depends on the tool; the Playwright acceptance tests drive the same screens signed in.
- **Repro:** `bash .tfcore/utils/tf-verify-screens.sh --base http://localhost:5099 --screen user-devices='/users/66?tab=devices' --login-path /login --user admin@appmanager.local --password '…'` against AppManagerWeb.
- **Expected:** the screen is signed in, rendered and graded at 1280 and 390.
- **Actual:** `render UNREACHABLE … answered HTTP 401` on all three screens tried. In a browser that has just signed in, the document for a protected route still answers 401 and then renders fully once the circuit attaches. The session lives in the circuit, so there is no auth cookie for `--cookie` and nothing in local storage for `--storage-state` (a saved state holds only the antiforgery cookie, and a fresh context loaded from it lands on `/login`).
- **Encountered in:** `*verify all AppManager`, step 5, while driving the three screens that have mockups.
- **Workaround:** none for the tool; render and layout of those screens are covered only by the acceptance tests.
- **Suggested fix:** sign in and drive every screen inside one browser context (in-app navigation after the login, not a fresh document load per screen), and judge reachability by what renders rather than by the first document's status code.

### TF-007 — `tf-verify-tests.sh` finds no test project when the solution is `.slnx` only and the tests sit two folders under `tests/`

> ✅ **Closed 2026-09-14** — re-checked here: Ran bash .tfcore/utils/tf-verify-tests.sh --no-browser with no --target: unit tests PASS on rung 1 (cmd.exe /c dotnet), one TRX report read from tests/unit/AppManager.UnitTests, REQ-NFR-007 mapped as PASS (source unit, 1 passed, 0 failed) in tests/.artifacts/verify/tests.json. The .slnx-only root and the two-deep test project are now found.

- **Severity:** minor
- **Blocks:** no — passing `--target tests/unit/AppManager.UnitTests/AppManager.UnitTests.csproj` ran the unit tests and mapped REQ-NFR-007; the re-check of TF-005 carried on.
- **Repro:** `bash .tfcore/utils/tf-verify-tests.sh --no-browser` in AppManager, whose root holds `AppManager.slnx` and no `.sln`, with the test project at `tests/unit/AppManager.UnitTests/`.
- **Expected:** the unit tests run, as the TF-005 reply's "Verify from here" line says they will.
- **Actual:** `unit tests: no solution or test project found; skipped`, then `rows with a test: 0`, exit 2.
- **Encountered in:** re-checking TF-005.
- **Workaround:** name the test project with `--target`.
- **Suggested fix:** at `tf-verify-tests.sh:53`, `ls *.sln *.slnx` fails whenever either pattern matches nothing, and `tests/*/*.csproj` looks only one folder deep. Test each pattern on its own (for example `compgen -G '*.sln' || compgen -G '*.slnx'`) and look for a `.csproj` at any depth under `tests/`.

### TF-008 — `tf-build-list.sh` sends UI rows to the `trblazeui` sub-agent in a project that does not use that library

> ✅ **Closed 2026-09-14** — re-checked here: Ran bash .tfcore/utils/tf-build-list.sh AppManager: printed 'UI rows go to: builder — none of the 7 .csproj/.props file(s) references TrBlazeUI', then 'Cluster A [builder]: REQ-UI-001, REQ-UI-003, REQ-UI-006, REQ-UI-007, REQ-UI-022, REQ-UI-024 (UI / Pages)'. No cluster is labelled trblazeui.

- **Severity:** minor
- **Blocks:** no — the list of rows is correct; UI rows here are built by flow-master, as AGENTS.md says, whatever the label.
- **Repro:** `bash .tfcore/utils/tf-build-list.sh AppManager`
- **Expected:** the UI cluster labelled `[builder]`, because this project does not use TrBlazeUI (AGENTS.md, "Project basics").
- **Actual:** `Cluster A [trblazeui]: REQ-UI-001, REQ-UI-003, REQ-UI-006, REQ-UI-007, REQ-UI-022, REQ-UI-024  (UI / Pages)`.
- **Encountered in:** re-checking TF-003.
- **Workaround:** none needed yet; the next `*build-phase` must route that cluster to flow-master and ignore the label.
- **Suggested fix:** label a UI cluster `trblazeui` only when the project references TrBlazeUI (a package or project reference, or a setting in `core-config.yaml`); otherwise label it `builder`.

### TF-009 — `tf-verify-list.py` finds no test users when the guide is named `{App}-Usage-Guide.md`

> ✅ **Closed 2026-09-14** — re-checked here: Ran tf-verify-list.sh AppManager all: under Test users (UsageGuide) it listed admin@appmanager.local — Admin and appmanager-yolo-tester@appmanager.local — Manager, read from docs/AppManager-Usage-Guide.md.

- **Severity:** minor
- **Blocks:** no — the two test users are in the guide and were used by hand; the verify run carried on.
- **Repro:** `bash .tfcore/utils/tf-verify-list.sh AppManager all` in AppManager, whose guide is `docs/AppManager-Usage-Guide.md` with a `### Test users` table.
- **Expected:** the Admin and Manager test users listed under "Test users (UsageGuide)".
- **Actual:** `- none in the UsageGuide: the smoke policy says what to do`.
- **Encountered in:** `*build-phase AppManager`, chained verify, step 1.
- **Workaround:** read the users from the guide directly.
- **Suggested fix:** at `tf-verify-list.py:191` (and `tf-devguide-list.py:67`) try `{app}-UsageGuide.md` then `{app}-Usage-Guide.md`, the two spellings `tf-doc-check.py` already accepts. The heading pattern at line 138 also needs `#{2,3}`, since this guide nests Test users one level down.

### TF-010 — `tf-verify-boot.sh start --head web` boots the external API instead of the admin site

> ✅ **Closed 2026-09-14** — re-checked here: Ran tf-verify-boot.sh start --dry-run: printed '2 web projects; src/AppManagerWeb/AppManagerWeb.csproj serves screens … booting it' and 'PICK head=web project=src/AppManagerWeb/AppManagerWeb.csproj'. Then tf-verify-boot.sh start with no --project printed the same choice and BOOTED the admin site at http://localhost:5041 from its copy.

- **Severity:** minor
- **Blocks:** no — `--project src/AppManagerWeb/AppManagerWeb.csproj` booted the admin site; the verify run carried on.
- **Repro:** `bash .tfcore/utils/tf-verify-boot.sh start --head web` in AppManager, which has two `Microsoft.NET.Sdk.Web` projects: `AppManagerApi` and `AppManagerWeb`.
- **Expected:** the project that serves the screens (the one referencing the Razor component library), or `NONE` asking for `--project`, because there are several.
- **Actual:** `BOOTED head=web … project=src/AppManagerApi/AppManagerApi.csproj` — the first match in sorted order, which has no screens.
- **Encountered in:** `*build-phase AppManager`, chained verify, step 3.
- **Workaround:** always pass `--project`.
- **Suggested fix:** in the project search around `tf-verify-boot.sh:67`, when more than one web project is found, prefer one that references a `Microsoft.NET.Sdk.Razor` project or has `Components/`/`Pages/` with `.razor` files; otherwise stop with `NONE` naming the candidates.

### TF-011 — `tf-assets.sh` and `tf-mockup-parity.sh` cannot get past a Blazor Server sign-in that sets no cookie

> ✅ **Closed 2026-09-14** — re-checked here: Booted the admin site with tf-verify-boot.sh start and ran tf-assets.sh --base http://localhost:5041 --paths /dashboard,/reports/device-adoption --login-path /login --user admin@appmanager.local: status measured, 11 assets declared and graded on each path, 0 failed, each reached 'answered HTTP 401, then drew the screen signed in'. tf-mockup-parity.sh --screen device-adoption-report=/reports/device-adoption with the same sign-in: no HTTP 401 error, reached at 1280 and 390. Its FAIL verdict is the mockup's missing data-testid anchors (19 named, repaired here through *amend-docs) and a document-scroll finding filed as TF-014.

- **Severity:** minor
- **Blocks:** no — the assets and mockup checks are recorded as not measured; every other check ran.
- **Repro:** `bash .tfcore/utils/tf-assets.sh --base http://localhost:5041 --paths "/dashboard,/reports/device-adoption" --json-out tests/.artifacts/verify/assets.json`, and `bash .tfcore/utils/tf-mockup-parity.sh --base http://localhost:5041 --screen device-adoption-report=/reports/device-adoption`, in AppManager, whose admin site signs in inside the live page connection and sets no auth cookie.
- **Expected:** a way to sign in, as `tf-verify-screens.sh` does with `--login-path --user --password` or `--storage-state`.
- **Actual:** every path answers `401`; assets `declared 0 graded 0`; parity `app returned HTTP 401` at both widths. Both tools take only `--cookie`, and this app has no cookie to give.
- **Encountered in:** `*build-phase AppManager`, chained verify, step 5.
- **Workaround:** none; the two checks are left as not measured.
- **Suggested fix:** give both tools the same `--login-path/--user/--password` and `--storage-state` options `tf-verify-screens.sh` has (the TF-006 fix), and drive the page through the browser rather than a bare HTTP request.

### TF-012 — `tf-verify-screens.sh` reports a signed-in form with a password field as unreachable

> ✅ **Closed 2026-09-14** — re-checked here: Booted the admin site with tf-verify-boot.sh start and ran tf-verify-screens.sh --base http://localhost:5041 --login-path /login --user admin@appmanager.local --screen user-create=/users/create: render OK and visual OK at 1280 and 390, reached 'answered HTTP 401, then drew the screen signed in'.

- **Severity:** minor
- **Blocks:** no — the screenshot the tool itself saved shows the form rendered correctly; the row was graded on its test.
- **Repro:** `bash .tfcore/utils/tf-verify-screens.sh --base http://localhost:5041 --login-path /login --user admin@appmanager.local --password '…' --screen user-create=/users/create`.
- **Expected:** `render OK` — the page is the signed-in "Create User" form, with a Password field for the new account.
- **Actual:** `FAIL user-create (/users/create) — render UNREACHABLE … answered HTTP 401`, while `tests/.artifacts/verify/screens/user-create-390.png` shows the full form.
- **Encountered in:** `*build-phase AppManager`, chained verify, step 5.
- **Workaround:** read the saved screenshot and grade the row on its test.
- **Suggested fix:** decide "this is the sign-in page" from the URL having returned to `--login-path`, not from a password input being present.

### TF-013 — `tf-verify-tests.sh` runs the whole browser suite in one command, which the foreground limit cannot hold

> ✅ **Closed 2026-09-14** — re-checked here: Ran tf-verify-tests.sh --base http://localhost:5041 --shard 1/4 to 4/4 against the admin site: each wrote its own playwright-NofM.json and tests-NofM.json. --no-browser --json-out tests-unit.json ran the unit tests (PASS, 12 rows). --merge of those five files wrote one tests.json with merged_from naming all five, 51 rows (the union of the parts), browser totals adding to 134 tests, unit totals carried, every FAIL kept with its reason. Two notes for TechieFlow: shards 2 to 4 each ran past ten minutes, so 1/4 is too coarse for this suite in one foreground command; and the line's literal glob tests-*.json also swept in two older files from the TF-007 re-check (tests-tf007.json, tests-tf007-deployed.json), while a --no-browser run left at its default writes tests.json, which the glob misses. The 6 FAIL rows are email tests that found no captured mail, because the site was booted with a plain start and no test mail settings.

- **Severity:** minor
- **Blocks:** no — the suite was run in groups through `PW_FILES`, one results file per group, merged by row before the verdict.
- **Repro:** `bash .tfcore/utils/tf-verify-tests.sh --base <url>` in AppManager (34 spec files; one keyboard test alone may run past ten minutes). The YOLO guard refuses a background run, and a foreground command is stopped at ten minutes.
- **Expected:** a way to run the suite in parts and have `tests.json` cover them all.
- **Actual:** no shard or file option; every run overwrites `playwright.json` and `tests.json`, and `--no-browser` deletes `playwright.json`, so parts cannot be combined through the script.
- **Encountered in:** `*build-phase AppManager`, chained verify, step 5.
- **Workaround:** set `PW_FILES` per group, write each to its own `--json-out`, and merge the `reqs` maps (FAIL wins, counts add).
- **Suggested fix:** add `--shard N/M` (passed to Playwright) and `--merge <tests-*.json…>` that combines `reqs` and the `browser`/`unit` totals into `tests.json`.

### TF-014 — `tf-mockup-parity.sh` reports "escaped the app shell's scroll container" on an app whose document is meant to scroll

> ✅ **Closed 2026-09-14** — re-checked here: Booted the admin site with tf-verify-boot.sh start (it picked src/AppManagerWeb/AppManagerWeb.csproj) and ran tf-mockup-parity.sh --base http://localhost:5041 --screen device-adoption-report=/reports/device-adoption --login-path /login --user admin@appmanager.local: reached the screen signed in at 1280 and 390, findings 0, no document-scroll finding at either width. Verdict UNGRADEABLE only because the mockup has no data-testid anchors (19 named in anchor_deficit), repaired here through *amend-docs.

- **Severity:** minor
- **Blocks:** no — the finding was judged against the app's own layout and set aside; the comparison is ungradeable anyway until the mockup carries anchors.
- **Repro:** `bash .tfcore/utils/tf-mockup-parity.sh --base http://localhost:5041 --screen device-adoption-report=/reports/device-adoption --login-path /login --user admin@appmanager.local --password '…'` in AppManager.
- **Expected:** no scroll finding, because this app has no content scroll container: the page body scrolls, and only the side menu scrolls inside itself.
- **Actual:** `document-scroll` — "document.scrollHeight 6600 exceeds clientHeight 800 — the page has escaped the app shell's scroll container" at 1280, and 9701 against 844 at 390.
- **Encountered in:** re-checking TF-011.
- **Workaround:** measured five signed-in pages at 1280×800 in a browser. On every one `body` has `overflow-y: auto`, the document is the scroller, and the only inner scroll area is `div.main-sidebar`. Document heights: `/dashboard` 2375, `/applications` 1066, `/users` 978, `/reports` 1588, `/reports/device-adoption` 6600. The adoption report is long because it lists every application, not because it broke out of a container.
- **Suggested fix:** raise `document-scroll` only when the shell actually has a content scroll container (an element around the page body with `overflow-y: auto|scroll` and a fixed height) and the document scrolls as well. Where the document is the app's only scroller, say nothing, or compare against the same measure on a sibling screen of the same shell.

### TF-015 — `tf-mockup-parity.sh` reports a one-line padded badge as wrapping to two rows

> ✅ **Closed 2026-09-16** — re-checked here: Re-checked here on 2026-09-16: booted the admin site with tf-verify-boot.sh start (src/AppManagerWeb, port 5041) and ran tf-mockup-parity.sh --base http://localhost:5041 --screen device-adoption-report=/reports/device-adoption --login-path /login --user admin@appmanager.local. Verdict PASS at 1280 and 390, findings 0, anchor_deficit 0 — the wrap finding on adoption-status-badge > span[0] is gone at both widths. Evidence tests/.artifacts/verify/parity.json. REQ-UI-027 returned to Verified in the same run.

- **Severity:** minor
- **Blocks:** no — the screen was measured by hand and is correct; only REQ-UI-027's return to `Verified` waits, because its mockup check would fail on this finding alone.
- **Repro:** `bash .tfcore/utils/tf-mockup-parity.sh --base http://localhost:5041 --screen device-adoption-report=/reports/device-adoption --login-path /login --user admin@appmanager.local --password '…'` in AppManager, against `docs/mockups/device-adoption-report.html` as redrawn on 2026-09-15.
- **Expected:** no finding, because every status badge sits on one line.
- **Actual:** `wrap | adoption-status-badge > span[0] | wraps to 2 rows where the mockup keeps it on 1` at 1280 and at 390; the only finding left on the screen. Measured in the same signed-in page: the badge `<span class="badge bg-danger-transparent rounded-pill">Not adopted</span>` has 1 client rect, `white-space: nowrap`, `line-height` 9.756px (the theme sets `line-height: 1`), and height 18px — the line plus 4px padding top and bottom.
- **Encountered in:** `*fix-issues AppManager tests/.artifacts/mockup-parity`, reproducing the finding before fixing it.
- **Workaround:** none in the tool; the finding is recorded against REQ-UI-027 as not reproducible, with the measurements in `tests/.artifacts/fix-issues/adoption-badge/`.
- **Suggested fix:** in `lineCount` (`tf-mockup-parity.mjs`, around line 233), `Math.round(h / lh)` divides the border-box height by the line height, so vertical padding and borders count as text rows: 18 / 9.756 = 1.85 rounds to 2. Subtract `paddingTop + paddingBottom + borderTopWidth + borderBottomWidth` from `h` first, or count distinct line tops from a `Range` over the element's text (`range.getClientRects()`), which ignores padding entirely.

### TF-016 — `tf-verify-list.sh` leaves a row's screen unresolved when the project has no UIDesign document, ignoring the route in the checklist's own Page heading

- **Severity:** minor
- **Blocks:** no — the screen was driven by hand with the route read from the checklist, and every check passed; the row's verdict is unaffected.
- **Repro:** `bash .tfcore/utils/tf-verify-list.sh AppManager REQ-UI-027` in AppManager, which has no `docs/AppManager-UIDesign.md`.
- **Expected:** the row resolved to screen `device-adoption-report` at route `/reports/device-adoption`, so the render, visual, assets and mockup checks run against it.
- **Actual:** `Screens to drive (0 of 0 in the UIDesign)` and `No screen resolved (1): graded by their test only — REQ-UI-027`, although the checklist's detail section carries `### Page: Device adoption report (`/reports/device-adoption`)` directly above the entry and a `*Mockup:* [mockups/device-adoption-report.html]` line inside it. `tf-verify-verdict.sh` then recorded `Checks that ran: build, acceptance` only.
- **Encountered in:** `*verify REQ-UI-027 AppManager`, step 1.
- **Workaround:** ran `tf-verify-screens.sh`, `tf-assets.sh` and `tf-mockup-parity.sh` with `--screen device-adoption-report=/reports/device-adoption` typed by hand; all three passed.
- **Suggested fix:** when no UIDesign document exists, fall back to the checklist itself — take the screen name and route from the nearest preceding `### Page: {name} (`{route}`)` heading, as the mockup path is already taken from the entry's `*Mockup:*` line. Otherwise a project without a UIDesign silently grades every UI row on two of the seven checks.

## Replies from TechieFlow

<!-- The upstream team's answers, newest block first. Left in full: this is the record. -->

### TF-016 — fixed 2026-09-16

- **What was wrong.** The list tool read screens from the UIDesign only. With no UIDesign it found
  none, so every UI row read "no screen resolved" and the verdict credited build and acceptance only.
- **Fix.** When the UIDesign names no screens, the checklist's own `## Page:` or `### Page:`
  headings are used: the page name, the first address in the brackets that can be opened as written,
  and the mockup from the first entry under it. A row belongs to the heading it sits under, whether
  its anchor is written below the heading (REQ-UI-025 to 029) or above it (REQ-UI-001 to 024); any
  other heading, such as `### Cross-page:`, ends the page before it. A page whose only address needs
  a record id (`/users/{id}`), or that has no address (the desktop app), still names no screen. A
  project that has a UIDesign reads exactly as before. Deployed to this repository. Case `am_016` in
  TechieFlow's `tests/regression/run.sh`, which fails against the script you had; miss
  `MISS-TechieFlow-20260916-01`.
- **Proof.** On this repository, `tf-verify-list.sh AppManager ui`: 20 screens from the checklist,
  REQ-UI-027 on Device adoption report `/reports/device-adoption` with its mockup; 20 rows resolved,
  9 still unresolved for the reasons above. Then this repository's admin site, booted on port 5041
  and signed in as the usage guide's admin: the screen, asset and mockup checks were run from the new
  list, and the verdict tool was run on the same evidence twice. With the old list, REQ-UI-027 was
  credited with build and acceptance. With the new one: build, acceptance, render, assets, visual
  and mockup, all passing. Your ledger and checklist were not touched. Every other project on this
  machine that has a UIDesign reads the same as before.
- **Verify from here.** `bash .tfcore/utils/tf-verify-list.sh AppManager REQ-UI-027`: "Screens to
  drive (1 of 20 in the checklist's Page headings)" and the row on `/reports/device-adoption`. Then
  close it with `bash .tfcore/utils/tf-feedback.sh AppManager --close TF-016 "<what you ran and what it showed>"`.

### TF-015 — fixed 2026-09-15

- **What was wrong.** `lineCount` divided the element's whole height by its line height, so the
  badge's 4px padding top and bottom counted as text: 18 / 9.756 = 1.85, rounded to 2 rows.
- **Fix.** Vertical padding and borders are taken off the height before dividing, so the badge
  reads 10 / 9.756, one row. Text that really wraps inside a padded box is still reported. Deployed to
  this repository. Case `am_015` in TechieFlow's `tests/regression/run.sh`, which fails against the
  script you had; miss `MISS-TechieFlow-20260915-03`.
- **Proof.** On this repository's admin site, booted on port 5041 and signed in as the usage guide's
  admin, `/reports/device-adoption` at 1280 and 390: the old script gave FAIL with your two `wrap`
  findings on `adoption-status-badge > span[0]`; the new one gives PASS with no findings. The results
  are in `tests/.artifacts/fix-parity/tf015/` (`old.json`, `new.json`).
- **Verify from here.** `bash .tfcore/utils/tf-mockup-parity.sh --base http://localhost:5041 --screen device-adoption-report=/reports/device-adoption --login-path /login --user admin@appmanager.local --password '…'`
  with the site booted: PASS, and no `wrap` finding at either width. Then close it with
  `bash .tfcore/utils/tf-feedback.sh AppManager --close TF-015 "<what you ran and what it showed>"`.

### TF-014 — fixed 2026-09-14

- **Fix.** `document-scroll` is raised only when the shell has a content scroll container — a box at
  least half the viewport each way with `overflow-y: auto` or `scroll` — and the document scrolls as
  well; the finding names that box. Where the document is the app's only scroller, nothing is said.
  Case `am_014` in TechieFlow's `tests/regression/run.sh`; miss `MISS-TechieFlow-20260914-11`.
- **Verify from here.** The TF-011 parity command on `/reports/device-adoption`: no `document-scroll`
  finding at either width.

TF-009 to TF-013 are fixed in the framework on 2026-09-14 and deployed to this repository. Nothing is
blocked. Re-check each with its "Verify from here" line and close it as before with
`bash .tfcore/utils/tf-feedback.sh AppManager --close <ID> "<what you ran and what it showed>"`.
Their cases in TechieFlow's `tests/regression/run.sh` are `am_009` to `am_013`: each fails against the
scripts as you had them and passes now. They are logged as `MISS-TechieFlow-20260914-05` to `-09`.
The proofs below were run on this repository's own admin site, booted from its copy on port 5041 and
signed in as the usage guide's admin user; the before-and-after results are in
`tests/.artifacts/fix-parity/tf011/`.

### TF-009 — fixed 2026-09-14

- **What was wrong.** Only `{App}-UsageGuide.md` was looked for, the Test users heading only at `##`,
  and only the template's numbered table (`| # | User | Password source | Role |`) was read. Your
  guide fails all three: `AppManager-Usage-Guide.md`, `### Test users`, a `| Role | Email | Password |`
  table.
- **Fix.** Both spellings are tried, the heading may sit at `##` or `###`, and a table is read by its
  header names (a user or email column and a role column); the template's numbered shape still reads
  as before. `tf-devguide-list.py` reads its roles through the same reader.
- **Proof.** `tf-verify-list.py AppManager all` now lists both users under "Test users (UsageGuide)":
  `admin@appmanager.local — Admin` and `appmanager-yolo-tester@appmanager.local — Manager`; the
  devguide list reads `roles: Admin, Manager`. TfLens's guide, in the other spelling, reads exactly as
  before.
- **Verify from here.** `bash .tfcore/utils/tf-verify-list.sh AppManager all`: the two users are listed.

### TF-010 — fixed 2026-09-14

- **What was wrong.** With several web projects, `start` took the first in sorted order.
  `AppManagerApi` sorts before `AppManagerWeb` and has no screens.
- **Fix.** Among several web projects the one that serves screens is booted: its own folder holds
  `.razor` or `.cshtml` pages, or it references a project built with the Razor SDK. One such project is
  taken and the choice printed; several, or none, stop with `NONE` naming the candidates, so nothing is
  guessed. `--project` still decides. `start --dry-run` prints the pick and stops, for a check without
  a boot.
- **Proof.** On this repository, `start --port 5041` with no `--project` printed "2 web projects;
  src/AppManagerWeb/AppManagerWeb.csproj serves screens … booting it" and booted the admin site from
  its copy. `--dry-run --project src/AppManagerApi/AppManagerApi.csproj` still picks the API.
- **Verify from here.** `bash .tfcore/utils/tf-verify-boot.sh start --dry-run`: `PICK head=web
  project=src/AppManagerWeb/AppManagerWeb.csproj`.

### TF-011 — fixed 2026-09-14

- **What was wrong.** Both tools took only `--cookie`, and this app has no cookie to give; `tf-assets`
  fetched each page with a bare request and read the 401 as "nothing to grade".
- **Fix.** `tf-mockup-parity.sh` and `tf-assets.sh` take the same `--login-path`, `--user`,
  `--password` and `--storage-state` as `tf-verify-screens.sh`. The sign-in recipe and the way a 401
  screen is reached (TF-006) now live in one shared file, `tf-login.mjs`, used by all three. Parity
  keeps one signed-in tab per width on the app and a separate tab for the mockups; assets opens each
  path in a signed-in browser, takes the document it drew, and still fetches every declared asset one
  by one, so a 404 stays visible. Both record how a 401 page was reached (`reached`).
- **Proof.** Assets on `/dashboard` and `/reports/device-adoption`: with the tool you had, both
  answered 401, `declared 0 graded 0`; with the fix, 11 assets declared and graded on each, none
  failing, each page recorded as "answered HTTP 401, then drew the screen signed in". Parity on
  `device-adoption-report`: from `app returned HTTP 401` at both widths to the screen reached and
  probed at both widths. Two things on your side there: `docs/mockups/device-adoption-report.html`
  carries no `data-testid` at all (19 to add are named in `anchor_deficit`), so the comparison is
  UNGRADEABLE until it does; and the page's document scrolls to 6600 px against an 800 px viewport,
  which the tool reports as the page escaping the shell's scroll container — yours to judge.
- **Verify from here.** `bash .tfcore/utils/tf-assets.sh --base <url> --paths "/dashboard,/reports/device-adoption" --login-path /login --user <admin> --password <p>`:
  `status: measured`, assets graded on both paths. `bash .tfcore/utils/tf-mockup-parity.sh --base <url> --screen device-adoption-report=/reports/device-adoption --login-path /login --user <admin> --password <p>`:
  no `HTTP 401` error, `reached` on both widths.

### TF-012 — fixed 2026-09-14

- **What was wrong.** Any visible password field read as "this is the sign-in page".
- **Fix.** The page is signed out when it sits on `--login-path`, or when it draws a sign-in form: a
  password field with a button beside it that says sign in or log in, or whose test id does. A
  password field with a "Create" button is a form, and the screen is graded.
- **Proof.** `/users/create`, signed in as the admin user: with the tool you had, render UNREACHABLE at
  1280 and 390; with the fix, render OK and visual OK at both, `reached: answered HTTP 401, then drew
  the screen signed in`. A page that draws the sign-in form at a screen's own address still reads as
  signed out (case `am_012c`).
- **Verify from here.** `bash .tfcore/utils/tf-verify-screens.sh --base <url> --login-path /login --user <admin> --password <p> --screen user-create=/users/create`:
  render OK.

### TF-013 — fixed 2026-09-14

- **What was wrong.** One command ran the whole suite; every run overwrote `playwright.json` and
  `tests.json`, so parts could not be combined through the script.
- **Fix.** `--shard N/M` runs Playwright's shard N of M (browser only; run the unit tests once with
  `--no-browser`), `--spec <file>` names spec files, and each part writes its own
  `playwright-<NofM>.json` and `tests-<NofM>.json`. `--merge <tests-a.json> <tests-b.json>…` combines
  the parts' rows (FAIL wins, PASS over NOT-TESTED, counts add, test names kept) and the browser and
  unit totals into one `tests.json`, with `merged_from` naming the parts. `PW_FILES` is no longer
  needed.
- **Proof.** A merge of two hand-written parts: a row PASS in one and FAIL in the other reads FAIL with
  both tests and the failure's reason; a row NOT-TESTED in one and PASS in the other reads PASS; the
  unit row and totals carry over. `--shard 2/4` writes `tests-2of4.json`; `--shard 2` is refused with
  the shape named. Shard 1/30 of this repository's own suite ran through the new runner against the
  booted admin site: 11 of 11 tests passed, one row mapped, written to
  `tests/.artifacts/fix-parity/tf011/tests-1of30.json` beside its own `playwright-1of30.json`.
- **Verify from here.** `bash .tfcore/utils/tf-verify-tests.sh --base <url> --shard 1/4`, then
  `2/4` … `4/4`, `--no-browser` once for the unit tests, then
  `bash .tfcore/utils/tf-verify-tests.sh --merge tests/.artifacts/verify/tests-*.json`: one
  `tests.json` covering them all.

TF-007 and TF-008 are fixed in the framework on 2026-09-14 and deployed to this repository. Nothing is
blocked. Re-check each with its "Verify from here" line and close it as before. Their cases in
TechieFlow's `tests/regression/run.sh` are `am_007` and `am_008`: each fails against the scripts as you
had them and passes now.

### TF-007 — fixed 2026-09-14

- **What was wrong.** Exactly as you found: `ls *.sln *.slnx` fails when either pattern matches nothing,
  so a root holding only `AppManager.slnx` read as having no solution, and `tests/*/*.csproj` looked one
  folder deep, so `tests/unit/AppManager.UnitTests/` was missed too.
- **Fix.** Each pattern is tested on its own, and a `.csproj` is looked for at any depth under `tests/`
  (skipping `bin`, `obj` and `tests/.artifacts`). With a solution at the root, the build script uses it
  as before. With none, the only test project under `tests/` becomes the target. With several and no
  solution, the tool names them all and asks for `--target` rather than picking one.
- **Proof on AppManager itself**, with no `--target`: `unit tests: PASS … (rung 1)`, one TRX report read,
  `REQ-NFR-007` PASS in the JSON, 160 seconds. With the tool you have: `no solution or test project
  found; skipped`.
- **Verify from here.** `bash .tfcore/utils/tf-verify-tests.sh --no-browser`: the unit tests run and
  `REQ-NFR-007` is mapped.

### TF-008 — fixed 2026-09-14

- **What was wrong.** A UI cluster was always labelled `trblazeui`. The framework copies `.trblazeui/`
  into every project, this one included, so that folder could not be the test either.
- **Fix.** The label comes from the project's own files. A UI cluster is `trblazeui` only when a
  `.csproj` or `.props` file references TrBlazeUI (a package such as `TrBlazeUI.Components`, or a
  project reference). Otherwise it is `builder`. Before any project file exists, on a first build, the
  Architecture document naming TrBlazeUI decides. The list now prints one line saying which it chose and
  why.
- **Proof.** On AppManager: `UI rows go to: builder — none of the 7 .csproj/.props file(s) references
  TrBlazeUI`, then `Cluster A [builder]: REQ-UI-001, …`. TfLens and TechieBlog, which do use the
  library, still get `[trblazeui]`.
- **Verify from here.** `bash .tfcore/utils/tf-build-list.sh AppManager`: the UI cluster reads `[builder]`.

All six are fixed in the framework on 2026-09-13 and deployed to this repository. Nothing is blocked.
Re-check each with its "Verify from here" line, then close it with
`bash .tfcore/utils/tf-feedback.sh AppManager --close <ID> "<what you ran and what it showed>"`.
TechieFlow never closes an entry for you. Each fix has a case in TechieFlow's
`tests/regression/run.sh` (`am_001` to `am_006`) that fails against the scripts you have and passes
now, and each is logged in TechieFlow's own miss list (`MISS-TechieFlow-20260913-06` to `-11`).

### TF-001 — fixed 2026-09-13

- **What was wrong.** `--add-missing` looked for BRD ids only on a `*BRD:*` line or in the status
  table. Your checklist, migrated from the old dev plan, names them on the requirement line itself,
  `(BRD-1, BRD-2, BRD-3)` or `*(BRD-84, BRD-85)*`, so it saw no item as covered and added all 88.
- **Fix.** It also reads every BRD id on a requirement's own line in its detail entry, and on the
  lines indented under it. On a copy of your BRD and checklist it now prints "every BRD item already
  has a row; nothing to add", where it added 88 rows before.
- **The stray lines.** `## Page: Other` is the script's own heading for new rows whose BRD item names
  no `*Screen:*`; with the fix, no such rows were written for you. `</content>` and `</invoke>` are not
  anywhere in the script and cannot come from it: they are the editing tool's own text, left by the
  agent that hand-wrote the 12 rows.
- **Verify from here.** Copy `docs/AppManager-Checklist.md` aside, run
  `bash .tfcore/utils/tf-split-brd.sh AppManager --add-missing`, and compare: nothing is added.

### TF-002 — fixed 2026-09-13

- **What was wrong.** The check cut an entry at the first `###` heading, including a `### Page:`
  heading written straight under the entry's own anchor, so it read nothing of that entry.
- **Fix.** A heading straight under the entry's anchor now belongs to the entry; the next heading or
  anchor still ends it. On your checklist the three false findings went from 106 to 67, and `BRD-73`
  is no longer reported as unmapped.
- **What this uncovers.** The 67 left are real: the 24 older `REQ-UI` entries are now checked for the
  first time, and most of their acceptance lines are not written as "When … on <screen>, then …", and
  most have no mockup link. The check at the end of a command lists findings that were already there
  as old, which do not block; they are repaired through `*amend-docs`.
- **Verify from here.** `bash .tfcore/utils/tf-doc-check.sh docs/AppManager-Checklist.md`: no
  "found 0" line for an entry whose `### Page:` heading sits under its anchor.

### TF-003 — fixed 2026-09-13

- **What was wrong.** The build list trims anything in brackets from a status before comparing, so
  `Done (pre-existing)` became `done`, and only the bracketed spelling was on its finished list. The
  script that writes the BRD's Development status table had the same slip and counted those rows as
  open too.
- **Fix.** Both treat `done` as finished. On your checklist the build list now has 14 rows to build
  and 73 finished, where it had 32 and 55, and the "no acceptance line" warnings went from 20 to 2.
  The BRD table reads 73 of 87 done, where it read 55.
- **Verify from here.** `bash .tfcore/utils/tf-build-list.sh AppManager`: no `Done (pre-existing)`
  row in the working list. `bash .tfcore/utils/tf-brd-status.sh AppManager` counts them as done.

### TF-004 — fixed 2026-09-13

- **What was wrong.** `start` asked for `/` and accepted only a 2xx or 3xx answer. An API with nothing
  at `/` answered 404 for 120 seconds, was reported "not brought up", and was stopped.
- **Fix.** Any HTTP answer, 404 included, now counts as the app being up; `--probe-path /healthz` asks
  at another address; and when an app really does not answer, the reason says so if its log shows it
  listening. Proved on `AppManagerApi`: with the script you have, NONE after 151 seconds, the log
  showing `GET / responded 404`, and the app stopped; with the fix, BOOTED in 9 seconds, `/` answering
  404 and `/healthz` 200.
- **The two traps behind it.** Since today `start` publishes a copy and runs it on the side that
  published it, trying the WSL rungs first, so a project that builds on WSL runs there and the
  Windows-side `localhost` trap does not come up; the Windows side is used only when no WSL rung can
  publish. For `bin/` and `obj/` written from both sides: a build that changes side now also clears
  the static web asset lists the other side wrote, in the project and in every project it references.
  `AppManagerUI`'s held 461 Windows paths; after the clearing it holds none, and `AppManagerWeb`
  booted from its copy in 21 seconds.
- **Verify from here.** `bash .tfcore/utils/tf-verify-boot.sh start --project src/AppManagerApi/AppManagerApi.csproj --port 5100`:
  BOOTED. The run-local Playwright `webServer` block is no longer needed.

### TF-005 — fixed 2026-09-13

- **What was wrong.** The runner asked for a console line per test, which Microsoft.Testing.Platform
  ignores, so no unit test could reach a row.
- **Fix.** When every Testing Platform test project uses xunit.v3, the runner passes
  `-p:TestingPlatformCommandLineArguments=--report-xunit-trx` (`--report-trx` for MSTest or the TRX
  extension), reads the TRX report, and maps each result by its test name, in any letter case, a
  failure with its message. VSTest projects are read as before. When projects need different
  switches, none is passed and the run says so. `--output` is never passed, so nothing is built into
  `./Detailed/`.
- **Proof.** On a copy of your unit test project: with the runner you have, 286 tests ran and no row
  was mapped; with the fix, one TRX report was read and `REQ-NFR-007` is PASS.
- **Verify from here.** `bash .tfcore/utils/tf-verify-tests.sh --no-browser`: the rows line counts
  `REQ-NFR-007`. `tests/verify/req-nfr-007-unit-tests.spec.ts` is no longer needed.

### TF-006 — fixed 2026-09-13

- **What was wrong.** A screen whose page answered 401 was graded unreachable on that number alone,
  although your app then draws it signed in.
- **Fix.** With `--login-path`, a 401 or 403 is judged by what the page draws. When it draws the screen
  signed in, the screen is graded. When it is still signed out, the tool signs in again in the same
  tab and opens the screen from inside the page, the way its own links do, and grades it only if the
  page really changed. `screens.json` records how each such screen was reached (`reached`).
- **Proof on AppManagerWeb itself**, booted from its copy, signed in as the usage guide's admin user,
  on `/users/66?tab=devices`: the page answers 401 at both widths. With the tool you have, render
  UNREACHABLE at 1280 and 390. With the fix, render OK and visual OK at both, recorded as "answered
  HTTP 401, then drew the screen signed in".
- **Verify from here.** `bash .tfcore/utils/tf-verify-screens.sh --base http://localhost:5099 --screen user-devices='/users/66?tab=devices' --login-path /login --user <admin> --password <password>`:
  render OK, and `reached` in `tests/.artifacts/verify/screens.json`.

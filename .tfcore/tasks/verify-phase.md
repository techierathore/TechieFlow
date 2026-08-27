# verify-phase

Autonomously verify implemented requirements against their numbered REQ IDs. The AGENT performs every step itself in its own shell. The user runs nothing.

## Purpose

Replace manual verification. Given a scope, prove whether each numbered requirement is actually implemented and behaving, by running real headless browser tests and unit tests against the running application. Verdicts are written into the owning checklist's Requirements Status table (the single source of truth) plus a console miss list.

## Inputs

- `{AppName}` — required for the checklist path; resolve from the command argument, `core-config.yaml` → `customTechnicalDocuments`, or the `docs/{AppName}-Checklist.md` filename. Ask only if it cannot be resolved.
- `{scope}` — see Modes.
- **The DevGuide** (`docs/{AppName}-DevGuide.md`, or the split set under `docs/devguides/`) — the screen-by-screen, **per-control** test map. The verifier uses it to know which controls each screen must render (the render gate, §4a). If it is missing, the verifier still runs but notes that no control map exists and recommends `*devguide {AppName}`; if it exists, the verifier **refreshes its observed render-status tags** for every screen it exercises (§6b) — this is the DevGuide ⇄ Checklist ⇄ Verifier loop.

## Modes

- **Full mode** (default, `*verify {scope}`): run the entire pipeline below. There is **one checklist** (`docs/{AppName}-Checklist.md`); scopes filter its Requirements Status table by REQ prefix, they do NOT pick a separate file. Scope values:
  - `ui` — all `REQ-UI-*` rows.
  - `functional` — all `REQ-FN-*` / `REQ-NFR-*` / `REQ-RAG-*` rows.
  - `all` — every row.
  - An explicit ID list (`REQ-UI-007,REQ-UI-013`) — just those rows.
  - `phase-N` — LEGACY fallback for pre-split projects: grade the BRD's Phase-N numbered IDs (see §0 legacy path).
- **Setup-only mode** (`*setup`): execute only Section 1, then HALT.

## Local-only deployment policy (CRITICAL — read before every run)

The verifier MUST run the application **LOCALLY**. Never propose, suggest, or initiate any of the following to "make Playwright work":

- Cloudflare / Cloudflare Pages / Cloudflare Tunnels
- Vercel / Netlify / Render / Fly.io
- Azure App Service / AWS / GCP / any cloud deploy
- Pushing to a remote branch so a preview environment builds
- Asking the user to "deploy somewhere I can reach"

The user runs the harness (Claude Code or OpenCode, both in WSL) on their own machine. Local boot is always possible. If you find yourself drafting "let me deploy this to X first" — STOP, that is a banned escape hatch. The user has explicitly called this out as an "idiotic option" — do not repeat it.

**Local device hosts are NOT cloud.** Driving the MAUI Android head via the Appium server on the **Windows host** and the MAUI iOS / Mac Catalyst heads via the Appium server on the **LAN Mac** (`runtimeVerification.appium` in `core-config.yaml`, see §3b) is local infrastructure the owner set up once (`WORKFLOW.html §0b`) — it is the native analogue of headless Playwright, not a remote deploy. Use it. Only the cloud-deploy escape hatches above are banned.

If the WSL-side `dotnet run` is unreachable by Playwright (port collision, WSL networking quirks, missing browser deps), the correct escalation order is:

1. **Use the platform-specific bridge.** In WSL, rung #4 `cmd.exe /c "dotnet run --project ..."` launches Windows-side dotnet. In OpenCode Docker, use `winrun "dotnet run --project ..."`; direct `cmd.exe` is expected to be absent. The Windows-side port is reachable through the configured Docker host bridge. Try the appropriate bridge BEFORE asking the user anything.
2. **Try a different port** if rung #2 is on a busy port (5099 → 5599).
3. **Ask the user to run it locally themselves.** Output the EXACT two-line shell recipe and a `go` prompt:

   ```
   I can't reach the app from Playwright in this environment. Please run these two
   commands in separate terminals on the Windows side (or in your usual dev setup):

     Terminal 1 (API):  dotnet run --project src/{AppName}.Api --urls http://localhost:5100
     Terminal 2 (Web):  dotnet run --project src/{AppName}.Web --urls http://localhost:5099

   When both show "Now listening on", reply `go` and I'll run the verifier against
   those URLs.
   ```

   Wait for `go`. Then point Playwright at `http://localhost:5099` (and `http://localhost:5100` for API checks). Do NOT skip verification. Do NOT propose cloud anything.

This applies to EVERY phase task that boots an app (the `build-phase` self-smoke, the `fix-issues` repro, the `devguide` OBSERVE pass, and this verifier). They all share this policy.

## SEQUENTIAL Execution (do not proceed until current section is complete)

### 0. Load inputs and build the working list

- **First action, before anything else:** run `date -u +%Y-%m-%dT%H:%M:%SZ` and keep the value. It is this run's `started` **and** its `run_id` for the §6a telemetry emit. You cannot reconstruct it at the end, and an invented duration is a fabricated measurement.
- Load `.tfcore/core-config.yaml`; resolve `{AppName}` per Inputs above. Note any `runtimeVerification.appium` endpoints — they tell you which MAUI native heads (Android/iOS/Mac Catalyst) this app ships and how to reach them (§3b).
- Determine the scope from the command argument (`ui` / `functional` / `all` / explicit REQ IDs / legacy `phase-N`). **When this task is chained from `build-phase` or `fix-issues`, the caller has already stated the scope — use it and ask nothing.** Only if invoked standalone with NO scope: ask the user once "Verify which scope — ui, functional, all, or specific REQ IDs?" — this is the ONLY question you may ask.
- **Checklist path (normal):** open the one checklist `docs/{AppName}-Checklist.md`. From the **Requirements Status** table, filter rows by the scope's REQ prefix (`REQ-UI-*` for `ui`; `REQ-FN/NFR/RAG-*` for `functional`; all rows for `all`) and build the working list `[{id, text, status, type-guess, perf-budget}]` (type-guess ∈ {ui, behavioral, backend-logic, nonfunctional}; pull each REQ's acceptance criteria from its Details anchor section). While reading the acceptance criteria, capture any `perf-budget:` line verbatim — that, and only that, is what makes a REQ perf-gradeable in §4c. Most REQs will have none; that is expected and is not a gap to fill.
- **`Done (pre-existing)` is NOT a free pass — it is an unverified migrated claim.** Do NOT skip those rows. They were carried over from a dev-plan and have **never been runtime-verified** — this is exactly how blank-rendering screens slipped through (a `Done (pre-existing)` home page with an empty table and a blank list). Every in-scope row, **including `Done (pre-existing)`**, gets the **§4a DevGuide render sweep** at minimum (load its screens, confirm every control actually renders its data). Only `N/A` rows are skipped. Rows already `Verified` get a fast re-confirm (render sweep + re-run their test); `Done (pre-existing)` that passes the render sweep gets a `runtime render-confirmed {date}` remark and may stay Done; anything that renders blank/empty/errors → `Needs re-verify`/`FAIL` (§6).
- **Load the DevGuide map.** Read the DevGuide (`docs/{AppName}-DevGuide.md`, or the split set under `docs/devguides/`) and, for each in-scope screen, extract the list of controls + their expected data source from the *Controls*/*Data lineage* tables. This is the checklist of what must render in §4a. If no DevGuide exists, note it and fall back to acceptance-criteria-only grading, and recommend `*devguide {AppName}` in the report.
- **Legacy BRD path (only for `phase-N` scope on pre-split projects):** locate the BRD (`customTechnicalDocuments`, then `docs/{AppName}-BRD*.md`, then `docs/brd*.md`/`docs/BRD*.md`) and extract that phase's numbered IDs (`BRD-12`, `REQ-12`, `FR-12`, `[BRD-12]`). If no numbered IDs exist, STOP auto-grading and tell the user: "This phase has no numbered, checkable requirements, so coverage cannot be graded by ID. Number them as BRD-N (or run `*split-brd`) and re-run." Then offer a loose best-effort prose verification.
- If the working list is empty (all rows `N/A`), report "Nothing to verify — all rows N/A" and skip to §8. (Note: `Verified` and `Done (pre-existing)` rows are NOT empty-list — they still get the §4a render sweep.)

### 1. Ensure the verification environment (self-healing)

Run these checks yourself and act on them. Echo a one-line summary of what you did.

- If no `package.json` in repo root: `npm init -y`.
- Check Playwright: run `npx playwright --version`. If it errors or is absent: `npm install -D @playwright/test`.
- Check browsers: attempt `npx playwright install chromium`. If it reports missing system libraries (common on a fresh WSL/Ubuntu): run `npx playwright install --with-deps chromium`. If that needs sudo and sudo is unavailable, run `sudo npx playwright install --with-deps chromium`; if sudo also fails, report the single apt command the user must run once and HALT (this is the only situation where a manual step is unavoidable, and it happens at most once per machine).
- **Ensure `playwright.config.ts` at repo root, and ensure it pins `outputDir`.** If absent, create it. If present but missing `outputDir` (or pointing anywhere outside `tests/`), **edit it** — an unpinned config defaults to a repo-root `test-results/`, which is the exact litter this rule exists to stop. Canonical config:

  ```ts
  import { defineConfig } from '@playwright/test';
  export default defineConfig({
    testDir: './tests/verify',
    outputDir: './tests/.artifacts/test-results',   // ALL run artifacts live under tests/ — never the repo root
    reporter: 'line',                                // if you add 'html', set outputFolder: 'tests/.artifacts/playwright-report'
    use: { headless: true, screenshot: 'only-on-failure', trace: 'retain-on-failure' },
  });
  ```

- **ARTIFACT-LOCATION RULE (hard, no exceptions).** Everything this run generates that is not a deliverable — **what the tools output** (Playwright output, screenshots, traces, videos, Appium captures, HTML reports) **and what you write to drive them** (throwaway smoke/verify/load/cleanup scripts) — lands under **`tests/.artifacts/`**. Both halves matter: pinning only the output location leaves the agent free to invent a root-level home for its scripts, which is the same bug with a different noun. Consequences you must honor:
  - **NEVER create a repo-root sibling directory for run material — not `test-results-<something>/`, not `scripts-<something>/`, not any other suffixed variant.** Per-run/per-cluster directories at the root (`test-results-cluster-a/`, `test-results-<slug>/`, `scripts-cluster-a/`, `scripts-<slug>/`) are BANNED: a suffixed name escapes the ignore pattern written for the unsuffixed one, so it lands in the owner's `git status` as untracked machine output, and it accumulates one directory per run forever with nothing to clean it up. This has actually happened twice — one app ended up with fourteen `test-results-*` dirs, and after those were banned the next fan-out produced four `scripts-cluster-*` dirs instead. **Do not reason by the letter of this list**: any *new* root-level `<name>-<slug>/` you are about to create for a fan-out is the same defect, whatever the noun.
  - **The harness enforces this MECHANICALLY** (added 2026-08-25, after TechieBlog accumulated ten root `test-results-*` dirs on top of the two prior recurrences this rule already records): the `.tfcore/hooks/guard-artifacts.sh` PreToolUse hook blocks any Bash command that points `--output` / `--output-dir` at a root-level `test-results*` or `scripts-*`, or `mkdir`s one — in every harness (Claude Code hook, Codex via `codex-adapter.py`, OpenCode via the plugin bridge). A blocked call is **the policy working** — re-run writing under `tests/.artifacts/`, never reword the command to slip past it. `--output tests/.artifacts/<slug>` is allowed by design, as are `tests/`, `docs/screenshots/` and the project's own tracked `scripts/`.
  - **Never pass `--output test-results-…`.** The config's `outputDir` is the single answer, and Playwright already namespaces per test *inside* it and **wipes it at the start of every run**, which is what keeps the tree from growing. If a parallel fan-out genuinely needs isolation, the only permitted form is a **subfolder**: `--output tests/.artifacts/<slug>`.
  - **A harness script you write is an artifact, not project source — it goes under `tests/.artifacts/harness/`.** A smoke/verify/load/cleanup script you author for this run is scratch: name it per cluster *inside* that folder (`tests/.artifacts/harness/smoke-cluster-b.mjs`), never as a root-level folder per cluster. The repo's own **`scripts/`** directory — release, publish, dev-setup scripts the project owns and tracks — **is not yours**: never write a run harness into it, and never delete it. If a harness turns out to be worth keeping, it has stopped being scratch: promote it to a real spec under `tests/verify/` so the runner owns its config, its output location, and its lifecycle.
  - **A harness that drives the Playwright *library* still obeys this rule, and nothing enforces it for you.** `import { chromium } from 'playwright'` does **not** load `playwright.config.ts` — `outputDir` does not apply, and nothing wipes what the script writes. So such a script must place its own captures under `tests/.artifacts/` explicitly, and must **never hardcode an absolute path** (`/mnt/c/…/test-results-cluster-b`); resolve relative to the repo root. Prefer a real spec under `tests/verify/` run by `npx playwright test`, which inherits the pinned `outputDir` for free; reach for a standalone script only when the runner genuinely cannot express the check.
  - Screenshots are **failure evidence with a session lifetime**, not work product; so are the harnesses that produced them. They exist so §6 can cite a path in a Remark during this run. Nothing under `tests/.artifacts/` is ever committed, and nothing there is expected to survive the next run. Evidence that must outlive the run is the one-line Remark in the checklist, and — for reviewed screens only — the deliberately tracked `docs/screenshots/{AppName}/` set the DevGuide owns.
- **Gitignore what you provision — in this same step, never later.** Git is manual in TechieFlow: the owner runs every commit and must NEVER have to triage machine artifacts. Check `.gitignore` for each of: `node_modules/`, `/package.json`, `/package-lock.json`, `tests/.artifacts/`, `test-results/`, `test-results-*/`, `/scripts-*/`, `playwright-report/`, `.verify/`, `logs/`, `/docs/.last-verify.json`, `.DS_Store` — append any that are missing under a `# TechieFlow agent artifacts — machine-generated test harness & logs, never commit` header (the scaffold/update scripts manage the same block since 2026-07-11; doing it here too self-heals projects refreshed earlier). `test-results/`, `test-results-*/` and `/scripts-*/` are kept for **legacy** trees only — a compliant run writes none of them. Note the leading slash on `/scripts-*/`: it must match only a **root-level** `scripts-<slug>/`, never a legitimate nested one, and it deliberately does **not** match the project's own tracked `scripts/`. Match tolerantly (strip `\r`, accept anchored/slash variants) and never rewrite existing owner content. `playwright.config.ts` stays TRACKED — committed test suites depend on it. This rule generalizes: **any machine-generated file a task introduces (npm, Playwright output, logs, caches) gets its `.gitignore` entry in the same step that creates it.**
- **Expired run material is deleted for you (added 2026-08-26).** The `.tfcore/hooks/sweep-artifacts.sh` SessionStart hook removes files under `tests/.artifacts/` and `.verify/` older than the retention window (default 7 days; `artifactRetentionDays:` in `.tfcore/core-config.yaml`) and any banned repo-root legacy dir, in every harness. Consequences: **never rely on a previous run's material still existing** — a screenshot or log you want to cite in a Remark must be cited (path + date) in the same run that produced it; anything worth keeping past a week has stopped being scratch and is promoted (a harness to `tests/verify/`, a capture to `docs/screenshots/`). Do not "protect" material by moving it out of `tests/.artifacts/` — that recreates the litter the rule exists to stop.
- **Sweep legacy artifact dirs once, here.** Repo-root leftovers from pre-rule runs, both classes (the SessionStart sweep now removes these too, so this step is a belt-and-braces check on a project that has not had a fresh session since the update):
  - Any repo-root `test-results/` or `test-results-*/` — machine output from a pre-`outputDir` run.
  - Any repo-root `scripts-*/` (hyphen required: `scripts-cluster-b/`, `scripts-tr054/`) — a fan-out's throwaway harness folder.

  Delete those directories (`rm -rf`), report the count in your one-line summary, and move on. They are fully regenerable — that is the whole reason they were never work product. **Delete only root-level directories whose name matches `test-results*` or `scripts-*`.** Two hard exclusions: the project's own **`scripts/`** (no hyphen — release/publish/dev-setup scripts the repo tracks and owns) is NEVER touched, and neither is `tests/`, `docs/screenshots/`, or anything else. If a `scripts-*/` directory contains something that is plainly not a run harness, do not delete it — name it in the report and leave it for the owner.
- In SETUP-ONLY mode: print "Verification environment ready." and HALT here.

### 2. Locate and characterize the Blazor app

- Find the startup `*.csproj` (the one referencing `Microsoft.NET.Sdk.Web` or a Blazor SDK; if multiple, prefer one named like `*.Web`, `*.Server`, `*.App`, else ask once).
- Read `Properties/launchSettings.json` for `applicationUrl`. Capture both the https and http URLs. **Prefer the http URL** for testing to avoid dev-cert friction in WSL. If only https is exposed, run `dotnet dev-certs https --trust` (best-effort) and fall back to http if the cert blocks navigation.
- Note whether it is Blazor Server (SignalR — needs explicit waits) or WASM (slower first paint).

### 3. Boot the app headless in the background

- **Pick the right rung first** — read the startup `.csproj`. If it targets a MAUI **Android / iOS / Mac Catalyst** head (`<UseMaui>` + `-android`/`-ios`/`-maccatalyst`) → this section (Playwright boot) does not apply; jump to **§3b** to drive it over Appium. The MAUI **Windows** head builds/runs via rung #4 (`cmd.exe /c "dotnet run ..."`) and is driven by FlaUI/Appium-Windows as before. Otherwise (Blazor) use the ladder's platform rung: on WSL rung #2 (`~/.dotnet/dotnet run --project ...`); on macOS / native Linux `dotnet` is on PATH — plain `dotnet run` (ladder §A; `~/.dotnet/dotnet` does not exist there).
- Start it yourself, detached, capturing logs (WSL form shown — on macOS/Linux substitute plain `dotnet`):
  `nohup ~/.dotnet/dotnet run --project <csproj> --urls http://localhost:5099 > .verify/app.log 2>&1 &`
  (Pin a known free port like 5099 so the test URL is deterministic. Create `.verify/` if needed.)
- Poll `http://localhost:5099` (curl, up to ~60s) until it returns HTTP 200, or until `app.log` shows "Now listening on".
- If the log shows `NETSDK1178` / workload missing / `Microsoft.iOS.Sdk missing` → you picked the wrong rung. Kill the process, switch to rung #4, retry.

### 3a. Boot-failure fallback — ASK USER, never propose cloud

If the boot doesn't succeed in 60s, OR Playwright cannot connect to it (e.g. WSL networking blocks the WSL→localhost lookup):

1. Capture the last 30 lines of `.verify/app.log` and read them. If the error is fixable (port already in use → pick another port; missing dev cert → http only) — retry once.
2. Try rung #4 of the build invocation ladder: `cmd.exe /c "cd C:\\path\\to\\project && dotnet run --project src\\{AppName}.Web --urls http://localhost:5099"`. Detached, log to `.verify/app.log`. This launches Windows-side dotnet which Playwright in WSL can reach via `http://localhost:5099` (WSL2 forwards localhost to the Windows host).
3. If both fail, fall through to the **ask-user flow** (per the "Local-only deployment policy" at the top of this file). Output the two-terminal shell recipe. **Wait for `go`** and proceed.

**NEVER**: propose cloud deploy, propose skipping verification, propose "let me push to staging", propose "let me deploy to Cloudflare Pages so Playwright can reach it." Banned escape hatches.

### 3b. MAUI native heads — drive with Appium, not Playwright

§3/§3a boot a **Blazor** app for **Playwright**. A MAUI **Android / iOS / Mac Catalyst** screen has no browser — it is driven over the **Appium** WebDriver endpoint instead. Appium is the native analogue of Playwright: it returns a `base64` screenshot (for §4b) and an element tree with `rect` + text + page source (for §4a), so **the §4a render gate and §4b visual-truth gate run unchanged — only the driver differs.** The MAUI **Windows** head keeps its existing FlaUI / Appium-Windows path (its boot is rung #4, not this section — but the **window-binding & input discipline below applies to it in full**); Blazor keeps Playwright.

Trigger: the startup/owning `.csproj` has `<UseMaui>` / MAUI SDK and a `-android` / `-ios` / `-maccatalyst` target framework. For each such head in scope:

1. **Resolve the endpoint** from `core-config.yaml → runtimeVerification.appium.{android|ios|maccatalyst}`. If the app didn't register that head, note "no Appium endpoint configured for {head}" and stamp the head `⚠ STATIC-ONLY` (do NOT fake a pass); tell the user in §8 to add it per `WORKFLOW.html §0b`.
2. **Bring the device host up yourself** (boot-it-yourself rule, same as §3):
   - **Android** — run the registry `launch` command (e.g. `winrun "powershell -File start-android-verify.ps1"`) to start the emulator (`avd`) + Appium on the Windows host; then poll `curl http://localhost:4723/status` (Win11 mirrored networking → `localhost`) until `{"ready":true}` (emulator cold start can take minutes — poll, don't assume).
   - **iOS / Mac Catalyst** — the LAN Mac runs Appium; `curl http://<mac>:4723/status`. You do **not** start the Mac; if it is unreachable, that is a session dependency → stamp the head `⚠ STATIC-ONLY` with "Mac build host unreachable" and continue with the heads you can reach. Never mark those REQs `Verified` on visual grounds you couldn't observe.
3. **Build + install + launch the app on the device** via the build ladder runtime-observe leg (`build-invocation-ladder.md §D`): Android via rung #4 (`cmd.exe`), iOS/Catalyst on the Mac. Start an Appium session with the right driver (`uiautomator2` / `xcuitest` / `mac2`) pointed at the built `.apk`/`.app`.
4. Hand the live session to §4a/§4b: the fan-out subagents target this Appium session (selectors by `AutomationId` per the coding standard) instead of a Playwright `baseURL`. Screenshots land under `tests/.artifacts/` exactly as Playwright's do — the §1 artifact-location rule is driver-independent, so an Appium capture never gets its own root-level folder either.

**Window binding & input discipline (ALL native heads, INCLUDING MAUI Windows).** The classic desktop-automation failure is typing into the WRONG window: a global keystroke goes to whatever happens to hold focus (the IDE, a terminal, another app) — not the app under test. This has actually happened; it is banned, mechanically:

- **Bind the session to the app under test, by identity, before any interaction.** MAUI **Windows**: you launched the app, so you know its **PID** — attach the driver to THAT process's top-level window (Appium Windows: `appium:appTopLevelWindow` = the window handle resolved from the PID; FlaUI: `Application.Attach(pid).GetMainWindow(...)`). Never attach by "the active window" or a partial title search across the desktop. **Android / iOS / Catalyst**: the Appium session you created with the app's package/bundle id IS the binding — assert `currentPackage` / the active app id matches before interacting.
- **Element-scoped input ONLY.** Locate every target by `AutomationId` (the coding standard) *within the bound session/window*, and act on the **element** — `element.Click()`, `element.SendKeys(...)` / ValuePattern `SetValue(...)`. **NEVER inject global input**: FlaUI `Keyboard.Type(...)` / `Mouse.Click(x, y)` at desktop coordinates, PowerShell `SendKeys` / `SendInput`, `wshell.SendKeys`, or `adb shell input` aimed outside the app — all of these write into whichever window has focus and are BANNED.
- **Focus is verified, not assumed.** Before any input burst, assert the bound window is foreground (title + PID match); if it isn't, activate it through the automation API (`window.SetForeground()` / `driver.activateApp(...)`) and re-assert — never "just type".
- **Re-resolve after window changes.** A login dialog, popup, or navigation that spawns a new top-level window means you re-resolve the handle from the app's PID before continuing — a stale handle is how input lands in a dead or foreign window.
- **A missing `AutomationId` is a defect, not a license.** If a control can't be located by `AutomationId`, log it to the owning REQ's Remarks as a coding-standard defect (MAUI UI-testability rule, day1 §4) and fall back to name/type lookup *within the bound window* — never to screen coordinates or global keys.

If a head genuinely can't be reached after this escalation, it is `⚠ STATIC-ONLY` for that head — never a faked `Verified`. Tear the Appium session + any emulator you started down in §7.

### 4. Generate / refresh tests from the scoped requirement IDs (PARALLEL FAN-OUT)

**Test users (per `.tfcore/tasks/_smoke-test-policy.md`):** any test that needs a logged-in user MUST use a documented/existing account — first from `docs/{AppName}-UsageGuide.md`'s Test-users table, else looked up from the database via the connection string in `appsettings*.json`. **NEVER auto-create random verify/smoke users** (that pollutes the DB). If no usable account exists, STOP and ask the user to provide or confirm credentials before creating any — then record the created account in the UsageGuide table. Pass the chosen credentials into each subagent prompt so all tests share the same accounts.

**Single-agent test generation is a banned anti-pattern for the verifier too** — splits cleanly along test-type lines.

Group the working list by `type-guess`:

- **Cluster UI** — all `ui` / `behavioral` IDs (Playwright tests).
- **Cluster API** — all `backend-logic` IDs with HTTP surface (Playwright `page.request` or dotnet test integration tests).
- **Cluster Unit** — all `backend-logic` / `nonfunctional` IDs without HTTP surface (dotnet unit tests).

For each non-empty cluster, spawn a parallel **test-writer subagent** in ONE assistant turn: `tf-test-writer` if the harness registers it, otherwise the harness's general subagent (Claude Code: the `Agent` tool, `subagent_type=tf-test-writer|general-purpose`; OpenCode: the `task` tool, `subagent_type=tf-test-writer|general`). Each subagent prompt MUST include:
- The cluster's REQ IDs + requirement text.
- The running app URL (`http://localhost:5099` or whatever §3/§3a resolved to).
- Path to where the test files should land: `tests/verify/{scope}-{cluster}.spec.ts` (Playwright; scope slug = `ui` / `functional` / `req-list` / `phase-N`) or appropriate `*Tests.csproj` for dotnet tests.
- Black-box rule: do NOT touch application source.
- Return contract: `{ testsAdded[], testsRefreshed[], unobservable[] }`.

After all subagents return, you (the verifier) own running the tests in §5. Do NOT have subagents run tests — concurrent test runs against one running app would race.

Per-requirement guidance for subagents:

- **ui / behavioral** → one `test()` per requirement, title PREFIXED with the ID, e.g. `test('BRD-12 user can filter the grid by status', ...)`. Use Playwright auto-waiting plus explicit `await page.waitForSelector(...)` for Blazor Server render/SignalR. Assert the observable outcome the requirement describes.
- **backend-logic / nonfunctional** → if a `*Tests.csproj` exists, ensure a matching unit/integration test is present (do not rewrite existing passing tests; only flag absence). If no test project exists, mark the requirement `NOT-OBSERVABLE` rather than guessing.
- Reference the running URL as `baseURL`.
- Keep tests black-box and idempotent.

### 4a. DevGuide render sweep — the STRICT RENDER GATE (run for every in-scope screen)

Acceptance tests check "does the feature behave"; this sweep checks the thing that actually slips through — **"does every control on the screen actually render its data, or is it blank?"** A page that returns HTTP 200 with an empty table, a count badge over zero visible rows, or a chart with no data is a DEFECT, not a pass. This is what the verifier missed before.

For **every in-scope screen** in the DevGuide map (including those backing `Done (pre-existing)` and `Verified` REQs), generate/refresh a Playwright check (fan out by role-cluster like §4) that:
- Logs in as the role that reaches the screen (use the DevGuide's stated role + the `_smoke-test-policy.md` test user), navigates to the screen's route.
- For **each control the DevGuide lists** for that screen, asserts it actually rendered its data:
  - grids/tables/lists → **row count > 0 AND cells are non-empty** (catch the "count says 16 but rows blank" case: assert visible data cells, not just the count badge);
  - charts → the chart/SVG/series node exists and is non-empty;
  - detail/value panels → the value element is present and not blank/placeholder;
  - a control hidden behind a null guard (`@if (X != null)`) that never appears → **render-empty**, not "absent by design", unless the DevGuide says it's conditional.
- Record per control: **RENDERS** / **RENDER-EMPTY** (blank, zero-rows, count-vs-rows mismatch, null-guarded-away) / **RENDER-ERROR** (console/Blazor error) / **UNREACHABLE** (route/auth failed).

A screen with any RENDER-EMPTY / RENDER-ERROR control **fails the render gate** for every REQ that owns a control on it (§6). Capture a screenshot for each failing control. These observations are also what feed the DevGuide refresh in §6b — the DevGuide's render-status tags become *observed runtime facts*, not static inferences.

**For MAUI native heads (§3b),** run the identical assertions over the **Appium** session instead of Playwright: locate each control by its `AutomationId`, read the element's text / child count from the page source (grid rows non-empty, value non-blank), and treat a missing/empty element exactly as RENDER-EMPTY. Same verdicts, same screenshots — only the locator API changes.

### 4b. VISUAL-TRUTH gate — does the screen actually LOOK right (run for every in-scope screen)

The §4a render gate proves the data is *present in the DOM*; it does NOT prove the screen is *usable*. The exact failure the owner hit: every control renders its data, the verifier passes — but the controls **overlap, sit off-screen, are clipped to zero height, or the layout is broken**, so the running app is unusable. "Has data" ≠ "looks right." This gate closes that hole.

For **every in-scope screen** (same screens as §4a, same role login), at **at least two viewport widths** — desktop (1280×800) and mobile (390×844) — assert via Playwright:
- **No overlap:** no two sibling/interactive controls have intersecting bounding boxes (`boundingBox()` rectangles must not overlap beyond a small tolerance). Overlapping controls = `VISUAL-FAIL`.
- **In-viewport & sized:** every control the DevGuide lists has a bounding box with width > 0 and height > 0, and lies within the page bounds (not pushed off-canvas, not clipped to 0). A control with a zero-size or off-screen box = `VISUAL-FAIL`.
- **Not occluded / not collapsed:** key containers are not zero-height and content is not spilling out of its container.
- **Screenshot + vision:** capture a full-page screenshot at each width and **inspect it** — broken grid, stacked/overlapping text, unstyled fallback (raw HTML with no TrBlazeUI styling), or content overflowing its region is a `VISUAL-FAIL` even if the box-geometry checks passed.
- **Mockup diff (greenfield, when a mockup exists):** compare the screen against its mockup (`docs/mockups/{screen}.html` named in the REQ's checklist row). The same regions/controls should be present in roughly the same layout. A large structural deviation = `MOCKUP-DRIFT` (a `VISUAL-FAIL` sub-type); a match = `MOCKUP-MATCH`. Brownfield has no mockup — rely on the geometry + vision checks (and, where present, the reviewed DevGuide screenshots from `docs/screenshots/{AppName}/`).

Record per screen: **VISUAL-OK** / **VISUAL-FAIL** (with the failing controls + which width + a screenshot path) / **MOCKUP-DRIFT**. A screen with any `VISUAL-FAIL` fails the visual gate for every REQ that owns a control on it (§6). These observations also feed the DevGuide refresh (§6b).

**For MAUI native heads (§3b),** run the identical overlap / in-viewport / sized / screenshot-inspection checks over the **Appium** session: `element.rect` gives each control's bounding box (overlap + zero-size + off-screen detection), and `driver.get_screenshot_as_base64()` gives the full-screen image to inspect. Drive the device's natural size plus, where the simulator/emulator supports it, a phone vs tablet/desktop variant. Same `VISUAL-OK` / `VISUAL-FAIL` verdicts.

### 4c. PERFORMANCE gate — is it fast enough to meet the budget the BRD declared

§4a proves the data is there; §4b proves the screen is usable. Neither says anything about *speed* — a page that renders every control perfectly and takes nine seconds passes both gates today. This gate closes that, and it is deliberately the narrowest of the three.

**THE GOVERNING RULE: this gate never invents a budget.** It runs for a REQ **only** if that REQ's acceptance criteria declare one, in this exact form:

```
perf-budget: p95 ttfb <= 500ms @ concurrency 50
perf-budget: p95 load <= 2000ms @ concurrency 1
```

`p50|p95|max` · `ttfb|load` · a millisecond number · optional `@ concurrency N` (default 1). **No `perf-budget:` line → the gate does not run for that REQ**, it is omitted from `gates_run`, and nothing is reported. That is not a gap to fill by picking a sensible-sounding number: a threshold the owner never agreed to would produce failures they never asked for, and the first false failure is the moment gate verdicts stop being believed. A REQ whose prose says "should be fast" without a number is **not** perf-gated — flag it in §8 as *"REQ-NFR-00X asks for performance but declares no `perf-budget:` — add one to the BRD to make it gradeable"* and move on.

**Measure with the shipped harness — never hand-roll timing:**

```bash
bash .tfcore/utils/tf-perf.sh --base http://localhost:5099 \
     --paths "/,/posts,/admin/dashboard" --levels 1,50 --requests 8 \
     --build-config Release --label REQ-NFR-001 \
     --json-out tests/.artifacts/perf/REQ-NFR-001.json
```

Paths come from the DevGuide screens the REQ owns (its routes), not from a guess. Exit `2` means the app was unreachable — that is a `build`-gate problem, not a perf result. The harness prints one JSON object: `levels[].ttfb_ms.{p50,p95,max}`, `load_ms`, a `per_path` breakdown (which page is the slow one), `samples`, `errors`, `redirects` / `redirect_rate`, and a `weak` flag.

**If the app requires a login, PRESENT A SESSION — do not measure the door.** Pass the authenticated cookie or token through:

```bash
bash .tfcore/utils/tf-perf.sh --base http://localhost:5099 --paths "/,/export" \
     --cookie 'AuthCookie=<value from your Playwright login>' --build-config Release
# or: --header 'Authorization: Bearer <token>'   (--header is repeatable)
```

Grab the value from the same login your Playwright spec already performs in §3. **Exit `4` = `status:"redirected"`: every request was turned away and NOTHING was measured** — grade `PERF-UNMEASURED (auth wall)` and re-run with a session; never record the redirect latency as a page figure. (Added 2026-08-27, TfLens TF-002: the harness had no auth option, so on a gated app it timed the 302 to `/login` and reported `p95 = 4.1 ms` — the speed of being turned away at the door — with nothing marking the number meaningless.)

**Grading — three bands, and the middle one exists specifically so this gate does not cry wolf:**

| Measured vs budget | Verdict | Effect |
|---|---|---|
| ≤ budget | `PERF-OK` | gate passes |
| > budget, ≤ budget × 1.25 | `PERF-MARGINAL` | **does NOT block `Verified`** — writes a dated remark `⚠ perf: p95 {metric} {measured}ms vs budget {budget}ms (marginal)` so the drift is visible before it becomes a failure |
| > budget × 1.25 | `PERF-FAIL` | fails the gate for that REQ (§6) |

**Errors during the run — read the RATE, not the count.** This is the one place where "an error occurred" does not mean "do not grade", and getting it backwards makes the gate useless at exactly the concurrency levels it exists for:

- **`error_rate` ≥ 0.10 with timeout/connection error kinds → `PERF-FAIL`, `failure_class: "timeout"`.** The app did not serve the declared concurrency. Requests timing out under load **is** the perf result, not an obstacle to measuring it — a budget of `@ concurrency 100` is precisely a claim that this does not happen. Report the completed/attempted split and the p95 of what *did* complete, and say plainly that the latency figure describes only the survivors.
- **`0 < error_rate < 0.10` → `PERF-UNMEASURED (errors during run)`.** A handful of failures in an otherwise healthy run tells you the sample is contaminated, not that the app is overloaded. Re-run; if it persists, the failure belongs to the `acceptance` gate.
- **Any `non_200` → `PERF-UNMEASURED (non-200 responses)`** regardless of rate. A 404 means the path set is wrong (a test-setup bug), and a 5xx is a correctness failure the `acceptance` gate owns. Neither is a latency verdict. A non-zero **`redirect_rate`** is the auth case specifically — supply `--cookie` / `--header` and re-measure rather than grading the redirect.

**Three further conditions under which you must NOT record `PERF-FAIL`** — each produces `PERF-UNMEASURED` plus a one-line reason in §8, because a wrong perf failure costs more than a missing one:

1. **`build_config` is not `Release`.** A Debug-build number is not evidence — no tiered JIT steady state, no optimizations. Boot the app `-c Release` and re-measure, or stamp `PERF-UNMEASURED (Debug build)`.
2. **`weak: true`** (fewer than 20 samples behind the p95). Raise `--requests` and re-run; if you still cannot get samples, the number is indicative only. Note the interaction with the rule above: a run that shed most of its load can be *both* `weak` and a genuine `PERF-FAIL` — the load-shed verdict wins, because it does not depend on the latency distribution being trustworthy.
3. **The host is visibly contended** — you are running builds or other agents concurrently, or `wall_s` is wildly inconsistent between levels. Re-run once when quiet; if it stays noisy, say so rather than grading it.

**Never compare across machines or across runs on different hosts.** The harness stamps a `machine` block for exactly this reason. The budget is absolute (the BRD declared it); the measurement is local; a number from the Mac and a number from WSL are not the same measurement, and neither is a trend.

**MAUI native heads (§3b) are not perf-gated.** The harness speaks HTTP; an Appium-driven Android/iOS/Catalyst screen has no URL to sample, and app-launch/frame timing is a different discipline with different tooling. For a native head, the gate does not run — omit `perf` from `gates_run` and never substitute a Blazor measurement for a native one (same rule as `⚠ STATIC-ONLY`: an unmeasured thing is unmeasured, not passed).

**This gate is informational during a self-smoke.** `_smoke-test-policy.md` lets build-phase run the harness to catch an obvious regression early, but a self-smoke may never write a perf verdict into the checklist — the smoke ceiling stays `Implemented`, exactly as it does for §4a/§4b.

### 5. Run the tests

- Playwright: `npx playwright test --reporter=line`. **No `--output` flag** — the config's `outputDir` (`tests/.artifacts/test-results`) is the single artifact destination (§1 artifact-location rule). If you must isolate a parallel run, the only permitted override is a subfolder: `--output tests/.artifacts/<slug>`.
- Unit/integration (if a test project exists): `dotnet test --nologo`.
- Collect: per-test pass/fail, and for FAILURES only, the screenshot path under `tests/.artifacts/` and the relevant assertion message. Do not open artifacts for passing tests.

### 6. Build the coverage matrix AND write it into the Status table

Map every requirement ID to exactly one verdict:

- `PASS` — a real test for this ID passed against the running app / a unit test passed, **AND** every control the DevGuide attributes to this REQ's screens passed the §4a render gate **AND** the §4b visual-truth gate **AND** (only if the REQ declared a `perf-budget:`) the §4c perf gate.
- `RENDER-FAIL` — the acceptance behavior may work, but at least one of the REQ's controls is **RENDER-EMPTY / RENDER-ERROR** (blank table, count-vs-rows mismatch, empty chart, blank value, Blazor error). Include the control + screenshot. This is a real defect even if an old status said `Done`.
- `VISUAL-FAIL` — the data renders, but the screen does not LOOK right: controls overlap, sit off-viewport, are clipped to zero size, the layout is broken/unstyled, or it drifts structurally from its mockup (§4b). Include the failing control(s), the width, and a screenshot. A real defect even if §4a passed and an old status said `Done`.
- `PERF-FAIL` — the REQ declared a `perf-budget:` and the measured p95 exceeded it by more than 25% under the four measurement preconditions of §4c. Include metric, measured value, budget, and concurrency. **Only for REQs that declared a budget** — a REQ with no `perf-budget:` line is never graded here.
- `FAIL` — a test for this ID ran and failed (include the one-line reason + screenshot path).
- `NOT-IMPLEMENTED` — feature/element the requirement needs was absent (test could not even find it).
- `NOT-OBSERVABLE` — backend/nonfunctional requirement with no test project to assert it; needs a human or a test to be written.

**A missing file is NEVER a verdict until you have read its literal path.** Before grading a REQ `NOT-OBSERVABLE` — or writing any remark that a required script, oracle, fixture, or harness "is not present in this tree" — read the exact path the REQ, its BRD section, or this task names. Paths under `.tfcore/` are hidden **and** gitignored, so Grep and Glob return nothing for files that are plainly there (`_status-update-gate.md` §"The framework tree is INVISIBLE to search"; `rg -uu` if you must search). A "the tool does not exist here" verdict sourced from a default search is a false negative that lands in the checklist Remarks, the BRD §4 status row, and every gate downstream of it — and the next agent reads it as established fact.

**STRICT GATE (non-negotiable):** a REQ may be `Verified` **only if** its acceptance test passes AND all its DevGuide-listed controls RENDER their data (§4a) AND every screen it owns passes VISUAL-TRUTH (§4b) AND — *where and only where the REQ declared a `perf-budget:`* — it is not `PERF-FAIL` (§4c). Never mark `Verified` when any owned control is RENDER-EMPTY/RENDER-ERROR or any owned screen is VISUAL-FAIL — those are the exact failure modes these gates exist to stop (data-present-but-blank, and data-present-but-visually-broken). A `Done (pre-existing)` REQ whose screens pass both gates stays `Done (pre-existing)` with a `runtime render+visual-confirmed {date}` remark; one that fails either drops to `Needs re-verify`.

**The perf gate never widens the `Verified` bar for a REQ that never declared a budget.** Most REQs are not perf-gated and must not be treated as if they failed something they were never measured against — `PERF-UNMEASURED` and "no budget declared" are both simply *absent* from the verdict, not a demotion.

**Write the run ledger FIRST (mechanical unlock).** Immediately before recording the first verdict, Write `docs/.last-verify.json` (overwrite the previous run's file; it lives next to the checklist):

```json
{"date":"<today YYYY-MM-DD>","app":"{AppName}","scope":"{scope}","booted":"<rung/URL or Appium target>","gates":["acceptance","data-render","visual-truth"],"evidence":"<tests/.artifacts/ path or one-line pointer>"}
```

List in `gates` the gates this run actually applied — add `"performance"` when §4c graded at least one REQ. (`guard-verify.sh` reads only `date`; the array is the human-readable record of what the run did, so an accurate list costs nothing and a padded one is a false audit trail.)

The PreToolUse hook `.tfcore/hooks/guard-verify.sh` BLOCKS any checklist write that introduces a `Verified` status without a same-day ledger — this is what makes "only the verifier writes `Verified`" mechanical rather than prose. You may write the ledger ONLY after actually executing §3–§5 above (boot + scoped tests + both gates); writing it without having run them is falsifying the audit record.

Then **write each verdict into the Requirements Status table** of the one checklist `docs/{AppName}-Checklist.md` (find the row by its REQ ID). This is the single source of truth; there are no dated coverage files. Update only the Status / % / Remarks cells (never the requirement text or app source). Map verdict → table Status:

| Verdict | Status | % | Remark |
|---------|--------|---|--------|
| PASS | `Verified` | 100% | date + test path + `render+visual gate: all controls render and look right` |
| RENDER-FAIL | `Needs re-verify` | lower to reflect reality | date + `⚠ render gate: {control} renders empty/error on {screen}` + screenshot path |
| VISUAL-FAIL | `Needs re-verify` | lower to reflect reality | date + `⚠ visual: {control(s)} overlap/clip/off-viewport on {screen} @ {width}` (or `⚠ visual: drifts from mockup`) + screenshot path |
| PERF-FAIL (slow) | `Needs re-verify` | lower to reflect reality | date + `⚠ perf: p95 {metric} {measured}ms vs budget {budget}ms @ concurrency {n}` + the slowest path from `per_path` |
| PERF-FAIL (load shed) | `Needs re-verify` | lower to reflect reality | date + `⚠ perf: {failed}/{attempted} requests timed out @ concurrency {n} — budget {budget}ms not servable` + the p95 of the completed subset, labelled as survivors only |
| PERF-MARGINAL | **unchanged** (may still be `Verified`) | keep | date + `⚠ perf: p95 {metric} {measured}ms vs budget {budget}ms (marginal)` — a warning, never a demotion |
| PERF-UNMEASURED | **unchanged** | keep | date + `perf: not measured — {Debug build / weak sample / errors during run / host contended}` |
| FAIL | `FAIL` | keep | date + one-line reason + screenshot path |
| FAIL caused by a library gap | `Blocked` | keep | date + link the `TR-NNN` entry in `docs/{AppName}-TrBlazeUI-Feedback.md` or the `TR-RAG-NNN` entry in `docs/{AppName}-TechieRag-Feedback.md` (add the entry if the implementing agent didn't — one feedback file per library) |
| NOT-IMPLEMENTED | `In Progress` | 25% | date + "element/feature absent" |
| NOT-OBSERVABLE | `N/A` | — | date + "no test surface; needs human/test" |

A FAIL counts as "caused by a library gap" when the failing behavior traces to TrBlazeUI/TechieRag rather than app code (matches an entry in the owning library's feedback file, or your diagnosis pins it on the library). `Blocked` rows pass through phase-completion checks — they are not the app's fault.

If a graded ID has no row in the Status table yet, add one.

### 6a. Emit gate telemetry (immediately after the ledger + verdicts)

Read `.tfcore/tasks/_metrics-emit-gate.md` once; it carries the constraints. Schema: `.tfcore/telemetry/SCHEMA.md` §3.

`docs/.last-verify.json` is the *same-day unlock ledger* and is overwritten every run — it is not history. This step is what makes the run durable. **Emit ONE `gates.jsonl` record per REQ you evaluated in §6** — pass or fail, no exceptions, including `Blocked` and `Done (pre-existing)`.

For each REQ:

1. **`gate` — the FIRST gate that failed, or `null` on a pass.** This one field produces the whole gate-catch distribution; get it right and everything else is secondary. Execution order is `build` → `acceptance` → `render` → `visual` → `perf` → `standards`. A REQ that failed §4a *and* §4b records `render`, not `visual` — recording the later gate inflates the visual gate's apparent catch rate. Same for `perf`: a REQ that was already `VISUAL-FAIL` records `visual`, even if its p95 also blew the budget.
2. **`attempt` — derive it, never guess it:** `bash .tfcore/utils/tf-emit.sh --next-attempt REQ-UI-004` prints the number. Run it per REQ.
3. **`gates_run`** — only the gates that actually executed this pass. A `⚠ STATIC-ONLY` head did not run `render` or `visual`; leave them out rather than crediting a gate that never fired. **`perf` belongs here only when a `perf-budget:` existed AND the §4c preconditions held** — a REQ with no budget, a native head, a Debug build, or a `PERF-UNMEASURED` outcome did not run the perf gate, and listing it would silently inflate the gate's measured coverage. This field is the only thing that makes the perf gate's catch rate readable at all (SCHEMA §3.5), so it is worth getting exactly right.
4. **`prior_verdict`** — the Status cell value you just overwrote (`null` if the row is new).
5. **`failure_class`** — from the closed enum only (`blank-data` · `zero-rows` · `overlap` · `clipped` · `offscreen` · `slow-ttfb` · `slow-load` · `timeout` · `exception` · `assert-fail` · `naming` · `build-error` · `other`). **Never free text** — a description here would leak requirement and client detail. A `perf` gate failure is `slow-ttfb` or `slow-load` depending on which metric the budget named, or `timeout` when the run failed by shedding load rather than by being slow; **never emit the measured milliseconds** — a number is a measurement of this machine on this day and does not belong in an append-only stream that is read across hosts.
6. **`run_id`** — the same value for every REQ in this pass: the timestamp you noted when the verify run started.

```bash
ATT=$(bash .tfcore/utils/tf-emit.sh --next-attempt REQ-UI-009)
cat <<JSON | bash .tfcore/utils/tf-emit.sh gates
{"kind":"gate","app":"{AppName}","run_id":"2026-08-08T03:41:02Z",
 "req_id":"REQ-UI-009","req_class":"UI","attempt":$ATT,"verdict":"Needs re-verify",
 "gate":"visual","gates_run":["acceptance","render","visual"],
 "failure_class":"overlap","prior_verdict":"Implemented"}
JSON
```

Map the §6 verdict table to the record: PASS → `verdict:"Verified"`, `gate:null` · RENDER-FAIL → `"Needs re-verify"`, `gate:"render"` · VISUAL-FAIL → `"Needs re-verify"`, `gate:"visual"` · **PERF-FAIL → `"Needs re-verify"`, `gate:"perf"`, `failure_class:"slow-ttfb"|"slow-load"|"timeout"`** · FAIL → `"FAIL"`, `gate:"acceptance"` (or `"build"` if it never compiled/booted) · library-caused FAIL → `"Blocked"`, `gate` = whatever actually failed · NOT-IMPLEMENTED → `"FAIL"`, `gate:"build"`, `failure_class:"other"` · NOT-OBSERVABLE → **emit nothing**; there was no gate and no verdict, and a fabricated record would poison the distribution.

**`PERF-MARGINAL` and `PERF-UNMEASURED` are NOT failures and must not be emitted as one.** A marginal REQ that otherwise passed emits an ordinary pass (`gate:null`) with `perf` present in `gates_run` — the warning lives in the checklist Remark, where a human reads it, and not in a stream whose whole purpose is counting what each gate caught. `PERF-UNMEASURED` emits a pass with `perf` **absent** from `gates_run`. Inventing a failure record for a warning would corrupt the one number this gate exists to produce.

Then emit ONE `runs.jsonl` record for the verify pass itself:

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"verify-phase","mode":null,
 "started":"<run start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":["REQ-UI-009","REQ-FN-011"],"reqs_count":2,
 "subagents":[],"files_written":<n>,"build_result":"pass"}
JSON
```

**Hard rules for this step.** Telemetry has **no veto** — if an emit fails, the verify run still succeeded; do not retry, do not diagnose, do not mention it, and never let it change a verdict. Do not touch `docs/.last-verify.json`. Do not write metrics into the checklist or PROJECT-STATUS. Never emit `"backfilled":true` — only the owner-run `tf-metrics.sh` writes those.

### 6b. Refresh the DevGuide render-status (close the loop)

For every screen you exercised, update its entry in the DevGuide (`docs/{AppName}-DevGuide.md`, or the matching role file under `docs/devguides/`) so its control render-status reflects **what you just observed at runtime** — not the old static inference:
- Tag each control **renders ✓ (runtime-confirmed {date})** / **renders-empty (DEFECT — {what}, {date})** / **render-error** / **unreachable**, matching the §4a sweep, and add the §4b visual result for the screen **looks-right ✓ (runtime-confirmed {date})** / **visual-broken (DEFECT — {what} @ {width}, {date})**.
- Update/refresh the screen's *Known issues* with any new RENDER-EMPTY/ERROR **or VISUAL-FAIL** finding (with file refs if known), and clear ones that now render and look right.
- Stamp the DevGuide file header (or the screen block) `Runtime-verified {date} as {roles exercised}`. If a screen could not be reached/booted, mark it `NOT RUNTIME-VERIFIED` rather than leaving a stale "renders" claim.
- This is markdown only — do NOT render the checklists to HTML; DO re-render the touched DevGuide `.html` via `.tfcore/tasks/generate-html.md` (it is a human doc).

If no DevGuide exists, skip this and add to the report: "No DevGuide to refresh — run `*devguide {AppName}` to create the control map, then re-verify."

### 7. Tear down

- Kill the app process you started (by the pinned port / stored PID). Confirm the port is free.
- For MAUI native heads (§3b): quit the Appium session, and shut down any **emulator** you started yourself (leave a pre-existing/owner-run emulator or the LAN Mac's Appium server up — only tear down what you booted).
- **Leave no artifact directory outside `tests/.artifacts/`.** If this run produced a repo-root `test-results/`, `test-results-*/` or `scripts-*/` anyway (a stray `--output`, a tool default you didn't pin, a harness you dropped at the root), delete it now — you created it, you remove it. The project's own `scripts/` is never yours to remove. `tests/.artifacts/` itself STAYS: it is gitignored, Playwright wipes it at the start of the next run, and the paths you cited in §6 Remarks must still resolve for the owner reading the report today.

### 8. Report and HALT

Print a compact report (you have already updated the checklist Status table in §6; do NOT modify requirement text or app source):

```
# Verification — {scope}
Source checklist(s): <path(s)>   |   Requirements graded: N

| ID      | Requirement (short)        | Status          | Evidence                          |
|---------|----------------------------|-----------------|-----------------------------------|
| BRD-10  | ...                        | PASS            | tests/verify/phase-2.spec.ts      |
| BRD-12  | ...                        | FAIL            | screenshot: tests/.artifacts/.../...png — "expected grid rows > 0" |
| BRD-13  | ...                        | NOT-IMPLEMENTED | element [data-testid=status] absent |
| BRD-14  | ...                        | NOT-OBSERVABLE  | no test project; logic-only       |

## MISS LIST (act on these)
- BRD-12 FAIL — <one line>
- BRD-13 NOT-IMPLEMENTED — <one line>

## Summary: PASS x / FAIL y / BLOCKED b / NOT-IMPLEMENTED z / NOT-OBSERVABLE w
## Perf (§4c): graded p of q budget-carrying REQs — PERF-OK a / MARGINAL m / FAIL f / UNMEASURED u
```

Print the Perf line **only when at least one in-scope REQ declared a `perf-budget:`** — on a project where none do, the gate did not run and a line saying so is noise. When you did skip REQs for a missing budget, name them once: *"REQ-NFR-003, REQ-NFR-007 ask for performance but declare no `perf-budget:` — add one to the BRD to make them gradeable."*

- The per-REQ detail now lives in the checklist Status table (§6) — do NOT also save a dated `docs/verify/*.md` report. The console report above plus the updated Status table ARE the deliverable.
- **FINAL GATE — update PROJECT-STATUS (MANDATORY, non-skippable).** Before you HALT, update PROJECT-STATUS — **both `PROJECT-STATUS.md` AND re-rendered `PROJECT-STATUS.html`** — per `.tfcore/tasks/_status-update-gate.md`: `last_updated`, `last_verified_build`/`last_verified_date`, sync Open requirements to the Status table (anything not `Verified` stays open), set the Next command (**command-against-checklist only — re-run the phase naming the FAILed REQ IDs if there are FAILs; advance if all `Verified` — no prose to-do narrative**), and add a verification-log row pointing at the checklist's `#requirements-status`. **Record this run's outcome as that ONE Verification-log row + the per-REQ Remarks you wrote in the checklist (§6) — do NOT add a `## *verify all — coverage matrix (date)` section (or any new H2) to PROJECT-STATUS; it is a fixed-shape snapshot you overwrite, never an append-log (see `_status-update-gate.md`).** A verification run that updates the markdown but not the HTML, or that does not update PROJECT-STATUS at all, is incomplete.
- Do not fix source. If the user wants fixes, that is a separate instruction to the dev/orchestrator agent referencing the miss list.
- HALT.

## Key principles

- The user typed one command. You did everything else.
- Grade only against numbered IDs; never inflate coverage.
- **A feature is not "done" until its UI renders its data AND looks right.** Behaves-correctly AND renders-its-data (§4a) AND looks-right (§4b) are ALL required for `Verified`. HTTP 200 with a blank table is a FAIL; data-present-but-overlapping/clipped/off-screen is also a FAIL. This is the gap that let "verified" screens be visibly broken.
- **Speed is graded only against a budget someone declared** (§4c). The perf gate is the narrowest of the four on purpose: it fires only for a REQ carrying a `perf-budget:`, it warns before it fails, and it refuses to grade a Debug build or a thin sample. A gate that produces false failures teaches the owner to ignore verdicts, which costs more than the defects it would have caught.
- **`Done (pre-existing)` is an unverified claim, not a pass** — it gets the render sweep like everything else. The first runtime pass either confirms it or flags it.
- **Close the loop:** the DevGuide is your control map (§0/§4a) and you write your runtime observations back into it (§6b). DevGuide ⇄ Checklist ⇄ Verifier stay in sync; a build phase marking a REQ done → this verifier → updated checklist + DevGuide → repeat.
- Results go in the checklist Status table + PROJECT-STATUS (+ the DevGuide render tags) — never a separate dated file.
- Lean context: read failures, ignore successes, tear down what you booted.

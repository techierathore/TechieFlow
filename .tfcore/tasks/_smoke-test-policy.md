# _smoke-test-policy (shared rule — included by every task that builds or verifies code)

## The rule

**Every code change is SMOKE-TESTED by the agent that made it, in this same session, BEFORE it is handed to the verifier or reported as "done".** A green `dotnet build` is NOT a smoke test — it proves the code compiles, not that the feature runs. No build phase chains to the verifier, and no agent says "implemented / done", with un-smoke-tested code. The owner should never have to discover at UAT that a feature was never actually run once.

A smoke test = boot the app (or the relevant host), exercise the changed feature once against the running app, and confirm it reaches the user without an unhandled exception. The per-phase tasks define the exact shape (`build-phase §6`, `fix-issues`, `devguide §5a`, `verify-phase`). This file defines the things every one of them must honor: **you run it yourself**, **you confirm the data actually renders**, **you confirm the screen actually looks right**, and **you use real test users**.

## "It runs" means the CONTROLS RENDER THEIR DATA *and* the screen LOOKS RIGHT — not just HTTP 200

A screen passes the smoke only if it clears **two** gates. Both have shipped real, damaging bugs:

**RENDER-TRUTH — the data is actually there.** A page that loads without an exception but shows a **blank table, a count badge over zero visible rows, an empty chart, or a blank value** is a FAILED smoke, not a pass (a home page whose details table is empty and whose list shows "16" over blank rows, shipped because the smoke only checked that the page opened). So:
- For **every data-bound control on the screen you touched** (grid/table/list, chart, detail/value panel), confirm it actually shows data: **rows present AND cells non-empty** (not just a count), chart/series non-empty, value not blank/placeholder. A control hidden by a `@if (x != null)` guard that never appears is render-empty, not "fine".
- A render-empty/blank control is a defect: log it to the owning `REQ-*` Remarks and do not report the screen "done"/`Verified`.

**VISUAL-TRUTH — the screen actually looks right.** Data being present is necessary but NOT sufficient. A screen where every control has its data but the controls **overlap each other, sit off-screen, are clipped to zero height, the layout is broken, or the UI renders unstyled** is a FAILED smoke — this is the exact "the verifier passed but the running UI is completely broken / controls overlapping" problem the framework exists to catch. So, for the screen you touched, at **desktop and a mobile width**:
- No two controls overlap (intersecting bounding boxes); every control is in-viewport with non-zero width and height; nothing is clipped or pushed off-canvas.
- Capture a screenshot and **look at it** — overlapping/stacked text, a broken grid, content overflowing its container, or raw unstyled HTML is a visual FAIL even if the geometry checks pass.
- ❌ "The data is present, so the screen is fine" is a **BANNED excuse** — a visually broken screen is a failed smoke regardless of data.
- A visual failure is a defect: log it to the owning `REQ-*` Remarks (prefix `⚠ visual:`) and route the fix to the UI builder (`/trblazeui`); do not report the screen "done"/`Verified`.

Where a DevGuide exists (`docs/{AppName}-DevGuide.md`, or the split set under `docs/devguides/`), it lists the controls each screen must render — use it as the per-control checklist. The verifier formalizes both gates: the **render gate** (`verify-phase.md §4a/§6`) and the **visual-truth gate** (`verify-phase.md §4b/§6`). A REQ is `Verified` only when it passes acceptance AND render-truth AND visual-truth.

**Performance during a smoke is informational only.** If a REQ you just built declares a `perf-budget:` in its acceptance criteria, you MAY run the harness to catch an obvious regression while the app is already up:

```bash
bash .tfcore/utils/tf-perf.sh --base http://localhost:5099 --paths "/,/your/route" \
     --build-config Release --json-out tests/.artifacts/perf/smoke.json
```

Report a blown budget in your summary so it gets fixed now rather than at verify time. But **a smoke never writes a perf verdict** into the checklist — the §4c grading bands, the Debug/weak-sample preconditions, and the `gates_run` telemetry all belong to an executed verify-phase. Same ceiling as everything else here: `Implemented`, never `Verified`.

This is the difference between "the method exists / the page compiled" and "the feature works". Only the latter — data present AND looking right — counts.

## Smoke is NOT verify — a self-smoke's ceiling is `Implemented`

Your smoke (this policy) and the verifier gate (`verify-phase.md`) are **different steps by different actors**, even when the same session performs both. However thorough your smoke felt, it earns a REQ **at most `Implemented`** — never `Verified`. `Verified` is written only by an **executed** verify-phase run (chained inline per `build-phase §6b`, or a standalone `*verify`): boot, scoped tests, §4a data-render + §4b visual-truth gates, and the run ledger `docs/.last-verify.json` (verify-phase §6). "I did my own smoke and wrote the verdicts myself" is **self-attestation** — the 2026-07-09 TrSetup failure — and is now blocked **mechanically**: the PreToolUse hook `.tfcore/hooks/guard-verify.sh` rejects any checklist write that introduces `Verified` without a same-day ledger. Writing the ledger without actually running verify-phase's steps is falsifying the audit record.

## "I can't run it here" is a BANNED excuse — the environment is already set up

The owner did the one-time setup (`WORKFLOW.html §0` on WSL / `§0a` on macOS) precisely so the agent can smoke-test without help. These capabilities are PERMANENTLY available on the host:

- **Headless Playwright + Chromium** are available on every supported host (WSL: system libs from the §0 bootstrap; macOS/Linux: nothing beyond Node). Browser smoke tests run **headless** — no GUI, no display server needed. **Never ask the owner to install Playwright** — `verify-phase.md §1` self-provisions it per project (`npm install -D @playwright/test` + `npx playwright install chromium`; the browser binary is a shared per-machine cache, so only the first project pays the download). The same step **gitignores every artifact it creates** (`node_modules/`, `/package.json`, `/package-lock.json`, `tests/.artifacts/`, `test-results/`, `test-results-*/`, `playwright-report/`, `.verify/`, `logs/`, …) — git checkin is the owner's manual job and they must never have to triage machine artifacts; any file YOUR run generates that isn't work product gets its `.gitignore` entry in the same step. **All run artifacts go under `tests/.artifacts/`** — both the output *and* the harness. A smoke run may never create a repo-root sibling for either: no `test-results/` or `test-results-<slug>/`, no `scripts-<slug>/`, no `--output test-results-…`. A throwaway smoke script you write is scratch, not project source: it goes in `tests/.artifacts/harness/`, never in the project's own tracked `scripts/` and never in a root-level `scripts-cluster-x/` of its own. A script that imports the Playwright **library** directly bypasses `playwright.config.ts` entirely, so it must place its captures under `tests/.artifacts/` itself and must never hardcode an absolute path. See `verify-phase.md` §1 (artifact-location rule), which binds every self-smoke exactly as it binds the verifier.
- **The MAUI / Windows-side dotnet bridge** exists (`build-invocation-ladder.md §B`, rungs #3–#4). Windows-targeted code and MAUI code **build AND run** on the right rung (`cmd.exe /c "dotnet run ..."` / `winrun`). WSL2 forwards `localhost`, so WSL-side Playwright reaches a Windows-side port.
- **The MAUI mobile/desktop runtime bridge** exists for any app that registers it (`core-config.yaml → runtimeVerification.appium`; one-time host setup `WORKFLOW.html §0b`; driver detail `build-invocation-ladder.md §D`). MAUI **Android** runs on an emulator on the Windows host; MAUI **iOS / Mac Catalyst** run on the LAN Mac — both driven over an **Appium** WebDriver endpoint that returns the same screenshot + element tree the gates consume. Appium is the native analogue of Playwright. The MAUI Windows head keeps its FlaUI/Appium-Windows path.

Therefore the following are **NOT acceptable reasons to skip the smoke and push the work onward un-tested.** Each maps to an already-solved capability — saying one of these means you skipped the setup, exactly like logging a wrong-rung build error as a "blocker":

- ❌ "I can't run the app on Linux / WSL."
- ❌ "This app targets Windows, so I can't run it from here."
- ❌ "It's a MAUI app — MAUI can't run on this system."
- ❌ "It's an Android / iOS / Mac Catalyst app — I can't run a mobile/desktop head from WSL." (If the app registered an Appium endpoint, drive it; if it didn't, log that it's unregistered and stamp the head `⚠ STATIC-ONLY` — never silently skip.)
- ❌ "Playwright needs a GUI / there's no browser here."
- ❌ "I'll let the verifier (or the user) smoke it."
- ❌ "The build passed, so it's fine."
- ❌ "It's a multi-service app — the API / DB / LLM endpoint it depends on is down, so I can't run it." (You bring those services up yourself — see below.)

**Escalating to the user is the LAST resort, not the first.** If WSL-side `dotnet run` can't be reached, switch to rung #4 (Windows-side) per the build ladder. If Playwright still can't connect after that, follow `verify-phase.md §3a` (try rung #4, try another port, THEN — only then — ask the user to run the two-line recipe and wait for `go`). Never propose a cloud deploy (banned per verify-phase's Local-only policy). You ask the user to boot the app **only after** the ladder genuinely fails — and you still run the smoke yourself once they reply `go`.

**A multi-service app does not change this — bring the dependent services up yourself.** When the feature needs an API + a web front-end + a database + an LLM endpoint, a dependent service being down is something you **start**, not a blocker you hand to the owner. Read each dependent project's `appsettings*.json` / launch settings for its configured port and URL, then start EACH service yourself **in dependency order** (DB/LLM endpoint first, then API, then web) via the build ladder before concluding you "can't run it". "The stack is down / it's multi-service" is the same banned excuse as "it can't run on Linux" — already-solved by booting the pieces.

**A MAUI mobile head does not change this either — boot the emulator + Appium yourself.** For a MAUI **Android** screen, starting the emulator and the Appium server on the Windows host is YOUR job (run the `runtimeVerification.appium.android.launch` command, e.g. via `winrun`; poll `…/status` until ready — emulators are slow to cold-start, so poll, don't give up). For **iOS / Mac Catalyst**, the LAN Mac's Appium must be reachable (`curl …/status`); that one is a genuine session dependency — if the Mac is down, stamp the head `⚠ STATIC-ONLY` and say so, never a faked pass. Asking the owner is still the LAST resort, after the boot-it-yourself escalation.

**Native-head input goes to the app's OWN window — never to "whatever has focus".** When smoking a MAUI head (Windows/Android/iOS/Catalyst), bind the automation session to the app under test by identity (launched **PID → its top-level window handle** on Windows; the app **package/bundle id** on mobile) and interact **element-by-element via `AutomationId`** inside that bound session. Global keyboard/mouse injection (FlaUI `Keyboard.Type`, coordinate clicks, PowerShell `SendKeys`, `adb shell input` outside the app) is **BANNED** — it types into whichever window happens to hold focus (an IDE, a terminal, a different app), which both corrupts the smoke *and* stomps on the owner's desktop. Full discipline (bind → verify focus → element-scoped input → re-resolve after dialogs): `verify-phase.md §3b`.

## Git is manual — NEVER run git to inspect code or chase a defect

This framework keeps **all** git activity manual: agents never run `git` or `gh` — not to commit, and **not to read**. Do NOT reach for `git diff` / `git log` / `git status` / `git blame` to see "what changed" or to investigate a bug while smoking, verifying, observing, or mapping code. **The harness enforces this mechanically**: `.claude/settings.json` DENIES `git`/`gh`, and the PreToolUse hook `.tfcore/hooks/block-git.sh` blocks compound forms (`cd x && git log`) too. A blocked git call is the policy working — do **not** retry with another git form, and do not treat the block as an obstacle to the task: everything you need is local. Investigate by **reading the working-tree files** at their paths: the files on disk ARE the as-built code, and a finding's evidence is the `file:line` you read, never a diff. (`refresh-status` was de-git-ed for exactly this reason — see `WorkFlow-Context.md`; status/recovery is reconstructed from the checklist tables + files-on-disk + a fresh `dotnet build`, never from commit history.) Sub-agent prompts must carry this rule verbatim — library agents (`/trblazeui`, `/techierag`) never read this file.

## Test users — use the documented/existing ones; NEVER auto-create random smoke users

Smoke and verify runs that create throwaway accounts (`smoketest_user_8472`, `test@test.test`, randomly-named users) **pollute the database** and are banned. The agent has DB access (the connection string lives in `appsettings*.json` / environment config) — use it to find real accounts instead of inventing them. Resolve test credentials in THIS order and stop at the first that works:

1. **`docs/{AppName}-UsageGuide.md` → the "Test users" table** is the canonical registry. Use an account listed there (matching the role the feature needs).
2. **If that account isn't created yet, or there is no UsageGuide:** query the **database directly** with the connection string from config. Read the users/identity table; reuse a suitable existing account. (Read-only — you're looking up credentials, not mutating data.)
3. **If neither yields a usable account: STOP and ASK the user.** Show what you need and what you'd create, e.g. — *"I need an Admin test user to smoke REQ-FN-7. The DB has no admin account and the UsageGuide lists none. Either give me credentials to use, or confirm I should create: `admin@{app}.test` / `Pass!23` (Admin). Create it? (y/n)"* — and wait. Do not proceed on a guess.
4. **Only after explicit confirmation,** create the user(s) — then **record them in `docs/{AppName}-UsageGuide.md`'s Test users table** (mark `Created? = ✅`) so the next phase and the verifier reuse the SAME accounts instead of making new ones.

NEVER invent a throwaway user mid-smoke. NEVER create accounts without the user's confirmation. The UsageGuide Test-users table is the single source of truth for test accounts — every smoke, every verify, and the human UAT all draw from it, so the DB stays clean and reproducible.

## Evidence discipline — state which command actually ran (both harnesses)

When reporting a build, smoke, or verify result, name the exact command and where it ran. Distinguish: WSL `dotnet` vs Windows-host build/run through `winrun`/`cmd.exe` vs native Mac vs container; focused tests vs the full solution build; your self-smoke vs an executed verifier run. **Never convert a successful intermediate command into a full workflow pass.** These are incomplete outcomes, not completion: "build is green; run smoke later" · "bridge exists; user can verify it" · "tests passed" when only focused unit tests ran · "full build blocked" because the wrong ladder rung was used before trying the right one. (This section is the harness-neutral doctrine that also appears in `opencode-operating-contract.md` — this file is the canonical copy, loaded by every build/verify task in both harnesses.)

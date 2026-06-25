# _smoke-test-policy (shared rule — included by every task that builds or verifies code)

## The rule

**Every code change is SMOKE-TESTED by the agent that made it, in this same session, BEFORE it is handed to the verifier or reported as "done".** A green `dotnet build` is NOT a smoke test — it proves the code compiles, not that the feature runs. No build phase chains to the verifier, and no agent says "implemented / done", with un-smoke-tested code. The owner should never have to discover at UAT that a feature was never actually run once.

A smoke test = boot the app (or the relevant host), exercise the changed feature once against the running app, and confirm it reaches the user without an unhandled exception. The per-phase tasks define the exact shape (build-functional §6a, build-ui §4a, build-rag §5a, verify-phase). This file defines the things every one of them must honor: **you run it yourself**, **you confirm the data actually renders**, and **you use real test users**.

## "It runs" means the CONTROLS RENDER THEIR DATA — not just HTTP 200

A page that loads without an exception but shows a **blank table, a count badge over zero visible rows, an empty chart, or a blank value** is a FAILED smoke, not a pass. The most damaging bugs here have been exactly this shape — a screen that "loads" but renders nothing real (a home page whose details table is empty and whose list shows "16" over blank rows), shipped because the smoke only checked that the page opened. So when you smoke or verify a screen:

- For **every data-bound control on the screen you touched** (grid/table/list, chart, detail/value panel), confirm it actually shows data: **rows present AND cells non-empty** (not just a count), chart/series non-empty, value not blank/placeholder. A control hidden by a `@if (x != null)` guard that never appears is render-empty, not "fine".
- Where a DevGuide exists (`docs/{AppName}-DevGuide.md`, or the split set under `docs/devguides/`), it lists the controls each screen must render — use it as the per-control checklist (the verifier formalizes this as the **render gate**, `verify-phase.md §4a/§6`).
- A render-empty/blank control is a defect: log it to the owning `REQ-*` Remarks and do not report the screen "done"/`Verified`.

This is the difference between "the method exists / the page compiled" and "the feature works". Only the latter counts.

## "I can't run it here" is a BANNED excuse — the environment is already set up

The owner did the one-time setup (`WORKFLOW.html §0`) precisely so the agent can smoke-test without help. Two capabilities are PERMANENTLY available on the reference WSL-on-Windows machine:

- **Headless Playwright + system Chromium** are installed in WSL. Browser smoke tests run **headless** — no GUI, no display server needed. (`verify-phase.md §1` also self-heals them if a fresh machine is missing them.)
- **The MAUI / Windows-side dotnet bridge** exists (`build-invocation-ladder.md §B`, rungs #3–#4). Windows-targeted code and MAUI code **build AND run** on the right rung (`cmd.exe /c "dotnet run ..."` / `winrun`). WSL2 forwards `localhost`, so WSL-side Playwright reaches a Windows-side port.

Therefore the following are **NOT acceptable reasons to skip the smoke and push the work onward un-tested.** Each maps to an already-solved capability — saying one of these means you skipped the setup, exactly like logging a wrong-rung build error as a "blocker":

- ❌ "I can't run the app on Linux / WSL."
- ❌ "This app targets Windows, so I can't run it from here."
- ❌ "It's a MAUI app — MAUI can't run on this system."
- ❌ "Playwright needs a GUI / there's no browser here."
- ❌ "I'll let the verifier (or the user) smoke it."
- ❌ "The build passed, so it's fine."

**Escalating to the user is the LAST resort, not the first.** If WSL-side `dotnet run` can't be reached, switch to rung #4 (Windows-side) per the build ladder. If Playwright still can't connect after that, follow `verify-phase.md §3a` (try rung #4, try another port, THEN — only then — ask the user to run the two-line recipe and wait for `go`). Never propose a cloud deploy (banned per verify-phase's Local-only policy). You ask the user to boot the app **only after** the ladder genuinely fails — and you still run the smoke yourself once they reply `go`.

## Test users — use the documented/existing ones; NEVER auto-create random smoke users

Smoke and verify runs that create throwaway accounts (`smoketest_user_8472`, `test@test.test`, randomly-named users) **pollute the database** and are banned. The agent has DB access (the connection string lives in `appsettings*.json` / environment config) — use it to find real accounts instead of inventing them. Resolve test credentials in THIS order and stop at the first that works:

1. **`docs/{AppName}-UsageGuide.md` → the "Test users" table** is the canonical registry. Use an account listed there (matching the role the feature needs).
2. **If that account isn't created yet, or there is no UsageGuide:** query the **database directly** with the connection string from config. Read the users/identity table; reuse a suitable existing account. (Read-only — you're looking up credentials, not mutating data.)
3. **If neither yields a usable account: STOP and ASK the user.** Show what you need and what you'd create, e.g. — *"I need an Admin test user to smoke REQ-FN-7. The DB has no admin account and the UsageGuide lists none. Either give me credentials to use, or confirm I should create: `admin@{app}.test` / `Pass!23` (Admin). Create it? (y/n)"* — and wait. Do not proceed on a guess.
4. **Only after explicit confirmation,** create the user(s) — then **record them in `docs/{AppName}-UsageGuide.md`'s Test users table** (mark `Created? = ✅`) so the next phase and the verifier reuse the SAME accounts instead of making new ones.

NEVER invent a throwaway user mid-smoke. NEVER create accounts without the user's confirmation. The UsageGuide Test-users table is the single source of truth for test accounts — every smoke, every verify, and the human UAT all draw from it, so the DB stays clean and reproducible.

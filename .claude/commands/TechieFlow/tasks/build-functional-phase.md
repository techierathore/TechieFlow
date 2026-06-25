# build-functional-phase

Implement every `REQ-FN-*` and `REQ-NFR-*` in the Functional Checklist, following the project's coding standards. Chain into verifier automatically.

## Purpose

The non-AI backend/business-logic implementation phase. `REQ-RAG-*` items are handled separately by `*build-rag-phase` (techierag agent).

## Inputs

- `{AppName}` argument (required; or resolve from core-config.yaml).

## SEQUENTIAL Execution

### 1. Required reading
1. `docs/{AppName}-Coding-Standards.md` — strict compliance
2. `docs/{AppName}-Architecture.md` — module boundaries
3. `docs/{AppName}-Functional-Checklist.md` — work list

### 2. Scope filtering

Implement ONLY:
- `REQ-FN-*` items
- `REQ-NFR-*` items (perf, security, accessibility, observability)

Skip:
- `REQ-UI-*` (already done by build-ui-phase)
- `REQ-RAG-*` (handled by techierag's build-rag-phase)

### 2a. Re-entry mode detection (FIX mode vs FRESH mode)

Before implementing anything, check if this is a re-run after a verifier FAIL by reading the **Requirements Status** table in `docs/{AppName}-Functional-Checklist.md` (the single source of truth — no separate dated coverage files):

**Terminal statuses — never rebuild, never count as open:** `Verified`, `Done (pre-existing)` (migrated from a dev plan; do NOT re-implement), `N/A`.

- If any `REQ-FN-*` / `REQ-NFR-*` row has Status `FAIL` / `PARTIAL` / `In Progress`: **FIX mode**. Working list = ONLY those REQ IDs. (`Blocked` rows are library gaps — pass through unless their TR entry is marked resolved.)
- If every `REQ-FN-*` / `REQ-NFR-*` row is terminal (or terminal + `Blocked`): nothing to build — say so and update PROJECT-STATUS (§7).
- Otherwise: **FRESH mode**. Working list = all non-terminal, non-`Blocked` `REQ-FN-*` + `REQ-NFR-*` from the Functional Checklist.

Echo one line: `Mode: FIX — N items to repair: REQ-FN-3, REQ-NFR-2` or `Mode: FRESH — N items to implement`. Then continue.

### 3. Dependency analysis + parallel fan-out (MANDATORY — do not skip)

**Single-agent sequential implementation is a banned anti-pattern.** Group the working list into dependency clusters, then fan out clusters in parallel.

Clustering rules:
- Two REQs are in the SAME cluster if they touch the same controller, the same service class, or the same DB table, OR one depends on a type/contract the other defines.
- Two REQs are in DIFFERENT clusters if they share no files and have no contract dependency.
- Aim for 2–5 clusters typical; cap at one cluster per ~3 REQs to keep subagents focused.

Output a one-block cluster table BEFORE fanning out:
```
Cluster A: REQ-FN-1, REQ-FN-2  (User service + UsersController)
Cluster B: REQ-FN-3, REQ-FN-4  (Order pipeline)
Cluster C: REQ-NFR-1           (Logging middleware — independent)
```

Then in ONE assistant turn, spawn **multiple parallel `Agent` calls** (subagent_type=general-purpose, one call per cluster). Each subagent prompt MUST include:
- The cluster's REQ IDs and acceptance criteria (paste verbatim from Functional Checklist).
- Path to `docs/{AppName}-Coding-Standards.md` and the field-prefix rule.
- Architecture module boundaries this cluster lives in.
- Instruction to **commit each REQ with `[REQ-FN-N]` prefix** and add unit tests in `tests/unit/`.
- Instruction to log library issues to the owning library's file — `docs/{AppName}-TrBlazeUI-Feedback.md` or `docs/{AppName}-TechieRag-Feedback.md` (one file per library) — and continue.
- Return contract: summary `{ reqsImplemented[], filesChanged[], testsAdded[], libraryIssues[] }`.

Wait for ALL subagents to return, then aggregate. The orchestrator owns the build + verifier handoff (steps 5–7 below); subagents only own per-cluster implementation.

**Cluster of size 1** still fans out — a single parallel call is fine, the point is the agent operates in its own context window. **Skip parallelism only if the entire working list is a single tight cluster** (e.g. all REQs touch one file). In that case, do the work inline and note "Single-cluster — implemented sequentially."

### 4. Do not modify the UI from build-ui-phase except to wire data/handlers

Service injection, DI registration, callback wiring is fine. Page layout changes are NOT — those belong in the UI phase (`/trblazeui Follow .tfcore/tasks/build-ui-phase.md for the app {AppName}.`).

### 5. Library issue logging

If you hit gaps in TrBlazeUI (only relevant when wiring UI) or TechieRag, log to the OWNING library's feedback file — `docs/{AppName}-TrBlazeUI-Feedback.md` (TR-NNN) or `docs/{AppName}-TechieRag-Feedback.md` (TR-RAG-NNN) — per the schema in `.tfcore/templates/v4custom/app-library-feedback-tmpl.md` (Severity, Repro, Expected, Actual, Encountered in, Workaround, Suggested fix). One file per library; each goes to its own team. Continue with workaround.

### 6. Build (must PASS before self-smoke)

Run the build using the **invocation ladder** at `.tfcore/templates/v4custom/build-invocation-ladder.md`. MANDATORY:

- **Solution-scan first** — if building a `.sln`/`.slnx`, check each referenced `.csproj` for MAUI/iOS/Android markers. ANY MAUI in the solution → start at rung #4 (`cmd.exe /c "dotnet build ..."`), NOT rung #2.
- **Workload errors are wrong-rung signals, not project blockers.** `NETSDK1178`, `Microsoft.iOS.Sdk missing`, `Workload ID ... not recognized` → switch to rung #4 and retry. Do NOT log these as failures.
- **Real compile errors** (CS####, missing source references) → fan out fix subagents (group by file) and retry.
- Do NOT give up on "command not found" — that means you tried the wrong rung.

### 6a. Orchestrator self-smoke (MANDATORY — do not skip)

**Follow `.tfcore/tasks/_smoke-test-policy.md` for this whole section.** Two non-negotiables from it: (1) you run the smoke yourself — "I can't run it on Linux / it targets Windows / it's MAUI / Playwright needs a GUI" are BANNED excuses; the headless-Playwright + Windows/MAUI bridge are already set up (use rung #4 and verify-phase §3a before ever asking the user). (2) For any smoke needing a logged-in user, use a test account from `docs/{AppName}-UsageGuide.md` or the database — NEVER auto-create random smoke users; if none exists, ask the user to confirm before creating, then record it in the UsageGuide.

**The orchestrator does NOT hand off to the verifier on "build PASS" alone.** A green compiler is not proof the code works. Self-smoke first:

1. Boot the app yourself using the build invocation ladder (e.g. `nohup ~/.dotnet/dotnet run --project src/{AppName}.Web --urls http://localhost:5099 > .verify/orch-smoke.log 2>&1 &` — or rung #4 `cmd.exe /c` if WSL dotnet isn't reachable; see [§Local-only deployment policy in verify-phase.md] for the no-cloud rule, which applies here too).
2. Poll `http://localhost:5099` until HTTP 200 or "Now listening on" appears in the log (up to 60s).
3. For EACH REQ implemented this phase, run a **minimal Playwright smoke** — one assertion: the feature is reachable and renders without an unhandled exception. This is NOT the full verifier matrix; it's a "did I obviously break things" gate.
   - REQ touches a page → `await page.goto(...); await expect(page.locator('h1')).toBeVisible();`
   - REQ touches an API endpoint → `await page.request.get(url); expect(response.ok()).toBeTruthy();`
   - REQ is pure backend logic (no HTTP surface) → run the unit test for it: `~/.dotnet/dotnet test --filter "FullyQualifiedName~{TypeName}"`
4. **Fan out the smoke tests across parallel subagents** the same way step 3 fanned out implementation (one subagent per cluster, each runs the cluster's smokes).
5. Kill the boot process. Confirm the port is free.
6. **Write the smoke results into the Requirements Status table** of `docs/{AppName}-Functional-Checklist.md` — do NOT create a `docs/qa/orchestrator-smoke-*.md` file. Per REQ set Status (`Implemented` if smoke PASS pending verifier, `FAIL`/`PARTIAL` otherwise), `%`, and a dated Remark.

**If any smoke FAILed:** loop back into FIX mode (§2a) on the failed REQs. Do NOT chain to the verifier with known smoke failures — that wastes the verifier's run and the user's time.

**If app failed to boot:** apply the local-fallback flow from verify-phase.md §3a (ask user to run the app locally, wait for `go`) — never propose cloud deploy.

### 6b. Chain verifier (only after smoke is clean)

- **How to chain:** read `.tfcore/tasks/verify-phase.md` and execute it inline in THIS session with scope `functional` — the scope is already known, so skip its §0 question entirely. (Do not hand back to the user; the chain is automatic.)
  - Scope: all `REQ-FN-*` + `REQ-NFR-*` + (if RAG done) `REQ-RAG-*` (verify-phase scope `functional`)
  - Output: the verifier writes each REQ's verdict (Status / % / Remarks) **into the Requirements Status table** of `docs/{AppName}-Functional-Checklist.md` — no dated coverage file.
- The verifier ALSO runs the standards-compliance grep checks from `docs/{AppName}-Coding-Standards.md` §"Enforcement". Any underscore-prefix field, mis-prefixed test, or non-`obj` field name gets noted in the offending REQ's Remarks (or a standards row) and reflected in PROJECT-STATUS standards-compliance.
- The verifier reads the current Status table as its baseline — REQs already `Verified` re-confirm fast; it prioritizes the rest. A REQ that smoked PASS but verify FAIL gets its Remark updated to explain the delta.

If verifier reports any `FAIL` items: return to user with the matrix + message: "Fix FAILed REQ-* items by re-running this phase task — it will detect FIX mode automatically and fan out repair subagents."

### 7. FINAL GATE — update PROJECT-STATUS.md (MANDATORY, non-skippable)

**You are NOT done until this is written. Updating `PROJECT-STATUS.md` is the LAST action of every phase, every time — never report completion without it.** (Hard framework rule for all checklist-executing agents; see `.tfcore/tasks/_status-update-gate.md`.)

- **Build status (always update):** `last_verified_build: PASS` and `last_verified_date: {today YYYY-MM-DD}`. If §6's build failed and you somehow advanced anyway, set `FAIL` and add to "Known blockers".
- **Open requirements:** sync the checkbox list to the Functional Checklist Status table — anything not `Verified` stays open.
- If all REQ-* are `Verified`: phase = `Handoff`, next command = `/TechieFlow:agents:flow-master *handoff-phase {AppName}` (OpenCode: `/flow-master *handoff-phase {AppName}`).
- Log a verification-log row (Status table column → `docs/{AppName}-Functional-Checklist.md#requirements-status`).
- Update standards-compliance section.

## Output Checklist

- [ ] All `REQ-FN-*` and `REQ-NFR-*` from Functional Checklist implemented (REQ-UI/RAG untouched)
- [ ] Commits tagged with REQ IDs
- [ ] Unit tests added next to each new service
- [ ] `dotnet build` passes
- [ ] **Cluster table emitted and subagents fanned out in parallel** (or single-cluster note recorded)
- [ ] **Orchestrator self-smoke ran (agent ran it — no "can't run on Linux/Windows/MAUI" excuse); results written into the Functional Checklist Status table** (no `docs/qa/*.md` file) — per `_smoke-test-policy.md`
- [ ] Smoke used a documented/existing test user (UsageGuide table or DB) — NO random smoke-user was auto-created (any new user was confirmed first + recorded in `docs/{AppName}-UsageGuide.md`)
- [ ] **Verifier verdicts written into the Functional Checklist Status table** (Status / % / Remarks per REQ)
- [ ] Library issues (if any) logged
- [ ] Standards-compliance greps clean (or violations noted in Remarks / PROJECT-STATUS)
- [ ] **PROJECT-STATUS.md updated — FINAL GATE (phase, next command, open reqs, log row)**

# build-ui-phase

Implement every `REQ-UI-*` in the UI Checklist using TrBlazeUI, while strictly following the project's coding standards. Chain into verifier automatically when done.

## Purpose

The UI implementation phase. Wraps the trblazeui agent's code-generation work with explicit standards enforcement, REQ-ID commit tagging, and a mandatory verifier chain.

## Inputs

- `{AppName}` argument (required; or resolve from core-config.yaml).

## SEQUENTIAL Execution

### 1. Load required reading

Load these files in order — **never skip**:
1. `docs/{AppName}-Coding-Standards.md` — every line of code you write or modify MUST comply
2. `.trblazeui/TrBlazeUI-AI-Reference.md` — component library reference (if absent, run `dotnet build` once to deploy)
3. `docs/{AppName}-UI-Checklist.md` — work list (REQ-UI-*)
4. `docs/{AppName}-Architecture.md` — respect module boundaries

### 1a. Re-entry mode detection (FIX vs FRESH)

Read the **Requirements Status** table in `docs/{AppName}-UI-Checklist.md` (the single source of truth — there are no separate dated coverage files). **Terminal statuses — never rebuild, never count as open:** `Verified`, `Done (pre-existing)` (migrated from a dev plan; do NOT re-implement), `N/A`. Then:
- Any row `FAIL` / `PARTIAL` / `In Progress` → **FIX mode**, working list = only those REQ IDs. (`Blocked` rows are library gaps — pass through unless the blocking TR entry is marked resolved.)
- Every row terminal (or terminal + `Blocked`) → you are done; say so and update PROJECT-STATUS (§6).
- Otherwise → **FRESH mode**, working list = all non-terminal, non-`Blocked` REQ-UI-* IDs. Echo the mode + count.

### 2. Dependency analysis + parallel fan-out (MANDATORY)

**Single-agent sequential implementation is a banned anti-pattern for UI phase too.** Group REQ-UI-* into clusters:

- SAME cluster if REQs touch the same page, the same shared component, or a shared layout.
- DIFFERENT clusters if they touch independent pages/components.

Emit a cluster table:
```
Cluster A: REQ-UI-1, REQ-UI-2  (Login page)
Cluster B: REQ-UI-3, REQ-UI-4, REQ-UI-5  (Admin grid)
Cluster C: REQ-UI-6           (Settings dialog — independent)
```

Then in ONE assistant turn, spawn parallel `Agent` calls (subagent_type=general-purpose), one per cluster. Each subagent prompt MUST include:
- Cluster's REQ IDs + acceptance criteria verbatim from `docs/{AppName}-UI-Checklist.md`.
- Path to `docs/{AppName}-Coding-Standards.md` + `obj` field prefix rule.
- Path to `.trblazeui/TrBlazeUI-AI-Reference.md`.
- Architecture page/component boundaries.
- Instruction to commit each REQ with `[REQ-UI-N]` and log library issues to `docs/{AppName}-TrBlazeUI-Feedback.md` (one feedback file PER library — TrBlazeUI issues never go in a combined or TechieRag file).
- Return contract: `{ reqsImplemented[], filesChanged[], libraryIssues[] }`.

Wait for all subagents, aggregate, proceed to build + self-smoke. Single tight cluster (everything in one .razor) → do inline and note "Single-cluster — implemented sequentially."

For each REQ within a cluster:
a. Re-read its acceptance criterion.
b. Generate Razor/CSS/component code using TrBlazeUI components per the reference doc.
c. **Apply coding standards** — `obj` instance fields, `a` params, `v` locals, file-scoped namespace, XML docs, no underscores.
d. Commit `[REQ-UI-N]`.

### 3. Library issue logging (continue with workaround, do not stop)

If you hit a gap in TrBlazeUI:
- Missing component → use closest workaround (HTML primitive + TrBlazeUI styling).
- Unclear API → infer from existing usage in the codebase + the reference doc.
- Broken behavior → polyfill in the app code.

Whatever the workaround, append an entry to `docs/{AppName}-TrBlazeUI-Feedback.md` (create from `.tfcore/templates/v4custom/app-library-feedback-tmpl.md` on first issue — one file per library, so the TrBlazeUI team receives only its own list). Each entry has these fields:

```markdown
### TR-NNN — {short title}
- **Severity:** {blocker | major | minor | nice-to-have}
- **Repro:** {minimal code snippet that reproduces}
- **Expected:** {what should happen}
- **Actual:** {what does happen}
- **Encountered in:** REQ-UI-N
- **Workaround:** {what you did in app code}
- **Suggested fix:** {hypothesis for the library team}
```

Do not stop the build for a library issue — workaround + log + continue.

### 4. Build (must PASS before self-smoke)

- Run the build using the **invocation ladder** at `.tfcore/templates/v4custom/build-invocation-ladder.md`. MANDATORY:
  - **Solution-scan first** — `.sln`/`.slnx` containing ANY MAUI/iOS/Android project → start at rung #4.
  - **Workload errors are wrong-rung signals** — `NETSDK1178`, `Microsoft.iOS.Sdk missing`, etc. → switch to rung #4 and retry. Do NOT log as failure.
  - Never accept "command not found" as a stop condition — that means wrong rung, not missing dotnet.
- If REAL compile fails (CS#### errors, missing references in source code), fan out fix subagents per failing file and retry. Do not advance to smoke with a broken build.

### 4a. UI self-smoke (MANDATORY — boot + render check before verifier)

**Follow `.tfcore/tasks/_smoke-test-policy.md` for this section.** You run the smoke yourself — "can't run on Linux / it targets Windows / it's MAUI / Playwright needs a GUI" are BANNED excuses (headless Playwright + the Windows/MAUI bridge are already set up). Any smoke that needs a login uses a test user from `docs/{AppName}-UsageGuide.md` or the database — NEVER auto-create a random smoke user (confirm with the user first, then record it in the UsageGuide).

UI builds compile cleanly even when a Razor component throws at first render. So self-smoke before chaining the verifier:

1. Boot the app with the build invocation ladder. Local-only — never propose cloud deploy (see [verify-phase.md §Local-only deployment policy]).
2. Poll until ready.
3. For each `REQ-UI-N` implemented this phase, run a minimal Playwright smoke (one assertion per REQ — "the page or component renders without exception and the top-level element is visible"). Fan these out across subagents the same way step 2 fanned out implementation.
4. Kill the boot process.
5. **Write results into the Requirements Status table** of `docs/{AppName}-UI-Checklist.md` — do NOT create a `docs/qa/ui-smoke-*.md` file. For each smoked REQ set Status (`Implemented` if smoke PASS pending verifier, `FAIL`/`PARTIAL` if not), `%`, and a dated Remark (one line: what was built / what broke). Playwright failure screenshots stay in `test-results/` (gitignored); only the one-line outcome goes in Remarks.

If any smoke FAILed → loop back into FIX mode (§1a) on the failed REQs. If app failed to boot → ask-user-to-run fallback per verify-phase.md (NEVER propose cloud deploy).

### 5. Chain into verifier (only after smoke is clean)

**How to chain:** read `.tfcore/tasks/verify-phase.md` and execute it inline in THIS session with scope `ui` — the scope is already known, so skip its §0 question entirely. (Do not hand back to the user to run the verifier; the chain is automatic.)
- Scope: all `REQ-UI-*` IDs (verify-phase scope `ui`)
- Output: the verifier writes each REQ's verdict (Status / % / Remarks) **into the Requirements Status table** of `docs/{AppName}-UI-Checklist.md` — no dated coverage file.
- The verifier auto-installs Playwright if needed, boots the app headless, runs tests per REQ ID, and updates the status table.
- The verifier reads the current Status table as its baseline — REQs already `Verified` can be quickly re-confirmed; it focuses on the rest.

If the verifier reports any `FAIL` items, DO NOT terminate — return control to the user with the updated Status table and the message: "Fix the FAILed REQ-UI-* items by re-running `/trblazeui Follow .tfcore/tasks/build-ui-phase.md for the app {AppName}.` — it will detect FIX mode and fan out repair subagents. `Blocked` (library-gap) items pass through."

### 6. FINAL GATE — update PROJECT-STATUS.md (MANDATORY, non-skippable)

**You are NOT done until this is written. Updating `PROJECT-STATUS.md` is the LAST action of every phase, every time — never report completion without it.** (This is a hard framework rule for all checklist-executing agents; see `.tfcore/tasks/_status-update-gate.md`.)

- **Build status (always update):** `last_verified_build: PASS` and `last_verified_date: {today YYYY-MM-DD}`. If `dotnet build` failed at §4 you wouldn't be here — but if you ran a partial build with known compile errors that the verifier accepted, set `FAIL` and log to "Known blockers".
- **Open requirements:** sync the checkbox list to the UI-Checklist Status table — anything not `Verified` stays open.
- If all REQ-UI-* are `Verified` (`Blocked`-by-library counts as pass-through): set current_phase to `Functional build`, "Next command" to `/TechieFlow:agents:flow-master *build-functional-phase {AppName}` — OpenCode: `/flow-master *build-functional-phase {AppName}`. (Or for RAG items: in Claude Code `/techierag` followed by the prompt `Follow .tfcore/tasks/build-rag-phase.md for the app {AppName}.` — techierag is a NuGet-deployed agent, no `*command` syntax.)
- Append a verification-log row (Status table column → `docs/{AppName}-UI-Checklist.md#requirements-status`).
- Update "Library feedback summary" counts.
- Update "Standards compliance" with what verifier reported.

## Output Checklist

- [ ] All `REQ-UI-*` from UI Checklist implemented
- [ ] All commits tagged `[REQ-UI-N]`
- [ ] **Cluster table emitted and subagents fanned out in parallel** (or single-cluster note)
- [ ] `dotnet build` passes
- [ ] **UI self-smoke ran (agent ran it — no "can't run on Linux/Windows/MAUI" excuse); results written into the UI-Checklist Status table** (no `docs/qa/*.md` file) — per `_smoke-test-policy.md`
- [ ] Smoke used a documented/existing test user (UsageGuide table or DB) — NO random smoke-user auto-created
- [ ] **Verifier verdicts written into the UI-Checklist Status table** (Status / % / Remarks per REQ)
- [ ] Library issues (if any) logged to `docs/{AppName}-TrBlazeUI-Feedback.md`
- [ ] **PROJECT-STATUS.md updated — FINAL GATE (phase, next command, open reqs, log row)**

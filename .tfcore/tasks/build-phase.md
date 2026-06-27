# build-phase

The single unified build. Implement every open REQ in `docs/{AppName}-Checklist.md` — UI, functional, RAG, and NFR — then self-smoke (data + visual) and chain the verifier automatically.

## Purpose

There is one build phase for the whole app. `build-phase` (driven by **flow-master**) reads the one checklist, clusters ALL open REQs, and fans the work out — **calling the library agents as sub-agents** rather than as separate phase commands:
- `REQ-UI-*` clusters → built by invoking **`/trblazeui`** as a sub-agent, **from the approved mockups** (`docs/{AppName}-UIDesign.md` + `docs/mockups/*.html`).
- `REQ-RAG-*` clusters → built by invoking **`/techierag`** as a sub-agent.
- `REQ-FN-*` / `REQ-NFR-*` clusters → built directly by flow-master's own general-purpose subagents.

There is no separate `build-ui-phase` / `build-rag-phase` command — those were dissolved; trblazeui and techierag are skills this phase calls.

## Inputs

- `{AppName}` argument (required; or resolve from core-config.yaml).

## SEQUENTIAL Execution

### 1. Required reading
1. `docs/{AppName}-Coding-Standards.md` — strict compliance (`obj` field prefix where the project uses one, `a`/`v` prefixes, no underscores, file-scoped namespace, XML docs)
2. `docs/{AppName}-Architecture.md` — module boundaries
3. `docs/{AppName}-Checklist.md` — the work list (all REQ classes)
4. **The UI design source** — greenfield: `docs/{AppName}-UIDesign.md` + `docs/mockups/*.html` (build UI to match the approved mockups); brownfield: `docs/{AppName}-DevGuide.md` (or the split set under `docs/devguides/`) for the as-built screen map.
5. The library references when their REQ classes are in scope: `.trblazeui/TrBlazeUI-AI-Reference.md` (if absent, run `dotnet build` once to deploy), `.techierag/TechieRag-AI-Reference.md`.

### 2. Scope filtering — ALL open REQs

Working list = every non-terminal REQ in the checklist, all prefixes (UI / FN / RAG / NFR). No prefix is excluded.

### 2a. Re-entry mode detection (FIX vs FRESH)

Read the **Requirements Status** table in `docs/{AppName}-Checklist.md` (the single source of truth — no separate dated coverage files). **Terminal statuses — never rebuild, never count as open:** `Verified`, `Done (pre-existing)` (migrated from a dev plan; do NOT re-implement), `N/A`.

- Any row `FAIL` / `PARTIAL` / `In Progress` / `Needs re-verify` → **FIX mode**, working list = only those REQ IDs. (`Blocked` rows are library gaps — pass through unless the blocking TR entry is marked resolved.)
- Every row terminal (or terminal + `Blocked`) → nothing to build; say so and update PROJECT-STATUS (§7).
- Otherwise → **FRESH mode**, working list = all non-terminal, non-`Blocked` REQs.

Echo one line: `Mode: FIX — N items: REQ-UI-3, REQ-FN-2` or `Mode: FRESH — N items`.

### 3. Dependency analysis + parallel fan-out (MANDATORY — do not skip)

**Single-agent sequential implementation is a banned anti-pattern.** Group the working list into dependency clusters by feature, then fan out clusters in parallel — **routing each cluster to the right builder by its REQ prefix**.

Clustering rules:
- SAME cluster if REQs touch the same page/component/layout (UI), the same controller/service/DB table (FN), the same `TechieRagBuilder`/embedding/`IConversationMemory` (RAG), or one depends on a type/contract the other defines.
- DIFFERENT clusters if they share no files and no contract dependency.
- A cluster is single-prefix where possible so it routes cleanly to one builder. A mixed feature (e.g. a settings page that saves to DB) splits into a UI cluster (REQ-UI) + an FN cluster (REQ-FN) with the FN one depending on the UI contract.

Emit a one-block cluster table BEFORE fanning out, naming the builder per cluster:
```
Cluster A [trblazeui]: REQ-UI-1, REQ-UI-2  (Login page — mockup: docs/mockups/login.html)
Cluster B [flow-master]: REQ-FN-3, REQ-FN-4  (Order pipeline)
Cluster C [techierag]: REQ-RAG-1            (Doc-search RAG flow)
Cluster D [flow-master]: REQ-NFR-1          (Logging middleware)
```

Then in ONE assistant turn, spawn the clusters in parallel:
- **`[trblazeui]` clusters** — invoke `/trblazeui` as a sub-agent (Claude Code `/trblazeui …`, OpenCode `/trblazeui …`). The prompt MUST include: the cluster's REQ-UI IDs + acceptance verbatim from the checklist; **the mockup file(s) the cluster realizes + their component map** (build the screen to match the mockup — same TrBlazeUI controls, same layout); `docs/{AppName}-Coding-Standards.md` + field-prefix rule; `.trblazeui/TrBlazeUI-AI-Reference.md`; commit each REQ `[REQ-UI-N]`; log TrBlazeUI gaps to `docs/{AppName}-TrBlazeUI-Feedback.md` (one file per library); return `{ reqsImplemented[], filesChanged[], libraryIssues[] }`.
- **`[techierag]` clusters** — invoke `/techierag` as a sub-agent. Prompt MUST include: REQ-RAG IDs + acceptance; `.techierag/TechieRag-AI-Reference.md`; coding standards; wire via `TechieRagBuilder` / `ITechieRag` (`IngestAsync`/`SearchAsync`/`AskAsync`/`ChatWithRagAsync`), `ITokenTracker` if an NFR needs it; unit tests in `tests/unit/Rag/`; commit `[REQ-RAG-N]`; log gaps to `docs/{AppName}-TechieRag-Feedback.md` (one file per library); return contract as above + `testsAdded[]`.
- **`[flow-master]` clusters** — spawn general-purpose `Agent` calls (one per cluster). Prompt MUST include: REQ-FN/NFR IDs + acceptance; coding standards + field-prefix rule; architecture boundaries; commit `[REQ-FN-N]`/`[REQ-NFR-N]` + unit tests in `tests/unit/`; log library gaps to the owning library file; return contract.

Wait for ALL sub-agents to return, then aggregate. The orchestrator owns the build + smoke + verifier handoff (§6–§7); sub-agents own per-cluster implementation only. **Cluster of size 1 still fans out.** Skip parallelism only if the entire working list is a single tight cluster — then do it inline and note "Single-cluster — implemented sequentially."

### 4. Library issue logging (continue with workaround, do not stop)

Gaps in TrBlazeUI → `docs/{AppName}-TrBlazeUI-Feedback.md` (TR-NNN); gaps in TechieRag → `docs/{AppName}-TechieRag-Feedback.md` (TR-RAG-NNN). Create from `.tfcore/templates/v4custom/app-library-feedback-tmpl.md` on first issue. One file PER library (separate teams — never combine). Schema: Severity / Repro / Expected / Actual / Encountered in / Workaround / Suggested fix. Workaround + log + continue — never stop the build for a library gap, never silently swallow it.

### 5. Build (must PASS before self-smoke)

Run the build using the **invocation ladder** at `.tfcore/templates/v4custom/build-invocation-ladder.md`. MANDATORY:
- **Solution-scan first** — `.sln`/`.slnx` containing ANY MAUI/iOS/Android project → start at rung #4 (`cmd.exe /c "dotnet build ..."`), not rung #2.
- **Workload errors are wrong-rung signals, not project blockers** — `NETSDK1178`, `Microsoft.iOS.Sdk missing`, `Workload ID … not recognized` → switch to rung #4 and retry. Do NOT log these as failures.
- **Real compile errors** (CS####, missing source references) → fan out fix subagents (group by file) and retry.
- Never accept "command not found" as a stop condition — that means wrong rung, not missing dotnet.

### 6. Self-smoke — data + visual (MANDATORY — do not skip)

**Follow `.tfcore/tasks/_smoke-test-policy.md` for this whole section.** Non-negotiables from it: (1) you run the smoke yourself — "can't run on Linux / it targets Windows / it's MAUI / Playwright needs a GUI / it's multi-service / data is present so it's fine" are BANNED excuses; the headless-Playwright + Windows/MAUI bridge are already set up (use rung #4 and verify-phase §3a before ever asking the user). (2) For any smoke needing a login, use a test account from `docs/{AppName}-UsageGuide.md` or the database — NEVER auto-create random smoke users; if none exists, ask the user to confirm before creating, then record it in the UsageGuide. (3) **"it runs" means the controls RENDER THEIR DATA *and* the screen LOOKS RIGHT** — a blank table is a failed smoke (RENDER-TRUTH) and so is a screen whose controls overlap / clip / sit off-viewport (VISUAL-TRUTH).

**A green compiler is not proof the code works.** Self-smoke before chaining the verifier:

1. Boot the app yourself via the build invocation ladder (local-only — never propose cloud deploy; see verify-phase.md §Local-only deployment policy). Bring up dependent services (DB/LLM/API) yourself in dependency order if it's a multi-service stack.
2. Poll until ready (HTTP 200 or "Now listening on", up to 60s).
3. For EACH REQ implemented this phase, run a **minimal smoke**, fanned out across parallel subagents (one per cluster):
   - UI / page REQ → Playwright: page reachable AND its top-level control **renders its data** (rows present and non-empty, chart non-empty) AND the screen passes the **visual check** — no sibling-control bounding-box overlap, every control in-viewport and non-zero size, at desktop + a mobile width; capture a screenshot and eyeball it; where a mockup exists, it should match the mockup's layout.
   - API REQ → request the endpoint, expect `ok()`; for RAG: ingest→200, search→non-empty, chat→non-empty answer.
   - Pure backend REQ → run its unit test (`~/.dotnet/dotnet test --filter "FullyQualifiedName~{TypeName}"`).
4. Kill the boot process; confirm the port is free.
5. **Write the smoke results into the Requirements Status table** of `docs/{AppName}-Checklist.md` — do NOT create a `docs/qa/*-smoke-*.md` file. Per REQ set Status (`Implemented` if smoke PASS pending verifier; `FAIL`/`PARTIAL`/`Needs re-verify` otherwise), `%`, and a dated Remark (visual failures prefixed `⚠ visual:`). Playwright screenshots stay in `test-results/` (gitignored); only the one-line outcome goes in Remarks.

**If any smoke FAILed (data or visual):** loop back into FIX mode (§2a) on the failed REQs — route layout/overlap failures back to the `[trblazeui]` builder. Do NOT chain to the verifier with known smoke failures.

**If app failed to boot:** apply the local-fallback flow from verify-phase.md §3a (escalate, bring services up yourself, ask the user to run it only as a last resort) — never propose cloud deploy.

### 6b. Chain verifier (only after smoke is clean)

- **How to chain:** read `.tfcore/tasks/verify-phase.md` and execute it inline in THIS session with scope `all` — the scope is known, so skip its §0 question. (Do not hand back to the user; the chain is automatic.)
- Output: the verifier writes each REQ's verdict (Status / % / Remarks) **into the Requirements Status table** of `docs/{AppName}-Checklist.md` — no dated coverage file. It applies BOTH the data render gate (§4a) AND the visual-truth gate (§4b); a REQ is `Verified` only if acceptance passes AND its controls render data AND the screen looks right.
- The verifier ALSO runs the standards-compliance grep checks from `docs/{AppName}-Coding-Standards.md` §"Enforcement". Violations get noted in the offending REQ's Remarks (or a standards row) and reflected in PROJECT-STATUS standards-compliance.
- The verifier reads the current Status table as its baseline — REQs already `Verified` re-confirm fast; it prioritizes the rest.

If the verifier reports any `FAIL` / `Needs re-verify` items: return to the user with the matrix + message: "Fix the flagged REQ-* items by re-running `*build-phase {AppName}` — it detects FIX mode and fans out repair subagents (layout fixes route to trblazeui). `Blocked` (library-gap) items pass through."

### 7. FINAL GATE — update PROJECT-STATUS.md (MANDATORY, non-skippable)

**You are NOT done until this is written. Updating PROJECT-STATUS — BOTH `PROJECT-STATUS.md` AND re-rendered `PROJECT-STATUS.html` — is the LAST action of every phase, every time; a markdown-only update is incomplete (the owner reads the HTML). Never report completion without both.** (Hard framework rule; see `.tfcore/tasks/_status-update-gate.md`.)

- **Build status (always update):** `last_verified_build: PASS` and `last_verified_date: {today YYYY-MM-DD}`. If the build failed and you somehow advanced anyway, set `FAIL` and add to "Known blockers".
- **Open requirements:** sync the checkbox list to the checklist Status table — anything not `Verified` stays open.
- If all REQ-* are `Verified` (`Blocked`-by-library counts as pass-through): phase = `Handoff`, next command = `/TechieFlow:agents:flow-master *handoff-phase {AppName}` (OpenCode: `/flow-master *handoff-phase {AppName}`). Otherwise keep phase `Build`, next command `/TechieFlow:agents:flow-master *build-phase {AppName}` naming the open REQ IDs.
- Log a verification-log row (Status table column → `docs/{AppName}-Checklist.md#requirements-status`).
- Update "Library feedback summary" counts and "Standards compliance".

## Output Checklist

- [ ] All open `REQ-UI/FN/RAG/NFR-*` from the checklist implemented (terminal rows untouched)
- [ ] Commits tagged with REQ IDs; unit tests added
- [ ] `dotnet build` passes
- [ ] **Cluster table emitted naming the builder per cluster; sub-agents (trblazeui / techierag / flow-master) fanned out in parallel** (or single-cluster note)
- [ ] UI clusters built to match the approved mockups
- [ ] **Self-smoke ran (agent ran it — no excuses); DATA-render AND VISUAL checks applied; results in the checklist Status table** (no `docs/qa/*.md` file) — per `_smoke-test-policy.md`
- [ ] Smoke used a documented/existing test user (UsageGuide table or DB) — NO random smoke-user auto-created
- [ ] **Verifier verdicts written into the checklist Status table** (Status / % / Remarks per REQ)
- [ ] Library issues (if any) logged to the owning per-library file
- [ ] Standards-compliance greps clean (or violations noted)
- [ ] **PROJECT-STATUS.md updated — FINAL GATE (phase, next command, open reqs, log row) + re-rendered HTML**

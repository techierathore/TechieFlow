# build-rag-phase

Implement every `REQ-RAG-*` in the Functional Checklist using the TechieRag library.

## Purpose

The AI/RAG/LLM implementation phase. Routed exclusively to the techierag agent.

## How to invoke

Since `/techierag` is a NuGet-deployed free-form persona (not a full TechieFlow agent with `*command` syntax), invoke this task via:

```
/techierag Follow .tfcore/tasks/build-rag-phase.md for the app {AppName}.
```

The techierag agent will read this task file and execute it.

## Inputs

- `{AppName}` — required.

## SEQUENTIAL Execution

### 1. Required reading
1. `docs/{AppName}-Coding-Standards.md` — strict compliance (`obj` field prefix, `a`/`v` prefixes, no underscores)
2. `.techierag/TechieRag-AI-Reference.md` — library reference (if absent, the user needs to run `dotnet build` once with TechieRag NuGet installed)
3. `docs/{AppName}-Functional-Checklist.md` — find all `REQ-RAG-*` items
4. `docs/{AppName}-Architecture.md` — RAG service module boundaries

### 1a. Re-entry mode detection (FIX vs FRESH)

Read the **Requirements Status** table in `docs/{AppName}-Functional-Checklist.md` (the single source of truth — no separate dated coverage files). **Terminal statuses — never rebuild:** `Verified`, `Done (pre-existing)` (migrated from a dev plan; do NOT re-implement), `N/A`. If any `REQ-RAG-*` row has Status `FAIL` / `PARTIAL` / `In Progress` → **FIX mode** (working list = those; `Blocked` rows pass through unless their TR entry is resolved). If every `REQ-RAG-*` row is terminal (or terminal + `Blocked`) → nothing to build; say so and update PROJECT-STATUS (§6). Otherwise **FRESH mode** (all non-terminal, non-`Blocked` REQ-RAG-*). Echo mode + count.

### 2. Dependency analysis + parallel fan-out

Group `REQ-RAG-*` into clusters:
- SAME cluster: REQs sharing a `TechieRagBuilder` configuration, the same embedding provider setup, or the same `IConversationMemory` instance.
- DIFFERENT clusters: independent RAG flows (e.g. "doc search" vs "chat assistant" vs "summarization endpoint").

Many small apps will have a single cluster (one TechieRag instance, multiple consumers) — that's fine; do inline and note "Single-cluster RAG — sequential implementation." Larger apps with multiple RAG flows fan out via parallel `Agent` calls (subagent_type=general-purpose), one per cluster.

Each subagent prompt MUST include:
- Cluster's `REQ-RAG-*` IDs + acceptance criteria.
- Path to `.techierag/TechieRag-AI-Reference.md`.
- Coding standards path.
- Architecture's RAG module boundaries.
- Instruction to use `ITechieRag` interface, log gaps to `docs/{AppName}-TechieRag-Feedback.md` (one feedback file PER library — TechieRag issues never go in a combined or TrBlazeUI file).
- Return contract: `{ reqsImplemented[], filesChanged[], testsAdded[], libraryIssues[] }`.

For each REQ within a cluster (subagent does this work):
a. Re-read acceptance criterion.
b. Wire TechieRag via `TechieRagBuilder` fluent API: embedding provider, vector store, LLM provider, tools, resilience. Pick defaults per Architecture choices.
c. Use `ITechieRag` interface (`IngestAsync`, `SearchAsync`, `AskAsync`, `ChatWithRagAsync`).
d. Token tracking via `ITokenTracker` if `REQ-NFR-*` requires it.
e. Add unit tests in `tests/unit/Rag/`.
f. Commit `[REQ-RAG-N]`.

### 3. Apply coding standards

Every field on TechieRag-related services uses the `obj` prefix:
```csharp
private readonly ITechieRag objRag;
private readonly ITokenTracker objTokenTracker;
private readonly IConversationMemory objMemory;
```

Same for all locals (`v` prefix) and parameters (`a` prefix).

### 4. Library issue logging

TechieRag gaps → `docs/{AppName}-TechieRag-Feedback.md` (create from `.tfcore/templates/v4custom/app-library-feedback-tmpl.md` on first issue) per schema:
```markdown
### TR-RAG-NNN — {short title}
- **Severity:** {blocker | major | minor | nice-to-have}
- **Repro:** {minimal code}
- **Expected:** …
- **Actual:** …
- **Encountered in:** REQ-RAG-N
- **Workaround:** …
- **Suggested fix:** …
```

Continue with workaround; do not stop.

### 5. After all REQ-RAG-* implemented

- Run the build using the **invocation ladder** at `.tfcore/templates/v4custom/build-invocation-ladder.md`. Solution-scan first (MAUI projects → start rung #4); workload errors are wrong-rung signals, not blockers — switch rungs and retry. Never accept "command not found".

### 5a. RAG self-smoke (MANDATORY before handoff)

**Follow `.tfcore/tasks/_smoke-test-policy.md` for this section.** You run the smoke yourself — "can't run on Linux / it targets Windows / Playwright needs a GUI" are BANNED excuses (the headless-Playwright + Windows/MAUI bridge are already set up). Any smoke that needs a login uses a test user from `docs/{AppName}-UsageGuide.md` or the database — NEVER auto-create a random smoke user.

RAG code compiles even when the embedding provider is misconfigured or the vector store is unreachable. Self-smoke:

1. Boot the app via the build invocation ladder. **Local-only — never propose cloud deploy** (see [verify-phase.md §Local-only deployment policy]).
2. For each `REQ-RAG-N`, run a minimal smoke:
   - Ingest endpoint exists → POST a 1-line doc, expect 200.
   - Search endpoint exists → query the ingested doc, expect non-empty results.
   - Chat endpoint exists → ask one trivial question, expect non-empty answer.
   - If RAG is purely embedded (no HTTP surface), run the unit test that exercises `ITechieRag.AskAsync` against a stub LLM.
3. **Write the smoke results into the Requirements Status table** of `docs/{AppName}-Functional-Checklist.md` (Status / % / dated Remark per `REQ-RAG-*`) — do NOT create a `docs/qa/rag-smoke-*.md` file.
4. Kill the boot process.

If smoke FAILs → FIX mode loop. If app won't boot → ask-user-to-run fallback.

### 5b. Handoff

- Hand off to the orchestrator for FN/NFR work, or directly to verifier if RAG is the only outstanding work:
  - If `REQ-FN-*` or `REQ-NFR-*` still pending: tell the user: "RAG work complete. Run `/TechieFlow:agents:flow-master *build-functional-phase {AppName}` (OpenCode: `/flow-master *build-functional-phase {AppName}`) for the remaining FN/NFR items."
  - If RAG is the last category: read `.tfcore/tasks/verify-phase.md` and execute it inline in THIS session with scope `functional` (the scope is known — skip its §0 question; do not hand back to the user).

### 6. FINAL GATE — update PROJECT-STATUS.md (MANDATORY, non-skippable)

**You are NOT done until this is written. Updating `PROJECT-STATUS.md` is the LAST action of every phase, every time — never report completion without it.** (Hard framework rule for all checklist-executing agents; see `.tfcore/tasks/_status-update-gate.md`.)

- **Build status (always update):** `last_verified_build: PASS` and `last_verified_date: {today YYYY-MM-DD}`. (If §5's build failed you'd have fixed it before continuing — if not, log `FAIL` and add to "Known blockers".)
- **Open requirements:** sync the checkbox list to the Functional Checklist Status table — any `REQ-RAG-*` not `Verified` stays open.
- Append a verification-log row noting RAG implementation (Status table column → `docs/{AppName}-Functional-Checklist.md#requirements-status`).
- Update "Library feedback summary" TechieRag counts.
- If RAG was the last category, set current_phase = `Functional verify` and Next command = `/TechieFlow:agents:verifier *verify functional` (OpenCode: `/flow-verifier *verify functional`).

## Output Checklist

- [ ] Every `REQ-RAG-*` from Functional Checklist implemented
- [ ] All commits tagged `[REQ-RAG-N]`
- [ ] Unit tests added next to each RAG service
- [ ] Coding standards respected (verify with grep before declaring done)
- [ ] `dotnet build` passes
- [ ] **RAG self-smoke ran (agent ran it — no "can't run here" excuse); results written into the Functional Checklist Status table** (no `docs/qa/*.md` file) — per `_smoke-test-policy.md`
- [ ] TechieRag issues (if any) logged to `docs/{AppName}-TechieRag-Feedback.md`
- [ ] **PROJECT-STATUS.md updated — FINAL GATE (phase, next command, open reqs, log row)**

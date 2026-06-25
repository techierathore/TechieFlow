# day1-greenfield

Day-1 master task for a GREENFIELD (new) project. Produces all six day-1 deliverables in a single session: target Architecture + BRD + Coding Standards + .editorconfig + PROJECT-STATUS + CLAUDE.md.

## Purpose

Replace the multi-step paste-and-substitute prompt with a single command: `*day1-greenfield {AppName}`. For new projects there's no existing code to reverse-doc; instead the analyst takes a free-form concept (sentence, paragraph, bullets — whatever the user has, even half-baked) and proposes a target architecture + BRD in bulk.

## elicit

elicit=false (after at most a 3-question kickoff). The task asks ONLY for `{AppName}` (if missing), the concept (any length), and optional custom instructions / source-doc hints — then drafts every artifact (including the full BRD) in one pass and presents them for one-shot review. NO per-section confirmation. NO per-requirement confirmation.

## Inputs

- `{AppName}` argument (required). PascalCase, no spaces.
- `{Concept}` — free-form description of the app. **Any length** — single sentence, multiple paragraphs, bulleted list of features, half-baked stream-of-thought notes, mockup descriptions, "kind of like X but with Y" comparisons. The more the user puts in, the better the first-pass BRD. The analyst MUST NOT cap or summarize the user's input — read all of it and use it as the primary source.
- `{Hints}` — OPTIONAL. Free-form text containing any combination of:
  - Paths to existing concept docs, mockups, requirement notes, competitor analyses, napkin sketches converted to text, etc. that should be HARVESTED into the BRD/Architecture.
  - Custom drafting instructions (e.g. "use Blazor WebAssembly not Server", "skip the auth section, this is internal-only", "make it mobile-first", "include offline mode in NFR").
- If `{AppName}` missing: ask once. Then ask once: "Describe the app concept — any length is fine. Sentence, paragraph, bullets, half-baked notes, comparisons to other apps. The more you give, the better the first-pass draft. (No need to be polished; you'll edit the doc afterwards.)" Then ask once (optional): "Any existing notes/mockups/docs to harvest, or specific drafting instructions (stack overrides, scope limits, etc.)? Paths/notes, or `none`."
- All templates live at `.tfcore/templates/v4custom/` in THIS project. Read them with relative paths. Do NOT look outside the project for templates.

## SEQUENTIAL Execution

### 1. Resolve app name + concept + hints + persist config

- Capture `{AppName}`, `{Concept}` (full, untruncated), and `{Hints}` (may be empty).
- Parse `{Hints}` the same way day1-brownfield §1.5 does: paths/globs → `SourceDocs[]` (Read each), instructions → `CustomInstructions` text blob, `none`/empty → both empty.
- **Collision policy:** apply day1-brownfield §1.6 verbatim — every deliverable written fresh at its canonical name; any pre-existing version moves to `docs/OldDocs/` (created if missing, date-suffixed on collision); superseded source docs move there after harvesting; NEVER ask merge-vs-new; NEVER write `-v2`-style variants.
- Update `.tfcore/core-config.yaml` with the `customTechnicalDocuments` paths AND the `devLoadAlwaysFiles` list exactly as in day1-brownfield §1.

### 2. Propose target architecture → `docs/{AppName}-Architecture.md`

- Load `.tfcore/templates/v4custom/app-architecture-tmpl.md` as the structural template.
- Status field: "Target" (this is greenfield).
- **Input priority for every section:**
  1. **`SourceDocs[]`** from §1 (if any) — harvest verbatim where they speak to stack, components, or flows.
  2. **`{Concept}`** — the user's own description is authoritative for goals and feature scope.
  3. **`CustomInstructions`** — overrides defaults (stack, scope, NFR).
  4. **Defaults below** — only when 1–3 are silent on a given choice.
- Pick stack defaults unless the concept or `CustomInstructions` imply otherwise:
  - Runtime: .NET 9
  - UI: Blazor Server with TrBlazeUI (so /trblazeui is in scope)
  - DB: SQLite for dev, configurable per env
  - Vector store: SqliteVec for dev (only if RAG/AI is implied by the concept)
  - Auth: cookie auth for MVP, JWT for API tier if API is in scope
- Populate Mermaid diagrams (component map, primary user journey, deployment) from the concept and any source docs. The richer the concept, the richer the diagrams — a 5-bullet feature list should produce a 5-component diagram, not a 2-box generic placeholder.
- **Depth mandate (Architecture is a HUMAN document):** if `SourceDocs[]` exist, apply the information-preservation rule — their architecture content carries forward, never gets summarized into a stub. Each non-trivial module in §4 gets a short prose paragraph (not just a table row), and any significant runtime flow beyond the primary path (background jobs, ingestion pipelines, auth handshakes, external-API round-trips) gets its own `sequenceDiagram` or `flowchart`. A reader skimming only the diagrams should grasp how the system hangs together.
- Seed §7 ADRs with: `ADR-001 — {chosen UI host}`, `ADR-002 — {chosen DB}`, `ADR-003 — {chosen vector store, if RAG}` — each with a one-line reason that cites the concept/CustomInstructions when relevant.
- **Table of Contents:** the template at `.tfcore/templates/v4custom/app-architecture-tmpl.md` ships with a `## Table of Contents` section. After drafting, regenerate that section to match the actual H2 headings you wrote. Use the slug rule from `.tfcore/templates/v4custom/html-render-shell.md §1` so the links work in both MD and the rendered HTML.
- Write to `docs/{AppName}-Architecture.md`. Do NOT prompt the user mid-draft.

### 3. Draft the FULL BRD in one pass → `docs/{AppName}-BRD.md`

**Do NOT run `author-brd`. Do NOT prompt per section.**

- Load `.tfcore/templates/v4custom/app-brd-tmpl.md`.
- Derive content from (priority order):
  1. **`SourceDocs[]`** from §1 — harvest goals, audience, features verbatim where the source docs speak to them. Cite the source file inline (e.g. `BRD-3 — From design-notes.md §2`).
  2. **`{Concept}`** — this is the user's primary input. Mine it for every feature, actor, and constraint mentioned. If the concept is a bullet list, each bullet probably maps to one or more BRDs. If it's a paragraph, parse sentences for "users should be able to …" / "the app needs to …" patterns.
  3. The target architecture (§2) — every component implies functional requirements.
  4. **`CustomInstructions`** — apply throughout (scope limits, stack overrides, NFR additions).
  5. Reasonable inference for sections still empty. Mark inferred items with `<!-- inferred — please verify -->` HTML comments so the user can scan and confirm.
- **INFORMATION-PRESERVATION RULE (when SourceDocs exist):** the BRD must be a SUPERSET of the requirements content in the harvested docs — never a summary. Tables, matrices, screen lists, persona detail, and per-feature workflows carry forward (updated, attributed), not compressed into one-liners. Length sanity check: a draft under ~60% of the source docs' requirements content means you compressed — go back and restore the detail. One-line statements are allowed ONLY in the §10 ledger; this is a HUMAN document read as rendered HTML (the coding agents get their compact view later from `*split-brd` / the UI-Checklist).
- **§4 Development status (greenfield: this is the build ROADMAP):** fill the §4 table with one row per §9 feature-catalog F-code. Nothing is built yet, so every row is `Planned`, `0%`, with its target Phase (and a one-line Notes scope). Set the "Snapshot as of" date to today. As build phases complete later, the live status lives in PROJECT-STATUS + the checklists; this table stays the human roadmap view.
- **§9 Feature catalog (the heart of the doc):** one `### F-{CODE}: {Name}` subsection per feature/capability area implied by the concept and source docs. Per feature: personas + phase, 1-2 paragraphs of what/why, a screens & routes table (proposed, for greenfield), a numbered workflow (inputs → outputs), and the owning BRD-N IDs. Depth scales with the concept — a rich concept should yield 8–25 features; there is NO cap. Every F-code MUST also appear as a row in the §4 Development status table.
- For §10 Functional requirements ledger: walk the feature catalog and emit `BRD-1`, `BRD-2`, … as one-line `<actor> can <action>` statements, each tagged `(F-CODE)`. **One BRD per discrete capability — the count scales with the concept; NEVER merge capabilities to keep the count low.** Suffix BRDs pulled directly from a source doc with `<!-- from: <source-file> -->`.
- For §11 Non-functional: cover performance, security, accessibility, auth model — derived from the stack you chose in §2 and from any NFR signals in the concept or CustomInstructions. Present concrete targets (latency, uptime, concurrency) as a target table.
- **Mermaid mandate:** the three canonical diagrams (context, user journey, component sketch — copied from the architecture, adapted to BRD framing) are the MINIMUM. Every feature-catalog entry with a multi-step or multi-actor flow gets its own diagram. Simple CRUD features may skip it. **Every diagram MUST follow the authoring rules in `.tfcore/templates/v4custom/html-render-shell.md §5.5` — quote every node/edge/subgraph label and never use `end` as a node id; unquoted special characters in flowchart labels are the #1 cause of broken diagrams in the rendered HTML.**
- Append footer with `Highest BRD ID: BRD-{N}`, a `Sources harvested:` line, a `Custom instructions applied:` line, and the note: "First-pass draft from concept — review and edit. New BRDs may be added (append-only); do not renumber existing IDs."
- **Table of Contents:** the BRD template includes a `## Table of Contents` section. Regenerate it to match the actual H2 headings, and list each `### F-…` feature-catalog entry as an H3 sub-entry under "Feature catalog". Use the slug rule from `.tfcore/templates/v4custom/html-render-shell.md §1`.

### 3.5. Migrate an existing development/phase plan → split requirement docs (CONDITIONAL)

If `SourceDocs[]` includes a phased plan / roadmap (`*Development-Plan*.md`, `*Roadmap*.md`, or content structured as Phase 0/1/2… with build order/statuses), do NOT leave the BRD split as a separate step. Follow day1-brownfield §3.5 exactly: execute `.tfcore/tasks/split-brd.md` inline, seed `docs/{AppName}-UI-Checklist.md` + `docs/{AppName}-Functional-Checklist.md` with the plan's phase tags and any pre-marked completions (`Done (pre-existing)` + evidence pointer), header-note the migration, and — per the §1 collision policy — move the now-superseded plan file unchanged to `docs/OldDocs/` (date-suffix on name collision). If no such plan exists, SKIP — the user runs `*split-brd {AppName}` after reviewing the BRD.

### 4. Create the Coding Standards → `docs/{AppName}-Coding-Standards.md`

Use the exact template content embedded in `day1-brownfield.md` §4 (the canonical block), including its one per-project decision: the instance-field prefix. Greenfield has no existing code to detect from, so default to `obj` unless `CustomInstructions` pick no-prefix. Record the decision in the standards file and CLAUDE.md per §4's instructions.

### 5. Create `.editorconfig` at repo root

Copy `.tfcore/templates/v4custom/app-editorconfig-tmpl.editorconfig` verbatim. No substitution.

### 6. Create `PROJECT-STATUS.md`

Load `.tfcore/templates/v4custom/app-project-status-tmpl.md` and substitute:
- `{AppName}` everywhere
- `{YYYY-MM-DD}` → today
- `stack:` line → from §2's choices
- `current_phase:` → `Discovery`
- `last_verified_build:` → if a `.csproj`/`.sln` exists, run the build using the **invocation ladder** at `.tfcore/templates/v4custom/build-invocation-ladder.md`. Follow the same MANDATORY workflow as day1-brownfield §6:
  - Solution-scan first (check each .csproj for MAUI/iOS/Android targets).
  - Solution containing ANY MAUI/iOS/Android project → start at rung #4.
  - Workload-missing errors (`NETSDK1178`, etc.) are wrong-rung signals — switch rungs, don't log as blocker.
  - BANNED Known-blocker entries: "MAUI build cannot run on WSL", "iOS/Android workload missing", "dotnet not in PATH" — see the ladder doc.
  - Record `PASS`/`FAIL`/`not-run` per the ladder.
  - If no project file exists yet (pure scaffolding), record `not-run` with a Known blocker: "No .csproj/.sln yet — create the solution before next phase." (This IS a real blocker.)
- **Where I am:** one paragraph summarizing the concept and the chosen stack/architecture.
- **Next command to run:** HTML is rendered by this task itself (§7.5) — point at the real next step: `/TechieFlow:agents:analyst *split-brd {AppName}` (or the first build-phase command if §3.5 already split).
- **Open requirements / blockers / verification log / library feedback:** empty (initial values from the template).

### 7. Create `CLAUDE.md`

Copy `.tfcore/templates/v4custom/app-claude-md-tmpl.md` and substitute `{AppName}` throughout.

### 7.4. Create the Usage Guide (test users + test plan) → `docs/{AppName}-UsageGuide.md`

Always create this — follow day1-brownfield §7.4, with the greenfield differences:
- Load `.tfcore/templates/v4custom/app-usageguide-tmpl.md` and substitute `{AppName}`.
- **Test users table:** greenfield has no DB yet, so list the *intended* test accounts — one row per actor/role named in the BRD (§9 feature catalog personas) — all `Created? = ⬜` (planned; created on first build only after confirming with the owner, per `_smoke-test-policy.md`). Do NOT create any users.
- **Screen-by-screen test plan:** one subsection per *proposed* screen/route from the BRD §9 feature catalog's screens-and-routes tables, in navigation order, each naming the test user, the steps, the expected result, and the BRD-N it covers.
- **Setup/Deployment + Test + Smoke + Known limitations:** fill from the chosen stack (§2) at a roadmap level; mark commands that depend on not-yet-built projects clearly. Subject to the §1 collision policy.

### 7.5. Auto-render every day-1 doc to HTML — no separate render step

Follow day1-brownfield §7.5 exactly: render `docs/{AppName}-BRD.md`, `docs/{AppName}-Architecture.md`, `docs/{AppName}-UsageGuide.md`, `PROJECT-STATUS.md` (no-toc + "NEXT COMMAND TO RUN" CTA box), each to its sibling `.html`, using `.tfcore/tasks/generate-html.md` with the shared shell. **Do NOT render the checklists to HTML** — if §3.5 produced them, they stay markdown (AI-agent working documents). Write tool only, no bash heredocs. The user must NEVER be told to run a render command after day-1.

### 8. HALT — summary + next-step pointer

Output a numbered summary listing what was created (same shape as day1-brownfield §8, including the HTML renders). Then say:

```
Day-1 artifacts complete — MD docs AND their HTML renders are all written. Nothing left
to run. Everything was drafted in bulk from your concept (and any source docs / custom
instructions you provided). Review the human-readable docs (open the .html files, or
edit the .md sources directly). The BRD is a first-pass draft — please verify
BRD-1..BRD-{N} reflect actual intent.

If you edit any .md afterwards, re-render just that file:
  /generate-html @docs/{AppName}-BRD.md      (works in Claude Code and OpenCode)

Next workflow step (after your review): *split-brd {AppName} via /TechieFlow:agents:analyst —
unless this run already migrated a phased plan (§3.5), in which case the next step is
the first build phase shown in PROJECT-STATUS.md.
```

Do NOT auto-advance past day-1 (no split/build without the user). Rendering HTML is NOT auto-advancing — it is part of day-1 (§7.5).

## Output Checklist

- [ ] core-config.yaml has customTechnicalDocuments for this app
- [ ] `docs/{AppName}-Architecture.md` (status: Target) with Mermaid
- [ ] `docs/{AppName}-BRD.md` with a §4 Development status table (one row per F-code, all `Planned` for greenfield) + a populated §9 Feature catalog (one `### F-…` per feature) + §10 BRD-N ledger + Mermaid diagrams (canonical three + per-feature where non-trivial), every diagram passing the §5.5 authoring self-check (quoted labels, no `end` ids)
- [ ] If SourceDocs were harvested: BRD is a SUPERSET of their requirements content (no tables/detail dropped)
- [ ] `docs/{AppName}-Coding-Standards.md`
- [ ] `.editorconfig`
- [ ] `PROJECT-STATUS.md` (phase = Discovery)
- [ ] `CLAUDE.md`
- [ ] `docs/{AppName}-UsageGuide.md` — Test-users table (all planned ⬜ for greenfield; NO users created) + screen-by-screen test plan from the BRD feature catalog
- [ ] If a phased plan was among SourceDocs (§3.5): UI-Checklist + Functional Checklist written with phase tags and pre-existing completions — NOT left for a separate `*split-brd` run
- [ ] §7.5 auto-render done: every day-1 .md deliverable has a sibling .html — the user was NOT told to run a render command
- [ ] Summary and next-command pointer delivered
- [ ] Did NOT prompt the user mid-task for per-section confirmation

# day1-greenfield

Day-1 master task for a GREENFIELD (new) project. Produces all day-1 deliverables in a single session: target Architecture + BRD + **UI mockups** + Coding Standards + .editorconfig + PROJECT-STATUS + CLAUDE.md + UsageGuide.

## Purpose

Replace the multi-step paste-and-substitute prompt with a single command: `*day1-greenfield {AppName}`. For new projects there's no existing code to reverse-doc; instead the analyst takes a free-form concept (sentence, paragraph, bullets — whatever the user has, even half-baked) and proposes a target architecture + BRD in bulk.

## elicit

elicit=false (after at most a 4-question kickoff). The task asks ONLY for `{AppName}` (if missing), the concept (any length), optional custom instructions / source-doc hints, and the app size (§1) — then drafts every artifact (including the full BRD) in one pass and presents them for one-shot review. NO per-section confirmation. NO per-requirement confirmation.

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
- **Size and kind (reset Session 3, 2026-09-04):** from the concept, count the routed pages (every page with its own route counts, sign-in included; dialogs and tabs are regions of a page) and the roles, then ask once: "Size: Small (up to 10 screens, one role, 50 requirements), Medium (up to 20 screens, 100 requirements) or Large (split into phases)? I count {N} screens and {N} roles, so I propose {X}." Kind is `app` unless the concept is a library. Write `appSize:` and `appKind:` into `.tfcore/core-config.yaml` and carry both into every document header. The size sets the document budgets and the requirement cap that `bash .tfcore/utils/tf-doc-check.sh` enforces at the status gate.

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
- **Fill the template's sections in its order** (reset Session 3, 2026-09-04; `tf-doc-check.sh` refuses any other shape): **Stack decisions** — one row per stack question, answered from the Stack answer set (`.tfcore/templates/stack-defaults/<set>.md`) or the owner, citing the source; **Solution structure** — one row per project with its kind; **Component map** — one diagram plus the "How a request travels" numbered list in words (no sequence diagram; per-screen detail belongs to the DevGuide later); **Data model** — a mermaid `erDiagram` and an entity table; **Cross-cutting** — identity, configuration, logging, errors, one short paragraph each; **Decisions log** — a row each for the UI host, the database, and every package, with Why and Status. Module responsibilities is required for Medium and Large. No Deployment section (decided after UAT) and no Table of Contents (the renderer builds it).
- If `SourceDocs[]` exist, their architecture content carries forward into these sections, attributed, never summarised away.
- Mermaid: quote every label; never use `end` as a node id.
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
- **INFORMATION-PRESERVATION RULE (when SourceDocs exist):** the BRD must be a SUPERSET of the requirements content in the harvested docs — never a summary. Tables, matrices, screen lists, persona detail, and per-feature workflows carry forward (updated, attributed), not compressed into one-liners. Length sanity check: a draft under ~60% of the source docs' requirements content means you compressed — go back and restore the detail. One-line statements are allowed ONLY in the §10 ledger; this is a HUMAN document read as rendered HTML (the coding agents get their compact view later from `*split-brd` / the Checklist).
- **Fill the template's sections in its order** (reset Session 3, 2026-09-04; `tf-doc-check.sh` refuses any other shape). Header: App, Kind, Size, Stack answer set, Status, Date. **Summary** at most 200 words. **Scope** in and out. **Users and roles** table. **Screens and flow** — one table row per routed page (screen, route, role, mockup link, fields); a dialog is a row under its parent screen with `on /route` in the Route column; then the primary journey as a numbered list. **Requirements** — one `**BRD-N**` item per thing the verifier will test, each naming its screen, linking its mockup, and carrying one acceptance line in the form "When <actor> <does what> on <screen>, then <a result a browser robot can observe>"; ids append-only, never renumbered. **Non-functional requirements** table: the `perf-budget:` measure only where the owner gave a number; the logging requirement from the Stack answer set always. **Development status** — one row per screen, all `Planned` for greenfield; the status gate maintains it afterwards. Context diagram, Constraints and assumptions and Risks are required for Medium and Large only. No Feature catalog, no Table of Contents, no footer.
- **The requirement count stays within the size cap** (Small 50, Medium 100). If the concept needs more, propose a phase split — each phase its own BRD, checklist and build — rather than merging requirements or growing the document. Never merge capabilities to fit.
- If `SourceDocs[]` exist, their requirements carry forward as BRD items (attributed inline), never summarised away.
- Mermaid: quote every label; never use `end` as a node id.

### 3.5. Migrate an existing development/phase plan → split requirement docs (CONDITIONAL)

If `SourceDocs[]` includes a phased plan / roadmap (`*Development-Plan*.md`, `*Roadmap*.md`, or content structured as Phase 0/1/2… with build order/statuses), do NOT leave the BRD split as a separate step. Follow day1-brownfield §3.5 exactly: execute `.tfcore/tasks/split-brd.md` inline, seed the one checklist `docs/{AppName}-Checklist.md` with the plan's phase tags and any pre-marked completions (`Done (pre-existing)` + evidence pointer), header-note the migration, and — per the §1 collision policy — move the now-superseded plan file unchanged to `docs/OldDocs/` (date-suffix on name collision). If no such plan exists, SKIP — the user runs `*split-brd {AppName}` after reviewing the BRD and mockups.

### 3.6. Create UI mockups (greenfield UI design — the build's visual contract)

Greenfield has no code, so the UI is built freehand unless there's a design to build against — that is exactly why a new app's UI ends up broken. Produce **TrBlazeUI-replicable mockups** now so the build (and the verifier's visual-truth gate) have a baseline.

Run `.tfcore/tasks/mockups.md` for `{AppName}` end-to-end: it reads the trblazeui component catalog FIRST (so it designs only with controls that exist), then produces `docs/{AppName}-UIDesign.md` (the per-screen UI Design Spec with a `region → TrBlazeUI control` component map) + rendered `docs/mockups/*.html` (styled to look like TrBlazeUI), one per key screen from the BRD §9 feature catalog. These are the design `/trblazeui` builds from and the image the verifier diffs the live screen against.

The mockups are part of the day-1 review (§8) — the owner approves them alongside the BRD and Architecture before any build. (If the concept is purely an API/no-UI app, `mockups.md` self-detects "no screens" and records "skipped — no UI"; that is not an error.)

### 4. Create the Coding Standards → `docs/{AppName}-Coding-Standards.md`

Load `.tfcore/templates/v4custom/app-coding-standards-tmpl.md` (reset Session 3, 2026-09-04: the standards live in the framework, `.tfcore/standards/coding-standards-core.md` plus `.tfcore/standards/coding-standards-<stack>.md` for the Stack answer set, and are not copied per project). Fill "Standards applied" with those two files and the per-project choices the stack file leaves open (for .NET: the instance-field prefix, default `obj` unless `CustomInstructions` pick no-prefix; record it in CLAUDE.md as before). Leave "Project rules" empty unless the concept demands a rule true of this project alone. Fill "Enforcement" from §5. Run `bash .tfcore/utils/tf-doc-check.sh docs/{AppName}-Coding-Standards.md`; fix any FAIL.

### 5. Create `.editorconfig` at repo root

Copy `.tfcore/templates/v4custom/app-editorconfig-tmpl.editorconfig` verbatim. No substitution.

### 5b. Close the `.gitignore` on the stack you just chose (MANDATORY)

```bash
bash .tfcore/utils/tf-gitignore-audit.sh . --fix
```

**Run it here, in this step, and read the output.** The scaffold wrote a `.gitignore`
covering **TechieFlow's** artifacts — `.tfcore/`, `.claude/`, `node_modules/`,
`tests/.artifacts/`, `playwright-report/`, `logs/` — every section framework-managed
and labelled as such. It says **nothing** about the stack, because at scaffold time
nobody had chosen one. **You just did.** You picked the stack, wrote it into
`core-config.yaml` and generated the solution; you are the only step that knows the
answer, and the file the scaffold left is complete-looking enough to be read as
finished.

That is exactly how it went wrong once (TfLens TF-007, 2026-08-29): a repository whose
`core-config.yaml` and four `.csproj` files said .NET throughout carried an ignore file
with **no `bin/`, no `obj/`, and no rule of any kind for .NET**. The first build produced
output and one commit — named, with some irony, *"Updated git ignore"* — swept **1,041**
build-output files into the index; four later commits reached **1,962**. Those files carry
the static-web-assets manifest, whose content roots are **machine-absolute** (`/mnt/c/…`
after a WSL build, `C:\…` after a Windows one), so committing them ships one machine's
paths to another — a plausible route to precisely the asset 404 that TF-007 is about.

**The agent that ran day-1 generated that file and did not read it. That agent was
responsible**, and the audit exists to make the mistake harder rather than to move the
blame — a generator's omission is not a defence for the agent operating the generator.

Two outputs, and the second one is the one people miss:

- **Missing rules** — `--fix` appends them under their own labelled header. Existing
  owner content is never rewritten.
- **Build output that is ALREADY TRACKED** — reported, never fixed here. **A tracked file
  is never ignored, whatever the ignore file says**, so adding the rule does nothing on
  its own. The audit prints the exact `git rm -r --cached <path>` lines; **put them in
  your §8 summary for the owner to run.** Agents never run git, in any mode.

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
- **Next command to run:** HTML is rendered by this task itself (§7.5) — point at the real next step: `/TechieFlow:agents:analyst *split-brd {AppName}` (OpenCode: `/flow-analyst *split-brd {AppName}`) (or the first build-phase command if §3.5 already split).
- **Open requirements / blockers / verification log / library feedback:** empty (initial values from the template).

### 7. Create `AGENTS.md` (the harness-neutral session memory — both harnesses load it)

Copy `.tfcore/templates/v4custom/app-agents-md-tmpl.md` and substitute `{AppName}` throughout; resolve the field-prefix line to this project's decision. `AGENTS.md` carries the CONTENT (required reading, hard rules, project basics, REQ prefixes, verification, slash-command table): OpenCode auto-loads it directly (and skips `CLAUDE.md` whenever an `AGENTS.md` exists); Claude Code loads it through `CLAUDE.md`'s `@AGENTS.md` import. **`AGENTS.md` is committed.** If a previous `AGENTS.md` exists, archive it per the §1 collision policy and write fresh.

### 7.2. Create `CLAUDE.md` (Claude-only wrapper — imports AGENTS.md)

Copy `.tfcore/templates/v4custom/app-claude-md-tmpl.md` and substitute `{AppName}` throughout. It is a thin wrapper: `@AGENTS.md` plus the Claude-only permissions/tool-preference section. `CLAUDE.md` stays gitignored as before.

### 7.4. Create the Usage Guide (test users + test plan) → `docs/{AppName}-UsageGuide.md`

Always create this — follow day1-brownfield §7.4, with the greenfield differences:
- Load `.tfcore/templates/v4custom/app-usageguide-tmpl.md` and substitute `{AppName}`.
- **Test users table:** greenfield has no DB yet, so list the *intended* test accounts — one row per actor/role named in the BRD (§9 feature catalog personas) — all `Created? = ⬜` (planned; created on first build only after confirming with the owner, per `_smoke-test-policy.md`). Do NOT create any users.
- **Screen-by-screen test plan:** one subsection per *proposed* screen/route from the BRD §9 feature catalog's screens-and-routes tables, in navigation order, each naming the test user, the steps, the expected result, and the BRD-N it covers.
- **Setup/Deployment + Test + Smoke + Known limitations:** fill from the chosen stack (§2) at a roadmap level; mark commands that depend on not-yet-built projects clearly. Subject to the §1 collision policy.

### 7.5. Auto-render every day-1 doc to HTML — no separate render step

Follow day1-brownfield §7.5 exactly: render `docs/{AppName}-BRD.md`, `docs/{AppName}-Architecture.md`, `docs/{AppName}-UsageGuide.md`, `docs/{AppName}-UIDesign.md` (the mockup spec, if §3.6 produced one), `PROJECT-STATUS.md` (no-toc + "NEXT COMMAND TO RUN" CTA box), each to its sibling `.html`, using `.tfcore/tasks/generate-html.md` with the shared shell. (`mockups.md` already rendered the `docs/mockups/*.html` screens.) **Do NOT render the checklist to HTML** — if §3.5 produced it, it stays markdown (AI-agent working document). Write tool only, no bash heredocs. The user must NEVER be told to run a render command after day-1.

### 7a. Emit the run record (telemetry)

Same turn as the status/PROJECT-STATUS write. Doctrine + the ten constraints: `.tfcore/tasks/_metrics-emit-gate.md`. Schema: `.tfcore/telemetry/SCHEMA.md` §2. Stamp `started` with `date -u +%Y-%m-%dT%H:%M:%SZ` as your FIRST action of this task — it cannot be reconstructed at the end.

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"day1-greenfield","mode":null,
 "started":"<start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":[],"reqs_count":0,
 "subagents":[],"files_written":<n>,"build_result":"not-run"}
JSON
```

`reqs_touched` carries REQ IDs only — never requirement text — and `[]` is correct when this task touched no specific REQ. **Telemetry has no veto:** if the emit fails, the phase still succeeded; do not retry, do not diagnose, do not mention it.

### 8. HALT — summary + next-step pointer

Output a numbered summary listing what was created (same shape as day1-brownfield §8, including the HTML renders). Then say:

```
Day-1 artifacts complete — MD docs AND their HTML renders are all written. Nothing left
to run. Everything was drafted in bulk from your concept (and any source docs / custom
instructions you provided). Review and APPROVE the human-readable docs (open the .html
files, or edit the .md sources directly): the BRD (verify BRD-1..BRD-{N} reflect intent),
the Architecture, AND the UI MOCKUPS (open docs/mockups/*.html + docs/{AppName}-UIDesign.md
— this is the visual design the UI will be built to match, so flag any screen that's wrong
NOW, before build). To change a mockup, edit the concept and re-run, or run
*mockups {AppName} --update later.

If you edit any .md afterwards, re-render just that file:
  /generate-html @docs/{AppName}-BRD.md      (Claude Code form; in OpenCode use the plain path without @)

Next workflow step (after you approve the BRD + Architecture + mockups): *split-brd {AppName}
via /TechieFlow:agents:analyst (OpenCode: /flow-analyst) — unless this run already migrated a phased plan (§3.5), in
which case the next step is *build-phase shown in PROJECT-STATUS.md.
```

Do NOT auto-advance past day-1 (no split/build without the user). Rendering HTML is NOT auto-advancing — it is part of day-1 (§7.5).

## Output Checklist

- [ ] core-config.yaml has customTechnicalDocuments for this app
- [ ] `docs/{AppName}-Architecture.md` (status: Target) with Mermaid
- [ ] `docs/{AppName}-BRD.md` in template shape: header with Size and Kind, Screens and flow table, BRD-N ledger with one "When …, then …" acceptance line per item, Development status table (one row per screen, all `Planned`)
- [ ] `appSize` and `appKind` written to `.tfcore/core-config.yaml`
- [ ] `bash .tfcore/utils/tf-doc-check.sh --app {AppName}` prints no FAIL
- [ ] If SourceDocs were harvested: BRD is a SUPERSET of their requirements content (no tables/detail dropped)
- [ ] `docs/{AppName}-UIDesign.md` + `docs/mockups/*.html` produced (§3.6, TrBlazeUI-replicable, one per key screen) — or "skipped — no UI" recorded for an API-only app
- [ ] `docs/{AppName}-Coding-Standards.md`
- [ ] `.editorconfig`
- [ ] `PROJECT-STATUS.md` (phase = Discovery)
- [ ] `CLAUDE.md`
- [ ] `AGENTS.md` (§7.2 OpenCode pointer)
- [ ] `docs/{AppName}-UsageGuide.md` — Test-users table (all planned ⬜ for greenfield; NO users created) + screen-by-screen test plan from the BRD feature catalog
- [ ] If a phased plan was among SourceDocs (§3.5): the one `docs/{AppName}-Checklist.md` written with phase tags and pre-existing completions — NOT left for a separate `*split-brd` run
- [ ] Mockups presented for owner approval in the §8 review (BRD + Architecture + mockups approved before build)
- [ ] §7.5 auto-render done: every day-1 .md deliverable has a sibling .html — the user was NOT told to run a render command
- [ ] Summary and next-command pointer delivered
- [ ] Did NOT prompt the user mid-task for per-section confirmation

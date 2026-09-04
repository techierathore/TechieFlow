# day1-brownfield

Day-1 master task for a BROWNFIELD project. Produces all six day-1 deliverables in a single session: reverse-doc the codebase, plus BRD, Architecture, Coding Standards, .editorconfig, PROJECT-STATUS.md, and CLAUDE.md — each named with the app's prefix. Because a brownfield repo already has built code, the task ALSO generates the screen-by-screen **Developer Guide** (§7.6) — the as-built page → control → service → data-access → proc map — which greenfield day-1 cannot (no code yet). If the project already has a development/phase plan, the task ALSO migrates it into the one checklist (`docs/{AppName}-Checklist.md`) in the same run (§3.5) — no separate `*split-brd` step.

## Purpose

Replace the multi-step paste-and-substitute prompt with a single command: `*day1-brownfield {AppName}`. The task drives the analyst through reverse-doc + scaffolding of all human-facing day-1 artifacts so the user does not have to copy-paste a wall of instructions and manually substitute `<APP>`.

## elicit

elicit=false — this task runs autonomously end-to-end. It asks AT MOST THREE questions (app name if missing, optional source-doc hints, then the size confirmation in §1), then drafts every artifact (including the full BRD) in bulk and presents them for ONE-shot review at the end. NO per-section confirmation. NO per-requirement confirmation. The user reviews the written docs and edits the files directly, or replies with bulk changes.

This is a deliberate departure from TechieFlow's standard `author-brd` per-item elicitation — the user has explicitly opted into a low-friction flow for a one-person team.

## Inputs

- `{AppName}` argument (required). PascalCase, no spaces (e.g. `AppManager`, `AstroLyfe`, `TrTools`).
  - If absent, ask once: "What's the application name for this project? Use PascalCase, no spaces (e.g. AppManager)."
  - Reject names with spaces, hyphens, underscores, or non-letter characters. Re-prompt.
- `{Hints}` — OPTIONAL second argument (or everything after `{AppName}`). Free-form text containing any combination of:
  - Paths to existing requirement / design / spec / functionality docs that should be HARVESTED rather than re-inferred (any naming — `requirements.md`, `Spec.md`, `design-notes.md`, `docs/v1-plan.md`, `README.functional.md`, etc.).
  - Custom drafting instructions (e.g. "focus the BRD on the admin module only", "don't propose JWT — we're keeping cookies", "stack is .NET 8 not .NET 9", "ignore the `legacy/` folder").
  - Anything else the analyst should know going in.
  - If absent in the args, the task asks ONE optional question (§1.5 below). User can reply with hints, or "none", or just press enter to skip.
- All templates live at `.tfcore/templates/v4custom/` in THIS project. Read them with relative paths. Do NOT look outside the project for templates — everything you need is scaffolded locally.

## SEQUENTIAL Execution (do not proceed until current section is complete)

### 1. Resolve and persist the app name

- Capture `{AppName}` from the command argument or the one-question elicitation above.
- Read `.tfcore/core-config.yaml`. If it has a `customTechnicalDocuments` block, ensure the BRD path is `docs/{AppName}-BRD.md`. If it doesn't, add:
  ```yaml
  customTechnicalDocuments:
    brd: docs/{AppName}-BRD.md
    architecture: docs/{AppName}-Architecture.md
    codingStandards: docs/{AppName}-Coding-Standards.md
  ```
  Write the file back. Other TechieFlow tasks read this and use the right paths.
- In the same write, set `devLoadAlwaysFiles` to the project's concrete paths (the stock agents always-load these):
  ```yaml
  devLoadAlwaysFiles:
    - docs/{AppName}-Coding-Standards.md
    - docs/{AppName}-Architecture.md
  ```
- **Size and kind (reset Session 3, 2026-09-04):** count the routed pages in the code (every `@page` route or equivalent counts, sign-in included; dialogs and tabs are regions of a page) and the roles, then confirm once: "Size: Small (up to 10 screens, one role, 50 requirements), Medium (up to 20 screens, 100 requirements) or Large (split into phases)? I count {N} screens and {N} roles, so I propose {X}." Kind is `app`, or `library` for a component or service library. Write `appSize:` and `appKind:` into `.tfcore/core-config.yaml` in the same write and carry both into every document header. The size sets the document budgets and the requirement cap that `bash .tfcore/utils/tf-doc-check.sh` enforces at the status gate.

### 1.5. Discovery hints — harvest existing docs before inferring anything

**First, auto-detect harvest candidates:** Glob `docs/*.md` and repo-root `*.md` (exclude `docs/OldDocs/`, generated `.html`, `CLAUDE.md`, `PROJECT-STATUS.md`, `README.md` unless it contains requirements content). These are the docs available for harvesting.

If `{Hints}` was passed as a command argument, use it (detected docs not excluded by the hints are harvested too). Otherwise ask exactly ONCE (then move on regardless of the answer):

> "I found these existing docs: {numbered list of detected candidates, or '(none)'}.
> Reply `all` (or just press enter) to harvest ALL of them — the default — or list the ones to use.
> You can also add extra paths and/or custom drafting instructions (stack overrides, scope limits, etc.) in the same reply. `none` = harvest nothing, reverse-doc from code alone."

Do NOT ask anything else about existing docs — no merge-vs-new, no keep-vs-overwrite (see §1.6 for the fixed collision policy).

Parse the response:
- **`all` / empty**: every detected candidate goes into `SourceDocs[]`.
- **A selection** (numbers or names from the list): only those go into `SourceDocs[]`.
- **Paths** (anything that looks like a relative or absolute file path): collect into `SourceDocs[]`. For each, attempt to **Read** it. If it exists, capture its content for §2/§3. If it doesn't exist, note it in the summary at §8 and continue (do NOT block).
- **Glob patterns** (e.g. `docs/*.md`): expand with the Glob tool and Read each match.
- **Instructions** (anything that doesn't look like a path): collect into `CustomInstructions` — a single text blob that §2 and §3 must honor when drafting (stack overrides, scope limits, naming preferences, exclusions).
- **`none`** or empty: proceed with code-only inference; record `SourceDocs = []` and `CustomInstructions = (none)`.

This step is **non-blocking** — never re-ask, never elicit per-doc. One question, one parse, move on.

### 1.6. Existing-doc collision policy — fresh canonical docs + OldDocs archive (NO QUESTIONS)

This policy is FIXED. **NEVER ask merge-vs-new or keep-vs-overwrite. NEVER write suffixed variants (`-v2`, `-new`, `-updated`) of any deliverable.** Suffixed variants are what broke HTML rendering and traceability in the past.

- Every deliverable is ALWAYS written fresh at its canonical name (`docs/{AppName}-BRD.md`, `docs/{AppName}-Architecture.md`, etc.).
- **Before writing a deliverable whose target file already exists:** create `docs/OldDocs/` if missing, then MOVE the existing file there unchanged (its sibling `.html`, if any, moves with it). On a name collision inside `OldDocs/`, append `-{YYYY-MM-DD}` to the moved file's name; if still colliding, `-2`, `-3`, …
- This applies to all day-1 deliverables, including root-level `PROJECT-STATUS.md` and `CLAUDE.md` (archived as `docs/OldDocs/PROJECT-STATUS.md` etc.). Exception: `.editorconfig` is machine config, identical across projects — overwrite in place, no archive.
- **Superseded source docs move too:** after §2/§3 (and §3.5 if it runs) complete, move each harvested source doc whose ROLE is now filled by a new deliverable (old BRDs/requirement specs, old architecture/design notes, dev/phase plans after migration) into `docs/OldDocs/`. Docs that remain independently authoritative (API usage guides, setup/ops guides, third-party integration notes) STAY in `docs/` — they were harvested as input, not replaced.
- List every moved file in the §8 summary (`archived to docs/OldDocs/: …`) so nothing disappears silently.

Net effect: `docs/` always contains exactly one current version of each doc under its canonical name; history lives in `docs/OldDocs/`; render/split/build tasks never face variant ambiguity.

### 2. Reverse-document the codebase → `docs/{AppName}-Architecture.md`

- Load `.tfcore/templates/v4custom/app-architecture-tmpl.md` as the structural template. Substitute `{AppName}` and `{YYYY-MM-DD}` throughout.
- Status field: "Current" (this is brownfield).
- **Source-doc harvesting (do this FIRST, before any inference):**
  - If `SourceDocs[]` from §1.5 contains anything that reads as architecture / design / system / data-flow material, harvest from it directly: copy structural prose verbatim (with attribution), pull diagram intent, map their components to your §4 module table. Do not re-invent what the user already wrote.
  - Attribute harvested content inline; there is no "Sources harvested" section (the run record carries the list).
- **Apply `CustomInstructions`** from §1.5 throughout — if the user said "stack is .NET 8", use .NET 8 in §1; if they said "ignore `legacy/`", skip that folder in the scan.
- Populate the template's sections, in its order, by SCANNING the codebase (only for what the source docs didn't cover; reset Session 3, 2026-09-04 — `tf-doc-check.sh` refuses any other shape):
  - **Stack decisions:** one row per stack question, answered from the project files (`.csproj`/`.sln`, package references, target frameworks, configuration files) and the Stack answer set where the code agrees with it; cite the source per row.
  - **Solution structure:** one row per project with its kind (web app, class library, test project, migrations project) and purpose.
  - **Component map:** a `flowchart TB` of project-level dependencies from `<ProjectReference>` and `using` directives, then the "How a request travels" numbered list in words for the primary path (controller → service → data access). No sequence diagram; per-screen detail goes to the DevGuide (§7.6).
  - **Data model:** a mermaid `erDiagram` and an entity table from the migrations project, entity classes or schema scripts.
  - **Cross-cutting:** logging library, auth scheme, configuration mechanism, error handling — from package references and startup code.
  - **Decisions log:** a first row `current stack as-is (reverse-doc baseline)`, Status `decided`; any structural change the BRD (§3) calls out is a row with Status `planned` naming its BRD item. There is no Target architecture section.
  - **Module responsibilities** (required for Medium and Large): one row per project, from top-of-namespace docs or README.
  - **Open questions:** the field-prefix drift finding (below) and any TODOs / FIXMEs that look architectural. No Deployment section: hosting is decided after UAT.
- Source-doc architecture content carries forward into these sections, attributed, never summarised away.
- **Field-prefix drift detection:** scan `src/`, `source/`, or any `.cs` files for instance-field declarations and note the dominant style (`obj`-prefixed vs bare PascalCase vs `_underscore`/mixed) — §4 uses this to pick the project's field convention. If no style reaches ~80% dominance, add to Open questions: "Standards drift detected — mixed instance-field naming (N obj / M bare / K underscore). §4 picked {chosen}; remediation happens incrementally during implementation."
- Mermaid: quote every label; never use `end` as a node id. No Table of Contents (the renderer builds it).
- Write the populated doc to `docs/{AppName}-Architecture.md`.

### 3. Draft the FULL BRD in one pass → `docs/{AppName}-BRD.md`

This is the friction-removal step. **Do NOT run `author-brd`. Do NOT prompt the user per section.** Instead:

- Load `.tfcore/templates/v4custom/app-brd-tmpl.md` as the structural template. Substitute `{AppName}` and `{YYYY-MM-DD}` throughout.
- **Source-doc harvesting takes precedence over inference.** Populate every section in this priority order:
  1. **`SourceDocs[]` from §1.5** — if the user provided existing requirement / spec / functionality docs, harvest from them FIRST. Pull goals, audience, features verbatim where possible. Convert any "the system shall …" / "user can …" prose into numbered `BRD-N` items. Cite the source file inline (e.g. `BRD-7 — From requirements.md §4`).
  2. The reverse-doc from §2 (what the codebase ALREADY does — fills gaps the source docs didn't cover).
  3. README / `docs/` contents (project intent, goals, audience — only for fields still empty after 1 and 2).
  4. Reasonable inference for sections that have no signal anywhere (mark these with `<!-- inferred — please verify -->` HTML comments).
- **Apply `CustomInstructions`** from §1.5 — if the user said "focus on admin module only", scope BRDs accordingly; if "skip auth", omit auth BRDs even if the codebase implements them.
- **INFORMATION-PRESERVATION RULE (hard requirement when SourceDocs exist):** the new BRD must be a SUPERSET of the requirements content in the harvested source docs — never a summary of it. Concretely:
  - Every table, matrix, screen inventory, route list, license/feature matrix, navigation-menu tree, persona-detail block, and per-feature workflow in a source BRD/spec **carries forward** into the new doc (updated where stale, attributed where copied) — it does NOT get compressed into a one-liner.
  - **Length sanity check before writing:** if the source docs' requirements content totals X lines and your draft (excluding boilerplate) is under ~60% of X, you compressed — go back and restore the detail. A 1,000-line source BRD should never produce a 250-line replacement.
  - Source requirements become BRD items; the Requirements ledger is where one-line statements live, and each item still carries its screen, mockup link and acceptance line.
- **Fill the template's sections in its order** (reset Session 3, 2026-09-04; `tf-doc-check.sh` refuses any other shape). Header: App, Kind, Size, Stack answer set, Status, Date. **Summary** at most 200 words. **Scope**. **Users and roles**. **Screens and flow** — one table row per routed page found in the code (screen, route, role, mockup link where a mockup exists, fields); a dialog is a row under its parent screen with `on /route` in the Route column; then the primary journey as a numbered list. **Requirements** — one `**BRD-N**` item per thing the verifier will test, each naming its screen, linking its mockup, and carrying one acceptance line "When <actor> <does what> on <screen>, then <observable result>"; ids append-only, never renumbered; a source-doc item is attributed inline. **Non-functional requirements** table: the `perf-budget:` measure only where the owner stated a number; the logging requirement from the Stack answer set always, recorded as met when the §2 scan found it wired. **Development status** — one row per screen with Verified / Open counts from the strongest evidence (a migrated plan first, then the code scan); the status gate maintains it afterwards. Context diagram, Constraints and assumptions and Risks are required for Medium and Large only. No Feature catalog, no Table of Contents, no footer.
- **The requirement count stays within the size cap** (Small 50, Medium 100). If the code holds more, propose a phase split — each phase its own BRD, checklist and build — rather than merging requirements or growing the document.
- Mermaid: quote every label; never use `end` as a node id.
- Write the populated doc to `docs/{AppName}-BRD.md`.

### 3.5. Migrate an existing development/phase plan → split requirement docs (CONDITIONAL)

**Trigger:** any doc among `SourceDocs[]` or in `docs/` matching dev-plan patterns — `*Development-Plan*.md`, `*Dev-Plan*.md`, `*Implementation-Plan*.md`, `*Roadmap*.md`, or any doc whose content is a phased plan (Phase 0/1/2…, sprint list, feature-by-feature build order with statuses).

**If no such doc exists, SKIP this section entirely** — the user runs `*split-brd {AppName}` later, after reviewing the BRD (the normal flow).

**If a dev plan EXISTS, do NOT leave the split as a separate step** — the plan already validates the requirements, so migrate it now:

- Execute the logic of `.tfcore/tasks/split-brd.md` inline (read that file and follow §2–§4): classify every `BRD-N` from §3 into `REQ-UI-*` / `REQ-FN-*` / `REQ-RAG-*` / `REQ-NFR-*` and write the one checklist `docs/{AppName}-Checklist.md` (all prefixes in a single Requirements Status table).
- **Seed from the dev plan (the migration part) — preserve EVERY column the plan tracked.** The plan's own status table is the gold standard; the new **Requirements Status** table (top of the checklist) must be a SUPERSET of it, never a lossy summary:
  - Carry the plan's phase structure into both docs — tag each REQ with its phase (e.g. `**REQ-FN-007** — … (BRD-21, Phase 1)`), and order sections by phase.
  - Fill ALL columns of the Status table for each migrated REQ: **Status**, **%**, **Remarks**, **Details** link. If the old plan had a `% Done` column, carry the number verbatim; if it had a Status/Remarks column with dates and detail (e.g. "Completed 2026-04-30 (DTOs split…)"), carry that whole remark into **Remarks** — do NOT truncate it.
  - COMPLETE / done / shipped → Status `Done (pre-existing)`, `%` = the plan's figure (usually `100%`), Remarks = the plan's completion note + `per {plan-file} §{section}`. Build agents must NOT rebuild these.
  - Partial items (e.g. "50% Scaffolded") → Status `In Progress` or `PARTIAL`, carry the plan's `%` and remark verbatim.
  - Not-yet-started items → Status `Not Started`, `0%`.
  - Add a header note to both docs: `> Migrated from {plan-file} on {YYYY-MM-DD}. Phase structure, completion %, and status remarks carried over verbatim — verify before building.`
- **Keep the BRD Development status table consistent with this migration:** its per-screen rows must agree with the per-REQ statuses you just wrote (all `Done (pre-existing)` → `Done`; mixed → `Partial`; none started → `Planned`). The checklist is the live per-REQ truth; the BRD table is the human snapshot of the same reality.
- Do NOT modify the dev-plan file's content. After migration it is superseded — move it to `docs/OldDocs/` per §1.6 and say so in the §8 summary.
- If the `*split-brd` artifact (`docs/{AppName}-Checklist.md`) already exists (re-run scenario), apply §1.6: archive the old one to `docs/OldDocs/`, write fresh at the canonical name. No questions.

### 4. Create the Coding Standards → `docs/{AppName}-Coding-Standards.md`

Load `.tfcore/templates/v4custom/app-coding-standards-tmpl.md` (reset Session 3, 2026-09-04: the standards themselves now live in the framework and are not copied per project).

- The standards are `.tfcore/standards/coding-standards-core.md` (every project) plus `.tfcore/standards/coding-standards-<stack>.md` for the Stack answer set named in the Architecture (`dotnet` for the .NET set). List both under "Standards applied".
- **One per-project choice for .NET — the instance-field prefix.** Use the drift scan from §2: if ≥80% of instance fields are `obj`-prefixed or ≥80% bare PascalCase, adopt that style; `{Hints}` / CustomInstructions override; otherwise default to `obj`. Record it in the "Standards applied" choices table and in CLAUDE.md (§7).
- "Project rules" holds only rules that are true of this project alone (a mixed MAUI build invocation is the kind of thing that belongs here). Empty is a valid answer.
- "Enforcement" names the `.editorconfig` (§5), the analyzers in use, and any project-specific grep beyond the stack file's.
- Run `bash .tfcore/utils/tf-doc-check.sh docs/{AppName}-Coding-Standards.md`; fix any FAIL.

### 5. Create `.editorconfig` at the repo root

Copy `.tfcore/templates/v4custom/app-editorconfig-tmpl.editorconfig` verbatim to `.editorconfig` at the repo root. No substitution — the rules are identical across projects.

### 5b. Close the `.gitignore` on the stack this repo is written in (MANDATORY)

```bash
bash .tfcore/utils/tf-gitignore-audit.sh . --fix
```

**Run it here, in this step, and read the output.** The scaffold wrote a `.gitignore`
covering **TechieFlow's** artifacts — `.tfcore/`, `.claude/`, `node_modules/`,
`tests/.artifacts/`, `playwright-report/`, `logs/` — every section framework-managed
and labelled as such. It says **nothing** about the stack the project is written in.
On brownfield that stack is already on disk and you have just spent §2–§4 reading it,
so you are the step that knows the answer — and the file the scaffold left is
complete-looking enough to be read as finished. Existing repos are the likelier
offenders here, not the safer ones: the build output may already be committed.

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

### 6. Create `PROJECT-STATUS.md` at the repo root

Load `.tfcore/templates/v4custom/app-project-status-tmpl.md` and substitute:
- `{AppName}` everywhere
- `{YYYY-MM-DD}` → today
- `stack:` line → from §2 detection (e.g. `.NET 9 / Blazor Server / TrBlazeUI`)
- `last_verified_build:` → run the build using the **invocation ladder** at `.tfcore/templates/v4custom/build-invocation-ladder.md`. MANDATORY workflow:
  1. **Platform probe FIRST** — Read ladder §0. In OpenCode Docker, prove `winrun "dotnet --info"` before building. Then scan the `.sln`/`.slnx` file. A Windows MAUI project uses `winrun "dotnet build <slnx>"`; a standard .NET solution uses container `dotnet build`. Do not check/install `maui-tizen`.
  2. **Symptom-based escalation** — if a build fails with `NETSDK1178`, `Microsoft.iOS.Sdk` missing, `Microsoft.Android.Sdk` missing, `Workload ID not recognized`, or any workload-related error → you are on the WRONG RUNG. In Docker use `winrun` for the Windows head; in WSL switch to rung #4. Do NOT log workload errors as Known blockers.
  3. Try rungs 1-5 in order; do NOT report `not-run` unless ALL five rungs genuinely failed (workload errors don't count — they're wrong-rung signals).
  4. Record `PASS`, `FAIL`, or `not-run` per the ladder's rules. If `FAIL` from a REAL compile error (CS#### codes, missing source references), add a one-line summary to "Known blockers".
  5. **BANNED Known-blocker entries** (these are wrong-rung confessions, not project issues — see the ladder doc's "What NEVER goes into Known blockers" section): "MAUI build cannot run on WSL", "NETSDK1178 workload missing", "iOS/Android SDK missing", "dotnet not in PATH". If you wrote one of these, you didn't follow the ladder. Switch rungs and rebuild.
  6. If the solution mixes MAUI + non-MAUI projects: log the per-platform result for transparency, e.g. "standard projects build in the container; Windows MAUI project builds through `winrun`; solution-level build uses `winrun`."
- `last_verified_date:` → today
- `current_phase:` → `Discovery`; if §3.5 ran (dev plan migrated), use `Discovery — requirements split done; next build phase: {first incomplete phase from the dev plan}` instead.
- **Where I am:** one paragraph from §2's findings — what exists, what state it's in. If §3.5 ran, include which dev-plan phases are already complete.
- **Next command to run:** HTML is rendered by this task itself (§7.5), so point at the real next step: `/TechieFlow:agents:analyst *split-brd {AppName}` (OpenCode: `/flow-analyst *split-brd {AppName}`) — or, if §3.5 ran (split already done), `/TechieFlow:agents:flow-master *build-phase {AppName}` (OpenCode: `/flow-master *build-phase {AppName}`) (the unified build; it calls trblazeui/techierag itself). **NEVER set `*verify all` as the day-1 next command** — day-1 has verified nothing and a brownfield repo virtually always has unbuilt/PARTIAL features in the freshly-migrated checklist; per the Build → Verify → Handoff ladder (`_status-update-gate.md` item 5), the next step after a brownfield day-1 is `*split-brd` (to create the checklist) or, once the checklist exists, `*build-phase` (to finish building). Verification comes only after the build is substantially complete.
- **Open requirements:** empty list — populated later by `*split-brd`. If §3.5 ran, list the REQ-* counts per type with phase tags (already populated; `*split-brd` is NOT needed).
- **Known blockers:** from §2 (build failure, standards drift, etc.) — otherwise "None".
- **Verification log:** empty table with headers only.
- **Library feedback summary:** both libraries `0 major, 0 minor` initially.
- **Standards compliance:** "not yet run".
- **Deferred / future:** empty.

### 7. Create `AGENTS.md` at the repo root (the harness-neutral session memory — both harnesses load it)

Copy `.tfcore/templates/v4custom/app-agents-md-tmpl.md` and substitute `{AppName}` throughout. Resolve the field-prefix line to THIS project's §4 decision, e.g.: "Field-prefix convention: `obj` prefix on instance fields (e.g. `private readonly ILogger<X> objLogger;`) — see Coding Standards." or "...bare PascalCase, no prefix — see Coding Standards."

`AGENTS.md` carries the CONTENT (required reading, hard rules, project basics, REQ prefixes, verification, slash-command table): OpenCode auto-loads it directly (and skips `CLAUDE.md` whenever an `AGENTS.md` exists); Claude Code loads it through `CLAUDE.md`'s `@AGENTS.md` import. **`AGENTS.md` is committed** (it is NOT in the gitignored framework block). If a previous `AGENTS.md` exists, archive it per the §1.6 collision policy and write fresh.

### 7.2. Create `CLAUDE.md` (Claude-only wrapper — imports AGENTS.md)

Copy `.tfcore/templates/v4custom/app-claude-md-tmpl.md` and substitute `{AppName}` throughout. It is a thin wrapper: `@AGENTS.md` (Claude resolves the import) plus the Claude-only permissions/tool-preference section. `CLAUDE.md` stays gitignored as before.

### 7.4. Create the Usage Guide (test users + test plan) → `docs/{AppName}-UsageGuide.md`

Always create this — it is the canonical registry of **test users** and the screen-by-screen **test plan** that every later smoke/verify run (and the human UAT) draws from, so the pipeline never invents throwaway accounts (`.tfcore/tasks/_smoke-test-policy.md`).

- Load `.tfcore/templates/v4custom/app-usageguide-tmpl.md` and substitute `{AppName}`.
- **Test users table:** this is a brownfield app, so the DB may already have accounts. Locate the connection string (`appsettings*.json` / env config) and, if reachable, read the users/identity table and list the **existing** accounts (one row per distinct role) with `Created? = ✅`. Do NOT dump real production passwords you can't see — where a password is unknown, note "{existing — ask owner}" and leave `Created?` ✅. If the DB isn't reachable or has no users, list the *intended* test accounts (one per role from the BRD's actors) as `Created? = ⬜` (planned, to be created with confirmation on first build). **Do NOT create any users in this step.**
- **Screen-by-screen test plan:** one subsection per screen/menu found in §2's reverse-doc (and the §9 BRD feature catalog), in navigation order, each naming the test user to log in as, the steps, the expected result, and the BRD-N/REQ-* it covers. Cover every feature.
- **Setup/Deployment + Test + Smoke + Known limitations:** populate from §2 detection (same runbook discipline as handoff — one command per line, omit inapplicable steps).
- Write to `docs/{AppName}-UsageGuide.md` (subject to the §1.6 collision policy like every other deliverable).

### 7.5. Auto-render every day-1 doc to HTML — no separate render step

Render the deliverables to HTML NOW, in this same run, by following `.tfcore/tasks/generate-html.md` (which applies the shared shell at `.tfcore/templates/v4custom/html-render-shell.md` — copy buttons, mermaid toolbar, TOC, slug rule):

- `docs/{AppName}-BRD.md` → `docs/{AppName}-BRD.html`
- `docs/{AppName}-Architecture.md` → `docs/{AppName}-Architecture.html`
- `docs/{AppName}-UsageGuide.md` → `docs/{AppName}-UsageGuide.html`
- `PROJECT-STATUS.md` → `PROJECT-STATUS.html` (use `layout no-toc`; include the "NEXT COMMAND TO RUN" call-to-action box per render-workflow-docs §5)

**Do NOT render the checklist to HTML.** If §3.5 produced `docs/{AppName}-Checklist.md`, leave it as markdown — it is an AI-agent working document, never rendered (HTML mirrors of agent docs only burn tokens and drift).

Use the Write tool — NOT bash heredocs. The user should NEVER have to run a render command after day-1; rendering is idempotent, so post-review edits are handled by a quick re-render (`/generate-html @docs/{file}.md`).

### 7.6. Generate the Developer Guide (brownfield has as-built code → map it NOW)

A brownfield project already has built code, so the screen-by-screen **Developer Guide** — the doc a human uses to chase bugs and catch AI-hallucinated code from page → control → service → data-access → stored proc / query — can and SHOULD be produced at day-1, not deferred to handoff. (Greenfield day-1 has no code, so it has no equivalent step; brownfield does — this is the brownfield-only step that closes the "verifier passed but it's still buggy" gap on day one.)

- Run `.tfcore/tasks/devguide.md` for `{AppName}` (the `*devguide {AppName}` task) and follow it end-to-end: discover roles/menus/screens (it reads the §7.4 UsageGuide test-users table + code authorization), **fan out per role** to bound tokens, map each screen's controls + full data lineage, verify every path is a real symbol (`{unresolved — TODO}` rather than an invented proc name), apply **LANDING-TRUTH** + **RENDER-TRUTH**, and render the markdown + sibling `.html` (single `docs/{AppName}-DevGuide.md`, or an index + per-role files under `docs/devguides/` for a large app — the task auto-decides per its §3).
- **Self-guard:** if the repo turns out to be doc-only (no built UI/code — unusual for brownfield, but possible when day-1 is run before any code lands), the devguide task HALTs itself. Record "DevGuide skipped — no built code yet (run `*devguide {AppName}` after the first build phase)" in the §8 summary and move on; do NOT treat it as an error.
- **OBSERVE pass (devguide §5a):** the devguide attempts to boot the app and runtime-observe each control. At day-1 the app's stack is often not up yet, so the guide will commonly be stamped **`⚠ STATIC-ONLY — NOT runtime-verified`** — that is EXPECTED and acceptable here; do NOT block day-1 trying to bring a stack up. The user runs `*verify {scope}` / `*devguide {AppName} --update` later (once the stack is up) to runtime-confirm render-status.
- **Screenshot capture + owner visual-review (devguide §5a/§5b):** the OBSERVE pass captures a screenshot of every screen to `docs/screenshots/{AppName}/` and embeds it in the DevGuide. At day-1 this is usually non-interactive (chained, no live Q&A), so the devguide skips the live "what needs to change?" gate but still captures the shots — **tell the user in §8 to review `docs/screenshots/{AppName}/` and run `*fix-issues {AppName} {folder}` (or `*devguide {AppName} --update`) for any screen that's wrong.** This is how the broken-UI problem surfaces on day-1. (If the stack can't boot, the guide is STATIC-ONLY and no screenshots are captured — noted below.)
- **Defect logging (devguide §6a) depends on the checklist existing — handle both branches:**
  - **If §3.5 ran** (a dev plan was migrated → `docs/{AppName}-Checklist.md` exists): the devguide logs every confirmed defect into the owning `REQ-*`'s Remarks (and flags `Needs re-verify` where the feature is actually broken) per its §6a — markdown only, never checklist HTML.
  - **If §3.5 did NOT run** (no checklist until `*split-brd`): the devguide cannot map screen → `REQ-*` yet, so its findings stay in the DevGuide's own "Known issues" prose. **Tell the user in §8** to run `*devguide {AppName} --update` immediately AFTER `*split-brd` so those findings get pushed into the freshly-created checklist (otherwise the day-1 defects are lost when the verifier later trusts a clean checklist).

### 7a. Emit the run record (telemetry)

Same turn as the status/PROJECT-STATUS write. Doctrine + the ten constraints: `.tfcore/tasks/_metrics-emit-gate.md`. Schema: `.tfcore/telemetry/SCHEMA.md` §2. Stamp `started` with `date -u +%Y-%m-%dT%H:%M:%SZ` as your FIRST action of this task — it cannot be reconstructed at the end.

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"day1-brownfield","mode":null,
 "started":"<start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":[],"reqs_count":0,
 "subagents":[],"files_written":<n>,"build_result":"not-run"}
JSON
```

`reqs_touched` carries REQ IDs only — never requirement text — and `[]` is correct when this task touched no specific REQ. **Telemetry has no veto:** if the emit fails, the phase still succeeded; do not retry, do not diagnose, do not mention it.

### 8. HALT — produce a summary and stop

Output a numbered summary listing what was created:
1. `docs/{AppName}-Architecture.md` — N modules documented, M Mermaid diagrams
2. `docs/{AppName}-BRD.md` — K BRD requirements drafted (BRD-1 through BRD-K)
3. `docs/{AppName}-Coding-Standards.md` — created from canonical template
4. `.editorconfig` — created
5. `PROJECT-STATUS.md` — current_phase = Discovery
6. `CLAUDE.md` — created with the project's field-prefix decision pinned
6a. `AGENTS.md` — created (OpenCode pointer; same content via §7.2)
7. `docs/{AppName}-UsageGuide.md` — test-users registry (N accounts: M existing ✅ / K planned ⬜) + screen-by-screen test plan
8. *(only if §3.5 ran)* `docs/{AppName}-Checklist.md` — migrated from `{plan-file}` (X REQs done pre-existing, Y open); the old dev plan is archived to docs/OldDocs/; `*split-brd` is NOT needed for this project
9. *(§7.6)* DevGuide — `docs/{AppName}-DevGuide.md` (single) or `docs/devguides/` (split): R roles, M screens mapped, {STATIC-ONLY | runtime-verified}, {k} unresolved paths, {d} defects logged ({to the checklist if §3.5 ran, else "in DevGuide prose — run `*devguide --update` after `*split-brd`"}); screenshots in `docs/screenshots/{AppName}/` (if runtime-verified). *(Or "skipped — no built code yet" if the self-guard tripped.)*
10. HTML renders (§7.5 + §7.6) — list every `.html` written

If `SourceDocs[]` was non-empty, also include a "Sources harvested" line listing each file that contributed content (and any that were declared but couldn't be Read).

Then say exactly:

```
Day-1 artifacts complete — MD docs, their HTML renders (§7.5), AND the screen-by-screen
DevGuide (§7.6, the as-built code map) are all written. Nothing left to run.

Review the human-readable docs (open the .html files, or edit the .md sources directly).
The BRD especially is a first-pass draft inferred from the codebase; please verify
BRD-1..BRD-{N} reflect actual intent. The DevGuide traces each screen page → control →
service → data-access → proc; it is {STATIC-ONLY — run *verify once the stack is up to
runtime-confirm | runtime-verified}.

{If runtime-verified:} Review the per-screen SCREENSHOTS in docs/screenshots/{AppName}/ — this
is how each screen actually renders. For any screen that's visually broken or wrong, run
*fix-issues {AppName} {folder} (drop the screenshots + a note in a folder) — it triages and
fixes UI + functional bugs and re-verifies.

If you edit any .md afterwards, re-render just that file:
  /generate-html @docs/{AppName}-BRD.md      (Claude Code form; in OpenCode use the
                                              plain path without @ — @ there inlines
                                              the whole file into the prompt;
                                              multiple paths allowed; docs/ = all
                                              top-level .md, non-recursive)

Next workflow step (after your review): *split-brd {AppName} via /TechieFlow:agents:analyst (OpenCode: /flow-analyst) —
unless this run already migrated a dev plan (§3.5), in which case the next step is
*build-phase {AppName} shown in PROJECT-STATUS.md.
{If §3.5 did NOT run AND the DevGuide flagged defects: immediately after *split-brd, run
*devguide {AppName} --update so the DevGuide's day-1 findings get logged into the new
checklist before the verifier trusts it.}
```

If any pre-existing docs were archived (§1.6), append the list: "Archived to docs/OldDocs/: {files}".

Do NOT auto-advance past day-1 (no split/build without the user). Rendering HTML is NOT auto-advancing — it is part of day-1 (§7.5).

## Output Checklist (verify before saying done)

- [ ] `.tfcore/core-config.yaml` updated with customTechnicalDocuments paths
- [ ] `docs/{AppName}-Architecture.md` exists, contains Mermaid blocks, status = Current
- [ ] `docs/{AppName}-BRD.md` exists with a populated §4 Development status table (one row per F-code, real Status/% from dev-plan or code scan), a §9 Feature catalog (one `### F-…` per feature, screens table + workflow + diagram where non-trivial), a §10 BRD-N ledger, and a footer showing highest ID
- [ ] Every BRD Mermaid diagram passes the §5.5 authoring self-check (quoted labels, no `end` node ids) — no diagram will throw "Syntax error" in the rendered HTML
- [ ] If SourceDocs were harvested: new BRD is a SUPERSET of their requirements content (length sanity check passed — no tables/matrices/inventories dropped)
- [ ] `docs/{AppName}-Coding-Standards.md` exists with the instance-field convention decided and recorded (obj prefix or no-prefix)
- [ ] `.editorconfig` exists at repo root
- [ ] `PROJECT-STATUS.md` exists with current_phase=Discovery and a "Next command to run" pointer
- [ ] `CLAUDE.md` exists at repo root
- [ ] `AGENTS.md` exists at repo root (§7.2 OpenCode pointer)
- [ ] `docs/{AppName}-UsageGuide.md` exists — Test-users table populated (existing accounts from the DB marked ✅, planned ones ⬜; NO users were created in day-1) + screen-by-screen test plan
- [ ] If a dev/phase plan existed (§3.5): the one `docs/{AppName}-Checklist.md` written with phase tags and pre-existing completions marked `Done` — NOT left for a separate `*split-brd` run
- [ ] Collision policy §1.6 followed: all deliverables at canonical names, pre-existing versions + superseded source docs moved to `docs/OldDocs/`, NO merge-vs-new question asked, NO `-v2` variants written
- [ ] §7.5 auto-render done: every day-1 .md deliverable has a fresh sibling .html (shared shell: copy buttons, mermaid toolbar, working TOC) — the user was NOT told to run a render command
- [ ] §7.6 DevGuide generated (brownfield has as-built code): `docs/{AppName}-DevGuide.md` (single) or `docs/devguides/` (split) + sibling `.html`, with the verification-status banner (STATIC-ONLY is acceptable at day-1) — OR self-guard-skipped because the repo is genuinely doc-only (noted in §8). If §3.5 produced the checklist, devguide defects were logged into it (§6a); if not, the §8 message tells the user to run `*devguide --update` after `*split-brd`
- [ ] §7.6 if runtime-verified: per-screen screenshots captured to `docs/screenshots/{AppName}/` and the §8 message points the owner at them + `*fix-issues` for any broken screen
- [ ] Output summary delivered (incl. archived-files list), next command suggested
- [ ] Did NOT prompt the user mid-task for per-section confirmation

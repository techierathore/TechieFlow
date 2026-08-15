# day1-brownfield

Day-1 master task for a BROWNFIELD project. Produces all six day-1 deliverables in a single session: reverse-doc the codebase, plus BRD, Architecture, Coding Standards, .editorconfig, PROJECT-STATUS.md, and CLAUDE.md — each named with the app's prefix. Because a brownfield repo already has built code, the task ALSO generates the screen-by-screen **Developer Guide** (§7.6) — the as-built page → control → service → data-access → proc map — which greenfield day-1 cannot (no code yet). If the project already has a development/phase plan, the task ALSO migrates it into the one checklist (`docs/{AppName}-Checklist.md`) in the same run (§3.5) — no separate `*split-brd` step.

## Purpose

Replace the multi-step paste-and-substitute prompt with a single command: `*day1-brownfield {AppName}`. The task drives the analyst through reverse-doc + scaffolding of all human-facing day-1 artifacts so the user does not have to copy-paste a wall of instructions and manually substitute `<APP>`.

## elicit

elicit=false — this task runs autonomously end-to-end. It asks AT MOST TWO questions (app name if missing, then optional source-doc hints), then drafts every artifact (including the full BRD) in bulk and presents them for ONE-shot review at the end. NO per-section confirmation. NO per-requirement confirmation. The user reviews the written docs and edits the files directly, or replies with bulk changes.

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
  - At the end of the doc, add a `## Sources harvested` section listing each source file that contributed content.
- **Apply `CustomInstructions`** from §1.5 throughout — if the user said "stack is .NET 8", use .NET 8 in §1; if they said "ignore `legacy/`", skip that folder in the scan.
- Populate remaining sections by SCANNING the codebase (only for what the source docs didn't cover):
  - **§1 Tech stack:** read `.csproj`/`.sln` files, package references, target frameworks. Note TrBlazeUI / TechieRag presence (look in package references AND in `.claude/` for deployed agent files).
  - **§2 Component map:** scan `src/` (or `source/`) for projects; build a Mermaid `flowchart TB` showing project-level dependencies inferred from `<ProjectReference>` and `using` directives.
  - **§3 Data flow:** if you can identify a primary request path (e.g. controller → service → repo), diagram it as a `sequenceDiagram`. Otherwise leave the template placeholder and add a note "data flow unknown from static analysis — populate after first feature pass."
  - **§4 Module responsibilities:** one row per project under `src/`. Responsibility = one-line summary derived from top-of-namespace XML doc or README mentions.
  - **§5 Cross-cutting:** detect logging library (Serilog/ILogger), auth scheme (JWT/cookies/Identity), telemetry (OTel/AppInsights) by package references.
  - **§6 Deployment:** if `.github/workflows/`, `Dockerfile`, `azure-pipelines.yml` exist, derive the path. Otherwise mark "no CI/CD detected; manual deploy."
  - **§7 ADRs:** seed with `ADR-001 — current stack as-is (reverse-doc baseline).` and any obvious decisions visible in README.
  - **§8 Target architecture:** leave blank unless the BRD (§3 below) calls out a structural change.
  - **§9 Open questions:** include "field-prefix drift" detection (see below) and any TODOs / FIXMEs that look architectural.
- **Depth mandate (Architecture is a HUMAN document too):** apply the same information-preservation rule as the BRD (§3) — source-doc architecture content carries forward, never gets summarized into a stub. Each module in §4 with non-trivial behavior gets a short prose paragraph (not just a table row), and any significant runtime flow beyond the primary path (background jobs, ingestion pipelines, auth handshakes, external-API round-trips) gets its own `sequenceDiagram` or `flowchart` in the relevant section. A reader skimming only the diagrams should grasp how the system hangs together.
- **Field-prefix drift detection:** scan `src/`, `source/`, or any `.cs` files for instance-field declarations and note the dominant style (`obj`-prefixed vs bare PascalCase vs `_underscore`/mixed) — §4 uses this to pick the project's field convention. If no style reaches ~80% dominance, add to §9 Open questions: "Standards drift detected — mixed instance-field naming (N obj / M bare / K underscore). §4 picked {chosen}; remediation happens incrementally during implementation."
- **Table of Contents:** the template at `.tfcore/templates/v4custom/app-architecture-tmpl.md` includes a `## Table of Contents` section. After populating the rest of the doc, regenerate that section to match the actual H2 headings you wrote (drop entries for sections that ended up empty, add entries for any new sections). Use the slug rule from `.tfcore/templates/v4custom/html-render-shell.md §1` — same slug for the link in the TOC and the `id` the renderer will assign. Broken TOC links are a known recurring bug; don't be the next instance.
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
  - One-line statements are allowed ONLY in the §10 BRD ledger. Everything else is full prose, tables, and diagrams — this is a HUMAN document read as rendered HTML; the coding agents get their compact view later from `*split-brd` / the Checklist.
- **§4 Development status (brownfield: the reader's first question — "what's built, what's pending?"):** fill the §4 table with ONE row per §9 feature-catalog F-code. Derive each row's Status / % / Phase / Notes from the **strongest evidence available**, in priority order: (1) a migrated dev/phase plan (§3.5) — carry its phase + completion verbatim; (2) the code scan from §2 — a feature whose screens/handlers actually compile and exist is `Done`, partially-present is `Partial`, absent is `Planned`; (3) source-doc status notes. Set the "Snapshot as of" date to today. This is a feature-level SUMMARY only — do NOT restate per-REQ status (that's PROJECT-STATUS + the checklists). Keep it consistent with §3.5's migrated statuses and with PROJECT-STATUS.
- **§9 Feature catalog (the heart of the doc):** one `### F-{CODE}: {Name}` subsection per feature/capability area found in the source docs and the codebase. Per feature: personas + phase, 1-2 paragraphs of what/why, a screens & routes table, a numbered workflow (inputs → outputs), and the owning BRD-N IDs. If a source doc already has a feature catalog, preserve its feature codes and per-feature detail. Depth scales with the app (8–25 features is normal) — there is NO cap. Every F-code MUST also appear as a row in the §4 Development status table.
- For §10 Functional requirements ledger: walk the feature catalog and emit `BRD-1`, `BRD-2`, … as one-line `<actor> can <action>` or `system shall <behavior>` statements, each tagged with its catalog feature `(F-CODE)`. Number monotonically. **One BRD per discrete capability — the count scales with the app (20–60 is normal for a real product); NEVER merge capabilities to keep the count low.** If a BRD came directly from a source doc, suffix the line with `<!-- from: <source-file> -->`.
- For §11 Non-functional: cover performance, security, accessibility, scalability, reliability based on visible NFR signals (auth scheme, target framework, any `aria-` attrs in Razor). Where concrete targets exist (latency, uptime, concurrency), present them as a target table, not buried in prose. **ALWAYS include the standing Observability NFR: Serilog file-based logging in every executable head** — if the §5 cross-cutting scan found Serilog (or an equivalent structured file-logging stack) already wired, record it as met/`Done (pre-existing)`; if the app logs only to console or not at all, add the NFR as `Planned` so it becomes a `REQ-NFR-*` row and gets built (recipe: coding-standards §Logging).
- **Mermaid mandate:** §6, §7, §8 (context, journey, component) are the MINIMUM — build them from §2's component map (copy verbatim if identical). Additionally, every feature-catalog entry with a multi-step or multi-actor flow gets its own diagram (`flowchart` or `sequenceDiagram`). Target: a reader skimming only the diagrams should grasp how the app works. Simple CRUD features may skip the diagram. **Every diagram MUST follow the authoring rules in `.tfcore/templates/v4custom/html-render-shell.md §5.5` — quote every node/edge/subgraph label and never use `end` as a node id; unquoted special characters in flowchart labels are the #1 cause of broken diagrams in the rendered HTML.**
- Append a footer:
  ```
  ---
  Last updated: {YYYY-MM-DD}
  Highest BRD ID: BRD-{N}
  Sources harvested: {comma-separated list of SourceDocs paths, or "none — drafted from reverse-doc"}
  Custom instructions applied: {one-line summary of CustomInstructions, or "none"}
  Drafted from reverse-doc — review and edit. New BRDs may be added (append-only); do not renumber.
  ```
- **Table of Contents:** the template includes a `## Table of Contents` section. Regenerate it after populating the doc so it matches the actual H2 headings, and list each `### F-…` feature-catalog entry as an H3 sub-entry under "Feature catalog". Use the slug rule from `.tfcore/templates/v4custom/html-render-shell.md §1`.
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
- **Keep the BRD §4 Development status table consistent with this migration:** the feature-level rows in BRD §4 must agree with the per-REQ statuses you just wrote (a feature whose REQs are all `Done (pre-existing)` → `Done` in §4; mixed → `Partial`; none started → `Planned`). The checklist is the live per-REQ truth; BRD §4 is the human feature-level snapshot of the same reality.
- Do NOT modify the dev-plan file's content. After migration it is superseded — move it to `docs/OldDocs/` per §1.6 and say so in the §8 summary.
- If the `*split-brd` artifact (`docs/{AppName}-Checklist.md`) already exists (re-run scenario), apply §1.6: archive the old one to `docs/OldDocs/`, write fresh at the canonical name. No questions.

### 4. Create the Coding Standards → `docs/{AppName}-Coding-Standards.md`

Write the file with the exact content below, substituting `{AppName}` in the title only.

**ONE per-project decision first — the instance-field prefix.** The shared rules (no underscores, `a` params, `v` locals, PascalCase everywhere) are fixed; the instance-field convention is decided per project (existing samples: AppManager = `obj` prefix, AstroLyfe = bare PascalCase no-prefix):
- If the existing code has a clear dominant style (≥80% of instance fields `obj`-prefixed OR ≥80% bare PascalCase), adopt that style.
- If `{Hints}` / CustomInstructions specify one, that wins.
- Otherwise default to `obj`.
Record the decision in the table below (swap the Instance-fields row to `PascalCase, no prefix — e.g. private readonly ILogger<X> Logger;` if no-prefix won), in the §"Enforcement" greps (the missing-obj-prefix grep only applies to obj-style projects), and in CLAUDE.md (§7).

```markdown
# {AppName} Coding Standards

**Last Updated:** {today YYYY-MM-DD}
**Status:** Authoritative for all code under `src/`/`source/` and `tests/`. Conformance enforced via repo-root `.editorconfig` + verifier grep checks in §"Enforcement".

## Database Naming Conventions

### Tables and Columns
- PascalCase: `CustomerOrder` NOT `customer_order`
- Singular: `CustomerOrder` NOT `CustomerOrders`
- **NEVER use underscores** in any DB object name
- FK columns: `{TableName}Id` (e.g., `CustomerId`)
- PK: `{TableName}Id` (e.g., `UserId`)

### Stored Procedures & Functions
- PascalCase verb prefix: `GetCustomerOrders`, `InsertOrder`, `CalculateTotal`
- Action prefixes: Get / Insert / Update / Delete / Calculate

### Indexes & Constraints
- Index: `IX{Table}{Column}` · PK: `Pk{Table}` · FK: `Fk{Table}{Ref}` · Unique: `Uc{Table}{Column}`

## C# Conventions

### Classes & Interfaces
- PascalCase for classes; `I` prefix for interfaces; descriptive names.
- Async methods end with `Async`.

### Fields, Parameters, Locals

**NEVER use underscores** anywhere in any identifier.

| Kind | Convention | Example |
|------|-----------|---------|
| **Instance fields** | `obj` prefix + PascalCase tail (no underscores) | `private readonly ILogger<X> objLogger;`<br>`private readonly HttpClient objHttpClient;`<br>`private string objCachedPublicKey;` |
| **Static / `const` fields** | PascalCase, no prefix | `private const string CachePrefix = "…";` |
| **Method parameters** | `a` prefix + PascalCase | `LoginAsync(string aEmail, string aPassword)` |
| **Local variables** | `v` prefix + PascalCase | `var vResponse = await …` |
| **Booleans** | same prefix + `Is`/`Has`/`Can` | `IsAuthenticated`, `vIsValid`, `aHasAccess` |
| **Properties** | PascalCase, no prefix | `public string ConnectionString { get; set; }` |
| **Constants** | PascalCase, no underscores | `MaxRetryCount` NOT `MAX_RETRY_COUNT` |
| **Test methods** | Short PascalCase, no underscores — full scenario in XML `<summary>` | `LoginRejectsBadPassword` not `Login_BadPassword_ReturnsUnauthorized` |

**Rejected forms:** `_underscore` field prefixes, snake_case anywhere, Hungarian prefixes (`strName`), underscores in test method names.

### Controller-action parameters
The `a`-prefix applies uniformly to `[FromRoute]`/`[FromQuery]`/`[FromBody]`. Parameter name flows through to OpenAPI. Body DTO **property** names stay PascalCase no prefix; only the parameter symbol holding the deserialized DTO gets the `a` prefix.

### Environment Variables
**PascalCase, no separators.** `{AppName}BaseUrl` NOT `APPNAME_BASE_URL` and NOT `AppName__BaseUrl`. Use a custom configuration provider mapping PascalCase env vars → `:`-nested config paths. Read via `IConfiguration["Section:Key"]` only — never `Environment.GetEnvironmentVariable(...)`.

### Project & solution naming — the primary head carries the PRODUCT name
- The product's **primary executable head** project is named exactly `{AppName}` — `src/{AppName}/{AppName}.csproj`. A single-head product's one head IS `{AppName}`.
- **`{AppName}.App` is BANNED** (owner rule 2026-07-10): "App" says nothing — the product name already names the app. Never scaffold it; if the codebase has one, log a rename REQ (dir + `.csproj` + sln entry + namespaces) in the checklist instead of propagating the name.
- Secondary heads of a multi-head product take a **descriptive** dotted suffix: `{AppName}.Api`, `{AppName}.Desktop`, `{AppName}.Cli`. Satellites keep their conventional names: `{AppName}.Core` (engine), `{AppName}UI` (RCL), `{AppName}.Core.Tests` / `{AppName}.Tests`.

### File Structure
```csharp
using System;

namespace {AppName}.Services.Example;

public class DatabaseService
{
    private readonly ILogger<DatabaseService> objLogger;
    private readonly IConfiguration objConfiguration;

    public DatabaseService(ILogger<DatabaseService> aLogger, IConfiguration aConfiguration)
    {
        objLogger = aLogger;
        objConfiguration = aConfiguration;
    }

    public string ConnectionString { get; set; }

    public async Task<DataTable> GetDataAsync(string aQueryName)
    {
        var vConnString = objConfiguration.GetConnectionString("Default");
        var vResult = await ExecuteQueryAsync(vConnString, aQueryName);
        return vResult;
    }
}
```

### Best Practices
- One class per file. File name matches class.
- File-scoped namespaces. Nullable reference types enabled.
- Methods small (<20 lines). Single responsibility.
- Max 3 nesting levels. Early returns for validation.
- ConfigureAwait(false) in libraries.
- StringBuilder for loop concatenation. Dispose IDisposable. Cache expensive ops.

### XML Documentation (MANDATORY on public members)
`<summary>`, `<remarks>`, `<param>`, `<returns>`, `<exception>` — all required.

### Testing
- Short PascalCase test name, no underscores. Full scenario in XML `<summary>`.
- Arrange-Act-Assert. One assertion per test where practical.

### Security
- Never hardcode credentials. Parameterized queries. Validate inputs. Log security events.

### Logging — Serilog file sink (MANDATORY, every .NET app type)
- **Every executable head gets Serilog with a rolling FILE sink — web (Blazor Server/WASM host), API, MAUI, WinForms/WPF desktop, console/CLI, background service. No exceptions, and never wait for the owner to ask.**
- Wire at startup, before anything else can fail: `Log.Logger = new LoggerConfiguration().MinimumLevel.Information().WriteTo.Console().WriteTo.File("logs/{appname}-.log", rollingInterval: RollingInterval.Day, retainedFileCountLimit: 14).CreateLogger();` then plug into DI (`builder.Services.AddSerilog()` / `builder.Host.UseSerilog()` for hosts; `builder.Logging.AddSerilog()` in `MauiProgram.CreateMauiApp`). Read overrides from `appsettings.json` (`Serilog` section) where the host has one. For MAUI/desktop, root the path in a writable per-app location (`FileSystem.AppDataDirectory` / `Environment.SpecialFolder.LocalApplicationData`), not the install dir.
- Log unhandled exceptions at the head boundary: `try/catch` + `Log.Fatal` around startup, `AppDomain.CurrentDomain.UnhandledException` / `TaskScheduler.UnobservedTaskException` handlers, and `Log.CloseAndFlush()` on exit.
- **Class libraries never reference Serilog** — they log through `ILogger<T>` / `Microsoft.Extensions.Logging.Abstractions` only; the head's Serilog config picks those up automatically.
- App code logs through injected `ILogger<T>` (structured message templates, e.g. `logger.LogInformation("Imported {Count} rows", n)`), not static `Log.*`, outside the startup boundary.
- The `logs/` output folder is gitignored (the owner adds it — agents never run git).
- Brownfield: an app already on a working structured file-logging stack (e.g. NLog-to-file) is compliant — record the stack in this section; new heads added to it still use Serilog.

### MAUI UI testability — stable AutomationId (MAUI apps only)
- Every interactive or data-bound control the verifier must reach (buttons, entries, pickers, list/collection views, key labels/values) carries a stable, unique **`AutomationId`** — the native analogue of a stable DOM id for Playwright. Without it Appium selectors drift and the runtime gates (`verify-phase §4a/§4b`) can't reliably find controls on the Android/iOS/Mac Catalyst heads.
- Name them by intent, not layout: `AutomationId="LoginSubmitButton"`, `AutomationId="ClientsGrid"`, `AutomationId="TotalBalanceValue"` — never positional (`Button2`).
- Set it on the control whose data the gate asserts (the grid/list itself, the value label), so "rows present AND non-empty" / "value not blank" maps to one addressable element.
- (Blazor screens use the equivalent `data-testid`/stable element ids for Playwright — same principle.)

## Enforcement

### .editorconfig (machine-checkable)
- File-scoped namespaces (`warning`)
- Async-method `Async` suffix (`warning`)
- `var` for locals (`warning`)
- Nullable reference types enabled
- No `_` prefix on private fields (`warning` via custom naming rule)

### Verifier grep checks
```bash
# Forbidden underscore-prefix fields
grep -rE "private(\s+readonly)?\s+\w+\s+_[a-z]" src/ source/ 2>/dev/null

# Forbidden test-method underscores
grep -rE "public\s+(async\s+)?Task\s+\w+_\w+\s*\(" tests/

# Field missing obj prefix
grep -rE "private(\s+readonly)?\s+\w+\s+(?!obj)[A-Z]\w+\s*[;=]" src/ source/ 2>/dev/null | grep -v "static\|const"
```

### Severity
- **Error**: file-scoped namespace, underscore field prefix
- **Warning**: nullable, async suffix
- **Info**: consider fixing
```

### 5. Create `.editorconfig` at the repo root

Copy `.tfcore/templates/v4custom/app-editorconfig-tmpl.editorconfig` verbatim to `.editorconfig` at the repo root. No substitution — the rules are identical across projects.

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

### 7. Create `CLAUDE.md` at the repo root

Copy `.tfcore/templates/v4custom/app-claude-md-tmpl.md` and substitute `{AppName}` throughout. Resolve the field-prefix line to THIS project's §4 decision, e.g.: "Field-prefix convention: `obj` prefix on instance fields (e.g. `private readonly ILogger<X> objLogger;`) — see Coding Standards." or "...bare PascalCase, no prefix — see Coding Standards."

### 7.2. Create `AGENTS.md` (OpenCode auto-loads this, not CLAUDE.md)

OpenCode's root-scan file is `AGENTS.md` (it never reads `CLAUDE.md`; `opencode.jsonc` `instructions` already lists it). Write `AGENTS.md` at the repo root as a **harness-neutral pointer** with the same substituted `{AppName}`:

```markdown
# {AppName} — session memory (OpenCode)

This project's full memory is `CLAUDE.md` (same content the Claude Code harness loads).
Read it before any code change. Required reading:
- **docs/{AppName}-Coding-Standards.md** — strict compliance for every line of code.
- **docs/{AppName}-Architecture.md** — respect module boundaries.
- **PROJECT-STATUS.md** — current phase & next-step context.

Hard rule: git/gh are MANUAL. Agents NEVER run `git` or `gh` (opencode.jsonc denies
both). Evidence for status = the checklist Requirements Status table + working-tree
files + a fresh `dotnet build`, never git history. The owner commits.

Slash-command syntax: /flow-master, /flow-analyst, /flow-architect, /flow-verifier,
/trblazeui, /techierag (the last two are NuGet-deployed — run `dotnet build` once if
missing). Tasks invoke as `*command args` after the agent is loaded.
```

No substitution beyond `{AppName}`. If a previous `AGENTS.md` exists, archive it per the §1.6 collision policy and write fresh.

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

Same turn as the status/PROJECT-STATUS write. Doctrine + the nine constraints: `.tfcore/tasks/_metrics-emit-gate.md`. Schema: `.tfcore/telemetry/SCHEMA.md` §2. Stamp `started` with `date -u +%Y-%m-%dT%H:%M:%SZ` as your FIRST action of this task — it cannot be reconstructed at the end.

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
  /generate-html @docs/{AppName}-BRD.md      (works in Claude Code and OpenCode;
                                              multiple @paths allowed; @docs/ = all
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

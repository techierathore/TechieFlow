# handoff-phase

Final-phase wrap-up: usage doc + status refresh + library-feedback consolidation + HTML re-render.

## Purpose

After the checklist's Requirements Status table is green (or `Blocked` library-gap items accepted), produce the artifacts the user needs to ship and the artifacts future-you needs to resume.

**Run-once-per-UAT-cycle guard:** handoff *produces* the UAT bundle — it runs BEFORE owner UAT, once. If the PROJECT-STATUS Verification log already has a READY-FOR-UAT handoff row for the current cycle and the only open rows are documented owner-run UAT, there is nothing for this task to add: say so and point at the UsageGuide UAT plan instead of re-running. Execute anyway ONLY when the owner explicitly invoked `*handoff-phase` themselves, or when substantive doc-affecting work landed after the last handoff (then note in the Verification log row what changed). Agents never *suggest* a repeat handoff while non-terminal rows remain (`_status-update-gate.md` item 5, UAT tier).

## Inputs

- `{AppName}` argument (required; or resolve from core-config.yaml).

## SEQUENTIAL Execution

### 1. Finalize `docs/{AppName}-UsageGuide.md`

The Usage Guide was created at day-1 (`day1-*` §7.4) from `.tfcore/templates/v4custom/app-usageguide-tmpl.md`. **Update it in place — do not create a new doc.** (If it's missing — a project that predates this step — create it now from that template.) At handoff, bring every section up to ship-reality and **TERSELY**. Hard rules:

- **Test-users table:** reconcile with the database — every account that actually exists now is marked `Created? = ✅`; drop or mark any planned ⬜ account that was never created. This table is what UAT logs in with, so it must match the live DB.
- **Screen-by-screen test plan:** ensure every shipped feature has a walkthrough block; remove blocks for cut features.

Below, "populate" means refresh these sections of the existing doc. Hard rules:

- **No narrative prose anywhere.** No "this app uses Blazor Server because…", no caveats, no explanations. The deployment-steps section must look like a runbook — one command per line, numbered in execution order.
- **Skip any step that doesn't apply.** If the repo has no SQL migrations, omit the database-setup step entirely — do not leave "N/A" placeholders or "// not applicable" comments.
- **No optional steps in the numbered list.** The numbered deployment-steps section is the minimum sufficient set of commands to go from `git clone` to a running app. Anything optional goes in "Known limitations" or a separate doc.

Detection sources for each section:

- **Prerequisites**: SDK version from `global.json` / `.csproj` `<TargetFramework>`. Add a one-line entry for each external runtime the build/test commands depend on (Node only if Playwright tests exist; Postgres/SQL Server/etc. only if migrations exist; MAUI workload only if there's a MAUI project). One line each. No prose.
- **Deployment steps**: detect in this order and emit one numbered step per command:
  1. `git clone <repo>` (always)
  2. `dotnet restore` (always)
  3. SQL migrations — scan `database/`, `db/migrations/`, `src/*Db/Scripts/`, and any DbUp project's `<EmbeddedResource>` paths. List `.sql` files in lexicographic order, one per line. If a DbUp project exists, prefer `dotnet run --project src/{AppName}.Db` as a single step instead of listing each SQL file.
  4. `dotnet build`
  5. Backend run — find the API/service startup project. One `dotnet run --project ... --urls http://localhost:5100` line.
  6. Frontend run — find the Web/UI startup project. One `dotnet run --project ... --urls http://localhost:5099` line.
  7. "Open http://localhost:5099 in a browser."
  - For MAUI: replace step 5/6 with `winrun "dotnet build src/{AppName}.Maui"` then `winrun "dotnet run --project src/{AppName}.Maui"`.
  - If frontend and backend are the same project (Blazor Server-only): collapse steps 5+6 into one.
- **Test**: `dotnet test`. Add `npx playwright test` ONLY if the repo has Playwright tests checked in.
- **Smoke checklist**: one checkbox per top-level BRD capability (5–10 max). Each line is a user action, not a technical step ("Log in as admin and load the dashboard" — NOT "verify JWT validation").
- **Known limitations**: pull every `Blocked` REQ row from the checklist Status table + every entry from the per-library feedback files (`docs/{AppName}-TrBlazeUI-Feedback.md`, `docs/{AppName}-TechieRag-Feedback.md`). One line each. Cross-reference to issue IDs (TR-NNN, TR-RAG-NNN).

**If you find yourself writing more than one line per numbered step, you're doing it wrong** — the user has explicitly called out that the deployment steps got polluted with "unnecessary details" in past runs. Strip aggressively.

### 2. Update `PROJECT-STATUS.md` (per `.tfcore/tasks/_status-update-gate.md`)

- `current_phase: Handoff` (the user manually sets `Released` after UAT passes — §5)
- `last_updated`: today
- `last_verified_build: PASS` (you just verified — confirm with `dotnet build` if uncertain)
- `last_verified_date`: today
- "Where I am": one paragraph — "All REQ-* verified; awaiting UAT per usage doc."
- "Next command to run": `Manual UAT per docs/{AppName}-UsageGuide.md smoke checklist.`
- "Open requirements": list any REQ-* not `Verified` in the checklist Status table (`Blocked`-by-library or deferred). Empty if all clear.
- "Library feedback summary": refresh counts from the consolidated library-feedback doc (§4 below)
- "Standards compliance": copy from the latest verifier run (recorded in the checklist Status table Remarks / prior PROJECT-STATUS entry)
- Append a "Verification log" row for the handoff (Result = ship-readiness verdict; Status table column → `docs/{AppName}-Checklist.md#requirements-status`)
- **BRD §4 Development status** — per the gate's item 9, roll the now-final checklist statuses up into the BRD §4 table (at handoff, most features should land on `Done`). If the BRD has no §4 section (legacy), say so and point the user at `*refresh-status {AppName}` to add it. The re-render in §3 picks up the change.

### 3. Re-render the HTMLs

Invoke `render-workflow-docs {AppName}` as a subtask. Specifically:
- `docs/{AppName}-BRD.html` — always re-render (do NOT mtime-compare with bash; the Write tool is cheap and a stale HTML is worse than a redundant re-render)
- `docs/{AppName}-Architecture.html` — if implementation revealed "as-built" deltas from "Target", update Architecture.md first, then re-render. Set status to "Current (post-implementation)" or "Current + planned target" as appropriate.
- `PROJECT-STATUS.html` — always re-render (just updated in §2)

Then re-render the **Usage Guide** (updated in §1) and the **DevGuide** (refreshed in §3a) via `.tfcore/tasks/generate-html.md`: `docs/{AppName}-UsageGuide.md` (+ the DevGuide — `docs/{AppName}-DevGuide.md` if single, or every file under `docs/devguides/` if split) → sibling `.html`. **Do NOT render the checklist to HTML** — it is an AI-agent working document kept in markdown only; its Status table stays accurate in markdown.

### 3a. Refresh the Developer Guide

Run `.tfcore/tasks/devguide.md` for `{AppName}` (`*devguide {AppName}`) so the screen-by-screen code map reflects the final as-built code — this is the doc a human developer uses to chase bugs and verify the AI-generated code from page → control → service → data-access → stored proc. If a DevGuide already exists, an incremental `--update` is enough (remap only changed screens). It produces `docs/{AppName}-DevGuide.md` (single) — or, for a large app, an index + per-role files under `docs/devguides/` — and their `.html`; §3 above already lists them in the re-render set.

### 4. Consolidate the per-library feedback files

For EACH of `docs/{AppName}-TrBlazeUI-Feedback.md` and `docs/{AppName}-TechieRag-Feedback.md` (and any other `docs/{AppName}-{LibName}-Feedback.md`) that exists — they are separate files because each goes to a different team:
- Deduplicate entries (same expected/actual pair = duplicate; merge them).
- Sort by severity: blocker → major → minor → nice-to-have.
- Ensure each entry has all the schema fields (Severity, Repro, Expected, Actual, Encountered in, Workaround, Suggested fix). Fill in missing ones from context if possible.
- Refresh the file's summary block:
  ```markdown
  ## Summary
  - {N blockers, M majors, P minors, Q nice-to-haves}
  - Last consolidated: {today}
  ```
- If a legacy combined `docs/{AppName}-Library-Feedback.md` exists (pre-split projects), split its sections into the per-library files first, then archive it to `docs/OldDocs/`.

If no feedback file exists (no library issues encountered), skip this step.

### 5. Output summary + ship-readiness verdict

Deliver:
- "✔ {AppName} is ready for UAT." OR
- "⚠ {AppName} has {N} `Blocked` (library-gap) items — see docs/{AppName}-TrBlazeUI-Feedback.md / docs/{AppName}-TechieRag-Feedback.md before UAT."

Then explicitly tell the user:
1. Open `docs/{AppName}-UsageGuide.md` and run the smoke checklist.
2. Hand each per-library feedback file to its team (or file as GitHub issues against that library's repo): `docs/{AppName}-TrBlazeUI-Feedback.md` → TrBlazeUI team, `docs/{AppName}-TechieRag-Feedback.md` → TechieRag team. The library teams use this same framework, so the file drops straight into their flow.
3. After UAT passes, manually update `PROJECT-STATUS.md`: `current_phase: Released`.
4. For end-user / external documentation, run `*productguide {AppName}` (flow-master) — it builds a screenshot-illustrated, task-oriented user manual (MD + HTML) from the DevGuide's screen map + captured screenshots. On-demand; re-run with `--update` as the UI evolves.

## Output Checklist

- [ ] `docs/{AppName}-UsageGuide.md` finalized — Test-users table reconciled with the DB (created accounts ✅) + screen-by-screen plan current + prereqs/build/run/test/smoke; its `.html` re-rendered
- [ ] Developer Guide generated/refreshed (`*devguide {AppName}`) — screen-by-screen code map (page→control→service→data-access→proc) + its `.html`
- [ ] `PROJECT-STATUS.md` updated with handoff phase + UAT next-step
- [ ] `docs/{AppName}-BRD.html`, `docs/{AppName}-Architecture.html`, `PROJECT-STATUS.html`, the UsageGuide + DevGuide HTML re-rendered (the checklist is NOT rendered to HTML — markdown only)
- [ ] Per-library feedback files consolidated, one per library (if applicable; legacy combined file split + archived)
- [ ] Ship-readiness verdict delivered with explicit next steps

# devguide

Generate (or incrementally refresh) the **screen-by-screen Developer Guide** — the human-developer document that traces every screen, control, and value from the UI down to the database (Razor page → control → service method → data-access method → stored proc / query), grouped by user role. It documents the **code as built**, so a developer can find and fix bugs and verify AI-generated code without reverse-engineering the whole repo.

Output: `docs/{AppName}-DevGuide.md` (single doc for small apps, kept directly in `docs/`) **or**, for a multi-part split (large apps), a dedicated **`docs/devguides/`** subfolder holding the index `docs/devguides/{AppName}-DevGuide.md` + one `docs/devguides/{AppName}-DevGuide-{Role}.md` per role — each rendered to a sibling `.html`. The subfolder keeps a multi-file guide from cluttering `docs/`. Template: `.tfcore/templates/v4custom/app-devguide-tmpl.md`.

## When to use

- **After a build phase** that added/changed screens, to give developers a current map (auto-run at handoff — `handoff-phase §3a`).
- **Anytime a developer needs to chase a bug** and the BRD/Architecture/DB-design don't show the code path.
- **Re-runnable**: regenerate after code changes. Use `--update` (or pass a `{Scope}`) to refresh only the changed screens instead of remapping everything (saves tokens — see `.tfcore/TOKEN-GUIDE.md`).

This task documents code; it **never edits source**. If there is no built code yet (greenfield day-1), HALT and tell the user to build first.

## Inputs

- `{AppName}` (required; or resolve from `core-config.yaml`).
- `{Scope}` — OPTIONAL: `all` (default) · a role name · a screen/route · a comma-list of either. Limits which screens are (re)mapped.
- `--update` — OPTIONAL flag: incremental refresh. Re-map only screens whose Razor/service/data-access files changed since the DevGuide's last generation (by file mtime vs the guide's subtitle date), or only the `{Scope}` given. Preserve every unchanged screen entry verbatim.
- `--split` / `--single` — OPTIONAL: force the structure instead of auto-deciding (§3).

## SEQUENTIAL Execution

### 1. Confirm there is code to map

Verify the app has built source (e.g. `src/{AppName}.Web` Razor files exist). If the repo is doc-only (no UI/code yet), HALT: "No built UI found — the DevGuide maps as-built code. Run the build phases first, then re-run `*devguide {AppName}`."

### 2. Discover roles, menus, and screens (the work-list)

Build the list of `(role, screen)` pairs to document. Gather from, in order:

1. **Roles** — `docs/{AppName}-UsageGuide.md` Test-users table (canonical role list) + authorization in code (`[Authorize(Roles=…)]`, policy registrations, role/claim constants). Reconcile the two.
2. **Menus** — the nav definition(s) (`Shared/NavMenu.razor` / menu config) and any per-role menu filtering, so you can record which role sees which menu item and what it opens.
3. **Screens** — every routable Razor page (`@page` directives) and significant component, mapped to the role(s) that can reach it. A screen reachable by several roles is documented once, noted under each role's menu map.

Produce a flat work-list: `role → [screens]`. Echo a one-line count: `N roles, M distinct screens`.

### 3. Decide structure — single doc vs per-role split

- **`--single` / `--split`** if the user forced it.
- **Auto** otherwise: **split per role** when `roles ≥ 3` OR `distinct screens > 12` OR any single role has `> 8` screens (large app like a multi-tenant admin suite). **Single doc** otherwise (small app). State which you chose and why.
- **Single:** one `docs/{AppName}-DevGuide.md` from the template (directly in `docs/`), all roles' screens under §4.
- **Split:** create a **`docs/devguides/`** subfolder and write the whole multi-part guide into it, so the many files don't clutter `docs/`. `docs/devguides/{AppName}-DevGuide.md` is the **index** (template §1–§3 + the role→file table + menu maps, no per-screen bodies); each `docs/devguides/{AppName}-DevGuide-{Role}.md` carries template §4 for that role's screens (plus a short §1/§2 pointer back to the index). Index and role files are co-located in `docs/devguides/`, so the index's relative links (`./{AppName}-DevGuide-{Role}.md`) resolve as-is.
- **Switching structure on a re-run:** if the guide already exists in the *other* layout (a single `docs/{AppName}-DevGuide.md` that now splits, or a `docs/devguides/` set that now collapses to a single doc), move/delete the stale-location file(s) so only one canonical copy survives — never leave both a `docs/{AppName}-DevGuide.md` and a `docs/devguides/{AppName}-DevGuide.md` (+ their `.html`).

### 4. Map the code — FAN OUT across roles (token-bounded)

**Do not read the whole codebase in one context.** Spawn one subagent per role (or per screen-cluster for a huge role), each scoped to map only its slice. This keeps each context small and lets the work run in parallel — the single biggest token lever for this large doc (see `.tfcore/TOKEN-GUIDE.md`).

Each subagent is told to, for its assigned screens ONLY:
- Open each screen's Razor page/component (+ code-behind) and list the **controls** (grids, charts, forms, tables, buttons that load/compute data).
- For each control/action, follow the call chain in code: Razor → injected **service method** → **data-access method** (repository / DbContext / Dapper) → **stored proc name or SQL query**. Record file paths. If a value is **calculated**, name the calculator method and where.
- Draft the screen's **flowchart**, **Controls** table, **Data lineage** table, business-rules and known-issues bullets per the template's `### {Role} · {Screen}` block.
- Return the finished markdown section(s) only — raw doc text, no commentary.

**LANDING-TRUTH — read the routing, never infer it.** Where a screen says it is "reached via" / where a role "lands" after login is a **claim about the code that MUST be read, not inferred from folder or role names**. Resolve the actual post-login route from the login/redirect code (the `NavigateTo(...)` after a successful login, the default `@page "/"`, `App.razor`/authentication redirect, `[Authorize]` fallback) and cite the `file:line` that performs the navigation. ❌ "Admin logs in → lands on Admin Dashboard (because the page is in the Admin folder)" is exactly the hallucination this guide exists to kill. ✅ "After login `LoginPage.razor.cs:57` does `NavigateTo("/Index")` for **all** roles; Admin Dashboard is reached only from the menu." If a role's landing is the same shared home page, say so.

**RENDER-TRUTH — verify the data REACHES and RENDERS, not just that a method exists.** "The service/proc exists" is NOT verification — the whole point is to catch the case where code is wired but the control still shows blank/empty/stale. For each control, also check:
- **Guards & binding:** the `@if (X != null)` / `@if (list.Any())` conditions, and whether the bound data can actually be non-empty. A header that renders while its table is hidden by a null guard is a *defect*, not "working".
- **Source returns:** does the query/proc actually return rows, and do its **columns map to the model's property names** (case/underscore)? Are there **computed getters** (e.g. `BirthDate => new DateTime(BYear,…)`) that throw or blank when the source columns are unmapped/empty? Rows present but cells blank = a real defect.
- **Required component parameters:** is every parameter the control needs actually declared and supplied (e.g. a grid bound to `Pagination="@pagination"` where `pagination` is never declared)? A missing/undeclared/null required param that suppresses rendering is a defect.
- Tag each lineage/control row with its render status: **renders** · **renders-empty/blank (suspected defect — why)** · **{unresolved — TODO}**. A "suspected defect" MUST also be logged to the checklist per §6a.

**Verify, don't trust.** A lineage row is a claim about the code. Confirm named methods/procs/components actually exist AND that data reaches the control (above). If a path can't be confirmed, record `{unresolved — TODO: reason}` rather than inventing a name. Prefer "I read X at file:line and it does Y" over any inference.

For `--update`: locate the existing guide first (single `docs/{AppName}-DevGuide.md`, or the split set under `docs/devguides/`), only spawn subagents for changed/in-scope screens, reuse existing entries for the rest, and write back to wherever the guide already lives.

### 5. Assemble the doc(s)

- Fill the template header (§1 How to use, §2 Architecture cheat-sheet from `docs/{AppName}-Architecture.md` + the real project layout, §3 Roles-and-menu map from §2's discovery).
- Insert each role's screen sections (single doc) or write each role file + the index (split).
- Every Mermaid diagram MUST pass the `html-render-shell.md §5.5` self-check (quoted labels, no `end` node id).
- Subtitle/footer: `Generated {today YYYY-MM-DD} · reflects code as built`.

### 5a. OBSERVE + RECONCILE — ground the guide in the RUNNING app (mandatory attempt)

A guide built only from reading code is a hypothesis, not the truth — static reading cannot see that a table renders blank, a list shows a count over zero visible rows, or a calc returns empty at runtime. So after drafting the map, **run the app and observe**, then reconcile.

**OBSERVE (reuse the verifier — do not build a second app-runner).** Invoke the verifier's runtime render sweep (`.tfcore/tasks/verify-phase.md §4a`) over the screens in this DevGuide: it boots the app via the build-invocation-ladder, logs in as each role's `docs/{AppName}-UsageGuide.md` test user, navigates each screen, and records for **every control** in the draft map whether it **RENDERS** its data or is **RENDER-EMPTY / RENDER-ERROR / UNREACHABLE** (per `_smoke-test-policy.md` — running it is mandatory, "can't run on Linux" is banned). 

**RECONCILE.** Diff the static map against what was observed:
- Tag each control in the doc with its **observed** status — `renders ✓ (runtime-confirmed {date})` / `renders-empty (DEFECT — {what})` / `render-error` / `unreachable` — NOT a static guess.
- Every deviation (documented-to-render but observed-empty/error, or a landing that differs from what was read) is a **runtime-confirmed defect** → log it to the checklist in §6a (these carry more weight than static suspicions).
- Stamp the file header with a **verification-status banner** (see below).

**If the app genuinely cannot be booted in this environment** (dependent stack down and the user can't bring it up now): do NOT fake render-status. Stamp the guide **`⚠ STATIC-ONLY — NOT runtime-verified`**, leave control render-status as `static-only (unconfirmed)`, and tell the user in §8 to run `*verify {scope}` (or re-run `*devguide`) once the stack is up so the OBSERVE pass can complete. A static-only guide is explicitly a draft, never presented as confirmed.

**Verification-status banner (top of the index AND every area file):**
- `> ✅ Runtime-verified {date} — exercised as: {roles}. Control render-status below is observed, not inferred.` — when OBSERVE ran.
- `> ⚠ STATIC-ONLY ({date}) — built from code reading; NOT yet runtime-verified. Render-status is unconfirmed until \`*verify\` runs against the running app.` — when it didn't.

### 6. Render to HTML (human doc)

Render each produced markdown to a sibling `.html` via `.tfcore/tasks/generate-html.md` (shared shell — light/dark theme, TOC, mermaid toolbar). The DevGuide **is** a human-readable doc, so it gets HTML (unlike the checklists). For a split guide, render the index + every role file **in place inside `docs/devguides/`** (each `.html` sits beside its `.md`).

### 6a. Log confirmed defects into the checklists (the findings must reach the source of truth)

Mapping the code as-built routinely surfaces real defects — a Save handler that's a no-op, a page missing `[Authorize]`, a GET/POST (405) mismatch, stubbed/hard-coded data, an unwired stat, a value that's never persisted, a route the menu points at that doesn't exist. **These are exactly the "verifier passed but it's still buggy" issues the guide exists to expose, and they MUST land in the tracked source of truth — the checklist Requirements Status tables — not only in the DevGuide prose.** A finding logged only in the DevGuide gets lost.

For each **confirmed** defect (not a `{unresolved — TODO}` you couldn't verify):
- Map the affected screen → its owning `REQ-*` using the checklist's Page-details sections (which list which REQ covers which screen). UI defects → `docs/{AppName}-UI-Checklist.md`; functional/data/API defects → `docs/{AppName}-Functional-Checklist.md`.
- **Append** (never overwrite) a dated note to that REQ's **Remarks** cell: `⚠ DevGuide {date}: {one-line defect + file:line}`.
- If the defect means the feature does **not** work as specified (no-op, missing auth, 405, won't-compile, stub data, never-persisted), set that REQ's **Status to `Needs re-verify`** and lower `%` to reflect reality. **Never mark anything `Verified`**, and do **not** downgrade an item whose only gap is externally-blocked-but-correct (e.g. needs a live dependency) — add a remark only.
- For a `{unresolved — TODO}` (a hop you could not confirm from code): add a Remarks note flagging it for review, but do **not** change Status (uncertain ≠ defect).
- **Runtime-confirmed defects from §5a (OBSERVE) are logged the same way and carry the strongest evidence** — an observed RENDER-EMPTY/RENDER-ERROR control with a screenshot is a hard defect, not a suspicion; flag its REQ `Needs re-verify` with the observed note. (When OBSERVE could not run — STATIC-ONLY — these are static *suspicions*; still log them, but say "static — confirm at runtime".)
- These are **markdown-only** edits to the checklist tables — do NOT render the checklists to HTML.

### 7. Note it in PROJECT-STATUS (light touch — NOT the full gate)

Add/refresh one line under "Where I am" / artifacts: `DevGuide generated {date}: docs/{AppName}-DevGuide.md (single) or docs/devguides/ (split) (+ .html); {N} defects logged to the checklists`. This task does not change build/verify state, so do not touch `current_phase` or `last_verified_build`; the only Requirements Status table edits allowed are the §6a defect remarks/flags. Re-render `PROJECT-STATUS.html` only if you edited it.

### 8. HALT — report

```
# DevGuide — {AppName}
Structure: {single | split per role (R files)}
Verification: {✅ runtime-verified {date} as {roles} | ⚠ STATIC-ONLY — not yet runtime-verified}
Roles: {list}   Screens documented: {M}   Unresolved paths: {k (listed below)}
Render defects found at runtime: {r (controls observed empty/error — logged to checklist)}
Files: docs/{AppName}-DevGuide.md (single) — or, split, docs/devguides/{AppName}-DevGuide.md + -{Role}.md ... — and sibling .html
{if any} Unresolved lineage (code path not found — review): screen/control → reason
Next: {if static-only → "run `*verify {scope}` (or re-run `*devguide`) with the app up to runtime-confirm render-status"} ; open the .html in a browser to chase bugs.
```

## Hard rules

- **Never edit source code.** Read-only mapping of the as-built code into a doc.
- **No hallucinated paths or inferred routing.** Every service/data-access/proc name in a lineage row must be a real symbol you READ in the code; if you can't confirm it, mark `{unresolved — TODO}`. **Never infer a screen's post-login landing or "reached via" from folder/role names — read the redirect code and cite file:line** (LANDING-TRUTH, §4). Inventing a plausible proc name, or asserting a landing page you didn't trace, defeats the guide's entire purpose (catching AI hallucination — the framework exists to FIND bugs, not generate confident-but-wrong docs).
- **Render-truth over method-existence (§4).** "The method/proc exists" is not "the control works". Verify data actually reaches and renders — guards, column→property mapping, throwing computed getters, undeclared required component params. Mark each control renders / renders-empty (suspected defect) / unresolved, and log suspected defects to the checklist (§6a).
- **Render-status must be OBSERVED, not inferred (§5a).** The strongest version of render-truth is running the app. Always attempt the OBSERVE pass (reuse the verifier); write control render-status from what you saw at runtime. If the app could not be booted, stamp the guide `⚠ STATIC-ONLY — NOT runtime-verified` and mark control status `static-only (unconfirmed)` — NEVER present a static "renders ✓" as confirmed. Every index + area file carries the verification-status banner.
- **Checklists stay markdown; the DevGuide is human-readable and IS rendered to HTML.** Do not confuse the two.
- **Incremental by default when re-running.** Preserve unchanged screen entries verbatim; only remap what changed or what `{Scope}` names. Don't burn tokens regenerating a 60-screen guide to fix one screen.
- **Confirmed defects go into the checklists (§6a).** A bug found while mapping but logged only in the DevGuide prose is lost — route every confirmed defect to its owning `REQ-*` Remarks (and flag `Needs re-verify` when it means the feature doesn't work). Never mark anything `Verified`; never downgrade an externally-blocked-but-correct item.
- **Token discipline:** fan out per role/cluster (§4) rather than loading the whole repo into one context. See `.tfcore/TOKEN-GUIDE.md`.

## Output Checklist

- [ ] Built code confirmed present (HALT if doc-only)
- [ ] Roles + menus + screens discovered and reconciled (UsageGuide ↔ code authorization)
- [ ] Structure decided (single vs split per role) with stated reason / honored `--single`/`--split`
- [ ] **Split guides written to `docs/devguides/`** (index + role files co-located there); single guides kept at `docs/{AppName}-DevGuide.md`; no stale copy left in the other location after a structure switch
- [ ] Each screen has: route + Razor file, flowchart, Controls table, full Data lineage (Razor → service → data-access → proc/query), business rules, known issues
- [ ] **Landing-truth:** every "reached via" / post-login landing was READ from the redirect/routing code and cites file:line — none inferred from folder/role names
- [ ] **Render-truth:** each control tagged renders / renders-empty (suspected defect, with reason) / unresolved — guards, column→property mapping, computed getters, and required component params (e.g. an undeclared `pagination`) checked; not just method-existence
- [ ] Code paths verified real (no invented proc/method names; unresolved ones flagged `{unresolved — TODO}`)
- [ ] **OBSERVE pass attempted (§5a):** the app was booted and each control's render-status was observed at runtime (reusing the verifier render sweep) — OR the guide is stamped `⚠ STATIC-ONLY` because the stack couldn't be booted (never a faked "renders ✓")
- [ ] **Verification-status banner** present on the index AND every area file (✅ runtime-verified {date}/{roles}, or ⚠ STATIC-ONLY)
- [ ] Runtime-observed RENDER-EMPTY/ERROR deviations logged to the checklist as defects (§6a)
- [ ] Every Mermaid diagram passes the §5.5 self-check
- [ ] Markdown + sibling HTML produced (index + role files if split); checklists NOT rendered
- [ ] Confirmed defects logged into the owning checklist Requirements Status tables (Remarks + `Needs re-verify` where the feature is broken; never `Verified`; markdown only, no checklist HTML)
- [ ] PROJECT-STATUS got the one-line DevGuide note incl. defect count (no full status gate)
- [ ] Report printed with structure, counts, defects logged, and any unresolved paths

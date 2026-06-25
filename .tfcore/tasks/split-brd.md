# split-brd

Split the BRD into the two AI-targeted requirement docs: UI Checklist and Functional Checklist.

## Purpose

The BRD captures business intent with `BRD-N` IDs. Implementation needs finer-grained, type-tagged requirements that route to the right agent:
- `REQ-UI-*` → trblazeui agent (Claude Code `/trblazeui`, OpenCode `/trblazeui`)
- `REQ-FN-*` → flow-master agent (Claude Code `/TechieFlow:agents:flow-master`, OpenCode `/flow-master`)
- `REQ-RAG-*` → techierag agent (Claude Code `/techierag`, OpenCode `/techierag`)
- `REQ-NFR-*` → flow-master agent (cross-cutting checks)

This task converts each `BRD-N` into one or more `REQ-*` items, sorted into the two AI-only docs.

## Inputs

- `{AppName}` argument (required; or resolve from core-config.yaml).

## SEQUENTIAL Execution

### 1. Load inputs

- `docs/{AppName}-BRD.md` — must exist. Parse `BRD-N` IDs and their text.
- `docs/{AppName}-Architecture.md` — read for module boundaries and stack.

### 2. Classify each BRD-N

For each `BRD-N`, classify as UI / FN / RAG / NFR:
- **UI**: any user-visible change — page, component, form, dashboard, layout.
- **RAG**: anything involving LLM, embedding, vector search, chat, prompt templates, token tracking, tool calling.
- **NFR**: performance, security, accessibility, observability, compliance.
- **FN**: everything else — backend logic, data, APIs, integrations, business rules.

A single `BRD-N` may map to multiple REQs (e.g. a "settings page that saves to DB" splits into REQ-UI-N (the page) and REQ-FN-N (the save handler)).

### 2.5. Dev-plan seeding (CONDITIONAL — brownfield projects with an existing plan)

Check `docs/` for an existing development/phase plan (`*Development-Plan*.md`, `*Dev-Plan*.md`, `*Implementation-Plan*.md`, `*Roadmap*.md`, or any doc structured as Phase 0/1/2… with build order/statuses). If one exists:

- Carry its phase structure into §3/§4 — tag each REQ with its phase (e.g. `(BRD-21, Phase 1)`) and order sections by phase.
- **Preserve every column the plan tracked** — the new Requirements Status table must be a SUPERSET of the plan's, never a lossy summary. For each migrated REQ fill Status, **%**, **Remarks**, Details: carry the plan's `% Done` verbatim and its full dated status remark (e.g. "Completed 2026-04-30 (DTOs split…)") into Remarks — do not truncate.
- COMPLETE/done/shipped → Status `Done (pre-existing)`, `%` = plan's figure (usually `100%`), Remarks = plan's note + `per {plan-file} §{section}`. Build agents must NOT rebuild these. Partial → `In Progress`/`PARTIAL` with the plan's `%`+remark. Not started → `Not Started`, `0%`.
- Add a header note to both output docs: `> Migrated from {plan-file} on {YYYY-MM-DD}. Phase structure, completion %, and status remarks carried over verbatim — verify before building.`
- Do not modify the plan file's content. After migration it is superseded — move it unchanged to `docs/OldDocs/` (create the folder if missing; date-suffix on name collision) and note this in the §6 summary.

If no plan exists, skip — classify purely from the BRD.

### 3. Write `docs/{AppName}-UI-Checklist.md`

Schema per `.tfcore/templates/v4custom/app-ui-checklist-tmpl.md` — the **Requirements Status** table sits at the TOP (single source of truth), the per-REQ detail follows with `<a id="d-REQ-ID">` anchors the Details column links to:
```markdown
# {AppName} — UI Mockup Checklist

## Scope
{one paragraph derived from the BRD's UI-related BRD-N items}

## Requirements Status
| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-UI-001 | {short name} | Not Started | 0% | — | [view](#d-req-ui-001) |
{Status values + % guide + Remarks note — copy the legend from the template}

## Page details

### Page: {page name} (`{route}`)
<a id="d-req-ui-001"></a>
- **REQ-UI-001** — {description; traces to BRD-X}
  - *Acceptance:* {specific testable criterion}
```

Cross-link: every REQ-UI-N's description ends with `(BRD-X)` so traceability is two-way.

### 4. Write `docs/{AppName}-Functional-Checklist.md`

Schema per `.tfcore/templates/v4custom/app-functional-checklist-tmpl.md` — **Requirements Status** table at the TOP (single source of truth), detail sections below with `<a id="d-REQ-ID">` anchors:
```markdown
# {AppName} — Functional Checklist

## Goal
{one paragraph; ties back to BRD §1}

## Requirements Status
| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-FN-001  | {short name} | Not Started | 0% | — | [view](#d-req-fn-001) |
| REQ-RAG-001 | {short name} | Not Started | 0% | — | [view](#d-req-rag-001) |
| REQ-NFR-001 | {short name} | Not Started | 0% | — | [view](#d-req-nfr-001) |
{Status values + % guide + Remarks note — copy the legend from the template}

## Functional requirements
<a id="d-req-fn-001"></a>
- **REQ-FN-001** — {trigger / acceptance} (BRD-X)

## RAG / AI / LLM requirements (route to /techierag)
<a id="d-req-rag-001"></a>
- **REQ-RAG-001** — {trigger / acceptance via TechieRag} (BRD-X)

## Non-functional requirements
<a id="d-req-nfr-001"></a>
- **REQ-NFR-001** — {perf/security/accessibility} (BRD-X)
```

Same `(BRD-X)` back-link for every REQ.

### 5. Trace check

- Every `BRD-N` should appear at least once in the union of UI-Checklist and Functional Checklist.
- If any `BRD-N` is unmapped, list it in the output summary and ask: "BRD-X has no REQ. Is it deferred, or should I map it now?"

### 6. Output summary

Report counts:
- `K` `REQ-UI-*` items in UI Checklist
- `M` `REQ-FN-*`, `N` `REQ-RAG-*`, `P` `REQ-NFR-*` in Functional Checklist
- Any unmapped `BRD-N`s flagged in §5

Update `PROJECT-STATUS.md` per `.tfcore/tasks/_status-update-gate.md` (this task counts as a phase — the gate applies):
- Pick the next phase by the FIRST category with OPEN (non-terminal) REQs, in order UI → RAG → FN/NFR (dev-plan seeding in §2.5 may have pre-marked whole categories `Done (pre-existing)`):
  - Open `REQ-UI-*` → current_phase `UI build`, Next command `/trblazeui Follow .tfcore/tasks/build-ui-phase.md for the app {AppName}.` (trblazeui is NuGet-deployed and has no `*command` syntax — freeform follow-task prompt.)
  - Else open `REQ-RAG-*` → Next command `/techierag Follow .tfcore/tasks/build-rag-phase.md for the app {AppName}.`
  - Else open `REQ-FN-*`/`REQ-NFR-*` → current_phase `Functional build`, Next command `/TechieFlow:agents:flow-master *build-functional-phase {AppName}`.
- `last_updated`: today. Leave `last_verified_build`/`last_verified_date` as-is (no build this phase).
- Sync "Open requirements" to the two new Status tables (everything non-terminal).
- Append a row to "Verification log" — N/A (no verify yet)
- List unmapped open requirements if any
- Re-render `PROJECT-STATUS.html` (gate minimum #8). Do NOT render the checklists to HTML — they are AI-agent working documents (markdown only).

## Output Checklist

- [ ] `docs/{AppName}-UI-Checklist.md` exists with REQ-UI-* IDs each back-linking to BRD-N
- [ ] `docs/{AppName}-Functional-Checklist.md` exists with REQ-FN/RAG/NFR-* IDs each back-linking to BRD-N
- [ ] Every `BRD-N` is mapped or explicitly deferred
- [ ] `PROJECT-STATUS.md` updated with new phase + next command

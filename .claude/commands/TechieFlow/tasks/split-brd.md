# split-brd

Split the BRD into the single AI-targeted requirement doc: the app Checklist (`docs/{AppName}-Checklist.md`).

## Purpose

The BRD captures business intent with `BRD-N` IDs. Implementation needs finer-grained, type-tagged requirements. There is **one checklist per app**; the requirement *type* is carried by the REQ prefix, which routes work to the right builder:
- `REQ-UI-*` → built by `/trblazeui` (from the approved mockups), invoked as a sub-agent by the unified `build-phase`
- `REQ-RAG-*` → built by `/techierag`, invoked as a sub-agent by `build-phase`
- `REQ-FN-*` / `REQ-NFR-*` → built directly by `build-phase` (flow-master)

This task converts each `BRD-N` into one or more `REQ-*` items inside the one checklist.

## Inputs

- `{AppName}` argument (required; or resolve from core-config.yaml).

## SEQUENTIAL Execution

### 1. Load inputs

- `docs/{AppName}-BRD.md` — must exist. Parse `BRD-N` IDs and their text.
- `docs/{AppName}-Architecture.md` — read for module boundaries and stack.
- `docs/{AppName}-UIDesign.md` + `docs/mockups/*.html` — if they exist (greenfield, post-`*mockups`), read them so each `REQ-UI-*` cites the mockup screen it realizes.

### 2. Classify each BRD-N

For each `BRD-N`, classify as UI / FN / RAG / NFR:
- **UI**: any user-visible change — page, component, form, dashboard, layout.
- **RAG**: anything involving LLM, embedding, vector search, chat, prompt templates, token tracking, tool calling.
- **NFR**: performance, security, accessibility, observability, compliance.
- **FN**: everything else — backend logic, data, APIs, integrations, business rules.

A single `BRD-N` may map to multiple REQs (e.g. a "settings page that saves to DB" splits into REQ-UI-N (the page) and REQ-FN-N (the save handler)).

### 2.5. Dev-plan seeding (CONDITIONAL — brownfield projects with an existing plan)

Check `docs/` for an existing development/phase plan (`*Development-Plan*.md`, `*Dev-Plan*.md`, `*Implementation-Plan*.md`, `*Roadmap*.md`, or any doc structured as Phase 0/1/2… with build order/statuses). If one exists:

- Carry its phase structure into §3 — tag each REQ with its phase (e.g. `(BRD-21, Phase 1)`) and order rows by phase.
- **Preserve every column the plan tracked** — the Requirements Status table must be a SUPERSET of the plan's, never a lossy summary. For each migrated REQ fill Status, **%**, **Remarks**, Details: carry the plan's `% Done` verbatim and its full dated status remark (e.g. "Completed 2026-04-30 (DTOs split…)") into Remarks — do not truncate.
- COMPLETE/done/shipped → Status `Done (pre-existing)`, `%` = plan's figure (usually `100%`), Remarks = plan's note + `per {plan-file} §{section}`. Build agents must NOT rebuild these. Partial → `In Progress`/`PARTIAL` with the plan's `%`+remark. Not started → `Not Started`, `0%`.
- Add a header note to the checklist: `> Migrated from {plan-file} on {YYYY-MM-DD}. Phase structure, completion %, and status remarks carried over verbatim — verify before building.`
- Do not modify the plan file's content. After migration it is superseded — move it unchanged to `docs/OldDocs/` (create the folder if missing; date-suffix on name collision) and note this in the §6 summary.

If no plan exists, skip — classify purely from the BRD.

### 3. Write `docs/{AppName}-Checklist.md`

Schema per `.tfcore/templates/v4custom/app-checklist-tmpl.md` — the **Requirements Status** table sits at the TOP (single source of truth for the WHOLE app), with all REQ classes in one table, and the per-REQ detail follows in prefix-grouped sections with `<a id="d-REQ-ID">` anchors the Details column links to:
```markdown
# {AppName} — Checklist

## Goal
{one paragraph; ties back to BRD §1}

## Requirements Status
| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-UI-001  | {short name} | Not Started | 0% | — | [view](#d-req-ui-001) |
| REQ-FN-001  | {short name} | Not Started | 0% | — | [view](#d-req-fn-001) |
| REQ-RAG-001 | {short name} | Not Started | 0% | — | [view](#d-req-rag-001) |
| REQ-NFR-001 | {short name} | Not Started | 0% | — | [view](#d-req-nfr-001) |
{Status values + % guide + Remarks note — copy the legend from the template}

## UI / Pages
### Page: {page name} (`{route}`)
<a id="d-req-ui-001"></a>
- **REQ-UI-001** — {description; traces to BRD-X}. *Mockup:* docs/mockups/{screen}.html (if mockups exist).
  - *Acceptance:* {specific testable criterion}; controls do not overlap at desktop + mobile widths (visual gate).

## Functional requirements
<a id="d-req-fn-001"></a>
- **REQ-FN-001** — {trigger / acceptance} (BRD-X)

<!-- If the source BRD NFR carried a `perf-budget:` line, copy it into the REQ's Acceptance
     bullet VERBATIM — same grammar, same numbers. verify-phase §4c reads it literally and
     grades speed only where it exists. Never synthesize one for an NFR that lacked it, and
     never drop one that was there: both silently change what "Verified" means for that REQ. -->


## RAG / AI requirements (→ /techierag)
<a id="d-req-rag-001"></a>
- **REQ-RAG-001** — {trigger / acceptance via TechieRag} (BRD-X)

## Non-functional
<a id="d-req-nfr-001"></a>
- **REQ-NFR-001** — {perf/security/accessibility} (BRD-X)
```

Cross-link: every REQ-N's description ends with `(BRD-X)` so traceability is two-way.

### 4. Trace check

- Every `BRD-N` should appear at least once in the checklist's Requirements Status table.
- If any `BRD-N` is unmapped, list it in the output summary and ask: "BRD-X has no REQ. Is it deferred, or should I map it now?"

### 5. Output summary

Report counts:
- `K` `REQ-UI-*`, `M` `REQ-FN-*`, `N` `REQ-RAG-*`, `P` `REQ-NFR-*` items in the checklist
- Any unmapped `BRD-N`s flagged in §4

Update `PROJECT-STATUS.md` per `.tfcore/tasks/_status-update-gate.md` (this task counts as a phase — the gate applies):
- Next phase is always the unified build while any REQ is open: current_phase `Build`, Next command `/TechieFlow:agents:flow-master *build-phase {AppName}` (OpenCode: `/flow-master *build-phase {AppName}`). `build-phase` clusters all open REQs and calls `/trblazeui` (REQ-UI-*, from the mockups) and `/techierag` (REQ-RAG-*) as sub-agents itself — you do NOT point the user at a separate UI or RAG command.
- `last_updated`: today. Leave `last_verified_build`/`last_verified_date` as-is (no build this phase).
- Sync "Open requirements" to the new Status table (everything non-terminal).
- Append a row to "Verification log" — N/A (no verify yet)
- List unmapped open requirements if any
- Re-render `PROJECT-STATUS.html` (gate minimum #8). Do NOT render the checklist to HTML — it is an AI-agent working document (markdown only).

### 6. Emit the run record (telemetry)

Same turn as the status/PROJECT-STATUS write. Doctrine + the nine constraints: `.tfcore/tasks/_metrics-emit-gate.md`. Schema: `.tfcore/telemetry/SCHEMA.md` §2. Stamp `started` with `date -u +%Y-%m-%dT%H:%M:%SZ` as your FIRST action of this task — it cannot be reconstructed at the end.

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"split-brd","mode":null,
 "started":"<start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":[],"reqs_count":0,
 "subagents":[],"files_written":<n>,"build_result":"not-run"}
JSON
```

`reqs_touched` carries REQ IDs only — never requirement text — and `[]` is correct when this task touched no specific REQ. **Telemetry has no veto:** if the emit fails, the phase still succeeded; do not retry, do not diagnose, do not mention it.

## Output Checklist

- [ ] `docs/{AppName}-Checklist.md` exists with REQ-UI/FN/RAG/NFR-* IDs each back-linking to BRD-N, in one Requirements Status table
- [ ] Every `BRD-N` is mapped or explicitly deferred
- [ ] `PROJECT-STATUS.md` updated with `Build` phase + `*build-phase` next command (+ re-rendered HTML)

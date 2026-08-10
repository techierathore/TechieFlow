# {AppName} — Checklist

## Table of Contents

<!-- Auto-maintained. Slug rule: .tfcore/templates/v4custom/html-render-shell.md §1. Update when sections change. As pages grow, list each `### Page: ...` as an H3 sub-entry under "UI / Pages". -->

1. [Goal](#goal)
2. [Requirements Status](#requirements-status)
3. [UI / Pages](#ui--pages)
4. [Functional requirements](#functional-requirements)
5. [RAG / AI requirements (→ /techierag)](#rag-ai-requirements-techierag)
6. [Non-functional](#non-functional)

## Goal
<one paragraph; ties back to BRD §1. This single checklist is the whole app's work list — UI, functional, RAG, and NFR requirements live together, distinguished only by their REQ prefix.>

## Requirements Status

<!-- ============================================================
     SINGLE SOURCE OF TRUTH for the WHOLE app (UI + functional +
     RAG + NFR). There is exactly ONE checklist per app — the two
     former files (UI-Checklist / Functional-Checklist) were merged
     into this one. Build, self-smoke, and the verifier ALL write
     their outcomes into THIS table — never into a separate dated
     results file. One row per REQ, grouped by prefix:
       REQ-UI-*  → built by /trblazeui (from the mockups)
       REQ-FN-*  → built by the unified build-phase
       REQ-RAG-* → built by /techierag
       REQ-NFR-* → built by the unified build-phase
     Scopes (`*verify ui|functional|all`) filter THIS table by
     prefix — they do NOT pick a separate file. Update Status + % +
     Remarks every time work (implementation, smoke, or verify)
     touches the REQ. Bugs and change notes live in the Remarks
     column, NOT in docs/qa/*.md.
     ============================================================ -->

| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-UI-001  | Dashboard top nav | Not Started | 0% | — | [view](#d-req-ui-001) |
| REQ-FN-001  | <short name> | Not Started | 0% | — | [view](#d-req-fn-001) |
| REQ-RAG-001 | <short name> | Not Started | 0% | — | [view](#d-req-rag-001) |
| REQ-NFR-001 | <short name> | Not Started | 0% | — | [view](#d-req-nfr-001) |

**Status values:** `Not Started` · `In Progress` · `Implemented` (code done, not yet verified) · `Verified` (self-smoke or verifier PASS — acceptance AND data-render AND visual gates all pass) · `Done (pre-existing)` (migrated from an earlier dev plan as already complete — build agents must NOT rebuild; terminal like `Verified`) · `Needs re-verify` (a defect or change was logged — must be re-run before it can return to `Verified`) · `PARTIAL` (some acceptance unmet — say what in Remarks) · `FAIL` (verifier ran and failed — bug in Remarks) · `Blocked` (external/library gap — link the TR-/TR-RAG- entry in Remarks) · `N/A`.

**% guide:** `0` not started · `25` scaffolded · `50` in progress · `75` implemented-unverified · `100` verified.

**Remarks:** date + what was done / what is missing / bug or library reference. This is the home for bugs and change notes — do not spawn a separate file. Visual-gate failures are prefixed `⚠ visual:`; security findings `⚠ SECURITY`.

## UI / Pages

<!-- Each REQ carries an explicit `<a id="d-REQ-ID">` anchor (lowercase) so the
     Details column above links straight to it in both Markdown and rendered HTML.
     UI REQs are built by /trblazeui from the approved mockups (docs/{AppName}-UIDesign.md
     + docs/mockups/*.html); cite the mockup screen each REQ realizes.

     A REQ whose BRD NFR declared a `perf-budget:` carries that line VERBATIM in its
     Acceptance bullet — split-brd copies it across unchanged. It is machine-read by
     verify-phase §4c, which grades speed only where such a line exists. Never add one
     that the BRD did not state, and never paraphrase it: the grammar is
         perf-budget: <p50|p95|max> <ttfb|load> <= <N>ms [@ concurrency <N>] -->


### Page: Dashboard (`/dashboard`)

<a id="d-req-ui-001"></a>
- **REQ-UI-001** — TrBlazeUI top nav (logo, user menu, theme toggle). *Mockup:* docs/mockups/dashboard.html.
  - *Acceptance:* page renders; nav fixed-top; theme toggle persists in localStorage; controls do not overlap at desktop + mobile widths (visual gate).

## Functional requirements

<a id="d-req-fn-001"></a>
- **REQ-FN-001** — <trigger / acceptance>.

<!-- Example of a perf-gated NFR row (only where the BRD declared the budget):
<a id="d-req-nfr-001"></a>
- **REQ-NFR-001** — Public pages stay responsive under normal load. (BRD-N)
  - *Acceptance:* pages return 200 and render their data; perf-budget: p95 load <= 2000ms @ concurrency 1
-->


## RAG / AI requirements (→ /techierag)

<a id="d-req-rag-001"></a>
- **REQ-RAG-001** — <trigger / acceptance via TechieRag>.

## Non-functional

<a id="d-req-nfr-001"></a>
- **REQ-NFR-001** — <perf / security / accessibility>.

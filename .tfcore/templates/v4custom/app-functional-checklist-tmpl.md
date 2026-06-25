# {AppName} — Functional Checklist

## Table of Contents

<!-- Auto-maintained. Slug rule: .tfcore/templates/v4custom/html-render-shell.md §1. Update when sections change. -->

1. [Goal](#goal)
2. [Requirements Status](#requirements-status)
3. [Functional requirements](#functional-requirements)
4. [RAG / AI requirements (→ /techierag)](#rag-ai-requirements-techierag)
5. [Non-functional](#non-functional)

## Goal
<one paragraph; ties back to BRD §1>

## Requirements Status

<!-- ============================================================
     SINGLE SOURCE OF TRUTH for the functional / RAG / NFR scope.
     Build, self-smoke, and the verifier ALL write their outcomes
     into THIS table — never into a separate dated results file.
     One row per REQ. Update Status + % + Remarks every time work
     (implementation, smoke, or verify) touches the REQ. Bugs and
     change notes live in the Remarks column, NOT in docs/qa/*.md.
     ============================================================ -->

| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-FN-001  | <short name> | Not Started | 0% | — | [view](#d-req-fn-001) |
| REQ-RAG-001 | <short name> | Not Started | 0% | — | [view](#d-req-rag-001) |
| REQ-NFR-001 | <short name> | Not Started | 0% | — | [view](#d-req-nfr-001) |

**Status values:** `Not Started` · `In Progress` · `Implemented` (code done, not yet verified) · `Verified` (self-smoke or verifier PASS) · `Done (pre-existing)` (migrated from an earlier dev plan as already complete — build agents must NOT rebuild; terminal like `Verified`) · `PARTIAL` (some acceptance unmet — say what in Remarks) · `FAIL` (verifier ran and failed — bug in Remarks) · `Blocked` (external/library gap — link the TR-/TR-RAG- entry in Remarks) · `N/A`.

**% guide:** `0` not started · `25` scaffolded · `50` in progress · `75` implemented-unverified · `100` verified.

**Remarks:** date + what was done / what is missing / bug or library reference. This is the home for bugs and change notes — do not spawn a separate file.

## Functional requirements

<!-- Each REQ carries an explicit `<a id="d-REQ-ID">` anchor so the Details column
     above links straight to it in both Markdown and rendered HTML. -->

<a id="d-req-fn-001"></a>
- **REQ-FN-001** — <trigger / acceptance>.

## RAG / AI requirements (→ /techierag)

<a id="d-req-rag-001"></a>
- **REQ-RAG-001** — <trigger / acceptance via TechieRag>.

## Non-functional

<a id="d-req-nfr-001"></a>
- **REQ-NFR-001** — <perf / security / accessibility>.

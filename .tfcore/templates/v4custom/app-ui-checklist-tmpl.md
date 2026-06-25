# {AppName} — UI Mockup Checklist

## Table of Contents

<!-- Auto-maintained. Slug rule: .tfcore/templates/v4custom/html-render-shell.md §1. Update when sections change. As pages grow, list each `### Page: ...` as an H3 sub-entry under "Page details". -->

1. [Scope](#scope)
2. [Requirements Status](#requirements-status)
3. [Page details](#page-details)

## Scope
<one paragraph: what UI is in scope for this build pass>

## Requirements Status

<!-- ============================================================
     SINGLE SOURCE OF TRUTH for this checklist.
     Build, self-smoke, and the verifier ALL write their outcomes
     into THIS table — never into a separate dated results file.
     One row per REQ. Update Status + % + Remarks every time work
     (implementation, smoke, or verify) touches the REQ. Bugs and
     change notes live in the Remarks column, NOT in docs/qa/*.md.
     ============================================================ -->

| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-UI-001 | Dashboard top nav | Not Started | 0% | — | [view](#d-req-ui-001) |

**Status values:** `Not Started` · `In Progress` · `Implemented` (code done, not yet verified) · `Verified` (self-smoke or verifier PASS) · `Done (pre-existing)` (migrated from an earlier dev plan as already complete — build agents must NOT rebuild; terminal like `Verified`) · `PARTIAL` (some acceptance unmet — say what in Remarks) · `FAIL` (verifier ran and failed — bug in Remarks) · `Blocked` (external/library gap — link the TR-/TR-RAG- entry in Remarks) · `N/A`.

**% guide:** `0` not started · `25` scaffolded · `50` in progress · `75` implemented-unverified · `100` verified.

**Remarks:** date + what was done / what is missing / bug or library reference. This is the home for bugs and change notes — do not spawn a separate file.

## Page details

<!-- Each REQ carries an explicit `<a id="d-REQ-ID">` anchor (lowercase) so the
     Details column above links straight to it in both Markdown and rendered HTML. -->

### Page: Dashboard (`/dashboard`)

<a id="d-req-ui-001"></a>
- **REQ-UI-001** — TrBlazeUI top nav (logo, user menu, theme toggle).
  - *Acceptance:* page renders; nav fixed-top; theme toggle persists in localStorage.

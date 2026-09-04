# MyDiary — Checklist

| | |
|---|---|
| App | MyDiary |
| Size | Small |

## Goal

Build the journal site described in the BRD.

## Requirements Status

| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-UI-001 | Login screen | Not Started | 0% | — | [view](#d-req-ui-001) |
| REQ-FN-001 | Search entries | Started | 10% | history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history history | [view](#d-req-fn-001) |
| REQ-NFR-001 | Entries list speed | Not Started | 0% | — | [view](#d-req-nfr-001) |

## Page: Login (`/login`)

<a id="d-req-ui-001"></a>
- **REQ-UI-001** — Login screen. *BRD:* BRD-1 · *Mockup:* mockups/login.html
  - *Acceptance:* login works.

## Page: Entries (`/entries`)

<a id="d-req-fn-001"></a>
- **REQ-FN-001** — Search entries. *BRD:* BRD-2
  - *Acceptance:* Given three entries exist, when the writer types `holiday` in the search box on Entries and presses Enter, then only entries containing `holiday` are listed.

## Non-functional

<a id="d-req-nfr-001"></a>
- **REQ-NFR-001** — Entries list speed. *BRD:* BRD-3
  - *Acceptance:* When the Entries list is measured with one user, then p95 load is within budget; perf-budget: p95 load <= 2000ms @ concurrency 1

## UAT Bugs

- a bug

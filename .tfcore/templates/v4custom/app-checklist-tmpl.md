<!-- tf-schema
doc: checklist
file: docs/{App}-Checklist.md
header: App, Size
section: Goal | required | max 120
section: Requirements Status | required
rule: checklist-rows
-->
<!-- Authoring notes (agent only). An agent document: never rendered, never reviewed by the owner.
     Sections: Goal, Requirements Status (the one table), then one section per page or group holding
     the detail entries. No other sections: bugs, UAT findings and feedback go to the misses stream.
     Row rules (tf-doc-check.sh refuses the file otherwise):
       - header exactly | ID | Requirement | Status | % | Remarks | Details |
       - ID is REQ-UI-, REQ-FN-, REQ-RAG- or REQ-NFR- plus three digits; row count within the size cap
       - Status is one of the fixed values; Verified is written only by a verify run (hook)
       - % is 0, 25, 50, 75 or 100
       - Details links to the entry's anchor in this file
       - every entry names its BRD-N item; UI rows link a mockup that exists
       - exactly one acceptance line per entry: "When <actor> <does what> on <screen>, then <observable result>"
         ("Given …," may precede it; NFR rows name the measurement instead of a screen)
       - a perf-budget line is copied verbatim from the BRD, never invented:
         perf-budget: <p50|p95|max> <ttfb|load> <= <N>ms [@ concurrency <N>]
       - Remarks holds the current state only, at most 60 words; history lives in gates.jsonl and misses.jsonl
     Prefix routing: REQ-UI- built from the mockups by the UI sub-agent; REQ-RAG- by the RAG sub-agent;
     REQ-FN- and REQ-NFR- by the build phase. `*verify ui|functional|all` filters this table by prefix. -->

# {App} — Checklist

| | |
|---|---|
| App | {App} |
| Size | Small, Medium or Large |

## Goal

{One paragraph tying back to the BRD summary. This single checklist is the whole work list.}

## Requirements Status

| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-UI-001 | {short name} | Not Started | 0% | — | [view](#d-req-ui-001) |
| REQ-FN-001 | {short name} | Not Started | 0% | — | [view](#d-req-fn-001) |
| REQ-NFR-001 | {short name} | Not Started | 0% | — | [view](#d-req-nfr-001) |

**Status values:** `Not Started` · `In Progress` · `Implemented` · `Verified` · `Done (pre-existing)` · `Needs re-verify` · `PARTIAL` · `FAIL` · `Blocked` · `N/A`.

## Page: {Screen name} (`/route`)

<a id="d-req-ui-001"></a>
- **REQ-UI-001** — {what the screen shows}. *BRD:* BRD-{N} · *Mockup:* mockups/{screen-slug}.html
  - *Acceptance:* When {actor} opens {screen}, then {what is visible, with real data, at desktop and mobile widths}.

<a id="d-req-fn-001"></a>
- **REQ-FN-001** — {what the user can do}. *BRD:* BRD-{N}
  - *Acceptance:* When {actor} {does what} on {screen}, then {observable result}.

## Non-functional

<a id="d-req-nfr-001"></a>
- **REQ-NFR-001** — {the requirement}. *BRD:* BRD-{N}
  - *Acceptance:* When {the measurement is taken}, then {the value within its limit}; perf-budget: p95 load <= 2000ms @ concurrency 1

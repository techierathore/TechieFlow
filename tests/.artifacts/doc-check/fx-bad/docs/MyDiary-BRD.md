# MyDiary — Business Requirements

| | |
|---|---|
| App | MyDiary |
| Kind | app |
| Size | Small |
| Stack answer set | dotnet |
| Status | Draft |
| Date | 2026-09-04 |

## 1. Summary

A private journal site. One user writes dated entries and finds them again later.

## 3. Users and roles

| Role | Who they are | What they need |
|---|---|---|
| Writer | the owner | write and find entries |

## 4. Screens and flow

| Screen | Route | Role | Mockup | Fields |
|---|---|---|---|---|
| Login | `/login` | Writer | [mockup](mockups/login.html) | email, password |
| Entries | `/entries` | Writer | [mockup](mockups/missing.html) | search, list |
| Edit entry (dialog) | on `/entries` | Writer | [mockup](mockups/entries.html) | title, body |

**Primary journey:**
1. The writer signs in and lands on Entries.
2. The writer searches for a word and opens an entry.

## 5. Requirements

- **BRD-1** — Sign in. *Screen:* Login · *Mockup:* [mockup](mockups/login.html)
  - *Acceptance:* When the writer enters a valid email and password on Login and presses Enter, then the Entries screen opens.
- **BRD-2** — Search entries. *Screen:* Entries · *Mockup:* [mockup](mockups/entries.html)
  - *Acceptance:* When the writer types `holiday` in the search box on Entries and presses Enter, then only entries containing `holiday` are listed.

## 6. Non-functional requirements

| Id | Area | Requirement | Measure |
|---|---|---|---|
| BRD-3 | Performance | Entries list is quick | perf-budget: p95 load <= 2000ms @ concurrency 1 |

## 7. Development status

**Snapshot as of 2026-09-04.**

| Screen | Requirements | Verified | Open | Status |
|---|---|---|---|---|
| Login | 1 | 0 | 1 | Planned |
| Entries | 2 | 0 | 2 | Planned |

## Feature catalog

Stray section.

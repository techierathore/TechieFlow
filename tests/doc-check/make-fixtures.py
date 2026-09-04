#!/usr/bin/env python3
"""Build a minimal passing document set for a fake Small app (MyDiary) and a broken twin."""
import os, shutil, sys

BASE = os.environ.get("TF_FIXTURE_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".artifacts", "doc-check")
GOOD = os.path.join(BASE, "fx-good")
BAD = os.path.join(BASE, "fx-bad")

BRD = """# MyDiary — Business Requirements

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

## 2. Scope

**In:**
- Write, edit, search entries.

**Out:**
- Sharing.

## 3. Users and roles

| Role | Who they are | What they need |
|---|---|---|
| Writer | the owner | write and find entries |

## 4. Screens and flow

| Screen | Route | Role | Mockup | Fields |
|---|---|---|---|---|
| Login | `/login` | Writer | [mockup](mockups/login.html) | email, password |
| Entries | `/entries` | Writer | [mockup](mockups/entries.html) | search, list |
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
"""

ARCH = """# MyDiary — Architecture

| | |
|---|---|
| App | MyDiary |
| Kind | app |
| Size | Small |
| Stack answer set | dotnet |
| Date | 2026-09-04 |

## 1. Stack decisions

| Q | Topic | Decision | Source |
|---|---|---|---|
| Q1 | Configuration | appsettings.json | answer set |
| Q4 | Authentication | AppManager | owner |

## 2. Solution structure

| Project | Kind | Purpose |
|---|---|---|
| `MyDiary` | web app | the head |
| `MyDiary.Tests` | test project | tests |

## 3. Component map

```mermaid
flowchart TB
  UI["UI"] --> Svc["Services"] --> Data["Data"]
```

**How a request travels:**
1. The page calls the entry service.
2. The service calls the entry data access.
3. Rows come back and the grid shows them.

## 4. Data model

```mermaid
erDiagram
  ENTRY {
    int EntryId PK
    string Title
  }
```

| Entity | Key fields | Notes |
|---|---|---|
| Entry | EntryId, Title, Body | one per day at most |

## 5. Cross-cutting

- **Identity:** AppManager API.
- **Configuration:** appsettings.json.
- **Logging:** Serilog file sink.
- **Errors:** problem details.

## 6. Decisions log

| Date | Decision | Why | Status |
|---|---|---|---|
| 2026-09-04 | Blazor Server | one process | decided |
"""

UI = """# MyDiary — UI Design

| | |
|---|---|
| App | MyDiary |
| Kind | app |
| Size | Small |
| UI library | TrBlazeUI 2.0 |
| Theme | both |

## Design system

- **Layout shell:** top nav.
- **Theme:** light and dark.
- **Shared controls:** TrNavMenu, TrCard.
- **Rules:** 8px grid.

## Screens

### Screen: Login (`/login`)

**Mockup:** [mockups/login.html](mockups/login.html) · **Roles:** Writer · **BRD:** BRD-1

| Region | Control | Shows or binds |
|---|---|---|
| Form | TrForm | email, password |

| Field | Type | Required | Validation |
|---|---|---|---|
| Email | text | yes | email form |
| Password | password | yes | 8 or more |

**Dialogs opened here:** none

**States:** empty: form blank · loading: button spinner · error: red alert under the form

### Screen: Entries (`/entries`)

**Mockup:** [mockups/entries.html](mockups/entries.html) · **Roles:** Writer · **BRD:** BRD-2

| Region | Control | Shows or binds |
|---|---|---|
| Search | TrTextBox | search term |
| List | TrDataGrid | entries |

| Field | Type | Required | Validation |
|---|---|---|---|
| Search | text | no | none |

**Dialogs opened here:** Edit entry: title, body

**States:** empty: "No entries yet" · loading: skeleton rows · error: alert
"""

CL = """# MyDiary — Checklist

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
| REQ-FN-001 | Search entries | Not Started | 0% | — | [view](#d-req-fn-001) |
| REQ-NFR-001 | Entries list speed | Not Started | 0% | — | [view](#d-req-nfr-001) |

## Page: Login (`/login`)

<a id="d-req-ui-001"></a>
- **REQ-UI-001** — Login screen. *BRD:* BRD-1 · *Mockup:* mockups/login.html
  - *Acceptance:* When the writer enters a valid email and password on Login and presses Enter, then the Entries screen opens.

## Page: Entries (`/entries`)

<a id="d-req-fn-001"></a>
- **REQ-FN-001** — Search entries. *BRD:* BRD-2
  - *Acceptance:* Given three entries exist, when the writer types `holiday` in the search box on Entries and presses Enter, then only entries containing `holiday` are listed.

## Non-functional

<a id="d-req-nfr-001"></a>
- **REQ-NFR-001** — Entries list speed. *BRD:* BRD-3
  - *Acceptance:* When the Entries list is measured with one user, then p95 load is within budget; perf-budget: p95 load <= 2000ms @ concurrency 1
"""

CS = """# MyDiary — Coding Standards

| | |
|---|---|
| App | MyDiary |
| Stack answer set | dotnet |
| Date | 2026-09-04 |

## Standards applied

| File | Applies | Notes |
|---|---|---|
| `.tfcore/standards/coding-standards-core.md` | yes | every project |
| `.tfcore/standards/coding-standards-dotnet.md` | yes | .NET answer set |

| Choice | Decision |
|---|---|
| Instance-field prefix | obj |

## Project rules

| Rule | Why | Since |
|---|---|---|

## Enforcement

- **Editor configuration:** `.editorconfig` at the root.
- **Analyzers:** none.
- **Verifier checks:** the stack file's greps.
"""

PS = """---
project: MyDiary
last_updated: 2026-09-04
current_phase: Day-1 — documents drafted
last_verified_build: not-run
last_verified_date: 2026-09-04
---

# MyDiary — Status

## Where I am

Day-1 documents drafted. Nothing built.

## Next command to run

Claude Code:
```
/TechieFlow:agents:flow-master *build-phase MyDiary
```
OpenCode:
```
/flow-master *build-phase MyDiary
```

## Open requirements

| Status | Count |
|---|---|
| Not Started | 3 |

- [ ] REQ-UI-001 — Login screen

## Known blockers

- None

## Verification log

| Date | Phase | Result | Status table |
|---|---|---|---|
| 2026-09-04 | day-1 | documents only | docs/MyDiary-Checklist.md#requirements-status |

## Library feedback summary

- TrBlazeUI: 0 open

## Standards compliance

- not yet run

## Deferred / future

- none
"""

UG = """# MyDiary — Usage Guide

| | |
|---|---|
| App | MyDiary |
| Kind | app |
| Size | Small |
| Date | 2026-09-04 |

## Test users

| # | User | Password source | Role | Exists |
|---|---|---|---|---|
| 1 | writer@app.test | user secrets | Writer | no |

## Execution guide

Prerequisites: .NET 9 SDK, PostgreSQL in Docker.

```
dotnet restore
dotnet run --project src/MyDiary --urls http://localhost:5099
```

Open http://localhost:5099 and sign in as user 1.

## How to test, screen by screen

### Login
- **Sign in as:** 1
- **Steps:** 1) open /login 2) enter email and password 3) press Enter
- **Expected:** Entries opens
- **Covers:** REQ-UI-001

## Automated tests

```
dotnet test
```
Unit tests for the entry service.

## Known limitations

- none
"""

DG = """# MyDiary — Developer Guide

| | |
|---|---|
| App | MyDiary |
| Kind | app |
| Size | Small |
| Verified on | 2026-09-04 |
| Date | 2026-09-04 |

## Architecture cheat-sheet

| Layer | Project or folder | What lives here |
|---|---|---|
| UI | `src/MyDiary/Pages` | pages |

## Roles and menu map

| Role | Test user | Menu items and the screen each opens |
|---|---|---|
| Writer | 1 | Entries → Entries (`/entries`) |

## Screen-by-screen code map

### Login (`/login`)

![Login](screenshots/MyDiary/login.png)

**Call chain:** `Login.razor.cs:HandleLogin` → `AuthSvc.CheckLogin` → `UserDa.VerifyUser`

| File and line | Function | Watch | Expected value |
|---|---|---|---|
| `src/MyDiary/Pages/Login.razor.cs:127` | `HandleLogin` | `aLogin.Email` | the email typed in the box |

## Cross-cutting flows

### Sign-in
**Call chain:** as above.

## Known issues

- none
"""

PG = """# MyDiary — Product Guide

| | |
|---|---|
| App | MyDiary |
| Size | Small |
| Date | 2026-09-04 |

## Welcome

MyDiary is a private journal.

## Getting started

1. Open the site and sign in.
2. You land on Entries.

![Sign in](screenshots/MyDiary/login.png)

## Using MyDiary

### Write an entry

1. Press New.
2. Type a title and the text.
3. Press Save; the entry appears in the list.

![Write an entry](screenshots/MyDiary/entries.png)
"""

FILES = {
    "docs/MyDiary-BRD.md": BRD,
    "docs/MyDiary-Architecture.md": ARCH,
    "docs/MyDiary-UIDesign.md": UI,
    "docs/MyDiary-Checklist.md": CL,
    "docs/MyDiary-Coding-Standards.md": CS,
    "PROJECT-STATUS.md": PS,
    "docs/MyDiary-UsageGuide.md": UG,
    "docs/MyDiary-DevGuide.md": DG,
    "docs/MyDiary-ProductGuide.md": PG,
    "docs/mockups/login.html": "<html></html>",
    "docs/mockups/entries.html": "<html></html>",
    "docs/screenshots/MyDiary/login.png": "png",
    "docs/screenshots/MyDiary/entries.png": "png",
}


def write_set(root, files):
    if os.path.exists(root):
        shutil.rmtree(root)
    for rel, content in files.items():
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(content)


write_set(GOOD, FILES)

bad = dict(FILES)
bad["docs/MyDiary-BRD.md"] = (BRD.replace("## 2. Scope\n\n**In:**\n- Write, edit, search entries.\n\n**Out:**\n- Sharing.\n\n", "")
                             .replace("| Entries | `/entries` | Writer | [mockup](mockups/entries.html) | search, list |",
                                      "| Entries | `/entries` | Writer | [mockup](mockups/missing.html) | search, list |")
                             + "\n## Feature catalog\n\nStray section.\n")
bad["docs/MyDiary-Checklist.md"] = (CL.replace("*Acceptance:* When the writer enters a valid email and password on Login and presses Enter, then the Entries screen opens.",
                                               "*Acceptance:* login works.")
                                    .replace("| REQ-FN-001 | Search entries | Not Started | 0% | — |",
                                             "| REQ-FN-001 | Search entries | Started | 10% | " + " ".join(["history"] * 70) + " |")
                                    + "\n## UAT Bugs\n\n- a bug\n")
bad["PROJECT-STATUS.md"] = PS.replace("OpenCode:\n```\n/flow-master *build-phase MyDiary\n```\n", "").replace(
    "Day-1 documents drafted. Nothing built.", " ".join(["narrative"] * 90))
bad["docs/MyDiary-Architecture.md"] = ARCH.replace("```mermaid\n  erDiagram", "```mermaid\n  flowchart").replace(
    "## 6. Decisions log", "## 6. Deployment\n\nVPS.\n\n## 7. Decisions log")
bad["docs/MyDiary-UIDesign.md"] = UI.replace("**States:** empty: form blank · loading: button spinner · error: red alert under the form", "")
bad["docs/MyDiary-DevGuide.md"] = DG.replace("| `src/MyDiary/Pages/Login.razor.cs:127` | `HandleLogin` | `aLogin.Email` | the email typed in the box |\n", "").replace(
    "| File and line | Function | Watch | Expected value |\n|---|---|---|---|\n", "")
write_set(BAD, bad)
print("fixtures written:", GOOD, BAD)

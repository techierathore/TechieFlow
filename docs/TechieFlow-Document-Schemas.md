# TechieFlow — Document Schemas

| | |
|---|---|
| Purpose | For each human document the framework produces: which sections it must have, how big it may be, and what every row must contain. A checker script enforces this, so the AI cannot drift from the shape. |
| Audience | The owner (reviews the section lists, the size limits and the decisions in §7). Agents read the same rules in machine form at the top of each template. |
| Status | **Built in Session 3 of the reset and closed 2026-09-04.** Nine templates carry a schema block; `tf-doc-check.sh` enforces it; the status gate runs it; day-1 asks the size. §6 holds the real results on fourteen projects. The tenth document, the Deployment Checklist (§3.10), is agreed and is built in Sitting 4b. |
| Companion | `TechieFlow-Reset-Plan-2026-09-04.md` (Session 3), `TechieFlow-Requirements.md` (FR-07 to FR-09, FR-14, FR-15, FR-17), `TechieFlow-How-It-Works.md` §8 (D-1, D-2, D-3, D-20). |

---

## 1. How a schema works

Each template opens with a short block inside an HTML comment, so it never shows in a rendered page. The block says, in a fixed form:

- which file the template produces (`docs/<App>-BRD.md`);
- the required sections, in order, and the optional ones;
- the word budget for each size (Small, Medium, Large), as a target and a maximum;
- the rules every row or entry must follow.

One script, `tf-doc-check.sh`, reads the block for a document and checks the document against it. It prints one line per problem, in words a person can act on, and exits with a failure when anything is wrong. The status gate runs it on every human document a command wrote. A failing document means the phase does not close.

The owner does not read the machine blocks. This page is the readable version of the same rules.

---

## 2. Size, kind, and what counts as a screen

The size is chosen at day-1 and written into `core-config.yaml` and every document header. The definition was agreed on 2026-09-04 (D-3, FR-09):

| Size | Screens | Roles | Requirements |
|---|---|---|---|
| Small | up to 10 | one | up to 50 |
| Medium | up to 20 | any | up to 100 |
| Large | more than 20, or more than 100 requirements | any | split into phases; each phase is its own Small or Medium BRD, checklist and build |

**What counts as a screen** (owner, 2026-09-04). A screen is a page with its own route. Every routed page counts, including sign in, register, forgot password, reset password, and any licence, subscription or role screens. AppManager provides the API behind those screens; the application builds the screens. Dialogs, tabs and panels inside a page are regions of that page, not screens. They are listed under their parent screen in the UIDesign, drawn in that screen's mockup, and verified on that page. By this rule TfLens has thirteen screens, which is Medium by screens; its 169 requirements are beyond Medium in any case, which is the D-3 complaint.

A known defect follows from this and is logged as a miss (§8): the verifier today cannot drive a dialog, so dialogs have been built as separate routed screens to get them verified. Session 4c rewrites the verify task so a dialog is verified on its parent page, and the build never promotes a dialog to a route to make it testable.

**Kind.** A project is an `app` or a `library`. Kind sits beside Size. For a library the UIDesign and mockups are optional, and the screen maps become component maps:

- A UI library with a sample app (TrBlazeUI): the DevGuide's component map links every component to the sample-app screen that shows it, with that screen's screenshot.
- A service library (TechieRag): the component map is the consumer's view, one entry per service with how it is called, and it lives in the UsageGuide.

**Where the size and kind are asked.** Greenfield day-1 asks one more question after the concept: "Size: Small, Medium or Large? From the concept I count N screens and N roles, so I propose X." Brownfield day-1 counts the routes in the code and confirms the same way. The answer is written to `appSize:` and `appKind:` in `core-config.yaml` and into every document header. `*amend-docs` reads the cap from there and proposes a phase split when an addition would pass it (FR-10; wired in Session 4a).

---

## 3. The documents

For each document: what it is for, the sections a Small app needs, what Medium and Large add, the budget, and the row rules. "Removed" means the section was in the old template and is no longer allowed; existing content in a project is not deleted by anything.

**Budgets are a target and a maximum** (owner, 2026-09-04: a single hard number makes the AI truncate). The checker warns above the target and fails only above the maximum. Word counts exclude code blocks, diagrams and comments. Truncation is stopped by the content rules, not the budget: a document that drops a screen, a field, a requirement or a row to fit fails on those rules first, so the only way to meet a budget is shorter prose. The only fixed numbers are Coding Standards and the checklist Remarks cell.

### 3.1 BRD — `docs/<App>-BRD.md`

What it is for: the owner's statement of what the product does, screen by screen, with one numbered requirement per thing the verifier will test. Produced at day-1 together with the Architecture and the mockups (D-1, D-2).

| Order | Section | Small | Medium / Large | Content rule |
|---|---|---|---|---|
| 0 | Header table | required | required | App, Kind, Size, Stack answer set, Status, Date |
| 1 | Summary | required | required | What it is, for whom, why. At most 200 words. |
| 2 | Scope | required | required | Two lists: in, out. |
| 3 | Users and roles | required | required | One table. |
| 4 | Screens and flow | required | required | One table: screen, route, role, mockup link, fields. A dialog is a row under its parent screen with `on /route` in the Route column. Then the primary journey as a numbered list. |
| 5 | Requirements | required | required | The `BRD-N` ledger. Every item: id, title, screen, mockup link, one acceptance line in the "When …, then …" form. Ids never renumbered. |
| 6 | Non-functional requirements | required | required | One table. A speed requirement uses the `perf-budget:` form, only where the owner gave a number. |
| 7 | Development status | required | required | One row per screen with counts. Written by the status gate, not by hand. |
| 8 | Context diagram | optional | required | |
| 9 | Constraints and assumptions | optional | required | |
| 10 | Risks | optional | required | |
| 11 | Glossary | optional | optional | |

Removed: Business objectives (folded into Summary), Component sketch (the Architecture owns it), Feature catalog (repeated the ledger), Success metrics, Table of Contents (the renderer builds it), the footer.

Budget: Small 6,000 target, 8,000 maximum. Medium 10,000 target, 15,000 maximum. Large: the Medium figures per phase. Checks: requirement ids unique and within the size cap; every mockup link points at a file that exists; the screens table has the five columns; the set of screens equals the UIDesign's (dialog rows excluded).

### 3.2 Architecture — `docs/<App>-Architecture.md`

What it is for: the technical decisions, once, so no phase re-invents them. Produced at day-1. Read at every build.

| Order | Section | Small | Medium / Large | Content rule |
|---|---|---|---|---|
| 0 | Header table | required | required | App, Kind, Size, Stack answer set, Date |
| 1 | Stack decisions | required | required | One row per stack question with its source: the answer set, the owner, or the existing code (FR-01). |
| 2 | Solution structure | required | required | One table: project, kind (web app, class library, test project, migrations project), purpose. |
| 3 | Component map | required | required | One diagram, then "How a request travels": one typical request as a numbered list in words. No sequence diagram; per-screen detail belongs to the DevGuide. |
| 4 | Data model | required | required | One ER diagram, then a table of entities with key fields. |
| 5 | Cross-cutting | required | required | Identity (AppManager API), configuration, logging, errors. One short paragraph each. |
| 6 | Decisions log | required | required | One row per decision: date, decision, why, status (decided, planned, done). Every package added has a row. A planned brownfield change is a row with status "planned" naming the BRD item that drives it. |
| 7 | Module responsibilities | optional | required | |
| 8 | Open questions | optional | optional | |

Removed: Deployment (decided after UAT; how a developer runs the application is in the UsageGuide), Primary data flow (folded into the Component map as the request list), Target architecture (replaced by the status column), Sources harvested, Table of Contents.

Budget: Small 2,500 target, 3,500 maximum. Medium 4,000 target, 6,000 maximum. Checks: the stack table, the solution table, the request list, the ER diagram and the four-column decisions table are all present.

### 3.3 UIDesign — `docs/<App>-UIDesign.md`

What it is for: one section per screen, mapping every region to a control and listing every field, beside the mockup. The build implements from it; the verifier compares the built screen to it. Optional for libraries.

| Order | Section | Small | Medium / Large | Content rule |
|---|---|---|---|---|
| 0 | Header table | required | required | App, Kind, Size, UI library, Theme |
| 1 | Design system | required | required | Layout rules, theme, shared controls. At most 300 words. |
| 2 | Screens | required | required | One `### Screen: Name (/route)` per screen. Each: mockup link (file must exist), roles, a regions-to-controls table, a fields table (field, type, required, validation), the dialogs the screen opens with their fields, and one line each for the empty, loading and error states. Target 250 words per screen, maximum 400. |
| 3 | Click-through flow | optional | required | Which screen leads to which. |
| 4 | Branding guide | optional | optional | Colours and type when they differ from the library defaults. |

Removed: How to use, Library gaps (the library feedback file owns them), Table of Contents.

Budget: 300 words plus the per-screen figures, so a ten-screen Small app is 2,800 words target and 4,300 maximum. Checks: every screen has its mockup, its two tables and its three states; every mockup file in `docs/mockups/` is linked from a screen (a warning otherwise).

### 3.4 Checklist — `docs/<App>-Checklist.md`

An agent document. The owner does not review it and it is never rendered. Only the row rules matter.

Sections, in order: Goal, Requirements Status (the one table), then one section per page or group holding the detail entries. No other sections: a `UAT Bugs` or `Feedback tracker` section goes into the misses stream instead.

Row rules, each checked by script:

1. Table header is exactly `| ID | Requirement | Status | % | Remarks | Details |`.
2. ID matches `REQ-UI-`, `REQ-FN-`, `REQ-RAG-` or `REQ-NFR-` plus three digits. No duplicates.
3. Status is one of the fixed values. `Verified` is written only by a verify run (hook exists).
4. `%` is 0, 25, 50, 75 or 100.
5. The Details link resolves to an anchor in the same file.
6. Every detail entry names its `BRD-N` item, and every `BRD-N` item in the BRD has at least one row.
7. Every UI row carries a mockup link to a file that exists.
8. Every row has exactly one acceptance line, and it reads **"When `<actor>` `<does what>` on `<screen>`, then `<a result a browser robot can observe>`"**. An optional "Given …," may precede it. UI and functional rows name the screen; a NFR row names the measurement instead and, for speed, carries `perf-budget:` in the fixed form.
9. Remarks holds the current state only, at most 60 words. The history of a row lives in the telemetry streams.
10. Row count is within the size cap.

### 3.5 Coding Standards — `docs/<App>-Coding-Standards.md`

Decided 2026-09-04: the standards are baked into the framework, and the .NET set is a framework document with guidance on how to edit it, the way model routing is done.

| Where | File | Content | Size |
|---|---|---|---|
| Framework, every project | `.tfcore/standards/coding-standards-core.md` | Technology-neutral rules: naming style, layout, one configuration mechanism, no package without a decisions-log row, logging, testability, what the verifier's standards check reads. | about 500 words |
| Framework, .NET answer set | `.tfcore/standards/coding-standards-dotnet.md` | The .NET rules, seeded from the two sample files in this repository's `docs/` folder. Header explains how to edit it. Loaded when the project's Stack answer set is .NET. | about 800 words |
| Per project | `docs/<App>-Coding-Standards.md` | Sections: Standards applied (which files, and the choices the stack file leaves open, such as the instance-field prefix), Project rules (often empty), Enforcement. | 800 target, 1,200 maximum, every size |

The per-project file stays because the verifier's standards check and the build read it, and because a developer joining the project needs one starting point. `update-framework.sh` now copies the `standards` folder into every project.

### 3.6 PROJECT-STATUS — `PROJECT-STATUS.md`

The owner's report (2026-09-04): agents fill it with long accounts of what they did and fixed, and the next-command section is not in a fixed place and shows one harness only. Two causes were found: the hook watches only the harness's file-write tool, so a write through the shell is not seen; and it checks headings and length, not content.

Sections, fixed, in order, with a word limit each: Where I am (80), Next command to run (60), Open requirements (200), Known blockers (150), Verification log (250), Library feedback summary (60), Standards compliance (60), Deferred / future (100). Same for every size and kind.

Rules: at most 120 lines, 60 as the target. **Next command to run holds exactly two one-line code blocks, the first labelled Claude Code and the second OpenCode**, so each can be copied on its own. Verification log keeps the last five rows, and no cell in it exceeds 20 words: a result is a count, not a story. Open requirements shows counts by status and at most ten named rows.

The fix, built: the checker enforces all of the above at the status gate whichever way the file was written; a shell write to PROJECT-STATUS (redirection, tee, cp, mv, sed -i, a script) is refused by the guard hook in both harnesses; the checker becomes a Stop hook in Session 6.

### 3.7 UsageGuide — `docs/<App>-UsageGuide.md`

What it is for: the owner's test plan. Who to sign in as, how to start it, what to click on every screen and what should happen. Started at day-1, finished at handoff.

| Order | Section | Small | Medium / Large | Content rule |
|---|---|---|---|---|
| 1 | Test users | required | required | One table: user, password source, role, exists. |
| 2 | Execution guide | required | required | Prerequisites, then start commands in a code block, one per line. |
| 3 | How to test, screen by screen | required | required | One `###` per screen, at most 120 words: who to sign in as, numbered steps, the expected result, the REQ ids covered. |
| 4 | Automated tests | required | required | The command and what it covers. |
| 5 | Known limitations | required | required | |
| 6 | Platform notes | optional | optional | Only when the app runs on more than one platform. |
| 7 | Component map | service libraries | service libraries | One entry per service: what it does, how it is called. |

Removed: Smoke checklist (folded into section 3), the separate Setup and Deployment sections (folded into the Execution guide), the long section titles.

Budget: Small 2,500 target, 3,500 maximum. Medium 4,000 target, 6,000 maximum.

### 3.8 DevGuide — `docs/<App>-DevGuide.md`

What it is for: a developer's map from each screen to the code that serves it, written so the developer can set breakpoints and debug it. Produced automatically when the build completes the checklist (D-7), refreshed at handoff.

| Order | Section | Small | Medium / Large | Content rule |
|---|---|---|---|---|
| 0 | Header table | required | required | App, Kind, Size, Verified on (the run the screenshots and line numbers come from), Date |
| 1 | Architecture cheat-sheet | required | required | One diagram and at most 300 words. |
| 2 | Roles and menu map | apps | apps | |
| 3 | Screen-by-screen code map | required | required | One `###` per screen (per component for a UI library). Each entry: the screenshot (file must exist); one "Call chain:" line, page method to service class and method to data-access class and method; a where-to-break table, one row per step: file and line, function, the variable to watch, the value it should hold. Example row: `Login.razor.cs:127`, `HandleLogin`, `aLogin.Email`, the email typed in the box. Target 300 words per screen, maximum 450. |
| 4 | Cross-cutting flows | required | required | Sign-in, configuration, logging, errors, each with its own call chain and where-to-break table. |
| 5 | Known issues | required | required | |

Line numbers are taken from the code at the time of writing and refreshed at handoff; the function name is what a developer searches for when a line has moved.

Removed: How to use this guide, How to fix a bug with this guide (boilerplate), Table of Contents.

Budget: Small 4,000 target, 6,000 maximum. Medium 7,000 target, 10,000 maximum.

### 3.9 ProductGuide — `docs/<App>-ProductGuide.md`

What it is for: the end user's manual, task by task, with a screenshot per task. On demand.

| Order | Section | Small | Medium / Large | Content rule |
|---|---|---|---|---|
| 1 | Welcome | required | required | What it does, at most 150 words. |
| 2 | Getting started | required | required | Sign in, first task. |
| 3 | Roles at a glance | only with more than one role | required | |
| 4 | Using `<App>` | required | required | One `###` per task: numbered steps, one screenshot each. |
| 5 | Troubleshooting | optional | optional | |

Budget: Small 2,500 target, 3,500 maximum. Medium 4,500 target, 6,500 maximum.

### 3.10 Deployment Checklist — `docs/<App>-Deployment-Checklist.md` (agreed 2026-09-04; template and command built in Sitting 4b)

Raised by the owner in this session: the two existing deployment checklists (TfLens, TechieBlog) are a mess and the document needs a schema like the others. The survey of those two confirmed it. Both are long (6,500 and 12,200 words), one has eight checkboxes and the other none, both re-describe the same secrets in three or four places, one mixes a local Docker path with the production path in one file, one carries a variable that another section says was deleted, and one says on its first page that the pipeline is settled and on its last that it has never run against the real server.

What it is for: the steps to put the application on its host, produced after UAT from the pipeline guidance document the owner supplies (Stack Q9 and Q10). One document per hosting target. Running the application locally is not in it; that is the UsageGuide's Execution guide.

| Order | Section | Content rule |
|---|---|---|
| 0 | Header table | App, Hosting target, Pipeline document (the source), Date, Proven (never, or the date of the last real deploy) |
| 1 | Who does what | One table: step, done by the pipeline or by the owner. |
| 2 | Secrets and settings | One table: name, where it is set, what breaks without it. Each name appears exactly once in the document. |
| 3 | Before the first deploy | A checkbox list. Each box is one action with one observable result. |
| 4 | Deploy | A checkbox list. |
| 5 | After the deploy | A checkbox list: the command to run and the output that proves it worked. |
| 6 | Rollback | A checkbox list, and one line saying what a rollback does not undo (migrations). |
| 7 | Routine operations | One table: task, command. |
| 8 | Troubleshooting | One table: symptom, cause, fix. |
| 9 | Proven | One table: what has been executed for real and when; what remains unverified. |

Rules: every item in sections 3 to 6 is a checkbox; no narrative sections; one hosting target per document. Budget 2,500 target, 4,000 maximum, every size.

Produced by a small new command, `*deploy-checklist <App> <pipeline-document>`, built in Sitting 4b beside the handoff task, because handoff runs before UAT and deployment comes after.

---

## 4. The checker, as built

`bash .tfcore/utils/tf-doc-check.sh` takes document paths, or `--app <App>` to check every human document of that app plus `PROJECT-STATUS.md`. For each document it finds the template by file name, reads the schema block, and checks:

1. Header fields present and filled in (Size, Kind where required). A document without a Size falls back to the BRD's header, then to `core-config.yaml`.
2. Required sections present, in order, no top-level section outside the allowed set. Numbering and trailing qualifiers in headings are ignored, so "## 3. Scope (v2)" still counts as Scope.
3. Word budget for the document's size: WARN above the target, FAIL above the maximum. Per-section and per-screen limits the same way.
4. The row rules of §3 for that document.
5. Across documents: BRD screens equal UIDesign screens; every `BRD-N` has a checklist row; every mockup file has a screen.

It prints one line per problem, for example:

```
WARN docs/TrSetup-BRD.md: 7,599 words; the Small target is 6,000 (maximum 8,000)
FAIL docs/TrSetup-Checklist.md: REQ-FN-012 acceptance line does not read "When <actor> <does what> on <screen>, then <observable result>"
FAIL docs/TrSetup-UIDesign.md: screen "Settings" has no mockup link (docs/mockups/<screen>.html)
FAIL PROJECT-STATUS.md: "Next command to run" must hold exactly two code blocks, Claude Code then OpenCode; found 1
```

It exits with failure when any line says FAIL. `--warn` prints every finding as WARN and exits clean: report mode for an existing project, after which each finding is logged as a miss and fixed through `*amend-docs`.

Where it runs: step 7b of the status gate (`_status-update-gate.md`), on the documents the command wrote, before the HTML render. Both harnesses run it, because it is a shell script called from the task. It becomes a Stop hook in Session 6, after the fixture projects pass.

Self-test: `bash tests/doc-check/run.sh` builds a minimal Small app document set (nine documents, two mockups, two screenshots) that passes with no findings, and a broken twin that fails on thirteen lines, one per planted defect. This is the FR-14 check; the distribution pipeline runs it.

---

## 5. What changed in the framework

| Change | Where |
|---|---|
| Nine templates rewritten with a schema block and a lean skeleton | `.tfcore/templates/v4custom/app-*-tmpl.md`; Coding Standards is new; templates total 3,400 words against 8,300 before |
| The checker | `.tfcore/utils/tf-doc-check.sh` and `tf-doc-check.py` |
| Standards moved into the framework | `.tfcore/standards/coding-standards-core.md`, `coding-standards-dotnet.md`; `update-framework.sh` copies the folder |
| Stack documents installed as templates | `.tfcore/templates/stack-questions.md`, `.tfcore/templates/stack-defaults/dotnet.md` (copies of the two Stack documents in `docs/`) |
| Status gate step 7b | `.tfcore/tasks/_status-update-gate.md` and its Claude Code mirror |
| Day-1 size and kind question, and the coding-standards step | `.tfcore/tasks/day1-greenfield.md`, `day1-brownfield.md` and their mirrors; the 150-line standards block left the brownfield task |
| `appSize`, `appKind` keys | `.tfcore/core-config.yaml` |
| Shell writes to PROJECT-STATUS refused | `.tfcore/hooks/guard-status.sh` now also runs on Bash; registered in `.claude/settings.json`, the OpenCode plugin, and the three scaffold and update scripts |

Task references to the old template sections (for example "BRD §4 Development status" in the status gate and split-brd's reading of "§10 Functional requirements") are updated when those tasks are shrunk in Session 4. Until then the day-1 tasks point at the new sections and the other tasks still name the old ones.

---

## 6. What the checker says about existing documents

Run on 2026-09-04 in report mode on fourteen projects. Every project fails, as expected: the shape did not exist before today. The count is findings, one line each.

| Project | Findings | The main reasons |
|---|---|---|
| TfLens | 577 | BRD 29,400 words and 169 requirements against Medium limits; UIDesign screens without a fields table; all 178 acceptance lines out of form; 178 Remarks cells over 60 words; six mockup links to files that do not exist; DevGuide in its own section set; PROJECT-STATUS with narrative log cells and one command block. |
| TechieBlog | 547 | 38 screens, so Large; 135 Remarks cells over limit; 87 rows with no acceptance line; 38 screens without a fields table; 31 Details links unresolved; Verification log over five rows. |
| TrStudio | 310 | 112 acceptance lines out of form; 22 screens without a fields table; Architecture with twelve sections outside the list; PROJECT-STATUS with twelve narrative log cells. |
| TechieRag and TechieDesk | 231 and 651 | TechieDesk 153 Remarks cells over limit, 118 rows without an acceptance line, 94 rows with a `%` outside the five values; TechieRag DevGuide entries without screenshots, call chains or where-to-break tables. |
| TrBlazeUI | 198 | 34 rows not naming their BRD item; 19 UI rows without a mockup; acceptance lines out of form; needs the `library` kind. |
| TrSetup | 201 | 42 acceptance lines out of form; UsageGuide and DevGuide in their own section sets; a mockup link still holding the template placeholder. |
| Seven private projects | 50 to 733 each | The same pattern. One checklist has 354 acceptance lines out of form and 132 UI rows without a mockup; one BRD has 80 requirements against a Small cap of 50; two use the older BRD template; every PROJECT-STATUS fails the two-block rule. |

Every existing project fails on the acceptance line and on the two-block next command, because neither rule existed until today. That is not evidence the rules are too strict; it is why they exist. The owner's decision (§7.1, item 8) is that existing projects are reported with `--warn`, each finding logged as a miss, and repaired through `*amend-docs` when the project is next worked on.

---

## 7. Decisions

### 7.1 Taken on 2026-09-04

| # | Decision | Result |
|---|---|---|
| 1 | Small section lists | Accepted as listed, with the Architecture changes (solution structure and ER diagram added, Deployment removed) and the DevGuide debugging shape. |
| 2 | Budgets | A target and a maximum for every document, not one number. Fixed numbers only for Coding Standards and the Remarks cell. |
| 3 | Acceptance line | "When … on `<screen>`, then …"; "Given" allowed as a prefix; NFR rows name the measurement. |
| 4 | What counts as a screen | Every routed page counts, sign-in and AppManager-backed screens included. Dialogs are regions of their page. |
| 5 | Kind | `app` or `library`. TrBlazeUI's component map links to the sample app; TechieRag's lives in the UsageGuide. |
| 6 | Coding Standards | Baked into the framework: a neutral core file plus a .NET file in `.tfcore/standards/`, and a short per-project file. |
| 7 | Remarks | Current state only, at most 60 words. |
| 8 | Block or warn | Block on shape and row rules and on the maximum budget; `--warn` for existing projects; Stop hook in Session 6. |
| 9 | Scope | All nine documents from the start. |
| 10 | UsageGuide section 2 | Named "Execution guide". |
| A | Primary data flow | Folded into the Component map as "How a request travels", a numbered list in words. No sequence diagram: the owner's view is that sequence diagrams belong to low-level design, and the maintainer agrees; the DevGuide holds the detailed flows. |
| B | Target architecture | Replaced by a Status column in the Decisions log (decided, planned, done). |
| C | Coding Standards shape | As in §3.5. |
| D | PROJECT-STATUS | "Spoiled" means long accounts of what was done, and a next-command section that moves and shows one harness. Fixed by per-section word limits, the two labelled command blocks, the five-row log with 20-word cells, the shell-write guard, and the checker at the gate. |

| E | Deployment Checklist schema (§3.10) | Accepted as listed. |
| F | Which command produces it | A small new command, `*deploy-checklist <App> <pipeline-document>`, built in Sitting 4b. |
| G | Tenth document in the Reset Plan | Yes; the plan now lists it under Session 3 and Sitting 4b. |

### 7.2 Still open

Nothing. Session 3 closed on 2026-09-04.

---

## 8. Misses logged in this session

Framework defects found during Session 3, each recorded in `docs/metrics/misses.jsonl` with the sentence below (the sentence itself is stored in a readable file from Session 5, per D-10).

| Miss | What |
|---|---|
| MISS-TechieFlow-20260904-24 | The verifier cannot drive a dialog, so dialogs have been built as separate routed screens to get them verified; a dialog must be verified on its parent page. |
| MISS-TechieFlow-20260904-25 | Coding Standards had no template file: the content was a prose block inside the brownfield day-1 task, so it could not be checked, word-counted or kept in one place. |
| MISS-TechieFlow-20260904-26 | The PROJECT-STATUS guard watched only the harness's file-write tool, so a write through the shell bypassed it, and it checked headings and length but not content; both are how status files were spoiled. |

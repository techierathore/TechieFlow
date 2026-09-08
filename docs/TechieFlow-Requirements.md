# TechieFlow — Framework Requirements

| | |
|---|---|
| Purpose | The list of things the framework must do, each with a way to check it. This is the framework's checklist. |
| Audience | Agents, and the framework maintainer who reviews it (Claude). **The owner does not review this list.** The owner reviews the descriptive documents it is derived from: `TechieFlow-How-It-Works.md` (including its defect table), `TechieFlow-Stack-Questions.md` and `TechieFlow-Stack-Defaults-DotNet.md`. Every line below traces to a statement in one of those documents or to a decision the owner gave in conversation. When a line needs a decision only the owner can make, the maintainer asks it as a plain question, never as "review this line". |
| Status | Session 2 of the reset (2026-09-04). Reviewed by the maintainer for traceability; owner decisions of 2026-09-04 applied. Checks marked "script" are written in Sessions 3 and 4. Group I (distribution) added 2026-09-04 after freeze, via miss 23; FR-53 added 2026-09-05 via miss 05 of that day; FR-54 (Large layout), FR-55 (honest `ended` and the command marker), FR-56 (database writes only from build and fix) and FR-57 (Architecture stack rows and head name) added in Sitting 4b, 2026-09-05 and 06, from the owner's decisions and misses 9, 11, 16; FR-10, FR-15, FR-36 and FR-53 reworded from misses 10, 13, 15 and the review record build. **Session 5 (2026-09-07):** FR-31 and FR-32 built; FR-58 to FR-61 added from the four-question sort of Session 4's misses (04, 08, 17 of 09-05 and 26 of 09-06, all sorted `unsaid`); FR-18 and FR-40 checks reworded from misses 07 of 09-06 and 02 of 09-05. **Session 6 (2026-09-07):** FR-62 added from miss 07 of that day (sorted `unsaid`); FR-47's check rewritten and built from miss 05, which found that it named a script nobody had written. Agent document; not rendered to HTML. |
| Sources | The conventions in `WorkFlow-Context.md` §2; the 128 recorded misses across all repositories; the incident log; defects D-1 to D-22 in `TechieFlow-How-It-Works.md` §8; the Stack documents; owner decisions of 2026-09-04. |

---

## 1. How to read a line

Every line says one thing the framework must do, and how to prove it does.

- **ID**: `FR-` and a number. Used when a miss is traced back to a requirement.
- **The framework …**: one sentence. If the sentence needs "and" twice, it is two lines.
- **Check**: how to prove it. Three kinds:
  - *script*: a command that fails when the requirement is broken. The best kind, because it runs without a person.
  - *fixture run*: run a named command on one of the fixture projects and look at a named file. Used where a script cannot exist yet.
  - *review*: a person or the maintainer reads something. The weakest kind. Every review check is a candidate to become a script.
- **Source**: where the requirement came from, so it can be argued with.

## 2. Fixture projects

The projects on which checks run. Agreed with the owner on 2026-09-04. All public.

| Fixture | Kind | Used for |
|---|---|---|
| MyDiary | greenfield application (a journal app the owner is about to build; the first real project on the reset framework). Its brief of 2026-09-05 lists 25 screens in two phases, so it is Large and also the first phased project (Sitting 4b) | day-1 greenfield, mockups, the Large layout, build, verify, bugs |
| TrStudio | brownfield application | day-1 brownfield, amend-docs, DevGuide |
| Xpenser | brownfield application | second brownfield sample, so that a check passing on one codebase is confirmed on another |
| TrBlazeUI | UI component library | library modes of DevGuide and verify, library feedback |
| TechieRag | service library, with TechieDesk as its bundled application | library modes, multi-product repository |

## 3. When an agent does something unexpected

This is how a framework miss is handled. Four questions, asked in order, each with one fixed answer.

1. **Is there a line here that covers it?** No: add a line, with a check. Nothing is added to a task file.
2. **Is the line's check a "review"?** Yes: replace the review with a script, so it never depends on someone noticing.
3. **Is the check a script, and did it fail to fire?** Yes: the check is wrong. Fix the check, not the prose.
4. **Did the check fire, and did the agent carry on anyway?** Yes: the rule becomes a hook the agent cannot bypass, or it is deleted because it did not matter. A rule never gets a third paragraph of prose.

The same four questions are asked for a miss in an application, against that application's checklist.

---

## 4. Requirements

### A. Technology neutrality

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-01 | asks the stack questions (`TechieFlow-Stack-Questions.md` Q1 to Q8) before writing any project document, and records the answers in the Architecture document's Stack Decisions section. | fixture run: `*day1-greenfield MyDiary` without an answer set; the run stops and asks before any file under `docs/` is written. | D-4; Stack Questions §1 |
| FR-02 | accepts a named answer set that fills in the stack questions, ships the .NET answer set as an option, and asks only the questions the set leaves open. | fixture run: `*day1-greenfield MyDiary` naming the DotNet answer set; only Q4 and the Q8 rendering mode are asked; the Stack Decisions table cites the set for the rest. | Stack Questions §1; Stack Defaults header |
| FR-03 | contains no language-, database-, UI-library- or host-specific instruction in any persona, task or shared rule file; such facts live only in answer sets and in a project's Stack Decisions. **One stated exception:** the two library sub-agents the framework ships may be named where they are the routing key (`[trblazeui]`, `/techierag`, `"trblazeui"` in a record), because the name *is* the address — see the briefing §2. Naming either library anywhere else is still a failure. | script (built 2026-09-07, **passing since 2026-09-08**): `bash tests/requirements/run.sh` → `fr_03` greps every persona and task, skipping only a routing form. It failed for a year of sittings on 20 lines in 7 files — `handoff-phase` alone emitted `dotnet restore`, `dotnet build`, `dotnet run` and `dotnet test` as literal deployment steps, so a project on any other stack got .NET commands in its runbook. Those now read "the stack's build command", taken from the Architecture's stack table and `tf-build.sh`. | owner 2026-09-04; fixed and the exception worded 2026-09-08 (`MISS-TechieFlow-20260908-05`) |
| FR-04 | applies the two default rules of Q11 (logs under the build output folder, no unnecessary root folders) to every project unless the owner removes them. | script (built 2026-09-07): `bash tests/requirements/run.sh` fails on a `*.log` at the repository root or a run-litter folder there. | Stack Questions Q11 |
| FR-05 | enforces every rule recorded under Q11 in a project's Stack Decisions, and logs a violation as a miss. | script per rule, generated from the Stack Decisions table; for the .NET set: Dapper present and no other ORM, an `<App>Db` project using DbUp, no `database` root folder, no NuGet package absent from the Architecture document, one configuration mechanism. | Stack Defaults Q11; TfLens incident |

### B. Day-1 and documents

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-06 | runs greenfield day-1 in two stages: stage 1 produces the Architecture, the BRD and the mockups, linked to each other, and runs to completion in YOLO mode; stage 2 runs only on the owner's go-ahead and produces the checklist and the remaining documents. | fixture run: `*day1-greenfield MyDiary` in YOLO mode ends with Architecture, BRD and `docs/mockups/*.html` present and no checklist; the go-ahead produces the checklist. | D-1 |
| FR-07 | writes the BRD so that every use case links its mockup and lists the fields of every screen, beside the acceptance criteria. | script: every use-case section in the BRD contains a link to `docs/mockups/`; every screen in the UIDesign appears in the BRD. | D-2 |
| FR-08 | records an application size at day-1 stage 1 and applies that size's requirement cap and document budgets. | script: the BRD header carries `Size:`; requirement count and document word counts are within budget for that size. | D-3 |
| FR-09 | defines Small as up to 10 screens, one role, up to 50 requirements; Medium as up to 20 screens, up to 100 requirements; Large as anything beyond, to be split into phase-wise BRDs. AppManager does not count as an external integration. | review: the definition appears once, in the BRD template, and nowhere else. | D-3; owner 2026-09-04 |
| FR-10 | raises a Small project to Medium when `*amend-docs` would take it past 50 requirements, and proposes a phase split, rather than growing the single BRD, only when a Medium project or a phase would pass 100 requirements or 20 screens. | fixture run: `*amend-docs Xpenser` with additions past 50 raises the size; `*amend-docs TrStudio` with additions past 100 stops and proposes a phase split. | D-3; owner 2026-09-05 (Schemas §7.2 K; MISS-TechieFlow-20260905-10) |
| FR-11 | applies mockups to any project, not only greenfield; brownfield day-1 finds existing mockups, records their location, and links them from the documents. | fixture run: `*day1-brownfield Xpenser` with a `docs/mockups/` folder present; the UIDesign and BRD link them and no mockup is regenerated. | D-5 |
| FR-12 | produces the checklist automatically once the owner approves the BRD; the owner never types `*split-brd`. | fixture run: after the stage 2 go-ahead on MyDiary the checklist exists without a separate command. | D-6 |
| FR-13 | produces the DevGuide automatically when the build phase completes the checklist, for every project type, and refreshes it at handoff. | fixture run: `*build-phase MyDiary` to completion; `docs/MyDiary-DevGuide.md` exists at the end. | D-7 |
| FR-14 | gives every human document template a strict structure (required sections in order, size budget per size class, row rules) and refuses to close a phase whose document breaks it. | script: `bash tests/doc-check/run.sh` — `tf-doc-check.sh` exits 0 on a clean generated document set, non-zero on the deliberately broken twin, and the status gate refuses to close. | How-It-Works §2 Template; Session 3 |
| FR-15 | requires every checklist row and every BRD item to carry one acceptance line of the form "when … then …" naming an observable result, of at most 30 words (target 20) and holding one behaviour, under a title in everyday words; BRD items sit under a heading per screen that opens with one plain sentence. | script: `bash tests/doc-check/run.sh` — the clean set passes and the broken twin's bundled 41-word line fails on the pattern and the word cap. | D-20; owner 2026-09-06 (miss 13) |
| FR-16 | keeps one checklist per application as the single source of truth, in markdown only, and never creates dated `docs/qa/` or `docs/verify/` files or `-v2` document copies. | script (built 2026-09-07): `bash tests/requirements/run.sh`. | conventions |
| FR-17 | renders every human document to HTML by script, never by hand; configuration and agent documents are not rendered. | script: every human `docs/*.md` has a sibling `.html` newer than itself; no `.html` exists for the checklist, the Stack documents or this file. | TF-003; owner 2026-09-04 |
| FR-54 | lays a Large project out by phase: BRD, checklist, UIDesign and DevGuide are one file per phase (phase 1 under the plain names, phase n as `<App>-Pn-…`), `BRD-N` and `REQ-` ids run on across phases and are never reused, a `docs/<App>-Phases.md` table names every phase's screens and id range, `appPhase` in `core-config.yaml` selects the phase every command works on, and the Architecture, Coding Standards, PROJECT-STATUS, UsageGuide, ProductGuide and the mockup folder stay single. | script: `bash tests/doc-check/run.sh` passes the two-phase fixture clean and fails its broken twin on a screen in two phases, an id in two phases, an id outside its phase's range and a phase without its BRD; `tf-split-brd.sh --all-phases` numbers phase 2 after phase 1. | owner 2026-09-05 (Schemas §2, §3.11, §7.2 H to L) |
| FR-53 | produces mockups as one click-through set: every link and form action resolves to a mockup that exists when opened from the mockup folder, navigation is a link or a form action and never a script, every menu item leads to its screen, every stylesheet exists, every screen is reachable by clicking from the entry screen, every screen has a way out, every button navigates or shows a message, and every mockup carries `data-testid` anchors. Existing mockups in a brownfield repository are moved into `docs/mockups/` before anything is linked. | script: `tf-doc-check.sh --app <App>` FAILs on a broken link, an unreachable or dead-end screen, an inert button or an unanchored mockup; `tf-mockups-locate.sh` leaves no mockup outside `docs/mockups/`. | owner 2026-09-05 (MISS-TechieFlow-20260905-05); D-5 |

### C. Build

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-18 | builds UI requirements from the approved mockups and nothing else, and compares the built screen to its mockup before marking it implemented. | fixture run: `*build-phase MyDiary`; `tests/.artifacts/verify/screens.json` (written by `tf-verify-screens.sh`, the smoke evidence since Sitting 4c) has an entry for every screen the build touched, and `tests/.artifacts/verify/parity.json` names the mockup compared for every UI row. Reworded 2026-09-07 from MISS-TechieFlow-20260906-07: the old check read a smoke log no task wrote. | 39 partial-implementation misses; How-It-Works §3.4 |
| FR-19 | never writes `Verified` from a build, a fix or a status refresh; only an executed verify may. | script (built 2026-09-07): `bash tests/requirements/run.sh` drives `guard-verify.sh` both ways — refused with no ledger, allowed with a same-day one. | convention; guard-verify hook |
| FR-20 | ends every command by rewriting PROJECT-STATUS in template shape and appending one run record. | script: after any fixture command, PROJECT-STATUS matches the template shape and `runs.jsonl` has one new line. | status gate; D-11 |
| FR-21 | records a library gap in that library's feedback file and holds the feature; it never implements a workaround. | fixture run: build a MyDiary requirement needing a TrBlazeUI control that does not exist; the row is `BLOCKED-BY-LIBRARY`, the feedback file has the entry, no workaround code exists. | Stack Defaults Q11.3 |
| FR-22 | starts a stopped database container itself when the database is unreachable, asks only when no container exists, and never creates its own database. | fixture run: stop the PostgreSQL container, run `*build-phase MyDiary`; the container is started and no new container or compose file appears. | Stack Defaults Q3 |
| FR-23 | writes all run-generated artefacts under `tests/.artifacts/` and never at the repository root. | script (built 2026-09-07): `bash tests/requirements/run.sh` drives `guard-artifacts.sh`: a root `--output` and a root `mkdir` are refused, the `tests/.artifacts/` form is allowed. | TechieBlog incident |

### D. Verify

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-24 | applies the seven checks to every requirement in a fixed order and records the first that fails. | script: `bash tests/verify/run.sh` — every `gates.jsonl` record the fixture verify writes carries a gate value from the fixed list or none. | How-It-Works §6.2 |
| FR-25 | verifies against the acceptance line and the mockup, and states in the remark what was observed, so a `Verified` row can be re-derived by a reader. | review, to become a script: sample ten verified rows across fixtures; each remark names the observation. | 63 misses classified insufficient-verify-method |
| FR-26 | has a verify task of at most 4,000 words, with every mechanical step in a script. | script: `bash tests/mirror/run.sh` counts `verify-phase.md` and fails above 4,000 words (built 2026-09-07; it is 964). | D-8 |
| FR-27 | never reports a file or tool as "not present" without trying its literal path, because the framework folder is invisible to search. | script: `bash tests/doc-check/run.sh` — the broken twin plants a Remarks cell that says "not present" without a path, and the checker refuses it. | D-21 |

### E. Bugs and misses

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-28 | never edits source or spawns builders during `*triage-issues`. | script: `bash tests/bugs/run.sh` — a triage run over the fixture leaves `src/` untouched, and a planted code edit during triage is reported and logged as `instruction-ignored`. | convention; How-It-Works §3.7 |
| FR-29 | records a miss automatically from triage (discovery cost) and from fix (fix cost); the owner never types `*log-miss` for a bug that went through either. | fixture run: triage then fix one bug on MyDiary; `misses.jsonl` gains a `miss` and a `miss-fix` with no manual log command. | D-15 |
| FR-30 | offers one command that runs the owner's bug sequence end to end in YOLO mode: compare screens to mockups, triage, log discovery cost, fix, log fix cost, metrics, with a summary per step. | fixture run: `*triage-and-fix MyDiary <folder>`; the final summary has six sections. | D-16 |
| FR-31 | stores the owner's one-sentence description of every miss in a human-readable file beside the record. | script (built 2026-09-07): `tf-emit.sh` rebuilds `docs/<App>-Misses.md` and its HTML from the stream after every write to it; `bash tests/bugs/run.sh` checks that the row count equals the record count and that the sentence, the row and whose gap are in the row. | D-10 |
| FR-32 | sorts every miss with the four questions of §3 and records the answer. | script (built 2026-09-07): `tf-log-miss.sh` refuses a miss without `--sort` and prints the four questions; `tf-triage.sh` defaults it; `tf-emit.sh --amend <miss> sort <value>` sorts an older record once and never twice; `tf-metrics.sh` reports the distribution over the records that carry it. `bash tests/bugs/run.sh`. | §3 |
| FR-33 | records issues found by people in UAT as misses, never as reviews. | script: `bash tests/bugs/run.sh` — every record the triage run writes to the miss stream is of kind `miss`, one per row. | owner 2026-09-04 |

### F. Telemetry

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-34 | emits one run record for every command, including day-1, mockups, DevGuide, ProductGuide and the idea-stage commands. | script (built 2026-09-07, **passing since 2026-09-08**): `bash tests/requirements/run.sh` → `fr_34` fails when a command task calls neither `tf-phase.sh` nor `tf-emit.sh` and does not reference the status-gate file. **The check itself was too weak until 2026-09-08**: it matched the bare words "status gate", so `metrics-report.md` passed for months on the sentence *"Do not run the status gate"* while recording nothing. Five commands wrote no record — `create-doc`, `create-deep-research-prompt`, `facilitate-brainstorming-session`, `generate-html`, `metrics-report` — so their time and tokens were invisible in every report. All five are wired now; removing the step from one fails the check. | D-11; D-13; fixed 2026-09-08 (`MISS-TechieFlow-20260908-05`) |
| FR-35 | records on every run whether YOLO mode was on. | script (built 2026-09-07): `bash tests/requirements/run.sh` emits a record without the field and checks the appended one carries it. | D-12 |
| FR-36 | records the outcome of every owner review as a record of kind `review` on the misses stream, named by its phase (`day1-review`, `build-review`, `verify-review`, `handoff-review`), carrying the number of corrections given, and the cost of producing the reviewed output and of applying the corrections, both copied by the emitter from the two runs the record names. | script: the emitter refuses a review without a phase from the list or without a corrections count, and copies the costs from the runs named (built 2026-09-06); fixture run: MyDiary stage 2 after the owner's review of stage 1 leaves a `day1-review` record. | D-17; owner 2026-09-04; built Sitting 4b |
| FR-37 | records framework maintenance work under the command value `framework-reset`. | script (built 2026-09-07): `bash tests/requirements/run.sh` checks that `SCHEMA.md` lists the value and that the report carries it. It failed on its first run: the schema had never gained `framework-reset`, nor four other values its own tasks were writing (`MISS-TechieFlow-20260907-17`). | D-19 |
| FR-38 | never merges provenance in a report: live with backfilled, or one project type with another. | script (exists in `tf-metrics.sh`): the report prints separate figures. | schema §0 |
| FR-39 | never blocks, fails or changes a verdict because a telemetry write failed. | review: `tf-emit.sh` exits 0 on every path. | schema |
| FR-55 | records a run's `ended` as the moment the record is written, never a value the agent guessed: an `ended` in the future or before `started` is replaced with now and the duration recomputed; `started` comes from the command marker `tf-phase.sh start` writes at step 0 of every task when the record leaves it out. | script: emit a run record with `ended` an hour ahead on a fixture; the appended record carries now; a record without `started` carries the marker's time. | MISS-TechieFlow-20260905-11 |
| FR-56 | writes to an application's database only from `*build-phase` and `*fix-issues`, and only through the migration path the Stack decisions name; a direct SQL write through a client is refused from every command, and a migration runner is refused unless the command marker says build-phase or fix-issues. | script (hook `guard-db.sh`, both harnesses): an SQL update is refused with and without a marker; a migration runner is refused under a day-1 marker and allowed under a build marker; a select and a build pass. | MISS-TechieFlow-20260905-09; owner 2026-09-05 |
| FR-57 | checks the Architecture's Stack decisions table for a row per question 1 to 8 and 11, and refuses an app whose Solution structure names `<App>.App` or has no project named exactly the app. | script: `bash tests/doc-check/run.sh` — the broken twin carries a missing stack row and an `<App>.App` head, and both fail. | MISS-TechieFlow-20260905-16; owner 2026-09-06 |

### G. Harnesses

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-40 | works identically in Claude Code and OpenCode; every task is registered in both, and every hook has an OpenCode equivalent or a documented gap. | script (built 2026-09-07 from MISS-TechieFlow-20260905-02): `bash tests/mirror/run.sh` fails when a persona or task differs from the Claude Code mirror, when the mirror holds a removed file, when a command task is not referenced from `opencode.jsonc`, or when a reference there does not resolve; it also holds FR-43 and FR-44 to their budgets. The hook parity table has no undocumented row (review). | owner 2026-09-04 |
| FR-41 | honours YOLO mode in every command; `*build-phase` and `*verify` default to it. | fixture run: each command with the flag on completes without a prompt; build and verify complete without the flag. | D-18 |
| FR-42 | carries no Codex-specific code path. The adapter was removed on 2026-09-07: no file deploys, generates or dispatches to Codex, and no shipped document or template names it. The telemetry schema keeps `codex` as a retired `harness` value, because records written before that date carry it and must stay readable. | script (built 2026-09-07): `bash tests/mirror/run.sh` greps `.tfcore/`, the Claude mirror, `.opencode/`, the three shell scripts, the installer, `package.json`, the README and the briefing for `codex`, allowing only the two retired-value notes in `SCHEMA.md`. | D-14 |
| FR-58 | runs one command to completion in YOLO and stops at the next owner review; it never starts the following phase on its own. | fixture run: `*day1-greenfield MyDiary` in YOLO ends after stage 1 with no checklist; `*build-phase` in YOLO ends after its verify with no handoff. Script candidate: `tf-yolo.sh done` refuses `complete` when the phase marker names a command other than the goal's. | MISS-TechieFlow-20260905-04 (sorted `unsaid`, Session 5); D-18 |
| FR-59 | starts every unattended run through the goal supervisor `tf-goal.sh`, never through a bare harness command, so a usage limit, a crash or an early stop is survived. | review, to become a script: every run record with `yolo: true` written outside an interactive session has a `goal.json` under `.tfcore/.session/` whose start precedes it. | MISS-TechieFlow-20260905-08 (sorted `unsaid`, Session 5); How-It-Works §3.10 |
| FR-60 | reads the project's Stack answer set before any command proposes a project, folder or head name, the idea-stage commands included, so a banned name such as `<App>.App` never enters a brief. | script candidate: the document checker refuses a project brief that names `<App>.App` when the .NET answer set is chosen. Until then, review. Not built: the idea-stage commands also emit no run record yet (FR-34 unmet for them). | MISS-TechieFlow-20260905-17 (sorted `unsaid`, Session 5) |
| FR-61 | when a verify's acceptance line needs test data the application does not hold, creates it through the application as a UsageGuide test user, passes a password gate through its own screen, and otherwise grades the row `not observable, environment`; it never grades it FAIL or logs a regression for missing data. | fixture run: `*verify all TechieBlog` on an empty database ends with rows `not observable`, not 86 FAIL and 87 regression misses. Script candidate: `tf-verify-verdict.sh` maps an acceptance failure whose test output is a sign-in redirect or an empty list to `not observable, environment`. | MISS-TechieFlow-20260906-26 (sorted `unsaid`, Session 5) |

### H. Instruction budget

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-43 | reads no more than the instruction budget before the first useful step of any command. The budget is a variable per model tier in `routing.yaml`, not a fixed number: 7,000 words for the frontier tier (about 9,500 tokens, under 5 percent of a 200,000-token context), and smaller for the standard and economy tiers. A task is written as a short core plus reference sections loaded only when a step needs them, so a small budget can be met without losing steps. | script: `bash tests/mirror/run.sh` fails when any task file passes the 7,000-word frontier budget. The per-tier recomputation of the §5 table remains a review. | How-It-Works §5; owner question 2026-09-04 |
| FR-44 | keeps the shared rule files under 3,000 words in total and every persona under 1,500. | script: `bash tests/mirror/run.sh` fails when the shared rule files together pass 3,000 words or any persona passes 1,500. | How-It-Works §5 |
| FR-45 | keeps explanation and history out of task files; a task file contains steps only. | review, to become a script: no paragraph in a task file begins with "Why", "Because", "This exists", or a date. | How-It-Works §7 |
| FR-46 | converts a prose rule to a hook or deletes it after the second recorded `instruction-ignored` miss against it. | script: the miss report lists prose rules with two or more `instruction-ignored` misses; the list is empty. | §3 question 4 |
| FR-47 | names only public repositories in the documents a person outside the owner's machines reads: the README, the briefing, and every template that ships into a project. The reset's own working documents name fixtures on purpose and are out of scope until the owner rules otherwise. | script (built 2026-09-07): `bash tests/mirror/run.sh` reads the owner's private names from `~/.techieflow/private-names.txt`, a per-machine file that is in no repository, and fails when one appears in the README, `WorkFlow-Context.md` or a template. Without that file the check says it was skipped. Reworded from MISS-TechieFlow-20260907-05: the old check named a script that was never written, and a private project sat in the public README for months. | owner 2026-09-04 |
| FR-62 | keeps the two files a person reads first short and true: the briefing at most 3,000 words, the README at most 4,000, neither naming a command the framework has removed, with the maintenance history in `docs/CHANGELOG.md` and the machine-specific detail in its own document under `docs/`. | script (built 2026-09-07): `bash tests/mirror/run.sh` counts both files and greps them for the seven removed command names; a planted 6,167-word briefing and a planted `*author-brd` both fail it. | MISS-TechieFlow-20260907-07 (sorted `unsaid`); Reset Plan Session 6 |


### I. Distribution

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-48 | is published as an npm package, `@techierathore/techieflow`, installable into any project with one command, `npx @techierathore/techieflow@latest install`, and updatable with `… update`, without adding the framework as an application dependency. | script: `npm run test:install` — it installs by each route into identical folders and compares every path, its content and its executable bit, then checks no npm footprint is left. Run it on a normal filesystem. | D-22 |
| FR-49 | installs for both harnesses from the one package: the Claude Code mirror and settings, and the OpenCode registrations. | script: `npm run test:install` checks the mirror and both `opencode.jsonc` files after an install by each route. | D-22; FR-40 |
| FR-50 | is versioned through GitHub releases and published by a pipeline that runs automated checks first: mirror parity, OpenCode reference resolution, `bash -n` on every script, the installer's own tests, and a dry-run pack. | script (built 2026-09-07): `bash tests/requirements/run.sh` reads `.github/workflows/release.yml` and fails unless `npm run validate` and `npm run test:install` both run before `npm publish`. The tag-equals-version half remains a review. | D-22; Playbook release process |
| FR-51 | keeps the shell scripts (`scaffold-*.sh`, `update-framework.sh`) working from a local clone, and the installer produces the same result, so both routes stay valid. | script: `npm run test:install` — the same diff, from both routes. | D-22 |
| FR-63 | carries every change that alters what a project receives into **both** routes in the same pass: the shell scripts and the npm installer. That includes a new or removed hook registration in `.claude/settings.json`, a new folder under `.tfcore/`, and any change to how an existing project's files are refreshed. | script: `npm run test:install` installs by each route into identical folders and compares every path, its content and its executable bit; it failed on five checks when a hook registration and the `standards` folder were in the shell scripts only. Run it on a normal filesystem: a Windows mount reports every file executable and produces one false difference. | MISS-TechieFlow-20260907-13 and -14 (both sorted `unsaid`); D-22 |
| FR-52 | ships an Installation document that a person outside the owner's machines can follow to a working project in under ten minutes. | review, then fixture run: a fresh machine with Node installed, following the document only, reaches a working `*day1-greenfield` on MyDiary. | D-22 |

### G. What the owner reads (added 2026-09-08, from the owner's reading of a TfLens hand-back)

| # | The framework… | How it is checked | Source |
|---|---|---|---|
| FR-64 | renders to HTML only what a person reads. A document whose only reader is an agent stays markdown; the requirements checklist and the miss log are banned by name. | script (built 2026-09-08): `bash tests/requirements/run.sh` → `fr_64` — `tf-render-html.sh` must exit 2 on a planted miss log and on a planted checklist, exit 0 on an ordinary document, write no HTML for either, and the framework's own `docs/` must hold no `*-Misses.html` or `*-Checklist.html`. Planting one file fails it. | Owner, 2026-09-08: an HTML copy of the miss log nobody opened was re-rendered on every miss, in 20 projects |
| FR-65 | puts a choice only the owner can make in `docs/{App}-Decision-Request.md` — plain English, options with their cost, a recommendation with its reason, and one block per decision to paste back — then says one line in the terminal and never argues it there. No agent ever reads the file back. | script (built 2026-09-08): `bash tests/requirements/run.sh` → `fr_65` — `tf-doc-check.sh` accepts the well-formed fixture and refuses it once the recommendation, the paste-back block, or the plain wording (a glossary section) is removed. | Owner, 2026-09-08; `_owner-language.md` §2 |
| FR-66 | never refuses a report of an upstream defect, and holds every one to the same shape: one file per upstream, `Blocks: yes\|no` as the first answer, 250 words per live entry, and the run continuing when the answer is `no`. | script (built 2026-09-08): `bash tests/requirements/run.sh` → `fr_66` — `tf-doc-check.sh` accepts the well-formed fixture, refuses an entry with no `Blocks:` answer, and refuses a Summary that never says what is blocked. | Owner, 2026-09-08: *"feedback is needed, it should be there"*; `_owner-language.md` §3 |
| FR-67 | never states the same rule in two places. A word cap stops one file growing; nothing stopped a rule being copied into a second and a third file, which is how a rule set rots — the copies drift, and a reader who finds one never learns there was another. | script (built 2026-09-08): `bash tests/mirror/run.sh` runs `tests/mirror/dup-check.py` over the tasks, the personas, the templates and the framework's readable documents; any sentence of 12+ words in two files fails unless it is in `allowed-duplicates.txt`. 26 deliberate duplicates are baselined; planting the same sentence in three files fails it and names all three. | MISS-TechieFlow-20260908-04 (sorted `ignored`); maintenance contract rule 3, which said it and was not enforced |
| FR-68 | offers the same command names in both harnesses. A command a persona lists must have its own `techieflow:tasks:<command>` registration in `opencode.jsonc`, because OpenCode addresses a task by its registered name and cannot alias. A built-in that runs no task and writes no file is exempt (`help`, `exit`, `doc-out`, `yolo`, `report`). | script (built 2026-09-08): `bash tests/mirror/run.sh` runs `tests/mirror/cmd-parity.py` over all four personas, reading both command shapes — the analyst and architect's YAML list and the flow-master and verifier's markdown table. It found seven commands offered in Claude Code only, then five more that were aliases OpenCode could not reach, `*verify` and `*metrics` among them. **A first, looser version of the check would have passed all seven**, because each named `create-doc` and `create-doc` is registered; the defect was a command NAME existing in one harness, not a missing task. | MISS-TechieFlow-20260908-06 (sorted `unsaid`); briefing §1, both harnesses behave the same |

---

## 5. Decisions taken on 2026-09-04

| Decision | Result |
|---|---|
| Fixture projects | MyDiary (small greenfield, new), TrStudio and Xpenser (brownfield), TrBlazeUI and TechieRag (libraries). TechieDesk is Medium and part of a larger product, so it is not the small sample. |
| Small requirement cap | 50. |
| Owner review records | A new record kind `review`, named by phase (`day1-review`, `build-review`, …). UAT issues remain misses. |
| Instruction budget | A variable per model tier, 7,000 words for the frontier tier. Maintainer's recommendation accepted pending the owner's reading of FR-43. |
| Who reviews this list | The maintainer. The owner reviews the descriptive documents. |
| Distribution | Raised by the owner at the close of Session 2 and logged as `MISS-TechieFlow-20260904-23` before being added (group I). An npm package and pipeline like the Playbook's, built on the main branch in parallel with the reset on the dev branch. |

## 6. Maintainer's traceability review

Every line above cites a source the owner has reviewed or a decision the owner gave. Two statements were missing from the descriptive document and were added to `TechieFlow-How-It-Works.md` §8 as D-20 (acceptance lines are vague in 14 recorded misses) and D-21 (the framework folder is invisible to file search, so "not present" is written without trying the path). No line rests on the maintainer's opinion alone.

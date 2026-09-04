# TechieFlow — Framework Requirements

| | |
|---|---|
| Purpose | The list of things the framework must do, each with a way to check it. This is the framework's checklist. |
| Audience | Agents, and the framework maintainer who reviews it (Claude). **The owner does not review this list.** The owner reviews the descriptive documents it is derived from: `TechieFlow-How-It-Works.md` (including its defect table), `TechieFlow-Stack-Questions.md` and `TechieFlow-Stack-Defaults-DotNet.md`. Every line below traces to a statement in one of those documents or to a decision the owner gave in conversation. When a line needs a decision only the owner can make, the maintainer asks it as a plain question, never as "review this line". |
| Status | Session 2 of the reset (2026-09-04). Reviewed by the maintainer for traceability; owner decisions of 2026-09-04 applied. Checks marked "script" are written in Sessions 3 and 4. Group I (distribution) added 2026-09-04 after freeze, via miss 23. Agent document; not rendered to HTML. |
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
| MyDiary | small greenfield application (a journal site the owner is about to build; the first real project on the reset framework) | day-1 greenfield, mockups, build, verify, bugs |
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
| FR-03 | contains no language-, database-, UI-library- or host-specific instruction in any persona, task or shared rule file; such facts live only in answer sets and in a project's Stack Decisions. | script: grep persona, task and shared-rule files for `dotnet`, `Blazor`, `MAUI`, `Postgres`, `Serilog`, `xUnit`, `Dapper`, `DbUp`, `TrBlazeUI`, `Bluehost`; zero hits outside examples marked as examples. | owner 2026-09-04 |
| FR-04 | applies the two default rules of Q11 (logs under the build output folder, no unnecessary root folders) to every project unless the owner removes them. | script: after any fixture run, no log file at the repository root and no root folder outside the allowed set. | Stack Questions Q11 |
| FR-05 | enforces every rule recorded under Q11 in a project's Stack Decisions, and logs a violation as a miss. | script per rule, generated from the Stack Decisions table; for the .NET set: Dapper present and no other ORM, an `<App>Db` project using DbUp, no `database` root folder, no NuGet package absent from the Architecture document, one configuration mechanism. | Stack Defaults Q11; TfLens incident |

### B. Day-1 and documents

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-06 | runs greenfield day-1 in two stages: stage 1 produces the Architecture, the BRD and the mockups, linked to each other, and runs to completion in YOLO mode; stage 2 runs only on the owner's go-ahead and produces the checklist and the remaining documents. | fixture run: `*day1-greenfield MyDiary` in YOLO mode ends with Architecture, BRD and `docs/mockups/*.html` present and no checklist; the go-ahead produces the checklist. | D-1 |
| FR-07 | writes the BRD so that every use case links its mockup and lists the fields of every screen, beside the acceptance criteria. | script: every use-case section in the BRD contains a link to `docs/mockups/`; every screen in the UIDesign appears in the BRD. | D-2 |
| FR-08 | records an application size at day-1 stage 1 and applies that size's requirement cap and document budgets. | script: the BRD header carries `Size:`; requirement count and document word counts are within budget for that size. | D-3 |
| FR-09 | defines Small as up to 10 screens, one role, up to 50 requirements; Medium as up to 20 screens, up to 100 requirements; Large as anything beyond, to be split into phase-wise BRDs. AppManager does not count as an external integration. | review: the definition appears once, in the BRD template, and nowhere else. | D-3; owner 2026-09-04 |
| FR-10 | proposes a phase split, rather than growing the single BRD, when `*amend-docs` would take a project past its size's requirement cap. | fixture run: `*amend-docs TrStudio` with additions that exceed the cap; the run stops and proposes a phase split. | D-3 |
| FR-11 | applies mockups to any project, not only greenfield; brownfield day-1 finds existing mockups, records their location, and links them from the documents. | fixture run: `*day1-brownfield Xpenser` with a `docs/mockups/` folder present; the UIDesign and BRD link them and no mockup is regenerated. | D-5 |
| FR-12 | produces the checklist automatically once the owner approves the BRD; the owner never types `*split-brd`. | fixture run: after the stage 2 go-ahead on MyDiary the checklist exists without a separate command. | D-6 |
| FR-13 | produces the DevGuide automatically when the build phase completes the checklist, for every project type, and refreshes it at handoff. | fixture run: `*build-phase MyDiary` to completion; `docs/MyDiary-DevGuide.md` exists at the end. | D-7 |
| FR-14 | gives every human document template a strict structure (required sections in order, size budget per size class, row rules) and refuses to close a phase whose document breaks it. | script: `tf-doc-check.sh` exits 0 on every document the fixture runs produce, exits non-zero on a deliberately broken one, and the status gate refuses to close. | How-It-Works §2 Template; Session 3 |
| FR-15 | requires every checklist row to carry an acceptance line of the form "when … then …" naming an observable result. | script: every `REQ-` row in the fixture checklists matches the pattern. | D-20 |
| FR-16 | keeps one checklist per application as the single source of truth, in markdown only, and never creates dated `docs/qa/` or `docs/verify/` files or `-v2` document copies. | script: no `docs/qa/`, `docs/verify/`, `*-v2.*` or `*-Checklist.html` in any fixture. | conventions |
| FR-17 | renders every human document to HTML by script, never by hand; configuration and agent documents are not rendered. | script: every human `docs/*.md` has a sibling `.html` newer than itself; no `.html` exists for the checklist, the Stack documents or this file. | TF-003; owner 2026-09-04 |

### C. Build

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-18 | builds UI requirements from the approved mockups and nothing else, and compares the built screen to its mockup before marking it implemented. | fixture run: `*build-phase MyDiary`; the smoke log names the mockup compared for every UI row. | 39 partial-implementation misses; How-It-Works §3.4 |
| FR-19 | never writes `Verified` from a build, a fix or a status refresh; only an executed verify may. | script (hook exists): a write of `Verified` without a same-day verify ledger is refused. | convention; guard-verify hook |
| FR-20 | ends every command by rewriting PROJECT-STATUS in template shape and appending one run record. | script: after any fixture command, PROJECT-STATUS matches the template shape and `runs.jsonl` has one new line. | status gate; D-11 |
| FR-21 | records a library gap in that library's feedback file and holds the feature; it never implements a workaround. | fixture run: build a MyDiary requirement needing a TrBlazeUI control that does not exist; the row is `BLOCKED-BY-LIBRARY`, the feedback file has the entry, no workaround code exists. | Stack Defaults Q11.3 |
| FR-22 | starts a stopped database container itself when the database is unreachable, asks only when no container exists, and never creates its own database. | fixture run: stop the PostgreSQL container, run `*build-phase MyDiary`; the container is started and no new container or compose file appears. | Stack Defaults Q3 |
| FR-23 | writes all run-generated artefacts under `tests/.artifacts/` and never at the repository root. | script (hook exists): no root-level `test-results*`, `scripts-*` or similar after a fixture run. | TechieBlog incident |

### D. Verify

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-24 | applies the seven checks to every requirement in a fixed order and records the first that fails. | script: every `gates.jsonl` record from a fixture verify carries a gate value from the fixed list or none. | How-It-Works §6.2 |
| FR-25 | verifies against the acceptance line and the mockup, and states in the remark what was observed, so a `Verified` row can be re-derived by a reader. | review, to become a script: sample ten verified rows across fixtures; each remark names the observation. | 63 misses classified insufficient-verify-method |
| FR-26 | has a verify task of at most 4,000 words, with every mechanical step in a script. | script: word count of `verify-phase.md` ≤ 4,000. | D-8 |
| FR-27 | never reports a file or tool as "not present" without trying its literal path, because the framework folder is invisible to search. | script: the phrase "not present" in a checklist remark is refused unless the remark also names the path tried. | D-21 |

### E. Bugs and misses

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-28 | never edits source or spawns builders during `*triage-issues`. | script: no file under `src/` or `tests/` changes during a fixture triage run. | convention; How-It-Works §3.7 |
| FR-29 | records a miss automatically from triage (discovery cost) and from fix (fix cost); the owner never types `*log-miss` for a bug that went through either. | fixture run: triage then fix one bug on MyDiary; `misses.jsonl` gains a `miss` and a `miss-fix` with no manual log command. | D-15 |
| FR-30 | offers one command that runs the owner's bug sequence end to end in YOLO mode: compare screens to mockups, triage, log discovery cost, fix, log fix cost, metrics, with a summary per step. | fixture run: `*triage-and-fix MyDiary <folder>`; the final summary has six sections. | D-16 |
| FR-31 | stores the owner's one-sentence description of every miss in a human-readable file beside the record. | script: every `miss` record has a matching line in `docs/<App>-Misses.md`. | D-10 |
| FR-32 | sorts every miss with the four questions of §3 and records the answer. | script: every `miss` record carries the sort field. | §3 |
| FR-33 | records issues found by people in UAT as misses, never as reviews. | script: every record from `*triage-issues` is of kind `miss`. | owner 2026-09-04 |

### F. Telemetry

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-34 | emits one run record for every command, including day-1, mockups, DevGuide, ProductGuide and the idea-stage commands. | script: after each fixture command, `runs.jsonl` has a record with that command's name. | D-11; D-13 |
| FR-35 | records on every run whether YOLO mode was on. | script: every new run record carries `yolo: true|false`. | D-12 |
| FR-36 | records the outcome of every owner review as a record of kind `review`, named by its phase (`day1-review`, `build-review`, `verify-review`, `handoff-review`), carrying the number of corrections given, the cost of producing the reviewed output, and the cost of applying the corrections. | fixture run: day-1 stage 1 on MyDiary followed by an owner correction; the stream gains a `day1-review` record with those three fields. | D-17; owner 2026-09-04 |
| FR-37 | records framework maintenance work under the command value `framework-reset`. | script: the schema lists the value; the report accepts it. | D-19 |
| FR-38 | never merges provenance in a report: live with backfilled, or one project type with another. | script (exists in `tf-metrics.sh`): the report prints separate figures. | schema §0 |
| FR-39 | never blocks, fails or changes a verdict because a telemetry write failed. | review: `tf-emit.sh` exits 0 on every path. | schema |

### G. Harnesses

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-40 | works identically in Claude Code and OpenCode; every task is registered in both, and every hook has an OpenCode equivalent or a documented gap. | script: every task under `.tfcore/tasks/` is byte-identical in the Claude mirror and referenced in `opencode.jsonc`; the hook parity table has no undocumented row. | owner 2026-09-04 |
| FR-41 | honours YOLO mode in every command; `*build-phase` and `*verify` default to it. | fixture run: each command with the flag on completes without a prompt; build and verify complete without the flag. | D-18 |
| FR-42 | carries no Codex-specific code path once the Codex adapter is removed. | script: no `codex` reference outside the changelog. | D-14 |

### H. Instruction budget

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-43 | reads no more than the instruction budget before the first useful step of any command. The budget is a variable per model tier in `routing.yaml`, not a fixed number: 7,000 words for the frontier tier (about 9,500 tokens, under 5 percent of a 200,000-token context), and smaller for the standard and economy tiers. A task is written as a short core plus reference sections loaded only when a step needs them, so a small budget can be met without losing steps. | script: the section 5 table of `TechieFlow-How-It-Works.md` recomputed per tier; every "at start" value ≤ that tier's budget. | How-It-Works §5; owner question 2026-09-04 |
| FR-44 | keeps the shared rule files under 3,000 words in total and every persona under 1,500. | script: word counts. | How-It-Works §5 |
| FR-45 | keeps explanation and history out of task files; a task file contains steps only. | review, to become a script: no paragraph in a task file begins with "Why", "Because", "This exists", or a date. | How-It-Works §7 |
| FR-46 | converts a prose rule to a hook or deletes it after the second recorded `instruction-ignored` miss against it. | script: the miss report lists prose rules with two or more `instruction-ignored` misses; the list is empty. | §3 question 4 |
| FR-47 | names only public repositories in every document under the framework's `docs/`, README and templates. | script: grep for the private project names; zero hits. | owner 2026-09-04 |


### I. Distribution

| ID | The framework … | Check | Source |
|---|---|---|---|
| FR-48 | is published as an npm package, `@techierathore/techieflow`, installable into any project with one command, `npx @techierathore/techieflow@latest install`, and updatable with `… update`, without adding the framework as an application dependency. | script: on a clean fixture clone, the install command produces the same file set as `scaffold-brownfield.sh` (diff of the two results is empty) and leaves no `node_modules`, `package.json` or lock file behind. | D-22 |
| FR-49 | installs for both harnesses from the one package: the Claude Code mirror and settings, and the OpenCode registrations. | script: after install, `.claude/commands/TechieFlow/` is byte-identical to `.tfcore/`, and every `opencode.jsonc` file reference resolves. | D-22; FR-40 |
| FR-50 | is versioned through GitHub releases and published by a pipeline that runs automated checks first: mirror parity, OpenCode reference resolution, `bash -n` on every script, the installer's own tests, and a dry-run pack. | script: the release workflow fails when any check fails; the published package version equals the release tag. | D-22; Playbook release process |
| FR-51 | keeps the shell scripts (`scaffold-*.sh`, `update-framework.sh`) working from a local clone, and the installer produces the same result, so both routes stay valid. | script: the FR-48 diff, run from both routes. | D-22 |
| FR-52 | ships an Installation document that a person outside the owner's machines can follow to a working project in under ten minutes. | review, then fixture run: a fresh machine with Node installed, following the document only, reaches a working `*day1-greenfield` on MyDiary. | D-22 |

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

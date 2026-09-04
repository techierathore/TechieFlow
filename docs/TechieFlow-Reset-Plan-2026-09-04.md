# TechieFlow — Reset Plan (started 2026-09-04)

The owner's decision: fix both frameworks properly before building anything else. No deadline. No "good enough for now". The sessions below run in order until each one's output exists and the owner understands it. Then the Playbook gets the same treatment. Then the blog. Then building resumes.

**The order follows the software life cycle.** Documents come before code, so the document templates are fixed first. Then the tasks are shrunk in the order a project passes through them: day-1 documents, design, build, guides and handoff, and verification last. That matches the owner's portfolio: TechieRag and TrStudio are in design or redevelopment and need the early tasks first; AstroLyfe and most other apps are in user testing and need the late tasks, which come last.

Companion files written in the same pass:

- `TechieFlow-How-It-Works.md` — read this first, before Session 1.
- `AI-First-Playbook-Review-Prompt.md` — version 1 draft; version 2 is written after these sessions.
- `TechieFlow-Stack-Questions.md`, `TechieFlow-Stack-Defaults-DotNet.md`, `TechieFlow-Requirements.md` — Session 2 outputs; agent and configuration documents, not rendered.
- `TechieFlow-Distribution-Pipeline-Prompt.md` — the parallel track on `main`: npm package and release pipeline.

Blog material is kept out of this repo, in `/mnt/c/3AIGenCode/MyBlogSrc/`:

- `MyBlogSrc/Blog-Prompts.md` — three blog prompts plus the data-collection steps, for after the frameworks are fixed.
- `MyBlogSrc/collect-data.sh` — collects telemetry and feedback from every repo into `MyBlogSrc/data/`; also used in Sessions 2 and 5.

---

## 0. Decisions made now

**Clean slate: no.** The hooks, scripts, templates and scaffold scripts are six months of working parts. A rewrite would lose them and rebuild the same rules from the same incidents. We shrink in place. The owner creates a git branch named `dev` from `main` before Session 3, which is the first session that edits framework files. Sessions 3 to 7 work on `dev`; `main` stays a working framework until Session 6 has deployed the shrunk framework to a test project and it has run clean. Agents never run git.

**Both harnesses stay.** Every change is checked in the Claude Code mirror and in `opencode.jsonc`. Nothing OpenCode-related is removed. Codex is frozen: not removed, not touched, not propagated.

**Evidence comes from every project.** Seven repos carry telemetry, eighteen feedback files exist across the portfolio, and the framework's incident log names AstroLyfe, TrSetup, TrStudio, TechieBlog, AppStudio, TechieRag and more. Every session draws on all of them and asks the owner for examples from any project. Nothing is validated on one project only.

**Distribution runs in parallel.** The owner raised at the close of Session 2 that the framework has no package, version or pipeline (D-22, FR-48 to FR-52). That work runs on `main`, on a separate machine, from `TechieFlow-Distribution-Pipeline-Prompt.md`, while the reset continues on `dev`. The installer ships whatever `.tfcore/` contains, so the two tracks do not conflict.

**Where each change is proven.** TechieFlow changes are made in Claude Code and tested in both Claude Code and OpenCode, on a project that is actually at the matching life-cycle stage. Playbook changes are made in Claude Code and tested only in OpenCode.

---

## 1. Ground rules for every session

1. Plain words. If the owner cannot repeat a sentence back, the sentence gets rewritten before we move on.
2. The owner decides. Claude drafts, proposes, and explains. Every keep, cut, or change is the owner's call.
3. No new prose rules enter any task file during the reset. Misses found during the work go into the three-question sort in Session 5.
4. Every document goes into `docs/` in the repo. Never online.
5. Every change keeps both harnesses working.
6. Every example, question, and test spans projects. When Claude reaches for TfLens, the owner is entitled to say "give me another project".
7. Public-facing documents name only the owner's public repositories (TechieRag, TechieDesk, TrBlazeUI, TfLens, TechieBlog, TrStudio, TrSetup, Xpenser). Private projects are discussed in conversation only.
8. **Owner-reviewed documents are changed only with the owner's yes.** `TechieFlow-How-It-Works.md`, the Stack documents, this plan, and any BRD or mockup are the owner's review surface. Claude proposes a change in plain words, the owner accepts or rejects, and only then is the document edited. The same holds for a frozen checklist or requirements list: a gap found after freezing is first logged as a miss, then proposed, then added. Telling the owner afterwards is the defect that grew the framework unreviewed; it was repeated once in Session 2 and is logged as `MISS-TechieFlow-20260904-22`.
9. The reset is measured like any other development work. Every session ends with one run record in this repository's `docs/metrics/runs.jsonl` (command value `framework-reset`, added to the schema in Session 2), and every defect found is logged as a miss with its one-sentence description. Until the schema change lands, the session records are written with the new value and the schema is updated to match in Session 2.

---

## 2. The sessions

A session ends when its output exists and the owner understands it. Session 4 is long and is split into three sittings.

### Session 1 — Understand it

**Goal:** the owner can explain the framework to a colleague, and knows which commands they actually use.

**Owner brings:**
- `TechieFlow-How-It-Works.md` read once, with every line marked that is unclear, wrong, or disagreed with.
- Three or four real situations, from different projects, where the framework did something the owner did not expect. Examples of the kind of thing: TfLens spreading secrets across three places; TechieBlog's fourteen test-result folders; the AstroLyfe status loss; anything from TrBlazeUI or TechieRag builds.

**We do:** go through the marks. Claude answers each in plain words and edits the file until the owner is satisfied. Then each command gets a verdict: use, rarely use, never use.

**Output:** a corrected How-It-Works. A list of commands by usage. The "never use" list is removed in Session 4.

### Session 2 — The framework's own requirements, and the standing .NET decisions

**Goal:** the framework gets what every app gets: a checklist with testable lines. And the .NET decisions each app has been inventing on its own get written down once.

**Owner brings:** answers to the ten stack questions below. **Decided 2026-09-04:** the framework stays technology-neutral and asks these questions at day-1; the owner's .NET answers become an answer set offered as an option (`TechieFlow-Stack-Defaults-DotNet.md`). Fixtures agreed: MyDiary (small greenfield, new), TrStudio and Xpenser (brownfield), TrBlazeUI and TechieRag (libraries).

The ten questions:

1. Where does non-secret configuration live? (Expected: `appsettings.json` plus `appsettings.{Environment}.json`.)
2. Where do secrets live in development? (Expected: `dotnet user-secrets`.) And in production? (Environment variables, Key Vault, Docker secrets?)
3. Which database in development, which in production? Is a Docker container for the database ever allowed without a requirement asking for it?
4. Authentication: the owner has stated that AppManager is the shared platform for identity, roles, licences and subscriptions and is part of every application, not an external integration. Confirm this is the standing default, and state what a project does when AppManager is not wanted.
5. Logging: Serilog to file is already standing. Anything else?
6. Test projects: which framework (xUnit, NUnit, MSTest), and is a test project mandatory from day one?
7. Solution layout: one `src/` and `tests/`? Project naming is already standing (`<App>`, never `<App>.App`).
8. UI: TrBlazeUI always for Blazor? Blazor Server, WASM, or Auto by default? What about MAUI apps?
9. Hosting target by default: Bluehost VPS, Docker, IIS, Azure?
10. Anything an agent must never do in a .NET repo that is not yet a hook? (Examples: never add a NuGet package without a line in the Architecture doc saying why; never create a second configuration mechanism.)

**We do:**
- Claude writes `docs/TechieFlow-Stack-Questions.md` (the generic questionnaire, when each question is asked, where answers are recorded) and `docs/TechieFlow-Stack-Defaults-DotNet.md` (the owner's answer set). Both are configuration documents read by agents; neither is rendered to HTML.
- Claude runs `/mnt/c/3AIGenCode/MyBlogSrc/collect-data.sh` and drafts `docs/TechieFlow-Requirements.md`: about 40 lines of "the framework must …", each with a way to check it against one of the fixture projects. The lines come from four sources: the owner's non-negotiable conventions, the 128 recorded misses across all repos, the incidents in the framework's log, and the defects D-1 to D-14 listed in `TechieFlow-How-It-Works.md` §8. **The owner does not review this list line by line** (decided 2026-09-04: checklists are agent documents). Claude reviews it for traceability to the descriptive documents the owner has reviewed, and brings the owner only plain-language decisions.

**Output:** three documents. From now on a framework miss is either a requirement line with no check, or a line that was ignored. **Done 2026-09-04:** 47 requirement lines, 5 owner decisions recorded in the document's §5.

### Session 3 — Templates become schemas

**Goal:** every human document the framework produces gets a short required-shape list and a check script, so the AI cannot drift from the format. This comes before any task is shrunk, because the tasks exist to produce these documents.

**Owner brings:** a git branch created. For each document, which sections a small app truly needs and a rough maximum size. Claude proposes defaults from the existing documents across projects (TfLens, TechieBlog, Lekhak, AstroLyfe, TrBlazeUI have full sets); the owner adjusts.

**The documents, in the order a project produces them:** BRD, Architecture, UIDesign, Checklist (row rules only; it stays an agent document), Coding Standards, PROJECT-STATUS, UsageGuide, DevGuide, ProductGuide. **Added by the owner during Session 3 (2026-09-04):** a tenth document, the Deployment Checklist, produced after UAT from the owner's pipeline guidance document; its schema is agreed in `TechieFlow-Document-Schemas.md` §3.10 and its template and command are built in Sitting 4b.

**We do:** for each template, write a schema block at the top: required sections in order, word or row budgets by app size, per-row rules such as "acceptance line contains when … then". Write one script, `tf-doc-check.sh`, that reads the schema and fails the phase if a generated document breaks it. Wire it into the status gate. Add an app size (S, M, L) question to day-1 that sets the budgets. Test the checker against existing documents from at least three projects and report which would fail today and why.

**Output:** nine schema-backed templates, one checker script, size caps at day-1. Both harnesses can run the checker. **Done 2026-09-04:** nine templates with schema blocks, `tf-doc-check.sh` plus its self-test, status-gate step 7b, the day-1 size and kind question, the standards moved into `.tfcore/standards/`, and a shell-write guard on PROJECT-STATUS. Fourteen projects checked in report mode; the results and the owner's decisions are in `TechieFlow-Document-Schemas.md`. Three misses logged (24 to 26).

### Session 4 — Shrink every task, in life-cycle order

**Goal:** every task file the owner fully understands, roughly one third its current size overall, with prose that needed judgement kept, mechanical steps turned into scripts, and duplicates deleted.

**The method, same for every file:** Claude prints the task as a table, one row per block, with a one-line plain summary and a proposed verdict: keep as words, turn into a script, or delete as duplicate or obvious. The owner rules on each row and can ask "show me the block" or "why delete" on any row. Claude applies the verdicts, writes the replacement scripts, copies the file to the Claude Code mirror, confirms `opencode.jsonc` still points at it, and runs the command for real in both harnesses on a project at that life-cycle stage.

**Sitting 4a — the shared rules, then the document phase.**
- First the three shared rule files that every command loads (`_status-update-gate`, `_smoke-test-policy`, `_metrics-emit-gate`; 9,300 words together). They go first because every later task inherits whatever they say, so shrinking them first shrinks every task. This is the one step out of life-cycle order, and this is why.
- Then `day1-greenfield` (3,400 words), `day1-brownfield` (7,300), `mockups`, `split-brd`, `amend-docs`, `author-brd`.
- **Test on:** a project in design or redevelopment, TechieRag or TrStudio, the owner picks. Day-1 or amend-docs runs for real in both harnesses, and the Session 3 checker passes on what it produces.
- **Output:** the document-phase tasks shrunk and proven.

**Sitting 4b — the build phase and the guides.**
- `build-phase` (4,400 words), `devguide` (5,300), `productguide`, `handoff-phase`, `refresh-status`.
- **Added 2026-09-04:** the Deployment Checklist template (schema in `TechieFlow-Document-Schemas.md` §3.10) and a small new command, `*deploy-checklist {App} {pipeline-document}`, that fills it from the owner's pipeline guidance and the Stack Q9 and Q10 answers after UAT. It sits beside handoff because handoff runs before UAT and deployment after.
- **Test on:** the same design-stage project once it has a checklist, or a small project the owner chooses. A real build runs in both harnesses.
- **Output:** the build and handoff tasks shrunk and proven.

**Sitting 4c — verification and bug handling, last.**
- `verify-phase` (11,850 words, the largest), `fix-issues`, `triage-issues`, `log-miss`.
- **Test on:** a project in user testing, AstroLyfe or another the owner picks. A real verify and a real triage run in both harnesses.
- The seven commands the owner decided to remove on 2026-09-04 are removed here, with their registrations, from both harnesses: create-brd (author-brd), elicit (advanced-elicitation), document-project, index-docs, shard-doc, execute-checklist, kb-mode-interaction. `create-doc` stays because brainstorm's brief, competitor analysis and market research depend on it.
- YOLO handling is made uniform across every task (D-18): every command honours the flag; build-phase and verify default to it.
- **Output:** all tasks shrunk. Total task words near 20,000. Both harnesses tested end to end.

### Session 5 — The miss protocol and the telemetry explainer

**Goal:** misses become readable by a human, and the owner can present every telemetry number.

**We do, part one:** `*log-miss` (already shrunk in 4c) gains a one-sentence `what` that is written to a human file `docs/<App>-Misses.md` beside the record. The three-question sort becomes the first step of the task:

1. Did the app's spec say it clearly? If not, fix the app's checklist line. Framework untouched.
2. Did the framework say it anywhere? If not, add one line to `TechieFlow-Requirements.md` plus a check. No prose in task files.
3. Was it said and ignored anyway? Make it a hook or script, or delete it. A rule ignored twice never gets a third paragraph.

**Decided 2026-09-04 (FR-36):** an owner review is recorded as a new record kind `review`, named by phase (`day1-review`, `build-review`, …), with corrections given, cost to produce, cost to correct. UAT issues stay misses.

**We do, part two:** Claude writes `docs/TechieFlow-Telemetry-Explained.md`: each of the five report numbers, what it means, how it is calculated, one real figure from the combined data and one from a named project, and the one sentence the owner says about it in a talk. The owner reads it and rewrites any sentence they would not say.

**Output:** a miss log a human can read, and a telemetry page the owner can present from.

### Session 6 — Make the repository readable again, and deploy

**Goal:** the "read this first" file is short, the six-month log is archived, and every repo has the new framework.

**We do:** split `WorkFlow-Context.md` into a briefing of at most 3,000 words (what it is, how it is used, conventions, repo map, open items, maintenance contract) and `docs/CHANGELOG.md` holding the full maintenance log untouched. Trim README to what a new user needs, moving the rest to `docs/`. Run `update-framework.sh` against the projects the owner will build next (TechieRag, AstroLyfe, TrStudio), against one library repo, then the rest.

**Output:** a framework a newcomer, or the owner in six months, can pick up in twenty minutes, deployed everywhere.

### Session 7 — Write the Playbook review prompt, version 2

**Goal:** carry what these sessions taught into the Playbook review.

**We do:** rewrite `AI-First-Playbook-Review-Prompt.md` with the final keep/script/delete table format, the schema block format, the miss protocol wording, and a list of what went wrong during the TechieFlow sessions so the Playbook review does not repeat it. Built in Claude Code, tested only in OpenCode.

**Output:** the version 2 prompt. The Playbook sessions then follow their own plan.

---

## 3. What comes after the frameworks are fixed — order only, no dates

1. Run the distribution pipeline prompt on `main` (can start now, on another machine). Merge when its validation workflow is green.
2. Run the Playbook review (version 2 prompt) and its sessions, tested under OpenCode.
2. In `/mnt/c/3AIGenCode/MyBlogSrc/`, run `collect-data.sh`, then blog prompt 1 (the year), then prompt 2 (the framework), then prompt 3 (the measurements). One writing session each, in that order.
4. Resume building, in the owner's pipeline order: TechieRag update, AstroLyfe update, TrStudio, then the new apps (journal app, TechieDesk, the super-app). Each build logs every miss with the new `what` sentence.
5. Framework changes are batched: a miss goes into the three-question sort when it happens; the fix is applied in a batch, not the same hour.
6. When enough new misses exist across the new builds, re-run the collection script and compare against the 2026-09-04 figures. That comparison is the follow-up blog.

---

## 4. What the owner should expect Claude to ask, per session

So nothing is a surprise, and the owner can prepare answers in advance.

**Session 1**
- For each marked line in How-It-Works: "What did you read this as?" and then "Does this rewording say it?"
- For each of the 15 commands: "Have you run this in the last three months? On which project?"
- "Tell me the situations you brought. For each: which project, what you expected, what happened, what you did about it."
- "Which of these situations do you think was the framework's fault, which was the spec's, which was the model's?" (This warms up the three-question sort.)

**Session 2**
- The ten .NET questions, one at a time. For each answer: "Is there any project where you did it differently, and was that deliberate?"
- "Which two or three projects should be the fixtures we check the framework against?"
- Plain-language decisions only, never "review this line": fixtures, size caps, record kinds, budgets.
- "Is there a rule you follow in your head that is not written anywhere?"

**Session 3**
- For each of nine documents: "Which sections does a small app truly need? Which are only for medium or large?" and "What is too long, in pages or in words?"
- "For a requirement row, what must the acceptance line contain for you to trust it?"
- "The checker says these existing documents from these projects would fail today. Do you agree they are wrong, or is the schema too strict?"
- "Should the checker block the phase, or warn and continue?"

**Session 4, every sitting**
- "Which project do we test this batch on?"
- For each block in each task: "Keep as words, turn into a script, or delete?" Claude gives a one-line summary first; the owner can ask "show me the block" or "why do you think delete".
- When a block becomes a script: "What should the script print when it fails, in words you would want to read?"
- When two tasks say the same thing: "Which one owns this rule? The other loses it."
- At the end of each sitting: "Run the real command now in both harnesses, or first finish the next file?"
- In 4c only: "These commands were on the never-use list. Remove them now?"

**Session 5**
- For each of the five telemetry numbers: "Here is the plain definition and two real figures. Is this the sentence you would say on stage? If not, say it your way and I will write that."
- "When you log a miss, what is the one sentence you want to read a month later?"
- "Here are five real misses from different projects. Sort each with the three questions. Do we agree?"

**Session 6**
- "Here is the 3,000-word briefing. Anything from the old context file you want kept in it?"
- "Which repos get the update first?"

**Session 7**
- "What went wrong in our sessions that the Playbook review must avoid?"
- "What is different about a corporate team that the Playbook prompt must account for?"

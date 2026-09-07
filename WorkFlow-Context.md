# WorkFlow-Context — the briefing for this repository

> **Read this first, and read only this.** It says what this repository is, how the framework is used, the rules that are not negotiable, where everything lives, what is still open, and what you must keep in step when you change something. It is under 3,000 words on purpose. The six-month history that used to sit here is in **`docs/CHANGELOG.md`** and is not session reading.

| | |
|---|---|
| Repo | `/mnt/c/3AIGenCode/TechieFlow` on Windows/WSL and `/Users/MyCode/TechieFlow` on the owner's Mac, synced through GitHub. This is the framework template, not an application. |
| Last updated | 2026-09-07, at the close of the reset. |
| Branch | Work since Session 3 is on `dev`. The owner commits; agents never run git. |

---

## 1. What this repository is

TechieFlow is a software development harness companion. One person with domain knowledge takes a product through the whole life cycle, with AI agents doing the work and the person managing and reviewing every output. It is the template copied into each application, not an application itself.

It runs in two harnesses, **Claude Code** and **OpenCode**, and must behave the same in both. Nothing else is supported.

The owner's portfolio is .NET, Blazor, TrBlazeUI and MAUI, but **the framework itself is technology-neutral**. No persona, task or shared rule names a language, database, UI library or host. Those facts live in a stack answer set (`docs/TechieFlow-Stack-Defaults-DotNet.md` is the owner's) and in each project's Architecture document.

Alongside the work the framework measures the work: five append-only streams under each project's `docs/metrics/`. `docs/TechieFlow-Telemetry-Explained.md` is the readable version.

**The documents that explain the framework**, in reading order:

| Document | What it answers |
|---|---|
| `docs/TechieFlow-How-It-Works.md` | What every command does, what surrounds it, what it costs, where the design falls short. |
| `docs/TechieFlow-Document-Schemas.md` | The required shape, size and row rules of every document the framework produces. |
| `docs/TechieFlow-Requirements.md` | The framework's own checklist: 63 lines, each with a way to check it. Agent document. |
| `docs/TechieFlow-Telemetry-Explained.md` | The five report numbers, with real figures and the sentence to say about each. |
| `docs/TechieFlow-Reset-Plan-2026-09-04.md` | The seven sessions that shrank the framework, one Done line each. |
| `README.md` | How a person installs it and drives it. |
| `docs/CHANGELOG.md` | Everything that has been done to it, newest first. |

---

## 2. How the framework is used

Four personas: **analyst** (documents), **flow-master** (build, bugs, guides, status), **verifier** (verdicts), **architect** (optional deep dive). Two library agents, **trblazeui** and **techierag**, are deployed by their NuGet packages and are called as sub-agents, never directly.

1. **Scaffold.** `scaffold-greenfield.sh` or `scaffold-brownfield.sh` copies the framework into a project; `update-framework.sh` refreshes one already scaffolded. Never `npm install`.
2. **Day-1, stage 1.** `*day1-greenfield <App>` or `*day1-brownfield <App>` asks the stack questions and the application's size and kind, then produces the Architecture, the BRD and the mockups, linked to each other. It runs to completion in YOLO mode and stops there, because the next thing is the owner's review.
3. **Day-1, stage 2.** On the owner's go-ahead: the checklist through `*split-brd`, then Coding Standards, PROJECT-STATUS, CLAUDE.md, AGENTS.md and the UsageGuide. The owner never types `*split-brd` by hand.
4. **Build.** `*build-phase <App>` clusters every open row, routes `REQ-UI-` to trblazeui and `REQ-RAG-` to techierag, builds the rest itself, smoke-tests each screen it touched, then chains the verifier. A pass ends when every row is at least Implemented, never with "run me again for the rest".
5. **Verify.** `*verify ui|functional|all|<REQ list>` boots the application, drives it, and applies seven checks in a fixed order: build, acceptance, data, visual, assets, speed, standards. The first that fails is recorded. Only a verify run may write `Verified`.
6. **Bugs.** `*triage-issues` analyses and never touches code. `*fix-issues` repairs. `*triage-and-fix` runs the owner's whole sequence unattended. `*log-miss <App> "<one sentence>"` is the twenty-second record.
7. **Ship.** `*handoff-phase`, then the owner's testing, then `*deploy-checklist <App> <pipeline-document>` after UAT.
8. **Anytime.** `*amend-docs` for a change, `*refresh-status` after an interrupted run, `*devguide` and `*productguide` for the guides, `*metrics` for the report.

**Unattended runs go through the supervisor**, never a bare harness command: `bash .tfcore/utils/tf-goal.sh [--harness opencode] [--model <id>] <app-folder> "<goal>"`. It waits out a usage limit, retries a crash, and re-prompts an agent that stopped early.

---

## 3. Conventions an agent must honour

- **Agents never run git.** Writes are denied in every mode; reads are allowed only in YOLO. Status comes from the checklist, the files on disk and a fresh build, never from commit history.
- **One checklist per application**, `docs/<App>-Checklist.md`, one table, the single source of truth. Never rendered to HTML. Never a dated `docs/qa/` or `docs/verify/` file, never a `-v2` copy.
- **Every command ends at the status gate**: PROJECT-STATUS rewritten in its fixed shape, the documents it wrote checked by `tf-doc-check.sh`, the HTML re-rendered, one run record appended. A hook refuses to end the turn while any of that is undone.
- **`Verified` is written only by an executed verify run.** A build's own smoke test cannot go past Implemented.
- **Every human document has a schema** and a budget for the application's size. The checker blocks the phase on a broken shape and on the maximum budget; `--warn` is report mode for an existing project.
- **Every acceptance line reads "When `<actor>` `<does what>` on `<screen>`, then `<observable result>`"**, at most 30 words, one behaviour.
- **Telemetry is emitted by script, never assembled by hand**, and has no veto: a failed write never blocks anything. Never edit a stream.
- **Run material lives under `tests/.artifacts/`**, never at the repository root. It is swept after seven days.
- **A library gap is logged in that library's feedback file and the row is blocked.** Never work around it silently, never merge the two files.
- **The framework tree is invisible to file search.** `.tfcore/` is hidden and git-ignored, so Grep and Glob return nothing for files that are there. Confirm a file by reading its literal path, and never write "not present" without naming the path tried.
- **Every miss is logged through `tf-log-miss.sh` with its sort** — whose gap it was: `spec`, `unsaid`, `weak-check` or `ignored`. The maintainer's own misses included.
- **Owner-reviewed documents change only after the owner says yes.** `TechieFlow-How-It-Works.md`, the Stack documents, the Reset Plan, this file, the README, and any BRD or mockup. Propose in plain words first.
- **Public documents name only public repositories**: TechieRag, TechieDesk, TrBlazeUI, TfLens, TechieBlog, TrStudio, TrSetup, Xpenser.

---

## 4. Repo map

| Path | What it is |
|---|---|
| `WorkFlow-Context.md` | This briefing. |
| `README.md` | How a person installs and drives the framework. |
| `docs/CHANGELOG.md` | The full maintenance log and the 2026-06-12 audit register. |
| `docs/` | The framework's own documents (the table in §1), plus its telemetry under `docs/metrics/`. |
| `.tfcore/agents/` | The four personas. |
| `.tfcore/tasks/` | One file per command, plus the three shared rule files every command loads (`_status-update-gate`, `_smoke-test-policy`, `_metrics-emit-gate`) and `_yolo-mode`. |
| `.tfcore/templates/v4custom/` | Nineteen templates. Each human document's template opens with its schema block. |
| `.tfcore/standards/` | The technology-neutral coding standards and the .NET set. |
| `.tfcore/hooks/` | Eleven shell hooks. Eight refuse an action; three do housekeeping. |
| `.tfcore/utils/` | The scripts, `tf-*`. Every mechanical step of every task is one of these. |
| `.tfcore/telemetry/` | `SCHEMA.md` (read before emitting), `install-metrics.sh`, `tf-metrics.sh`, the `pre-commit` template the owner installs. |
| `.tfcore/core-config.yaml` | Per-project settings: application name, size, kind, phase, which documents load. |
| `.tfcore/routing.yaml` | Which model tier runs which command, per harness. Per project, owner-tuned. |
| `.claude/commands/TechieFlow/` | The Claude Code mirror of the personas and tasks. Byte-identical to `.tfcore/`. |
| `opencode.jsonc`, `.opencode/` | OpenCode's registrations and its guard-bridge plugin. There is no OpenCode mirror; it reads `.tfcore/` through file references. |
| `tests/` | The self-tests: `mirror`, `doc-check`, `bugs`, `verify`, `goal`. |
| `scaffold-*.sh`, `update-framework.sh` | Deploy the framework into a project, or refresh it. |

---

## 5. Recovering an interrupted session

If a run died mid-phase, the status gate never ran and `PROJECT-STATUS.md` is stale. Do not trust it. Run `*refresh-status <App>`; it rebuilds the status from the checklist, the working tree and a fresh build, writes a dated recovery note, and prints the command to resume with. It never reads git and never edits source. An unattended run resumes instead with `tf-goal.sh --resume <app-folder>`.

---

## 6. Open items

| Item | Whose |
|---|---|
| **Distribution**: the framework is an npm package with a validation workflow, merged from `main` on 2026-09-07. Publishing it is the remaining step (FR-48 to FR-52). | Owner action |
| Three requirements name a **script that has not been written**: FR-58 (refuse `done complete` while rows are unfinished), FR-60 (refuse a banned head name in a brief), FR-61 (grade a row not observable when the environment lacks the data). The idea-stage commands still emit no run record (FR-34, FR-60). | Maintainer |
| **Open misses** are listed with their outcome in `docs/TechieFlow-Misses.md`; the one this maintainer owes a fix for is 12 of 2026-09-07, that a hidden framework folder is invisible to search and nothing enforces the rule. | Maintainer |
| **TrStudio is not on this machine.** It is a named fixture and could not be refreshed here. | Owner action |
| **TfLens** needs the miss stream read into its pages before its figures are quotable, and carries three fixes named in its own feedback file. | Separate repo |
| **TrSetup has thousands of tracked build-output files.** Its ignore rules are correct and inert until the index entries go. `bash .tfcore/utils/tf-gitignore-audit.sh <repo>` prints the commands. Agents never run version control. | Owner action |
| **Both library packages need republishing** so the persona fixes reach consumers (TR-002, TR-RAG-002). | Owner action |
| **TechieRag holds two products in one repository**, which the one-checklist assumption cannot resolve: split the repo, or teach telemetry about it. | Owner decision |
| **Mockup parity needs anchored mockups.** A project whose mockups carry no `data-testid` is reported ungradeable, never passed. Per-project work. | Per project |
| Two owner-owned HTML documents still name the pre-2026 layout; the updater reports them and never edits them. | Owner action |

The last five are carried from the pre-reset list and were not re-checked during the reset.

---

## 7. Maintenance contract

When you change the framework, change all of these together.

1. **Mirror parity.** Any edit to `.tfcore/agents/` or `.tfcore/tasks/` is copied byte-for-byte to `.claude/commands/TechieFlow/`. Prove it with `bash tests/mirror/run.sh`. Never create `.opencode/command/TechieFlow/`.
2. **A new task needs four wirings**: the file under `.tfcore/tasks/`, the mirror, the command registered on its owning persona (mirrored too), and an entry in `opencode.jsonc`.
2b. **Anything that changes what a project receives goes into both delivery routes**: the shell scripts and `scripts/install.mjs`. A hook registration, a new folder under `.tfcore/`, a change to how an existing project is refreshed. `npm run test:install` compares the two routes file by file and is the check; run it on a normal filesystem, because a Windows mount reports every file executable and yields one false difference.
3. **A new rule is a script or a hook, not a paragraph.** A rule ignored twice never gets a third paragraph. Task files hold steps only; explanation and history belong in the documents of §1 and in the changelog.
4. **Prove every script by running it.** A script the maintainer has not run on a real project is not done. Both harnesses.
5. **Log every gap as a miss** through `tf-log-miss.sh`, with its sort, before proposing the fix.
6. **Record the work.** A maintenance session ends with one `framework-reset` run record in this repository's own metrics, a dated entry in `docs/CHANGELOG.md`, and this file's open items and date refreshed.
7. **Session memory is keyed on the repository path**, so it does not follow a move. This file is the durable record.

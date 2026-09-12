# WorkFlow-Context — the briefing for this repository

> **Read this first, and read only this.** It says what this repository is, how the framework is used, the rules that are not negotiable, where everything lives, what is still open, and what you must keep in step when you change something. It is under 3,000 words on purpose. The six-month history that used to sit here is in **`docs/CHANGELOG.md`** and is not session reading.

| | |
|---|---|
| Repo | `/mnt/c/3AIGenCode/TechieFlow` on Windows/WSL and `/Users/MyCode/TechieFlow` on the owner's Mac, synced through GitHub. This is the framework template, not an application. |
| Last updated | 2026-09-11. |
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
| `docs/TechieFlow-Requirements.md` | The framework's own checklist: 78 lines, each with a way to check it, 44 of them proved by a script. Agent document. |
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

**Unattended runs go through the supervisor**, never a bare harness command: `bash .tfcore/utils/tf-goal.sh [--harness opencode] [--model <id>] [--tier <tier>] <app-folder> "<goal>"`. It retries a crash, re-prompts an agent that stopped early, and on a usage limit moves to the next model the tier's `fallbacks:` chain names — waiting for the reset only when every model in the chain is limited (`--no-fallback` restores the old always-wait behaviour).

---

## 3. Conventions an agent must honour

- **Every command opens with a framework self-check.** `tf-phase.sh start` runs `tf-selfcheck.sh`, which points the framework's own scripts at this project's real files. A FAIL is the framework's, never the project's: log it in the project's framework-feedback file and carry on. It never blocks, writes nothing and grades nothing. `--report` prints the entry to paste; `TF_SKIP_SELFCHECK=1` skips it.
- **Agents never run git.** Writes are denied in every mode; reads are allowed only in YOLO. Status comes from the checklist, the files on disk and a fresh build, never from commit history.
- **One checklist per application**, `docs/<App>-Checklist.md`, one table, the single source of truth. Never rendered to HTML. Never a dated `docs/qa/` or `docs/verify/` file, never a `-v2` copy.
- **Every command ends at the status gate**: PROJECT-STATUS rewritten in its fixed shape, the documents it wrote checked by `tf-doc-check.sh`, the HTML re-rendered, one run record appended. A hook refuses to end the turn while any of that is undone.
- **`Verified` is written only by an executed verify run.** A build's own smoke test cannot go past Implemented.
- **Every human document has a schema** and a budget for the application's size. The checker blocks the phase on a broken shape and on the maximum budget; `--warn` is report mode for an existing project.
- **Every acceptance line reads "When `<actor>` `<does what>` on `<screen>`, then `<observable result>`"**, at most 30 words, one behaviour.
- **Telemetry is emitted by script, never assembled by hand**, and has no veto: a failed write never blocks anything. Never edit a stream. **A run's `started` is measured or taken from the previous run's `ended` — never typed.** The emitter refuses a run that begins before the last one ended and names the timestamp to use (SCHEMA §2.7b, FR-72); `--allow-overlap` is for two machines on one stream, nothing else. A record that is **wrong** is voided, not edited: `tf-emit.sh --void-run <cmd> <started> "<why>"` leaves both records on the stream and takes the named one out of every figure, with the count and the reason printed (SCHEMA §2.7, FR-69).
- **Records hold tokens; money is worked out by the report.** A run record carries tokens per model and whatever cost the provider itself reported — never a computed price, because pricing is a reporting job (`tf-metrics.sh`, TfLens) and a rate card that changes must not make an old record wrong. It also carries `billing_mode`, resolved from the harness's own credentials by `tf-model-pick.sh` and never declared by an agent, so a flat fee, a monthly plan's allowance and a real invoice are never added together (SCHEMA §2.5b).
- **Run material lives under `tests/.artifacts/`**, never at the repository root. It is swept after seven days.
- **A library gap is logged in that library's feedback file and the row is blocked.** Never work around it silently, never merge the two files.
- **The framework tree is invisible to file search.** `.tfcore/` is hidden and git-ignored, so Grep and Glob return nothing for files that are there. Confirm a file by reading its literal path, and never write "not present" without naming the path tried.
- **Every miss is logged through `tf-log-miss.sh` with its sort** — whose gap it was: `spec`, `unsaid`, `weak-check` or `ignored`. The maintainer's own misses included.
- **Owner-reviewed documents change only after the owner says yes.** `TechieFlow-How-It-Works.md`, the Stack documents, the Reset Plan, the README, and any BRD or mockup. Propose in plain words first. **This file is not one of them** — it is the agent's briefing, written by the maintainer for the maintainer, and it is kept current without asking (owner, 2026-09-09: *"it's a document for you"*). The owner reads output, the productivity figures and the readable documents; those are what a change must be worth.
- **Plain English to the owner; a decision goes in a file, not the conversation; an upstream defect is always filed, `Blocks: yes|no` first, and `no` never stops the run.** `.tfcore/tasks/_owner-language.md`. Since 2026-09-11 the closing message of a command, and any free-form document it hands over, is checked by the Stop hook through `tf-owner-text.sh` (FR-74): no word from `.tfcore/standards/owner-words.txt`, every open upstream problem with what it affects and its prompt, none fixed upstream called open, every command still to run as a line to paste, the next prompt in a code block. Add a word to that list when the owner has to ask what one means.
- **An agent document is never rendered to HTML.** The checklist and the miss list are refused by name; anything else whose only reader is an agent stays markdown.
- **A rule is a script, and it is written once.** `tests/mirror/run.sh` refuses the same sentence in two rule files (32 deliberate ones baselined) and holds the word caps. When a cap is reached, delete prose a check has replaced; never raise the cap.
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
| `.tfcore/templates/v4custom/` | Twenty-four templates, sixteen carrying a schema block. Each human document's template opens with its own; phase 2 onward of a Large project has its own BRD and UIDesign templates (`app-phase-brd-tmpl.md`, `app-phase-uidesign-tmpl.md`). |
| `.tfcore/standards/` | The technology-neutral coding standards and the .NET set. |
| `.tfcore/hooks/` | Twelve shell hooks. Nine refuse an action; three do housekeeping. |
| `.tfcore/utils/` | The scripts, `tf-*`. Every mechanical step of every task is one of these. |
| `.tfcore/telemetry/` | `SCHEMA.md` (read before emitting), `install-metrics.sh`, `tf-metrics.sh`, the `pre-commit` template the owner installs. |
| `.tfcore/core-config.yaml` | Per-project settings: application name, size, kind, phase, which documents load. |
| `.tfcore/routing.yaml` | Which model tier runs which command, per harness; the fallback chain each tier drops to when a model is limited; how each harness is paid for. Per project, owner-tuned. `docs/TechieFlow-Routing-Guide.md` is the plain version. |
| `.claude/commands/TechieFlow/` | The Claude Code mirror of the personas and tasks. Byte-identical to `.tfcore/`. |
| `opencode.jsonc`, `.opencode/` | OpenCode's registrations and its guard-bridge plugin. There is no OpenCode mirror; it reads `.tfcore/` through file references. |
| `tests/` | The self-tests: `mirror`, `doc-check`, `bugs`, `verify`, `goal`, `routing`, `requirements`, and `regression` — one case per defect a real project found in a shipped script, each required to fail against the script as that project found it. |
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
| **Model routing is deployed everywhere and enabled in three**: 19 repositories carry `tf-model-pick.sh` and a `routing.yaml` with a `fallbacks:` chain and a `billing:` block (added by the updater, never overwriting a line); three of them have `enabled: true` and generated bindings, the other sixteen keep their own `enabled: false`. Turning one on is `bash .tfcore/utils/tf-routing.sh on` in that project — Routing-Guide §2b. | Owner decision, per project |
| **Open misses** are listed with their outcome in `docs/TechieFlow-Misses.md` — 52 of 161 open (2026-09-11). The one this maintainer owes a fix for is 12 of 2026-09-07, that a hidden framework folder is invisible to search and nothing enforces the rule. | Maintainer |
| **TrStudio is not on this machine.** It is a named fixture and could not be refreshed here. | Owner action |
| **TfLens** needs the miss stream read into its pages before its figures are quotable. Its metrics update is specified in TfLens's own `docs/TfLens-Metrics-Update-Prompt.md` (that repository, not this one) and waiting on the owner's go-ahead. | Separate repo |
| **The 2026-09-11 changes, TF-028 to TF-036 included, are deployed in all 19 repositories**; each one's `tf-selfcheck` passes. TfLens's feedback file (identical to the copy in `docs/` here) reads 0 open, 14 fixed upstream and waiting to be re-checked (TF-018, TF-020, TF-021, TF-025 to TF-028, TF-030 to TF-036), 22 closed. | TfLens (re-check and close) |
| **Eighteen `.gitignore` files carry repeated framework blocks** left by FR-76's defect: TechieBlog 50 copies, TfLens 30, one private project 10, fifteen others 2. Repeated lines ignore nothing extra, so nothing is wrong, only untidy; the updater no longer adds them, and removes none. | Owner decision |
| **286 misses predate the `sort` field** (2026-09-07). Nothing is backfilled and no stream is edited: a reader derives what it can from the `why_missed` already on the record and labels it derived, and the field-start date reports the rest as predating the question, never as unanswered. No action, by anyone. | Closed |
| **TrSetup has thousands of tracked build-output files.** Its ignore rules are correct and inert until the index entries go. `bash .tfcore/utils/tf-gitignore-audit.sh <repo>` prints the commands. Agents never run version control. | Owner action |
| **Both library packages need republishing** so the persona fixes reach consumers (TR-002, TR-RAG-002). | Owner action |
| **TechieRag holds two products in one repository**, which the one-checklist assumption cannot resolve: split the repo, or teach telemetry about it. | Owner decision |
| **Mockup parity needs anchored mockups.** A project whose mockups carry no `data-testid` is reported ungradeable, never passed. Per-project work. | Per project |
| Two owner-owned HTML documents still name the pre-2026 layout; the updater reports them and never edits them. | Owner action |

| **Impossible run records on three streams cannot be repaired**, and no longer need to be. TechieBlog holds 13 whose `started` is after their `ended`, TfLens 1, and TechieRag 1 record no elapsed time. The emitter refuses new ones, the reader discards them and prints how many (`duration_measured_n` / `duration_impossible_n` / `duration_absent_n` / `duration_recomputed_n`), and the streams are append-only, so nothing is deleted. TechieBlog reads 72.9 hours over 33 usable records where it used to read 79.0 over 45. | Closed |

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
5b. **Answer every fix in the project's feedback file.** A problem a project filed is answered by a row in a `## Resolution status (TechieFlow team, <date>)` table in `docs/<App>-TechieFlow-Feedback.md` here, which the owner copies across. `tests/regression/run.sh replies_complete` fails while a problem the suite holds a case for still reads open there. `bash .tfcore/utils/tf-feedback.sh <App>` (run in the project) is the one reading of those files: open, fixed upstream and not yet re-checked, closed.
6. **Record the work.** A maintenance session ends with one `framework-reset` run record in this repository's own metrics, a dated entry in `docs/CHANGELOG.md`, and this file's open items and date refreshed.
7. **Session memory is keyed on the repository path**, so it does not follow a move. This file is the durable record.

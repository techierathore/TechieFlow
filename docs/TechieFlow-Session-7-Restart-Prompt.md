# TechieFlow — Session 7, restart prompt

| | |
|---|---|
| Purpose | The text the owner pastes into a fresh Claude Code window to start Session 7 of the reset, the last one. Written 2026-09-07 at the close of Session 6. |
| Audience | The owner, and the maintainer session that reads it. |
| Companion | `TechieFlow-Reset-Plan-2026-09-04.md` (Session 7), `AI-First-Playbook-Review-Prompt.md` (the version 1 draft being replaced), `TechieFlow-How-It-Works.md`, `TechieFlow-Document-Schemas.md`, `TechieFlow-Requirements.md`, `docs/CHANGELOG.md`, `TechieFlow-Session-6-Restart-Prompt.md` (the previous session) |

---

## The prompt (paste from here)

We are on the TechieFlow reset, Session 7, the last one: carry what these sessions taught into the AI-First Playbook review prompt. Branch: dev, everything uncommitted since Session 3; I commit when all sessions are done, agents never run git. Read, in this order: `WorkFlow-Context.md` (it is now 1,961 words and is the whole briefing), docs/TechieFlow-Reset-Plan-2026-09-04.md, docs/TechieFlow-Requirements.md, docs/AI-First-Playbook-Review-Prompt.md, then docs/TechieFlow-Session-7-Restart-Prompt.md in full. The six-month history is in docs/CHANGELOG.md and is not session reading.

State on 2026-09-07 at the close of Session 6. Sessions 1 to 6 are done; the Reset Plan carries a Done line for each. Session 6 left this on disk, all proven by real runs:

- `WorkFlow-Context.md` is a briefing of 1,961 words: what the repository is, how the framework is used, the conventions, the repo map, the open items, the maintenance contract. `README.md` is 1,864 words: what it is, how to install it, the flow, the command table for both harnesses, what it produces, where to read more. The history moved to `docs/CHANGELOG.md` unedited; the machine setup, the permission model and the gotchas moved to `docs/TechieFlow-Setup.md`, `docs/TechieFlow-Permissions-And-YOLO.md` and `docs/TechieFlow-FAQ.md`.
- The framework is deployed to **all 23 projects** carrying `.tfcore/`, three passes, every one exit 0, each verified by content rather than by modification time. No project's `opencode.jsonc` holds a dead reference; no project's `routing.yaml` names a removed command.
- Four framework defects found, fixed and proven (misses 05 to 09 of 2026-09-07): FR-47's check had never been written; `tf-log-miss.sh` called a refused record logged; the updater treated dead BMAD-era registrations as project content and so froze one repository with no working agents; and a run record with no `ended` was accepted and could never be costed.
- Five new checks: three in `tests/mirror/run.sh` (the two readable files against their budgets, no removed command named, FR-47 against a per-machine private-name file) and two in `tests/bugs/run.sh`. Self-tests at the close: mirror 12, doc-check 12, bugs 51, verify 67, goal 29.
- FR-62 added; FR-47's check rewritten. The requirements list stands at 62 lines.

Open work for this session:

1. Rewrite `docs/AI-First-Playbook-Review-Prompt.md` as version 2, carrying what the TechieFlow sessions actually taught: the keep-as-words / turn-into-a-script / delete table as the method for shrinking any prose file; the schema block format that stopped documents drifting; the four-question miss sort with its `sort` field; the rule that a rule ignored twice becomes a hook or is deleted; the instruction budget per model tier; and the discipline that every script is proven by a real run whose output is shown.
2. Include a plain list of what went wrong during the TechieFlow sessions so the Playbook review does not repeat it. The candidates are in each session's Done line and in `docs/CHANGELOG.md`'s Session 6 entry: rules that named a script nobody wrote, commands that reported success after a refusal, checks that measured the wrong thing, owner-review documents edited before the owner said yes, and the shell working directory drifting into a fixture.
3. Say what is different about a corporate team, because the Playbook is the team edition: review gates, onboarding, shared standards, and the fact that its harness is OpenCode only.
4. Build it in Claude Code and test it only in OpenCode, per the plan's rule for Playbook work.
5. Close the reset: one `framework-reset` run record, mode `session-7`; propose the Done line for Session 7; refresh the memory file; and tell the owner plainly that the seven sessions are complete and what happens next (the distribution pipeline on `main`, then the Playbook's own sessions, then the blog, then building resumes).

All three decisions the prompt carried are now taken (2026-09-07):

1. The **Codex adapter is removed** — from the framework, both delivery routes and all 23 projects (D-14 closed, FR-42 built as a check).
2. **`WORKFLOW.html` is dropped**, not regenerated; the README and the documents under `docs/` say what it said, and the updater removes it from a project that still has one.
3. **FR-47's scope stands** as Session 6 set it: the README, the briefing and the templates, with the reset's working documents deliberately out.

Method, unchanged: tables for anything the owner rules on, questions numbered after the table with a suggested answer, every script proven by a real run with its output shown, files mirrored to `.claude/commands/TechieFlow/` (`bash tests/mirror/run.sh` proves it), `opencode.jsonc` checked, both harnesses. Plain words. Owner-reviewed documents change only after the owner's yes. Every gap is logged as a miss through `tf-log-miss.sh` with its sort, the maintainer's own included. Every open decision is restated in full at the end of a message as a yes-or-no question. Fable 5.1 only in the reset session; Sonnet for long Claude runs; OpenCode through `tf-goal.sh --harness opencode --model openai/gpt-5.6-terra`.

Watch-outs paid for in Session 6, on top of the earlier ones:

- The metrics guard refuses any command line that names `docs/metrics/*.jsonl` together with `python3`, a redirection, `sed -i` or `cp`. It fired twice this session. A read of the streams goes into a script file under the scratchpad and the file is run.
- A self-test's `check` helper compares a **string** to 0, so a check must pass the exit code, not the command's output: end the substitution with `; echo $?`. A check written without it reports a failure that is not there, which is how ten minutes went on a fix that was already working.
- Grepping for a phrase that wraps across two comment lines finds nothing and looks exactly like a missing fix. Verify a deployed change by a distinctive phrase that sits on one line.
- A script changed mid-session has to be propagated again: this session ran `update-framework.sh` over all 23 projects three times for that reason. Always confirm by content.
- `tf-doc-check.sh` needs `--app` named explicitly in a repository holding two products: given the choice it takes the first checklist in alphabetical order, so TechieRag was reported as TechieDesk.
- Both readable files are owner-review surfaces. Session 6 rewrote them inside an unattended run and put the outline to the owner afterwards, with the originals recoverable; if the owner wants any of the old wording back, it is in `docs/CHANGELOG.md` and in the last commit on `main`.

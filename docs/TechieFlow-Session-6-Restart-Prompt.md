# TechieFlow — Session 6, restart prompt

| | |
|---|---|
| Purpose | The text the owner pastes into a fresh Claude Code window to start Session 6 of the reset. Written 2026-09-07 at the close of Session 5. |
| Audience | The owner, and the maintainer session that reads it. |
| Companion | `TechieFlow-Reset-Plan-2026-09-04.md` (Session 6), `TechieFlow-How-It-Works.md`, `TechieFlow-Document-Schemas.md`, `TechieFlow-Requirements.md`, `TechieFlow-Telemetry-Explained.md`, `TechieFlow-Session-5-Restart-Prompt.md` (the previous session) |

---

## The prompt (paste from here)

We are on the TechieFlow reset, Session 6: make the repository readable again, and deploy. Branch: dev, everything uncommitted since Session 3; I commit when all sessions are done, agents never run git. Read, in this order: docs/TechieFlow-Reset-Plan-2026-09-04.md, docs/TechieFlow-How-It-Works.md, docs/TechieFlow-Document-Schemas.md, docs/TechieFlow-Requirements.md, then docs/TechieFlow-Session-6-Restart-Prompt.md in full.

State on 2026-09-07 at the close of Session 5. Sessions 1 to 5 are done; the Reset Plan carries a Done line for each. Session 5 left these on disk, all proven by self-tests and real runs:

- Every miss record carries `sort`, whose gap it was: `spec`, `unsaid`, `weak-check` or `ignored`. `tf-log-miss.sh` refuses a miss without it and prints the four questions; `tf-triage.sh` fills a default; an older record is sorted once with `tf-emit.sh --amend <miss> sort <value>`. Session 4's 53 misses are sorted (weak-check 26, unsaid 15, ignored 14); 41 of them closed against the sitting in which the fix landed; four stay open with their outcome named in `docs/TechieFlow-Misses.md`.
- `docs/<App>-Misses.md` and its HTML are rebuilt by `tf-misses-md.sh` from the stream after every write to it, by the emitter itself. This repository, TechieBlog and the MyDiary copy have theirs; every other project gets its file the first time a miss is written after `update-framework.sh`, or by running the script once.
- `tests/mirror/run.sh` (8 checks): mirror parity, OpenCode references, the FR-43 and FR-44 budgets. Self-tests: bugs 48, verify 67, goal 29, doc-check clean, mirror 8.
- `tf-metrics.sh` keys a requirement by project and id in a rollup (the combined first-pass rate is 48%, not the 72% it printed before), reports whose gap and owner reviews, and counts an amended old record as sorted.
- `docs/TechieFlow-Telemetry-Explained.md`: the five numbers with definitions, calculations, combined and named figures, and the owner's stage sentences. The combined figures exclude the OpenCode copies, which carry their originals' history.
- FR-58 to FR-61 added; FR-18, FR-31, FR-32, FR-40 checks reworded. Open script candidates named there: `tf-yolo.sh done complete` refused while rows sit at Implemented or Blocked or the ledger has untested rows (misses 08 of 09-06 and 01 of 09-07); the verdict script mapping a sign-in redirect or an empty list to "not observable, environment" (FR-61); the idea-stage commands still emit no run record (FR-34, FR-60).
- TechieBlog's 87 regression misses of 2026-09-06 are closed as will-not-fix (one empty database, not 87 defects); its readable file says so.

Open work for this session, in the plan's order:

1. Split `WorkFlow-Context.md` (344 KB, mostly the six-month incident log) into a briefing of at most 3,000 words (what it is, how it is used, conventions, repo map, open items, maintenance contract) and `docs/CHANGELOG.md` holding the full log untouched. Trim `README.md` (121 KB) to what a new user needs; the rest moves to `docs/`. Both are owner-review surfaces: propose the briefing's outline first.
2. Run `update-framework.sh` on the projects the owner will build next (TechieRag, AstroLyfe, TrStudio), then one library repo (TrBlazeUI), then the rest. Before each: `pgrep -af tf-goal.sh` excluding `bash -c`, so no active supervisor is touched. After each: `tf-doc-check.sh --app <App> --warn` for the report, and `bash .tfcore/utils/tf-misses-md.sh` so the readable file exists. Projects not refreshed since Sitting 4c still name `author-brd` in their own `routing.yaml`; the updater prints the warning.
3. Decide with the owner whether the Codex adapter is removed now (D-14, FR-42) or after the reset; it is frozen, not propagated.
4. Close the session: one `framework-reset` run record, mode `session-6`; propose the Done line; refresh the memory file; write the Session 7 restart prompt.

Method, unchanged: tables for anything the owner rules on, questions numbered after the table with a suggested answer, every script proven by a real run with its output shown, files mirrored to `.claude/commands/TechieFlow/` (`bash tests/mirror/run.sh` proves it), `opencode.jsonc` checked, both harnesses. Plain words. Owner-reviewed documents change only after the owner's yes. Every gap is logged as a miss through `tf-log-miss.sh` with its sort, the maintainer's own included. Every open decision is restated in full at the end of a message as a yes-or-no question. Fable 5.1 only in the reset session; Sonnet for long Claude runs; OpenCode through `tf-goal.sh --harness opencode --model openai/gpt-5.6-terra`.

Watch-outs paid for in Session 5, on top of 4b's and 4c's:

- The shell's working directory drifts into a fixture after a test run; every path is absolute, and a `cd` in a compound command is a permission prompt.
- The metrics guard refuses any command line that names `docs/metrics/*.jsonl` together with `python3`, a redirection, `sed -i` or `cp`. A read of the streams goes into a script file under the scratchpad and the file is run.
- An amend record can never be undone: a sort or a why written on the wrong miss stays. Table the batch, get the yes, run it once.
- A `${var:?message}` guard with an apostrophe in the message is a syntax error that stops the whole script; `bash -n` every script before it writes a record.
- The combined figures pool the OpenCode copies with their originals unless the copies are left out of the rollup.

# TechieFlow — Session 5, restart prompt

| | |
|---|---|
| Purpose | The text the owner pastes into a fresh Claude Code window to start Session 5 of the reset. Written 2026-09-07 at the close of Sitting 4c. |
| Audience | The owner, and the maintainer session that reads it. |
| Companion | `TechieFlow-Reset-Plan-2026-09-04.md` (Session 5), `TechieFlow-How-It-Works.md`, `TechieFlow-Document-Schemas.md`, `TechieFlow-Requirements.md`, `TechieFlow-Sitting-4c-Restart-Prompt.md` (the previous sitting) |

---

## The prompt (paste from here)

We are on the TechieFlow reset, Session 5: the miss protocol and the telemetry explainer. Branch: dev, everything uncommitted since Session 3; I commit when all sessions are done, agents never run git. Read, in this order: docs/TechieFlow-Reset-Plan-2026-09-04.md, docs/TechieFlow-How-It-Works.md, docs/TechieFlow-Document-Schemas.md, docs/TechieFlow-Requirements.md, then docs/TechieFlow-Session-5-Restart-Prompt.md in full.

State on 2026-09-07 00:45 UTC. Sessions 1 to 4 are done; the Reset Plan carries a Done line for each sitting. Sitting 4c left these on disk, all proven by self-tests and real runs:

- `verify-phase` is 964 words on nine scripts under `.tfcore/utils/`: `tf-verify-list.sh` (the work list), `tf-verify-env.sh`, `tf-verify-boot.sh` (web head, a MAUI Blazor Hybrid Windows head over the WebView2 DevTools port through `tf-cdp-relay.ps1`, or a static folder), `tf-verify-screens.sh` (render and visual at two widths, a screenshot per screen; also the smoke evidence), `tf-verify-tests.sh`, `tf-perf-grade.sh`, `tf-verify-verdict.sh` (the seven checks in order, the ledger with every row's verdict, the checklist cells) and `tf-verify-emit.sh`. Android, iOS and Mac heads have no driver: their rows are written "not verified". Self-test `bash tests/verify/run.sh`, 67 checks.
- `triage-issues` (448 words), `fix-issues` (386), `log-miss` (430) and the new `triage-and-fix` (283) run on `tf-triage.sh` (demote, new, note, close), `tf-log-miss.sh`, `tf-fix-close.sh` and the shared `tf-checklist-edit.py`; the emitter has `--origin-of` and fills `yolo` on every run record. A row logged from UAT starts `Not Started` with the marker `BRD-pending`. Self-test `bash tests/bugs/run.sh`, 36 checks. All task files together: 20,282 words.
- The seven never-used commands are gone from both harnesses; the routing bind generator skips a phase whose task file no longer exists and says so. Projects not refreshed since the removal still list `author-brd` in their own `routing.yaml`; the next `update-framework.sh` prints the warning.
- Hooks: the verify hook refuses a hand-written `Verified` unless today's ledger lists the row as PASS; the build guard also refuses a backgrounded `npx playwright test` or verify script; the database guard ignores echo strings and comments. The document checker takes a baseline at every `tf-phase.sh start` and prints findings that predate the command as OLD, which do not block.
- Real runs: MyDiary `*fix-issues` found the blank-screen root cause (a LoggingErrorBoundary with no markup shadowed ErrorBoundary's render); all 20 screens render; rows stay `Needs re-verify` until the app carries the mockups' `data-testid` anchors. TechieBlog `*verify all` ran in Claude Code (Sonnet, three hours: 15 PASS, 86 FAIL on acceptance because the local database has no published post and the staff accounts sat behind a password gate) and in OpenCode on TechieBlog-oc (gpt-5.6-terra, twelve minutes: it wrote no tests, 101 rows not tested). `*triage-issues uiIssues` (five owner screenshots of 2026-08-24) ran in both: Claude found none reproducing and wrote three notes; OpenCode demoted two and noted three. TechieBlog and TechieBlog-oc share one database; the UsageGuide test-user rows were aligned by hand after two runs rotated passwords.
- Misses 17 to 27 of 2026-09-06 and 01 to 02 of 2026-09-07 are logged in this repository's stream. Two are for this session's sort: 26 (what a verify does when the test data an acceptance line needs is missing: create it through the app, pass a password gate through its screen, or write "not observable, environment") and 20260907-01 (the OpenCode verify skipped writing tests).

Open work for this session, in the plan's order:

1. `*log-miss` gains the readable file: every `miss` record's `what` sentence is written to `docs/<App>-Misses.md` beside the record (FR-31; the sentence is already in the record since 4c). The three-question sort becomes the first step of `tf-log-miss.sh` and the record carries the answer (FR-32): the app's spec did not say it (fix the checklist line), the framework did not say it (one requirement line plus a check, no prose in task files), it was said and ignored (a hook or script, or delete the rule).
2. Sort the misses of Session 4 with the three questions, five real ones from different projects first, and apply the outcomes in a batch.
3. Write `docs/TechieFlow-Telemetry-Explained.md`: the five report numbers, each with its plain definition, how it is calculated, one figure from the combined data and one from a named public project, and the sentence the owner would say on stage. The owner rewrites any sentence they would not say.
4. Close the session: one `framework-reset` run record, mode `session-5`; propose the Done line; refresh the memory file.

Method, unchanged: tables for anything the owner rules on, questions numbered after the table with a suggested answer, every script proven by a real run with its output shown, files mirrored to `.claude/commands/TechieFlow/`, `opencode.jsonc` checked, both harnesses. Plain words. Owner-reviewed documents change only after the owner's yes. Every gap is logged as a miss, the maintainer's own included. Every open decision is restated in full at the end of a message as a yes-or-no question. Fable 5.1 only in the reset session; Sonnet for long Claude runs; OpenCode through `tf-goal.sh --harness opencode --model openai/gpt-5.6-terra`.

Watch-outs paid for in 4c, on top of 4b's:

- The framework's own hooks fire in the maintainer's session: a command whose text names `docs/metrics/*.jsonl`, a migration tool, or a verify script together with `&`, `nohup` or `setsid` is refused whatever it does. Write such steps into a script file with the Write tool and run the file.
- `pgrep -f <pattern>` matches the maintainer's own shell, whose command line holds the pattern; exclude `bash -c` before killing or waiting on anything.
- A copy for OpenCode (`<App>-oc`) shares the original's database; a password rotated by one run must be written into both UsageGuides.
- The rsync of a project on `/mnt/c` takes hours; exclude `node_modules`, `bin`, `obj`, `.git` and `tests/.artifacts`, and check completion by the folder's contents, not by a process match.

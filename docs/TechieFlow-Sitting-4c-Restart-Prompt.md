# TechieFlow — Sitting 4c, restart prompt

| | |
|---|---|
| Purpose | The text the owner pastes into a fresh Claude Code window to start Sitting 4c of the reset. Written 2026-09-06 16:15 UTC at the close of Sitting 4b. |
| Audience | The owner, and the maintainer session that reads it. |
| Companion | `TechieFlow-Reset-Plan-2026-09-04.md` (Session 4, Sitting 4c), `TechieFlow-How-It-Works.md`, `TechieFlow-Document-Schemas.md`, `TechieFlow-Requirements.md`, `TechieFlow-Sitting-4b-Restart-Prompt.md` (the previous sitting) |

---

## The prompt (paste from here)

We are on the TechieFlow reset, Session 4, Sitting 4c. Branch: dev, everything uncommitted since Session 3; I commit when all sessions are done, agents never run git. Read, in this order: docs/TechieFlow-Reset-Plan-2026-09-04.md, docs/TechieFlow-How-It-Works.md, docs/TechieFlow-Document-Schemas.md, docs/TechieFlow-Requirements.md, then docs/TechieFlow-Sitting-4c-Restart-Prompt.md in full.

State on 2026-09-06 16:15 UTC. Sessions 1, 2, 3 and Sittings 4a and 4b are done; the Reset Plan carries a Done line for each. Sitting 4b left these on disk, all proven by real runs:

- The goal supervisor `.tfcore/utils/tf-goal.sh`: reads the Claude result line before guessing (a clean stop is a stop, not a crash), kills a cycle silent for 15 minutes and re-prompts, starts a fresh session after two stalled resumes (`--resume --fresh` by hand), reads the OpenCode log after a silent stall and exits 5 when the provider refused the model, stops its child on Ctrl-C or kill and exits 130. Self-test `bash tests/goal/run.sh`, 29 checks.
- `tf-yolo.sh done` refuses the completion sentinel until PROJECT-STATUS and a run record for the command the phase marker names are newer than the goal start.
- Hooks, eleven in all, listed in How-It-Works §2: new are `guard-build.sh` (a backgrounded build, test or app run is refused while YOLO is on) and the Stop hook checking every checklist written in the session. The OpenCode plugin vets `apply_patch` per file through the same guards, because OpenAI models have no edit or write tool.
- `tf-build.sh` counts Razor, Blazor and XAML errors as code errors. `tf-emit.sh` names the app from `<App>-Checklist.md` only and fills a missing `duration_s`.
- Models: OpenCode runs on `openai/gpt-5.6-terra` (frontier, standard) and `openai/gpt-5.6-luna` (economy) since 2026-09-06; the OpenCode Go monthly limit is reached until about 2026-09-12. Claude Code: Sonnet for long runs, Haiku for cheap ones. The framework default `.tfcore/routing.yaml` and the four test projects say so; `docs/TechieFlow-Routing-Guide.md` was rewritten plainly.
- MyDiary (`/mnt/c/1MyCode/MyDiary`, Sonnet): built, 67 tests pass, the Windows head boots, but every screen is blank at runtime because routed content never mounts in the layout's `@Body` (found by the DevGuide run). Checklist: 7 Verified, 9 Implemented, 60 Needs re-verify, 1 Blocked. The copy `/mnt/c/1MyCode/MyDiary-oc` (OpenCode, gpt-5.6-terra): 84 Implemented, 1 Needs re-verify, 2 N/A, nothing runtime-verified, DevGuide static-only.
- Misses 01 to 16 of 2026-09-06 are logged; the ones that belong to this sitting: 07 (the smoke policy has no path for a native app head and names no evidence file, so a MAUI build wrote no smoke evidence and called 69 untested rows Implemented), 08 (a build agent wrote "complete" where "blocked" was honest), 13 and 15 (a build closed without its own run record).
- Four projects carry today's framework through `update-framework.sh`: MyDiary, MyDiary-oc, TfLens, TfLens-oc. Every other project does not.

Open work for this sitting, in the plan's order:

1. Shrink `verify-phase` (11,850 words, FR-26 says at most 4,000). It is where 63 of the 128 recorded misses came from. The seven checks stay as the definition; the setup and the how-to become scripts; the checks that already are scripts (`tf-assets.sh`, `tf-mockup-parity.sh`, `tf-perf.sh`) are wired, not described. It must say what a verify does for a native app head (MAUI, no browser robot): drive the Windows head, or record honestly that the row is not verified, never "static-only Implemented". A dialog is verified on its parent page, never promoted to a route (Schemas §2, miss 24 of 2026-09-04).
2. Shrink `fix-issues`, `triage-issues`, `log-miss`. Triage calls log-miss for every root cause, fix calls it when a fix lands (D-15). One command runs the owner's whole bug sequence in YOLO with a summary per step (D-16, FR-30). Every task honours YOLO; build and verify default to it (D-18).
3. Remove the seven never-used commands from both harnesses and their registrations: create-brd (author-brd), elicit (advanced-elicitation), document-project, index-docs, shard-doc, execute-checklist, kb-mode-interaction. `create-doc` stays.
4. Real runs, both harnesses, on a project in user testing that the owner picks (the plan names AstroLyfe): a real `*verify` and a real `*triage-issues`. Before that project is used, run `update-framework.sh` on it. A real `*fix-issues` on MyDiary for the blank screens is the natural first fix run.
5. Close the sitting: one `framework-reset` run record, mode `sitting-4c`; propose the 4c Done line for the Reset Plan and wait for my yes; refresh the memory file.

Method, unchanged: print each task as a table (block, plain summary, verdict: keep as words, script, or delete), questions in a numbered list after the table with a suggested answer, never inside a cell; I rule on every row; write the scripts; prove every script and hook with a real run and show me the output; mirror the file to `.claude/commands/TechieFlow/`; confirm `opencode.jsonc` still points at it; run the command for real in both harnesses. Plain words, no jargon; when I say I did not understand, say it again shorter. Owner-reviewed documents (the plan, How-It-Works, the Stack documents, the Schemas doc) change only after my yes. Every gap found is logged as a miss with one sentence, my own slips included. Every open decision is restated in full at the end of a message as a yes-or-no question, never as a pointer. Fable 5.1 only in this reset session; Sonnet for every long Claude run; OpenCode through `tf-goal.sh --harness opencode --model openai/gpt-5.6-terra`.

Watch-outs paid for in 4b:

- The shell's working directory persists between commands. Every script edit and every emit uses the absolute framework path `/mnt/c/3AIGenCode/TechieFlow/…`; a relative path once patched a project copy and once put a framework miss into a copy's stream.
- Never touch a folder with an active supervisor. Check with `pgrep -af tf-goal.sh` before an update or an edit there.
- Start a long supervisor detached (`nohup setsid bash …tf-goal.sh … > log 2>&1 < /dev/null & disown`), because Claude Code kills its own background shells when memory runs low. Watch it by polling its `goal.log` every 30 seconds; `tail -F` fails on `/mnt/c` files.
- `--model` on the supervisor changes only the main agent; sub-agents use the project's routing bindings. When a provider is down, change the project's `routing.yaml` tiers and run `tf-routing.sh bind`.
- OpenCode prints only its header when the provider refuses the model; the reason is in `~/.local/share/opencode/log/opencode.log`. The supervisor now reads it.
- Before saying nothing is running, stop every monitor by its id; the maintainer cannot list them, the owner sees `/tasks`. Name each background shell by its launch line and its folder.
- The framework's own hooks fire in the maintainer's session too: a command whose text writes to PROJECT-STATUS or to `docs/metrics/*.jsonl` is refused even inside a heredoc. Put such test steps in a script file and run the file.

## Appendix: goal texts to reuse

### fix-issues on MyDiary (Sonnet, Claude Code)

    Load the flow-master persona (.tfcore/agents/flow-master.md) and run `*fix-issues MyDiary docs/MyDiary-DevGuide.md`, following .tfcore/tasks/fix-issues.md step by step, starting with step 0 (`bash .tfcore/utils/tf-phase.sh start fix-issues MyDiary`). The defect is in the DevGuide's Known issues: on the MAUI Windows head every routed page's content fails to mount inside MainLayout's `@Body` (src/MyDiary/Components/Layout/MainLayout.razor), so all 20 phase-1 screens are blank at runtime. Reproduce it by booting the Windows head (bash .tfcore/utils/tf-build.sh run src/MyDiary/MyDiary.csproj -- -f net10.0-windows10.0.19041.0), fix the root cause, re-smoke every screen, re-verify the touched rows, run the status gate and the run record, then `bash .tfcore/utils/tf-yolo.sh done complete "<one line: root cause, screens now rendering, rows by status>"`. Builds run in the foreground. Never run git.

### verify on the user-testing project (both harnesses; replace <App>)

    Load the verifier persona (.tfcore/agents/verifier.md) and run `*verify all <App>`, following .tfcore/tasks/verify-phase.md step by step, starting with step 0 (`bash .tfcore/utils/tf-phase.sh start verify-phase <App>`). Boot the application yourself, apply the seven checks to every row in scope in the fixed order, record the first failing check per row in gates.jsonl, write `Verified` only for a row you observed, state the observation in the Remark, write docs/.last-verify.json, run the status gate and the run record, then `bash .tfcore/utils/tf-yolo.sh done complete "<one line: rows Verified, Needs re-verify, first-failing-check counts>"`. Never run git.

# develop-end-to-end

`*develop-end-to-end {App} [{brief}] [--no-git | --no-push] [--model <id>] [--dry-run]` develops an app unattended to the point where the owner starts UAT: Day 1 (both stages), then every phase of `docs/{App}-Phases.md` in order (one phase when there is none), each with its build, inline verify and fixes, and its handoff (UsageGuide, smoke checklist, test users). No question, no confirmation, no review stop (`.tfcore/tasks/_develop-mode.md`). It commits and pushes after every step unless told not to, and reports the time and tokens of each step and of the whole build.

It takes a new app from a brief, or an app whose documents are already written. `tf-develop-plan.py` decides before each step: a Day-1 stage whose documents are all on disk is skipped, one with some missing writes only those, and a phase whose Phases row says `done` or `kept-whole` is skipped.

## Before it starts

TechieFlow is scaffolded into the app's folder. `{brief}` is a file path or the brief's text; text is written to `docs/{App}-Brief.md` as given, never shortened. It is needed only when `docs/{App}-BRD.md` does not exist.

Git: by default the folder is a git repository of its own with a remote (GitHub). `--no-push` commits without pushing. `--no-git` when the owner keeps git: nothing is committed or pushed, no repository is needed, and every step is still recorded.

Refuse, with one line saying what is missing, when: there is no BRD and no brief, the git setup the chosen switch needs is missing, or a develop run is already active (`.tfcore/.session/develop.json` exists: offer `--resume`). `--dry-run` prints the plan (each step run or skipped, and the git line) and runs nothing.

## Steps

First: `bash .tfcore/utils/tf-phase.sh start develop-end-to-end {App}` prints the start time; keep it.

1. Write the brief to `docs/{App}-Brief.md` when it was given as text. Then record this launch, before the run starts, so its record never overlaps the phases' own (`.tfcore/tasks/_metrics-emit-gate.md`): `tf-emit.sh runs` with `"cmd":"develop-end-to-end","mode":"launch"`, the start time and no rows, then `bash .tfcore/utils/tf-phase.sh end`. The phases record themselves; the Build Report adds them up.
2. Start the supervisor detached, so it outlives this session, with the harness this session runs in and the model it runs on:
   `bash .tfcore/utils/tf-develop.sh . --app {App} [--brief docs/{App}-Brief.md] --harness <claude|opencode> --model <id> --detach`
   `--model` is the one the owner named, else this session's own model id. Without it the script reads this session's model itself; it never falls back to a routing default, and it refuses when it cannot tell. `--no-git` or `--no-push` when the owner gave it. `--dry-run` instead of `--detach`: print its output and end, recording nothing.
   It returns once the run is alive and prints its pid, host, harness and model. Show that line to the owner as it is.
3. Follow the run in this window until it ends, with a background command the harness reports back on. Never a sleep loop, and never end the turn without it:
   - Claude Code: the Monitor tool on `bash .tfcore/utils/tf-develop.sh . --follow`, the longest timeout it allows; when it expires, start it again. Each line it prints is an event.
   - OpenCode: the bash tool with background on, `bash .tfcore/utils/tf-develop.sh . --follow --next`. It returns at the next event; say it, then start it again.
   For each event, one line to the owner: a step started or ended, the phase, rows built and verified, a verify's result, the time of the last activity. When the follow prints `the run has ended`, give its lines: the result, built in, tokens, the blocker if any, and the next command. This session does none of the phases itself.

`*develop-status {App}` (`develop-status.md`), from any window: `bash .tfcore/utils/tf-develop.sh . --status`, shown as printed. It says whether the run is alive (its pid and host, checked, never assumed; a run whose process is gone reads `stopped`), the harness and model, the step and phase, when it started, elapsed time, last activity, tokens so far, and where the log and the report are.

`*develop-end-to-end {App} --follow`, from any window: follow the run there as in step 3, for instance after the launching window was closed.

`*develop-end-to-end {App} --stop`: `bash .tfcore/utils/tf-develop.sh . --stop`. It ends the supervisor and every process the run started (each carries the run's mark, so a server the agent started in a session of its own goes too), keeps the database container, and records the step it stopped in.

`*develop-end-to-end {App} --resume` continues a stopped run from that step: `bash .tfcore/utils/tf-develop.sh . --resume --model <id> --detach`, then follow it as in step 3. A step already done is not run again; the git switch is kept. `--model` as in step 2; with none, the stopped run's model.

The run lives in its own processes, not in this session: closing the window leaves it running. A machine that sleeps pauses it; a restart or a WSL shutdown ends it, and `--status` then reads `stopped`: say `--resume` is the next command. A stopped run's `develop.json` does not put this or any other session into develop mode (`tf-develop.sh . --mode` says `off`).

## What the run leaves

- One commit per step (`TechieFlow develop-end-to-end: <step> done — {App}`), pushed, and a last one with the final report; none under `--no-git`.
- `docs/{App}-Build-Report.md`: built in how long, how long the agent worked, the tokens, one row per step, skipped steps shown as skipped.
- `docs/metrics/develop-report.json`: the same figures for a comparison harness, per phase and in total, by model.
- The usual run records, misses and PROJECT-STATUS, written by each phase's own commands.

A usage limit pauses the run until the limit resets, then it resumes on the same model (`tf-goal.sh --no-fallback`). A phase the agent declares blocked stops the run with the blocker in PROJECT-STATUS "Known blockers" and in the report; `--resume` continues once the owner has dealt with it.

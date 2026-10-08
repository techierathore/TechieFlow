# develop-end-to-end

`*develop-end-to-end {App} {brief}` takes a brief and develops a new app from it, unattended, to the point where the owner starts UAT: Day 1 (both stages), the build with its inline verify and fixes, and the handoff (UsageGuide, smoke checklist, test users). Greenfield only. No question, no confirmation, no review stop (`.tfcore/tasks/_develop-mode.md`). It commits and pushes after every phase and reports the time and tokens of each phase and of the whole build.

## Before it starts

The owner has made a git repository for the app with a remote (GitHub) and scaffolded TechieFlow into it. `{brief}` is a file path or the brief's text; text is written to `docs/{App}-Brief.md` as given, never shortened.

Refuse, with one line saying what is missing, when: the folder is not a git repository, it has no remote, it already has a `docs/{App}-BRD.md` or source code (this command is greenfield only: use `*build-phase`), or a develop run is already active (`.tfcore/.session/develop.json` exists: offer `--resume`).

## Steps

First: `bash .tfcore/utils/tf-phase.sh start develop-end-to-end {App}` prints the start time; keep it.

1. Write the brief to `docs/{App}-Brief.md` when it was given as text. Then record this launch, before the run starts, so its record never overlaps the phases' own (`.tfcore/tasks/_metrics-emit-gate.md`): `tf-emit.sh runs` with `"cmd":"develop-end-to-end","mode":"launch"`, the start time and no rows, then `bash .tfcore/utils/tf-phase.sh end`. The phases record themselves; the Build Report adds them up.
2. Start the supervisor detached, so it outlives this session, with the harness this session runs in:
   `bash .tfcore/utils/tf-develop.sh . --app {App} --brief docs/{App}-Brief.md --harness <claude|opencode> --detach`
   (`--model <id>` when the owner named one; `--no-push` only when the owner said not to push.)
3. Wait until `.tfcore/.session/develop.log` shows `day1 started`, then say, in three lines: the run has started; it is followed in `.tfcore/.session/develop.log`; the result will be `docs/{App}-Build-Report.md`. End the turn. This session does none of the phases itself.

`*develop-end-to-end {App} --resume` continues a stopped run: `bash .tfcore/utils/tf-develop.sh . --resume --detach`. A phase already done is not run again.

## What the run leaves

- One commit per phase (`TechieFlow develop-end-to-end: <phase> done — {App}`), pushed, and a last one with the final report.
- `docs/{App}-Build-Report.md`: built in how long, how long the agent worked, the tokens, one row per phase.
- `docs/metrics/develop-report.json`: the same figures for a comparison harness, per phase and in total, by model.
- The usual run records, misses and PROJECT-STATUS, written by each phase's own commands.

A usage limit pauses the run until the limit resets, then it resumes (`tf-goal.sh`). A phase the agent declares blocked stops the run with the blocker in PROJECT-STATUS "Known blockers" and in the report; `--resume` continues once the owner has dealt with it.

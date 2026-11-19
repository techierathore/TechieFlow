# develop-end-to-end

`*develop-end-to-end {App} [{brief}] [--no-git | --no-push] [--dry-run]` develops an app unattended to the point where the owner starts UAT: Day 1 (both stages), then every phase of `docs/{App}-Phases.md` in order (one phase when there is none), each with its build, inline verify and fixes, and its handoff (UsageGuide, smoke checklist, test users). No question, no confirmation, no review stop (`.tfcore/tasks/_develop-mode.md`). It commits and pushes after every step unless told not to, and reports the time and tokens of each step and of the whole build.

It takes a new app from a brief, or an app whose documents are already written. `tf-develop-plan.py` decides before each step: a Day-1 stage whose documents are all on disk is skipped, one with some missing writes only those, and a phase whose Phases row says `done` or `kept-whole` is skipped.

## Before it starts

TechieFlow is scaffolded into the app's folder. `{brief}` is a file path or the brief's text; text is written to `docs/{App}-Brief.md` as given, never shortened. It is needed only when `docs/{App}-BRD.md` does not exist.

Git: by default the folder is a git repository of its own with a remote (GitHub). `--no-push` commits without pushing. `--no-git` when the owner keeps git: nothing is committed or pushed, no repository is needed, and every step is still recorded.

Refuse, with one line saying what is missing, when: there is no BRD and no brief, the git setup the chosen switch needs is missing, or a develop run is already active (`.tfcore/.session/develop.json` exists: offer `--resume`). `--dry-run` prints the plan (each step run or skipped, and the git line) and runs nothing.

## Steps

First: `bash .tfcore/utils/tf-phase.sh start develop-end-to-end {App}` prints the start time; keep it.

1. Write the brief to `docs/{App}-Brief.md` when it was given as text. Then record this launch, before the run starts, so its record never overlaps the phases' own (`.tfcore/tasks/_metrics-emit-gate.md`): `tf-emit.sh runs` with `"cmd":"develop-end-to-end","mode":"launch"`, the start time and no rows, then `bash .tfcore/utils/tf-phase.sh end`. The phases record themselves; the Build Report adds them up.
2. Start the supervisor detached, so it outlives this session, with the harness this session runs in:
   `bash .tfcore/utils/tf-develop.sh . --app {App} [--brief docs/{App}-Brief.md] --harness <claude|opencode> --detach`
   (`--model <id>` when the owner named one; `--no-git` or `--no-push` when the owner gave it. `--dry-run` instead of `--detach`: print its output and end, recording nothing.)
3. Wait until `.tfcore/.session/develop.log` shows its first step `started` or `skipped`, then say, in three lines: the run has started; it is followed in `.tfcore/.session/develop.log`; the result will be `docs/{App}-Build-Report.md`. End the turn. This session does none of the phases itself.

`*develop-end-to-end {App} --resume` continues a stopped run: `bash .tfcore/utils/tf-develop.sh . --resume --detach`. A step already done is not run again; the git switch is kept.

## What the run leaves

- One commit per step (`TechieFlow develop-end-to-end: <step> done — {App}`), pushed, and a last one with the final report; none under `--no-git`.
- `docs/{App}-Build-Report.md`: built in how long, how long the agent worked, the tokens, one row per step, skipped steps shown as skipped.
- `docs/metrics/develop-report.json`: the same figures for a comparison harness, per phase and in total, by model.
- The usual run records, misses and PROJECT-STATUS, written by each phase's own commands.

A usage limit pauses the run until the limit resets, then it resumes (`tf-goal.sh`). A phase the agent declares blocked stops the run with the blocker in PROJECT-STATUS "Known blockers" and in the report; `--resume` continues once the owner has dealt with it.

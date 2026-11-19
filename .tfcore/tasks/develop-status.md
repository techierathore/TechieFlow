# develop-status

`*develop-status {App}` says, from any window, what the app's `*develop-end-to-end` run is doing. It reads only; it starts, stops and changes nothing.

## Steps

First: `bash .tfcore/utils/tf-phase.sh start develop-status {App}` prints the start time; keep it.

1. In the app's folder run `bash .tfcore/utils/tf-develop.sh . --status` and show its lines as printed, nothing added.
2. It says whether the run is alive, checked and never assumed: the process id and its host, and that the process still belongs to this run. A run whose process is gone reads `stopped`, never `running`. Then the harness and model, the step and phase, when the step started, the elapsed time, the last activity, the rows built and verified, the tokens so far, and where `.tfcore/.session/develop.log` and `docs/{App}-Build-Report.md` are.
3. When it reads `stopped`, its last line is the next command (`*develop-end-to-end {App} --resume`). Say it as the next command; do not run it. When there is no develop run in the folder, say so in one line.
4. One `runs.jsonl` record with `"cmd":"develop-status"`, the start time and no rows, written as `.tfcore/tasks/_metrics-emit-gate.md` shows; then `bash .tfcore/utils/tf-phase.sh end`. The Build Report leaves these records out, so a status read during a step never adds to that step's tokens.

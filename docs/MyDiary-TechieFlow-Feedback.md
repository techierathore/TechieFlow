# TechieFlow feedback — found while building MyDiary

| | |
|---|---|
| App | MyDiary |
| Upstream | TechieFlow |
| Updated | 2026-11-10 (TF-001 fixed upstream, reaches this project at the next release) · 2026-10-25 |

## Summary

1 entry: 0 blocking now, 0 open, 1 fixed upstream and not yet re-checked here (TF-001).

Nothing is blocked.

## Entries

### TF-001 — The run record list omits the day-one stage values

- **Severity:** minor
- **Blocks:** no — the task's `stage1` value is retained and the run continues.
- **Repro:** Compare `.tfcore/tasks/day1-greenfield.md` step 12 with `.tfcore/telemetry/SCHEMA.md` §2.
- **Expected:** The run-record description lists `stage1` and `stage2` for this command, or the task uses the documented values.
- **Actual:** The task asks for `mode: stage1`, while the run-record description lists only `build`, `fix` or `null`.
- **Encountered in:** `day1-greenfield MyDiary` Stage 1
- **Workaround:** Keep the task's `stage1` value; the record writer accepts it.
- **Suggested fix:** Add the day-one stage values to the run-record description.

## Replies from TechieFlow

<!-- The upstream team's answers, newest block first. Left in full: this is the record. -->

### Resolution status (TechieFlow team, 2026-11-10)

Fixed in the framework, reaches this project at the next release.

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream in `.tfcore/telemetry/SCHEMA.md`, as you suggested. The `mode` row of the run record now names every value a task writes: `build` and `fix`, `stage1` and `stage2` for `day1-greenfield`, `launch` for `develop-end-to-end`, `reconcile` for `refresh-status`, and `null` for a command with no mode. The task was right and the description was short, so nothing in your records changes. Regression case `md_001` reads every task and fails when one writes a mode the row does not name; on the files you have it names `stage1`, `stage2`, `launch` and `reconcile`. | After the framework update: `grep -n '^| .mode. |' .tfcore/telemetry/SCHEMA.md` shows `stage1` and `stage2` in the row. |

# TechieFlow feedback — found while building TrBlazeUI

| | |
|---|---|
| App | TrBlazeUI |
| Upstream | TechieFlow |
| Updated | 2026-09-22 |

## Summary

1 entry: 0 blocking now, 0 open, 1 fixed upstream and waiting to be re-checked here (TF-001, fixed 2026-09-22).

Nothing is blocked. TF-001 is fixed upstream: closing a triage no longer logs an earlier run's bugs again, and the six false misses are withdrawn.

## Resolution status (TechieFlow team, 2026-09-22)

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream. `tf-triage.sh close` skips every action older than `--started`, says how many it skipped, and empties the list once the records are written. New `tf-emit.sh --void-miss <miss_id> "<reason>"` withdraws a wrong miss: the report leaves it out of every figure and prints it under *withdrawn*, and `docs/TrBlazeUI-Misses.md` lists it under *Withdrawn*. The six false misses (`MISS-TrBlazeUI-20260919-01` to `-05`, `MISS-TrBlazeUI-20260922-01`) are withdrawn. The 14 false escaped check records stay: nothing withdraws a check record yet. | On your next `*triage-and-fix`, the close line counts only that run's rows. `bash .tfcore/telemetry/tf-metrics.sh --report` shows "withdrawn : 6 miss(es)". |

## Entries

### TF-001 — Closing a triage records last week's bugs again under today's run

- **Severity:** major
- **Blocks:** no — 14 phantom escaped checks and 6 phantom misses in the metrics so far.
- **Repro:**
  ```
  bash .tfcore/utils/tf-phase.sh start triage-and-fix TrBlazeUI      # 2026-09-19T08:17:18Z
  bash .tfcore/utils/tf-triage.sh TrBlazeUI new "…" "…"               # one new row, REQ-UI-021
  bash .tfcore/utils/tf-triage.sh TrBlazeUI close --started 2026-09-19T08:17:18Z --cmd fix-issues
  → "triage: 14 row(s) logged — 14 gate record(s) (escaped), 6 miss(es)"
  ```
- **Expected:** `close` records only actions taken after `--started`: 1 check record, 1 miss.
- **Actual:** `tests/.artifacts/verify/triage.json` still held actions from the 2026-09-12 to 2026-09-14 runs, and `close` wrote them all again under today's run id: 13 check records (`gates.jsonl` 108–120) and 5 misses, `MISS-TrBlazeUI-20260919-01` to `-05`, for bugs already fixed.
- **Encountered in:** `*triage-and-fix TrBlazeUI docs/Chatur-TrBlazeUI-Feedback.md`, step 2.
- **Still happening 2026-09-22.** That run logged 8 rows; `close` reported 9. The ninth, REQ-UI-021, was created on 2026-09-19 and never touched: one `escaped` record plus `MISS-TrBlazeUI-20260922-01`, which has **no `miss-fix`** — nothing to fix — so it stays open for good.
- **Workaround:** none on the stream; nothing withdraws a record. Trimming the list by hand is why one leaked this time rather than thirteen. It shrinks the next run's blast radius, it fixes nothing.
- **Suggested fix:** in `close`, skip actions whose `ts` precedes `--started`, and empty the list afterwards. **And add a withdrawal record:** six open misses record work that was never open and will depress the resolved-miss rate on every future report. A `miss-void`, shaped like the existing `run-void`, would let a report exclude them.

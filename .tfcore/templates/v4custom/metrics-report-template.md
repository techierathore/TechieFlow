# {AppName} — Development Metrics

<!-- Written by .tfcore/tasks/metrics-report.md (`*metrics`). Regenerated on demand,
     never hand-edited. Source: docs/metrics/*.jsonl (append-only) — schema at
     .tfcore/telemetry/SCHEMA.md.

     THE ONE RULE FOR THIS DOCUMENT: no combined first-pass rate, gate catch
     distribution, or escape rate across live/backfilled or across project_type.
     No "total" row, no "overall" line, no averaged intro sentence. If you are
     tempted to add one, re-read metrics-report.md §2 — the reason is not
     cosmetic. Commit-derived metrics are exempt from both separations. -->

**Snapshot as of {date}** · project_type `{app|library|docs|framework}` · schema v1

| Stream | Records | Span |
|---|---|---|
| `runs.jsonl` | {n} | {first date} → {last date} |
| `gates.jsonl` | {n} ({b} backfilled) | {first} → {last} |
| `sessions.jsonl` | {n} | {first} → {last} |
| `commits.jsonl` | {n} | {first} → {last} |

---

## 1. First-pass rate

*What fraction of REQs reach `Verified` on attempt 1.*

| Provenance | project_type | REQs scored | First-pass | Rate |
|---|---|---|---|---|
| **Live** | app | {n} | {n} | {x%} |
| **Live** | library | {n} | {n} | {x%} |
| Backfilled† | app | {n} | {n} | {x%} |

<!-- One row per (provenance × project_type). NEVER a "total" or "all projects" row. -->

† **Backfilled rows are reconstructed, not recorded.** `attempt` was inferred on
every one of them — the Requirements Status table is a mutated-in-place snapshot,
so a REQ that failed three times then passed is indistinguishable from one that
passed first try. **This column cannot support a published first-pass rate.**
Fields inferred: {list from the records' `inferred[]`}.

**Excluded from the live rate:** {n} REQ(s) that carry backfilled history — their
live `attempt` numbering restarts at 1, so counting them would import the guess.
{REQ IDs}.

---

## 2. Gate catch distribution

*Of all failures, which gate caught them.*

### Live · `{project_type}` — {n} failures

| Gate | Caught | Share |
|---|---|---|
| build | {n} | {x%} |
| acceptance | {n} | {x%} |
| render (§4a data-render) | {n} | {x%} |
| visual (§4b visual-truth) | {n} | {x%} |
| standards | {n} | {x%} |
| **escaped** — no gate caught it | {n} | {x%} |

<!-- A separate table per project_type, and a separate table for backfilled data.
     Never one table with a "combined" column: a library project cannot fail the
     visual gate, so pooling it understates that gate's real catch rate. -->

**Most common failure classes:** {failure_class} ×{n}, {failure_class} ×{n}.

---

## 3. Escape rate

*What fraction of defective REQs reached UAT/production instead of a gate.*

| Provenance | project_type | REQs with any failure | Escaped to UAT/prod | Rate |
|---|---|---|---|---|
| **Live** | {type} | {n} | {n} | {x%} |

Escapes are the `gate:"escaped"` records written by `*triage-issues` — a human
found the defect after every gate passed it. A REQ whose `prior_verdict` was
`Verified` when it escaped is the strongest signal on this page.

---

## 4. Throughput and rework — poolable

*These are comparable across `project_type` and across provenance, so they are
pooled deliberately.*

| Metric | Value |
|---|---|
| Runs total | {n} ({cmd}={n}, …) |
| Rework ratio (fix-mode ÷ build-phase runs) | {x%} |
| Batch size — median REQs per `build-phase` run | {n} |
| REQ throughput — median REQs/hour | {n} |
| Sessions / total tokens | {n} / {n} |
| Tokens per `Verified` REQ | {n} |
| Commit cadence | {n} commits/active day over {n} days |

**Cost in USD is not reported.** Claude Code transcripts carry token counts but no
per-message dollar cost, and this framework runs on a subscription where marginal
per-token cost is not the real unit. Multiplying tokens by a rate card would be an
estimate presented as a measurement, so the row says tokens and stops.

`commits.jsonl` lags reality by one commit — the `post-commit` hook fires after the
commit is sealed, so its record rides in the next one. By design: the alternative
puts git inside an automated path, and git stays manual here.

---

## 5. What is missing

<!-- Name every metric that had no data or too little. A missing number reported as
     missing is worth more than a number nobody can defend. -->

- {metric} — `insufficient data (n={n})`; needs ≥3 supporting records.
- {stream} — empty; {why: framework refresh not run here / hook unavailable / no runs yet}.

---

<!-- Privacy: this document may only contain IDs, counts, durations, verdicts and
     file paths — exactly like the streams it summarises. Never requirement text,
     never prompt text, never a commit subject, never a failure description in
     prose. Assume it could become public. -->

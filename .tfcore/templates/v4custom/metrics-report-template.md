# {AppName} — Development Metrics

<!-- Written by .tfcore/tasks/metrics-report.md (`*metrics`). Regenerated on demand,
     never hand-edited. Source: docs/metrics/*.jsonl (append-only) — schema at
     .tfcore/telemetry/SCHEMA.md.

     THE ONE RULE FOR THIS DOCUMENT: no combined first-pass rate, gate catch
     distribution, escape rate, miss rate, or cost-per-miss across live/backfilled,
     across project_type, across attribution confidence, or across cost attribution.
     No "total" row, no "overall" line, no averaged intro sentence. If you are
     tempted to add one, re-read metrics-report.md §2 — the reason is not
     cosmetic. Commit-derived metrics are exempt from the first two separations. -->

**Snapshot as of {date}** · project_type `{app|library|docs|framework}` · schema v1

| Stream | Records | Span |
|---|---|---|
| `runs.jsonl` | {n} | {first date} → {last date} |
| `gates.jsonl` | {n} ({b} backfilled) | {first} → {last} |
| `sessions.jsonl` | {n} | {first} → {last} |
| `commits.jsonl` | {n} | {first} → {last} |
| `misses.jsonl` | {n} miss + {n} miss-fix | {first} → {last} |

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

**Cost in USD is not reported here.** Claude Code transcripts and Codex usage
payloads carry token counts but no per-message dollar cost, and this framework runs
on subscriptions where marginal per-token cost is not the real unit. Multiplying
tokens by a rate card would be an estimate presented as a measurement, so the row
says tokens and stops. OpenCode runs *do* carry real provider cost — where they
exist, §5b reports them and names the harness.

`commits.jsonl` lags reality by one commit — at `pre-commit` time HEAD is still the
previous commit, so the newest record ships in the next one. Unavoidable in either
direction: a record of commit N cannot predate N. The hook reconciles against the
log rather than appending a single line, so the lag never becomes a loss, and
commits made on another machine appear after a pull + commit. If this repo's clone
has no hook installed, `tf-metrics.sh --report` says so — note it in §6 rather than
treating a thin commit count as a finding (§6). The report also de-duplicates commits on
`sha`; if it says duplicates were collapsed, that is a normal union merge, not data
corruption, and needs no comment.

---

## 5. Misses — what was missed, who missed it, what the fix cost

<!-- SCHEMA.md §5.5. Delete this whole section if misses.jsonl is empty; do not
     print a table of zeroes. Counts and the class distribution ARE poolable; the
     attribution and cost figures below are NOT — each carries its own exclusion. -->

| Metric | Value |
|---|---|
| Misses logged | {n} ({o} open, {r} resolved, {w} wont-fix) |
| Design-miss share (`unspecified-gap`) | {x%} |
| Found by a human (`owner` / `production`) | {x%} |

*Reported **beside** the escape rate in §3, never merged with it: that figure is
computed from `gates.jsonl` `gate:"escaped"` records by a different definition, and
one word cannot mean two things on one page.*

*`wont-fix` is a decision, not a backlog item, so it is not counted as open. The
collapse check still treats it as a live defect, so a repeat failure on the same
REQ will not open a duplicate record — the two predicates differ deliberately.*

**Miss classes** — *what* was missed

| Class | n | Share |
|---|---|---|
| {miss_class} | {n} | {x%} |

**Why it was missed** — *which practice failed* ({a} of {m} misses assessed)

<!-- Optional field (SCHEMA §5.5.6): the denominator is records that CARRY it, never
     all misses. A missing value means "not assessed", never a zero for a category.
     And records written BEFORE the field existed (FIELD_SINCE, 2026-08-28 for
     why_missed) leave the denominator entirely — they had no field to fill, which is
     not the same as leaving one empty. State how many were excluded on that ground;
     never backfill them with a value nobody assessed at the time. -->

| Practice | n | Share |
|---|---|---|
| {why_missed} | {n} | {x%} |

{k} miss(es) predate the field and are outside this denominator.
{u} escape(s) could have carried it and did not — complete those records with
`bash .tfcore/utils/tf-emit.sh --amend <miss_id> why_missed <value>` (SCHEMA §5.5.7);
never by editing `misses.jsonl`.

This is the table that says whether your **specification** or your **verification** is
the weak one — `missing-checklist-item` climbing means the spec has holes;
`insufficient-verify-method` climbing means the gates are too weak for the defects
that actually occur; `instruction-ignored` climbing means agents are skipping written
steps, which no gate change will fix.

### 5a. Attribution — `linked` records only

**{a} of {m} misses are attributed; {e} are excluded** because they name a phase no
`runs.jsonl` record backs, so the model that produced them is unknown.

| By | Counts |
|---|---|
| Origin phase | {phase}={n}, … |
| Origin agent | {agent}={n}, … |
| Origin model | {model}={n}, … |

**These are observational, not causal.** Which model gets the hard work is not
random, so a model at the top of this list may be doing the hardest building rather
than the worst. Read it as a question to investigate, never as a ranking to route on.

### 5b. Rework cost — measured and apportioned never combine

| | Fix records | Tokens out per miss |
|---|---|---|
| **Measured** (`sole` — the run fixed only this REQ) | {n} | {n} |
| Apportioned (`shared:n` — divided equally, **not a measurement**) | {n} | {n} |
| Unattributable (`none` — no usable token window) | {n} | — |

**Dollars.** {Either: "$X per miss — MEASURED, from {n} OpenCode records." Or:
"No measured dollars. Claude Code and Codex carry `cost_usd: null` permanently —
no cost source exists on either, and pricing tokens from a rate card here would be
an estimate presented as a measurement. Tokens are the honest figure."}

A miss fixed inline, inside a longer run with no distinct fix record, cannot be
costed at all. It counts toward the miss count and contributes nothing to the
money — which is why the "unattributable" row is printed rather than dropped.

---

## 6. What is missing

<!-- Name every metric that had no data or too little. A missing number reported as
     missing is worth more than a number nobody can defend. -->

- {metric} — `insufficient data (n={n})`; needs ≥3 supporting records.
- {stream} — empty; {why: framework refresh not run here / hook unavailable / no runs yet}.

---

<!-- Privacy: this document may only contain IDs, counts, durations, verdicts and
     file paths — exactly like the streams it summarises. Never requirement text,
     never prompt text, never a commit subject, never a failure description in
     prose. Assume it could become public. -->

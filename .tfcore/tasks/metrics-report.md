# metrics-report

## Purpose

Turn `docs/metrics/*.jsonl` into a report the owner can read and, more importantly, **defend**. Produces `docs/metrics/METRICS.md` + `docs/metrics/METRICS.html`.

This task answers four questions and nothing else:

1. **First-pass rate** — what fraction of REQs reach `Verified` on attempt 1?
2. **Gate catch distribution** — of all failures, which gate caught them?
3. **Escape rate** — what fraction of defects reached UAT/production instead of being caught by a gate?
4. **Miss attribution and rework cost** — *what* was missed, *which phase / agent / model* let it through, and *what did fixing it cost*? (SCHEMA.md §5.5)

Everything else in the report is context for those four.

Read `.tfcore/telemetry/SCHEMA.md` before you start. Read `.tfcore/tasks/_metrics-emit-gate.md` if you are unsure what may be written where.

## Inputs

- `{AppName}` (required; or resolve from `core-config.yaml`).
- Optional additional repo paths for a cross-project rollup: `*metrics {AppName} /path/to/OtherApp /path/to/Third`.

## SEQUENTIAL Execution

### 1. Compute the figures — do the arithmetic with the tool, not by eye

```bash
bash .tfcore/telemetry/tf-metrics.sh --report . --json
```

For a cross-project view, pass every repo: `bash .tfcore/telemetry/tf-metrics.sh --rollup . /path/to/OtherApp --json`.

**Use this output. Do not recompute anything by hand.** The provenance separations of §2 are enforced inside that script — it has no code path that emits a combined figure. Hand arithmetic over the raw JSONL is exactly how an indefensible number gets into a report, and it is also how "insufficient data" quietly becomes "0%".

`--report` and `--rollup` are read-only and run no git. **Never run `--backfill-commits` or `--backfill-gates`** — those are owner-only, and `--backfill-commits` invokes git, which agents never do.

`--json` carries `per_repo[].commit_hook`. When it is `false`, this clone has no commit-telemetry hook (`pre-commit` — the retired `post-commit` form also counts), so commit telemetry is not being written **on this machine** — the commit count is understated for a reason that has nothing to do with how the project is going. Say so in §5 "What is missing" and point at `update-framework.sh <repo>` (or the owner running `--backfill-commits`). **Do not act on it yourself**: installing the hook is a framework refresh, and backfilling it is git.

If the streams are empty or the script reports nothing: say so plainly, write no report, and point at re-running `update-framework.sh` on the repo (which sets telemetry up). Do not produce a page of zeroes.

### 2. THE PROVENANCE RULE — this is what the task exists to enforce

`METRICS.md` must **never** print a combined **first-pass rate**, **gate catch distribution**, or **escape rate** that crosses either provenance boundary:

- **live vs backfilled** — records reconstructed after the fact never pool with records written at the moment of the event;
- **`project_type`** — `app`, `library`, and `docs` never pool with each other;
- **attribution and cost confidence** (§5.5) — a miss whose `origin_confidence` is not `linked` never enters a per-phase / per-agent / per-model figure, and a `miss-fix` whose `cost_attribution` is not `sole` never enters a headline cost figure.

Not as a merged figure. Not as a "total" row. Not as an "overall" summary line. Not as a helpfully-labelled average in the intro paragraph. Data on the wrong side of a boundary may appear in an **adjacent, labelled column** — never summed with the figure beside it.

**Every exclusion is printed with the figure it bounds.** The JSON carries `misses.attribution_excluded` and the three `cost_*_n` counts for exactly this: an exclusion the reader cannot see is indistinguishable from a bug, and the reader is entitled to know that a per-model miss rate was computed over 7 of 19 records.

**Any table containing backfilled data carries a footnote** naming what was reconstructed and what was inferred (`inferred[]` on the records tells you exactly which fields).

**Commit-derived metrics are exempt from both separations.** `git log` is a real append-only log, and commit volume is comparable across project types.

**Why this is not cosmetic.** A merged first-pass rate cannot be defended when someone asks how attempts were counted, because backfilled attempts are inferred from a mutable status table that never recorded them. A pooled gate distribution understates the visual gate, because `library` and `docs` projects never had screens to fail on. One indefensible figure contaminates every other number in the report — the reader stops trusting the page, not just the row.

If you find yourself wanting to write "overall, across all projects, …" — **that sentence is the thing this task forbids.** Write the segmented figures and let them stand apart.

### 3. Honesty rules for every number on the page

- **Fewer than 3 supporting records → print `insufficient data (n=…)`, never a number.** A 100% first-pass rate from one REQ is noise wearing a suit.
- **Never estimate, interpolate, or infer a metric that was not measured.** A missing number is reported as missing. `cost_usd` is `null` on every Claude Code and Codex record (no cost source exists, and inventing one would be an estimate presented as a measurement) — report **tokens**, name the harness, and say why dollars are absent. **Do not multiply tokens by a rate card.** Real dollars appear only on OpenCode records and are never pooled with the others.
- **Measured cost and apportioned cost are two columns, never one number.** A fix run that repaired three misses has one token window; dividing it three ways is arithmetic. Print `cost_attribution:"sole"` figures as the headline and `shared:<n>` figures beside them, labelled as apportioned. `none` records are counted and costed at nothing.
- **Never invent a metric that has no stream behind it.** No cycle-time-per-feature: the unit of work in this framework is the run, not the ticket, and that is deliberate.
- Records with `project_type_inferred: true` are **unclassified** — give them their own row labelled as such. Do not silently fold them into `app`.
- Name the REQs excluded from the live first-pass rate because they carry backfilled history (the tool lists them). A hidden exclusion is a lie of omission.
- **Miss counts are poolable; miss *attribution* is not.** A miss counts as a miss whoever missed it, so raw counts and the class distribution may pool freely. The per-phase / per-agent / per-model rates run over `origin_confidence:"linked"` records only, and the excluded count is printed with them.
- **A per-model miss rate is observational, not causal, and the page must say so once.** Which model gets the hard work is not random, and a reader who takes the ranking at face value will make a routing decision on a confounded number.

### 4. Write `docs/metrics/METRICS.md`

Use `.tfcore/templates/v4custom/metrics-report-template.md` for the shape. Fill only what the data supports; delete sections with no data rather than printing empty tables.

**Never write metrics into `PROJECT-STATUS.md`** (`guard-status.sh` blocks any H2 outside the template's section set, correctly) **or into any `*-Checklist.md`** (`guard-verify.sh` inspects those writes; a stray metrics edit risks a false block). The report lives in `docs/metrics/` and nowhere else.

**Do not modify any `.jsonl` file.** They are append-only history. Nothing derived is ever written back into a stream.

### 5. Render `docs/metrics/METRICS.html`

Per `.tfcore/tasks/generate-html.md` using the shared shell (`.tfcore/templates/v4custom/html-render-shell.md`) — theme toggle, never hand-rolled HTML. METRICS is a human doc, so it renders; the checklists still never do.

### 6. HALT — report

```
# Metrics — {AppName}
Streams: runs {r} · gates {g} ({b} backfilled) · sessions {s} · commits {c} · misses {m}
First-pass rate: {live, per project_type — or "insufficient data"}
Gate catch: {top gate} {n}%  |  Escape rate: {x}%
Misses: {m} logged ({o} open) · design-miss share {d}% · attributed {a}/{m}
Rework cost: {tokens} tokens per miss (measured, n={s}) {| $X measured, OpenCode only}
Written: docs/metrics/METRICS.md + .html
{if backfilled records present: "Backfilled data is reported in a separate column and cannot support a published first-pass rate."}
```

Then stop. Do not run the status gate — this task reports on history, it does not advance the project, and PROJECT-STATUS is not where metrics go.

## Hard rules

- **No combined figure across live/backfilled, across `project_type`, across attribution confidence, or across cost attribution** — for first-pass rate, gate catch distribution, escape rate, miss rates, or cost per miss. This is the rule the whole task exists for.
- **The miss stream's escape share is reported BESIDE the `gates.jsonl` escape rate, never merged into it.** They are computed from different records by different definitions; presenting one number for both would make the word meaningless.
- **Never run git**, and never run `tf-metrics.sh --backfill-*` — owner-only.
- **Never write into `PROJECT-STATUS.md`, any `*-Checklist.md`, or any `.jsonl` stream.**
- **`insufficient data` is a legitimate result.** Print it without apology and without a workaround.
- **Never store or quote requirement text** pulled from a checklist to "make the report readable". REQ IDs only — the constraint that governs the streams governs the report built from them.
- Do not refactor the streams, re-sort them, or "clean up" a malformed line. Report the line number and move on.

## Output Checklist

- [ ] `tf-metrics.sh --report --json` run; figures taken from it, not recomputed by hand
- [ ] Live and backfilled reported separately; `app`/`library`/`docs` reported separately
- [ ] Miss attribution figures computed over `linked` records only, with the excluded count printed beside them
- [ ] `why_missed` distribution reported against **records that carry the field** *and* could have carried it — misses predating the field's introduction (`FIELD_SINCE`, SCHEMA §5.5.6) are outside the denominator and their count is stated; escapes lacking it are flagged, with `--amend` named as the remedy
- [ ] `miss-amend` records folded into their parents before counting; amendments applied and orphaned amends both reported
- [ ] Open-miss count excludes `wont-fix` (a decision, not a backlog item) and reports it in its own bucket
- [ ] Measured (`sole`) and apportioned (`shared:n`) rework cost in separate labelled columns — never one blended number
- [ ] Dollars quoted only where a harness measured them; no rate-card estimate anywhere on the page
- [ ] No "overall" / "total" / "combined" figure for first-pass rate, gate distribution, or escape rate
- [ ] Every table containing backfilled data carries the inferred-fields footnote
- [ ] Metrics with n < 3 printed as `insufficient data (n=…)`
- [ ] Excluded (backfill-tainted) REQs named
- [ ] `docs/metrics/METRICS.md` written + `METRICS.html` rendered via the shared shell
- [ ] No `.jsonl` file touched; PROJECT-STATUS and the checklist untouched

# TechieFlow — Development Metrics

<!-- Written by .tfcore/tasks/metrics-report.md (`*metrics`). Regenerated on demand,
     never hand-edited. Source: docs/metrics/*.jsonl (append-only) — schema at
     .tfcore/telemetry/SCHEMA.md. Every figure below comes from
     `bash .tfcore/telemetry/tf-metrics.sh --report . --json` and
     `bash .tfcore/telemetry/tf-metrics.sh --phases .`; nothing here was worked out by hand.
     The date spans in the first table are the first and last `ts` read from each file. -->

**Snapshot as of 2026-09-13** · project type: framework · schema v1

This repository is the framework itself, not an application. Its own checklist is `docs/TechieFlow-Requirements.md`, whose numbered lines (FR-nn) are graded by `tests/requirements/run.sh`. It has no screens, so the gate and escape figures stay thin for a reason that is about screens, not about requirements. What it does measure well is **the cost of keeping the framework working**: the seven-session reset of 2026-09-04 to 2026-09-07, and since then a run of fixes driven mostly by TfLens feedback.

| Stream | Records | Span |
|---|---|---|
| `runs.jsonl` | 93 counted (3 more marked wrong and left out, §6) | 2026-08-28 → 2026-09-12 |
| `gates.jsonl` | 41 (0 backfilled) | 2026-09-07 only (two grading passes over the framework's own requirement lines) |
| `sessions.jsonl` | 35 (3 repeat snapshots of one session merged, normal for OpenCode) | 2026-08-20 → 2026-09-12 |
| `commits.jsonl` | 66 (0 duplicates) | 2026-06-25 → 2026-09-12 |
| `misses.jsonl` | 172 miss + 120 miss-fix + 53 miss-amend | 2026-08-28 → 2026-09-13 |

All records are live: none were rebuilt after the fact, so there is no backfilled column anywhere on this page.

---

## 1. First-pass rate — the framework's own requirements

**93%: 27 of the 29 requirement lines scored passed on their first recorded verdict.** Live records only, project type `framework`. No line was left out for carrying rebuilt history, because none has any.

| Where the records came from | Kind of line | Lines scored | Passed first time | Rate |
|---|---|---|---|---|
| **Live** | framework requirement (FR) | 29 | 27 | 93% |

**The two failures**, both caught by the `acceptance` check on 2026-09-07:

- **FR-03**, technology neutrality.
- **FR-34**, a run record for every command.

**This figure has not moved since the last report, and that is the point to read first.** The gates stream ends on 2026-09-07. No grading pass has been recorded since, so work done after that date, including the neutrality check run on 2026-09-12, has no verdict on this page. Whether FR-03 or FR-34 now pass is not something these records can say.

**What this figure is not.** These lines were graded for the first time at the end of the reset, not as each was built. "Passed on the first recorded verdict" is true, and it is not evidence that the framework got things right first time. The better measure of that is the miss stream: **172 misses logged** (§5). Read the two together or neither.

## 2. Gate catch distribution

**insufficient data (n=2).** Both failures above were caught by `acceptance`, and two records cannot support a share. The three gates added later (`perf` since 2026-08-10, `assets` and `mockup-parity` since 2026-08-31) ran on **0** records here, because they check a running app's screens and this repository has none.

Nothing is borrowed from the miss stream to fill the gap: the two are counted from different records in different ways, and printing one as the other would make the word meaningless.

## 3. Escape rate

**insufficient data (n=2)** from `gates.jsonl`. An escape is a defect that got past every gate to a person, and with no screens to gate there is almost nothing for one to escape.

The miss stream's own "found by a human" share, **59%**, is reported in §5 **beside** this, never merged into it. For the framework it is the more telling number: the owner found more of its defects than any check did.

## 4. Throughput and rework — these may be pooled

| Figure | Value | Note |
|---|---|---|
| Runs recorded | 93 | `log-miss` 56 · `framework-reset` 31 · `fix-issues` 6 |
| Rework ratio | insufficient data (n=0 build-phase runs) | this repository has no `build-phase` runs |
| Batch size | insufficient data | same reason |
| REQ throughput | 1.67 REQ/hour | middle value across runs; here a "REQ" is a framework line (FR-nn) touched by a maintenance run |
| Sessions and tokens | 35 sessions · 14,210,531 tokens | 3 repeat snapshots merged |
| Tokens per Verified line | 364,372.6 | every session's tokens divided by the lines marked Verified; most of those tokens went on work that was not grading |
| Commit cadence | 2.28 commits per active day | 66 commits over 29 active days; the commit hook is installed on this clone, so the count is complete |

**No dollar figure is reported here.** Claude Code records carry no cost (their cost field is always empty), and turning tokens into dollars with a price list would be a guess dressed as a measurement. The only money a harness actually measured in this repository is **$0.230819, on one OpenCode `log-miss` run**, and it is never added to anything else.

## 5. Misses — what was missed, who missed it, what the fix cost

**172 misses logged: 52 open, 119 resolved, 1 will-not-fix**, with 120 fix records. Will-not-fix is a decision, not a backlog item, so it is not counted as open. 53 empty fields have been filled in by `miss-amend` records; no fix record or amend points at a miss that does not exist.

At the last report (2026-09-07) the stream held 121 misses, 33 of them open.

### Today's five misses (2026-09-13)

`MISS-TechieFlow-20260913-01` to `-05` were logged while fixing TfLens feedback TF-042, TF-043 and TF-044, all three fixed in the framework on 2026-09-13. Four are checks that reported defects that were not there, or missed ones that were: `tf-mockup-parity` twice, `tf-verify-boot` once and `tf-verify-screens` once. The fifth is a slip in the earlier TF-039 fix (that entry is closed), which let a card hide content that really was cut off; that slip is fixed too. The three TfLens fixes are not yet re-checked here: that happens by running each entry's "Verify from here" step in `docs/TfLens-TechieFlow-Feedback.md`. The records agree on four points:

- all five were **found by the owner**;
- all five are sorted **"the check was too weak"**, with the reason **`insufficient-verify-method`**;
- each names `build-phase` as its origin, but no run record backs that, so **none enters the attribution figures in §5a**;
- all five were closed the same day, by fix records with **no token window**, so their repair cost is in the "not costed" row of §5b.

### What was missed, why, and whose gap it was

| Cut | Distribution |
|---|---|
| Class (all 172) | wrong-behaviour 102 (59%) · unspecified-gap 35 (20%) · partial-implementation 17 (10%) · scope-creep 6 (3%) · spec-contradiction 4 (2%) · other 3 (2%) · missed-requirement 2 (1%) · standards-violation 2 (1%) · regression 1 (1%) |
| Why it was missed (133 of 172 assessed; 0 written before the field existed) | insufficient-verify-method 57 (43%) · missing-checklist-item 40 (30%) · instruction-ignored 30 (23%) · ambiguous-acceptance 5 (4%) · other 1 (1%) |
| Whose gap (117 of 117 sorted; 55 more were written before the field existed and are outside these shares) | weak-check 68 (58%) · unsaid 27 (23%) · ignored 22 (19%) |
| Found by | owner 101 · agent-review 52 · library-feedback 11 · gate 8 |

- **Design-miss share: 20%.** One miss in five was the specification's fault, not the build's.
- **Found by a human: 59%.** Reported beside the gate escape rate of §3, never merged into it. At the last report it was 41%.
- **37 escapes have no reason recorded for why they were missed.** At the last report there was one. Each is something that got past every check with nothing written down about why, which makes it the most useful kind of record in the stream. Fill them in one at a time with the line below (the miss's ID, then one of the reasons in the table), never by editing the file:

```
bash .tfcore/utils/tf-emit.sh --amend <miss-id> why_missed <reason>
```

**The main finding has grown stronger.** At the last report half of the sorted misses were a check that was too weak (50%). Now it is **58%**, and today's five all landed there. The framework's defects are mostly checks that exist and do not catch enough, not rules nobody wrote.

### 5a. Attribution — `linked` records only

**5 of 172 misses are attributed; 167 are left out**, because they name a phase that no run record backs, so the model that produced them is unknown.

| By | Counts (5 records) |
|---|---|
| Origin phase | log-miss 3 · fix-issues 2 |
| Origin agent | flow-master 3 · general 2 |
| Origin model | gpt-5.6-sol 3 · unknown 1 · claude-opus-5 1 |

Five records support no per-model or per-phase rate, and none is drawn. **These counts show what happened, not what caused it:** which model gets the hard work is not random, so a model near the top may be doing the hardest work rather than the worst.

### 5b. Rework cost — measured and shared costs never combine

| How the cost is known | Fix records | Tokens out per miss |
|---|---|---|
| **Measured** (`sole`: the run fixed only this miss) | 5 | 240,750.8 (all 5 carry tokens; 0 left out) |
| Shared (`shared:n`: one run's tokens split equally across the misses it fixed, **not a measurement**) | 65 | 81,246.6 (all 65 carry tokens; 0 left out) |
| Not costed (`none`: no usable token window) | 50 | — |

4 fix records stored as `none` do have a measured window; the script works out their share again from the misses each run actually closed, and they sit in the shared row.

**Dollars:** no fix record carries a measured dollar amount (0 records). Claude Code never records cost, and no price list is applied here.

A miss fixed inside a longer run, with no separate run record, cannot be costed at all. It still counts as a miss and adds nothing to the cost, which is why the "not costed" row is printed rather than dropped.

## 6. Effort per phase — time, tokens, model, fan-out

**93 live run records**, grouped by command. A phase figure describes runs of one command, never one feature or one requirement.

**3 run records are marked wrong and left out of every figure** (both they and the notes marking them stay in the stream):

- `framework-reset` started 2026-09-09T11:40:00Z: the start time was guessed; the session began at 16:31:54, so the stored time overstates it by about five hours (`MISS-TechieFlow-20260909-06`).
- `framework-reset` started 2026-09-10T10:18:17Z: the start time was typed, and it overlaps the record before it by 42 minutes (`MISS-TechieFlow-20260910-04`).
- `framework-reset` started 2026-09-10T11:38:31Z: the start time was typed, and it overlaps the record before it by nearly three hours (`MISS-TechieFlow-20260910-04`).

**Token windows:** `main` 61 · `none` 27 · `conversation` 3 · `tree` 1 · missing 1. A run whose window could not be worked out is left out of every token figure, never counted as zero.
**Time:** 45 of the 93 records carry a stored time; 48 carry none, so their time was read from the record's own start and end; 3 stored times disagreed with those timestamps, and the timestamps were used.

| Phase | Runs | Wall clock (total / middle) | Tokens out | Tokens in | Share of all output | Share of all time | Tokens measured on |
|---|---|---|---|---|---|---|---|
| `framework-reset` | 31 | 99h47m / 1h35m | 9.9M | 65.2k | 96% | 97% | 30 of 31 runs |
| `fix-issues` | 6 | 3h05m / 26m45s | 418.7k | 6.6M | 4% | 3% | 6 of 6 runs |
| `log-miss` | 56 | 25m46s / 0m55s | 35.2k | 2.9M | 0% | 0% | 29 of 56 runs |

Time was stored on all 31 `framework-reset` runs except 1, and on 8 of the 56 `log-miss` runs; the other 48 `log-miss` times come from the records' own timestamps.

`framework-reset` costing more than `log-miss` is a fact about what those phases are, not a finding about either.

### 6a. Framework maintenance, piece by piece

The `framework-reset` runs, in the order they ran, as labelled by each run's `mode`.

| Piece of work | Runs | Wall clock | Tokens out | Files written |
|---|---|---|---|---|
| Sessions 1 to 3 (before the `mode` field) | 3 | 10h56m | 1.7M | 48 |
| `sitting-4a` | 1 | 9h55m | 1.0M | 2 |
| `sitting-4b` | 3 | 24h38m | 2.6M | 104 |
| `sitting-4c` | 1 | 8h21m | 1.4M | 42 |
| `session-5` | 1 | 53m53s | 989.5k | 24 |
| `session-6` | 1 | 30m19s | **not measured** | 34 |
| `session-7` | 1 | 20m37s | 100.7k | 4 |
| `session-7-merge-fix` | 1 | 18m24s | 39.4k | 5 |
| `codex-removal` | 1 | 2m35s | 4.5k | 41 |
| `metrics` | 1 | 32m51s | 45.5k | 4 |
| `requirement-checks` | 1 | 51m12s | 169.2k | 6 |
| `owner-language` | 1 | 9h30m | 192.9k | 18 |
| `fix` | 1 | 11h26m | 184.6k | 14 |
| `routing-fallback-and-billing` | 1 | 1h35m | 178.5k | 16 |
| `routing-fallback-and-billing-corrections` | 1 | 2h15m | 80.9k | 12 |
| `routing-pricing-layer-correction` | 1 | 3h28m | 68.3k | 11 |
| `routing-deploy-19-repos` | 1 | 18m05s | 26.6k | 21 |
| `emit-refuses-overlap` | 1 | 1h40m | 47.8k | 9 |
| `deploy-and-doc-refresh` | 1 | 10m19s | 17.5k | 5 |
| `tflens-feedback-investigate` | 1 | 10m13s | 104.5k | 2 |
| `tflens-tf023-tf024-owner-text` | 1 | 2h22m | 305.3k | 28 |
| `feedback-reader-tf025-027-phase-uidesign` | 1 | 9m34s | 23.1k | 31 |
| `deploy-18-repos` | 1 | 32m45s | 46.1k | 2 |
| `tf028-bare-heading-reader` | 1 | 20m20s | 61.8k | 7 |
| `tf029-log-miss-run-record` | 1 | 7m00s | 59.6k | 7 |
| `tf030-036-tflens-build-verify` | 1 | 5h10m | 316.6k | 14 |
| `tf037-041-and-neutrality-check` | 1 | 3h07m | 134.7k | 11 |
| **All `framework-reset` runs** | **31** | **99h47m** | **9.9M over 30 measured runs** | **522** |

The `session-6` run has no token window and is left out of the token figures rather than counted as zero (`MISS-TechieFlow-20260907-09`).

**Reading the shape.** The reset sittings are still the biggest rows: `sitting-4b` alone took 24h38m and 2.6M output tokens. Since the reset closed, the work has been a long line of smaller fixes, most of them answers to TfLens feedback TF-023 to TF-041, all of which are now fixed in the framework. None of those rows passed 320k output tokens. The two longest, `fix` (11h26m) and `owner-language` (9h30m), are long in wall clock but light in tokens; the records do not say why.

### 6b. Which model did the work

| Phase | Model | Tokens out | Share of the phase | Runs |
|---|---|---|---|---|
| `framework-reset` | `claude-fable-5-1` | 7.7M | 78% | 9 |
| `framework-reset` | `claude-opus-5` | 2.2M | 22% | 21 |
| `framework-reset` | synthetic (no model recorded) | 0 | 0% | 3 |
| `fix-issues` | `claude-opus-5` | 396.3k | 95% | 4 |
| `fix-issues` | `gpt-5.6-sol` | 22.4k | 5% | 2 |
| `log-miss` | `claude-opus-5` | 26.9k | 76% | 27 |
| `log-miss` | `gpt-5.6-sol` | 7.5k | 21% | 1 |
| `log-miss` | `opencode-go/glm-5.3` | 890 | 3% | 1 |

**Harness:** `framework-reset` claude-code 31 · `fix-issues` claude-code 4, codex 2 · `log-miss` claude-code 52, codex 3, opencode 1. (Codex was retired on 2026-09-07; its older records stay valid.)
**Routing, observed and never enforced:** `log-miss` on the planned model 0 · drifted 24 · unknown 32; `framework-reset` unknown 31; `fix-issues` unknown 6.
**How the model was paid for:** `framework-reset` subscription 14 · not recorded 16; `log-miss` subscription 2 · not recorded 27; `fix-issues` not recorded 6. Records written before 2026-09-10 carry no payment field.

**This ranking shows what happened, not what caused it.** Which model gets the hard phases is not random, so a difference here is at least as much about what each model was asked to do as about the models.

### 6c. Subagent fan-out — measured, on its own count

**Not observed on any run: 0 of 93.**

| Phase | Runs observed | Why the rest are left out |
|---|---|---|
| `framework-reset` | 0 of 31 | 31: the token window did not read subagent transcripts (not `tree` scope) |
| `fix-issues` | 0 of 6 | 6: not `tree` scope |
| `log-miss` | 0 of 56 | 55: not `tree` scope · 1: written before the fan-out count existed (2026-08-31) |

A zero on a run that never looked at subagent transcripts means *not looked at*, not *none ran*. `framework-reset` runs **declared** an `explore` subagent 3 times in their own records. The measured count is the one to trust when the two disagree, but here nothing was measured, so the declared figure can be neither confirmed nor ruled out. It is kept beside the measured one and never merged with it.

## 7. What is missing

- **First-pass rate is frozen at 2026-09-07.** No grading pass has been recorded since, so nothing done in the six days after has a verdict here. A fresh run of `tests/requirements/run.sh` is what would move it. These two scripts do not report how many requirement lines have no check at all, so that count is not repeated on this page.
- **Gate catch distribution and escape rate:** insufficient data (n=2). Both describe a running app's screens, and this repository has none.
- **Rework ratio and batch size:** insufficient data (n=0 build-phase runs).
- **37 escapes have no reason recorded for why they were missed**, up from 1. These are the records most worth completing; the line to fill one in is in §5.
- **55 misses were written before the "whose gap" field existed** and sit outside those shares. The same fill-in line completes them, with `sort` in place of the reason field and one of spec, unsaid, weak-check or ignored as the value.
- **Attribution covers 5 of 172 misses.** Until more misses name a run that exists, no per-model or per-phase miss rate can be published. Today's five did not change that.
- **50 fix records have no token window**, today's five among them, so their repair cost is unknown.
- **27 of the 56 `log-miss` runs and 1 `framework-reset` run (Session 6) have no token window**, and 48 `log-miss` runs stored no time.
- **Fan-out was never observed** on any run (§6c).
- **Dollars:** the only measured money is $0.230819 on one OpenCode run. The script also prints a price worked out from a published price list; this report's rules do not allow price-list figures on the page, so it is left out.
- **3 run records are marked wrong** and left out of every figure, with the reasons in §6.

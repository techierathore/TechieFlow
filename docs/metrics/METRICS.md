# TechieFlow — Development Metrics

<!-- Written by .tfcore/tasks/metrics-report.md (`*metrics`). Regenerated on demand,
     never hand-edited. Source: docs/metrics/*.jsonl (append-only) — schema at
     .tfcore/telemetry/SCHEMA.md. Every figure below comes from
     `bash .tfcore/telemetry/tf-metrics.sh --report .`; nothing here was computed by hand. -->

**Snapshot as of 2026-09-07** · project_type `framework` · schema v1

This repository is the framework itself, not an application. It **does** have a checklist of its own — `docs/TechieFlow-Requirements.md`, 63 numbered lines each with a stated way to prove it — and since 2026-09-07 it is graded against them by `tests/requirements/run.sh` like any other project. What it has no data for is a *screen* verdict: it has no application to boot, so the gate catch distribution and escape rate below stay empty for a reason that is about screens, not about requirements. Alongside that it measures **the cost of maintaining the framework**, which in this snapshot is almost entirely the seven-session reset of 2026-09-04 to 2026-09-07.

| Stream | Records | Span |
|---|---|---|
| `runs.jsonl` | 42 | 2026-08-28 → 2026-09-07 |
| `gates.jsonl` | 41 | 2026-09-07 (two grading passes over the framework's own requirement lines) |
| `sessions.jsonl` | 29 | 2026-08-20 → 2026-09-07 |
| `commits.jsonl` | 52 | 2026-06-25 → 2026-09-07 |
| `misses.jsonl` | 121 miss + 88 miss-fix + 53 miss-amend | 2026-08-28 → 2026-09-07 |

---

## 1. First-pass rate — the framework's own requirements

**93%: 27 of the 29 lines that can be graded passed on their first recorded verdict.** Two failed, and both failures are real.

| | |
|---|---|
| Requirement lines in `docs/TechieFlow-Requirements.md` | 63 |
| Graded by a check that runs today | 29 |
| Passed | 27 |
| Failed | 2 |
| Ungraded | 34 |

**The two failures**, neither of them new, both invisible until a check existed to say so:

- **FR-03, technology neutrality.** The line says no persona or task names a language, database, UI library or host. The analyst and `build-phase` hardcode routing to the TrBlazeUI and TechieRag library agents, and `day1-brownfield` names the `dotnet` answer set. Either library routing is a legitimate exception and the line must say so, or the tasks must route by requirement prefix to whatever library agents a project has. That is the owner's call (`MISS-TechieFlow-20260907-18`).
- **FR-34, a run record for every command.** Four tasks wire none: `create-doc`, `generate-html`, `facilitate-brainstorming-session` and `create-deep-research-prompt`. This is the idea-stage gap D-13 named in Session 1 and FR-60 still carries; the check now states it in a number rather than in prose.

**Why 29 and not 63.** A line is graded only when something runnable proves it, and that artefact is run for the verdict. The other 34: **14 need a fixture run** (a real command on a real project, which no automated pass stands in for), **5 need a review** by a person, **3 are script candidates nobody built**, **1 needs a filesystem this machine cannot provide** (`FR-63`, which a Windows mount cannot grade honestly), and **11 still describe a script in prose with nothing behind it**.

On 2026-09-07 that last group was 28. Checks were built for 10 of them, five more were repointed at the self-test whose planted defect already proved them, and three at the installer test. **Coverage went from 12 lines to 29 in one pass**, and it immediately found the two failures above plus a third defect: the telemetry schema had never listed `framework-reset` or four other command values its own tasks were writing (`MISS-TechieFlow-20260907-17`).

**What this figure is not.** These lines were graded for the first time at the end of the reset, not as each was built. "Passed on the first recorded verdict" is literally true and it is not evidence that the framework got things right first time. The honest measure of that is its miss stream: **126 misses logged** (§5). Read the two together or neither.

Until 2026-09-07 this section read "no data", on the reasoning that the framework had no checklist to verify. That was wrong: it has had 63 requirement lines since Session 2, named in every session restart prompt. Logged as `MISS-TechieFlow-20260907-16`.

## 2. Gate catch distribution

**No data**, and here the original reasoning does hold: a gate distribution answers "which of the seven checks caught the failure", and those checks — build, acceptance, data, visual, assets, speed, standards — are applied to a running application's screens. This repository has none. All 12 framework verdicts passed, so there is no failure to attribute in any case.

Nothing is inferred from the miss stream to fill the gap: the two are computed from different records by different definitions, and presenting one as the other would make the word meaningless.

## 3. Escape rate

**No data** from `gates.jsonl`: an escape is a defect that got past every gate to a person, and with no screens to gate there is nothing for one to escape. The miss stream's own "found by a human" share — **41%** — is reported in §5 **beside** this, never merged into it. For the framework that share is the meaningful number, and it says the owner found two of every five framework defects.

## 4. Throughput and rework — poolable

| Figure | Value | Note |
|---|---|---|
| Runs recorded | 42 | `framework-reset` 14 · `log-miss` 22 · `fix-issues` 6 |
| Rework ratio | insufficient data | no `build-phase` runs in this repository |
| Batch size | insufficient data | same reason |
| REQ throughput | 1.83 REQ/hour | median across runs; here a "REQ" is a framework requirement line (FR-nn) touched by a maintenance run |
| Sessions and tokens | 29 sessions · 10,415,290 tokens | 3 duplicate session ids collapsed, normal for OpenCode |
| Commit cadence | 2.17 commits per active day | 52 commits over 24 active days |
| Tokens per Verified | insufficient data | nothing is verified in this repository |

## 5. Misses — what was missed, who missed it, what the fix cost

121 misses logged: **33 open, 87 resolved, 1 will-not-fix**, with 88 fix records. Will-not-fix is a decision, not a backlog item, so it is not counted as open.

| Cut | Distribution |
|---|---|
| Class | wrong-behaviour 64 (53%) · unspecified-gap 26 (21%) · partial-implementation 17 (14%) · scope-creep 6 (5%) · other 3 · spec-contradiction 3 · missed-requirement 2 |
| Why it was missed (118 of 121 assessed) | insufficient-verify-method 46 (39%) · missing-checklist-item 40 (34%) · instruction-ignored 26 (22%) · ambiguous-acceptance 5 (4%) · other 1 |
| Whose gap (66 of 66 sorted) | weak-check 33 (50%) · unsaid 18 (27%) · ignored 15 (23%) |
| Found by | agent-review 52 · owner 50 · library-feedback 11 · gate 8 |

- **Design-miss share: 21%** — one miss in five was the specification's fault, not the build's.
- **Found by a human: 41%.** Reported beside the gate-derived escape rate of §3, never merged into it.
- **55 misses predate the `sort` field** (added 2026-09-07) and are outside the "whose gap" percentages. 53 fields have been completed by `miss-amend` records.
- **One escape carries no `why_missed`.** Something got past every gate and nothing recorded why; that is the most valuable record in the stream and it is still incomplete.

The headline finding of the "whose gap" cut: **half of what the framework got wrong was a check that was too weak, not a rule nobody had written.** That is why the reset's method was to turn prose into scripts rather than to add prose.

### 5a. Attribution — `linked` records only

**5 of 121 records (116 excluded as inferred or unknown.)** An excluded record named a phase that no run record backs, so its model is unknown, and a per-model rate computed from guesses is a routing decision made on invented evidence.

- by origin phase: log-miss 3 · fix-issues 2
- by origin agent: flow-master 3 · general 2
- by origin model: gpt-5.6-sol 3 · unknown 1 · claude-opus-5 1

At n=5 this supports no per-model conclusion and none is drawn. **A per-model miss rate is observational, not causal:** which model gets the hard work is not random.

### 5b. Rework cost — measured and apportioned never combine

| Attribution | Fix records | Tokens out per miss |
|---|---|---|
| `sole` — measured | 4 | 289,563 (n=4 priced) |
| `shared` — apportioned by equal division, **not a measurement** | 63 | 81,140 (n=63) |
| unattributable — no usable token window | 20 | not costed |

Four further records stored as `none` do have a measured window; the divisor is recomputed at read time from the misses each run actually closed. **No dollar figure exists**: Claude Code carries `cost_usd: null` permanently and is never priced from a rate card. The only measured money in this repository is $0.230819 across one OpenCode `log-miss` run.

## 6. Effort per phase — time, tokens, model, fan-out

42 live run records. Token-window coverage: `main` 28 · `none` 7 · `conversation` 3 · `tree` 1 · absent 1. A window is only as good as its scope, and a run whose window could not be computed is excluded from every token figure rather than averaged in as a zero.

| Phase | Runs | Wall clock | Tokens out | Tokens in | % out | % time |
|---|---|---|---|---|---|---|
| `framework-reset` | 14 | 56h 30m | 7.9M | 60.8k | 95% | 94% |
| `fix-issues` | 6 | 3h 05m | 418.7k | 6.6M | 5% | 5% |
| `log-miss` | 22 | 29m 45s | 30.4k | 2.9M | 0% | 1% |

`framework-reset` costing more than `log-miss` is a fact about what those phases are, not a finding about either.

### 6a. The reset, session by session

The framework's own maintenance, in the order it ran. Time on six of these fourteen records was computed from the record's own two timestamps, because they predate the `duration_s` field; that is arithmetic on recorded facts, and it is flagged here rather than left to assume.

| Session | Runs | Wall clock | Tokens out | Files written |
|---|---|---|---|---|
| Sessions 1 to 3 (before the `mode` field) | 3 | 10h 56m | 1.7M | 48 |
| Sitting 4a | 1 | 9h 55m | 1.0M | 2 |
| Sitting 4b | 3 | 24h 38m | 2.6M | 104 |
| Sitting 4c | 1 | 8h 21m | 1.4M | 42 |
| Session 5 | 1 | 53m 53s | 989.5k | 24 |
| Session 6 | 1 | 30m 19s | **unmeasured** | 34 |
| Session 7 | 1 | 20m 37s | 100.7k | 4 |
| Session 7, merge fix | 1 | 18m 24s | 39.4k | 5 |
| Codex removal | 1 | 2m 35s | 4.5k | 41 |
| This metrics pass | 1 | 32m 51s | 45.5k | 4 |
| **Total** | **14** | **56h 30m** | **7.9M over 13 records** | **308** |

Session 6's own record carries no token window and is excluded from every token figure above rather than counted as zero. That gap is itself a recorded defect (`MISS-TechieFlow-20260907-09`): the emitter accepted a run record with no `ended`, so the run could never be costed. It is fixed, and the fix is what makes the other twelve rows complete.

Reading the shape: **the four Session 4 sittings account for 43 of the 56.5 hours and 5.0M of the 7.9M output tokens.** That was the work of shrinking every task file, and it cost roughly three quarters of the whole reset. The five sessions that followed — the miss protocol, the readability split, the Playbook prompt, the merge fix and the Codex removal — took two hours and five minutes between them.

### 6b. Which model did the work

| Model | Tokens out | Runs | Share |
|---|---|---|---|
| claude-fable-5-1 | 7.7M | 9 | 98% |
| claude-opus-5 | 190.1k | 4 | 2% |
| synthetic (no model recorded) | 0 | 2 | 0% |

Harness: `claude-code` on all 14 reset runs. Model routing across the whole repository was observed as on-tier 0 · drifted 10 · unknown 12 — observed, never enforced.

### 6c. Subagent fan-out — measured, on its own denominator

**Not observed on any of the 14 reset runs.** Every one carried a `main`-scope window, which never reads the subagent transcripts, so a zero here means *not looked at*, not *none ran*. Three runs declared an `explore` subagent in their own emit; the declared figure is kept beside the measured one and never merged with it.

## 7. What is missing

- **34 of the framework's 63 requirement lines are ungraded** — 14 need a fixture run, 11 still describe a script nobody built, 5 need a review, 3 are unbuilt candidates and 1 needs a filesystem this machine cannot provide. That is the largest gap on this page, and it is a gap in the framework's own verification, not in its telemetry.
- **No gate catch distribution or escape rate**, because both describe a running application's screens and this repository has none.
- **One run record has no token window** (Session 6), and one miss has no `why_missed`. Both are named above rather than filled in.
- **55 misses predate the `sort` field** and are outside the "whose gap" percentages. They can be completed one at a time with `tf-emit.sh --amend <miss_id> sort <value>`.
- **Attribution covers 5 of 121 misses.** Until more misses carry a linked run, no per-model or per-phase miss rate can be published from this repository.
- **Sessions 1 to 3 share one row** because the `mode` field arrived with Sitting 4a; their three records are individually intact in the stream.

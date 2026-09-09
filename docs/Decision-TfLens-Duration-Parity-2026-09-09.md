# Decision — TfLens must follow the reference on duration, or declare that it will not

| | |
|---|---|
| For | The owner, to read and decide. Then the prompt at the end goes to TfLens's Claude. |
| Written | 2026-09-09 |
| Upstream change | TechieFlow `tf-metrics.sh`, 2026-09-09 |
| Affects | TfLens only. No other project reads the reference figure-for-figure. |
| Urgency | Not urgent. Nothing is broken and no published TfLens figure is wrong today. |

---

## What happened, in one paragraph

A run record stores three things: when it started, when it ended, and how long it took. On streams written before the framework checked them, the third can contradict the first two — TechieBlog has a `refresh-status` run that started at 20:05:00, ended at 17:59:39, and stored 600 seconds. Reading the stored number could never catch that. So the reference now **takes the duration from the record's own two timestamps**, and where those timestamps are themselves impossible, the record carries **no duration at all** rather than a plausible one. It publishes how many it dropped.

TfLens does the opposite in one specific case: a record that already carries a duration is returned untouched. That was correct against the old reference. It is no longer.

---

## Why this needs your decision rather than just a fix

TfLens's acceptance gate requires it to match the reference **key for key, with zero tolerance**. So a change in the reference is automatically a change in what TfLens must do. There are only two honest positions and they lead to different work:

**Position A — follow the reference.** TfLens adopts the same rule. Its numbers change: fewer records counted, every one of them true. The parity gate goes green again. This is a code change plus a specification change, because the rule TfLens implements is written into its BRD.

**Position B — diverge deliberately.** TfLens keeps its rule, records the disagreement in `DECISIONS.md` the way `D-012` was recorded for the token-average dispute, and declares the divergence in `parity-compare.py` so the gate passes while showing the difference on the face of it. This is the position TfLens took once before and was right to.

**The recommendation is A.** Position B was right last time because TfLens was correct and the reference was wrong. That is not the case here: taking a duration from a stored number that its own clocks contradict cannot be defended, and TfLens has no independent reason to prefer it. B would be defending a number nobody would defend if asked how it was measured.

---

## What actually changes if you choose A

### The rule

| | Old | New |
|---|---|---|
| Record has no duration, timestamps readable | derive from timestamps | derive from timestamps — *unchanged* |
| Record has a duration, timestamps agree | keep it | keep it — *unchanged* |
| Record has a duration, timestamps **disagree** | keep the stored number | **take the timestamps** |
| Timestamps impossible (`ended` before `started`) | keep whatever is stored | **no duration at all**, and count it |
| Start and end in the same second, no duration | no duration | no duration — *unchanged* |

Only the two bold rows are new.

### The numbers, measured

These are the real figures from the reference as it now stands:

| Repository | Usable | Discarded as impossible | Taken from timestamps |
|---|---|---|---|
| TechieBlog | 33 of 46 | 13 | 4 |
| TfLens | 54 of 55 | 1 | 5 |
| TechieRag | 5 of 6 | 1 record no elapsed time | — |
| TechieFlow | 31 of 61 | 30 record no elapsed time | 3 |
| MyDiary | every record | — | — |

TechieBlog's total effort reads **72.9 hours over 33 records**, where the old rule read **79.0 hours over 45**. The old number was six hours too high, and TfLens currently reproduces the old number.

### The new keys TfLens must publish

Four, all on the `phases` block:

- `duration_measured_n` — records that produced a usable duration
- `duration_impossible_n` — records whose `ended` precedes their `started`, discarded
- `duration_absent_n` — records that carry no elapsed time at all
- `duration_recomputed_n` — records where the timestamps overrode a stored figure that disagreed

The last three are the point. A smaller total offered without its exclusions is just a different wrong number, so the count of what was dropped travels with the figure.

---

## Where the work lands in TfLens

| Thing | Where |
|---|---|
| The rule itself | `src/TfLens.Core/Metrics/RunDuration.cs` — its `Derive` currently returns a record with a duration untouched |
| The figures | `src/TfLens.Core/Metrics/PhaseMetrics.cs`, `Pooled.cs` |
| The shape it publishes | `src/TfLens.Core/Contracts/PhaseEffort.cs` |
| The gate | `tools/parity-compare.py` — `PHASES_TOP_KEYS` and the `duration_s` tuple both need the new keys |
| The specification | the BRD item that owns duration derivation (`BRD-179` / `REQ-FN-112`), which states the old rule in its own words |

---

## Two things it must not do

**It must not delete or edit any record.** The streams are append-only — `SCHEMA.md` says never rewritten, never compacted. The impossible records stay exactly where they are; they are simply not counted, and the count of them is published. Deleting them would break the one guarantee that makes any of these figures quotable, and would erase the evidence that the defect happened.

**It must not go quiet about the drop.** Reporting 72.9 hours without also reporting that 13 records were discarded replaces one misleading number with another.

---

## Which agent, and in what order

Two commands, in this order. Do not skip the first: the rule TfLens implements is written in its BRD, and changing code to disagree with its own specification is how a project ends up with two answers.

| Step | Command | Persona | Why |
|---|---|---|---|
| 1 | `*amend-docs TfLens "<the change>"` | **analyst** | The BRD states the old rule. An amendment changes it, adds the four new keys as requirements, and appends the checklist rows. |
| 2 | `*build-phase TfLens` | **flow-master** | Implements the amended rows, smoke-tests, then chains the verifier itself. |

You do not run `*split-brd` or the verifier by hand — step 1 calls the first, step 2 chains the second.

**Before either, deploy the framework**, since TfLens was skipped in the 2026-09-09 rollout while an agent was working in it:

```
bash /mnt/c/3AIGenCode/TechieFlow/update-framework.sh /mnt/c/1MyCode/TfLens
```

---

## The prompt to give TfLens's Claude

Paste everything between the lines into TfLens's Claude Code window.

---

```
The TechieFlow reference changed how a run's duration is read, on 2026-09-09. TfLens's
parity gate is zero-tolerance, so this changes what TfLens must do. Adopt the reference's
rule — this is decided, not open.

First run: bash /mnt/c/3AIGenCode/TechieFlow/update-framework.sh /mnt/c/1MyCode/TfLens
That deploys the 2026-09-09 framework, which TfLens was skipped for.

THE NEW RULE — the timestamps win.

1. A run's duration comes from its own `started` and `ended` whenever both parse.
2. If a stored `duration_s` disagrees with those timestamps by more than one second, the
   timestamps win and the record counts as recomputed. This is the case TfLens currently
   gets wrong: RunDuration.Derive returns a record that already carries a duration
   untouched, which was right against the old reference and is now wrong.
3. If `ended` precedes `started`, the record is impossible: it carries NO duration and is
   excluded from every duration figure. Do not substitute, clamp or guess one.
4. Start and end in the same second with no stored duration is not impossible — it is a
   run that records no elapsed time. Count it separately. Do not report it as corrupt.
5. Where timestamps cannot be read at all, fall back to a positive stored `duration_s`,
   as today.

FOUR NEW KEYS on the phases block, because a total without its exclusions is just a
different wrong number:
  duration_measured_n     records that produced a usable duration
  duration_impossible_n   ended before started, discarded
  duration_absent_n       no elapsed time recorded
  duration_recomputed_n   timestamps overrode a stored figure that disagreed

NEVER edit or delete a stream record. The streams are append-only (SCHEMA.md). The bad
records stay; they are excluded at read time and the exclusion is published.

DO IT IN THIS ORDER:

Step 1 — analyst, `*amend-docs TfLens "duration is derived from a record's own timestamps;
a stored duration that disagrees with them is overridden; a record whose ended precedes its
started carries no duration and is excluded; the counts of measured, impossible, absent and
recomputed records are published"`.
The BRD item that owns duration derivation (BRD-179 / REQ-FN-112) states the OLD rule in its
own words — amend it rather than leaving code and specification disagreeing. Add the four
keys as requirements and let the step append the checklist rows.

Step 2 — flow-master, `*build-phase TfLens`. Expect to touch:
  src/TfLens.Core/Metrics/RunDuration.cs      the rule
  src/TfLens.Core/Metrics/PhaseMetrics.cs     the figures
  src/TfLens.Core/Metrics/Pooled.cs           the pooled figures
  src/TfLens.Core/Contracts/PhaseEffort.cs    the published shape
  tools/parity-compare.py                     PHASES_TOP_KEYS and the duration_s tuple
                                              both need the four new keys

HOW TO KNOW IT WORKED. Run the parity gate. It must reach zero findings against
bash /mnt/c/3AIGenCode/TechieFlow/.tfcore/telemetry/tf-metrics.sh --rollup <repo> --json
for these repositories, and these are the reference's own current figures:
  TechieBlog   33 of 46 usable, 13 impossible, 4 recomputed   (total 72.9 h, was 79.0)
  TfLens       54 of 55 usable, 1 impossible, 5 recomputed
  TechieRag    5 of 6 usable, 1 records no elapsed time
  TechieFlow   31 of 61 usable, 30 record no elapsed time, 3 recomputed
  MyDiary      every record usable
Add a test pinning each of the four rules above, including rule 4 — reporting a
no-elapsed-time run as impossible is a defect, not a rounding difference.

If you conclude the reference is wrong about any of this, do NOT quietly implement
something else. Say so, name the case, and stop — that is what DECISIONS.md D-012 was for.
```

---

## If you would rather not do this now

Nothing is on fire. TfLens's published figures are not wrong in a way that misleads anyone today — they are the old reading, and the old reading was accepted until yesterday. The consequence of waiting is that TfLens's parity gate fails on duration, which blocks its own `/export` page from reading QUOTABLE. That is a self-imposed gate, and it is doing its job by refusing to certify figures that no longer agree with the reference.

The framework side is finished and deployed. This is the only outstanding piece.

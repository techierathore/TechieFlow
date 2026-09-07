# TechieFlow — Telemetry Explained

| | |
|---|---|
| Purpose | The five numbers the framework's report prints, each in plain words: what it means, how it is worked out, one real figure from all the projects together and one from a named project, and the sentence the owner says about it on stage. |
| Audience | The owner, for talks, blog posts and interviews. Anyone who asks "how do you know". |
| Status | Written 2026-09-07 in Session 5 of the reset, from the streams as they stood that day. The owner rewrites any stage sentence they would not say. Figures are re-read from the report before every use; the ones here are a snapshot. |
| Companion | `TechieFlow-How-It-Works.md` §6 (what the streams are), `.tfcore/telemetry/SCHEMA.md` (every field), `TechieFlow-Reset-Plan-2026-09-04.md` (Session 5). |

---

## 0. Where the numbers come from, and how to answer "how do you know"

Every project the framework runs in keeps five files under `docs/metrics/`. One line is added per event and no line is ever edited: one line per command run, one per requirement graded in a verify, one per miss and one more when it is fixed, one per chat session, one per commit. A script, `tf-metrics.sh`, reads the files and prints the five numbers below. It refuses to mix things that must not be mixed: figures reconstructed after the fact never pool with figures written at the time, an app never pools with a library, and a miss whose origin is guessed never enters a per-model figure. It prints `insufficient data` instead of a number when fewer than three records support it.

The figures in this page were read on 2026-09-07 from nine repositories: TfLens, TechieBlog, TechieRag, TrBlazeUI, Lekhak, AppManager, MyDiary, Xpenser and the framework itself. The OpenCode test copies (`TfLens-oc`, `TechieBlog-oc`, `MyDiary-oc`) are left out, because each carries a copy of its original's history and would count it twice. To re-read them:

```
bash .tfcore/telemetry/tf-metrics.sh --rollup <repo> <repo> …      # all together, still segmented
bash .tfcore/telemetry/tf-metrics.sh --report <repo>               # one project
```

Two facts to say before any number:

- **Tokens, not dollars.** Claude Code reports tokens and never a price, so the framework never converts. Dollars appear only on OpenCode runs, where the harness measured them. Every token figure is output tokens, counted from the harness's own transcript inside the run's time window; a run whose window could not be read is left out, never counted as zero.
- **The unit is the run, not the feature.** "A build phase costs three hours" is a fact the streams hold. "Requirement 14 took two hours" is not, and nothing here will produce it.

Three caveats that belong beside the figures they touch are marked below with ⚠.

---

## 1. First-pass rate

**What it means.** Of all the requirements the verifier has ever graded, the share that passed the first time they were verified. It measures how often the agent gets a requirement right without rework.

**How it is worked out.** Every verify writes one line per requirement with an attempt number: 1 the first time that requirement is graded, 2 the next, and so on. A requirement counts as first-pass when its attempt-1 line says `Verified`. The rate is first-pass requirements divided by requirements graded, per project type, over live records only. A requirement is identified by its project and its id together, because every project has a REQ-UI-001 (this was wrong until 2026-09-07 and printed 72%; the corrected figure is below).

| Where | Requirements graded | Passed first time | First-pass rate |
|---|---|---|---|
| All apps together | 420 | 201 | 48% |
| TfLens (the metrics dashboard, seven screens) | 178 | 36 | 20% |
| TechieBlog | 155 | 125 | 81% |
| Lekhak | 54 | 29 | 54% |
| MyDiary (first project on the reset framework) | 27 | 7 | 26% |
| TfLens's first period, when it was a documents-only project | 113 | 106 | 94%, reported apart |

⚠ TfLens is the outlier and the reason the reset happened: 178 requirements for a seven-screen app, written before the acceptance line had a fixed shape, so the verifier and the builder read the same line differently.

**On stage.** "Across my apps, about half of the requirements passed verification the first time. On TfLens it was one in five; on TechieBlog four in five. The difference was the specification, not the model: TfLens had a hundred and seventy-eight requirements for a seven-screen app, and the acceptance lines had no fixed shape."

---

## 2. Which check caught it

**What it means.** The verifier applies seven checks to every requirement, always in the same order: does it build, does its acceptance test pass, does the screen show real data, does it look right against the mockup, did the stylesheet and scripts load, is it within its speed budget, does the code follow the standards. The first check to fail is written down. Counting those first failures shows which checks do the work. A failure found by a person after every check passed is written as `escaped`.

**How it is worked out.** Every failed grading line names the check that failed. The distribution is the count per check over all failures, per project type, live records only. A check added after the stream started (speed, assets, mockup comparison) is also reported against the records that actually ran it, so its share is not understated.

| Check | All apps (293 failures) | TfLens (96) | Lekhak (28) |
|---|---|---|---|
| acceptance test | 127 (43%) ⚠ | 12 | 8 |
| escaped, a person found it | 45 (15%) | 22 | 0 |
| no check named | 44 (15%) | 44 | 0 |
| data present (render) | 31 (11%) | 0 | 5 |
| visual, against the mockup | 27 (9%) | 13 | 8 |
| build | 10 (3%) | 2 | 4 |
| mockup comparison | 5 (2%) | 3 | 0 |
| standards | 1 | 0 | 0 |

The late checks, over every repository: the speed check has run on 8 records and caught nothing; the assets check on 108 and caught nothing; the mockup comparison on 217 and caught 8.

⚠ 107 of the 127 acceptance failures come from one TechieBlog verify on 2026-09-06 that ran against an empty local database with the staff accounts behind a must-change-password screen. Those rows should have been graded "not observable, environment"; the rule now exists (FR-61) and the numbers will look different once it is applied.

**On stage.** "When a requirement fails, the acceptance test is what catches it, four times in ten. The visual check and the data check together catch one in five. The speed and assets checks have never caught anything yet, and the mockup comparison caught eight failures in two hundred runs. And one failure in seven was caught by nothing: I found it."

---

## 3. Escape rate

**What it means.** Of the requirements that failed at some point, the share whose failure got past every check and was found by a person, in testing or in production. It says how far the automation can be trusted. A second figure sits beside it, from the miss stream: of all misses, the share found by the owner or by production rather than by a check or an agent's own review. The two are computed from different records and are never merged.

**How it is worked out.** From the grading stream: requirements with an `escaped` line divided by requirements with any failed line, per project type. From the miss stream: misses whose `found_by` is owner or production divided by all misses.

| Where | Escape rate (grading stream) | Misses found by a person (miss stream) |
|---|---|---|
| All apps together | 21% | 32%, 108 of 340 misses across the nine repositories |
| TfLens | 33% | 49%, 42 of 86 |
| TechieBlog | 1% | 0 of 89 (all found by the verify) |
| TrBlazeUI (library) | 100%, 12 of 12 | 45%, 5 of 11 |
| MyDiary | 100%, 20 of 20 | 48%, 20 of 42 |
| The framework itself | no grading stream | 36%, 39 of 108 |

MyDiary's 100% is one event: the first build's screens were all blank at runtime and the owner found it, not the verifier, which had no driver for the Windows head. TrBlazeUI's 100% is the library case: its verify has no screens of its own to check, so every failure came from a consumer.

**On stage.** "One failure in five got past every automated check and was found by me. On TfLens, half of the eighty-six recorded misses were found by me, not by the framework. That number is why the verify task was rewritten."

---

## 4. Misses and rework cost

**What it means.** A miss is one thing an agent got wrong: a requirement built wrongly, half built, never specified, or a rule ignored. One defect is one miss however many times it fails. Each miss records what kind it was, which practice let it through, whose gap it was, who found it, and, when it is fixed, what the fix cost in tokens. Together they show where the process leaks and what each leak costs.

**How it is worked out.** Every miss is one record; a fix is a second record linked to it, carrying the output tokens of the run that made the fix. The cost is a measurement only when that run fixed exactly one miss (`sole`); when one run fixed several, the window is divided equally and reported apart as apportioned. A fix with no run record has no cost and is counted as such, never as free.

| | All nine repositories | TfLens | The framework itself |
|---|---|---|---|
| Misses logged | 340: 244 open, 95 fixed, 1 will not fix | 86: 37 open, 49 fixed | 108: 73 open, 34 fixed |
| Which practice failed (of those assessed) | the check was too weak 48% · the checklist had a hole 27% · an instruction was ignored 15% · the acceptance line was ambiguous 8% | 41 · 19 · 5 · 13 | 37 · 37 · 25 · 5 |
| What kind | wrong behaviour 30% · regression 26% ⚠ · half built 20% · never specified 14% | half built 29, wrong behaviour 24, never specified 19 | wrong behaviour 53, never specified 26 |
| Who found it | a check 133 · the owner 108 · an agent's review 81 · a library consumer 17 | owner 42, agent review 26, check 17 | agent review 51, owner 39, library 11 |
| Fix cost, measured (one miss per run) | 108,671 output tokens per miss, 8 fixes | 171,804, 4 fixes | too few to say, 2 fixes |
| Fix cost, apportioned (several per run) | 34,417 per miss, 115 fixes | 39,877, 66 fixes | 17,745, 18 fixes |
| Fixes with no cost recorded | 21 | 5 | 15 |

⚠ 87 of the 90 regressions are the TechieBlog empty-database verify of §2; they are one environment problem logged 87 times, and FR-61 is the answer.

**Per model, per agent.** Only misses whose origin run is on record enter this: 139 of 340. By model: claude-opus-5 65, claude-sonnet-5 40 (all from one MyDiary build), unknown 31, gpt-5.6-sol 3. By agent: the TrBlazeUI builder 67, general-purpose builders 39, flow-master 31. This is observational. The hard work went to the expensive model on purpose, so a per-model miss rate is not a ranking.

**Whose gap (from 2026-09-07).** Every new miss now answers four questions in order: did the app's spec say it, did the framework say it, was there a check that failed to catch it, was it written and ignored. The answer decides the fix: a checklist line, a requirement line plus a check, a fixed check, or a hook. The first fifty-one misses sorted this way are Session 4's own: the reset's own defects (`docs/TechieFlow-Misses.md`).

**On stage.** "Half of my recorded misses happened because the check was too weak, a quarter because the specification had a hole, and one in seven because the agent ignored an instruction it had just read. Fixing one miss on its own cost about a hundred thousand output tokens. When a fix run repaired several at once, about thirty-five thousand each."

---

## 5. Effort per phase

**What it means.** For each command: how many times it ran, how long it took, how many output tokens it used, on which model, and how much of that went to sub-agents. It shows what each stage of the life cycle costs, and lets a cheap model be compared with an expensive one on the same kind of work.

**How it is worked out.** Every command writes one run record with its start and end; the emitter reads the harness's own transcript between those two times and counts the tokens, per model, main thread and sub-agents apart. Medians are over the runs that had a readable window. Fan-out is counted only on runs whose window included the sub-agent transcripts.

| Command | Runs | Median time | Median output tokens | Share of all recorded time | Share of all output |
|---|---|---|---|---|---|
| build-phase | 23 | 2 h 51 min | 457,000 (10 of 23 measured) | 44% | 22% |
| verify-phase | 29 | 30 min | 98,000 (18 of 29) | 25% | 8% |
| fix-issues | 43 | 35 min | 130,000 (30 of 43) | 15% | 19% |
| amend-docs | 9 | 20 min | 91,000 (8 of 9) | 3% | 9% |
| triage-issues | 7 | 23 min | 127,000 (5 of 7) | 1% | 2% |
| mockups | 3 | 25 min | 99,000 | 1% | 1% |
| log-miss | 21 | 2 min 27 s | 7,900 (14 of 21) | under 1% | under 1% |
| framework-reset (this reset, 8 sittings) | 8 | 5 h 53 min | 764,000 (8 of 8) | 7% | 27% |

Over the nine repositories: 163 runs, 219 hours of recorded time, 25.1 million output tokens. The build phase spent 38% of its output in sub-agents where that was observed. The reset of the framework, 6.7 million output tokens, cost more output than every build phase together, 5.5 million.

Named projects: TfLens's eight build runs took a median of 2 h 16 min and 457,000 output tokens each, half of everything TfLens ever spent. TechieBlog's twenty-two fix runs took a median of 37 min and 165,000 tokens each, two thirds of its recorded output. Dollars exist only where OpenCode ran: MyDiary's day-1 on mimo-v2.5 cost $0.06, a deploy checklist $0.05, one log-miss on glm-5.3 $0.23.

**On stage.** "A build phase is a three-hour, half-million-token run. A verify is half an hour and a hundred thousand tokens. Logging a miss takes two minutes. And rewriting the framework itself, eight sittings, cost more output tokens than all my build phases put together."

---

## 6. What is not in the numbers yet

- **Owner reviews.** Since 2026-09-06 a review of a phase's output is a record: how many corrections the owner gave, what producing the output cost, what the corrections cost. Two exist (MyDiary day-1). The report prints them; the figure is not yet worth a sentence.
- **Idea-stage commands** (brainstorm, project brief) write no run record yet, so their cost is unknown.
- **Runs whose window could not be read** (13 of 23 builds) are outside every token figure. The per-run medians are of the measured ones, and the table says how many that is.
- **Dollars for Claude Code** will never appear; that is a decision, not a gap.

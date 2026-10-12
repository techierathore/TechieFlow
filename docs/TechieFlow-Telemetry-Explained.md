# TechieFlow — Telemetry Explained

| | |
|---|---|
| Purpose | The five numbers the framework's report prints, each in plain words: what it means, how it is worked out, one real figure from all the projects together and one from a named project, and the sentence the owner says about it on stage. |
| Audience | The owner, for talks, blog posts and interviews. Anyone who asks "how do you know". |
| Status | Written 2026-09-07 in Session 5 of the reset, from the streams as they stood that day. Refreshed 2026-10-12 for the 17 Oct livestream. Figures re-read from `tf-metrics.sh --rollup` over the public repositories only. The owner rewrites any stage sentence they would not say. |
| Companion | `TechieFlow-How-It-Works.md` §6 (what the streams are), `.tfcore/telemetry/SCHEMA.md` (every field), `TechieFlow-Reset-Plan-2026-09-04.md` (Session 5). |

---

## 0. Where the numbers come from, and how to answer "how do you know"

Every project the framework runs in keeps five files under `docs/metrics/`. One line is added per event and no line is ever edited: one line per command run, one per requirement graded in a verify, one per miss and one more when it is fixed, one per chat session, one per commit. A script, `tf-metrics.sh`, reads the files and prints the five numbers below. It refuses to mix things that must not be mixed: figures reconstructed after the fact never pool with figures written at the time, an app never pools with a library, and a miss whose origin is guessed never enters a per-model figure. It prints `insufficient data` instead of a number when fewer than three records support it.

The figures in this page were read on 2026-10-12 from seven public repositories: Chatur, TechieRag, TrBlazeUI, TechieFlow, TfLens, TechieBlog and Xpenser. Xpenser has no telemetry yet. Private projects and the OpenCode test copies are left out. To re-read them:

```
bash .tfcore/telemetry/tf-metrics.sh --rollup <repo> <repo> …      # all together, still segmented
bash .tfcore/telemetry/tf-metrics.sh --report <repo>               # one project
```

Two facts to say before any number:

- **Tokens are what is recorded; money is worked out when the report runs.** Claude Code reports tokens and never a price, and no record here ever stores a price. A dollar figure on a record is one the provider itself reported, and only OpenCode has those. Since 2026-09-10 the report also prints a **list price** from the tokens and a rate card — labelled a price, never a bill (§5a). Every token figure is output tokens, counted from the harness's own transcript inside the run's time window; a run whose window could not be read is left out, never counted as zero.
- **The unit is the run, not the feature.** "A build phase costs three hours" is a fact the streams hold. "Requirement 14 took two hours" is not, and nothing here will produce it.

Three caveats that belong beside the figures they touch are marked below with ⚠.

---

## 1. First-pass rate

**What it means.** Of all the requirements the verifier has ever graded, the share that passed the first time they were verified. It measures how often the agent gets a requirement right without rework.

**How it is worked out.** Every verify writes one line per requirement with an attempt number: 1 the first time that requirement is graded, 2 the next, and so on. A requirement counts as first-pass when its attempt-1 line says `Verified`. The rate is first-pass requirements divided by requirements graded, per project type, over live records only. A requirement is identified by its project and its id together, because every project has a REQ-UI-001 (this was wrong until 2026-09-07 and printed 72%; the corrected figure is below).

| Where | Requirements graded | Passed first time | First-pass rate |
|---|---|---|---|
| All apps together | 529 | 220 | 42% |
| Chatur | 164 | 30 | 18% |
| TfLens (the metrics dashboard, seven screens) | 208 | 65 | 31% |
| TechieBlog | 155 | 125 | 81% |
| TechieRag (library) | 111 | 100 | 90% |
| TrBlazeUI (library) | 59 | 10 | 17% |
| TfLens's first period, when it was a documents-only project | 113 | 106 | 94%, reported apart |

⚠ TfLens is still the outlier: two hundred and eight requirements for a seven-screen app, written before the acceptance line had a fixed shape, so the verifier and the builder read the same line differently.

**On stage.** "Across my public apps, about four in ten requirements pass verification the first time. Chatur is one in five, TfLens three in ten, and TechieBlog four in five, because the gap is in the specification, not the model."

---

## 2. Which check caught it

**What it means.** The verifier applies seven checks to every requirement, always in the same order: does it build, does its acceptance test pass, does the screen show real data, does it look right against the mockup, did the stylesheet and scripts load, is it within its speed budget, does the code follow the standards. The first check to fail is written down. Counting those first failures shows which checks do the work. A failure found by a person after every check passed is written as `escaped`.

**How it is worked out.** Every failed grading line names the check that failed. The distribution is the count per check over all failures, per project type, live records only. A check added after the stream started (speed, assets, mockup comparison) is also reported against the records that actually ran it, so its share is not understated.

| Check | All apps (1,171 failures) | Chatur (834) | TfLens (208) | TechieBlog (127) |
|---|---|---|---|---|
| mockup comparison | 697 (60%) | 622 | 73 | 2 |
| data present (render) | 242 (21%) | 210 | 25 | 7 |
| acceptance test | 128 (11%) | 2 | 19 | 107 |
| escaped, a person found it | 35 (3%) | 0 | 32 | 1 |
| no check named | 44 (4%) | 0 | 44 | 0 |
| visual, against the mockup | 18 (2%) | 0 | 13 | 5 |
| build | 6 | 0 | 2 | 4 |
| standards | 1 | 0 | 0 | 1 |

The late checks, over every repository: the speed check has run on 4 records and caught nothing; the assets check on 1,345 and caught nothing; the mockup comparison on 1,483 and caught 697.

⚠ Chatur's mockup comparison numbers are high because its phase 1 mockups were not yet annotated for sample rows and state-only content; the comparison reported them as missing until the annotations went in.

**On stage.** "The mockup comparison catches six in ten of these failures, and the render check catches another two in ten. The acceptance test catches one in ten, and one in ten is found by me after every check passed."

---

## 3. Escape rate

**What it means.** Of the requirements that failed at some point, the share whose failure got past every check and was found by a person, in testing or in production. It says how far the automation can be trusted. A second figure sits beside it, from the miss stream: of all misses, the share found by the owner or by production rather than by a check or an agent's own review. The two are computed from different records and are never merged.

**How it is worked out.** From the grading stream: requirements with an `escaped` line divided by requirements with any failed line, per project type. From the miss stream: misses whose `found_by` is owner or production divided by all misses.

| Where | Escape rate (grading stream) | Misses found by a person (miss stream) |
|---|---|---|
| All apps together | 10% | 42%, 369 of 883 misses across the seven public repositories |
| Chatur | 0% | 4%, 10 of 266 |
| TfLens | 37% | 45%, 67 of 150 |
| TechieBlog | 1% | 0 of 89 (all found by the verify) |
| TrBlazeUI (library) | 98%, 48 of 49 | 90%, 64 of 71 |
| TechieRag (library) | 100%, 19 of 19 | 78%, 28 of 36 |
| The framework itself | no grading stream | 74%, 200 of 271 |

TrBlazeUI's and TechieRag's high escape rates are the library case: their verify has no screens of its own to check, so most failures came from a consumer.

**On stage.** "One failure in ten got past every automated check and was found by me. On TfLens it's more than one in three, which is why the verify task keeps getting rewritten."

---

## 4. Misses and rework cost

**What it means.** A miss is one thing an agent got wrong: a requirement built wrongly, half built, never specified, or a rule ignored. One defect is one miss however many times it fails. Each miss records what kind it was, which practice let it through, whose gap it was, who found it, and, when it is fixed, what the fix cost in tokens. Together they show where the process leaks and what each leak costs.

**How it is worked out.** Every miss is one record; a fix is a second record linked to it, carrying the output tokens of the run that made the fix. The cost is a measurement only when that run fixed exactly one miss (`sole`); when one run fixed several, the window is divided equally and reported apart as apportioned. A fix with no run record has no cost and is counted as such, never as free.

| | All public repositories | TfLens | The framework itself |
|---|---|---|---|
| Misses logged | 883: 219 open, 576 resolved, 88 will not fix | 150: 79 open, 71 resolved | 271: 56 open, 214 resolved, 1 will not fix |
| Which practice failed (of those assessed) | the check was too weak 48% · the checklist had a hole 31% · an instruction was ignored 11% · the acceptance line was ambiguous 5% · other 5% | 48 · 23 · 8 · 14 · 8 | 79 · 41 · 30 · 5 · 1 |
| What kind | wrong behaviour 29% · half built 29% · regression 21% · never specified 15% · other 6% | half built 55, wrong behaviour 27, never specified 27 | wrong behaviour 200, never specified 36, half built 17 |
| Who found it | a check 379 · the owner 340 · an agent's review 118 · production 23 · a library consumer 17 · self-smoke 6 | owner 65 · a check 54 · agent review 29 · production 1 · self-smoke 1 | owner 186 · agent review 52 · production 14 · library 11 · a check 8 |
| Fix cost, measured (one miss per run) | 140,913 output tokens per miss, 22 fixes | 142,976, 5 fixes | 217,144, 6 fixes |
| Fix cost, apportioned (several per run) | 60,023 per miss, 234 fixes | 38,370, 86 fixes | 79,728, 68 fixes |
| Fixes with no cost recorded | 465 | 28 | 141 |

⚠ 87 of TechieBlog's 89 misses are regressions from one empty-database verify in 2026-09; they are one environment problem logged many times, and the "not observable, environment" rule now exists for cases like it.

**Per model, per agent.** Only misses whose origin run is on record enter this: 418 of 883. By model: claude-opus-5 347, claude-opus-5-5 31, claude-sonnet-5-5 18, unknown 14, claude-fable-5-1 4, gpt-5.6-sol 3, opencode-go/glm-5.3 1. By agent: flow-master 191, general-purpose builders 75, trblazeui 92, builder 18, analyst 7, none 35. This is observational. The hard work went to the expensive model on purpose, so a per-model miss rate is not a ranking.

**Whose gap (from 2026-09-07).** Every new miss now answers four questions in order: did the app's spec say it, did the framework say it, was there a check that failed to catch it, was it written and ignored. The answer decides the fix: a checklist line, a requirement line plus a check, a fixed check, or a hook. The first fifty-one misses sorted this way are Session 4's own: the reset's own defects (`docs/TechieFlow-Misses.md`).

**On stage.** "Just under half my recorded misses happened because the check was too weak, and just under a third because the specification had a hole. Fixing one miss on its own costs about a hundred and forty thousand output tokens; when a fix run repairs several at once, about sixty thousand each."

---

## 5. Effort per phase

**What it means.** For each command: how many times it ran, how long it took, how many output tokens it used, on which model, and how much of that went to sub-agents. It shows what each stage of the life cycle costs, and lets a cheap model be compared with an expensive one on the same kind of work.

**How it is worked out.** Every command writes one run record with its start and end; the emitter reads the harness's own transcript between those two times and counts the tokens, per model, main thread and sub-agents apart. Medians are over the runs that had a readable window. Fan-out is counted only on runs whose window included the sub-agent transcripts.

| Command | Runs | Median time | Median output tokens | Share of all recorded time | Share of all output |
|---|---|---|---|---|---|
| build-phase | 59 | 50 min | 154,590 (51 of 59 measured) | 29% | 26% |
| verify-phase | 109 | 19 min 49 s | 18,835 (99 of 109) | 18% | 9% |
| fix-issues | 84 | 21 min 32 s | 70,607 (67 of 84) | 8% | 15% |
| amend-docs | 40 | 7 min 37 s | 46,162 (39 of 40) | 2% | 7% |
| triage-issues | 8 | 14 min 48 s | 118,213 (6 of 8) | under 1% | 1% |
| mockups | 3 | 24 min 43 s | 99,144 | 1% | under 1% |
| log-miss | 150 | 1 min 3 s | 771 (69 of 150) | under 1% | 1% |
| framework-reset (this reset, 85 sittings) | 85 | 20 min 37 s | 43,299 (84 of 85) | 31% | 21% |

Over the seven public repositories: 624 runs, 472 hours of recorded time, 60.1 million output tokens. The build phase spent 67% of its output in sub-agents where that was observed. The reset of the framework, 12.7 million output tokens, cost less output than every build phase together, 15.5 million.

Named projects: TfLens's fourteen build runs took a median of 1 h 56 min and 378,000 output tokens each, 38% of everything TfLens ever spent. TechieBlog's twenty-two fix runs took a median of 37 min and 165,000 tokens each, two thirds of its recorded output. Dollars exist only where OpenCode ran: one log-miss on glm-5.3 cost $0.23.

**On stage.** "A build run is about fifty minutes and a hundred and fifty thousand tokens. A verify is twenty minutes and twenty thousand tokens, and logging a miss takes one minute."

---

## 5a. What a cost number means (added 2026-09-10)

**What it means.** Every run is measured in tokens, and tokens are what the whole report is built on. But tokens are hard to talk about, so the report now also puts a price on them — and keeps that price strictly apart from what was actually billed, because those are two different facts:

| The number | What it answers | Where it comes from |
|---|---|---|
| **List price** | "What would these tokens cost at the published rate?" | Worked out **when the report runs**, from the tokens already on the record. Every run has one, on both harnesses. A **price, not a bill**. |
| **Plan allowance used** | "How much of this month's allowance has this model eaten?" | OpenCode Go is $10 a month with a separate allowance per model. Its dollars are a meter, and they are what runs out and sends a phase to its fallback model. |
| **Money billed** | "What was I actually charged?" | Only a provider that bills per token. A flat monthly plan charges nothing extra, so there is nothing to record. |

The framework itself stores none of these. It stores what it measured — tokens, per model, per run, on both harnesses — and the report turns them into money. That is deliberate: a rate card changes, and when it does, every run ever recorded is re-priced and no record was ever wrong. It also means the numbers below could be produced by TfLens from the same files, without asking the framework for permission.

What changed on 2026-09-10 is that a run now says **how it was paid for**, so the report can tell a flat fee, a monthly allowance and a real invoice apart instead of adding them up. Before that, a subscription run recorded a zero that read exactly like a free one.

Two things the price deliberately does not do: it uses the base rate, so a long-context surcharge is not added; and a model it has no rate for is left out rather than counted as free.

**On stage.** "Every run is priced at the published rate, so I can say what a build phase is worth in money as well as tokens — and separately, what I was actually billed, which on a subscription is nothing. The report never adds those together, and none of it is baked into the files: change the price list and the whole history re-prices."

---

## 5b. When a record turns out to be wrong

The five files are append-only: nothing is ever edited and nothing is ever deleted. That is what makes the numbers worth quoting — no one can go back and tidy a figure they did not like. It leaves one real problem, and on 2026-09-09 it happened here: a run record was written with a **guessed** start time, so it claimed five hours for a session that took nineteen minutes. Its own start and end agreed with each other, so no check could catch it, and it could not be corrected.

**The answer is another record, never an edit.** `run-void` names the bad run and says why it is wrong. Both records stay exactly where they are, and every figure then skips the one that was named — and says so:

```
20 run record(s) VOIDED — named by a run-void record as wrong, so they are
in no figure above. Both records stay on the stream; nothing was deleted:
  TechieRag build-phase 2026-09-25T04:25:00Z — the start time was guessed, not measured
  TrBlazeUI verify-phase 2026-09-12T08:54:30Z — mislabelled: this window is a *fix-issues run whose step 4 chains the verifier inline
  …
```

Three things make this a correction rather than a cover-up. The reason travels with it, so anyone can check whether the record deserved to go. The count travels with the figures, because a smaller total offered without its exclusions is just a different wrong number. And there is no way to *replace* the bad figure with a better one — a duration nobody measured cannot be recovered by asserting one, so the run simply leaves.

**On stage.** "The files can never be edited, so a wrong record can't be quietly fixed. It gets a second record saying it's wrong and why, and every report tells you how many were excluded."

---

## 5c. What Verified does not mean

`Verified` means every check the framework knows how to run passed on that requirement. It does not mean there was a check for everything that matters. On Chatur's 11 Oct nightly, six rows were marked `Verified` even though their acceptance tests were skipped; the screens rendered and looked right, but the behaviour was not measured. I found that by reading the checklist, not because any check failed.

**On stage.** "Verified does not mean perfect. It means the checks that ran and passed — and some of those checks can still be placeholders."

---

## 6. What is not in the numbers yet

- **Owner reviews.** Since 2026-09-06 a review of a phase's output is a record: how many corrections the owner gave, what producing the output cost, what the corrections cost. The report prints them; the figure is not yet worth a sentence.
- **Idea-stage commands** (brainstorm, project brief) write no run record yet, so their cost is unknown.
- **Runs whose window could not be read** (142 of 624 in this rollup) are outside every token figure. The per-run medians are of the measured ones, and the table says how many that is.
- **Dollars actually billed for Claude Code** will never appear; that is a decision, not a gap. Since 2026-09-10 the report does put a **list price** on its runs — the rate card applied to the tokens they measured — which is a different question and is labelled as one (§5a).

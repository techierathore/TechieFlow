# AI-First Playbook — Review Session Prompt (version 3)

| | |
|---|---|
| Purpose | The text the owner pastes into a fresh Claude Code window to review the AI-First Playbook, the team edition, and produce a plan for fixing it. |
| Audience | The owner, and the review session that reads it. |
| Status | **Version 3, written 2026-09-07 after the TechieFlow reset closed and its own metrics were built.** Version 2 was written earlier the same day, before the framework was graded against its own checklist; that grading changed what this prompt asks for. Versions 1 and 2 are in git history. Ready to run. |
| Companion | `TechieFlow-Reset-Plan-2026-09-04.md`, `TechieFlow-Requirements.md`, `TechieFlow-Document-Schemas.md`, `docs/CHANGELOG.md`, `docs/metrics/METRICS.md` |

---

## 1. What version 3 adds

Version 2 already carried the reset's methods. Then the framework was measured against its own requirements for the first time, and that produced the finding this version is built around.

**TechieFlow had 63 requirement lines and had never graded one.** They were written in Session 2, named in every session restart prompt, and each carried a stated check. Nothing ran them. The framework's own metrics reported "no first-pass rate" on the reasoning that it had no checklist to verify — while the checklist sat in `docs/`. When a grader was finally built it took an afternoon and immediately found three real defects, including two that had been live for days.

Worse than the not-running was **what the grading revealed about the checks themselves**: of 63 lines, 42 said "script", and **28 of those described a script in prose that nobody had ever written**. A requirement that names a check it does not have reads exactly like a requirement that is enforced. That is the single most expensive habit the reset found, and it is the thing this review must look for in the Playbook first.

So version 3 changes the ask. Version 2 said "write a requirements list for the Playbook, about 30 lines, each with a way to check it". That is not enough, and it is how TechieFlow got 28 phantom checks. Version 3 says: **write fewer lines, build the grader in the same session, and report the ungraded count as the headline.** A checklist nobody can run is documentation pretending to be enforcement.

Everything version 2 measured about the Playbook still stands and is repeated in Step 1 for confirmation.

**How the work is split, unchanged.** The Playbook is edited in Claude Code, because that is where the owner works fastest. It is proven only in OpenCode, because that is the harness its users have. A change that works in Claude Code and fails in OpenCode is not done.

---

## 2. The prompt (paste from here)

Run this in Claude Code with the working directory set to `/mnt/c/3AIGenCode/AI-First-Playbook`. The output is two documents and a short report. No other file is touched.

```
You are reviewing the AI-First Playbook, a team-edition, spec-driven development process for AI
coding agents. It is published on npm as @techierathore/ai-first-playbook and is used through
OpenCode. Corporate teams are the audience; they avoid single-vendor tools, so OpenCode is the
primary harness and must stay so. Claude Code is secondary here.

The Playbook and its solo sibling TechieFlow were both borrowed from BMAD and then corrected
incident by incident over six months. TechieFlow has just been through a seven-session reset and
has been graded against its own requirements for the first time. What that cost is written into the
method below. Do not assume the two frameworks have the same faults: measure this one.

RULES FOR THIS SESSION
- Plain English in everything you write. Short sentences. Any term of art gets a one-clause
  explanation the first time. The owner is a .NET expert, not a YAML or harness expert, and will
  reject text they cannot repeat to a colleague.
- Analysis and plan only. Do not edit any file except the two you are asked to create. Never run
  git in any form.
- Every claim has a number or a file path behind it. Measure, do not estimate. If a number
  contradicts something stated in this prompt, the number wins and you say so.
- Keep OpenCode first-class in every proposal. Never propose removing OpenCode support, the
  operating contract, or the npm packaging.
- NEVER propose a check you are not also prepared to build. If a line needs a check that cannot be
  written this session, say "review" and mean it. A requirement that names a script nobody wrote is
  worse than one that admits it rests on a person: it reads as enforced and is not. TechieFlow
  carried 28 of those.

STEP 1 — MEASURE THE SURFACE
Two counting rules, both paid for. Break either and every number below is wrong.

- Count RECURSIVELY, and print the file count beside every word count. A folder measured only at
  its top level reports zero for a folder whose content sits one level down, and a zero that should
  be a number reads as "nothing here" instead of "I did not look". That mistake was made while
  preparing this prompt and hid 174 files and 196,498 words.
- Count HIDDEN paths. Use `find`, not a shell glob, and not a search tool that honours .gitignore.
  A harness lives in a dot-directory: `.opencode/`. When Step 1 was run through OpenCode on
  2026-09-07 it reported verification/ as 120 files and 82,168 words against the true 174 and
  196,498, because `**/*.md` skips dot-directories. It under-reported by 58 percent and looked
  entirely plausible.

Confirm or refute this snapshot, taken 2026-09-07. Print your own figures beside it.

  phases/          10 files     3,572 words
  templates/       29 files     5,991 words   (16 of them command definitions)
  docs/            31 files    57,105 words
  onboarding/       2 files     1,538 words
  harness/         20 files    40,350 words   <- what actually ships and is read at run time
  verification/   174 files   196,498 words   <- committed run evidence, not shipped
  root              4 files     3,187 words
  whole repository 274 files   317,385 words
  shipped agents: verifier 8,630 · builder 352 · orchestrator 125 · analyst 37
  shipped commands: 15 files, 29,800 words; largest add-doc 4,855, implement 4,030
  shouted rules (MUST/NEVER/ALWAYS/BANNED/FORBIDDEN/REQUIRED/MANDATORY): 61, of which 46 in harness/
  scripts under scripts/: 15          docs/metrics/: absent

1. Word count of every markdown file, grouped by folder, sorted by size, with file counts.
2. For each of the ten phases, what an OpenCode agent actually loads when that phase runs. Trace it
   from opencode.json, AGENTS.md and the harness folder: which files, in what order, total words.
   That total is the instruction surface for the phase, not the phase document's own size. Say
   plainly which phase reads the most before its first useful step.
3. Count prose rules and script-enforced rules side by side, and say where each cluster sits.
4. List every document in docs/ with its audience and whether anything in the repo points at it.
   Flag every document nothing points at, and separately any that belongs to the other framework.
5. Report every file that exists more than once with the same name and near-identical content.

STEP 2 — THE EXISTING CHECKS: WHICH ARE REAL
For every rule the Playbook states as enforced — in AGENTS.md, the phase files, the scripts, the
release workflow — answer one question: is there an artefact that fails when the rule is broken,
and can you run it right now? Print a table:

  | The rule | Where it is stated | The check it claims | Runs today? | Proof |

"Runs today" is yes only if you ran it in this session and saw it pass or fail. Anything else is no.
Count the yes and the no. That ratio is the Playbook's real enforcement, and it is the number the
owner should see first — TechieFlow's equivalent was 12 of 63 before this work and 29 of 63 after.

STEP 3 — THE MISS AND TELEMETRY DATA
1. If a misses stream or docs/metrics exists, summarise misses by cause, by phase, and by who found
   them. If none exists, say so plainly: a framework that cannot show what it got wrong cannot show
   it improved, and that is the single finding most worth fixing first.
2. Read Ai-First-Playbook-Gap.md and docs/Decisions.md. List the rules added in reaction to an
   incident, and mark each prose or enforced.

STEP 4 — EVERY PROSE FILE, ONE TABLE
Start with what the agent reads, not what the reader reads: harness/opencode/agent/verifier.md
(8,630 words) and the four largest command files, then the rest of harness/, then phases/ and
templates/. Shrinking the verifier shrinks every verify run, and the equivalent file was the single
worst source of misses in TechieFlow. For each file, print one row per block:

  | # | What the block says, in one line | Verdict | Why |

Verdict is exactly one of: KEEP AS WORDS (it needs judgement), SCRIPT (it is mechanical, and name
the script), DELETE (it duplicates another file or states the obvious). The owner can rule on a row
without reading the block, and can always ask to see the block.

STEP 5 — THE TEMPLATES BECOME SCHEMAS
A template that only advises produces a document that drifts. Propose for each template a schema
block: required sections in order, the optional ones, a word budget per project size as a TARGET
and a MAXIMUM, and the rules every row must follow. A single hard number makes the agent truncate,
which is why the budget is always a pair.

Give one worked example in full, for templates/checklist-item-template.md, including the rule
TechieFlow found mattered most: every acceptance line reads

  "When <actor> <does what> on <screen>, then <a result a machine can observe>"

at most 30 words, target 20, holding one behaviour. Fourteen recorded misses were traced to
acceptance lines that allowed two honest readings.

STEP 6 — THE MISS PROTOCOL
Propose it as four questions asked in order, each with one fixed response, and a field on the record
that stores which one it was:

  1. Did the project's spec say it clearly?          no  -> fix the checklist line. Framework untouched.
  2. Did the Playbook say it anywhere?               no  -> add one requirement line plus a check.
  3. Was there a check, and did it fail to catch it? yes -> fix the check, not the prose.
  4. Was it written and ignored anyway?              yes -> make it a script or a gate, or delete it.

TechieFlow's own numbers say why the third question earns its place: of its sorted misses, about
half were "the check was too weak", a quarter "nobody said it", a quarter "said and ignored". Half
of a framework's failures are its checks, not its words. The fourth response is the one with teeth:
a rule ignored twice never gets a third paragraph.

STEP 7 — THE INSTRUCTION BUDGET
Propose a budget per phase, expressed per model tier rather than as one number, and say how a phase
document is written so a small budget can be met without losing steps: a short core, plus reference
sections loaded only when a step needs them. State each phase's current figure against the budget.

STEP 8 — THE PLAN
Write docs/Playbook-Reset-Plan.md with these sections, in this order:
 1. What is genuinely right and should be kept. Name files.
 2. What grew without earning its place. Name files, sizes, and why.
 3. The instruction surface per phase today, and a target for each.
 4. The keep / script / delete table from Step 4, consolidated.
 5. Which documents to merge, shrink, or move out of the reader's path. A corporate adopter needs a
    getting-started, the ten phases, the templates, and one operating guide. Everything else must
    justify itself. Say where the rest goes; nothing is deleted without a home.
 5b. What to do about verification/, which is 62 percent of the repository. Say what the campaigns
    prove, whether anything still depends on them, what evidence a future run should keep and for
    how long, and where it should live so it is not committed. TechieFlow's answer was one ignored
    folder swept after seven days, with the durable proof kept as a self-test anyone can re-run
    instead of a stored copy of its output. Recommend, do not assume: these campaigns may be the
    only record that the OpenCode-only install was ever proven.
 6. A requirements list for the Playbook itself — AND ITS GRADER. This section replaces version 2's
    "about 30 lines, each with a way to check it", which is how TechieFlow ended up with 28 checks
    that did not exist. The rules:
      - Fewer lines, each one testable. Twenty that can be graded beat forty that cannot.
      - Every line is marked script, fixture run, or review, and the three are counted separately.
      - A line marked "script" names the artefact that runs it, and that artefact is written in the
        same session as the line. If it cannot be, the line is marked "review" instead.
      - The grader is part of the deliverable: one command that walks the list, runs what can be
        run, and reports every other line as ungraded WITH ITS REASON. Never guess a verdict.
      - The headline number is not how many pass. It is **how many can be graded at all**. Report it
        as "N of M graded", and treat the ungraded count as the backlog it is.
      - The grader writes one verdict record per line into the telemetry, so the Playbook's own
        compliance is visible beside the projects it builds.
 7. The miss protocol from Step 6, as it will be recorded and reported.
 8. An ordered list of work sessions, each with a goal, the inputs the owner brings, and the output
    file. Put the shared files that every phase loads first: shrinking those shrinks every phase at
    once. Say so in the plan, because it is the one step out of life-cycle order.

Also write docs/Playbook-How-It-Works.md: the ten phases in plain words, one paragraph each, saying
what is read, what is written, which template is used, and what OpenCode does around it. A team lead
with no AI experience should be able to follow it. This document, not the plan, is what the owner
reviews first.

STEP 9 — REPORT
Finish with a short message: the five biggest findings, each one sentence with its number, the
enforcement ratio from Step 2, and the first session to run. Nothing else.
```

---

## 3. What went wrong in the TechieFlow sessions

Give this list to the review session if it asks how the method was earned. Each item cost time, and the last four were found after version 2 of this prompt was written.

- **A framework never graded itself.** 63 requirement lines, each with a stated check, and not one verdict recorded in the four days they existed. Its own metrics reported "no first-pass rate" because the maintainer reasoned it had no checklist — while the checklist sat in `docs/`, named in every restart prompt. Nobody notices this from inside: it took the owner rejecting a sentence.
- **A rule named a check that nobody had written.** 28 of 63 lines described a script in prose that did not exist. When the grader was built, the first run found technology-specific routing in two tasks that FR-03 forbids, four commands emitting no run record, and five command values the telemetry schema had never listed. All three had been live for days behind a requirement that read as enforced.
- **A number was reported over the wrong denominator.** A phase's total time summed the runs that carried a duration while its tokens summed every run — so the reset showed 16h49m of work against a true 55h57m. Separately, a set of records that all passed reported a first-pass rate of 0%, because the field the rate keys on was absent and absence read as "no". Both were arithmetic the reader could have done from the records it already had.
- **Two delivery routes drifted apart.** The shell scripts and the npm installer produced different projects for four sittings, because nothing said that a change to what a project receives goes into both. A project installed from the package ran without three of its guard hooks.
- **A guard read the whole command line.** The database guard refused a documentation edit and a read-only search because a migration tool's name appeared in the text being written. A rule that blocks the work it was meant to protect gets switched off.
- **A command reported success after its only deliverable was refused.** The miss recorder printed "Miss logged" and an id that existed nowhere, because the emitter had rejected a value and appended nothing.
- **A checklist was frozen and then quietly grown.** Items were added to an owner-reviewed document and the owner was told afterwards. Propose in plain words, get the yes, then edit.
- **Rules were restated instead of enforced.** 622 prose MUST and NEVER statements against 8 hooks. The 8 always held.
- **Documents grew until nobody read them.** The briefing reached 344 KB and the README 121 KB, both mostly history. They are now 2,003 and 1,863 words, and a script counts them.
- **A single hard budget made the agent truncate.** Every budget became a target and a maximum.
- **The largest file was the worst file.** The verify task at 11,850 words was the origin of 63 of 128 recorded misses. It is now 964.
- **A self-test check compared the wrong thing** and reported a failure that was not there. A check is not trusted until it has been made to fail on purpose.
- **Search tools do not see the framework.** Dot-directories are skipped by ripgrep, Glob and shell globs, and git-ignored inside a project. Confirm a file by reading its literal path, never by searching for its name. It recurred on 2026-09-07 while measuring the Playbook, costing 58 percent of one folder's size.
- **Removing a harness is a delivery job, not a deletion job.** When the Codex adapter went, the fix was to make the updater *remove* what it used to deploy. One propagation pass then cleaned 23 projects, repeatably and auditably, instead of anyone deleting folders by hand.

---

## 4. What is different about a corporate team

The Playbook is not TechieFlow with more people. Four differences change the design.

- **One harness, and it enforces differently.** OpenCode has no blocking end-of-turn hook, so a rule that must hold at the end of a turn is a plugin follow-up prompt there, not a hook. Anything proposed as a hook needs its OpenCode form stated beside it, or it is not a rule, it is a hope.
- **A rule that depends on remembering fails faster with more people.** Enforcement belongs in the repository, where a joiner inherits it: scripts, validators, the pipeline. In a solo framework a habit can substitute for a gate. In a team it cannot.
- **The review gates have named humans.** Phases 02, 06 and 08 are real handoffs between people. Each needs its record: what was reviewed, how many corrections came back, and what producing and correcting it cost. TechieFlow added exactly this record kind and it is the only one that prices a specification defect.
- **Onboarding is a deliverable, not documentation.** A new joiner should reach a working feature in a day, and the getting-started document has to make that true. That is the test for `docs/`: if a document does not serve a joiner, an agent, or a gate, it is not on the reading path.

Two further constraints: the Playbook is already distributed on npm, so any change ships through its release checks — and those checks must run before publish, not after, which is itself a requirement worth grading. Its telemetry runs beside customer work, so records carry identifiers and counts only, never requirement text, prompt text, or anything from a customer's repository.

---

## 5. Notes for the owner

- The two output documents land in the Playbook's `docs/`. Read the How-It-Works first, mark every line you cannot repeat to a colleague, and have that conversation before any session starts.
- The plan's sessions are carried out in Claude Code and proven in OpenCode against a fixture repository. Nothing is marked done from Claude Code alone.
- Keep TechieFlow and the Playbook in step on one thing only: the miss protocol and the telemetry schema. Everything else may diverge, because the audiences differ.
- The Playbook's `docs/` holds two documents that belong to TechieFlow, `Miss-Telemetry-TechieFlow.md` and `Phase-Efficiency-TfLens-Contract.md`, 7,700 words between them. The review will flag them; deciding where they live is yours.
- **When the plan's Step 8.6 lands, ask one question of it before approving: "how many of these lines can be graded on the day we write them?"** If the answer is most of them, the list is honest. If it is a handful, the list is a wish and the session that wrote it has handed you TechieFlow's 28 phantom checks in a new folder.

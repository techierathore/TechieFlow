# AI-First Playbook — Review Session Prompt (version 2)

| | |
|---|---|
| Purpose | The text the owner pastes into a fresh Claude Code window to review the AI-First Playbook, the team edition, and produce a plan for fixing it. |
| Audience | The owner, and the review session that reads it. |
| Status | **Version 2, written 2026-09-07 at the close of the TechieFlow reset (Session 7).** It replaces version 1, which was drafted before those sessions and is kept only in git history. Ready to run. |
| Companion | `TechieFlow-Reset-Plan-2026-09-04.md`, `TechieFlow-Document-Schemas.md`, `TechieFlow-Requirements.md`, `TechieFlow-How-It-Works.md`, `docs/CHANGELOG.md` |

---

## 1. What changed between version 1 and version 2

Version 1 assumed the Playbook had TechieFlow's disease and told the review to look for the same pattern. A measurement on 2026-09-07 says the shape is different, and the difference decides where the work goes.

**The prose the reader sees is lean.** The ten phase files total 3,572 words, an average of 357 each. Shouted rules of the MUST / NEVER / BANNED kind number 61 across the whole repository, against 622 in TechieFlow before its reset, and 46 of those 61 sit in one folder. Fifteen scripts already exist.

**The prose the agent reads is not.** The shipped OpenCode harness carries a **verifier agent of 8,630 words** and fifteen command files totalling **29,800**, the largest of them 4,855. TechieFlow's caps after its reset are 1,500 words for a persona and 7,000 for a command, and its own evidence is that its 11,850-word verify task was the origin of 63 of 128 recorded misses. The Playbook's verify path is the same shape as the file that hurt TechieFlow most.

**And there is a third thing neither version predicted.** `verification/` holds **174 files and 196,498 words** of committed run evidence: three dated campaigns, each keeping a complete copy of an installed target. That is 62 percent of the repository's 317,385 markdown words, it is not shipped by the npm package, and it is why the same 8,630-word verifier file exists six times in the tree. TechieFlow bans exactly this: run material lives under `tests/.artifacts/` and is swept after seven days, because a repository that keeps every run's output makes every later search return stale copies.

So version 2 does three things version 1 did not. It hands the review a measured starting point to confirm or refute rather than a borrowed diagnosis. It carries the methods the TechieFlow sessions proved. And it names what went wrong in those sessions, including the two ways these very numbers were nearly reported wrong, so this review does not repeat it.

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
incident by incident over six months. TechieFlow has just been through a seven-session reset. What
that reset learned is written into the method below. Do not assume the two frameworks have the same
faults: measure this one.

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
- A proposal that cannot be checked by a script is a weak proposal. Say so when you make one.

STEP 1 — MEASURE THE SURFACE
Two counting rules, both paid for. Break either and every number below is wrong.

- Count RECURSIVELY, and print the file count beside every word count. A folder measured only at
  its top level reports zero for a folder whose content sits one level down, and a zero that should
  be a number reads as "nothing here" instead of "I did not look". That mistake was made while
  preparing this prompt and hid 174 files and 196,498 words.
- Count HIDDEN paths. Use `find`, not a shell glob, and not a search tool that honours .gitignore.
  A harness lives in a dot-directory: `.opencode/`. When this prompt's own Step 1 was run through
  OpenCode on 2026-09-07 it reported verification/ as 120 files and 82,168 words, against the true
  174 and 196,498, because `**/*.md` skips dot-directories. It under-reported by 58 percent and
  looked entirely plausible. This is the same defect TechieFlow recorded as D-21: the framework's
  own tree is invisible to ordinary search, so an agent concludes a file is not there when it is.

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
   That total is the instruction surface for the phase, and it is the number that matters, not the
   phase document's own size. Say plainly which phase reads the most before its first useful step.
3. Count prose rules and script-enforced rules side by side, and say where each cluster sits.
4. List every document in docs/ with its audience (team lead, developer, agent, owner) and whether
   anything in the repo points at it. Flag every document nothing points at. Flag separately any
   document that belongs to the other framework rather than this one.
5. Report every file that exists more than once in the tree with the same name and near-identical
   content. Duplication is why an edit lands in one copy and not the other.

STEP 2 — THE MISS AND TELEMETRY DATA
1. If a misses stream or docs/metrics exists, summarise misses by cause, by phase, and by who found
   them. If none exists, say so plainly: a framework that cannot show what it got wrong cannot show
   it improved, and that is the single finding most worth fixing first.
2. Read Ai-First-Playbook-Gap.md and docs/Decisions.md. List the rules that were added in reaction
   to an incident, and mark each prose or enforced.

STEP 3 — EVERY PROSE FILE, ONE TABLE
Start with what the agent reads, not what the reader reads: harness/opencode/agent/verifier.md
(8,630 words) and the four largest command files, then the rest of harness/, then phases/ and
templates/. Shrinking the verifier shrinks every verify run, and the equivalent file was the single
worst source of misses in TechieFlow. For each file, print one row per block of the file:

  | # | What the block says, in one line | Verdict | Why |

Verdict is exactly one of: KEEP AS WORDS (it needs judgement), SCRIPT (it is mechanical, and name
the script), DELETE (it duplicates another file or states the obvious). This is the format the
TechieFlow reset used on every task file; it worked because the owner could rule on a row without
reading the block, and could always ask to see the block.

STEP 4 — THE TEMPLATES BECOME SCHEMAS
A template that only advises produces a document that drifts. Propose for each template a schema
block: the required sections in order, the optional ones, a word budget per project size as a
TARGET and a MAXIMUM, and the rules every row must follow. A single hard number makes the agent
truncate, which is why the budget is always a pair.

Give one worked example in full, for templates/checklist-item-template.md, and include the rule
TechieFlow found mattered most: every acceptance line reads

  "When <actor> <does what> on <screen>, then <a result a machine can observe>"

at most 30 words, target 20, holding one behaviour. Fourteen recorded misses across the owner's
projects were traced to acceptance lines that allowed two honest readings.

STEP 5 — THE MISS PROTOCOL
Propose it as four questions asked in order, each with one fixed response, and a field on the record
that stores which one it was:

  1. Did the project's spec say it clearly?          no  -> fix the checklist line. Framework untouched.
  2. Did the Playbook say it anywhere?               no  -> add one requirement line plus a check.
  3. Was there a check, and did it fail to catch it? yes -> fix the check, not the prose.
  4. Was it written and ignored anyway?              yes -> make it a script or a gate, or delete it.

The fourth response is the important one: a rule ignored twice never gets a third paragraph.
TechieFlow's own numbers say why the third question earns its place — of 61 sorted misses,
31 (51%) were "the check was too weak", 16 (26%) "nobody said it", 14 (23%) "said and ignored".
Half of a framework's failures are its checks, not its words.

STEP 6 — THE INSTRUCTION BUDGET
Propose a budget per phase, expressed per model tier rather than as one number, and say how a phase
document is to be written so a small budget can be met without losing steps: a short core, plus
reference sections loaded only when a step needs them. State each phase's current figure from
Step 1.2 against the budget you propose.

STEP 7 — THE PLAN
Write docs/Playbook-Reset-Plan.md with these sections, in this order:
 1. What is genuinely right and should be kept. Name files.
 2. What grew without earning its place. Name files, sizes, and why.
 3. The instruction surface per phase today, and a target for each.
 4. The keep / script / delete table from Step 3, consolidated.
 5. Which documents to merge, shrink, or move out of the reader's path. A corporate adopter needs a
    getting-started, the ten phases, the templates, and one operating guide. Everything else must
    justify itself. Say where the rest goes; nothing is deleted without a home.
 5b. What to do about verification/, which is 62 percent of the repository. Say what the campaigns
    prove, whether anything still depends on them, what evidence a future run should keep and for
    how long, and where it should live so it is not committed. TechieFlow's answer was a single
    ignored folder swept after seven days, with the durable proof kept as a self-test that anyone
    can re-run instead of as a stored copy of its output. Recommend, do not assume: these campaigns
    may be the only record that the OpenCode-only install was ever proven.
 6. A requirements list for the Playbook itself: about 30 lines of "the Playbook must …", each with
    a way to check it against a fixture repository under OpenCode. Mark each check script, fixture
    run, or review. Every review check is a candidate to become a script, and say so.
 7. The miss protocol from Step 5, as it will be recorded and reported.
 8. An ordered list of work sessions to carry the plan out, each with a goal, the inputs the owner
    brings, and the output file. Put the shared files that every phase loads first: shrinking those
    shrinks every phase at once. Say so in the plan, because it is the one step that is out of
    life-cycle order.

Also write docs/Playbook-How-It-Works.md: the ten phases in plain words, one paragraph each, saying
what is read, what is written, which template is used, and what OpenCode does around it. A team lead
with no AI experience should be able to follow it. This document, not the plan, is what the owner
reviews first.

STEP 8 — REPORT
Finish with a short message: the five biggest findings, each one sentence with its number, and the
first session to run. Nothing else.
```

---

## 3. What went wrong in the TechieFlow sessions

Give this list to the review session if it asks how the method was earned. Each item cost time.

- **A rule named a check that nobody had written.** The requirement said a script proved it; no script existed, and a private project name sat in the public README for months. When a requirement names a check, the check is written in the same session or the requirement says "review" honestly.
- **A command reported success after its only deliverable was refused.** The miss recorder printed "Miss logged" and an identifier that existed nowhere, because the emitter had rejected a value and appended nothing. A command that reports what it did not do is worse than one that fails loudly.
- **A checklist was frozen and then quietly grown.** Items were added to an owner-reviewed document and the owner was told afterwards. That is how the framework grew unreviewed in the first place. Propose in plain words, get the yes, then edit.
- **Rules were restated instead of enforced.** 622 prose MUST and NEVER statements against 8 hooks. The 8 always held. The 622 held most of the time, and the remainder is where the misses came from.
- **Documents grew until nobody read them.** The briefing reached 344 KB and the README 121 KB, both mostly history. Session 6 cut them to 1,961 and 1,864 words and moved the history to a changelog. Now a script counts them.
- **A single hard budget made the agent truncate.** Every budget became a target and a maximum, and the content rules stop truncation, not the number.
- **The largest file was the worst file.** The verify task at 11,850 words was the origin of 63 of 128 recorded misses. Size is not a cosmetic problem.
- **A self-test check compared the wrong thing** and reported a failure that was not there, wasting time on a fix that already worked. A check is not trusted until it has been made to fail on purpose.
- **Scripts were called done without being run.** The standing rule now is that every script the maintainer touches is run for real, in both harnesses, and its output shown.
- **A measurement taken at the top level of each folder reported zero for folders whose content sits one level down.** It hid 174 files and 196,498 words while preparing this very prompt, and the wrong headline was written into a draft before the recount caught it. Count recursively, and always print the file count beside the word count so a zero that means "I did not look" cannot pass for a zero that means "nothing here".
- **Search tools do not see the framework.** `.tfcore/`, `.claude/` and `.opencode/` are dot-directories and are git-ignored inside a project, so ripgrep, Glob and `git grep` all return nothing for files that are plainly present. TechieFlow recorded it as D-21 after a verify run wrote "not present anywhere in this tree" about a script that existed and closed a gate on it. The rule that followed: confirm a file by reading its literal path, never by searching for its name, and never write "not present" without naming the path tried. It is not a solved problem, only a known one: it recurred on 2026-09-07 while measuring the Playbook, costing 58 percent of one folder's true size.

---

## 4. What is different about a corporate team

The Playbook is not TechieFlow with more people. Four differences change the design.

- **One harness, and it enforces differently.** OpenCode has no blocking end-of-turn hook, so a rule that must hold at the end of a turn is a plugin follow-up prompt there, not a hook. Anything proposed as a hook needs its OpenCode form stated beside it, or it is not a rule, it is a hope.
- **A rule that depends on remembering fails faster with more people.** Enforcement belongs in the repository, where a joiner inherits it: scripts, validators, and the pipeline. In a solo framework a habit can substitute for a gate. In a team it cannot.
- **The review gates have named humans.** Phases 02, 06 and 08 are real handoffs between people, where TechieFlow's equivalent is the owner reviewing their own work. Each gate needs its record: what was reviewed, how many corrections came back, and what producing and correcting it cost. Without that the cost of a bad specification stays invisible.
- **Onboarding is a deliverable, not documentation.** A new joiner should reach a working feature in a day, and the getting-started document is the thing that has to make that true. That is the test to apply to `docs/`: if a document does not serve a joiner, an agent, or a gate, it is not on the reading path.

Two further constraints: the Playbook is already distributed on npm, so any change ships through its release checks, and its telemetry runs beside customer work, so records carry identifiers and counts only, never requirement text, prompt text, or anything from a customer's repository.

---

## 5. Notes for the owner

- The two output documents land in the Playbook's `docs/`. Read the How-It-Works first, mark every line you cannot repeat to a colleague, and have that conversation before any session starts.
- The plan's sessions are carried out in Claude Code and proven in OpenCode against a fixture repository. Nothing is marked done from Claude Code alone.
- Keep TechieFlow and the Playbook in step on one thing only: the miss protocol and the telemetry schema. Everything else may diverge, because the audiences differ.
- The Playbook's `docs/` currently holds two documents that belong to TechieFlow, `Miss-Telemetry-TechieFlow.md` and `Phase-Efficiency-TfLens-Contract.md`, 7,700 words between them. The review will flag them; deciding where they live is yours.

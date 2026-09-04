# AI-First Playbook — Review Session Prompt (version 1, draft)

**Status:** this is a first draft written before the TechieFlow reset. **Do not run it yet.** Once the TechieFlow sessions are finished, a version 2 of this prompt will be written that carries over what those sessions actually taught: the final keep/script/delete method, the schema format that worked, the miss protocol as it ended up, and the mistakes made along the way. Version 1 is kept so the two can be compared.

**How the Playbook work will be split.** The Playbook is built and edited in Claude Code, because that is where the owner works fastest. It is tested only in OpenCode, because that is the harness its users have. So the review below runs under Claude Code, the plan's changes are made under Claude Code, and every change is proven by running the Playbook's commands in OpenCode against a fixture repo. A change that works in Claude Code and fails in OpenCode is not done.

Run this in Claude Code with the working directory set to `/mnt/c/3AIGenCode/AI-First-Playbook`. It performs the same diagnosis TechieFlow received on 2026-09-04, but for the team edition, whose real harness is OpenCode. The output is a plan, not changes.

Copy from here to the end of the block.

```
You are reviewing the AI-First Playbook, a team-edition, spec-driven development process for AI coding agents. It is published on npm as @techierathore/ai-first-playbook and is used through OpenCode. Corporate teams are the audience; they avoid single-vendor tools, so OpenCode is the primary harness and must stay so. Claude Code is secondary here.

The Playbook was borrowed from BMAD and then corrected incident by incident over six months, alongside its solo sibling TechieFlow. TechieFlow's review found the same pattern this review should look for: prose rules accumulating faster than enforcement, documents nobody reads, and no requirements list for the framework itself.

RULES FOR THIS SESSION
- Plain English in everything you write. Short sentences. Any term of art gets a one-clause explanation the first time. The owner is a .NET expert, not a YAML or harness expert, and will reject text they cannot repeat to a colleague.
- Analysis and plan only. Do not edit any file except the two you are asked to create. Do not run git in any form.
- Every claim has a number or a file path behind it. Measure, do not estimate.
- Keep OpenCode first-class in every proposal. Never propose removing OpenCode support, the operating contract, or the npm packaging.

STEP 1 — MEASURE THE SURFACE
1. Word count of every markdown file, grouped by folder (phases/, templates/, docs/, onboarding/, harness/, playbook/, root). Print a table sorted by size.
2. For each of the ten phase documents, what an OpenCode agent actually loads when that phase runs. Trace it from opencode.json and AGENTS.md: which files, in what order, total words. This is the instruction surface per phase.
3. Count MUST / NEVER / HARD / BANNED / ALWAYS in prose across all agent-facing files. Count what is enforced by a script (scripts/*.mjs, hooks, validators). Print both numbers side by side.
4. List every document in docs/ with its audience (team lead, developer, agent, owner) and whether anything in the repo refers to it. Flag documents nothing points at.

STEP 2 — READ THE MISS AND TELEMETRY DATA
1. If docs/metrics or any misses file exists, summarise misses by cause, by phase, and by who found them. If none exists, say so; that is a finding.
2. Read Ai-First-Playbook-Gap.md and docs/Decisions.md. List rules that were added in reaction to an incident and note whether each is prose or enforced.

STEP 3 — THE TEMPLATES
For each file in templates/: size, what document it produces, whether it is prose guidance or a checkable shape. Propose for each: keep as is, turn into a schema (required sections, budgets, row rules, checked by a script), or delete. Give one concrete schema example for the checklist item template.

STEP 4 — THE PLAN
Write docs/Playbook-Reset-Plan.md with these sections, in this order:
1. What is genuinely right and should be kept (be specific: file names).
2. What grew without earning its place (file names, sizes, why).
3. The instruction surface per phase today, and a target for each (roughly one third).
4. Which prose rules to convert to scripts, which to delete, which to keep as judgement. Use three buckets: keep, script, delete.
5. Which documents to merge, shrink, or move out of the reader's path. A corporate adopter needs a getting-started, the ten phases, the templates, and one operating guide. Everything else must justify itself.
6. A requirements list for the Playbook itself: about 30 lines of "the Playbook must …", each with a way to check it against a fixture repo under OpenCode.
7. A miss protocol for the Playbook, three questions: did the project's spec say it; did the Playbook say it; was it said and ignored. Each with its one fixed response. No prose rule survives being ignored twice.
8. An ordered list of work sessions to carry the plan out under OpenCode, each with a goal, inputs the owner brings, and the output file.

Also write docs/Playbook-How-It-Works.md: the ten phases explained in plain words, one paragraph each, saying what is read, what is written, which template is used, and what OpenCode does around it. A team lead with no AI experience should be able to follow it.

STEP 5 — REPORT
Finish with a short message: the five biggest findings, each one sentence with its number, and the first session to run. Nothing else.
```

---

## Notes for the owner

- The two output files land in the Playbook's `docs/` folder. Read the How-It-Works first, mark what is unclear, and have that conversation before starting the plan's sessions.
- The plan's sessions are carried out in Claude Code. Every session ends by running the changed commands in OpenCode against a fixture repo. Nothing is marked done from Claude Code alone.
- Version 2 of this prompt will add: the TechieFlow keep/script/delete table format, the schema block format, the miss protocol wording, and a list of what went wrong in the TechieFlow sessions so the Playbook review does not repeat it.
- Keep TechieFlow and the Playbook in step on one thing only: the miss protocol and the telemetry schema. Everything else may diverge; they serve different audiences.

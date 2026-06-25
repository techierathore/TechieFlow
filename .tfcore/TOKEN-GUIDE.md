# TechieFlow — Token-Efficiency Guide

> For the framework owner **and** anyone running an agent in it. This framework generates a lot of documents and runs multi-agent builds, so AI tokens add up. This guide explains *where* the tokens go and the concrete levers — both habits the team should follow and things already **baked into the framework** — to keep usage low without losing quality.

## TL;DR — the five biggest levers

1. **Don't load what you don't need.** The single largest waste is pulling whole documents (or the whole repo) into context "just in case." Read the *specific* section/file the task names. (Baked in: agents are told to "load resources at runtime, never pre-load.")
2. **Checklists are markdown-only — never rendered to HTML.** (Baked in.) Rendering an agent doc to HTML doubled the bytes of the framework's biggest files for zero human value. Human docs (BRD, Architecture, UsageGuide, DevGuide, PROJECT-STATUS) get HTML; checklists do not.
3. **Fan out, don't marathon.** Big jobs (a build phase, the DevGuide) split across parallel subagents, each with a *small* scoped context, instead of one agent reading everything. (Baked in: build phases and `*devguide` fan out by cluster/role.)
4. **Update incrementally, don't regenerate.** Use `*amend-docs` (not a full `*day1-*` re-run) for doc changes, and `*devguide --update` for code-map refreshes. Regenerating a 60-screen guide to fix one screen is the most common avoidable burn.
5. **Recover, don't redo.** If a session dies mid-phase, run `*refresh-status` (reconstructs state cheaply from evidence) instead of re-running the whole build.

---

## Where the tokens actually go

| Cost center | Why it's expensive | The lever |
|-------------|--------------------|-----------|
| **Reading docs into context** | BRD/Architecture/checklists are large; loading all of them every turn is the #1 silent cost | Load only the file + section the current task needs. The checklists are the agents' working docs — the BRD is for humans; a coding agent rarely needs the full BRD once split. |
| **Whole-repo reads** | "Let me understand the codebase" → reads hundreds of files | Use search (grep/Explore subagent) to locate, then read only the hits. Never `cat` a directory. |
| **Re-rendering HTML** | Every re-render rewrites a big self-contained HTML | Render human docs only; checklists never. Re-render on real changes, not defensively. |
| **Regenerating whole docs** | Full `*day1-*` / full `*devguide` rewrites everything | Prefer `*amend-docs` / `*devguide --update` (changed-only). |
| **Long single-agent runs** | One context accumulates the whole job's history | Fan out to subagents; each returns just its result, not its scratch work. |
| **Re-doing lost work** | A crashed phase tempts a full re-run | `*refresh-status` rebuilds state from the checklist tables + files + a build. |

## For the team (agent habits)

- **Open the task file first, then load only what it names.** Tasks list their exact inputs. If a task says "read the Functional-Checklist Requirements Status table," read that — not the BRD, Architecture, and every source file too.
- **Search before reading.** To find where something lives, use grep or an `Explore` subagent (it reads excerpts, returns the conclusion) rather than reading whole files. Read fully only the 1–3 files that matter.
- **Prefer the checklist over the BRD during builds.** After `*split-brd`, the per-REQ checklist tables are the compact work view. The rich BRD is the human document — don't reload it every build turn.
- **Scope your reads.** Use `Read` with `offset`/`limit` for big files; use `@path` mentions for specific files instead of broad directory loads.
- **Fan out big work.** A build phase or a DevGuide over many screens → spawn a subagent per cluster/role. Each gets a small context and returns structured output; the orchestrator never holds every file at once.
- **Incremental beats wholesale.** Changed a few requirements? `*amend-docs`. Changed some code paths? `*devguide --update {scope}`. Don't regenerate the world.
- **Don't render agent docs.** Never produce `*-Checklist.html`. Never re-render a doc that didn't change.
- **Reuse a subagent's conclusion, not its transcript.** When delegating, ask for the answer/structured result, not a dump of everything it read.

## For the owner (setup & workflow)

- **Right-size the loop.** The owner's day-to-day loop is intentionally lighter than full TechieFlow (analyst → trblazeui → flow-master → verifier, not story-by-story). Don't run phases you don't need.
- **Batch reviews.** Review rendered HTML in browser (cheap, local) rather than asking the agent to re-explain docs (re-reads them = tokens).
- **Use `*refresh-status` after any interruption** before resuming — it's far cheaper than re-running a build to rediscover state.
- **Keep `devLoadAlwaysFiles` lean** (`.tfcore/core-config.yaml`). Only the Coding-Standards + Architecture paths the day-1 tasks set belong there; every file listed is loaded on every relevant agent turn.
- **Split large apps' DevGuide per role** (the default for big apps). A developer chasing a bug then loads only the one role file, not a 200-page guide.
- **Watch usage where you can see it.** In Claude Code, `/cost` (or the usage view) shows session token spend; the Anthropic Console usage dashboard shows account-level trends. If a session's cost spikes, it's almost always a whole-doc or whole-repo load — check what got read.
- **Prefer cheaper models for mechanical sub-steps** when you orchestrate them yourself (e.g. a pure file-mapping subagent can run on a smaller model than the architect-level reasoning).

## What the framework already does for you (baked-in defaults)

- **Checklists are never rendered to HTML** — only human docs are (saves a re-render of the largest files on every phase).
- **Build phases fan out** across parallel subagents by cluster, each scoped to its slice.
- **`*devguide` fans out per role** and supports `--update` for changed-only refreshes; large apps split per role so each file stays small.
- **`*amend-docs`** exists specifically so doc evolution is surgical/in-place instead of a full regenerate.
- **`*refresh-status`** reconstructs state from evidence after a crash, so a dead session doesn't force a re-build.
- **Agents load resources at runtime, never pre-load**, and the KB is loaded only on `*kb`/`*kb-mode`.
- **Single source of truth** (one checklist table per REQ) avoids duplicated status docs that would each need loading/updating.

## A simple rule of thumb

> Before you read something, ask: *does the current step actually need this whole thing, or just one section?* Before you regenerate something, ask: *did most of it actually change, or just a piece?* Those two questions, asked every time, cut the majority of avoidable token spend.

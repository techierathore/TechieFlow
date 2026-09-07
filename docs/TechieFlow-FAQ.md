# TechieFlow — Questions and gotchas

| | |
|---|---|
| Purpose | The things that trip people up, each with the answer and the date it was fixed. |
| Audience | Anyone using the framework who has just hit something surprising. |
| Status | Moved out of `README.md` on 2026-09-07 (Session 6 of the reset), unedited. Every entry predates the reset, so a few describe commands and task sections that Session 4 renamed or removed; the answer's substance still holds. `docs/TechieFlow-How-It-Works.md` is the current description. |
| Companion | `README.md`, `docs/TechieFlow-Setup.md`, `docs/TechieFlow-Permissions-And-YOLO.md`. |

---

## 15. FAQ & gotchas

**Q: Rendering docs to HTML burns enormous tokens every phase. Is the model really writing all that by hand?**

It was, until 2026-08-27. There was no renderer: `html-render-shell.md` was a 494-line prose spec and both render tasks told the agent to implement it by hand. One phase re-rendering four documents emitted ~300 KB of HTML — roughly **75–80k output tokens** — and `PROJECT-STATUS.html` is mandatory at the end of *every* phase.

One command now:

```bash
bash .tfcore/utils/tf-render-html.sh docs/MyApp-BRD.md PROJECT-STATUS.md
```

Dependency-free (Python 3 stdlib — no pandoc, no node, no pip). It **extracts the §2 CSS, §3 theme script and §7 JS out of `html-render-shell.md` at render time** instead of duplicating them, so the shell cannot drift from its own spec. Passing a `*-Checklist.md` is refused with exit 2 — that ban is mechanical now, not prose. It also runs the §5.5 Mermaid self-check; those warnings are defects in the **source markdown**, so fix the diagram and re-render, never edit generated HTML. (TfLens TF-003 — a gap, not a regression.)

**Q: Does `update-framework.sh` update the root `opencode.jsonc`? Mine looks very old.**

It does now; it did not until 2026-08-27. The 2026-08-20 split moved framework config to `.opencode/opencode.jsonc` (refreshed every run, wins on conflicts) and demoted the root file to project-only keys — then preserved it forever. A survey of all ten apps carrying the file found **none has any project-only content**; nine held a 138–154 line copy of a 925-line template, all nine missing the `trblazeui`/`techierag` agents. Two still wired the `build-ui/rag/functional-phase` commands dissolved 2026-06-26 as `{file:}` refs to deleted files — and **a dead `{file:}` ref hard-fails OpenCode's entire config load**, so those repos silently loaded no framework agents or commands. The root file now refreshes like `.claude/settings.json`: replaced when nothing project-owned would be lost (old → `opencode.jsonc.bak`), preserved with the project-only keys named when there is, dead refs reported either way.

**Q: An agent says a framework file — `tf-metrics.sh`, a task, a template — is "not present anywhere in this tree". It obviously is. Why?**

Because the framework is invisible to every default file-search tool, and until 2026-08-27 nothing told the agents that. **Two independent filters stack**, and you have to defeat both:

- `.tfcore/`, `.claude/`, `.codex/`, `.opencode/` and `.agents/skills/` are **hidden dot-directories** — ripgrep (which backs the agents' Grep tool) skips hidden paths by default.
- They are also in the **managed `.gitignore` block** the scaffolders write into every app (§3) — and ripgrep honours `.gitignore` by default too.

So `rg --hidden` is *not* enough in an app repo; it takes `rg --hidden --no-ignore` (`rg -uu`). And since nothing under `.tfcore/` is *tracked* in an app, `git grep` and `git ls-files` return zero rows as well. An agent that globs for a filename gets nothing and reasonably concludes the framework isn't installed.

**This is not fixed by un-ignoring the framework.** That ignore block is deliberate and load-bearing — deployed copies are re-synced from the template by `update-framework.sh` and must never be committed in an app (§3). The fix is on the agent side: every framework file has exactly one canonical path, and whatever needs it names that path, so **existence is confirmed by reading the literal path, never by searching for the name**. The rule now lives in `.tfcore/tasks/_status-update-gate.md` §"The framework tree is INVISIBLE to search" (a shared include, so every checklist-executing task gets it), is restated in verify-phase's verdict rules, and ships in the `AGENTS.md` / `CLAUDE.md` hard rules for new apps.

**Why it matters more than a wasted search:** the false negative doesn't stay in the transcript. It gets written into a checklist Remarks cell, a BRD §4 status row, or a blocker — and the next agent inherits it as fact, closing a gate that was never actually blocked.

**When it really *is* missing:** a fresh clone genuinely has no `.tfcore/`, because it was never committed. That repo needs `update-framework.sh <repo>` run once *on that machine* (§16) — one command, never a reason to reimplement what the missing file does.

**Q: What if the agent ignores the coding standards mid-implementation?**

The verifier's standards-compliance grep checks (§10, item 3) catch the most common violations and produce coverage misses. When you see a miss like `STANDARDS: underscore-field in src/Foo.cs:42` flagged in the checklist's Requirements Status table, tell the implementing agent: *"Fix the standards violations flagged in the Requirements Status table of docs/<APP>-Checklist.md per docs/<APP>-Coding-Standards.md."* Loop until clean.

**Q: What if existing brownfield code doesn't use the `obj` field prefix?**

First: the prefix only applies if THIS project chose `obj` — the field prefix is a per-project day-1 decision recorded in `docs/<APP>-Coding-Standards.md` (e.g. AstroLyfe uses bare PascalCase, no prefix). If it did, the analyst flags it as standards drift in the day-1 output summary. You then either: (a) let the standards-compliance grep checks in the verify pass catch them and fold the fixes into the regular build loop (the implementing agent renames as it touches the file), or (b) explicitly ask flow-master for a one-shot rename pass: *"Rename every non-obj-prefixed instance field in src/ to use the obj prefix per docs/<APP>-Coding-Standards.md, in one commit per file."* Option (a) is lower-risk; option (b) is faster if you want a clean baseline.

**Q: I want to change the coding standards mid-project. Will the agents pick it up?**

Yes — they read `docs/<APP>-Coding-Standards.md` on every invocation. Update the file, then in the next implementation prompt include *"NOTE: the coding standards file was updated; conform new code to it and flag any existing non-conforming areas in your output summary."*

**Q: Should the architecture document be updated as the code changes?**

Yes. Handoff includes "if the architecture changed during implementation, update Architecture.md first to reflect 'as-built', then regenerate the HTML." For mid-flight structural changes, the implementing agent should note it; `/flow-master` reconciles at handoff. For a deliberate scope/structure change, run `*amend-docs <APP> "<what changed>"` (§7.9).

**Q: `scaffold-brownfield.sh` / `scaffold-greenfield.sh` re-run wiped my work?**

No for your work product — framework files copy with `rsync --ignore-existing`. EXCEPTION: the harness agent mirror under `.claude/commands/TechieFlow/agents/` is force-synced from `.tfcore/agents/` on every run — edit agents only in `.tfcore/agents/`. (The old `.opencode/command/TechieFlow/` mirror no longer exists — OpenCode loads agents/tasks from `opencode.jsonc` `{file:./.tfcore/...}` references.)

**Q: `*yolo` doesn't stop Bash prompts.**

It does now (2026-08-21, §12a). `*yolo` writes `.tfcore/.session/yolo.json`; the PreToolUse hook reads it and stops asking for `rm`/`rmdir`/`sudo` and allows read-only git. If you still see a delete prompt: (1) the app's `.claude/settings.json` predates the change and still has `Bash(rm *)` under `ask` — run `update-framework.sh <app>`; a settings `ask` rule prompts in every mode, even bypass; (2) the agent forgot to run `tf-yolo.sh on` — type `*yolo` again or run it yourself. Git **writes** prompt for nobody — they are denied outright in every mode.

**Q: My unattended goal run stopped on "You've hit your limit · resets …".**

Use the supervisor, not a bare session: `bash .tfcore/utils/tf-goal.sh <app-dir> "<goal>"` (§12a). It parses the reset time, sleeps until reset + 15 min, and resumes the same session; `--resume <app-dir>` continues after a reboot. Watch `.tfcore/.session/goal.log`.

**Q: `*build-phase` implemented a few REQs and told me to run it again for the rest.**

That ending is banned (build-phase §2b). Re-run it — FRESH/FIX detection picks up the open rows — and, if it happens again, quote §2b back: a pass is done when every working-list REQ is ≥ `Implemented`; context pressure means more sub-agent clusters, not a shorter pass.

**Q: Mermaid not rendering in BRD.html / Architecture.html.**

(1) Offline + CDN script blocked — inline mermaid.min.js instead. (2) Missing `mermaid.initialize` — check end of HTML. (3) Malformed code fence — confirm ````mermaid` on its own line and valid Mermaid syntax.

**Q: Verifier says "Playwright not installed".**

Vidur self-heals browser binaries. If install fails: did you run §0?

**Q: Agent implemented things *not* in the requirements doc.**

*"Revert anything not tied to a REQ-* ID."* Add new REQ first if you actually want it.

**Q: Slash command `/trblazeui` shows "no skill".**

Run `dotnet build` once to fire the TrBlazeUI NuGet deploy target. If still missing: `dotnet build -t:TrBlazeUIRedeployAgentFiles`. Restart Claude Code so it rescans skills.

**Q: Should I commit the HTML files?**

Yes for all of `PROJECT-STATUS.html`, `<APP>-BRD.html`, `<APP>-Architecture.html`, `<APP>-<Library>-Feedback.md`. Browseable on GitHub without cloning, and they're the human-facing artifacts.

**Q: Standard TechieFlow story-by-story flow — ever?**

Only with a second person. For solo + Claude Max, the compressed flow is strictly faster. The stock story-flow agents and tasks no longer ship with this scaffold (trimmed 2026-06-12) — obtain a full story-by-story agent set separately if that day comes.

**Q: How do I keep token usage down?**

Read `.tfcore/TOKEN-GUIDE.md` (ships with every project). Key levers: don't load whole docs or repo trees into context; checklists stay markdown-only (never rendered to HTML — HTML adds weight with no AI benefit); fan work out to subagents instead of loading everything in one session; use `*amend-docs` and `*devguide --update` for incremental refreshes instead of re-running phases from scratch; use `*refresh-status` to recover a broken session instead of re-running the whole phase.

**Q: A screen passed verification but was rendering blank OR was visually broken — how is it prevented now?**

Before the gates, verification only checked acceptance-test pass/fail (HTTP 200, no exception, element present). A screen could pass while its data table showed zero rows, or while every control rendered its data but the controls **overlapped / sat off-screen / were clipped** so the running app was unusable. Two gates close both holes:

- **Render gate (verify-phase §4a):** the verifier asserts every control listed in the DevGuide actually renders its data — no blank table, no count-over-zero-rows, no empty chart.
- **Visual-truth gate (§4b):** it then asserts the screen LOOKS right — no control overlap, every control in-viewport and non-zero-size, checked at desktop + mobile widths, the screenshot inspected, and diffed against the mockup when one exists.

A REQ is `Verified` only if acceptance passes AND data renders AND the screen looks right; otherwise it drops to `Needs re-verify` / `FAIL`. `Done (pre-existing)` is treated as an unverified migrated claim and gets the same sweep. The DevGuide's observed render/visual tags are refreshed each run, keeping DevGuide ⇄ Checklist ⇄ Verifier runtime-true.

**Q: The verifier passed but the running UI is broken — who do I call?**

`/TechieFlow:agents:flow-master *fix-issues {AppName} {folder}` (§7.11). Drop a folder of screenshots of the broken screens (optionally a `bugs.md` naming what's wrong on each). Flow-master reads them (vision), reproduces each issue live with Playwright, triages it (layout / data / logic / RAG), and **fans the fix out to the right builder** — `/trblazeui` for layout, its own subagents for data/logic, `/techierag` for RAG. You never invoke a builder agent yourself. It then re-smokes (data + visual), re-verifies the affected REQs, and updates the DevGuide + checklist + PROJECT-STATUS.

**Q: I found bugs at UAT / in production — I want them analyzed and logged, but NOT fixed yet**

`/TechieFlow:agents:flow-master *triage-issues {AppName} {evidence}` (§7.12). Same evidence channel as `*fix-issues` (a screenshots folder), plus it accepts a written bug list. Flow-master reproduces each issue live and delivers **docs only**: regressed REQs demoted to `Needs re-verify` with dated `⚠ UAT bug` remarks, new `Planned` REQ rows for unspecified defects, refreshed DevGuide known-issues, and a PROJECT-STATUS whose next command is the `*fix-issues` pointer naming the REQ IDs. Add `verify` to also regression-re-verify the affected screens' sibling REQs. It never edits `src/`/`tests/` and never spawns a builder — you decide when the fixing starts.

**Q: How does a developer understand or verify the AI-generated code?**

Run `/TechieFlow:agents:flow-master *devguide {AppName}` (also auto-run at handoff). It produces `docs/{AppName}-DevGuide.md` + a styled `.html`: every screen grouped by user role, each with a flowchart tracing the full stack (Razor page → service → data-access → stored procedure/query), a Controls table (with observed render-status from the OBSERVE pass), and a Data-lineage table. Use it to find the right service method for a bug, confirm the correct stored procedure is called, or check that a control is bound to the right DTO property. Re-run with `--update` after implementing changes to refresh only the affected screens. See §6 for the full schema and the 3-pass generation model.


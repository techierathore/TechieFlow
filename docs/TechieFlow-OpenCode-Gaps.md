# TechieFlow v4 — OpenCode-Harness Gap Analysis & Fixes

Scope: correctness of the OpenCode harness implementation (`opencode.jsonc`, `.opencode/command/`, mirror-sync) as shipped, verified against the **OpenCode 1.18.18** binary (`/root/.opencode/bin/opencode`) and its docs (https://opencode.ai/docs/{config,agents,commands}/). Empirically confirmed with `opencode agent list`, `opencode debug config`, and scratch projects in `/tmp/opencode/{cmdtest,subtest,permtest2,instr}`.

Status: **FIXED** — all 8 gaps closed 2026-08-13. Each gap records evidence, impact, the applied fix, and its current state. Verified post-fix: `opencode agent list` resolves exactly the registered agents; `opencode debug config` shows the cleaned command surface; Claude Code side untouched.

---

## Verified ground truth (how OpenCode 1.18.18 actually behaves)

- **Agents load from** the `opencode.jsonc` `agent` key (as `/app` uses) or `.opencode/agents/*.md` — NOT from `.opencode/command/`. `opencode agent list` in `/app` resolves the registered agents (`flow-master` primary; `flow-analyst`/`flow-architect`/`flow-verifier`/`trblazeui`/`techierag` `all`), plus built-ins.
- **Commands load from** the `command` key in config AND from markdown files under `.opencode/commands/` (canonical plural) or `.opencode/command/` (singular — deprecated but works). Nested files become **slash-separated** command names: `.opencode/commands/team/review.md` → `/team/review`. A scratch test confirmed `.opencode/command/TechieFlow/tasks/build-phase.md` registers as command `TechieFlow/tasks/build-phase`.
- **Resolved-config reality in `/app`** (`opencode debug config`, post-fix): **29 commands** = 26 config colon-keyed (`techieflow:tasks:*`, described) + 3 loose files (`trblazeui`, `techierag`, `generate-html`). The 33 phantom slash-keyed mirror commands are gone.
- **Command frontmatter supports only** `description`, `agent`, `subtask`, `model`. All other keys are dropped. Verified: `trblazeui`'s `mode`/`temperature`/`tools`/`permission` frontmatter is absent from the resolved command — only `description` + `template` survive. `subtask: true` + `agent: <id>` are preserved and force subagent invocation.
- **`tools` config key is deprecated**; the resolved config auto-normalizes it to a `permission` block (`{"edit":"allow","bash":"allow"}`). `tools: {write:true, edit:true, bash:true}` leaves read/grep/glob/task at their defaults (allowed) — so OpenCode agents keep read/grep/glob/task even though the file "lists" only three tools. We now use `permission` explicitly.
- **Critical resolution behavior:** a `{file:...}` reference to a nonexistent path hard-fails the ENTIRE config (`Configuration is invalid … bad file reference`). Agent prompts must therefore only reference guaranteed-existing files — this is why `trblazeui`/`techierag` get inline prompts, not `{file:}` refs (their persona files are NuGet-deployed and may not exist at scaffold time). `instructions` entries tolerate missing files (no hard error).
- **OpenCode auto-loads `AGENTS.md`** up the directory tree, **never project-root `CLAUDE.md`** (binary references `AGENTS.md` 24×, `CLAUDE.md` 8×; the instruction-context layer globs targets `["AGENTS.md"]`). It also merges user-level `~/.claude/CLAUDE.md`.
- **No settings-level hooks** in OpenCode. The extension point is npm plugins (the `plugin` key); the framework's deployment model does no `npm install` in scaffolded apps (`.opencode/` is rsync-copied), so hook equivalents are absent by design. Git/gh denial under OpenCode is enforced by a root `permission.bash` block instead.
- **Root `permission` schema verified working:** `{"bash": {"*": "allow", "git": "deny", "git *": "deny", "gh": "deny", "gh *": "deny"}}` resolves and denies git/gh (prefix rules; compound forms like `cd x && git log` are not matched — personas repeat the rule in prose, same contract as the Claude-side block-git hook).

---

## GAP 1 — Mirror "agents" are dead weight; the §7 "paths the harnesses actually load" claim is wrong for OpenCode — **FIXED**

**Evidence:** WORKFLOW.html:744 said the scaffold force-sync copies agent files to `.claude/commands/TechieFlow/agents/` and `.opencode/command/TechieFlow/agents/` — "(the paths the harnesses actually load)". For Claude Code that is true; for OpenCode it is not. Empirically, OpenCode registers every file under `.opencode/command/TechieFlow/agents/` as a **command** named `TechieFlow/agents/flow-master` (slash form), not as an agent — the real agents load from `opencode.jsonc` instead. WORKFLOW.html:508 listed the `.opencode/command/TechieFlow/` subtree as a framework-owned path, and scaffold-greenfield.sh / scaffold-brownfield.sh force-synced `.tfcore/agents/` → `.opencode/command/TechieFlow/agents/`.

**Impact:** 4 phantom commands (`TechieFlow/agents/{flow-master,analyst,architect,verifier}`) with empty descriptions polluted the command palette; users could invoke them and get an agent-prompt dump instead of a command. The byte-identical mirroring is semantically meaningful on the Claude side, inert + misleading on the OpenCode side.

**Fix applied:** the entire `.opencode/command/TechieFlow/` mirror was **deleted** (from `/app` and from the scaffold/update deployment). OpenCode loads agents/tasks from `opencode.jsonc` `{file:./.tfcore/...}` references; the mirror only registered phantom commands. `.claude/commands/TechieFlow/` is untouched — Claude Code still loads its agents from there. The byte-identity constraint between the two harness mirrors intentionally ends (separate consumers). WORKFLOW.html:744, :508, :450, :573, :1321 were corrected to state OpenCode loads from `opencode.jsonc`.

**Status: ✅ Verified** — `opencode debug config` no longer lists any `TechieFlow/agents/*` or `TechieFlow/tasks/*` commands; `diff -r .tfcore/agents/ .claude/commands/TechieFlow/agents/` clean.

---

## GAP 2 — Duplicate/undescribed commands: 33 mirror commands vs 26 config commands — **FIXED**

**Evidence:** `opencode debug config` showed 62 commands. The 26 config commands (`techieflow:tasks:*`) carry real descriptions; the 33 file-mirror commands (`TechieFlow/tasks/build-phase` etc.) carried **none** and held the same `.tfcore/tasks/*.md` content under a second, slash-separated name. Scratch test confirmed nested `.opencode/command/TechieFlow/tasks/build-phase.md` registers as command `TechieFlow/tasks/build-phase` independently of the config command `techieflow:tasks:build-phase`.

**Impact:** Every task existed twice in the OpenCode command palette under different names (colon vs slash), with the file-mirror copies undescribed. Confusing discovery, ambiguous invocation, wasted command-list tokens.

**Fix applied:** removed the `tasks` (and `agents`) subdirectories from the OpenCode mirror (GAP 1). OpenCode's task surface is now purely `opencode.jsonc` `command` keys (`techieflow:tasks:*`, all described) + the three loose files (`trblazeui`, `techierag`, `generate-html`).

**Status: ✅ Verified** — `opencode debug config`: 29 commands, no duplicates, every `techieflow:tasks:*` carries its description.

---

## GAP 3 — No `permission` block in `opencode.jsonc` → "GIT IS MANUAL" is unenforced in OpenCode — **FIXED**

**Evidence:** `opencode debug config` resolved `"permission": null` at root. The framework's git/gh denial lives in `.claude/settings.json` (Claude-only deny rules + `block-git.sh` PreToolUse hook). Every agent persona's "GIT IS MANUAL — NEVER run git or gh" is prose only; nothing mechanical stopped an OpenCode agent from running `git commit`.

**Impact:** A hard framework rule ("the harness denies it") was false under OpenCode. An agent that git-commits violates the workflow's evidence model and the "git is manual/owner-only" contract.

**Fix applied:** added a root `permission` block to `opencode.jsonc`:
```jsonc
"permission": {
  "bash": {
    "*": "allow",
    "git": "deny",
    "git *": "deny",
    "gh": "deny",
    "gh *": "deny"
  }
}
```
`.claude/settings.json` is unchanged; the two harnesses enforce independently.

**Status: ✅ Verified** — `opencode debug config` resolves the root bash permission with git/gh denied; `opencode agent list` shows agents still functional.

---

## GAP 4 — Deprecated `tools` key; agent-style frontmatter on command files is silently dropped — **FIXED**

**Evidence:** `opencode.jsonc` used `"tools": {"write":true,"edit":true,"bash":true}` (deprecated form). `.opencode/command/trblazeui.md` and `techierag.md` carried `mode: primary`, `temperature: 0.1`, `tools: {...}`, `permission: {edit: ask, bash: ask}` frontmatter. The resolved config showed `trblazeui` as a command with keys `[description, template]` only — the rest silently dropped because command frontmatter only supports `description`/`agent`/`subtask`/`model`.

**Impact:** The intended "call `/trblazeui` as a sub-agent" flow (build-phase.md) had no mechanical path under OpenCode. `trblazeui`/`techierag` were NOT registered as agents in `opencode.jsonc` — they existed only as commands (with primary-mode intentions ignored). `flow-master` could not spawn them via the `task` tool (which requires registered agents with `mode: all`). The `permission: bash: ask` intent was lost — bash resolved to `allow`.

**Fix applied:**
1. Replaced every `tools` block in `opencode.jsonc` with a `permission` block (`{"edit":"allow","bash":"allow"}`) on all 6 agents.
2. Registered `trblazeui` and `techierag` as agents (`mode: all`) with **inline prompts** (NOT `{file:}` refs — their persona files are NuGet-deployed to `.opencode/command/<lib>.md` / `.claude/<lib>.md` and may not exist at scaffold time; a `{file:}` ref to a missing file hard-fails the entire config). The inline prompt tells the agent to read the persona file at runtime (falling back gracefully) and never run git/gh.
3. Rewrote the `.opencode/command/{trblazeui,techierag}.md` frontmatter to the supported keys only: `description` + `subtask: true` + `agent: trblazeui|techierag`. `subtask: true` is preserved by OpenCode and forces subagent invocation.
4. Added a `description` frontmatter to `.opencode/command/generate-html.md`.

**Status: ✅ Verified** — `opencode agent list` shows `trblazeui (all)` and `techierag (all)`; `opencode debug config` shows both commands with `subtask: true` + `agent:` set; `generate-html` now described.

---

## GAP 5 — `instructions` points at a YAML config; the CLAUDE.md auto-load enforcement layer is absent under OpenCode — **FIXED**

**Evidence:** `opencode.jsonc:3` set `"instructions": [".tfcore/core-config.yaml"]` — a YAML config file used as an instruction blob (works, but it injects raw config, not standards). OpenCode auto-loads `AGENTS.md`, and the framework never emitted one (day-1 produces CLAUDE.md; the binary's instruction-context globs `["AGENTS.md"]` only).

**Impact:** Under OpenCode, the coding-standards file (`docs/{AppName}-Coding-Standards.md`) was not auto-loaded unless an agent explicitly read it. `devLoadAlwaysFiles` in `.tfcore/core-config.yaml` is a Claude-side convention; nothing wired it to OpenCode. Standards drift was more likely when working via OpenCode.

**Fix applied:**
1. `opencode.jsonc` `instructions` is now `[".tfcore/core-config.yaml", "AGENTS.md"]` — AGENTS.md is tolerated when missing (verified: no hard error), so pre-day-1 projects still load cleanly.
2. day-1 tasks (brownfield §7.2 + greenfield §7.2) now emit a harness-neutral `AGENTS.md` at repo root (OpenCode pointer: required reading + the "git is manual" hard rule + slash-command syntax), so OpenCode auto-loads the standards layer after day-1.

**Status: ✅ Applied** — config + day-1 task instructions updated; AGENTS.md emission is part of the next day-1 run.

---

## GAP 6 — Claude-Code invocation forms in task files are invalid under OpenCode — **FIXED**

**Evidence:** Task/agent files referenced `/TechieFlow:agents:verifier *verify ui`, `/TechieFlow:agents:flow-master *build-phase {AppName}` (e.g. `.tfcore/tasks/_status-update-gate.md:43`, plus day1-brownfield, day1-greenfield, refresh-status, triage-issues, build-phase, flow-master.md, install-metrics.sh). Those are Claude-Code slash-command names (path-derived namespace `TechieFlow:agents:*`). Under OpenCode there are no such commands/agents — agents are `/flow-*`, commands are `techieflow:tasks:*` or `TechieFlow/*`. `_status-update-gate.md:43` itself demanded "both Claude Code and OpenCode forms where they differ", but most task files gave only the Claude form.

**Impact:** A next-step command written by an OpenCode agent following the task file referenced a nonexistent `/TechieFlow:agents:verifier` — a dead link the user/next agent could not invoke.

**Fix applied:** swept every single-form reference to dual form (`/TechieFlow:agents:<x>` … `(OpenCode: /flow-<x>)`) across:
- `.tfcore/tasks/build-phase.md` (next-command gates)
- `.tfcore/tasks/day1-brownfield.md` (PROJECT-STATUS next-command + §8 handoff)
- `.tfcore/tasks/day1-greenfield.md` (PROJECT-STATUS next-command + §8 handoff)
- `.tfcore/tasks/refresh-status.md` (next-command recovery pointers)
- `.tfcore/tasks/triage-issues.md` (handoff pointer)
- `.tfcore/tasks/_status-update-gate.md` (already demanded dual form; confirmed)
- `.tfcore/agents/flow-master.md` (verifier recommendation)
- `.tfcore/telemetry/install-metrics.sh` (report pointer)
- `.tfcore/templates/v4custom/app-claude-md-tmpl.md` (slash-command table fixed: deduped flow-master row, corrected verifier → `/flow-verifier`, added architect row)

**Status: ✅ Applied** — no remaining single-form references that would dead-link under OpenCode.

---

## GAP 7 — Singular `.opencode/command/` is deprecated; colon-keyed config commands vs slash-named files diverge — **RESOLVED (keep singular)**

**Evidence:** The framework ships `.opencode/command/` (singular). Canonical is plural `.opencode/commands/` (singular still works, no runtime warning; BMAD issue #1762 marks singular as deprecated). Config commands are colon-keyed (`techieflow:tasks:build-phase`); file commands are slash-named (`TechieFlow/tasks/build-phase`) — two naming schemes for the same content.

**Impact:** Fragile naming divergence; future OpenCode versions may drop the singular dir; command-name collisions are possible (BMAD #1762 notes unprefixed collisions).

**Fix applied (decision):** the naming divergence is largely resolved by GAP 2 (the mirror is gone; config colon keys are the single source for tasks). The remaining loose files live at `.opencode/command/` (singular) because that is the **external NuGet deploy contract** — library personas deploy to `.opencode/command/<libname>.md` (WORKFLOW.html:1023), which we cannot change. Moving the framework's own files to `.opencode/commands/` (plural) would split the command root across two directories. Decision: **keep singular `.opencode/command/`** (works in 1.18.18, matches the NuGet target), and document the deprecation rather than churn the layout. If a future OpenCode drops the singular dir, the only affected files are the NuGet-deployed personas (external) — migrate then.

**Status: ✅ Documented decision** — no layout change; rationale recorded in the scaffold/update comments and this doc.

---

## GAP 8 — `@path` file mentions in command templates behave differently in OpenCode — **FIXED**

**Evidence:** `.opencode/command/generate-html.md` used Claude's file-mention sigil `@` (e.g. `*generate-html @docs/File.md`). In OpenCode command templates, `@` triggers file-content inclusion in the prompt rather than a mention.

**Impact:** Mostly benign (the arg still passes through), but the model may receive file contents it did not ask for, or misread `@path` args. Low severity.

**Fix applied:**
1. The OpenCode copy `.opencode/command/generate-html.md` now documents the OpenCode `@` semantics up front and uses **plain paths** in its invocation examples (the shared task body still strips a stray `@` defensively). The Claude copy `.claude/commands/generate-html.md` is untouched (keeps `@`).
2. The shared task `.tfcore/tasks/generate-html.md` invocation-forms section now notes the dual-harness wrapper forms and the `@` semantic difference.

**Status: ✅ Applied** — OpenCode copy harness-aware; Claude copy unchanged.

---

## Summary table

| # | Gap | Severity | Fix location | Status |
|---|-----|----------|--------------|--------|
| 1 | Mirror "agents" are commands, not agents; WORKFLOW.html:744 claim wrong for OpenCode | Medium | `.opencode/command/TechieFlow/` deleted; scaffold/update scripts; WORKFLOW.html | ✅ Fixed + verified |
| 2 | 33 undescribed duplicate mirror commands | Medium | mirror removed (same as 1) | ✅ Fixed + verified |
| 3 | No `permission` block → git/gh not denied | **High** | `opencode.jsonc` root `permission.bash` | ✅ Fixed + verified |
| 4 | Deprecated `tools`; trblazeui/techierag agent intent dropped | **High** | `opencode.jsonc` (permission + trblazeui/techierag agents with inline prompts) + command frontmatter (`subtask`+`agent`) | ✅ Fixed + verified |
| 5 | `instructions` = YAML; no AGENTS.md auto-load | Medium | `opencode.jsonc` instructions + day-1 §7.2 AGENTS.md emission | ✅ Applied |
| 6 | `/TechieFlow:agents:*` invocation forms invalid in OpenCode | Medium | dual-form sweep across tasks/agents/scripts/tmpl | ✅ Applied |
| 7 | Singular `.opencode/command/` deprecated; dual naming schemes | Low | keep singular (NuGet deploy contract); documented | ✅ Documented decision |
| 8 | `@path` sigil semantic mismatch | Low | OpenCode generate-html copy + shared task note | ✅ Applied |

## Verification performed

- `opencode agent list` (in `/app`): 6 registered agents — `flow-master (primary)`, `flow-analyst`/`flow-architect`/`flow-verifier`/`trblazeui`/`techierag` (`all`) — plus built-ins.
- `opencode debug config` (in `/app`): 29 commands, zero `TechieFlow/*` phantoms, `trblazeui`/`techierag` resolve with `subtask: true` + `agent:`, `generate-html` described, root bash permission denies git/gh.
- `bash -n` clean on scaffold-greenfield.sh, scaffold-brownfield.sh, update-framework.sh.
- `diff -r .tfcore/agents/ .claude/commands/TechieFlow/agents/` clean (Claude mirror in sync).
- Claude Code side: only `.claude/commands/TechieFlow/agents/flow-master.md` changed (the harness-neutral dual-form line, mirroring the canonical `.tfcore/agents/flow-master.md`); nothing else under `.claude/` touched.
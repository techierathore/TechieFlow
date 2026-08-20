# Adapter Design — the harness boundary and per-phase model routing

**Date:** 2026-08-19 · **Scope:** Tasks 3 and 4 · **Status:** design only; nothing here is implemented. Inputs: `Capability-Matrix.md` (facts, cited), `Coupling-Points.md` (what is coupled, by severity).

**Non-negotiables honoured.** (1) No phase-logic restructuring — the adapter *wraps* four coupling points and touches task prose only to swap vocabulary. (2) Additive or behind a flag — the current Claude Code path (`/TechieFlow:agents:<persona> *<command>`, `.claude/settings.json` hooks, `sessions.jsonl`) is unchanged unless the owner opts in. (3) Capabilities that do not exist are named as such; uncertain ones are marked UNVERIFIED with the test that would settle them.

One place where routing presses against constraint (1) is called out explicitly in §4.4 — the inline verifier chain in `build-phase` §6b — with the choice left to the owner.

---

## 1. The adapter in one paragraph

A **harness profile** = three small, deployable things, plus a vocabulary rule:

| Piece | What it is | Lives at | Deployed by |
|---|---|---|---|
| **(a) Guard/telemetry bridge** | Per harness, the *wiring* that makes `.tfcore/hooks/*.sh` run. Claude: the existing `hooks` block in `.claude/settings.json`. OpenCode: a new local plugin `.opencode/plugin/techieflow.ts` that re-creates the Claude hook payload and shells out to the **same** scripts. | `.claude/settings.json`, `.opencode/plugin/techieflow.ts` | scaffold/update scripts (force-refreshed, gitignored) |
| **(b) Harness config (framework-owned)** | The framework's agents, commands, permissions, plugin, instructions and routing, in the harness's own syntax. Claude: `.claude/settings.json` + `.claude/commands/…` (as today) + optional `.claude/agents/tf-*.md`, `.claude/commands/tf/*.md`. OpenCode: a **new framework-owned `.opencode/opencode.jsonc`** (OpenCode merges `.opencode/opencode.json(c)` as a config layer — `packages/opencode/src/config/config.ts:424-434`), leaving the root `opencode.jsonc` to the project. | `.claude/…`, `.opencode/opencode.jsonc` | scripts, force-refreshed; generated from (c) |
| **(c) Routing manifest** | One YAML: phase → tier, tier → model per harness, default off. | `.tfcore/routing.yaml` | part of `.tfcore/` rsync |
| **(d) Vocabulary rule** | Task prose names *roles* ("builder subagent", "the verifier", "the harness's general subagent") and resolves harness forms through one helper, `.tfcore/utils/tf-harness.sh`, instead of Claude tool names and dual-form strings. | 3 task files + 1 helper | `.tfcore/` |

Everything else — phases, gates, the Verifier, personas, templates, telemetry schema, the status gate, the scaffold model — stays exactly where it is.

```
                      framework (harness-neutral)                       harness glue (profile)
 ┌──────────────────────────────────────────────────────┐     ┌─────────────────────────────────────┐
 │ .tfcore/agents/*.md  .tfcore/tasks/*.md  templates    │     │ Claude:  .claude/settings.json hooks │
 │ .tfcore/hooks/{block-git,guard-status,guard-verify}.sh│◄────┤          .claude/commands/TechieFlow │
 │ .tfcore/hooks/metrics-session.sh (Claude-only today)  │     │          .claude/agents/tf-*.md  (new│
 │ .tfcore/utils/tf-emit.sh  telemetry/SCHEMA.md         │     │          .claude/commands/tf/*.md (new)
 │ .tfcore/routing.yaml (new)                            │     │ OpenCode: .opencode/opencode.jsonc   │
 │ .tfcore/utils/tf-harness.sh (new: detect/invoke/tier) │◄────┤           .opencode/plugin/techieflow.ts
 └──────────────────────────────────────────────────────┘     │           .opencode/command/*.md     │
                                                              └─────────────────────────────────────┘
```

---

## 2. What sits **behind** the adapter (covers every *breaks* row in Coupling-Points §1)

### 2.1 Guard bridge for OpenCode — `.opencode/plugin/techieflow.ts` (fixes H-1, H-2; helps H-3, T-1, T-2)

**Why a plugin is now acceptable.** DECISIONS.md §3b rejected plugins because they seemed to need `npm install` in every app. OpenCode 1.18.18 globs `.opencode/{plugin,plugins}/*.{ts,js}` and `import()`s them directly (`config/plugin.ts:18-30`, `config.ts:462-465`, `plugin/loader.ts:139`); a file plugin skips the npm compatibility gate (`loader.ts:123-131`). The only install is OpenCode's own background `npm install @opencode-ai/plugin` for types — which is what already put `.opencode/package.json` + `node_modules/` in this repo. So a plugin is a *copied file*, exactly like a hook script. (Capability-Matrix Q5.)

**Design rule: the plugin contains no policy.** It is a payload translator + process runner. All three guards keep living in `.tfcore/hooks/*.sh`, unchanged, and keep reading the Claude-shaped stdin JSON they already parse. The plugin:

1. On `tool.execute.before({tool, sessionID, callID}, {args})` — for `bash`, `edit`, `write`, `apply_patch` — builds `{"hook_event_name":"PreToolUse","tool_name":<mapped>,"tool_input":<mapped>,"cwd":directory,"session_id":sessionID}` and runs the matching script(s) with `CLAUDE_PROJECT_DIR=<worktree>` set, via the plugin's `$` (Bun shell). Exit 2 → `throw new Error(stderr)` (blocks the call and returns the guard's message to the model, `processor.ts:416-419,186-199`; documented pattern `plugins.mdx:250-255`). Any other exit / missing python3 / script absent → allow (fail-open, same posture as today).
2. On `event` `message.updated` (assistant) — accumulate `tokens`, `cost`, `modelID` per `sessionID`; on `session.status` → `idle` for a **root** session (and at plugin `dispose`) emit one `sessions.jsonl` record through `tf-emit.sh sessions` with `harness:"opencode"` and **real `cost_usd`**; children are rolled up into the root by `parentID` (Telemetry-Hooks.md §2). Also write the **session pointer file** (§2.4) so run-level emits can find this session in SQLite.
3. On `shell.env` — inject `TF_HARNESS=opencode`, `TF_SESSION_ID`, `TF_PROJECT_DIR` into every bash tool process (`tool/shell.ts:417-425`) so `tf-emit.sh` never has to guess (T-2).

**Payload mapping (from source, Matrix f):**

| OpenCode tool / args | Claude `tool_name` / `tool_input` the scripts expect | Guard |
|---|---|---|
| `bash {command}` (`tool/shell/id.ts:16`) | `Bash {command}` | `block-git.sh` (compound-safe: it greps the raw payload) |
| `edit {filePath, oldString, newString}` (`tool/edit.ts:48-50`) | `Edit {file_path, old_string, new_string}` | `guard-status.sh`, `guard-verify.sh` |
| `write {filePath, content}` (`tool/write.ts:21-22`) | `Write {file_path, content}` | same |
| `apply_patch {patchText}` (`tool/apply_patch.ts:19`) | no Claude analogue → map to `Write` with `file_path` parsed from the patch header and `content` = patch text; **UNVERIFIED** that the guards' regexes read a unified-diff body sensibly — simplest safe rule: deny `apply_patch` on `*-Checklist.md` / `PROJECT-STATUS.md` via `permission` instead (plain config, no code) | — |

**Size:** ~120 lines of TypeScript, zero runtime dependencies beyond `@opencode-ai/plugin` types (which OpenCode installs itself). It is *additive*: Claude Code never loads `.opencode/`.

**UNVERIFIED, with tests:** (i) `tool.execute.before` fires for the `edit` tool invoked by a subagent session (expected yes — `session/tools.ts:106-125` is the common path). (ii) `throw` inside the hook blocks without killing the session (expected yes per docs). (iii) `shell.env` output env reaches the child process (expected yes). Each is a five-minute check in a scratch repo with `opencode run`.

### 2.2 Framework-owned OpenCode config — `.opencode/opencode.jsonc` (fixes D-1; carries routing)

Today the root `opencode.jsonc` is per-project *and* the only carrier of framework config, so `update-framework.sh` must preserve it and the fixes never propagate. The Claude side solved the same problem long ago: `.claude/settings.json` is the *framework's* canonical block, refreshed by default, and project approvals live in `settings.local.json`.

Mirror that: the framework owns `.opencode/opencode.jsonc` (already gitignored via `.opencode/`), containing `permission`, `agent.*` (with `{file:./.tfcore/agents/…}` prompts as now), `command.*`, `instructions`, `plugin`, and the `model:` fields generated from `routing.yaml`. The root `opencode.jsonc` stays for project-specific additions (extra agents, MCP, LSP). **Precedence UNVERIFIED:** the merge order read from source is project walk-up *then* `.opencode/*` (`config.ts:356-534`), which would make the framework file win on conflicting keys; if runtime shows the reverse, the framework can instead refresh a fenced `// tf-managed:begin … end` block inside the root file. Either way the scripts stop *preserving* the framework's part of the config. Existing apps: `update-framework.sh` deploys the new file and leaves the old root file untouched (warns on duplicated agent keys).

Also expressed here, not in code: `permission.bash` gains `"rm *": "ask"`, `"rmdir *": "ask"`, `"sudo *": "ask"` (P-1); `permission.task` on `flow-verifier`/`flow-analyst` restricts which subagents each may spawn (`tool/registry.ts:265-269`).

### 2.3 Vocabulary neutralisation in three files (fixes S-1; no logic change)

| Today (Claude dialect) | Neutral wording | Harness resolution |
|---|---|---|
| `build-phase.md:65` "spawn general-purpose **`Agent`** calls (one per cluster)" | "spawn one **builder subagent** per cluster — `tf-builder` if the harness registers it, otherwise the harness's general subagent" | Claude: Agent tool, `subagent_type: tf-builder\|general-purpose`; OpenCode: `task`, `subagent_type: tf-builder\|general` |
| `build-phase.md:63-64` "invoke `/trblazeui` as a sub-agent (Claude Code `/trblazeui …`, OpenCode `/trblazeui …`)" | "delegate the cluster to the **trblazeui subagent**" | Claude: Agent tool with the persona pasted (as today) or `subagent_type: trblazeui` once `.claude/agents/trblazeui.md` exists; OpenCode: `task subagent_type: trblazeui` (registered, `mode: all`) |
| `verify-phase.md:166` "spawn a parallel **`Agent`** (subagent_type=general-purpose)" | "spawn a parallel **test-writer subagent** (`tf-test-writer` if registered, else general)" | as above |
| `SCHEMA.md:87` `subagents` enum `general-purpose` | add `general` and the `tf-*` names | — |
| Dual-form next-command strings (N-1) | `$(bash .tfcore/utils/tf-harness.sh invoke verifier "*verify all {App}")` **or** keep dual-form (cosmetic) | helper prints the right form for the detected harness |

Three edits, mirrored once to `.claude/commands/TechieFlow/tasks/`. The parallel-fan-out rule stays as written; OpenCode's concurrency of multiple `task` calls in one step is UNVERIFIED (`task.ts:98-101` gates *background* tasks behind `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS`) — if sequential, the phase still completes, only slower.

### 2.4 `tf-harness.sh` — one deterministic answer-machine (supports T-2, N-1, routing, telemetry)

```
tf-harness.sh detect            # claude-code | opencode | unknown   (env TF_HARNESS first, then tf-emit's walk)
tf-harness.sh root              # project root (CLAUDE_PROJECT_DIR | TF_PROJECT_DIR | walk-up)
tf-harness.sh invoke <agent|task> "<args>"   # prints the harness's slash form
tf-harness.sh tier <phase>      # prints the declared tier from routing.yaml
tf-harness.sh model <tier>      # prints the harness's model id for a tier (or "inherit")
tf-harness.sh session           # prints {session_id, store, path} from the session pointer file
```

The **session pointer file** `.tfcore/.session/<harness>.json` is written by the harness bridge (Claude: a `SessionStart`/`UserPromptSubmit` hook that records `session_id` + `transcript_path`; OpenCode: the plugin records `session_id` + `opencode.db` path). `tf-emit.sh` reads it to attribute tokens to a run (Telemetry-Hooks.md §3). Gitignored; last-writer-wins is acceptable for a single-owner repo and is stated as such.

### 2.5 Context layer (fixes C-1, C-2) — additive

- Day-1 writes the **content** into `AGENTS.md` (harness-neutral: required reading, hard rules, command syntax table — what `app-claude-md-tmpl.md` §1–§3 hold today) and writes `CLAUDE.md` as `@AGENTS.md` plus the Claude-only sections (permissions/tool preference). Claude resolves `@imports` (memory docs); OpenCode reads `AGENTS.md` and ignores `CLAUDE.md` (`instruction.ts:122-133`) — which is now correct rather than lossy. `AGENTS.md` is committed; `CLAUDE.md` stays gitignored as today.
- `opencode-operating-contract.md` §"Build-Phase Completion Contract" and §"Evidence Discipline" are harness-neutral doctrine; move them into `_smoke-test-policy.md`/`build-phase.md` (already 80% duplicated there) and keep only the runtime classification in the OpenCode-only file. Optional; cosmetic.

---

## 3. What stays **in framework code** (unchanged)

- All 29 tasks, 4 personas, 3 shared rules, the templates, the build ladder, the status gate, the Verifier's §1–§8, the gates (§4a/§4b/§4c), the MISS LIST, `refresh-status`, `triage-issues`.
- The three guard scripts and the session-metrics script — unchanged logic, now reachable from two wirings.
- `tf-emit.sh`, `tf-metrics.sh`, `install-metrics.sh`, `pre-commit`, `SCHEMA.md` (extended, Telemetry-Hooks §4 — additive fields).
- The scaffold/update scripts' *structure*; they gain one more force-refreshed file per harness and the generation step for `model:` fields.

## 4. What is **deliberately left harness-specific** (not worth abstracting)

| Left as-is | Why abstracting it is not worth it |
|---|---|
| Permission **syntax** (`Bash(git *)` vs `permission.bash`) | Two ~30-line canonical blocks already exist and are force-refreshed; a generator would be more code than both blocks. |
| Session resume / naming / TUI keybinds / `/model` vs `/models` | User-facing harness UX; the framework never drives it. |
| Headless CLI (`claude -p` vs `opencode run --command`) | Used only by the owner's shell, not by tasks; documented in the deployment guide. |
| The `@` sigil, `$ARGUMENTS`/`$N`, `!`cmd`` | Task files pass args as trailing text already; no framework file needs positional args. |
| Bash-guard depth (Claude's parser vs OpenCode's tree-sitter) | Both parse compounds natively (Matrix e); `block-git.sh` is the belt, the harness deny is the braces. |
| Cost display (`/usage` vs `opencode stats`) | Telemetry reads the store, not the UI. |
| The `*agent {name}` persona transformation | Rare in the owner's loop; OpenCode users press Tab. Documented, not bridged. |
| Docker launcher, `winrun` SSH bridge, `TF_OPENCODE_DOCKER` branches | Retained on disk as a fallback; retired from the recommended path (OpenCode-Deployment-Guide). Not an abstraction target. |
| `.claude/commands/TechieFlow/` byte-identical mirror | Claude needs a file per command; OpenCode needs `{file:}` refs. Two deployment shapes, one source. Keep. |
| MCP, LSP, formatters, share, OTel collectors | Out of framework scope. |

---

## 5. Model routing design (Task 4)

### 5.1 Facts that bound the design (Capability-Matrix row b)

- **Both** harnesses bind a model to a *subagent definition* and to a *command definition*. Neither lets the running agent re-route its own next step from inside a turn, and neither exposes a per-tool-call model. A plugin cannot change the model (`chat.params` has no model output; `permission.ask` is dead). **Routing is therefore declared at the harness boundary and observed by telemetry — never enforced mid-turn.**
- Claude: a command's `model:` is **turn-scoped** (reverts on the next prompt); `context: fork` + `agent:` runs the command as a subagent with that model; subagent `model:` values are `sonnet|opus|haiku|inherit|<id>`; `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` pin the aliases. ([skills](https://code.claude.com/docs/en/skills.md), [sub-agents](https://code.claude.com/docs/en/sub-agents.md), [env-vars](https://code.claude.com/docs/en/env-vars.md))
- OpenCode: agent `model`, command `model` (**command beats agent**, `prompt.ts:1411-1419`), `task` uses the subagent's model else the parent's (`task.ts:174-184`); `opencode run --command <name> --model p/m`; the command's model is written to the session row (`prompt.ts:672-687`) — in the TUI the next plain send carries the TUI's own selection (UNVERIFIED), via SDK/`run -c` it persists.

### 5.2 Declaration — `.tfcore/routing.yaml` (new, default off)

```yaml
# TechieFlow model routing. enabled:false = nothing changes anywhere.
enabled: false
tiers:                       # abstract; harness profiles map these to ids
  frontier:   {claude: opus,   opencode: anthropic/claude-opus-4-7}     # examples — owner chooses
  standard:   {claude: sonnet, opencode: anthropic/claude-sonnet-4-6}
  economy:    {claude: haiku,  opencode: anthropic/claude-haiku-4-5}
  # OpenCode Go/Zen users substitute e.g. opencode/kimi-k3, opencode/glm-5.3 (ids per `opencode models`)
phases:                      # one line each; tier names above or `inherit`
  day1-greenfield: frontier
  day1-brownfield: frontier
  author-brd:      frontier
  amend-docs:      frontier
  mockups:         standard
  split-brd:       standard
  build-phase:     standard         # orchestrator; builders below
  fix-issues:      frontier         # diagnosis; fixes fan out to builders
  triage-issues:   standard
  verify-phase:    standard
  devguide:        standard
  productguide:    economy
  handoff-phase:   economy
  refresh-status:  economy
  render-workflow-docs: economy
  generate-html:   economy
  metrics-report:  economy
subagents:
  tf-builder:      standard         # FN/NFR cluster builders (replaces ad-hoc general-purpose)
  trblazeui:       standard
  techierag:       standard
  tf-test-writer:  standard         # verify §4 spec generation
  tf-explorer:     economy          # read-only scans (devguide OBSERVE, index-docs)
effort:                             # Claude-only knob, optional
  frontier: high
  standard: medium
  economy:  low
```

A phase *declares* a tier, never a model. Harness model ids live in the `tiers` map (and can be overridden per machine by env: Claude's `ANTHROPIC_DEFAULT_*_MODEL`; OpenCode's root `opencode.jsonc`).

### 5.3 Honouring it in **Claude Code** — additive, opt-in

Generated by the scripts from `routing.yaml` when `enabled: true`:

1. **Routed phase commands** `.claude/commands/tf/<phase>.md` — a thin wrapper per phase with frontmatter `model: <tier model>`, `effort: <tier effort>`, `description`, and a body: "Load `.tfcore/agents/<owner>.md` for its core principles (git ban, smoke policy, status gate), then execute `.tfcore/tasks/<phase>.md` with arguments: $ARGUMENTS." Invoked as `/tf:verify-phase all MyApp`. The whole turn — including every tool call and the inline verifier chain — runs on the tier model; the next prompt reverts to the session model (docs). The existing `/TechieFlow:agents:<persona> *<phase>` path is untouched (`.tfcore/tasks/*.md` stay frontmatter-free, so the byte-identical mirror rule holds).
2. **Tier-bound subagents** `.claude/agents/tf-builder.md`, `tf-test-writer.md`, `tf-explorer.md`, and `trblazeui.md`/`techierag.md` (bodies = "read the persona file at `.claude/<lib>.md` and adopt it" — same trick as `opencode.jsonc` uses, since the persona is NuGet-deployed) with `model:` from the manifest. `build-phase` §3 then says "builder subagent (`tf-builder` if registered)". This is the **largest cost lever**: builders do most of the token work and today inherit the orchestrator's model.
3. **Optional**: `context: fork` + `agent: tf-verifier` on `/tf:verify-phase` to run a standalone verify as a subagent (background, own model). Not for the chained case — see §5.5.

Nothing here changes a phase's steps; it changes which model the harness starts the turn/subagent on.

### 5.4 Honouring it in **OpenCode** — additive, opt-in

Generated into the framework-owned `.opencode/opencode.jsonc`:

1. `command.techieflow:tasks:<phase>.model` = tier model (command beats agent, `prompt.ts:1411-1419`) — invoked as `/techieflow:tasks:verify-phase all MyApp` (or, **headless**, `opencode run --command techieflow:tasks:verify-phase --model <p/m> "all MyApp"`).
2. `agent.flow-verifier.model`, `agent.flow-analyst.model`, `agent.flow-master.model` (persona-level defaults when the phase is typed as `*verify …` inside a persona session), and `agent.trblazeui/techierag/tf-builder/tf-test-writer/tf-explorer.model` for subagents (`task.ts:174-184`).
3. The TUI shows the active model per agent; **Tab** cycles primary agents, each remembering its own model (`local.tsx:164-179`) — the "bind different agents to different models" feature the owner heard about on Discord is exactly this (see §5.7).

**Caveat (source-verified):** a command's model becomes the session's stored model. In the TUI this is harmless (the TUI re-sends its selection); for `opencode run -c` / SDK callers that omit `model`, a later prompt inherits the last command's tier. Mitigation: every `tf` command declares a model, and the persona agents declare theirs.

### 5.5 What is **not** possible, and the honest options

| Want | Claude Code | OpenCode | Options |
|---|---|---|---|
| Change tier **mid-turn** (e.g. build on standard, then the chained verify on economy) | No — the turn runs on one model; `/model` is a user action. | No — model fixed when the message is created (`prompt.ts:646`); plugin cannot change it. | (a) **Accept** that the inline verifier chain (build-phase §6b) inherits the build tier — it is the same `standard` tier in the proposed map, so nothing is lost today. (b) Make §6b *delegate* to a `tf-verifier` subagent with its own model — a one-paragraph change to §6b ("execute inline" → "execute via the verifier subagent and wait"); the ledger/guard still work because the subagent performs the steps and writes `docs/.last-verify.json`. **This is the one routing change that touches phase wording; left to the owner.** (c) Split sessions: `/tf:build-phase` then `/tf:verify-phase` as separate invocations — already supported, costs the owner one extra prompt. |
| Per-**tool-call** tier (e.g. cheap model for `dotnet build` narration) | No. | No (`task.ts:43-62`). | Not a real loss: deterministic steps should be scripts, not cheaper prompts (§5.6). |
| **Enforce** a tier (prevent the owner/agent from running a phase on frontier) | No (`availableModels` is org-level). | No. | Telemetry records the *observed* model per run (Telemetry-Hooks §3) so drift is visible. |
| Route by **REQ class** within one build (UI clusters on standard, RAG on frontier) | Yes via subagents (`trblazeui`/`techierag` models). | Yes via agent models. | Already covered by §5.3(2)/§5.4(2). |

### 5.6 Starting tier map — and the challenge to the working hypothesis

Hypothesis: *planning/architecture need frontier; scaffolding, refactoring and test generation don't; gates should be deterministic wherever possible.*

| Phase / role | Tier | One-line justification |
|---|---|---|
| `day1-brownfield`, `day1-greenfield`, `author-brd`, `amend-docs` | **frontier** | Requirements and architecture errors are the most expensive to discover late; brownfield also needs whole-codebase comprehension. *Agrees with hypothesis.* |
| `mockups` | **standard** | Bounded design from a known component catalog; frontier adds little over a vision-capable standard model. *Slight challenge:* the owner may find greenfield first-pass mockups want frontier — make it the easiest override. |
| `split-brd` | **standard** | BRD → checklist rows is a transformation with acceptance-criteria authoring; not mechanical enough for economy (bad acceptance bullets poison every later gate). |
| `build-phase` (orchestrator) | **standard** | Clustering + fan-out + FIX-mode detection is judgement, but the expensive judgement already lives in the BRD/architecture; **challenge to hypothesis:** the *orchestrator* is not where frontier pays; the *builders* are where tokens go, and they should be standard, not economy — "scaffolding doesn't need frontier" is true, "doesn't need standard" is not: a cheap builder that ships a blank table costs a full verify cycle. |
| `tf-builder`, `trblazeui`, `techierag` (subagents) | **standard** | As above; economy builders measurably raise `mode:"fix"` re-entries (rework ratio is the metric that will prove or refute this within a month). |
| `fix-issues` | **frontier** | Root-causing from screenshots + repro is diagnosis; the fix itself fans out to standard builders. *Challenge:* the hypothesis lumps "refactoring" with scaffolding — the *triage* half of fixing is the frontier part. |
| `triage-issues` | **standard** | Reproduce + classify + log; no code. |
| `verify-phase` | **standard**, with the **gates themselves deterministic** | §4a bbox/data checks, §4c `tf-perf.sh`, standards greps, test *runs* are scripts — make the verdict computation deterministic and keep the model for test *generation* (§4) and the screenshot eyeball (§4b), which needs vision and judgement. *Agrees with "gates deterministic"; disagrees that the whole phase can be economy.* |
| `tf-test-writer` | **standard** | Spec generation from acceptance criteria is code generation that must actually assert the right thing. |
| `devguide` | **standard** | Large code-tracing; economy models lose the thread across page→service→proc. Fan-out per role already bounds cost. |
| `productguide`, `handoff-phase`, `render-workflow-docs`, `generate-html`, `refresh-status`, `metrics-report` | **economy** | Mechanical doc assembly; `metrics-report` calls `tf-metrics.sh --report --json` and formats; `refresh-status` gathers evidence (build + mtimes + tables). **Reassess `refresh-status`**: the *reconcile* judgement (which REQ row is trustworthy) is occasionally subtle — if recovery notes look wrong, promote to standard. |
| `tf-explorer` | **economy** | Read-only scans. |
| Gates (`guard-*`, perf, acceptance runs, verdict arithmetic) | **none (script)** | Already scripts; the design direction is to move more of verify §6 arithmetic into `tf-emit.sh --next-attempt`-style helpers. |

Predicted effect: the two largest token sinks (builder subagents; verify test generation) move from "whatever the session runs on" to standard; frontier is reserved for five phases the owner runs a handful of times per project. The rework ratio (`runs.mode:"fix"`) and first-pass rate per tier are the acceptance test for this map — Telemetry-Hooks.md records `tier` and `model` per run precisely so this table can be corrected with data instead of opinion.

### 5.7 "Can I bind different agents to different models?" — both harnesses, with examples

**OpenCode — yes (the Discord claim is correct).** Config or markdown agent with `model`:

```jsonc
// opencode.jsonc
"agent": {
  "flow-verifier": { "prompt": "{file:./.tfcore/agents/verifier.md}", "mode": "all",
                     "model": "anthropic/claude-sonnet-4-6" },
  "tf-builder":    { "description": "FN/NFR cluster builder", "mode": "subagent",
                     "model": "opencode/kimi-k3" }
}
```
or `.opencode/agent/tf-builder.md` with frontmatter `model: opencode/kimi-k3`. Verify with `opencode agent list`; Tab cycles primaries; `task` spawns subagents on their own model (`task.ts:174-184`). Per-command binding: `"command": {"techieflow:tasks:verify-phase": {"template": "{file:…}", "model": "…"}}`.

**Claude Code — yes, the equivalent exists.** Subagent file with `model`:

```markdown
---
name: tf-builder
description: Builds one REQ cluster (FN/NFR) to the coding standards; smokes it; never runs git.
model: sonnet
tools: Read, Edit, Write, Bash, Glob, Grep
---
Read `.tfcore/tasks/_smoke-test-policy.md` … (body)
```
(`.claude/agents/tf-builder.md`; values `sonnet|opus|haiku|inherit|<id>`; `/agents` lists them.) Per-command binding: `.claude/commands/tf/verify-phase.md` with `model: sonnet` (turn-scoped) and optionally `context: fork` + `agent: tf-verifier`. Session-wide agent: `claude --agent <name>`. Pin aliases to ids with `ANTHROPIC_DEFAULT_SONNET_MODEL` etc. ([sub-agents](https://code.claude.com/docs/en/sub-agents.md), [skills](https://code.claude.com/docs/en/skills.md), [env-vars](https://code.claude.com/docs/en/env-vars.md))

Guidance for TechieFlow: declare tiers once in `routing.yaml`; let the scripts emit both forms; check with `opencode agent list` and `/agents`; read the observed `model` in `runs.jsonl` after the first routed run to confirm the binding actually took.

---

## 6. Rollout — flags and order (no implementation in this session)

1. `routing.yaml` with `enabled: false`; `tf-harness.sh`; the OpenCode plugin; the framework-owned `.opencode/opencode.jsonc`; three vocabulary edits. **Claude Code behaviour unchanged** (the wrapper commands and `tf-*` agents are not generated until `enabled: true`, and even then the old invocation path still works).
2. Run the UNVERIFIED tests (§2.1, §2.2, compound-git, TUI command-model persistence) on the owner's WSL OpenCode.
3. Flip `enabled: true` on one app; compare `runs.jsonl` `tier/model/tokens` for two weeks; adjust the map.

## 7. Council of experts — adversarial review

- **Framework owner (constraint 1):** "§5.5(b) edits build-phase §6b. That is phase wording." — Correct, and it is the *only* such touch, presented as an option with (a) and (c) requiring nothing. The recommendation is (a) now (same tier anyway), (b) only if telemetry shows verify dominating cost.
- **Harness engineer:** "A plugin that shells out to bash/python on every edit/write/bash call adds latency." — Three guards already run on every such call under Claude Code (same scripts, same cost); the plugin adds one process spawn per call, tens of milliseconds. Fail-open keeps it from ever blocking a session on its own failure.
- **Red team:** "The plugin is the new single point of failure for OpenCode guardrails, and it is TypeScript the owner does not write." — 120 lines, no policy, no dependencies; the policy stays in the bash scripts the owner already maintains. If the plugin is absent, OpenCode degrades to exactly today's state, never worse.
- **Cost accountant:** "Your tier map puts builders on standard. The owner's hypothesis was *cheaper*." — Deliberate, and testable: rework ratio by tier will show whether economy builders pay for themselves. The map is a starting point with a measurement attached, not a belief.
- **OpenCode maintainer:** "`.opencode/opencode.jsonc` precedence over the root file is your inference." — Flagged UNVERIFIED with the fallback (fenced managed block). Either way, the principle — the framework refreshes its own config — is the decision; the file location is a detail.
- **Claude Code sceptic:** "Turn-scoped `model:` means if the owner types a follow-up ('also fix X') the phase continues on the session model." — True, and visible in telemetry (observed model ≠ tier model on that run). It is also the *desired* behaviour for conversational follow-ups; routed phases are meant to be invoked whole.
- **Minimalist:** "Four new files is not 'smallest'." — The alternatives considered were smaller and wrong: (i) prose-only ("OpenCode agents, please behave") — the 2026-07-09 incident; (ii) `.tfcore/tasks` frontmatter — breaks the byte-identical mirror and leaks into OpenCode prompts; (iii) one generic "harness abstraction layer" DSL — more code than both harness configs combined and a third dialect to maintain. See DECISIONS.md entry.

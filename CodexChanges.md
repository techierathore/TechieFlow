# TechieFlow changes required for Codex

**Assessment date:** 2026-08-24  
**Scope:** the repository's canonical `.tfcore/` framework, its Claude Code and OpenCode adapters, the three scaffold/update scripts, routing, telemetry, unattended goal mode, library personas, and the current official Codex feature set.

**Implementation status (updated 2026-08-24):** the repository changes described here are implemented. The public command and behavior references are synchronized in `README.md`, `WORKFLOW.html`, `.tfcore/user-guide.md`, and `docs/TechieFlow-Routing-Guide.md`; the durable session record is in `WorkFlow-Context.md`. The acceptance checklist below remains a release-validation checklist for exercising the adapter in real applications, not a list of missing source changes.

## 1. Executive conclusion

TechieFlow can run on Codex, including its specialist agents, build/verify fan-out, mechanical write guards, MCP-backed tools, model tiers, and non-interactive runs. The workflow content in `.tfcore/` does not need to be rewritten wholesale.

It does need a third harness adapter. Copying either the Claude or OpenCode integration unchanged will not work:

- Codex uses root/nested `AGENTS.md` for durable repository instructions.
- Reusable, repository-shared commands should be Codex skills under `.agents/skills/`; deprecated custom prompts are user-local and are the wrong distribution mechanism.
- Specialist subagents are project TOML files under `.codex/agents/`.
- Project settings and lifecycle hooks belong in `.codex/config.toml` and/or `.codex/hooks.json` and run only after the project and hook definitions are trusted.
- Scripted execution uses `codex exec`, with `--json` for event/usage capture and `codex exec resume` for continuation.

The recommended implementation is therefore:

```text
.tfcore/                         canonical workflow content (keep)
        |
        +-- Claude adapter       existing .claude/
        +-- OpenCode adapter     existing opencode.jsonc + .opencode/
        +-- Codex adapter        new .codex/ + .agents/skills/ + AGENTS.md
```

## 2. What was reviewed

The assessment started with `WorkFlow-Context.md` and then inspected the repository-owned code and documentation, excluding generated/vendor contents under `.opencode/node_modules/`. In particular:

- canonical agents, tasks, templates, checklists, data, hooks, telemetry and utilities under `.tfcore/`;
- `.claude/commands/TechieFlow/`, `.claude/settings.json`, and the library command shims;
- `opencode.jsonc`, `.opencode/command/`, and `.opencode/plugin/techieflow.js`;
- `scaffold-brownfield.sh`, `scaffold-greenfield.sh`, and `update-framework.sh`;
- `tf-harness.sh`, `tf-routing.sh`, `tf-routing-bind.sh`, `tf-goal.sh`, `tf-yolo.sh`, and `tf-emit.sh`;
- the capability, coupling, adapter, routing, telemetry, deployment, and decision documents.

Current Codex behavior was checked against the official Codex manual fetched on 2026-08-24. Relevant official pages are [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [skills](https://learn.chatgpt.com/docs/build-skills), [subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents), [hooks](https://learn.chatgpt.com/docs/hooks), [configuration](https://learn.chatgpt.com/docs/config-file/config-reference), [MCP](https://learn.chatgpt.com/docs/extend/mcp), and [non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).

## 3. Capability mapping

| TechieFlow concern | Claude/OpenCode implementation now | Codex implementation |
|---|---|---|
| Always-loaded operating rules | `CLAUDE.md`, OpenCode `instructions`, root `AGENTS.md` | Root `AGENTS.md`; nested overrides only where needed |
| User-invocable workflow commands | Claude command mirrors; OpenCode config commands | Repository skills in `.agents/skills/<name>/SKILL.md` |
| Specialist personas | Claude command/agent files; OpenCode configured agents | `.codex/agents/*.toml` custom agents |
| Builder/test/explorer fan-out | Task/Agent tools | Native Codex subagent tools; explicitly enabled by skill/`AGENTS.md` instructions |
| Per-subagent model and effort | Claude/OpenCode agent config | `model` and `model_reasoning_effort` in custom-agent TOML |
| Per-phase model | generated command binding | launcher-selected `codex exec -m ... -c model_reasoning_effort=...`, or phase-specific custom agent |
| Git/status/verify enforcement | Claude `PreToolUse`; OpenCode JS bridge | Native Codex `PreToolUse` hooks plus Codex exec-policy rules |
| Session lifecycle | Claude hooks; OpenCode plugin events | Native `SessionStart`, `SessionEnd`, `SubagentStart`, `SubagentStop`, `Stop` hooks |
| Token telemetry | transcript parser / OpenCode events | `codex exec --json` `turn.completed.usage`; optional session rollout/OTel adapter for interactive sessions |
| Unattended runs | `tf-goal.sh` drives `claude -p` or `opencode run` | Extend it to drive `codex exec` and `codex exec resume` |
| External tools | harness-specific MCP config | `[mcp_servers.*]` in Codex config or a distributable Codex plugin |
| Distribution | scaffolded hidden harness folders | Scaffold `.codex/`, `.agents/skills/`, and Codex additions to `AGENTS.md` |

## 4. Required repository changes

### 4.1 Add a repository-scoped Codex configuration

Create `.codex/config.toml`. It should contain only repository-safe settings; authentication, provider definitions, profiles, notifications, and OTel export belong in the user's `~/.codex/config.toml` because Codex ignores those keys in project-local config.

The project config should:

- enable multi-agent support;
- set an appropriate maximum concurrent thread count for TechieFlow fan-outs;
- register each custom role by description and config file;
- configure `workspace-write` as the normal sandbox, with only the app repository and genuinely required external directories writable;
- use `on-request` for ordinary interactive sessions; unattended launches should override this with an explicit non-interactive policy;
- configure project hooks, preferably by referencing `.codex/hooks.json` rather than duplicating hook definitions;
- contain MCP entries only when they are portable and non-secret.

Illustrative shape (model IDs are deliberately not hard-coded here; generate them from `routing.yaml`):

```toml
[agents]
enabled = true
max_concurrent_threads_per_session = 8

[agents.flow_master]
description = "TechieFlow orchestrator and workflow router."
config_file = "agents/flow-master.toml"

[agents.analyst]
description = "Business analysis, discovery, BRDs, and mockups."
config_file = "agents/analyst.toml"

[agents.architect]
description = "Architecture and technical design specialist."
config_file = "agents/architect.toml"

[agents.verifier]
description = "Independent requirement verifier and evidence grader."
config_file = "agents/verifier.toml"
```

Do not put `approval_policy = "never"` into the shared project default. That would silently reject approval requests during normal interactive use. Pass it only in a controlled unattended invocation after the sandbox and rules are correct.

### 4.2 Convert the four canonical personas to Codex custom agents

Generate these project files:

```text
.codex/agents/flow-master.toml
.codex/agents/analyst.toml
.codex/agents/architect.toml
.codex/agents/verifier.toml
```

Also generate the routed implementation roles already emitted for Claude/OpenCode when routing is enabled:

```text
.codex/agents/tf-builder.toml
.codex/agents/tf-test-writer.toml
.codex/agents/tf-explorer.toml
.codex/agents/trblazeui.toml       # only when the library persona exists
.codex/agents/techierag.toml       # only when the library persona exists
```

Each file requires `name`, `description`, and `developer_instructions`. Convert the YAML persona content in `.tfcore/agents/*.md` into plain developer instructions; do not ask the Codex subagent to “activate” itself, greet, print help, or halt. Those activation rituals were designed for command-driven primary personas and are counterproductive in a spawned Codex worker.

Preserve these behavioral requirements in the converted instructions:

- dependency paths resolve under `.tfcore/`;
- task files are executable workflow specifications;
- the git/gh prohibition;
- verifier independence and evidence requirements;
- triage is analyze-only;
- smoke/build/verify must be executed by the agent;
- checklist and PROJECT-STATUS update gates;
- library feedback and runtime-observation rules.

Codex custom agents may set `model`, `model_reasoning_effort`, `sandbox_mode`, MCP servers, and skill configuration. Use `read-only` for `tf-explorer` and other genuinely read-only roles. Do not give `verifier` read-only mode because it must update verdict artifacts.

### 4.3 Convert tasks into repository skills

Create one skill directory for every user-facing TechieFlow workflow. At minimum:

```text
.agents/skills/techieflow-day1-brownfield/SKILL.md
.agents/skills/techieflow-day1-greenfield/SKILL.md
.agents/skills/techieflow-amend-docs/SKILL.md
.agents/skills/techieflow-author-brd/SKILL.md
.agents/skills/techieflow-mockups/SKILL.md
.agents/skills/techieflow-split-brd/SKILL.md
.agents/skills/techieflow-build/SKILL.md
.agents/skills/techieflow-verify/SKILL.md
.agents/skills/techieflow-fix-issues/SKILL.md
.agents/skills/techieflow-triage-issues/SKILL.md
.agents/skills/techieflow-devguide/SKILL.md
.agents/skills/techieflow-productguide/SKILL.md
.agents/skills/techieflow-handoff/SKILL.md
.agents/skills/techieflow-refresh-status/SKILL.md
.agents/skills/techieflow-generate-html/SKILL.md
.agents/skills/techieflow-metrics/SKILL.md
.agents/skills/techieflow-yolo/SKILL.md
```

Keep `.tfcore/tasks/*.md` canonical. A generated `SKILL.md` should be a thin loader that:

1. declares a precise name and trigger description;
2. reads the complete corresponding `.tfcore/tasks/<task>.md` when invoked;
3. reads only the dependencies named by that task;
4. states which custom agent should own or assist with the work;
5. preserves interactive elicitation unless YOLO mode is active;
6. translates old invocation prose (`*verify`, `/TechieFlow:...`, `/flow-...`) into the Codex skill name or natural-language delegation.

Do not use `~/.codex/prompts` as the main port. Codex custom prompts are deprecated, user-local, top-level-only, and unsuitable for a framework deployed into multiple application repositories.

The framework can keep documenting the familiar `*command` vocabulary as a conceptual alias, but Codex will not register those literal star commands. User-facing Codex examples should use either `$techieflow-verify ...` (explicit skill invocation where supported) or plain language such as “Use the techieflow-verify skill for AppName, scope all.”

### 4.4 Make `AGENTS.md` the Codex operating contract

The day-1 tasks already create a harness-neutral root `AGENTS.md`; expand its template (`.tfcore/templates/v4custom/app-agents-md-tmpl.md`) so it is sufficient for Codex without loading `CLAUDE.md`.

Add a concise “TechieFlow under Codex” section that tells Codex to:

- read `.tfcore/core-config.yaml` and the relevant skill/task, not the whole framework, before a workflow;
- use `.agents/skills/techieflow-*` for framework phases;
- delegate only when the user or the applicable skill/`AGENTS.md` explicitly requests subagents (this matches current Codex delegation behavior);
- use the registered `tf-builder`, `tf-test-writer`, `tf-explorer`, `trblazeui`, and `techierag` roles where the task specifies them;
- never run git or gh;
- obey the artifact-location, local-only verification, status, and verified-verdict rules;
- treat `.tfcore/` as canonical and `.codex/`/`.agents/skills/` as generated adapter output.

Keep `AGENTS.md` short enough to remain always-loaded. Detailed process belongs in skills and `.tfcore/tasks`, using Codex's progressive disclosure.

### 4.5 Port mechanical guards to native Codex hooks

Create `.codex/hooks.json` with these mappings:

| Codex event/matcher | Existing script or new adapter | Purpose |
|---|---|---|
| `PreToolUse`, `Bash` | `.tfcore/hooks/block-git.sh` through a payload adapter | Block all git/gh access and destructive forms according to TechieFlow policy |
| `PreToolUse`, `Edit|Write|apply_patch` | `guard-status.sh` and `guard-verify.sh` through a payload adapter | Mechanically validate status/checklist writes |
| `SessionStart` and `UserPromptSubmit` | Codex-aware `session-pointer.sh` | Maintain a Codex session pointer |
| `SessionEnd` | Codex-aware telemetry adapter | Emit session telemetry when reliable usage is available |
| `SubagentStart`/`SubagentStop` | optional telemetry adapter | Track child sessions without confusing them with the main session |

Codex hook payloads are similar in spirit but must not be assumed byte-identical to Claude payloads. Add `.tfcore/hooks/codex-adapter.sh` (or a small Python program) that converts Codex JSON into the existing Claude-shaped contract. Set at least:

```text
TF_HARNESS=codex
TF_PROJECT_DIR=<project root>
CLAUDE_PROJECT_DIR=<project root>   # compatibility only for existing scripts
TF_SESSION_ID=<Codex thread/session id when supplied>
```

Important implementation details:

- Codex treats unified exec as `Bash` and lets `apply_patch` match `apply_patch`, `Edit`, or `Write`.
- Therefore, unlike the current OpenCode plugin, Codex can mechanically inspect and block an `apply_patch` that changes PROJECT-STATUS or a checklist. Do not ban `apply_patch` outright; normalize its patch payload and run the guards.
- Multiple matching hooks launch concurrently. If guard ordering matters, put the status and verify checks behind one adapter command rather than two independent handlers.
- Project hooks are skipped until the repository and the exact hook definitions are trusted. The scaffold/update output must tell the owner to trust the repo and review `/hooks` after installation or any hook change.
- Hooks should continue to fail open for telemetry, but policy guards should fail closed on malformed protected-file writes. The current universal fail-open posture is too weak for a new adapter that can validate the payload natively.

### 4.6 Add Codex exec-policy rules

Hooks are defense in depth, not the only permission layer. Create project rules under the Codex rules location used by the installed client (for example `.codex/rules/techieflow.rules`) to reject git and gh commands before execution.

The rules must cover command segments, not merely raw-string prefixes, and should distinguish:

- always forbidden: every `git` command and state-changing `gh` command required by the framework's “GIT IS MANUAL” rule;
- harmless diagnostics that TechieFlow still deliberately forbids for agent consistency;
- destructive filesystem commands, which remain approval-gated outside YOLO;
- normal build/test/runtime commands, which should be allowed inside the workspace sandbox.

Verify the exact rule syntax against the installed Codex version during implementation; do not mechanically translate Claude `Bash(pattern*)` or OpenCode wildcard syntax into Codex rules.

### 4.7 Extend harness detection and invocation

Update `.tfcore/utils/tf-harness.sh`:

- detection result set: `claude-code | opencode | codex | unknown`;
- recognize `TF_HARNESS=codex` first;
- recognize Codex-specific process/environment/session evidence only as fallback;
- add `model <tier> codex` using a new `models.<tier>.codex` key;
- map `invoke task <name>` to the relevant Codex skill instruction;
- map `invoke agent <name>` to “delegate to the `<name>` Codex subagent” rather than inventing a slash command;
- return `.tfcore/.session/codex.json` from `session`.

Update every whitelist currently accepting only `claude-code` or `opencode`, notably `tf-emit.sh`, `tf-yolo.sh`, `tf-routing.sh`, and `tf-goal.sh`.

### 4.8 Extend model routing

Add a Codex model column to `.tfcore/routing.yaml`:

```yaml
models:
  frontier:
    claude: <existing>
    opencode: <existing>
    codex: <owner-selected Codex model>
  standard:
    claude: <existing>
    opencode: <existing>
    codex: <owner-selected Codex model>
  economy:
    claude: <existing>
    opencode: <existing>
    codex: <owner-selected Codex model>
```

Replace the comment “Claude-only knob” above `effort` with a per-harness mapping or explicitly state that Codex also supports reasoning effort. Codex custom agents use `model_reasoning_effort`.

Extend `tf-routing-bind.sh` to generate:

- model/effort fields in `.codex/agents/*.toml` for routed subagents;
- a machine-readable phase launcher map for `tf-goal.sh`/a new `tf-codex.sh`;
- optionally phase-specific orchestrator agents when a phase must force a model in interactive use.

Do not claim that a repository skill itself forces the current main thread onto a different model. Codex supports model selection for spawned custom agents and the CLI invocation; use those boundaries. For a phase started in an already-running interactive main thread, routing is advisory unless the phase is delegated to a configured role.

Update `tf-routing.sh` to accept `codex` and validate model IDs without assuming OpenCode's `provider/model` syntax.

### 4.9 Extend telemetry

Update the telemetry schema and emitters to accept `harness: codex`.

For headless/goal runs, use the reliable path:

```bash
codex exec --json "<phase prompt>"
```

Parse:

- `thread.started.thread_id` for the session pointer;
- `turn.completed.usage.input_tokens`;
- `turn.completed.usage.cached_input_tokens`;
- `turn.completed.usage.output_tokens`;
- `turn.completed.usage.reasoning_output_tokens` where the schema is extended to retain it.

Do not synthesize `cost_usd` from account credits. Leave it null unless the selected authentication/provider supplies an authoritative cost signal.

For interactive CLI/IDE sessions, choose one explicit strategy and document its fidelity:

1. parse Codex session rollout JSONL at `SessionEnd`, if the current hook payload exposes a stable path; or
2. configure OTel in the user's global config and ingest its events outside the repository; or
3. record session metadata without token totals and mark the fields null.

Project-local config cannot set OTel routing, so scaffolding must never overwrite a user's telemetry destination. `tf-emit.sh` should add `_window_codex()` only after the session storage shape is verified against the installed Codex version.

### 4.10 Extend unattended goal mode

Update `tf-goal.sh` to accept `--harness codex`.

Initial cycle:

```bash
codex exec --json --sandbox workspace-write \
  --ask-for-approval never \
  -m "<routed-model>" \
  -c 'model_reasoning_effort="<effort>"' \
  "<goal prompt>"
```

Resume cycle:

```bash
codex exec resume <thread-id> "<continue prompt>" --json
```

Confirm the installed CLI's option ordering while implementing. Capture the thread ID from JSON instead of scraping prose. Preserve the existing maximum-cycle, idle retry, state-file, and crash-resume controls.

Codex `--full-auto` is deprecated; use explicit sandbox and approval flags. `danger-full-access` must not be the default. The existing YOLO promise should mean “no elicitation pauses and no avoidable approval prompts inside the configured workspace,” not “unrestricted machine access.”

Rate-limit recovery needs a Codex-specific parser. If the JSON event does not contain an authoritative reset time, use bounded backoff; do not infer a precise reset window from human-readable text.

### 4.11 Port library personas

The NuGet libraries currently deploy `.claude/<library>.md` and `.opencode/command/<library>.md`. Add a Codex payload at the library source of truth, ideally:

```text
.codex/agents/trblazeui.toml
.codex/agents/techierag.toml
```

or install the persona as a repository skill plus a generated custom-agent TOML. Update the NuGet `.targets` files documented in `docs/TechieFlow-Library-Persona-Propagation.md` to deploy the Codex files into consuming apps.

The framework updater must preserve NuGet-owned Codex persona files exactly as it preserves the Claude/OpenCode library files. Do not generate a Codex role that references a missing persona file, because a missing project config dependency can prevent the role from loading.

### 4.12 Update scaffold and update scripts

Modify all three scripts to deploy and report:

```text
.codex/config.toml
.codex/hooks.json
.codex/agents/*.toml
.codex/rules/techieflow.rules
.agents/skills/techieflow-*/SKILL.md
```

Required behavior:

- `.tfcore/` remains canonical and force-refreshed as today.
- Framework-owned Codex adapter files are refreshed; per-project Codex additions need a documented preservation/merge policy.
- User-global `~/.codex/*` is never written by a project scaffold.
- The script warns that the owner must trust the repository and review changed hooks.
- `--dry-run` shows Codex additions and removals.
- routing-enabled output runs the Codex binding generator; routing-disabled output removes only generated routing fields/files, not user-owned Codex config.
- legacy migrations never delete an existing `.codex/` directory wholesale.
- generated `.gitignore` blocks include `.codex/` and `.agents/skills/` only if the existing product decision remains to keep all deployed framework copies untracked. If teams should share Codex support through Git, reverse that policy deliberately; repository skills and project config are designed to be committed.

That last choice deserves an explicit decision. Ignoring `.agents/skills/` means every clone needs the scaffold/update step before Codex sees TechieFlow. Committing the adapter makes Codex support available immediately to collaborators but changes the current “framework copies are deployment artifacts” model.

### 4.13 Update documentation and maintenance contracts

Update at least:

- `README.md` and `WORKFLOW.html`: bootstrap, project structure, command examples, permissions, YOLO/goal mode, routing, telemetry, FAQ, and cheat sheet;
- `.tfcore/user-guide.md`: replace the currently incomplete “Codex (CLI & Web)” text with the actual skill/agent/config workflow;
- `docs/Capability-Matrix.md`: add a Codex column;
- `docs/Coupling-Points.md`: classify Codex breaks/degrades/cosmetic differences;
- `docs/Adapter-Design.md`: make the harness boundary three-way;
- `docs/TechieFlow-Routing-Guide.md`: Codex model/effort and interactive-routing caveat;
- telemetry guides/schema: Codex session and usage provenance;
- `WorkFlow-Context.md`: add the implementation entry and update the repo map/maintenance contract;
- `DECISIONS.md`: record the skills-vs-prompts choice, trust behavior, telemetry fidelity, and whether generated Codex files are tracked.

Search and neutralize two-harness assumptions such as “both harnesses,” “Claude Code or OpenCode,” and enum checks containing only `claude-code|opencode`.

## 5. Features that Codex cannot support exactly

These are exact-parity gaps, not necessarily blockers to the framework.

### 5.1 Literal TechieFlow `*commands` and the existing slash-command namespace

Codex does not natively register the framework's `*verify`, `/TechieFlow:tasks:verify-phase`, or OpenCode `/techieflow:tasks:*` vocabulary from this repository. Skills provide equivalent explicit/implicit invocation, but the text typed by the user and command-menu presentation differ.

**Impact:** cosmetic and documentation-level after skills are added.

### 5.2 A repository skill cannot reliably force the main thread's model for one phase

Codex can set model/effort on custom subagents and at `codex exec` launch. A skill is reusable instruction content, not a guaranteed turn-scoped model switch for the already-running main agent.

**Impact:** per-phase routing is exact in scripted runs or delegated phase agents; it is advisory for an in-place interactive main-thread phase.

### 5.3 Automatic use of subagents without an explicit enabling instruction

Current Codex releases delegate when the user asks or when an applicable `AGENTS.md`/skill requests it. TechieFlow therefore must place delegation instructions in the build/verify skills. It cannot assume that merely defining agents causes automatic fan-out.

**Impact:** fully addressable by the generated skills, but not implicit from agent registration alone.

### 5.4 Trust-free activation of repository hooks and config

Codex intentionally ignores project `.codex/` config in untrusted projects and requires review/trust of non-managed hook definitions. A scaffold cannot silently activate new or changed policy hooks for a user.

**Impact:** unavoidable one-time/manual trust checkpoint per repo or changed hook hash. Enterprise managed configuration can remove this checkpoint only through administrator policy.

### 5.5 OpenCode-style in-process plugin event parity

Codex does not load `.opencode/plugin/techieflow.js`, and command hooks are process-based rather than an arbitrary OpenCode JavaScript event plugin. Codex hooks cover the important enforcement lifecycle, but there is no reason to expect every OpenCode event object (`message.updated` cost/tokens, `session.idle`, mutable `permission.ask`, `shell.env`) to have an identical Codex callback.

**Impact:** guards port cleanly; telemetry, YOLO auto-approval, and environment injection need Codex-specific implementations.

### 5.6 Guaranteed interactive token and cost telemetry identical to OpenCode

`codex exec --json` exposes authoritative per-turn token usage. Interactive token capture depends on hook/session-log or OTel details and may not expose authoritative monetary cost. ChatGPT credits are not interchangeable with API dollar cost.

**Impact:** headless run telemetry can be complete for tokens; interactive session and cost fields may be null and must be labeled honestly.

### 5.7 Unlimited unattended operation through account limits or machine prompts

No harness can guarantee uninterrupted multi-day execution across account exhaustion, OS credential prompts, reboots, unavailable mobile/device hosts, or administrator policy. Codex can resume threads and a supervisor can retry, but it cannot bypass limits or policy.

**Impact:** retain bounded retries, durable state, explicit blocked states, and truthful `STATIC-ONLY` degradation.

### 5.8 Identical behavior across every Codex surface

Local CLI/IDE/app runs can access the local repository, hooks, local tools, and device bridges according to their sandbox. Codex cloud runs in a hosted environment and cannot automatically reach the owner's WSL-to-Windows `winrun`, LAN Mac Appium host, local NuGet credentials, or already-running services.

**Impact:** TechieFlow's full MAUI/runtime verification path remains a local Codex workflow. Cloud runs should be documented as planning, review, or static verification unless equivalent infrastructure is explicitly provisioned.

## 6. Features that remain supported without framework redesign

The following are already harness-neutral or need only the adapter wiring above:

- BRD, Architecture, Checklist, PROJECT-STATUS, DevGuide, ProductGuide, UsageGuide, mockup, and HTML artifact formats;
- stable BRD/REQ identifiers and the one-checklist model;
- build → self-smoke → verifier → status/HTML → telemetry sequencing;
- Playwright, Appium, FlaUI, `winrun`, .NET, shell utilities, and performance harnesses, subject to the same host prerequisites;
- local-only verification and `STATIC-ONLY` truthfulness;
- artifact confinement under `tests/.artifacts/`;
- telemetry JSONL streams and provenance separation;
- MCP servers and authenticated external connectors;
- multiple specialist subagents with distinct models, reasoning effort, sandbox modes, skills, and MCP access;
- non-interactive execution, JSONL events, resumable threads, and structured output;
- mechanical pre-tool enforcement for Bash and protected-file edits.

## 7. Recommended implementation order

1. Add `codex` to the harness enums and telemetry schema without changing behavior for Claude/OpenCode.
2. Generate root `AGENTS.md` additions and the minimal workflow skills.
3. Generate the four primary custom agents and routed builder/test/explorer roles.
4. Add Codex hooks plus the payload adapter; test git, PROJECT-STATUS, Checklist, and `apply_patch` denial cases.
5. Extend routing and verify model/effort selection in a spawned agent and `codex exec`.
6. Extend `tf-goal.sh` and JSON telemetry using a short disposable goal.
7. Add NuGet library persona deployment.
8. Update all scaffold/update scripts and verify dry-run, first install, repeat install, preserved user config, routing on/off, and hook-change trust messaging.
9. Update the public docs, capability matrix, context, and decisions.
10. Run one brownfield day-1, one routed build fan-out, one full verify, one triage-only run, one interrupted/resumed goal, and one metrics report under Codex before declaring parity.

## 8. Acceptance checklist for a Codex adapter

- [ ] A fresh scaffold is recognized by Codex after the owner trusts the repo.
- [ ] Codex discovers every TechieFlow skill without loading every task body into context.
- [ ] The four primary personas and five routed worker roles appear as custom agents.
- [ ] A build skill explicitly fans independent work to the intended roles and waits for results.
- [ ] A verifier remains independent and is the only path that introduces `Verified` verdicts.
- [ ] Direct Bash, compound Bash, and indirect attempts to run `git` or `gh` are blocked.
- [ ] `apply_patch`, edit, and write operations on protected docs all pass through guards.
- [ ] Normal source edits and build/test commands still work inside the workspace sandbox.
- [ ] Routing off inherits the launch model; routing on selects the declared Codex model/effort at the supported boundary.
- [ ] `tf-emit.sh` records `harness: codex` and never fabricates token or cost values.
- [ ] `tf-goal.sh --harness codex` captures a thread ID, resumes it, and survives a killed supervisor process.
- [ ] Scaffold/update is idempotent and preserves project/user-owned Codex settings.
- [ ] Claude Code and OpenCode byte/content parity requirements continue to pass unchanged.
- [ ] README, WORKFLOW, user guide, routing guide, telemetry guide, context, and decisions agree on the supported Codex behavior and limitations.

## 9. Bottom line

There is no fundamental Codex blocker for TechieFlow's core lifecycle. The highest-risk work is not the agent prompts; it is the mechanical edge of the adapter: protected-file hook payload normalization, permission rules, interactive telemetry fidelity, model-routing boundaries, and safe merging of generated `.codex/config.toml` with project-owned configuration. Implement and test those as first-class code rather than documenting them as assumptions.

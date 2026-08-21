# TechieFlow Model Routing Guide

**Audience:** the framework owner. **TL;DR:** run cheap phases on cheap models, expensive thinking on expensive models — one script controls everything. **Design doc:** `docs/Adapter-Design.md §5` (the reasoning) · **quick summary:** README §17b / WORKFLOW.html §17b.

## 1. The problem routing solves

Every TechieFlow phase used to run on whatever model your session happened to be using. Day-1 architecture — where a wrong decision costs days of rework — and re-rendering markdown to HTML — pure mechanics — cost exactly the same per token. Over a project's life the mechanical phases (renders, status refreshes, reports) plus the bulk token spend of builder subagents dominate the bill, while the genuinely hard thinking is a handful of runs.

Routing assigns every phase and every subagent a **tier**, and maps each tier to a real model per harness. It is:

- **OFF by default** — a freshly scaffolded or updated app changes nothing until you turn it on.
- **Per-app** — enable it on one project, leave the others alone.
- **Reversible** — `off` removes every generated file and your map survives for the next `on`.
- **Observed, never enforced** — nothing blocks a phase from running on the "wrong" model; the telemetry records what actually ran so drift is visible, not hidden.

A real measured datapoint (TechieBlog pilot, 2026-08-20): one complete `metrics-report` phase on the economy tier — 14,000 output tokens, full report written — cost **$0.036**. The same phase on the frontier model is roughly 10× that for identical output.

## 2. The three tiers

| Tier | Mental model | Claude Code model | OpenCode model (shipped defaults) |
|---|---|---|---|
| `frontier` | The expensive thinking. Mistakes here are the costliest to discover late. | `opus` | `opencode-go/kimi-k3` |
| `standard` | The everyday building. Needs real competence, not brilliance. | `sonnet` | `opencode-go/kimi-k2.7-code` |
| `economy` | The mechanical work. Format, assemble, scan, report. | `haiku` | `opencode-go/deepseek-v4-flash` |

The models are **starting values, yours to change** (§6). Claude side accepts the aliases `opus` / `sonnet` / `haiku` or a full model id; OpenCode side takes `provider/model` ids — list everything your account offers with `opencode models`.

## 3. The complete map — what runs on what

### 3.1 Phases (the commands you type)

| Phase | Tier | Why this tier |
|---|---|---|
| `day1-greenfield` | frontier | Architecture + BRD from nothing; errors here poison everything downstream. |
| `day1-brownfield` | frontier | Same, plus whole-codebase comprehension of an existing app. |
| `author-brd` | frontier | Requirements authoring — bad acceptance criteria fail every later gate. |
| `amend-docs` | frontier | Surgical edits to the day-1 docs; must understand the whole picture. |
| `fix-issues` | frontier | The *diagnosis* half (root-causing from screenshots) is frontier work; the fixes themselves fan out to standard builders. |
| `mockups` | standard | Bounded design from a known component catalog. Promote to frontier if greenfield first-pass mockups disappoint — it's the easiest override. |
| `split-brd` | standard | BRD → checklist rows with acceptance authoring; not mechanical enough for economy. |
| `build-phase` | standard | The orchestrator: clustering, fan-out, FIX-mode detection. The expensive judgement already lives in the BRD/architecture. |
| `verify-phase` | standard | Test *generation* and the visual-truth eyeball need a capable vision model; the gates themselves are deterministic scripts. |
| `triage-issues` | standard | Reproduce, classify, log — no code changes. |
| `devguide` | standard | Large code-tracing; cheap models lose the thread across page → service → query. |
| `productguide` | economy | Screenshot-illustrated how-to assembly from existing material. |
| `handoff-phase` | economy | Wrap-up docs and re-renders. |
| `refresh-status` | economy | Evidence gathering (build + mtimes + tables). Promote to standard if recovery notes look wrong — the reconcile judgement is occasionally subtle. |
| `render-workflow-docs` | economy | Markdown → HTML. |
| `generate-html` | economy | Markdown → HTML. |
| `metrics-report` | economy | Runs `tf-metrics.sh` and formats the output. |

### 3.2 Personas and subagents (the agents that do the work)

Personas get the tier of their *primary phase*; subagents get their own row in the map. This matters because typing `*verify all MyApp` inside the flow-verifier persona is routed through the **persona's** model, and every builder the build orchestrator spawns runs on the **subagent's** model.

| Agent | Kind | Tier | Claude model | OpenCode model | When it runs |
|---|---|---|---|---|---|
| `flow-master` | persona | standard (= build-phase) | sonnet | opencode-go/kimi-k2.7-code | The super-agent: build, fix, triage, utilities typed as `*commands` |
| `flow-analyst` | persona | frontier (= day-1) | opus | opencode-go/kimi-k3 | Day-1 docs, mockups, split-brd, amendments |
| `flow-architect` | persona | frontier (= day-1) | opus | opencode-go/kimi-k3 | Optional deep architecture dives |
| `flow-verifier` | persona | standard (= verify-phase) | sonnet | opencode-go/kimi-k2.7-code | `*verify ui/functional/all` |
| `tf-builder` | subagent | standard | sonnet | opencode-go/kimi-k2.7-code | One per FN/NFR cluster in build-phase §3 and fix-issues §4 |
| `trblazeui` | subagent | standard | sonnet | opencode-go/kimi-k2.7-code | UI clusters (REQ-UI-*) — wraps the NuGet-deployed persona |
| `techierag` | subagent | standard | sonnet | opencode-go/kimi-k2.7-code | RAG clusters (REQ-RAG-*) — wraps the NuGet-deployed persona |
| `tf-test-writer` | subagent | standard | sonnet | opencode-go/kimi-k2.7-code | Verify-phase §4 test generation, one per cluster |
| `tf-explorer` | subagent | economy | haiku | opencode-go/deepseek-v4-flash | Read-only scans (devguide OBSERVE, index-docs) |
| `build` (OpenCode) / your session (Claude) | default chat | **never routed** | your `/model` choice | your TUI selection | Your normal conversation — routing deliberately leaves it alone |

> **Why builders are standard, not economy** — the single most-challenged row. A cheap builder that ships a page with a blank data table doesn't save money: it costs a full verify → fix-issues → re-verify cycle, which dwarfs the per-token saving. This is a *hypothesis with a measurement attached*: the rework ratio in `runs.jsonl` (§8) confirms or overturns it with your own data.

## 4. Turning it on and off

Everything is one script, run from the app repo. It edits `.tfcore/routing.yaml` for you and regenerates all harness bindings — you never touch a generated file.

```bash
cd /mnt/c/1MyCode/TechieBlog
bash .tfcore/utils/tf-routing.sh status     # read-only: what routing is/would be doing
bash .tfcore/utils/tf-routing.sh on         # enable  → generates ~23 binding files
bash .tfcore/utils/tf-routing.sh off        # disable → removes exactly those files
```

`status` prints the live tier/model/phase table for THIS app, whether the bindings on disk agree with the flag, the advisory escalation policy (§6.4), and where routing shows up in the TUI.

After `on`, **you keep using the same commands you always used**:

| Harness | You type | What changed |
|---|---|---|
| OpenCode | `/techieflow:tasks:verify-phase all MyApp` — unchanged | The phase now executes on its tier's model |
| OpenCode | Tab to `flow-verifier`, then `*verify all MyApp` — unchanged | The persona carries its tier's model |
| Claude Code | `/tf:verify-phase all MyApp` — new short wrapper | Runs the phase on the tier model for that turn |
| Claude Code | `/TechieFlow:agents:verifier *verify all MyApp` — the old way | Still works, **unrouted** (session model) |

## 5. What you will — and won't — see in the TUI

**Opening OpenCode looks exactly the same as before. That is deliberate.** Your normal chat runs on the default `build` agent, and routing never binds it — your conversation stays on the model YOU picked. If you enable routing, open the TUI and see your usual model in the status bar: that is correct behavior, not a failure.

Routing is visible in exactly three places:

1. **Running a phase command.** `/techieflow:tasks:metrics-report MyApp` → the footer shows the run executing on `deepseek-v4-flash` while it works.
2. **Switching persona.** Tab to `flow-master` / `flow-verifier` / `flow-analyst` — each shows and uses its bound model.
3. **The telemetry.** Every run lands in `docs/metrics/runs.jsonl` with declared tier, observed model, `routed: true/false`, tokens, and (OpenCode) real dollar cost.

**Verified gotcha #1 — the model sticks (OpenCode).** After a routed command finishes, that TUI session **continues on the phase's model**. It does not bounce back to your selection. If you finish an economy phase and keep chatting, you are chatting with the economy model until you pick another from the model list or start a new session.

**Verified gotcha #2 — turn-scoped (Claude Code).** The mirror image: a `/tf:<phase>` wrapper's model lasts exactly one turn; your next plain prompt reverts to the session model automatically.

## 6. Changing the map — every case, with examples

Each command edits `routing.yaml` and immediately regenerates the bindings. Verify any change with `status`.

### 6.1 Moving a phase between tiers

```bash
# Greenfield mockups keep missing the mark → give them the frontier model:
bash .tfcore/utils/tf-routing.sh set-tier mockups frontier

# Verify feels like overkill on standard for a stable app → try economy:
bash .tfcore/utils/tf-routing.sh set-tier verify-phase economy

# Recovery notes from refresh-status look sloppy → promote it:
bash .tfcore/utils/tf-routing.sh set-tier refresh-status standard

# Take a phase out of routing entirely (runs on the session model again):
bash .tfcore/utils/tf-routing.sh set-tier devguide inherit
```

### 6.2 Moving a subagent between tiers

```bash
# Test the "cheap builders" hypothesis yourself (watch the rework ratio!):
bash .tfcore/utils/tf-routing.sh set-tier tf-builder economy

# UI builders struggle with a complex design system → promote just them:
bash .tfcore/utils/tf-routing.sh set-tier trblazeui frontier
```

### 6.3 Changing which model a tier means — per tier, per harness

```bash
# FRONTIER — try a different top model on OpenCode:
bash .tfcore/utils/tf-routing.sh set-model frontier opencode opencode-go/qwen3.8-max
# ...and pin Claude's frontier to opus explicitly:
bash .tfcore/utils/tf-routing.sh set-model frontier claude opus

# STANDARD — swap the workhorse:
bash .tfcore/utils/tf-routing.sh set-model standard opencode opencode-go/kimi-k2.7-code
bash .tfcore/utils/tf-routing.sh set-model standard claude sonnet

# ECONOMY — chase the cheapest model that doesn't degrade output:
bash .tfcore/utils/tf-routing.sh set-model economy opencode opencode-go/mimo-v2.5
bash .tfcore/utils/tf-routing.sh set-model economy claude haiku
```

Find OpenCode ids with `opencode models`. On the Claude side you can also repoint what the aliases mean machine-wide with environment variables: `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`.

### 6.4 Escalation — when the base tier isn't cutting it

`routing.yaml` carries an **advisory** escalation policy, ported from the AI-First Playbook's `model-tiers.yml`:

```yaml
escalation:
  fix-issues:
    after_attempts: 2
    tier: frontier
```

Meaning: if the same REQs have already been through `fix-issues` twice without reaching `Verified`, launch the **third** run on the frontier tier. Three things it is *not*:

- **Not runtime.** Nothing switches a running phase's model — neither harness can, and the one place it could be faked (OpenCode's undocumented `chat.message` mutation) has no Claude Code equivalent (DECISIONS.md 2026-08-21).
- **Not enforced.** It is applied by whoever launches the command — you, or a wrapper script — by reading the attempt history *before* the run starts.
- **Not a binding.** `set-escalation` edits `routing.yaml` only; it generates no files, so it needs no `bind`.

How to apply it at launch:

```bash
# 1. What attempt would the next fix-issues run on these REQs be?
bash .tfcore/utils/tf-emit.sh --next-run-attempt fix-issues REQ-UI-009 REQ-FN-011   # → 3
# 2. status prints the policy next to the base tier:
bash .tfcore/utils/tf-routing.sh status
#    Escalation (ADVISORY ...):
#      fix-issues   after 2 attempt(s) on the same REQs -> launch the next on frontier (base tier: frontier)
# 3. If the answer exceeds after_attempts, launch on the escalation tier:
#    Claude Code:  /model opus  then  /tf:fix-issues ...   (or run the old command form on opus)
#    OpenCode:     pick the tier model from the model list, then /techieflow:tasks:fix-issues ...
```

The attempt history is the checklist's own record: `attempt` on each `runs.jsonl` record (§2.5 of `SCHEMA.md` — `1 +` prior non-backfilled runs of the same `cmd` touching any of the same REQs), with the per-REQ verdict history in `gates.jsonl` and the Verification Log in `PROJECT-STATUS.md` as the human-readable view. Tune the threshold from the data — if third attempts on the base tier usually succeed anyway, raise it; if second attempts mostly fail, lower it:

```bash
bash .tfcore/utils/tf-routing.sh set-escalation fix-issues 3 frontier   # raise the threshold
bash .tfcore/utils/tf-routing.sh set-escalation build-phase 2 frontier  # add a policy for another phase
```

With the shipped map `fix-issues` is already `frontier`, so the default row only bites after you demote it (`set-tier fix-issues standard`) — which is exactly the experiment it exists to make safe.

### 6.5 Editing routing.yaml by hand

The file is deliberately human-editable (flat, two-space indent, commented). After any manual edit:

```bash
bash .tfcore/utils/tf-routing.sh bind      # re-apply → regenerates all bindings
```

## 7. Under the hood — what actually gets generated

You never need this section to *use* routing; it is here so nothing is a black box.

| File | Harness | What it does |
|---|---|---|
| `.opencode/opencode.json` | OpenCode | Pure-JSON binding file loaded alongside the framework config. Adds `model` to each persona (deep-merges — prompt/permission preserved), registers `tf-builder`/`tf-test-writer`/`tf-explorer` as subagents with their models, and re-declares each `techieflow:tasks:*` command with its tier model. |
| `.claude/commands/tf/<phase>.md` × 17 | Claude | Wrapper commands: frontmatter `model:` + `effort:` from the tier; body loads the owner persona then executes the task with your arguments. |
| `.claude/agents/{tf-builder, tf-test-writer, tf-explorer, trblazeui, techierag}.md` | Claude | Tier-bound subagent definitions (the library two adopt the NuGet-deployed personas). |
| `.tfcore/.session/routing-bind.manifest` | both | The exact list of generated files. `off` deletes precisely this list — never anything else. |

All generated files live under gitignored paths — **nothing to commit in the app**. `update-framework.sh` re-runs the generator on every refresh, so framework updates and your routing coexist: your `routing.yaml` is never overwritten, your bindings are always regenerated from it (verified in the TechieBlog pilot).

## 8. Reading the results — the tuning loop

Every phase run appends a record to `docs/metrics/runs.jsonl` (full field reference: `docs/TechieFlow-Telemetry-Guide.md`):

```json
{"kind":"run","cmd":"verify-phase","app":"TechieBlog","harness":"opencode",
 "tier":"standard",
 "tier_model":"opencode-go/kimi-k2.7-code",
 "model":"opencode-go/kimi-k2.7-code",
 "routed":true,
 "tokens_in":784,"tokens_out":42310,"tokens_cache_read":310221,
 "cost_usd":0.41,"tokens_scope":"tree", "...":"..."}
```

- `tier` / `tier_model` — what routing **declared** should run.
- `model` — what **actually** ran (from the harness's own store, never self-reported).
- `routed` — do they match. `false` = drift (someone ran the phase unrouted); visible, never blocked.
- `cost_usd` — real dollars on OpenCode; always `null` on Claude (no cost source exists — the framework never estimates).

**The deciding question after ~2 weeks:** does the rework ratio rise on cheaper tiers? Run `*metrics` (or read `runs.jsonl`): if standard-tier builders hold the first-pass rate, consider demoting more phases; if `mode:"fix"` re-entries climb after a demotion, promote back. Data corrects the map — not opinion, and not this guide.

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| "I turned it on and the TUI looks the same" | Expected — the default chat agent is never routed (§5) | Run a phase command or Tab to a persona |
| `status` says flag and bindings disagree | An update or manual edit got out of sync | `bash .tfcore/utils/tf-routing.sh bind` |
| A phase ran on the wrong model | Invoked unrouted (old Claude command form, or model picked manually) | Check `runs.jsonl` → `routed:false` confirms; use `/tf:<phase>` (Claude) or the `/techieflow:tasks:*` command (OpenCode) |
| `fix-issues` keeps failing on the same REQs | That's what escalation is for (§6.4) — it is advisory, so nothing happens until you act on it | `tf-emit.sh --next-run-attempt fix-issues <REQs>`; if it exceeds `after_attempts`, launch the next run on the escalation tier |
| Follow-up chat is on the phase's model (OpenCode) | Verified behavior — the session keeps the command's model | Pick your model from the model list, or start a new session |
| "I want my normal chat cheaper too" | That's not routing's job | TUI model list, or `"model"` in `~/.config/opencode/opencode.jsonc` |
| Config error mentioning `.opencode/opencode.json` | Hand-edited generated file | Never edit generated files — `bind` regenerates them |
| Want a clean slate | — | `off` removes everything generated; your `routing.yaml` map survives for the next `on` |

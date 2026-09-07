# TechieFlow — Model Routing Guide

| | |
|---|---|
| Purpose | Which model runs which command, where that is written down, and how to change it. |
| Audience | The framework owner. |
| Status | Rewritten in plain words 2026-09-06 (Sitting 4b), when the owner found the old guide confusing. Default OpenCode models changed to the OpenAI ones the same day. |
| Companion | `.tfcore/routing.yaml` (the file itself, with the same how-to in its header), `TechieFlow-How-It-Works.md` §2 "Model routing". |

---

## 1. What routing is, in one paragraph

Every command and every sub-agent is given a **tier**: `frontier` for the expensive thinking, `standard` for everyday building, `economy` for mechanical work. Each tier is then mapped to one real model per harness. Day-1 documents run on the frontier tier; a build runs on standard; rendering HTML runs on economy. Routing only sets the model a command starts on. It never switches a model mid-run, and it never blocks anything: the run record says which model actually ran, so a drift is visible, not hidden.

## 2. The current defaults

| Tier | Claude Code | OpenCode | Used for |
|---|---|---|---|
| `frontier` | `sonnet` | `openai/gpt-5.6-terra` | day1-greenfield, day1-brownfield, amend-docs, fix-issues |
| `standard` | `sonnet` | `openai/gpt-5.6-terra` | build-phase, verify-phase, mockups, split-brd, triage-issues, devguide, and the builder sub-agents |
| `economy` | `haiku` | `openai/gpt-5.6-luna` | refresh-status, handoff-phase, productguide, metrics-report, HTML rendering, the explorer sub-agent |

Why these: the owner's decisions of 2026-09-05 (Sonnet for every long Claude run, Haiku for the cheap ones) and 2026-09-06 (OpenAI models for OpenCode, after the OpenCode Go monthly limit was reached with MiMo). Codex is frozen; its column in the file is kept but not maintained.

Your normal chat is never routed. Opening OpenCode or Claude Code looks exactly as before; routing shows only when a command runs or a persona is selected.

## 3. Where the models are written down

There are two copies of the same file, and knowing which one you are editing is the whole trick.

| File | What it is | Who changes it |
|---|---|---|
| `TechieFlow/.tfcore/routing.yaml` | The **framework default**. Copied into a project when the project is scaffolded. | Edit it to change what every *future* project starts with. |
| `<project>/.tfcore/routing.yaml` | The **project's own copy**. `update-framework.sh` never overwrites it. | Edit it to change *this* project. |

The file is short and flat: a `tiers:` block (tier to model, per harness), a `phases:` block (command to tier), a `subagents:` block, and an `effort:` block. Its header repeats the steps below.

**Nothing happens until the bindings are regenerated.** The harnesses do not read `routing.yaml`; they read files generated from it (`.opencode/opencode.json`, `.claude/commands/tf/*.md`, `.claude/agents/*.md`). Every change ends with the bind step.

## 4. How to change a model, the four cases

All commands run inside the project folder.

**Case 1, this project, one tier.** The script edits the file and regenerates the bindings in one go:

```bash
bash .tfcore/utils/tf-routing.sh set-model standard opencode openai/gpt-5.6-terra
bash .tfcore/utils/tf-routing.sh set-model economy claude haiku
```

Model ids: for Claude Code `opus`, `sonnet`, `haiku` or a full id; for OpenCode `provider/model` exactly as `opencode models` prints it.

**Case 2, this project, move a command or a sub-agent to another tier:**

```bash
bash .tfcore/utils/tf-routing.sh set-tier mockups frontier
bash .tfcore/utils/tf-routing.sh set-tier tf-builder economy
bash .tfcore/utils/tf-routing.sh set-tier devguide inherit     # take it out of routing
```

**Case 3, edit the file by hand** (either copy), then regenerate:

```bash
bash .tfcore/utils/tf-routing.sh bind
```

For the framework default there is nothing to bind; the next scaffold copies the file. To bring an existing project up to a changed default, change its own copy (case 1 or 3), because the updater leaves it alone on purpose.

**Case 4, one unattended run only.** Pass the model to the supervisor; the file is untouched:

```bash
bash .tfcore/utils/tf-goal.sh --harness opencode --model openai/gpt-5.6-terra /path/to/App @goal.md
```

The main agent uses that model. The sub-agents it spawns still use the project's bindings, so when a provider is down, change the project's tiers too (case 1), or the sub-agents will fail while the main agent works. That is what happened on 2026-09-06.

## 5. Turning routing on and off

```bash
bash .tfcore/utils/tf-routing.sh status   # what this project would do, and whether the bindings match
bash .tfcore/utils/tf-routing.sh on       # write the bindings
bash .tfcore/utils/tf-routing.sh off      # remove exactly those files; the map stays for next time
```

With routing off, every command runs on whatever model the session is on. `status` is the first thing to run when a model looks wrong.

## 6. How to see what ran

Every run appends a line to `docs/metrics/runs.jsonl` with the tier the file declared, the model the harness actually used, and `routed: true` when they match. On OpenCode the line also carries the real dollar cost. After a few weeks, `*metrics` shows whether cheaper tiers cost more rework; that data, not opinion, decides the map.

## 7. Two things that surprise people

- **OpenCode keeps the model.** After a routed command finishes, that OpenCode session stays on the command's model. Pick your model again, or start a new session, before chatting on.
- **Claude Code reverts.** A `/tf:<phase>` wrapper's model lasts one turn; the next prompt is back on the session model. The old long command form (`/TechieFlow:agents:verifier *verify …`) still works but is not routed.

## 8. When something is wrong

| You see | Why | Do |
|---|---|---|
| A command ran on the wrong model | It was started unrouted, or the bindings are stale | `status`; then `bind` |
| Sub-agents fail while the main agent works | Sub-agents use the project's bindings, not `--model` | Change the tiers in the project's copy, then `bind` |
| OpenCode prints its header and nothing else | The provider refused the model; OpenCode says so only in its own log (`~/.local/share/opencode/log/opencode.log`) | The supervisor stops with exit 5 and the provider's message; pick another model or wait for the reset |
| The TUI looks unchanged after `on` | Expected: your chat is never routed | Run a command or select a persona |
| An error mentions `.opencode/opencode.json` | A generated file was edited by hand | Never edit generated files; `bind` |

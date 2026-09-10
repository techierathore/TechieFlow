# TechieFlow — Model Routing Guide

> **The Codex adapter was removed on 2026-09-07** (D-14, FR-42). The framework supports Claude Code and OpenCode. Everything below that describes `.codex/`, `.agents/skills/` or a Codex code path is history, kept for traceability; see `docs/CHANGELOG.md`.

| | |
|---|---|
| Purpose | Which model runs which command, where that is written down, and how to change it. |
| Audience | The framework owner. |
| Status | Rewritten in plain words 2026-09-06 (Sitting 4b), when the owner found the old guide confusing. Default OpenCode models changed to the OpenAI ones the same day. 2026-09-10: section 2b (setting routing up, step by step), section 9 (what happens when a model's limit is reached) and section 10 (what a cost number means). |
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

## 2b. Setting it up in a project, step by step

Do this once per project, in the project folder. Every step prints what it did; nothing is silent.

**Step 1 — see where you stand.**

```bash
bash .tfcore/utils/tf-routing.sh status
```

It says `ON` or `OFF`, which model each tier resolves to, and whether the generated files match the map. If it says the flag and the bindings disagree, step 5 fixes it.

**Step 2 — list the models this machine can actually reach.**

```bash
opencode models          # OpenCode: prints provider/model ids, e.g. opencode-go/glm-5.3
```

For Claude Code the ids are `opus`, `sonnet`, `haiku`, or a full id like `claude-opus-5`. The OpenCode Go plan's models are listed at <https://opencode.ai/docs/go>.

**Step 3 — set the model for each tier.** Three tiers, two harnesses; set only the ones you use.

```bash
bash .tfcore/utils/tf-routing.sh set-model frontier claude   sonnet
bash .tfcore/utils/tf-routing.sh set-model standard claude   sonnet
bash .tfcore/utils/tf-routing.sh set-model economy  claude   haiku
bash .tfcore/utils/tf-routing.sh set-model standard opencode opencode-go/glm-5.3
```

**Step 4 — set the fallback chain for each tier**, so a limit does not stop the run. This is edited in the file rather than by a command; open `.tfcore/routing.yaml` and put the models in order, comma-separated:

```yaml
fallbacks:
  standard:
    claude: haiku
    opencode: opencode-go/mimo-v2.5, opencode-go/qwen3.8-max, openai/gpt-5.6-luna
```

Put a **different model on the same plan** first (an OpenCode Go allowance is per model, so another model on the plan is usually still available), then a **different provider** last, for when the whole plan is out. Section 9 explains what the supervisor does with this.

**Step 5 — write the bindings.** Nothing takes effect until this runs.

```bash
bash .tfcore/utils/tf-routing.sh on      # turns routing on AND writes the bindings
bash .tfcore/utils/tf-routing.sh bind    # if it is already on and you edited the file
```

**Step 6 — check it.**

```bash
bash .tfcore/utils/tf-routing.sh status                  # the map and the bindings agree
bash .tfcore/utils/tf-model-pick.sh status               # what each tier would run right now
bash .tfcore/utils/tf-model-pick.sh chain standard opencode   # the order it will fall back in
```

**Step 7 — run something and look at the record.** After any command, the last line of `docs/metrics/runs.jsonl` carries `tier`, `tier_model`, the model that actually ran, and `routed: true` when they match. `*metrics` turns those into the per-phase table.

To move a *command* to a different tier rather than change a tier's model, that is `set-tier` — case 2 below.

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
| A phase ran on a model you did not choose | Its own model was out of quota and the tier fell back | `bash .tfcore/utils/tf-model-pick.sh status` — it names what is parked and until when |

## 9. When a model runs out

Every tier now has a **second choice**, and a third if you list one. The chain lives in `.tfcore/routing.yaml` under `fallbacks:`, one line per harness, models separated by commas:

```yaml
fallbacks:
  standard:
    claude: haiku
    opencode: opencode-go/mimo-v2.5, openai/gpt-5.6-luna
```

What happens when a limit is hit, in order:

1. The supervisor reads the reset time out of the limit message, exactly as it always did.
2. It **parks** the limited model until that time, in this project: `.tfcore/.session/model-cooldown.json`. TechieFlow is installed per project through npm/npx and never at machine level, so its state lives per project too, and what you change for one project never reaches another. The cost of that, plainly: a limit belongs to your account, so two projects each find it out for themselves — one wasted cycle apiece. Uncomment `cooldown_file:` in `routing.yaml` and point several projects at one path if you would rather they learned it from each other.
3. It asks the tier for the next model in the chain that is not parked, **re-binds** so the sub-agents move with the main agent, and starts the next cycle straight away. No sleeping.
4. If every model in the chain is parked, it sleeps until the reset, exactly as before.

Three plain commands:

```bash
bash .tfcore/utils/tf-model-pick.sh status                       # what every tier would run right now
bash .tfcore/utils/tf-model-pick.sh chain standard opencode      # the order, and what is parked
bash .tfcore/utils/tf-model-pick.sh clear opencode               # unpark by hand
```

**Where this does not help, said plainly.** On Claude Code the 5-hour and weekly limits belong to the account, not to the model, so falling back from Sonnet to Haiku will usually hit the same limit. The supervisor finds that out honestly: the next cycle is limited too, that model is parked as well, and once the chain is exhausted it waits — one wasted cycle, then the old behaviour. Where the Claude column does earn its keep is a limit on **one** model (Opus exhausted while the account is fine). The OpenCode column earns its keep more often, because a monthly balance or an outage really is one provider's problem.

`bash .tfcore/utils/tf-goal.sh --no-fallback …` turns all of it off and restores the sleep-until-reset behaviour. A project scaffolded before 2026-09-10 behaves that way anyway, until `update-framework.sh` gives it the new script.

## 10. What a cost number means

One machine pays for models in three different ways at once, and until 2026-09-10 all three landed in one column:

**Tokens are what the framework records.** Every run already carried them — in, out, cache read, cache write, split per model, main thread and sub-agents apart — on both harnesses, and OpenCode reports them for every provider including OpenCode Go. Turning tokens into money is a *reporting* job, so no record ever stores a computed price; `*metrics` (and TfLens) work it out at read time from what is on the stream. The one money number a record does carry is the one the provider itself reported.

What changed is that the report now knows what that number **means**, because a run record says how the model was paid for:

| `billing_mode` | Example here | What the provider's cost number is |
|---|---|---|
| `subscription` | Claude Max; the ChatGPT plan on OpenCode | Nothing, or `0.0`. The fee was paid before the run started. **Not free** — it used quota. |
| `plan` | **OpenCode Go** — $10/month with a per-model monthly allowance | **Allowance consumed**, not an invoice. These are the numbers that hit the 5-hour, weekly and monthly limits — the very thing section 9's fallback chain exists for, which is why the report lists them per model. |
| `metered` | a raw API key billed per token | Money you actually spent. |
| `local` | a model on your own machine | There is no bill. |

`*metrics` therefore prints three separate lines and never adds them together: **list price** (the published rate applied to the tokens on the record — a price, not a bill, and the only figure that compares a Claude phase with an OpenCode one), **plan allowance used** per model, and **money billed** over metered runs only. Each says how many records it left out.

Rates come from the models.dev catalog OpenCode already keeps (`~/.cache/opencode/models.json`). To use your own — a negotiated rate, or a model the catalog has never heard of — put a `.tfcore/rate-card.json` in the project and it wins:

```json
{ "claude-opus-5": { "input": 5, "output": 25, "cache_read": 0.5, "cache_write": 6.25 } }
```

Two things the list price does not do, so you are not surprised by them: it uses the **base** rate, so a provider's long-context surcharge is not added; and a model with no rate anywhere produces no number rather than a zero, with the run counted as unpriced beside the figure.

Because none of it is stored, changing a rate card — or disagreeing with this one — re-prices every run you have ever recorded, and makes no record wrong.

You do not have to configure this. If you want to override it — a local runtime with an unusual name, or a key whose billing you know and OpenCode's file does not state — name the provider inside `billing:` in `routing.yaml`:

```yaml
billing:
  claude: subscription
  opencode: auto
  myserver: local
```

Check any model with:

```bash
bash .tfcore/utils/tf-model-pick.sh billing openai/gpt-5.6-terra opencode   # how it is paid for
bash .tfcore/utils/tf-model-pick.sh rate    claude-opus-5                   # $ per million tokens
```

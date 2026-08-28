# TechieFlow Development Telemetry Guide

> **Codex:** headless/goal runs parse authoritative `codex exec --json`
> `turn.completed.usage` through `tf-codex-telemetry.py`. Interactive
> `SessionEnd` records identify the session/model but leave token and cost fields
> null when no stable source exists. ChatGPT credits are never fabricated as
> `cost_usd`.

**Audience:** the framework owner. **TL;DR:** the framework measures its own development process — first-pass quality, where gates catch problems, what escapes to you, and (since 2026-08-20) which model did the work and what it cost. **Reference docs:** `.tfcore/telemetry/SCHEMA.md` (the field-by-field contract) · `docs/TechieFlow-Telemetry-Runbook.md` (the original implementation record) · `docs/TechieFlow-Routing-Guide.md` (how the model/cost fields feed routing decisions).

## 1. Why this exists — the four questions

TechieFlow used to produce all this evidence and throw it away: every `*verify` applied named gates to identified REQs, wrote its ledger — and the next run overwrote everything. The status table mutates in place, so history evaporated.

Telemetry keeps that evidence in **append-only JSONL streams** under `docs/metrics/` (tracked in git, one JSON object per line, never rewritten). It exists to answer exactly four questions:

1. **First-pass rate** — how often does a REQ pass verification on its first attempt?
2. **Gate catch distribution** — *which* gate catches the problems (build? acceptance? data-render? visual? perf? standards?)
3. **Escape rate** — how much gets past all gates and is found by a human (UAT/production)?
4. **Miss attribution and rework cost** (added 2026-08-28) — *what* was missed, *which phase / agent / model* let it through, and *what did fixing it cost*?

Everything else (throughput, rework ratio, cost per phase) is derived from the same records.

## 2. The five streams at a glance

| File | One record per… | Written by | When |
|---|---|---|---|
| `docs/metrics/runs.jsonl` | framework command run (a `*build-phase`, a `*verify`, …) | the phase task, at its status gate | end of every run |
| `docs/metrics/gates.jsonl` | REQ verdict per verify run — **the primary stream** | `verify-phase` §6a (and `triage-issues` for escapes) | every time a REQ is graded |
| `docs/metrics/sessions.jsonl` | agent session (token totals) | Claude: `SessionEnd` hook · OpenCode: the `.opencode/plugin/techieflow.js` plugin | session end / session idle |
| `docs/metrics/commits.jsonl` | git commit | YOUR own `pre-commit` hook (agents never run git) | your commits |
| `docs/metrics/misses.jsonl` | something an agent **missed** (`miss`) + what repairing it cost (`miss-fix`) + a field completed later (`miss-amend`) | `verify-phase`, `build-phase`, `triage-issues`, `fix-issues`, `amend-docs`, `*log-miss` | when a miss is found / fixed |

Every record is appended through one primitive — `.tfcore/utils/tf-emit.sh` — which stamps the shared fields (`v`, `ts`, `app`, `project_type`, `harness`) and **never blocks anything**: telemetry has no veto, a failed write is a silently dropped record, never a broken session.

## 3. Each stream, with a real-shaped example

### 3.1 `runs.jsonl` — what happened, on which model, for how much

```json
{"v":1, "ts":"2026-08-20T09:41:02Z", "kind":"run",
 "app":"TechieBlog", "project_type":"app", "harness":"opencode",
 "cmd":"verify-phase", "mode":null,
 "started":"2026-08-20T09:12:40Z", "ended":"2026-08-20T09:41:02Z", "duration_s":1702,
 "reqs_touched":["REQ-UI-004","REQ-FN-011"], "reqs_count":2,
 "subagents":["tf-test-writer"], "build_result":"pass",
 "tier":"standard", "tier_model":"opencode-go/kimi-k2.7-code",
 "model":"opencode-go/kimi-k2.7-code", "routed":true,
 "tokens_in":784, "tokens_out":42310, "tokens_cache_read":310221, "tokens_cache_write":0,
 "cost_usd":0.41, "tokens_scope":"tree"}
```

Reading it line by line:

- `cmd` + `mode` — which phase ran; `mode:"fix"` marks a rework pass (this is what the rework ratio counts).
- `started` / `ended` / `duration_s` — the run window. These two timestamps are also what the token attribution keys on (§4).
- `reqs_touched` — REQ **ids only**, never requirement text (privacy rule, §6).
- `subagents` — which helpers were spawned (`trblazeui`, `techierag`, `tf-builder`, `general`/`general-purpose`, …).
- `harness` — `claude-code` or `opencode`, **detected** by the tooling, never self-declared by an agent (agents copy template text too faithfully to be trusted with it).
- The second half — `tier` through `tokens_scope` — is injected automatically by `tf-emit.sh` (§4). Absent fields mean "not captured", never zero.
- `attempt` (added 2026-08-21, also injected) — how many times this `cmd` has run against any of these REQs, counting this one: `1 +` prior non-backfilled runs of the same `cmd` whose `reqs_touched` overlaps. Present only on runs that touch REQs. This is the counter the advisory `escalation:` policy in `routing.yaml` reads **at launch** (`tf-emit.sh --next-run-attempt <cmd> <REQ>...`; Routing Guide §6.4). Not the same field as the per-REQ `attempt` on `gates.jsonl` (§3.2).

### 3.2 `gates.jsonl` — the primary stream: every verdict, and what caught the failure

```json
{"v":1, "ts":"2026-08-19T14:02:11Z", "kind":"gate",
 "app":"TechieBlog", "project_type":"app", "harness":"opencode",
 "req_id":"REQ-UI-007", "verdict":"fail", "attempt":2,
 "gate":"render", "failure_class":"empty-control",
 "gates_run":["build","acceptance","render"], "scope":"ui"}
```

- `gate` — the **first failing** gate for that REQ on that attempt: `build` → `acceptance` → `render` → `visual` → `perf` → `standards`. Distribution over this field = "which gate earns its keep".
- `attempt` — 1 on the REQ's first grading, incremented per re-verify. First-pass rate = share of REQs whose `attempt:1` record is a pass. Derived with `tf-emit.sh --next-attempt REQ-X`, never guessed by an agent.
- `gate:"escaped"` — written by `*triage-issues` when a HUMAN found the bug (UAT/production). Escape rate = escaped / everything graded.
- `gates_run` — which gates executed that time; a gate added later in the project's life is measured against runs that included it, never against the whole history (otherwise new gates look uselessly weak).

### 3.3 `sessions.jsonl` — token totals per agent session

```json
{"v":1, "ts":"2026-08-20T07:12:44Z", "kind":"session",
 "app":"TechieBlog", "harness":"opencode", "project_type":"app",
 "session_id":"ses_fdfe727dbffeSm3xDX3h0Dw712",
 "model":"opencode-go/deepseek-v4-flash", "duration_s":151,
 "input_tokens":1893, "output_tokens":13984,
 "cache_read_tokens":401220, "cache_creation_tokens":0,
 "cost_usd":0.03601, "children_sessions":0}
```

- **Claude Code:** written by the `SessionEnd` hook, one record per session, `cost_usd` always `null` (Claude transcripts carry tokens but no dollars, and the framework never estimates — a rate-card guess presented as a measurement would poison every comparison).
- **OpenCode:** written by the guard-bridge plugin with **real cost** from the provider, child-session tokens rolled into the root. The plugin appends a *cumulative snapshot* each time the session goes idle (a TUI session idles after every turn), so several records can share a `session_id` — readers take the one with the highest `output_tokens`.
- A session is NOT a run: one session may span several commands and vice versa. Session records answer "what does a working session cost"; run records answer "what did this phase cost".

### 3.4 `commits.jsonl` — your commits, never the agents'

```json
{"v":1, "ts":"2026-08-19T09:30:11Z", "kind":"commit", "app":"TechieBlog",
 "sha":"a1b2c3d", "files":9, "insertions":412, "deletions":57,
 "subject_prefix":"feat", "branch":"main"}
```

Written by the `pre-commit` hook inside YOUR own `git commit` (git is manual in TechieFlow — no agent path ever runs it). The hook reconciles: every commit, it backfills any commits the stream is missing, so multi-machine work and fresh clones converge. Only the conventional-commit prefix is kept; the subject line is discarded on the spot (§6). **An empty `commits.jsonl` means "no commits made from this clone since install" — not a bug.**

### 3.5 `misses.jsonl` — the fourth question, and the only stream that sees a DESIGN miss

Three record kinds, linked by `miss_id`. The `miss` opens; the `miss-fix` closes; the `miss-amend` completes a field the `miss` left empty.

```json
{"v":1, "ts":"2026-08-28T11:04:19Z", "kind":"miss",
 "app":"AstroLyfe", "project_type":"app", "harness":"claude-code",
 "miss_id":"MISS-AstroLyfe-20260828-03", "req_id":"REQ-UI-014", "req_class":"UI",
 "miss_class":"partial-implementation", "artifact":"src", "severity":"major",
 "origin_phase":"build-phase", "origin_agent":"trblazeui",
 "origin_run_id":"2026-08-26T09:12:40Z", "origin_confidence":"linked",
 "origin_model":"claude-opus-5", "origin_harness":"claude-code",
 "found_by":"gate", "found_phase":"verify-phase", "found_gate":"render",
 "found_run_id":"2026-08-28T10:41:02Z", "failure_class":"blank-data"}
```

```json
{"v":1, "ts":"2026-08-28T14:52:07Z", "kind":"miss-fix",
 "miss_id":"MISS-AstroLyfe-20260828-03", "req_id":"REQ-UI-014",
 "fix_run_id":"2026-08-28T13:58:11Z", "fix_cmd":"fix-issues", "fix_attempt":1,
 "verdict_after":"Verified", "reopened":false, "cost_attribution":"shared:3",
 "tokens_in":812, "tokens_out":38104, "cost_usd":null, "tokens_scope":"tree"}
```

- **`miss_class:"unspecified-gap"` with `artifact:"brd"` is the design-phase miss** — the case nothing in the framework could see before. `gates.jsonl` is written by the verifier, and by the time verification runs a specification gap has already been papered over or built wrongly. `build-phase` §4a records it at the moment a builder hits it.
- **`origin_model` / `origin_harness` / `origin_confidence` are looked up, never typed.** `tf-emit.sh` resolves them from the `runs.jsonl` record whose `started` equals `origin_run_id`, and **forces the model to `null` when it can't** — overwriting whatever the agent supplied. Same rule as `harness` (§4), sharper consequence: a per-model miss rate built from guesses is a routing decision made on invented evidence.
- **`cost_attribution` is derived from the fix run's `reqs_touched`** — `sole` (the run fixed only this REQ: a real measurement), `shared:n` (equal division, *not* a measurement), `none` (no window at all). Reports keep measured and apportioned in separate columns, always.
- **One defect is one miss.** `tf-emit.sh --open-miss REQ-X` is the collapse check: a REQ that fails three verify passes produces one record, not three, unless the *kind* of failure changes.
- **`why_missed` says which *practice* failed** (§5.5.6, ported from the Playbook 2026-08-28): `missing-checklist-item` · `insufficient-verify-method` · `code-audit-limitation` · `ambiguous-acceptance` · `dependency-not-declared` · `instruction-ignored` · `other`. `miss_class` names the defect; this names the practice, and it is the one that tells you whether your **specification** or your **verification** is weak. Optional — but an escape without it wastes the record, and the report says so.
- **`wont-fix` is not "open".** The report counts open / resolved / wont-fix separately: a wont-fix is a decision, not a backlog item. The collapse check still treats it as a live defect so a repeat failure cannot open a duplicate — two questions, two predicates, deliberately not the same.
- **A field left empty can be completed later, without editing anything** (§5.5.7, added 2026-08-28 from TfLens feedback TF-005):

  ```bash
  bash .tfcore/utils/tf-emit.sh --amend MISS-App-20260828-01 why_missed missing-checklist-item
  ```

  That appends a third kind, `miss-amend`. It may fill a field that is `null` and may **never** overwrite one that is not — so it adds to the history rather than revising it, and a reader that ignores amendments entirely still sees nothing false. Only closed-vocabulary *judgements* are amendable (`why_missed` today); nothing the emitter derives — attribution, tokens, cost — ever is, and an observation about a finished run is never backfilled. **Never hand-edit `misses.jsonl`.** If `--amend` refuses, that is the answer.
- **A record written before a field existed is not "unassessed".** `why_missed` arrived on 2026-08-28; misses older than that had no field to fill, so they leave that field's denominator and the report says how many did. Same rule as a gate added mid-stream (§3.5 of the schema) — never backfill a record with a verdict nobody made at the time.

**How to record one yourself:**

```
/TechieFlow:agents:flow-master *log-miss MyApp "the export button ignores the active date filter"
/flow-master *log-miss MyApp "..."           (OpenCode)        # --fixed if it is already repaired
```

Seconds, no app boot, no repro, no code touched. That last part is the point — `*triage-issues` does all three, which is right for UAT triage and is exactly the friction that stopped one-line misses from ever being recorded.

**What a miss costs, by harness:** OpenCode gives **real dollars**; Claude Code and Codex give **tokens** and `cost_usd: null`, permanently. No rate card is applied anywhere in this framework to make a dollar figure appear.

## 4. How model, tokens and cost get onto run records (the 2026-08-20 upgrade)

No agent ever reports its own token usage (it can't know it, and self-reports drift). Instead `tf-emit.sh` reads the **harness's own store** at append time:

| Harness | Where the numbers come from | Scope |
|---|---|---|
| Claude Code | The session transcript (JSONL on disk), located via a pointer file that a `SessionStart`/`UserPromptSubmit` hook maintains at `.tfcore/.session/claude-code.json`. Subagent transcripts sit at a deterministic path next to it and are included automatically. | `tokens_scope:"tree"` (or `"main"` if the run spawned no subagents) |
| OpenCode | The `opencode.db` SQLite database, located via the pointer the plugin writes; the query covers the session **and all its child sessions**, and includes the provider's real per-message cost. | `tokens_scope:"tree"`, `cost_usd` real |

Any record carrying `started` + `ended` gets the numbers for exactly that window. If anything is missing — no pointer, unreadable store, empty window — the record says `tokens_scope:"none"` and carries **no numbers at all**. Missing beats invented, every time.

When routing is enabled (`docs/TechieFlow-Routing-Guide.md`), the same enrichment adds `tier` (declared), `tier_model` (what the tier should resolve to here) and `routed` (`model == tier_model`) — which is how routing decisions get made from data. Independently of the routing flag, every run that touches REQs also gets `attempt` (§3.1) — the per-run retry count that the advisory escalation policy (Routing Guide §6.4) is tuned against.

## 5. Reading the results — `*metrics` and the derived numbers

```
/flow-master *metrics TechieBlog        (OpenCode — economy tier when routed)
/TechieFlow:agents:flow-master *metrics TechieBlog        (Claude Code)
```

writes `docs/metrics/METRICS.md` + `.html`. A real output line (TechieBlog, 2026-08-20):

```
Streams: runs 13 · gates 190 (0 backfilled) · sessions 13 · commits 93
First-pass rate: 80% (live, app — 121/151 REQs)
Gate catch: acceptance 53% (19/36) | Escape rate: 0% (0/34)
```

How to read the headline numbers:

- **First-pass rate 80%** — 121 of 151 REQs passed verification on attempt 1. The single best proxy for "is the pipeline producing right-first-time work". Falling? Look at the gate distribution to see *where* it fails.
- **Gate catch: acceptance 53%** — of all first-failures, the acceptance gate caught half. A healthy pattern: failures caught early (build/acceptance) are cheap; failures caught late (visual) or never (escaped) are expensive.
- **Escape rate 0%** — nothing graded `Verified` was later demoted by a human-found bug. This is the number the whole gate system exists to keep at zero.
- **Rework ratio** (in the full report) — the share of runs with `mode:"fix"`. This is the number that judges the routing tier map: cheaper builders are only cheaper if this doesn't climb.

Derived numbers are **computed at report time and never stored** — so a definition fix corrects all of history, and stored records never contain a stale formula.

## 6. The rules that keep the data trustworthy

- **Provenance never merges.** No report pools live records with backfilled ones, `app` projects with `library` ones, or dollar figures across harnesses (Claude cost is `null`; a pooled sum would silently understate). `tf-metrics.sh` enforces this in code.
- **Privacy — assume every record could leak.** Records carry ids, counts, durations, verdicts and file paths at most. Never requirement text, never prompt text, never file contents, never commit subjects. `failure_class` is a closed vocabulary for exactly this reason.
- **Telemetry has no veto.** Every writer exits 0 unconditionally. A telemetry bug can cost a record, never a working session.
- **Append-only.** Records are never edited or deleted; corrections happen at read time.
- **Agents never write what they can't know.** `harness` is detected, `attempt` is computed, tokens come from the harness store, commits come from your own hook.

## 7. Where everything is wired (so nothing is a black box)

| Piece | File | Trigger |
|---|---|---|
| The append primitive | `.tfcore/utils/tf-emit.sh` | called by every writer below |
| Run/gate records | emit steps inside each task (`build-phase` §7a, `verify-phase` §6a, …) | the status gate at the end of a run |
| Claude session totals | `.tfcore/hooks/metrics-session.sh` | `SessionEnd` hook |
| Claude session pointer (token attribution) | `.tfcore/hooks/session-pointer.sh` | `SessionStart` + `UserPromptSubmit` hooks |
| OpenCode sessions + pointer + cost | `.opencode/plugin/techieflow.js` | plugin `event` hook (message updates, session idle) |
| Commit records | `.tfcore/telemetry/pre-commit` | your own `git commit` |
| The report | `.tfcore/telemetry/tf-metrics.sh` via the `metrics-report` task | `*metrics {App}` |

## 8. FAQ

- **"sessions.jsonl is empty on this machine."** Claude side writes on `SessionEnd`; OpenCode side needs the plugin (deployed by `update-framework.sh` since 2026-08-20). An empty stream means "not collected here", never "no work happened".
- **"cost_usd is null everywhere."** On Claude Code that is permanent and deliberate — no real cost source exists and the framework never estimates. Real dollars come from OpenCode runs.
- **"commits.jsonl is empty / behind."** It fills only from YOUR commits on THIS clone; the reconcile catches up on your next commit. **No hook is required either way** — `.tfcore/telemetry/tf-metrics.sh --backfill-commits .` reconstructs the identical data from the commit log at any time, and reconstructs it *perfectly* (that log is itself append-only, which is why commit records are the one backfill exempt from the live-vs-backfilled separation). The hook only makes it automatic.
- **"Do I need the commit hook to get metrics at all?"** No. **Four of the five streams need no version-control hook whatsoever**: `runs`, `gates` and `misses` are written by `tf-emit.sh` from the phase tasks, and `sessions` by the Claude Code `SessionEnd` hook (or the OpenCode plugin) — neither of those is a version-control hook. Only `commits.jsonl` uses `.git/hooks/pre-commit`, and only for commit volume and cadence. Nothing about *what was missed, who missed it, or what the fix cost* depends on it.
- **"My project reports as `docs` but it is clearly an app."** A greenfield repo is classified at scaffold time, when it genuinely is docs-only — no `src/`, no `.csproj`. Since 2026-08-28 a later `update-framework.sh` **upgrades** a `docs` classification once real heads appear, and only ever upwards (`app`/`library`/`framework` are never re-guessed, and `--type` always wins). Correct it by hand at any time with `.tfcore/telemetry/install-metrics.sh . --type app`. **Records already written keep the old value** — the streams are append-only and corrections happen at read time — so the project shows under both segments until the old records age out, and `--report` states the split rather than letting one project look like two.
- **"Two sessions records with the same session_id?"** OpenCode snapshot semantics (§3.3) — take the record with the highest `output_tokens`.
- **"Can I trust a `Verified` in the checklist?"** That's what `gates.jsonl` + the `guard-verify.sh` hook exist for: a `Verified` can only be written after an executed verify run left its ledger — self-attestation is blocked mechanically on both harnesses.
- **"What does this cost me?"** Nothing at run time (one process spawn per record) and nothing when it breaks (no veto). The streams are a few KB per week of heavy use.

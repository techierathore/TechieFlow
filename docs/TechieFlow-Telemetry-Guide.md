# TechieFlow Development Telemetry Guide

**Audience:** the framework owner. **TL;DR:** the framework measures its own development process — first-pass quality, where gates catch problems, what escapes to you, and (since 2026-08-20) which model did the work and what it cost. **Reference docs:** `.tfcore/telemetry/SCHEMA.md` (the field-by-field contract) · `docs/TechieFlow-Telemetry-Runbook.md` (the original implementation record) · `docs/TechieFlow-Routing-Guide.md` (how the model/cost fields feed routing decisions).

## 1. Why this exists — the three questions

TechieFlow used to produce all this evidence and throw it away: every `*verify` applied named gates to identified REQs, wrote its ledger — and the next run overwrote everything. The status table mutates in place, so history evaporated.

Telemetry keeps that evidence in **append-only JSONL streams** under `docs/metrics/` (tracked in git, one JSON object per line, never rewritten). It exists to answer exactly three questions:

1. **First-pass rate** — how often does a REQ pass verification on its first attempt?
2. **Gate catch distribution** — *which* gate catches the problems (build? acceptance? data-render? visual? perf? standards?)
3. **Escape rate** — how much gets past all gates and is found by a human (UAT/production)?

Everything else (throughput, rework ratio, cost per phase) is derived from the same records.

## 2. The four streams at a glance

| File | One record per… | Written by | When |
|---|---|---|---|
| `docs/metrics/runs.jsonl` | framework command run (a `*build-phase`, a `*verify`, …) | the phase task, at its status gate | end of every run |
| `docs/metrics/gates.jsonl` | REQ verdict per verify run — **the primary stream** | `verify-phase` §6a (and `triage-issues` for escapes) | every time a REQ is graded |
| `docs/metrics/sessions.jsonl` | agent session (token totals) | Claude: `SessionEnd` hook · OpenCode: the `.opencode/plugin/techieflow.js` plugin | session end / session idle |
| `docs/metrics/commits.jsonl` | git commit | YOUR own `pre-commit` hook (agents never run git) | your commits |

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

## 4. How model, tokens and cost get onto run records (the 2026-08-20 upgrade)

No agent ever reports its own token usage (it can't know it, and self-reports drift). Instead `tf-emit.sh` reads the **harness's own store** at append time:

| Harness | Where the numbers come from | Scope |
|---|---|---|
| Claude Code | The session transcript (JSONL on disk), located via a pointer file that a `SessionStart`/`UserPromptSubmit` hook maintains at `.tfcore/.session/claude-code.json`. Subagent transcripts sit at a deterministic path next to it and are included automatically. | `tokens_scope:"tree"` (or `"main"` if the run spawned no subagents) |
| OpenCode | The `opencode.db` SQLite database, located via the pointer the plugin writes; the query covers the session **and all its child sessions**, and includes the provider's real per-message cost. | `tokens_scope:"tree"`, `cost_usd` real |

Any record carrying `started` + `ended` gets the numbers for exactly that window. If anything is missing — no pointer, unreadable store, empty window — the record says `tokens_scope:"none"` and carries **no numbers at all**. Missing beats invented, every time.

When routing is enabled (`docs/TechieFlow-Routing-Guide.md`), the same enrichment adds `tier` (declared), `tier_model` (what the tier should resolve to here) and `routed` (`model == tier_model`) — which is how routing decisions get made from data.

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
- **"commits.jsonl is empty / behind."** It fills only from YOUR commits on THIS clone; the reconcile catches up on your next commit.
- **"Two sessions records with the same session_id?"** OpenCode snapshot semantics (§3.3) — take the record with the highest `output_tokens`.
- **"Can I trust a `Verified` in the checklist?"** That's what `gates.jsonl` + the `guard-verify.sh` hook exist for: a `Verified` can only be written after an executed verify run left its ledger — self-attestation is blocked mechanically on both harnesses.
- **"What does this cost me?"** Nothing at run time (one process spawn per record) and nothing when it breaks (no veto). The streams are a few KB per week of heavy use.

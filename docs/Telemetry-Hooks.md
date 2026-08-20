# Telemetry Hook Points — per-phase model, tier, tokens, attempt, verdict

**Date:** 2026-08-19 · **Scope:** Task 5 · **Feeds:** the existing telemetry design (`.tfcore/telemetry/SCHEMA.md`, `_metrics-emit-gate.md`, DECISIONS.md 2026-08-08). **Inputs:** `Capability-Matrix.md` row (i), `Adapter-Design.md` §2.4 (session pointer), §5 (tiers).

> **Implementation status (2026-08-20, final):** EVERYTHING in this design is implemented and live-tested. OpenCode §3: `.opencode/plugin/techieflow.js` emits `sessions.jsonl` with real `cost_usd` + `children_sessions` (cumulative snapshot per root idle; dedupe rule in SCHEMA.md §4) and writes `.tfcore/.session/opencode.json`; `tf-emit.sh` honors `TF_HARNESS` first. Claude §2: `session-pointer.sh` wired to `SessionStart` + `UserPromptSubmit` writes `.tfcore/.session/claude-code.json`. Per-run window: `tf-emit.sh` `enrich_run()` adds the §4 fields (`tier`, `tier_model`, `model`, `models`, `routed`, `tokens_*`, `cost_usd`, `tokens_scope`) to `runs`/`gates` records carrying `started`+`ended` — tested against the real Claude transcript (scope `main`, `cost_usd:null`) and the real `opencode.db` (scope `tree`, real cost, session-tree rollup via `parent_id`); fallback `tokens_scope:"none"` verified. SCHEMA.md §2.5 documents the fields. **Probed 2026-08-20 (second round):** Claude `SubagentStop` is **VERIFIED** — the payload's `transcript_path` is the *parent's*, but a dedicated **`agent_transcript_path`** field names the subagent's own transcript at the deterministic path `<transcript-dir>/<session-id>/subagents/agent-<id>.jsonl`, in the same JSONL/`message.usage` format. Because the path is deterministic, `tf-emit.sh` includes subagent transcripts by globbing beside the pointer transcript — **no hook needed** — so Claude runs now report `tokens_scope:"tree"` whenever a subagents dir exists (`"main"` otherwise); live-tested against a real subagent session. OpenCode: a routed command's model is **verified persisted on the session row** (state-level check), so model-less `run -c`/SDK continuations inherit the command's tier as designed; and two `task` calls in one assistant message are **verified CONCURRENT** (child sessions 35ms apart, ~6s overlapped busy windows — build-phase's one-turn parallel fan-out works, no experimental flag). **The last sliver closed 2026-08-20 (owner TUI test):** the TUI does NOT re-impose its own selection — a plain follow-up after a routed command **continues on the command's model** (db-confirmed: the routed session ran and stayed on the tier model). Nothing in this design remains unverified. Owner-facing consequence documented in README/WORKFLOW §17b: switch models via the model list (or a new session) after a routed phase if you keep chatting.

**Required minimum record:** `phase, model, tier, tokens_in, tokens_out, attempt, gate_verdict, project_type, timestamp`.

**Doctrine carried forward unchanged:** telemetry has no veto; nothing is estimated from a rate card; no content is ever recorded; provenance never merges; `harness` is detected, never declared.

---

## 1. Where each field already lives, and what is missing

| Required field | Today | Stream | Gap |
|---|---|---|---|
| `phase` | `runs.cmd` (`SCHEMA.md:80`); `gates.run_id` joins a verdict to its run | runs / gates | none |
| `attempt` | `gates.attempt` = 1 + prior live gate records for the same REQ (`SCHEMA.md:129-145`); `runs.mode` = `build\|fix` is the run-level rework flag | gates / runs | none — **attempt is per REQ, by design**; a run-level "attempt" is `mode:"fix"` |
| `gate_verdict` | `gates.verdict` + `gate` (first failing) + `gates_run` (`SCHEMA.md:122-124`) | gates | none |
| `project_type`, `timestamp` | injected by `tf-emit.sh` (`SCHEMA.md:30-34`) | all | none |
| `model` | only `sessions.model` (last assistant message), Claude only | sessions | **missing on runs/gates; missing entirely on OpenCode** |
| `tier` | nowhere | — | **missing** (no routing exists yet) |
| `tokens_in`, `tokens_out` | only `sessions.*_tokens`, Claude only, whole session | sessions | **missing per run; session ≠ run (`SCHEMA.md:225`)** |
| `cost_usd` | always `null` (`SCHEMA.md:223`) | sessions | OpenCode can supply a real number |

So the work is: (1) a per-run **token/model window** on both harnesses, (2) a declared **tier** stamped next to the observed model, (3) the **session stream on OpenCode**. Nothing about attempt/verdict changes.

---

## 2. Capture points — Claude Code

| What | Hook / source | Data available there | Writes |
|---|---|---|---|
| Session totals (exists) | `SessionEnd` hook → `metrics-session.sh` | `session_id, transcript_path, cwd, reason`; transcript lines `type:"assistant"` with `message.model`, `message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}`, `timestamp` (confirmed by the existing script against real transcripts; the format is documented as internal — [sessions](https://code.claude.com/docs/en/sessions.md)) | `sessions.jsonl` |
| **Session pointer (new)** | `SessionStart` hook (matchers `startup\|resume\|clear\|compact`; payload may carry `model` — [hooks](https://code.claude.com/docs/en/hooks.md)) and/or `UserPromptSubmit` (no matcher; fires every prompt) | `session_id`, `transcript_path`, `cwd` | `.tfcore/.session/claude-code.json` = `{session_id, transcript_path, model?, ts}` (gitignored) |
| **Subagent transcripts (new, UNVERIFIED)** | `SubagentStart`/`SubagentStop` hooks carry `agent_id`, `agent_type` and the common fields; whether `transcript_path` there points at the *subagent's* transcript is not stated in the docs | if it does: one path per subagent | appended to the pointer file as `subagents: [{agent_id, agent_type, transcript_path}]` so the run window can include them. Test: fire a subagent, print the payload. |
| **Per-run window (new)** | **No hook** — the existing status-gate emit (`build-phase` §7a, `verify-phase` §6a, every task's `_status-update-gate` item 10) calls `tf-emit.sh runs\|gates` with `started`/`ended`; `tf-emit.sh` enriches: read the pointer file → sum assistant `usage` for records with `timestamp ∈ [started, ended]` → `tokens_*`, `model` (the id carrying the most output tokens), `models[]` if more than one | exact for the main thread; subagent tokens included only if the subagent path above verifies | `runs.jsonl`, `gates.jsonl` (same enrichment, same window = `run_id`) |
| Tier (new) | declared: `tf-harness.sh tier <cmd>` from `routing.yaml`; `tf-emit.sh` injects `tier` and `tier_model_expected` when routing is enabled | — | runs, gates |
| Bulk alternative | OTel (`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `api_request` events with tokens/model/cost, `prompt.id`) — [monitoring](https://code.claude.com/docs/en/monitoring-usage.md) | exact per request, full tree | needs a collector; **not proposed** for a solo WSL setup — documented as the upgrade path if the transcript format breaks |
| Headless only | `claude -p --output-format json` → `usage`, `model_usage` (full tree) — [headless](https://code.claude.com/docs/en/headless.md) | exact | only for scripted runs; not the daily loop |

**What Claude Code cannot give:** tokens inside a hook payload (none carries usage), dollar cost (`/usage` computes list-rate figures and the transcript has none — `cost_usd` stays `null`, as today), and — pending the SubagentStop test — per-subagent attribution. **Fallback when the window cannot be computed** (pointer missing, transcript unreadable, clock skew): the run record carries `tokens_scope:"none"` and `tokens_*: null`; `duration_s` and `subagents[]` remain as the only cost proxies. Never estimated.

## 3. Capture points — OpenCode 1.18.18

| What | Hook / source | Data available there | Writes |
|---|---|---|---|
| **Session totals (new)** | plugin `event` hook: `message.updated` with assistant `info.{modelID, providerID, agent, cost, tokens{input, output, reasoning, cache{read, write}}, variant}` (`packages/schema/src/v1/session.ts:453-485`, populated at each `step-finish`, `session/processor.ts:438-456`); end signal = `session.status` → `idle` for a **root** session (`session/status.ts:39-47`) plus plugin `dispose` | exact, per message, **real cost**, per child session (children have `parentID`; no automatic rollup — `task.ts:156-300`) | `sessions.jsonl` with `harness:"opencode"`, `cost_usd` real, `children_sessions: n`, child tokens rolled into the root by the plugin |
| **Session pointer (new)** | same plugin, on `session.created`/first `message.updated` | `sessionID`, `directory`, `opencode db path` (`~/.local/share/opencode/opencode.db`, `OPENCODE_DB` — `packages/core/src/database/database.ts:43-55`) | `.tfcore/.session/opencode.json` = `{session_id, db_path, ts}`; also `shell.env` injects `TF_SESSION_ID` so `tf-emit.sh` can skip the file when it has the env |
| **Per-run window (new)** | same emit call sites; `tf-emit.sh` queries SQLite read-only (python3 `sqlite3`, no extra binary): messages for `session_id` **and its children** (`session.parent_id`) with `time.created ∈ [started, ended]`, summing `tokens.*`, `cost`, grouping by `modelID` | exact, full tree, real cost | `runs.jsonl`, `gates.jsonl` |
| Tier | as Claude (declared from `routing.yaml`) | — | runs, gates |
| Fallbacks | `opencode export <id>` JSON (`cli/cmd/export.ts:223-232`) if the SQLite schema moves between versions (`packages/core/src/session/sql.ts:22-117` is internal); `opencode stats --project "" --days N` for owner-run reconciliation (`cli/cmd/stats.ts:52-68`); HTTP `GET /session/:id/message` when `opencode serve` is running | — | `tf-metrics.sh --ingest-opencode` (owner-run, append-safe on `session_id`) |

**What OpenCode cannot give:** nothing on this list — it is the richer side. The one caveat is schema stability of the SQLite tables (UNVERIFIED across versions; pin the query to `message.data` JSON fields, which are the public `AssistantMessage` shape, rather than to columns).

## 4. Proposed schema extension (additive; `v` stays 1 until a breaking change)

Fields added to **`runs.jsonl` and `gates.jsonl`** (all optional; absent = not captured, never `0`):

| Field | Type | Meaning | Source |
|---|---|---|---|
| `tier` | string \| null | Declared tier for `cmd` from `routing.yaml` (`frontier\|standard\|economy`) when routing is enabled | `tf-harness.sh tier` |
| `tier_model` | string \| null | The model id the tier *should* have resolved to on this harness | `routing.yaml` |
| `model` | string \| null | Observed dominant model id in the run window | transcript / SQLite |
| `models` | string[] | Present only if more than one model was observed (e.g. subagents on a different tier) | same |
| `routed` | bool | Present only when `tier_model` is set: `model == tier_model` | derived |
| `tokens_in`, `tokens_out`, `tokens_cache_read`, `tokens_cache_write` | int \| null | Σ over the window | same |
| `cost_usd` | number \| null | Σ real per-message cost (OpenCode); `null` on Claude Code | SQLite |
| `tokens_scope` | string | `main` (Claude, main thread only), `tree` (Claude with subagent transcripts / OpenCode root+children), `none` | derived |

`sessions.jsonl` gains `cost_usd` (real on OpenCode), `children_sessions`, and loses the hard-coded `harness` literal (detected, as everywhere else).

Example run record under OpenCode with routing on:

```json
{"v":1,"ts":"2026-08-20T09:41:02Z","kind":"run","app":"TrSetup","project_type":"app","cmd":"verify-phase",
 "mode":null,"started":"2026-08-20T09:12:40Z","ended":"2026-08-20T09:41:02Z","duration_s":1702,
 "reqs_touched":["REQ-UI-004","REQ-FN-011"],"reqs_count":2,"subagents":["tf-test-writer"],"build_result":"pass",
 "harness":"opencode","tier":"standard","tier_model":"anthropic/claude-sonnet-4-6","model":"anthropic/claude-sonnet-4-6",
 "routed":true,"tokens_in":184320,"tokens_out":41880,"tokens_cache_read":1204416,"tokens_cache_write":0,
 "cost_usd":1.93,"tokens_scope":"tree"}
```

Derived metrics (computed at report time, never stored — `SCHEMA.md` §8 rule): **tokens per Verified REQ by tier**, **first-pass rate by tier**, **rework ratio by tier**, **cost per phase** (OpenCode only — provenance rule: never pooled with Claude's `null` cost). `tf-metrics.sh` refuses to pool across harness for any dollar figure, exactly as it refuses across `project_type`.

## 5. Attempt / retry — nothing new, stated plainly

`attempt` stays on `gates.jsonl` per REQ (derive with `tf-emit.sh --next-attempt`, never guess); `runs.mode:"fix"` marks a rework pass. A **per-run retry counter** was considered and rejected: a build that loops §5 compile-fix three times is one run with one outcome; counting internal loops would need the agent to self-report, which `_metrics-emit-gate.md` constraint 8 forbids for good reason. If the owner wants "how many build passes until all-Verified", it is `count(runs where cmd=build-phase) between two verify runs that ended all-Verified` — computable from what exists.

## 6. Privacy and failure posture (unchanged)

Only counters, ids, model ids and timestamps are read from transcripts/SQLite — never message text, tool input or file paths (the Claude script already does this; the OpenCode query selects only `tokens`, `cost`, `modelID`, `time`). Every new path `exit 0`s silently; the session pointer and SQLite reads are best-effort. A failed enrichment yields `tokens_scope:"none"`, never a missing run record.

## 7. Council of experts — adversarial review

- **Data sceptic:** "A timestamp window over a shared transcript will mis-attribute tokens when the owner chats mid-phase." — True and bounded: the window is the phase's own `started..ended`, which is exactly the cost the owner incurred *for that phase*, chat included. The record says `tokens_scope`, and the report labels windows as "wall-clock attribution". Exact per-request attribution needs OTel (Claude) — documented as the upgrade, not assumed.
- **Harness engineer:** "Claude's transcript format is declared internal." — It is already the framework's source for `sessions.jsonl` and has been stable for the fields used; the design adds no new fields, only a time filter. If it breaks, enrichment degrades to `none` and the OTel path exists.
- **OpenCode maintainer:** "Reading `opencode.db` directly couples you to internal tables." — The query is pinned to the `message.data` JSON (the public `AssistantMessage` schema) with `opencode export` as the fallback; both are cited.
- **Cost accountant:** "Real cost on OpenCode and `null` on Claude means the two harnesses can never be compared in dollars." — Correct, and it is the existing provenance rule applied once more: tokens are comparable, dollars are not pooled. The Max subscription makes dollars the wrong unit on Claude anyway.
- **Red team:** "The session pointer is last-writer-wins; two concurrent sessions in one repo corrupt attribution." — Stated. Single-owner repos; the pointer carries `session_id` so `tf-emit.sh` can refuse when `TF_SESSION_ID` (OpenCode) disagrees; on Claude there is no env to cross-check, so the record is marked `tokens_scope:"none"` if the pointer is older than the run's `started`.
- **Minimalist:** "Do you need `tier_model`, `routed` *and* `model`?" — `model` is the fact; `tier` the intent; `routed` the one-bit answer the report prints. Three fields, all optional. Keep.

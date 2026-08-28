# TechieFlow Telemetry — Canonical Schema

> **Read this before emitting anything.** Every field, every enum, every known limitation.
> Doctrine (who writes what, and when) lives in `.tfcore/tasks/_metrics-emit-gate.md`.
> **Do not invent a field that is not on this page.** If a field seems needed, add it here first,
> with a rationale, then emit it.

**Schema version:** `v = 1`
**Location:** `docs/metrics/` inside each app repo — **tracked by git, never gitignored.**
**Streams:** `runs` · `gates` · `sessions` · `commits` · `misses` (§5.5, added 2026-08-28)
**Format:** JSONL — one JSON object per line, append-only. Never rewritten, never compacted, never sorted in place.

---

## 0. The questions this exists to answer

1. **First-pass rate** — what fraction of REQs reach `Verified` on attempt 1?
2. **Gate catch distribution** — of all failures, which gate caught them?
3. **Escape rate** — what fraction of defects reached UAT/production (`*triage-issues`) instead of being caught by a gate?
4. **Miss attribution and rework cost** (added 2026-08-28, §5.5) — *what* was missed, *which phase / agent / model* let it through, and *what did fixing it cost*?

Questions 1–3 are answered by `gates.jsonl`, which remains **the primary stream**; the rest is context. Question 4 is answered by `misses.jsonl` and is deliberately a *separate* stream on a *separate* unit: a gate record is a verdict at an instant, a miss is an object with a lifecycle that can span several runs — and can exist with no verify run at all, which is how design-phase misses become visible for the first time.

**Question 4 never redefines questions 1–3.** Escape rate keeps its existing definition and its existing source (`gates.jsonl` `gate:"escaped"`). The miss stream's own escape share is reported *beside* it, never merged into it. Two definitions of one word in one report is how a report loses its reader.

**Non-goal:** cycle-time-per-feature. The unit of work in this framework is **the run**, not the ticket. There is no per-feature timing field and there will not be one.

---

## 1. Fields present on EVERY record

| Field | Type | Values / notes |
|---|---|---|
| `v` | int | Schema version. Always `1` today. Injected by `tf-emit.sh` if absent. |
| `ts` | string | ISO-8601 UTC, second precision, `Z` suffix — e.g. `2026-08-08T04:12:33Z`. Injected by `tf-emit.sh` if absent. |
| `kind` | string | `run` \| `gate` \| `session` \| `commit` \| `miss` \| `miss-fix` \| `miss-amend`. Must be one of the kinds the stream file declares. Every stream but `misses.jsonl` declares exactly one, so for those "matches the file" and "is declared by the file" are the same rule; `misses.jsonl` declares three (§5.5). |
| `app` | string | The `{AppName}` the record belongs to. Injected by `tf-emit.sh` if absent — inferred from the one `docs/<App>-Checklist.md`, falling back to the repo directory name. Emitters should still pass it explicitly. |
| `project_type` | string | `app` \| `library` \| `docs` \| `framework`. Injected by `tf-emit.sh` — from the tree shape for `framework`, otherwise from `core-config.yaml`. |
| `project_type_inferred` | bool | Present **only when `true`** — `metrics.project_type` was absent from `core-config.yaml` and `app` was assumed. Reports must label these records **unclassified**, never silently pool them. |
| `backfilled` | bool | Present **only when `true`** — the record was reconstructed after the fact, not written at the moment of the event. Written exclusively by `tf-metrics.sh --backfill-*`. |
| `inferred` | string[] | Present only on backfilled records. Names the fields that were **guessed rather than read**. |
| `harness` | string \| null | `claude-code` \| `opencode` \| `codex` \| `null`. **Detected by `tf-emit.sh`, never declared by a task** — see below. |

### `project_type` — what it is and why it exists

Read from `core-config.yaml → metrics.project_type` (a **preserved** per-project file, so the classification survives every `update-framework.sh`). It is auto-detected once by the framework scripts and then never re-guessed; correct a wrong guess with `.tfcore/telemetry/install-metrics.sh . --type <type>`.

**One exception, and it is structural rather than configured (added 2026-08-28).** A repo containing `scaffold-brownfield.sh` beside `.tfcore/tasks/` **is** the TechieFlow template — nothing else can be, and a scaffolded app never has those at its root. `tf-emit.sh` and `tf-metrics.sh` therefore check that shape **first and authoritatively**, ahead of `core-config.yaml`, and `install-metrics.sh` writes nothing in that case.

The reason is worth recording, because the obvious implementation is a live defect: the scaffolds copy `.tfcore/` with `rsync -a --ignore-existing`, so the framework's own `core-config.yaml` lands verbatim in every new app — and an existing classification always beats the heuristic. Writing `project_type: framework` into that file would silently stamp `framework` on **every app scaffolded afterwards**, pooling them wrongly in every segmented figure with nothing in the output to reveal it. Detecting the framework from its tree shape means it can classify itself with nothing to leak.

| Value | Meaning | Gate availability |
|---|---|---|
| `app` | Has runtime screens. | All four gates apply. (`TrSetup`, `TrStudio`, `AstroLyfe`, `AppManager`) |
| `library` | NuGet package, no screens. | The §4b visual-truth gate **never fires**. (`TechieRag`, `TrBlazeUI`) |
| `docs` | Markdown / spec repo. | Verify degrades to `STATIC-ONLY` — effectively no gates. |
| `framework` | TechieFlow / AI-First-Playbook themselves. | As `docs`. |

Gate-catch distribution is only meaningful across projects where the same gates *could* fire. A `library` run cannot fail the visual gate, so pooling it understates that gate's catch rate. See §5.

If `metrics.project_type` is absent: default to `app` **and** set `project_type_inferred: true`. Flag it in the report as unclassified. Never silently assume.

#### `docs` at scaffold time is not a classification — it is the absence of one (fixed 2026-08-28)

`scaffold-greenfield.sh` runs `install-metrics.sh` **at scaffold time**, when a greenfield repo is by definition docs-only: the day-1 documents exist and `src/` does not. `detect_type()` correctly answers `docs`, writes it, and "auto-detected once, then never re-guessed" freezes it there. **Every greenfield project was therefore born labelled `docs`** and stayed that way until somebody noticed. TfLens accumulated **225 gate records, visual gates included, under a `project_type` whose own definition says gates cannot fire** — and whose figures, per §6, never pool with the apps it belongs beside.

So `install-metrics.sh` now re-examines **`docs` alone**, on a later refresh, and **only upgrades**: once real heads or a published package appear, the tree has answered a question that was unanswerable at scaffold time. `app` / `library` / `framework` are never re-guessed, an owner's `--type` always wins, and a genuine docs repo never grows a head so it is never touched.

**Records already written keep the old value.** The streams are append-only; a correction is applied at **read time**, never by rewriting history (§6). A reclassified project therefore appears under **both** segments, which §6 forbids pooling — so `tf-metrics.sh --report` states the split explicitly rather than letting one project look like two. Read each segment as a period of the project, not as the whole of it.

### `harness` — detected, never declared

The framework runs under **three harnesses**: Claude Code (`.claude/commands/TechieFlow/`), OpenCode (agents/tasks loaded from `opencode.jsonc`), and Codex (`.agents/skills/` plus `.codex/agents/`). The task content is identical across harnesses. A task template therefore **cannot know which one is executing it** — an agent copying a literal from the markdown would stamp whichever harness the example happened to name, and every per-harness comparison would be quietly wrong.

So `tf-emit.sh` detects it and injects it. **Never write `harness` into an emit template.** Detection order:

1. the adapter-owned `TF_HARNESS`, then harness environment variables (`CLAUDECODE`, `CLAUDE_CODE_*` → `claude-code`; any `OPENCODE*` → `opencode`; Codex thread/session markers → `codex`);
2. the parent process chain, bounded to 12 levels (OpenCode sets no `OPENCODE_*` variables, so the process name is the only honest signal);
3. **`null`** if neither resolves.

`null` is deliberate. A wrong harness label corrupts every comparison built on it; a missing one is merely missing.

---

## 2. `docs/metrics/runs.jsonl` — one record per framework command run

```json
{"v":1,"ts":"2026-08-08T04:12:33Z","kind":"run","app":"TrSetup","project_type":"app","cmd":"build-phase",
 "mode":"build","started":"2026-08-08T03:41:02Z","ended":"2026-08-08T04:12:33Z",
 "duration_s":1891,"reqs_touched":["REQ-UI-004","REQ-FN-011"],"reqs_count":2,
 "subagents":["trblazeui"],"files_written":14,"build_result":"pass","harness":"claude-code"}
```

| Field | Type | Values / notes |
|---|---|---|
| `cmd` | string | `day1-brownfield` \| `day1-greenfield` \| `split-brd` \| `mockups` \| `build-phase` \| `verify-phase` \| `fix-issues` \| `triage-issues` \| `log-miss` \| `devguide` \| `productguide` \| `handoff-phase` \| `refresh-status` \| `amend-docs` |
| `mode` | string \| null | `build` \| `fix`. `build-phase` already distinguishes these (FIX mode) — capture it; the ratio is the rework metric. `null` for commands with no mode. |
| `started` | string | ISO-8601 UTC. When the task began — the timestamp you noted at step 0, not "now minus a guess". |
| `ended` | string | ISO-8601 UTC. Normally equal to `ts`. |
| `duration_s` | int | `ended − started`, whole seconds. |
| `reqs_touched` | string[] | REQ IDs the run acted on. IDs only — **never** requirement text. |
| `reqs_count` | int | `len(reqs_touched)`. |
| `subagents` | string[] | Sub-agents invoked: `trblazeui` \| `techierag` \| `verifier` \| `general-purpose` (Claude) \| `general` (OpenCode) \| `tf-builder` \| `tf-test-writer` \| `tf-explorer`. Empty array if none. |
| `files_written` | int | A count the agent **already knows**. Do not shell out to compute it. |
| `build_result` | string \| null | `pass` \| `fail` \| `not-run`. |
| `harness` | string \| null | Injected by `tf-emit.sh` (§1). **Do not emit it yourself.** |

---

### 2.5 Per-run routing + token fields (added 2026-08-20; injected by `tf-emit.sh`, never emitted by an agent)

`tf-emit.sh` enriches `runs` and `gates` records at append time (docs/Telemetry-Hooks.md §2–§4). All fields are **optional — absent means "not captured", never `0`**:

| Field | Type | Meaning / source |
|---|---|---|
| `tier` | string | Declared tier for `cmd` from `.tfcore/routing.yaml` — injected only when routing is `enabled: true`. |
| `tier_model` | string | The model id the tier should have resolved to on this harness (from `routing.yaml` `tiers`). |
| `model` | string | **Observed** dominant model in the run window (most output tokens). Claude: transcript `message.model`; OpenCode: `providerID/modelID` from `opencode.db`. |
| `models` | string[] | Present only when more than one model was observed in the window. |
| `routed` | bool | `model == tier_model`. Present only when both are known. Routing is observed, never enforced — `routed:false` is drift made visible, not an error. |
| `tokens_in`, `tokens_out`, `tokens_cache_read`, `tokens_cache_write` | int | Σ over assistant messages whose timestamp ∈ [`started`, `ended`]. Requires the record to carry `started` + `ended` and the session pointer (`.tfcore/.session/<harness>.json` — written by the `session-pointer.sh` hook on Claude, by the plugin on OpenCode). |
| `cost_usd` | number \| null | Σ real per-message cost from `opencode.db` on OpenCode; **always `null` on Claude Code** (the transcript has no cost and a rate-card estimate would be an estimate presented as a measurement). |
| `tokens_scope` | string | `tree` = the full session tree — OpenCode: pointer session + descendant sessions; Claude: pointer transcript + the subagent transcripts beside it (`<transcript-dir>/<session-id>/subagents/agent-*.jsonl`, a deterministic path verified 2026-08-20 via a `SubagentStop` payload's `agent_transcript_path`). `main` = Claude main thread only (no subagents dir existed). `conversation` = an exact persisted Codex rollout counter bounded by documented conversation events; measured session data, not an estimate. `none` = window could not be computed (no pointer / unreadable store / empty window) — **tokens are never estimated**. |

| `attempt` | int | **`runs` only, added 2026-08-21.** `1 +` the number of prior non-backfilled `run` records with the same `cmd` whose `reqs_touched` intersects this record's. Stamped only when the record carries a non-empty `reqs_touched`; absent on backfilled records and on REQ-less runs (`metrics-report`, renders). Distinct from the gate-level `attempt` in §3.1 (per REQ per verify). This is the counter `routing.yaml` `escalation:` reads **at launch** — `bash .tfcore/utils/tf-emit.sh --next-run-attempt <cmd> <REQ-ID>...` prints the value the next record would get. Advisory: telemetry records, it never switches a model (DECISIONS.md 2026-08-21). |

Provenance rule applied once more: **never pool `cost_usd` across harness** — Claude records are `null`, and a sum over mixed records silently under-reports. Tokens may be compared across harness; dollars may not.

## 3. `docs/metrics/gates.jsonl` — one record per REQ verdict per verify run

**This is the primary stream.** If only one stream survives, it is this one.

Pass:

```json
{"v":1,"ts":"2026-08-08T04:10:07Z","kind":"gate","app":"TrSetup","project_type":"app",
 "run_id":"2026-08-08T03:41:02Z","req_id":"REQ-UI-004","req_class":"UI","attempt":2,
 "verdict":"Verified","gate":null,"gates_run":["acceptance","render","visual","standards"],
 "prior_verdict":"Needs re-verify"}
```

Failure:

```json
{"v":1,"ts":"2026-08-08T04:10:07Z","kind":"gate","app":"TrSetup","project_type":"app",
 "run_id":"2026-08-08T03:41:02Z","req_id":"REQ-UI-009","req_class":"UI","attempt":1,
 "verdict":"FAIL","gate":"visual","gates_run":["acceptance","render","visual"],
 "failure_class":"overlap","prior_verdict":"Implemented"}
```

| Field | Type | Values / notes |
|---|---|---|
| `run_id` | string | The `started` timestamp of the owning run. Ties every REQ verdict in one verify pass together. |
| `req_id` | string | e.g. `REQ-UI-004`. |
| `req_class` | string | `UI` \| `FN` \| `RAG` \| `NFR` — the prefix segment of `req_id`. |
| `attempt` | int | See §3.1. Derive it; never guess it. |
| `verdict` | string | Mirrors the checklist vocabulary **exactly**: `Verified` \| `Needs re-verify` \| `FAIL` \| `Blocked` \| `Implemented` \| `Done (pre-existing)`. |
| `gate` | string \| null | **The FIRST gate that failed**, or `null` on a pass. See §3.2. |
| `gates_run` | string[] | Which gates actually executed this pass — subset of `["build","acceptance","render","visual","perf","standards"]`, in execution order. A gate absent here did **not** run and cannot be credited or blamed. For `perf` this carries real weight: see §3.5. |
| `failure_class` | string \| null | Controlled vocabulary only, §3.3. `null` on a pass. |
| `prior_verdict` | string \| null | The Status cell value **before** this run wrote over it. `null` if the row is new. |
| `proof` | string \| null | Optional, §3.4. |

### 3.1 `attempt` — the field first-pass rate depends on entirely

`attempt` = **1 + the number of prior non-backfilled `gate` records in `docs/metrics/gates.jsonl` for the same `req_id` in the same `app`.**

Derive it by counting. Never guess, never "probably 1".

Use the helper — it is the only supported way:

```bash
.tfcore/utils/tf-emit.sh --next-attempt REQ-UI-004      # prints an integer on stdout
```

**Backfilled records are excluded from the count**, deliberately. A backfilled `attempt` is itself inferred (§7), so counting it would propagate a guess into a live record. The consequence is stated plainly rather than hidden:

> On an app that was backfilled, the first *live* verify of a pre-existing REQ records `attempt: 1` even though it is not truly that REQ's first attempt.

That is why **`*metrics` excludes any REQ that has *any* backfilled record from the live first-pass rate** (see §5). The exclusion is the fix; the field is not silently corrected.

### 3.2 `gate` — the single field that produces the gate catch distribution

Get this right; everything else on the record is secondary.

| Value | The assertion that failed |
|---|---|
| `build` | The code did not compile / the app did not boot. Nothing downstream ran. |
| `acceptance` | The REQ's acceptance test ran and failed (Playwright spec, `dotnet test`). |
| `render` | verify-phase §4a data-render gate — a control is `RENDER-EMPTY` / `RENDER-ERROR` (blank table, count-vs-rows mismatch, empty chart). |
| `visual` | verify-phase §4b visual-truth gate — overlap, clip, off-viewport, unstyled fallback, mockup drift. |
| `perf` | verify-phase §4c performance gate — measured p95 exceeded the REQ's declared `perf-budget:` by more than 25%. **Added 2026-08-10; see §3.5 before reading its share of the distribution.** |
| `standards` | The standards grep — naming/prefix/structure violation against `docs/{AppName}-Coding-Standards.md`. |
| `escaped` | **Not a gate.** A defect that reached UAT/production and was logged by `*triage-issues` — i.e. *every* gate missed it. This value is what makes escape rate computable. Written only by `triage-issues.md`. |
| `null` | Nothing failed. |

**"First" means first in execution order** (`build` → `acceptance` → `render` → `visual` → `perf` → `standards`). If a REQ fails render *and* visual, `gate` is `render`. Recording the later one inflates the visual gate's apparent catch rate.

`gate: "escaped"` is deliberately in the same field rather than a separate one: escape rate is "which gate caught it — none of them", and keeping it on one axis means a single `group by gate` answers questions 2 and 3 together. Reports must nonetheless present `escaped` as its own row, never folded into a gate's share.

### 3.3 `failure_class` — controlled vocabulary, no free text

`blank-data` · `zero-rows` · `overlap` · `clipped` · `offscreen` · `slow-ttfb` · `slow-load` · `timeout` · `exception` · `assert-fail` · `naming` · `build-error` · `other`

If none fits, use `other`. **Do not** write a description. Free text here would leak requirement and client detail — the exact thing constraint 8 forbids.

`slow-ttfb` / `slow-load` / `timeout` (added 2026-08-10) name *which metric* the budget was written against, or — for `timeout` — that the run failed by shedding load rather than by being slow (requests never completed at the declared concurrency). Nothing more. **Never record the measured milliseconds anywhere in a record.** A latency figure is a property of one machine on one day — these streams are read across hosts and pooled across months, so a number here would be compared with numbers it was never comparable to. The measurement itself belongs in the run's JSON under `tests/.artifacts/perf/` and in the checklist Remark a human reads.

### 3.4 `proof` — optional, cross-edition

`executed` \| `code-audit` \| `null`.

Reserved for the shared schema with the AI-First-Playbook team edition (see §8). TechieFlow's solo edition emits `executed` normally; it may emit `code-audit` **only** where a run stamped `⚠ STATIC-ONLY` because a runtime bridge was unreachable. It never converts a `code-audit` proof into a `Verified` verdict — `guard-verify.sh` already refuses that.

### 3.5 Gates added after the stream started — read their share against `gates_run`, never against the total

`perf` entered the enum on **2026-08-10**, long after `gates.jsonl` started collecting. Every record written before that date had **zero chance** of recording `gate:"perf"`, and even after it, most records still will not: the gate fires only for a REQ carrying a `perf-budget:`, never for a native head, and never on a Debug build or a thin sample (`verify-phase` §4c).

So the raw gate catch distribution — a `Counter` over `gate` across all failures — **understates `perf` structurally**, and the size of the understatement is not knowable from that count alone. The correct denominator is *records that actually ran the gate*:

```
perf catch rate = failures with gate="perf"  ÷  records with "perf" in gates_run
```

This is why `gates_run` must be populated truthfully rather than padded with every gate name. Listing `perf` on a REQ that had no budget would silently inflate the denominator and drive the gate's apparent catch rate toward zero — the same class of error as recording a later failing gate in `gate`, and just as invisible after the fact.

**The rule for any future gate.** A gate added mid-stream carries this hazard permanently; the fix is never to backfill the old records with a verdict they never had. Instead: record its introduction date here, populate `gates_run` honestly, and let a report present its coverage (`n` records that ran it) beside its count. `tf-metrics.sh --report` prints exactly that for `perf` and refuses to print a share without it.

The reasoning, recorded because it will be questioned later: a gate distribution is a claim about *what catches what*. A gate that only ran on 6 of 400 records did not fail to catch things — it was not asked. Presenting those as the same number is the same indefensible merge the provenance rule (§5) forbids for backfilled data, arriving by a different route.

---

## 4. `docs/metrics/sessions.jsonl` — one record per agent session

```json
{"v":1,"ts":"2026-08-08T04:15:00Z","kind":"session","app":"TrSetup","project_type":"app",
 "harness":"claude-code","model":"claude-sonnet-4-6","duration_s":2210,
 "input_tokens":184320,"output_tokens":41880,"cache_read_tokens":1204416,"cost_usd":null}
```

Written by `.tfcore/hooks/metrics-session.sh`, wired to the **`SessionEnd`** hook event (verified present in Claude Code `2.1.226`; see `DECISIONS.md`). Never written by an agent.

> **OpenCode records (since 2026-08-20):** `.opencode/plugin/techieflow.js` (a local plugin file — auto-loaded by OpenCode, no npm install; the "npm plugin modules" premise in the old gap note was wrong, see DECISIONS.md 2026-08-19 §7) emits into this stream from the `message.updated` events, with **real `cost_usd`**, `children_sessions`, and child-session tokens rolled into the root by `parentID`. **Snapshot semantics differ from Claude:** the plugin appends a CUMULATIVE snapshot at every root-session idle (a TUI session idles after each turn; `opencode run` idles once), so several records may share a `session_id` — consumers take the record with the highest `output_tokens` (or the latest `ts`) per `session_id`. Claude Code records stay one-per-session via `SessionEnd` → `metrics-session.sh`. `opencode stats` / `opencode export` remain the owner-run reconciliation fallbacks.

| Field | Type | Notes |
|---|---|---|
| `session_id` | string | The harness session id from the hook payload. An opaque UUID — carries no content. |
| `model` | string \| null | The model id seen on the last assistant message in the transcript. |
| `duration_s` | int | Last transcript timestamp − first transcript timestamp. |
| `input_tokens` | int | Σ `usage.input_tokens` across assistant messages. |
| `output_tokens` | int | Σ `usage.output_tokens`. |
| `cache_read_tokens` | int | Σ `usage.cache_read_input_tokens`. |
| `cache_creation_tokens` | int | Σ `usage.cache_creation_input_tokens`. |
| `cost_usd` | number \| null | **Almost always `null`.** See the limitation below. |

**Known limitation — cost is not in the transcript.** Claude Code `2.x` transcripts carry token counts but no per-message dollar cost, and this framework runs on a Claude Max subscription where marginal per-token cost is not the real unit anyway. `cost_usd` is therefore emitted as `null` and *never* computed from a rate card — that would be an estimate presented as a measurement. Consequently **"cost per verified REQ" is reported in tokens, not dollars**, unless a real cost source appears. (OpenCode's `opencode stats` *does* report real cost — that is the one thing it can measure which Claude Code cannot. Wiring it in is the obvious way this field stops being `null`.)

**Known limitation — session ≠ run.** One session may span several commands, or one command several sessions. `sessions.jsonl` is **not** joinable to `runs.jsonl` on anything but time. Do not attribute a session's tokens to a single run.

---

## 5. `docs/metrics/commits.jsonl` — one record per commit

```json
{"v":1,"ts":"2026-08-08T09:30:11Z","kind":"commit","app":"TrSetup","project_type":"app",
 "sha":"a1b2c3d","files":9,"insertions":412,"deletions":57,"subject_prefix":"feat","branch":"main"}
```

Written by the repo's `pre-commit` hook (`.tfcore/telemetry/pre-commit`, installed by the framework scripts during a normal refresh — that install is a **file copy** and invokes no git), or reconstructed by `tf-metrics.sh --backfill-commits`. The hook runs inside the owner's own `git commit`. **No agent ever writes this stream.**

**The hook reconciles; it does not merely append.** It writes a record for **every** commit reachable from HEAD that the stream does not already carry, skipping on `sha`, then stages that one file so the records ship *inside* the commit being made. `--backfill-commits` is the same operation run by hand. Reconciling matters because a one-record-per-commit hook loses data in exactly the situation this portfolio lives in — one repo, several machines:

| Gap | Why an appending hook loses it | Why reconciling closes it |
|---|---|---|
| A clone with no hook (`.git/` is not part of the repository) records nothing, silently | Nothing to notice until you look | The first reconcile on that clone fills its whole history; `--report` also warns when the hook is absent |
| Commits made on the other machine while this one was idle | Never seen here | After a pull, they are in `git log`, so the next reconcile records them |
| Merge commits, `--no-verify`, rebase, cherry-pick — the hook does not run | Permanently unrecorded | The next ordinary commit sees them in the log and writes them |

**Why `pre`-commit, reversing the original design (owner decision, 2026-08-11).** `post-commit` can only describe commit N once N exists, so its line can never be *inside* N — `commits.jsonl` was dirty the moment every commit finished, permanently, with no reachable clean state (committing the pending line creates a new commit whose record is then pending). It also blocked `git pull` whenever the file had also changed upstream. Moving the write earlier costs one thing, stated plainly: **the hook stages a file into your commit.** Scope is exactly one path, `docs/metrics/commits.jsonl`; on a partial commit (`git commit -- <paths>`, detected via `GIT_INDEX_FILE`) it writes the record but does **not** stage, so it can never add a file to a commit you deliberately scoped down. A pre-commit hook that exits non-zero aborts the commit, so every path in it ends `exit 0` — telemetry still has no veto (§10).

**This hook is optional.** `--backfill-commits` reconstructs the identical data from `git log` at any time, and reconstructs it *perfectly* — see the exemption note below. Delete `.git/hooks/pre-commit` if you would rather not have a hook, and backfill before you want a report; nothing else in the schema changes.

**Files are `merge=union`** (`.gitattributes`, managed by the scaffold/update scripts). Two machines appending never conflict, so no record is ever lost to a hand-resolved merge. The cost is that a record can appear twice and line order stops being chronological — consumers sort on `ts`, and commit records de-duplicate on `sha`.

**Duplicate shas are expected, and are the other half of the union-merge trade.** Machine A commits `N`; A's *next* commit records `N` and carries it. If A has not pushed that yet by the time machine B pulls commit `N` itself, B's reconcile reconstructs the same record from the log. Both are now genuine lines in two branches of one file, and union merge — whose entire job is to never drop a line — keeps both. So:

- **Nothing is ever missing.** Whatever a machine failed to push, the next machine rebuilds from `git log`, because the log is what actually replicates.
- **Nothing is ever double-counted.** `tf-metrics.sh` de-duplicates commit records on `sha` at read time and prints how many it collapsed. `--backfill-commits` skips shas already present.

Only `commits.jsonl` needs this **for the union-merge reason**. `runs`/`gates` record events that happen on one machine and cannot be independently reconstructed elsewhere, so a union merge has no way to manufacture a second copy of them.

**`sessions.jsonl` is not in that set** (corrected 2026-08-27, TfLens TF-001). It has its own, unrelated duplication source — the OpenCode plugin appends a *cumulative* snapshot at every root-session idle (§4) — so several records legitimately share a `session_id` and only the largest is complete. Consumers de-duplicate it too, by the §4 rule: **highest `output_tokens` per `session_id`, ties broken on the latest `ts`, per repo**. `tf-metrics.sh` does this in `dedupe_sessions()`. Before that existed, this paragraph's scoped claim was read as "sessions never duplicate", and every session count and token total derived from them was silently overstated.

**Practical note:** the record for your latest commit is written by the *next* commit's hook, so between commits the file matches HEAD. Nothing pending, nothing blocking a pull.

| Field | Type | Notes |
|---|---|---|
| `sha` | string | Short sha. |
| `files` / `insertions` / `deletions` | int | From `--shortstat`. |
| `subject_prefix` | string \| null | First token of the subject **only if** it matches `feat\|fix\|docs\|chore\|refactor\|test\|build`, else `null`. **Never store the full subject** — subjects leak project detail. |
| `branch` | string | The branch **at the moment the record was written**, not necessarily the branch the commit was made on. Live records are written seconds later, so they are right; a record filled in by a reconcile — after a pull, or on a clone that had no hook — carries the reconciling clone's current branch. `git log` does not retain per-commit branch membership, so this cannot be recovered. Treat `branch` as approximate on anything but the newest record. |

**Known limitation — the one-commit lag.** At `pre-commit` time HEAD is still the *previous* commit, so the record for the commit being made ships inside the **next** one. Metrics lag reality by a commit. The lag is unavoidable in either direction — a record of commit N cannot predate N — but it is now *committed* rather than *pending*, so the working tree is clean when a commit finishes. And because the hook reconciles, the lag never becomes a *loss*: the missing record is written by whichever commit comes next, on whichever machine.

**Practical note:** `commits.jsonl` no longer carries a permanently pending line, so it no longer blocks a `git pull` the way the post-commit form did.

**Commit records are exempt from both provenance separations** (§6). `git log` is a real append-only log, so a backfilled commit is exactly as trustworthy as a live one; and commit volume/cadence is comparable across every `project_type`.

---

## 5.5 `docs/metrics/misses.jsonl` — what was missed, who missed it, what the fix cost

**Added 2026-08-28.** Design record: `docs/Miss-Telemetry-TechieFlow.md` (in the framework repo).

This is the only stream that carries **three record kinds**: `miss` opens, `miss-fix` closes, `miss-amend` completes a field the `miss` left `null` (§5.5.7). A miss has a lifecycle across runs, and appending lifecycle state to a verdict stream would mean editing records — which §6 and `_metrics-emit-gate.md` constraint 5 forbid outright. So the lifecycle is expressed as append-only records linked by `miss_id`, and nothing is ever rewritten.

### 5.5.1 `kind: "miss"`

```json
{"v":1,"ts":"2026-08-28T11:04:19Z","kind":"miss","app":"AstroLyfe",
 "project_type":"app","harness":"claude-code",
 "miss_id":"MISS-AstroLyfe-20260828-03","req_id":"REQ-UI-014","req_class":"UI",
 "miss_class":"partial-implementation","artifact":"src","severity":"major",
 "origin_phase":"build-phase","origin_agent":"trblazeui",
 "origin_run_id":"2026-08-26T09:12:40Z","origin_confidence":"linked",
 "origin_model":"claude-opus-5","origin_harness":"claude-code",
 "found_by":"gate","found_phase":"verify-phase","found_gate":"render",
 "found_run_id":"2026-08-28T10:41:02Z","failure_class":"blank-data"}
```

| Field | Type | Values / notes |
|---|---|---|
| `miss_id` | string | `MISS-<app>-<YYYYMMDD>-<NN>`. **Never invented** — `bash .tfcore/utils/tf-emit.sh --next-miss-id` prints it. The link key for `miss-fix`. |
| `req_id` | string \| null | The owning REQ. **`null` is meaningful**, not missing data: it means no REQ existed to miss, which is itself the finding. |
| `req_class` | string \| null | `UI` \| `FN` \| `RAG` \| `NFR` — the prefix segment of `req_id`. |
| `miss_class` | string | `missed-requirement` (in scope, never built) · `partial-implementation` (built, an acceptance bullet unmet) · `wrong-behaviour` (built, behaves other than specified) · `regression` (was `Verified`, now broken) · `unspecified-gap` (**the spec itself omitted it — the design-phase miss**) · `spec-contradiction` · `scope-creep` (built what nobody asked for) · `hallucinated-api` (used a library member that does not exist) · `standards-violation` · `other` |
| `artifact` | string | Which artifact was deficient: `brd` · `architecture` · `uidesign` · `checklist` · `devguide` · `src` · `tests` · `config` · `other` |
| `severity` | string | `blocker` · `major` · `minor` — **owner-visible impact, never an estimate of effort.** |
| `origin_phase` | string \| null | The `cmd` that should have produced it correctly — same enum as `runs.jsonl` `cmd` (§2). |
| `origin_agent` | string \| null | `analyst` \| `architect` \| `flow-master` \| `verifier` \| `trblazeui` \| `techierag` \| `tf-builder` \| `tf-test-writer` \| `general-purpose` \| `general` |
| `origin_run_id` | string \| null | The `started` timestamp of that run, **found in `runs.jsonl`**. Never guessed. |
| `origin_model` | string \| null | **Injected by `tf-emit.sh`** — looked up from the `runs.jsonl` record whose `started` equals `origin_run_id`. |
| `origin_harness` | string \| null | Same lookup, same rule. |
| `origin_confidence` | string | **Derived by `tf-emit.sh`, never written by an agent.** `linked` = `origin_run_id` resolved to a real `runs.jsonl` record · `inferred` = an `origin_phase` was named but no run record backs it · `unknown` = no origin named at all. **A provenance boundary — see §6.** |
| `why_missed` | string \| null | **Which practice failed** — see §5.5.6. Optional; `null` means "not assessed", never "nothing to say". |
| `found_by` | string | `gate` · `self-smoke` · `owner` (UAT / manual) · `production` · `agent-review` · `library-feedback` |
| `found_phase` | string \| null | The `cmd` that was running when it surfaced. |
| `found_gate` | string \| null | When `found_by == "gate"`, which gate — same vocabulary as §3.2. `null` otherwise. |
| `found_run_id` | string \| null | `started` of the finding run. |
| `failure_class` | string \| null | The §3.3 closed vocabulary, reused verbatim. `null` where none applies. |

**`origin_model`, `origin_harness` and `origin_confidence` are never written by an agent** — the same rule as `harness` (§1) and for the same reason: task markdown is shared byte-identically across three harnesses, so a copied literal would stamp the wrong model on every record and quietly corrupt every per-model comparison built on it. `tf-emit.sh` resolves all three from `origin_run_id`, and **forces `origin_model` / `origin_harness` to `null` whenever the lookup fails, overwriting anything the caller supplied.** A guess is worse than a gap here, because nothing downstream can see that it was one.

The agent's job on a `miss` record is therefore small and honest: name what was missed (`miss_class`, `artifact`, `severity`), name the phase it believes is responsible (`origin_phase`, `origin_agent`), and pass the `origin_run_id` if it found one in `runs.jsonl`. The emitter decides what that attribution is worth.

### 5.5.2 `kind: "miss-fix"`

```json
{"v":1,"ts":"2026-08-28T14:52:07Z","kind":"miss-fix","app":"AstroLyfe",
 "project_type":"app","harness":"claude-code",
 "miss_id":"MISS-AstroLyfe-20260828-03","req_id":"REQ-UI-014",
 "fix_run_id":"2026-08-28T13:58:11Z","fix_cmd":"fix-issues","fix_attempt":1,
 "verdict_after":"Verified","reopened":false,"cost_attribution":"shared:3",
 "tokens_in":812,"tokens_out":38104,"tokens_cache_read":286110,
 "tokens_cache_write":0,"cost_usd":null,"tokens_scope":"tree","model":"claude-opus-5"}
```

| Field | Type | Values / notes |
|---|---|---|
| `miss_id` | string | The link. A `miss-fix` matching no `miss` is reported as an **orphan** and counted, never silently dropped. |
| `req_id` | string \| null | Copied from the miss, for readability. |
| `fix_run_id` | string | `started` of the repair run. **This is where the cost comes from.** |
| `fix_cmd` | string | `fix-issues` \| `build-phase` \| `triage-issues` \| `amend-docs` \| `log-miss` |
| `fix_attempt` | int | `1 +` the count of prior `miss-fix` records for this `miss_id`. `tf-emit.sh --next-fix-attempt <miss_id>`. |
| `verdict_after` | string | `Verified` \| `Needs re-verify` \| `FAIL` \| `deferred` \| `wont-fix` |
| `reopened` | bool | `true` when this miss had already closed `Verified` and a later escape re-opened it. |
| `cost_attribution` | string | **Derived by `tf-emit.sh`** from the fix run's `reqs_touched`: `sole` \| `shared:<n>` \| `none` — §5.5.3. |
| `tokens_in`, `tokens_out`, `tokens_cache_read`, `tokens_cache_write`, `cost_usd`, `tokens_scope`, `model` | — | **Injected by `tf-emit.sh`** from the `fix_run_id` window, by exactly the §2.5 mechanism. Never written by an agent. `cost_usd` stays `null` on Claude Code and Codex, per §4. |

### 5.5.3 `cost_attribution` — the field the money number stands on

A fix run that repaired three misses has **one** token window. Dividing it three ways is arithmetic, not measurement, and this field is what keeps the difference visible.

| Value | Derived when |
|---|---|
| `sole` | The fix run's `reqs_touched` is exactly `[req_id]`. The whole window is this miss's cost. **This is a measurement.** |
| `shared:<n>` | The run touched *n > 1* REQs. The window covers all of them and cannot be split by anything the framework can observe. A report divides equally **and says so.** |
| `none` | The run's `tokens_scope` was `none`, or `fix_run_id` matched no run record at all (the fix happened inline, with no distinct run). **No numbers at all.** |

**Reporting rule, enforced in `tf-metrics.sh` code and not merely stated here:** a headline cost-per-miss figure is computed **only over `cost_attribution:"sole"` records.** Apportioned figures appear in a separate, labelled column and are never summed into the headline.

The limitation is stated rather than hidden: **a miss fixed inline during a long build session, with no distinct fix run, is unattributable.** It gets `none`, counts toward the miss count, and contributes nothing to the money. Missing beats invented.

### 5.5.4 Collapse — one defect is one miss, however many times it fails

A REQ that fails three verify passes must produce **one** miss, not three; otherwise the miss count measures retry patience rather than quality, and every distribution built on it is inflated.

> Before emitting a `miss`, look for an **open** miss on the same `req_id` in the same `app` — one with no `miss-fix` record, or whose latest `miss-fix` carries a `verdict_after` other than `Verified`. If one exists **and** its `miss_class` equals the one you would record, **emit nothing**: it is the same miss, still open. If the `miss_class` differs, emit a new `miss` — the REQ is now failing for a genuinely different reason, and that is new information.

```bash
bash .tfcore/utils/tf-emit.sh --open-miss REQ-UI-014
# prints "<miss_id> <miss_class>" if one is open, nothing otherwise
```

The check belongs to the emitter, never to an agent's judgement.

### 5.5.5 Relationship to `gates.jsonl` — additive, never substitutive

`gates.jsonl` is untouched by this stream: not one field, not one writer, not one definition. In particular `gate:"escaped"` keeps its exact meaning and its exact source in `triage-issues.md`, and **escape rate is still computed from it alone.** The miss stream's `found_by ∈ {owner, production}` share is a second, adjacent figure with its own name. A new stream that silently altered the meaning of an existing headline number would cost more trust than it bought.

### 5.5.6 `why_missed` — which *practice* failed (ported from the Playbook 2026-08-28)

`miss_class` says **what** was missed. `why_missed` says **which practice let it through** — and it is the more decision-changing of the two, because it tells you whether your *specification* or your *verification* is the weak one. That is a question no other field on any stream answers.

Ported from the AI-First-Playbook team edition, whose Phase 9 (`/analyze-fix`) has always produced exactly this judgement in prose — *"why did the Verifier miss it: missing checklist item? insufficient Verify method? code-audit limitation?"* — and thrown it away with the transient issues file.

| Value | The practice that failed |
|---|---|
| `missing-checklist-item` | No REQ, or no acceptance bullet, covered the behaviour at all. The spec had a hole. |
| `insufficient-verify-method` | A REQ and its acceptance existed, and the gate that ran **could not catch this class of defect**. The spec was fine; the test was too weak. |
| `code-audit-limitation` | The run was `⚠ STATIC-ONLY` — no runtime bridge — so the defect was never observable, whatever the gate said. |
| `ambiguous-acceptance` | The acceptance was open to more than one honest reading, and the build took a different one from the verifier. |
| `dependency-not-declared` | The REQ depended on something no document stated, so nobody built or checked it. |
| `instruction-ignored` | **A written framework rule existed and was not followed.** Not a spec gap and not a weak gate — the instruction was there, in a file the agent had loaded, and it was not honoured. |
| `other` | None of the above fits. Do not stretch a label to avoid this. |

**`instruction-ignored` is TechieFlow's own addition, not in the Playbook's list**, and it exists because this framework's dominant failure mode is an agent skipping a step in a long markdown task — the thing the whole miss stream was commissioned to measure. Offer it back to the Playbook once it has earned its keep here; do not assume it transfers.

**Optional, and `null` is honest.** Many misses have no clear answer and a forced one is noise. But an **escape** (`found_by` ∈ `owner` / `production`) without a `why_missed` wastes the most valuable record in the stream: something got past every gate, and "why did nothing catch it" is the entire question. Fill it there — and if the record is already on the stream, `tf-emit.sh --amend` (§5.5.7) is how.

**Records written before 2026-08-28 legitimately carry no `why_missed`, and are not counted as unassessed.** The field did not exist, so those records had no chance to fill it — exactly the §3.5 hazard (`perf`, a gate added mid-stream) arriving on a different stream. They leave that field's denominator and are **reported separately**, never silently dropped and never backfilled with a value nobody assessed at the time. `tf-metrics.sh` holds the introduction date in `FIELD_SINCE` and prints the excluded count; **add a row there whenever an optional field is added to any stream.**

**It never substitutes for `miss_class`.** Different axes — one names the defect, the other names the practice — and per the §11 rule about `gate`/`phase_gate`, axes that answer different questions never share a field.

### 5.5.7 `kind: "miss-amend"` — completing a record without editing it

**Added 2026-08-28**, from TfLens feedback **TF-005**. The gap it closes is precise and was real: constraint 5 says *"if a record is wrong, the correction is a **new record**, never an edit"* — and for this stream there was no record kind that could carry one. `miss` opens, `miss-fix` closes, and a re-emitted `miss` is barred by the §5.5.4 collapse rule. So a field left `null` — most sharply, a `why_missed` on a record written before §5.5.6 shipped — was **unreachable**: leave it empty forever, or break constraint 5. The rule named a remedy the stream did not implement.

```json
{"v":1,"ts":"2026-08-28T07:44:39Z","kind":"miss-amend","app":"TfLens",
 "project_type":"app","harness":"claude-code",
 "miss_id":"MISS-TfLens-20260828-01","field":"why_missed","value":"missing-checklist-item"}
```

| Field | Type | Values / notes |
|---|---|---|
| `miss_id` | string | The `miss` this completes. An amend naming no known `miss` is an **orphan** — reported and counted, never applied, exactly as §5.5.2 treats an orphan `miss-fix`. |
| `field` | string | Must be on the **allowlist** below. Anything else is refused. |
| `value` | string | Must be in that field's closed vocabulary. |

**It completes a record; it never alters a fact.** The one invariant, enforced in `tf-emit.sh` and re-checked in `tf-metrics.sh`:

> An amend may set a field that is currently `null`. It may **never** overwrite a non-`null` value — including one set by an earlier amend.

That is what keeps it inside the append-only rule rather than an edit wearing a record's clothes. History is added to, never revised: every earlier state of the stream stays true, and a reader that ignores `miss-amend` records entirely still sees nothing false — only less.

**The allowlist, and the rule for extending it.** A field is amendable only when it is **(a) a closed-vocabulary judgement a reader can still make correctly later, and (b) not derived by the emitter**:

| Field | Vocabulary |
|---|---|
| `why_missed` | §5.5.6's seven values |

- **A judgement may be completed; an observation may not.** `why_missed` is a classification an analyst can still make honestly next week. `found_gate` is a fact about a run that is over — §3.5's *"never backfill the old records with a verdict they never had"* is this same rule seen from the other side.
- **Nothing the emitter derives is ever amendable** — `origin_model`, `origin_harness`, `origin_confidence`, `cost_attribution` and every token/cost field are excluded outright. An amend that could set them would be a hole straight through §5.5.1's central rule.
- **Closed vocabularies only**, so the kind can never become a free-text back door (§9, constraint 7).

**How to write one — one command, and the emitter decides:**

```bash
bash .tfcore/utils/tf-emit.sh --amend MISS-App-20260828-01 why_missed missing-checklist-item
# -> tf-emit: amended MISS-App-20260828-01 — why_missed = missing-checklist-item
# -> tf-emit: amend refused — why_missed is already 'other' on MISS-App-20260828-01 …
```

It **prints its refusal on stdout** rather than failing silently — an agent that believes it recorded a correction and did not is worse off than one that is told no. It still exits 0: telemetry has no veto (§10), and neither does a refused amend. A hand-written `miss-amend` piped onto the stream faces the identical checks and is dropped if it fails them — two doors, one enforcement.

**Readers fold amendments into the parent before counting anything**, and re-apply the null-check while doing it: a stream merged from another machine can carry an amend and a later-written value in either order.

---

## 6. Provenance — three separations, one rule applied three times

**Data from different provenances never merges.**

1. **Live vs backfilled.** Records not written at the moment of the event carry `backfilled: true` and never pool with live records.
2. **Across `project_type`.** Records never pool across types where the available gates differ.
3. **Across attribution confidence and cost attribution** (added 2026-08-28, §5.5). A `miss` whose `origin_confidence` is not `linked` never pools into a per-model, per-agent or per-phase figure. A `miss-fix` whose `cost_attribution` is not `sole` never pools into a headline cost figure.

No report may produce a single **first-pass rate**, **gate catch distribution**, **escape rate**, **per-model / per-agent / per-phase miss rate**, or **cost per miss** that crosses any of these boundaries — not as a merged figure, not as a "total" row, not as an "overall" summary line. Data on the wrong side of a boundary may appear in an adjacent **labelled column**, never summed with the figure it sits beside.

Additionally, per §3.1: **any `req_id` with even one backfilled record is excluded entirely from the live first-pass rate**, because its live `attempt` numbering restarts at 1.

Run counts, commit volume, cadence, token totals, **raw miss counts, and miss-class distribution** may be pooled freely — those are comparable across types and provenances. (A miss counts as a miss whoever missed it; only the *attribution* of that miss is confidence-bounded.)

### Why (this is not cosmetic)

A merged first-pass rate cannot be defended when someone asks how attempts were counted, because backfilled attempts are inferred from a mutable status table that never recorded them. A pooled gate distribution understates the visual gate, because `library` and `docs` projects never had screens to fail on. One indefensible figure contaminates every other number in the report.

The third separation has the sharpest version of the same problem, because its figures are the ones that change decisions. **A per-model miss rate computed partly from guessed attributions is a routing decision made on invented evidence** — and unlike a merged first-pass rate, nothing about the output reveals that it happened. Same for cost: an equal division across a run that spent 90% of its tokens on one hard REQ and 10% on four easy ones is an *inference*, and inferences do not get to sit in the same column as measurements. Both exclusions must be **applied and displayed** — a report states how many records it excluded and why, because an exclusion the reader cannot see is indistinguishable from a bug.

---

## 7. Backfilled records — know what the data is worth

`tf-metrics.sh --backfill-gates` parses existing `<APP>-Checklist.md` Requirements Status tables plus dated Remarks.

Every backfilled record carries:

```json
{"backfilled":true,"inferred":["attempt","failure_class"]}
```

`inferred` names which fields were guessed rather than read — **`attempt` always**, `failure_class` usually, `gate` whenever it came from prose rather than an explicit gate name.

**The Requirements Status table is a mutated-in-place *snapshot*, not a log.** A REQ that failed three times and then passed is indistinguishable from one that passed first try, unless every failure happened to leave a dated remark — and they did not.

> `attempt`, the field first-pass rate depends on entirely, is **not recoverable** and is being assumed.

Treat backfilled gate data as **context and volume**, never as evidence for a published rate.

`--backfill-commits` is different and genuinely reliable — see §5.

---

## 8. Derived metrics — computed at report time, NEVER stored

| Metric | Formula | Segmentation |
|---|---|---|
| First-pass rate | `gates` where `attempt=1 AND verdict=Verified` ÷ distinct `req_id` | live-only, per `project_type` |
| Gate catch distribution | count of `gate` values across all `verdict != Verified` records | live-only, per `project_type` |
| Escape rate | REQs with a `gate="escaped"` record ÷ REQs with any failure record | live-only, per `project_type` |
| Rework ratio | `runs` where `mode=fix` ÷ `runs` where `cmd=build-phase` | poolable |
| REQ throughput | `reqs_count ÷ duration_s` per run, median across runs | poolable |
| Cost per verified REQ | Σ tokens ÷ count of `verdict=Verified` transitions (§4: tokens, not dollars) | poolable |
| Batch size | median `reqs_count` per `build-phase` run | poolable |
| Commit cadence | commits per active day, from `commits.jsonl` | poolable, exempt |
| Miss class distribution | count of `miss_class` over `miss` records | live-only, poolable |
| Design-miss share | `miss_class="unspecified-gap"` ÷ all misses | live-only, poolable |
| Failed-practice distribution | count of `why_missed`, after folding `miss-amend` records | live-only, poolable — **denominator is records that carry the field, never all misses** (§5.5.6 is optional; a missing value is "not assessed", not a zero), and **records predating the field leave the denominator entirely** (`FIELD_SINCE`, §5.5.6) |
| Miss rate per origin phase | misses grouped by `origin_phase` ÷ `runs` of that `cmd` | live-only, per `project_type`, **`origin_confidence="linked"` only** |
| Miss rate per origin model | misses grouped by `origin_model` | as above — this is the routing-decision number |
| Miss rate per origin agent | misses grouped by `origin_agent` | as above |
| Miss escape share | misses with `found_by ∈ {owner, production}` ÷ all misses | live-only; reported **beside** the `gates.jsonl` escape rate, never merged |
| Open misses | `miss` with no `miss-fix`, or whose latest `miss-fix.verdict_after ≠ Verified` | poolable |
| Tokens per miss fixed | Σ `tokens_out` ÷ count over `miss-fix` | **`cost_attribution="sole"` only**; apportioned in a labelled column |
| Measured cost per miss fixed | Σ `cost_usd` ÷ count | **OpenCode records only** (§4); never pooled across harness |
| Median time-to-close a miss | `miss-fix.ts − miss.ts` | poolable |

Any metric with **fewer than 3 supporting records** is printed as `insufficient data (n=…)`, never as a number.

**Nothing derived is ever written back into a stream.** The streams are facts; the report is arithmetic.

---

## 9. Privacy — assume every record could become public

Records carry **IDs, counts, durations, verdicts, and file paths at most.**

Never: requirement text · prompt text · file contents · commit subjects · anything from a `docs/` document body · anything from `src/`.

This framework is used on employer projects. A leaked field is not a bug you fix later — it is already in the history file, which is append-only by design.

---

## 10. Failure policy — telemetry has no veto

No metrics write may fail a build, block a tool call, abort a phase, or emit a visible error.

`tf-emit.sh` **exits 0 unconditionally** — missing directory, unreadable file, malformed JSON, absent `python3`, full disk. On any error the event is dropped and the caller continues. This matches how `guard-status.sh` / `guard-verify.sh` already fail open.

Set `TF_METRICS_DEBUG=1` to make `tf-emit.sh` explain a drop on stderr. It still exits 0.

**A telemetry bug must never cost the owner a working session.**

---

## 11. Cross-edition note — the AI-First-Playbook team edition

When the Playbook grows agents, it emits **this same schema** — same streams, same field names, same `project_type` and `backfilled` discipline. Team-edition records add one field, `actor` (who ran it), which the solo edition has no use for — and which, per the design record, must stay **aggregate-only**: a per-person miss count is a performance metric, and a performance metric stops people logging misses at all.

**`gate` must not be reused across editions without disambiguation.** TechieFlow's `gate` names an *assertion* that failed (`build` / `acceptance` / `render` / `visual` / `standards`). The Playbook's four gates are *process* gates (plan review, verify, gap report, post-verification bugs). Different axes; they must not share a field name. **`gate` is reserved for assertions; `phase_gate` is reserved for the process gate.** The same rule governs the miss stream: TechieFlow writes `found_gate`, the Playbook writes `found_phase_gate`.

**Miss records differ across editions by design** (`docs/Miss-Telemetry-AI-First-Playbook.md` §7). The Playbook keys on `item_id` rather than `req_id`, writes to `verification/telemetry/misses.ndjson` rather than `docs/metrics/misses.jsonl`, carries real dollars everywhere (it is OpenCode-only), and adds `actor` — which is **aggregate-only and must never be reported per person**. It also carries one field this schema does not yet have:

> **`why_missed`** — **ported into this schema on 2026-08-28; see §5.5.6.** It says *which practice failed*, where `miss_class` says *what was missed*. The port is **not verbatim**: TechieFlow adds **`instruction-ignored`** — a written framework rule existed and was not followed — because an agent skipping a step in a long markdown task is this framework's dominant failure mode, and the Playbook's list has no slot for it. **Offer that value back to the Playbook once it has earned its keep here**; do not assume it transfers. The other six values are identical in both editions, so the field remains comparable across them.

Shared and non-negotiable in both editions: append-only · closed vocabularies, never free text · numbers never self-reported · attribution looked up or `null` · apportioned cost never blended with measured cost · telemetry never blocks a run.

Verdict vocabulary mapping is recorded in `DECISIONS.md` §Playbook.

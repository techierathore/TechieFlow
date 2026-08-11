# TechieFlow Telemetry — Implementation Runbook

**Target repo:** `techierathore/TechieFlow` (the reference repo — WSL: `/mnt/c/3AIGenCode/TechieFlow` · macOS: `/Volumes/MacD/MyCode/TechieFlow`)
**Audience:** Claude Code, working *on* the framework. Read `WorkFlow-Context.md` first, per the repo's own rule.
**Owner:** S Ravi Kumar (techierathore)
**Estimated:** one 60–90 min session. If it looks bigger than that, stop and report scope back before writing code.

---

## 0. The problem this solves

TechieFlow already produces the evidence. It throws it away.

Every `*verify` run applies four separately-named gates (acceptance, §4a data-render, §4b visual-truth, standards-grep) to individually-identified requirements (`REQ-UI-*`, `REQ-FN-*`, `REQ-RAG-*`, `REQ-NFR-*`) and writes verdicts into a Requirements Status table. It writes `docs/.last-verify.json` as a run ledger. Then the next run overwrites it, the table is mutated in place, and the history is gone.

**Goal:** a durable, append-only telemetry stream, written automatically by the framework, that answers three questions about any project built with TechieFlow:

1. **First-pass rate** — what fraction of REQs reach `Verified` on attempt 1?
2. **Gate catch distribution** — of all failures, which gate caught them?
3. **Escape rate** — what fraction of defects reached UAT/production (`*triage-issues`) instead of being caught by a gate?

Everything else in this runbook is in service of those three.

**Non-goal:** cycle-time-per-feature. The owner does not decompose work into features; he hands a checklist to a phase and runs it. The unit of work is **the run**, not the ticket. Do not add per-feature timing.

---

## 1. Hard constraints — violating any of these is a failed implementation

1. **Agents never run `git` or `gh`.** `.tfcore/hooks/block-git.sh` stays exactly as it is. Do not weaken the deny list. Do not add a git call to any task, agent, or hook that an agent triggers. The only git-derived stream comes from a `pre-commit` hook that fires inside the owner's own `git commit`, and a backfill script the owner runs himself.
2. **Metrics data must be tracked by git.** `docs/metrics/` must NOT land in the framework's managed `.gitignore` blocks (the one carrying `.tfcore/`, `.claude/`, etc., or the one carrying `test-results/`, `logs/`, `/docs/.last-verify.json`). After implementing, re-read the gitignore-management step in `scaffold-brownfield.sh`, `scaffold-greenfield.sh`, and `update-framework.sh` and confirm no pattern catches `docs/metrics/`. If one does, add an explicit negation.
3. **Never write metrics into `PROJECT-STATUS.md`.** `.tfcore/hooks/guard-status.sh` blocks any H2 outside the template's section set and any full-file write past ~120 lines. A metrics section there will be rejected. Same for `<APP>-Checklist.md` — `guard-verify.sh` inspects those writes and a stray edit risks a false block.
4. **Do not change `docs/.last-verify.json` semantics.** It is the same-day gate ledger that `guard-verify.sh` depends on to permit a `Verified` cell. It stays ephemeral, stays gitignored, stays exactly the shape `verify-phase §6` writes today. Telemetry *reads alongside* it; it never replaces it.
5. **Source of truth is the reference repo.** Every new file goes under `.tfcore/` (or the canonical settings block) so `update-framework.sh` propagates it to every already-scaffolded project. Never instruct the owner to hand-author a file inside an app repo.
6. **Append-only, schema-versioned JSONL.** One JSON object per line, `"v"` field on every record. Never rewrite or compact a history file. Never sort in place.
7. **Telemetry fails silently and never blocks.** No metrics write may fail a build, block a tool call, abort a phase, or emit a visible error. Wrap every emit in a guard; on any error — missing dir, unreadable file, malformed input, absent `python3` — drop the event and continue. A telemetry bug must never cost the owner a working session.
8. **No secrets, no content, no client data.** Records carry IDs, counts, durations, verdicts, file *paths* at most. Never requirement text, never prompt text, never file contents, never anything from a `docs/` document body. This framework is used on employer projects; assume every record could become public.
9. **Data from different provenances never merges.** Two separations are mandatory and are the same rule applied twice: (a) records not written at the moment of the event carry `"backfilled":true` and never pool with live records; (b) records carry `"project_type"` and never pool across types where the available gates differ. No report may produce a single first-pass rate, gate catch distribution, or escape rate that crosses either boundary. Commit-derived metrics are exempt from both. See Step 7 for enforcement, Step 8 for the reasoning.

---

## 2. Data model

All streams live in `docs/metrics/` inside each app repo. All are JSONL. All records carry `"v": 1` and an ISO-8601 UTC `"ts"`.

**Every record also carries `"project_type"`**, read from `core-config.yaml → metrics.project_type` (a preserved, per-project file). Values:

- `app` — has runtime screens; all four gates apply (`TrSetup`, `TrStudio`, `AstroLyfe`, `AppManager`)
- `library` — NuGet package, no screens; the §4b visual-truth gate never fires (`TechieRag`, `TrBlazeUI`)
- `docs` — markdown/spec repo; verify degrades to `STATIC-ONLY`, effectively no gates
- `framework` — TechieFlow / Playbook themselves

This exists because gate-catch distribution is only meaningful across projects where the same gates could fire. A `library` run cannot fail the visual gate, so including it in a pooled distribution understates that gate's catch rate. `*metrics` and `tf-metrics.sh --rollup` **must segment by `project_type` and must never pool `app` with `library` or `docs`** for gate catch distribution or first-pass rate. Run counts, commit volume, cadence, and token cost may be pooled freely — those are comparable across types.

If `metrics.project_type` is absent, default to `app` and flag it in the report as unclassified rather than silently assuming.

### 2.1 `docs/metrics/runs.jsonl` — one record per framework command run

```json
{"v":1,"ts":"2026-08-08T04:12:33Z","kind":"run","app":"TrSetup","cmd":"build-phase",
 "mode":"build","started":"2026-08-08T03:41:02Z","ended":"2026-08-08T04:12:33Z",
 "duration_s":1891,"reqs_touched":["REQ-UI-004","REQ-FN-011"],"reqs_count":2,
 "subagents":["trblazeui"],"files_written":14,"build_result":"pass","harness":"claude-code"}
```

- `cmd`: `day1-brownfield` | `day1-greenfield` | `split-brd` | `mockups` | `build-phase` | `verify-phase` | `fix-issues` | `triage-issues` | `devguide` | `productguide` | `handoff-phase` | `refresh-status` | `amend-docs`
- `mode`: `build` | `fix` — `build-phase` already distinguishes these (FIX mode). Capture it; the ratio is the rework metric.
- `files_written`: a count the agent already knows. Do not shell out to compute it.

### 2.2 `docs/metrics/gates.jsonl` — one record per REQ verdict per verify run. **The primary stream.**

```json
{"v":1,"ts":"2026-08-08T04:10:07Z","kind":"gate","app":"TrSetup","run_id":"2026-08-08T03:41:02Z",
 "req_id":"REQ-UI-004","req_class":"UI","attempt":2,"verdict":"Verified",
 "gate":null,"gates_run":["acceptance","render","visual","standards"],
 "prior_verdict":"Needs re-verify"}
```

On failure:

```json
{"v":1,"ts":"2026-08-08T04:10:07Z","kind":"gate","app":"TrSetup","run_id":"2026-08-08T03:41:02Z",
 "req_id":"REQ-UI-009","req_class":"UI","attempt":1,"verdict":"FAIL",
 "gate":"visual","gates_run":["acceptance","render","visual"],
 "failure_class":"overlap","prior_verdict":"Implemented"}
```

- `gate` — **the first gate that failed**, or `null` on a pass. Values: `build` | `acceptance` | `render` | `visual` | `standards`. This single field produces the gate catch distribution. Get it right; everything else is secondary.
- `attempt` — 1 for the first verify of this REQ ever, incrementing on each subsequent verify of the same REQ in the same app. Derive it by counting prior `gates.jsonl` records for that `req_id`, not by guessing.
- `failure_class` — short controlled vocabulary only: `blank-data` | `zero-rows` | `overlap` | `clipped` | `offscreen` | `exception` | `assert-fail` | `naming` | `build-error` | `other`. No free text.
- `verdict` — mirror the checklist vocabulary exactly: `Verified` | `Needs re-verify` | `FAIL` | `Blocked` | `Implemented` | `Done (pre-existing)`.

### 2.3 `docs/metrics/sessions.jsonl` — one record per agent session

```json
{"v":1,"ts":"2026-08-08T04:15:00Z","kind":"session","app":"TrSetup","harness":"claude-code",
 "model":"claude-sonnet-4-6","duration_s":2210,
 "input_tokens":184320,"output_tokens":41880,"cache_read_tokens":1204416,"cost_usd":3.84}
```

Written by a session-end hook. See §3.4 — **verify the hook event name against the installed Claude Code version before wiring it; do not assume.** If no suitable event exists in this version, emit nothing and report that back rather than faking the stream.

### 2.4 `docs/metrics/commits.jsonl` — one record per commit, written by the owner's `pre-commit` hook

```json
{"v":1,"ts":"2026-08-08T09:30:11Z","kind":"commit","app":"TrSetup","sha":"a1b2c3d",
 "files":9,"insertions":412,"deletions":57,"subject_prefix":"feat","branch":"main"}
```

- `subject_prefix`: first token of the commit subject if it matches `feat|fix|docs|chore|refactor|test|build`, else `null`. Never store the full subject — subjects leak project detail.
- **Known limitation, document it in `SCHEMA.md`:** the record for the newest commit is included in the *next* one. Metrics lag reality by a commit — unavoidable in either direction, since a record of commit N cannot predate N.
- **Superseded 2026-08-11 (owner decision).** This runbook originally specified `post-commit` and told the implementer *not* to use `pre-commit` + `git add`. That was reversed. `post-commit` cannot put its line inside the commit it describes, so `commits.jsonl` was permanently dirty with no reachable clean state, and it blocked `git pull` on any repo worked from two machines. The hook is now `pre-commit`: it reconciles from the log, then stages **exactly one path** (`docs/metrics/commits.jsonl` — never a directory, never `-A`), skips staging on a partial commit (detected via `GIT_INDEX_FILE`), and exits 0 on every path so it can never abort a commit. Constraint 1 above is unaffected: *agents* still never run git, and `block-git.sh` is unchanged.
- **Revised 2026-08-11 — the hook reconciles rather than appends.** On each commit it writes a record for *every* commit reachable from HEAD the stream lacks (skipping on `sha`), which is the same operation as `--backfill-commits`. The lag stays; the *loss* goes. That matters because this portfolio is worked on from more than one machine, where a naive appending hook drops the trailing record on a machine you stop using, records nothing at all in a clone that has no hook (`.git/` is not part of the repository), and never sees what the other machine committed. `git log` is already replicated by push/pull, so the stream is a projection of it. Constraint 1 is untouched — still the owner's own `git commit`, still nothing added to the commit being made.

### 2.5 Derived metrics — computed at report time, never stored

| Metric | Formula |
|---|---|
| First-pass rate | `gates` where `attempt=1 AND verdict=Verified` ÷ distinct `req_id` |
| Gate catch distribution | count of `gate` values across all `verdict != Verified` records |
| Escape rate | REQs first appearing in a `triage-issues` run ÷ total REQs with any failure |
| Rework ratio | `runs` where `mode=fix` ÷ `runs` where `cmd=build-phase` |
| REQ throughput | `reqs_count` ÷ `duration_s`, per run, median across runs |
| Cost per verified REQ | Σ `cost_usd` ÷ count of `verdict=Verified` transitions |
| Batch size | median `reqs_count` per `build-phase` run |
| Commit cadence | commits per active day, from `commits.jsonl` |

---

## 3. Files to create

All paths relative to the TechieFlow reference repo root.

| Path | Purpose |
|---|---|
| `.tfcore/telemetry/SCHEMA.md` | Canonical schema doc. Every field, every enum, every known limitation. Agents and future-you read this before emitting. |
| `.tfcore/utils/tf-emit.sh` | The single append primitive. Takes a stream name and a JSON object on stdin; validates it parses, appends one line, exits 0 no matter what. Every other component calls this and only this. |
| `.tfcore/telemetry/install-metrics.sh` | One-time per-app-repo installer, run by the owner. Creates `docs/metrics/`, seeds empty streams, installs the `pre-commit` hook, writes `docs/metrics/README.md`. Idempotent. |
| `.tfcore/telemetry/pre-commit` | The commit hook template. No agent involvement. Reconciles the stream against the log via `tf-metrics.sh --backfill-commits --quiet`, falling back to a pure-bash single-record append when `python3` is absent. |
| `.tfcore/telemetry/tf-metrics.sh` | Owner-run script: `--backfill-commits` (walk `git log`, populate `commits.jsonl`), `--backfill-gates` (parse existing `<APP>-Checklist.md` Requirements Status tables + dated Remarks into partial `gates.jsonl` history), `--report` (roll up to stdout), `--rollup <path>` (merge several app repos into one cross-project view). **This is the only file allowed to contain git commands, and the owner invokes it himself.** |
| `.tfcore/hooks/metrics-session.sh` | Session-end hook → `sessions.jsonl`. Reads the hook payload from stdin, locates the transcript, extracts usage. Silent on any failure. |
| `.tfcore/tasks/_metrics-emit-gate.md` | The doctrine doc — the sibling of `_status-update-gate.md`. States when each stream is written, by whom, and the eight constraints from §1. Every task that emits references this. |
| `.tfcore/tasks/metrics-report.md` | The `*metrics` task. |
| `.tfcore/templates/v4custom/metrics-report-template.md` | Output shape for `docs/metrics/METRICS.md`. |

### Files to edit

| Path | Edit |
|---|---|
| `.tfcore/tasks/verify-phase.md` | New step **§6a — emit gate telemetry**, immediately after the existing §6 ledger write. One `gates.jsonl` record per REQ evaluated, carrying the first failing gate. This is the highest-value edit in the runbook. |
| `.tfcore/tasks/build-phase.md` | Emit a `runs.jsonl` record at phase end, carrying `mode` (build vs FIX), `reqs_touched`, `files_written`. |
| `.tfcore/tasks/fix-issues.md` | Emit `runs.jsonl` with `cmd=fix-issues`. |
| `.tfcore/tasks/triage-issues.md` | Emit `runs.jsonl` with `cmd=triage-issues`, **and** a `gates.jsonl` record per demoted REQ with `gate:"escaped"` — this is what makes escape rate computable. |
| `.tfcore/tasks/handoff-phase.md`, `day1-*.md`, `split-brd.md`, `devguide.md`, `productguide.md`, `amend-docs.md`, `refresh-status.md` | Emit a `runs.jsonl` record at completion. Low value individually, but the run stream is only honest if it's complete. |
| `.tfcore/tasks/_status-update-gate.md` | One line: the status gate now also triggers the run emit. Do not add metrics content to `PROJECT-STATUS.md` itself. |
| `.tfcore/agents/flow-master.md` | Register `*metrics` in the task list. |
| `scaffold-brownfield.sh` · `scaffold-greenfield.sh` · `update-framework.sh` | (a) Add the session hook to the **canonical `.claude/settings.json` block — in all three files, identically.** The updater force-refreshes `settings.json`, so a block that exists in only two of the three silently reverts on next update. (b) Create `docs/metrics/` on scaffold. (c) Confirm no gitignore pattern catches `docs/metrics/`. |
| `WORKFLOW.html` + `README.md` | New §17 "Development telemetry" — what's measured, where it lands, how to read it, the one-commit lag caveat, the privacy stance from constraint 8. |
| `WorkFlow-Context.md` | Add telemetry to the AI-agent context doc. |

---

## 4. Implementation order

Work in this order. Each step has a done-condition; do not proceed past a failing one.

**Step 1 — `SCHEMA.md`.** Write the schema first, in full, including limitations. Everything downstream references it.
*Done when:* every field in §2 above is documented with type, enum values, and who writes it.

**Step 2 — `tf-emit.sh`.** The primitive. `tf_emit <stream>` reads JSON on stdin, verifies it parses (`python3 -c 'import json,sys;json.load(sys.stdin)'`), appends one line to `docs/metrics/<stream>.jsonl`, creates the dir if absent. Exits 0 unconditionally — including when `python3` is missing, matching how `guard-status.sh` / `guard-verify.sh` already fail open.
*Done when:* `echo '{"v":1}' | .tfcore/utils/tf-emit.sh runs` appends a line; `echo 'garbage' | ... ; echo $?` prints `0` and appends nothing.

**Step 3 — `verify-phase.md §6a`.** The single most important edit. Per-REQ gate emission, first-failing-gate captured, `attempt` derived from prior records.
*Done when:* a `*verify all` run on any scaffolded app produces one `gates.jsonl` line per REQ in the scope, and `.last-verify.json` is byte-identical in shape to before.

**Step 4 — the run stream.** `build-phase` first, then `fix-issues` and `triage-issues`, then the remaining tasks.
*Done when:* a build→verify cycle produces ≥2 `runs.jsonl` records with sane `duration_s`.

**Step 5 — git side.** `pre-commit`, `install-metrics.sh`, `tf-metrics.sh --backfill-commits`.

`install-metrics.sh` prompts once for `project_type` (`app` | `library` | `docs` | `framework`) and writes it to `core-config.yaml → metrics.project_type`. It is a preserved file, so the classification survives every `update-framework.sh`.

*Done when:* the owner commits and `commits.jsonl` grows by one line, with `block-git.sh` untouched and no agent having run git.

**Step 6 — session hook.** *First, verify which session-lifecycle hook events the installed Claude Code version supports* — read the local docs or config schema, do not assume from memory. Wire `metrics-session.sh` to the correct event. If no suitable event exists, skip this step, emit nothing, and say so in the report.
*Done when:* a session ends and `sessions.jsonl` gains a record — or the report explicitly states the event is unavailable and `sessions.jsonl` stays empty.

**Step 7 — `*metrics` task + template.** Reads all four streams, computes §2.5, writes `docs/metrics/METRICS.md` + `.html` via the existing render shell. Prints "insufficient data" for any metric with fewer than 3 supporting records rather than reporting a number from n=1.

**Provenance rule — enforce this in the task, not just the data.** `METRICS.md` must never print a combined **first-pass rate**, **gate catch distribution**, or **escape rate** that crosses either provenance boundary from constraint 9 — not as a merged figure, not as a "total" row, not as an "overall" summary line. Live and backfilled stay separate; `app`, `library`, and `docs` stay separate. Backfilled records may appear in an adjacent labelled column, never summed with live. Any table containing backfilled data carries a footnote naming what was reconstructed and what was inferred. Commit-derived metrics are exempt from both separations: `git log` is a real log, and commit volume is comparable across project types.

The reason is not cosmetic. A merged first-pass rate cannot be defended when someone asks how attempts were counted, because backfilled attempts are inferred from a mutable status table that never recorded them. A pooled gate distribution understates the visual gate, because library and docs projects never had screens to fail on. One indefensible figure contaminates every other number in the report. The task must make the tempting numbers impossible to produce.

*Done when:* `/flow-master *metrics <APP>` produces a readable report on a real app, and — on an app with both live and backfilled records — no combined figure appears for any of the three live-only metrics.

**Step 8 — backfill gates.** `tf-metrics.sh --backfill-gates` parses existing `<APP>-Checklist.md` Requirements Status tables. Current status and dated Remarks give partial history.

Every backfilled record carries `"backfilled":true` and `"inferred":[...]` naming which fields were guessed rather than read — `attempt` always, `failure_class` usually, `gate` whenever it came from prose rather than an explicit gate name.

**Know what this data is worth.** The Requirements Status table is a mutated-in-place *snapshot*, not a log. A REQ that failed three times and then passed is indistinguishable from one that passed first try, unless every failure happened to leave a dated remark — and they did not. `attempt`, the field first-pass rate depends on entirely, is therefore not recoverable and is being assumed. Treat backfilled gate data as context and volume, never as evidence for a published rate.

Commit backfill (`--backfill-commits`) is different and genuinely reliable: `git log` is an append-only log, so backfilled commits are as trustworthy as live ones and need no separation in reporting.

*Done when:* run against one existing app; output is plausible, every synthetic record is flagged, and `*metrics` on that app still refuses to print a combined first-pass rate per Step 7.

**Step 9 — propagate + document.** Update the three scripts, `WORKFLOW.html`, `README.md`, `WorkFlow-Context.md`. Confirm the gitignore check from constraint 2.
*Done when:* `update-framework.sh /path/to/app --dry-run` shows the new `.tfcore/` files landing and nothing under `docs/` being overwritten.

---

## 5. Verification the owner runs

```bash
# In the reference repo
./update-framework.sh /path/to/TrSetup --dry-run     # expect: .tfcore/ additions, docs/ untouched
./update-framework.sh /path/to/TrSetup
cd /path/to/TrSetup
/mnt/c/3AIGenCode/TechieFlow/.tfcore/telemetry/install-metrics.sh .
```

Then, in Claude Code inside that app: run `*build-phase`, then `*verify all`, then `*metrics`.

Expected: `docs/metrics/` contains four files, `gates.jsonl` has one line per REQ verified, `METRICS.md` renders, `git status` shows `docs/metrics/` as untracked-or-modified (**not** ignored), and no agent ever attempted a git call.

---

## 6. What not to do

- Do not weaken, bypass, or add exceptions to `block-git.sh`.
- Do not change what `.last-verify.json` contains or where it lives.
- Do not add a hook that can block a write. Telemetry has no veto.
- Do not put metrics in `PROJECT-STATUS.md` or in any `*-Checklist.md`.
- Do not invent fields absent from `SCHEMA.md`. If a field seems needed, add it to the schema first, with a rationale.
- Do not estimate, interpolate, or infer a metric that wasn't measured. A missing number is reported as missing.
- Do not emit a backfilled record without `"backfilled":true`, and do not produce any combined live+backfilled figure for the three live-only metrics — including a helpfully-labelled "overall" row.
- Do not store requirement text, prompt text, file contents, commit subjects, or anything else that could carry employer or client detail.
- Do not refactor unrelated parts of the framework while in here. If something looks wrong, note it in the report and leave it.

---

## 7. Report back

On completion, write `DECISIONS.md` in the reference repo (create it if absent) with:

1. Which streams are live and which were skipped, with reasons.
2. The exact session-hook event name used, or a statement that none was available.
3. Any constraint from §1 that created a design compromise, and what the compromise was.
4. The one-line install command the owner runs per app repo.
5. A list of his app repos this still needs to be installed into.
6. If Step 8 ran: how many gate records are backfilled vs live per app, and which fields were inferred. State plainly that the backfilled set cannot support a published first-pass rate.

---

## 8. Forward note — the Playbook (team edition)

[`AI-First-Playbook`](https://github.com/techierathore/AI-First-Playbook) is now public. It ships as documentation but is intended to become a spec-driven, agent-based framework — the team-scale sibling of TechieFlow, same Apache-2.0, publicly positioned as one philosophy at two scales.

**Record this decision in `DECISIONS.md` now, even though implementation is months out:** when the Playbook grows agents, it emits **this same schema** — same four streams, same field names, same `project_type` and `backfilled` discipline. Team-edition records add one field, `actor` (who ran it), which the solo edition has no use for.

The two vocabularies have **already diverged**, which is why this can't wait. Record the mapping:

| Playbook verdict | TechieFlow verdict | Notes |
|---|---|---|
| `PASS` | `Verified` | execution-proven |
| `PASS (code-audit)` | `Implemented` | **not** `Verified` — TechieFlow's `guard-verify.sh` already refuses `Verified` without an executed run ledger. Same principle, enforce it identically. |
| `FAIL` / `FAIL (code-audit)` | `FAIL` | |
| `BLOCKED` | `Blocked` | |
| — | `Needs re-verify` | Playbook has no equivalent; a re-opened item re-enters as `FAIL` |

**Do not reuse the `gate` field across editions without disambiguation.** TechieFlow's `gate` names an *assertion* that failed (`build` / `acceptance` / `render` / `visual` / `standards`). The Playbook's four gates are *process* gates (plan review, verify, gap report, post-verification bugs). These are different axes and must not share a field name. Reserve `gate` for assertions; add `phase_gate` for the process gate if the Playbook needs it.

**One metric the Playbook produces that TechieFlow cannot:** *execution-proven rate* — `PASS` ÷ (`PASS` + `PASS (code-audit)`). Code audit is the Playbook's explicit last resort, so this ratio measures whether the team is honouring "verify by executing, not by reading" or quietly degrading to reading. It is also a **leading indicator of adoption decay** — rising code-audit fallback is what process abandonment looks like before anyone says so. Add it to the shared schema as an optional field (`proof:"executed"|"code-audit"`) so the solo edition can carry it if a runtime bridge is ever unreachable and stamps `⚠ STATIC-ONLY`.

Do not implement anything Playbook-side in this session. Write the decision and the mapping down; that is the whole task. The cost of deciding this now is one table. The cost of deciding it later is reconciling two incompatible schemas across two public frameworks that advertise themselves as one system.

Then stop. Do not start using the framework to build anything else in the same session.

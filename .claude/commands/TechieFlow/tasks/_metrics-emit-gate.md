# _metrics-emit-gate (shared rule — included by every task that emits telemetry)

> Sibling of `_status-update-gate.md`. That gate says *a phase is not done until PROJECT-STATUS
> reflects reality*. This one says *a run that produced evidence and threw it away is a run that
> half-happened.* Schema: `.tfcore/telemetry/SCHEMA.md` — read it before emitting anything.

## The rule

**Every task that runs a phase emits ONE `runs.jsonl` record at completion. Every verify pass emits ONE `gates.jsonl` record per REQ it evaluated.**

Emission happens in the same turn as the status-gate write, immediately after it — the status gate is the trigger. Both are terminal housekeeping; neither is optional.

**But telemetry has no veto.** If an emit fails, silently or otherwise, the phase still succeeded. Never retry, never diagnose, never mention it in your report, never let it change a verdict. `tf-emit.sh` exits 0 no matter what; that is the design, not a bug to work around.

## Who writes what

| Stream | Written by | When |
|---|---|---|
| `runs.jsonl` | the task itself | once, at phase completion, right after the status gate |
| `gates.jsonl` | `verify-phase.md` §6a · `triage-issues.md` | one record per REQ evaluated / per REQ demoted |
| `misses.jsonl` | `verify-phase` · `build-phase` · `triage-issues` · `fix-issues` · `amend-docs` · `log-miss` | `miss` when something was missed; `miss-fix` when it is repaired |
| `sessions.jsonl` | `.tfcore/hooks/metrics-session.sh` (SessionEnd hook) | automatically — **never by an agent** |
| `commits.jsonl` | the owner's `pre-commit` hook | automatically — **never by an agent** |

## Misses — the fourth question (SCHEMA.md §5.5)

A `gates.jsonl` record says a REQ failed. A **`misses.jsonl`** record says *what* was missed, *which phase / agent / model* let it through, and — via its `miss-fix` sibling — *what fixing it cost*. It is the only stream that can carry a design-phase miss, because it is the only one not written by the verifier.

**Three things make this stream trustworthy, and none of them are your judgement:**

1. **`miss_id` is issued, never invented** — `bash .tfcore/utils/tf-emit.sh --next-miss-id`. It is the join key between a `miss` and its `miss-fix`; a collision silently merges two defects into one lifecycle.
2. **Attribution is looked up, never typed.** You name `origin_phase`, `origin_agent` and (if you found one in `runs.jsonl`) `origin_run_id`. `tf-emit.sh` resolves `origin_model`, `origin_harness` and `origin_confidence` from that run record — and **forces the model to `null` if the lookup fails, overwriting anything you wrote.** Do not put a model name in a miss record. You cannot know which model ran a phase two days ago, and a wrong one corrupts every per-model comparison built on it.
3. **Cost is copied, never computed.** A `miss-fix` carries only `fix_run_id`; the emitter copies that run's token window and derives `cost_attribution` (`sole` / `shared:<n>` / `none`) from its `reqs_touched`. Never write token counts, dollars, or an attribution yourself.

**Collapse before you emit — one defect is ONE miss (SCHEMA.md §5.5.4).** A REQ that fails three verify passes must not produce three misses; that would make the miss count a measure of retry patience rather than of quality.

```bash
bash .tfcore/utils/tf-emit.sh --open-miss REQ-UI-014   # "<miss_id> <miss_class>", or nothing
```

If it prints a miss whose `miss_class` matches the one you would record, **emit nothing** — it is the same miss, still open. If the class differs, emit a new one: the REQ is now failing for a different reason, and that is new information.

```bash
MID=$(bash .tfcore/utils/tf-emit.sh --next-miss-id)
cat <<JSON | bash .tfcore/utils/tf-emit.sh misses
{"kind":"miss","miss_id":"$MID","req_id":"REQ-UI-014","req_class":"UI",
 "miss_class":"partial-implementation","artifact":"src","severity":"major",
 "why_missed":"insufficient-verify-method",
 "origin_phase":"build-phase","origin_agent":"trblazeui",
 "origin_run_id":"2026-08-26T09:12:40Z",
 "found_by":"gate","found_phase":"verify-phase","found_gate":"render",
 "found_run_id":"<this run's start>","failure_class":"blank-data"}
JSON
```

**`why_missed` — which PRACTICE failed (SCHEMA.md §5.5.6).** `miss_class` names the defect; this names the practice that let it through, and it is the more decision-changing of the two because it says whether your *specification* or your *verification* is the weak one.

`missing-checklist-item` (no REQ or acceptance bullet covered it) · `insufficient-verify-method` (acceptance existed; the gate could not catch this class of defect) · `code-audit-limitation` (`⚠ STATIC-ONLY` — never observable) · `ambiguous-acceptance` (two honest readings) · `dependency-not-declared` · **`instruction-ignored`** (a written framework rule existed and was not honoured) · `other`.

**Optional — omit it rather than guess.** `null` means "not assessed" and is an honest answer. But on an **escape** (`found_by` ∈ `owner` / `production`) fill it: something got past every gate, and *why nothing caught it* is the whole value of that record. The report warns when an escape arrives without one.

```bash
FA=$(bash .tfcore/utils/tf-emit.sh --next-fix-attempt "$MID")
cat <<JSON | bash .tfcore/utils/tf-emit.sh misses
{"kind":"miss-fix","miss_id":"$MID","req_id":"REQ-UI-014",
 "fix_run_id":"<the fix run's started>","fix_cmd":"fix-issues","fix_attempt":$FA,
 "verdict_after":"Verified","reopened":false}
JSON
```

**Every field is a closed vocabulary** (`miss_class`, `artifact`, `severity`, `found_by`, `failure_class`, `verdict_after` — SCHEMA.md §5.5). Never a free-text description of what was missed: that is requirement prose and constraint 7 forbids it here as absolutely as anywhere else. The *description* belongs in the checklist Remark, where a human reads it.

## How to emit — the only supported form

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"TrSetup","cmd":"build-phase","mode":"build",
 "started":"2026-08-08T03:41:02Z","ended":"2026-08-08T04:12:33Z","duration_s":1891,
 "reqs_touched":["REQ-UI-004","REQ-FN-011"],"reqs_count":2,
 "subagents":["trblazeui"],"files_written":14,"build_result":"pass"}
JSON
```

`tf-emit.sh` injects `v`, `ts`, `project_type`, `app`, and `harness` if you leave them out. It validates the JSON and drops anything malformed. **Do not append to a `.jsonl` file with Write, Edit, or `>>`.** One primitive, one code path — that is what keeps the streams parseable.

**Never write `harness` yourself.** These task files are shared byte-identically by Claude Code and OpenCode, so you cannot know from the markdown which harness is running you — copying a literal would stamp the wrong one on every record. `tf-emit.sh` detects it (env vars, then the parent process chain) and records `null` when it genuinely cannot tell. Same reasoning applies to `ts`, `project_type`, and `app`: if the primitive can determine it, let it.

To get an `attempt` number, ask; never guess:

```bash
bash .tfcore/utils/tf-emit.sh --next-attempt REQ-UI-004      # prints an integer
```

**Note your `started` timestamp at step 0 of the task**, before you do any work. `date -u +%Y-%m-%dT%H:%M:%SZ`. You cannot reconstruct it at the end, and an invented duration is a fabricated measurement.

## The ten constraints — violating any one is a failed emit

1. **Agents never run `git` or `gh`** — not to emit, not to read, not to backfill. `.tfcore/hooks/block-git.sh` blocks it and is correct to. The only git-derived stream comes from the owner's own `pre-commit` hook, and the only script containing git commands (`.tfcore/telemetry/tf-metrics.sh`) is **owner-run**. If you think you need git for a metric, you need a different metric. *(That script lives at exactly that path in every installation. It is invisible to Grep/Glob — `.tfcore/` is a hidden, gitignored directory — so confirm it by reading the literal path, never by searching for the name; see `_status-update-gate.md` §"The framework tree is INVISIBLE to search".)*
2. **Metrics data is tracked by git.** `docs/metrics/` must never land in a `.gitignore` block. If you notice a pattern that would catch it, say so in your report — do not add the pattern, and do not "helpfully" ignore the directory.
3. **Never write metrics into `PROJECT-STATUS.md`** — `guard-status.sh` will block it, correctly. Same for `<APP>-Checklist.md`: `guard-verify.sh` inspects those writes and a stray metrics edit risks a false block. Telemetry lives in `docs/metrics/` and nowhere else.
4. **Do not change `docs/.last-verify.json`.** It is the same-day gate ledger `guard-verify.sh` depends on to permit a `Verified` cell. It stays ephemeral, stays gitignored, stays exactly the shape `verify-phase §6` writes today. Telemetry *reads alongside* it; it never replaces it.
5. **Append-only, schema-versioned.** One JSON object per line, `"v"` on every record. Never rewrite, compact, sort, or de-duplicate a history file. If a record is wrong, the correction is a *new* record, never an edit.
6. **Telemetry fails silently and never blocks.** No emit may fail a build, block a tool call, abort a phase, or print a visible error.
7. **No secrets, no content, no client data.** IDs, counts, durations, verdicts, and file paths — that is the whole permitted vocabulary. Never requirement text, prompt text, file contents, commit subjects, or anything from a `docs/` document body. This framework runs on employer projects: assume every record could become public. `failure_class` is a closed enum for exactly this reason — **never** write a free-text description of a failure.
8. **Provenance never merges.** Records you write are live and carry no `backfilled` flag. Only `tf-metrics.sh --backfill-*` writes `backfilled: true`. Never hand-author a backfilled record, and never produce a figure that pools live with backfilled, or `app` with `library`/`docs`, for first-pass rate, gate catch distribution, or escape rate.
9. **Never invent a field.** If it is not in `SCHEMA.md`, it does not get emitted. If a field seems genuinely needed, add it to the schema first, with a rationale, then use it.
10. **Never name a model, a token count, a dollar figure, or a cost attribution on a miss record.** `origin_model` / `origin_harness` / `origin_confidence` on a `miss`, and every `tokens_*` / `cost_usd` / `tokens_scope` / `cost_attribution` on a `miss-fix`, are resolved by `tf-emit.sh` from the run record you point it at. You supply `origin_run_id` and `fix_run_id`; it supplies the rest, or `null`. This is the same rule as `harness` (constraint: shared task markdown cannot know it) with a sharper consequence — a per-model miss rate built from a guessed attribution is a routing decision made on invented evidence, and nothing in the output reveals that it happened.

## Do not

- Do not estimate, interpolate, or infer a value that was not measured. A missing number is emitted as `null` and reported as missing. `null` is an honest answer; a plausible number is not.
- Do not shell out to compute `files_written` — it is a count you already know.
- Do not emit a `runs` record for work you did not do (a phase that halted at step 1 emits `build_result: "not-run"`, not a fabricated success).
- Do not emit per-feature timing. The unit of work here is **the run**, not the ticket, and that is deliberate.
- Do not mention telemetry in your user-facing report unless something was genuinely notable. It is instrumentation, not a deliverable.

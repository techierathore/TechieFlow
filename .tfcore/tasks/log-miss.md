# log-miss

The **20-second front door** for "you missed this". The owner says what an agent got wrong — in their own words, at the moment they notice it — and this task turns that sentence into a `misses.jsonl` record plus the matching checklist line. It **never boots the app, never reproduces anything, and never touches `src/` or `tests/`.**

## Why this exists

The framework had three ways to record a defect and all three were expensive. `*fix-issues` fixes it. `*triage-issues` boots the app and reproduces every issue before it writes a word. `*verify` grades a whole scope. All correct for what they do — and all far too heavy for *"the export button ignores the date filter, you missed that"*, which is how most misses are actually reported.

So they were not recorded at all. They became a sentence in chat, then a Remark if the owner was patient, then nothing. **An unrecorded miss is the exact problem the miss stream exists to solve**, and the friction of "first, boot the app" is what made it unrecorded. This task removes that friction and nothing else.

It is deliberately *not* a mode of `*triage-issues`: the moment logging requires a repro, it stops happening.

## Inputs

- `{AppName}` (required; or resolve from `core-config.yaml`).
- `{Description}` — the owner's own words. A sentence is enough. May name a REQ, a screen, a phase, or none of them.
- Optional: a screenshot path, a REQ id, `--fixed` (see §6).

## HARD SCOPE RULE

**This task writes records and documentation. Nothing else.** You may read source to identify the owning REQ. You MUST NOT edit `src/` or `tests/`, MUST NOT boot the app, MUST NOT spawn a builder sub-agent, and MUST NOT fix the thing being reported — however obvious the one-liner. If the owner wants it fixed, that is `*fix-issues`, and you say so in the report.

You also do not argue. If the owner says something was missed, it was missed. Your job is to classify it accurately, not to assess whether it was reasonable to miss.

## SEQUENTIAL Execution

### 0. Stamp the start time

`date -u +%Y-%m-%dT%H:%M:%SZ` — this run's `started` and its `found_run_id`.

### 1. Classify from what the owner said

Do not ask questions you can answer from the checklist and the docs. Resolve, in order:

1. **The owning REQ.** Match the description against `docs/{AppName}-Checklist.md` (and the DevGuide screen→REQ map if one exists). If the behaviour falls inside an existing REQ's scope, that is the `req_id`. **If nothing owns it, `req_id` is `null`** — that is a real and more interesting finding, not a failure to search hard enough.
2. **`miss_class`** — the closed enum (SCHEMA.md §5.5.1). The distinction that matters most:
   - The spec said it and the build did not do it → `missed-requirement` / `partial-implementation`, `origin_phase` = the build.
   - The spec never said it → **`unspecified-gap`**, `origin_phase` = the authoring command. This is a *design* miss and it is the one the framework was blind to.
   - It used to work → `regression`. It works but not as specified → `wrong-behaviour`.
3. **`why_missed`** — which *practice* let it through (SCHEMA §5.5.6): `missing-checklist-item` (nothing covered the behaviour) · `insufficient-verify-method` (acceptance existed; no gate could catch this) · `code-audit-limitation` (never runtime-observable) · `ambiguous-acceptance` · `dependency-not-declared` · **`instruction-ignored`** (a written framework rule existed and was not honoured) · `other`. **Omit rather than guess** — but when `found_by` is `owner`/`production` this is the most valuable field on the record, so answer it. If the owner's sentence names the reason ("you were told to X"), that is usually `instruction-ignored`.
4. **`artifact`** — `brd` / `architecture` / `uidesign` / `checklist` / `src` / `tests` / `config` / `devguide`.
5. **`severity`** — `blocker` / `major` / `minor`, by owner-visible impact. Not by how hard it looks to fix.
6. **`origin_phase` / `origin_agent` / `origin_run_id`** — read `docs/metrics/runs.jsonl` and find the most recent non-backfilled run whose `cmd` matches the responsible phase and whose `reqs_touched` contains the REQ. Pass its `started` as `origin_run_id`. **If you cannot find one, pass nothing** — the emitter marks the record `inferred` and nulls the model, which is the honest outcome.

Ask the owner **at most one** question, and only when the classification genuinely turns on it (usually: "was this ever specified?"). In YOLO / goal mode, take the sensible reading, mark it in the report, and continue.

### 2. Collapse check — never log the same defect twice

```bash
bash .tfcore/utils/tf-emit.sh --open-miss REQ-UI-014     # "<miss_id> <miss_class>", or nothing
```

If a miss is already open on that REQ with the same `miss_class`, **stop and say so**: "already logged as `MISS-…`, still open." Do not write a second record. Skip this check when `req_id` is `null`.

**But do not throw away what the owner just told you.** A repeat report often carries information the first record does not — most often *why* it was missed. If the open record's `why_missed` is `null` and the owner's sentence answers it, complete the record instead of duplicating it:

```bash
bash .tfcore/utils/tf-emit.sh --amend MISS-AstroLyfe-20260828-03 why_missed instruction-ignored
```

That appends a `miss-amend` (SCHEMA.md §5.5.7) — it fills a `null` field and refuses to overwrite a value that is already there, so it can never rewrite the original classification. **Never edit `misses.jsonl` by hand** (constraint 5); if `--amend` refuses, report the refusal and leave the stream alone. Say in your report which record you completed and with what.

### 3. Emit the miss

```bash
MID=$(bash .tfcore/utils/tf-emit.sh --next-miss-id)
cat <<JSON | bash .tfcore/utils/tf-emit.sh misses
{"kind":"miss","miss_id":"$MID","req_id":"REQ-UI-014","req_class":"UI",
 "miss_class":"partial-implementation","artifact":"src","severity":"major",
 "why_missed":"instruction-ignored",
 "origin_phase":"build-phase","origin_agent":"trblazeui",
 "origin_run_id":"<started, or omit>",
 "found_by":"owner","found_phase":"log-miss","found_gate":null,
 "found_run_id":"<the §0 timestamp>","failure_class":"blank-data"}
JSON
```

`found_by` is `"owner"` unless the owner is relaying a live report, which is `"production"`. **Never write `origin_model`, `origin_harness`, `origin_confidence`, or any token/cost field** — `tf-emit.sh` resolves them from the run you named (`_metrics-emit-gate.md` constraint 10).

**The owner's words never enter the record.** Closed vocabularies only; the sentence goes in the checklist Remark, where a human reads it (constraint 7).

### 4. Write it into the checklist — the record is not the deliverable on its own

**If the repo has no `docs/*-Checklist.md`** — a `framework` or `docs` project, or an app before `*split-brd` has run — there is nothing to demote and no row to add. **Emit the record and skip to §5**, saying so in the report (`Docs: no checklist in this repo — record only`). Do not invent a checklist, do not write the miss into `PROJECT-STATUS.md` instead (the guard hook blocks it, correctly), and do not treat the absence as a reason to skip the record: a framework's own misses are exactly as worth counting as an app's, and the stream is where they belong.

Otherwise, in `docs/{AppName}-Checklist.md`:

- **Existing REQ:** Status → `Needs re-verify`, % adjusted, plus a dated Remark — `⚠ miss {today}: {the owner's words, kept}` (`⚠ prod bug {today}:` when `found_by` is `production`). Demotions are always permitted; `guard-verify.sh` never blocks one. **NEVER write `Verified` from this task.**
- **No owning REQ:** append a new row — next free ID in the right prefix — Status `Planned`, Remark `logged via *log-miss {today}`, plus a detail bullet with its `<a id="d-req-…">` anchor stating the **acceptance that would close it**. If it is genuinely new scope rather than a defect, log the row and flag `*amend-docs` in the report; do not invent BRD text here.

### 5. Status gate + the run record

Update `PROJECT-STATUS.md` **and** re-render `PROJECT-STATUS.html` per `_status-update-gate.md` — next command is the `*fix-issues` pointer naming the REQ. Then:

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"log-miss","mode":null,
 "started":"<start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":["REQ-UI-014"],"reqs_count":1,
 "subagents":[],"files_written":<n>,"build_result":"not-run"}
JSON
```

`build_result` is always `"not-run"` — this task never builds.

### 6. `--fixed` — logging a miss that is already repaired

Sometimes the owner reports a miss *after* it has been fixed ("that export bug you fixed yesterday — you should never have missed it"). Recording only the fix would lose the miss; recording only the miss would leave it permanently open.

With `--fixed`, emit the `miss` as above, then close it:

```bash
FA=$(bash .tfcore/utils/tf-emit.sh --next-fix-attempt "$MID")
cat <<JSON | bash .tfcore/utils/tf-emit.sh misses
{"kind":"miss-fix","miss_id":"$MID","req_id":"REQ-UI-014",
 "fix_run_id":"<started of the run that fixed it, from runs.jsonl — or omit>",
 "fix_cmd":"log-miss","fix_attempt":$FA,"verdict_after":"Verified","reopened":false}
JSON
```

If you can identify the run that actually did the repair, name it and the cost attaches correctly. **If you cannot, omit `fix_run_id`** — the record is costed `none`, which is exactly right: the fix happened, and what it cost is not recoverable. Do not point at a plausible-looking run to make the number appear; that is a fabricated measurement, and one of them discredits every other cost figure in the report.

Do **not** demote the checklist row in `--fixed` mode — the REQ's status already reflects reality.

### 7. HALT — report

```
# Miss logged — {AppName}
{MISS-id}  {miss_class} / {artifact} / {severity}
Why missed : {why_missed | not assessed}
Owning REQ : {REQ-id | none — new Planned row REQ-FN-0NN}
Attributed : {origin_phase} ({origin_agent}) — {linked to run <ts> | inferred, no run record found}
Found by   : {owner|production}
Docs       : checklist row {demoted to Needs re-verify | added as Planned}, PROJECT-STATUS updated
Next       : /TechieFlow:agents:flow-master *fix-issues {AppName} {REQ-id}   (OpenCode: /flow-master)
```

Say plainly when attribution came out `inferred` — the owner should know that this miss will not appear in the per-model figures, and why.

## Hard rules

- **Never fix anything.** This task's deliverable is a record and a checklist line. `*fix-issues` fixes.
- **Never boot the app or reproduce.** That is `*triage-issues`, and requiring it here is what stopped misses being logged at all.
- **Never write `Verified`.** The ceiling here is a demotion (`guard-verify.sh` enforces it).
- **Never name a model or a token count.** The emitter resolves attribution and cost, or writes `null`.
- **Never free-text into telemetry.** Closed vocabularies in the record, the owner's words in the checklist Remark.
- **Never argue with the report.** Classify it and log it.
- **Never run git.**

## Output Checklist

- [ ] Owning REQ resolved from the checklist, or `req_id: null` recorded deliberately
- [ ] `--open-miss` collapse check run (skipped only when `req_id` is null); duplicate reported instead of re-logged — and if the open record's `why_missed` was null and the owner's words answered it, completed with `--amend` rather than duplicated or hand-edited
- [ ] `miss_class` / `why_missed` / `artifact` / `severity` chosen from the closed enums — no free text in the record; `why_missed` omitted rather than guessed, but present on any owner/production report
- [ ] `origin_run_id` resolved from `runs.jsonl`, or deliberately omitted; **no model name written**
- [ ] `misses.jsonl` record emitted (+ `miss-fix` if `--fixed`)
- [ ] Checklist updated — demotion with a dated `⚠ miss` Remark, or a new `Planned` row with acceptance (or: no checklist in this repo, stated in the report, record still emitted)
- [ ] PROJECT-STATUS `.md` **and** `.html` updated with the `*fix-issues` next command
- [ ] `runs.jsonl` record emitted
- [ ] Nothing under `src/` or `tests/` changed; app never booted

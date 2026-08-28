# triage-issues

The **ANALYZE-ONLY** front door for bugs a human found by running the app — UAT feedback, production reports, an owner test session. Flow-master reproduces each reported issue, triages it to its owning screen + REQ, and delivers **documentation, not code**: checklist updates (demotions + new bug REQ rows), an optional scoped regression re-verify, DevGuide known-issues notes, and a PROJECT-STATUS refresh whose next-command points at the fix. **It NEVER changes source code and NEVER spawns builder sub-agents.** Fixing is a separate, later decision the owner makes by running `*fix-issues` (or `*build-phase`).

## Why this exists

`*fix-issues` fixes — that is its deliverable. When the owner says "analyze these UAT bugs, re-verify the other features, and update the checklist", they want a **plan and a paper trail** — which REQs regressed, what is new, what still passes — WITHOUT an agent charging ahead and editing code nobody asked it to touch (that happened: AstroLyfe UAT, 2026-07-16 — an "analyze and log" request was routed into fixing). After this task runs, the checklist + PROJECT-STATUS fully describe the bugs, and NOTHING in `src/` or `tests/` has moved.

## Inputs

- `{AppName}` (required; or resolve from `core-config.yaml`).
- `{Evidence}` — one or both of:
  - a **folder** of screenshots (+ optional description file `bugs.md` / `README.md` / `notes.txt`) — the same evidence channel `*fix-issues` uses; and/or
  - a **written bug list** — chat text or a file path (UAT/production reports often arrive as prose).
  If neither is given, ask once for the folder path or the list.
- `[verify]` (optional literal) — after logging, ALSO execute a scoped regression re-verify (§5). Without it, the verifier is not run at all.

## HARD SCOPE RULE — read this before anything else

**This task is read-only on the application.** You may boot and drive the app, but you MUST NOT edit anything under `src/` or `tests/`, MUST NOT spawn `/trblazeui`, `/techierag`, or any fixer sub-agent, and MUST NOT "quickly fix" anything you find — however obvious the one-liner. The only files you write: `docs/{AppName}-Checklist.md`, the DevGuide's known-issues lines, `PROJECT-STATUS.md` + `.html`, and (in `verify` mode) whatever an executed verify-phase legitimately writes. If the owner asks mid-run for a fix, that is a NEW command (`*fix-issues`) — finish the triage deliverables first, then say so.

## SEQUENTIAL Execution

### 0. Stamp the start time

`date -u +%Y-%m-%dT%H:%M:%SZ` — keep it. It is this run's `started` and `run_id` for §6a.

### 1. Ingest the evidence

- If a folder was given: list it, **read every screenshot** (vision) and the description file if present.
- If a written list was given: extract one issue per distinct symptom, keeping the owner's wording in the record.
- Build a working list: `{ id, screen/route guess, role guess, symptom, evidence (image path or quoted words), kind-guess }` — kinds as in fix-issues: `layout`, `render-empty`, `data/logic`, `rag`. Final classification happens after repro (§3).

### 2. Boot the app (per `_smoke-test-policy.md` + `verify-phase.md §Local-only`)

- Boot it yourself via the build-invocation-ladder; dependent services in dependency order. "Can't run on Linux / it's MAUI / needs a GUI" are BANNED excuses; escalate per `verify-phase.md §3a`. Never propose a cloud deploy.
- Resolve a test login from `docs/{AppName}-UsageGuide.md` / the DB — never auto-create a random user.

### 3. Reproduce and triage each issue

For each issue: log in as the relevant role, navigate to the screen, and **reproduce the symptom**. Apply the data-render gate (`verify-phase.md §4a`) and the visual-truth gate (`§4b`) OBSERVATIONALLY, settle the issue's kind from what you see, and map it to the owning screen + `REQ-*` in `docs/{AppName}-Checklist.md` (DevGuide screen→REQ map). An issue that does not reproduce is recorded as `could-not-reproduce` with what you tried — never guessed at.

Echo a triage table — same shape as fix-issues §3, but the last column is the **checklist action**, not a builder:
```
Issue 1 → REQ-UI-007 (Dashboard) — kind: layout (KPI cards overlap chart)  → demote to Needs re-verify
Issue 2 → REQ-FN-014 (Clients)   — kind: render-empty (16 count, 0 rows)   → demote to Needs re-verify
Issue 3 → (no owning REQ — export button missing)                          → NEW row REQ-FN-021 (Planned)
Issue 4 → REQ-RAG-003 (Assistant)— could-not-reproduce (answer rendered OK) → dated Remark + owner question
```

### 4. Log the bugs — the checklist IS the deliverable

For each reproduced issue, in `docs/{AppName}-Checklist.md`:

- **Regression of an existing REQ** (the broken behaviour is inside a REQ's scope, whatever its current status): set Status → `Needs re-verify`, adjust % per the guide, and add a dated Remark — `⚠ UAT bug {today}: {symptom} (evidence: {path or "owner report"}; kind: {kind})` (use `⚠ prod bug` for production reports). Demotions are always allowed — guard-verify never blocks them. **NEVER write `Verified` from this task.**
- **Defect with no owning REQ** (behaviour that was never specified): append a NEW row — next free ID in the right prefix — Status `Planned`, Remark `logged from UAT {today}`, plus a detail bullet (with its `<a id="d-req-…">` anchor) in the matching section stating the ACCEPTANCE that would close it. If it is genuinely NEW SCOPE (a feature request, not a defect), still log the row but flag `*amend-docs` in the report — do not invent BRD text here.
- **Could-not-reproduce**: a dated Remark on the nearest REQ (no status change) + a question for the owner in the report.

### 5. Optional regression re-verify (`verify` argument only)

The owner often wants "and check the rest still works". With `verify`: read `.tfcore/tasks/verify-phase.md` and **EXECUTE it inline** (skip its §0 question — scope is known), scoped to (a) the demoted REQs' siblings — other REQs owning the same screens/services — and (b) any scope the owner named. This is a real verify-phase run: it writes the `docs/.last-verify.json` ledger and may legitimately write `Verified` / `FAIL` verdicts. Without `verify`, skip this section entirely — do not "informally" re-check other features and write verdicts from it.

### 6. Update the docs (status gate)

- **DevGuide:** add/refresh the affected screens' Known-issues lines (cite the evidence screenshot). If a screen is not in the DevGuide yet, note it for `*devguide {AppName} --update` — do not run a full devguide pass here.
- **PROJECT-STATUS (FINAL GATE, per `_status-update-gate.md`):** overwrite in place, `.md` AND `.html`. Phase reflects reality (open bug rows pull the project back to Build/Verify per the ladder). **Next command:** the bug rows just logged are build-tier work whose front door is **`*fix-issues {AppName} {Folder}`** — point there, naming the REQ IDs (fall back to `*build-phase {AppName}` when there is no evidence folder to hand it). Add a Verification-log row ONLY if §5 ran — triage by itself is not a verify pass.
- **Never run git.**

### 6a. Emit telemetry — this is where ESCAPE RATE comes from

Doctrine: `.tfcore/tasks/_metrics-emit-gate.md`. Schema: `.tfcore/telemetry/SCHEMA.md` §3.

A bug reaching this task means **every gate missed it** — it got past acceptance, data-render, visual-truth and standards, and a human found it in UAT or production. That fact exists nowhere else in the framework, and it is the only way escape rate can be computed. Emit it.

**One `gates.jsonl` record per REQ you demoted or newly logged in §4**, with `gate:"escaped"`:

```bash
ATT=$(bash .tfcore/utils/tf-emit.sh --next-attempt REQ-UI-009)
cat <<JSON | bash .tfcore/utils/tf-emit.sh gates
{"kind":"gate","app":"{AppName}","run_id":"<the run start timestamp>",
 "req_id":"REQ-UI-009","req_class":"UI","attempt":$ATT,"verdict":"Needs re-verify",
 "gate":"escaped","gates_run":[],"failure_class":"overlap","prior_verdict":"Verified"}
JSON
```

- `gate` is **always `"escaped"`** here. Never name a real gate — none of them fired; that is the entire finding.
- `gates_run` is `[]` — this task runs no gates. (Records written by the §5 verify pass are the verifier's, emitted by verify-phase §6a with real gate names. Do not duplicate them.)
- `prior_verdict` is the Status you demoted **from** — `Verified` there is the strongest possible signal and must be recorded faithfully.
- `failure_class` from the closed enum only. **Never the symptom text** — the symptom belongs in the checklist Remark, never in telemetry (constraint 7).
- **Could-not-reproduce → emit nothing.** No defect was established; a record would inflate the escape rate with a non-event.
- New `Planned` rows for never-specified behaviour: emit with `verdict:"FAIL"`, `prior_verdict:null` — the gap escaped just as surely, it simply had no REQ to escape from.

**Then one `misses.jsonl` record per reproduced issue** (SCHEMA.md §5.5). The `escaped` gate record above says *no gate caught it*; the miss record says *what was missed and which phase let it through* — the two answer different questions and both are wanted.

```bash
MID=$(bash .tfcore/utils/tf-emit.sh --next-miss-id)
cat <<JSON | bash .tfcore/utils/tf-emit.sh misses
{"kind":"miss","miss_id":"$MID","req_id":"REQ-UI-009","req_class":"UI",
 "miss_class":"regression","artifact":"src","severity":"blocker",
 "why_missed":"insufficient-verify-method",
 "origin_phase":"build-phase","origin_agent":"trblazeui",
 "origin_run_id":"<started of the run that last touched this REQ, from runs.jsonl>",
 "found_by":"owner","found_phase":"triage-issues","found_gate":null,
 "found_run_id":"<this run's start>","failure_class":"overlap"}
JSON
```

- **`found_by`** is `"owner"` for a UAT / owner test session and `"production"` for a live report. Nothing else — this field is what separates an in-cycle failure from a true escape, and it is the whole reason the record is worth writing.
- **`found_gate` is `null`.** No gate fired; that is the finding.
- **`why_missed` is NOT optional here.** Every record this task writes is an escape — it got past every gate and a human found it — so *why nothing caught it* is the entire value of the record, and the report warns when it is absent. Answer it from what you observed reproducing the bug: `missing-checklist-item` (no acceptance covered this behaviour), `insufficient-verify-method` (acceptance existed but no gate could have caught this), `code-audit-limitation` (the screen was never runtime-observable), `ambiguous-acceptance`, `dependency-not-declared`. This is the field that tightens the gates for next time.
- **Run the `--open-miss` collapse check first**, exactly as verify-phase does: if this REQ already has an open miss of the same `miss_class`, the owner has found the same defect the gates already know about — emit nothing.
- **A defect with no owning REQ** (a new `Planned` row in §4) is `req_id:null`, `miss_class:"unspecified-gap"`, `artifact:"brd"`. That combination is the single most valuable record in this stream: **it is a design miss, caught by a human, months after the phase that made it.**
- **Could-not-reproduce → emit nothing**, for the same reason no `gates` record is written: no defect was established.

Then one `runs.jsonl` record:

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"triage-issues","mode":null,
 "started":"<start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":["REQ-UI-009"],"reqs_count":1,
 "subagents":[],"files_written":<n>,"build_result":"not-run"}
JSON
```

`build_result` is `"not-run"` unless you actually built something (you did not — this task never touches code). **Telemetry has no veto:** a failed emit changes nothing and is not worth reporting.

### 7. HALT — report (and DO NOT fix)

```
# Triage — {AppName}
Evidence: {folder and/or written list} ({S} screenshots, {n} reported issues)
Reproduced: {r} → {d} REQs demoted to Needs re-verify, {p} new Planned rows | Could-not-reproduce: {x} (questions below)
Regression re-verify: {ran on <scope> — <pass>/<fail> | not requested}
Docs: checklist + DevGuide known-issues + PROJECT-STATUS (.md + .html) updated
NOTHING in src/ or tests/ was changed — fixing was not requested.
Next: /TechieFlow:agents:flow-master *fix-issues {AppName} {Folder}   (OpenCode: /flow-master)   (targets: {REQ IDs})
```

## Hard rules

- **Docs are the deliverable; code is untouchable.** No `src/`/`tests/` edits, no builder sub-agents, no "obvious one-liner" fixes. If you changed a source file, this task FAILED.
- **Never write `Verified` from triage.** Demote freely; promotion happens only through the §5 EXECUTED verify-phase (which writes its own run ledger).
- **Triage from what you OBSERVE** — reproduce live before logging; `could-not-reproduce` is a valid answer, never a licence to guess.
- **Boot it yourself**; documented test users only; never auto-create one.
- **Status gate is the last action** — PROJECT-STATUS `.md` AND `.html`; next command = the fix pointer with REQ IDs. Never run git.

## Output Checklist

- [ ] Evidence ingested — screenshots vision-read and/or prose parsed; issue list built
- [ ] App booted (incl. dependent services); documented test user used
- [ ] Every issue reproduced (or recorded could-not-reproduce) and mapped to screen + REQ — triage table echoed
- [ ] Checklist updated — demotions with dated `⚠ UAT bug` remarks; new `Planned` rows with acceptance detail bullets
- [ ] `verify` arg honoured (scoped verify-phase EXECUTED, ledger written) — or verifier untouched
- [ ] DevGuide known-issues refreshed; PROJECT-STATUS `.md` + `.html` updated; next command = `*fix-issues` pointer with REQ IDs
- [ ] ZERO source/test files modified; no builder sub-agent spawned
- [ ] `gates.jsonl` record with `gate:"escaped"` emitted per demoted/new REQ, + one `misses.jsonl` `miss` per reproduced issue (`found_by:"owner"`/`"production"`, collapse-checked), + one `runs.jsonl` record (§6a)

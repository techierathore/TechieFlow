# fix-issues

The single front door for fixing bugs the owner found by running the app — UI layout, broken rendering, wrong data, or logic. You drop **a folder of screenshots (+ an optional description file)**; flow-master reproduces each issue, triages where it lives, fans the fix out to the right builder, re-verifies, and updates the docs. **You never invoke the UI / functional / RAG agents yourself — flow-master calls them as sub-agents.**

## Why this exists

When the verifier passes but the running UI is still broken (overlapping controls, blank screens, wrong behavior), the owner needs ONE command to hand a pile of evidence to and have it fixed end-to-end — not to choreograph trblazeui, techierag, and the verifier by hand. `*fix-issues` is that command. It is generic: a bug can be anywhere (layout, data, logic, RAG), so it triages first and routes second. (Analysis WITHOUT fixing — "log these UAT bugs, don't fix yet" — is `*triage-issues`, not this task; see §0.)

## Inputs

- `{AppName}` (required; or resolve from `core-config.yaml`).
- `{Folder}` (required) — a path to a folder the owner filled with **screenshots** of the broken screens and, optionally, a **description file** (`bugs.md` / `README.md` / `notes.txt`) naming what's wrong on each (e.g. "Dashboard: KPI cards overlap the chart; Clients list shows count 16 but rows are blank"). If `{Folder}` is omitted, ask once for the folder path. (Screenshots-in-a-folder is the intended evidence channel — do not require the owner to describe bugs in chat.)

## SEQUENTIAL Execution

### 0. Scope guard — was a FIX actually requested?

**`*fix-issues` fixes.** If the owner's words ask only to **analyze / triage / log / document** the bugs, update the checklist, or re-verify other features — and do NOT ask for a fix — STOP: execute `.tfcore/tasks/triage-issues.md` instead (same evidence channel, docs-only deliverable) and let the owner decide about fixing afterwards. "Analyze these bugs" is NEVER permission to edit code.

### 1. Ingest the evidence

- List the folder. **Read every screenshot** (vision) and the description file if present. Build a working list of issues: `{ id, screen/route guess, role guess, symptom, evidence-image }`.
- For each issue, classify a first-guess **kind**: `layout` (overlap/clip/off-viewport/unstyled), `render-empty` (blank table/chart/value), `data/logic` (wrong values, failed action), `rag` (bad/empty AI answer). Final classification happens after repro (§3).
- If the description names screens/roles, use them; otherwise infer the screen from the screenshot (match against the DevGuide screen list / routes).

### 2. Boot the app (per `_smoke-test-policy.md` + `verify-phase.md §Local-only`)

- Boot the app yourself via the build-invocation-ladder; bring up dependent services (DB/LLM/API) in dependency order for a multi-service stack. "Can't run on Linux / it's multi-service / it targets Windows" are BANNED excuses; escalate per `verify-phase.md §3a` (rung #4 Windows-side → another port → ask the owner only as a last resort). Never propose a cloud deploy.
- Resolve a test login from `docs/{AppName}-UsageGuide.md` / the DB — never auto-create a random user.

### 3. Reproduce each issue live with Playwright

For each issue, log in as the relevant role, navigate to the screen, and **reproduce the symptom**:
- Take a fresh screenshot at desktop + a mobile width and compare to the owner's evidence.
- Apply the **data render gate** (`verify-phase.md §4a`) and the **visual-truth gate** (`§4b`): is the control blank? do controls overlap / clip / sit off-viewport? is it unstyled?
- Settle the issue's **kind** from what you observe (not just the owner's guess), and map it to the owning screen + `REQ-*` in `docs/{AppName}-Checklist.md` (use the DevGuide screen→REQ map). If an issue can't be reproduced, note it (maybe environment/data-specific) and ask the owner rather than guessing a fix.

Echo a triage table before fixing:
```
Issue 1 → REQ-UI-007 (Dashboard) — kind: layout (KPI cards overlap chart @ both widths) → /trblazeui
Issue 2 → REQ-FN-014 (Clients)   — kind: render-empty (grid 16 count, 0 rows)         → flow-master (data) 
Issue 3 → REQ-RAG-003 (Assistant)— kind: rag (empty answer)                            → /techierag
```

### 4. Fan out the fixes to the right builder (flow-master calls them — the owner does not)

In ONE turn, route each issue to its builder as a sub-agent, in parallel where they don't share files:
- **`layout` / UI** → invoke **`/trblazeui`** as a sub-agent: fix the Razor/CSS/component so it renders correctly and matches the mockup (greenfield) / intended layout; cite the REQ + the symptom + the screenshot. Page-layout fixes are trblazeui's job.
- **`render-empty` / `data` / `logic`** → spawn a **flow-master general-purpose subagent**: fix the binding/guard/column-mapping/service/query so the control actually renders its data (the `verify-phase §4a` failure modes — undeclared params, column→property mismatch, throwing computed getters, null guards).
- **`rag`** → invoke **`/techierag`** as a sub-agent: fix the RAG flow (ingestion/search/prompt/provider config).
- Each sub-agent tags its fix with the `[REQ-*]` tag in the checklist Remarks (**NEVER a git commit — git is manual; agents never run git/gh**), logs any library gap to the owning feedback file, and returns `{ reqsFixed[], filesChanged[], notes[] }`. Every sub-agent prompt MUST carry the two standing rules from `build-phase.md §3` verbatim (no git; smoke it yourself — library agents don't read `.tfcore/` tasks). Wait for all to return.

### 5. Re-smoke (data + visual) then re-verify the affected REQs

- Rebuild (invocation ladder). Re-smoke each fixed screen yourself: data renders AND it looks right at desktop + mobile (per `_smoke-test-policy.md` — both gates). If a fix didn't take, loop back to §4 for that issue.
- Chain the verifier: read `.tfcore/tasks/verify-phase.md` and run it inline scoped to the affected REQ IDs (skip its §0 question — scope is known). It applies §4a + §4b and writes verdicts into `docs/{AppName}-Checklist.md`.

### 6. Update the docs (status gate)

- **Checklist:** the verifier already wrote verdicts; confirm each fixed REQ is `Verified` (or note why not).
- **DevGuide:** refresh the affected screens' observed render/visual status + Known issues (the verifier's §6b does this; if a screen wasn't in scope, update it via `*devguide {AppName} --update`).
- **PROJECT-STATUS (FINAL GATE, per `_status-update-gate.md`):** update `PROJECT-STATUS.md` AND re-render `PROJECT-STATUS.html` — open requirements, a verification-log row, next command. A markdown-only update is incomplete.
- **Never run git.** Investigate by reading working-tree files at `file:line`, never a diff.

### 6a. Emit the run record

Same turn as the status gate. Doctrine: `.tfcore/tasks/_metrics-emit-gate.md`; schema `.tfcore/telemetry/SCHEMA.md` §2. Stamp `started` with `date -u +%Y-%m-%dT%H:%M:%SZ` at §1, before you ingest anything.

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"fix-issues","mode":"fix",
 "started":"<start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":["REQ-UI-009"],"reqs_count":1,
 "subagents":["trblazeui"],"files_written":<n>,"build_result":"pass"}
JSON
```

`mode` is always `"fix"` here — that is the whole point of this command. The verifier chained in §5 emits its own `gates.jsonl` records; do not emit those yourself. **Telemetry has no veto:** a failed emit never changes the outcome and is not worth reporting.

### 7. HALT — report

```
# Fix-issues — {AppName}
Evidence: {Folder} ({S} screenshots, {desc|no} description)
Issues: {N} triaged → {u} UI/layout, {d} data/render, {r} RAG, {x} could-not-reproduce
Fixed + re-verified: {f} REQs now Verified  |  Still open: {o} (reason)
Docs: checklist + DevGuide + PROJECT-STATUS updated (+ HTML re-rendered)
Next: {if open issues → re-run *fix-issues with the still-broken shots / *verify all ; else "all reported issues fixed and re-verified"}
```

## Hard rules

- **A fix must be ASKED for.** Analyze/log/document-only requests route to `.tfcore/tasks/triage-issues.md` (§0) — never start fixing on an analysis request.
- **One front door, flow-master routes.** The owner runs only `*fix-issues`; flow-master calls trblazeui / techierag / its own subagents. Never tell the owner to invoke a builder agent themselves.
- **Triage from what you OBSERVE, not just the owner's words.** Reproduce live before fixing; classify by the actual data + visual gates.
- **Both gates before "fixed".** A fix is done only when the screen renders its data AND looks right (no overlap/clip/off-viewport), confirmed by re-smoke + the verifier.
- **Boot the app yourself**, incl. multi-service stacks; asking the owner to run it is the last resort. Never propose a cloud deploy.
- **Use documented test users; never auto-create random ones.**
- **Status gate is the last action** — PROJECT-STATUS `.md` AND `.html`. Never run git.

## Output Checklist

- [ ] Evidence folder ingested — screenshots read (vision) + description parsed; issue list built
- [ ] App booted (incl. dependent services); documented test user used
- [ ] Each issue reproduced live and triaged (kind + owning REQ) — triage table echoed
- [ ] Fixes fanned out to the right builder (trblazeui / flow-master subagent / techierag) — owner did NOT invoke any agent
- [ ] Re-smoked (data + visual) and verifier re-run on the affected REQs (verdicts in the checklist)
- [ ] DevGuide affected screens refreshed; PROJECT-STATUS.md + .html updated (status gate)
- [ ] `runs.jsonl` record emitted with `cmd:"fix-issues"`, `mode:"fix"` (§6a)
- [ ] Report printed with fixed vs still-open counts

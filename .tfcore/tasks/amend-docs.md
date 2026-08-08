# amend-docs

Update the existing day-1 docs **in place** when a project's concept or requirements evolve — mid-development, or during the back-and-forth of defining a greenfield project. Surgically amends the BRD + Architecture (and ripples PROJECT-STATUS / BRD §4 / the checklists), preserving everything that didn't change. This is the **incremental** counterpart to re-running `*day1-*` (which archives the old docs and regenerates wholesale).

## When to use vs the alternatives

- **`*amend-docs`** (this task) — the concept shifted, or requirements were added / reworded / dropped, and you want to keep the existing docs and IDs and just fold the change in. Surgical, append-only, no archive.
- **`*author-brd`** — add NEW requirements interactively, one at a time (per-item elicitation). Use when you only need additions and want to confirm each. (`*amend-docs` can call into its append-only ID semantics for the additive part.)
- **Re-run `*day1-greenfield` / `*day1-brownfield`** — a full concept pivot where most of the docs are now wrong. The §1.6 collision policy archives the old docs to `docs/OldDocs/` and writes fresh. Do NOT use `*amend-docs` for that.

## Inputs

- `{AppName}` (required; or resolve from `core-config.yaml`).
- `{Change}` — free-form description of what changed: new features, reworded/expanded requirements, removed scope, stack changes, a new external integration, etc. May also be a **path to an amended concept doc / notes** to harvest. If absent, ask once: "What changed? Describe the new/changed/removed features or paste the amended concept (any length). I'll fold it into the BRD + Architecture without disturbing the rest."
- `{Scope}` — OPTIONAL: `brd` | `architecture` | `both` (default `both`).

## SEQUENTIAL Execution

### 1. Load the targets

- Read `.tfcore/core-config.yaml`; resolve `{AppName}`, the BRD (`docs/{AppName}-BRD.md`), and the Architecture (`docs/{AppName}-Architecture.md`). Note the highest existing `BRD-N`.
- Check whether the checklist exists (`docs/{AppName}-Checklist.md`) — it does iff `*split-brd` has run. This decides §6 (ripple).
- If a BRD doesn't exist at all, this isn't an amend — tell the user to run `*day1-*` first, and HALT.

### 2. Parse the change into a change-set

Classify every item in `{Change}` (harvesting a concept-doc path if given) into:

- **ADD** — a new capability / requirement / actor / integration not in the BRD yet.
- **MODIFY** — an existing capability whose behavior/scope changed (map it to the owning `BRD-N` / `F-code`).
- **REMOVE** — scope being dropped (map to the owning `BRD-N`).
- **ARCH** — structural impact: new/changed module, new runtime flow, stack/library change, new ADR-worthy decision.

### 3. Confirm the change-set ONCE before writing (single gate, not per-item)

Present the parsed change-set as a numbered table and ask the user to confirm or amend it:

```
Proposed amendments to {AppName}:
ADD     → new BRD-{next..} : {one-line each}
MODIFY  → BRD-{n} : {old → new, one line}
REMOVE  → BRD-{n} : {reason}
ARCH    → {module/flow/ADR} : {what changes}
Confirm to apply (these are in-place edits; existing BRD IDs are never renumbered). Reply `go`, or correct any line.
```

Wait for `go` (or corrections, then re-show). This is the ONLY interaction — once confirmed, apply everything in bulk. (For a purely additive change where the user wants per-item confirmation instead, defer to `.tfcore/tasks/author-brd.md` for the ADD items and skip this gate.)

### 4. Amend the BRD (append-only, in place)

Apply the confirmed change-set to `docs/{AppName}-BRD.md` — **edit in place, do NOT archive to OldDocs, do NOT regenerate the whole doc, preserve every unchanged section verbatim:**

- **ADD** → assign the next unused `BRD-N` (continue from the highest; never reuse a removed ID). Add/extend the owning `### F-{CODE}` feature-catalog entry (what/why, screens table, workflow, owning BRD-N), append the one-line statement to the §10 ledger, and add a `Planned` row to the §4 Development-status table for any new F-code.
- **MODIFY** → edit the EXISTING `BRD-N` text in place (keep the ID) and update its feature-catalog entry. Note the revision inline if helpful.
- **REMOVE** → mark `~~BRD-N~~ (removed {YYYY-MM-DD}: reason)` in the ledger and its feature entry — **never delete or renumber**. The ID stays retired.
- **Diagrams:** update any BRD diagram the change touches; add a diagram for any new multi-step/multi-actor flow. Every diagram MUST follow `.tfcore/templates/v4custom/html-render-shell.md §5.5` (quoted labels, no `end` node id).
- **Footer:** update `Highest BRD ID: BRD-{N}` and add/update a `Last amended: {YYYY-MM-DD} — {one-line summary}` line.
- **INFORMATION-PRESERVATION:** the amended BRD is a superset of the prior one minus only the explicitly-removed items — never a re-summarization. If the doc got shorter for any reason other than a REMOVE, you over-compressed; restore it.

### 5. Amend the Architecture (in place)

If `{Scope}` includes architecture and there are ARCH items, edit `docs/{AppName}-Architecture.md` in place:

- Update the affected §4 modules (prose + table rows), add new modules where introduced — preserve unchanged modules verbatim.
- Update or add the runtime flow diagrams the change affects (§5.5 authoring rules).
- Add an ADR for any new significant decision (`ADR-{next} — {decision}` with a one-line reason); never rewrite a historical ADR — supersede it with a new one if reversed.
- Update the stack line if the change altered it.
- Status note: keep the existing status (`Target` / `Current`) and append `amended {YYYY-MM-DD}: {summary}`.

### 6. Ripple to the checklist (only if it already exists)

If `*split-brd` has run (checklist present), the BRD change must reach the per-REQ table — but **never clobber existing statuses by re-splitting blindly:**

- **New BRD-N (ADD):** append new `REQ-*` row(s) to the one checklist `docs/{AppName}-Checklist.md` (the prefix carries the type — `REQ-UI/FN/NFR/RAG-*`), Status `Not started`, with the new ID's acceptance criteria in its Details anchor. Pick the REQ type the way `split-brd` does. **If the ADD is a UI change and mockups exist** (`docs/{AppName}-UIDesign.md`), the new `REQ-UI-*` should cite its mockup screen — if that screen doesn't exist yet, flag it in the §7 report to run `*mockups {AppName} --update` so the new screen gets a mockup before build.
- **MODIFY:** find the REQ rows derived from that BRD-N and set their Status to `Needs re-verify` (or add a Remark) so the verifier re-grades them — do not silently flip to Verified.
- **REMOVE:** mark the derived REQ rows `N/A (removed {date})`; keep the rows for traceability.
- If the mapping from BRD-N → REQ-* is non-obvious for a MODIFY/REMOVE, list those rows in the §7 report and ask the user rather than guessing.
- **If the checklist does NOT exist yet** (pre-split greenfield still in discovery): nothing to ripple — note that the next `*split-brd {AppName}` will pick up all the amendments.

### 7. Re-render + status gate (MANDATORY)

- Re-render the touched HUMAN docs to HTML via `.tfcore/tasks/generate-html.md` (shared shell): `docs/{AppName}-BRD.html` always; `docs/{AppName}-Architecture.html` if §5 ran. **Do NOT render the checklist to HTML** even though §6 may have changed its rows — it is an AI-agent working document kept in markdown only. (If the amendment changed code-level flows, refresh the DevGuide separately via `*devguide {AppName}`; if it changed greenfield UI/screens, refresh the mockups via `*mockups {AppName} --update`.)
- **Run `.tfcore/tasks/_status-update-gate.md`:** update `PROJECT-STATUS.md` (`last_updated`, a "Where I am" line noting the amendment, the BRD §4 Development-status rollup per gate item 9) and re-render `PROJECT-STATUS.html`. Add a one-line note to PROJECT-STATUS: `Docs amended {date}: {summary}`.

### 7a. Emit the run record (telemetry)

Same turn as the status/PROJECT-STATUS write. Doctrine + the nine constraints: `.tfcore/tasks/_metrics-emit-gate.md`. Schema: `.tfcore/telemetry/SCHEMA.md` §2. Stamp `started` with `date -u +%Y-%m-%dT%H:%M:%SZ` as your FIRST action of this task — it cannot be reconstructed at the end.

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"amend-docs","mode":null,
 "started":"<start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":[],"reqs_count":0,
 "subagents":[],"files_written":<n>,"build_result":"not-run"}
JSON
```

`reqs_touched` carries REQ IDs only — never requirement text — and `[]` is correct when this task touched no specific REQ. **Telemetry has no veto:** if the emit fails, the phase still succeeded; do not retry, do not diagnose, do not mention it.

### 8. HALT — amendment report

Print:

```
# Docs amended — {AppName}
BRD:   +{a} added (BRD-{x}..BRD-{y}) · {m} modified · {r} removed   (highest now BRD-{N})
Arch:  {modules/flows/ADRs touched, or "no change"}
Checklist: {rows appended / flagged for re-verify / removed, or "not split yet — run *split-brd"}
Re-rendered: {list of .html}

Next: {if new reqs and not split → "*split-brd {AppName}"} / {if new UI screens need mockups → "*mockups {AppName} --update"} / {if reqs need building → "*build-phase {AppName}"} / {else "review the rendered docs"}
```

## Hard rules

- **In-place, surgical.** Preserve every unchanged section verbatim. NEVER archive the doc to `docs/OldDocs/` and NEVER regenerate the whole doc — that is `*day1-*`'s job, and using it here would destroy unchanged content and history.
- **BRD IDs are append-only.** Never renumber; removed IDs are struck through and retired, never reused.
- **One confirmation gate** (§3), then bulk-apply. Do not per-item elicit unless the user explicitly wants the additive-only `*author-brd` path.
- **Never edit source code.** This task only touches the docs (and the checklist Status tables per §6).
- **Full pivot ≠ amendment.** If the change invalidates most of the BRD/Architecture, tell the user to re-run `*day1-greenfield`/`*day1-brownfield` instead, and HALT.

## Output Checklist

- [ ] Change-set parsed (ADD/MODIFY/REMOVE/ARCH) and confirmed once with the user
- [ ] BRD amended in place — new BRD-N appended, modified IDs edited in place, removed IDs struck through; §4/§9/§10 + footer updated; no renumbering; no OldDocs archive
- [ ] Architecture amended in place (if in scope) — modules/flows/ADRs updated, unchanged sections preserved
- [ ] Checklist rippled (new REQ rows appended / modified flagged for re-verify / removed marked) — or noted "not split yet"
- [ ] BRD.html (+ Architecture.html as touched) re-rendered; every diagram passes the §5.5 self-check (the checklist is NOT rendered to HTML — markdown only)
- [ ] PROJECT-STATUS.md updated via the status gate (incl. BRD §4 rollup) + PROJECT-STATUS.html re-rendered
- [ ] Amendment report printed with the next command

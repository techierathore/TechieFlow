# _status-update-gate (shared rule — included by every checklist-executing task)

## The rule

**Every agent that executes a checklist or phase MUST update PROJECT-STATUS — BOTH `PROJECT-STATUS.md` AND its rendered `PROJECT-STATUS.html` — as its final action, before reporting "done", before handing back to the user, before chaining to another agent. This is non-negotiable and non-skippable.**

A phase is not complete when the build passes or the tests are green. It is complete when PROJECT-STATUS reflects the new reality. **"Update PROJECT-STATUS" always means the markdown AND the HTML — never the `.md` alone.** The owner reads the `.html` to check status; a status update that touches only the markdown leaves the page the human actually looks at stale, which defeats the entire purpose of the gate. If you wrote `PROJECT-STATUS.md` but did not re-render `PROJECT-STATUS.html`, you are NOT finished. If you are about to end your turn and you have not written both, you are not finished.

## What "update PROJECT-STATUS" means (minimum)

1. `last_updated: {today YYYY-MM-DD}`.
2. `current_phase` set to where the project now is.
3. `last_verified_build` + `last_verified_date` reflect the most recent build.
4. **Open requirements** list synced to the checklist's **Requirements Status** table — every REQ not yet `Verified` stays listed.
5. **Next command to run** updated to the exact next step, expressed **only as a command pointed at a checklist/scope** — e.g. `/TechieFlow:agents:verifier *verify ui` (filters `docs/{AppName}-Checklist.md` to `REQ-UI-*`) or `/TechieFlow:agents:flow-master *build-phase {AppName}` (with both Claude Code and OpenCode forms where they differ). **Do NOT write a prose description of the technical work to do next** — no "next, wire up the X service and fix the Y binding and then add validation to Z". The *what* already lives in the checklist's REQ rows; PROJECT-STATUS only says **which command to run against which checklist/REQs**. If you need to point at specific items, name the REQ IDs (e.g. "resume FAILed `REQ-UI-007`, `REQ-UI-012`"), not a paragraph explaining how to fix them. Keep the whole "Next command to run" section to the command block plus, at most, one line naming the target REQ IDs.
6. A new **Verification log** row whose "Status table" column links to the checklist that holds the per-REQ detail (`docs/{AppName}-Checklist.md#requirements-status`) — NOT a dated `docs/qa/*.md` file (those no longer exist).
7. Library-feedback counts + standards-compliance lines refreshed if the phase touched them.
8. **HTML refresh (MANDATORY — every time, same turn you edit the `.md`):** re-render `PROJECT-STATUS.html` from the markdown you just wrote (use `.tfcore/tasks/generate-html.md` with the shared shell — never hand-rolled HTML). This is not optional cleanup and not a "later" step — the owner reads the `.html`, so a markdown-only update is an **incomplete** update that fails this gate. If you edited `PROJECT-STATUS.md` you re-render `PROJECT-STATUS.html` in the same turn, full stop. **Do NOT render the checklists to HTML** — they are AI-agent working documents kept in markdown only (the per-REQ Requirements Status table is the agent's source of truth, not a human HTML page).
9. **BRD §4 Development status rollup** (keeps the human BRD snapshot tracking reality). If `docs/{AppName}-BRD.md` has a `## … Development status` section, refresh it from the checklists:
   - One row per feature (each §"Feature catalog" `### F-…` entry). Roll its owned REQs up to a feature-level status: feature → its `Requirements: BRD-…` line → the `REQ-*` those BRDs split into → the per-REQ Status in the checklist tables.
   - Map: **all** owned REQs terminal (`Verified` / `Done (pre-existing)` / `N/A`) → `Done`, 100%; some done + some open → `Partial` with an approximate %; work started but nothing verified (`In Progress`/`Implemented`) → `In progress`; nothing started → `Planned`, 0%; any `Blocked` REQ → keep the feature's computed status and add a short "blocked: …" note.
   - Update ONLY the table cells + the `Snapshot as of {today}` line — touch nothing else in the BRD (no requirement text, feature prose, or BRD-N IDs). Then re-render `docs/{AppName}-BRD.html` via `generate-html.md`.
   - **If the BRD has no Development status section** (a BRD authored before this section existed): do NOT do section surgery inside a build phase — leave the BRD untouched and add one line to your phase report: "BRD has no §4 Development status section — run `*refresh-status {AppName}` once to add it." (`refresh-status` owns the insert + renumber.)

## Single source of truth

Per-REQ status, %, remarks, and bugs live in the **Requirements Status** table at the top of the one checklist (`docs/{AppName}-Checklist.md`, all REQ prefixes in a single table). Do not create separate dated result files (`docs/qa/*.md`, `docs/verify/*.md`). Smoke and verify write INTO that table. PROJECT-STATUS summarizes and points at it. The **BRD §4 Development status** table (item 9) is a *derived* feature-level rollup of those same tables — a human snapshot, never an independent source of truth; always recompute it from the checklists, never the other way round.

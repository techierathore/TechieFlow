# refresh-status

Rebuild `PROJECT-STATUS.md` from **ground-truth evidence** after a development session was interrupted (lost internet, revoked/changed model access, crashed agent, killed terminal) — i.e. whenever a build/verify phase died BEFORE its mandatory status-update gate (`.tfcore/tasks/_status-update-gate.md`) ran, leaving PROJECT-STATUS stale, wrong, or silent about work that actually happened.

## Purpose

The normal flow guarantees PROJECT-STATUS is accurate because every phase ends by writing it. When a phase is killed mid-flight, that guarantee is broken: code may have been written, checklist tables may be half-updated, and PROJECT-STATUS still points at an old "Next command" that no longer matches reality. **This task does NOT trust PROJECT-STATUS.** It reconstructs the true state from the evidence that actually exists in this framework — the checklist Requirements Status tables, what is really in the working tree (the source files and when they were last touched), and a fresh build — then rewrites PROJECT-STATUS to match and tells you the exact next command.

> **No git.** In this framework git is **manual and agent-owned by the human, never by an agent** — no task commits, and nothing here keys off commit history. Ground truth lives in the checklist tables, the files on disk, and the build. (This is a deliberate design rule, mechanically enforced: `.claude/settings.json` DENIES `git`/`gh` and the `.tfcore/hooks/block-git.sh` PreToolUse hook blocks compound forms — see the CLAUDE.md "Hard rules" section.) Do **not** run `git` in this task.

This is a **read-and-reconcile** task. It NEVER edits application source code and NEVER implements requirements. Its only writes are to `PROJECT-STATUS.md`, its `.html`, the checklist Requirements Status tables (Status/%/Remarks cells only, never new files, and only when hard evidence says a cell is wrong), and the BRD's **§4 Development status** table — the derived feature-level snapshot (§4.5), including inserting that section into a legacy BRD that predates it.

## Inputs

- `{AppName}` argument (required; or resolve from `.tfcore/core-config.yaml`).
- Optional flag `verify` — after reconciling, chain the verifier on any REQ whose true state is ambiguous (see §5). Default is reconcile-only (fast).

## SEQUENTIAL Execution

### 1. Gather ground truth (read-only — run these in parallel)

Collect evidence the interrupted agent could not have faked or selectively updated. Do NOT read PROJECT-STATUS first and reason from it — gather independently, compare last.

1. **Checklist Requirements Status table** (the primary source) — read the top table in the one checklist `docs/{AppName}-Checklist.md` (all REQ prefixes in a single table). This is the per-REQ source of truth (Status / % / Remarks). Terminal statuses: `Verified`, `Done (pre-existing)`, `N/A`. Note `Blocked` rows (library gaps) and especially any row left at `In Progress`/`Implemented` (smoke done, verifier never ran — the classic interruption fingerprint).
2. **What is actually in the working tree** — look at the source the checklists imply should exist, and *when it was last touched*:
   - For the REQs the tables claim are done/in-progress, confirm the corresponding components/services/pages actually exist on disk (a row marked `Implemented` whose files are absent is suspect; a row left open whose files DO exist is work that happened but was never recorded).
   - Compare file modification times against PROJECT-STATUS `last_updated` (read in step 4): **source files newer than `last_updated`** are work that landed *after* the last gate write — the status undercounts it. This is the no-git replacement for "what was committed since the last status write".
   - Use `ls -lt`, `find . -newer PROJECT-STATUS.md -type f` (scoped to the app's source dirs), Glob/Grep — read-only inspection only. Never modify, stage, or commit anything.
3. **Fresh build** — run `dotnet build` via the invocation ladder at `.tfcore/templates/v4custom/build-invocation-ladder.md` (solution-scan first; a `.sln`/`.slnx` with any MAUI/iOS/Android project starts at rung #4; workload errors `NETSDK1178`/`Microsoft.*.Sdk missing` mean wrong rung, not failure). Record PASS/FAIL and real `CS####` errors only.
4. **The stale PROJECT-STATUS** — read `PROJECT-STATUS.md` LAST, and only to see what it CLAIMED (`last_updated`, `current_phase`, "Next command"). Treat every field as a hypothesis to confirm or overwrite, never as fact. (Its `last_updated` is also the cutoff you compared file mtimes against in step 2.)
5. **Library feedback files** — glance at `docs/{AppName}-TrBlazeUI-Feedback.md` / `docs/{AppName}-TechieRag-Feedback.md` for open `Blocked`-causing entries.

### 2. Detect the interruption signature

Decide what really happened by comparing the evidence. Common signatures:

- **Worked-but-unrecorded:** source files newer than PROJECT-STATUS `last_updated`, and/or files exist on disk for REQs the tables still show as open → the work landed but the gate never ran. The checklist tables and/or PROJECT-STATUS undercount progress.
- **In-flight / partial:** a REQ's expected files only partially exist, or the fresh build errors inside them → a phase was mid-implementation. Those REQs are **In Progress**, NOT done — even if a subagent reported them done before dying.
- **Smoke-without-verify:** checklist rows at `Implemented`/`In Progress` with no `Verified` → self-smoke ran, verifier was cut off. Those REQs need verification, not rebuilding.
- **Build regressed:** PROJECT-STATUS says `last_verified_build: PASS` but step 1.3 fails → a later edit broke the build; capture the real `CS####` errors as a Known blocker.
- **Phase boundary lost:** every row is terminal but PROJECT-STATUS still says `current_phase: Build` → phase actually advanced to `Handoff`; correct it.

State the detected signature in one or two plain sentences. If evidence conflicts (e.g. a table marks a REQ `Implemented` but the build fails on that file), trust the **build + files on disk over the table cell**, and flag the REQ as `PARTIAL`/`FAIL` with a note.

### 3. Reconstruct the true per-REQ picture

For each REQ in the checklist, settle on a status from evidence, in this precedence:

1. **Verifier verdict already in the table** (`Verified`/`FAIL`/`PARTIAL`) → keep, unless step 1.3's build contradicts it.
2. **`Done (pre-existing)` / `N/A`** → terminal, keep, never touch.
3. **Implementing files present on disk + build PASS + a smoke/verify Remark present** → `Implemented` (pending verify) at minimum; do not upgrade to `Verified` without a verifier verdict.
4. **Files absent, partial, or build-broken for that REQ** → `In Progress`; do NOT mark done on a dead subagent's say-so.
5. **No evidence of any work** → leave as the original open status.

Only write a checklist cell when evidence **contradicts** what's there (e.g. table says `FAIL` but the implementing files are present and the build now passes → set `Implemented` with a dated Remark `recovered by refresh-status: files present + build PASS, pending re-verify`). When in doubt, prefer the *less complete* status — under-claiming triggers a re-verify; over-claiming ships a bug. Never invent `Verified`.

**Reconciling a Status column UP to `Verified`** is allowed in exactly one case: the row's Remarks **already carry a dated verifier verdict** (e.g. `VERIFIED 2026-07-07 …`) that the Status column merely lagged. The PreToolUse hook `.tfcore/hooks/guard-verify.sh` blocks any checklist write introducing `Verified` without a same-day run ledger, so first Write `docs/.last-verify.json` as `{"date":"<today>","app":"{AppName}","mode":"reconcile","evidence":"<the pre-existing verdict date(s) + REQ IDs>"}`, then make the cell edit. Reconcile-mode is ONLY for surfacing a pre-existing verdict — never for promoting smoke results or files-on-disk evidence to `Verified`.

### 4. Rewrite PROJECT-STATUS.md (the whole point)

Overwrite `PROJECT-STATUS.md` to reflect the reconstructed reality, honoring every minimum in `.tfcore/tasks/_status-update-gate.md`.

**Rebuild to the CRISP, FIXED-SHAPE template** (`.tfcore/templates/v4custom/app-project-status-tmpl.md`) — the gate's §"CRISP, FIXED-SHAPE snapshot" applies in full to a reconstruction. Start from the template's section set; do NOT copy forward the old file's per-run dated sections (`## *verify all — formal coverage matrix (…)`, `## *fix-issues — …`, `## *build-phase — …`) or its paragraph-stuffed `current_phase`. If the file you are rebuilding has them, they are the mess this task exists to clean up — drop them, fold any still-true facts into the one-paragraph `## Where I am` + the `## Verification log` table, and keep the result well under ~60 lines. The ONE extra section a reconstruction adds is the `## Recovery note` (item 8) — and only because this was an interrupted-session rebuild. Concretely:

1. `last_updated: {today YYYY-MM-DD}`.
2. `current_phase` = where the evidence says the project actually is (not what the file claimed).
3. `last_verified_build` + `last_verified_date` from step 1.3's real build.
4. **Open requirements** = every non-terminal REQ from the reconciled tables.
5. **Next command to run** = the exact command that resumes from the true state (Claude Code + OpenCode forms). Examples:
   - in-flight build work → `/TechieFlow:agents:flow-master *build-phase {AppName}` (FIX/FRESH mode will re-detect the open REQs from the now-correct table; it calls trblazeui/techierag itself).
   - smoke-without-verify → `/TechieFlow:agents:verifier *verify ui` (or `functional`/`all`).
   - all built, verify open → `/TechieFlow:agents:verifier *verify all`.
6. A **Verification log** row only if a verifier actually ran this session (don't fabricate one); otherwise leave the log untouched.
7. Library-feedback + standards-compliance lines refreshed only if evidence changed them.
8. Add a one-block **`## Recovery note ({today})`** section at the end recording: the interruption signature (step 2), which files were found newer-than-status / present-for-open-REQs, which checklist cells were corrected and why, and any REQ now flagged for re-verify. This is the audit trail so the next session — human or AI — knows this status was reconstructed, not gate-written.

Then **re-render** `PROJECT-STATUS.html` via `.tfcore/tasks/generate-html.md` with the shared shell — never hand-rolled HTML. A stale HTML defeats the recovery. Do NOT render the checklists to HTML — they are AI-agent working documents (markdown only); correcting their Requirements Status tables in markdown is sufficient.

### 4.5. Sync the BRD §4 Development status snapshot

Bring `docs/{AppName}-BRD.md`'s **§4 Development status** table in line with the reconciled checklist statuses — it is the human, feature-level view of the same reality you just rebuilt. Use the rollup rule in `.tfcore/tasks/_status-update-gate.md` item 9 (feature → its `Requirements: BRD-…` line → the `REQ-*` those BRDs split into → per-REQ Status; map all-terminal → `Done`, mixed → `Partial`, started-but-unverified → `In progress`, none → `Planned`).

- **If the BRD already has a Development status section:** refresh its rows from the rollup and set `Snapshot as of {today}`.
- **If the BRD has NO such section** (a BRD authored before this section existed — e.g. AstroLyfe): **insert it now** (one-time migration). Add a `## 4. Development status` H2 immediately after the Scope section, **renumber the following H2 sections by +1**, and **regenerate the BRD's `## Table of Contents`** to match (slug rule = `.tfcore/templates/v4custom/html-render-shell.md §1`). Then fill the table via the rollup. After this run, the status gate keeps it current on every phase.
- Touch ONLY the §4 table, the heading renumber + TOC the insert requires, and the snapshot date — never requirement text, feature prose, or BRD-N IDs.
- Re-render `docs/{AppName}-BRD.html` via `.tfcore/tasks/generate-html.md` (shared shell). If you renumbered, double-check every BRD diagram still passes the §5.5 mermaid self-check (you didn't touch them, but the re-render must not introduce bare labels).
- Note in the §6 report whether §4 was refreshed in place or inserted (migration), and which features changed status.

### 5. Optional verify pass (only if `verify` flag given, or you flagged ambiguity)

If invoked with `verify`, or if step 3 left any REQ in an evidence-ambiguous state (files present but never smoked/verified), chain the verifier: read `.tfcore/tasks/verify-phase.md` and execute it inline with the narrowest scope that covers the ambiguous REQs (`ui` / `functional` / `all` / explicit REQ-ID list) — skip its §0 question, scope is known. The verifier writes verdicts into the tables; then re-run step 4's PROJECT-STATUS write so it reflects the fresh verdicts. The verifier never edits source, so this stays safe to run during recovery.

### 6. Report to the user

Print a tight recovery summary (this is for a human who just lost their session):
- **What happened:** the interruption signature in one line.
- **What was recovered:** worked-but-unrecorded REQs, in-flight REQs, build state.
- **What PROJECT-STATUS now says:** current_phase + open-REQ count.
- **Exact next command** to resume (copy-paste, both harness forms).
- **Anything needing a human decision** (e.g. half-finished edits to review, or work the human may want to commit manually before resuming — committing is the human's job, never this task's).

## Guardrails

- NEVER run `git` (or `gh`). Git is manual in this framework; this task reconstructs status from checklist tables + working-tree files + build only.
- NEVER edit application source code, requirement text, feature prose, BRD-N IDs, or Architecture content. The ONLY BRD edit permitted is maintaining the **§4 Development status** table — a derived snapshot — plus, for a legacy BRD lacking it, inserting that one section with the heading-renumber + TOC regen described in §4.5. Everything else in the BRD is read-only.
- NEVER mark a REQ `Verified` without an actual verifier verdict produced this session or already present in the table.
- NEVER create dated `docs/qa/*.md` / `docs/verify/*.md` files. The checklist tables + PROJECT-STATUS are the only status surfaces.
- Prefer under-claiming to over-claiming when evidence is thin — a needless re-verify is cheap; a falsely-"done" bug is not.
- This task is itself a checklist-executing task: it ends by leaving PROJECT-STATUS accurate. Do not hand back before §4 is written.

## Output Checklist

- [ ] Ground truth gathered independently (checklist tables, working-tree files + mtimes, fresh build) BEFORE reading PROJECT-STATUS — and WITHOUT git
- [ ] Interruption signature stated
- [ ] Per-REQ statuses reconciled from evidence (no fabricated `Verified`)
- [ ] `PROJECT-STATUS.md` overwritten to true state with a dated `## Recovery note`
- [ ] BRD §4 Development status table refreshed from the reconciled checklists (or inserted + headings renumbered + TOC regenerated, for a legacy BRD that lacked it) — §4 table only, no requirement text touched
- [ ] `PROJECT-STATUS.html` and `docs/{AppName}-BRD.html` re-rendered (checklists are NOT rendered to HTML — markdown only)
- [ ] Optional verify pass run if requested / ambiguity remained
- [ ] User given the exact copy-paste next command

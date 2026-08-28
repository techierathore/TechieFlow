# mockups

Produce the **UI design / mockups** for a greenfield app: a per-screen UI Design Spec (`docs/{AppName}-UIDesign.md`) plus **rendered HTML mockups** (`docs/mockups/*.html`) styled to look like TrBlazeUI, each annotated with a `region → TrBlazeUI control` component map. This is the visual design the build is matched against and the verifier's visual-truth gate diffs the live app against.

## Why this exists

A greenfield app has no code, so its UI is built freehand from prose requirements — which is exactly why a new app's UI comes out broken (overlapping controls, wrong layout, nothing to verify against). Mockups give the build an **approved visual contract** and give `verify-phase.md §4b` a **baseline to diff** the running screen against. They are **TrBlazeUI-replicable by construction**: the analyst designs only with controls the library actually ships, so `/trblazeui` can reproduce them 1:1.

## When to use

- **At greenfield day-1** — auto-run by `day1-greenfield §3.6`, after the BRD draft; approved with the BRD + Architecture before build.
- **On demand** — `*mockups {AppName}` to (re)generate, or `*mockups {AppName} --update` to refresh only changed/new screens after an `*amend-docs` that added UI.
- **Greenfield only.** Brownfield already has built screens — it uses the DevGuide's captured screenshots (`devguide §5a/§5b`) as its visual baseline instead.

## Inputs

- `{AppName}` (required; or resolve from `core-config.yaml`).
- `{Scope}` — OPTIONAL: `all` (default) · a screen/route · a comma-list. Limits which screens are (re)mocked.
- `--update` — OPTIONAL: refresh only screens whose BRD feature changed or that are new; preserve unchanged mockups verbatim.

## SEQUENTIAL Execution

### 1. Read the TrBlazeUI component catalog FIRST (design only with what exists)

Before designing anything, learn what the library actually provides:
- Read `.trblazeui/TrBlazeUI-AI-Reference.md` (the component reference; if absent, run `dotnet build` once to deploy it, or ask the `/trblazeui` agent for its component catalog).
- Optionally converse with the **`/trblazeui` agent** to confirm which controls exist and how they're composed (it owns the library knowledge).
- Build a working list of available controls (nav, cards, grids, forms, dialogs, charts, layout shells, inputs). **You design ONLY with these** — a mockup that uses a layout/control TrBlazeUI can't produce is worse than none (it guarantees drift). If a screen genuinely needs something the library lacks, note it and log a `docs/{AppName}-TrBlazeUI-Feedback.md` entry (TR-NNN) so the gap is tracked rather than silently designed-in.

### 2. Derive the screen list from the BRD

- Read `docs/{AppName}-BRD.md` §9 Feature catalog — its screens-and-routes tables and per-feature workflows are the screen list. Also read `docs/{AppName}-Architecture.md` for the UI host/layout choice.
- Produce the flat screen list: `screen (route) → role(s) → owning BRD-N`. Echo a one-line count: `N screens to mock`.
- **No-UI app:** if the concept is purely an API/service with no screens, record `docs/{AppName}-UIDesign.md` = "skipped — no UI in this app" and HALT (this is not an error; `day1-greenfield` treats it as skipped).

### 3. Design each screen — spec + rendered mockup (FAN OUT for many screens)

Load `.tfcore/templates/v4custom/app-uidesign-tmpl.md`. For each screen (fan out across subagents when there are many — one per screen-cluster — to bound tokens):

1. Decide the **layout** (regions: nav, sidebar, content blocks) using TrBlazeUI's layout shell components.
2. Write the **component map** — every region → the specific TrBlazeUI control that renders it + the data it shows + its empty/loading/error states. This is the build contract.
3. Produce the **rendered mockup** `docs/mockups/{screen-slug}.html`: a self-contained HTML page that *looks like the real screen* using TrBlazeUI's design language (its CSS tokens / classes where known, or a close visual approximation — spacing, colors, typography, component shapes). Use realistic placeholder data so the layout reads true. Each mockup is a static preview, not wired — but its STRUCTURE (regions, control types, arrangement) must be what the build will produce.
4. Fill the screen's spec block in `docs/{AppName}-UIDesign.md` (mockup link, component map table, layout one-liner, interaction + state notes).

Keep the visual language consistent across screens (one shell, one theme, one spacing system) so the set reads as one app.

### 4. Assemble + render

- Fill the UIDesign header (§"Design system" from §1's catalog — name the layout shell, theme, and the controls inventory the app uses).
- Regenerate the UIDesign Table of Contents (slug rule `html-render-shell.md §1`; list each `### Screen:` under "Screens").
- Render `docs/{AppName}-UIDesign.md` → `docs/{AppName}-UIDesign.html` via `.tfcore/tasks/generate-html.md` (shared shell — it's a human doc). The `docs/mockups/*.html` screens are already HTML; leave them as-is.
- **`--update`:** only (re)write changed/new screens + their mockups; preserve the rest verbatim; re-render the UIDesign HTML.

### 5. PROJECT-STATUS note (light touch — NOT the full gate)

Add/refresh one line under "Where I am" / artifacts: `Mockups generated {date}: docs/{AppName}-UIDesign.md (+ .html) + docs/mockups/ ({N} screens)`. This task does not change build/verify state — do not touch `current_phase` or `last_verified_build`. (When run inside `day1-greenfield`, that task owns the status write.)

### 5a. Emit the run record (telemetry)

Same turn as the status/PROJECT-STATUS write. Doctrine + the ten constraints: `.tfcore/tasks/_metrics-emit-gate.md`. Schema: `.tfcore/telemetry/SCHEMA.md` §2. Stamp `started` with `date -u +%Y-%m-%dT%H:%M:%SZ` as your FIRST action of this task — it cannot be reconstructed at the end.

```bash
cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs
{"kind":"run","app":"{AppName}","cmd":"mockups","mode":null,
 "started":"<start>","ended":"<now>","duration_s":<n>,
 "reqs_touched":[],"reqs_count":0,
 "subagents":[],"files_written":<n>,"build_result":"not-run"}
JSON
```

`reqs_touched` carries REQ IDs only — never requirement text — and `[]` is correct when this task touched no specific REQ. **Telemetry has no veto:** if the emit fails, the phase still succeeded; do not retry, do not diagnose, do not mention it.

### 6. HALT — report

```
# Mockups — {AppName}
Screens mocked: {N}   TrBlazeUI controls used: {list}   Library gaps logged: {g}
Files: docs/{AppName}-UIDesign.md (+ .html) · docs/mockups/*.html ({N} screens)
Next: review/approve the mockups (open docs/mockups/*.html); they are the visual contract the build matches and the verifier diffs against. Then *split-brd → *build-phase.
```

## Hard rules

- **TrBlazeUI-replicable only.** Read the component catalog first; design with controls that exist. A mockup the library can't produce is a defect — flag + log the gap, never design it in silently.
- **Every screen has a component map** (`region → TrBlazeUI control`). The map is the build contract; a pretty picture with no control mapping is not enough.
- **Mockups are a HUMAN doc → rendered to HTML.** Unlike the checklist, the UIDesign spec renders to HTML; the mockups are HTML by construction.
- **Greenfield only.** Do not run for a brownfield app with built screens (use the DevGuide screenshots instead).
- **Never edit source code.** This task only writes the design docs/mockups.
- **Incremental on `--update`.** Preserve unchanged screens verbatim; only remock what changed.

## Output Checklist

- [ ] TrBlazeUI component catalog read FIRST; design uses only existing controls (gaps logged to the feedback file)
- [ ] Screen list derived from BRD §9 feature catalog (or "skipped — no UI" recorded)
- [ ] `docs/{AppName}-UIDesign.md` written: per-screen spec with a `region → TrBlazeUI control` component map + state notes
- [ ] `docs/mockups/{screen}.html` rendered for every screen, styled to look like TrBlazeUI, consistent across the set
- [ ] `docs/{AppName}-UIDesign.html` rendered (human doc); mockups left as HTML; the checklist is NOT involved here
- [ ] PROJECT-STATUS got the one-line mockups note (no full status gate)
- [ ] Report printed; mockups ready for owner approval

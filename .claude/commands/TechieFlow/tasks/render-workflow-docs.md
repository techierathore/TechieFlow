# render-workflow-docs

Render BRD.html, Architecture.html, and PROJECT-STATUS.html from their markdown sources.

## Purpose

After day-1 (or any phase that changes BRD/Architecture/PROJECT-STATUS), regenerate the human-readable HTML mirrors. Self-contained single-file HTML with Mermaid rendering, copy buttons on every code block, mermaid toolbar (zoom/fit/1:1/fullscreen/popout), inline TOC, and sidebar TOC for long docs.

**If the user has ad-hoc HUMAN-readable docs to render (library-feedback files, design notes, archived docs, anything else), use `*generate-html @path/to/file.md` instead — this task only handles the three canonical files.** Note: the **checklist is an AI-agent working document and is NEVER rendered to HTML** — do not render `*-Checklist.md` here or via `generate-html`.

## Inputs

- `{AppName}` argument (required).
  - If absent, read `.tfcore/core-config.yaml` → `customTechnicalDocuments.brd` and extract the app name from `docs/{AppName}-BRD*.md`. If both are absent, ask: "Application name?"

## SEQUENTIAL Execution

### 1. Locate sources

**Use the Read tool — NOT bash.** Bash file-existence checks trigger permission prompts; the Read tool is auto-allowed.

For BRD and Architecture, locate the file using this priority:

1. If `core-config.yaml` has `customTechnicalDocuments.brd` (or `.architecture`) pointing at a specific path, USE that path verbatim.
2. Otherwise look for `docs/{AppName}-BRD.md` and any versioned variants matching `docs/{AppName}-BRD*.md` (e.g. `docs/{AppName}-BRD-v2.md`, `docs/{AppName}-BRD-old.md`, `docs/{AppName}-BRD-V3.md`). Same for Architecture. Top-level `docs/` ONLY — never scan `docs/OldDocs/` (the archive folder the day-1 tasks move superseded docs into; archived files are not render candidates). Since the day-1 collision policy (day1-brownfield §1.6) archives old versions instead of suffixing new ones, multiple variants should only occur in projects predating that policy.

**If multiple variants are found, ASK before rendering** — list each candidate with its `Last updated:` value if visible, and ask which one to render. This is the one-and-only question this task may ask, and it's required to avoid the bug where a stale BRD gets rendered when a fresh versioned one (`-v2.md`) is sitting next to it.

If the user wants to render a different file than what the canonical name pattern resolves to, tell them to use `*generate-html @docs/{the-file}.md` (plain path without `@` under OpenCode) and HALT.

PROJECT-STATUS is always at the repo root: `PROJECT-STATUS.md`.

Read each of the three resolved files. If any required source is missing, HALT and tell the user which is missing + suggest `*day1-brownfield` / `*day1-greenfield`.

For the "Last rendered" subtitle, use today's date — do not bash-fetch file mtimes.

### 2. Render with the framework renderer — one command for every document

```bash
bash .tfcore/utils/tf-render-html.sh docs/{AppName}-BRD.md docs/{AppName}-Architecture.md PROJECT-STATUS.md
```

`tf-render-html.sh` implements `.tfcore/templates/v4custom/html-render-shell.md` in full and reads that spec's §2 CSS / §3 theme script / §7 JS **at render time**, so a rendered page cannot drift from the shell — the drift that used to break the mermaid toolbar, the copy buttons and the TOC links is now structurally impossible.

Pass every document in ONE invocation; it renders each to a sibling `.html` (same directory, same basename). It refuses `*-Checklist.md` with exit 2.

Hand-authoring these files through the Write tool is no longer the path (TfLens TF-003, 2026-08-27): it burned 75–80k output tokens per phase, could not be reproduced run-to-run, and a 130 KB file emitted in one generation could silently truncate with no gate to catch it.

`html-render-shell.md` stays the specification — read it to understand or change the shell, not to render.

### 3. Render `docs/{AppName}-BRD.html` (or the chosen variant's `.html` sibling)

**Rendered by `tf-render-html.sh` in step 2** — do not hand-author it, and do not bash-heredoc it. This step documents what the output must contain so you can check it, not how to build it.

Output path: same directory as the source MD, same basename, `.html` extension (so `docs/{App}-BRD-v2.md` → `docs/{App}-BRD-v2.html`).

Apply the full shell. Title: `{AppName} — Business Requirements`. Subtitle: `Last rendered: {today YYYY-MM-DD}`.

BRDs typically have ~12 H2 sections (Executive summary, Objectives, Scope, …, Glossary) — the sidebar TOC condition (>6 H2) almost always triggers. Inline TOC is always present.

### 4. Render `docs/{AppName}-Architecture.html` (or chosen variant's `.html` sibling)

Same as §3. Title: `{AppName} — Architecture`. Subtitle: `Last rendered: {today YYYY-MM-DD} · Status: {value of "Status:" line from source MD}`.

Architecture docs typically have 7–9 H2 sections — usually >6, so sidebar TOC triggers. Inline TOC always present.

### 5. Render `PROJECT-STATUS.html`

Apply the shell. Title: `{AppName} — Project Status`. Subtitle: `Last rendered: {today YYYY-MM-DD}`.

PROJECT-STATUS usually has 4–6 H2 sections — under the >6 threshold, so NO sidebar (use the `no-toc` class on `.layout`). Inline TOC may still appear if ≥2 H2.

**`tf-render-html.sh` emits the "NEXT COMMAND TO RUN" call-to-action box itself** (since 2026-08-31, TfLens TF-010) — you do not add it, and you must not hand-patch it in afterwards. It special-cases `PROJECT-STATUS.md`, reads the **first fenced code block under `## Next command to run`**, and emits this markup immediately after the subtitle `<div>`, above the frontmatter table and the inline TOC:

```html
<div class="cta-next" style="padding:20px; background:var(--cta-bg); border:2px solid var(--accent); border-radius:10px; margin:20px 0;">
  <div style="font-size:11px; color:var(--muted); letter-spacing:.5px;">NEXT COMMAND TO RUN</div>
  <div style="font-family:var(--mono); font-size:18px; margin-top:6px;">{first line of that code block}</div>
</div>
```

Theme variables only, never a hex — that is what `--cta-bg` is for, in both palettes.

**If the box is missing, the source is missing, not the render.** The renderer emits nothing when `## Next command to run` is absent or its code block is empty — an absent box is honest, an invented command is not. Fix `PROJECT-STATUS.md` per `_status-update-gate.md` and re-render; do not edit the HTML.

> **Why this is worth a paragraph.** From TF-003 (when hand-authoring moved into the script) until 2026-08-31 this section *required* the box and the renderer never emitted one, so the Output Checklist item below was unfalsifiable by reading the task, and the only workaround — patching the generated HTML — was overwritten by the next render. The tell was `--cta-bg`: a shell variable defined in both palettes and used by nothing.

Render the frontmatter (project, stack, current_phase, last_verified_build, last_verified_date) as a clear definition list near the top.

### 6. Verify each HTML mentally (per shell §9)

This is a review of what you Wrote — do NOT shell out to an HTML validator. Confirm:

- Every heading id matches the TOC link slug.
- Every mermaid fence is wrapped in `<div class="diagram">` with the full 6-button toolbar.
- **Mermaid validity pass (shell §5.5):** every node/edge/subgraph label containing non-alphanumeric characters is double-quoted (quotes inside the shape brackets), and no node id is the reserved word `end`. Fix any bare label in the emitted HTML rather than rendering a diagram that throws "Syntax error" in the browser.
- Copy buttons will be added by the JS (no need to verify visually — but make sure the JS block is intact).
- Sidebar TOC present iff H2 count > 6.
- The two CDN scripts are present (mermaid, svg-pan-zoom).

### 7. Output summary

List the three written file paths (one per line). End with: `Open each in a browser to confirm Mermaid renders correctly. Code blocks have copy buttons; diagrams have a zoom/fit/1:1/fullscreen/popout toolbar.`

## Output Checklist

- [ ] All three sources located (BRD/Architecture variants resolved with user input if multiple matched)
- [ ] Shared shell applied to every output (no hand-rolled palettes)
- [ ] `docs/{AppName}-BRD.html` (or chosen variant) self-contained
- [ ] `docs/{AppName}-Architecture.html` (or chosen variant) self-contained
- [ ] `PROJECT-STATUS.html` self-contained, and its "NEXT COMMAND TO RUN" call-to-action present — **check it with `grep -c "NEXT COMMAND TO RUN" PROJECT-STATUS.html`, which must print `1`.** The renderer emits it (§5); a `0` means `PROJECT-STATUS.md` has no `## Next command to run` code block, which is a status-gate defect to fix in the markdown — never by editing the HTML.
- [ ] Mermaid blocks wrapped in `.diagram` with toolbar
- [ ] Mermaid validity pass done (shell §5.5): every non-trivial label double-quoted, no `end` node ids, bare labels fixed not emitted
- [ ] Copy-button JS + mermaid toolbar JS present in each file
- [ ] Inline TOC present where H2 count ≥ 2
- [ ] Sidebar TOC present where H2 count > 6
- [ ] Every TOC link has a matching heading `id` (shell §1 slug rule)

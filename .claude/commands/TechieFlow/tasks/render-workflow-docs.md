# render-workflow-docs

Render BRD.html, Architecture.html, and PROJECT-STATUS.html from their markdown sources.

## Purpose

After day-1 (or any phase that changes BRD/Architecture/PROJECT-STATUS), regenerate the human-readable HTML mirrors. Self-contained single-file HTML with Mermaid rendering, copy buttons on every code block, mermaid toolbar (zoom/fit/1:1/fullscreen/popout), inline TOC, and sidebar TOC for long docs.

**If the user has ad-hoc HUMAN-readable docs to render (library-feedback files, design notes, archived docs, anything else), use `*generate-html @path/to/file.md` instead — this task only handles the three canonical files.** Note: the **checklists are AI-agent working documents and are NEVER rendered to HTML** — do not render `*-UI-Checklist` / `*-Functional-Checklist` here or via `generate-html`.

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

If the user wants to render a different file than what the canonical name pattern resolves to, tell them to use `*generate-html @docs/{the-file}.md` and HALT.

PROJECT-STATUS is always at the repo root: `PROJECT-STATUS.md`.

Read each of the three resolved files. If any required source is missing, HALT and tell the user which is missing + suggest `*day1-brownfield` / `*day1-greenfield`.

For the "Last rendered" subtitle, use today's date — do not bash-fetch file mtimes.

### 2. Read the shared HTML rendering shell

Read **`.tfcore/templates/v4custom/html-render-shell.md`** in full. Apply every section (§1 slug rule, §2 CSS, §3 skeleton, §4 anchors, §5 mermaid wrapper, §6 code blocks, §7 JS, §8 inline TOC, §9 checklist) to each HTML you write below.

Do NOT hand-roll a different CSS palette or skip the scripts. If the BRD/Architecture/PROJECT-STATUS HTMLs ever drift from the shared shell, the user's mermaid toolbar / copy buttons / TOC links break.

### 3. Render `docs/{AppName}-BRD.html` (or the chosen variant's `.html` sibling)

**Use the Write tool — NOT bash heredocs / `cat <<EOF` / `echo >`.**

Output path: same directory as the source MD, same basename, `.html` extension (so `docs/{App}-BRD-v2.md` → `docs/{App}-BRD-v2.html`).

Apply the full shell. Title: `{AppName} — Business Requirements`. Subtitle: `Last rendered: {today YYYY-MM-DD}`.

BRDs typically have ~12 H2 sections (Executive summary, Objectives, Scope, …, Glossary) — the sidebar TOC condition (>6 H2) almost always triggers. Inline TOC is always present.

### 4. Render `docs/{AppName}-Architecture.html` (or chosen variant's `.html` sibling)

Same as §3. Title: `{AppName} — Architecture`. Subtitle: `Last rendered: {today YYYY-MM-DD} · Status: {value of "Status:" line from source MD}`.

Architecture docs typically have 7–9 H2 sections — usually >6, so sidebar TOC triggers. Inline TOC always present.

### 5. Render `PROJECT-STATUS.html`

Apply the shell. Title: `{AppName} — Project Status`. Subtitle: `Last rendered: {today YYYY-MM-DD}`.

PROJECT-STATUS usually has 4–6 H2 sections — under the >6 threshold, so NO sidebar (use the `no-toc` class on `.layout`). Inline TOC may still appear if ≥2 H2.

ADD a prominent call-to-action box at the very top of `<main>` (above the inline TOC):

```html
<div style="padding:20px; background:var(--cta-bg); border:2px solid var(--accent); border-radius:10px; margin:20px 0;">
  <div style="font-size:11px; color:var(--muted); letter-spacing:.5px;">NEXT COMMAND TO RUN</div>
  <div style="font-family:var(--mono); font-size:18px; margin-top:6px;">{value from Next command section of PROJECT-STATUS.md}</div>
</div>
```
(Uses theme variables so the box stays legible in both light and dark — never hardcode hex here.)

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
- [ ] `PROJECT-STATUS.html` self-contained with "NEXT COMMAND TO RUN" call-to-action
- [ ] Mermaid blocks wrapped in `.diagram` with toolbar
- [ ] Mermaid validity pass done (shell §5.5): every non-trivial label double-quoted, no `end` node ids, bare labels fixed not emitted
- [ ] Copy-button JS + mermaid toolbar JS present in each file
- [ ] Inline TOC present where H2 count ≥ 2
- [ ] Sidebar TOC present where H2 count > 6
- [ ] Every TOC link has a matching heading `id` (shell §1 slug rule)

# /generate-html Task

> Claude Code note: this command file embeds `.tfcore/tasks/generate-html.md` VERBATIM — regenerate
> it whenever that task changes; do not edit the embedded body here. It is also the copy
> `update-framework.sh` pushes to every app's `.claude/commands/`, so drift here ships everywhere.

When this command is used, execute the following task:


# generate-html

Convert one or more **human-readable** markdown files to self-contained HTML using the shared shell. Use this when you need to render documents that `*render-workflow-docs` does not cover (the UsageGuide, the DevGuide, library-feedback docs, ad-hoc design notes, legacy/archived docs). Note: suffixed doc variants like `-v2` are banned by the collision policy (day1-brownfield §1.6) — superseded docs live unmodified in `docs/OldDocs/`.

**NEVER render the checklist to HTML.** The `*-Checklist.md` (and its Requirements Status table) is an **AI-agent working document** — agents read it in markdown. An HTML mirror just burns tokens and drifts from the source. If asked to render a `*-Checklist.md`, decline and explain it's an agent doc; if a stale `*-Checklist.html` exists from before this rule, the user may delete it.

## Why this exists

`*render-workflow-docs` only renders the three canonical files (`{App}-BRD.md`, `{App}-Architecture.md`, `PROJECT-STATUS.md`). When the user has additional or versioned docs, this task accepts explicit paths.

## Invocation forms

```
*generate-html @path/to/file.md
*generate-html @path/to/file1.md @path/to/file2.md @path/to/file3.md
*generate-html @docs/SomeFolder/
```

(Or via the slash-command wrapper: `/TechieFlow:tasks:generate-html @path/to/file.md` in Claude Code; `/techieflow:tasks:generate-html path/to/file.md` in OpenCode. **The `@` sigil is Claude Code's file-mention; under OpenCode type the plain path WITHOUT `@`** — an `@file` in an OpenCode prompt inlines the entire file into context, wasting tokens. This task accepts both forms and treats them identically.)

Note: the `@` prefix is Claude Code's file-mention sigil. OpenCode treats a leading `@` as file-content-inclusion, so pass plain paths there.

- **Single file:** convert that one MD to a sibling HTML.
- **Multiple files:** convert each. List separated by spaces. Each becomes a sibling HTML.
- **Directory:** convert every `*.md` directly inside that directory. **Non-recursive** — do not descend into subdirectories. If the user wants subdirectories included, they can pass each subdir as another argument.

If no arguments are passed, HALT and tell the user: `Usage: *generate-html @<path-to-md-or-dir> [@<more-paths>]`.

## Inputs

- One or more `@`-prefixed paths (the `@` is Claude Code's file-mention sigil; strip it when resolving the actual path).
- Paths may be absolute or relative to project root.

## SEQUENTIAL Execution

### 1. Resolve the input set

For each argument:
- Strip leading `@`.
- If the path ends with `/` or is a directory: use the Read tool to read each `*.md` directly under that directory (non-recursive, no subdirs).
- Otherwise: treat as a single file path.
- Skip any path that doesn't exist; emit a one-line note for each skip and continue with the rest. Do not HALT unless ZERO paths resolve.

If ZERO paths resolve, HALT with: `No markdown files found at the given paths. Check the paths and retry.`

Echo a one-line summary: `Rendering N markdown file(s): file1.md, file2.md, ...`.

### 2. For each MD, build the HTML

**Run the renderer. Do NOT hand-author HTML.**

```bash
bash .tfcore/utils/tf-render-html.sh docs/{AppName}-BRD.md PROJECT-STATUS.md
```

It takes one or more `.md` paths, writes a sibling `.html` for each, and implements `html-render-shell.md` in full — §1 slugs (with dedupe), §2 CSS, §3 skeleton + flash-free theme script, §4 heading anchors *and* hand-written `<a id="…"></a>` anchors preserved verbatim, §5 mermaid toolbar wrapper, §5.5 label self-check, §6 escaped code blocks, §6b agent-note strip, §7 JS, §8 inline + sidebar TOC (sidebar only above 6 H2s). It reads the CSS and JS **out of the spec file at render time**, so the output cannot drift from the spec.

Hand-authoring the HTML through the Write tool is no longer the path: it cost 75–80k output tokens per phase for documents whose content barely changed, produced non-reproducible output, and risked silent truncation on large files (TfLens TF-003, 2026-08-27). Reserve it for the case where the renderer genuinely cannot express something — and report that as a framework defect rather than hand-rolling around it.

**Read the output.** The renderer prints one line per file (size, H2 count, sidebar yes/no, diagram count, notes stripped) and warns on `⚠ mermaid §5.5` for an unquoted flowchart label or a reserved `end` node id. Those warnings are about the **source `.md`** — fix the diagram in the markdown and re-render; never edit the generated HTML.

**It refuses to render a checklist** (`*-Checklist.md`, exit 2) — that ban is now mechanical, not just prose.

Read `.tfcore/templates/v4custom/html-render-shell.md` when you need to understand or change the shell; it remains the specification. You do not need to read it just to render.

For each MD file:

1. **Read** the source MD content.
2. **Extract title** from the first `#` heading; if none, derive from the filename (humanize: replace `-` and `_` with spaces, title-case).
3. **Build the heading list** (every `##`, `###`, `####`): for each, compute the slug per shell §1, attach an `id` to the heading, and decorate with the anchor link `<a class="anchor-link" href="#{slug}">#</a>`. Dedupe slugs by appending `-2`, `-3`, ... when a slug already exists in the doc.
4. **Decide TOC mode:**
   - If H2 count > 6: render with sidebar TOC (no `no-toc` class).
   - Otherwise: render with `no-toc` class on `.layout` and omit the `<nav class="side">` block.
   - **Always** render the inline `.toc-inline` block at the top of `<main>` when H2 count ≥ 2.
5. **If the MD source already contains a `## Table of Contents` section**, replace it inline with the inline `.toc-inline` HTML block (don't double-render). Use the same slugs you assigned in step 3 so links work.
6. **Convert body markdown** to HTML:
   - Paragraphs, bold/italic, links, lists, tables, blockquotes — standard markdown → HTML.
   - Code fences: `` ```mermaid `` → §5 `<div class="diagram">` wrapper with toolbar buttons; any other code fence → §6 `<pre><code class="language-{lang}">{escaped}</code></pre>`.
   - Inline code: `<code>...</code>`.
   - HTML comments in source (`<!-- ... -->`): pass through.
   - **Agent-facing authoring notes NEVER render as visible text.** The doc templates carry drafting-agent instructions (the "Depth mandate", "Mermaid mandate", "read before drafting" notes, how-to-use-this-template guidance) as HTML comments, which pass through invisibly. If the source MD still carries such a note as a **visible** blockquote or paragraph — text addressed to the drafting/authoring AGENT rather than to the document's human reader (typical in docs generated from pre-2026-07 templates) — **OMIT it from the rendered HTML** and, if you are also allowed to edit the MD, convert it to an HTML comment there. List every such omission in the output summary. Reader-facing blockquotes (a DevGuide's verification-status banner or Purpose note, a UsageGuide's test-user rules, etc.) stay.
7. **Assemble** using the §3 skeleton, with §2 CSS inlined verbatim in `<head>`, and §7 JS inlined verbatim at end of `<body>`. The mermaid + svg-pan-zoom CDN scripts go just before the JS.
8. **Write** the output to `{same-dir}/{basename}.html` (replace `.md` with `.html`). If the file already exists, overwrite.

### 3. Validate (mental review — no shell-out)

Per shell §9 checklist, for each rendered file confirm:
- CSS palette and JS pasted verbatim.
- Every TOC entry's `href` matches an existing heading `id`.
- Every mermaid fence wrapped in `.diagram` with all 6 toolbar buttons.
- Sidebar present iff H2 count > 6.
- No external resource references except the two CDN scripts.

**Mermaid validity pass (do this for EVERY diagram — it is the #1 reported bug).** Apply the shell §5.5 self-check to each mermaid block before emitting it:
- Each node/edge/subgraph label that contains anything other than letters, digits, and spaces (i.e. has `(` `)` `/` `&` `:` `,` `[` `]` `{` `}` `#` `@` `<` `>` `|` `"` etc.) MUST be wrapped in double quotes, with the quotes INSIDE the shape brackets (`API["ASP.NET API (v2)"]`, `DB[("SQL Server")]`).
- No node id is a reserved word (lowercase `end`).
- If you find a bare label in the source MD, **fix it in the emitted HTML** (quote it) rather than copying through a diagram you know will throw "Syntax error" in the browser. Note any such fix in the output summary so the author can also fix the MD source.

Do NOT shell out to an HTML validator. Do NOT `wc -c` the files. Do NOT `du`.

### 4. Output summary

Print one line per rendered file: the absolute output path. End with: `Open each in a browser to confirm Mermaid renders correctly and copy buttons / diagram toolbars work.`

## Output Checklist

- [ ] Every input MD has a sibling HTML produced
- [ ] Each HTML is self-contained (no broken local refs)
- [ ] Sidebar TOC present only when H2 count > 6
- [ ] Inline TOC present when H2 count ≥ 2
- [ ] Every heading has an id matching the TOC link
- [ ] Mermaid diagrams have working toolbar (zoom, fit, 1:1, fullscreen, popout)
- [ ] Mermaid validity pass done (shell §5.5): every non-trivial label double-quoted, no `end` node ids, bare labels fixed not emitted
- [ ] No agent-facing authoring note (Depth/Mermaid mandate, template how-to) rendered as visible text — leaked ones omitted and reported
- [ ] Copy buttons present on every `<pre>` (added by JS, no need to inject manually)

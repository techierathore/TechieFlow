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

(Or via the slash-command wrapper: `/TechieFlow:tasks:generate-html @path/to/file.md`)

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

Read **`.tfcore/templates/v4custom/html-render-shell.md`** for the full rendering specification. Apply every section (§1 slug rule, §2 CSS, §3 skeleton, §4 anchors, §5 mermaid wrapper, §6 code blocks, §7 JS, §8 inline TOC). Use the Write tool to create the sibling HTML — never bash heredocs.

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
- [ ] Copy buttons present on every `<pre>` (added by JS, no need to inject manually)

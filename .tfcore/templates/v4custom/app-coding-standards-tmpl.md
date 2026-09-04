<!-- tf-schema
doc: coding-standards
file: docs/{App}-Coding-Standards.md
header: App, Stack answer set, Date
section: Standards applied | required
section: Project rules | required
section: Enforcement | required
budget: S 800 1200 | M 800 1200 | L 800 1200
rule: standards-pointer
-->
<!-- Authoring notes (agent only; never visible text).
     The standards themselves live in the framework and are not copied here:
       .tfcore/standards/coding-standards-core.md    (every project, technology-neutral)
       .tfcore/standards/coding-standards-<stack>.md (the stack's answer set, e.g. dotnet)
     This file says which of those apply and lists only the rules specific to this project.
     The Project rules table is often empty; a mixed-technology build rule or a per-project naming
     choice is the kind of thing that belongs here. Fixed budget for every size. -->

# {App} — Coding Standards

| | |
|---|---|
| App | {App} |
| Stack answer set | {name, or "none"} |
| Date | {YYYY-MM-DD} |

## Standards applied

| File | Applies | Notes |
|---|---|---|
| `.tfcore/standards/coding-standards-core.md` | yes | every project |
| `.tfcore/standards/coding-standards-{stack}.md` | yes | {from the Stack answer set} |

Per-project choices the stack file leaves open:

| Choice | Decision |
|---|---|
| {e.g. instance-field prefix} | {…} |

## Project rules

Rules that hold in this project only. Empty is a valid answer.

| Rule | Why | Since |
|---|---|---|
| {…} | {…} | {YYYY-MM-DD} |

## Enforcement

- **Editor configuration:** `.editorconfig` at the repository root carries the machine-checkable subset.
- **Analyzers:** {which, or "none"}.
- **Verifier checks:** the standards check runs the greps listed in the stack file's Enforcement section, plus: {any project-specific grep, or "none"}.

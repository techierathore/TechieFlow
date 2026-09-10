# create-project-brief

`*create-project-brief {App}` writes `docs/{App}-Brief.md`, the one page day-1 reads. It is the cheapest place to be wrong, so it is short and the owner corrects it in two minutes.

First: `bash .tfcore/utils/tf-phase.sh start create-project-brief {App}` prints the start time and marks the command running.

## Inputs

- `{App}`, or read it from `core-config.yaml`.
- Whatever the owner gives: a paragraph, a brainstorm result (`docs/brainstorming-session-results.md`), a conversation, or nothing.

## Steps

1. Read `.tfcore/templates/v4custom/app-brief-tmpl.md` — its schema block is the required shape.
2. Fill the five sections from what the owner gave. Ask only for what you cannot infer, one round of questions, all at once. In YOLO mode take the sensible reading and mark it.
3. **A thing you do not know goes in "Open questions", never into a section as a guess.** Day-1 then asks rather than assumes, which is the whole point of writing this before the Architecture exists.
4. Every "Must do" line is an outcome a user gets, numbered, one per line. A line needing a paragraph is two lines.
5. Write `docs/{App}-Brief.md`. Never a `-v2`; an amended brief is edited in place.
6. `bash .tfcore/utils/tf-doc-check.sh docs/{App}-Brief.md`; fix every FAIL.
7. Render it: `bash .tfcore/utils/tf-render-html.sh docs/{App}-Brief.md`. The owner reads the HTML.
8. Close: one `runs.jsonl` record carrying `"cmd":"create-project-brief"`, written as `.tfcore/tasks/_metrics-emit-gate.md` shows. No status gate — the project has no checklist yet.
9. Report in one line: the file, and how many open questions it carries. Then say the next command is `*day1-greenfield {App}` or `*day1-brownfield {App}`.

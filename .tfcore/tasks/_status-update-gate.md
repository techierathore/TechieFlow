# _status-update-gate (shared rule — every command ends here)

A command is finished when `PROJECT-STATUS.md` is rewritten in template shape, its HTML is rendered, the documents pass the checker, the BRD status table is current, and one run record is appended. The Stop hook checks all five and refuses to end the turn until they hold.

Steps, in this order:

1. `bash .tfcore/utils/tf-status-facts.sh {App} "{command}"` prints today's date, the phase line, the last verified build, the Open requirements section, the Verification log with its new row, the library feedback lines, and the next command in both harness forms. Copy them as printed.
2. Write `PROJECT-STATUS.md` with the Write tool in the shape of `.tfcore/templates/v4custom/app-project-status-tmpl.md`: replace every section in place, add none. You write two parts yourself: "Where I am" (at most 80 words, state not story) and "Known blockers". A refused write means the content is mis-shaped: trim it, do not reword it.
3. `bash .tfcore/utils/tf-doc-check.sh PROJECT-STATUS.md <every document this command wrote>`; day-1 and `*amend-docs` run `--app {App}` instead, because they own every document. A `FAIL` line means the phase is not closed: fix the document and re-run. A line printed as `OLD` was already there when the command started (the phase marker records them); it does not block and is repaired through `*amend-docs`. Never edit a schema to make a document pass. Documents this command did not write are reported with `--warn`, not fixed here: an older project is repaired through `*amend-docs` when it is next worked on (Schemas §7.1, decision 8).
4. `bash .tfcore/utils/tf-render-html.sh PROJECT-STATUS.md`, and the same for every human document this command wrote. The checklist is never rendered.
5. `bash .tfcore/utils/tf-brd-status.sh {App}` rewrites the BRD's Development status table from the checklist and re-renders the BRD.
6. Append the run record: `.tfcore/tasks/_metrics-emit-gate.md`.

Evidence for every line is the checklist's Requirements Status table and the files on disk, never git. Check a framework file by reading its literal path under `.tfcore/`; search tools skip that folder.

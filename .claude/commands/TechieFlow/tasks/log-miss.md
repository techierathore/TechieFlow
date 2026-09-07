# log-miss

`*log-miss {App} "sentence" [REQ] [--fixed]` is the twenty-second record: the owner says what an agent got wrong, in their own words, and it becomes one miss record, one line in `docs/{App}-Misses.md` and one checklist line. It never boots the application, never reproduces, never edits code, and never argues: if the owner says it was missed, it was missed. Fixing is `*fix-issues`. It honours YOLO.

First: `bash .tfcore/utils/tf-phase.sh start log-miss {App}` prints the start time; keep it.

## Steps

1. Sort it. Read the sentence, the checklist row and the documents, then answer the four questions in order and keep the first that fits; ask at most one question, and only when the answer turns on it. In YOLO take the sensible reading and say so in the report.
   - Did the app's spec say it clearly? No: `--sort spec`. The checklist line is fixed (in this run when it is only the line; through `*amend-docs` when the BRD changes too); the framework is untouched.
   - Did the framework say it anywhere? No: `--sort unsaid`. The outcome is one line in `TechieFlow-Requirements.md` plus a check, never prose in a task file; name the line in the report for the maintainer.
   - Was there a check, and did it not catch it? Yes: `--sort weak-check`. The check is fixed; a review becomes a script.
   - Was it written and ignored anyway? Yes: `--sort ignored`. The rule becomes a hook or script, or is deleted; it never gets more prose.
2. Classify from the same reading:
   - The owning row: the row whose scope holds the behaviour. None is a real answer: the defect was never specified.
   - `--class`: the spec said it and the build did not do it, `missed-requirement` or `partial-implementation`; the spec never said it, `unspecified-gap`; it used to work, `regression`; it works but not as specified, `wrong-behaviour`; `standards-violation`; `spec-contradiction`.
   - `--why`: which practice let it through: `missing-checklist-item`, `insufficient-verify-method`, `code-audit-limitation`, `ambiguous-acceptance`, `dependency-not-declared`, `instruction-ignored` (a written rule was not honoured; "you were told to" usually means this). Answer it on an owner or production report; leave it out rather than guess otherwise.
   - `--artifact` (`brd`, `architecture`, `uidesign`, `checklist`, `src`, `tests`, `config`, `devguide`) and `--severity` (`blocker`, `major`, `minor`, by what the owner sees, never by effort).
3. `bash .tfcore/utils/tf-log-miss.sh {App} --what "<the sentence>" --sort … --req <REQ> --class … --why … --artifact … --severity …` does the rest: the duplicate check (an open miss of the same class is reported, not re-logged, and its empty why or sort is completed), the origin lookup, the record with the sentence and the sort, the readable file, the checklist line (the row demoted to `Needs re-verify` with `⚠ miss <date>: <sentence>`), and the run record. When no row owns it: `--new "<title>" --acceptance "<When … on <screen>, then …>" --section "<screen>"` adds a Not Started row with `BRD-pending`; the report names `*amend-docs` when it is new scope rather than a defect. `--found-by production` for a live report. `--fixed [--fix-run <started>]` when the miss is already repaired: the record is closed at once and the row is left alone; without the run that fixed it, the cost is `none`, never a guess.
4. Run the status gate (`.tfcore/tasks/_status-update-gate.md`); the run record is the one step 3 wrote; the next command is `*fix-issues {App} <REQ>`.
5. Report: the block the script printed, the outcome the sort calls for (the checklist line fixed, the requirement line to add, the check to fix, the rule to make mechanical), and a plain sentence when the attribution came out inferred, so the owner knows this miss will not appear in the per-model figures.

# day1-greenfield

`*day1-greenfield {App}` starts a product that has no code. It runs in two stages with one owner review between them. Stage 1 produces the Architecture, the mockups and the BRD, then stops for review. `*day1-greenfield {App} --stage2` runs only after the owner has approved them and produces the checklist and the remaining documents. No mode skips the review: YOLO runs one stage to completion, never both.

First, before anything else: `bash .tfcore/utils/tf-phase.sh start day1-greenfield {App}` prints the start time and marks the command running.

## Stage 1 — Architecture, mockups, BRD

Ask once each, and nothing per section:

1. `{App}` if missing. PascalCase, no spaces.
2. The concept: "Describe the app, any length: a sentence, paragraphs, bullets, half-baked notes, comparisons to other apps. You will edit the document afterwards." Read all of it. Never cap or summarise the owner's input.
3. Hints, optional: paths to notes or mockups to harvest, and drafting instructions. `none` is fine.
4. The stack: "Which answer set: `dotnet` (`.tfcore/templates/stack-defaults/dotnet.md`), or answer the questions in `.tfcore/templates/stack-questions.md`?" Then ask only the questions the set leaves open (for dotnet: Q4, and the rendering mode of Q8).
5. The size: count the routed pages in the concept (every page with its own route, sign-in included; dialogs and tabs are regions of a page) and the roles, then ask: "Size: Small (up to 10 screens, one role, 50 requirements), Medium (up to 20 screens, 100 requirements) or Large (split into phases)? I count {N} screens and {N} roles, so I propose {X}." Kind is `app` unless the concept is a library.

Then, in this order:

6. `bash .tfcore/utils/tf-day1-files.sh {App} --size {S|M|L} --kind {app|library}` writes the size, the kind and the document paths into `core-config.yaml`; for Large it also writes `docs/{App}-Phases.md`, whose table you fill first: one row per phase, each within Medium, every screen in exactly one phase. On a re-run of stage 1, first `bash .tfcore/utils/tf-day1-files.sh --archive docs/{App}-BRD.md docs/{App}-Architecture.md docs/{App}-UIDesign.md` moves the old copies to `docs/OldDocs/`. Never write a `-v2` variant; never ask merge-or-new.
7. Architecture: `docs/{App}-Architecture.md` from `.tfcore/templates/v4custom/app-architecture-tmpl.md`, in the template's order. Stack decisions come from the answer set and the owner's answers, each row citing its source. Harvested notes carry into the sections attributed, never summarised away. Quote every mermaid label; never use `end` as a node id.
8. BRD, first half: `docs/{App}-BRD.md` from `app-brd-tmpl.md`: the header (App, Kind, Size, Stack answer set, Status, Date), Summary, Scope, Users and roles, and the Screens and flow table. A dialog is a row under its parent screen with `on /route` in the Route column.
9. Mockups: run `.tfcore/tasks/mockups.md` for `{App}`. It reads the Screens and flow table and produces `docs/{App}-UIDesign.md` and one `docs/mockups/<screen>.html` per screen. An app with no screens records "skipped — no UI".
10. BRD, second half: the Requirements ledger, one `BRD-N` per thing the verifier will test, each naming its screen, linking its mockup and carrying one acceptance line "When <actor> <does what> on <screen>, then <observable result>"; the Non-functional table (a `perf-budget:` only where the owner gave a number; the logging requirement from the answer set); the Development status table, one row per screen, all Planned. The concept is the primary source: every feature, actor and constraint in it becomes an item. Mark inferred items `<!-- inferred — please verify -->`. Harvested requirements carry in as items, attributed, none dropped. If the count would pass the size cap, propose a phase split instead of merging items.
   Large: steps 8 to 10 run once per phase of the Phases table, phase 1 in `docs/{App}-BRD.md` and `docs/{App}-UIDesign.md`, phase n in `docs/{App}-Pn-BRD.md` and `docs/{App}-Pn-UIDesign.md`, each header carrying `Phase | n of m` and its own Size, ids running on across phases. Every screen gets its mockup now.
11. `bash .tfcore/utils/tf-doc-check.sh --app {App}`; fix every FAIL.
12. Run the status gate (`.tfcore/tasks/_status-update-gate.md`); the run record carries `"cmd":"day1-greenfield","mode":"stage1"`.
13. Stop and say: "Stage 1 is complete: BRD, Architecture and mockups are written and rendered. Review them in the HTML files, or edit the markdown. When you approve, run `*day1-greenfield {App} --stage2`. To change a screen, edit the concept and re-run stage 1, or run `*mockups {App} --update`."

## Stage 2 — checklist and the remaining documents

Only with `--stage2`, and only when `docs/{App}-BRD.md` exists. Ask nothing.

0. If the owner gave corrections at the review, apply them to the stage-1 documents first (ids never renumbered; `bash .tfcore/utils/tf-doc-check.sh --app {App}` must pass), count them, and after this run's record append a `review` record: `{"kind":"review","phase":"day1-review","reviewed_run_id":"<stage 1 started>","correction_run_id":"<this run's started>","corrections":N,"what":"<one sentence>"}` through `tf-emit.sh misses`.
1. Checklist: run `.tfcore/tasks/split-brd.md` for `{App}` (Large: with `--all-phases`, one checklist per phase). The owner never types `*split-brd`.
2. Coding Standards: `docs/{App}-Coding-Standards.md` from `app-coding-standards-tmpl.md`. "Standards applied" names `.tfcore/standards/coding-standards-core.md` and the stack file, plus the choices the stack file leaves open (for dotnet, the instance-field prefix, default `obj`). "Project rules" stays empty unless the concept demands a rule true of this project alone.
3. `bash .tfcore/utils/tf-day1-files.sh {App} --prefix {obj|none}` writes `.editorconfig`, `AGENTS.md` and `CLAUDE.md` from their templates.
4. UsageGuide: `docs/{App}-UsageGuide.md` from `app-usageguide-tmpl.md`. The Test users table lists the intended accounts, one per role, none created. The Execution guide is at roadmap level, marking commands that depend on projects not yet built. One "How to test" section per screen in navigation order, naming the user, the steps, the expected result and the REQ ids.
5. `bash .tfcore/utils/tf-gitignore-audit.sh . --fix`. Read its output. Any untracking commands it prints go into your summary for the owner to run; agents never run git.
6. Run the status gate; the run record carries `"mode":"stage2"`. The next command is `*build-phase {App}`.

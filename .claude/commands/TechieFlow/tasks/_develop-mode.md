# _develop-mode (shared rule — *develop-end-to-end: a brief to a UAT-ready app, nobody asked)

Develop mode is on only in the run's own session (`tf-develop.sh . --mode` says `on`), never from a stopped run's `develop.json`. Everything in `_yolo-mode.md` applies, and on top of it:

## What changes

- **No question to the owner, ever.** Every question a task would ask is answered here, or by the brief (`docs/{App}-Brief.md`), or decided by you. A decision the owner would normally make is written down where the owner will see it: in the Architecture's Stack Decisions, or in the document it belongs to, under a line starting `Decided in develop mode:`, with one reason. Never stop to ask, never write `done blocked` for a question you could decide.
- **The mockups are yours.** In this command you drew them on Day 1, so a difference between a mockup and what the stack mandates (a library's own control, a required layout) is never an owner decision: redraw the mockup to match the mandated component, write `Decided in develop mode:` with the reason in the UIDesign, re-render it, and verify again. The same for any document you wrote in this run. Only a thing the owner alone can supply is a blocker.
- **No owner-review stop.** This is the one command that crosses the reviews: `*day1-greenfield` stage 1 ends without "review them, then run --stage2"; the supervisor starts stage 2 itself. Everything else about each stage is unchanged.
- **Git is the supervisor's, or the owner's** (`--no-git`). You never run a git write; the guard is unchanged.
- **Documents already written are kept.** A Day-1 goal that names missing documents: write those, change nothing else.

## Day 1 answers

| Question in `day1-greenfield.md` | Answer in develop mode |
|---|---|
| 1. The app name | `{App}` from `develop.json` |
| 2. The concept | `docs/{App}-Brief.md`, all of it; with no brief, the documents already written |
| 3. Hints | none, unless the brief names notes or mockups to harvest |
| 4. The stack | the stack the brief names; when it names none, the owner's answer set under `.tfcore/templates/stack-defaults/` (the one `core-config.yaml` names, or the only one there). Each question that answer set leaves open is decided as below, and every answer is written into the Architecture's Stack Decisions |
| 5. The size | the size you propose from your count; a Large app is built phase by phase |

Questions an answer set commonly leaves open:

- **Authentication.** The mechanism the brief names. When it names none: the app's own sign-in with local accounts, stored in the app's database; a shared identity platform needs credentials an unattended run does not have.
- **Rendering or hosting model of the UI.** The one the brief implies; otherwise the answer set's first choice.
- **Hosting and production secrets.** Not asked: they belong after UAT.

## The database

When the Architecture names a database server and none is reachable, create it locally and continue: a container named `{app}-db` (lower case) on a free port, with a development password kept in the app's development secrets, never in a committed file. Write the connection details into the UsageGuide's setup section. Create the schema only through the migration path the Stack Decisions name, during `*build-phase` (the database guard allows it there). This overrides the answer set's "never creates its own database container" for this command only.

## What does not change

The status gate, the smoke policy, the verifier's checks and the guard hooks. A row is `Verified` only from an executed verify. A thing only the owner can supply (a paid account, a device, a credential for a third-party service the brief requires) is still a blocker: finish everything else first, list it under PROJECT-STATUS "Known blockers", then `done blocked`.

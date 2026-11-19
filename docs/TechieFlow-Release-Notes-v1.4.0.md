# TechieFlow v1.4.0 — release notes

The text to paste into the GitHub release for tag `v1.4.0`. It follows v1.3.1. The full record is the
"v1.4.0 (since v1.3.1)" section of `docs/CHANGELOG.md`.

## What is new

- **`*develop-end-to-end` works on an app that already has its documents.** A Day-1 stage whose documents are all
  written is skipped; one with some missing writes only those. A large app is built phase by phase, in the order of
  its Phases table, each phase with its verify, its fixes and its handoff. `--no-git` leaves git to you: no commit,
  no push, every phase still in the Build Report. `--dry-run` shows the plan first and runs nothing.
- **Builds can stay out of your repository.** Set `buildCopy: <folder>` in `.tfcore/core-config.yaml` and the status
  gate's document tests build and run in that copy (or pass `--root <copy>` for one run). A Windows path such as
  `C:\Runs\copy` works from WSL. A copy that does not exist stops the step instead of building in the repository,
  and with no copy named the step says first that it builds in the repository.
- **A verify run from a separate copy writes everything in one place**: the checklist cells, the ledger and the
  telemetry go to the project your session names, so nothing has to be copied back.

## What is fixed

- **Token counts on Claude Code.** A reply with many tool calls was counted once per call. One run showed 772,000
  output tokens for a real 20,000. New records are right; older records run 2 to 5 times high and stay as written.
- **`*estimate-phase`** now prices a phase from what earlier phases really spent, every re-verify and fix included.
  Checking is no longer estimated about 40 times too low, nor fixing about 6 times too high.
- **The mockup check:** a tab drawn as a div in the mockup and as a button in the app is judged by one rule; two
  boxes that measure the same on both sides are never "a badge on one side"; and a switch's empty track is no longer a missing badge where the app draws a
  library switch.
- **A later phase's row on an earlier phase's screen** is now screen-checked on that screen. Rows of phase 2 onward
  that were graded by their tests alone may move on their next verify.
- **The screen check** no longer grades an invisible native select laid over a label; the label is graded.
- **Tests cannot write to your repository.** Seeds, browser tests, unit tests and a booted app run with a guard that
  refuses any git write to the project's own repository, and the artifact sweep removes a test repository whole or
  not at all.
- **Fixed since v1.3.1 as well:** a gradient is read as the colour a person sees; a progress bar's fill is no badge;
  the dropdown check closes whatever it opened; a first-run screen every address leads back to is compared at
  every width; and the Mac screen checker (TrStudio) scrolls a control into view, starts from the screen the app
  opens on, and reaches screens whose menu is built in code.
- **Smaller fixes:** the test-user script sends no application id beside an API key; the fix close no longer stops
  on a run record with no start time, and writes none itself; the status facts' phase line fits the status guard;
  the Mac check reads `<CodesignProvision>` as a provisioning profile; a compile error an analyzer reports on a source
  line fails the build at once instead of reading as a host problem; and a menu item that opens a second window is no
  longer reported as doing nothing.

## Before you update a project

The screen and mockup checks changed. Run `*verify` on a phase after the update and read the findings that appear
or go before you trust a status that moved.

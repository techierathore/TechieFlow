# amend-docs

`*amend-docs {App} {change}` folds a change into the existing documents in place: the BRD, the Architecture, the mockups and the checklist. Unchanged content stays exactly as it was; ids are never renumbered; nothing is archived. A change that invalidates most of the BRD is not an amendment: say so and point at `*day1-greenfield` or `*day1-brownfield`, which archive and rewrite. Never edit source code here.

First: `bash .tfcore/utils/tf-phase.sh start amend-docs {App}` prints the start time and marks the command running.

## Inputs

- `{App}`, or read it from `core-config.yaml`.
- `{change}`: what changed, any length, or the path of an amended concept document. If missing, ask once: "What changed? New, changed or removed features, or paste the amended concept."
- `{scope}`, optional: `brd`, `architecture` or `both` (default).

## Steps

1. Read the BRD and note the highest `BRD-N`. On a Large project the BRD and checklist are the phase's: `appPhase` in `core-config.yaml` names it, phase 1 is `docs/{App}-BRD.md`, phase n is `docs/{App}-Pn-BRD.md`; the highest id is the highest across every phase. No BRD means no amendment: stop and point at day-1. Note whether the checklist exists.
2. Sort every point of the change into ADD (a new capability, actor, screen or integration), MODIFY (an existing item whose behaviour changed, mapped to its `BRD-N`), REMOVE (scope dropped, mapped to its `BRD-N`) or ARCH (a new module, flow, package or decision).
3. Show the change-set as a numbered table (ADD with the next ids, MODIFY as old to new, REMOVE with the reason, ARCH by decision) and wait for "go" or corrections. **A table, not an essay: no glossary, no verification chapter, no re-argued history.** This is the only question. In YOLO mode apply it without waiting. If a point of the change turns on something only the owner can decide, do not argue it here — write `docs/{App}-Decision-Request.md` per `.tfcore/tasks/_owner-language.md`, render it, and say one line naming the file and how many decisions it holds.
4. BRD. ADD: append a ledger item with the next id, its screen, its mockup link and its acceptance line "When <actor> <does what> on <screen>, then <observable result>"; a new screen gets a row in the Screens and flow table and a Planned row in the Development status table. MODIFY: edit the item in place, same id. REMOVE: `~~BRD-N~~ (removed {date}: reason)`, never deleted. If the additions would take a Small project past 50 requirements, raise it to Medium: `bash .tfcore/utils/tf-day1-files.sh {App} --size M` and the Size in every document header. If they would take a Medium project, or one phase, past 100 requirements or 20 screens, stop and propose a phase split: a new row in `docs/{App}-Phases.md` (written with `--size L` when absent) and a new `docs/{App}-Pn-BRD.md`, instead of growing this one.
5. Architecture, when in scope and ARCH items exist: edit the affected sections in place, and add a Decisions log row (date, decision, why, status `planned` naming the BRD item) for every new decision or package. A reversed decision gets a new row; the old row stays.
6. Mockups: when a screen was added or changed, run `.tfcore/tasks/mockups.md` with `--update`, so every screen in the BRD has a current mockup before the checklist changes.
7. Checklist, only if it exists. ADD: `bash .tfcore/utils/tf-split-brd.sh {App} --add-missing` appends rows for the new items; correct their class. MODIFY: set the rows derived from that item to `Needs re-verify` with a Remark saying what changed. REMOVE: set them to `N/A (removed {date})` and keep the rows. Where the mapping from an item to its rows is unclear, ask, do not guess. If the checklist does not exist yet, the next day-1 stage 2 picks everything up.
8. If the amendment changed code-level flows, say that `*devguide {App} --update` is due after the next build.
9. Close what this amendment fixed: `bash .tfcore/utils/tf-emit.sh --open-misses {App} --artifact-class doc` lists the open misses whose deficient artifact is a document. Close the ones this amendment resolves in one call: `bash .tfcore/utils/tf-fix-close.sh {App} --misses <id>,<id> --fix-cmd amend-docs --verdict Verified`. Where the mapping from a miss to this amendment is unclear, ask, do not guess. Without this a document miss can never close: `*fix-issues` and `*build-phase` close off checklist rows the verifier touched, which a BRD edit never is.
10. Decide whether this amendment is a miss: should the original documents plainly have said this (a behaviour that was always required, or two sections that contradicted each other)? Then run `*log-miss {App} "<one sentence>"`. A change of mind or a feature decided today is scope arriving late, not a miss.
11. `bash .tfcore/utils/tf-doc-check.sh --app {App}`; fix every FAIL.
12. Run the status gate (`.tfcore/tasks/_status-update-gate.md`) with `"cmd":"amend-docs"`.
13. Report: items added (ids), modified, removed, the highest id now, what changed in the Architecture, the checklist rows touched, and the next command from the gate.

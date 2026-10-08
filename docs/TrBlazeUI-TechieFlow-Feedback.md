# TechieFlow feedback — found while building TrBlazeUI

| | |
|---|---|
| App | TrBlazeUI |
| Upstream | TechieFlow |
| Updated | 2026-10-07 |

## Summary

5 entries: 0 blockers, 2 majors (TF-001 closed, TF-005 open), 3 minors (TF-002 closed, TF-003 and TF-004 open), 0 nice-to-haves. 0 blocking now, 3 open (TF-003 the document checker asks a library's UI rows for a mockup link; TF-004 a triage-and-fix run cannot record itself; TF-005 a library's fix run ends before its shipped documents are updated), 0 fixed upstream and waiting, 2 closed.

Last consolidated: 2026-10-07. Entries are sorted by severity.

Nothing is blocked. TF-002 was re-checked on 2026-10-07 and is closed. TF-004 and TF-005 were found on the 2026-10-07 run for Chatur TR-015 to TR-017.

## Resolution status (TechieFlow team, 2026-10-08)

| ID | Fix | Check it here |
|---|---|---|
| TF-003 | Fixed upstream. `tf-doc-check` no longer asks a UI row for a mockup link when `core-config.yaml` says `metrics.project_type: library` (or `docs`). A link a row does carry must still point at a file that exists. `tf-triage.sh new` no longer prints "a UI row needs a mockup link" there either. Proved on this project: 28 "UI row without a mockup link" findings are gone, and no other finding appeared or went. The consumer mockups you copied in (`process-run.html`, `sevak-*.html`) are no longer needed; you may keep or remove them. Regression case `tb_003`. | After the framework update, `bash .tfcore/utils/tf-doc-check.sh docs/TrBlazeUI-Checklist.md` prints no "without a mockup link" line. |
| TF-004 | Fixed upstream, as you suggested. `tf-fix-close.sh` takes `--cmd` (default `fix-issues`), and `triage-and-fix.md` step 3 passes `--cmd triage-and-fix`. The run record it writes around the chained verify is filed under `triage-and-fix`, and step 5 no longer asks for a second record (that one was refused). The miss-fix records keep `fix_cmd: fix-issues`, the only value the schema allows for a fix. Regression case `tb_004`. | On your next `*triage-and-fix`, the close prints `triage-and-fix: run record written`, and `docs/metrics/runs.jsonl` gains a `cmd: triage-and-fix` record and no `fix-issues` one. |
| TF-005 | Fixed upstream. `fix-issues.md` has a step 5a, which `triage-and-fix.md` step 3 also runs. On a library it brings the documents the package ships up to date before the status gate: `handoff-phase.md` steps 1, 3, 3a and 4 (UsageGuide, HTMLs, DevGuide with `--update`, feedback replies), and `docs/TrBlazeUI-AI-Reference.md` for every component or option the run changed. No separate handoff record is written. The log row's Phase reads `triage-and-fix + handoff`. When that row is there and every row is terminal, the gate offers "commit, then build and publish the package" and never `*handoff-phase` after a release. `tf-devguide-list.sh` now reads `metrics.project_type` when `appKind` is not set: here it went from "NOTHING: no routed page found" to 368 components with their demo pages. Regression case `tb_005`. | `bash .tfcore/utils/tf-devguide-list.sh TrBlazeUI --update` prints `kind ui-library` and the component list. On your next `*triage-and-fix`, the documents are updated before the gate, and the next command it prints is the release. |

## Resolution status (TechieFlow team, 2026-09-22)

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream. `tf-triage.sh close` skips every action older than `--started`, says how many it skipped, and empties the list once the records are written. New `tf-emit.sh --void-miss <miss_id> "<reason>"` withdraws a wrong miss: the report leaves it out of every figure and prints it under *withdrawn*, and `docs/TrBlazeUI-Misses.md` lists it under *Withdrawn*. The six false misses (`MISS-TrBlazeUI-20260919-01` to `-05`, `MISS-TrBlazeUI-20260922-01`) are withdrawn. The 14 false escaped check records stay: nothing withdraws a check record yet. | On your next `*triage-and-fix`, the close line counts only that run's rows. `bash .tfcore/telemetry/tf-metrics.sh --report` shows "withdrawn : 6 miss(es)". |
| TF-002 | Fixed upstream (2026-10-02). `tf-phase.sh start verify-phase` or `start metrics-report` no longer writes a new document baseline when the marker shows it is running inside `build-phase`, `fix-issues` or `triage-and-fix`. It keeps the outer command's baseline and prints "runs inside triage-and-fix — keeping its document baseline". Findings the triage creates now stay `FAIL` until the run ends. Side effect: a standalone verify started right after a fix also keeps the fix's baseline, which can only make the gate stricter. | On your next `*triage-and-fix`, the verify's step 0 prints "verify-phase runs inside triage-and-fix — keeping its document baseline" and no second "baseline written" line. `tf-doc-check.sh docs/TrBlazeUI-Checklist.md` prints the new rows' findings as `FAIL`, not `OLD`. |

## Entries

### TF-001 — Closing a triage records last week's bugs again under today's run

> ✅ **Closed 2026-10-01** — re-checked here: On the 2026-10-01 triage-and-fix run, tf-triage.sh close printed '3 row(s) logged, 3 gate record(s) (escaped), 3 miss(es)' for the 3 rows that run logged (REQ-UI-021, REQ-UI-026, REQ-UI-027); nothing from an earlier run was replayed. tf-metrics.sh --report printed 'withdrawn : 6 miss(es)' naming the six false misses.

- **Severity:** major
- **Blocks:** no — 14 phantom escaped checks and 6 phantom misses in the metrics so far.
- **Repro:**
  ```
  bash .tfcore/utils/tf-phase.sh start triage-and-fix TrBlazeUI      # 2026-09-19T08:17:18Z
  bash .tfcore/utils/tf-triage.sh TrBlazeUI new "…" "…"               # one new row, REQ-UI-021
  bash .tfcore/utils/tf-triage.sh TrBlazeUI close --started 2026-09-19T08:17:18Z --cmd fix-issues
  → "triage: 14 row(s) logged — 14 gate record(s) (escaped), 6 miss(es)"
  ```
- **Expected:** `close` records only actions taken after `--started`: 1 check record, 1 miss.
- **Actual:** `tests/.artifacts/verify/triage.json` still held actions from the 2026-09-12 to 2026-09-14 runs, and `close` wrote them all again under today's run id: 13 check records (`gates.jsonl` 108–120) and 5 misses, `MISS-TrBlazeUI-20260919-01` to `-05`, for bugs already fixed.
- **Encountered in:** `*triage-and-fix TrBlazeUI docs/Chatur-TrBlazeUI-Feedback.md`, step 2.
- **Still happening 2026-09-22.** That run logged 8 rows; `close` reported 9. The ninth, REQ-UI-021, was created on 2026-09-19 and never touched: one `escaped` record plus `MISS-TrBlazeUI-20260922-01`, which has **no `miss-fix`** — nothing to fix — so it stays open for good.
- **Workaround:** none on the stream; nothing withdraws a record. Trimming the list by hand is why one leaked this time rather than thirteen. It shrinks the next run's blast radius, it fixes nothing.
- **Suggested fix:** in `close`, skip actions whose `ts` precedes `--started`, and empty the list afterwards. **And add a withdrawal record:** six open misses record work that was never open and will depress the resolved-miss rate on every future report. A `miss-void`, shaped like the existing `run-void`, would let a report exclude them.

### TF-005 — A library's fix run ends before the documents it ships are brought up to date

- **Severity:** major
- **Blocks:** no — the documents were updated afterwards, but only because the owner asked.
- **Repro:** `*triage-and-fix TrBlazeUI` on a project with `metrics.project_type: library`. When every row is `Verified`, the status gate prints `*handoff-phase TrBlazeUI` as the next command, after the run has ended.
- **Expected:** for a library, a fix is not finished until the documents that ship inside the package describe it: the AI agent reference (`docs/TrBlazeUI-AI-Reference.md`, packed into `TrBlazeUI.Components`), the usage guide and the developer guide. The handoff runs inside the fix run, before the owner commits and cuts the release, so that one package carries the code and its documents.
- **Actual:** `triage-and-fix.md` and `fix-issues.md` stop at the status gate, and the gate offers `*handoff-phase` as a separate next step. On a library that order means one of two things: the owner releases a package whose guides do not yet describe the new features, or the owner rebuilds and republishes it after the handoff. The owner has had to rebuild a package for this reason.
- **Encountered in:** `*triage-and-fix TrBlazeUI` for Chatur TR-015 to TR-017, 2026-10-07. The agent also wrote "run `*handoff-phase` after the release" in its closing message, which is the wrong order for a library.
- **Workaround:** run `*handoff-phase` straight after the fix, before committing, and only then cut the release.
- **Also:** `tf-devguide-list.sh TrBlazeUI --update` prints "NOTHING: no routed page found … outside samples and tests" for this library, because it reports the kind as `app` and skips the demo pages, so the DevGuide step of a handoff cannot list anything. `devguide.md` says a UI library's unit is the component; the list script does not read `project_type: library`. The DevGuide was updated by hand on 2026-10-07.
- **Suggested fix:** when `project_type` is `library`, have `triage-and-fix.md` and `fix-issues.md` run the handoff steps (UsageGuide, DevGuide `--update`, the shipped agent reference, the feedback replies) before the status gate, and have the gate never print `*handoff-phase` as a step after a library's release.

### TF-002 — A command that chains another one has its own document findings relabelled as old

> ✅ **Closed 2026-10-07** — re-checked here: On the 2026-10-07 triage-and-fix run, verify-phase was started inside it and the status gate's tf-doc-check.sh then printed the three rows that run added (REQ-UI-030..032) as 8 FAIL lines, not OLD, so they blocked until fixed.

- **Severity:** minor
- **Blocks:** no — the findings are still printed; only their label is wrong, and the run carried on.
- **Repro:**
  ```
  bash .tfcore/utils/tf-phase.sh start triage-and-fix TrBlazeUI   # "baseline written … (106 old finding(s))"
  bash .tfcore/utils/tf-triage.sh TrBlazeUI new "…" "…"            # twice: two new rows
  bash .tfcore/utils/tf-phase.sh start verify-phase TrBlazeUI     # "baseline written … (114 old finding(s))"
  bash .tfcore/utils/tf-doc-check.sh docs/TrBlazeUI-Checklist.md  # the two new rows' findings print as OLD
  ```
- **Expected:** findings this run created stay `FAIL` until the run ends, whatever commands it runs inside itself.
- **Actual:** `*triage-and-fix` tells its fix step to start `verify-phase` with its own step 0, and its metrics step to start `metrics-report`. Each start writes a new baseline, so the findings the triage had just created (the old count rose from 106 to 114; on REQ-UI-026 and REQ-UI-027 they were an acceptance line too long, no BRD item named and no mockup link) became "from before this command" and stopped blocking.
- **Encountered in:** `*triage-and-fix TrBlazeUI`, 2026-10-01, at the status gate.
- **Workaround:** read the `OLD` lines for the rows this run added and fix them by hand, which is what was done here.
- **Suggested fix:** when a phase marker already exists for a running command, a chained start keeps the outer command's baseline instead of writing a new one.

### TF-003 — The document checker asks a library's UI rows for a mockup link

- **Severity:** minor
- **Blocks:** no — the row is built and verified; the gate passed once the workaround below was in place.
- **Repro:**
  ```
  bash .tfcore/utils/tf-triage.sh TrBlazeUI new "…" "When a consumer … on the Switch demo screen, then …" --prefix UI
  bash .tfcore/utils/tf-doc-check.sh docs/TrBlazeUI-Checklist.md
  → FAIL docs/TrBlazeUI-Checklist.md: REQ-UI-029 is a UI row without a mockup link
  ```
- **Expected:** a project whose `core-config.yaml` says `metrics.project_type: library` has no screens and no `docs/mockups/`, so a UI row is not asked for a mockup link (or the rule is a warning there). `tf-triage.sh new` already prints "a UI row needs a mockup link" for the same row.
- **Actual:** `tf-doc-check.py` fails every `REQ-UI` detail entry without a link into `docs/mockups/`. Here that is every UI row: 27 sit in the `OLD` list for this alone, and each new one fails the gate. The checklist says why: "UI REQs map to component families, not mockups."
- **Encountered in:** `*triage-and-fix TrBlazeUI` for Chatur TR-014, 2026-10-03, status gate step 3.
- **Workaround:** the consumer's mockup is copied unchanged into `docs/mockups/` and linked (a link outside the repo does not work: the checker keeps only the `mockups/…` tail). A row with no consumer mockup has no honest workaround.
- **Suggested fix:** skip the mockup-link check (and the matching `tf-triage.sh new` note) when `project_type` is `library` or `docs`, as the verifier already skips mockup parity without mockups.
- **Still happening 2026-10-07:** REQ-UI-030 to -032 (Chatur's `process-run.html` copied in), then REQ-UI-034 to -043 (eight Sevak mockups copied in as `sevak-*.html`). That run also hit the 50-row Small cap; `appSize: Medium` was set.

### TF-004 — A triage-and-fix run cannot write its own run record

- **Severity:** minor
- **Blocks:** no — the time was recorded, under the wrong command name, and was put right by hand.
- **Repro:**
  ```
  bash .tfcore/utils/tf-phase.sh start triage-and-fix TrBlazeUI          # 2026-10-07T05:59:51Z
  … triage, fix, chained verify-phase …
  bash .tfcore/utils/tf-fix-close.sh TrBlazeUI --started 2026-10-07T05:59:51Z --build pass
  → "fix-issues: recorded around 1 chained run(s) (verify-phase) in 2 segment(s)"
  cat <<'JSON' | bash .tfcore/utils/tf-emit.sh runs                       # triage-and-fix.md step 5
  {"kind":"run","cmd":"triage-and-fix","started":"2026-10-07T05:59:51Z", …}
  JSON
  → "tf-emit: REFUSED — this run … overlaps the verify-phase run …"
  ```
- **Expected:** the run is on the stream as `cmd: triage-and-fix`, so `tf-metrics.sh --phases` counts its time and tokens under that command.
- **Actual:** `triage-and-fix.md` step 3 runs `tf-fix-close.sh`, which always writes the segments around the chained verify as `cmd: fix-issues`. Step 5 then asks for a `triage-and-fix` record over the same window, and the overlap rule (SCHEMA §2.7b) correctly refuses it. Every `*triage-and-fix` run is therefore counted as `*fix-issues`, and the record the task asks for can never be written.
- **Encountered in:** `*triage-and-fix TrBlazeUI` for Chatur TR-015 to TR-017, 2026-10-07, status gate.
- **Workaround:** both `fix-issues` segments (started 05:59:51Z and 06:32:45Z) were voided with `tf-emit.sh --void-run`, giving the reason, and re-emitted with the same windows as `cmd: triage-and-fix`. The miss-fix records still find their window, because it is keyed on `started`.
- **Suggested fix:** give `tf-fix-close.sh` a `--cmd` (default `fix-issues`), as `tf-triage.sh close` already has, and have `triage-and-fix.md` step 3 pass `--cmd triage-and-fix`. Then drop the separate record from step 5, or let step 5 say the run record is the one step 3 wrote, as `fix-issues.md` step 6 does.

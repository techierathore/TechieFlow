# TechieFlow code review for bloat — 10 Nov 2026

Asked by the owner on 10 Nov 2026. Nothing was changed, nothing was committed, no script or test suite was run. This file is the only thing written.

**The answer you may not want: yes, it is bloated again — but mostly not in the way the question assumes.** One-app special cases are only 18% of the code in the six check scripts. The bigger part is general rules that one project's entry added for every project (40%), the story of each defect written into comments (a quarter of every file), and the same logic typed again in a second or third file. A clean-up gets back about 1,600 lines of 24,300 (7%), or about 2,900 with the installer. It does not undo the growth. What undoes it is a rule about how fixes land (section 5 and section 7).

## How to read this

- **What was reviewed:** the files as they are on disk at commit `d12f51c` ("IN Progress before ReStructure"), which landed while the review ran. That is v1.3.0 plus the fixes of 10 Nov. Line numbers are from that state.
- **Confidence tags:** [Certain] = counted by a program or read in the code. [Likely] = a strong inference, or a judgement another reviewer could draw a little differently. [Guessing] = filling a gap.
- **Entry names:** TF numbers clash between projects, so every entry is written with its project (Sevak TF-021). A bare number in a code comment was resolved from `docs/CHANGELOG.md`.
- **Line counts:** "code lines" means lines that are not blank and not only a comment.
- **Not done:** no check was run, so "this would fail" is read from the code, not observed. [Likely]

## The size today

| What | v1.0.4 (10 Sep) | Now | Note |
|---|---|---|---|
| `.tfcore/utils` script files (no `.pyc`) | 56 | 88 | 49 bash, 27 python, 11 node, 1 PowerShell |
| `.tfcore/utils` + `.tfcore/hooks` lines | — | 24,310 in 101 files | median file is 142 lines |
| Lines in the 10 largest files | — | 9,686 (40%) | |
| Comment-only lines | — | 4,051 (16% of lines, 24% of bytes) | python docstrings not counted |
| `tests/regression/run.sh` | — | 8,299 lines, 202 cases | half of it is python or node inside bash |

A line in these scripts is long. `tf-verify-boot.sh` averages 67 characters a line and has 96 lines over 120 characters, so line counts understate the size. [Certain]

---

## 1. General rule or one-app special case?

The five verify scripts taken are `tf-verify-boot.sh`, `tf-verify-tests.sh`, `tf-verify-verdict.py`, `tf-verify-screens.mjs` and `tf-verify-list.py`, plus `tf-mockup-parity.mjs`.

Every line was put in one of four groups:

- **General rule:** the job the script had at v1.0.4, or would need with no feedback entry.
- **General hardening:** added for one entry, but every project runs it.
- **Special case:** only one app, one platform shape (Mac head, desktop window, WSL side), one stack, one naming habit or one tuned number reaches it.
- **Comments and blanks.**

| File | Lines at v1.0.4 | Lines now | General rule | General hardening | Special case | Comments, blanks |
|---|---|---|---|---|---|---|
| `tf-verify-boot.sh` | 250 | 895 | 226 | 263 | 224 | 182 |
| `tf-verify-tests.sh` | 166 | 607 | 146 | 269 | 69 | 123 |
| `tf-verify-verdict.py` | 292 | 592 | 225 | 139 | 62 | 166 |
| `tf-verify-screens.mjs` | 355 | 717 | 266 | 242 | 42 | 167 |
| `tf-verify-list.py` | 270 | 537 | 223 | 62 | 124 | 128 |
| `tf-mockup-parity.mjs` | 555 | 1,321 | 379 | 403 | 123 | 416 |
| **All six** | **1,888** | **4,669** | **1,465** | **1,378** | **644** | **1,182** |
| Share of the 3,487 code lines | | | 42% | 40% | 18% | — |

The counts are measured; which group a line range belongs in is a judgement. [Likely]

What this says, in plain words:

- **The growth is mostly general rules, not app branches.** There is no "if this is app X" anywhere. A project files an entry, and the fix becomes a rule every project runs.
- **A quarter of every file is comments, and most of that is history.** Between 450 and 550 comment lines in these six files tell the story of a defect (which project, which screen, what date) and do not explain the code. `tf-mockup-parity.mjs` alone has 220 to 250 of them. [Likely] The same story is already in `docs/CHANGELOG.md`.
- **The "general rule" in `tf-verify-boot.sh` is itself one stack.** Outside the static head, every general line assumes `.csproj`, `dotnet` and MAUI. That dates from v1.0.4, not from feedback. [Certain]
- **In `tf-mockup-parity.mjs` the `diff` function is 83% patches:** 38 of its 166 code lines are the original rule. `PROBE` grew from 222 to 445 lines. In `tf-verify-verdict.py`, `main` grew from 210 to 429 lines and is 72% of the file. [Certain]

### The special cases, and the entry behind each

"Could become": **rule** = one general rule replaces it; **setting** = a per-project line in `tests/verify/testsettings.json`; **stay** = it is needed as it is.

**`tf-verify-boot.sh` — 224 lines**

| Lines | What | Code lines | Entry | Could become |
|---|---|---|---|---|
| 499-658, plus pieces at 159, 237-254, 291-294, 433-434, 466-488 | The whole Mac Catalyst branch | 167 | The Mac head (owner decision, 7 Oct); narrow parts Lekhak TF-026 and Lekhak TF-032 | Stay, but in its own file. Only Lekhak is named in it. [Likely] |
| 528-548 | Mac machine set-up checks (Automation Mode, mac2 driver version) | 17 | Lekhak TF-026 | Rule: a one-time machine check in `tf-verify-env.sh`, not on every boot. Two version numbers are typed in and will go stale. |
| 613-620 | Two crash hints that look for one literal word each | 6 | Lekhak BlogAdmin, 7 Oct (no TF number) | Rule: `tf-maccatalyst-check.sh` already checks one of them before the build. |
| 174-185, 699-712, 733-735 | Which side of a WSL machine runs the web copy; the WSL gateway address | 20 | AppManager TF-030, TechieBlog TF-002, Chatur TF-018, Lekhak TF-036 | Already a setting (`Verify:Runner`). The guess on line 709 can go. |
| 743-759 | Point the app at the Windows user-secrets store | 12 | Lekhak TF-001 | Stay, or always a setting (`Verify:WindowsAppData`). [Likely] |
| 435-461 | `serves_screens()`, `pick_web()`: guess which of several web projects has pages (Razor only) | 22 | AppManager TF-010 | Setting: `Verify:Project`. 22 lines of guessing save one line of settings in one app. |
| 307-316 | Read the process list where there is no `/proc` | 9 | none (Mac portability, 27 Sep) | Rule: use `ps` everywhere and drop the `/proc` reader. |

**`tf-verify-tests.sh` — 69 lines**

| Lines | What | Code lines | Entry | Could become |
|---|---|---|---|---|
| 338-376, 481-503, 517-519 | Detect Microsoft.Testing.Platform projects, ask for a TRX report, read it | 53 | AppManager TF-005 | Setting for the report switch, or move into `tf-build.sh test`, which already owns how tests run. |
| 180-192, 206-208 | `CDP_URL` for a desktop head, and a text search of the tests for the literal `env.CDP_URL` | 12 | Lekhak TF-021 | Rule: one address name for every head (`BASE_URL` already carries it). |
| 193-198 | `APPIUM_URL`, `TF_BUNDLE_ID`, `TF_APP_PATH` | 4 | The Mac head (no entry cited) | Rule: hand the tests the path of `boot.json` once. |

**`tf-verify-verdict.py` — 62 lines**

| Lines | What | Code lines | Entry | Could become |
|---|---|---|---|---|
| 133-148, 185-186, 283-290, 575-578 | Test-users check; only fails apps that sign in through the shared AppManager | 28 | FW-001 (owner, 1 Nov) | Stay. Today it is switched on by reading the Architecture document; an explicit setting would be clearer. |
| 151-157, 225-229, 307-308, 327-330, 402, 417 | Wording and branches for a Mac web view driven by Appium | 16 | Chatur TF-016, Sevak TF-014 | Rule: copy the driver's own "not measured" reason for any head; the verdict need not know the words Mac or Appium. |
| 264-275 | OS zoom check | 12 | Lekhak TF-030 [Likely] | Rule: "a row may name an outside check whose result stands as its test", the way perf-budget already works. |
| 324, 355-356, 423-425 | Mockup comparison not measured (desktop window not drawing) | 6 | Sevak TF-011 | Rule: the same single "not measured" rule. |

**`tf-verify-screens.mjs` — 42 lines**

| Lines | What | Code lines | Entry | Could become |
|---|---|---|---|---|
| 558-569 | Desktop window draws no frames | 12 | Sevak TF-011 | Stay. |
| 212-219, 485, 491, 545 | `data-tf-overlay` mark | 11 | Sevak TF-019 (10 Nov) | Rule [Likely]: if the mockup draws the same two controls overlapping, it is by design. **No mockup in the 8 projects searched carries this mark.** [Certain] |
| 315, 575-584 | Sign-in held in the page (401/403, then re-open) | 11 | AppManager TF-006 | Rule: it is a copy of `reach()` in `tf-login.mjs` 169-179; call that. |
| 44, 190, 198-202 | `data-tf-phase` mark | 7 | Sevak TF-018 (10 Nov) | **No mockup carries it either.** Sevak's own file says the entry stopped blocking once its mockups were marked `data-tf-state="phase-5"`. This code may never run. [Likely] |
| 71 | `#blazor-error-ui` as the default error banner | 1 | none (v1.0.4) | Setting. |

**`tf-verify-list.py` — 124 lines**

| Lines | What | Code lines | Entry | Could become |
|---|---|---|---|---|
| 21, 226-317, 482, 496-497 | Click path read from Razor code under `src/` or `source/` | 80 | Lekhak TF-027 | Setting for the folders, and share `routes_in_code()` in `tf-devguide-list.py`, which already knows several stacks. Only the Mac driver uses the result. Sevak keeps its code under `apps/`, so it finds nothing there. [Certain] |
| 134, 139-154, 432-434, 470-472 | One screen per mockup file (`/settings/{tab}`), guessed from file names | 19 | Chatur TF-003 | Setting: list the tab values in `route_values`; the general fill-the-address rule (Lekhak TF-005) does the rest. |
| 336-343 | Test users table read by header words | 8 | AppManager TF-009 | Rule: the template's table shape, enforced by the document check. |
| 108-110, 448, 510-512 | OS zoom check | 7 | Lekhak TF-030 [Likely] | Rule: as in the verdict. |
| 201-209 | Two spellings of the usage guide file name | 6 | AppManager TF-009 | Rule: pick one spelling. |
| 90-93 | Anchor written above its page heading | 4 | none ("AppManager's older entries") | Rule: fix the one checklist, drop the lines. |

**`tf-mockup-parity.mjs` — 123 lines**

| Lines | What | Code lines | Entry | Could become |
|---|---|---|---|---|
| 778-822 | `rowsGone`, `takeRows`, `sampleGone`: guess which app elements are "the real rows standing where sample rows were" | 39 | Chatur TF-007 (fixing what the Chatur TF-006 fix broke on five Chatur screens) | Rule (see below). The largest single guess in the file. |
| 61, 962-992, 1047, 1169, 1251, 1288, 1304 | Attach to a desktop app's built-in browser | 29 | Lekhak TF-006, Lekhak TF-037, Lekhak TF-038, Sevak TF-011 | Stay as a mode; the attach code is a copy of `tf-verify-screens.mjs` 235-243. |
| 386-396, 510-516, 669, 683-686 | `nearOf`: accept a pill or border on the box around the element, within 8 px | 21 | TfLens TF-047 | Rule. Fitted to two TfLens shapes. |
| 528-530, 731-768 | `nested`, `strip`, `dropRows`: treat `commit-row-7` as more of `commit-row-1` by swapping the digits | 18 | Chatur TF-006 | Rule. Rests on one naming habit. |
| 839-850, 931 | `iconMoved`: drop an icon finding when up to 4 icons match two levels up | 13 | TfLens TF-047 | Rule. "2 levels" and "4 icons" are fitted numbers. |
| 635-636 | Two shapes that are not the main scroll area | 2 | AppManager TF-028 | Rule. |
| 278 | Grey means under 25% saturation | 1 | Sevak TF-007 | Stay; put the number with the other colour numbers. |

### What could become one general rule

1. **One pairing rule in the mockup check — about 180 code lines, seven entries.** Elements are matched by their position in the page, and the icon rule asks "any icon anywhere inside this box?". TfLens TF-027, TF-045, TF-046, TF-047 and Chatur TF-002, TF-006, TF-007 each patched one more symptom of that choice. Matching an element by what it is (its text, its role, its named box) and giving each icon to exactly one box would retire most of the family. [Likely — unproven; it would need measuring on every project.]
2. **One "leave this box out" table.** Seven separate lists (hidden, other state, sample, toggle, chart, named child, later phase) are tested at ten places in `tf-mockup-parity.mjs`.
3. **One "not measured" rule in the verdict.** The driver writes the reason; the verdict copies it for any head. This removes every Mac and Appium word from `tf-verify-verdict.py`.
4. **One "outside check stands as the row's test" rule** for perf-budget and zoom.
5. **About 48 tuning numbers in `tf-mockup-parity.mjs`, 6 of them changeable by a flag.** One named table at the top of the file would at least show them. [Likely complete]

### What could become a per-project setting

`Verify:Project` (replaces `pick_web`), the unit-test report switch, the code folders for the click path, the tab values of a split screen, the icon class names (`bi-`, `fa-` on line 335 of the mockup check), the error banner selector, and whether the test-users check is on.

---

## 2. What is duplicated

**13 of the 20 true duplicates have already drifted apart, and several of the drifts look like live faults. The line saving is the smaller story.** Outside the installer, merging everything saves about 800 lines (3%). [Likely]

| # | The logic | Copies | Lines saved | Drifted? |
|---|---|---|---|---|
| 1 | The installer | `update-framework.sh` (1,049 lines), `scripts/install.mjs` (1,066), `scaffold-brownfield.sh` (544), `scaffold-greenfield.sh` (521). The 155-line `.claude/settings.json` text is pasted in all four. | 465 for the settings text alone; 895 to 1,327 code lines if `install.mjs` becomes a launcher and the two scaffold files merge | Agree today, because `scripts/test-install.mjs` compares the routes. It broke on 5 Nov. |
| 2 | Thin `.sh` files that only start a `.py` | 19 files of 3 to 29 lines | about 320 (85 code) | Mild: four different exit codes when python3 is missing |
| 3 | Reading and rewriting checklist rows | `tf-checklist-edit.py` 33-73, `tf-brd-status.py` 60-66, `tf-build-list.py` 95-133, `tf-verify-list.py` 60-114, `tf-status-facts.py` 67-83, `tf-verify-verdict.py` 545-563, `tf-doc-check.py` 1097-1104, `guard-verify.sh` 33-44 | about 128 | Yes, three ways (below) |
| 4 | Small python helpers: `read()`, `die()`, the loader for a sibling file, the jsonl loop | `read` and `die` in 10 files each; the loader in 10 places; the jsonl loop in 12 | about 130 [Likely] | Yes: four different file encodings in `read()` |
| 5 | Reading `routing.yaml` | `tf-harness.sh` 73-118, `tf-model-pick.sh` 93-120, `tf-emit.sh` 868-893, `tf-routing-bind.sh` 102-125 | 96 | Yes: each knows different sections |
| 6 | Reading `core-config.yaml` (phase, kind, project type) | 12 readers; the "phase number to checklist file name" rule is typed 13 times | 87 | Yes: `appPhase: "2"` in quotes reads as 2 in four scripts and as 1 in seven |
| 7 | Browser set-up in the node checks | `tf-verify-screens.mjs`, `tf-mockup-parity.mjs`, `tf-assets-browser.mjs`, `tf-verify-native.mjs` against `tf-login.mjs` | about 74 | Yes (below) |
| 8 | The menu walk block | `tf-verify-screens.mjs` 644-695 and `tf-mockup-parity.mjs` 1223-1285: the same job with the same helper calls, written twice | about 55 | Small differences |
| 9 | Which harness is running | `tf-harness.sh` 44-72, `tf-emit.sh` 697-738, `guard-status-html.sh` 71-80, `tf-yolo.sh` 96 | about 50 | Mild |
| 10 | Where the project root is | 5 multi-line copies and 11 one-liners, with different orders of the environment variables | about 40 | Yes (below) |
| 11 | Setting a theme on a page | `tf-mockup-parity.mjs` 151-189 and `tf-theme.mjs` 27-73; colour reading at parity 238-267 and `tf-theme.mjs` 104-147 | about 40 | Two ways live side by side |
| 12 | The helper around `tf-emit.sh` | `tf-log-miss.py` 52-68, `tf-triage.py` 141-152, `tf-fix-close.sh` 70-75, `tf-verify-emit.sh` 64-94 | 28 | Agree |
| 13 | Reading the "which command is running" marker | 6 readers | about 25 | Yes (below) |
| 14 | "A run record was written after the status file" | `tf-yolo.sh` 136-180 and `guard-status-html.sh` 160-180 | 21 | Yes: 60 seconds against 300, named command against any |
| 15 | Is YOLO on | `tf-yolo.sh` 71-76, `block-git.sh` 40-53, the OpenCode plugin 86-97, `tf-emit.sh` 774-780 | about 20 | Yes (below) |
| 16 | Inside one file | `tf-verify-boot.sh`: the PowerShell "stop what listens on this port" line four times (284, 778, 817, 885), the "first compiler error" three times (724, 820, 871), three scans of `boot-*.json` with three "still running" rules. `tf-verify-tests.sh`: the Sevak TF-004 rule twice (143-147, 529-534), the id-reader loader three times, the Playwright result walker three times | about 75 [Likely] | The walker copies disagree on `.tsx`/`.jsx` (line 263 against 475) |

**The same check written twice** was found in one place only: the status file's fixed section list and 120-line cap are typed by hand in `guard-status.sh` 84-133 and also read from the template by `tf-doc-check.py`. Add a section to the template and the hook refuses it. No rule is checked in both `tf-doc-check.py` and `tf-verify-verdict.py`. [Likely]

**Drifts that look like faults** (read in the code, not run):

- **Project root.** `tf-harness.sh` tries `TF_PROJECT_DIR` first, `tf-yolo.sh` tries `CLAUDE_PROJECT_DIR` first, and `tf-emit.sh` never reads `TF_PROJECT_DIR`. This is the way the 18 fixture records leaked into TechieFlow's own streams on 18 Oct. [Likely]
- **Marker age.** `tf-phase.sh` 18-19 says a marker older than 24 hours is ignored. `tf-emit.sh` 785, `tf-test-users-check.py` 504 and `tf-register-test-users.mjs` 28 do not check its age. [Certain]
- **Backticked row ids.** `tf-doc-check.py` 1097 does not see a row written as `` | `REQ-UI-004` | ``. Every other reader does. [Certain]
- **Owner-UAT rows.** `tf-build-list.py` has no Owner-UAT status, so such a row lands on the builder's work list; `tf-status-facts.py` 36 treats it as the owner's. [Likely]
- **Blocked rows after a fix.** `tf-fix-close.sh` 126 records a held Blocked row as "Needs re-verify" while `tf-verify-verdict.py` 457 keeps it Blocked. [Likely]
- **Status file reads blocked.** `guard-status.sh` 48 refuses any python or node command that names `PROJECT-STATUS.md`, a read included. The same fault was fixed in `guard-metrics.sh` on 9 Sep. [Certain]
- **Asset check signs in differently.** `tf-assets-browser.mjs` 27 does not read the sign-in from the test settings; the screen and mockup checks do. [Likely]
- **YOLO expiry.** `tf-emit.sh` 778 types in 24 hours and ignores `TF_YOLO_TTL_HOURS`. [Certain]
- **Window height.** The screen check switches to phone height below 600 px wide (`tf-verify-screens.mjs` 160, 279, 282), the mockup check below 700 (`tf-mockup-parity.mjs` 1012, 1047, 1251). [Certain]
- **Sentences read back by pattern.** "on-app test skipped (…)" is written at `tf-verify-tests.sh` 534 and taken apart at `tf-verify-verdict.py` 243; "answered HTTP 404" is written at `tf-verify-screens.mjs` 589 and searched for at verdict 384. A wording change in one file silently breaks the other. [Certain]

**Leave alone:** `tf-testsettings.py` and `.mjs` (two languages, they agree); `tf-selfcheck.sh` and `tests/mirror` (different jobs); the opening lines of the hooks (each hook must stand alone). Telemetry writing (`tf-emit.sh`) and feedback-file reading (`tf_feedback.py`) are already in one place each.

---

## 3. What is dead

**Very little is dead. The bloat is live code.** A program followed every name from the task files, agent files, hook settings, the OpenCode plugin, the installer, CI and the tests.

**Scripts** — 96 of 101 are reached from a task, an agent file or a hook. The other five:

| Script | Lines | Who names it |
|---|---|---|
| `tf-routing.sh` | 253 | Nothing in the framework and **no test**. Only `README.md` and the routing guide, as a command typed by hand. Not dead, but unproven. |
| `tf-yolo-alias.sh`, `tf-yolo-start.sh` | 84 + 44 | Each other and the regression suite; typed by hand (`tfyolo`). |
| `tf-opencode-audit.py` | 142 | The installer only. |
| `tf-gitignore-blocks.sh` | 43 | The installer only. |

**Functions** — no function in `utils` or `hooks` is named only at its own definition. [Likely — a name scan; a function called only from dead branches would not show.]

**Unused inside files** [Certain]:

- `anchorsPresent` and `waitArrived` are imported and never used in `tf-mockup-parity.mjs` 46 and `tf-verify-screens.mjs` 274.
- `tf-verify-verdict.py` 173 sets `tests_ran` and never reads it.
- `tf-status-facts.py` imports `glob` and never uses it.

**Flags no task, test or other script passes** (14) [Likely — a model could still pass one after reading the script's own help]:

- `tf-verify-boot.sh`: `--config`, `--probe-path`, and on `adopt`: `--log`, `--url`
- `tf-goal.sh`: `--default-wait-min`, `--probe-max-hours`, `--stall-min`
- `tf-mockup-parity.mjs`: `--max-findings`, `--thin-ratio`
- `tf-assets.sh`: `--include-external`, `--min-bytes`
- `tf-perf.sh --warmup`, `tf-status-evidence.sh --no-build`, `tf-verify-emit.sh --mode`

**Flags only the tests pass** (15): `tf-verify-boot.sh --environment`, `--pid`, `--static`; `tf-verify-tests.sh --no-browser`, `--no-unit`, `--shard`; `tf-verify-native.mjs --app-path`, `--boot`, `--from-source`, `--no-names`; `tf-goal.sh --fresh`, `--idle-retry-sec`; `tf-doc-check.py --strict`; `tf-fix-close.sh --reqs`; `tf-register-test-users.mjs --appsettings`.

**Likely dead weight** [Likely]:

- `tf-verify-tests.sh` 98-114: readers for three older shapes of a part file. Part files live for one verify run.
- `tf-verify-boot.sh` 270-282: a stop path for boot records written before `win_pids` existed.
- `tf-verify-boot.sh` 787-827: the old `dotnet run` path, reached only by a standalone Blazor WebAssembly project. [Guessing that no project is one]
- The two marks added on 10 Nov that no mockup uses (section 1).

**Small faults found on the way** [Certain]:

- Both help texts are cut off: `tf-verify-boot.sh` 369 prints header lines 2-49 of 56; `tf-verify-tests.sh` 52 prints 2-30 of 34.
- `tf-verify-tests.sh` 199, 203, 206 use `tests/verify/**/*.spec.*` without bash's globstar switch, so specs two folders down are missed by three checks.
- `tf-verify-boot.sh` 807: the WebAssembly path waits a fixed 120 s and ignores `Verify:BootWaitSeconds`.
- `tf-verify-verdict.py` 361: lines for Chatur TF-002 were put in the middle of an if/elif chain; the `NO-MOCKUP` branch now hangs off the wrong `if` and is right only by accident.

**Compiled files in git:** commit `d12f51c` removed the seven under `.tfcore/utils/__pycache__`. Two are still tracked: `tests/doc-check/__pycache__/make-fixtures.cpython-312.pyc` and `tests/verify/__pycache__/make-fixtures.cpython-312.pyc`. `.gitignore` already lists `*.pyc`; they were added before that line. [Certain]

---

## 4. Python or node inside bash strings

**About 6,200 of the 11,124 bash lines in `utils` and `hooks` are python or node held inside a bash string (56%).** [Likely — counted by a pattern scan plus two blocks found by hand]

| Script | Lines | Python or node inside | Largest block |
|---|---|---|---|
| `tf-emit.sh` | 1,835 | about 1,500 python | 1,210 lines (608-1817), plus 10 smaller blocks |
| `tf-verify-boot.sh` | 895 | 186 python + 253 node [node count Likely too high: the scan mis-reads one block] | 104 lines at 231 |
| `tf-model-pick.sh` | 475 | 414 python | one block: the whole script |
| `tf-verify-tests.sh` | 607 | 403 python | 222 lines at 383; 9 blocks |
| `tf-selfcheck.sh` | 360 | 321 python | one block |
| `tf-assets.sh` | 395 | 282 python | one block |
| `tf-routing-bind.sh` | 307 | 268 python | one block |
| `tf-gitignore-audit.sh` | 328 | 263 python | one block |
| `block-git.sh` | 326 | about 235 python | 214 lines (93-306) |
| `guard-status-html.sh` | 235 | 202 python | one block |
| `sweep-artifacts.sh` | 244 | 193 python | one block |
| `tf-perf.sh` | 241 | 176 python | one block |
| `tf-goal.sh` | 645 | 170 python | 111 lines at 247 |
| `guard-db.sh` | 200 | 166 python | one block |
| `tf-routing.sh` | 253 | 158 python | 6 blocks |
| `tf-verify-emit.sh` | 165 | 128 python | one block |
| `guard-status.sh`, `guard-verify.sh`, `tf-fix-close.sh`, `tf-develop.sh`, `guard-verify-deps.sh` | 151, 135, 235, 264, 139 | 118, 113, 117, 105, 94 | one block each |
| 10 more files | — | 12 to 67 each | — |
| `tests/regression/run.sh` | 8,299 | 3,724 python + 456 node | 392 lines at 5973; 77 blocks |

31 blocks are longer than 30 lines, in 25 files.

**What moving them out would save. It saves few lines; that is not the gain.** The python moves, it does not shrink. About 150 to 250 lines of hand-off go (`TF_X="$X" python3 - <<'PY'` and the matching `os.environ` reads). [Guessing] The real gains:

- **The duplicates in section 2 can only be merged once the code is in files.** A block inside a bash string cannot import a shared helper, which is why `tf-emit.sh` carries its own copies of the root finder, the harness test and the routing reader. Moving out is what unlocks the 800 lines there.
- **An editor and a checker can read it.** Today an unused variable or a wrong indent inside a string is found only when the line runs. The `tf-verify-verdict.py` fault at line 361 is the kind a checker would flag.
- **`tf-verify-tests.sh` runs python nine separate times and loads the same id reader three times**; one python file would do it once.
- **Twelve scripts are python with a bash wrapper around it** (one block that is three quarters of the file or more). Each can become a `.py` plus a thin `.sh`, as 19 scripts already are.
- **No quoting traps.** `tf-emit.sh` 607 carries a comment about bash 3.2 misreading its own here-document.

The cost: each hook is meant to be one file that still lets the call through when python is missing. A hook plus a `.py` is two files to install. That is a fair reason to keep the small hooks as they are and move only the blocks over 30 lines in `utils`.

---

## 5. Fixes that changed behaviour for projects that did not ask

**Most fixes of the last month changed something for every project: 48 of 62. Eleven of those 48 had to be patched again, and in four of the eleven a different project was the one hit.** The grouping is one changelog change = one fix, good to about ±3. [Likely]

| | Count |
|---|---|
| Fixes answering a project's entry, 10 Oct to 10 Nov | 62 |
| Reached only the asker (an opt-in flag, a new mockup mark, a Mac-only path) | 14 |
| Changed behaviour for everyone | 48 |
| Of those, patched again or partly reversed | 11 |
| Of those 11, a different project was hit | 4 |

Of the 48: about 14 made a check stricter, 15 made one looser or added an exemption, 6 flipped a default; the rest changed output, timing or a file format.

### The cases that matter most

| Date | Asked by | Where | What changed for everyone | Who was hit |
|---|---|---|---|---|
| 10 Nov | **Sevak TF-021** (your example) | `tf-verify-tests.sh` 228-242; `tf-verify-list.py` `main()` 408, 528; `verify-phase.md` 26, 36 | On any project with two or more phase checklists, `*verify all` now runs only the browser tests whose title carries a row id of the graded phase. A test with no row id does not run. `--phase all` boots once per phase. The old behaviour is the opt-out (`--all-specs`). [Certain] | Chatur (4 checklists, deployed the same day), then TfLens (4), Lekhak (3) and AstroLyfe (2) at their next update. **12 of AstroLyfe's 38 spec files have no row id anywhere.** Patched the same day: the first version dropped three Sevak tests in silence. They are named now, and still not run. No other project's app was measured. |
| 21 Oct | Lekhak TF-036 | `tf-build.sh` 222-246 | On WSL, a web or test project that shares a solution with a MAUI project is built on the Windows side first. [Certain] | AppManager TF-030, TechieBlog TF-002, Chatur TF-018: verify could not boot the app on three projects. |
| 1 Nov | The repair of the above | `tf-verify-boot.sh` 699-712, 739 | Every WSL project's web copy now runs on the WSL side by default; the Windows fallback listens on every network address (`0.0.0.0`). [Certain] | Sevak TF-015 objected to the override being an environment variable. Chatur TF-024 looks like a consequence. [Guessing] |
| 14 Oct | Chatur TF-011 | new `tf-menus.mjs` (`walkMenus()` 221, `reachability()` 525) | Both browser checks now open every menu and click every item, on every project. Stricter, slower, and it clicks things in the app. Measured on Chatur only. [Certain] | Sevak TF-006 the same day (a working theme menu called dead). Then Chatur TF-020, TF-022, TF-023, and Chatur TF-025: the walk checked out another git branch in the app's repository and left it there. Patched five times. |
| 29 Oct | TechieRag TF-008 | `tf-checklist-edit.py` `next_id()` 114 | New row ids are also taken from ids found in code and tests. [Certain] | Chatur TF-021: a sample `REQ-UI-999` made triage hand out `REQ-UI-1000` and later, and the test reader cut them to `REQ-UI-100`. |
| 11 Oct | Sevak TF-005 | `tf-status-facts.py` 260, 384-394; `tf-verify-list.py` 399-410 | The suggested next command changed on Sevak, TfLens and Chatur. [Certain] | Chatur TF-013: its first `--phase all` wrote 19 false misses. |
| 1 Nov | FW-001 (owner) | `tf-verify-verdict.py` 134-139, 281-290; `tf-build.sh` 115-125 | A test that registers a user fails the row and the build. [Certain] | New findings on AstroLyfe (5), Chatur (4), Sevak (4); the document rule fails four projects until each adds a sentence. Its follow-up (Sevak TF-016) gave TfLens a new finding. |
| 5-8 Nov | TechieRag TF-009 | `tf-verify-verdict.py` 250-259, 444-457 | A row with some tests skipped is no longer Verified. A correct rule, and it was measured first: 20 rows drop — TechieRag 11, Chatur 6, AstroLyfe 2, Lekhak 1. [Certain] | Nobody complained. |
| 10 Nov | Sevak TF-017 | `tf-verify-verdict.py` 447-457, 483-497 | A Blocked row that fails a check now writes **no gate record and no miss**, on any project. A real defect on a Blocked row no longer shows in the numbers. [Certain] | Not yet known. |
| 1-10 Nov | Lekhak TF-037, Lekhak TF-038 | `tf-login.mjs` `waitArrived()` 214, `openFresh()` 277 | Every desktop-head project's screens are opened by leaving and coming back, and wait differently. A former PASS can become "not measured". [Certain] | The framework's own tests, twice. Patched three times. |
| 10 Nov | Sevak TF-023 | `tf-mockup-parity.mjs` 297, 323, 672 | Checkboxes, radios and switches are no longer compared at all. [Certain] | Not measured. |
| 10 Nov | Sevak TF-020, Sevak TF-024 | `tf-verify-screens.mjs` 344-351 | A control inside a hidden box is no longer a finding. [Certain] | Not measured. |
| 10 Nov | Chatur TF-024 | `tf-build.sh` 314-329 | On WSL a build that fails with any Razor error shuts the compiler servers down for the whole machine and builds again. The fault it answers was not reproduced. [Certain] | A build running at the same time in another project may lose its server. [Guessing] |
| 1 Nov | TfLens TF-056 | `tf-mockup-parity.mjs` 250-270 | A see-through colour is blended before it is named. Measured on mockups only: colour classes change in Chatur (146), AppManager (42), TrBlazeUI (14). [Likely] | App side not measured. |
| 14 Oct | Chatur TF-012 | `tf-req-ids.py` 19 | A test proves only the row ids at the start of its name. [Likely] | Drops TfLens REQ-UI-001 and Sevak REQ-UI-050. |
| 5 Nov | Sevak TF-015 | `tf-verify-boot.sh` 392-394 | The old environment variables work "for this release" only; every project that sets one must move it to the settings file. [Likely] | A set-up change still to come. |

### Three patterns

1. **Measured or not decides it.** Where the changelog says "measured on every project" (TechieRag TF-009, FW-001, Sevak TF-016, TechieBlog TF-003), no other project was surprised later. Every fix that hurt had been measured on the asker only.
2. **The opt-out is built, the opt-in is not.** `--all-specs`, `Verify:Runner` and `--no-click` each give a project the old behaviour back after it was changed for it.
3. **Exemptions pile up.** In one month the verify checks stopped reporting toggles, hidden boxes, sample boxes, Blocked rows, Not Started rows on a 404, scrolling boxes, large images and tests without ids. Each was right for the asker. Nobody has counted what they now hide on the other projects.

---

## 6. Rules in model-read files that code already enforces

**The rules the hooks block are already short: cutting every git, hand-written `Verified` and telemetry-file sentence saves about 150 words. The weight is in four task files that still describe by hand what a script now does.** About 6,165 words could go: 5,375 of the 28,768 words in the 35 task and agent files (19%), and 790 of the 2,253 words in three files read in every session. [Likely — line ranges and word counts are measured; the savings assume a short pointer is left behind.]

| File and lines | Words now | Could go | Why |
|---|---|---|---|
| `handoff-phase.md` 17-49 | 631 | about 550 | It prescribes UsageGuide sections the template no longer has; `tf-doc-check.py` 503 fails a section not in the template. **Following the prose as written produces a FAIL.** [Likely] |
| `generate-html.md` 66-83 | 382 | 382 | Eight steps for building HTML by hand; `tf-render-html.py` does every one. It contradicts line 50 of the same file ("do not hand-author"). |
| `metrics-report.md` 136-158 | 432 | about 330 | The third statement of the same rules in one file. |
| `opencode-operating-contract.md` 24-56 | 336 | about 300 | Its own text says it repeats the build and smoke tasks. Loaded in every OpenCode session. |
| `generate-html.md` 85-99 | 219 | 219 | "Review the HTML in your head"; the renderer checks it. |
| `render-workflow-docs.md` 51-71 | 194 | 194 | Titles and subtitles the renderer sets itself; the model cannot control them. |
| `render-workflow-docs.md` 73-86 | 228 | about 190 | The "next command" box the renderer writes, plus a 71-word history paragraph. |
| `render-workflow-docs.md` 18-35 | 251 | about 190 | Says bash asks permission (it does not) and searches for `-v2` copies nothing writes any more. |
| `handoff-phase.md` 51-63 | 193 | about 165 | PROJECT-STATUS fields filled by hand; `tf-status-facts.py` 420-422 prints them. |
| `productguide.md` 86-94 | 175 | about 160 | "Hard rules" restating the file's own steps. |
| Installed `AGENTS.md` template 16-18 and `CLAUDE.md` template 29-31 | 1,620 together | about 490 | The "framework folder is hidden from search" rule is in both, 337 words; Claude Code loads both, so reads it twice. Both cite gate sections that no longer exist. |

Per file: `handoff-phase.md` 1,170 of 1,796; `render-workflow-docs.md` 1,004 of 1,347; `generate-html.md` 995 of 1,558; `metrics-report.md` 700 of 2,432; `productguide.md` 425 of 1,437; `analyst.md` 360 of 1,265; `verify-phase.md` 170 of 1,560. Eleven files need nothing cut.

**History inside model-read files** costs about 400 words in all (13 entry ids, 10 project names, 9 dates). 23 of the 35 files carry none. This is small; the scripts are where the history lives.

**What must stay, because code does not fully enforce it** [Certain]:

- **The status gate.** The Stop hook blocks in Claude Code only. In OpenCode it is one nudge, and on OpenCode 2 the closing-message check does not run.
- **"Never edit the checklist by shell."** `guard-verify.sh` has no shell branch.
- **"Do not change `.last-verify.json`."** No hook guards that file, and a hand-written one unlocks `Verified`.
- **The backfill ban in `metrics-report.md`.** `block-git.sh` does not see git called from inside `tf-metrics.sh --backfill-commits`.

**Prose that now contradicts the code** — worse than extra words:

- `handoff-phase.md` 58 asks for one next-command line; the checker wants two blocks. Lines 97-104 ask for seven feedback fields; the checker needs eight.
- `generate-html.md` 97 and `render-workflow-docs.md` 96 say "fix it in the emitted HTML"; `generate-html.md` 60 says never edit the generated HTML.
- `analyst.md` 58 says confirm each requirement with the owner one by one; both day-1 tasks say ask once. Which is meant is your decision.
- `guard-artifacts.sh` 4 and 82 print a section name ("verify-phase.md §1") that is no longer in that file.
- `handoff-phase.md` is the only task with no `tf-phase.sh start` line.

---

## 7. A size rule the mirror suite could enforce

**Proposed: four numbers, checked the way the 7,000 words are.**

| Rule | Number | What fails today |
|---|---|---|
| A script in `.tfcore/utils` or `.tfcore/hooks` | at most **600 lines and 40,000 bytes** | 10 of 101 files |
| Python or node inside a bash string | no block over **30 lines** | 33 blocks in 26 files |
| A test file | at most **1,500 lines** | `tests/regression/run.sh` (8,299) |
| A script already over a limit | **may not grow**; its size today is written down as its ceiling | — |

Why these numbers:

- The median script is 142 lines and 91 of 101 are already under 600. The limit names the outliers and nothing else.
- Lines alone can be dodged with longer lines, and they already run long here. The byte limit closes that: `tf-menus.mjs` is 555 lines and 40,233 bytes.
- The fourth rule is the one that works from day one. Nothing has to be split before the check can go in; the ten files simply stop growing, and a fix that needs 40 more lines in one of them has to take 40 out or go in a new file.

**The ten that fail the first rule today:**

| Script | Lines | Bytes |
|---|---|---|
| `tf-emit.sh` | 1,835 | 91,600 |
| `tf-doc-check.py` | 1,617 | 88,236 |
| `tf-mockup-parity.mjs` | 1,321 | 79,681 |
| `tf-verify-boot.sh` | 895 | 59,684 |
| `tf-render-html.py` | 809 | 32,452 |
| `tf-verify-screens.mjs` | 717 | 48,906 |
| `tf-ci-repro.py` | 685 | 28,701 |
| `tf-goal.sh` | 645 | 35,683 |
| `tf-verify-tests.sh` | 607 | 37,927 |
| `tf-menus.mjs` | 555 | 40,233 |

Next to cross: `tf-verify-verdict.py` (592 lines, 38,718 bytes), `tf-verify-list.py` (537), `tf-test-users-check.py` (530).

**The regression file** splits cleanly by the project prefix its cases already carry: tf_ 41 cases and 1,773 lines, lk_ 37 and 1,325, am_ 30 and 982, ch_ 25 and 952, sv_ 23 and 938, 25 unprefixed cases and 981, tr_ 9 and 354, the rest under 250 each, with 332 lines of shared helpers. Only the tf_ file would be over 1,500. CI already runs every `tests/*/run.sh`, so files named that way are picked up with no change to CI.

**Two rules that are not about size but would have stopped most of section 5.** They cannot be checked by the mirror suite; they belong in the fix task:

1. A fix that changes what an existing check does for every project lands switched off, behind a setting, for the project that asked. It becomes the default only after it is measured on the named projects.
2. A new exemption (something a check stops reporting) is counted on every project before it ships, and the count goes in the changelog.

---

## What to cut or merge

Ordered by lines saved. "Protects it" names the regression cases and suites that would catch a mistake; the count in brackets is how many regression cases touch the script.

| # | Cut or merge | Lines saved | Risk | Protects it |
|---|---|---|---|---|
| 1 | Installer: one copy of the settings text; then `install.mjs` as a launcher and one scaffold script | 465, up to about 1,300 | Medium. Every project installs through it. | `scripts/test-install.mjs` (compares the routes), `tests/portability`, regression `gitignore_once`, `codex_keep` |
| 2 | Take defect history out of comments in the six check scripts; keep the one line that explains the code | 450 to 550 | None to behaviour. The history stays in the changelog. | Every suite; nothing should change |
| 3 | The 19 thin `.sh` starters → one launcher | about 320 (85 code) | Medium for little gain: every task file names the `.sh`. Do it only when the task files are being edited anyway. | `tests/mirror`, `tests/doc-check`, `tests/verify`, `tests/bugs` |
| 4 | One pairing rule in `tf-mockup-parity.mjs` in place of seven patches | about 180 | **High.** It changes results on every project; must be measured on all of them first. | Regression (36): `tf_027`, `tf_045`, `tf_046`, `tf_047`, `ch_002`, `ch_006`, `ch_007` |
| 5 | Move the Mac Catalyst branch out of `tf-verify-boot.sh` into its own file | 0 overall; 167 leave the shared script | Low | `tests/maccatalyst`, regression `lk_026`, `lk_030`, `lk_032` |
| 6 | Small python helpers (`read`, `die`, loader, jsonl loop) in one module | about 130 | Low | `tests/doc-check`, `tests/bugs`, regression across the python scripts |
| 7 | One checklist reader and writer (`tf-checklist-edit.py`) | about 128 | Medium. It decides what gets built and graded. | Regression `am_003`, `am_008`, `am_017`, `am_020`, `am_022`, `ch_004`, `lk_007`; `tests/doc-check`, `tests/bugs`. **No regression case names `tf-checklist-edit.py` itself.** |
| 8 | One `routing.yaml` reader | 96 | Low | `tests/routing`, `tests/goal`. **No regression case names `tf-model-pick.sh`, `tf-routing-bind.sh` or `tf-routing.sh`.** |
| 9 | One `core-config.yaml` reader and one "phase to file name" rule | 87 | Low | Regression `sv_005`, `am_017`, `am_018`, `tb_005`; `tests/doc-check` |
| 10 | Repeats inside `tf-verify-boot.sh` and `tf-verify-tests.sh` | about 75 | Low | Regression boot (15): `tf_034`, `tf_043`, `sv_003`, `ch_018`; tests (23): `sv_004`, `lk_007`, `am_013`, `ch_012` |
| 11 | Browser set-up into `tf-login.mjs` | about 74 | Low to medium | Regression `am_006`, `am_011`, `am_012`, `lk_006`, `lk_037b`, `lk_037c`; `tests/verify` |
| 12 | One menu-walk block for both browser checks | about 55 | Medium | Regression `ch_011`, `ch_020`, `ch_022`, `ch_023`, `ch_025` |
| 13 | Harness test, project root, marker reader, YOLO test: one home each | about 135 together | Medium. They decide where records land. This also closes three of the faults in section 2. | Regression `owner_handoff`, `harness_env`, `tf_052`, `tb_002`, `bl_001`, `tfyolo`, `goal_guard`; `tests/goal`, `tests/routing` |
| 14 | Special cases to settings or shared code: `pick_web` (22), split-screen guess (19), click path shared with the DevGuide lister (about 40), in-page sign-in copy (10) | about 90 | Medium. Each needs one settings line in the project that asked. | Regression `am_010`, `ch_003`, `lk_027`, `am_006` |
| 15 | Theme and colour code shared between the mockup check and `tf-theme.mjs` | about 40 | Medium | Regression `lk_010`, `lk_013`, `lk_024`, `lk_025`, `sv_007` |
| 16 | Dead weight: old part-file readers (11), old boot-record stop path (12), the two unused marks of 10 Nov (18), unused imports and variables (6), 14 unpassed flags (about 20) | about 65 | Low. Ask Sevak before removing the two marks. | Regression `lk_007`, `ch_012`, `sv_003`, `sv_018`, `sv_019` |
| 17 | The two `.pyc` files still in git | 2 files | None | — |
| 18 | Move python blocks over 30 lines out of the `utils` bash scripts | 150 to 250 [Guessing]; it is what makes rows 6 to 9 and 13 possible | Medium. Twelve scripts change shape. | The whole regression suite; `tests/routing`, `tests/goal`, `tests/estimate` |
| 19 | Split `tests/regression/run.sh` by project prefix | 0 | Low | It is the protection; run all parts before and after and compare the `ok` lines |
| 20 | Model-read prose (words, not lines) | about 6,165 words | Low for the cuts. The three "prose contradicts code" items are faults, not cuts. | `tests/mirror` (7,000-word cap, the two copies stay equal), `tests/requirements` |

Rows 1 to 17 without row 4: about 2,100 to 3,000 lines, most of the range being the installer. Without the installer, about 1,600 of 24,310 (7%).

**Bloated again: yes. Not because of dead code or one-app branches, but because every project's entry was answered with a rule for all projects, its story written into the script, and a second copy typed where a shared one was needed — so the five check scripts and the mockup check went from 1,888 to 4,669 lines in two months, and trimming gets back about 7%.**

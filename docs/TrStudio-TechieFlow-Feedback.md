# TechieFlow feedback — found while building TrStudio

| | |
|---|---|
| App | TrStudio |
| Upstream | TechieFlow |
| Updated | 2026-11-21 (TF-011 fixed upstream, not yet in `.tfcore/`) · 2026-11-19 (TF-008 to TF-010 fixed upstream; ship in TechieFlow v1.4.0, not yet in `.tfcore/`) · 2026-11-16 (TechieFlow replies) |

## Summary

11 entries: 0 open, 1 fixed upstream on 2026-11-21 and not yet in `.tfcore/` (TF-011, which holds the mockup check of REQ-UI-040, REQ-FN-051, 052 and 054 until the framework is updated), 3 fixed upstream on 2026-11-19 (TF-008 to TF-010; TrStudio's own file records them re-checked and closed on 20 Nov), 7 fixed upstream and in TrStudio's `.tfcore`, not yet re-checked here by TrStudio (TF-001 to TF-007). Checked on the app by TechieFlow on 16 Nov 2026: TF-003, TF-004, TF-005 and TF-007 in full, TF-001 by its no-password branch, TF-006 for the admin screens; TF-002 waits for the `span` to come off, TF-006's creator screens for the test users' roles.

Nothing is blocked by the framework. On 16 Nov 2026 the Mac app was driven with the fixed checker: the four signed-out screens and the seven admin screens were reached by its own clicks at 1280 and 390. Two steps are TrStudio's: the `span` around `sign-in` (TF-002), and test users whose role gives them the creator surface (TF-006).

## Entries

### TF-001 — The Mac boot script misses the Automation Mode password check and names the wrong fix

- **Status:** fixed upstream 2026-11-16, fixed in TrStudio's `.tfcore`; the password branch not re-checked on this Mac
- **Severity:** minor
- **Blocks:** no — the cause was found by running the mac2 helper build by hand, and the run went on to the next stage
- **Repro:** on macOS 27.2 with Xcode 27.2, `automationmodetool` prints `This device requires user authentication to enable Automation Mode.`; run `bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst`
- **Expected:** the script stops before the build with "macOS asks for a password before Automation Mode comes on … sudo automationmodetool enable-automationmode-without-authentication"
- **Actual:** line 528 greps `'^This device REQUIRES user authentication'`, which is case-sensitive, so the check never matches; the script builds, the mac2 helper exits with code 65, and the reason printed points at Accessibility permissions. The helper's own log says `Timed out while enabling automation mode.`
- **Encountered in:** stage 2 of the 15 Nov 2026 night run (real-app checks for phase 3)
- **Workaround:** none in TrStudio; the one-time `sudo` command is listed for the owner
- **Suggested fix:** `grep -qi 'requires user authentication'`, and map xcodebuild code 65 with "automation mode" in the helper output to the same fix line
- **Reply (TechieFlow team, 16 Nov 2026, Mac):** Fixed in TrStudio's .tfcore. The check reads `automationmodetool` in any case and sits in `tf-mac-host-check.sh`, run before the build (case `ts_001`). On this Mac today the tool says "This device DOES NOT REQUIRE user authentication" (the one-time `sudo` command has been run), the host check passes, and `tf-verify-boot.sh start --head maccatalyst` booted the app and Appium. The branch that stops with the `sudo` line could not be shown on the real Mac without undoing that setting; it is proved by its test case only.


### TF-002 — The mockup comparison reads a gradient button as "neutral" and a solid one as "accent"

- **Status:** fixed upstream 2026-11-16, fixed in TrStudio's `.tfcore`; not re-checked with the `span` taken off
- **Severity:** minor
- **Blocks:** no — the control name was put on a box around the button, as Login already does, and the work carried on
- **Repro:** a mockup button `class="btn brand"` whose background is a `linear-gradient`, and the app's TrBlazeUI `Button` with the same gradient over `bg-primary`; run `tf-mockup-parity.sh --screen forgot-password=/forgot-password`
- **Expected:** both read as the brand colour, no finding
- **Actual:** `semantic colour differs — mockup neutral, app accent` and `mockup renders this as a plain element, app renders it as a badge/pill` on the button (`btn-send-reset-link`, 15 Nov 2026)
- **Encountered in:** decision 11 naming run, Forgot password (REQ-UI-003)
- **Workaround:** the name sits on a `span` around the button, so the button itself is not compared
- **Suggested fix:** take the first colour stop of a `background-image` gradient as the background colour before classifying, on both sides
- **Reply (TechieFlow team, 16 Nov 2026, Mac):** Fixed in TrStudio's .tfcore (case `ts_002`). Not re-checked on the app: the check needs the `span` taken off the buttons, and app code was not changed in this run. The `span` now causes a finding of its own: Login's `sign-in` reads "semantic colour differs — mockup accent, app neutral", because the gradient is read as a fill since TF-002 and the anchor is the `span` around the button, which has none. Taking the `span` off `sign-in` (and `btn-send-reset-link`) is the remaining step, in TrStudio.


### TF-003 — Graded at an earlier phase, a mockup box marked for a later phase shifts every box after it, though the app already shows that box

- **Status:** fixed upstream 2026-11-16, fixed in TrStudio's `.tfcore`, checked on the app
- **Severity:** minor
- **Blocks:** no — graded with `--phase 3` (the phase the app is in) both screens match; the phase 1 rows stay as they were and the run carried on
- **Repro:** the smallest page pair. Mockup `m.html`:
  `<div data-testid="card"><div>Title</div><div data-tf-phase="3">Remember me</div><div>Note</div><div style="border-top:1px solid #ccc">Setup link</div></div>`
  App page, the same four boxes with the same styles (phase 3 is built, so the "Remember me" box is there). Run `tf-mockup-parity.sh --phase 1 --screen m=/m`.
- **Expected:** no finding. Either the later-phase box is skipped on both sides, or it is kept on both sides once the app shows it.
- **Actual:** `markLaterPhase` turns the mockup's phase 3 box into a state, so `keyOf` stops counting it, but the app's box is still counted. Every box after it pairs with its neighbour: `card > div[2]` (mockup "Setup link", bordered) is compared with the app's "Note" (no border), giving `border style differs — mockup solid, app none`. On TrStudio: Login `card-1 > div[5]` and Setup required `card-trstudio-isn-t-set-up-yet > div[3]` (`icon` and `stroke`), 16 Nov 2026, phase 1 rows REQ-UI-001, REQ-FN-016, REQ-UI-004.
- **Encountered in:** owner run of 15 Nov 2026, part A item 1 (the five rows that fail only the mockup comparison)
- **Workaround:** none in TrStudio; the rows stay as they are until the checker is fixed. `--phase 3` shows both screens clean.
- **Suggested fix:** when the app holds an element whose `data-testid` matches the later-phase box (here `remember-me-row`, `card-local-data`), treat that phase as reached for that box; or apply the same state skip to the app's matching testid in `keyOf`, so both sides number their siblings alike.
- **Reply (TechieFlow team, 16 Nov 2026, Mac):** Fixed in TrStudio's .tfcore. A later phase's box the app already draws (by its own anchor, or with no anchor by its tag and text under the same anchor) is kept on both sides; one the app does not draw is still left out (case `ts_003`, with your four-box repro). On the running app (web test host, phase 1): the old script gave Login `card-1 > div[5]` stroke and Setup required `card-trstudio-isn-t-set-up-yet > div[3]` icon and stroke at 1280 and 390; the new script gives neither. Setup required now passes. Login still fails, on `sign-in`'s colour only: see TF-002.


### TF-004 — The Mac screen checker never starts a click path from the screen the app opens on

- **Status:** fixed upstream 2026-11-16, fixed in TrStudio's `.tfcore`, checked on the app
- **Severity:** minor
- **Blocks:** no — Register's "Sign in" line was moved into a component, which gives the checker a root link to Login; the run carried on
- **Repro:** a Blazor Hybrid app that opens on Login (`@page "/login"`), whose only links to Register and Setup required are on the Login page itself; run `tf-verify-list.sh {App} all --phase 1`, then the Mac screen check
- **Expected:** Register is "reached by clicking 'Create an account'", because Login is the screen on view when the check starts
- **Actual:** `navigation()` in `tf-verify-list.py` seeds its search only with links in files that are not pages, so links on the opening screen are never reached; Register, Login and Setup required come out with no path, and the checker writes `no control reaches Register: no link to /register was found in the code` (TrStudio, 15 Nov 2026 09:40, 3 of 4 screens that need no sign-in)
- **Encountered in:** owner run of 15 Nov 2026, part A item 4
- **Workaround:** `src/TrStudioUI/Components/AuthSignInSwitch.razor` holds Register's "Already have an account? Sign in" link
- **Suggested fix:** also seed the search with the links of the page the app opens on (the boot record's first screen, or the route `/` redirects to), with an empty path
- **Reply (TechieFlow team, 16 Nov 2026, Mac):** Fixed in TrStudio's .tfcore. `tf-verify-list.py` keeps every page's own links (now in `tf_nav.py`) and writes the link graph into list.json; the Mac checker tells which screen is on view by that screen's own links and plans its clicks from there (case `ts_004`). On the real Mac app (`tf-verify-boot.sh start --head maccatalyst`), signed out, at 1280 and 390: Register by "Create an account", Login by "Sign in", Forgot password by "Forgot password", Setup required by "Sign in" > "See the setup gate", all four OK; screenshots under `tests/.artifacts/verify/screens-tf/`. `AuthSignInSwitch.razor` is no longer needed by the checker; whether to keep it is yours.


### TF-005 — The mockup comparison counts a fixed-height button as two lines of text

- **Status:** fixed upstream 2026-11-16, fixed in TrStudio's `.tfcore`, checked on the app
- **Severity:** minor
- **Blocks:** no — the button draws its label on one line; the phase 1 grade (where this phase-2 control is hidden) has no finding
- **Repro:** a TrBlazeUI `Button` with `Size="ButtonSize.Small"` (fixed `h-8`, 32 px) labelled "Test connection", even with `white-space: nowrap`; mockup `<button class="btn outline" style="padding:4px 10px">Test connection</button>`; run `tf-mockup-parity.sh --phase 3 --screen admin-registry=/admin/registry`
- **Expected:** no finding; the label is one line on both sides
- **Actual:** `btn-test-connection wrap: wraps to 2 rows where the mockup keeps it on 1` at 1280 and 390 (TrStudio, 16 Nov 2026): `lineCount` divides the box height less padding by the line height, and a fixed-height control is taller than one line without wrapping
- **Encountered in:** owner run of 15 Nov 2026, part B (re-checking every screen after the Mac fixes)
- **Workaround:** none needed in TrStudio
- **Suggested fix:** count rows from the text's own line boxes (`Range.getClientRects()` over the text nodes, distinct tops) instead of the element's height
- **Reply (TechieFlow team, 16 Nov 2026, Mac):** Fixed in TrStudio's .tfcore. Rows are counted from the text's own line boxes, not the box height (case `ts_005`; AppManager's `am_015` still holds). On the running app at phase 3 the old script gave `btn-test-connection wrap: wraps to 2 rows` at 1280 and 390; the new one does not. Registry still fails on one finding that is not this one: `sidebar > div[0] > div[0]` colour, mockup accent, app neutral, the same shape as Login's (an anchor around a gradient).


### TF-006 — The Mac screen checker cannot reach screens whose menu is built in code, or that sit behind a surface switch

- **Status:** fixed upstream 2026-11-16, fixed in TrStudio's `.tfcore`; partly checked: the menu built in code is checked on the app; "Switch to Management" is fixed but could not be checked on this install
- **Severity:** minor
- **Blocks:** no — those screens were opened by hand through the real menu on the Mac app and screenshotted at both widths; the same screens pass headless on the test host
- **Repro:** TrStudio's sidebar is built from C# data (`TrStudioNavSets`), its labels differ from the UIDesign names ("Characters" for "Character library", "Account" for "Account and spend", "Hardware and Setup" for the admin hardware screen), and the admin screens appear only after "Switch to Management"; run `tf-verify-screens.sh --appium … --list` on the Mac head
- **Expected:** every signed-in screen reached through the menu the person sees
- **Actual:** `no control reaches Character library: no link to /avatar/characters was found in the code`, and the same for Comparison, Account and all seven admin screens (10 of 18 signed-in screens, 16 Nov 2026): `tf-verify-list.py` reads only `href`/`Href` in `.razor` files, and the checker never presses a surface switch
- **Encountered in:** owner run of 15 Nov 2026, part B
- **Workaround:** the 10 screens were opened by hand on the real app at 1280 and 390
- **Suggested fix:** let the UIDesign screen list carry an optional "Reached by" column (labels to click, in order), read before the code scan; or match a menu label to a screen by its route when the menu is data
- **Reply (TechieFlow team, 16 Nov 2026, Mac):** Fixed in TrStudio's .tfcore. A C# call whose first two arguments are a label and a route (`new("Characters", "/avatar/characters", …)`) is a menu link now, and a label not on view is looked for again after a "Switch to …" control is pressed (case `ts_006`). On the real Mac app, signed in with test user 1: all seven admin screens reached by their own menu labels at 1280 and 390 (Hardware & Setup, Model Sources, Model Library, Registry & Providers, ComfyUI Import, RunPod & Ops, Content Policy). **Still wrong, in TrStudio's data:** test users 1 and 2 in `testsettings.Local.json` both land on Hardware & Setup with no switch control, which the app shows to an Owner only; neither address is the one the UsageGuide's table lists. So Character library, Comparison and Account were not reachable for either user and were reported UNREACHABLE (no "Characters" control on view), never graded on another screen. Give user 1 the Owner role, or put the UsageGuide's Owner in the settings file, and run the signed-in check again.


### TF-007 — The Mac screen checker clicks a control below the window without scrolling, and then reports the screen reached

- **Status:** fixed upstream 2026-11-16, fixed in TrStudio's `.tfcore`, checked on the app
- **Severity:** minor
- **Blocks:** no — the same click paths pass headless (`tests/verify/comfy-and-auth-paths.spec.ts`), and Register and Login were looked at by hand
- **Repro:** the real Mac app signed out, window 1280 × 800 at the app's zoom: Register's "Already have an account? Sign in" link sits below the window; run `tf-verify-screens.sh --appium … --list` with Register, then Login, in the list
- **Expected:** the checker scrolls the link into view before clicking it, and a screen whose click changed nothing is "not reached"
- **Actual:** the click lands outside the window and does nothing; the checker still writes `OK Login … clicked "Sign in"` with a screenshot of Register (`tests/.artifacts/verify/screens/login-1280-mac.png`, 16 Nov 2026), and the next two screens are then unreachable because the app never left Register
- **Encountered in:** owner run of 15 Nov 2026, part B
- **Workaround:** none in TrStudio
- **Suggested fix:** scroll the found element into view (mac2 `scroll` to it, or keyboard focus) before `click`; after the clicks compare the window's source with the one before, and call the screen not reached when nothing changed
- **Reply (TechieFlow team, 16 Nov 2026, Mac):** Fixed in TrStudio's .tfcore. The control is scrolled into the window before the click (on the web view: aimed at the window, mac2 moved your page 19 points and no more), each click must change the window or the screen is not reached, and a screen identified as another one is not reached (cases `ts_007`, `ts_007c`). On the real Mac app: Register's "Sign in" sat below the window at 1280 and 390; the checker first reported Login not reached, and after the scroll fix reached it, with a Login screenshot. Two more faults of the same kind were found on your app and fixed: "Account" was matched to "Create an account" (Register graded as Account), and the sign-in typed nothing into fields holding "@" or "!", so no signed-in screen was measured (cases `ts_007c`, `ts_007d`).

### TF-008 — The status facts script prints a phase line the status guard then refuses

- **Status:** fixed upstream 2026-11-19, ships in TechieFlow v1.4.0; not yet in TrStudio's `.tfcore/` (the owner deploys it); not yet re-checked here.
- **Severity:** minor
- **Blocks:** no — shortening the phase name in `current_phase` lets the write through
- **Repro:** a phase whose name is long ("One desktop app with the engine inside (Mac first)"); run `bash .tfcore/utils/tf-status-facts.sh TrStudio "amend-docs"`, copy its `current_phase` line into PROJECT-STATUS.md with the Write tool
- **Expected:** the line the facts script prints is accepted as printed
- **Actual:** the printed line is 122 characters; `guard-status.sh` refuses any `current_phase` over 120 ("must be ONE short line")
- **Encountered in:** owner run of 17 Nov 2026, the status gate of `*amend-docs`
- **Workaround:** shorten the phase name in the copied line by hand
- **Suggested fix:** the facts script shortens the phase name (or drops the counts) so its line stays within the guard's 120 characters
- **Reply (TechieFlow team, 2026-11-19):** Fixed upstream in `tf-status-facts.py`, as you suggested: when `current_phase` would pass the status guard's 120 characters, the phase name gives way first (cut, with `…`), then the line itself. Case `ts_008`: a phase name like yours, made longer: on the script you have, a 167-character line the guard refuses; now one the guard takes as printed. Control half: a short phase name is printed whole. **Check it here:** `bash .tfcore/utils/tf-status-facts.sh TrStudio amend-docs`, then its `current_phase` line written as printed.

### TF-009 — The Mac boot warns "no provisioning profile" for a project that names one

- **Status:** fixed upstream 2026-11-19, ships in TechieFlow v1.4.0; not yet in TrStudio's `.tfcore/` (the owner deploys it); not yet re-checked here.
- **Severity:** minor
- **Blocks:** no — the app is signed with its profile, opens, and Appium drives it; the warning is only wrong text
- **Repro:** `src/TrStudio/TrStudio.csproj` sets, for maccatalyst Debug, `<CodesignProvision>Mac Catalyst Team Provisioning Profile: com.techierathore.trstudio</CodesignProvision>` and `<CodesignEntitlements>Platforms\MacCatalyst\Entitlements.Debug.plist</CodesignEntitlements>` (with keychain-access-groups); run `bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst --project src/TrStudio/TrStudio.csproj`
- **Expected:** no warning; the check sees the profile the project names (`CodesignProvision`)
- **Actual:** `WARN … the entitlements ask for keychain-access-groups and the project names no provisioning profile; macOS will not start a locally signed build that asks for it`, then `BOOTED … mode=appium` and the app runs signed (`codesign -dvv`: Authority=Apple Development, TeamIdentifier=254ZS7W29T)
- **Encountered in:** owner run of 17 Nov 2026 (night), `*triage-and-fix`
- **Workaround:** none needed
- **Suggested fix:** `tf-maccatalyst-check.sh` reads `CodesignProvision` (and `CodesignEntitlements`) in a PropertyGroup whose condition is the Mac target and the configuration being booted, before warning
- **Reply (TechieFlow team, 2026-11-19):** Fixed upstream in `tf-maccatalyst-check.sh`: `<CodesignProvision>` (the property MAUI's Mac targets read) counts as a profile beside `<CodesignProvisioningProfile>`, in any PropertyGroup. The Debug-only reading you suggested was not added: the check is not per configuration elsewhere either. Case `ts_009`, your PropertyGroup's shape: on the script you have, the WARN; now OK. Control half: keychain entitlements and no profile still warn. **On your own project file** (copied to a scratch folder with its `Platforms/`, read only): the script you have says WARN, the new one OK. **Check it here:** the Repro's boot prints no "no provisioning profile" line.

### TF-010 — The "select cuts its text" check measures a native select that is invisible under a label that wraps

- **Status:** fixed upstream 2026-11-19, ships in TechieFlow v1.4.0; not yet in TrStudio's `.tfcore/` (the owner deploys it); not yet re-checked here.
- **Severity:** minor
- **Blocks:** yes — REQ-UI-040 (Video studio) and REQ-UI-052 (Comparison) cannot pass the visual check, although no text is cut on the screen
- **Repro:** Video studio's Model box and Comparison's Slot A / Slot B now draw the chosen name in a `div.select-wrap-label` that wraps, with the real `<select class="select-wrap-native">` laid exactly over it at `opacity: 0` (so a click or the keyboard still opens the native list). Seed `tests/verify/seed/video-studio.sh` and `compare.sh`; run `tf-verify-screens.sh --list … --base http://localhost:5099`
- **Expected:** a select the person cannot see (computed `opacity` 0, or `visibility: hidden`) is not graded for cut text; the visible label is graded instead (its `scrollWidth`/`scrollHeight` within its box), as `tests/verify/video-model-fit.spec.ts` does
- **Actual:** `FAIL Video studio … the select "Model" cuts its text at 1280px: … needs 350 px, the box has 240 px` and `FAIL Comparison … the select "Slot A" cuts its text at 390px`; the screenshots show every name whole, on two lines
- **Encountered in:** owner run of 17 Nov 2026 (night), `*triage-and-fix`, fixing the owner's own screen check of 17 Nov
- **Workaround:** none honest in the app: a native select's closed box never wraps, and at 390 px no layout gives a 350 px name room
- **Suggested fix:** in `tf-dropdowns.mjs` `SELECTS`, skip a select whose computed opacity is 0 or visibility hidden; optionally grade the element drawn under it (`elementFromPoint` at the select's centre with the select hidden) for clipping
- **Reply (TechieFlow team, 2026-11-19):** Fixed upstream in `tf-dropdowns.mjs`, as you suggested: a native select whose computed opacity is 0, or whose visibility is hidden, is not graded for cut text; the element drawn under its centre is, when it cuts its text sideways (scroll width past its box and not overflowing visibly). Your wrapping label passes. Case `ts_010`, your Video studio shape: on the script you have, `the select "Model" cuts its text at 1280px … needs 441 px, the box has 218 px`; now none. Control half: a label under an invisible select that cuts its text, and a visible select too narrow for its option, are still reported. **Check it here:** the Repro's screen check on Video studio and Comparison: no `cuts its text` line; REQ-UI-040 and REQ-UI-052 can pass the visual check.

### TF-011 — The mockup check counts an empty slider track as a missing badge

- **Status:** fixed upstream 2026-11-21; not yet in TrStudio's `.tfcore/` (the owner deploys it); not yet re-checked here.
- **Severity:** minor
- **Blocks:** yes — REQ-UI-040, REQ-FN-051, 052 and 054 (Video studio) cannot pass the mockup check, although the app draws both sliders
- **Repro:** `docs/mockups/video-studio.html` draws Duration and Motion strength as `<div class="slider"><i></i><b></b></div>` (no text); the app draws a native range input. Seed `tests/verify/seed/video-studio.sh`, then `tf-mockup-parity.sh --base http://localhost:5099 --screen video-studio=/video …`
- **Expected:** an element with no text and no badge class is not graded as a badge; a slider is matched to the app's range input
- **Actual:** `missing on card-controls > div[0] > div[1] @1280: the mockup draws a badge/pill here (""); it could not be located in the app` (and `div[1] > div[1]`), in light and dark; `tests/.artifacts/verify/parity.json`, 20 Nov 2026
- **Encountered in:** owner run of 19 Nov 2026 (night), `*handoff-phase`, re-verifying the TF-010 rows
- **Workaround:** none honest in the app: changing the real slider to match a drawing would make it worse
- **Suggested fix:** in the parity badge pass, skip a candidate whose text is empty; treat `.slider` (or an element whose children are only empty `i`/`b`) as a range control and match it to `input[type=range]`
- **Reply (TechieFlow team, 2026-11-21):** Fixed upstream in `tf-mockup-parity.mjs`, both halves of your suggestion. (1) A drawn slider is a slider, not a badge: a range input, a library's `role="slider"` handle with the textless box around it, or a textless box whose class says `slider` (your `<div class="slider"><i></i><b></b></div>`). Nothing inside one is a badge, on either side, and the mockup's slider is matched to the app's by count under the same parent: where the app draws as many, no finding; where it draws fewer, the finding reads `the mockup draws a slider here; the app draws no range input under this parent`. (2) A mockup box with no text, no icon and no class that says badge, pill, chip, tag or dot is no longer reported as a missing badge. Case `ts_011`, your Controls card: on the script you have, `missing on card-controls > div[0] > div[1]` and `div[1] > div[1]` (`the mockup draws a badge/pill here ("")`); now none. Control half: with both sliders taken out of the app, two missing-slider findings; a dot of class `dot` and a pill with text that the app leaves out are still missing. **Check it here**, once the framework is updated: seed and run the Repro's `tf-mockup-parity.sh … --screen video-studio=/video`; expect no `missing` on `card-controls`, then `*verify` REQ-UI-040, REQ-FN-051, 052 and 054. Not run on your app by us: TrStudio was read only today.

## Resolution status (TechieFlow team, 2026-11-21)

From `/mnt/c/1MyCode/TrStudio/docs/TrStudio-TechieFlow-Feedback.md`, read on 2026-11-21.

**Not yet in TrStudio's `.tfcore`.** TrStudio was not touched: no file written, nothing run, no framework update (the owner's rule for this run). The fix reaches this project with the next `update-framework.sh`. Its case is in `tests/faults/n21-cases.sh` (run by `tests/faults/run.sh`); it fails on the scripts this project has and passes now, with a control half that shows a real finding is still reported.

| ID | Fix | Case | Check it here |
|---|---|---|---|
| TF-011 | A drawn slider is matched to the app's range input; a box with no text, no icon and no badge class is not a missing badge. | `ts_011` | Video studio: no `missing` on `card-controls`; then verify REQ-UI-040, REQ-FN-051, 052, 054. |

**The rules that changed, and which way each can move a finding** (mockup check only). (1) Slider: fewer findings, where a mockup draws a slider and the app draws one; a new `missing` finding only where the mockup draws more sliders under a box than the app does. (2) No text, no icon, no badge class: fewer `missing` findings, never more. Nothing else in the check changed.

**The table** (`measure-projects.py --base deployed`: your scripts against this tree, read only), your row: rows whose verdict moves: not measured; tests a phase verify stops running: 0 of 42 stop; findings that appear or go: none; build list and next command: same. The mockup check changed, so a row with a screen reads "not measured" there: the saved records were written by the old check. **The mockup side was measured** by opening your 22 mockups with the old and the new measuring code (read only, 1280 wide): of 349 boxes the old check called a badge, 21 are now slider parts (image-studio, video-studio and voice-studio), 40 have no text, no icon and no badge class and can no longer be reported missing (13 mockups), and 30 textless ones keep their badge by their class. Whether a finding goes on a given screen depends on what the app draws there, which was not run.

## Resolution status (TechieFlow team, 2026-11-19)

From `/mnt/c/1MyCode/TrStudio/docs/TrStudio-TechieFlow-Feedback.md`, read on 2026-11-19.

**Not yet in TrStudio's `.tfcore`.** TrStudio was not touched tonight: no file written, nothing run, no framework update (the owner's rule for this run, while other projects ran their own fixes). The fixes reach this project with the next `update-framework.sh` and ship in **TechieFlow v1.4.0**. Each has a case in `tests/faults/n19-cases.sh` (run by `tests/faults/run.sh`) that fails on the scripts this project has and passes now, with a control half that shows a real finding is still reported.

| ID | Fix | Case | Check it here |
|---|---|---|---|
| TF-008 | The facts' `current_phase` line fits the guard's 120 characters. | `ts_008` | the facts' line written as printed. |
| TF-009 | `<CodesignProvision>` counts as a profile. | `ts_009` | the boot prints no profile warning. |
| TF-010 | An invisible select is not graded; the label under it is. | `ts_010` | Video studio and Comparison: no `cuts its text`. |
| TF-007 | Fixed and checked on the app on 16 Nov; `ts_007`, `ts_007c`, `ts_007e` still pass tonight. Nothing new. | — | as in its reply. |

**One more change that reaches your verify, not filed by you (TfLens TF-060).** A row of a later phase that no screen of its own phase owns is now resolved against the earlier phases' screens. On your documents (read only), 71 rows gain a screen (phase 2: 26, phase 3: 45), for example REQ-FN-075 on `/admin/registry`; their next verify runs the screen and mockup checks they skipped.

**The table** (`measure-projects.py --base v1.3.1`), your row: rows whose verdict moves: not measured; tests a phase verify stops running: 0 of 40 stop; findings that appear or go: none; build list and next command: same. The screen and mockup checks changed, so a row with a screen reads "not measured" there: the saved records were written by the old checks. What they now do is in the cases above, and the earlier-phase screens (TfLens TF-060) are counted from your documents, not from a verify.


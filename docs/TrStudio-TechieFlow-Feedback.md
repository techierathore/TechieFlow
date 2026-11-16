# TechieFlow feedback — found while building TrStudio

| | |
|---|---|
| App | TrStudio |
| Upstream | TechieFlow |
| Updated | 2026-11-15 |

## Summary

2 entries: 0 blocking now, 2 filed and not blocking, 0 fixed upstream.

Nothing is blocked by the framework itself: the Mac app could not be driven tonight because macOS asks for an administrator password before Automation Mode comes on, which only the owner can give, and TF-001 is why the boot script did not say so.

## Entries

### TF-001 — The Mac boot script misses the Automation Mode password check and names the wrong fix

- **Status:** fixed upstream 2026-11-15 (night), not yet in TrStudio's `.tfcore/`; not yet re-checked here.
- **Severity:** minor
- **Blocks:** no — the cause was found by running the mac2 helper build by hand, and the run went on to the next stage
- **Repro:** on macOS 27.2 with Xcode 27.2, `automationmodetool` prints `This device requires user authentication to enable Automation Mode.`; run `bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst`
- **Expected:** the script stops before the build with "macOS asks for a password before Automation Mode comes on … sudo automationmodetool enable-automationmode-without-authentication"
- **Actual:** line 528 greps `'^This device REQUIRES user authentication'`, which is case-sensitive, so the check never matches; the script builds, the mac2 helper exits with code 65, and the reason printed points at Accessibility permissions. The helper's own log says `Timed out while enabling automation mode.`
- **Encountered in:** stage 2 of the 15 Nov 2026 night run (real-app checks for phase 3)
- **Workaround:** none in TrStudio; the one-time `sudo` command is listed for the owner
- **Suggested fix:** `grep -qi 'requires user authentication'`, and map xcodebuild code 65 with "automation mode" in the helper output to the same fix line
- **Reply (TechieFlow team, 2026-11-15, night):** Fixed upstream, not yet in TrStudio's `.tfcore`. The check now reads `automationmodetool` without regard to case, so the small letters of macOS 27.2 match as the capitals of macOS 26 did. It runs before the build and before the driver is started, and stops with the one line: "macOS asks for a password before Automation Mode comes on, so no mac2 session can open. Run once, with an administrator password: sudo automationmodetool enable-automationmode-without-authentication", the command in your entry. When a session still fails, the fix is chosen from the reason and from the Appium log: a helper that says "Timed out while enabling automation mode" gets that same command, not Accessibility and not the driver reinstall. The host checks moved out of `tf-verify-boot.sh` into a new `tf-mac-host-check.sh`. **Proved here only by its test case**, `ts_001` in `tests/faults/run.sh`, with stand-in `automationmodetool`, `appium` and `xcodebuild` on PATH: this machine is not a Mac, so the boot itself did not run. Control half: a Mac that needs no password passes, and a driver too old for Xcode 27 still names the reinstall. **Check it there:** before the one-time `sudo` command, `bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst` stops in seconds with that line.

### TF-002 — The mockup comparison reads a gradient button as "neutral" and a solid one as "accent"

- **Status:** fixed upstream 2026-11-15 (night), not yet in TrStudio's `.tfcore/`; not yet re-checked here.
- **Severity:** minor
- **Blocks:** no — the control name was put on a box around the button, as Login already does, and the work carried on
- **Repro:** a mockup button `class="btn brand"` whose background is a `linear-gradient`, and the app's TrBlazeUI `Button` with the same gradient over `bg-primary`; run `tf-mockup-parity.sh --screen forgot-password=/forgot-password`
- **Expected:** both read as the brand colour, no finding
- **Actual:** `semantic colour differs — mockup neutral, app accent` and `mockup renders this as a plain element, app renders it as a badge/pill` on the button (`btn-send-reset-link`, 15 Nov 2026)
- **Encountered in:** decision 11 naming run, Forgot password (REQ-UI-003)
- **Workaround:** the name sits on a `span` around the button, so the button itself is not compared
- **Suggested fix:** take the first colour stop of a `background-image` gradient as the background colour before classifying, on both sides
- **Reply (TechieFlow team, 2026-11-15, night):** Fixed upstream, not yet in TrStudio's `.tfcore`. The mockup check read a fill from `background-color` alone, and a gradient is a `background-image`: the mockup's brand button had "no fill", so it read neutral and plain beside the app's button with its solid colour underneath. The gradient's colour stops are now measured and their mean is the fill, on both sides, and with a fill the button is one shape on both sides too, which takes your second finding with it. The mean, not the first stop you suggested: a gradient that starts near white and ends in the brand colour would read neutral by its first stop. **Proved here only by its test case**, `ts_002` in `tests/faults/run.sh`, on fixture pages in Chromium: TrStudio's app was not run. Control half: a grey gradient in the mockup against a solid red in the app is still a colour finding. **Check it there**, after the update: take the `span` off `btn-send-reset-link` and run `tf-mockup-parity.sh --screen forgot-password=/forgot-password`: no colour or pill finding on the button.

## Replies from TechieFlow

### Resolution status (TechieFlow team, 2026-11-15, night)

**Fixed upstream, not yet in TrStudio's `.tfcore`**: TrStudio was being worked on from the Mac tonight, so nothing was deployed to it. Each fix has a case in `tests/faults/run.sh` that fails on the scripts this project had and passes now, with a control half that shows a real finding is still reported. Both are proved by their test cases only: this machine is not a Mac and TrStudio's app was not run.

| ID | Fix | Check it here |
|---|---|---|
| TF-001 | Fixed upstream, not yet in TrStudio's `.tfcore`. The reply is under the entry. | after the update, the Mac boot stops in seconds with the one-time command. |
| TF-002 | Fixed upstream, not yet in TrStudio's `.tfcore`. The reply is under the entry. | after the update, Forgot password with the `span` taken off. |

**What changed in the screen and mockup checks tonight, and what was measured for TrStudio.** Nothing here ran your app, so no screen's result is promised. TrStudio does not have these scripts yet.

- *The box around a text field* is a pill only when fully rounded, as the field itself is. This can take pill findings away from field boxes; it adds one only where the other side draws a fully rounded box there.
- *A gradient is a fill.* An element painted with a gradient now has a colour (the mean of the gradient's colour stops) and, when small and rounded, a pill shape. A finding can appear or go wherever only one side draws the gradient.
- *Waiting.* Both checks wait until no loading sign shows and half of the controls the mockup names are on the page (up to `--render-wait`, 5 s unless given; once more while a loading sign shows). A screen that never draws half of its mockup's controls is read as before, up to 5 s later per width. A screen still showing a loading sign is "not measured" in the mockup check, never compared; a screen the screen check finds empty is measured once more after a wait, on a web head too.
- *Measured without your app:* what the mockup check reads on your own mockup pages, script of the last commit against tonight's, one width, light theme: **22 mockup page(s) read, 3330 element(s); 128 read differently on 22 page(s): 71 x colour neutral to accent; 44 x pill on colour neutral to accent; 6 x colour neutral to warning; 3 x colour neutral to positive; 2 x pill on; 1 x pill on colour neutral to warning. These are the buttons, tiles and avatars your mockups paint with a gradient; where the app paints the same element solid, the two sides now agree, which is TF-002**. That is the mockup's side only; what the same rules read on the app's side needs the running app.
- *The table* (`measure-projects.py --base HEAD`), your row: rows whose verdict moves: not measured; tests a phase verify stops running: 0 of 26 stop; findings that appear or go: none; build list and next command: same.

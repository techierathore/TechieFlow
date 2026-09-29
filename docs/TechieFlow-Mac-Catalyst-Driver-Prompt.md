# TechieFlow — Mac Catalyst driver, session prompt

| | |
|---|---|
| Purpose | The text the owner pastes into a Claude Code window **on the Mac** to build the verifier's Mac Catalyst driver and close Lekhak's TF-003. Written 2026-09-29. |
| Audience | The owner, and the maintainer session that reads it. |
| Companion | `docs/Lekhak-TechieFlow-Feedback.md` (TF-003 and the 28 Sep reply), `docs/TechieFlow-Setup.md` §0a, §0b and §11, `.tfcore/utils/tf-verify-boot.sh`, `.tfcore/utils/tf-verify-screens.mjs`, `.tfcore/utils/tf-verify-verdict.py`, `docs/CHANGELOG.md` |

**When to run it.** Lekhak deferred its Mac-head rows until after UAT on 2026-09-29 (REQ-FN-140, 143 and 144, a roadmap decision). Its rule REQ-NFR-042, "Verified means verified on both heads", needs this driver before those rows can be verified. So run this session before Lekhak picks those rows up again. It does not block the release.

---

## The prompt (paste from here)

You are the TechieFlow maintainer, working on the owner's Mac. The job: build the verifier's **Mac Catalyst driver**, prove it on Lekhak's real Mac head, and close Lekhak's TF-003 (`MISS-TechieFlow-20260928-07`). It has stayed open only because every earlier session ran on the Windows/WSL machine, where a Catalyst app cannot be built or driven.

**Find the two folders first.** The briefing gives the TechieFlow checkout as `/Users/MyCode/TechieFlow`; if it is not there, look under `~` and `/Volumes/*/MyCode`. Lekhak is a sibling checkout. Say which paths you use before anything else.

**Rules for this session.**
- Git: never commit, push, stage, stash or check out. The owner reviews and commits. Read-only git only if the repository's hook allows it.
- Read `WorkFlow-Context.md` first, then `docs/Lekhak-TechieFlow-Feedback.md` (TF-003 and the 2026-09-28 reply).
- No script is done until it has run for real, and you show its output. A fix gets a regression case that fails against the script as it was.
- Every script must still run on Linux and on a stock Mac (bash 3.2, BSD tools): use `.tfcore/utils/tf-portable.sh`, and keep `bash tests/portability/run.sh` green.
- The Linux CI job has no Xcode or Appium. Every new case must **skip with a one-line reason** there, the way `lk_010` skips without Playwright, and never fail.
- Write to the owner in plain words: what you did, what you saw, what is left.

**What exists today.**
- `tf-verify-boot.sh start --head maccatalyst` writes a `NONE … no driver for the maccatalyst head ships in this framework version` state and exits 2 (`tf-verify-boot.sh` line ~275). Its `web` and `windows` heads are the pattern to follow: one state file and one log per port, `BOOTED head=… mode=… url=…`, and `stop` kills only what `start` started.
- `tf-verify-screens.mjs` checks each screen in a browser page and writes `tests/.artifacts/verify/screens.json`, which is the only thing `tf-verify-verdict.py` reads for the render and visual checks. The Mac driver must write **the same shape**, so the verdict needs no change.
- Lekhak's Mac head is `source/BlogAdmin/BlogAdmin.csproj`, a MAUI Blazor Hybrid app with `net10.0-maccatalyst` when it is not building on Windows. On Windows the same app is driven over the WebView2 DevTools port. On a Mac the web view is WKWebView, which has no DevTools port Playwright can attach to. So the Mac route is Appium's `mac2` driver and the accessibility tree.
- Lekhak already drove this head by hand. Its workaround, and the design to follow:
  - Open the app by `appium:appPath`. The bundle id alone was "not found" for a copy outside /Applications.
  - Set `AXEnhancedUserInterface` on the app process, so the web view's content appears in the element tree.
  - Type through `macos: keys` bound to the element. A plain `setValue` drops characters or replaces the field.
  - Take element screenshots of the app window.
- Look for Lekhak's own mac2 scripts on this Mac (Lekhak's `tests/`, `tests/.artifacts/`, or wherever it keeps them). They are not in the Windows checkout. Read them before writing anything.

**Step 1 — prove the one thing that could sink the design, before building.** The render check finds each control by its mockup anchor, `data-testid`. Find out whether a `data-testid` (or the element's `id`) is visible to `mac2` inside the web view: `AXDOMIdentifier`, `AXDOMClassList`, the element's label, or anything else. Do it on one Lekhak screen, and show the attribute dump for three anchored controls.
- If the anchors can be read: go on to Step 2.
- If they cannot: stop. Write `docs/TechieFlow-Decision-Request.md` in plain English, with the options (for example: Lekhak adds `id` attributes that mirror its test ids; the driver matches by label; the Mac head is graded on screenshots only) and each one's cost. End with your recommendation. Tell the owner in one line, and do nothing more.

**Step 2 — build.**
1. **`tf-verify-boot.sh start --head maccatalyst`.** Build the Catalyst head with `tf-build.sh`, the one-build-at-a-time lock included. Find the `.app`. Start Appium on `localhost:4723` if nothing answers there, or use the endpoint in `core-config.yaml → runtimeVerification.appium.maccatalyst` when set. Launch the app by `appium:appPath`. Print `BOOTED head=maccatalyst mode=appium url=…`, with its state file and log. Keep `NONE` with a plain reason when Xcode, the `mac2` driver or the automation permission is missing, and name the one command that fixes it. `stop` quits the app and any Appium process the start began, nothing else. Leave `android` and `ios` as they are.
2. **The screen driver.** Either a new `tf-verify-screens-mac.mjs` called by `tf-verify-screens.sh --appium <url>`, or a mode of the existing script; pick the smaller. For each screen: navigate the way the app's own menu does; check that every anchored control is present and shows something (render); check overlap, zero size and off-window (visual) from the element rectangles; save an element screenshot of the app window; and write the same `screens.json` fields and finding classes as the browser driver. Use the whole app window instead of the 1280 and 390 px widths, and record that in the JSON.
3. **Head choice.** When a project has both a web and a Mac head, the default stays `web`. If the owner asked for the Mac head, the agent passes `--head maccatalyst`. Add one line saying so to `verify-phase.md` step 3, and copy it byte for byte to `.claude/commands/TechieFlow/tasks/verify-phase.md` (FR-26: the file stays under 4,000 words).
4. The mockup check (`tf-mockup-parity`) and the asset check stay browser-only in this session. Say so in the verdict's note for Mac rows, rather than grading them as passes.

**Step 3 — prove it.**
- Regression cases in `tests/regression/run.sh` (name them `lk_003a`, `lk_003b` …): the boot, the driver's `screens.json` shape, the verdict reading it, `stop`. Each fails against the scripts as they are now, and skips with a reason where there is no Xcode or Appium.
- A real run on Lekhak: `tf-verify-boot.sh start --head maccatalyst`, the screen driver over at least the AI Setup and Connection settings screens, then `tf-verify-verdict.sh` on a targeted scope. Show `screens.json`, two screenshots and the Remarks the verdict wrote. **Do not change Lekhak's checklist rows**: they are deferred by the owner. Run the verdict on a copy, or with a scope that writes no Status.
- `npm run validate`, `npm run test:install`, and every `tests/*/run.sh` under `/bin/bash`, in UTC and with `TZ=Asia/Kolkata`. All must pass.

**Step 4 — record it.**
- `docs/TechieFlow-Setup.md` §11 and `docs/OpenCode-Deployment-Guide.md` §5: the Mac Catalyst head now has a driver; say what it checks and what it does not.
- `docs/CHANGELOG.md`: a dated entry, and a line in the "Unreleased" section.
- Close the miss with `tf-log-miss.sh … --fixed`, or the closing form the script offers for an existing miss.
- Reply to TF-003 in Lekhak's `docs/Lekhak-TechieFlow-Feedback.md` as a new `Resolution status (TechieFlow team, <date>)` block (fix, and "check it here"), keep its Summary counts right, and copy the file to this repository's `docs/`. `bash .tfcore/utils/tf-doc-check.sh` must pass both copies.
- Deploy to Lekhak on this Mac with `update-framework.sh`. The Windows machine's projects get it after the owner commits and pulls there.
- One `framework-reset` run record through `tf-emit.sh runs`, started at the previous record's `ended`.

**Finish with** one short message: a table (what was built, how it was proved, where the evidence is), anything that did not work and why, what is left for the owner, and the `git status` file list if the hook lets you read it.

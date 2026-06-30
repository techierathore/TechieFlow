# Mobile & desktop runtime-verification bridge — design proposal

> **Status:** APPROVED design (2026-06-29) — owner resolved the §12 decisions. No framework files changed yet; this is the finalized spec to implement against.
> **Scope (owner-chosen):** add **Android + iOS + Mac Catalyst** runtime UI verification, mirroring the existing Windows/MAUI bridge. Leave the working **Blazor/Playwright** and **MAUI Windows-head (FlaUI/Appium-Win)** paths untouched.
> **Locked decisions:** (1) **include Mac Catalyst** — same LAN Mac, `mac2` driver; (2) **enable Windows 11 mirrored networking** — the Android Appium endpoint is plain `localhost:4723`, no host-IP dance; (3) **add an `AutomationId` coding standard** so native controls are reliably addressable by Appium; (4) Android uses the **emulator** by default (real device supported by the same path).

---

## 1. The problem

The verifier (Vidur) and the self-smoke gates can today *observe the running UI* for two of your four heads:

| Head | Build today | **Runtime observe today** |
|------|-------------|---------------------------|
| Blazor | `dotnet build` (WSL) | ✅ headless Playwright → screenshot + DOM |
| MAUI **Windows** | Windows side via `winrun`/`cmd.exe` | ✅ FlaUI / Appium-Windows-driver |
| MAUI **Android** | Windows side via `cmd.exe` (rung #4) | ❌ **build only — never run/observed** |
| MAUI **iOS** | paired Mac (Xcode) | ❌ **build only — never run/observed** |
| MAUI **Mac Catalyst** | paired Mac (Xcode) | ❌ **build only — never run/observed** |

So the **visual-truth gate (verify-phase §4b)** and the **data-render gate (§4a)** — the whole point of the 2026-06-26 redesign — silently *do not apply* to Android, iOS, or Mac desktop. A MAUI mobile app can pass every gate while its screens overlap, clip, or render blank. This is the same class of blind spot the visual-truth gate was created to close, just on the heads the bridge never reached.

## 2. Core insight — Appium is the Playwright of native UI

The existing gates don't care *how* a screen is driven; they consume two artifacts:

- a **screenshot** → visual-truth gate (no overlap / in-viewport / non-zero size / diff vs mockup);
- an **element / accessibility tree with text + bounds** → data-render gate ("rows present AND non-empty", value non-blank).

**Appium** (WebDriver protocol) returns *exactly those two artifacts* for native apps, the same way Playwright does for the DOM:

| Gate needs | Playwright (Blazor) | Appium (native) |
|------------|---------------------|-----------------|
| Screenshot | `page.screenshot()` | `driver.get_screenshot_as_base64()` |
| Element bounds (overlap/clip/viewport) | `boundingBox()` | `element.rect` |
| Data presence (rows/text) | DOM query | page source (XML accessibility tree) |
| Drive UI (tap/type/nav) | `click`/`fill` | `click`/`send_keys` |

One Appium server per platform exposes an **HTTP WebDriver endpoint**, with a platform-specific driver underneath:

- **Android** → `uiautomator2` driver → emulator/device via `adb`
- **iOS** → `xcuitest` driver → iOS Simulator
- **Mac Catalyst** → `mac2` driver → the running .app
- (Windows → `windows` driver — *available but out of scope; we keep FlaUI/Appium-Win as-is*)

**Net:** the verifier gains a third "render engine" (Playwright, FlaUI, **Appium**) that returns the same evidence the gates already understand. Gate logic does not change.

## 3. Why this is "configure once per WSL", like Playwright/winrun

The verifier **never runs `adb`, an emulator, Xcode, or Appium inside WSL.** It only needs an **HTTP endpoint** to talk to. Everything heavy runs where it belongs:

```
                          HTTP (WebDriver / JSON)
WSL verifier  ─────────────────────────────────────►  Appium @ Windows host  ──adb──►  Android emulator / device
            │                                                                            [Android SDK on the host]
            ├──────────────────────────────────────►  Appium @ LAN Mac        ──XCUITest──►  iOS Simulator
            │                                          (same server)           ──mac2─────►  Mac Catalyst .app
            │                                                                            [Xcode + .NET on the Mac]
            ├── (existing, unchanged) ─────────────►  FlaUI / Appium-Win      ──────────►  MAUI Windows head
            └── (existing, unchanged) ─────────────►  Playwright headless Chromium ──────►  Blazor
```

- **Android** runs **entirely on the Windows host** (where the SDK + HAXM/WHPX virtualization live). You can even *launch* it through the bridge you already have: `winrun "emulator -avd Pixel_API_34"` and `winrun "appium ..."`. WSL then drives it over HTTP.
- **iOS Simulator + Mac Catalyst** run on the **LAN Mac** you already use as the iOS build host. One Appium server on the Mac serves both (xcuitest + mac2 drivers). WSL drives it over the network.

This is exactly the "set it up once, like Playwright and the Windows bridge" model you proposed — because the only per-session need on the WSL side is reaching a URL.

## 4. One-time setup (proposed new `WORKFLOW.html §0b`, sibling to the §0 WSL bootstrap)

### 4a. Android — on the Windows host, once

```powershell
# Android SDK already present. Add an AVD + Appium.
# (run on Windows / via winrun)
sdkmanager "system-images;android-34;google_apis;x86_64"
avdmanager create avd -n Pixel_API_34 -k "system-images;android-34;google_apis;x86_64"

npm install -g appium
appium driver install uiautomator2
```

Helper (Windows side) to bring the leg up for a session:

```powershell
# start-android-verify.ps1  (launched from WSL via: winrun "powershell -File start-android-verify.ps1")
Start-Process emulator -ArgumentList "-avd Pixel_API_34 -no-snapshot -no-boot-anim"
Start-Process appium   -ArgumentList "--address 0.0.0.0 --port 4723"
```

Verify once from WSL:

```bash
curl http://localhost:4723/status      # mirrored networking → localhost reaches the Windows-host Appium; expect {"value":{"ready":true,...}}
```

### 4b. iOS + Mac Catalyst — on the LAN Mac, once

```bash
# Mac already has Xcode + .NET + MAUI workload (it's your iOS build host).
npm install -g appium
appium driver install xcuitest      # iOS Simulator
appium driver install mac2          # Mac Catalyst desktop
# Give the Mac a stable LAN IP (DHCP reservation) so the endpoint never moves.
appium --address 0.0.0.0 --port 4723
```

Verify once from WSL:

```bash
curl http://<mac-lan-ip>:4723/status
```

## 5. Endpoint registry (proposed `core-config.yaml` addition)

The verifier auto-discovers device hosts the way it knows about `winrun` today:

```yaml
runtimeVerification:
  appium:
    android:
      url: http://localhost:4723         # Win11 mirrored networking is ON → localhost reaches the Windows-host Appium
      avd: Pixel_API_34
      launch: winrun "powershell -File start-android-verify.ps1"
    ios:
      url: http://192.168.1.50:4723      # LAN Mac
      simulator: "iPhone 15"
    maccatalyst:
      url: http://192.168.1.50:4723      # same Mac, mac2 driver
```

Absent/unreachable endpoint → that head degrades to `⚠ STATIC-ONLY` (see §7), never a faked pass.

## 6. How it plugs into the existing gates (no gate-logic change)

- **`verify-phase §4a` (data-render):** for an in-scope REQ whose screen is a MAUI Android/iOS/Catalyst head, the verifier picks the Appium driver from the registry instead of Playwright, navigates to the screen, and runs the *same* assertion — element present AND has non-empty text/children — against Appium's page source. `RENDER-FAIL → Needs re-verify`, unchanged.
- **`verify-phase §4b` (visual-truth):** same screenshot + element-bounds assertions (no overlap, in-viewport, non-zero size) using `element.rect`, at the device's natural size + a small/large variant where the simulator supports it. Diff vs the mockup where one exists. `VISUAL-FAIL → Needs re-verify`, unchanged.
- **`_smoke-test-policy.md`:** the "it runs means controls RENDER their data" rule already exists; we add Appium as an allowed driver and add a banned-excuse line ("it's Android/iOS, can't run from WSL") parallel to the existing MAUI/Playwright excuses — because the bridge now exists, exactly like winrun closed "can't build MAUI from WSL".

The verdict tables, checklist write-back, and DevGuide OBSERVE pass all keep working — they consume the gate result, not the driver.

## 7. Graceful degradation (reuses the STATIC-ONLY pattern)

The framework already stamps `⚠ STATIC-ONLY` when an app can't be booted (and the verifier must *try* to boot the whole stack itself first — `_smoke-test-policy` boot rule). The mobile/desktop legs inherit this exactly:

- Android: the verifier launches the emulator + Appium via the registry `launch` command itself (boot-it-yourself rule). Only if that genuinely fails → STATIC-ONLY for the Android head, with the real reason logged.
- iOS / Mac Catalyst: depend on the **Mac being on and reachable**. If `curl …/status` fails, that head is STATIC-ONLY with "Mac build host unreachable" — a session dependency, like "stack down" for AstroLyfe, **not** a faked `Verified`.

This keeps the "Verified = acceptance + data + visual" invariant honest per head: a mobile head is never marked `Verified` on visual grounds it couldn't observe.

## 8. Build is unchanged — this is a *runtime-observe* addendum

Important boundary: **builds already work** and don't change.

- Android still builds Windows-side via `cmd.exe` (ladder §B rung #4).
- iOS / Mac Catalyst still build on the paired Mac (ladder already documents this).

What's new is a **"runtime-observe" leg** appended to the build-invocation-ladder (a new §D, or a per-platform note): *after* a green build, how the verifier reaches the running UI to apply the gates. The build rungs stay exactly as written.

## 9. Networking specifics (the one fiddly bit, called out honestly)

- **WSL2 → Windows host (Android):** **Windows 11 mirrored networking is enabled** (owner decision) — add to `%UserProfile%\.wslconfig`:
  ```ini
  [wsl2]
  networkingMode=mirrored
  ```
  then `wsl --shutdown` once. With mirrored networking, `http://localhost:4723` reaches the Windows-host Appium directly in both directions — no host-IP lookup. (The §0b setup will include this as a one-time step; the `ip route`/host-IP fallback is documented only as a recovery path if a machine can't enable mirrored mode.)
- **WSL2 → LAN Mac (iOS/Catalyst):** straightforward LAN routing; just pin the Mac's IP via DHCP reservation so the registry URL is stable. Appium must bind `--address 0.0.0.0` (not `127.0.0.1`) to accept off-box connections.
- Appium servers should be firewall-allowed on port 4723 on each host.

## 10. Honest caveats

1. **Heavier than winrun.** Appium + drivers + an emulator/simulator is real setup. Keep it **opt-in per app** — only apps that actually ship a given head register that endpoint. Blazor-only apps are unaffected.
2. **iOS/Catalyst require the Mac to be up.** That's a session dependency, handled by STATIC-ONLY (§7). It is not "always-on" the way Playwright is.
3. **Emulator startup is slow** (tens of seconds to minutes cold). The `launch` helper should boot it once per session and reuse it; the verifier should poll `…/status` until ready rather than assume.
4. **Element-locator drift.** MAUI maps controls to native automation IDs; reliable Appium selectors need `AutomationId` set on key controls. Worth a coding-standards note so new screens are addressable (analogous to stable DOM ids for Playwright).
5. **We are deliberately NOT unifying the Windows head** onto Appium in this pass (owner scope). The Appium `windows` driver could later collapse FlaUI/Appium-Win/Android/iOS/Catalyst into one abstraction — noted as a future option, not done here.

## 11. Implementation plan (when approved — per the §7 maintenance contract)

Files that would change, all kept mirror-parity (`.tfcore/` → `.claude/commands/TechieFlow/` → `.opencode/command/TechieFlow/`, byte-identical):

| File | Change |
|------|--------|
| `WORKFLOW.html` | New **§0b** (device-host one-time setup, incl. the **mirrored-networking `.wslconfig` step**), extend **§11** (runtime: Android/iOS/Catalyst legs), update the §17 per-platform table + the §2 banned-excuse card. |
| `README.md` | Mirror the §0b / §11 / §17 changes. |
| `.tfcore/templates/v4custom/build-invocation-ladder.md` | New **§D "Runtime-observe leg"** (post-build, how the verifier reaches the running UI per head). Build rungs unchanged. |
| `.tfcore/tasks/verify-phase.md` | §4a/§4b: select Appium driver from the registry for MAUI mobile/desktop heads; STATIC-ONLY fallback per head. *(+ mirror ×2)* |
| `.tfcore/tasks/_smoke-test-policy.md` | Add Appium as an allowed driver + the new banned-excuse line + boot-the-emulator-yourself rule. *(+ mirror ×2)* |
| `.tfcore/tasks/devguide.md` | OBSERVE pass §5a can capture native screenshots via Appium for mobile/desktop screens. *(+ mirror ×2)* |
| `core-config.yaml` | New `runtimeVerification.appium` registry block (per app, opt-in) — Android/iOS/Catalyst endpoints. |
| `.tfcore/templates/v4custom/app-coding-standards-tmpl.md` (+ the two reference samples) | New **`AutomationId` rule**: key interactive/data controls on MAUI screens must carry a stable `AutomationId` (the native analogue of a stable DOM id for Playwright) so Appium selectors don't drift. |
| `.tfcore/agents/verifier.md` | Note the third render engine. *(+ mirror ×2)* |
| `WorkFlow-Context.md` | New dated §5 maintenance-log entry; update §6 if it opens an item. |
| Session memory | New memory file + `MEMORY.md` pointer (e.g. `mobile-runtime-bridge`). |

No `opencode.jsonc` change (no new command — this rides inside verify-phase/smoke). Templates aren't mirrored (loaded by relative path).

## 12. Decisions — RESOLVED (2026-06-29)

1. **Mac Catalyst desktop — INCLUDED.** Same LAN Mac, `mac2` Appium driver alongside `xcuitest`. Fills a real coverage gap (Catalyst had build-only today).
2. **Networking — Win11 mirrored networking ENABLED.** Android Appium endpoint is plain `localhost:4723`; §0b includes the one-time `.wslconfig` step. Host-IP fallback kept only as a recovery note.
3. **`AutomationId` coding standard — ADDED.** Key interactive/data controls carry a stable `AutomationId`; goes into the coding-standards template + reference samples (§11).
4. **Android device — EMULATOR default.** Real device via `adb connect` supported by the same path; not the default.

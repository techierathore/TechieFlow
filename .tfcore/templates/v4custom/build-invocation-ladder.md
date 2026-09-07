# Build invocation ladder

**Building, testing and running is a script since Sitting 4b (2026-09-05):** `bash .tfcore/utils/tf-build.sh [build|test|run] [<target>]`. It detects the host (macOS, native Linux, native Windows, WSL, OpenCode Docker), decides whether the target has a MAUI head, tries the invocation rungs in order (`dotnet`, `~/.dotnet/dotnet`, `winrun`, `cmd.exe /c dotnet`, `powershell.exe dotnet`), stops at the first that works, and prints one verdict line: `PASS … via <rung>`, `FAIL … real errors` (the code is wrong: fix it), or `NOT-RUN … tried: …` (the host is wrong: never a project blocker). `bash .tfcore/utils/tf-build.sh probe` prints the host and the rungs without building. The full output of every attempt is under `tests/.artifacts/build/`. Copy the verdict line into the status log row or the Remark.

Two facts the script cannot change: a MAUI iOS or Mac Catalyst head builds only on a Mac (prepare the source and the on-Mac commands; never substitute another head as "the" deliverable), and a workload missing on macOS is installed once with `sudo dotnet workload install <id>` by the owner.

## Reaching the running UI after a green build

A green build is half of a verify. The verifier, the DevGuide and every smoke drive the running UI to check that data shows and the screen looks right. The driver depends on the head; the build does not change:

| Head | Runtime driver | Where it runs |
|---|---|---|
| Blazor | headless Playwright (system Chromium) | WSL |
| MAUI Windows | FlaUI or Appium-Windows | Windows side |
| MAUI Android | Appium (`uiautomator2`) against the emulator or a device | Windows host runs the SDK and emulator; WSL drives it over HTTP |
| MAUI iOS | Appium (`xcuitest`) against the simulator | the LAN Mac; WSL drives it over HTTP |
| MAUI Mac Catalyst | Appium (`mac2`) against the running app | the LAN Mac; WSL drives it over HTTP |

Appium is the native analogue of Playwright: the same WebDriver protocol, a screenshot and an element tree with positions and text, so the checks are identical and only the driver differs.

- The endpoints are in `core-config.yaml → runtimeVerification.appium`, per app and opt-in. WSL needs only the HTTP URL.
- Android runs on the Windows host: the verifier boots the emulator and Appium itself through the registry `launch` command (through `winrun` if needed), then drives `http://localhost:4723`. Booting it yourself, never asking the owner, is the same rule as the build.
- iOS and Mac Catalyst need the LAN Mac up: `curl http://<mac>:4723/status` first; unreachable means that head is `⚠ STATIC-ONLY`, a session dependency like a stopped database, never a faked `Verified`.
- One-time host setup (Android SDK, AVD and Appium on Windows; Xcode, Appium, `xcuitest` and `mac2` on the Mac; the `.wslconfig` mirrored-networking switch): `WORKFLOW.html §0b`.
- Bind the driver to the app under test by identity, the PID you launched and its top-level window or the package or bundle id on mobile, and interact element by element through `AutomationId`. Never global keyboard or mouse injection, which lands in whichever window has focus. Full rules: `verify-phase.md §3b`.

**Dependent services are yours to start.** When the feature needs more than one process (a database, an API, a web front end, a model endpoint), a service that is down is something you start, not a blocker you hand to the owner. Read each dependent project's configuration for its port and URL, then start each one yourself in dependency order (data stores and endpoints first, then APIs, then the front end). Only when a service on another machine does not answer does that head degrade to `⚠ STATIC-ONLY`, and the report says which host and which probe.

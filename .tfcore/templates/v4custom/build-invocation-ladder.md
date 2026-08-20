# Build invocation ladder

When any task says "run `dotnet build`" / "run `dotnet test`" / "run `dotnet run`", **never accept "command not found" or "workload missing" as a stopping condition**. The right way to invoke `dotnet` depends on the host platform. **Detect the platform FIRST, then use that platform's ladder.**

## 0. Platform detection — do this ONCE per session, then cache it

Run a single probe to classify the host:

| Probe result | Platform | Ladder to use |
|---|---|---|
| `uname` → `Darwin` | **macOS** (Claude Code / OpenCode native, or via Terminal) | §A — dotnet in PATH, MAUI/iOS native via Xcode |
| `uname` → `Linux` **and** `/proc/version` contains `microsoft` / `WSL` | **WSL-on-Windows** (the reference machine) | §B — the WSL↔Windows interop ladder |
| `TF_OPENCODE_DOCKER=1` (or `uname` → `Linux`, no `microsoft` in `/proc/version`, and `/usr/local/bin/winrun` exists with `TF_WINDOWS_APP_PATH` set) | **OpenCode Docker on Windows** | §E — .NET in container, Windows head through SSH bridge |
| `uname` → `Linux`, no `microsoft` in `/proc/version`, and no Docker bridge | **native Linux** | §A (Linux notes) — standard .NET only; Windows/Apple heads are unavailable |
| `uname` not found / shell is `cmd`/`PowerShell`; paths look like `C:\…` | **native Windows** (Claude Code / OpenCode on Windows, not WSL) | §C — dotnet in PATH, MAUI native |

One-liner to detect: `uname -a 2>/dev/null || echo windows` — `Darwin…` = macOS, `…microsoft…`/`…WSL…` = WSL, plain `Linux` = native Linux, `windows` (uname absent) = native Windows.

> The §B WSL ladder below was the framework's original default because the owner's primary machine is WSL-on-Windows (`WORKFLOW.html §0`). It is **one platform's** ladder, not the universal one. A plain native Linux process has no Windows interop, but OpenCode Docker is a deliberate exception: when `/usr/local/bin/winrun` and `TF_WINDOWS_APP_PATH` are present, use §E and probe the SSH bridge. Never report `cmd.exe` missing inside the container; it is expected not to exist there.

---

## A. macOS / native Linux — `dotnet` is in `PATH`

→ **Start (and stay) at rung #1: `dotnet build`.** The .NET SDK installer puts `dotnet` on the `PATH`; there is no interop layer.

- **Non-MAUI projects** (Web, API, library, console, test): `dotnet build` / `dotnet test` / `dotnet run` directly.
- **MAUI on macOS:** builds natively once the workload + toolchains are installed — `sudo dotnet workload install maui`. **`sudo` is REQUIRED on macOS**: the SDK lives in root-owned `/usr/local/share/dotnet`, so any `dotnet workload install/update` (and SDK updates) without it fails with `Inadequate permissions. Run the command with elevated privileges.` — that error is a sudo signal, NEVER a project blocker. iOS / Mac Catalyst targets require **Xcode** (and `xcode-select --install`); Android targets require the **Android SDK + a JDK** (`sudo dotnet workload install maui-android`). With those present, `dotnet build -t:Run -f net9.0-maccatalyst` (or `-f net9.0-ios`) just works — no `cmd.exe`.
- **MAUI on native Linux:** this framework's Docker image installs no MAUI workloads. Windows MAUI Blazor Desktop uses §E; mobile/iOS/Mac Catalyst work belongs on a native Mac. Do not install or report `maui-tizen` as a Docker prerequisite.
- If `dotnet build` fails with `NETSDK1178` / "workload not installed", the fix is `dotnet workload install <id>` — with `sudo` on macOS (root-owned SDK dir; see above) — a one-time setup step the user runs, not a rung change; there is no other rung on this platform. If the user reports `Inadequate permissions` from a workload/SDK command, give them the exact `sudo` form of the same command.

---

## B. WSL-on-Windows (the reference machine) — WSL ↔ Windows interop ladder

The owner's machine is set up per `WORKFLOW.html §0` and has BOTH:

- **WSL-side .NET** at `/home/srkra/.dotnet/dotnet` (rung #2) — *replace with your own WSL dotnet path if different*. Compiles non-MAUI projects green.
- **Windows-side .NET** with full workloads — including MAUI / iOS / Android — reachable via `cmd.exe /c "dotnet …"` (rung #4) or the `winrun` bridge (rung #3). Compiles MAUI/iOS/Android workloads green.

Both are PERMANENT setups — you are NEVER reporting "MAUI cannot build on WSL" or "MAUI workloads missing" as a project blocker. Those are environment-config misunderstandings, not project issues. If a build fails because the workload isn't where you tried, you are on the wrong rung — switch rungs.

### The WSL ladder — try until one works

| # | Command | Works when |
|---|---------|------------|
| 1 | `dotnet build` | dotnet is in WSL `$PATH` (rare on this machine) |
| 2 | `~/.dotnet/dotnet build` (or `/home/srkra/.dotnet/dotnet build`) | dotnet is WSL-installed but not in PATH (the user's default — confirmed present) |
| 3 | `winrun "dotnet build"` | user's WSL→Windows helper at `/home/srkra/bin/winrun` |
| 4 | `cmd.exe /c "dotnet build"` | Windows-side .NET 10 (full workloads — MAUI, iOS, Android, etc.) — works for any `/mnt/c/...` project |
| 5 | `powershell.exe -Command "dotnet build"` | same as #4 with PowerShell |

Each candidate is a SINGLE bash command — no `for`/`if`/loops — so each matches the project's `.claude/settings.json` allow patterns (`Bash(dotnet *)`, `Bash(cmd.exe *)`, `Bash(powershell.exe *)`, `Bash(winrun *)`).

## How to PICK the right rung (§B / WSL only — READ THIS, most failures come from skipping it)

> The rest of this document (rung selection, symptom escalation, probe order, banned-blocker list) is **§B WSL-specific detail**. On macOS / native Windows / native Linux there is a single rung (`dotnet build`), so skip ahead to §C if you're on native Windows; macOS/Linux is fully covered by §A above.

The right starting rung depends on **what you are building**:

### A. Single .csproj — non-MAUI (Web, API, library, console, test project)
→ **Start at rung #2.** If it works, stay there for the session.

### B. Single .csproj — MAUI / iOS / Android / .NET MAUI Hybrid
Detect: `<UseMaui>true</UseMaui>`, `<TargetFramework>` contains `-android` / `-ios` / `-maccatalyst` / `-windows10`, or the SDK is `Microsoft.NET.Sdk.Maui`.
→ **Skip rungs #1–#2 entirely.** Start at rung #4 (or #3 if you prefer the `winrun` wrapper). MAUI workloads ONLY live on the Windows side per the user's setup.

### C. Solution / multi-project build (`.sln` or `.slnx`) — MIXED projects
**Do this BEFORE picking a rung.** Scan the solution file's project entries:

1. Read the `.sln` / `.slnx` file (use the `Read` tool — single call).
2. For each `<Project Path="…" />` (slnx) or `Project("…") = "…", "…\X.csproj"` line (sln), look at the .csproj path. Then quickly grep each `.csproj` for `<UseMaui>` or MAUI SDK references.
3. **If ANY project in the solution is MAUI/iOS/Android → the SOLUTION-level build needs the Windows side. Start at rung #4.** Do NOT try rung #2 on the slnx — it will fail with `NETSDK1178` or `Microsoft.iOS.Sdk missing` or similar workload errors, and that failure is a wasted attempt, not a project blocker.
4. **If NO project is MAUI** → start at rung #2.

### D. Per-project build to isolate a failure
If a solution-level build fails on the right rung, fall back to building each project individually:
- Non-MAUI projects (Web/API/library) on rung #2 (faster).
- MAUI/iOS/Android projects on rung #4.
- Aggregate the results in your status report. This isolates which projects compile clean and which have real code-level issues.

## Symptom-based auto-escalation (catch the wrong-rung-by-error pattern)

If a build fails with ANY of these errors, you are on the WRONG RUNG — escalate immediately, do NOT log it as a project blocker:

| Error code / message | Meaning | Action |
|---|---|---|
| `NETSDK1178` ("workload missing") | MAUI/iOS/Android workload not installed at the dotnet you're calling | Switch to rung #4 (`cmd.exe /c "dotnet build ..."`) |
| `Microsoft.iOS.Sdk` / `Microsoft.Android.Sdk` / `Microsoft.MacCatalyst.Sdk` missing | Same as above | Rung #4 |
| `error : Workload ID '...' not recognized` | Workload definition missing at the dotnet you're calling | Rung #4 |
| `error : Microsoft.WindowsAppSDK ... not found` | WinUI / WinAppSDK workload missing on WSL side | Rung #4 |
| `command not found: dotnet` | Wrong rung (not the right thing) | Next rung |
| Real C# compile errors (CS####), missing references in source code | This IS a project issue | Log as Known blocker; stay on the rung |

**Rule of thumb:** Workload/SDK errors → rung change. Source-code errors → project blocker.

## Probe order (optional, single commands)

If you want to detect availability before building (do this once per session, cache the result):

1. `ls /home/srkra/.dotnet/dotnet 2>/dev/null` — fastest WSL probe
2. `cmd.exe /c "where dotnet"` — fastest Windows probe (confirms rung #4 is available)
3. `cmd.exe /c "dotnet workload list"` — see which workloads Windows-side has (one-time check)

## Recording the result

After a successful build (any rung):
- `last_verified_build: PASS`
- `last_verified_date: {today YYYY-MM-DD}`
- Note which rung was used in the PROJECT-STATUS verification-log row or Remarks (e.g. `built via rung #4`).

After a failed build that's NOT a workload/wrong-rung issue (real CS#### errors):
- `last_verified_build: FAIL`
- `last_verified_date: {today YYYY-MM-DD}`
- Add to "Known blockers" with one-line error summary AND which rung was used.

After all rungs genuinely failed (probed all 5, none could find dotnet at all):
- `last_verified_build: not-run`
- `last_verified_date: {today YYYY-MM-DD}`
- Add to "Known blockers": "Tried ladder rungs 1-5; no dotnet found in WSL PATH, ~/.dotnet/, winrun, cmd.exe, or powershell.exe. User needs to install .NET SDK or expose it to WSL PATH."

## What NEVER goes into Known blockers (banned escape-hatch entries)

These are NOT blockers — they are signals you used the wrong rung. If you find yourself writing one, you skipped this doc:

- ❌ "MAUI build cannot run on WSL"
- ❌ "Microsoft.iOS.Sdk workload missing"
- ❌ "Microsoft.Android.Sdk workload missing"
- ❌ "NETSDK1178 — workload not installed"
- ❌ "WSL doesn't have the MAUI workload"
- ❌ "dotnet not in PATH"
- ❌ Anything that boils down to "I tried the wrong rung and it failed"

The user has the bridge set up. Their projects build green on the right rung. Document what RUNG produced the working build, not what failed on the wrong one.

## What NOT to do

- Do NOT report `last_verified_build: not-run` because rung #1 failed. That is a lazy escape. Try rungs 2-5 first.
- Do NOT wrap the probe in `if [ -x ... ]; then ... else ... fi` — that triggers a permission prompt. Run probes as plain single commands.
- Do NOT log workload-missing / NETSDK1178 / wrong-rung errors as "Known blockers". They are wrong-rung errors. Switch and retry.
- Do NOT claim ".NET is unavailable on this system" unless ALL five rungs failed AND your probe commands also failed. Even then, report which rungs you tried verbatim.
- **Do NOT let a host limitation cancel a cross-OS deliverable.** A MAUI Mac Catalyst / iOS head genuinely cannot be built from Windows/WSL (`-r osx-arm64` only cross-compiles *plain* .NET — a Catalyst `.app` needs Xcode's toolchain, macOS only; `NETSDK1005`/`NETSDK1139`/a maccatalyst TFM guarded by `IsOSPlatform('OSX')` is that fact surfacing, not a failure). That is a **rung-selection fact, never a reason to drop the native head, declare it impossible, or quietly substitute another head** (e.g. a web-head publish) as "the" deliverable. The app's BuildAndRun guide documents the owner-run on-Mac path — prepare the source + the exact on-Mac commands, state plainly "the Catalyst `.app` is built on the Mac per the guide §<n> (one command, owner-run)", and treat any substitute you can build locally as a *complement*, offered alongside, never a silent replacement.

---

## C. Native Windows (Claude Code / OpenCode running on Windows, not inside WSL)

→ **Use rung #1: `dotnet build`.** You are already on the Windows side, so there is no interop bridge — `cmd.exe`/`winrun`/`/home/...` from §B do NOT apply.

- **Non-MAUI** projects: `dotnet build` / `dotnet test` / `dotnet run` directly.
- **MAUI**: builds natively here. Windows (`net9.0-windows10…`) and Android heads build directly once `dotnet workload install maui` has been run. **iOS / Mac Catalyst heads require a paired Mac** (Apple's toolchain only runs on macOS) — building those from Windows needs a Mac build host; absence of one is a genuine platform limitation, not a wrong-rung error.
- Paths in commands use the project's actual location (e.g. `C:\src\App\App.sln`). Single commands, no `if/for` wrappers (same permission-prompt reason as §B).
- `NETSDK1178` / "workload not installed" → run `dotnet workload install <id>` once; there is no alternate rung to switch to.

## D. Runtime-observe leg — reaching the RUNNING UI after a green build

Building is only half of "verify". Once a head builds green, the verifier / devguide OBSERVE / smoke gates must **drive the running UI** to apply the data-render (§4a) and visual-truth (§4b) gates. The driver depends on the head — this is the runtime counterpart to the build rungs above, and it does NOT change how anything builds:

| Head | Build (above) | **Runtime driver** | Where it runs |
|------|---------------|--------------------|---------------|
| Blazor | rung #1/#2 | headless **Playwright** (system Chromium) | WSL |
| MAUI **Windows** | §B rung #4 / §C native | **FlaUI / Appium-Windows** | Windows side |
| MAUI **Android** | §B rung #4 / §A/§C native | **Appium** (`uiautomator2`) → emulator/device | Windows host (SDK + emulator); WSL drives over HTTP |
| MAUI **iOS** | paired Mac (Xcode) | **Appium** (`xcuitest`) → iOS Simulator | LAN Mac; WSL drives over HTTP |
| MAUI **Mac Catalyst** | paired Mac (Xcode) | **Appium** (`mac2`) → the running .app | LAN Mac; WSL drives over HTTP |

**Appium is the native analogue of Playwright** — same WebDriver protocol, returns a `base64` screenshot (visual-truth) + an element tree with `rect`/text (data-render). So the gates' assertions are identical; only the driver differs.

- The endpoints live in `core-config.yaml → runtimeVerification.appium` (per app, opt-in). The WSL side needs only the **HTTP url** — no `adb`, emulator, or Xcode inside WSL.
- **Android** runs entirely on the Windows host; the verifier boots the emulator + Appium itself via the registry `launch` command (you may launch it through `winrun`), then drives it over `http://localhost:4723` (Win11 mirrored networking) — booting it yourself, never asking the owner, is the same rule as the build ladder.
- **iOS / Mac Catalyst** depend on the **LAN Mac being up**. `curl http://<mac>:4723/status` first; if unreachable, that head degrades to `⚠ STATIC-ONLY` (a session dependency, like "stack down"), never a faked `Verified`.
- One-time host setup (Android SDK + AVD + Appium on Windows; Xcode + Appium + xcuitest/mac2 on the Mac; the `.wslconfig` mirrored-networking switch) is **`WORKFLOW.html §0b`**.
- **Input discipline (all native heads, esp. MAUI Windows):** bind the driver to the app under test by identity — the **PID you launched → its top-level window handle** (Appium Windows `appium:appTopLevelWindow` / FlaUI `Application.Attach(pid)`) or the app **package/bundle id** on mobile — and interact **element-by-element via `AutomationId`** inside that bound window. NEVER global keyboard/mouse injection (FlaUI `Keyboard.Type`, coordinate clicks, `SendKeys`): it lands in whatever window has focus, not the app. Full rules: `verify-phase.md §3b`.

## E. OpenCode Docker on Windows — host bridge

> **FALLBACK ONLY (since 2026-08-20).** OpenCode's primary deployment is native WSL — the same distro as Claude Code, using the §B ladder like any other WSL process (`docs/OpenCode-Deployment-Guide.md`). This section applies only when the Docker container is deliberately in use (`TF_OPENCODE_DOCKER=1`); nothing here concerns a WSL OpenCode session.

An OpenCode Linux container is not WSL: `/proc/version` does not expose Windows interop, and `cmd.exe` cannot be installed into it. The framework Dockerfile uses the .NET 10 SDK and deliberately installs no MAUI workloads. Standard .NET projects build and test in the container. For a Windows MAUI Blazor Desktop target, use the image's `winrun` wrapper, which sends the command over SSH to the Windows host and starts it in `TF_WINDOWS_APP_PATH`. Mobile/iOS/Mac Catalyst builds and runtime tests belong on a native Mac.

- Probe: `test -x /usr/local/bin/winrun && test -n "$TF_WINDOWS_SSH_USER" && test -n "$TF_WINDOWS_APP_PATH"` followed by `winrun "dotnet --info"`. The first checks configuration; the second proves the SSH bridge actually works. The Docker launcher may mount `/root/.ssh` read-only; `winrun` copies the key to a writable `/tmp` file with mode `0600` and maintains host trust in `/tmp`, so do not attempt to `chmod` the mounted key.
- Build: `winrun "dotnet build -c Release"`.
- Do not report missing `cmd.exe` as a code blocker when the bridge probe succeeds.
- Do not check for or install `maui-tizen` in the container. The image intentionally contains no MAUI workloads.
- If the bridge is absent or SSH fails, report the exact setup failure and mark only the Windows head `STATIC-ONLY`; continue Linux-compatible builds and Appium HTTP verification.
- For private feeds, use the Docker-specific user config mounted at `/root/.nuget/NuGet/NuGet.Config`. A Windows `%AppData%\NuGet\NuGet.Config` may contain DPAPI-encrypted credentials that cannot be decrypted in Linux. Never put the Docker config in the repository.

## Recording the result (all platforms)

After a successful build, note **which platform + invocation** produced it (e.g. "built on macOS via `dotnet build` (rung #1)", "built on WSL via `cmd.exe /c` (rung #4)") in the PROJECT-STATUS verification-log row or Remarks — so a reader on a different machine knows what to expect. The §B "what NEVER goes into Known blockers" list applies to WSL specifically; on §A/§C the equivalent non-blocker is "workload not yet installed — run `dotnet workload install`", which is a one-time user setup step, not a project defect.

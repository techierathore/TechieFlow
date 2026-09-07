# TechieFlow — Machine setup

| | |
|---|---|
| Purpose | Everything you install once per machine before the framework can build, run and see your applications: WSL, macOS, the device hosts for mobile heads, how MAUI is built from each host, and what changes on native Windows or Linux. |
| Audience | The owner, and anyone setting up a new machine. |
| Status | Moved out of `README.md` on 2026-09-07 (Session 6 of the reset), unedited. The sections keep their old numbers so older links still make sense. |
| Companion | `README.md` (start there), `docs/TechieFlow-Permissions-And-YOLO.md`, `docs/TechieFlow-FAQ.md`. |

Do the one section that matches your machine. Nothing here is needed twice.

---

## 0. WSL bootstrap — DO ONCE, EVER

Library persona source files and their NuGet deployment paths are documented
in [`docs/TechieFlow-Library-Persona-Propagation.md`](docs/TechieFlow-Library-Persona-Propagation.md).

**Run this once per WSL distro.** Installs headless-Chromium system libs + the MAUI bridge.

> **On macOS: skip this section — your one-time setup is §0a instead.** There is no `winrun` bridge on a Mac (`dotnet` and MAUI run natively) and Playwright's Chromium needs no apt libraries.

```bash
sudo apt-get update && sudo apt-get install -y \
  libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 \
  libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 \
  libcairo2 libasound2 libgtk-3-0 libx11-xcb1

mkdir -p ~/bin && cat > ~/bin/winrun << 'SH'
#!/usr/bin/env bash
WINPATH=$(wslpath -w "$PWD")
powershell.exe -NoProfile -Command "cd '$WINPATH'; $*"
SH
chmod +x ~/bin/winrun
grep -q 'HOME/bin' ~/.bashrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
```

### OpenCode in WSL — the primary path (same distro as Claude Code)

Since 2026-08-20 OpenCode runs **natively inside the same WSL distro as Claude Code** (OpenCode's own docs recommend WSL over native Windows; full rationale, probe evidence, and the crash playbook are in `docs/OpenCode-Deployment-Guide.md`). It gets the entire runtime harness above — `winrun`, headless Chromium, Appium — for free, with no SSH bridge and no second NuGet config.

```bash
curl -fsSL https://opencode.ai/install | bash
grep -q '.opencode/bin' ~/.bashrc || echo 'export PATH="$HOME/.opencode/bin:$PATH"' >> ~/.bashrc
opencode auth login     # or copy a portable API-key entry into ~/.local/share/opencode/auth.json
```

The PATH line matters: WSL's Windows-interop otherwise resolves `opencode` to the Windows npm shim (`AppData\Roaming\npm\opencode`) — the native-Windows Bun build that breaks on large repos. Verify with `type -a opencode` (the `~/.opencode/bin` entry must come first) and `opencode --version`.

The framework side needs no manual setup: `scaffold-*.sh` / `update-framework.sh` deploy `.opencode/plugin/techieflow.js` (the guard bridge — the same `.tfcore/hooks/` guards Claude Code runs: git ban, PROJECT-STATUS shape, Verified ledger — plus telemetry with real dollar cost into `docs/metrics/sessions.jsonl`) and a framework-owned `.opencode/opencode.jsonc` into every app. Check with `opencode agent list` in the app (the six TechieFlow agents must appear).

**Large repos:** the failure historically blamed on Bun is a `/mnt/c` (9p filesystem) pathology — OpenCode's snapshot walk can take minutes there while the identical repo on WSL-native ext4 (`~/`) boots in seconds. Typical TechieFlow apps on `/mnt/c` are fine; genuinely large repos belong on ext4, or see the watcher/snapshot tuning in `docs/OpenCode-Deployment-Guide.md` §6.

### OpenCode in Docker on Windows — FALLBACK ONLY

> **Since 2026-08-20 this path is a fallback**, kept in case the WSL path ever reproduces the native-Windows crash. Use the WSL section above; nothing below is needed for it.

A Linux container cannot execute `cmd.exe`. `docs/Dockerfile` uses the Debian .NET 10 SDK image and deliberately installs no MAUI workloads. Standard .NET apps build and test inside the container. Windows MAUI Blazor Desktop builds use the image's SSH-backed `/usr/local/bin/winrun` wrapper and run on the Windows host. Mobile, iOS, and Mac Catalyst builds and runtime tests should run natively on a Mac. This bridge is only needed for Windows-host builds. The first command uses Windows Update and can take several minutes, but it should not remain at `Operation [Running]` indefinitely. Run the following capability, service, and firewall commands separately in an **elevated PowerShell** window:

```powershell
$cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
$cap.State
if ($cap.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
if (-not (Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName "OpenSSH Server (sshd)" -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
}
```

When the capability reports `Installed`, open a **normal PowerShell** window as the Windows account that will run Docker. Copy and paste this key setup as one complete line; it is safe to run again:

```powershell
$ssh="$env:USERPROFILE\.ssh"; New-Item -ItemType Directory -Force $ssh | Out-Null; if (-not (Test-Path "$ssh\opencode-docker")) { ssh-keygen -t ed25519 -f "$ssh\opencode-docker" -N "" }; $publicKey=(Get-Content "$ssh\opencode-docker.pub" -Raw).Trim(); $auth="$ssh\authorized_keys"; if (-not (Test-Path $auth)) { Set-Content -Path $auth -Value $publicKey } elseif ((Get-Content $auth) -notcontains $publicKey) { Add-Content -Path $auth -Value $publicKey }
```

Verify the bridge before starting Docker. This test disables password fallback. A successful test prints the Windows host's `.NET` information and never asks for a password:

```powershell
ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -i "$env:USERPROFILE\.ssh\opencode-docker" "$env:USERNAME@localhost" powershell.exe -NoProfile -NonInteractive -Command "dotnet --info"
```

If `Add-WindowsCapability` stays at `Operation [Running]` for about 10 minutes, press `Ctrl+C`; the later commands have not run. Check `Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0` and the `Microsoft-Windows-DISM/Operational` event log, or install **OpenSSH Server** through Settings > System > Optional features > View features. Retry only after the capability reports `Installed`.

Keep `Dockerfile` and `opencode-docker.cmd` in `%USERPROFILE%\.opencode-docker-config`. Build the image once from that folder:

```powershell
Set-Location "$env:USERPROFILE\.opencode-docker-config"
docker build --pull --no-cache -t my-opencode-dotnet .
```

Put that folder on `PATH`. From any application folder, run `opencode-docker.cmd`; it uses the existing `my-opencode-dotnet` image and mounts the host NuGet and SSH directories:

```powershell
docker run --rm -it `
  -v "${USERPROFILE}\.opencode-docker\nuget:/root/.nuget/NuGet:ro" `
  -v "${USERPROFILE}\.ssh:/root/.ssh:ro" `
  -v "${PWD}:/workspace" -w /workspace `
  -e TF_WINDOWS_SSH_HOST=host.docker.internal `
  -e TF_WINDOWS_SSH_USER="$env:USERNAME" `
  -e TF_WINDOWS_SSH_KEY=/root/.ssh/opencode-docker `
  -e TF_WINDOWS_APP_PATH="C:\path\to\app" `
  -e TF_OPENCODE_DOCKER=1 `
  my-opencode-dotnet opencode
```

Use `dotnet build` for Linux-compatible projects and `winrun "dotnet build -c Release"` for the Windows head. The container is not WSL; if the SSH bridge is unavailable, only the Windows head is `STATIC-ONLY`.

The SSH directory is intentionally mounted read-only. Docker Desktop can expose the mounted private key with Linux mode `0777`, which OpenSSH rejects, and the mounted directory cannot accept a new `known_hosts` file. The image's `winrun` wrapper copies the key to writable `/tmp/opencode-docker/opencode-docker` with mode `0600` and creates its writable host-trust file there. Do not try to repair the mounted file from inside the container.

If the test reports `Permission denied (publickey)`, do not enter the VPS password or Windows password. Because the generated key has no passphrase, this means public-key authentication was rejected. If `whoami /groups | Select-String 'S-1-5-32-544'` prints a result, the account is an Administrator and Windows OpenSSH uses `%ProgramData%\ssh\administrators_authorized_keys` rather than the profile `authorized_keys` file. Add the same public key there from elevated PowerShell and apply `icacls` permissions, as shown in the OpenSSH documentation.

### NuGet credentials

Keep GitHub Packages credentials out of the repository. Native Windows uses `%AppData%\NuGet\NuGet.Config`; macOS/Linux uses `$HOME/.nuget/NuGet/NuGet.Config`. Docker uses the separate user-level `%USERPROFILE%\.opencode-docker\nuget\NuGet.Config`, mounted read-only by `opencode-docker.cmd`. Do not mount the normal Windows config for private feeds: its password may be DPAPI-encrypted and therefore unusable inside Linux. Create the Docker config with a Linux-readable credential, for example:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.opencode-docker\nuget" | Out-Null
dotnet nuget add source "https://nuget.pkg.github.com/OWNER/index.json" --name github --username GITHUB_USER --password GITHUB_TOKEN --store-password-in-clear-text --configfile "$env:USERPROFILE\.opencode-docker\nuget\NuGet.Config"
```

Replace the placeholders with the package owner's values. The token is stored only in the user profile, not the repository. A project `nuget.config` may provide source mapping but must contain no PAT.

## 0a. macOS bootstrap — DO ONCE, EVER

**Run this once per Mac.** The native equivalent of §0: everything the agents need to build, run, and *see* your apps on macOS. There is no `winrun` bridge to install — `dotnet`, Playwright, and Appium all run natively — but the machine still needs its toolchain once.

```bash
# 1. Xcode Command Line Tools — provides git AND python3 (the framework's
#    guard-status/guard-verify hooks silently fail open without python3)
xcode-select --install

# If full Xcode is installed (required for MAUI iOS / Mac Catalyst builds),
# accept its license once or python3/git error out with a license prompt:
sudo xcodebuild -license accept

# 2. Homebrew (skip if `brew --version` already works)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. The toolchain: .NET SDK + Node.js (Node powers Playwright and Appium)
brew install dotnet-sdk node

# 4. MAUI workload — only if any of your apps ships a MAUI head.
#    sudo is REQUIRED on macOS: the SDK lives in root-owned /usr/local/share/dotnet,
#    so without it this (and any `dotnet workload update` / SDK update) fails with
#    "Inadequate permissions. Run the command with elevated privileges."
sudo dotnet workload install maui
```

**Playwright — nothing for you to do.** The verifier **self-provisions** it per project the first time it runs (`verify-phase.md §1`, also used by every self-smoke): it creates `package.json` if missing, runs `npm install -D @playwright/test` + `npx playwright install chromium`, and writes a minimal `playwright.config.ts`. The only machine-level prerequisite is **Node** (step 3 above). The Chromium download is cached once under `~/Library/Caches/ms-playwright` and shared by every project, so only the first project ever pays it — and unlike WSL there are no system libraries to install.

**Verify:** `dotnet --info` prints an SDK, `node --version` answers, and `python3 --version` answers *without* an Xcode-license error. The agents handle everything else per project.

**MAUI native-UI testing** (Android emulator / iOS Simulator / Mac Catalyst): continue with §0b — on a Mac-native setup every piece of it (Android Studio + emulator, Appium + drivers, the Simulator) runs on this same machine, and all endpoints are `http://localhost:4723`.

## 0b. Device-host bootstrap (MAUI Android / iOS / Mac Catalyst) — DO ONCE PER HOST

Only needed for apps that ship a MAUI **mobile or Mac desktop** head. It lets the verifier (and the smoke / devguide-OBSERVE gates) **drive the running native UI** and apply the same data-render + visual-truth gates it applies to Blazor — closing the blind spot where a MAUI app passes every gate while its screens overlap, clip, or render blank. The driver is **Appium** (the native analogue of headless Playwright: same WebDriver protocol, returns a screenshot + an element tree). The WSL side only talks to an **HTTP endpoint** — no `adb`, emulator, or Xcode inside WSL. Builds are unchanged (§9 ladder); this is the *runtime-observe* leg.

**Step 1 — enable Win11 mirrored networking** (once) so WSL reaches the Windows-host Appium on plain `localhost`. In `%UserProfile%\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

then `wsl --shutdown` and reopen WSL.

**Step 2 — Android, on the Windows host** (Android SDK already present):

```powershell
sdkmanager "system-images;android-34;google_apis;x86_64"
avdmanager create avd -n Pixel_API_34 -k "system-images;android-34;google_apis;x86_64"
npm install -g appium
appium driver install uiautomator2
# session helper (start-android-verify.ps1) boots the emulator + Appium the verifier calls itself
```

**Step 3 — iOS + Mac Catalyst, on a Mac on the same LAN** (also your iOS build host — Xcode + .NET + `dotnet workload install maui` already there); give it a stable IP:

```bash
npm install -g appium
appium driver install xcuitest      # iOS Simulator
appium driver install mac2          # Mac Catalyst desktop
appium --address 0.0.0.0 --port 4723
```

**Step 4 — register the endpoints per app** in `core-config.yaml → runtimeVerification.appium` (only the heads that app ships). The verifier auto-discovers them; an absent/unreachable endpoint degrades that head to `⚠ STATIC-ONLY`, never a faked pass.

**WSL-on-Windows setup (Android on this PC, Apple on the LAN Mac):**

```yaml
runtimeVerification:
  appium:
    android:     { url: http://localhost:4723, avd: Pixel_API_34, launch: 'winrun "powershell -File start-android-verify.ps1"' }
    ios:         { url: http://192.168.1.50:4723, simulator: "iPhone 15" }
    maccatalyst: { url: http://192.168.1.50:4723 }
```

**macOS-native setup (everything on this Mac — no winrun, no LAN address):**

```yaml
runtimeVerification:
  appium:
    android:     { url: http://localhost:4723, avd: Pixel_API_34 }
    ios:         { url: http://localhost:4723, simulator: "iPhone 15" }
    maccatalyst: { url: http://localhost:4723 }
```

**Running Claude Code natively on a Mac?** Everything above collapses onto the one machine: do Step 3 (and Step 2's Android pieces if needed) in the Mac's own Terminal, skip Step 1 (mirrored networking) entirely, and use `http://localhost:4723` for every head.

**Verify:** from WSL, `curl http://localhost:4723/status` (Android) and `curl http://<mac-ip>:4723/status` (iOS/Catalyst); on a Mac-native setup it's `curl http://localhost:4723/status` for everything. Reliable selectors need a stable `AutomationId` on key controls (a coding standard — see §10).

## 11. MAUI builds & runs — from WSL (bridged) or macOS (native)

**WSL (Windows) — bridge every dotnet call to the Windows side via `winrun` (§0):**

```bash
cd /mnt/c/path/to/maui-project
winrun "dotnet build -c Release"
winrun "dotnet test"
winrun "dotnet build -t:Run -f net9.0-windows10.0.19041.0"
```

**macOS — no bridge; dotnet runs natively (ladder §A):**

```bash
cd /path/to/maui-project
dotnet build -c Release
dotnet test
dotnet build -t:Run -f net9.0-maccatalyst      # desktop head on Mac = Mac Catalyst
dotnet build -t:Run -f net9.0-android          # Android head (emulator via Android Studio)
```

On macOS the Windows head (`net9.0-windows…`) can't build — the Mac desktop head is **Mac Catalyst**, and iOS builds natively too (Xcode required, §16). The `winrun` lines apply only inside WSL.

For verifier on a MAUI **Windows** app: *"This is a MAUI Windows app. Build/run/test via `winrun`. UI automation: FlaUI or Appium-Windows-driver Windows-side, NOT Playwright. Output evidence the same as Blazor projects."* On a Mac the equivalent prompt names the **Catalyst** head and the local `mac2` Appium driver instead.

### Mobile & Mac-desktop heads — runtime-observe over Appium

The §4a data-render and §4b visual-truth gates reach the MAUI **Android / iOS / Mac Catalyst** heads through an **Appium** WebDriver endpoint — the native analogue of Playwright (same screenshot + element-tree evidence, so the gates run unchanged). One-time host setup is §0b; the per-head driver map lives in `build-invocation-ladder.md §D`. **Builds don't change** — on WSL, Android still builds via `cmd.exe` (ladder rung #4) and iOS/Catalyst on the paired Mac; on a Mac-native setup all three build locally with plain `dotnet build` and the Appium endpoints are all `localhost`. This is purely how the verifier reaches the *running* UI after a green build.

| Head | Where it runs (WSL setup) | Appium driver | WSL reaches it via | macOS-native reaches it via |
|------|---------------|---------------|--------------------|------------------------------|
| MAUI Android | emulator on the Windows host (Android SDK) | `uiautomator2` | `http://localhost:4723` (mirrored networking); verifier boots emulator + Appium itself | `http://localhost:4723` — emulator + Appium run on the Mac itself |
| MAUI iOS | Simulator on a LAN Mac | `xcuitest` | `http://<mac-ip>:4723`; Mac must be up or head is `⚠ STATIC-ONLY` | `http://localhost:4723` — local Simulator (Xcode) |
| MAUI Mac Catalyst | the same LAN Mac (desktop .app) | `mac2` | `http://<mac-ip>:4723` | `http://localhost:4723` — the .app runs right here |
| MAUI Windows | Windows side | FlaUI / Appium-Windows (unchanged) | `winrun` / `cmd.exe` | n/a — this head doesn't exist on a Mac |

Selectors target each control's `AutomationId` (a coding standard, §10). A head with no registered endpoint in `core-config.yaml → runtimeVerification.appium`, or an unreachable host, is stamped `⚠ STATIC-ONLY` for that head — never a faked `Verified`.

**Window binding & input discipline (all native heads, especially MAUI Windows):** the driver session is bound to the app under test *by identity* — the PID the agent launched → that process's top-level window handle (Appium Windows `appium:appTopLevelWindow` / FlaUI `Application.Attach(pid)`), or the app package/bundle id on mobile — and every interaction is **element-scoped via `AutomationId` inside that bound window**, with focus verified before input and handles re-resolved after dialogs. Global keyboard/mouse injection (FlaUI `Keyboard.Type`, coordinate clicks, `SendKeys`) is **banned**: it types into whatever window happens to hold focus — historically, a completely different window than the app. Full rules: `verify-phase.md §3b`.

## 16. Running on macOS / native Windows / Linux

TechieFlow was authored on the owner's **WSL-on-Windows** machine, so §0/§11 and the build-invocation ladder describe that setup. The framework itself is **portable** — agents, tasks, templates, and `/TechieFlow:*` slash-commands are plain Markdown and run identically under Claude Code / OpenCode on **macOS, native Windows, or native Linux**. Only two things are environment-specific: how `dotnet` is invoked, and the runtime-verification bridges (headless Playwright for Blazor; the §0b Appium endpoints for MAUI Android/iOS/Mac-Catalyst; FlaUI/Appium-Windows for the MAUI Windows head).

**Same everywhere:** the `scaffold-*.sh` / `update-framework.sh` scripts (bash + `rsync` + `realpath`), all slash commands, the day-1 → split → build → verify → handoff flow, every template, and the permission model. On native Windows run the bash scripts from **WSL or Git Bash**.

| Concern | WSL-on-Windows | macOS | native Windows | native Linux |
|---|---|---|---|---|
| `dotnet` | ladder §B (`~/.dotnet/dotnet`, `cmd.exe`, `winrun`) | **§A: `dotnet build`** | **§C: `dotnet build`** | **§A: `dotnet build`** |
| MAUI iOS / Mac Catalyst | Windows side via `cmd.exe` | native (Xcode + `sudo dotnet workload install maui`) | needs paired Mac | not supported |
| MAUI Android | Windows side | native (Android SDK + JDK) | native | native |
| MAUI Windows head | Windows side | not supported | native | not supported |
| Native UI verification (Android/iOS/Catalyst) | Appium endpoints (§0b): Android on Windows host, iOS/Catalyst on a LAN Mac | local Appium (all native) | local Appium (Android+Catalyst); iOS via paired Mac | local Appium (Android only) |

The build ladder (`.tfcore/templates/v4custom/build-invocation-ladder.md`) auto-detects the host (`uname -a` → `Darwin` = macOS, `…microsoft…` = WSL, plain `Linux` = native Linux, absent = native Windows) and picks §A/§B/§C. On macOS/Windows/Linux there is one rung — `dotnet build` — and a missing workload is a one-time `dotnet workload install maui` (on macOS with `sudo`: the SDK dir `/usr/local/share/dotnet` is root-owned, and without it workload/SDK updates fail with *"Inadequate permissions. Run the command with elevated privileges."*), never a project blocker. Running the scaffold scripts needs `bash` + `rsync` + `realpath` (preinstalled on macOS 12.3+ and Linux; on native Windows run them from **WSL or Git Bash**).

**macOS quick start:**
1. Run the one-time **§0a macOS bootstrap** — Xcode CLT/license, Homebrew, .NET SDK + Node, Playwright per project; `sudo dotnet workload install maui` (sudo required on macOS) + Xcode / Android SDK only for MAUI apps.
2. Scaffold: `/path/to/TechieFlow/scaffold-brownfield.sh /path/to/your-app` (or `scaffold-greenfield.sh`).
3. Start Claude Code in the app folder: `/TechieFlow:agents:analyst *day1-brownfield <AppName>` — identical to WSL. The `winrun`/`cmd.exe` rungs don't apply once `uname` reports `Darwin`.

**Moving an existing project (or this framework repo) from Windows/WSL to a Mac:**
1. **Can't see `.tfcore/`, `.claude/`, `.opencode/` in Finder?** Finder hides dot-files by default. Press **Cmd+Shift+.** in any Finder window to toggle them on (the setting sticks), or run `defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder`. The Terminal always sees them: `ls -la`. Nothing is missing just because Finder doesn't show it — check with `ls -la` first.
2. **Moved an APP repo via git (clone/pull)?** Then the framework folders genuinely AREN'T there — every deployed framework copy (`.tfcore/`, `.claude/`, `.opencode/`, `/CLAUDE.md`, `/opencode.jsonc`) is *gitignored by design* (they're copies; this repo is the source of truth). Re-deploy them: `ls -la` the app — if `.tfcore/` exists, run `/path/to/TechieFlow/update-framework.sh /path/to/app`; if it's absent, run `/path/to/TechieFlow/scaffold-brownfield.sh /path/to/app` (safe on an app with existing docs/code — it uses `--ignore-existing` and never touches `src/`, `docs/`, or tests). Add `--dry-run` to `update-framework.sh` to preview.
3. **Per-project gitignored files don't come back from a scaffold.** `CLAUDE.md`, `.tfcore/core-config.yaml` customizations, and `.claude/settings.local.json` are per-project work product that git never carried. A plain *folder copy* from the old machine keeps them; a git clone loses them — copy them over from the Windows machine, or regenerate (`CLAUDE.md` comes back via day-1 / `*refresh-status`).
4. **Scripts won't execute (`permission denied`)?** A copy through a Windows filesystem drops the executable bit. Fix once: `chmod +x /path/to/TechieFlow/*.sh /path/to/TechieFlow/.tfcore/hooks/*.sh` (or run them as `bash script.sh`). Hooks inside apps are invoked via `bash` so they don't need it, but the same `chmod` doesn't hurt.
5. **No path edits needed:** since 2026-07-11 the three scripts locate the framework from their own directory (no hardcoded `/mnt/c/…`), and they run fine on macOS's stock `bash`/`rsync`.
6. **Afterwards, restart Claude Code** in the app folder so the freshly deployed agent/task definitions and `settings.json` load.

**native Windows quick start (Claude Code / OpenCode on Windows, not WSL):**
1. Install the .NET SDK (winget / official installer); confirm `dotnet --info`.
2. For MAUI: `dotnet workload install maui`. Windows + Android heads build natively; **iOS / Mac Catalyst need a paired Mac build host**.
3. Run the scaffold scripts from **WSL or Git Bash**, then drive the framework from Claude Code on Windows — the ladder uses §C (`dotnet build`).

**native Linux quick start:** install the .NET SDK; MAUI supports the **Android** head only (iOS / Mac Catalyst / Windows heads can't build without their toolchains — a genuine platform limit). Scaffold and run exactly as on macOS (ladder §A).

The framework never *requires* MAUI — many apps are Blazor-only and build with plain `dotnet build` everywhere. The full per-platform `dotnet` detail lives in `.tfcore/templates/v4custom/build-invocation-ladder.md`.

---


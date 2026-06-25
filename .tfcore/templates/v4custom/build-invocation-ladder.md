# Build invocation ladder

When any task says "run `dotnet build`" / "run `dotnet test`" / "run `dotnet run`", **never accept "command not found" or "workload missing" as a stopping condition**. The right way to invoke `dotnet` depends on the host platform. **Detect the platform FIRST, then use that platform's ladder.**

## 0. Platform detection — do this ONCE per session, then cache it

Run a single probe to classify the host:

| Probe result | Platform | Ladder to use |
|---|---|---|
| `uname` → `Darwin` | **macOS** (Claude Code / OpenCode native, or via Terminal) | §A — dotnet in PATH, MAUI/iOS native via Xcode |
| `uname` → `Linux` **and** `/proc/version` contains `microsoft` / `WSL` | **WSL-on-Windows** (the reference machine) | §B — the WSL↔Windows interop ladder |
| `uname` → `Linux`, no `microsoft` in `/proc/version` | **native Linux** | §A (Linux notes) — dotnet in PATH, Android-only MAUI |
| `uname` not found / shell is `cmd`/`PowerShell`; paths look like `C:\…` | **native Windows** (Claude Code / OpenCode on Windows, not WSL) | §C — dotnet in PATH, MAUI native |

One-liner to detect: `uname -a 2>/dev/null || echo windows` — `Darwin…` = macOS, `…microsoft…`/`…WSL…` = WSL, plain `Linux` = native Linux, `windows` (uname absent) = native Windows.

> The §B WSL ladder below was the framework's original default because the owner's primary machine is WSL-on-Windows (`WORKFLOW.html §0`). It is **one platform's** ladder, not the universal one. On macOS / native Windows / native Linux, `dotnet` is on the `PATH` and there is **no WSL→Windows interop** — `cmd.exe`, `winrun`, and `/home/srkra/.dotnet/` do **not** exist there. Use §A/§C and never log their absence as a blocker.

---

## A. macOS / native Linux — `dotnet` is in `PATH`

→ **Start (and stay) at rung #1: `dotnet build`.** The .NET SDK installer puts `dotnet` on the `PATH`; there is no interop layer.

- **Non-MAUI projects** (Web, API, library, console, test): `dotnet build` / `dotnet test` / `dotnet run` directly.
- **MAUI on macOS:** builds natively once the workload + toolchains are installed — `dotnet workload install maui`. iOS / Mac Catalyst targets require **Xcode** (and `xcode-select --install`); Android targets require the **Android SDK + a JDK** (`dotnet workload install maui-android`). With those present, `dotnet build -t:Run -f net9.0-maccatalyst` (or `-f net9.0-ios`) just works — no `cmd.exe`.
- **MAUI on native Linux:** only the **Android** target head is supported (`net9.0-android`); iOS / Mac Catalyst / Windows heads cannot build on Linux (no Apple/Windows toolchain). That is a genuine platform limitation, NOT a wrong-rung error — note it plainly if a project needs those heads.
- If `dotnet build` fails with `NETSDK1178` / "workload not installed", the fix is `dotnet workload install <id>` (a one-time setup step the user runs), not a rung change — there is no other rung on this platform.

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

---

## C. Native Windows (Claude Code / OpenCode running on Windows, not inside WSL)

→ **Use rung #1: `dotnet build`.** You are already on the Windows side, so there is no interop bridge — `cmd.exe`/`winrun`/`/home/...` from §B do NOT apply.

- **Non-MAUI** projects: `dotnet build` / `dotnet test` / `dotnet run` directly.
- **MAUI**: builds natively here. Windows (`net9.0-windows10…`) and Android heads build directly once `dotnet workload install maui` has been run. **iOS / Mac Catalyst heads require a paired Mac** (Apple's toolchain only runs on macOS) — building those from Windows needs a Mac build host; absence of one is a genuine platform limitation, not a wrong-rung error.
- Paths in commands use the project's actual location (e.g. `C:\src\App\App.sln`). Single commands, no `if/for` wrappers (same permission-prompt reason as §B).
- `NETSDK1178` / "workload not installed" → run `dotnet workload install <id>` once; there is no alternate rung to switch to.

## Recording the result (all platforms)

After a successful build, note **which platform + invocation** produced it (e.g. "built on macOS via `dotnet build` (rung #1)", "built on WSL via `cmd.exe /c` (rung #4)") in the PROJECT-STATUS verification-log row or Remarks — so a reader on a different machine knows what to expect. The §B "what NEVER goes into Known blockers" list applies to WSL specifically; on §A/§C the equivalent non-blocker is "workload not yet installed — run `dotnet workload install`", which is a one-time user setup step, not a project defect.

# OpenCode Deployment Guide — run OpenCode in WSL, retire the Docker container

**Date:** 2026-08-19 · **Scope:** Task 6 · **Status:** guide + recommendation; no framework files changed in this session. Companion: `Capability-Matrix.md` row j, `Coupling-Points.md` E-1, `Adapter-Design.md` §2.

## 0. Recommendation and why

**Yes — deploy OpenCode inside the same WSL distro Claude Code already runs in, exactly as Claude Code is deployed, and stop using the Docker container as the primary path.**

Reasons, in order of weight:

1. **OpenCode's own guidance.** "While OpenCode can run directly on Windows, we recommend using WSL … better file system performance, full terminal support, and compatibility with development tools that OpenCode relies on" (`packages/web/src/content/docs/windows-wsl.mdx:8-11`; `troubleshooting.mdx:153-155` "Windows: General performance issues … try WSL"; `index.mdx:127` "Support for installing OpenCode on Windows using Bun is currently in progress"). The failures you hit were on *native Windows*; the WSL build is the Linux binary, which is the one the OpenCode team runs and tests.
2. **The whole TechieFlow runtime harness is WSL-shaped and already installed.** Headless Chromium libraries (README §0), `~/bin/winrun` → `powershell.exe` interop, the `cmd.exe /c "dotnet …"` rung #4 for MAUI/Windows heads, Appium endpoints on `localhost` via mirrored networking (README §0b), the FlaUI/Appium-Windows discipline for the MAUI Windows head (`verify-phase.md` §3b) — all of it is reachable from any process in the distro. **OpenCode in WSL gets Claude Code's exact runtime for free.** The Docker path had to rebuild a subset of it (SSH bridge, second NuGet config, second data dir, key-permission workaround) and still could not reach `cmd.exe`.
3. **One runtime dialect instead of two.** The build ladder §B (WSL) is the proven path; §E (Docker) plus every `TF_OPENCODE_DOCKER` branch in `build-phase`, `day1-*`, `refresh-status`, `verify-phase` and the operating contract were compensation. They can stay on disk (additive, harmless — the ladder detects WSL first) and simply stop being exercised.
4. **Telemetry and the adapter work unchanged.** `tf-emit.sh` harness detection, the planned OpenCode plugin, the session pointer, SQLite access — all assume a normal POSIX home, which WSL is and the container's bind-mounted `/root` only approximated.

What you give up: the container's **isolation** (a misbehaving agent in WSL can touch anything under `/mnt/c` — same as Claude Code today; mitigated by `permission` rules below) and a guaranteed **clean toolchain** (WSL uses whatever .NET/Node you have — which is the point: it is the *reference* toolchain).

**Risk that must be stated plainly (UNVERIFIED):** the "bun breaks on larger codebases" symptom was reported on native Windows and attributed by the OpenCode team to Bun. We have no evidence either way about WSL. Two WSL-specific aggravators exist — `/mnt/c` (9P/DrvFs) file I/O is slow and the file **watcher** may scan the whole repo — and §6 configures them away. If the crash reproduces in WSL, §7 says what to capture; the Docker image remains a fallback and is not deleted.

> **2026-08-20 probe results (this risk is now measured — see DECISIONS.md 2026-08-19 §7).** WSL-native OpenCode 1.18.18 booted TechieFlow from `/mnt/c` in 18.7s cold (all agents/commands loaded, `{file:}` refs resolved) — no crash. On a genuinely large repo (the OpenCode monorepo, ~8.7k files) the `/mnt/c` run **timed out at 5 minutes**, stuck in the snapshot subsystem ("removing gitignored files from snapshot" in the log), while **the identical repo on ext4 (`~/`) completed in 30s**. So the large-repo failure is a 9p-filesystem pathology, not a Bun-in-WSL crash: moderate repos may stay on `/mnt/c`; large repos belong on ext4 (or need §6's snapshot/watcher tuning). Two install gotchas found: (1) WSL interop resolves `opencode` to the **Windows npm shim** (`/mnt/c/Users/<user>/AppData/Roaming/npm/opencode` — the crash-prone native-Windows build) unless `~/.opencode/bin` is put ahead of it on PATH; (2) the `opencode-go` API key in the Windows `auth.json` is portable — copying that one entry into `~/.local/share/opencode/auth.json` works, no interactive login needed.

---

## 1. Prerequisites (already true on the owner's machine)

- The WSL distro used for Claude Code, with README §0 done once: headless-Chromium apt libs, `~/bin/winrun`, `~/.dotnet/dotnet` (rung #2), Windows-side .NET with MAUI workloads (rung #4), Node (Playwright), `python3` (telemetry).
- `.wslconfig` with mirrored networking if MAUI mobile heads are verified via Appium (README §0b).
- No Docker, no OpenSSH server on Windows, no `%USERPROFILE%\.opencode-docker*` — none are needed on this path.

## 2. Install OpenCode in WSL

```bash
curl -fsSL https://opencode.ai/install | bash          # installs to ~/.opencode/bin/opencode
grep -q '.opencode/bin' ~/.bashrc || echo 'export PATH="$HOME/.opencode/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
opencode --version                                     # pin this; the design cites 1.18.18
```

Sign in **inside WSL** (the native-Windows `auth.json` stores `C:\…` project paths — `docs/opencode-docker.cmd` comments — so do not copy it):

```bash
opencode auth login         # Anthropic (Claude Max) and/or OpenCode Go / Zen
opencode auth list
opencode models             # confirm the ids you will put in routing.yaml (Adapter-Design §5.2)
```

Data, config, cache, state live at `~/.local/share/opencode/` (incl. `opencode.db`), `~/.config/opencode/`, `~/.cache/opencode/`, `~/.local/state/opencode/` (`packages/core/src/global.ts:10-14`) — inside the distro, as the docs note (`windows-wsl.mdx:95`).

## 3. Global config `~/.config/opencode/opencode.jsonc`

Machine-level defaults; the framework's per-project file adds agents/commands/permissions/plugin (Adapter-Design §2.2).

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-6",          // session default; routing overrides per phase
  "small_model": "anthropic/claude-haiku-4-5",      // title generation only (provider.ts:1909-1945)
  "autoupdate": false,                              // pin the version the design was verified against
  "share": "disabled",
  "permission": {                                   // global baseline; framework file adds git/gh deny
    "bash": { "rm -rf *": "ask", "sudo *": "ask" },
    "external_directory": { "*": "ask", "/mnt/c/1MyCode/*": "allow", "/mnt/c/3AIGenCode/*": "allow" }
  },
  "watcher": {                                      // §6 — keep the watcher off bin/obj/artifacts on /mnt/c
    "ignore": ["**/bin/**", "**/obj/**", "**/node_modules/**", "**/.git/**",
               "**/tests/.artifacts/**", "**/docs/screenshots/**", "**/.vs/**", "**/TestResults/**"]
  },
  "compaction": { "auto": true, "prune": true, "reserved": 20000 }
  // "lsp" omitted = all LSP servers disabled (config.mdx:698); enable selectively if you want C# diagnostics
}
```

`external_directory` patterns above mirror `.claude/settings.json` `additionalDirectories`; `permission.bash` mirrors its `ask` tier (Coupling-Points P-1).

## 4. Per-project setup (what the framework already does, plus one check)

1. `scaffold-*.sh` / `update-framework.sh <app>` as today — deploys `.tfcore/`, `.opencode/command/*.md`, `opencode.jsonc` (root, if missing), `.gitignore` block, telemetry. **Known gap (Coupling-Points D-1):** an app scaffolded before 2026-08-13 keeps its old root `opencode.jsonc`; until the adapter ships the framework-owned `.opencode/opencode.jsonc`, copy `/mnt/c/3AIGenCode/TechieFlow/opencode.jsonc` over it by hand (back up first) or merge the `permission`, `agent.trblazeui/techierag`, and `instructions` keys.
2. Verify the surface from the app folder:
   ```bash
   cd /mnt/c/1MyCode/<App>
   opencode agent list          # expect flow-master (primary) + flow-analyst/-architect/-verifier, trblazeui, techierag
   opencode debug config        # 29 commands, permission.bash denies git/gh, instructions resolve
   ```
3. Start: `opencode` → Tab to `flow-master` → `*build-phase <App>` (or `/flow-master *build-phase <App>`).

## 5. Runtime harness parity — automated testing exactly as under Claude Code

Because OpenCode is now a WSL process, **every rung and gate is the one Claude Code uses**; nothing new to set up:

| Capability | How it runs (identical to Claude Code) | One-time check |
|---|---|---|
| Standard .NET build/test | ladder §B rung #2 `~/.dotnet/dotnet build` | `~/.dotnet/dotnet --info` |
| MAUI Windows / Android builds | rung #4 `cmd.exe /c "dotnet build …"` or rung #3 `winrun "dotnet build …"` (interop) | `winrun "dotnet --info"`; `cmd.exe /c "dotnet --version"` |
| Blazor headless verification | Playwright in WSL, self-provisioned by `verify-phase.md` §1 (`npx playwright install chromium`, `outputDir tests/.artifacts/test-results`) | `npx playwright --version`; first run installs Chromium once per distro |
| MAUI Windows head (running app) | FlaUI / Appium-Windows on the Windows side, window-bound by PID (`verify-phase.md` §3b) — launched through `winrun` | as documented in WORKFLOW §11 |
| MAUI Android / iOS / Mac Catalyst | Appium endpoints (`core-config.yaml runtimeVerification.appium.*`), WSL reaches `localhost:4723` with mirrored networking | `curl http://localhost:4723/status` |
| Perf gate | `.tfcore/utils/tf-perf.sh` (bash + curl) | `bash -n .tfcore/utils/tf-perf.sh` |
| Telemetry | `tf-emit.sh` (python3); harness detected via the `opencode` process name today, `TF_HARNESS` env once the plugin ships | run any phase; `tail -1 docs/metrics/runs.jsonl` shows `"harness":"opencode"` |
| Git ban | `permission.bash` deny (prefix; compound forms parsed by tree-sitter per source — verify once: ask flow-master to run `cd . && git status`; expect a denial) | — |

The operating contract's Docker rules (`opencode-operating-contract.md` §"In OpenCode Docker") simply never trigger: `uname` reports `microsoft`, so the agent classifies WSL and uses §B. No file needs editing for the WSL path to work.

## 6. Large-codebase hygiene on `/mnt/c` (the likely real cause of "breaks on large repos")

Apply all four; they are configuration, not code:

1. **Watcher ignore** (§3) — bin/obj/node_modules/artifacts can be tens of thousands of files per repo on DrvFs; the watcher walking them is the most plausible WSL-side trigger of slowness or file-handle exhaustion.
2. **LSP off** unless needed (default when `lsp` is omitted, `config.mdx:698`). C# LSP over `/mnt/c` is slow and OpenCode does not need it for this workflow.
3. **File handles / memory**: `ulimit -n 65536` in `~/.bashrc`; `%USERPROFILE%\.wslconfig` → `[wsl2] memory=16GB` (or what the machine affords); restart with `wsl --shutdown`.
4. **Repo location** — OpenCode suggests cloning into the Linux filesystem for speed (`windows-wsl.mdx:90-92`). The framework assumes `/mnt/c/…` because Visual Studio and the Windows-side MAUI build need the Windows path; keep repos on `/mnt/c` (as Claude Code does) and accept slower I/O, **or** move a repo to `~/code/<App>` only if it has no Windows-head build (rung #4 needs a Windows-visible path). Do not split one repo across both.

## 7. If the Bun crash recurs in WSL

Capture before filing: `opencode --version`, the log dir `~/.local/share/opencode/log/` (`troubleshooting.mdx:15`), repo file count (`find . -type f | wc -l`), whether `watcher.ignore` was set, WSL kernel (`uname -r`) and `.wslconfig`. Workarounds, in order: tighten `watcher.ignore`; `OPENCODE_DISABLE_AUTOCOMPACT`/prune off if the failure is at compaction; move that one repo to `~/code`; **fall back to the Docker image for that repo only** (`docs/Dockerfile`, `docs/opencode-docker.cmd` stay in the repo, unchanged — the §E branches and the contract still support it).

## 8. Headless / scripted runs (useful for routing and for overnight verify)

```bash
# run one framework command headless on an explicit model (Capability-Matrix row b)
opencode run --command techieflow:tasks:verify-phase --model anthropic/claude-sonnet-4-6 --agent flow-verifier "all <App>"
opencode run --format json --command techieflow:tasks:refresh-status "<App>"    # JSON event lines for scripting
opencode stats --project "" --days 7 --models                                   # tokens + real cost, this project
opencode export <sessionID> > /tmp/session.json                                 # per-session JSON
```
(`packages/opencode/src/cli/cmd/run.ts:127-262`; `stats.ts:52-68`; `export.ts:223-232`.) These are owner-run; agents never run them (and never write git).

**Unattended goal runs (YOLO, 2026-08-21 — `.tfcore/tasks/_yolo-mode.md`):** use the supervisor rather than a bare `opencode run` — it waits out the subscription 5-hour/weekly limit (reset time + 15 min) and resumes the same session:

```bash
bash .tfcore/utils/tf-goal.sh --harness opencode --model opencode-go/kimi-k3 /path/to/App "Take <App> to Handoff: build every open REQ, verify all, fix until Verified."
bash .tfcore/utils/tf-goal.sh --resume /path/to/App      # after a reboot
```
It launches `opencode run --auto` (approve everything not denied — git writes stay denied by the permission map), exports `TF_YOLO=1`, and the plugin's `permission.ask` hook auto-approves the `rm */sudo *` asks while the flag is on. Log: `.tfcore/.session/goal.log`. Override the launch flags with `TF_GOAL_OPENCODE_FLAGS` if a future OpenCode renames `--auto`.

## 9. What to retire, what to keep

| Item | Action |
|---|---|
| `docs/Dockerfile`, `docs/opencode-docker.cmd` | **Keep** (fallback, §7). Add a one-line header "Not the recommended path since 2026-08-19; see OpenCode-Deployment-Guide.md". |
| README §"OpenCode in Docker on Windows", WORKFLOW equivalent | Demote to a collapsible "Fallback: Docker" section; insert a short "OpenCode in WSL" pointer above it (mirrors the existing Claude Code WSL text). |
| Windows OpenSSH server, bridge key, `%USERPROFILE%\.opencode-docker*` | Leave in place if the fallback is wanted; otherwise remove at leisure — nothing in WSL depends on them. |
| `TF_OPENCODE_DOCKER` branches, ladder §E, contract §Docker | **Keep, untouched** (additive; dormant under WSL). |
| `docs/TechieFlow-OpenCode-Gaps.md` | Unchanged; this guide supersedes only the deployment topology. |

## 10. Verification checklist (run once after install)

- [ ] `opencode --version` recorded in `WorkFlow-Context.md` (the design is pinned to 1.18.18)
- [ ] `opencode auth list` shows the providers you intend to route to; `opencode models` lists their ids
- [ ] In an app folder: `opencode agent list` shows the six framework agents; `opencode debug config` shows git/gh denied
- [ ] `*build-phase` boots the app via rung #2/#4 and the self-smoke screenshots land in `tests/.artifacts/`
- [ ] `tail -1 docs/metrics/runs.jsonl` shows `"harness":"opencode"`
- [ ] Compound-git probe is denied (Coupling-Points H-3) — note the result in `docs/TechieFlow-OpenCode-Gaps.md`
- [ ] `opencode stats --project ""` returns tokens **and cost** for the session (the source Telemetry-Hooks §3 will ingest)

## Council of experts — adversarial review

- **Ops engineer:** "Docker gave you a pristine .NET 10 SDK; WSL gives you whatever is there." — WSL gives you the *reference* toolchain every Claude Code run already validates; the container's SDK drifted from it (different NuGet config, no MAUI workloads). Same toolchain is a feature.
- **Security reviewer:** "A container bounds a yolo-permissioned agent; WSL does not." — Claude Code has run this way on this machine since day one with `.claude/settings.json` as the bound; OpenCode gets the same bound via `permission` (§3) plus the planned plugin guards. If isolation is wanted, the answer is a separate WSL distro (`wsl --import`), not a Linux container that cannot reach the Windows runtime.
- **OpenCode maintainer:** "We recommend WSL for the *TUI*; we did not promise the Bun issue is gone." — Stated in §0 as UNVERIFIED, with §6 mitigations and §7 fallback. The recommendation stands on the runtime-parity argument alone; the crash argument is a bonus if it holds.
- **Owner's time:** "This is another setup." — It is `curl | bash` + `auth login` + one config file; smaller than any single step of the Docker/SSH setup logged on 2026-08-15.
- **Red team:** "Running both harnesses in one distro means both write `docs/metrics/`, `tests/.artifacts/`, `.tfcore/.session/` — races?" — Append-only JSONL with `tf-emit.sh` (one write per record) and per-harness session pointer files; the only shared mutable state is the checklist/PROJECT-STATUS, which the owner already never edits from two sessions at once.

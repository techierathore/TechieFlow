# OpenCode Operating Contract

This file is loaded by OpenCode through `opencode.jsonc`. It is OpenCode-only; do not copy its rules into Claude permissions or settings.

## Runtime First

At the beginning of every build, smoke, verify, devguide, or status-recovery task, classify the runtime before choosing a command:

- `TF_OPENCODE_DOCKER=1`, or `/usr/local/bin/winrun` plus `TF_WINDOWS_APP_PATH` → OpenCode Docker on Windows (**fallback deployment only** — since 2026-08-20 OpenCode normally runs in WSL, next line).
- `uname` containing `microsoft` / `WSL` → WSL on Windows (**the expected OpenCode runtime** — behave exactly as Claude Code does here: §B ladder, `~/bin/winrun`, `cmd.exe` interop all available).
- `Darwin` → native macOS.
- Other plain Linux → native Linux.

In OpenCode Docker:

1. Never probe or invoke `cmd.exe`; it is expected to be absent.
2. Never install or check for `maui-tizen` or any MAUI workload in the container.
3. Run `winrun "dotnet --info"` before any Windows-head build or run. This is the bridge probe, not a suggestion.
4. Use container `dotnet build` / `dotnet test` for standard .NET projects.
5. Use `winrun "dotnet build ..."` / `winrun "dotnet test ..."` for a Windows MAUI Blazor Desktop project or a solution containing one.
6. Before any package restore, run `test -s "$NUGET_CONFIG_FILE"` and `dotnet nuget list source --configfile "$NUGET_CONFIG_FILE"`. A missing file is a mount/launcher problem; a missing private URL is a config problem; an HTTP `401` is an authentication problem. If restore returns `401`, inspect that mounted Docker config and its source credentials; do not switch to a Windows `C:\...` source, add a PAT to the repository, or declare the application broken.
7. For container restore, use `dotnet restore --configfile "$NUGET_CONFIG_FILE"` followed by the build with `--no-restore` when a private feed is involved. Do not let an implicit restore silently select a Windows source.

> The two sections below are harness-neutral doctrine; the canonical copies live in `.tfcore/tasks/_smoke-test-policy.md` (§"Smoke is NOT verify", §"Evidence discipline") and `build-phase.md §6`, which BOTH harnesses load through the tasks. They are repeated here because this file is injected into every OpenCode session.

## Build-Phase Completion Contract

`*build-phase` is an execution workflow, not a build command. A green compiler is an intermediate checkpoint and must never be reported as phase completion.

After the correct build succeeds, continue in the same session without asking the owner to run the next step:

1. Run the mandatory self-smoke from `.tfcore/tasks/build-phase.md §6`: boot the correct head, poll readiness, exercise every REQ cluster, verify data-render truth and visual truth, and clean up the process.
2. If smoke fails, fix the affected REQs and repeat build plus smoke. Do not chain verification with known smoke failures.
3. When smoke is clean, execute `.tfcore/tasks/verify-phase.md` inline with scope `all`. Do not merely summarize or recommend verification.
4. Let the verifier write verdicts to the one Checklist Requirements Status table. Do not self-attest `Verified`.
5. Finish the status gate: update `PROJECT-STATUS.md` and its HTML, set the real phase (`Build` or `Verify`), record the actual platform/invocation, and emit the required run telemetry.
6. Only then report the phase result and the exact next command. If requirements remain open, the next command must come from the Build → Verify → Handoff ladder, not an invented “done” statement.

The following are incomplete outcomes, not successful completion:

- “Build is green; run smoke later.”
- “Bridge exists; user can verify it.”
- “Tests passed” when only focused unit tests ran and the full phase was not smoked/verified.
- “Full build blocked” because the agent used direct Linux `dotnet` for a Windows head before trying `winrun`.

## Evidence Discipline

State which command actually ran. Distinguish:

- container build/test;
- Windows-host build/run through `winrun`;
- native Mac build/run;
- focused tests versus full solution build;
- self-smoke versus verifier execution.

Never convert a successful intermediate command into a full workflow pass.

# TrBlazeUI Feedback — surfaced during TechieFlow framework work

> For the TrBlazeUI team. Found during the 2026-06-12 framework audit (see `WorkFlow-Context.md`).
> Per-app feedback lives in each consumer repo as `docs/<APP>-TrBlazeUI-Feedback.md` — one file
> per library so it can be handed to (or picked up by) the owning team directly.

## Summary
- 1 major, 0 minor
- Last consolidated: 2026-06-12

## Issues

### TR-001 — Agent persona deploys to a path Claude Code never scans
- **Severity:** major
- **Repro:** `dotnet add package TrBlazeUI && dotnet build` in any consumer repo. The MSBuild target writes `.claude/trblazeui.md` (plus `.opencode/command/trblazeui.md` and `.trblazeui/TrBlazeUI-AI-Reference.md`). Open Claude Code → `/trblazeui` is not a registered command.
- **Expected:** the short slash form `/trblazeui` works in Claude Code right after `dotnet build`.
- **Actual:** Claude Code only registers commands found under `.claude/commands/`; files at the `.claude/` root are ignored, so the persona is invisible. (OpenCode is fine — `.opencode/command/` is correct for that harness.)
- **Encountered in:** TechieFlow framework audit 2026-06-12, issue I-13 in `WorkFlow-Context.md`.
- **Workaround:** the framework's `scaffold-*.sh` and `update-framework.sh` now shim-copy `.claude/trblazeui.md` → `.claude/commands/trblazeui.md` after every run (NuGet file stays authoritative). The shim only refreshes when a script runs, so a persona updated by `dotnet build` is stale in Claude Code until the next `update-framework.sh`.
- **Suggested fix:** change the MSBuild deploy target to write the Claude Code copy to `.claude/commands/trblazeui.md` (keep `.opencode/command/trblazeui.md` and the `.trblazeui/` reference doc as they are). Backwards-compatible: also delete any old `.claude/trblazeui.md` on deploy. Once shipped, the framework shim becomes a harmless no-op.

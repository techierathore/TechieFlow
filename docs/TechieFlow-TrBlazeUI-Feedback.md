# TrBlazeUI Feedback — surfaced during TechieFlow framework work

> For the TrBlazeUI team. Found during the 2026-06-12 framework audit (see `WorkFlow-Context.md`).
> Per-app feedback lives in each consumer repo as `docs/<APP>-TrBlazeUI-Feedback.md` — one file
> per library so it can be handed to (or picked up by) the owning team directly.

## Summary
- 1 major (resolved), 1 minor (resolved at source, pending package republish)
- Last consolidated: 2026-07-04

## Issues

### TR-002 — Persona file shipped stale branding + wrong core path; consumer-side edits are futile
- **Severity:** minor
- **Status:** ✅ RESOLVED at source 2026-07-04 (pending package republish)
- **Repro:** the packaged `skills/claude-code-trblazeui.md` carried a `<!-- Powered by BMAD™ Core -->` header and `Dependencies map to .bmad-core/{type}/{name}` — both pre-date the TechieFlow rebrand (`.tfcore/`). Because the MSBuild target re-copies the packaged file over `.claude/commands/trblazeui.md` on every consumer build (`SkipUnchangedFiles` only skips when identical), any consumer-side rebrand edit is silently reverted at the next `dotnet build`. The TechieFlow framework repo's own copies had been hand-edited and were exactly this kind of doomed edit.
- **Fix applied (in the TrBlazeUI repo):** `docs/skills/claude-code-trblazeui.md` — removed the BMAD header, `.bmad-core/` → `.tfcore/`. The OpenCode variant needed no change. **Remaining owner action: repack + republish TrBlazeUI.Components so consumers receive the corrected persona on their next restore/build.** Until then, deployed copies in consumer repos will still show the old branding after each build.
- **Policy reminder:** persona/skill files are LIBRARY-owned. Any customization must be made in the TrBlazeUI repo (`docs/skills/`) and shipped via the package — never edited in a consumer repo.

### TR-001 — Agent persona deploys to a path Claude Code never scans
- **Severity:** major
- **Status:** ✅ RESOLVED in the library — `build/TrBlazeUI.Components.targets` now deploys directly to `.claude/commands/trblazeui.md` (verified 2026-07-04). The framework's shim-copy remains as a harmless no-op.
- **Repro:** `dotnet add package TrBlazeUI && dotnet build` in any consumer repo. The MSBuild target writes `.claude/trblazeui.md` (plus `.opencode/command/trblazeui.md` and `.trblazeui/TrBlazeUI-AI-Reference.md`). Open Claude Code → `/trblazeui` is not a registered command.
- **Expected:** the short slash form `/trblazeui` works in Claude Code right after `dotnet build`.
- **Actual:** Claude Code only registers commands found under `.claude/commands/`; files at the `.claude/` root are ignored, so the persona is invisible. (OpenCode is fine — `.opencode/command/` is correct for that harness.)
- **Encountered in:** TechieFlow framework audit 2026-06-12, issue I-13 in `WorkFlow-Context.md`.
- **Workaround:** the framework's `scaffold-*.sh` and `update-framework.sh` now shim-copy `.claude/trblazeui.md` → `.claude/commands/trblazeui.md` after every run (NuGet file stays authoritative). The shim only refreshes when a script runs, so a persona updated by `dotnet build` is stale in Claude Code until the next `update-framework.sh`.
- **Suggested fix:** change the MSBuild deploy target to write the Claude Code copy to `.claude/commands/trblazeui.md` (keep `.opencode/command/trblazeui.md` and the `.trblazeui/` reference doc as they are). Backwards-compatible: also delete any old `.claude/trblazeui.md` on deploy. Once shipped, the framework shim becomes a harmless no-op.

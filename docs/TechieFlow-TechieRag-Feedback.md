# TechieRag Feedback — surfaced during TechieFlow framework work

> For the TechieRag team. Found during the 2026-06-12 framework audit (see `WorkFlow-Context.md`).
> Per-app feedback lives in each consumer repo as `docs/<APP>-TechieRag-Feedback.md` — one file
> per library so it can be handed to (or picked up by) the owning team directly.

## Summary
- 1 major (resolved), 1 minor (resolved at source, pending package republish)
- Last consolidated: 2026-07-04

## Issues

### TR-RAG-002 — Persona file shipped stale BMAD branding; consumer-side edits are futile
- **Severity:** minor
- **Status:** ✅ RESOLVED at source 2026-07-04 (pending package republish)
- **Repro:** the packaged `build/content/techierag-claude-command.md` carried a `<!-- Powered by BMAD Core -->` header pre-dating the TechieFlow rebrand. Because the MSBuild target re-copies the packaged file over `.claude/commands/techierag.md` on every consumer build, any consumer-side edit is silently reverted at the next `dotnet build`.
- **Fix applied (in the TechieRag repo):** removed the BMAD header from `src/TechieRag/build/content/techierag-claude-command.md` — the file is now byte-identical (modulo line endings) to the TechieFlow framework's rebranded copy. The OpenCode variant needed no change. **Remaining owner action: repack + republish TechieRag so consumers receive the corrected persona on their next restore/build.**
- **Policy reminder:** persona/skill files are LIBRARY-owned. Any customization must be made in the TechieRag repo (`src/TechieRag/build/content/`) and shipped via the package — never edited in a consumer repo.

### TR-RAG-001 — Agent persona deploys to a path Claude Code never scans
- **Severity:** major
- **Status:** ✅ RESOLVED in the library — `build/TechieRag.targets` now deploys directly to `.claude/commands/techierag.md` (verified 2026-07-04). The framework's shim-copy remains as a harmless no-op.
- **Repro:** `dotnet add package TechieRag && dotnet build` in any consumer repo. The MSBuild target writes `.claude/techierag.md` (plus `.opencode/command/techierag.md` and `.techierag/TechieRag-AI-Reference.md`). Open Claude Code → `/techierag` is not a registered command.
- **Expected:** the short slash form `/techierag` works in Claude Code right after `dotnet build`.
- **Actual:** Claude Code only registers commands found under `.claude/commands/`; files at the `.claude/` root are ignored, so the persona is invisible. (OpenCode is fine — `.opencode/command/` is correct for that harness.)
- **Encountered in:** TechieFlow framework audit 2026-06-12, issue I-13 in `WorkFlow-Context.md`.
- **Workaround:** the framework's `scaffold-*.sh` and `update-framework.sh` now shim-copy `.claude/techierag.md` → `.claude/commands/techierag.md` after every run (NuGet file stays authoritative). The shim only refreshes when a script runs, so a persona updated by `dotnet build` is stale in Claude Code until the next `update-framework.sh`.
- **Suggested fix:** change the MSBuild deploy target to write the Claude Code copy to `.claude/commands/techierag.md` (and clean up the legacy `.claude/techierag.md` on deploy). Apply the fix in the shared deploy-target template so future library agents inherit the correct path (WORKFLOW.html §9.1 pattern).

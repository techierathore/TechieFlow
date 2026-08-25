# TrBlazeUI Feedback — surfaced during TechieFlow framework work

> For the TrBlazeUI team. Found during the 2026-06-12 framework audit (see `WorkFlow-Context.md`).
> Per-app feedback lives in each consumer repo as `docs/<APP>-TrBlazeUI-Feedback.md` — one file
> per library so it can be handed to (or picked up by) the owning team directly.

## Summary
- All three findings are resolved in TrBlazeUI source.
- Ships in: **TrBlazeUI.Components 2.0.3** — **PUBLISHED** on the GitHub Packages feed (`nuget.pkg.github.com/techierathore`), verified 2026-08-25 by querying the source from the user-level `NuGet.Config` and inspecting the downloaded nupkg (`buildTransitive/TrBlazeUI.Components.targets` with the Codex ownership-marker block, `skills/codex-trblazeui.toml`, BMAD-free `skills/claude-code-trblazeui.md`). nuget.org still carries only 2.0.0.
- TechieFlow side done 2026-08-25: `tf-codex-bind.py` now honours the package's ownership marker (never overwrites a package-owned agent; plants `.trblazeui/.codex-agent-package-owned` next to its wrapper so the package may replace it). Without this, every existing TechieFlow app would have blocked 2.0.3's Codex deployment forever — see `docs/TechieFlow-Library-Persona-Propagation.md` § Ownership-marker contract.
- Remaining per-app action: `update-framework.sh <repo>` → `dotnet build` (2.0.3) → confirm `.codex/agents/trblazeui.toml` is the package copy.
- Last consolidated: 2026-08-25

## Issues

### TR-003 — NuGet package does not deploy a native Codex persona
- **Severity:** major
- **Status:** ✅ RESOLVED — shipped in the published 2.0.3 package (verified on the feed 2026-08-25); framework marker handling landed the same day
- **Repro:** install `TrBlazeUI.Components` into a clean Codex consumer and run `dotnet build` without first scaffolding TechieFlow. The package deploys Claude and OpenCode persona files plus `.trblazeui/TrBlazeUI-AI-Reference.md`, but no Codex custom-agent definition. Codex therefore cannot discover a native `trblazeui` specialist from the library package alone.
- **Expected:** the library source of truth includes a Codex persona and the NuGet target deploys it to `.codex/agents/trblazeui.toml`. The agent uses plain `developer_instructions`, reads `.trblazeui/TrBlazeUI-AI-Reference.md`, follows the consumer's applicable `AGENTS.md`, and does not contain Claude activation/help rituals or OpenCode slash-command syntax.
- **Historical actual (through 2.0.2):** TechieFlow generated a compatibility wrapper at `.codex/agents/trblazeui.toml`; standalone Codex consumers received no library-owned agent.
- **Encountered in:** TechieFlow Codex adapter implementation and documentation audit, 2026-08-24.
- **Workaround:** scaffold/update TechieFlow so its generated Codex wrapper is present. Do not hand-edit that consumer copy; it is regenerated.
- **Requested fix (completed in 2.0.3 source):** add a library-owned Codex source at `docs/skills/codex-trblazeui.toml`, pack it under `skills/`, and deploy it through `src/TrBlazeUI.Components/build/TrBlazeUI.Components.targets` to `.codex/agents/trblazeui.toml`, preserving consumer-owned files.
- **Codex invocation:** TechieFlow's `$techieflow-build` delegates REQ-UI clusters to the `trblazeui` custom agent; this is not a `/trblazeui` slash command.
- **Fix delivered for 2.0.3:** added `docs/skills/codex-trblazeui.toml`; packed it as `skills/codex-trblazeui.toml`; and added a build-transitive deployment to `.codex/agents/trblazeui.toml`. Package-owned copies upgrade safely, while consumer-owned agents, `.codex/config.toml`, hooks, rules, and unrelated agents are preserved. The plain `developer_instructions` loads `.trblazeui/TrBlazeUI-AI-Reference.md`, follows applicable consumer `AGENTS.md`, and contains no Claude/OpenCode activation syntax.
- **Verification:** `tests/package/codex-agent-deployment.sh` packed the local package graph and built two clean NuGet-only consumers with 0 warnings / 0 errors; exact agent/reference deployment, ownership-based refresh, preservation behavior, and TOML discovery contract passed.
- **Remaining TechieFlow action:** after 2.0.3 is published, update the framework's package baseline, run a clean scaffold/update build, confirm the package-owned Codex agent is discoverable, and retire or reduce the compatibility wrapper only when that published-package smoke is green.

### TR-002 — Persona file shipped stale branding + wrong core path; consumer-side edits are futile
- **Severity:** minor
- **Status:** ✅ RESOLVED — included in the 2.0.3 publication set
- **Repro:** the packaged `skills/claude-code-trblazeui.md` carried a `<!-- Powered by BMAD™ Core -->` header and `Dependencies map to .bmad-core/{type}/{name}` — both pre-date the TechieFlow rebrand (`.tfcore/`). Because the MSBuild target re-copies the packaged file over `.claude/commands/trblazeui.md` on every consumer build (`SkipUnchangedFiles` only skips when identical), any consumer-side rebrand edit is silently reverted at the next `dotnet build`. The TechieFlow framework repo's own copies had been hand-edited and were exactly this kind of doomed edit.
- **Fix applied (in the TrBlazeUI repo):** `docs/skills/claude-code-trblazeui.md` — removed the BMAD header, `.bmad-core/` → `.tfcore/`. The OpenCode variant needed no change. It will reach consumers in **2.0.3**; deployed copies remain stale until consumers restore/build that version.
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

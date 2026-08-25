# Library Persona Propagation

This is the source-of-truth map for the AI instructions shipped by the
TrBlazeUI and TechieRag NuGet packages. Do not fix only the copies in this
TechieFlow repository: the next consumer build can overwrite them from the
NuGet package.

## Codex packaging contract (implemented for TrBlazeUI 2.0.3)

Codex specialist personas are project custom agents under `.codex/agents/`.
They are TOML definitions with `name`, `description`, and plain
`developer_instructions`; they must not copy Claude activation/help rituals or
pretend that OpenCode slash commands exist. Each library-owned agent should read
its packaged AI reference and obey the consuming repository's `AGENTS.md`.

TrBlazeUI now owns and packages the native `trblazeui` Codex agent. The 2.0.3
build-transitive target deploys package-owned copies and preserves unrelated or
consumer-owned Codex files; it never overwrites `.codex/config.toml`, hooks,
rules, or other agents. **TrBlazeUI.Components 2.0.3 is published** on the
`https://nuget.pkg.github.com/techierathore/index.json` feed (verified from the
user-level `NuGet.Config` source on 2026-08-25; nuget.org still carries only
2.0.0). The package was downloaded and inspected: `buildTransitive/` targets,
`skills/codex-trblazeui.toml`, and a BMAD-free Claude persona all ship in it.

### Ownership-marker contract (what the framework depends on)

The package's MSBuild target deploys `.codex/agents/<lib>.toml` **only when the
file is absent OR `.<lib>/.codex-agent-package-owned` exists**; any other
existing file is treated as consumer-owned and preserved. TechieFlow's
`tf-codex-bind.py` honours this from both sides:

- it writes its compatibility wrapper only when the target is absent or is
  still the framework's own wrapper (`description = "TechieFlow <lib> role."`);
  a package- or consumer-owned file is never overwritten, and the run prints
  `kept library-owned .codex/agents/<lib>.toml`;
- when it does write the wrapper it also writes the marker
  (`.trblazeui/.codex-agent-package-owned` = `TrBlazeUI.Components`,
  `.techierag/.codex-agent-package-owned` = `TechieRag`) so the package is
  allowed to replace the wrapper on the next `dotnet build`.

Result: the wrapper self-retires per repo on the first build against a package
that ships the native agent. No flag day, no manual deletion. Apps scaffolded
before 2026-08-25 must run `update-framework.sh <repo>` once (to plant the
marker) **before** their first 2.0.3 build; otherwise the package sees a
marker-less file and skips deployment.

TechieRag remains a separate library/team action: its native Codex agent must be
implemented and published from the TechieRag repository, **using the same
marker path and semantics** (`.techierag/.codex-agent-package-owned`), before
the framework wrapper can retire there.

## OpenCode and Debian

OpenCode's official installation documentation supports Docker with
`ghcr.io/anomalyco/opencode` and lists Linux installation through the install
script, Homebrew, npm, and other package managers. OpenCode does not require
Alpine for a user-built image. The official Dockerfile uses Alpine because it
ships the musl-linked OpenCode binary; the custom `docs/Dockerfile` uses the
Debian .NET SDK image and installs the regular Linux OpenCode binary through
`https://opencode.ai/install`.

Therefore:

- Alpine is the base of the official OpenCode image, not a framework
  requirement.
- Debian is appropriate for this custom image because it provides glibc and a
  supported .NET SDK/workload environment.
- Keep the Docker smoke check (`opencode --version`) and test the MAUI workload
  install when changing the image.

References checked 2026-08-15:

- <https://opencode.ai/docs/> — Docker installation and Linux installation.
- <https://opencode.ai/docs/agents/> — project Markdown agents and JSON
  configuration.
- <https://opencode.ai/docs/commands/> — project `.opencode/commands` files.
- <https://github.com/anomalyco/opencode/blob/dev/packages/opencode/Dockerfile>
  — official Alpine/musl image implementation.

## TrBlazeUI Repository

Edit and commit these files in the TrBlazeUI repository before publishing a
new `TrBlazeUI.Components` package:

| Purpose | Library source file |
|---|---|
| Claude Code persona | `docs/skills/claude-code-trblazeui.md` |
| OpenCode persona | `docs/skills/opencode-trblazeui.md` |
| Codex custom agent (implemented for 2.0.3) | `docs/skills/codex-trblazeui.toml` |
| Deployment mapping | `src/TrBlazeUI.Components/build/TrBlazeUI.Components.targets` |

The target file already maps the package content to these consumer paths:

| Package content | Consumer path |
|---|---|
| `skills/claude-code-trblazeui.md` | `.claude/commands/trblazeui.md` |
| `skills/opencode-trblazeui.md` | `.opencode/command/trblazeui.md` |
| `skills/codex-trblazeui.toml` | `.codex/agents/trblazeui.toml` |
| `docs/TrBlazeUI-AI-Reference.md` | `.trblazeui/TrBlazeUI-AI-Reference.md` |

**TrBlazeUI.Components 2.0.3 is published** (GitHub Packages feed, verified
2026-08-25). The framework no longer snapshots anything from the package: the
compat wrapper retires itself per repo under the ownership-marker contract
above. Remaining per-app step: `update-framework.sh <repo>` then `dotnet build`,
and confirm `.codex/agents/trblazeui.toml` now reads
`description = "Expert .NET and Blazor specialist …"` (package copy), not
`"TechieFlow trblazeui role."` (wrapper).

The 2.0.3 package smoke already proves the source package contract locally:
three local dependency packages were packed; two clean NuGet-only consumers
built with 0 warnings / 0 errors; the Claude, OpenCode, AI-reference, and Codex
targets landed at their exact paths; package-owned Codex copies refreshed; and
consumer-owned Codex configuration and agents were preserved.

## TechieRag Repository

Edit and commit these files in the TechieRag repository before publishing a
new `TechieRag` package:

| Purpose | Library source file |
|---|---|
| Claude Code persona | `src/TechieRag/build/content/techierag-claude-command.md` |
| OpenCode persona | `src/TechieRag/build/content/techierag-opencode-command.md` |
| Codex custom agent (to add) | `src/TechieRag/build/content/techierag-codex-agent.toml` |
| AI reference | `src/TechieRag/build/content/TechieRag-AI-Reference.md` |
| Deployment mapping | `src/TechieRag/build/TechieRag.targets` |

The target file already maps the package content to these consumer paths:

| Package content | Consumer path |
|---|---|
| `techierag-claude-command.md` | `.claude/commands/techierag.md` |
| `techierag-opencode-command.md` | `.opencode/command/techierag.md` |
| `techierag-codex-agent.toml` (to add) | `.codex/agents/techierag.toml` |
| `TechieRag-AI-Reference.md` | `.techierag/TechieRag-AI-Reference.md` |

## NuGet Credential Rule

Both source personas must say that GitHub Packages credentials belong in the
user-level NuGet config, not in a repository file:

- Windows: `%AppData%\\NuGet\\NuGet.Config`
- macOS/Linux: `$HOME/.nuget/NuGet/NuGet.Config`
- OpenCode Docker: mount the host directory read-only at
  `/root/.nuget/NuGet`

After publishing a package, validate a clean consumer with `dotnet build`, then
check the Claude, OpenCode, AI-reference, and Codex files at their exact target
paths. For Codex, trust the repository, confirm the custom agent is discoverable,
and run a delegated task proving it loaded the packaged AI reference. Restart
any open Claude Code, OpenCode, or Codex session after package deployment.

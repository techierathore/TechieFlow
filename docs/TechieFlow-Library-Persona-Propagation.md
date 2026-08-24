# Library Persona Propagation

This is the source-of-truth map for the AI instructions shipped by the
TrBlazeUI and TechieRag NuGet packages. Do not fix only the copies in this
TechieFlow repository: the next consumer build can overwrite them from the
NuGet package.

## Codex packaging contract (added 2026-08-24)

Codex specialist personas are project custom agents under `.codex/agents/`.
They are TOML definitions with `name`, `description`, and plain
`developer_instructions`; they must not copy Claude activation/help rituals or
pretend that OpenCode slash commands exist. Each library-owned agent should read
its packaged AI reference and obey the consuming repository's `AGENTS.md`.

TechieFlow currently generates compatibility wrappers for `trblazeui` and
`techierag`, so scaffolded applications work before the libraries are
republished. A clean NuGet-only consumer should also receive the native Codex
agent. Package targets must preserve unrelated consumer-owned Codex files and
must never overwrite `.codex/config.toml`, hooks, rules, or other agents.

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
| Codex custom agent (to add) | `docs/skills/codex-trblazeui.toml` |
| Deployment mapping | `src/TrBlazeUI.Components/build/TrBlazeUI.Components.targets` |

The target file already maps the package content to these consumer paths:

| Package content | Consumer path |
|---|---|
| `skills/claude-code-trblazeui.md` | `.claude/commands/trblazeui.md` |
| `skills/opencode-trblazeui.md` | `.opencode/command/trblazeui.md` |
| `skills/codex-trblazeui.toml` (to add) | `.codex/agents/trblazeui.toml` |
| `docs/TrBlazeUI-AI-Reference.md` | `.trblazeui/TrBlazeUI-AI-Reference.md` |

The framework snapshots are `.claude/trblazeui.md`,
`.claude/commands/trblazeui.md`, and `.opencode/command/trblazeui.md`. Refresh
them from the newly published package; do not make the framework snapshot the
long-term source.

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

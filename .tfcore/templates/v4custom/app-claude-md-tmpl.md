# {AppName} — Claude Code session memory

## Required reading before any code change
ALWAYS read and follow:
- **docs/{AppName}-Coding-Standards.md** — strict compliance for every line of code you write or modify.
- **docs/{AppName}-Architecture.md** — respect module boundaries.
- **PROJECT-STATUS.md** — for current phase & next-step context.

## Project basics
- Stack: .NET 9, Blazor [Server], TrBlazeUI, [TechieRag if AI features].
- Field-prefix convention: {obj prefix on instance fields (e.g. `private readonly ILogger<X> objLogger;`) | bare PascalCase, no prefix} — PER-PROJECT day-1 decision; this project's choice is recorded in Coding Standards §"Fields, Parameters, Locals", which is authoritative.
- Test naming: short PascalCase, NO underscores. Full scenario in XML `<summary>` doc.

## Requirement ID prefixes used in this repo
- `REQ-UI-*` — UI work, routed to /trblazeui
- `REQ-FN-*` — backend, routed to /flow-master
- `REQ-RAG-*` — AI/RAG, routed to /techierag
- `REQ-NFR-*` — non-functional

Always reference REQ IDs in commit messages: `[REQ-UI-007] add settings form validation`.

## Verification
After every implementation phase, the verifier runs and writes per-REQ verdicts into the
owning checklist's Requirements Status table (the single source of truth — no dated
docs/qa files). PROJECT-STATUS.md is updated after EVERY phase (mandatory gate).
Library issues go in the owning library's feedback file — docs/{AppName}-TrBlazeUI-Feedback.md
or docs/{AppName}-TechieRag-Feedback.md (one file per library; each goes to its own team) —
never silently worked around.

## Permissions and tool preference (read before using Bash)

`.claude/settings.json` auto-allows every dedicated tool (Read, Edit, Write, Glob, Grep, MultiEdit, Task, WebFetch, WebSearch, TodoWrite, NotebookEdit) and **all Bash** (bare `Bash` allow). Only deletes (`rm`, `rmdir`) and `git` / `gh` / `sudo` prompt; catastrophic `rm -rf` paths are denied.

**Still: never reach for bash for file inspection or file writing.** The dedicated tools are faster, diff-aware, and keep the transcript readable:

| Want to | Bash (avoid) | Use this tool instead |
|---------|--------------|------------------------|
| Check if a file exists | `if [ -f x ]; then ...` | **Read** — returns content or "file does not exist" |
| Get file size / mtime | `wc -c < x`, `date -r x` | **Read** (you usually want content anyway) — or skip mtime entirely and use today's date |
| Write a file | `cat <<EOF > x` or `echo … > x` | **Write** |
| Edit a file | `sed -i 's/a/b/' x` | **Edit** with old_string / new_string |
| Find files by pattern | `find . -name '*.cs'` | **Glob** |
| Search file contents | `grep -r pattern src/` | **Grep** |
| Loop over a list of files | `for f in ...; do ...; done` | Multiple parallel Read/Edit calls in one assistant turn |

Reserve Bash for things that genuinely need a shell: `dotnet build`, `dotnet test`, `dotnet run`, `npm install`, `winrun "..."`, `playwright …`, single-command file listings like `ls src/`. Anything more complex than a single command — use a dedicated tool.

## Slash-command syntax (READ ME if a `/agent *command` invocation fails)

**Claude Code** registers TechieFlow-native agents under the path-derived namespace `TechieFlow:agents:<name>`. The short `/<agent>` form does NOT always resolve. When in doubt use the full form:

| Agent | Claude Code | OpenCode |
|-------|-------------|----------|
| analyst | `/TechieFlow:agents:analyst` (or `/analyst` if it resolves) | `/flow-analyst` |
| flow-master | `/TechieFlow:agents:flow-master` | `/flow-master` |
| flow-master | `/TechieFlow:agents:flow-master` | `/flow-master` |
| verifier | `/TechieFlow:agents:verifier` | (add to opencode.jsonc) |
| trblazeui | `/trblazeui` (NuGet-deployed; scaffold/update shims it into `.claude/commands/`) | `/trblazeui` |
| techierag | `/techierag` (NuGet-deployed; scaffold/update shims it into `.claude/commands/`) | `/techierag` |

If `/trblazeui` or `/techierag` is missing: run `dotnet build` (NuGet deploy target), then `update-framework.sh` (copies the persona into `.claude/commands/`), then restart Claude Code.

If `/flow-master *render-workflow-docs <App>` returns "Unknown command", use `/TechieFlow:agents:flow-master *render-workflow-docs <App>` instead.

After the agent is loaded, every TechieFlow-native agent (analyst, architect, flow-master, verifier) accepts `*command args` style invocations. trblazeui and techierag are free-form personas — normally `flow-master *build-phase <App>` calls them as sub-agents, but you can also drive them directly with prompts like `Implement REQ-UI-* from docs/<App>-Checklist.md to match the mockups in docs/mockups/.`

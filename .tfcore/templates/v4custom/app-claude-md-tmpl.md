# {AppName} — Claude Code session memory

<!-- Since 2026-08-20 the harness-neutral project memory lives in AGENTS.md
     (app-agents-md-tmpl.md — required reading, hard rules, project basics,
     REQ prefixes, verification, slash-command table). Claude Code pulls it in
     through the @import below; OpenCode auto-loads AGENTS.md directly and
     never reads this file. Keep ONLY Claude-specific material here.
     AGENTS.md is committed; this file stays gitignored. -->

@AGENTS.md

## Permissions and tool preference (read before using Bash)

`.claude/settings.json` auto-allows every dedicated tool (Read, Edit, Write, Glob, Grep, MultiEdit, Task, WebFetch, WebSearch, TodoWrite, NotebookEdit) and **all Bash** (bare `Bash` allow). Only deletes (`rm`, `rmdir`) and `sudo` prompt; **`git` / `gh` are DENIED** (Hard rule 1 — git is manual; a PreToolUse hook also blocks compound forms like `cd x && git log`); catastrophic `rm -rf` paths are denied.

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

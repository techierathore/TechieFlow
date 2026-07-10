#!/usr/bin/env bash
# TechieFlow PreToolUse hook — blocks any Bash tool call that invokes git or gh.
#
# Git is MANUAL in TechieFlow: agents never run git/gh, not even to read
# (no git status/log/diff/grep/blame). See .tfcore/tasks/_smoke-test-policy.md
# §"Git is manual" and .tfcore/tasks/_status-update-gate.md §"Never run git".
# The settings.json deny rules catch plain "git …" commands; this hook catches
# the compound forms prefix-matching misses ("cd x && git log", "foo | git …").
#
# Wired in .claude/settings.json → hooks.PreToolUse (matcher "Bash").
# Exit 2 + stderr = block the call and feed the message back to the agent.

INPUT="$(cat)"

# Match git/gh as a COMMAND WORD: preceded by start-of-string or a separator
# (not alnum, _, ., /, @, - — so .gitignore, foo/git, github, --ghost, my-gh
# stay legal) and followed by a non-word char or end-of-string.
if printf '%s' "$INPUT" | grep -qE '(^|[^[:alnum:]_./@-])(git|gh)([^[:alnum:]_.-]|$)'; then
  cat >&2 <<'MSG'
BLOCKED by TechieFlow policy: agents NEVER run git or gh — git is manual, owner-only.
Do NOT retry with another git/gh form. Instead:
- Status updates / "what changed": read the checklist Requirements Status table + the working-tree files (ls -lt, find -newer, Read/Glob/Grep) + a fresh dotnet build — never commit history (.tfcore/tasks/_status-update-gate.md).
- Investigating code: read the files on disk at file:line — the working tree IS the as-built code.
- Committing/tagging: never yours. Record REQ IDs in the checklist Remarks, not in commits. The owner commits manually.
- If your command merely CONTAINS the word git (e.g. writing a doc, grepping for the string): use the Write/Edit/Grep tools instead of bash — that is the standing tool-preference rule anyway.
MSG
  exit 2
fi
exit 0

#!/usr/bin/env bash
# tf-yolo-start.sh — what `tfyolo` runs: Claude Code in bypass mode with YOLO on (owner, 2026-10-14).
#
#   tfyolo                start a new Claude Code session here, nothing asks
#   tfyolo -c             the same, continuing the last conversation in this folder (claude --continue)
#   tfyolo <claude args>  any other claude arguments are passed through unchanged
#
# Why it exists: Claude Code drops its permission prompts only for a session STARTED in bypass mode
# (`claude --permission-mode bypassPermissions`). Project settings cannot grant that mode (Claude Code
# 2.1.299 ignores it there), and `*yolo` typed into an open session cannot switch it. So `tfyolo`
# turns YOLO on (tf-yolo.sh on: the git-write ban stays, OpenCode stops asking too), starts Claude in
# this terminal, and turns YOLO off again when that session ends, however it ends.
#
# It refuses outside a TechieFlow project: the hooks that keep git writes refused live in the
# project, and bypass mode without them would let a commit through.
# The `tfyolo` command itself is a shell function put in ~/.bashrc / ~/.zshrc by tf-yolo-alias.sh.
# Exit: claude's own exit code; 2 when it could not start.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
if [[ ! -f "$ROOT/.tfcore/hooks/block-git.sh" || ! -f "$ROOT/.claude/settings.json" ]]; then
  echo "tfyolo: $ROOT is not a TechieFlow project with its Claude Code hooks (no .tfcore/hooks/block-git.sh or .claude/settings.json); not starting in bypass mode." >&2
  exit 2
fi
grep -q 'block-git.sh' "$ROOT/.claude/settings.json" 2>/dev/null || {
  echo "tfyolo: $ROOT/.claude/settings.json does not register block-git.sh, so git writes would not be refused; run update-framework.sh on this project first." >&2
  exit 2
}
CLAUDE_BIN="${TF_CLAUDE_BIN:-$(command -v claude 2>/dev/null)}"
[[ -n "$CLAUDE_BIN" ]] || { echo "tfyolo: the claude command is not on PATH" >&2; exit 2; }

export CLAUDE_PROJECT_DIR="$ROOT"
bash "$HERE/tf-yolo.sh" on --source tfyolo >/dev/null
off() { CLAUDE_PROJECT_DIR="$ROOT" bash "$HERE/tf-yolo.sh" off >/dev/null 2>&1; }
trap 'off' EXIT
trap 'off; exit 130' INT TERM

echo "tfyolo: YOLO on, Claude Code starting in bypass mode in $ROOT (git writes stay refused; YOLO goes off when this session ends)"
cd "$ROOT" || exit 2
"$CLAUDE_BIN" --permission-mode bypassPermissions "$@"
rc=$?
echo "tfyolo: session ended; YOLO off"
exit $rc

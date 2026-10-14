#!/usr/bin/env bash
# TechieFlow PreToolUse hook — while YOLO is on, nothing asks (owner, 2026-10-14: "When I am running
# something in YOLO mode I am expecting that it doesn't ask me for permission whatever the case is").
#
# While the flag is live (TF_YOLO=1, or .tfcore/.session/yolo.json not expired — tf-yolo.sh is-on
# decides) it answers every tool call with permissionDecision "allow", in the session already
# running. A refusal still wins: the other PreToolUse hooks (block-git.sh for version-control
# writes, guard-build.sh, guard-db.sh …) exit 2 and the call is blocked, and the deny rules in
# settings.json still apply. Claude Code still asks where a hook's allow is not enough (an ask rule,
# its own safety checks); only a session started with `claude --permission-mode bypassPermissions`
# drops those, and project settings cannot set that mode (Claude Code refuses it there).
# While YOLO is off it says nothing, and puts the OpenCode config back if a flag expired or went
# away without `off` (tf-yolo.sh sync).
#
# Wired in .claude/settings.json → hooks.PreToolUse (matcher "*"). OpenCode's side is the plugin's
# permission.ask and the OpenCode config tf-yolo.sh rewrites. Fails OPEN: no output, exit 0.

cat >/dev/null
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
YOLO="$ROOT/.tfcore/utils/tf-yolo.sh"
[[ -f "$YOLO" ]] || exit 0
if CLAUDE_PROJECT_DIR="$ROOT" bash "$YOLO" is-on >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"TechieFlow YOLO is on: no permission prompts (tf-yolo.sh off to end it)"}}'
elif [[ -f "$ROOT/.tfcore/.session/yolo-perms.json" ]]; then
  CLAUDE_PROJECT_DIR="$ROOT" bash "$YOLO" sync >/dev/null 2>&1
fi
exit 0

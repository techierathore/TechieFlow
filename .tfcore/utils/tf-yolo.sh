#!/usr/bin/env bash
# tf-yolo.sh — YOLO / goal-mode state for TechieFlow (rule: .tfcore/tasks/_yolo-mode.md)
#
#   bash .tfcore/utils/tf-yolo.sh on [--source <who>] [--goal "<text>"]   turn YOLO on
#   bash .tfcore/utils/tf-yolo.sh off                                     turn YOLO off
#   bash .tfcore/utils/tf-yolo.sh status                                  print ON/OFF + details (exit 0 always)
#   bash .tfcore/utils/tf-yolo.sh is-on                                   exit 0 if ON, 1 if OFF (for scripts/hooks)
#   bash .tfcore/utils/tf-yolo.sh done [complete|blocked] ["<summary>"]   goal finished → write the sentinel
#                                                                         the tf-goal.sh supervisor stops on
#   bash .tfcore/utils/tf-yolo.sh clear-done                              remove the sentinel (supervisor does this)
#
# YOLO is ON when ANY of these holds (checked in this order by block-git.sh too):
#   1. env TF_YOLO=1                      (tf-goal.sh exports it for the whole run)
#   2. .tfcore/.session/yolo.json exists (written by `on`; the agent writes it on *yolo / a goal)
#   3. the harness itself is in bypass mode (Claude Code permission_mode=bypassPermissions —
#      only the hook can see that; this script cannot)
#
# State lives under .tfcore/.session/ — gitignored in the framework repo and, in
# consumer apps, inside the ignored .tfcore/ block. Nothing here is ever committed.
#
# NO VETO: this script never fails a phase. Every path exits 0 except `is-on`,
# whose non-zero exit is its answer, not an error.

set -u

ROOT="${CLAUDE_PROJECT_DIR:-${TF_PROJECT_DIR:-}}"
if [[ -z "$ROOT" ]]; then
  # walk up from cwd to the nearest .tfcore/
  d="$PWD"
  while [[ "$d" != "/" ]]; do
    if [[ -d "$d/.tfcore" ]]; then ROOT="$d"; break; fi
    d="$(dirname "$d")"
  done
fi
ROOT="${ROOT:-$PWD}"
STATE_DIR="$ROOT/.tfcore/.session"
FLAG="$STATE_DIR/yolo.json"
DONE="$STATE_DIR/goal-done.json"

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
json_escape() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "${1//\"/\\\"}"; }

cmd="${1:-status}"; shift || true

case "$cmd" in
  on)
    SOURCE="agent"; GOAL=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --source) SOURCE="${2:-agent}"; shift 2 ;;
        --goal) GOAL="${2:-}"; shift 2 ;;
        *) shift ;;
      esac
    done
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    {
      printf '{"on":true,"since":"%s","source":%s,"goal":%s,"harness":%s}\n' \
        "$(now_utc)" "$(json_escape "$SOURCE")" "$(json_escape "$GOAL")" "$(json_escape "${TF_HARNESS:-claude-code}")"
    } > "$FLAG" 2>/dev/null || true
    rm -f "$DONE" 2>/dev/null || true
    echo "YOLO: ON (source=$SOURCE) — no confirmations; deletes + read-only git allowed; git WRITES still blocked; run to completion."
    ;;
  off)
    rm -f "$FLAG" 2>/dev/null || true
    echo "YOLO: OFF — back to ask-on-delete, no-git, confirm-at-phase-boundaries."
    ;;
  is-on)
    if [[ "${TF_YOLO:-0}" == "1" || -f "$FLAG" ]]; then exit 0; else exit 1; fi
    ;;
  status)
    if [[ "${TF_YOLO:-0}" == "1" ]]; then
      echo "YOLO: ON (env TF_YOLO=1)"
    elif [[ -f "$FLAG" ]]; then
      echo "YOLO: ON ($(cat "$FLAG" 2>/dev/null))"
    else
      echo "YOLO: OFF"
    fi
    if [[ -f "$DONE" ]]; then echo "GOAL-DONE: $(cat "$DONE" 2>/dev/null)"; fi
    ;;
  done)
    OUTCOME="${1:-complete}"; SUMMARY="${2:-}"
    case "$OUTCOME" in complete|blocked) ;; *) SUMMARY="$OUTCOME $SUMMARY"; OUTCOME="complete" ;; esac
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    printf '{"outcome":%s,"summary":%s,"ts":"%s"}\n' \
      "$(json_escape "$OUTCOME")" "$(json_escape "$SUMMARY")" "$(now_utc)" > "$DONE" 2>/dev/null || true
    echo "GOAL-DONE ($OUTCOME) recorded at $DONE — the supervisor (tf-goal.sh) will stop."
    ;;
  clear-done)
    rm -f "$DONE" 2>/dev/null || true
    ;;
  *)
    echo "usage: tf-yolo.sh on|off|status|is-on|done [complete|blocked] [summary]|clear-done" >&2
    ;;
esac
exit 0

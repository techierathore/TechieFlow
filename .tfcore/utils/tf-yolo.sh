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

# A flag nobody turned off EXPIRES. `off` and `done` clear it, but a session that
# is killed, crashes, or simply ends without the sentinel leaves it behind, and an
# unnoticed flag silently grants unprompted deletes for as long as it sits there
# (found on five repos, one of them 6 days old, 2026-08-28). Age is taken from the
# file's mtime via `find -mmin`, which behaves the same on GNU and BSD — parsing
# the ISO `since` field would need `date -d`, which does not exist on macOS.
# Override with TF_YOLO_TTL_HOURS; 0 disables expiry. tf-goal.sh is unaffected —
# it exports TF_YOLO=1, which is checked first and never expires mid-run.
TTL_HOURS="${TF_YOLO_TTL_HOURS:-24}"
flag_live() {  # exit 0 = flag present AND not expired
  [[ -f "$FLAG" ]] || return 1
  [[ "$TTL_HOURS" == "0" ]] && return 0
  [[ -n "$(find "$FLAG" -mmin "+$(( TTL_HOURS * 60 ))" 2>/dev/null)" ]] && return 1
  return 0
}
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
    if [[ "${TF_YOLO:-0}" == "1" ]] || flag_live; then exit 0; else exit 1; fi
    ;;
  status)
    if [[ "${TF_YOLO:-0}" == "1" ]]; then
      echo "YOLO: ON (env TF_YOLO=1)"
    elif flag_live; then
      echo "YOLO: ON ($(cat "$FLAG" 2>/dev/null))"
    elif [[ -f "$FLAG" ]]; then
      echo "YOLO: OFF (flag EXPIRED after ${TTL_HOURS}h and is ignored — $(cat "$FLAG" 2>/dev/null)). Run 'tf-yolo.sh off' to delete it, or 'on' to start a fresh window."
    else
      echo "YOLO: OFF"
    fi
    if [[ -f "$DONE" ]]; then echo "GOAL-DONE: $(cat "$DONE" 2>/dev/null)"; fi
    ;;
  done)
    OUTCOME="${1:-complete}"; SUMMARY="${2:-}"
    case "$OUTCOME" in complete|blocked) ;; *) SUMMARY="$OUTCOME $SUMMARY"; OUTCOME="complete" ;; esac
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    # The sentinel comes AFTER the status gate: on 2026-09-06 an OpenCode build wrote
    # `blocked` with the status file untouched since day-1, every row Not Started and no run
    # record (MISS-TechieFlow-20260906-13). So `done` is refused, without writing the
    # sentinel, while the status file is older than the goal run's start or no run record
    # has been appended since the goal started. Exit stays 0 (no veto); the message says
    # what to finish first. TF_YOLO_DONE_FORCE=1 skips the check (owner use).
    if [[ "${TF_YOLO_DONE_FORCE:-0}" != "1" && -f "$STATE_DIR/goal.json" ]]; then
      _why="$(python3 - "$STATE_DIR/goal.json" "$ROOT" <<'PY2' 2>/dev/null
import json, os, sys, datetime
gj, root = sys.argv[1], sys.argv[2]
try:
    started = json.load(open(gj)).get("started") or ""
    t0 = datetime.datetime.strptime(started[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=datetime.timezone.utc).timestamp()
except Exception:
    sys.exit(0)
why = []
ps = os.path.join(root, "PROJECT-STATUS" + ".md")
if os.path.isfile(ps) and os.path.getmtime(ps) < t0 - 60:
    why.append("the status file has not been written since this goal run started (%s)" % started)
# The run record must be for the command the phase marker names (tf-phase.sh start <cmd>):
# a verify-phase record alone let a build close without its build-phase record
# (MISS-TechieFlow-20260906-15).
want_cmd = None
try:
    pj = os.path.join(root, ".tfcore", ".session", "phase.json")
    if os.path.isfile(pj) and os.path.getmtime(pj) >= t0 - 60:
        want_cmd = (json.load(open(pj)) or {}).get("cmd") or None
except Exception:
    want_cmd = None
runs = os.path.join(root, "docs", "metrics", "runs.jsonl"); last = None; last_cmd = None
try:
    for line in open(runs, encoding="utf-8", errors="replace"):
        try: r = json.loads(line)
        except Exception: continue
        ts = r.get("ts")
        if not ts: continue
        try:
            te = datetime.datetime.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=datetime.timezone.utc).timestamp()
        except Exception:
            continue
        if te >= t0 - 60:
            last = ts
            if want_cmd and r.get("kind") == "run" and r.get("cmd") == want_cmd:
                last_cmd = ts
except Exception:
    pass
if os.path.isfile(runs):
    if last is None:
        why.append("no run record has been appended to docs/metrics/runs.jsonl since the goal started")
    elif want_cmd and last_cmd is None:
        why.append("no run record for %s (the command the phase marker names) has been appended since the goal started" % want_cmd)
print("; ".join(why))
PY2
)"
      if [[ -n "$_why" ]]; then
        echo "GOAL-DONE refused: the status gate has not run — $_why. Finish the gate (_status-update-gate.md: the status file, its HTML, the checker, the run record), then run this command again. Nothing was written."
        exit 0
      fi
    fi
    printf '{"outcome":%s,"summary":%s,"ts":"%s"}\n' \
      "$(json_escape "$OUTCOME")" "$(json_escape "$SUMMARY")" "$(now_utc)" > "$DONE" 2>/dev/null || true
    # The grant ENDS WITH THE GOAL. Until 2026-08-28 `done` left the flag in place,
    # so even the well-behaved path — the one _yolo-mode.md §Completion prescribes as
    # the last action of every run — left the repo permanently in YOLO, with deletes
    # unprompted and read-only git open and nothing on screen saying so. The
    # supervisor reads $DONE, never $FLAG, so clearing it here stops nothing.
    rm -f "$FLAG" 2>/dev/null || true
    echo "GOAL-DONE ($OUTCOME) recorded at $DONE — the supervisor (tf-goal.sh) will stop. YOLO flag cleared."
    ;;
  clear-done)
    rm -f "$DONE" 2>/dev/null || true
    ;;
  *)
    echo "usage: tf-yolo.sh on|off|status|is-on|done [complete|blocked] [summary]|clear-done" >&2
    ;;
esac
exit 0

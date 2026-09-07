#!/usr/bin/env bash
# tf-phase.sh — mark which TechieFlow command is running (Sitting 4b, 2026-09-05).
#
#   bash .tfcore/utils/tf-phase.sh start <command> [App]   # step 0 of every task: prints the start
#                                                          # time and writes the marker
#   bash .tfcore/utils/tf-phase.sh show                    # prints the marker, or "none"
#   bash .tfcore/utils/tf-phase.sh end                     # removes the marker
#   bash .tfcore/utils/tf-phase.sh goal [App]              # tf-goal.sh only: an unclaimed marker the first
#                                                          # command's `start` claims, keeping its started
#
# The marker is .tfcore/.session/phase.json:
#   {"cmd":"build-phase","app":"MyApp","started":"2026-09-05T16:19:38Z"}
# Who reads it:
#   - .tfcore/hooks/guard-db.sh: a migration runner is allowed only while the marker says
#     build-phase or fix-issues (MISS-TechieFlow-20260905-09: day-1 patched a database).
#   - tf-emit.sh: a run record that leaves `started` out gets it from here, so the start
#     time is a measurement, never reconstructed.
# A marker older than 24 h is ignored by the readers (a killed session must not keep a
# grant alive). The next `start` overwrites; `end` is optional tidiness.
# Never committed: .tfcore/.session/ is git-ignored. Exit 0 always except a usage error (2).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$ROOT/.tfcore/.session"
FILE="$DIR/phase.json"
case "${1:-}" in
  start)
    CMD="${2:-}"
    [[ -z "$CMD" ]] && { echo "tf-phase: usage: tf-phase.sh start <command> [App]" >&2; exit 2; }
    CMD="${CMD#\*}"
    APP="${3:-}"
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$DIR"
    # A supervisor (tf-goal.sh) writes an unclaimed marker {"cmd":"goal",…} when its first cycle
    # starts. The first command of that run claims it and KEEPS its started: the run began when
    # the harness began reading, not when the agent got round to step 0 (MISS-TechieFlow-20260905-20:
    # a 38-minute stage 2 recorded a 27-second run because step 0 ran last).
    if [[ -f "$FILE" ]] && grep -q '"cmd":"goal"' "$FILE" && [[ -z "$(find "$FILE" -mmin +1440 2>/dev/null)" ]]; then
      NOW="$(sed -n 's/.*"started":"\([^"]*\)".*/\1/p' "$FILE")"
      echo "tf-phase: started taken from the supervisor's marker ($NOW)" >&2
    fi
    printf '{"cmd":"%s","app":"%s","started":"%s"}\n' "$CMD" "$APP" "$NOW" > "$FILE"
    echo "$NOW"
    echo "tf-phase: $CMD${APP:+ $APP} started $NOW (marker .tfcore/.session/phase.json)" >&2
    # The document-check baseline (Sitting 4c, 2026-09-06): the findings the checklists and the
    # status file already carry when the command starts are recorded, so the gate and the Stop
    # hook block only on findings this command introduces (Schemas §7.1 decision 8: old projects
    # are repaired through *amend-docs, never by whichever command happens to run next).
    if [[ -x "$ROOT/.tfcore/utils/tf-doc-check.sh" || -f "$ROOT/.tfcore/utils/tf-doc-check.sh" ]]; then
      docs=(); for f in "$ROOT"/docs/*-Checklist.md "$ROOT"/PROJECT-STATUS.md; do [[ -f "$f" ]] && docs+=("$f"); done
      if [[ ${#docs[@]} -gt 0 ]]; then
        ( cd "$ROOT" && bash .tfcore/utils/tf-doc-check.sh --root "$ROOT" --baseline-write "${docs[@]}" 2>/dev/null | tail -1 >&2 ) || true
      fi
    fi
    ;;
  goal)
    # written by tf-goal.sh at the start of a run's first cycle; claimed by the first `start`
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$DIR"
    printf '{"cmd":"goal","app":"%s","started":"%s"}\n' "${2:-}" "$NOW" > "$FILE"
    echo "$NOW"
    ;;
  show)
    if [[ -f "$FILE" ]]; then cat "$FILE"; else echo "none"; fi
    ;;
  end)
    rm -f "$FILE"
    echo "tf-phase: marker removed"
    ;;
  *)
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
exit 0

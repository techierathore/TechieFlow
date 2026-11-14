#!/usr/bin/env bash
# tf-verify-emit.sh — the telemetry of a verify run, from its verdict file (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-emit.sh <App> [--dir tests/.artifacts/verify] [--started <ISO>]
#
# Reads <dir>/verdicts.json (written by tf-verify-verdict.sh) and appends, through tf-emit.sh only:
#   gates.jsonl   one record per row that passed or failed a check: the first failing check (or null),
#                 the checks that ran, the failure class, the prior status, the attempt number
#   misses.jsonl  one `miss` per failing row that has no open miss of the same class (the duplicate
#                 check is tf-emit.sh --open-miss); origin = the last build or fix run that touched
#                 the row, looked up in runs.jsonl, or left out when there is none
#   runs.jsonl    one `run` record for the verify pass: cmd verify-phase, the rows touched, the build
#                 result, whether YOLO was on
# Run and gate records carry app_phase, the phase whose checklist was graded (list.json). A second pass
# of one *verify --phase all starts where the first one's record ended (Sevak TF-005).
# Rows the run could not grade (not tested, not observable, not driven) get no record. Telemetry
# never blocks: a refused record is printed and the script still exits 0.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -ge 1 && "$1" != "-h" && "$1" != "--help" ]] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 3; }
APP="$1"; shift
DIR="tests/.artifacts/verify"; MODE=""; STARTED=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 ;;
    --started) STARTED="${2:-}"; shift 2 ;;
    *) echo "tf-verify-emit: unknown argument $1" >&2; exit 3 ;;
  esac
done
[[ -f "$DIR/verdicts.json" ]] || { echo "tf-verify-emit: $DIR/verdicts.json missing; run tf-verify-verdict.sh first" >&2; exit 2; }
YOLO=false; bash "$HERE/tf-yolo.sh" is-on >/dev/null 2>&1 && YOLO=true
[[ -z "$STARTED" ]] && STARTED="$(bash "$HERE/tf-phase.sh" show 2>/dev/null | sed -n 's/.*"started":"\([^"]*\)".*/\1/p')"

TF_APP="$APP" TF_DIR="$DIR" TF_MODE="$MODE" TF_STARTED="$STARTED" TF_YOLO="$YOLO" TF_EMIT="$HERE/tf-emit.sh" python3 "$HERE/tf-verify-emit.py"
exit 0

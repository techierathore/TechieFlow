#!/usr/bin/env bash
# tf-verify-list.sh — the working list of a verify run (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-list.sh <App> <scope> [--phase N|all] [--json-out <file>]
#
# --phase N grades phase N's checklist (default appPhase); --phase all prints the phases to grade, in
# order, and writes nothing (Sevak TF-005).
# scope: ui · functional · all · a comma list of REQ ids. Prints every row to grade with its
# acceptance line, screen, route, mockup and perf budget, the screens to drive, and the test
# users; writes tests/.artifacts/verify/list.json for the other verify scripts. Skips N/A rows
# only. Writes nothing else. See tf-verify-list.py for the details.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "tf-verify-list: python3 is required" >&2; exit 2; }
# Chatur, 14 Nov 2026: three verifies chained in *triage-and-fix ran without step 0's mark, so their run records
# covered seconds each and their time was counted under the triage. This is the verify's first script, so when
# the marker is not a verify's own (none, another command's, or older than a day) it marks the verify here; the
# verify's emit ends that mark (tf-verify-emit.sh). Only for the project these scripts belong to.
if [[ $# -ge 1 && "$(cd "$HERE/../.." && pwd -P)" == "$(pwd -P)" ]]; then
  MK="$(cd "$HERE/../.." && pwd)/.tfcore/.session/phase.json"
  if [[ "$(sed -n 's/.*"cmd":"\([^"]*\)".*/\1/p' "$MK" 2>/dev/null)" != verify-phase || -n "$(find "$MK" -mmin +1440 2>/dev/null)" ]]; then
    NOW="$(TF_SKIP_SELFCHECK=1 bash "$HERE/tf-phase.sh" start verify-phase "$1" 2>/dev/null | head -1)"
    [[ -n "$NOW" ]] && printf '%s\n' "$NOW" > "$(dirname "$MK")/verify-auto" \
      && echo "tf-verify-list: this verify had no start mark of its own (step 0 was skipped); marked now, $NOW, so its run record covers it" >&2
  fi
fi
exec python3 "$HERE/tf-verify-list.py" "$@"

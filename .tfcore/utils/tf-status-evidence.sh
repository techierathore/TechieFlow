#!/usr/bin/env bash
# tf-status-evidence.sh — the evidence *refresh-status rebuilds PROJECT-STATUS from, after a
# session died before its status gate (Sitting 4b, 2026-09-06). Reads only; never git.
#
#   bash .tfcore/utils/tf-status-evidence.sh <App> [--no-build] [--phase N]
#
# Prints, in this order:
#   1. what the stale PROJECT-STATUS.md claims (last_updated, current_phase, the next command)
#   2. files under src/ and tests/ changed after that file was last written (work the gate never saw)
#   3. checklist rows left at Implemented / In Progress / Needs re-verify / PARTIAL / FAIL
#      (the fingerprint of a smoke that ran and a verify that did not)
#   4. the build verdict from tf-build.sh (skipped with --no-build)
# Then the agent decides the interruption signature and runs tf-status-facts.sh for the gate.
set -uo pipefail
APP="${1:-}"; [[ -z "$APP" ]] && { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }
shift
BUILD=1; PHASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) BUILD=0; shift ;;
    --phase) PHASE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -z "$PHASE" ]] && PHASE="$(grep -oE '^appPhase:\s*[0-9]+' .tfcore/core-config.yaml 2>/dev/null | grep -oE '[0-9]+' || echo 1)"
[[ "$PHASE" -le 1 ]] && CL="docs/${APP}-Checklist.md" || CL="docs/${APP}-P${PHASE}-Checklist.md"
ST="PROJECT-STATUS.md"

echo "# tf-status-evidence — $APP — $(date -u +%Y-%m-%dT%H:%M:%SZ) — phase $PHASE"
echo
echo "## 1. What the stale status file claims (a hypothesis, not a fact)"
if [[ -f "$ST" ]]; then
  grep -E '^(last_updated|current_phase|last_verified_build|last_verified_date):' "$ST" | sed 's/^/- /'
  awk '/^## Next command to run/{p=1;next} /^## /{p=0} p' "$ST" | grep -E '^\s*/' | sed 's/^\s*/- next: /' | head -2
  echo "- written: $(date -u -r "$ST" +%Y-%m-%dT%H:%M:%SZ)"
else
  echo "- no PROJECT-STATUS.md; treat as never written"
fi
echo
echo "## 2. Files changed after the status file was written (src/ and tests/, newest first)"
if [[ -f "$ST" ]]; then
  mapfile -t NEWER < <(find src tests -type f -newer "$ST" \
      -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' -not -path '*/.artifacts/*' 2>/dev/null \
      | xargs -r ls -t 2>/dev/null)
  echo "- ${#NEWER[@]} file(s)"
  printf -- '- %s\n' "${NEWER[@]:0:30}"
  [[ ${#NEWER[@]} -gt 30 ]] && echo "- (${#NEWER[@]} in total; the rest with: find src tests -type f -newer PROJECT-STATUS.md)"
else
  echo "- no status file to compare against"
fi
echo
echo "## 3. Checklist rows that look interrupted ($CL)"
if [[ -f "$CL" ]]; then
  grep -E '^\s*\|\s*`?REQ-' "$CL" | awk -F'|' '{id=$2; st=$4; gsub(/^[ `*]+|[ `*]+$/,"",id); gsub(/^[ ]+|[ ]+$/,"",st); print id" — "st}' \
    | grep -iE ' — (Implemented|In Progress|Needs re-verify|PARTIAL|FAIL)' | sed 's/^/- /' | head -40
  n=$(grep -E '^\s*\|\s*`?REQ-' "$CL" | awk -F'|' '{print $4}' | grep -ciE 'Implemented|In Progress|Needs re-verify|PARTIAL|FAIL' || true)
  [[ "$n" == "0" ]] && echo "- none: every row is terminal, Blocked or not started"
else
  echo "- $CL does not exist"
fi
echo
echo "## 4. Build"
if [[ $BUILD -eq 1 ]]; then
  bash "$(dirname "${BASH_SOURCE[0]}")/tf-build.sh" build 2>&1 | tail -3 | sed 's/^/- /'
else
  echo "- skipped (--no-build)"
fi
exit 0

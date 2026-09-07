#!/usr/bin/env bash
# tests/requirements/run.sh — grade the framework against its OWN checklist.
#
# `docs/TechieFlow-Requirements.md` is the framework's checklist: 63 lines, each with a stated
# way to prove it. Until 2026-09-07 nothing ever ran it, so the framework demanded of every
# application a verification it never performed on itself, and its metrics reported "no data"
# for first-pass rate as though it had no requirements at all. It has 63.
#
# WHAT THIS GRADES, and what it refuses to grade. A line is graded ONLY when its own Check
# column names something runnable — a self-test, a utility script, or an npm script. That
# artefact is run, and its exit status is the line's verdict. A line whose check is a fixture
# run (a real command on a real project) or a review (a person reads something) is NOT graded:
# it is reported as ungraded with the reason. Guessing there would be worse than the silence it
# replaces, and the ungraded count is the honest measure of how much of this checklist still
# rests on someone remembering.
#
#   bash tests/requirements/run.sh            grade and print
#   bash tests/requirements/run.sh --emit     also append one gate record per graded line
#
# Exit 0 when no graded line failed.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
EMIT=0; [[ "${1:-}" == "--emit" ]] && EMIT=1
cd "$ROOT" || exit 2

REQ_DOC="docs/TechieFlow-Requirements.md"
[[ -f $REQ_DOC ]] || { echo "no $REQ_DOC"; exit 2; }

# ---- run each distinct artefact once, cache its exit status -----------------------------
declare -A ARTEFACT_RC
run_artefact() {
  local key="$1" cmd="$2"
  if [[ -z "${ARTEFACT_RC[$key]:-}" ]]; then
    if bash -c "$cmd" >/dev/null 2>&1; then ARTEFACT_RC[$key]=0; else ARTEFACT_RC[$key]=1; fi
    echo "  ran ${key} -> $([[ ${ARTEFACT_RC[$key]} -eq 0 ]] && echo pass || echo FAIL)" >&2
  fi
  return "${ARTEFACT_RC[$key]}"
}

# The Check column names these; each maps to the command that runs it.
artefact_cmd() {
  case "$1" in
    tests/mirror/run.sh)     echo "bash tests/mirror/run.sh" ;;
    tests/doc-check/run.sh)  echo "bash tests/doc-check/run.sh" ;;
    tests/bugs/run.sh)       echo "bash tests/bugs/run.sh" ;;
    tests/verify/run.sh)     echo "bash tests/verify/run.sh" ;;
    tests/goal/run.sh)       echo "bash tests/goal/run.sh" ;;
    "npm run test:install")  echo "npm run test:install" ;;
    *)                       echo "" ;;
  esac
}

echo "Grading the framework against $REQ_DOC"
echo ""

graded=0; passed=0; failed=0; ungraded=0
declare -a EMIT_LINES=()
RUN_ID="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# The purpose-built checks for lines whose Check column described a script nobody had written.
# shellcheck source=/dev/null
source "$HERE/checks.sh"

while IFS=$'\t' read -r fid kind artefact; do
  [[ -n "$fid" ]] || continue

  # A purpose-built check wins: it proves the line directly.
  fn="fr_$(tr -d 'FR-' <<<"$fid")"
  if declare -F "$fn" >/dev/null; then
    graded=$((graded+1))
    if "$fn" 2>/dev/null; then
      verdict="Verified"; gate="null"; passed=$((passed+1))
    else
      verdict="FAIL"; gate='"acceptance"'; failed=$((failed+1))
    fi
    printf '%-7s %-11s %-22s %s\n' "$fid" "$verdict" "checks.sh:$fn" "purpose-built check"
    EMIT_LINES+=("{\"kind\":\"gate\",\"run_id\":\"$RUN_ID\",\"req_id\":\"$fid\",\"req_class\":\"FR\",\"verdict\":\"$verdict\",\"gate\":$gate,\"gates_run\":[\"acceptance\"],\"proof\":\"tests/requirements/checks.sh:$fn\"}")
    continue
  fi
  # FR-63's own check says to run it on a normal filesystem: on a Windows mount every file
  # reports mode 777, so the installer marks a file executable where the shell route does not
  # and the comparison shows one false difference. Grading it here would record a failure the
  # code does not have, so it is reported ungraded with the reason instead.
  if [[ "$artefact" == "npm run test:install" && "$ROOT" == /mnt/* ]]; then
    ungraded=$((ungraded+1))
    printf '%-7s %-11s %-22s %s\n' "$fid" "ungraded" "-" "needs a normal filesystem, not a Windows mount"
    continue
  fi
  if [[ -n "$artefact" ]]; then
    cmd="$(artefact_cmd "$artefact")"
    if [[ -n "$cmd" ]]; then
      graded=$((graded+1))
      if run_artefact "$artefact" "$cmd"; then
        verdict="Verified"; gate="null"; passed=$((passed+1))
      else
        verdict="FAIL"; gate='"acceptance"'; failed=$((failed+1))
      fi
      printf '%-7s %-11s %-22s %s\n' "$fid" "$verdict" "$artefact" "$kind"
      EMIT_LINES+=("{\"kind\":\"gate\",\"run_id\":\"$RUN_ID\",\"req_id\":\"$fid\",\"req_class\":\"FR\",\"verdict\":\"$verdict\",\"gate\":$gate,\"gates_run\":[\"acceptance\"],\"proof\":\"$artefact\"}")
      continue
    fi
  fi
  ungraded=$((ungraded+1))
  printf '%-7s %-11s %-22s %s\n' "$fid" "ungraded" "-" "$kind"
done < <(python3 - "$REQ_DOC" <<'PY'
import re, sys
for line in open(sys.argv[1]):
    m = re.match(r'^\|\s*(FR-\d+)\s*\|(.*)$', line)
    if not m: continue
    cells = [c.strip() for c in m.group(2).split('|')]
    check = cells[1] if len(cells) > 1 else ""
    low = check.lower()
    if "script candidate" in low:            kind = "script candidate, not built"
    elif low.startswith("fixture run"):      kind = "needs a fixture run"
    elif low.startswith("review"):           kind = "needs a review"
    elif low.startswith("script"):           kind = "script"
    else:                                     kind = "other"
    art = ""
    for cand in ("tests/mirror/run.sh", "tests/doc-check/run.sh", "tests/bugs/run.sh",
                 "tests/verify/run.sh", "tests/goal/run.sh", "npm run test:install"):
        if cand in check:
            art = cand; break
    if not art and kind == "script":
        kind = "script described, no runnable artefact named"
    print(f"{m.group(1)}\t{kind}\t{art}")
PY
)

total=$((graded + ungraded))
echo ""
echo "framework requirements: $total lines · graded $graded (passed $passed, failed $failed) · ungraded $ungraded"
echo "  ungraded means the line's own check is a fixture run, a review, or a script that was"
echo "  described but never written. It is not a pass and it is not a failure."

if [[ $EMIT -eq 1 && ${#EMIT_LINES[@]} -gt 0 ]]; then
  printf '%s\n' "${EMIT_LINES[@]}" | bash .tfcore/utils/tf-emit.sh gates
  echo "emitted ${#EMIT_LINES[@]} gate record(s) under run_id $RUN_ID"
fi

[[ $failed -eq 0 ]]

#!/usr/bin/env bash
# tests/bugs/run.sh — self-test for the bug scripts (Sitting 4c, 2026-09-06): tf-triage.sh,
# tf-log-miss.sh, tf-fix-close.sh and the checklist edits they share (tf-checklist-edit.py).
# Uses the verify fixture (tests/verify/make-fixtures.py). Checks:
#   1. triage demote: Needs re-verify, % capped at 75, a dated UAT remark in the reporter's words
#   2. triage new: the next free id, a Not Started row, a detail entry with the acceptance line and
#      BRD-pending under the named section; the checker prints no FAIL for it
#   3. triage note: a remark, no status change
#   4. triage close: one escaped gate record per row, one miss per row with the symptom as `what`
#      (regression when the row was Verified; unspecified-gap on brd for a new row), the run record,
#      a warning and an instruction-ignored miss when code changed during the triage; a second
#      close adds no duplicate
#   5. log-miss: refused without --sort (the four questions printed); the record with the sentence
#      and the sort, the row demoted with a ⚠ miss remark, the run record; a repeat is reported not
#      re-logged; --new adds a Not Started row; --fixed closes at once
#   5b. the readable file (FR-31, Session 5): docs/FxApp-Misses.md and its HTML exist, one row per
#      miss record, the sentence and whose gap in the row, a fixed miss under Fixed; a miss emitted
#      without a sort is sorted later with tf-emit.sh --amend and the file follows; triage misses
#      carry the default sorts (weak-check for a demoted row, spec for a new row, ignored for the
#      code edit)
#   6. fix-close: the fix-issues run record first, then one miss-fix per row with the verifier's
#      verdict from the ledger; a row with no open miss is named, not invented
# Telemetry goes to the fixture only (TF_METRICS_ROOT). Run: bash tests/bugs/run.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
export TF_FIXTURE_DIR="$ROOT/tests/.artifacts/verify-fixture"
APP="$(python3 "$ROOT/tests/verify/make-fixtures.py")" || { echo "could not build the fixture"; exit 2; }
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $*"; }
bad() { fail=$((fail+1)); echo "FAIL $*"; }
check() { if [[ "$2" == 0 ]]; then ok "$1"; else bad "$1"; fi; }
has() { grep -q -- "$2" <<<"$1"; echo $?; }
cd "$APP" || exit 2
export TF_METRICS_ROOT="$APP"; unset CLAUDE_PROJECT_DIR; export TF_PROJECT_DIR="$APP"
U=".tfcore/utils"; CL="docs/FxApp-Checklist.md"; M="docs/metrics"
cell() { grep -E "^\| $1 \|" "$CL" | cut -d'|' -f"$2" | sed 's/^ *//; s/ *$//'; }

# ---- 1-3. triage edits ----------------------------------------------------------------------
S1="$(bash $U/tf-phase.sh start triage-issues FxApp 2>/dev/null)"
sleep 1
out="$(bash $U/tf-triage.sh FxApp demote REQ-UI-003 "Save and Cancel sit on top of each other" --kind layout --evidence uat/editor.png 2>&1)"; rc=$?
check "demote runs (exit $rc): $out" "$rc"
check "demote: status Needs re-verify" "$([[ "$(cell REQ-UI-003 4)" == "Needs re-verify" ]]; echo $?)"
check "demote: % capped at 75" "$([[ "$(cell REQ-UI-003 5)" == "75%" ]]; echo $?)"
check "demote: dated UAT remark in the reporter's words" "$(has "$(cell REQ-UI-003 6)" "⚠ UAT bug $(date +%F): Save and Cancel sit on top of each other (evidence: uat/editor.png; kind: layout)")"
out="$(bash $U/tf-triage.sh FxApp new "Export entries" "When the user taps Export on Entries, then a file downloads." --section Entries --evidence uat/export.png 2>&1)"; rc=$?
check "new runs (exit $rc): $out" "$rc"
check "new: next free id REQ-FN-010, Not Started, 0%" "$([[ "$(cell REQ-FN-010 4)" == "Not Started" && "$(cell REQ-FN-010 5)" == "0%" ]]; echo $?)"
check "new: detail entry with BRD-pending under Entries" "$(python3 - <<'PY'
import re,sys
t=open("docs/FxApp-Checklist.md",encoding="utf-8").read()
sec=t.split("## Entries",1)[1].split("\n## ",1)[0]
ok = 'id="d-req-fn-010"' in sec and "(BRD-pending)" in sec and "*Acceptance:* When the user taps Export on Entries" in sec
sys.exit(0 if ok else 1)
PY
echo $?)"
chk="$(bash $U/tf-doc-check.sh --strict "$CL" 2>&1)"
check "checker: no FAIL on the new row (BRD-pending is a WARN)" "$([[ "$(grep -c 'FAIL.*REQ-FN-010' <<<"$chk")" == 0 && "$(grep -c 'WARN.*REQ-FN-010.*BRD-pending' <<<"$chk")" == 1 ]]; echo $?)"
out="$(bash $U/tf-triage.sh FxApp note REQ-UI-001 "could not reproduce: opened Home twice, list shows three entries" 2>&1)"; rc=$?
check "note runs (exit $rc)" "$rc"
check "note: status unchanged, remark appended" "$([[ "$(cell REQ-UI-001 4)" == Implemented ]] && grep -qE "^\| REQ-UI-001 \|.*$(date +%F) triage: could not reproduce" "$CL"; echo $?)"

# ---- 4. triage close ----------------------------------------------------------------------------
mkdir -p src && echo "// edited during triage" > src/Oops.cs
out="$(bash $U/tf-triage.sh FxApp close --started "$S1" 2>&1)"; rc=$?
check "close runs (exit $rc)" "$rc"
check "close: 2 rows logged, 2 escaped gate records, 2 misses, code NOT untouched" "$(has "$out" "triage: 2 row(s) logged — 2 gate record(s) (escaped), 2 miss(es), run record written; code untouched: NO")"
check "close: warns about the edited file and logs it" "$(has "$out" "WARNING: .*src/Oops.cs")"
check "gates: REQ-UI-003 escaped, prior Verified" "$(grep '"req_id":"REQ-UI-003"' $M/gates.jsonl | grep -q '"gate":"escaped".*"prior_verdict":"Verified"\|"prior_verdict":"Verified".*"gate":"escaped"'; echo $?)"
check "miss: REQ-UI-003 is a regression found by the owner with the symptom as what" "$(grep '"req_id":"REQ-UI-003"' $M/misses.jsonl | grep -q '"miss_class":"regression"' && grep '"req_id":"REQ-UI-003"' $M/misses.jsonl | grep -q '"found_by":"owner"' && grep '"req_id":"REQ-UI-003"' $M/misses.jsonl | grep -q '"what":"Save and Cancel sit on top of each other"'; echo $?)"
check "miss: REQ-FN-010 is an unspecified-gap on the brd" "$(grep '"req_id":"REQ-FN-010"' $M/misses.jsonl | grep -q '"miss_class":"unspecified-gap"' && grep '"req_id":"REQ-FN-010"' $M/misses.jsonl | grep -q '"artifact":"brd"'; echo $?)"
check "miss: the code edit is instruction-ignored" "$(grep -c '"why_missed":"instruction-ignored"' $M/misses.jsonl | grep -q '^1$'; echo $?)"
check "run record: cmd triage-issues, started from the marker, not-run" "$(grep '"cmd":"triage-issues"' $M/runs.jsonl | grep -q "\"started\":\"$S1\"" && grep '"cmd":"triage-issues"' $M/runs.jsonl | grep -q '"build_result":"not-run"'; echo $?)"
n1="$(grep -c '"kind":"miss"' $M/misses.jsonl)"
rm -f src/Oops.cs
bash $U/tf-triage.sh FxApp close --started "$S1" >/dev/null 2>&1
n2="$(grep -c '"kind":"miss"' $M/misses.jsonl)"
check "a second close adds no duplicate miss ($n1 → $n2)" "$([[ "$n1" == "$n2" ]]; echo $?)"

# ---- 5. log-miss --------------------------------------------------------------------------------
S2="$(bash $U/tf-phase.sh start log-miss FxApp 2>/dev/null)"
out="$(bash $U/tf-log-miss.sh FxApp --what "The entries list ignores the date filter" --req REQ-UI-002 --class wrong-behaviour 2>&1)"; rc=$?
check "log-miss without --sort is refused (exit $rc) and prints the four questions" "$([[ $rc -eq 2 ]] && [[ "$(has "$out" "1. Did the app's spec say it clearly?")" == 0 ]]; echo $?)"
out="$(bash $U/tf-log-miss.sh FxApp --what "The entries list ignores the date filter" --req REQ-UI-002 --class wrong-behaviour --why instruction-ignored --severity minor --sort ignored 2>&1)"; rc=$?
check "log-miss runs (exit $rc)" "$rc"
check "log-miss: report block names the id, the class and whose gap" "$([[ "$(has "$out" "MISS-FxApp-.*wrong-behaviour / src / minor")" == 0 && "$(has "$out" "Whose gap  : ignored")" == 0 ]]; echo $?)"
check "log-miss: the sentence and the sort are in the record" "$(grep '"what":"The entries list ignores the date filter"' $M/misses.jsonl | grep -q '"sort":"ignored"'; echo $?)"
check "log-miss: row demoted with a ⚠ miss remark" "$([[ "$(cell REQ-UI-002 4)" == "Needs re-verify" ]] && grep -qE "^\| REQ-UI-002 \|.*⚠ miss $(date +%F): The entries list ignores the date filter" "$CL"; echo $?)"
check "log-miss: run record cmd log-miss" "$(grep -q '"cmd":"log-miss"' $M/runs.jsonl; echo $?)"
n1="$(grep -c '"kind":"miss"' $M/misses.jsonl)"
out="$(bash $U/tf-log-miss.sh FxApp --what "The entries list ignores the date filter again" --req REQ-UI-002 --class wrong-behaviour --sort weak-check 2>&1)"
n2="$(grep -c '"kind":"miss"' $M/misses.jsonl)"
check "log-miss: a repeat is reported, not re-logged ($n1 → $n2), and its sort is not overwritten" "$([[ "$n1" == "$n2" ]] && [[ "$(has "$out" "already logged as MISS-FxApp-")" == 0 && "$(has "$out" "sort not amended")" == 0 ]]; echo $?)"
out="$(bash $U/tf-log-miss.sh FxApp --what "Nothing lets the user export a month" --new "Export a month" --acceptance "When the user taps Export month on Timeline, then a file downloads." --section Entries --sort spec 2>&1)"; rc=$?
check "log-miss --new adds a Not Started row (exit $rc)" "$([[ $rc -eq 0 && "$(cell REQ-FN-011 4)" == "Not Started" ]]; echo $?)"
check "log-miss --new: unspecified-gap on the brd, req_id the new row" "$(grep '"req_id":"REQ-FN-011"' $M/misses.jsonl | grep -q '"miss_class":"unspecified-gap"'; echo $?)"
out="$(bash $U/tf-log-miss.sh FxApp --what "The header logo was missing and got fixed yesterday" --req REQ-UI-001 --class partial-implementation --fixed --sort weak-check 2>&1)"; rc=$?
check "log-miss --fixed closes at once and leaves the row alone (exit $rc)" "$([[ $rc -eq 0 && "$(cell REQ-UI-001 4)" == Implemented ]] && grep -c '"kind":"miss-fix"' $M/misses.jsonl | grep -q '^1$'; echo $?)"

# ---- 5b. the readable file ----------------------------------------------------------------------
MD="docs/FxApp-Misses.md"
check "misses file: $MD and its HTML exist" "$([[ -f "$MD" && -f "docs/FxApp-Misses.html" ]]; echo $?)"
nrec="$(grep -c '"kind":"miss"' $M/misses.jsonl)"; nrow="$(grep -c '^| MISS-FxApp-' "$MD")"
check "misses file: one row per miss record ($nrec records, $nrow rows)" "$([[ "$nrec" == "$nrow" && "$nrec" -gt 0 ]]; echo $?)"
check "misses file: the sentence, the row and whose gap are in the row" "$(grep -E '^\| MISS-FxApp-[0-9]+-[0-9]+ \(REQ-UI-002\) \| [0-9-]+ by owner \| said and ignored \| The entries list ignores the date filter \|' "$MD" >/dev/null; echo $?)"
check "misses file: the fixed miss sits under Fixed with its closing command" "$(python3 - <<'PY'
import sys
t = open("docs/FxApp-Misses.md", encoding="utf-8").read()
fixed = t.split("## Fixed", 1)[1] if "## Fixed" in t else ""
sys.exit(0 if "(REQ-UI-001)" in fixed and "by log-miss" in fixed and "header logo" in fixed else 1)
PY
echo $?)"
check "misses file: triage misses carry the default sorts (demote weak-check, new spec, code edit ignored)" "$(grep '"req_id":"REQ-UI-003"' $M/misses.jsonl | grep -q '"sort":"weak-check"' && grep '"req_id":"REQ-FN-010"' $M/misses.jsonl | grep -q '"sort":"spec"' && grep '"why_missed":"instruction-ignored"' $M/misses.jsonl | grep 'triage edited' | grep -q '"sort":"ignored"'; echo $?)"
mid="$(bash $U/tf-emit.sh --next-miss-id)"
printf '{"kind":"miss","miss_id":"%s","req_id":"REQ-NFR-007","req_class":"NFR","miss_class":"wrong-behaviour","artifact":"src","severity":"minor","origin_phase":"build-phase","origin_agent":"flow-master","found_by":"owner","found_phase":"log-miss","what":"An older record with no sort yet"}' "$mid" | bash $U/tf-emit.sh misses >/dev/null
check "misses file: a record without a sort shows 'not sorted'" "$(grep -E "^\| $mid \(REQ-NFR-007\) \| .* \| not sorted \| An older record with no sort yet \|" "$MD" >/dev/null; echo $?)"
out="$(bash $U/tf-emit.sh --amend "$mid" sort spec 2>&1)"
check "amend: sort completed on the old record ($out)" "$(has "$out" "amended $mid — sort = spec")"
check "misses file: follows the amend (the app's spec)" "$(grep -F "| $mid (REQ-NFR-007) | " "$MD" | grep -F "| the app's spec | An older record with no sort yet |" >/dev/null; echo $?)"
out="$(bash $U/tf-emit.sh --amend "$mid" sort ignored 2>&1)"
check "amend: a second sort is refused, never overwritten" "$(has "$out" "amend refused")"
out="$(bash $U/tf-emit.sh --amend "$mid" sort nonsense 2>&1)"
check "amend: a value outside the four is refused" "$(has "$out" "not in the closed vocabulary")"
rep="$(bash .tfcore/telemetry/tf-metrics.sh --report . 2>&1)"
check "report: whose-gap block with the four values counted" "$([[ "$(has "$rep" "whose gap")" == 0 && "$(has "$rep" "weak-check")" == 0 && "$(has "$rep" "said and ignored")" == 0 ]]; echo $?)"

# ---- 6. fix-close ------------------------------------------------------------------------------
S3="$(bash $U/tf-phase.sh start fix-issues FxApp 2>/dev/null)"
python3 - <<PY
import json, datetime
json.dump({"date": datetime.date.today().isoformat(), "app": "FxApp", "scope": "REQ-UI-003,REQ-FN-010", "booted": "static",
           "gates": ["build", "acceptance"], "evidence": "tests/.artifacts/verify", "run_id": "$S3",
           "rows": {"REQ-UI-003": "PASS", "REQ-FN-010": "FAIL", "REQ-UI-002": "RENDER-FAIL"}}, open("docs/.last-verify.json", "w"), indent=1)
PY
out="$(bash $U/tf-fix-close.sh FxApp --started "$S3" --reqs REQ-UI-003,REQ-FN-010,REQ-UI-002,REQ-UI-004 --subagents trblazeui --build pass 2>&1)"; rc=$?
check "fix-close runs (exit $rc): $out" "$rc"
check "fix-close: a ledger RENDER-FAIL becomes verdict_after Needs re-verify (REQ-UI-002)" "$(grep '"kind":"miss-fix"' $M/misses.jsonl | grep '"req_id":"REQ-UI-002"' | grep -q '"verdict_after":"Needs re-verify"'; echo $?)"
n1="$(grep -c '"cmd":"fix-issues"' $M/runs.jsonl)"
out2="$(bash $U/tf-fix-close.sh FxApp --started "$S3" --reqs REQ-UI-003 --build pass 2>&1)"
n2="$(grep -c '"cmd":"fix-issues"' $M/runs.jsonl)"
check "fix-close called twice writes one run record ($n1 → $n2)" "$([[ "$n1" == 1 && "$n2" == 1 ]] && [[ "$(has "$out2" "already exists")" == 0 ]]; echo $?)"
check "fix-close: run record first, cmd fix-issues mode fix with the sub-agent" "$(grep '"cmd":"fix-issues"' $M/runs.jsonl | grep -q '"mode":"fix"' && grep '"cmd":"fix-issues"' $M/runs.jsonl | grep -q '"subagents":\["trblazeui"\]'; echo $?)"
check "fix-close: miss-fix for REQ-UI-003 says Verified" "$(grep '"kind":"miss-fix"' $M/misses.jsonl | grep '"req_id":"REQ-UI-003"' | grep -q '"verdict_after":"Verified"'; echo $?)"
check "fix-close: miss-fix for REQ-FN-010 says FAIL" "$(grep '"kind":"miss-fix"' $M/misses.jsonl | grep '"req_id":"REQ-FN-010"' | grep -q '"verdict_after":"FAIL"'; echo $?)"
check "fix-close: a row with no open miss is named" "$(has "$out" "no open miss on REQ-UI-004")"
check "fix-close: the miss-fix carries the fix run" "$(grep '"kind":"miss-fix"' $M/misses.jsonl | grep '"req_id":"REQ-UI-003"' | grep -q "\"fix_run_id\":\"$S3\""; echo $?)"

# ---- 7. the emitter and log-miss report honestly (Session 6, 2026-09-07) ---------------------
# 7a. MISS-TechieFlow-20260907-09: a run record with no `ended` was accepted and could never be
#     costed. `ended` is when the record is written, so an absent one is filled in.
echo '{"kind":"run","app":"FxApp","cmd":"devguide","started":"2026-09-07T07:00:00Z"}' | bash $U/tf-emit.sh runs >/dev/null 2>&1
check "emit: a run record with no ended gets one, and a duration" \
  "$(python3 - "$M/runs.jsonl" <<'PY'
import json,sys
r=[json.loads(l) for l in open(sys.argv[1]) if l.strip() and '"devguide"' in l][-1]
raise SystemExit(0 if r.get("ended") and r.get("duration_s") is not None else 1)
PY
echo $?)"
# 7b. MISS-TechieFlow-20260907-06: a record the emitter refused was reported as "Miss logged",
#     with an id that existed nowhere. A refusal must say so and append nothing.
before="$(grep -c '"kind":"miss"' $M/misses.jsonl)"
out7="$(bash $U/tf-log-miss.sh FxApp --sort spec --what "a bad artifact value must be reported, not claimed as logged" --artifact framework --found-by owner 2>&1)"; rc7=$?
after="$(grep -c '"kind":"miss"' $M/misses.jsonl)"
check "log-miss: a refused record says NOT recorded, exits non-zero, appends nothing ($before → $after)" \
  "$([[ "$(has "$out7" "Miss NOT recorded")" == 0 ]] && [[ "$rc7" != 0 ]] && [[ "$before" == "$after" ]]; echo $?)"
check "log-miss: the refusal names the value the emitter rejected" "$(has "$out7" "not in the closed vocabulary")"

echo
echo "bugs self-test: $pass passed, $fail failed (fixture $APP)"
[[ $fail -eq 0 ]]

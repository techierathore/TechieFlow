#!/usr/bin/env bash
# tests/verify/run.sh — self-test for the verify scripts (Sitting 4c, 2026-09-06).
# Builds a throw-away project (tests/verify/make-fixtures.py) with a static four-screen "app":
# one good screen, one whose table has no rows, one whose buttons overlap, one whose stylesheet
# is missing; a checklist of nine rows; anchored mockups; a spec with one failing test; a perf
# measurement over its budget. Then runs the whole verify chain on it and checks:
#   1. tf-verify-list.sh   rows in scope, the N/A row skipped, a dialog row mapped to its page
#   2. tf-verify-env.sh    installs the browser tooling into the fixture and reports READY
#   3. tf-verify-boot.sh   serves the static app, reports BOOTED, stops it, the port is free
#   4. tf-verify-screens.sh  render EMPTY on the empty table, visual FAIL on the overlap and the
#                            unstyled page, OK on the good screen, a screenshot per screen and width
#   5. tf-verify-tests.sh  REQ-FN-005 FAIL, the four UI rows PASS, from the Playwright JSON
#   6. tf-assets.sh        the missing stylesheet fails the assets check
#   7. tf-mockup-parity.sh runs and writes its JSON
#   8. tf-perf-grade.sh    OK, MARGINAL, FAIL, load-shed FAIL, UNMEASURED on Debug, weak, auth wall
#   9. tf-verify-verdict.sh  one verdict per row in check order, the ledger with every row, the
#                            checklist cells rewritten, NOT-* rows untouched
#  10. tf-verify-emit.sh   gate records, one miss per failing row, no duplicate on a second run,
#                          one run record with cmd verify-phase and the yolo flag
#  11. guard-verify.sh     refuses a hand-written Verified the ledger does not list as PASS,
#                          allows one it does, refuses everything when no ledger exists
# Telemetry goes to the fixture's docs/metrics only (TF_METRICS_ROOT), never to this repository.
# Run: bash tests/verify/run.sh   (about two minutes the first time, for the browser install)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
export TF_FIXTURE_DIR="$ROOT/tests/.artifacts/verify-fixture"
APP="$(python3 "$HERE/make-fixtures.py")" || { echo "could not build the fixture"; exit 2; }
PORT=5117
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $*"; }
bad() { fail=$((fail+1)); echo "FAIL $*"; }
check() { if [[ "$2" == 0 ]]; then ok "$1"; else bad "$1"; fi; }
has() { grep -q -- "$2" <<<"$1"; echo $?; }

cd "$APP" || exit 2
export TF_METRICS_ROOT="$APP"; unset CLAUDE_PROJECT_DIR; export TF_PROJECT_DIR="$APP"
U=".tfcore/utils"
trap 'bash $U/tf-verify-boot.sh stop >/dev/null 2>&1' EXIT

# ---- 1. the list -------------------------------------------------------------------------
out="$(bash $U/tf-verify-list.sh FxApp all 2>&1)"; rc=$?
check "list runs (exit $rc)" "$rc"
check "list grades 8 rows and skips the N/A row" "$(has "$out" "Rows to grade: 8 (.*1 N/A skipped")"
check "list maps the Quick settings dialog row to Home" "$(has "$out" "REQ-FN-005 .* Home / — dialog Quick settings")"
check "list finds the perf budget on REQ-NFR-008" "$(has "$out" "REQ-NFR-008 .*perf-budget: p95 ttfb <= 500ms")"
check "list names four screens to drive" "$(has "$out" "Screens to drive (4 of 4")"
n="$(python3 -c "import json;print(len(json.load(open('tests/.artifacts/verify/list.json'))['rows']))")"
check "list.json carries the 8 rows" "$([[ "$n" == 8 ]]; echo $?)"
out="$(bash $U/tf-verify-list.sh FxApp ui 2>&1)"; check "scope ui keeps only the four UI rows" "$(has "$out" "Rows to grade: 4 ")"
out="$(bash $U/tf-verify-list.sh FxApp REQ-UI-001,REQ-FN-006 2>&1)"; check "scope by id list keeps two rows" "$(has "$out" "Rows to grade: 2 ")"
bash $U/tf-verify-list.sh FxApp all >/dev/null 2>&1

# ---- 2. the environment --------------------------------------------------------------------
out="$(bash $U/tf-verify-env.sh 2>&1)"; rc=$?
check "env reports READY (exit $rc)" "$rc"
check "env pinned playwright.config.ts under tests/.artifacts" "$(grep -q "tests/.artifacts/test-results" playwright.config.ts; echo $?)"
check "env added the .gitignore lines" "$(grep -q "tests/.artifacts/" .gitignore; echo $?)"
out="$(bash $U/tf-verify-env.sh --check 2>&1)"; check "env --check is READY on the second pass" "$(has "$out" "^READY")"

# ---- 3. boot ---------------------------------------------------------------------------
out="$(bash $U/tf-verify-boot.sh start --static site --port $PORT 2>&1)"; rc=$?
check "boot serves the static app (exit $rc): ${out%% log=*}" "$rc"
check "boot state says mode=base" "$(has "$(cat tests/.artifacts/verify/boot.json)" '"mode": "base"')"
BASE="http://localhost:$PORT"
out="$(bash $U/tf-verify-boot.sh start --static site --port $PORT 2>&1)"; rc=$?
check "boot refuses a port already in use (exit $rc)" "$([[ $rc -eq 2 ]]; echo $?)"
check "a refused second start leaves the first boot's state alone" "$(has "$(cat tests/.artifacts/verify/boot.json)" '"mode": "base"')"

# ---- 4. screens --------------------------------------------------------------------------
out="$(bash $U/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --base "$BASE" 2>&1)"; rc=$?
check "screens exits 5 with failures (exit $rc)" "$([[ $rc -eq 5 ]]; echo $?)"
check "Home renders and looks right" "$(has "$out" "^OK   Home (/) — render OK, visual OK, 5 anchors")"
check "Entries: header-only table is render EMPTY (zero-rows)" "$(has "$out" "^FAIL Entries .*render EMPTY.*has a header and no rows")"
check "Editor: overlapping buttons are visual FAIL" "$(has "$out" "^FAIL Editor .*visual FAIL.*save overlaps cancel")"
check "Settings: missing stylesheet is visual FAIL (unstyled)" "$(has "$out" "^FAIL Settings .*visual FAIL.*no stylesheet")"
shots="$(ls tests/.artifacts/verify/screens/*.png 2>/dev/null | wc -l)"
check "a screenshot per screen and width (8): $shots" "$([[ "$shots" == 8 ]]; echo $?)"
out2="$(bash $U/tf-verify-screens.sh --screen Home=/ --base "$BASE" --mockups docs/mockups --json-out tests/.artifacts/verify/smoke.json 2>&1)"; rc=$?
check "a smoke on one named screen passes (exit $rc)" "$rc"

# ---- 5. tests ----------------------------------------------------------------------------
out="$(bash $U/tf-verify-tests.sh --base "$BASE" --no-unit 2>&1)"; rc=$?
check "tests run the spec (exit $rc)" "$rc"
check "tests: 4 PASS, 1 FAIL" "$(has "$out" "rows with a test: 5 — 4 PASS, 1 FAIL")"
check "tests: REQ-FN-005 is the failure" "$(has "$out" "FAIL REQ-FN-005")"

# ---- 6. assets and 7. parity ----------------------------------------------------------------
bash $U/tf-assets.sh --base "$BASE" --paths "/,/entries.html,/broken.html,/unstyled.html" --json-out tests/.artifacts/verify/assets.json >/dev/null 2>&1; rc=$?
check "assets exits 5 on the missing stylesheet (exit $rc)" "$([[ $rc -eq 5 ]]; echo $?)"
bash $U/tf-mockup-parity.sh --base "$BASE" --screen Home=/ --screen Entries=/entries.html --screen Editor=/broken.html --screen Settings=/unstyled.html --json-out tests/.artifacts/verify/parity.json >/dev/null 2>&1; rc=$?
check "parity runs and writes its JSON (exit $rc)" "$([[ -s tests/.artifacts/verify/parity.json ]]; echo $?)"

# ---- 8. perf grading -------------------------------------------------------------------------
g() { bash $U/tf-perf-grade.sh --budget "p95 ttfb <= 500ms @ concurrency 50" --json "perf-cases/$1" 2>&1; }
check "perf OK" "$(has "$(g ok.json)" "^PERF-OK")"
check "perf MARGINAL within a quarter over" "$(has "$(g marginal.json)" "^PERF-MARGINAL")"
check "perf FAIL on load shed (timeout)" "$(has "$(g shed.json)" "^PERF-FAIL reason=.*failed at concurrency")"
check "perf UNMEASURED on a Debug build" "$(has "$(g debug.json)" "^PERF-UNMEASURED reason=build is Debug")"
check "perf UNMEASURED on a weak sample" "$(has "$(g weak.json)" "^PERF-UNMEASURED reason=weak sample")"
check "perf UNMEASURED on an auth wall" "$(has "$(g redirected.json)" "^PERF-UNMEASURED reason=auth wall")"
check "perf FAIL slow" "$(has "$(bash $U/tf-perf-grade.sh --budget "p95 ttfb <= 500ms" --json tests/.artifacts/verify/perf/REQ-NFR-008.json)" "^PERF-FAIL reason=p95 ttfb 900 ms vs budget 500 ms")"

# ---- 9. verdicts -----------------------------------------------------------------------------
STARTED="$(bash $U/tf-phase.sh start verify-phase FxApp 2>/dev/null)"
out="$(bash $U/tf-verify-verdict.sh FxApp --apply --started "$STARTED" 2>&1)"; rc=$?
check "verdict runs (exit $rc)" "$rc"
v() { python3 -c "import json;print(json.load(open('docs/.last-verify.json'))['rows'].get('$1'))"; }
check "REQ-UI-001 PASS"            "$([[ "$(v REQ-UI-001)" == PASS ]]; echo $?)"
check "REQ-UI-002 RENDER-FAIL"     "$([[ "$(v REQ-UI-002)" == RENDER-FAIL ]]; echo $?)"
check "REQ-UI-003 VISUAL-FAIL (prior Verified)" "$([[ "$(v REQ-UI-003)" == VISUAL-FAIL ]]; echo $?)"
check "REQ-UI-004 ASSET-FAIL before visual" "$([[ "$(v REQ-UI-004)" == ASSET-FAIL ]]; echo $?)"
check "REQ-FN-005 FAIL (acceptance)" "$([[ "$(v REQ-FN-005)" == FAIL ]]; echo $?)"
check "REQ-FN-006 NOT-TESTED, screen failed elsewhere so RENDER-FAIL" "$([[ "$(v REQ-FN-006)" == RENDER-FAIL ]]; echo $?)"
check "REQ-NFR-007 NOT-OBSERVABLE" "$([[ "$(v REQ-NFR-007)" == NOT-OBSERVABLE ]]; echo $?)"
check "REQ-NFR-008 PERF-FAIL"      "$([[ "$(v REQ-NFR-008)" == PERF-FAIL ]]; echo $?)"
check "ledger dated today with the checks that ran" "$(has "$(cat docs/.last-verify.json)" "\"date\": \"$(date +%F)\"")"
cell() { grep -E "^\| $1 \|" docs/FxApp-Checklist.md | cut -d'|' -f4 | tr -d ' '; }
check "checklist: REQ-UI-001 written Verified" "$([[ "$(cell REQ-UI-001)" == Verified ]]; echo $?)"
check "checklist: REQ-UI-003 demoted to Needs re-verify" "$([[ "$(cell REQ-UI-003)" == Needsre-verify ]]; echo $?)"
check "checklist: REQ-FN-005 written FAIL" "$([[ "$(cell REQ-FN-005)" == FAIL ]]; echo $?)"
check "checklist: REQ-NFR-007 untouched (Implemented)" "$([[ "$(cell REQ-NFR-007)" == Implemented ]]; echo $?)"
check "checklist: REQ-FN-009 N/A untouched" "$([[ "$(cell REQ-FN-009)" == N/A ]]; echo $?)"
check "checklist: remark names the evidence" "$(grep -E "^\| REQ-UI-002 \|" docs/FxApp-Checklist.md | grep -q "verify: ⚠ render — table entries-table has a header and no rows on Entries @1280 (tests/.artifacts/verify/screens/entries-1280.png)"; echo $?)"
check "REQ-NFR-007 remark says not observable" "$(grep -E "^\| REQ-NFR-007 \|" docs/FxApp-Checklist.md | grep -q "not observable"; echo $?)"

# ---- 10. telemetry ----------------------------------------------------------------------------
out="$(bash $U/tf-verify-emit.sh FxApp --started "$STARTED" 2>&1)"; rc=$?
check "emit runs (exit $rc): $out" "$rc"
gates="$(grep -c '"kind":"gate"' docs/metrics/gates.jsonl 2>/dev/null)"; misses="$(grep -c '"kind":"miss"' docs/metrics/misses.jsonl 2>/dev/null)"; runs="$(grep -c '"cmd":"verify-phase"' docs/metrics/runs.jsonl 2>/dev/null)"
check "7 gate records (every graded row; NOT-OBSERVABLE none): $gates" "$([[ "$gates" == 7 ]]; echo $?)"
check "6 misses (one per failing row): $misses" "$([[ "$misses" == 6 ]]; echo $?)"
check "one verify-phase run record with yolo false: $runs" "$([[ "$runs" == 1 ]] && grep -q '"yolo":false' docs/metrics/runs.jsonl; echo $?)"
check "the run record's started is the phase marker's" "$(grep -q "\"started\":\"$STARTED\"" docs/metrics/runs.jsonl; echo $?)"
check "REQ-UI-003 miss is a regression (prior Verified)" "$(grep '"req_id":"REQ-UI-003"' docs/metrics/misses.jsonl | grep -q '"miss_class":"regression"'; echo $?)"
check "REQ-UI-004 gate is assets with missing-asset" "$(grep '"req_id":"REQ-UI-004"' docs/metrics/gates.jsonl | grep -q '"gate":"assets".*"failure_class":"missing-asset"\|"failure_class":"missing-asset".*"gate":"assets"'; echo $?)"
bash $U/tf-verify-emit.sh FxApp --started "$STARTED" >/dev/null 2>&1
misses2="$(grep -c '"kind":"miss"' docs/metrics/misses.jsonl)"
check "a second emit adds no duplicate miss: $misses2" "$([[ "$misses2" == 6 ]]; echo $?)"

# ---- 11. the hook -------------------------------------------------------------------------------
HOOK=".tfcore/hooks/guard-verify.sh"; CL="$APP/docs/FxApp-Checklist.md"
hook() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"%s","new_string":"%s"}}' "$CL" "$1" "$2" | bash "$HOOK" 2>&1; echo "rc=$?"; }
r="$(hook '| REQ-FN-005 | Save a quick setting | FAIL |' '| REQ-FN-005 | Save a quick setting | Verified |')"
check "hook refuses Verified on a row the ledger lists as FAIL" "$(has "$r" "rc=2")"
check "hook names the row and its ledger verdict" "$(has "$r" "REQ-FN-005: FAIL, not PASS")"
r="$(hook '| REQ-UI-001 | Home lists today'"'"'s entries | Implemented |' '| REQ-UI-001 | Home lists today'"'"'s entries | Verified |')"
check "hook allows Verified on a row the ledger lists as PASS" "$(has "$r" "rc=0")"
r="$(hook '| REQ-UI-002 | Entries table | Verified |' '| REQ-UI-002 | Entries table | Needs re-verify |')"
check "hook allows a demotion" "$(has "$r" "rc=0")"
mv docs/.last-verify.json docs/.last-verify.json.off
r="$(hook '| REQ-UI-001 | x | Implemented |' '| REQ-UI-001 | x | Verified |')"
check "hook refuses when no ledger exists" "$(has "$r" "rc=2")"
mv docs/.last-verify.json.off docs/.last-verify.json
r="$(printf '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' | bash "$HOOK" 2>&1; echo "rc=$?")"
check "hook ignores other tools" "$(has "$r" "rc=0")"

# ---- 3b. stop -------------------------------------------------------------------------------------
out="$(bash $U/tf-verify-boot.sh stop 2>&1)"; rc=$?
sleep 1
check "boot stop frees the port (exit $rc)" "$(curl -s -o /dev/null -m 2 "$BASE/" && echo 1 || echo 0)"

echo
echo "verify self-test: $pass passed, $fail failed (fixture $APP)"
[[ $fail -eq 0 ]]

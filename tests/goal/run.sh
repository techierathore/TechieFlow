#!/usr/bin/env bash
# tests/goal/run.sh — self-test for the goal supervisor (.tfcore/utils/tf-goal.sh).
# Builds a throw-away app folder, replaces the harness with TF_GOAL_FAKE_CMD, and proves:
#   1. classification: a clean Claude stop is IDLE (not a crash), a rejected rate limit is
#      LIMIT at the event's reset epoch plus the buffer, a non-zero exit is CRASH, plain
#      OpenCode text is IDLE
#   2. a cycle whose output stops growing is killed after the stall clock and re-prompted
#   3. TERM to the supervisor stops its harness child and exits 130 within seconds
#   4. a clean early stop is re-prompted after --idle-retry-sec, never backed off
#   5. two stalled resumes start a fresh session; --resume --fresh does the same by hand
#   6. a silent OpenCode cycle whose log says the provider refused the model exits 5
#   7. tf-yolo.sh done refuses the sentinel until the status file and a run record are newer
#      than the goal start
# Run: bash tests/goal/run.sh   (about 60 seconds; exit 0 = every check passed)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
GOAL_SH="$ROOT/.tfcore/utils/tf-goal.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tf-goal-test.XXXXXX")"
APP="$WORK/fakeapp"; mkdir -p "$APP/.tfcore/utils" "$APP/docs"
cp "$ROOT/.tfcore/utils/tf-yolo.sh" "$APP/.tfcore/utils/"
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   $*"; }
bad()  { fail=$((fail+1)); echo "FAIL $*"; }
check() { # description, condition-result
  if [[ "$2" == 0 ]]; then ok "$1"; else bad "$1"; fi
}
classify() { TF_GOAL_CLASSIFY="$1" TF_GOAL_CLASSIFY_RC="${2:-0}" bash "$GOAL_SH" "$APP" x | tr '\t' ' '; }

# ---- 1. classification -------------------------------------------------------------
cat > "$WORK/clean.out" <<'EOF'
{"type":"system","subtype":"init","session_id":"abc12345-0000-0000-0000-000000000000","model":"claude-sonnet-5"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Waiting for the build to complete."}]},"session_id":"abc12345-0000-0000-0000-000000000000"}
{"type":"result","subtype":"success","is_error":false,"num_turns":9,"api_error_status":null,"result":"Waiting for the build to complete.","session_id":"abc12345-0000-0000-0000-000000000000"}
EOF
r="$(classify "$WORK/clean.out" 0)"; check "clean Claude stop is IDLE ($r)" "$([[ "$r" == IDLE* ]]; echo $?)"

reset=$(( $(date +%s) + 3600 ))
cat > "$WORK/limit.out" <<EOF
{"type":"system","subtype":"init","session_id":"abc12345-0000-0000-0000-000000000000"}
{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":$reset,"rateLimitType":"five_hour"},"session_id":"abc12345-0000-0000-0000-000000000000"}
{"type":"assistant","message":{"content":[{"type":"text","text":"You've hit your session limit · resets 9am (UTC)"}]},"error":"rate_limit","is_api_error_message":true}
{"type":"result","subtype":"success","is_error":true,"api_error_status":429,"result":"You've hit your session limit · resets 9am (UTC)","terminal_reason":"api_error"}
EOF
r="$(classify "$WORK/limit.out" 0)"; want=$(( reset + 15*60 ))
check "rejected rate limit is LIMIT at resetsAt+15m ($r, want $want)" "$([[ "$r" == "LIMIT $want parsed" ]]; echo $?)"

r="$(classify "$WORK/clean.out" 143)"; check "exit 143 is CRASH ($r)" "$([[ "$r" == CRASH* ]]; echo $?)"

printf 'Reading .tfcore/tasks/deploy-checklist.md\nWrote docs/X-Deployment-Checklist.md\n' > "$WORK/oc.out"
r="$(classify "$WORK/oc.out" 0)"; check "plain OpenCode text is IDLE ($r)" "$([[ "$r" == IDLE* ]]; echo $?)"

# ---- 2. stall → kill → re-prompt → sentinel on the next cycle ----------------------------
rm -f "$APP/.tfcore/.session/"* 2>/dev/null
FAKE='cd "$PWD"; if [[ -f cycle1.done ]]; then bash .tfcore/utils/tf-yolo.sh done complete "second cycle"; else touch cycle1.done; echo started; sleep 120; fi'
t0=$(date +%s)
TF_GOAL_FAKE_CMD="$FAKE" TF_GOAL_STALL_SEC=4 TF_GOAL_STALL_TICK=1 \
  bash "$GOAL_SH" --idle-retry-sec 1 --max-cycles 3 "$APP" "stall test" >"$WORK/stall.log" 2>&1; rc=$?
took=$(( $(date +%s) - t0 ))
check "stalled cycle is killed and the run completes on cycle 2 (exit $rc, ${took}s)" "$([[ $rc -eq 0 && $took -lt 40 ]]; echo $?)"
check "log names the stall" "$(grep -q 'STALL: no output for' "$WORK/stall.log"; echo $?)"
check "stall is re-prompted, not backed off" "$(grep -q 'stalled 15m) — re-prompting in 1s' "$WORK/stall.log"; echo $?)"
check "no fake harness left running" "$(pgrep -x sleep -a | grep -q ' 120$'; [[ $? -ne 0 ]]; echo $?)"

# ---- 3. TERM stops the supervisor AND its child ---------------------------------------
rm -f "$APP/.tfcore/.session/"* "$APP/cycle1.done" 2>/dev/null
TF_GOAL_FAKE_CMD='echo up; sleep 300' TF_GOAL_STALL_TICK=1 \
  bash "$GOAL_SH" --idle-retry-sec 1 "$APP" "kill test" >"$WORK/kill.log" 2>&1 &
sup=$!
sleep 3
kill -TERM "$sup"
t0=$(date +%s); wait "$sup"; rc=$?; took=$(( $(date +%s) - t0 ))
check "TERM exits 130 within seconds (exit $rc, ${took}s)" "$([[ $rc -eq 130 && $took -lt 15 ]]; echo $?)"
sleep 1
check "the harness child is gone" "$(pgrep -x sleep -a | grep -q ' 300$'; [[ $? -ne 0 ]]; echo $?)"
check "goal.json says stopped" "$(grep -q '"last_reason": "stopped"' "$APP/.tfcore/.session/goal.json"; echo $?)"
check "YOLO flag cleared" "$([[ ! -f "$APP/.tfcore/.session/yolo.json" ]]; echo $?)"

# ---- 4. clean early stop → re-prompt after idle-retry, never a backoff --------------------
rm -f "$APP/.tfcore/.session/"* "$APP/cycle1.done" 2>/dev/null
FAKE='if [[ -f cycle1.done ]]; then bash .tfcore/utils/tf-yolo.sh done complete "done"; else touch cycle1.done; cat '"$WORK/clean.out"'; fi'
t0=$(date +%s)
TF_GOAL_FAKE_CMD="$FAKE" TF_GOAL_STALL_TICK=1 bash "$GOAL_SH" --idle-retry-sec 1 --max-cycles 3 "$APP" "idle test" >"$WORK/idle.log" 2>&1; rc=$?
took=$(( $(date +%s) - t0 ))
check "clean stop completes on cycle 2 (exit $rc, ${took}s)" "$([[ $rc -eq 0 && $took -lt 20 ]]; echo $?)"
check "log says clean stop, re-prompting in 1s" "$(grep -q 'clean stop: result is_error=false, 9 turn(s)) — re-prompting in 1s' "$WORK/idle.log"; echo $?)"
check "no harness/API error line" "$(grep -q 'harness/API error' "$WORK/idle.log"; [[ $? -ne 0 ]]; echo $?)"

# ---- 5. two stalled resumes → a fresh session; and --resume --fresh ----------------------
rm -f "$APP/.tfcore/.session/"* "$APP/cycle1.done" "$APP/n" 2>/dev/null
# cycle 1: clean stop (so cycle 2+ are resumes); cycles 2,3: hang; cycle 4: sentinel
FAKE='n=$(( $(cat n 2>/dev/null || echo 0) + 1 )); echo $n > n; case $n in 1) cat '"$WORK/clean.out"';; 2|3) echo hang; sleep 120;; *) bash .tfcore/utils/tf-yolo.sh done complete "fresh worked";; esac'
t0=$(date +%s)
TF_GOAL_FAKE_CMD="$FAKE" TF_GOAL_STALL_SEC=3 TF_GOAL_STALL_TICK=1 bash "$GOAL_SH" --idle-retry-sec 1 --max-cycles 6 "$APP" "fresh test" >"$WORK/fresh.log" 2>&1; rc=$?
took=$(( $(date +%s) - t0 ))
check "run completes on cycle 4 after two stalled resumes (exit $rc, ${took}s)" "$([[ $rc -eq 0 && $took -lt 40 ]]; echo $?)"
check "log announces the fresh session" "$(grep -q 'two stalled resumes in a row' "$WORK/fresh.log"; echo $?)"
check "cycle 4 was launched as a first (fresh) cycle" "$(grep -q 'cycle 4 (first)' "$WORK/fresh.log"; echo $?)"
check "cycle 3 was still a resume" "$(grep -q 'cycle 3 (resume)' "$WORK/fresh.log"; echo $?)"
check "no stray fake harness" "$(pgrep -x sleep -a | grep -q ' 120$'; [[ $? -ne 0 ]]; echo $?)"
# --resume --fresh on a stopped run: the state says cycle 4 and done; make it look stopped
python3 - "$APP/.tfcore/.session/goal.json" <<'PY2'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["last_reason"]="stopped"; d["session_id"]="oldsession"; json.dump(d,open(p,"w"))
PY2
rm -f "$APP/.tfcore/.session/goal-done.json" "$APP/n"; echo 3 > "$APP/n"   # next fake call is n=4 → sentinel
TF_GOAL_FAKE_CMD="$FAKE" TF_GOAL_STALL_TICK=1 bash "$GOAL_SH" --resume --fresh "$APP" >"$WORK/fresh2.log" 2>&1; rc=$?
check "--resume --fresh completes (exit $rc)" "$([[ $rc -eq 0 ]]; echo $?)"
check "--resume --fresh logs the fresh session and launches (first)" "$(grep -q 'in a FRESH session' "$WORK/fresh2.log" && grep -q 'cycle 5 (first)' "$WORK/fresh2.log"; echo $?)"

# ---- 6. OpenCode says nothing, its log says "monthly usage limit" → exit 5 ---------------
rm -f "$APP/.tfcore/.session/"* "$APP/n" 2>/dev/null
FAKELOG="$WORK/opencode.log"; : > "$FAKELOG"
FAKE='echo "> build · glm-5.2"; sleep 2; printf "timestamp=%s level=ERROR run=x message=\"stream error\" providerID=opencode-go modelID=glm-5.2 error.error=\"AI_APICallError: Monthly usage limit reached. Resets in 6 days.\"\n" "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" >> '"$FAKELOG"'; sleep 120'
t0=$(date +%s)
TF_GOAL_FAKE_CMD="$FAKE" TF_GOAL_OPENCODE_LOG="$FAKELOG" TF_GOAL_STALL_SEC=4 TF_GOAL_STALL_TICK=1 \
  bash "$GOAL_SH" --harness opencode --idle-retry-sec 1 --max-cycles 3 "$APP" "limit test" >"$WORK/plimit.log" 2>&1; rc=$?
took=$(( $(date +%s) - t0 ))
check "silent provider limit stops the supervisor with exit 5 (exit $rc, ${took}s)" "$([[ $rc -eq 5 && $took -lt 30 ]]; echo $?)"
check "log carries the provider's own words" "$(grep -q 'Monthly usage limit reached' "$WORK/plimit.log"; echo $?)"
check "goal.json says provider-limit" "$(grep -q '"last_reason": "provider-limit"' "$APP/.tfcore/.session/goal.json"; echo $?)"
check "no stray fake harness" "$(pgrep -x sleep -a | grep -q ' 120$'; [[ $? -ne 0 ]]; echo $?)"

# ---- 7. `done` is refused while the status gate has not run --------------------------------
rm -f "$APP/.tfcore/.session/"* "$APP/n" 2>/dev/null; mkdir -p "$APP/docs/metrics"
PS="$APP/PROJECT-STATUS.md"; printf '# status\n' > "$PS"; touch -d '2026-01-01' "$PS"; : > "$APP/docs/metrics/runs.jsonl"
FAKE='bash .tfcore/utils/tf-yolo.sh done blocked "too early"; if [[ ! -f .tfcore/.session/goal-done.json ]]; then echo refused-as-expected; touch PROJECT-STATUS.md; printf "{\"cmd\":\"build-phase\",\"claimed\":true}" > .tfcore/.session/phase.json; printf "{\"kind\":\"run\",\"cmd\":\"verify-phase\",\"ts\":\"%s\"}\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> docs/metrics/runs.jsonl; bash .tfcore/utils/tf-yolo.sh done blocked "only a verify record"; [[ -f .tfcore/.session/goal-done.json ]] || echo refused-again-as-expected; printf "{\"kind\":\"run\",\"cmd\":\"build-phase\",\"ts\":\"%s\"}\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> docs/metrics/runs.jsonl; bash .tfcore/utils/tf-yolo.sh done complete "after the gate"; fi'
TF_GOAL_FAKE_CMD="$FAKE" TF_GOAL_STALL_TICK=1 bash "$GOAL_SH" --idle-retry-sec 1 --max-cycles 2 "$APP" "done test" >"$WORK/done.log" 2>&1; rc=$?
check "done is refused before the gate and accepted after it (exit $rc)" "$([[ $rc -eq 0 ]] && grep -q 'refused-as-expected' "$APP/.tfcore/.session/goal.log" && grep -q 'GOAL-DONE refused' "$APP/.tfcore/.session/goal.log"; echo $?)"
check "done is refused again when only another command's run record exists" "$(grep -q 'refused-again-as-expected' "$APP/.tfcore/.session/goal.log" && grep -q 'no run record for build-phase' "$APP/.tfcore/.session/goal.log"; echo $?)"
check "the accepted sentinel is the complete one" "$(grep -q '"outcome":"complete"' "$APP/.tfcore/.session/goal-done.json"; echo $?)"

echo "tests/goal: $pass passed, $fail failed"
[[ $fail -eq 0 ]]

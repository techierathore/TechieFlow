#!/usr/bin/env bash
# tests/develop/run.sh — *develop-end-to-end on an app that already exists (owner's option A, 2026-11-19).
#
#   bash tests/develop/run.sh            # all
#   bash tests/develop/run.sh dev_nogit  # one
#
# A stand-in goal runner plays the agent (as dev_001 in tests/regression does): it writes a run record
# per step and logs which goal it was given, so a case sees which steps ran, in which order, with which
# appPhase. Each case fails on the tf-develop.sh of 4659972 and passes now. prove.sh in this folder is
# the long, paid run on a real harness; this file is the cheap check. Exit 0 all held, 1 a case failed.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.tfcore/utils/tf-portable.sh"   # tf_timeout
unset CLAUDE_PROJECT_DIR TF_METRICS_ROOT TF_PROJECT_DIR TF_YOLO CLAUDE_CODE_SESSION_ID OPENCODE_SESSION_ID TF_DEVELOP_RUN
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UTILS="${TF_REGRESSION_UTILS:-$ROOT/.tfcore/utils}"
SCRATCH="$ROOT/tests/.artifacts/develop.$$"
mkdir -p "$SCRATCH"
trap '[[ -n "${TF_KEEP:-}" ]] || rm -rf "$SCRATCH"' EXIT
fail=0; only="${1:-}"
ok()   { printf 'ok   %s — %s\n' "$1" "$2"; }
bad()  { printf 'FAIL %s — %s\n' "$1" "$2"; fail=1; }
_g() { GIT_CEILING_DIRECTORIES="$SCRATCH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
       GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com "$@"; }

FAKE="$SCRATCH/fake-goal.sh"
cat > "$FAKE" <<'SH'
#!/usr/bin/env bash
# stand-in for tf-goal.sh: the last argument is the goal, the one before it the app dir
dir="${@: -2:1}"; goal="${@: -1}"
case "$goal" in *--stage2*) p=day1-2 ;; *day1-greenfield*) p=day1 ;; *build-phase*) p=build ;; *handoff-phase*) p=handoff ;; *) p=other ;; esac
grep -q "develop mode" <<<"$goal" || exit 9
n="$(sed -n 's/.*for phase \([0-9]*\) of .*/\1/p' <<<"$goal")"; [[ -n "$n" ]] && p="$p-p$n"
ap="$(sed -n 's/^appPhase: *//p' "$dir/.tfcore/core-config.yaml" 2>/dev/null)"
only="$(sed -n 's/.*write only these, \([^,]*\), and keep.*/\1/p' <<<"$goal")"
echo "$p appPhase=${ap:-none}${only:+ only=$only}" >> "$dir/goals.log"
[[ -n "${TF_FAKE_BLOCK:-}" && "$p" == "$TF_FAKE_BLOCK" ]] && exit 3
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"kind":"run","app":"Fx","cmd":"%s","started":"%s","ended":"%s","duration_s":60,"tokens_in":10,"tokens_out":1000,"model":"m1"}\n' "$p" "$now" "$now" >> "$dir/docs/metrics/runs.jsonl"
sleep 1
SH
chmod +x "$FAKE"

# an app folder: the framework's scripts, the config, and the documents named (each file a stub)
app() {   # <dir> <doc>...
  local d="$1"; shift
  mkdir -p "$d/.tfcore/utils" "$d/docs/metrics" "$d/docs/mockups"
  cp "$UTILS/tf-develop.sh" "$UTILS/tf-day1-files.sh" "$UTILS/tf-day1-files.py" "$d/.tfcore/utils/"
  cp "$UTILS/tf-develop-plan.py" "$d/.tfcore/utils/" 2>/dev/null
  cp "$UTILS/tf-develop-watch.py" "$UTILS/tf-portable.sh" "$d/.tfcore/utils/" 2>/dev/null
  printf 'appSize: S\nappKind: app\n' > "$d/.tfcore/core-config.yaml"
  printf '.tfcore/.session/\ngoals.log\n' > "$d/.gitignore"
  local f; for f in "$@"; do printf '# %s\n' "$f" > "$d/$f"; done
}
STAGE1="docs/Fx-BRD.md docs/Fx-Architecture.md docs/Fx-UIDesign.md docs/mockups/home.html"
STAGE2="docs/Fx-Checklist.md docs/Fx-Coding-Standards.md docs/Fx-UsageGuide.md"
phases() {   # <dir> <status of phase 1> <status of phase 2>
  printf '# Fx — Phases\n\n## Phases\n\n| Phase | Name | Screens | BRD range | Status |\n|---|---|---|---|---|\n| 1 | Core | Home | BRD-1 to BRD-9 | %s |\n| 2 | More | Reports | BRD-10 to BRD-19 | %s |\n' "$2" "$3" > "$1/docs/Fx-Phases.md"
  printf '# x\n' > "$1/docs/Fx-P2-BRD.md"; printf '# x\n' > "$1/docs/Fx-P2-UIDesign.md"; printf '# x\n' > "$1/docs/Fx-P2-Checklist.md"
  printf 'appSize: L\nappKind: app\n' > "$1/.tfcore/core-config.yaml"
}
dev() { (cd "$1" && shift && _g env TF_DEVELOP_GOAL_SH="$FAKE" bash .tfcore/utils/tf-develop.sh . "$@" 2>&1); }
repo() { _g git -C "$1" init -q -b main && _g git -C "$1" add -A && _g git -C "$1" commit -q -m seed; }   # a repository of its own, no remote
printf 'A to-do app.\n' > "$SCRATCH/brief.md"
rep() { python3 -c "
import json, sys; r = json.load(open(sys.argv[1]))
print(r['status'], ','.join(p['phase'] + ':' + p['status'] for p in r['phases']))" "$1/docs/metrics/develop-report.json" 2>&1; }

# --- (1) an app whose documents are all written: Day 1 is skipped, no brief needed ----------------
dev_existing() {
  local d="$SCRATCH/existing" out rc
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2; repo "$d"
  out="$(dev "$d" --app Fx --model m1 --no-push)"; rc=$?
  [[ $rc -eq 0 && "$(tr '\n' ' ' < "$d/goals.log" 2>/dev/null)" == "build appPhase=none handoff appPhase=none " ]] \
    && [[ "$(rep "$d")" == "uat-ready day1:skipped,day1-2:skipped,build:done,handoff:done" ]] && grep -q 'Ready for UAT' "$d/docs/Fx-Build-Report.md" \
    && ok dev_existing "an app whose documents are written runs with no brief: both Day-1 stages are skipped and shown so, the build and the handoff run, UAT-ready" \
    || bad dev_existing "rc=$rc; goals run: $(tr '\n' ';' < "$d/goals.log" 2>/dev/null); report: $(rep "$d"); $(tail -1 <<<"$out")"
  # only part of stage 1 written: day 1 runs for the missing document alone, and stage 2 runs whole
  d="$SCRATCH/partial"
  # shellcheck disable=SC2086
  app "$d" docs/Fx-BRD.md docs/Fx-UIDesign.md docs/mockups/home.html; repo "$d"
  out="$(dev "$d" --app Fx --model m1 --brief "$SCRATCH/brief.md" --no-push)"; rc=$?
  [[ $rc -eq 0 && "$(head -2 "$d/goals.log" 2>/dev/null | tr '\n' ' ')" == "day1 appPhase=none only=docs/Fx-Architecture.md day1-2 appPhase=none " ]] \
    && ok dev_partial "with the Architecture alone missing, Day 1 runs for that document only and keeps the others; stage 2 runs whole" \
    || bad dev_partial "rc=$rc; goals run: $(tr '\n' ';' < "$d/goals.log" 2>/dev/null); $(tail -1 <<<"$out")"
  # no documents and no brief: refused, naming what is missing
  d="$SCRATCH/nothing"; app "$d"
  out="$(dev "$d" --app Fx --model m1)"; rc=$?
  [[ $rc -eq 2 ]] && grep -q 'brief' <<<"$out" && [[ ! -e "$d/goals.log" ]] \
    && ok dev_nobrief "a folder with no BRD and no brief is refused before anything runs" \
    || bad dev_nobrief "rc=$rc: $out"
}

# --- (2) a Large app: every phase of the Phases table, in order, each with its appPhase ---------
dev_phases() {
  local d="$SCRATCH/large" out rc want
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2; phases "$d" planned planned; repo "$d"
  out="$(dev "$d" --app Fx --model m1 --brief "$SCRATCH/brief.md" --no-push)"; rc=$?
  want="build-p1 appPhase=1 handoff-p1 appPhase=1 build-p2 appPhase=2 handoff-p2 appPhase=2 "
  [[ $rc -eq 0 && "$(tr '\n' ' ' < "$d/goals.log" 2>/dev/null)" == "$want" ]] \
    && [[ "$(rep "$d")" == "uat-ready day1:skipped,day1-2:skipped,build-p1:done,handoff-p1:done,build-p2:done,handoff-p2:done" ]] \
    && grep -q 'Phase 2: handoff' "$d/docs/Fx-Build-Report.md" \
    && ok dev_phases "a two-phase Large app builds, verifies and hands off phase 1, then phase 2, appPhase set before each build; one report row per step" \
    || bad dev_phases "rc=$rc; goals run: $(tr '\n' ';' < "$d/goals.log" 2>/dev/null); report: $(rep "$d"); $(tail -1 <<<"$out")"
  # phase 1 done in the table: only phase 2 runs; a block in phase 2 stops the run, --resume finishes it
  d="$SCRATCH/large2"
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2; phases "$d" done planned; repo "$d"
  out="$(TF_FAKE_BLOCK=build-p2 dev "$d" --app Fx --model m1 --brief "$SCRATCH/brief.md" --no-push)"; rc=$?
  local r1; r1="$(rep "$d")"
  out="$(dev "$d" --resume)"
  [[ $rc -eq 3 && "$r1" == "blocked day1:skipped,day1-2:skipped,build-p1:skipped,handoff-p1:skipped,build-p2:blocked" ]] \
    && [[ "$(tr '\n' ' ' < "$d/goals.log")" == "build-p2 appPhase=2 build-p2 appPhase=2 handoff-p2 appPhase=2 " && "$(rep "$d")" == uat-ready* ]] \
    && ok dev_phases_done "a phase the table marks done is skipped; a block in phase 2 stops the run and --resume finishes phase 2 alone" \
    || bad dev_phases_done "rc=$rc; first report: $r1; goals: $(tr '\n' ';' < "$d/goals.log" 2>/dev/null); last: $(rep "$d")"
}

# --- (3) --no-git: no commit, no push, no repository needed; every step still recorded ----------
dev_nogit() {
  local d="$SCRATCH/gitapp" remote="$SCRATCH/remote.git" out rc h0 h1 r0 r1
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2
  _g git init -q --bare "$remote"; _g git -C "$d" init -q -b main; _g git -C "$d" remote add origin "$remote"
  _g git -C "$d" add -A && _g git -C "$d" commit -q -m seed && _g git -C "$d" push -q -u origin main
  h0="$(_g git -C "$d" rev-parse HEAD)"; r0="$(_g git -C "$remote" rev-parse HEAD)"
  out="$(dev "$d" --app Fx --model m1 --no-git)"; rc=$?
  h1="$(_g git -C "$d" rev-parse HEAD)"; r1="$(_g git -C "$remote" rev-parse HEAD)"
  [[ $rc -eq 0 && "$h0" == "$h1" && "$r0" == "$r1" && -n "$(_g git -C "$d" status --porcelain)" ]] \
    && grep -q 'left to the owner' "$d/docs/Fx-Build-Report.md" && [[ "$(rep "$d")" == uat-ready* ]] \
    && ok dev_nogit "--no-git in a repository with a remote: the run completes, no commit is made and nothing is pushed, the work is left uncommitted for the owner" \
    || bad dev_nogit "rc=$rc; HEAD $h0 → $h1; remote $r0 → $r1; $(tail -1 <<<"$out")"
  # a folder that is no repository at all: runs, and creates none
  d="$SCRATCH/norepo"
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2
  out="$(dev "$d" --app Fx --model m1 --no-git)"; rc=$?
  [[ $rc -eq 0 && ! -e "$d/.git" && -f "$d/.tfcore/.session/develop-done.json" ]] && grep -q '"git": false' "$d/.tfcore/.session/develop-done.json" \
    && ok dev_nogit_b "--no-git in a folder that is no repository: it runs, records each step, and makes no repository" \
    || bad dev_nogit_b "rc=$rc; $(tail -1 <<<"$out")"
}

# --- (4) the dry run prints the plan and writes nothing ------------------------------------------
dev_dry() {
  local d="$SCRATCH/dry" out rc
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2; phases "$d" planned planned; repo "$d"
  out="$(dev "$d" --app Fx --model m1 --brief "$SCRATCH/brief.md" --no-push --dry-run)"; rc=$?
  local order; order="$(grep -oE '^(day1|day1-2|build-p[0-9]|handoff-p[0-9]): (skip|run)' <<<"$out" | tr '\n' ' ')"
  [[ $rc -eq 0 && "$order" == "day1: skip day1-2: skip build-p1: run handoff-p1: run build-p2: run handoff-p2: run " ]] \
    && grep -q 'build-p2: set appPhase 2' <<<"$out" && grep -q 'then commit, no push' <<<"$out" \
    && dev "$d" --app Fx --model m1 --no-git --dry-run | grep -q 'handoff-p2: then no commit and no push' \
    && [[ ! -e "$d/.tfcore/.session/develop.json" && ! -e "$d/goals.log" && "$(sed -n 's/^appSize: //p' "$d/.tfcore/core-config.yaml")" == L ]] \
    && ! grep -q appPhase "$d/.tfcore/core-config.yaml" \
    && ok dev_dry "the dry run prints the skipped Day-1 stages, then each phase's build and handoff in order with its appPhase and the git line, and writes nothing" \
    || bad dev_dry "rc=$rc; order: $order; $(head -3 <<<"$out" | tr '\n' ' ')"
}

# AppManager's shape (its own documents, read in a scratch copy on 19 Nov): the guide is docs/AppManager-Usage-Guide.md,
# and phase 1 is done with no UIDesign of its own. Neither is "missing": the plan wrote both until then.
dev_names() {
  local d="$SCRATCH/names" out
  app "$d" docs/Fx-BRD.md docs/Fx-Architecture.md docs/mockups/home.html docs/Fx-Checklist.md docs/Fx-Coding-Standards.md docs/Fx-Usage-Guide.md
  phases "$d" done planned
  out="$(dev "$d" --app Fx --model m1 --no-git --dry-run)"
  grep -q '^day1: skip' <<<"$out" && grep -q '^day1-2: skip' <<<"$out" && grep -q '^build-p1: skip' <<<"$out" && grep -q '^build-p2: run' <<<"$out" \
    && ok dev_names "a guide named Usage-Guide and a done phase with no UIDesign are not written again; the open phase still runs" \
    || bad dev_names "$(grep -E '^(day1|day1-2|build-p[12]):' <<<"$out" | tr '\n' ' ' | cut -c1-300)"
}

# --- TF-062 (AstroLyfe, 19 Nov): the launching window lost the run -----------------------------------
# A slower stand-in that behaves like tf-goal.sh from outside: its cycle lines on stderr, a Claude stream
# with token usage, the checklist rows moving, verify records, and (TF_FAKE_SPAWN) a process started in
# a session of its own, as the agent's web server was. TF_FAKE_SLEEP holds the build step open.
FAKE2="$SCRATCH/fake-goal2.sh"
cat > "$FAKE2" <<'SH'
#!/usr/bin/env bash
dir="${@: -2:1}"; goal="${@: -1}"; t() { date -u +%Y-%m-%dT%H:%M:%SZ; }
case "$goal" in *build-phase*) p=build ;; *handoff-phase*) p=handoff ;; *) p=other ;; esac
echo "$p ${*:1:$#-2}" >> "$dir/goal-args.log"
echo "[$(t)] tf-goal: cycle 1 (first) → claude -p --permission-mode bypassPermissions … (prompt 900 chars)" >&2
printf '{"type":"result","usage":{"input_tokens":10,"output_tokens":500,"cache_read_input_tokens":1000}}\n' > "$dir/.tfcore/.session/goal-cycle-1.out"
if [[ "$p" == build ]]; then
  if [[ -n "${TF_FAKE_SPAWN:-}" ]]; then
    python3 -c 'import os, sys, time
if os.fork(): sys.exit(0)
os.setsid(); open(sys.argv[1], "w").write(str(os.getpid())); time.sleep(300)' "$dir/spawned.pid" </dev/null >/dev/null 2>&1
  fi
  sed 's/| Not Started |/| Implemented |/' "$dir/docs/Fx-Checklist.md" > "$dir/c.tmp" && mv "$dir/c.tmp" "$dir/docs/Fx-Checklist.md"
  sleep "${TF_FAKE_SLEEP:-3}"
  echo "[$(t)] tf-goal: agent stopped without the goal-done sentinel (cycle 1, clean stop: result is_error=false, 1 turn(s)) — re-prompting in 30s" >&2
  echo "[$(t)] tf-goal: cycle 2 (resume) → claude -p … (prompt 400 chars)" >&2
  r="$(t)"
  for q in REQ-FN-001:Verified REQ-FN-002:Verified REQ-FN-003:FAIL; do
    printf '{"kind":"gate","app":"Fx","run_id":"%s","req_id":"%s","verdict":"%s","ts":"%s"}\n' "$r" "${q%%:*}" "${q#*:}" "$r" >> "$dir/docs/metrics/gates.jsonl"
  done
  sed 's/^| REQ-FN-00\([12]\) | \([^|]*\)| Implemented |/| REQ-FN-00\1 | \2| Verified |/;s/^| REQ-FN-003 | \([^|]*\)| Implemented |/| REQ-FN-003 | \1| FAIL |/' "$dir/docs/Fx-Checklist.md" > "$dir/c.tmp" && mv "$dir/c.tmp" "$dir/docs/Fx-Checklist.md"
  sleep 3
fi
echo "[$(t)] tf-goal: goal-done sentinel present (outcome=complete): {\"outcome\":\"complete\",\"summary\":\"$p finished\",\"ts\":\"$(t)\"}" >&2
now="$(t)"; printf '{"kind":"run","app":"Fx","cmd":"%s","started":"%s","ended":"%s","tokens_out":1000,"model":"m1"}\n' "$p" "$now" "$now" >> "$dir/docs/metrics/runs.jsonl"
SH
chmod +x "$FAKE2"
app2() {   # an app whose documents are written, with a real checklist of three rows
  # shellcheck disable=SC2086
  app "$1" $STAGE1 $STAGE2
  printf '# Fx — Checklist\n\n## Requirements Status\n\n| ID | Requirement | Status | %% | Remarks |\n|---|---|---|---|---|\n| REQ-FN-001 | Add | Not Started | 0%% | |\n| REQ-FN-002 | List | Not Started | 0%% | |\n| REQ-FN-003 | Delete | Not Started | 0%% | |\n' > "$1/docs/Fx-Checklist.md"
}
dev2() { (cd "$1" && shift && env TF_DEVELOP_GOAL_SH="$FAKE2" TF_DEVELOP_TICK=1 TF_DEVELOP_FOLLOW_TICK=0.5 bash .tfcore/utils/tf-develop.sh . "$@" 2>&1); }
gone() { ! kill -0 "$1" 2>/dev/null || [[ "$(ps -o stat= -p "$1" 2>/dev/null)" == Z* ]]; }
waitfor() { local i=0; until grep -q "$2" "$1" 2>/dev/null || [[ $i -ge 60 ]]; do sleep 0.5; i=$((i+1)); done; }
pidof_run() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pid",""))' "$1/.tfcore/.session/develop.json" 2>/dev/null; }

# (1) the launching window follows the run to its end, and hears how it ended
dev_follow() {
  local d="$SCRATCH/follow" out f rc
  app2 "$d"
  out="$(dev2 "$d" --app Fx --model m1 --no-git --detach)"
  f="$(tf_timeout 90 bash -c 'cd "$1" && TF_DEVELOP_FOLLOW_TICK=0.5 bash .tfcore/utils/tf-develop.sh . --follow' _ "$d" 2>&1)"; rc=$?
  local miss="" w
  for w in "build started" "cycle 1 started" "cycle 1 ended" "verify (started" "rows built, 2 verified" "build done" \
      "handoff started" "UAT-ready" "the run has ended" "Result: Ready for UAT" "next: UAT"; do grep -qF "$w" <<<"$f" || miss+="[$w] "; done
  [[ $rc -eq 0 && -z "$miss" ]] && grep -qE 'started Fx — pid [0-9]+ on host .*model m1' <<<"$out" \
    && ok dev_follow "the launch says pid, host and model; --follow shows each step's start and end, each cycle, each verify and the rows, then ends by itself with the Build Report's result and the next command" \
    || bad dev_follow "rc=$rc; missing: $miss; launch: $(head -1 <<<"$out"); follow: $(tail -4 <<<"$f" | tr '\n' '|')"
  # --next: one report per event, for a harness whose background command reports once, when it exits (OpenCode)
  d="$SCRATCH/follow-next"; app2 "$d"
  dev2 "$d" --app Fx --model m1 --no-git --detach >/dev/null
  f="$(tf_timeout 60 bash -c 'cd "$1" && TF_DEVELOP_FOLLOW_TICK=0.5 bash .tfcore/utils/tf-develop.sh . --follow --next' _ "$d" 2>&1)"; rc=$?
  [[ $rc -eq 0 ]] && ! grep -q 'the run has ended' <<<"$f" && [[ $(wc -l <<<"$f") -le 8 ]] \
    && ok dev_follow_next "--follow --next returns at the next event, so a harness that reports a background command once still hears every step" \
    || bad dev_follow_next "rc=$rc: $(tr '\n' '|' <<<"$f")"
  (cd "$d" && bash .tfcore/utils/tf-develop.sh . --stop >/dev/null 2>&1)
}

# (2) *develop-status from any window: alive is checked, never assumed
dev_status() {
  local d="$SCRATCH/status" s1 s2 rc1 rc2 pid
  app2 "$d"
  (cd "$d" && TF_FAKE_SLEEP=20 TF_DEVELOP_GOAL_SH="$FAKE2" TF_DEVELOP_TICK=1 bash .tfcore/utils/tf-develop.sh . --app Fx --model m1 --no-git --detach >/dev/null 2>&1)
  waitfor "$d/.tfcore/.session/develop.log" "build started"; sleep 1
  s1="$(cd "$d" && bash .tfcore/utils/tf-develop.sh . --status 2>&1)"; rc1=$?
  pid="$(pidof_run "$d")"
  [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null; sleep 1
  s2="$(cd "$d" && bash .tfcore/utils/tf-develop.sh . --status 2>&1)"; rc2=$?
  local miss="" w
  for w in "Fx develop run — running" "pid $pid on host" ": running (checked" "claude, m1" "step: build (phase 1: build and verify)" \
      "started" "elapsed:" "last activity:" "tokens so far: this step 500 out, 10 in, 1,000 read from cache" "log: .tfcore/.session/develop.log" "report: docs/Fx-Build-Report.md"; do
    grep -qF "$w" <<<"$s1" || miss+="[$w] "; done
  [[ $rc1 -eq 0 && -z "$miss" && $rc2 -eq 1 ]] && grep -q 'stopped' <<<"$(head -1 <<<"$s2")" && ! grep -q 'running' <<<"$(head -1 <<<"$s2")" \
    && grep -q 'not running (checked' <<<"$s2" && grep -q -- '--resume' <<<"$s2" \
    && ok dev_status "--status names the process and host (checked), harness and model, the step and phase, start, elapsed, last activity, tokens, log and report; a killed run reads stopped, never running" \
    || bad dev_status "rc $rc1/$rc2; missing: $miss; first: $(tr '\n' '|' <<<"$s1" | cut -c1-300); after kill: $(head -2 <<<"$s2" | tr '\n' '|')"
  (cd "$d" && bash .tfcore/utils/tf-develop.sh . --stop >/dev/null 2>&1)
}

# (3) develop.log shows what happens inside a step: every goal cycle and every verify, with times
dev_progress() {
  local d="$SCRATCH/progress" out rc
  app2 "$d"
  out="$(dev2 "$d" --app Fx --model m1 --no-git)"; rc=$?
  local L="$d/.tfcore/.session/develop.log" miss="" w
  for w in "build cycle 1 started (first, model m1)" "build cycle 1 ended: the agent stopped" "build cycle 2 started (continuing" \
      "build verify (started" "graded 3 rows: 2 Verified, 1 FAIL" "build cycle ended: goal complete — build finished"; do
    grep -E '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\] tf-develop: ' "$L" 2>/dev/null | grep -qF "$w" || miss+="[$w] "; done
  [[ $rc -eq 0 && -z "$miss" ]] \
    && ok dev_progress "inside a step develop.log gets each goal cycle's start and end and each verify's result, each line with its time" \
    || bad dev_progress "rc=$rc; missing: $miss; log: $(tr '\n' '|' < "$L" | cut -c1-400)"
}

# (4) the model: --model on every step; none given, the launching session's; never the routing default
dev_model() {
  local d="$SCRATCH/model" h="$SCRATCH/home" out rc r=""
  app2 "$d"; TF_FAKE_SLEEP=0 dev2 "$d" --app Fx --model given-model --no-git >/dev/null
  [[ "$(grep -c -- '--model given-model --no-fallback' "$d/goal-args.log" 2>/dev/null)" == 2 ]] && r+=a
  mkdir -p "$h/.claude/projects/-x-app"
  printf '{"type":"user","message":{"content":"go"}}\n{"type":"assistant","message":{"model":"claude-opus-5-5","content":[]}}\n' > "$h/.claude/projects/-x-app/sess-1.jsonl"
  d="$SCRATCH/model2"; app2 "$d"
  TF_FAKE_SLEEP=0 HOME="$h" CLAUDE_CODE_SESSION_ID=sess-1 dev2 "$d" --app Fx --no-git >/dev/null
  [[ "$(grep -c -- '--model claude-opus-5-5' "$d/goal-args.log" 2>/dev/null)" == 2 ]] && grep -q "model claude-opus-5-5 (the launching session's model)" "$d/.tfcore/.session/develop.log" && r+=b
  # an OpenCode session's store, a throw-away copy under tests/.artifacts
  python3 "$ROOT/tests/develop/oc-session-fixture.py" "$h/.local/share/opencode/opencode.db" ses_1 venice gpt-x
  d="$SCRATCH/model3"; app2 "$d"
  TF_FAKE_SLEEP=0 HOME="$h" OPENCODE_SESSION_ID=ses_1 dev2 "$d" --app Fx --harness opencode --no-git >/dev/null
  [[ "$(grep -c -- '--harness opencode --tier standard --model venice/gpt-x' "$d/goal-args.log" 2>/dev/null)" == 2 ]] && r+=c
  d="$SCRATCH/model4"; app2 "$d"; printf 'tiers:\n  standard:\n    claude: sonnet\n' > "$d/.tfcore/routing.yaml"
  out="$(HOME="$h" dev2 "$d" --app Fx --no-git)"; rc=$?
  [[ $rc -eq 2 ]] && grep -q 'which model' <<<"$out" && [[ ! -e "$d/goal-args.log" ]] && r+=d
  [[ "$r" == abcd ]] && ok dev_model "--model reaches every step; with none, the launching Claude Code or OpenCode session's model does; with neither the run is refused, never routed to a default" \
    || bad dev_model "held: '$r' of abcd (a given model, b Claude Code session, c OpenCode session, d refused); last: $(tail -1 <<<"$out")"
}

# (5) --stop ends the supervisor and everything it started, records where, and --resume goes on from there
dev_stop() {
  local d="$SCRATCH/stop" out rc pid gpid kid st r=""
  app2 "$d"
  (cd "$d" && TF_FAKE_SPAWN=1 TF_FAKE_SLEEP=120 TF_DEVELOP_GOAL_SH="$FAKE2" bash .tfcore/utils/tf-develop.sh . --app Fx --model m1 --no-git --detach >/dev/null 2>&1)
  waitfor "$d/spawned.pid" "[0-9]"; sleep 1
  pid="$(pidof_run "$d")"; kid="$(cat "$d/spawned.pid" 2>/dev/null)"; gpid="$(pgrep -f "$FAKE2" | head -1)"
  out="$(cd "$d" && bash .tfcore/utils/tf-develop.sh . --stop 2>&1)"; rc=$?
  st="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["phases"][-1]["name"], d["phases"][-1]["status"], d.get("stopped",{}).get("at"))' "$d/.tfcore/.session/develop.json" 2>&1)"
  [[ $rc -eq 0 && -n "$pid" && -n "$kid" ]] && gone "$pid" && gone "$kid" && { [[ -z "$gpid" ]] || gone "$gpid"; } && r+=a
  [[ "$st" == "build stopped build" ]] && grep -q 'stopped by --stop during build' "$d/.tfcore/.session/develop.log" && r+=b
  out="$(TF_FAKE_SLEEP=0 dev2 "$d" --resume)"; rc=$?
  [[ $rc -eq 0 && "$(rep "$d")" == "uat-ready day1:skipped,day1-2:skipped,build:done,handoff:done" ]] \
    && [[ "$(python3 -c 'import json,sys; print([p["attempts"] for p in json.load(open(sys.argv[1]))["phases"] if p["phase"]=="build"][0])' "$d/docs/metrics/develop-report.json")" == 2 ]] && r+=c
  [[ -n "$kid" ]] && kill "$kid" 2>/dev/null
  [[ "$r" == abc ]] && ok dev_stop "--stop ends the supervisor, the goal runner and a process the agent started in its own session, records the step it stopped in, and --resume finishes from that step" \
    || bad dev_stop "held '$r' of abc (a all ended, b recorded, c resumed); state: $st; $(tail -2 <<<"$out" | tr '\n' '|')"
}

# --- MISS-TechieFlow-20261119-04: a stopped run's develop.json turned every new session into develop mode ---
# Develop mode belongs to the run's own processes, which carry TF_DEVELOP_RUN = develop.json's run_id. A
# session the owner opens in the app, with the stopped run waiting for --resume, is a normal one: --mode
# says off, and the one thing develop mode unlocks (its <app>-db container) is refused there.
dev_mode() {
  local d="$SCRATCH/mode" h="${TF_REGRESSION_HOOKS:-$ROOT/.tfcore/hooks}/guard-verify-deps.sh" got="" m1 m2 id="Fx-20261119T121820Z-4242"
  app2 "$d"; mkdir -p "$d/.tfcore/.session"
  printf '{"app":"Fx","run_id":"%s","pid":"4242","phases":[{"name":"build","status":"blocked","attempt":"1"}]}\n' "$id" > "$d/.tfcore/.session/develop.json"
  hk() { printf '{"tool_input":{"command":"docker run -d --name fx-db -p 5561:5432 postgres:17"}}' \
         | env "$1" CLAUDE_PROJECT_DIR="$d" bash "$h" >/dev/null 2>&1; got+="$?"; }
  hk TF_NOTHING=1; hk "TF_DEVELOP_RUN=$id"; hk TF_DEVELOP_RUN=another-run
  m1="$(cd "$d" && bash .tfcore/utils/tf-develop.sh . --mode 2>&1)"
  m2="$(cd "$d" && TF_DEVELOP_RUN="$id" bash .tfcore/utils/tf-develop.sh . --mode 2>&1)"
  [[ "$got" == 202 && "$m1" == off && "$m2" == on ]] \
    && ok dev_mode "with a stopped run waiting, a session the owner opens is not in develop mode (--mode off, its database container refused); the run's own processes are (on, allowed)" \
    || bad dev_mode "hook exits $got (want 202: plain session, the run, another run); --mode '$m1' / '$m2' (want off / on)"
}

# --- MISS-TechieFlow-20261119-03: the Build Report counted 4,763 tokens out where the cycles used 29,314 -------
# AstroLyfe's shape: a build stopped blocked before tokens were saved per attempt, its four goal cycles'
# Claude Code output still on disk (8,427 + 1,133 + 4,288 + 15,466 out), and run records covering only
# part of them (4,000 + 763). --report must count the cycles; a resume keeps attempt 1's count and adds its own.
dev_tokens() {
  local d="$SCRATCH/tokens" s0 s1 n=0 u rep1 rep2
  app2 "$d"; mkdir -p "$d/.tfcore/.session"
  s0="$(tf_date_from -u '-120 min' +%Y-%m-%dT%H:%M:%SZ)"; s1="$(tf_date_from -u '-60 min' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"app":"Fx","brief":"","harness":"claude","model":"","tier":"standard","push":false,"git":false,"started":"%s","plan":["day1","day1-2","build","handoff"],"phases":[{"name":"day1","status":"skipped","started":"%s","ended":"%s","attempt":"1"},{"name":"day1-2","status":"skipped","started":"%s","ended":"%s","attempt":"1"},{"name":"build","status":"blocked","started":"%s","ended":"%s","goal_exit":"3","commit":"","pushed":"off","attempt":"1"}]}\n' \
    "$s0" "$s0" "$s0" "$s0" "$s0" "$s0" "$s1" > "$d/.tfcore/.session/develop.json"
  for u in 1:8427 2:1133 3:4288 4:15466; do
    printf '{"type":"assistant","message":{"id":"m%s","model":"claude-sonnet-5-5","usage":{"output_tokens":3}}}\n{"type":"result","usage":{"input_tokens":5,"output_tokens":%s,"cache_read_input_tokens":1000,"cache_creation_input_tokens":10}}\n' "${u%%:*}" "${u#*:}" > "$d/.tfcore/.session/goal-cycle-${u%%:*}.out"
    touch -t "$(tf_date_from "-$(( 100 - ${u%%:*} * 10 )) min" +%Y%m%d%H%M.%S)" "$d/.tfcore/.session/goal-cycle-${u%%:*}.out"
  done
  for u in 110:4000 100:763; do
    printf '{"kind":"run","app":"Fx","cmd":"build-phase","started":"%s","ended":"%s","tokens_in":2,"tokens_out":%s,"model":"claude-sonnet-5-5"}\n' "$(tf_date_from -u "-${u%%:*} min" +%Y-%m-%dT%H:%M:%SZ)" "$(tf_date_from -u "-$(( ${u%%:*} - 5 )) min" +%Y-%m-%dT%H:%M:%SZ)" "${u#*:}" >> "$d/docs/metrics/runs.jsonl"
  done
  (cd "$d" && bash .tfcore/utils/tf-develop.sh . --report >/dev/null 2>&1)
  rep1="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["totals"]["tokens_out"], [p["tokens_out"] for p in r["phases"] if p["phase"]=="build"][0])' "$d/docs/metrics/develop-report.json" 2>&1)"
  [[ "$rep1" == "29314 29314" ]] && grep -q '29,314 out' "$d/docs/Fx-Build-Report.md" && n=$((n+1))
  TF_FAKE_SLEEP=0 dev2 "$d" --resume --model m1 >/dev/null
  rep2="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); b=[p for p in r["phases"] if p["phase"]=="build"][0]; print(r["status"], b["attempts"], b["tokens_out"], r["totals"]["tokens_out"])' "$d/docs/metrics/develop-report.json" 2>&1)"
  [[ "$rep2" == "uat-ready 2 29814 30314" ]] && n=$((n+1))
  [[ $n -eq 2 ]] && ok dev_tokens "the Build Report counts the goal cycles' own tokens (29,314 out, not the run records' 4,763), and a resume keeps the stopped attempt's count and adds its own" \
    || bad dev_tokens "report: '$rep1' (want 29314 29314); after resume: '$rep2' (want uat-ready 2 29814 30314)"
}

echo "# tests/develop — *develop-end-to-end on an existing app"
for t in dev_existing dev_phases dev_nogit dev_dry dev_names dev_follow dev_status dev_progress dev_model dev_stop dev_mode dev_tokens; do
  [[ -n "$only" && "$only" != "$t" ]] && continue
  "$t"
done
[[ $fail -eq 0 ]] && echo "# all develop cases hold" || echo "# develop cases FAILED"
exit $fail

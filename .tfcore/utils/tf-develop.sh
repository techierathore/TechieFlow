#!/usr/bin/env bash
# tf-develop.sh — *develop-end-to-end: a brief, or an app whose documents are written, to UAT, unattended.
#
#   bash .tfcore/utils/tf-develop.sh <app-dir> --app <App> [--brief <file>] [--harness claude|opencode]
#        [--model <id>] [--tier standard] [--no-push | --no-git] [--dry-run] [--detach]
#   bash .tfcore/utils/tf-develop.sh <app-dir> --report           # write the Build Report again from the saved state
#   bash .tfcore/utils/tf-develop.sh <app-dir> --resume          # continue a stopped run where it stopped
#   bash .tfcore/utils/tf-develop.sh <app-dir> --status          # *develop-status: alive (checked), step, rows, tokens
#   bash .tfcore/utils/tf-develop.sh <app-dir> --follow [--next] # the launching window follows the run to its end
#   bash .tfcore/utils/tf-develop.sh <app-dir> --stop            # end the run and every process it started
#   bash .tfcore/utils/tf-develop.sh <app-dir> --mode            # "on" only inside the run's own processes
#
# MODEL: --model, else the model of the agent session that launches it (tf-develop-watch.py reads it),
# else refused. Never the routing default: the AstroLyfe run of 19 Nov ran on Sonnet from an Opus window.
# It is passed to every goal cycle of every step with --no-fallback, so a usage limit waits for the reset.
#
# The flow-master's *develop-end-to-end starts this; the owner never types it. Each step is an unattended
# goal run (tf-goal.sh: no questions, survives usage limits by waiting for the reset and resuming):
#   day1      *day1-greenfield <App>            BRD, Architecture, mockups — no owner review stop
#   day1-2    *day1-greenfield <App> --stage2   checklist and the remaining documents
#   build     *build-phase <App>                every row built, verified inline, FIX mode on failures
#   handoff   *handoff-phase <App>              UsageGuide with its smoke checklist and test users: UAT-ready
# A Day-1 stage whose documents are all on disk is skipped; one with some missing writes only those
# (--brief is needed only when docs/<App>-BRD.md is not there). A Large app runs build-pN and
# handoff-pN for every row of docs/<App>-Phases.md in order, appPhase set to N first; a row whose Status
# is done or kept-whole is skipped. tf-develop-plan.py decides all of this before each step.
# develop.json holds the run's state. Develop mode (.tfcore/tasks/_develop-mode.md) is on only in the run's own
# processes, which carry TF_DEVELOP_RUN: a stopped run's file leaves a session the owner opens a normal one (--mode).
#
# GIT — the one exception to "agents never write to git", for this command only. The agent still
# cannot commit: its git guard is unchanged. THIS script commits after each phase, and pushes, from
# its own shell, never through an agent's tool. When it ends, nothing is left switched on.
# --no-git leaves git to the owner: no commit, no push, no repository needed; every step is still
# recorded in develop.json, docs/metrics/develop-report.json and the Build Report.
#
# METRICS — after every phase it writes docs/metrics/develop-report.json and docs/<App>-Build-Report.md:
# per phase the wall-clock time (limit waits included), the agent's working time and its tokens (summed
# from that phase's run records in docs/metrics/runs.jsonl), and the totals: "built in …".
#
# Exit 0 UAT-ready · 3 the agent declared a phase BLOCKED (the owner must act; listed in the report)
#      · 4 a phase ran out of cycles · 5 the provider refused the model · 2 usage error.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
  "")        awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 2 ;;
esac

DIR="$(cd "$1" 2>/dev/null && pwd)" || { echo "tf-develop: no such dir: $1" >&2; exit 2; }; shift
APP=""; BRIEF=""; HARNESS="claude"; MODEL=""; TIER="standard"; PUSH=1; GIT=1; DRY=0; RESUME=0; DETACH=0; REPORT_ONLY=0; VIEW=""; NEXT=""
ARGS_IN=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:-}"; shift 2 ;;
    --brief) BRIEF="${2:-}"; shift 2 ;;
    --harness) HARNESS="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --tier) TIER="${2:-}"; shift 2 ;;
    --no-push) PUSH=0; shift ;;
    --no-git) GIT=0; PUSH=0; shift ;;
    --dry-run) DRY=1; shift ;;
    --resume) RESUME=1; shift ;;
    --detach) DETACH=1; shift ;;
    --report) REPORT_ONLY=1; shift ;;
    --status|--follow|--stop|--mode) VIEW="${1#--}"; shift ;;
    --next) NEXT=--next; shift ;;
    *) echo "tf-develop: unknown argument $1" >&2; exit 2 ;;
  esac
done
WATCH="$HERE/tf-develop-watch.py"
MODEL_FROM="${TF_DEVELOP_MODEL_FROM:-}"; [[ -n "$MODEL" && -z "$MODEL_FROM" ]] && MODEL_FROM="--model"   # a detached run is told where its model came from
case "$VIEW" in   # any window: status and follow read only; stop ends the run and keeps its state for --resume
  status|follow|mode) exec python3 "$WATCH" "$VIEW" "$DIR" $NEXT ;;
  stop) python3 "$WATCH" stop "$DIR"; rc=$?
        grep -q '"source":[[:space:]]*"goal"' "$DIR/.tfcore/.session/yolo.json" 2>/dev/null \
          && CLAUDE_PROJECT_DIR="$DIR" TF_PROJECT_DIR="$DIR" bash "$DIR/.tfcore/utils/tf-yolo.sh" off >/dev/null 2>&1
        exit $rc ;;
esac
STATE="$DIR/.tfcore/.session/develop.json"
GOAL_SH="${TF_DEVELOP_GOAL_SH:-$DIR/.tfcore/utils/tf-goal.sh}"   # tests point this at a fake
PLAN_PY="$HERE/tf-develop-plan.py"
mkdir -p "$DIR/.tfcore/.session" "$DIR/docs/metrics"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# The app folder must be the TOP of its own repository. A folder inside another repository answers
# rev-parse too, and `git add -A` there staged the whole outer repository (found by dev_001 on its first run).
own_repo() { local top; top="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "$top" && "$(cd "$top" && pwd -P)" == "$(cd "$DIR" && pwd -P)" ]]; }
log() { printf '[%s] tf-develop: %s\n' "$(ts)" "$*" | tee -a "$DIR/.tfcore/.session/develop.log" >&2; }
# --detach: this same run in its own session (tf_setsid, portable), so it outlives the agent session that
# started it. It returns once the run has written its pid, and says where it runs and on which model.
detach() {
  local rest=() a token="$$-$RANDOM" i=0
  for a in "${ARGS_IN[@]}"; do [[ "$a" != --detach ]] && rest+=("$a"); done
  [[ " ${ARGS_IN[*]} " == *" --model "* ]] || rest+=(--model "$MODEL")
  source "$HERE/tf-portable.sh"
  TF_DEVELOP_LAUNCH="$token" TF_DEVELOP_MODEL_FROM="$MODEL_FROM" tf_setsid bash "$0" "$DIR" "${rest[@]}" > "$DIR/.tfcore/.session/develop.out" 2>&1 < /dev/null &
  while [[ "$(st get launch)" != "$token" && $i -lt 40 ]]; do sleep 0.5; i=$((i+1)); done
  if [[ "$(st get launch)" != "$token" ]]; then echo "tf-develop: the run did not start — $(tail -3 "$DIR/.tfcore/.session/develop.out" | tr '\n' ' ')" >&2; exit 1; fi
  echo "tf-develop: started $APP — pid $(st get pid) on host $(st get host), harness $HARNESS, model $MODEL ($MODEL_FROM)"
  echo "  follow: bash .tfcore/utils/tf-develop.sh . --follow · status: … --status · stop: … --stop"
  echo "  log: .tfcore/.session/develop.log · result: docs/$APP-Build-Report.md"
  exit 0
}

st() { python3 - "$STATE" "$@" <<'PY'
import json, sys
p, op, *a = sys.argv[1:]
try: d = json.load(open(p))
except Exception: d = {}
if op == "get": print(d.get(a[0], ""))
elif op == "init":
    d = {"app": a[0], "brief": a[1], "harness": a[2], "model": a[3], "tier": a[4], "push": a[5] == "1", "started": a[6], "phases": [], "git": a[7] == "1"}
elif op == "set":     # key value ...; an empty value removes the key
    for k, v in zip(a[::2], a[1::2]):
        if v: d[k] = v
        else: d.pop(k, None)
elif op == "plan": d["plan"] = a[0].split(",")   # the steps that make the app UAT-ready, for the report
elif op == "done": print("yes" if any(x["name"] == a[0] and x["status"] in ("done", "skipped") for x in d.get("phases", [])) else "")
elif op == "attempts": print(sum(1 for x in d.get("phases", []) if x["name"] == a[0]))
elif op == "phase":   # name status started ended exit commit pushed attempt — one entry per attempt, keyed by its number:
    # a blocked attempt and its resume can start in the same second on a fast machine, and keying by the
    # start made the second overwrite the first (dev_001 on the CI runner, 2026-10-09)
    ph = d.get("phases", [])
    new = dict(zip(("name", "status", "started", "ended", "goal_exit", "commit", "pushed", "attempt"), a))
    hit = [i for i, x in enumerate(ph) if x["name"] == a[0] and str(x.get("attempt", "")) == a[7]]
    if hit: ph[hit[0]] = new
    else: ph.append(new)
    d["phases"] = ph
if op in ("init", "phase", "plan", "set"): json.dump(d, open(p, "w"), indent=1)
PY
}

if [[ $REPORT_ONLY -eq 1 ]]; then :
elif [[ $RESUME -eq 1 ]]; then
  [[ -f "$STATE" ]] || { echo "tf-develop: --resume: no $STATE" >&2; exit 2; }
  python3 "$WATCH" status "$DIR" >/dev/null 2>&1 && { echo "tf-develop: --resume: the run is still running — see: bash .tfcore/utils/tf-develop.sh . --status" >&2; exit 2; }
  APP="$(st get app)"; BRIEF="$(st get brief)"; HARNESS="$(st get harness)"; TIER="$(st get tier)"
  [[ -z "$MODEL" ]] && MODEL="$(st get model)" && MODEL_FROM="kept from the run it continues"   # --model on the resume wins
  [[ "$(st get push)" == "False" ]] && PUSH=0
  [[ "$(st get git)" == "False" ]] && { GIT=0; PUSH=0; }
else
  [[ -n "$APP" ]] || { echo "tf-develop: --app <App> is required" >&2; exit 2; }
  [[ "$APP" =~ ^[A-Z][A-Za-z0-9]*$ ]] || { echo "tf-develop: --app must be PascalCase with no spaces" >&2; exit 2; }
  if [[ $DRY -eq 0 && -f "$STATE" ]]; then
    python3 "$WATCH" status "$DIR" >/dev/null 2>&1 && { echo "tf-develop: a develop run is running here — see: bash .tfcore/utils/tf-develop.sh . --status" >&2; exit 2; }
    echo "tf-develop: a stopped develop run is here ($(st get app)) — continue it with --resume, or see --status" >&2; exit 2
  fi
  if [[ -n "$BRIEF" ]]; then [[ -f "$BRIEF" ]] || { echo "tf-develop: brief not found: $BRIEF" >&2; exit 2; }
  elif [[ ! -f "$DIR/docs/$APP-BRD.md" ]]; then echo "tf-develop: --brief <file> is required: docs/$APP-BRD.md is not written yet" >&2; exit 2; fi
  if [[ $GIT -eq 1 ]]; then
    own_repo || { echo "tf-develop: $DIR is not a git repository of its own (a folder inside another repository does not count) — set it up first, or pass --no-git" >&2; exit 2; }
    if [[ $PUSH -eq 1 && -z "$(git -C "$DIR" remote 2>/dev/null)" ]]; then echo "tf-develop: $DIR has no git remote to push to — add one, or pass --no-push" >&2; exit 2; fi
  fi
  if [[ -z "$MODEL" ]]; then MODEL="$(python3 "$WATCH" session-model "$HARNESS")"; MODEL_FROM="the launching session's model"; fi
  if [[ -z "$MODEL" && $DRY -eq 0 ]]; then
    echo "tf-develop: which model? No --model was given and the launching $HARNESS session's model could not be read — pass --model <id>" >&2; exit 2
  fi
  if [[ $DETACH -eq 1 && $DRY -eq 0 ]]; then detach; fi
  if [[ $DRY -eq 0 ]]; then
    if [[ -n "$BRIEF" ]]; then
      [[ "$(cd "$(dirname "$BRIEF")" && pwd)/$(basename "$BRIEF")" == "$DIR/docs/$APP-Brief.md" ]] || cp "$BRIEF" "$DIR/docs/$APP-Brief.md"
      BRIEF="docs/$APP-Brief.md"
    fi
    st init "$APP" "$BRIEF" "$HARNESS" "$MODEL" "$TIER" "$PUSH" "$(ts)" "$GIT"
  fi
fi
if [[ $RESUME -eq 1 ]]; then
  if [[ -z "$MODEL" ]]; then MODEL="$(python3 "$WATCH" session-model "$HARNESS")"; MODEL_FROM="the launching session's model"; fi
  [[ -n "$MODEL" ]] || { echo "tf-develop: which model? The stopped run recorded none and the launching $HARNESS session's model could not be read — pass --model <id>" >&2; exit 2; }
  [[ $DETACH -eq 1 ]] && detach
fi
if [[ $REPORT_ONLY -eq 0 && $DRY -eq 0 ]]; then   # this process is the run: what any window needs to check it
  TF_DEVELOP_RUN="$APP-$(date -u +%Y%m%dT%H%M%SZ)-$$"; export TF_DEVELOP_RUN   # every process it starts carries it (--stop)
  st set pid "$$" host "$(python3 -c 'import socket; print(socket.gethostname())')" run_id "$TF_DEVELOP_RUN" model "$MODEL" \
     model_from "${MODEL_FROM:-}" launch "${TF_DEVELOP_LAUNCH:-}" stopped ""
  python3 "$WATCH" backfill "$DIR" 2>/dev/null   # a stopped attempt's tokens, before this run's first cycle overwrites its files
  log "run started: pid $$ on host $(st get host), harness $HARNESS, model $MODEL (${MODEL_FROM:-})"
fi

if [[ -n "$BRIEF" ]]; then CONCEPT="The brief is $BRIEF."; else CONCEPT="There is no brief: the documents already written (docs/$APP-BRD.md and the rest) are the concept."; fi
MODE="Act as the flow-master (.tfcore/agents/flow-master.md). The command is *develop-end-to-end for $APP, in develop mode: read .tfcore/tasks/_develop-mode.md first and follow it in every task — no question to the owner, no stop for an owner review; every decision the owner would make is yours, written where that rule says. $CONCEPT"
goal_of() {   # $1 step, $2 its detail from tf-develop-plan.py (the paths still missing, or the phase number)
  local only="" n="${2%% *}" ph=""
  [[ -n "$2" ]] && only=" Some of this stage's documents are already written: write only these, $2, and keep every other document as it is (no --archive)."
  [[ "$1" == *-p* ]] && ph=" for phase $n of docs/$APP-Phases.md (appPhase $n in core-config.yaml): that phase's checklist and UIDesign"
  case "$1" in
    day1)    echo "$MODE Run *day1-greenfield $APP, stage 1 (.tfcore/tasks/day1-greenfield.md), with the brief as the concept, all of it.$only When stage 1 is complete and rendered, the goal is met: do not stop for review and do not start stage 2." ;;
    day1-2)  echo "$MODE Run *day1-greenfield $APP --stage2.$only The goal is met when stage 2 is complete and its status gate has run." ;;
    build*)  echo "$MODE Run *build-phase $APP (.tfcore/tasks/build-phase.md)${ph:- on the whole phase checklist}: every row built, the verifier chained inline, FIX mode on every failing row, until every row is terminal. Create and migrate the database the Architecture names, locally, as that rule says." ;;
    handoff*) echo "$MODE Run *handoff-phase $APP (.tfcore/tasks/handoff-phase.md)${ph}: the UsageGuide with its smoke checklist and test users, the guides, the HTMLs, the status gate. The goal is met when the app is ready for the owner's UAT${ph:+ of that phase}." ;;
  esac
}
plan_of() {   # day1 | day1-2 | phases → "<step> TAB run|skip TAB <detail>" lines; an older .tfcore without the helper gets the four steps
  if [[ -f "$PLAN_PY" ]]; then python3 "$PLAN_PY" "$DIR" "$APP" "$1"; return; fi
  case "$1" in day1|day1-2) printf '%s\trun\t\n' "$1" ;; phases) printf 'build\trun\t1\nhandoff\trun\t1\n' ;; esac
}

commit_phase() {   # $1 phase → prints "<sha> <pushed yes|no|off>"; "- off" under --no-git, which touches no git at all
  local sha="" pushed="off"
  [[ $GIT -eq 1 ]] || { echo "- off"; return; }
  own_repo || { echo "none no"; return; }   # never commit into a repository the app folder merely sits inside
  if [[ -n "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]]; then
    git -C "$DIR" add -A >/dev/null 2>&1
    git -C "$DIR" commit -q -m "TechieFlow develop-end-to-end: $1 done — $APP" -m "Written by tf-develop.sh after the $1 phase; per-phase time and tokens in docs/metrics/develop-report.json." >/dev/null 2>&1
  fi
  sha="$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null)"
  if [[ $PUSH -eq 1 ]]; then
    if git -C "$DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      git -C "$DIR" push -q >/dev/null 2>&1 && pushed=yes || pushed=no
    else
      git -C "$DIR" push -q -u "$(git -C "$DIR" remote | head -1)" HEAD >/dev/null 2>&1 && pushed=yes || pushed=no
    fi
  fi
  echo "${sha:-none} $pushed"
}

report() {   # writes docs/metrics/develop-report.json and docs/<App>-Build-Report.md from the state and runs.jsonl
  python3 - "$STATE" "$DIR" <<'PY'
import datetime, json, os, sys
state, root = json.load(open(sys.argv[1])), sys.argv[2]
app = state["app"]
def t(s):
    try: return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
    except Exception: return None
runs = []
try:
    for line in open(os.path.join(root, "docs", "metrics", "runs.jsonl"), encoding="utf-8", errors="replace"):
        try: r = json.loads(line)
        except Exception: continue
        if r.get("kind", "run") == "run" and r.get("app") in (None, app) and r.get("started") and r.get("cmd") != "develop-status": runs.append(r)
except OSError: pass
voided = {(r.get("cmd"), r.get("started")) for r in runs if r.get("kind") == "run-void"}
def hm(s): s = int(s or 0); return f"{s // 3600} h {s % 3600 // 60:02d} min" if s >= 3600 else f"{s // 60} min {s % 60:02d} s"
NAMES = {"day1": "Day 1, stage 1 (BRD, Architecture, mockups)", "day1-2": "Day 1, stage 2 (checklist, documents)",
         "build": "Build and verify", "handoff": "Handoff (UsageGuide, UAT-ready)", "build-p": "Phase {}: build and verify", "handoff-p": "Phase {}: handoff"}
out, tot, models = [], {"wall_s": 0, "work_s": 0, "tokens_in": 0, "tokens_out": 0, "tokens_cache_read": 0, "tokens_cache_write": 0, "runs": 0}, {}
try: cyc = json.load(open(os.path.join(root, ".tfcore", ".session", "develop-tokens.json")))   # per step and attempt, from the goal cycles
except Exception: cyc = {}
# One row per phase, summing its attempts. A record belongs to the attempt whose window holds its start, first second
# in and last out (the first proof run counted the build's 301,201 tokens under Day 1 stage 2).
order, attempts = [], {}
for x in state.get("phases", []):
    if x["name"] not in attempts: order.append(x["name"])
    attempts.setdefault(x["name"], []).append(x)
def inside(r, wins):
    s = t(r.get("started"))
    return s is not None and any(a <= s < b for a, b in wins)
for name in order:
    ats = attempts[name]; p = ats[-1]
    wins = [(t(x.get("started")), t(x.get("ended")) or datetime.datetime.utcnow()) for x in ats if t(x.get("started"))]
    rs = [r for r in runs if (r.get("cmd"), r.get("started")) not in voided and inside(r, wins)]
    # A record lying wholly inside another (devguide inside handoff-phase) is dropped, or its tokens count twice;
    # working time is the union of the windows, not their sum.
    span = lambda r: (t(r.get("started")), t(r.get("ended")) or t(r.get("started")))
    rs = [r for i, r in enumerate(rs) if not any(
        j != i and span(o)[0] and span(r)[0] and span(o)[0] <= span(r)[0] and span(r)[1] <= span(o)[1]
        and (span(o) != span(r) or j < i) for j, o in enumerate(rs))]
    iv = sorted(span(r) for r in rs if span(r)[0]); union, cur = 0, None
    for a_, b_ in iv:
        if cur and a_ <= cur[1]: cur = (cur[0], max(cur[1], b_))
        else:
            if cur: union += (cur[1] - cur[0]).total_seconds()
            cur = (a_, b_)
    if cur: union += (cur[1] - cur[0]).total_seconds()
    row = {"phase": name, "title": NAMES.get(name) or NAMES.get(name.rstrip("0123456789"), name).format(name.rsplit("p", 1)[-1]), "status": p.get("status"), "attempts": len(ats),
           "started": ats[0].get("started"), "ended": p.get("ended"), "wall_s": int(sum((b - a).total_seconds() for a, b in wins)), "work_s": int(union),
           "tokens_in": sum(int(r.get("tokens_in") or 0) for r in rs), "tokens_out": sum(int(r.get("tokens_out") or 0) for r in rs),
           "tokens_cache_read": sum(int(r.get("tokens_cache_read") or 0) for r in rs), "tokens_cache_write": sum(int(r.get("tokens_cache_write") or 0) for r in rs),
           "runs": len(rs), "commands": sorted({r.get("cmd") for r in rs if r.get("cmd")}), "commit": p.get("commit"), "pushed": p.get("pushed")}
    have = {str(x.get("attempt", "1")): cyc[name][str(x.get("attempt", "1"))] for x in ats if str(x.get("attempt", "1")) in (cyc.get(name) or {})}
    if have:   # the goal cycles' own count; run records only for an attempt with none saved (MISS-TechieFlow-20261119-03: 4,763 against 29,314)
        rs = [r for r in rs if inside(r, [w for x, w in zip([x for x in ats if t(x.get("started"))], wins) if str(x.get("attempt", "1")) not in have])]
        for k in ("in", "out", "cache_read", "cache_write"): row["tokens_" + k] = sum(int(v.get(k) or 0) for v in have.values()) + sum(int(r.get("tokens_" + k) or 0) for r in rs)
        models[state.get("model") or "unknown"] = models.get(state.get("model") or "unknown", 0) + sum(int(v.get("out") or 0) for v in have.values())
    row["tokens_from"] = "goal cycles" if have else "run records"
    for r in rs:
        for m, n in (r.get("model_tokens_out") or {r.get("model") or "unknown": r.get("tokens_out") or 0}).items():
            models[m] = models.get(m, 0) + int(n or 0)
    for k in tot: tot[k] += row[k]
    out.append(row)
ready = all(any(p["phase"] == s and p["status"] in ("done", "skipped") for p in out) for s in state.get("plan") or ["day1", "day1-2", "build", "handoff"])
starts = [t(p["started"]) for p in out if t(p["started"])]; ends = [t(p["ended"]) for p in out if t(p["ended"])]
span = int((max(ends) - min(starts)).total_seconds()) if starts and ends else 0
rep = {"app": app, "harness": state.get("harness"), "model": state.get("model") or None, "tier": state.get("tier"),
       "started": state.get("started"), "status": "uat-ready" if ready else (out[-1]["status"] if out else "not-started"),
       "elapsed_s": span, "totals": tot, "tokens_out_by_model": models, "phases": out,
       "note": "elapsed_s is first phase start to last phase end, usage-limit waits included; work_s is the agent's own run time from its run records"}
json.dump(rep, open(os.path.join(root, "docs", "metrics", "develop-report.json"), "w"), indent=1)
L = [f"# {app} — Build Report", "", "| | |", "|---|---|",
     f"| What | {app}, developed end to end from {state.get('brief') or 'the documents already written'} by *develop-end-to-end |",
     f"| Result | {'Ready for UAT' if ready else 'Stopped at ' + (out[-1]['title'] if out else 'the start') + ' (' + rep['status'] + ')'} |",
     f"| Built in | {hm(span)} from start to finish, of which the agent worked {hm(tot['work_s'])} |",
     f"| Harness and model | {state.get('harness')}, {', '.join(sorted(models)) or state.get('model') or 'default'} |",
     f"| Git | {'left to the owner (--no-git): nothing committed or pushed' if state.get('git') is False else 'committed after each phase' + ('' if state.get('push') else ', not pushed')} |",
     f"| Tokens | {tot['tokens_in']:,} in, {tot['tokens_out']:,} out, {tot['tokens_cache_read']:,} read from cache, {tot['tokens_cache_write']:,} written to cache |",
     "", "## Phases", "", "| Phase | Result | Time | Agent working | Tokens out | Commit |", "|---|---|---|---|---|---|"]
for p in out:
    L.append(f"| {p['title']}{' (' + str(p['attempts']) + ' attempts)' if p['attempts'] > 1 else ''} | {p['status']} | {hm(p['wall_s'])} | {hm(p['work_s'])} | {p['tokens_out']:,} | {p['commit'] or '—'}{'' if p['pushed'] in ('yes', 'off') else ' (not pushed)'} |")
L += ["", "Time is the clock from the phase's start to its end, summed over its attempts, waits for a usage limit to reset included. "
      "Built in also counts the time between attempts, while a stopped run waited to be resumed. "
      "Agent working is the sum of the phase's run records. Tokens are the goal cycles' own count where the harness reports it (Claude Code), else the run records'. The same figures, for a comparison harness, are in "
      "`docs/metrics/develop-report.json`.", ""]
open(os.path.join(root, "docs", f"{app}-Build-Report.md"), "w", encoding="utf-8").write("\n".join(L))
print(f"report: {rep['status']}, {hm(span)} elapsed, {tot['tokens_out']:,} tokens out — docs/{app}-Build-Report.md")
PY
}

# --report: write the report again from the saved state (the run's, or the finished run's), nothing else
if [[ $REPORT_ONLY -eq 1 ]]; then
  [[ -f "$STATE" ]] || STATE="$DIR/.tfcore/.session/develop-done.json"
  [[ -f "$STATE" ]] || { echo "tf-develop: --report: no develop run recorded here" >&2; exit 2; }
  python3 "$WATCH" backfill "$DIR" 2>/dev/null; report; exit 0
fi
GOAL_ARGS=(--harness "$HARNESS" --tier "$TIER"); [[ -n "$MODEL" ]] && GOAL_ARGS+=(--model "$MODEL" --no-fallback)
GIT_NOTE="commit and push"; [[ $PUSH -eq 0 ]] && GIT_NOTE="commit, no push"
[[ $GIT -eq 0 ]] && GIT_NOTE="no commit and no push (git is the owner's); recorded in develop.json, develop-report.json and the Build Report"
step() {   # $1 step, $2 run|skip, $3 detail — runs one step to its end; a failed or blocked step ends the run here
  local phase="$1" act="$2" detail="$3" start end rc status attempt sha pushed n="${3%% *}"
  if [[ $DRY -eq 1 ]]; then
    if [[ "$act" == skip ]]; then
      [[ "$phase" == *-p* ]] && echo "$phase: skip — phase $n is ${detail#* } in docs/$APP-Phases.md" || echo "$phase: skip — $detail"
    else
      local g; g="$(goal_of "$phase" "$detail")"; g="${g#"$MODE "}"
      [[ "$phase" == build-p* ]] && echo "$phase: set appPhase $n (tf-day1-files.sh $APP --phase $n)"
      [[ "$phase" == day1* && -n "$detail" ]] && echo "$phase: run — only what is missing: $detail" || echo "$phase: run — ${g:0:160}…"
      echo "$phase: then $GIT_NOTE"
    fi
    return 0
  fi
  [[ -n "$(st done "$phase")" ]] && { log "$phase already done — skipped"; return 0; }
  attempt=$(( $(st attempts "$phase") + 1 ))
  if [[ "$act" == skip ]]; then
    start="$(ts)"; st phase "$phase" skipped "$start" "$start" 0 "" off "$attempt"
    log "$phase skipped — $([[ "$phase" == *-p* ]] && echo "phase $n is ${detail#* } in docs/$APP-Phases.md" || echo "$detail")"; return 0
  fi
  if [[ "$phase" == build-p* ]]; then   # the phase being worked is appPhase; the agent builds that one
    (cd "$DIR" && bash .tfcore/utils/tf-day1-files.sh "$APP" --phase "$n" >/dev/null 2>&1) && log "appPhase set to $n" || log "appPhase not set (tf-day1-files.sh failed); the goal names phase $n"
  fi
  [[ -f "$WATCH" ]] && python3 "$WATCH" clear-cycles "$DIR" 2>/dev/null   # earlier steps' cycle files aside, their tokens already saved
  start="$(ts)"; log "$phase started — $HARNESS, model $MODEL"
  st phase "$phase" running "$start" "" "" "" "" "$attempt"
  python3 "$WATCH" progress "$DIR" "$phase" $$ </dev/null >/dev/null 2>&1 & local watcher=$!   # verifies and rows, into develop.log
  { bash "$GOAL_SH" "${GOAL_ARGS[@]}" "$DIR" "$(goal_of "$phase" "$detail")" </dev/null 2>&1 1>&3 \
      | if [[ -f "$WATCH" ]]; then python3 "$WATCH" cycles "$DIR" "$phase" "$MODEL"; else cat >&2; fi; rc=${PIPESTATUS[0]}; } 3>&1   # each goal cycle, into develop.log
  kill -TERM "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  python3 "$WATCH" tokens "$DIR" "$phase" all "$attempt" 2>/dev/null   # every cycle file present is this attempt's
  status=done; [[ $rc -eq 3 ]] && status=blocked; [[ $rc -ne 0 && $rc -ne 3 ]] && status="failed (exit $rc)"
  end="$(ts)"
  st phase "$phase" "$status" "$start" "$end" "$rc" "" "" "$attempt"
  report >/dev/null                                    # the phase's figures go into its own commit
  read -r sha pushed <<<"$(commit_phase "$phase")"; [[ "$sha" == - ]] && sha=""
  st phase "$phase" "$status" "$start" "$end" "$rc" "$sha" "$pushed" "$attempt"
  log "$phase $status — commit ${sha:-none (--no-git)}, pushed $pushed"
  if [[ $rc -ne 0 ]]; then report; commit_phase "report" >/dev/null; exit "$rc"; fi
}
[[ $DRY -eq 1 ]] && printf 'plan for %s in %s (dry run: nothing runs, nothing is written)\neach step runs: bash %s %s <app> "<develop mode> <the goal below>"\n' "$APP" "$DIR" "${GOAL_SH#"$DIR/"}" "${GOAL_ARGS[*]}"
for s in day1 day1-2; do
  IFS=$'\t' read -r name act detail <<<"$(plan_of "$s")"
  step "$name" "$act" "$detail"
done
PLAN="$(plan_of phases)"
[[ $DRY -eq 1 && ! -f "$DIR/docs/$APP-Phases.md" ]] && echo "(one phase: no docs/$APP-Phases.md yet; a Large app's phases are read from it once Day 1 has written it)"
[[ $DRY -eq 0 ]] && st plan "day1,day1-2,$(cut -f1 <<<"$PLAN" | paste -s -d, -)"
while IFS=$'\t' read -r name act detail <&3; do step "$name" "$act" "$detail"; done 3<<<"$PLAN"
[[ $DRY -eq 1 ]] && exit 0
report; read -r sha pushed <<<"$(commit_phase "build report")"; [[ "$sha" == - ]] && sha=""
log "UAT-ready — final report commit ${sha:-none (--no-git)}, pushed $pushed"
mv -f "$STATE" "$DIR/.tfcore/.session/develop-done.json"   # develop mode ends with the run
exit 0

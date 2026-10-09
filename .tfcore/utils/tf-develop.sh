#!/usr/bin/env bash
# tf-develop.sh — *develop-end-to-end: a brief in, a greenfield app out, up to UAT, unattended (2026-10-08).
#
#   bash .tfcore/utils/tf-develop.sh <app-dir> --app <App> --brief <file> [--harness claude|opencode]
#        [--model <id>] [--tier standard] [--no-push] [--dry-run] [--detach]
#   bash .tfcore/utils/tf-develop.sh <app-dir> --report           # write the Build Report again from the saved state
#   bash .tfcore/utils/tf-develop.sh <app-dir> --resume          # continue a stopped run where it stopped
#
# The flow-master's *develop-end-to-end starts this; the owner never types it. It runs four phases, each
# one an unattended goal run (tf-goal.sh: no questions, survives usage limits by waiting for the reset
# and resuming the same session):
#   day1      *day1-greenfield <App>            BRD, Architecture, mockups — no owner review stop
#   day1-2    *day1-greenfield <App> --stage2   checklist and the remaining documents
#   build     *build-phase <App>                every row built, verified inline, FIX mode on failures
#   handoff   *handoff-phase <App>              UsageGuide with its smoke checklist and test users: UAT-ready
# While it runs, .tfcore/.session/develop.json exists and every task follows .tfcore/tasks/_develop-mode.md.
#
# GIT — the one exception to "agents never write to git", for this command only. The agent still
# cannot commit: its git guard is unchanged. THIS script commits after each phase, and pushes, from
# its own shell, never through an agent's tool. When it ends, nothing is left switched on.
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
  -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "")        sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

DIR="$(cd "$1" 2>/dev/null && pwd)" || { echo "tf-develop: no such dir: $1" >&2; exit 2; }; shift
APP=""; BRIEF=""; HARNESS="claude"; MODEL=""; TIER="standard"; PUSH=1; DRY=0; RESUME=0; DETACH=0; REPORT_ONLY=0
ARGS_IN=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:-}"; shift 2 ;;
    --brief) BRIEF="${2:-}"; shift 2 ;;
    --harness) HARNESS="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --tier) TIER="${2:-}"; shift 2 ;;
    --no-push) PUSH=0; shift ;;
    --dry-run) DRY=1; shift ;;
    --resume) RESUME=1; shift ;;
    --detach) DETACH=1; shift ;;
    --report) REPORT_ONLY=1; shift ;;
    *) echo "tf-develop: unknown argument $1" >&2; exit 2 ;;
  esac
done
# --detach: start this same run in its own session and return at once, so it outlives the agent session
# that started it (the flow-master's *develop-end-to-end), in a session of its own (tf_setsid, portable).
if [[ $DETACH -eq 1 ]]; then
  mkdir -p "$DIR/.tfcore/.session"
  rest=(); for a in "${ARGS_IN[@]}"; do [[ "$a" != --detach ]] && rest+=("$a"); done
  source "$HERE/tf-portable.sh"   # tf_setsid works on macOS too (a python3 or perl stand-in)
  tf_setsid bash "$0" "$DIR" "${rest[@]}" > "$DIR/.tfcore/.session/develop.out" 2>&1 < /dev/null &
  echo "tf-develop: started (pid $!) — follow .tfcore/.session/develop.log; the result is docs/<App>-Build-Report.md"
  exit 0
fi
STATE="$DIR/.tfcore/.session/develop.json"
GOAL_SH="${TF_DEVELOP_GOAL_SH:-$DIR/.tfcore/utils/tf-goal.sh}"   # tests point this at a fake
mkdir -p "$DIR/.tfcore/.session" "$DIR/docs/metrics"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# The app folder must be the TOP of its own repository. A folder inside another repository answers
# rev-parse too, and `git add -A` there staged the whole outer repository (found by dev_001 on its first run).
own_repo() { local top; top="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "$top" && "$(cd "$top" && pwd -P)" == "$(cd "$DIR" && pwd -P)" ]]; }
log() { printf '[%s] tf-develop: %s\n' "$(ts)" "$*" | tee -a "$DIR/.tfcore/.session/develop.log" >&2; }

st() { python3 - "$STATE" "$@" <<'PY'
import json, sys
p, op, *a = sys.argv[1:]
try: d = json.load(open(p))
except Exception: d = {}
if op == "get": print(d.get(a[0], ""))
elif op == "init":
    d = {"app": a[0], "brief": a[1], "harness": a[2], "model": a[3], "tier": a[4], "push": a[5] == "1", "started": a[6], "phases": []}
elif op == "done": print("yes" if any(x["name"] == a[0] and x["status"] == "done" for x in d.get("phases", [])) else "")
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
if op in ("init", "phase"): json.dump(d, open(p, "w"), indent=1)
PY
}

if [[ $REPORT_ONLY -eq 1 ]]; then :
elif [[ $RESUME -eq 1 ]]; then
  [[ -f "$STATE" ]] || { echo "tf-develop: --resume: no $STATE" >&2; exit 2; }
  APP="$(st get app)"; BRIEF="$(st get brief)"; HARNESS="$(st get harness)"; MODEL="$(st get model)"; TIER="$(st get tier)"
  [[ "$(st get push)" == "False" ]] && PUSH=0
else
  [[ -n "$APP" && -n "$BRIEF" ]] || { echo "tf-develop: --app <App> and --brief <file> are required" >&2; exit 2; }
  [[ "$APP" =~ ^[A-Z][A-Za-z0-9]*$ ]] || { echo "tf-develop: --app must be PascalCase with no spaces" >&2; exit 2; }
  [[ -f "$BRIEF" ]] || { echo "tf-develop: brief not found: $BRIEF" >&2; exit 2; }
  own_repo || { echo "tf-develop: $DIR is not a git repository of its own (a folder inside another repository does not count) — set it up first" >&2; exit 2; }
  if [[ $PUSH -eq 1 && -z "$(git -C "$DIR" remote 2>/dev/null)" ]]; then echo "tf-develop: $DIR has no git remote to push to — add one, or pass --no-push" >&2; exit 2; fi
  if [[ $DRY -eq 0 ]]; then
    [[ "$(cd "$(dirname "$BRIEF")" && pwd)/$(basename "$BRIEF")" == "$DIR/docs/$APP-Brief.md" ]] || cp "$BRIEF" "$DIR/docs/$APP-Brief.md"
    st init "$APP" "docs/$APP-Brief.md" "$HARNESS" "$MODEL" "$TIER" "$PUSH" "$(ts)"
  fi
fi

MODE="Act as the flow-master (.tfcore/agents/flow-master.md). The command is *develop-end-to-end for $APP, in develop mode: read .tfcore/tasks/_develop-mode.md first and follow it in every task — no question to the owner, no stop for an owner review; every decision the owner would make is yours, written where that rule says. The brief is docs/$APP-Brief.md."
goal_of() {
  case "$1" in
    day1)    echo "$MODE Run *day1-greenfield $APP, stage 1 (.tfcore/tasks/day1-greenfield.md), with the brief as the concept, all of it. When stage 1 is complete and rendered, the goal is met: do not stop for review and do not start stage 2." ;;
    day1-2)  echo "$MODE Run *day1-greenfield $APP --stage2. The goal is met when stage 2 is complete and its status gate has run." ;;
    build)   echo "$MODE Run *build-phase $APP (.tfcore/tasks/build-phase.md) on the whole phase checklist: every row built, the verifier chained inline, FIX mode on every failing row, until every row is terminal. Create and migrate the database the Architecture names, locally, as that rule says." ;;
    handoff) echo "$MODE Run *handoff-phase $APP (.tfcore/tasks/handoff-phase.md): the UsageGuide with its smoke checklist and test users, the guides, the HTMLs, the status gate. The goal is met when the app is ready for the owner's UAT." ;;
  esac
}

commit_phase() {   # $1 phase → prints "<sha> <pushed yes|no|off>"
  local sha="" pushed="off"
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
        if r.get("kind", "run") == "run" and r.get("app") in (None, app) and r.get("started"): runs.append(r)
except OSError: pass
voided = {(r.get("cmd"), r.get("started")) for r in runs if r.get("kind") == "run-void"}
def hm(s):
    s = int(s or 0); return f"{s // 3600} h {s % 3600 // 60:02d} min" if s >= 3600 else f"{s // 60} min {s % 60:02d} s"
NAMES = {"day1": "Day 1, stage 1 (BRD, Architecture, mockups)", "day1-2": "Day 1, stage 2 (checklist, documents)",
         "build": "Build and verify", "handoff": "Handoff (UsageGuide, UAT-ready)"}
out, tot = [], {"wall_s": 0, "work_s": 0, "tokens_in": 0, "tokens_out": 0, "tokens_cache_read": 0, "tokens_cache_write": 0, "runs": 0}
models = {}
# One row per phase, summing every attempt of it (a phase stopped "blocked" and resumed is run again; its
# first attempts' time and tokens are part of what the phase cost). A run record belongs to the attempt
# whose window holds its start, the window's first second included and its last excluded: a record that
# starts the second the previous phase ends belongs to the next one (the first proof run counted the
# build's 301,201 tokens under Day 1 stage 2).
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
    # A record's tokens are measured over its own window of the session, so a command chained inside
    # another (devguide inside handoff-phase) is counted twice if both are summed: a record lying wholly
    # inside another is dropped, and working time is the union of the windows, not their sum.
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
    row = {"phase": name, "title": NAMES.get(name, name), "status": p.get("status"), "attempts": len(ats),
           "started": ats[0].get("started"), "ended": p.get("ended"),
           "wall_s": int(sum((b - a).total_seconds() for a, b in wins)), "work_s": int(union),
           "tokens_in": sum(int(r.get("tokens_in") or 0) for r in rs), "tokens_out": sum(int(r.get("tokens_out") or 0) for r in rs),
           "tokens_cache_read": sum(int(r.get("tokens_cache_read") or 0) for r in rs),
           "tokens_cache_write": sum(int(r.get("tokens_cache_write") or 0) for r in rs),
           "runs": len(rs), "commands": sorted({r.get("cmd") for r in rs if r.get("cmd")}), "commit": p.get("commit"), "pushed": p.get("pushed")}
    for r in rs:
        for m, n in (r.get("model_tokens_out") or {r.get("model") or "unknown": r.get("tokens_out") or 0}).items():
            models[m] = models.get(m, 0) + int(n or 0)
    for k in tot: tot[k] += row[k]
    out.append(row)
done = [p for p in out if p["status"] == "done"]
ready = len(done) == 4
starts = [t(p["started"]) for p in out if t(p["started"])]; ends = [t(p["ended"]) for p in out if t(p["ended"])]
span = int((max(ends) - min(starts)).total_seconds()) if starts and ends else 0
rep = {"app": app, "harness": state.get("harness"), "model": state.get("model") or None, "tier": state.get("tier"),
       "started": state.get("started"), "status": "uat-ready" if ready else (out[-1]["status"] if out else "not-started"),
       "elapsed_s": span, "totals": tot, "tokens_out_by_model": models, "phases": out,
       "note": "elapsed_s is first phase start to last phase end, usage-limit waits included; work_s is the agent's own run time from its run records"}
json.dump(rep, open(os.path.join(root, "docs", "metrics", "develop-report.json"), "w"), indent=1)
L = [f"# {app} — Build Report", "", "| | |", "|---|---|",
     f"| What | {app}, developed end to end from docs/{app}-Brief.md by *develop-end-to-end |",
     f"| Result | {'Ready for UAT' if ready else 'Stopped at ' + (out[-1]['title'] if out else 'the start') + ' (' + rep['status'] + ')'} |",
     f"| Built in | {hm(span)} from start to finish, of which the agent worked {hm(tot['work_s'])} |",
     f"| Harness and model | {state.get('harness')}, {', '.join(sorted(models)) or state.get('model') or 'default'} |",
     f"| Tokens | {tot['tokens_in']:,} in, {tot['tokens_out']:,} out, {tot['tokens_cache_read']:,} read from cache, {tot['tokens_cache_write']:,} written to cache |",
     "", "## Phases", "", "| Phase | Result | Time | Agent working | Tokens out | Commit |", "|---|---|---|---|---|---|"]
for p in out:
    L.append(f"| {p['title']}{' (' + str(p['attempts']) + ' attempts)' if p['attempts'] > 1 else ''} | {p['status']} | {hm(p['wall_s'])} | {hm(p['work_s'])} | {p['tokens_out']:,} | {p['commit'] or '—'}{'' if p['pushed'] in ('yes', 'off') else ' (not pushed)'} |")
L += ["", "Time is the clock from the phase's start to its end, summed over its attempts, waits for a usage limit to reset included. "
      "Built in also counts the time between attempts, while a stopped run waited to be resumed. "
      "Agent working is the sum of the phase's run records. The same figures, for a comparison harness, are in "
      "`docs/metrics/develop-report.json`.", ""]
open(os.path.join(root, "docs", f"{app}-Build-Report.md"), "w", encoding="utf-8").write("\n".join(L))
print(f"report: {rep['status']}, {hm(span)} elapsed, {tot['tokens_out']:,} tokens out — docs/{app}-Build-Report.md")
PY
}

# No --model: the tier's routed model (.tfcore/routing.yaml), never the machine's own default. The proof
# run on OpenCode fell back to a local model server that was not running and failed every cycle.
if [[ -z "$MODEL" && -f "$DIR/.tfcore/utils/tf-model-pick.sh" ]]; then
  MODEL="$(cd "$DIR" && bash .tfcore/utils/tf-model-pick.sh pick "$TIER" "$HARNESS" 2>/dev/null)"
  [[ "$MODEL" == inherit ]] && MODEL=""
fi
# --report: write the report again from the saved state (the run's, or the finished run's), nothing else
if [[ $REPORT_ONLY -eq 1 ]]; then
  [[ -f "$STATE" ]] || STATE="$DIR/.tfcore/.session/develop-done.json"
  [[ -f "$STATE" ]] || { echo "tf-develop: --report: no develop run recorded here" >&2; exit 2; }
  report; exit 0
fi
GOAL_ARGS=(--harness "$HARNESS" --tier "$TIER"); [[ -n "$MODEL" ]] && GOAL_ARGS+=(--model "$MODEL")
for phase in day1 day1-2 build handoff; do
  if [[ $DRY -eq 1 ]]; then echo "$phase: bash $GOAL_SH ${GOAL_ARGS[*]} $DIR \"$(goal_of "$phase" | cut -c1-90)…\"; then commit$([[ $PUSH -eq 1 ]] && echo ' and push')"; continue; fi
  [[ -n "$(st done "$phase")" ]] && { log "$phase already done — skipped"; continue; }
  start="$(ts)"; log "$phase started"; attempt=$(( $(st attempts "$phase") + 1 ))
  st phase "$phase" running "$start" "" "" "" "" "$attempt"
  bash "$GOAL_SH" "${GOAL_ARGS[@]}" "$DIR" "$(goal_of "$phase")"; rc=$?
  status=done; [[ $rc -eq 3 ]] && status=blocked; [[ $rc -ne 0 && $rc -ne 3 ]] && status="failed (exit $rc)"
  end="$(ts)"
  st phase "$phase" "$status" "$start" "$end" "$rc" "" "" "$attempt"
  report >/dev/null                                    # the phase's figures go into its own commit
  read -r sha pushed <<<"$(commit_phase "$phase")"
  st phase "$phase" "$status" "$start" "$end" "$rc" "$sha" "$pushed" "$attempt"
  log "$phase $status — commit $sha, pushed $pushed"
  if [[ $rc -ne 0 ]]; then report; commit_phase "report" >/dev/null; exit "$rc"; fi
done
[[ $DRY -eq 1 ]] && exit 0
report; read -r sha pushed <<<"$(commit_phase "build report")"
log "UAT-ready — final report commit $sha, pushed $pushed"
mv -f "$STATE" "$DIR/.tfcore/.session/develop-done.json"   # develop mode ends with the run
exit 0

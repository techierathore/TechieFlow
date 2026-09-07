#!/usr/bin/env bash
# tf-verify-emit.sh — the telemetry of a verify run, from its verdict file (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-emit.sh <App> [--dir tests/.artifacts/verify] [--mode <mode>] [--started <ISO>]
#
# Reads <dir>/verdicts.json (written by tf-verify-verdict.sh) and appends, through tf-emit.sh only:
#   gates.jsonl   one record per row that passed or failed a check: the first failing check (or null),
#                 the checks that ran, the failure class, the prior status, the attempt number
#   misses.jsonl  one `miss` per failing row that has no open miss of the same class (the duplicate
#                 check is tf-emit.sh --open-miss); origin = the last build or fix run that touched
#                 the row, looked up in runs.jsonl, or left out when there is none
#   runs.jsonl    one `run` record for the verify pass: cmd verify-phase, the rows touched, the build
#                 result, whether YOLO was on
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
    --mode) MODE="${2:-}"; shift 2 ;;
    --started) STARTED="${2:-}"; shift 2 ;;
    *) echo "tf-verify-emit: unknown argument $1" >&2; exit 3 ;;
  esac
done
[[ -f "$DIR/verdicts.json" ]] || { echo "tf-verify-emit: $DIR/verdicts.json missing; run tf-verify-verdict.sh first" >&2; exit 2; }
YOLO=false; bash "$HERE/tf-yolo.sh" is-on >/dev/null 2>&1 && YOLO=true
[[ -z "$STARTED" ]] && STARTED="$(bash "$HERE/tf-phase.sh" show 2>/dev/null | sed -n 's/.*"started":"\([^"]*\)".*/\1/p')"

TF_APP="$APP" TF_DIR="$DIR" TF_MODE="$MODE" TF_STARTED="$STARTED" TF_YOLO="$YOLO" TF_EMIT="$HERE/tf-emit.sh" python3 - <<'PY'
import datetime, json, os, subprocess

EMIT = os.environ["TF_EMIT"]; app = os.environ["TF_APP"]; d = os.environ["TF_DIR"]
mode = os.environ["TF_MODE"] or None; started = os.environ["TF_STARTED"]; yolo = os.environ["TF_YOLO"] == "true"
v = json.load(open(os.path.join(d, "verdicts.json"), encoding="utf-8"))
run_id = started or v.get("started") or ""
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def emit(stream, rec):
    p = subprocess.run(["bash", EMIT, stream], input=json.dumps(rec), capture_output=True, text=True)
    msg = (p.stdout + p.stderr).strip()
    if p.returncode != 0 or "refus" in msg.lower() or "error" in msg.lower():
        print(f"  {stream}: not written — {msg.splitlines()[0][:160] if msg else 'no reason printed'}")
        return False
    return True

def q(*args):
    p = subprocess.run(["bash", EMIT, *args], capture_output=True, text=True)
    return p.stdout.strip()

# origin lookup: the last build-phase or fix-issues run that touched the row
runs_path = os.path.join(q("--where") or "docs/metrics", "runs.jsonl")
origin = {}
if os.path.isfile(runs_path):
    for line in open(runs_path, encoding="utf-8", errors="replace"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("kind") != "run" or r.get("backfilled") or r.get("cmd") not in ("build-phase", "fix-issues"):
            continue
        for rid in r.get("reqs_touched") or []:
            if r.get("started", "") >= origin.get(rid, ("", ""))[0]:
                origin[rid] = (r.get("started", ""), r.get("cmd"), (r.get("subagents") or ["flow-master"])[0] if r.get("subagents") else "flow-master")

gates = misses = 0
for row in v["rows"]:
    if not row.get("emit_gate"):
        continue
    rid = row["id"]
    att = q("--next-attempt", rid) or "1"
    rec = {"kind": "gate", "app": app, "run_id": run_id, "req_id": rid, "req_class": row["class"],
           "attempt": int(att) if att.isdigit() else 1, "verdict": row["status"], "gate": row["gate"],
           "gates_run": row["gates_run"], "failure_class": row["failure_class"], "prior_verdict": row["prior_verdict"]}
    if emit("gates", rec):
        gates += 1
    if not row["gate"]:
        continue
    cls = ("regression" if (row["prior_verdict"] or "").lower().startswith("verified")
           else "standards-violation" if row["gate"] == "standards"
           else "partial-implementation")
    opened = q("--open-miss", rid)
    if opened and opened.split()[-1] == cls:
        continue
    mid = q("--next-miss-id")
    if not mid:
        print(f"  misses: no id for {rid}; skipped")
        continue
    m = {"kind": "miss", "miss_id": mid, "req_id": rid, "req_class": row["class"], "miss_class": cls,
         "artifact": "src", "severity": "major", "origin_phase": "build-phase", "origin_agent": "flow-master",
         "found_by": "gate", "found_phase": "verify-phase", "found_gate": row["gate"], "found_run_id": run_id,
         "failure_class": row["failure_class"] or "other"}
    if rid in origin:
        m["origin_run_id"], m["origin_phase"], m["origin_agent"] = origin[rid]
    if emit("misses", m):
        misses += 1

touched = [r["id"] for r in v["rows"] if r.get("emit_gate")]
rec = {"kind": "run", "app": app, "cmd": "verify-phase", "mode": mode, "yolo": yolo, "ended": now,
       "reqs_touched": touched, "reqs_count": len(touched), "subagents": [], "files_written": 2,
       "build_result": v.get("build_result", "not-run")}
if run_id:
    rec["started"] = run_id
ok = emit("runs", rec)
print(f"telemetry: {gates} gate record(s), {misses} new miss(es), run record {'written' if ok else 'not written'} (cmd verify-phase, yolo {str(yolo).lower()})")
PY
exit 0

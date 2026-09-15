#!/usr/bin/env bash
# tf-fix-close.sh — the telemetry a fix owes when it lands (Sitting 4c, 2026-09-06; D-15).
#
#   bash .tfcore/utils/tf-fix-close.sh <App> [--started <ISO>] [--reqs REQ-UI-009,REQ-FN-014]
#                                            [--subagents trblazeui,builder] [--build pass|fail|not-run] [--files N]
#   bash .tfcore/utils/tf-fix-close.sh <App> --misses MISS-App-20260901-06,MISS-App-20260830-03 \
#                                            --fix-cmd amend-docs [--verdict Verified]
#
# The second form closes misses DIRECTLY, by id, with no checklist row and no verify ledger.
# It exists because a miss whose deficient artifact is a document is fixed by *amend-docs
# editing the BRD -- never by the verifier touching a row -- so the row-driven form above can
# never reach it, and the miss stayed open forever (TF-016). It writes NO run record: the
# amending command emits its own through the status gate. `fix_cmd: "amend-docs"` was already
# legal in SCHEMA §5.5.2; only this door was missing.
#
# Emits, in this order, through tf-emit.sh only:
#   1. the fix-issues run record (cmd fix-issues, mode fix, the rows touched) — first, because the
#      miss-fix records below carry no numbers of their own: the emitter copies this run's token window.
#      A run the fix chained (the inline verify) keeps its own record, so the fix is recorded in the gaps
#      around it; the first gap carries the rows and the fix's start (TF-052).
#   2. one miss-fix per row that has an open miss, with verdict_after taken from every verify the fix
#      chained: the gate records written since the fix started, then the ledger docs/.last-verify.json
#      when it belongs to this fix (PASS → Verified; FAIL → FAIL; any other failing verdict → Needs
#      re-verify). A row no verify graded gets no miss-fix and is listed. A row with no open miss is listed,
#      not invented: a fix on a defect nobody logged is a triage gap, so open it first with tf-triage.sh
#      demote or tf-log-miss.sh, then re-run this.
# --reqs defaults to every row those verifies graded. The start defaults to the fix's marker, or its
# "outer" entry when a chained verify replaced it. Telemetry never blocks: refusals are printed, exit 0.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -ge 1 && "$1" != "-h" && "$1" != "--help" ]] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 3; }
APP="$1"; shift
STARTED=""; REQS=""; SUBS=""; BUILD="pass"; FILES=""; MISSES=""; FIXCMD="fix-issues"; VERDICT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --started) STARTED="${2:-}"; shift 2 ;;
    --reqs) REQS="${2:-}"; shift 2 ;;
    --subagents) SUBS="${2:-}"; shift 2 ;;
    --build) BUILD="${2:-}"; shift 2 ;;
    --files) FILES="${2:-}"; shift 2 ;;
    --misses) MISSES="${2:-}"; shift 2 ;;
    --fix-cmd) FIXCMD="${2:-}"; shift 2 ;;
    --verdict) VERDICT="${2:-}"; shift 2 ;;
    *) echo "tf-fix-close: unknown argument $1" >&2; exit 3 ;;
  esac
done
# the fix's start: its own marker, or the "outer" one when a verify it chained has replaced the marker
[[ -z "$STARTED" ]] && STARTED="$(bash "$HERE/tf-phase.sh" show 2>/dev/null | python3 -c "import json,sys
try: m=json.load(sys.stdin)
except Exception: m={}
o=m.get('outer') or {}
print(m.get('started','') if m.get('cmd')!='verify-phase' or not o.get('started') else o['started'])" 2>/dev/null)"
TF_APP="$APP" TF_STARTED="$STARTED" TF_REQS="$REQS" TF_SUBS="$SUBS" TF_BUILD="$BUILD" TF_FILES="$FILES" \
TF_MISSES="$MISSES" TF_FIXCMD="$FIXCMD" TF_VERDICT="$VERDICT" TF_EMIT="$HERE/tf-emit.sh" python3 - <<'PY'
import datetime, json, os, subprocess
EMIT = os.environ["TF_EMIT"]; app = os.environ["TF_APP"]; started = os.environ["TF_STARTED"]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
def q(*a): return subprocess.run(["bash", EMIT, *a], capture_output=True, text=True).stdout.strip()
def emit(stream, rec):
    p = subprocess.run(["bash", EMIT, stream], input=json.dumps(rec), capture_output=True, text=True)
    msg = (p.stdout + p.stderr).strip(); ok = p.returncode == 0 and "refus" not in msg.lower() and "error" not in msg.lower()
    if not ok: print(f"  {stream}: not written — {msg.splitlines()[0][:160] if msg else 'no reason printed'}")
    return ok
# --- close by miss id (the *amend-docs door) -------------------------------------------
direct = [m.strip() for m in (os.environ.get("TF_MISSES") or "").split(",") if m.strip()]
if direct:
    fix_cmd = os.environ.get("TF_FIXCMD") or "amend-docs"
    verdict = os.environ.get("TF_VERDICT") or "Verified"
    closed = 0
    for mid in direct:
        fa = q("--next-fix-attempt", mid) or "1"
        rec = {"kind": "miss-fix", "miss_id": mid, "fix_cmd": fix_cmd,
               "fix_attempt": int(fa) if fa.isdigit() else 1,
               "verdict_after": verdict, "reopened": False}
        if started:
            rec["fix_run_id"] = started
        if emit("misses", rec):
            closed += 1
    print("%s: %d of %d miss-fix record(s) written (no run record — the amending command emits its own)"
          % (fix_cmd, closed, len(direct)))
    raise SystemExit(0)

met = q("--where") or "docs/metrics"
def jsonl(name):
    try:
        for line in open(os.path.join(met, name), encoding="utf-8", errors="replace"):
            try: yield json.loads(line)
            except Exception: pass
    except OSError:
        return
# The verdicts: every verify this fix chained, not only the last. docs/.last-verify.json holds one scoped
# verify, so a fix that verified a Phase 3 scope and then a --phase 1 scope read the Phase 3 rows as absent
# and wrote Needs re-verify on their misses (TF-052). The gate records each verify wrote since the fix
# started come first; the ledger fills in only when it belongs to this fix.
rows = {}   # rid -> checklist status
if started:
    for g in jsonl("gates.jsonl"):
        if g.get("kind") == "gate" and g.get("app") in (None, app) and not g.get("backfilled") and g.get("gate") != "escaped" \
                and (g.get("run_id") or "") >= started and g.get("req_id"):
            rows[g["req_id"].upper()] = g.get("verdict")
ledger = {}
try:
    ledger = json.load(open(os.path.join("docs", ".last-verify.json"), encoding="utf-8"))
except Exception:
    pass
if not started or not ledger.get("run_id") or ledger["run_id"] >= started:
    for rid, v in (ledger.get("rows") or {}).items():
        # verdict_after takes a checklist status (SCHEMA §5.5): the ledger's verdict is mapped, never passed raw
        # (MISS-TechieFlow-20260906-25: RENDER-FAIL was refused and twenty miss-fix records never landed)
        rows.setdefault(rid.upper(), "Verified" if v == "PASS" else "FAIL" if v in ("FAIL", "BUILD-FAIL") else "Needs re-verify")
reqs = [r.strip().upper() for r in os.environ["TF_REQS"].split(",") if r.strip()] or sorted(rows)
subs = [s.strip() for s in os.environ["TF_SUBS"].split(",") if s.strip()]
files = os.environ["TF_FILES"]
# The fix's own time only: a run it chained (the inline verify) has its own record, so the fix is recorded
# in the gaps around it, the first gap keyed on the fix's start with the rows (its miss-fixes name that start).
inner, voided = [], set()
for r in jsonl("runs.jsonl"):
    if r.get("kind") == "run-void":
        voided.add((r.get("cmd"), r.get("started")))
    elif r.get("kind", "run") == "run" and r.get("app") == app and r.get("cmd") != "fix-issues" and not r.get("backfilled") \
            and started and (r.get("started") or "") >= started and (r.get("ended") or "") and r["ended"] <= now:
        inner.append((r["started"], r["ended"], r.get("cmd")))
inner = sorted(w for w in inner if (w[2], w[0]) not in voided)
gaps, t = [], started
for s, e, _c in inner:
    if t and s > t: gaps.append((t, s))
    t = max(t, e) if t else e
if not started or not gaps or t < now: gaps.append((t, now))
existing = {r.get("started") for r in jsonl("runs.jsonl") if r.get("kind", "run") == "run" and r.get("cmd") == "fix-issues"}
wrote = had = 0
for i, (s, e) in enumerate(gaps):
    first = i == 0
    run = {"kind": "run", "app": app, "cmd": "fix-issues", "mode": "fix", "ended": e, "reqs_touched": reqs if first else [],
           "reqs_count": len(reqs) if first else 0, "subagents": subs if first else [],
           "files_written": (int(files) if files.isdigit() else len(reqs)) if first else 0, "build_result": os.environ["TF_BUILD"]}
    if s: run["started"] = s
    # one run record per start: a close called twice must not count the fix twice
    if s and s in existing:
        had += 1; continue
    wrote += emit("runs", run)
if inner:
    print(f"fix-issues: recorded around {len(inner)} chained run(s) ({', '.join(sorted({c for _s, _e, c in inner}))}) in {len(gaps)} segment(s)")
closed, none, unverified = 0, [], []
for rid in reqs:
    if rid not in rows:
        unverified.append(rid); continue
    opened = q("--open-miss", rid)
    if not opened:
        none.append(rid); continue
    mid = opened.split()[0]
    fa = q("--next-fix-attempt", mid) or "1"
    rec = {"kind": "miss-fix", "miss_id": mid, "req_id": rid, "fix_cmd": "fix-issues", "fix_attempt": int(fa) if fa.isdigit() else 1,
           "verdict_after": rows[rid], "reopened": False}
    if started: rec["fix_run_id"] = started
    if emit("misses", rec): closed += 1
state = "already there" if had == len(gaps) else "written" if wrote + had == len(gaps) else "not written"
print(f"fix-issues: run record {state}; {closed} miss-fix record(s) with the verifier's verdict"
      + (f"; no open miss on {', '.join(none)} (log it first, then re-run)" if none else "")
      + (f"; no verify graded {', '.join(unverified)} during this fix, so its miss stays open with no miss-fix" if unverified else ""))
PY
exit 0

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
#      miss-fix records below carry no numbers of their own: the emitter copies this run's token window
#   2. one miss-fix per row that has an open miss, with verdict_after taken from the verify ledger
#      docs/.last-verify.json written by the verify the fix chained, mapped to a checklist status (PASS →
#      Verified; FAIL → FAIL; any other failing verdict or an absent row → Needs re-verify). A row with no open miss is listed,
#      not invented: a fix on a defect nobody logged is a triage gap, so open it first with tf-triage.sh
#      demote or tf-log-miss.sh, then re-run this.
# --reqs defaults to every row in the ledger. Telemetry never blocks: refusals are printed, exit 0.
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
[[ -z "$STARTED" ]] && STARTED="$(bash "$HERE/tf-phase.sh" show 2>/dev/null | sed -n 's/.*"started":"\([^"]*\)".*/\1/p')"
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

ledger = {}
try:
    ledger = json.load(open(os.path.join("docs", ".last-verify.json"), encoding="utf-8"))
except Exception:
    pass
rows = ledger.get("rows") or {}
reqs = [r.strip().upper() for r in os.environ["TF_REQS"].split(",") if r.strip()] or sorted(rows)
subs = [s.strip() for s in os.environ["TF_SUBS"].split(",") if s.strip()]
files = os.environ["TF_FILES"]
run = {"kind": "run", "app": app, "cmd": "fix-issues", "mode": "fix", "ended": now, "reqs_touched": reqs, "reqs_count": len(reqs),
       "subagents": subs, "files_written": int(files) if files.isdigit() else len(reqs), "build_result": os.environ["TF_BUILD"]}
if started: run["started"] = started
# one run record per start: a close called twice must not count the fix twice
runs_path = os.path.join(q("--where") or "docs/metrics", "runs.jsonl")
already = False
if started and os.path.isfile(runs_path):
    for line in open(runs_path, encoding="utf-8", errors="replace"):
        if '"cmd":"fix-issues"' in line and f'"started":"{started}"' in line:
            already = True
            break
ok = True if already else emit("runs", run)
if already:
    print(f"fix-issues: run record for start {started} already exists; not written again")
closed, none = 0, []
for rid in reqs:
    opened = q("--open-miss", rid)
    if not opened:
        none.append(rid); continue
    mid = opened.split()[0]
    fa = q("--next-fix-attempt", mid) or "1"
    v = rows.get(rid)
    # verdict_after takes a checklist status (SCHEMA §5.5): the ledger's verdict is mapped, never passed raw
    # (MISS-TechieFlow-20260906-25: RENDER-FAIL was refused and twenty miss-fix records never landed)
    after = ("Verified" if v == "PASS" else "FAIL" if v in ("FAIL", "BUILD-FAIL") else "Needs re-verify")
    rec = {"kind": "miss-fix", "miss_id": mid, "req_id": rid, "fix_cmd": "fix-issues", "fix_attempt": int(fa) if fa.isdigit() else 1,
           "verdict_after": after, "reopened": False}
    if started: rec["fix_run_id"] = started
    if emit("misses", rec): closed += 1
print(f"fix-issues: run record {'already there' if already else 'written' if ok else 'not written'}; {closed} miss-fix record(s) with the verifier's verdict"
      + (f"; no open miss on {', '.join(none)} (log it first, then re-run)" if none else ""))
PY
exit 0

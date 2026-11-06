#!/usr/bin/env bash
# tf-fix-close.sh — the telemetry a fix owes when it lands (Sitting 4c, 2026-09-06; D-15).
#
#   bash .tfcore/utils/tf-fix-close.sh <App> [--started <ISO>] [--reqs REQ-UI-009,REQ-FN-014]
#                                            [--subagents trblazeui,builder] [--build pass|fail|not-run] [--files N]
#                                            [--cmd triage-and-fix]   # the command the run record is filed under
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
# --cmd names the command the run record is filed under (default fix-issues): *triage-and-fix passes
# --cmd triage-and-fix, so its run is counted as itself and no second record over the same window is
# needed, which the overlap rule refused (TrBlazeUI TF-004). The miss-fix records carry fix_cmd triage-and-fix
# then, fix-issues otherwise (Lekhak TF-039: triage-and-fix was not in the vocabulary, so --misses refused it).
# A close called again after a later verify (the first verify said Needs re-verify, the re-verify PASS):
#   - the windows a close of this command already recorded are skipped, so no second run record overlaps;
#   - a row whose open miss already has a miss-fix gets a new one when a verify graded it after that record
#     (a newer gate record) and the verdict changed, even when this close's start is after that verify (Lekhak TF-039). The same
#     verdict again writes nothing, so a close run twice counts each fix once.
# --reqs defaults to every row those verifies graded. The start defaults to the fix's marker, or its
# "outer" entry when a chained verify replaced it. Telemetry never blocks: refusals are printed, exit 0.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -ge 1 && "$1" != "-h" && "$1" != "--help" ]] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 3; }
APP="$1"; shift
STARTED=""; REQS=""; SUBS=""; BUILD="pass"; FILES=""; MISSES=""; FIXCMD="fix-issues"; VERDICT=""; RUNCMD="fix-issues"
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
    --cmd) RUNCMD="${2:-}"; shift 2 ;;
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
TF_MISSES="$MISSES" TF_FIXCMD="$FIXCMD" TF_RUNCMD="$RUNCMD" TF_VERDICT="$VERDICT" TF_EMIT="$HERE/tf-emit.sh" python3 - <<'PY'
import datetime, json, os, subprocess
EMIT = os.environ["TF_EMIT"]; app = os.environ["TF_APP"]; started = os.environ["TF_STARTED"]
cmd = os.environ.get("TF_RUNCMD") or "fix-issues"
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
    row_runs = ledger.get("row_runs")   # a ledger kept row by row also holds older runs' rows (Lekhak TF-007)
    for rid, v in (ledger.get("rows") or {}).items():
        if started and isinstance(row_runs, dict) and rid not in (ledger.get("this_run") or []) \
                and (row_runs.get(rid) or "") < started:
            continue
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
    elif r.get("kind", "run") == "run" and r.get("app") == app and not r.get("backfilled") \
            and started and (r.get("started") or "") >= started and (r.get("ended") or "") and r["ended"] <= now \
            and (r.get("cmd") not in ("fix-issues", cmd) or (r.get("started") or "") > started):
        # a later window this command already recorded (an earlier close of the same fix) is skipped like a chained run
        inner.append((r["started"], r["ended"], r.get("cmd")))
inner = sorted(w for w in inner if (w[2], w[0]) not in voided)
gaps, t = [], started
for s, e, _c in inner:
    if t and s > t: gaps.append((t, s))
    t = max(t, e) if t else e
if not started or not gaps or t < now: gaps.append((t, now))
existing = {r.get("started") for r in jsonl("runs.jsonl") if r.get("kind", "run") == "run" and r.get("cmd") == cmd}
wrote = had = 0
for i, (s, e) in enumerate(gaps):
    first = i == 0
    run = {"kind": "run", "app": app, "cmd": cmd, "mode": "fix", "ended": e, "reqs_touched": reqs if first else [],
           "reqs_count": len(reqs) if first else 0, "subagents": subs if first else [],
           "files_written": (int(files) if files.isdigit() else len(reqs)) if first else 0, "build_result": os.environ["TF_BUILD"]}
    if s: run["started"] = s
    # one run record per start: a close called twice must not count the fix twice
    if s and s in existing:
        had += 1; continue
    wrote += emit("runs", run)
chained = [w for w in inner if w[2] != cmd]
if chained:
    print(f"{cmd}: recorded around {len(chained)} chained run(s) ({', '.join(sorted({c for _s, _e, c in chained}))}) in {len(gaps)} segment(s)")
fix_cmd = "triage-and-fix" if cmd == "triage-and-fix" else "fix-issues"
last_fix, misses_on, void = {}, {}, set()   # miss_id -> latest miss-fix; row -> its misses
for m in jsonl("misses.jsonl"):
    k = m.get("kind")
    if k == "miss-fix" and m.get("miss_id"):
        p = last_fix.get(m["miss_id"])
        if p is None or (m.get("ts") or "") >= (p.get("ts") or ""):
            last_fix[m["miss_id"]] = m
    elif k == "miss-void":
        void.add(m.get("miss_id"))
    elif k == "miss" and m.get("req_id") and m.get("app") in (None, app):
        misses_on.setdefault(m["req_id"].upper(), []).append(m)
def open_on(rid):
    """every open miss on the row (tf-emit.sh --open-miss gives only the newest): a row can hold two, a
    wrong-behaviour the owner found and a partial-implementation a later gate opened (Lekhak REQ-UI-154)"""
    return [m for m in misses_on.get(rid, []) if m.get("miss_id") not in void
            and (last_fix.get(m.get("miss_id")) or {}).get("verdict_after") not in ("Verified", "wont-fix")]
# the latest verdict a verify wrote for each row, with WHEN it was written (the record's ts): a verify chained
# by a fix carries the fix's start as its run_id, so run_id cannot say whether it graded after a miss-fix
latest_gate = {}
for g in jsonl("gates.jsonl"):
    if g.get("kind") == "gate" and g.get("app") in (None, app) and not g.get("backfilled") and g.get("gate") != "escaped" and g.get("req_id"):
        k = g["req_id"].upper()
        if (g.get("ts") or "") >= (latest_gate.get(k, {}).get("ts") or ""):
            latest_gate[k] = g
def write_fix(m, rid, verdict, run_id):
    fa = q("--next-fix-attempt", m["miss_id"]) or "1"
    rec = {"kind": "miss-fix", "miss_id": m["miss_id"], "req_id": rid, "fix_cmd": fix_cmd, "fix_attempt": int(fa) if fa.isdigit() else 1,
           "verdict_after": verdict, "reopened": False}
    if run_id: rec["fix_run_id"] = run_id
    return emit("misses", rec)
closed, followed, none, unverified = 0, 0, [], []
for rid in reqs:
    if rid not in rows:
        unverified.append(rid); continue
    mine = open_on(rid)
    if not mine:
        none.append(rid); continue
    for m in mine:
        prev = last_fix.get(m["miss_id"])
        if prev and prev.get("verdict_after") == rows[rid] and started and prev.get("fix_run_id") == started:
            continue    # this close already wrote this verdict for this fix
        closed += write_fix(m, rid, rows[rid], started)
# Lekhak TF-039: the follow-up. A fix's first verify said Needs re-verify, its miss-fix said so, and a later
# verify passed the row. A close started after that verify has no row in its window, so the miss stayed open
# although the row is Verified. The rows of the last run of this command before this close (the fix it
# follows up) get a miss-fix, filed under that run, for each open miss a verify graded after the miss's own
# record or its latest miss-fix (a newer gate record) with a different verdict. Rows of older fixes are left
# alone: their misses are closed by the next fix of those rows.
fu = None
if started:
    for r in jsonl("runs.jsonl"):
        if r.get("kind", "run") == "run" and r.get("app") == app and r.get("cmd") == cmd and r.get("reqs_touched") \
                and (r.get("started") or "") < started and (r.get("cmd"), r.get("started")) not in voided \
                and (fu is None or r["started"] > fu["started"]):
            fu = r
for rid in sorted({x.upper() for x in (fu or {}).get("reqs_touched") or []} - set(reqs)):
    g = latest_gate.get(rid)
    if not g or not g.get("verdict"):
        continue
    for m in open_on(rid):
        prev = last_fix.get(m["miss_id"])
        ref = (prev or m).get("ts") or ""
        if (g.get("ts") or "") <= ref or (prev and prev.get("verdict_after") == g["verdict"]):
            continue
        if write_fix(m, rid, g["verdict"], fu["started"]):
            closed += 1; followed += 1
state = "already there" if had == len(gaps) else "written" if wrote + had == len(gaps) else "not written"
print(f"{cmd}: run record {state}; {closed} miss-fix record(s) with the verifier's verdict"
      + (f" ({followed} for a re-verify after the {cmd} of {fu['started']})" if followed else "")
      + (f"; no open miss on {', '.join(none)} (log it first, then re-run)" if none else "")
      + (f"; no verify graded {', '.join(unverified)} during this fix, so its miss stays open with no miss-fix" if unverified else ""))
PY
exit 0

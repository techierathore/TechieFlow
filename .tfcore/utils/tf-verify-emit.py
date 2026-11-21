#!/usr/bin/env python3
"""tf-verify-emit.py — the program behind tf-verify-emit.sh (read that file's header); run that, not this.

Its inputs come from the environment tf-verify-emit.sh sets: TF_APP, TF_DIR, TF_MODE, TF_STARTED, TF_YOLO, TF_EMIT.
Moved out of the shell file on 2026-11-14, when the verify's own start mark (Chatur) grew it past its size limit.
"""
import datetime, json, os, subprocess

EMIT = os.environ["TF_EMIT"]; app = os.environ["TF_APP"]; d = os.environ["TF_DIR"]
mode = os.environ["TF_MODE"] or None; started = os.environ["TF_STARTED"]; yolo = os.environ["TF_YOLO"] == "true"
v = json.load(open(os.path.join(d, "verdicts.json"), encoding="utf-8"))
run_id = started or v.get("started") or ""
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# A verify chained inside another command is handed that command's start as "the step-0 time", and
# its record then covered the caller's whole window, so the caller's own record was refused (TF-052).
# This run's start is its own marker's; with no verify-phase marker (step 0 skipped), when the list
# was written.
mk = {}
try:
    pj = os.path.join(".tfcore", ".session", "phase.json")
    if datetime.datetime.now().timestamp() - os.path.getmtime(pj) < 24 * 3600:
        mk = json.load(open(pj, encoding="utf-8")) or {}
except Exception:
    pass
own, caller = "", (mk.get("outer") or {}).get("cmd") or "an earlier command"
# Chatur, 14 Nov 2026: with no verify-phase mark the start was guessed from when list.json was last written,
# and three verifies were recorded as 5 to 8 seconds. tf-verify-list.sh now marks a verify that skipped step 0;
# a verify that still has no mark of its own gets no run record (its gates and misses are written).
unmarked = mk.get("cmd") != "verify-phase"
if not unmarked:
    own = mk.get("started") or ""
if own and run_id and own > run_id:
    print(f"tf-verify-emit: {run_id} is when {caller} started; this verify started {own} and is recorded from then")
    run_id = own

def q(*args):
    p = subprocess.run(["bash", EMIT, *args], capture_output=True, text=True)
    return p.stdout.strip()

runs_path = os.path.join(q("--where") or "docs/metrics", "runs.jsonl")
runs = []
if os.path.isfile(runs_path):
    for line in open(runs_path, encoding="utf-8", errors="replace"):
        try:
            runs.append(json.loads(line))
        except Exception:
            pass

# Sevak TF-005: *verify --phase all is one pass per phase inside one command, all handed the same
# step-0 time. A pass that finds a run of this app already recorded since that time starts where it
# ended, so the second pass is not refused as an overlap (SCHEMA §2.7b) and no window is counted twice.
if run_id:
    after = [r.get("ended", "") for r in runs if r.get("kind") == "run" and not r.get("backfilled")
             and r.get("app") in (None, app) and r.get("started", "") >= run_id and r.get("ended", "") > run_id]
    if after:
        print(f"tf-verify-emit: a run of {app} was recorded since {run_id}; this pass is recorded from its end, {max(after)}")
        run_id = max(after)
phase = v.get("phase")

def emit(stream, rec):
    p = subprocess.run(["bash", EMIT, stream], input=json.dumps(rec), capture_output=True, text=True)
    msg = (p.stdout + p.stderr).strip()
    if p.returncode != 0 or "refus" in msg.lower() or "error" in msg.lower():
        print(f"  {stream}: not written — {msg.splitlines()[0][:160] if msg else 'no reason printed'}")
        return False
    return True

# origin lookup: the last build-phase or fix-issues run that touched the row
origin = {}
for r in runs:
    if r.get("kind") != "run" or r.get("backfilled") or r.get("cmd") not in ("build-phase", "fix-issues"):
        continue
    for rid in r.get("reqs_touched") or []:
        if r.get("started", "") >= origin.get(rid, ("", ""))[0]:
            origin[rid] = (r.get("started", ""), r.get("cmd"), (r.get("subagents") or ["flow-master"])[0] if r.get("subagents") else "flow-master")

# the defects this pass will open a miss for (same tests as below), counted first for the discovery window
def _would_open(row):
    if not row.get("emit_gate") or not row["gate"] or row.get("verdict") == "NOT-MEASURED":
        return False
    c = ("regression" if (row["prior_verdict"] or "").lower().startswith("verified")
         else "standards-violation" if row["gate"] in ("standards", "test-users") else "partial-implementation")
    o = q("--open-miss", row["id"], c)
    return not (o and o.split()[-1] == c)
n_new = sum(1 for r in v["rows"] if _would_open(r))
gates = misses = 0
for row in v["rows"]:
    if not row.get("emit_gate") or row.get("verdict") == "NOT-MEASURED":
        continue
    rid = row["id"]
    att = q("--next-attempt", rid) or "1"
    rec = {"kind": "gate", "app": app, "run_id": run_id, "req_id": rid, "req_class": row["class"],
           "attempt": int(att) if att.isdigit() else 1, "verdict": row["status"], "gate": row["gate"],
           "gates_run": row["gates_run"], "failure_class": row["failure_class"], "prior_verdict": row["prior_verdict"]}
    if phase:
        rec["app_phase"] = phase
    if emit("gates", rec):
        gates += 1
    if not row["gate"]:
        continue
    cls = ("regression" if (row["prior_verdict"] or "").lower().startswith("verified")
           else "standards-violation" if row["gate"] in ("standards", "test-users")
           else "partial-implementation")
    opened = q("--open-miss", rid, cls)
    if opened and opened.split()[-1] == cls:
        continue
    mid = q("--next-miss-id")
    if not mid:
        print(f"  misses: no id for {rid}; skipped")
        continue
    m = {"kind": "miss", "miss_id": mid, "req_id": rid, "req_class": row["class"], "miss_class": cls,
         "artifact": "tests" if row["gate"] == "test-users" else "src", "severity": "major", "origin_phase": "build-phase", "origin_agent": "flow-master",
         "found_by": "gate", "found_phase": "verify-phase", "found_gate": row["gate"], "found_run_id": run_id,
         "failure_class": row["failure_class"] or "other"}
    if rid in origin:
        m["origin_run_id"], m["origin_phase"], m["origin_agent"] = origin[rid]
    # TechieBlog TF-004: one pass grades every row at once, so a defect has the pass's window as its own
    # only when it is the pass's one new defect; otherwise it is not measured (never an even share)
    if n_new == 1 and run_id:
        m["discovery_started"], m["discovery_ended"] = run_id, now
    else:
        m["discovery_why"] = f"one verify pass found {n_new} defects at once; its window is not any one of theirs"
    if emit("misses", m):
        misses += 1

touched = [r["id"] for r in v["rows"] if r.get("emit_gate")]
nm = [r["id"] for r in v["rows"] if r.get("verdict") == "NOT-MEASURED"]   # the sign-in failed (TfLens TF-061)
if nm:
    print(f"  not measured, the sign-in failed: {len(nm)} row(s) get no gate record and no miss ({', '.join(nm[:8])}{' …' if len(nm) > 8 else ''})")
rec = {"kind": "run", "app": app, "cmd": "verify-phase", "mode": mode, "yolo": yolo, "ended": now,
       "reqs_touched": touched, "reqs_count": len(touched), "subagents": [], "files_written": 2,
       "build_result": v.get("build_result", "not-run"), **json.loads(subprocess.run(["python3", os.path.join(os.path.dirname(EMIT), "tf-checks-model.py")], capture_output=True, text=True).stdout or "{}")}  # checks_provider/_model: Chatur TF-028
if run_id:
    rec["started"] = run_id
if phase:
    rec["app_phase"] = phase
if unmarked:
    ok = False
    print("  runs: not written — this verify has no start mark of its own (no tf-phase.sh start verify-phase, and tf-verify-list.sh "
          "was not run here), so its time stays in the command around it; a record of a few seconds would be wrong")
else:
    ok = emit("runs", rec)
    auto = os.path.join(".tfcore", ".session", "verify-auto")   # a mark tf-verify-list.sh set ends with its record
    if os.path.isfile(auto) and open(auto).read().strip() == mk.get("started"):
        subprocess.run(["bash", os.path.join(os.path.dirname(EMIT), "tf-phase.sh"), "end", "verify-phase"], capture_output=True)
        os.remove(auto)
print(f"telemetry: {gates} gate record(s), {misses} new miss(es), run record {'written' if ok else 'not written'} (cmd verify-phase, phase {phase or '?'}, yolo {str(yolo).lower()})")

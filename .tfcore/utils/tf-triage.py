#!/usr/bin/env python3
"""tf-triage.py — log reported bugs in the checklist and the telemetry (see tf-triage.sh).

    bash .tfcore/utils/tf-triage.sh <App> demote <REQ> "<symptom>" [--kind layout|render-empty|data-logic|rag]
                                     [--evidence <path>] [--source owner|production] [--why <why_missed>] [--sort <sort>]
    bash .tfcore/utils/tf-triage.sh <App> new "<title>" "<When … on <screen>, then …>" [--prefix UI|FN|NFR|RAG]
                                     [--section "<screen>"] [--evidence <path>] [--source owner|production] [--mockup <file>] [--sort <sort>]
    bash .tfcore/utils/tf-triage.sh <App> note <REQ> "<could not reproduce: what was tried>"
    bash .tfcore/utils/tf-triage.sh <App> close [--started <ISO>] [--verify-ran] [--cmd triage-issues|fix-issues]

demote  the row goes to Needs re-verify (% capped at 75) with a dated Remark holding the symptom in the
        reporter's words, the evidence path and the kind.
new     a defect no row covers: the next free id in the prefix, a Not Started row, a detail entry with the
        acceptance line and the marker BRD-pending (*amend-docs gives it its BRD item).
note    a dated remark on the nearest row, no status change (could not reproduce).
close   what triage owes the telemetry, from the actions above (tests/.artifacts/verify/triage.json):
        one gate record per demoted or new row with gate "escaped" (no check caught it), one miss per row
        with found_by owner or production, the symptom as `what` and the sort (FR-32; --sort on demote or
        new, else weak-check for a demoted row, whose line existed and whose check let it through, and
        spec for a new row, which the spec never had) (duplicates collapsed through
        tf-emit.sh --open-miss; the origin run looked up with --origin-of), then the run record. It also
        lists every file under src/, source/ or tests/ changed since the start: a triage that edited code
        is reported and logged as an instruction-ignored miss (FR-28).
Exit 0 · 2 could not run.
"""
import datetime
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOGP = os.path.join("tests", ".artifacts", "verify", "triage.json")
KIND_CLASS = {"layout": "overlap", "render-empty": "blank-data", "data-logic": "assert-fail", "rag": "other", None: "other"}
EMIT = os.path.join(HERE, "tf-emit.sh")


def die(m):
    print(f"tf-triage: {m}", file=sys.stderr)
    sys.exit(2)


def mod():
    spec = importlib.util.spec_from_file_location("tf_checklist_edit", os.path.join(HERE, "tf-checklist-edit.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def cfg_phase():
    p = os.path.join(".tfcore", "core-config.yaml")
    if os.path.isfile(p):
        import re
        m = re.search(r"(?m)^appPhase:\s*(\d+)", open(p, encoding="utf-8").read())
        if m:
            return int(m.group(1))
    return 1


def checklist(app):
    ph = cfg_phase()
    p = os.path.join("docs", f"{app}-Checklist.md" if ph <= 1 else f"{app}-P{ph}-Checklist.md")
    if not os.path.isfile(p):
        die(f"{p} does not exist")
    return p


def log_load():
    try:
        return json.load(open(LOGP, encoding="utf-8"))
    except Exception:
        return {"actions": []}


def log_save(d):
    os.makedirs(os.path.dirname(LOGP), exist_ok=True)
    json.dump(d, open(LOGP, "w", encoding="utf-8"), indent=1)


def opt(argv, name, default=None):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


SORTS = ("spec", "unsaid", "weak-check", "ignored")


def sort_opt(argv, default):
    s = opt(argv, "--sort", default)
    if s not in SORTS:
        die(f"--sort must be one of {', '.join(SORTS)}")
    return s


def q(*args):
    p = subprocess.run(["bash", EMIT, *args], capture_output=True, text=True)
    return p.stdout.strip()


def emit(stream, rec):
    p = subprocess.run(["bash", EMIT, stream], input=json.dumps(rec), capture_output=True, text=True)
    msg = (p.stdout + p.stderr).strip()
    ok = p.returncode == 0 and "refus" not in msg.lower() and "error" not in msg.lower()
    if not ok:
        print(f"  {stream}: not written — {msg.splitlines()[0][:160] if msg else 'no reason printed'}")
    return ok


def main(argv):
    if len(argv) < 3 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if len(argv) > 1 else 2
    app, verb = argv[1], argv[2]
    ce = mod()
    cl = checklist(app)
    log = log_load()
    log.setdefault("app", app)
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    if verb == "demote":
        if len(argv) < 5:
            die("demote needs <REQ> \"<symptom>\"")
        rid, symptom = argv[3].upper(), argv[4]
        kind = opt(argv, "--kind"); ev = opt(argv, "--evidence"); src = opt(argv, "--source", "owner")
        prior = ce.demote(cl, rid, symptom, kind=kind, evidence=ev, source=src, prefix="⚠ prod bug" if src == "production" else "⚠ UAT bug")
        if prior is None:
            die(f"{rid} is not a row of {cl}")
        log["actions"].append({"verb": "demote", "req_id": rid, "symptom": symptom, "kind": kind, "evidence": ev, "source": src,
                               "why": opt(argv, "--why", "insufficient-verify-method"), "sort": sort_opt(argv, "weak-check"),
                               "prior": prior["status"], "ts": now})
        log_save(log)
        print(f"{rid}: {prior['status']} → Needs re-verify — {symptom}")
        return 0

    if verb == "new":
        if len(argv) < 5:
            die("new needs \"<title>\" \"<acceptance>\"")
        title, acc = argv[3], argv[4]
        prefix = opt(argv, "--prefix", "FN").upper(); section = opt(argv, "--section"); ev = opt(argv, "--evidence")
        src = opt(argv, "--source", "owner"); mockup = opt(argv, "--mockup")
        if prefix == "UI" and not mockup:
            print("note: a UI row needs a mockup link; pass --mockup docs/mockups/<screen>.html or the checker will flag it")
        rid = ce.add_row(cl, prefix, title, acc, section=section, mockup=mockup,
                         remark=f"logged from {'production' if src == 'production' else 'UAT'} {ce.TODAY}" + (f" (evidence: {ev})" if ev else ""))
        log["actions"].append({"verb": "new", "req_id": rid, "symptom": title, "kind": None, "evidence": ev, "source": src,
                               "why": opt(argv, "--why", "missing-checklist-item"), "sort": sort_opt(argv, "spec"), "prior": None, "ts": now})
        log_save(log)
        print(f"{rid}: new Not Started row — {title}")
        return 0

    if verb == "note":
        if len(argv) < 5:
            die("note needs <REQ> \"<text>\"")
        rid = argv[3].upper()
        if ce.note(cl, rid, argv[4]) is None:
            die(f"{rid} is not a row of {cl}")
        log["actions"].append({"verb": "note", "req_id": rid, "symptom": argv[4], "ts": now})
        log_save(log)
        print(f"{rid}: noted — {argv[4]}")
        return 0

    if verb == "close":
        started = opt(argv, "--started") or subprocess.run(["bash", os.path.join(HERE, "tf-phase.sh"), "show"], capture_output=True, text=True).stdout
        if started.startswith("{"):
            import re
            m = re.search(r'"started":"([^"]*)"', started)
            started = m.group(1) if m else ""
        started = started.strip() if started and not started.startswith("none") else ""
        cmd = opt(argv, "--cmd", "triage-issues")
        # code untouched?
        changed = []
        if started:
            t0 = datetime.datetime.strptime(started, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
            for top in ("src", "source", "tests"):
                for d, dirs, files in os.walk(top):
                    dirs[:] = [x for x in dirs if x not in ("bin", "obj", "node_modules", ".artifacts", "TestResults")]
                    for f in files:
                        p = os.path.join(d, f)
                        try:
                            if os.path.getmtime(p) > t0:
                                changed.append(p.replace("\\", "/"))
                        except OSError:
                            pass
        acts = [a for a in log.get("actions", []) if a["verb"] in ("demote", "new")]
        gates = misses = 0
        for a in acts:
            rid = a["req_id"]; cls_req = rid.split("-")[1]
            att = q("--next-attempt", rid) or "1"
            fc = KIND_CLASS.get(a.get("kind"), "other")
            rec = {"kind": "gate", "app": app, "run_id": started, "req_id": rid, "req_class": cls_req,
                   "attempt": int(att) if att.isdigit() else 1, "verdict": "Needs re-verify" if a["verb"] == "demote" else "FAIL",
                   "gate": "escaped", "gates_run": [], "failure_class": fc, "prior_verdict": a.get("prior")}
            if emit("gates", rec):
                gates += 1
            mc = ("unspecified-gap" if a["verb"] == "new" else "regression" if (a.get("prior") or "").lower().startswith("verified") else "wrong-behaviour")
            opened = q("--open-miss", rid)
            if opened and opened.split()[-1] == mc:
                print(f"  {rid}: already open as {opened.split()[0]} ({mc}); no second miss")
                continue
            mid = q("--next-miss-id")
            m = {"kind": "miss", "miss_id": mid, "req_id": rid, "req_class": cls_req, "miss_class": mc,
                 "artifact": "brd" if a["verb"] == "new" else "src", "severity": "major", "why_missed": a.get("why"),
                 "origin_phase": "day1-greenfield" if a["verb"] == "new" else "build-phase", "origin_agent": "analyst" if a["verb"] == "new" else "flow-master",
                 "found_by": a.get("source", "owner"), "found_phase": cmd, "found_gate": None, "found_run_id": started,
                 "failure_class": fc, "what": a["symptom"][:300], "sort": a.get("sort") or ("spec" if a["verb"] == "new" else "weak-check")}
            if a["verb"] != "new":
                o = q("--origin-of", rid).split()
                if len(o) >= 3:
                    m["origin_run_id"], m["origin_phase"], m["origin_agent"] = o[0], o[1], o[2]
            if emit("misses", m):
                misses += 1
                a["miss_id"] = mid
        if changed and cmd == "triage-issues" and not log.get("code_miss_id"):
            mid = q("--next-miss-id")
            log["code_miss_id"] = mid
            emit("misses", {"kind": "miss", "miss_id": mid, "req_id": None, "req_class": None, "miss_class": "other", "artifact": "src",
                            "severity": "major", "why_missed": "instruction-ignored", "origin_phase": "triage-issues", "origin_agent": "flow-master",
                            "found_by": "gate", "found_phase": "triage-issues", "found_gate": None, "found_run_id": started, "failure_class": "other",
                            "what": f"triage edited {len(changed)} file(s) under src, source or tests, which a triage never does: " + ", ".join(changed[:5]),
                            "sort": "ignored"})
            print(f"WARNING: {len(changed)} file(s) changed under src/, source/ or tests/ during this triage (logged as {mid}): " + ", ".join(changed[:5]))
        if cmd == "triage-issues":
            rec = {"kind": "run", "app": app, "cmd": "triage-issues", "mode": None, "ended": now, "reqs_touched": [a["req_id"] for a in acts],
                   "reqs_count": len(acts), "subagents": [], "files_written": 1, "build_result": "not-run"}
            if started:
                rec["started"] = started
            already = False   # one run record per start: a close called twice must not count the triage twice
            runs_path = os.path.join(q("--where") or "docs/metrics", "runs.jsonl")
            if started and os.path.isfile(runs_path):
                already = any('"cmd":"triage-issues"' in l and f'"started":"{started}"' in l for l in open(runs_path, encoding="utf-8", errors="replace"))
            ok = True if already else emit("runs", rec)
        else:
            ok = None
        log["closed"] = now
        log_save(log)
        print(f"triage: {len(acts)} row(s) logged — {gates} gate record(s) (escaped), {misses} miss(es)"
              + (f", run record {'written' if ok else 'not written'}" if ok is not None else "") + f"; code untouched: {'yes' if not changed else 'NO'}")
        return 0
    die(f"unknown verb {verb}")


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""tf-log-miss.py — one miss record from one sentence (see tf-log-miss.sh).

    bash .tfcore/utils/tf-log-miss.sh <App> --what "<the owner's sentence>" --sort spec|unsaid|weak-check|ignored
         [--req REQ-UI-014 | --new "<title>" --acceptance "<When … on <screen>, then …>" [--prefix FN] [--section "<screen>"]]
         [--class <miss_class>] [--why <why_missed>] [--artifact <artifact>] [--severity blocker|major|minor]
         [--found-by owner|production] [--evidence <path>] [--fixed [--fix-run <ISO>]] [--started <ISO>]

First the sort (FR-32): --sort answers the four questions, in order, and is required.
    spec        the app's spec did not say it            -> fix the checklist line; the framework is untouched
    unsaid      the framework never said it              -> one requirement line plus a check; no prose in a task
    weak-check  a check existed and did not catch it     -> fix the check (a review becomes a script)
    ignored     it was written and not followed          -> a hook or script, or delete the rule
Then, in order: the duplicate check (an open miss of the same class on the row is reported, not
re-logged; a null why_missed or sort on it is completed with --amend); the origin lookup
(tf-emit.sh --origin-of); the miss record with the sentence as `what` and the sort; the checklist line
(the row demoted to Needs re-verify with "⚠ miss <date>: <sentence>", or a new Not Started row with
BRD-pending when nothing owns it; nothing when the repo has no checklist); with --fixed, a miss-fix
record instead of a demotion; then the run record (cmd log-miss) — none when another command is
running, because that command's own record covers the time (TF-029). The emitter rewrites the readable
docs/<App>-Misses.md. Prints the report block. Exit 0 · 2 could not run.
"""
import datetime
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EMIT = os.path.join(HERE, "tf-emit.sh")
CLASSES = {"missed-requirement", "partial-implementation", "unspecified-gap", "regression", "wrong-behaviour", "standards-violation", "spec-contradiction", "other"}
DEFAULT_ARTIFACT = {"unspecified-gap": "brd", "spec-contradiction": "brd", "standards-violation": "src"}
SORTS = ("spec", "unsaid", "weak-check", "ignored")
SORT_QUESTIONS = """tf-log-miss: --sort is missing. Answer the four questions in order and pass the first that fits:
  1. Did the app's spec say it clearly?            no  -> --sort spec        (fix the checklist line)
  2. Did the framework say it anywhere?            no  -> --sort unsaid      (one requirement line plus a check)
  3. Was there a check, and did it fail to catch it? yes -> --sort weak-check (fix the check)
  4. Was it written and ignored anyway?            yes -> --sort ignored     (a hook, or delete the rule)"""


def die(m):
    print(f"tf-log-miss: {m}", file=sys.stderr)
    sys.exit(2)


def opt(argv, name, default=None):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


def q(*args):
    return subprocess.run(["bash", EMIT, *args], capture_output=True, text=True).stdout.strip()


def emit(stream, rec):
    """Append one record. Returns (ok, reason) — the reason is what the emitter refused it for,
    so the caller can say the miss was NOT recorded instead of claiming it was (miss 06 of
    2026-09-07: a refused artifact value printed 'Miss logged' and an id that existed nowhere)."""
    p = subprocess.run(["bash", EMIT, stream], input=json.dumps(rec), capture_output=True, text=True)
    msg = (p.stdout + p.stderr).strip()
    ok = p.returncode == 0 and "refus" not in msg.lower() and "error" not in msg.lower()
    reason = ""
    if not ok:
        reason = msg.splitlines()[0][:200] if msg else "no reason printed"
        print(f"  {stream}: not written — {reason}")
    return ok, reason


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help") or "--what" not in argv:
        print(__doc__)
        return 0 if "-h" in argv or "--help" in argv else 2
    app = argv[1]
    what = opt(argv, "--what", "").strip()
    if not what:
        die("--what needs the sentence")
    sort = opt(argv, "--sort")
    if not sort:
        print(SORT_QUESTIONS, file=sys.stderr)
        return 2
    if sort not in SORTS:
        die(f"--sort must be one of {', '.join(SORTS)}")
    req = (opt(argv, "--req") or "").upper() or None
    new_title = opt(argv, "--new")
    cls = opt(argv, "--class") or ("unspecified-gap" if new_title else "wrong-behaviour")
    if cls not in CLASSES:
        die(f"--class must be one of {', '.join(sorted(CLASSES))}")
    why = opt(argv, "--why")
    artifact = opt(argv, "--artifact") or DEFAULT_ARTIFACT.get(cls, "src")
    severity = opt(argv, "--severity", "major")
    found_by = opt(argv, "--found-by", "owner")
    fixed = "--fixed" in argv
    started = opt(argv, "--started") or ""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    # The command whose run record covers this time. Called inside another command (*amend-docs
    # step 10), that command's record covers it, so this script writes none: a log-miss run over
    # the enclosing command's window made the enclosing record overlap and be refused (TF-029).
    # A marker older than 24 h belongs to a session that died, and is ignored as every reader does.
    running = "log-miss"
    if not started:
        mk = subprocess.run(["bash", os.path.join(HERE, "tf-phase.sh"), "show"], capture_output=True, text=True).stdout
        m = re.search(r'"started":"([^"]*)"', mk)
        c = re.search(r'"cmd":"([^"]*)"', mk)
        try:
            age = (datetime.datetime.now(datetime.timezone.utc)
                   - datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc))
            fresh = age < datetime.timedelta(hours=24)
        except (AttributeError, ValueError):
            fresh = False
        started = m.group(1) if fresh else now
        if fresh and c and c.group(1) not in ("log-miss", "goal"):
            running = c.group(1)

    spec = importlib.util.spec_from_file_location("tf_checklist_edit", os.path.join(HERE, "tf-checklist-edit.py"))
    ce = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ce)
    phase = 1
    cfg = os.path.join(".tfcore", "core-config.yaml")
    if os.path.isfile(cfg):
        m = re.search(r"(?m)^appPhase:\s*(\d+)", open(cfg, encoding="utf-8").read())
        phase = int(m.group(1)) if m else 1
    cl = os.path.join("docs", f"{app}-Checklist.md" if phase <= 1 else f"{app}-P{phase}-Checklist.md")
    has_cl = os.path.isfile(cl)

    # 1. duplicate check
    if req:
        opened = q("--open-miss", req)
        if opened and opened.split()[-1] == cls:
            mid = opened.split()[0]
            line = f"already logged as {mid}, still open."
            for fld, val in (("why_missed", why), ("sort", sort)):
                if val:
                    r = q("--amend", mid, fld, val)
                    line += f" {fld} completed with {val}." if "refus" not in r.lower() else f" ({fld} not amended: {r.split('—')[-1].strip()[:90]})"
            print(f"# Miss not re-logged — {app}\n{line}")
            return 0

    # 2. the checklist line
    doc_line = "no checklist in this repo — record only"
    if has_cl:
        if req:
            if fixed:
                doc_line = f"{req} left as it is (--fixed)"
            else:
                prior = ce.demote(cl, req, what, evidence=opt(argv, "--evidence"), source=found_by,
                                  prefix="⚠ prod bug" if found_by == "production" else "⚠ miss")
                doc_line = f"{req} demoted to Needs re-verify (was {prior['status']})" if prior else f"{req} is not a row of {cl}; record only"
        elif new_title:
            acc = opt(argv, "--acceptance") or die("--new needs --acceptance")
            req = ce.add_row(cl, opt(argv, "--prefix", "FN").upper(), new_title, acc, section=opt(argv, "--section"),
                             mockup=opt(argv, "--mockup"), remark=f"logged via *log-miss {ce.TODAY}")
            doc_line = f"new Not Started row {req} (BRD-pending; *amend-docs gives it its BRD item)"
        else:
            doc_line = "no owning row and no --new: record only"

    # 3. the miss
    mid = q("--next-miss-id")
    rec = {"kind": "miss", "miss_id": mid, "req_id": req, "req_class": req.split("-")[1] if req else None, "miss_class": cls,
           "artifact": artifact, "severity": severity, "why_missed": why, "origin_phase": "day1-greenfield" if cls in ("unspecified-gap", "spec-contradiction") else "build-phase",
           "origin_agent": "analyst" if cls in ("unspecified-gap", "spec-contradiction") else "flow-master",
           "found_by": found_by, "found_phase": "log-miss", "found_gate": None, "found_run_id": started, "failure_class": "other", "what": what[:300],
           "sort": sort}
    attributed = "inferred, no run record found"
    if req and cls not in ("unspecified-gap", "spec-contradiction"):
        o = q("--origin-of", req).split()
        if len(o) >= 3:
            rec["origin_run_id"], rec["origin_phase"], rec["origin_agent"] = o[0], o[1], o[2]
            attributed = f"linked to run {o[0]}"
    ok, refusal = emit("misses", rec)

    # 4. --fixed
    fix_line = ""
    if fixed and ok:
        fa = q("--next-fix-attempt", mid) or "1"
        fr = {"kind": "miss-fix", "miss_id": mid, "req_id": req, "fix_cmd": "log-miss", "fix_attempt": int(fa) if fa.isdigit() else 1,
              "verdict_after": "Verified", "reopened": False}
        if opt(argv, "--fix-run"):
            fr["fix_run_id"] = opt(argv, "--fix-run")
        fix_ok, _ = emit("misses", fr)
        fix_line = ("closed in the same run" + (f" against run {fr['fix_run_id']}" if "fix_run_id" in fr else " (fix run unknown: costed none)")) if fix_ok else "miss-fix not written"

    # 5. the run record — only when log-miss is the command running
    if running == "log-miss":
        run = {"kind": "run", "app": app, "cmd": "log-miss", "mode": None, "started": started, "ended": now,
               "reqs_touched": [req] if req else [], "reqs_count": 1 if req else 0, "subagents": [], "files_written": 1 if has_cl else 0, "build_result": "not-run"}
        emit("runs", run)
        run_line = f"log-miss, {started} to {now}"
    else:
        run_line = f"none written — the running *{running}'s own record covers this time"

    if not ok:
        print(f"# Miss NOT recorded — {app}")
        print(f"Refused    : {refusal}")
        print(f"Nothing carries the id {mid}: the stream has no record and docs/{app}-Misses.md is unchanged.")
        print(f"Docs       : {doc_line}")
        print("Next       : fix the value the emitter named and run the same command again.")
        return 2

    print(f"# Miss logged — {app}")
    print(f"{mid}  {cls} / {artifact} / {severity}")
    print(f"Why missed : {why or 'not assessed'}")
    print(f"Whose gap  : {sort} — " + {"spec": "the app's spec did not say it; fix the checklist line", "unsaid": "the framework never said it; one requirement line plus a check",
                                        "weak-check": "the check was too weak; fix the check", "ignored": "said and ignored; a hook, or delete the rule"}[sort])
    print(f"Owning REQ : {req or 'none'}")
    print(f"Attributed : {rec['origin_phase']} ({rec['origin_agent']}) — {attributed}")
    print(f"Found by   : {found_by}")
    print(f"Docs       : {doc_line}; docs/{app}-Misses.md rewritten")
    if fix_line:
        print(f"Fix        : {fix_line}")
    print(f"Run record : {run_line}")
    print(f"Next       : *fix-issues {app}" + (f" {req}" if req and not fixed else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

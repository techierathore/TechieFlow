#!/usr/bin/env python3
"""tf-status-facts.py — print the facts PROJECT-STATUS.md is written from.

    bash .tfcore/utils/tf-status-facts.sh <App> ["<command label>"] [--phase N]

Reads docs/<App>-Checklist.md, docs/.last-verify.json, docs/metrics/gates.jsonl,
docs/<App>-*-Feedback.md and the current PROJECT-STATUS.md. On a Large project the
checklist is the one of the phase being worked: --phase N, else appPhase in
.tfcore/core-config.yaml (phase 1 is docs/<App>-Checklist.md, phase n is
docs/<App>-Pn-Checklist.md), and the phase line names it from docs/<App>-Phases.md. Prints, ready to copy
into the template (.tfcore/templates/v4custom/app-project-status-tmpl.md):

  - the frontmatter values (last_updated, current_phase, last_verified_*)
  - the Open requirements section (counts by status, at most ten named rows)
  - the Verification log table with its new row (last five kept)
  - the Library feedback summary lines
  - the Next command to run, in both harness forms, and why

Writes nothing. The agent writes PROJECT-STATUS.md with the harness Write tool.
Python 3 standard library only. Exit 0 printed, 2 could not run.
"""
import datetime
import glob
import json
import os
import re
import sys

TERMINAL = {"verified", "done (pre-existing)", "n/a"}
PASS_THROUGH = {"blocked"}           # a library gap; counts as closed for the ladder
BUILT = {"implemented", "needs re-verify"}
OWNER = {"owner-uat"}                # only the owner can close it, from the UsageGuide test plan
# anything else (Not Started, In Progress, PARTIAL, FAIL, unknown) is not built yet

LADDER = ["Not Started", "In Progress", "PARTIAL", "FAIL", "Implemented", "Needs re-verify",
          "Blocked", "Owner-UAT", "Verified", "Done (pre-existing)", "N/A"]
COUNT_ROWS = ["Not Started", "In Progress", "Implemented", "Needs re-verify", "Blocked"]

CC = "/TechieFlow:agents:"
OC = "/"
AGENT_OC = {"flow-master": "flow-master", "verifier": "flow-verifier", "analyst": "flow-analyst"}


def die(msg):
    print(f"tf-status-facts: {msg}", file=sys.stderr)
    sys.exit(2)


def norm_status(raw):
    s = raw.strip().strip("`* ").strip()
    low = s.lower()
    for v in LADDER:
        if low == v.lower() or low.startswith(v.lower() + " ("):
            return v
    return s or "?"


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def checklist_rows(text):
    rows = []
    for line in text.splitlines():
        if not re.match(r"^\s*\|\s*`?REQ-", line):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        rid = cells[0].strip("`* ")
        rows.append({"id": rid, "name": cells[1].strip("`* "), "status": norm_status(cells[2])})
    return rows


def ladder_rank(status):
    return LADDER.index(status) if status in LADDER else 0


def last_verify(root, app):
    """(date, build_result) from docs/.last-verify.json and gates.jsonl; ('', 'not-run') if none."""
    ledger = os.path.join(root, "docs", ".last-verify.json")
    if not os.path.isfile(ledger):
        return "", "not-run"
    try:
        data = json.loads(read(ledger).strip().splitlines()[-1])
    except Exception:
        return "", "not-run"
    date = str(data.get("date", ""))[:10]
    result = "PASS"
    gates = os.path.join(root, "docs", "metrics", "gates.jsonl")
    if date and os.path.isfile(gates):
        for line in read(gates).splitlines():
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if rec.get("app") == app and str(rec.get("ts", ""))[:10] == date and rec.get("gate") == "build":
                result = "FAIL"
                break
    return date, result


def existing_log_rows(status_text):
    m = re.search(r"(?ms)^## Verification log\s*\n(.*?)(?=^## |\Z)", status_text)
    if not m:
        return []
    rows = []
    for line in m.group(1).splitlines():
        if re.match(r"^\s*\|", line) and not re.match(r"^\s*\|\s*-", line) and "Date" not in line.split("|")[1]:
            rows.append(line.strip())
    return rows


def handoff_ran(log_rows):
    return any("handoff" in r.lower() for r in log_rows)


def feedback_lines(root, app):
    out = []
    for path in sorted(glob.glob(os.path.join(root, "docs", f"{app}-*-Feedback.md"))):
        lib = re.sub(rf"^{re.escape(app)}-(.+)-Feedback\.md$", r"\1", os.path.basename(path))
        text = read(path)
        entries = re.split(r"(?m)^###\s+", text)[1:]
        open_n = 0
        for e in entries:
            closed = re.search(r"(?im)^\s*[-*]\s*\*\*(status|resolved|fixed)[^:]*:\*\*\s*(fixed|resolved|closed|done)", e)
            if not closed:
                open_n += 1
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        out.append(f"- {lib}: {open_n} open of {len(entries)} — {rel}")
    return out or ["- None"]


def config_phase(root):
    p = os.path.join(root, ".tfcore", "core-config.yaml")
    if os.path.isfile(p):
        m = re.search(r"(?m)^appPhase:\s*(\d+)", read(p))
        if m:
            return int(m.group(1))
    return 1


def phase_prefix(app, phase):
    return f"{app}-" if phase <= 1 else f"{app}-P{phase}-"


def phase_row(root, app, phase):
    """(name, total phases) from docs/<App>-Phases.md; ('', 0) when the project has no phases."""
    p = os.path.join(root, "docs", f"{app}-Phases.md")
    if not os.path.isfile(p):
        return "", 0
    m = re.search(r"(?ms)^##\s+(?:\d+[.)]\s*)?Phases[^\n]*\n(.*?)(?=^## |\Z)", read(p))
    name, total = "", 0
    for line in (m.group(1) if m else "").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 2 and cells[0].strip("`* ").isdigit():
            total += 1
            if int(cells[0].strip("`* ")) == phase:
                name = cells[1].strip("`* ")
    return name, total


def next_command(app, rows, log_rows, phase=1):
    """Returns (phase, qualifier, cc_line, oc_line, reason)."""
    def ids(lst):
        return ", ".join(r["id"] for r in lst[:6]) + (" …" if len(lst) > 6 else "")

    if not rows:
        if os.path.isfile(os.path.join(os.getcwd(), "docs", f"{phase_prefix(app, phase)}BRD.md")):
            return ("Day-1", "stage 1 done, awaiting owner review",
                    f"{CC}analyst *day1-greenfield {app} --stage2", f"{OC}flow-analyst *day1-greenfield {app} --stage2",
                    "the BRD exists and no checklist; stage 2 runs on the owner's go-ahead")
        return ("Day-1", "no documents yet",
                f"{CC}analyst *day1-greenfield {app}", f"{OC}flow-analyst *day1-greenfield {app}",
                "no BRD and no checklist exist; day-1 stage 1 has not run")

    unbuilt = [r for r in rows if r["status"].lower() not in TERMINAL | PASS_THROUGH | BUILT | OWNER]
    built = [r for r in rows if r["status"].lower() in BUILT]
    owner = [r for r in rows if r["status"].lower() in OWNER]
    total = len(rows)
    closed = sum(1 for r in rows if r["status"].lower() in TERMINAL)
    q = f"{closed} of {total} verified"

    if unbuilt:
        return ("Build", f"{len(unbuilt)} not built, {q}",
                f"{CC}flow-master *build-phase {app}", f"{OC}flow-master *build-phase {app}",
                f"{len(unbuilt)} rows are not built yet: {ids(unbuilt)}")
    if built:
        ui = [r for r in built if r["id"].startswith("REQ-UI")]
        scope = "ui" if len(ui) == len(built) else ("functional" if not ui else "all")
        return ("Verify", f"{len(built)} to verify, {q}",
                f"{CC}verifier *verify {scope} {app}", f"{OC}flow-verifier *verify {scope} {app}",
                f"{len(built)} rows are built and not verified: {ids(built)}")
    if owner:
        if handoff_ran(log_rows):
            line = f"(owner-run) docs/{app}-UsageGuide.md — {ids(owner)}"
            return ("UAT", f"{len(owner)} owner-run, {q}", line, line,
                    f"{len(owner)} rows are Owner-UAT and handoff has run; the owner closes them")
        return ("Handoff", f"{len(owner)} owner-run, {q}",
                f"{CC}flow-master *handoff-phase {app}", f"{OC}flow-master *handoff-phase {app}",
                f"{len(owner)} rows are Owner-UAT and handoff has not run yet")
    if handoff_ran(log_rows):
        line = "(owner) set current_phase to Released after UAT — no agent command"
        return ("UAT", f"handoff done, {q}", line, line,
                "every row is terminal and handoff has run; waiting on the owner")
    return ("Handoff", q,
            f"{CC}flow-master *handoff-phase {app}", f"{OC}flow-master *handoff-phase {app}",
            "every row is terminal and handoff has not run yet")


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    app = argv[1]
    args = argv[2:]
    root = os.getcwd()
    phase_n = None
    if "--phase" in args:
        i = args.index("--phase")
        if i + 1 >= len(args) or not args[i + 1].isdigit() or int(args[i + 1]) < 1:
            die("--phase needs a number from 1 upwards")
        phase_n = int(args[i + 1])
        del args[i:i + 2]
    phase_n = phase_n or config_phase(root)
    label = args[0] if args else "status"
    today = datetime.date.today().isoformat()

    cl_rel = f"docs/{phase_prefix(app, phase_n)}Checklist.md"
    cl_path = os.path.join(root, cl_rel)
    rows = checklist_rows(read(cl_path)) if os.path.isfile(cl_path) else []
    st_path = os.path.join(root, "PROJECT-STATUS.md")
    st_text = read(st_path) if os.path.isfile(st_path) else ""
    log_rows = existing_log_rows(st_text)
    vdate, vresult = last_verify(root, app)
    phase, qual, cc, oc, reason = next_command(app, rows, log_rows, phase_n)
    pname, ptotal = phase_row(root, app, phase_n)
    if ptotal or phase_n > 1:
        tag = f"Phase {phase_n} of {ptotal or '?'}" + (f" ({pname})" if pname else "")
        phase = f"{tag} · {phase}"
        reason = f"{reason}; working {cl_rel}"

    total = len(rows)
    closed = sum(1 for r in rows if r["status"].lower() in TERMINAL)
    counts = {}
    for r in rows:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    open_rows = sorted((r for r in rows if r["status"].lower() not in TERMINAL),
                       key=lambda r: (ladder_rank(r["status"]), r["id"]))

    print(f"# tf-status-facts — {app} — {today} — copy into PROJECT-STATUS.md (Write tool)")
    print()
    print("## Frontmatter values")
    print(f"last_updated: {today}")
    print(f"current_phase: {phase} — {qual}")
    print(f"last_verified_build: {vresult}")
    print(f"last_verified_date: {vdate or 'never'}")
    print()
    print("## Next command to run")
    print(f"Claude Code:\n```\n{cc}\n```\nOpenCode:\n```\n{oc}\n```")
    print(f"Why: {reason}.")
    print()
    print("## Open requirements")
    print("| Status | Count |\n|---|---|")
    shown = set()
    for s in COUNT_ROWS:
        print(f"| {s} | {counts.get(s, 0)} |")
        shown.add(s)
    for s, n in sorted(counts.items(), key=lambda kv: ladder_rank(kv[0])):
        if s not in shown and s.lower() not in TERMINAL:
            print(f"| {s} | {n} |")
    print()
    if open_rows:
        for r in open_rows[:10]:
            print(f"- [ ] {r['id']} — {r['name']} ({r['status']})")
        if len(open_rows) > 10:
            print(f"- ({len(open_rows) - 10} more open rows in {cl_rel})")
    else:
        print("- None")
    print()
    print("## Verification log")
    print("Last five passes; older passes live in `docs/metrics/gates.jsonl`.")
    print()
    print("| Date | Phase | Result | Status table |\n|---|---|---|---|")
    new_row = f"| {today} | {label} | {closed}/{total} Verified | {cl_rel}#requirements-status |"
    for r in (log_rows[-4:] if len(log_rows) > 4 else log_rows):
        print(r)
    print(new_row)
    print()
    print("## Library feedback summary")
    for line in feedback_lines(root, app):
        print(line)
    print()
    print("## You write these yourself")
    print("- Where I am: at most 80 words, state not story." + (f" Name the phase: {phase.split(' · ')[0]}." if ptotal or phase_n > 1 else ""))
    print("- Known blockers: one line each, or `- None`.")
    print("- Standards compliance: `- Last check {date}: {n} findings, see the checklist Remarks.`")
    print("- Deferred / future: parked ideas, one line each.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as e:  # never a stack trace for the agent to wade through
        die(str(e))

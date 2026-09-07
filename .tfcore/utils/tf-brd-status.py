#!/usr/bin/env python3
"""tf-brd-status.py — rewrite the BRD's "Development status" table from the checklist.

    bash .tfcore/utils/tf-brd-status.sh <App> [--no-render] [--phase N]

On a Large project the pair is the phase being worked: --phase N, else appPhase in
.tfcore/core-config.yaml (phase 1 is docs/<App>-BRD.md and -Checklist.md, phase n is
docs/<App>-Pn-BRD.md and docs/<App>-Pn-Checklist.md).

Reads docs/<App>-Checklist.md: every REQ row of the Requirements Status table, and
the "## Page: …" section its detail entry sits under, which names the screen.
Writes one row per screen into the "Development status" section of
docs/<App>-BRD.md (Screen | Requirements | Verified | Open | Status) with a
"Snapshot as of <today>" line, inserting the section before "Context diagram"
(or at the end) when the BRD has none. Touches nothing else in the BRD. Then
re-renders docs/<App>-BRD.html through tf-render-html.sh unless --no-render.

Status per screen: Done (every row terminal), Planned (no row started),
Partial (some terminal, some open), In progress (started, none terminal).
Terminal = Verified, Done (pre-existing), N/A. Blocked is counted as open.

Python 3 standard library only. Exit 0 written or nothing to do, 2 could not run.
"""
import datetime
import os
import re
import subprocess
import sys

TERMINAL = {"verified", "done (pre-existing)", "n/a"}
NOT_STARTED = {"not started"}


def die(msg):
    print(f"tf-brd-status: {msg}", file=sys.stderr)
    sys.exit(2)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def norm(raw):
    s = raw.strip().strip("`* ").lower()
    return re.sub(r"\s*\(.*$", "", s).strip()


def screen_name(heading):
    h = heading.strip()
    h = re.sub(r"^(?:\d+[.)]\s*)?(?:page|screen)\s*:\s*", "", h, flags=re.I)
    h = re.sub(r"\s*\(`?/[^)]*`?\)\s*$", "", h)  # trailing (`/route`)
    return h.strip("` ").strip() or heading.strip()


def parse_checklist(text):
    rows = []
    for line in text.splitlines():
        if re.match(r"^\s*\|\s*`?REQ-", line):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 3:
                rows.append((cells[0].strip("`* "), norm(cells[2])))
    screen_of = {}
    current = "Other"
    for line in text.splitlines():
        m = re.match(r"^##\s+(.+)$", line)
        if m:
            current = screen_name(m.group(1))
            continue
        for a in re.findall(r"<a id=['\"]d-(req-[a-z]+-\d+)['\"]", line, flags=re.I):
            screen_of[a.upper()] = current
    return rows, screen_of


def table(rows, screen_of):
    per = {}
    order = []
    for rid, status in rows:
        s = screen_of.get(rid.upper(), "Unmapped")
        if s not in per:
            per[s] = {"n": 0, "v": 0, "ns": 0}
            order.append(s)
        per[s]["n"] += 1
        per[s]["v"] += 1 if status in TERMINAL else 0
        per[s]["ns"] += 1 if status in NOT_STARTED else 0
    out = ["| Screen | Requirements | Verified | Open | Status |", "|---|---|---|---|---|"]
    for s in order:
        d = per[s]
        open_n = d["n"] - d["v"]
        if open_n == 0:
            st = "Done"
        elif d["ns"] == d["n"]:
            st = "Planned"
        elif d["v"] > 0:
            st = "Partial"
        else:
            st = "In progress"
        out.append(f"| {s} | {d['n']} | {d['v']} | {open_n} | {st} |")
    return "\n".join(out), len(order)


def write_section(brd_text, app, body):
    """Replace the body of the Development status section, or insert the section."""
    sec = re.compile(r"(?ms)^(##\s+(?:\d+[.)]\s*)?Development status[^\n]*\n)(.*?)(?=^## |\Z)")
    m = sec.search(brd_text)
    if m:
        return brd_text[:m.start()] + m.group(1) + "\n" + body + "\n\n" + brd_text[m.end():], "updated"
    heading = "## Development status\n"
    ctx = re.search(r"(?m)^##\s+(?:\d+[.)]\s*)?Context diagram", brd_text)
    if ctx:
        return brd_text[:ctx.start()] + heading + "\n" + body + "\n\n" + brd_text[ctx.start():], "inserted"
    return brd_text.rstrip("\n") + "\n\n" + heading + "\n" + body + "\n", "appended"


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    app = argv[1]
    render = "--no-render" not in argv
    root = os.getcwd()
    phase = None
    if "--phase" in argv:
        i = argv.index("--phase")
        if i + 1 >= len(argv) or not argv[i + 1].isdigit() or int(argv[i + 1]) < 1:
            die("--phase needs a number from 1 upwards")
        phase = int(argv[i + 1])
    if phase is None:
        cfg = os.path.join(root, ".tfcore", "core-config.yaml")
        m = re.search(r"(?m)^appPhase:\s*(\d+)", read(cfg)) if os.path.isfile(cfg) else None
        phase = int(m.group(1)) if m else 1
    pfx = f"{app}-" if phase <= 1 else f"{app}-P{phase}-"
    cl_rel, brd_rel = f"docs/{pfx}Checklist.md", f"docs/{pfx}BRD.md"
    cl = os.path.join(root, cl_rel)
    brd = os.path.join(root, brd_rel)
    if not os.path.isfile(cl):
        print(f"tf-brd-status: {cl_rel} does not exist yet; nothing to do")
        return 0
    if not os.path.isfile(brd):
        die(f"{brd_rel} does not exist")
    rows, screen_of = parse_checklist(read(cl))
    if not rows:
        die(f"{cl_rel} has no REQ rows in its Requirements Status table")
    tbl, screens = table(rows, screen_of)
    today = datetime.date.today().isoformat()
    body = (
        "Written by the status gate after every build, verify and handoff; not by hand.\n\n"
        f"**Snapshot as of {today}.** Live per-requirement status: `PROJECT-STATUS.md` and the "
        f"Requirements Status table in `{cl_rel}`.\n\n" + tbl
    )
    text = read(brd)
    new_text, how = write_section(text, app, body)
    with open(brd, "w", encoding="utf-8") as f:
        f.write(new_text)
    verified = sum(1 for _, s in rows if s in TERMINAL)
    print(f"tf-brd-status: {brd_rel} Development status {how}: {screens} screens, {verified} of {len(rows)} requirements verified")
    if render:
        script = os.path.join(root, ".tfcore", "utils", "tf-render-html.sh")
        if os.path.isfile(script):
            rc = subprocess.call(["bash", script, os.path.relpath(brd, root)], cwd=root)
            if rc != 0:
                print(f"tf-brd-status: the HTML render exited {rc}; run bash .tfcore/utils/tf-render-html.sh {brd_rel} by hand", file=sys.stderr)
                return 1
            print(f"tf-brd-status: rendered {brd_rel[:-3]}.html")
        else:
            print("tf-brd-status: .tfcore/utils/tf-render-html.sh not found at its literal path; HTML not rendered", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as e:
        die(str(e))

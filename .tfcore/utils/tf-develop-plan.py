#!/usr/bin/env python3
"""tf-develop-plan.py — what *develop-end-to-end still has to do in an app folder (2026-11-19).

    python3 .tfcore/utils/tf-develop-plan.py <app-dir> <App> day1      # stage 1: run, or skip
    python3 .tfcore/utils/tf-develop-plan.py <app-dir> <App> day1-2    # stage 2: run, or skip
    python3 .tfcore/utils/tf-develop-plan.py <app-dir> <App> phases    # one line per build or handoff step

tf-develop.sh calls it before each step, so a document a step has just written counts. Each line is
three fields separated by a tab: the step's name, `run` or `skip`, and a detail.

  day1, day1-2  `skip` when every document of that stage is on disk ("documents already written");
                `run` with an empty detail when none is (a new app), or with the paths still missing,
                so the agent writes only those and keeps the rest.
  phases        a Small or Medium app (no docs/<App>-Phases.md) has one phase: `build`, `handoff`. A
                Large app has `build-pN` and `handoff-pN` per row of the Phases table, in the table's
                order; the detail is N. A row whose Status is done or kept-whole is `skip`, with N and that status.

Reads files only; writes nothing. Python 3 standard library only.
"""
import glob
import os
import re
import sys


def phase_rows(root, app):
    """[(n, status)] from docs/<App>-Phases.md, in table order; [] when there is no Phases document"""
    p = os.path.join(root, "docs", f"{app}-Phases.md")
    if not os.path.isfile(p):
        return []
    rows = []
    for line in open(p, encoding="utf-8", errors="replace"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 2 and re.fullmatch(r"\d+", cells[0]):
            rows.append((int(cells[0]), cells[-1].lower()))
    return rows


def docs_of(app, n, kind):
    return f"docs/{app}-{kind}.md" if n <= 1 else f"docs/{app}-P{n}-{kind}.md"


def missing(root, app, stage):
    rows = phase_rows(root, app)
    nums = [n for n, _ in rows] or [1]
    todo = [n for n, st in rows if st not in ("done", "kept-whole")] if rows else [1]   # a done phase's design is not wanted
    has = lambda w: any(os.path.isfile(os.path.join(root, x)) for x in w.split("|"))
    if stage == "day1":
        want = [f"docs/{app}-BRD.md", f"docs/{app}-Architecture.md"] + ([f"docs/{app}-UIDesign.md"] if 1 in todo else [])
        want += [docs_of(app, n, "BRD") for n in nums if n > 1] + [docs_of(app, n, "UIDesign") for n in todo if n > 1]
        gone = [w for w in want if not has(w)]
        if not glob.glob(os.path.join(root, "docs", "mockups", "*.html")):
            gone.append("docs/mockups/*.html")
        return gone, len(want) + 1
    want = [docs_of(app, n, "Checklist") for n in nums]
    # the usage guide under any name the framework's readers accept (AppManager writes docs/{App}-Usage-Guide.md)
    want += [f"docs/{app}-Coding-Standards.md", f"docs/{app}-UsageGuide.md|docs/{app}-Usage-Guide.md|docs/{app}-TestNUsageDoc.md"]
    return [w.split("|")[0] for w in want if not has(w)], len(want)


def main(argv):
    if len(argv) != 4 or argv[3] not in ("day1", "day1-2", "phases"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    root, app, what = argv[1], argv[2], argv[3]
    if what in ("day1", "day1-2"):
        gone, total = missing(root, app, "day1" if what == "day1" else "stage2")
        if not gone:
            print(f"{what}\tskip\tdocuments already written")
        else:
            print(f"{what}\trun\t{'' if len(gone) == total else ' '.join(gone)}")
        return 0
    rows = phase_rows(root, app)
    if not rows:
        print("build\trun\t1")
        print("handoff\trun\t1")
        return 0
    for n, status in rows:
        act = "skip" if status in ("done", "kept-whole") else "run"
        for step in ("build", "handoff"):
            print(f"{step}-p{n}\t{act}\t{n}" + (f" {status}" if act == "skip" else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

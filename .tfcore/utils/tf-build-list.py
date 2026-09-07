#!/usr/bin/env python3
"""tf-build-list.py — the mechanical start of a build pass (see tf-build-list.sh).

    bash .tfcore/utils/tf-build-list.sh <App> [--phase N] [--prompts]

Reads the phase's checklist (appPhase in core-config.yaml, or --phase) and prints:
  - the mode: FIX (rows FAIL / PARTIAL / In Progress / Needs re-verify exist), FRESH
    (every open row), or NOTHING (every row terminal or Blocked)
  - the working list, grouped into clusters by the checklist's page section, each
    naming its builder from the row prefix: REQ-UI -> trblazeui, REQ-RAG -> techierag,
    REQ-FN / REQ-NFR -> builder
  - with --prompts, one ready sub-agent prompt per cluster, filled from
    .tfcore/templates/v4custom/build-subagent-prompt.md with the rows, their acceptance
    lines, their mockups and the two standing rules.
Writes nothing. Python 3 standard library only. Exit 0 printed, 2 could not run.
"""
import os
import re
import sys

TERMINAL = {"verified", "done (pre-existing)", "n/a"}
FIX = {"fail", "partial", "in progress", "needs re-verify"}
BLOCKED = {"blocked"}
BUILDER = {"UI": "trblazeui", "RAG": "techierag", "FN": "builder", "NFR": "builder"}
TPL = os.path.join(".tfcore", "templates", "v4custom", "build-subagent-prompt.md")


def die(msg):
    print(f"tf-build-list: {msg}", file=sys.stderr)
    sys.exit(2)


def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def config_phase():
    p = os.path.join(".tfcore", "core-config.yaml")
    if os.path.isfile(p):
        m = re.search(r"(?m)^appPhase:\s*(\d+)", read(p))
        if m:
            return int(m.group(1))
    return 1


def norm(s):
    s = s.strip().strip("`* ").lower()
    return re.sub(r"\s*\(.*$", "", s).strip()


def rows_of(text):
    rows = []
    for line in text.splitlines():
        if re.match(r"^\s*\|\s*`?REQ-", line):
            c = [x.strip() for x in line.strip().strip("|").split("|")]
            if len(c) >= 3:
                rows.append({"id": c[0].strip("`* "), "title": c[1].strip("`* "), "status": norm(c[2]),
                             "remarks": c[4] if len(c) > 4 else ""})
    return rows


def entries_of(text):
    """id -> (section heading, acceptance line, mockup, brd)"""
    out, current = {}, "Other"
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r"^##\s+(.+)$", line)
        if m:
            current = re.sub(r"^(?:page|screen)\s*:\s*", "", m.group(1).strip(), flags=re.I)
            continue
        a = re.search(r"<a id=['\"]d-(req-[a-z]+-\d+)['\"]", line, re.I)
        if a:
            rid = a.group(1).upper()
            acc = mock = brd = ""
            for j in range(i, min(i + 12, len(lines))):
                l = lines[j]
                if re.search(r"\*Acceptance:?\*|^\s*[-*]\s*Acceptance:", l, re.I) and not acc:
                    acc = re.sub(r"^\s*[-*]\s*\*?Acceptance:?\*?:?\s*", "", l).strip()
                mm = re.search(r"((?:docs/)?mockups/[\w./-]+\.html)", l)
                if mm and not mock:
                    mock = mm.group(1)
                bm = re.search(r"BRD-\d+", l)
                if bm and not brd:
                    brd = bm.group(0)
                if j > i and re.match(r"^\s*(?:[-*]\s*)?<a id=|^## ", l):
                    break   # the next entry starts (it begins with "- <a id="): nothing below is this row's
            out[rid] = (current, acc, mock, brd)
    return out


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    app = argv[1]
    prompts = "--prompts" in argv
    phase = config_phase()
    if "--phase" in argv:
        i = argv.index("--phase")
        if i + 1 >= len(argv) or not argv[i + 1].isdigit():
            die("--phase needs a number")
        phase = int(argv[i + 1])
    pfx = f"{app}-" if phase <= 1 else f"{app}-P{phase}-"
    cl = os.path.join("docs", f"{pfx}Checklist.md")
    if not os.path.isfile(cl):
        die(f"{cl} does not exist; day-1 stage 2 writes it")
    text = read(cl)
    rows = rows_of(text)
    if not rows:
        die(f"{cl} has no REQ rows")
    ent = entries_of(text)

    fix_rows = [r for r in rows if r["status"] in FIX]
    open_rows = [r for r in rows if r["status"] not in TERMINAL | BLOCKED]
    if fix_rows:
        mode, work = "FIX", fix_rows
    elif open_rows:
        mode, work = "FRESH", open_rows
    else:
        mode, work = "NOTHING", []
    terminal = sum(1 for r in rows if r["status"] in TERMINAL)
    blocked = [r for r in rows if r["status"] in BLOCKED]
    print(f"# tf-build-list — {app} — {cl} — phase {phase}")
    print(f"Mode: {mode} — {len(work)} row(s) to build; {terminal} terminal, {len(blocked)} Blocked, {len(rows)} total"
          + (f" — {', '.join(r['id'] for r in work[:8])}{' …' if len(work) > 8 else ''}" if work else ""))
    if blocked:
        print("Blocked (library gaps, pass through unless the feedback entry is resolved): " + ", ".join(r["id"] for r in blocked))
    if not work:
        print("Nothing to build. Run the status gate; the next command is the verifier's or the owner's.")
        return 0

    clusters = {}
    for r in work:
        sec, acc, mock, brd = ent.get(r["id"].upper(), ("Other", "", "", ""))
        cls = re.match(r"REQ-(UI|FN|RAG|NFR)-", r["id"]).group(1)
        key = ("Non-functional" if cls == "NFR" else "RAG" if cls == "RAG" else sec, BUILDER[cls])
        clusters.setdefault(key, []).append((r, acc, mock, brd))
    print()
    print("## Clusters (one sub-agent each; spawn them all in one turn)")
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    named = []
    for i, ((sec, builder), items) in enumerate(clusters.items()):
        label = letters[i % 26] + ("" if i < 26 else str(i // 26))
        named.append((label, sec, builder, items))
        mocks = sorted({m for _r, _a, m, _b in items if m})
        print(f"Cluster {label} [{builder}]: " + ", ".join(r["id"] for r, *_ in items)
              + f"  ({sec}" + (f" — mockup: {', '.join(mocks)}" if mocks else "") + ")")
    print()
    print("## Working list")
    for label, sec, builder, items in named:
        for r, acc, mock, brd in items:
            todo = "" if acc else "  ⚠ no acceptance line: fix the checklist first"
            print(f"- {r['id']} [{label}/{builder}] {r['title']} — {r['status']}{todo}")
            if acc:
                print(f"    Acceptance: {acc}")
            if mock:
                print(f"    Mockup: {mock}")
    if not prompts:
        print()
        print("Add --prompts for one ready sub-agent prompt per cluster.")
        return 0
    if not os.path.isfile(TPL):
        die(f"template {TPL} does not exist at its literal path")
    tpl = read(TPL)
    tpl = re.sub(r"<!--.*?-->\s*", "", tpl, flags=re.S)
    for label, sec, builder, items in named:
        lines = []
        for r, acc, mock, brd in items:
            lines.append(f"- {r['id']} — {r['title']}" + (f" ({brd})" if brd else ""))
            lines.append(f"  Acceptance: {acc or 'MISSING — refuse the row and report it'}")
            if mock:
                lines.append(f"  Mockup: {mock}")
        mocks = sorted({m for _r, _a, m, _b in items if m})
        body = (tpl.replace("{App}", app).replace("{Cluster}", label).replace("{Builder}", builder)
                .replace("{Section}", sec).replace("{Rows}", "\n".join(lines))
                .replace("{Mockups}", ", ".join(mocks) if mocks else "none (not a UI cluster)")
                .replace("{Checklist}", cl))
        print()
        print(f"## Prompt for cluster {label} [{builder}]")
        print(body.strip())
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as e:
        die(str(e))

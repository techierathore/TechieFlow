#!/usr/bin/env python3
"""tf-build-list.py — the mechanical start of a build pass (see tf-build-list.sh).

    bash .tfcore/utils/tf-build-list.sh <App> [--phase N] [--prompts]

Reads the phase's checklist (appPhase in core-config.yaml, or --phase) and prints:
  - the mode: FIX (rows FAIL / PARTIAL / In Progress / Needs re-verify exist, and they
    come FIRST in the list), FRESH (nothing failing), or NOTHING (every row terminal or
    Blocked). The working list is every open row in both FIX and FRESH: the mode says
    what to build first, never what to leave out. A roadmap row (tf_roadmap.py) is not
    open: it is counted and named apart, never built.
  - the working list, grouped into clusters by the checklist's page section, each
    naming its builder from the row prefix: REQ-UI -> trblazeui when the project uses
    TrBlazeUI (else builder), REQ-RAG -> techierag, REQ-FN / REQ-NFR -> builder
  - with --prompts, one ready sub-agent prompt per cluster, filled from
    .tfcore/templates/v4custom/build-subagent-prompt.md with the rows, their acceptance
    lines, their mockups and the two standing rules.
Writes nothing. Python 3 standard library only. Exit 0 printed, 2 could not run.
"""
import os
import re
import sys

# norm() drops a bracketed tail ("Verified (2026-09-01)"), so "Done (pre-existing)" arrives as "done":
# only the bracketed spelling was listed, and AppManager's 18 finished rows went on the working list (TF-003)
TERMINAL = {"verified", "done", "done (pre-existing)", "n/a"}
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


def ui_builder(app):
    """-> (builder, why) for the UI clusters: trblazeui only when the project uses TrBlazeUI.

    The framework gives every project `.trblazeui/`, whether it uses the library or not, so that
    folder says nothing: AppManager, which does not use it, had its UI rows sent to the trblazeui
    sub-agent (TF-008). The project's own files decide: a TrBlazeUI package or project reference in
    a .csproj or .props. Before any such file exists (a first build), the Architecture document
    naming it decides. tests/regression/run.sh am_008."""
    skip = {"bin", "obj", "node_modules", ".git", ".tfcore", ".claude", ".opencode", ".trblazeui",
            ".techierag", ".artifacts"}
    seen = 0
    for root, dirs, files in os.walk("."):
        dirs[:] = sorted(d for d in dirs if d not in skip)
        for fn in sorted(files):
            if not fn.endswith((".csproj", ".props")):
                continue
            seen += 1
            p = os.path.join(root, fn)
            if re.search(r'Include="[^"]*\bTrBlazeUI[\w.]*(?:\.csproj)?"', read(p), re.I):
                return "trblazeui", f"{os.path.relpath(p)} references TrBlazeUI"
    if seen:
        return "builder", f"none of the {seen} .csproj/.props file(s) references TrBlazeUI"
    arch = os.path.join("docs", f"{app}-Architecture.md")
    if os.path.isfile(arch) and re.search(r"\bTrBlazeUI\b", read(arch)):
        return "trblazeui", f"no project file yet; {arch} names TrBlazeUI"
    return "builder", "no project file yet, and the Architecture document does not name TrBlazeUI"


def usage_guide(app):
    """The guide the project really has, UsageGuide or Usage-Guide: tf-verify-list.py's reader. The prompt
    named the first spelling only, a file AppManager does not have (TF-022). tests/regression/run.sh am_022."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("tf_verify_list", os.path.join(os.path.dirname(os.path.abspath(__file__)), "tf-verify-list.py"))
    vl = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(vl)
    return vl.usage_guide(app)


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
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import tf_roadmap
    import tf_defect
    marked = tf_roadmap.ids(text)
    roadmap = [r for r in rows if r["id"].upper() in marked and r["status"] not in TERMINAL | BLOCKED]

    fix_rows = [r for r in rows if r["status"] in FIX and r not in roadmap]
    open_rows = [r for r in rows if r["status"] not in TERMINAL | BLOCKED and r not in roadmap]
    # Repair before new work, but never INSTEAD of it. A row can sit at `Needs re-verify`
    # permanently -- TfLens REQ-FN-067 and -070 need a repository that emits events.ndjson
    # and none exists, so every honest verify run re-confirms that gate rather than clearing
    # it. FIX used to win outright, which pinned the mode forever: the twelve rows a later
    # *amend-docs added were never once printed, and a pass that trusted the working list
    # would have met build-phase's ending condition with twelve requirements at 0%.
    # So the working list is every open row, and FIX only says which ones come first.
    # tests/regression/run.sh tf_019.
    if fix_rows:
        rest = [r for r in open_rows if r not in fix_rows]
        mode, work = "FIX", fix_rows + rest
    elif open_rows:
        mode, work = "FRESH", open_rows
    else:
        mode, work = "NOTHING", []
    # A row in FIX mode is on the list for a defect its acceptance line rarely names; a builder given
    # only that line finds the row working and fixes nothing (AppManager TF-020). The defect rides with
    # the row: its ⚠ clauses, else a FAIL/PARTIAL row's whole Remarks. tests/regression/run.sh am_020.
    for r in rows:
        r["defects"] = (tf_defect.clauses(r["remarks"]) or ([r["remarks"]] if r["status"] in {"fail", "partial"}
                        and r["remarks"] else [])) if r in fix_rows else []
    terminal = sum(1 for r in rows if r["status"] in TERMINAL)
    blocked = [r for r in rows if r["status"] in BLOCKED]
    print(f"# tf-build-list — {app} — {cl} — phase {phase}")
    print(f"Mode: {mode} — {len(work)} row(s) to build; {terminal} terminal, {len(blocked)} Blocked, "
          f"{len(roadmap)} roadmap, {len(rows)} total"
          + (f" — {', '.join(r['id'] for r in work[:8])}{' …' if len(work) > 8 else ''}" if work else ""))
    # Every row is in exactly one of the five counts, and the arithmetic is printed so a
    # reader can check it rather than trust it. A row missing from all of them is the
    # failure this line exists to make impossible.
    if len(work) + terminal + len(blocked) + len(roadmap) != len(rows):
        print(f"⚠ {len(rows) - len(work) - terminal - len(blocked) - len(roadmap)} row(s) are in no category — "
              "the checklist carries a status this script does not know; fix the row or the script")
    if roadmap:
        print("Roadmap, not in this phase's scope (not built; the owner moves them with *amend-docs): "
              + ", ".join(r["id"] for r in roadmap))
    if fix_rows and len(work) > len(fix_rows):
        print(f"Order: {len(fix_rows)} failing row(s) first ({', '.join(r['id'] for r in fix_rows)}), "
              f"then {len(work) - len(fix_rows)} not yet started")
    if blocked:
        print("Blocked (library gaps, pass through unless the feedback entry is resolved): " + ", ".join(r["id"] for r in blocked))
    if not work:
        print("Nothing to build. Run the status gate; the next command is the verifier's or the owner's.")
        return 0

    clusters = {}
    builder = dict(BUILDER)
    if any(r["id"].upper().startswith("REQ-UI-") for r in work):
        builder["UI"], why = ui_builder(app)
        print(f"UI rows go to: {builder['UI']} — {why}")
    for r in work:
        sec, acc, mock, brd = ent.get(r["id"].upper(), ("Other", "", "", ""))
        cls = re.match(r"REQ-(UI|FN|RAG|NFR)-", r["id"]).group(1)
        key = ("Non-functional" if cls == "NFR" else "RAG" if cls == "RAG" else sec, builder[cls])
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
            for x in r["defects"]:
                print(f"    Defect: {x}")
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
    guide = usage_guide(app)
    for label, sec, builder, items in named:
        lines = []
        for r, acc, mock, brd in items:
            lines.append(f"- {r['id']} — {r['title']}" + (f" ({brd})" if brd else ""))
            lines.append(f"  Acceptance: {acc or 'MISSING — refuse the row and report it'}")
            lines.extend(f"  Defect: {x}" for x in r["defects"])
            if mock:
                lines.append(f"  Mockup: {mock}")
        if any(r["defects"] for r, *_ in items):
            lines.append("\nA row with a Defect line is on this list for that defect. Fix every one at the file and "
                         "line it names, keep the acceptance line true, and replace the row's Remarks: a row that "
                         "already passes its acceptance line is not done while its defect stands.")
        mocks = sorted({m for _r, _a, m, _b in items if m})
        body = (tpl.replace("{App}", app).replace("{Cluster}", label).replace("{Builder}", builder)
                .replace("{Section}", sec).replace("{Rows}", "\n".join(lines))
                .replace("{Mockups}", ", ".join(mocks) if mocks else "none (not a UI cluster)")
                .replace("{Checklist}", cl).replace("{UsageGuide}", guide))
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

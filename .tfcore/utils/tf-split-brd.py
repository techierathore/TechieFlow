#!/usr/bin/env python3
"""tf-split-brd.py — draft docs/<App>-Checklist.md from the BRD ledger (see tf-split-brd.sh).

    bash .tfcore/utils/tf-split-brd.sh <App>                # write the checklist (refuses if one exists)
    bash .tfcore/utils/tf-split-brd.sh <App> --force        # overwrite an existing checklist
    bash .tfcore/utils/tf-split-brd.sh <App> --add-missing  # append rows only for BRD items with no row yet
    bash .tfcore/utils/tf-split-brd.sh <App> --phase 2      # a later phase of a Large project
    bash .tfcore/utils/tf-split-brd.sh <App> --all-phases   # every phase in docs/<App>-Phases.md

Large projects (docs/TechieFlow-Document-Schemas.md §2): phase 1 is docs/<App>-BRD.md and
docs/<App>-Checklist.md; phase n is docs/<App>-Pn-BRD.md and docs/<App>-Pn-Checklist.md. Without
--phase the phase comes from appPhase in .tfcore/core-config.yaml (1 when absent). REQ numbers run
on across phases: a new checklist starts each prefix after the highest number in every other
phase's checklist, so an id is never reused.

Reads docs/<App>-BRD.md: the header (App, Size), the Screens and flow table (screen, route),
every `**BRD-N**` ledger item with its title, screen, mockup link and acceptance line, and
the Non-functional table. Writes the checklist in the template shape: header, Goal, the one
Requirements Status table, then one section per screen holding the detail entries, plus
"RAG / AI requirements" and "Non-functional". Acceptance and perf-budget lines are copied
verbatim; an item without one gets a TODO line the checker will refuse, never an invented one.

Class is guessed, and the agent corrects it: Non-functional table -> REQ-NFR; text about
embeddings, vectors, prompts, chat or a model -> REQ-RAG; text about what a screen shows
(page, screen, list, form, dialog, button, menu, layout, theme, displays, shows) -> REQ-UI;
everything else -> REQ-FN. Exit 0 written, 1 refused, 2 could not run.
"""
import os
import re
import sys

RAG_WORDS = re.compile(r"\b(embedding|embeddings|vector|rag\b|prompt template|llm|language model|retriev|semantic search|chatbot|chat completion)", re.I)
UI_WORDS = re.compile(r"\b(page|screen|list|lists|form|dialog|button|menu|layout|theme|display|displays|shows|shown|grid|table|card|panel|tab|tabs|badge|icon|responsive|mobile)\b", re.I)
STATUS_LINE = ("**Status values:** `Not Started` · `In Progress` · `Implemented` · `Verified` · `Done (pre-existing)` · "
               "`Needs re-verify` · `PARTIAL` · `FAIL` · `Blocked` · `Owner-UAT` · `N/A`.")


def die(msg, code=2):
    print(f"tf-split-brd: {msg}", file=sys.stderr)
    sys.exit(code)


def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def header_field(text, name):
    m = re.search(rf"(?im)^\|\s*{re.escape(name)}\s*\|\s*([^|]+?)\s*\|", text)
    return m.group(1).strip() if m else ""


def section(text, name):
    m = re.search(rf"(?ms)^##\s+(?:\d+[.)]\s*)?{name}[^\n]*\n(.*?)(?=^## |\Z)", text)
    return m.group(1) if m else ""


def screens(text):
    """[(name, route)] from the Screens and flow table; dialog rows are skipped."""
    out = []
    for line in section(text, "Screens and flow").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2 or cells[0].lower() in ("screen", "") or set(cells[0]) <= set("-: "):
            continue
        route = cells[1].strip("` ")
        if route.lower().startswith("on "):
            continue
        out.append((cells[0].strip("`* "), route))
    return out


def ledger(text):
    """Every **BRD-N** item: id, title, screen, mockup, acceptance, perf, section name."""
    items = []
    nfr_ids = set()
    for line in section(text, "Non-functional requirements").splitlines():
        m = re.match(r"^\s*\|\s*`?\**(BRD-\d+)", line)
        if m:
            nfr_ids.add(m.group(1))
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            title = cells[2] if len(cells) > 2 else cells[-1]
            measure = cells[3] if len(cells) > 3 else ""
            items.append({"id": m.group(1), "title": title.strip("`* "), "screen": "", "mockup": "",
                          "acceptance": "", "perf": measure if "perf-budget" in measure.lower() else "", "nfr": True})
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        # The anchor is not decoration: a BRD's §9 screen inventory links to each item as
        # [BRD-21](#brd-21), markdown generates no id for bold text inside a list item, and
        # tf-doc-check refuses a broken link -- so a real BRD carries `<a id="brd-N"></a>`
        # here and this regex matched NONE of TfLens's 179 items. tests/regression tf_017.
        m = re.match(r"^\s*[-*]\s*(?:<a id=[\"\']?[^\"\'>]*[\"\']?\s*>\s*</a>\s*)?"
                     r"\*\*(BRD-\d+)\*\*\s*[—:-]+\s*(.*)$", lines[i])
        if m and m.group(1) not in nfr_ids:
            rid, rest = m.group(1), m.group(2)
            title = re.split(r"\s*(?:\.\s+\*|\s\*Screen|\s·\s\*|\s\*Mockup)", rest, 1)[0].strip().rstrip(".")
            sm = re.search(r"\*Screen:\*\s*([^·*\n]+)", rest)
            mm = re.search(r"\(((?:\./|docs/)?mockups/[^)\s]+)\)", rest) or re.search(r"((?:docs/)?mockups/[\w./-]+\.html)", rest)
            acc = perf = ""
            j = i + 1
            while j < len(lines) and (lines[j].startswith("  ") or lines[j].strip() == ""):
                if re.search(r"\*Acceptance:?\*|^\s*[-*]\s*Acceptance:", lines[j], re.I):
                    acc = re.sub(r"^\s*[-*]\s*\*?Acceptance:?\*?:?\s*", "", lines[j]).strip()
                pm = re.search(r"perf-budget:[^\n|]+", lines[j], re.I)
                if pm:
                    perf = pm.group(0).strip()
                if lines[j].strip() == "" and j + 1 < len(lines) and not lines[j + 1].startswith("  "):
                    break
                j += 1
            items.append({"id": rid, "title": title, "screen": sm.group(1).strip() if sm else "",
                          "mockup": mm.group(1) if mm else "", "acceptance": acc, "perf": perf, "nfr": False})
        i += 1
    return [it for it in items if not it["nfr"]] + [it for it in items if it["nfr"]]


def classify(it):
    if it["nfr"]:
        return "NFR"
    blob = it["title"] + " " + it["acceptance"]
    if RAG_WORDS.search(blob):
        return "RAG"
    if UI_WORDS.search(blob):
        return "UI"
    return "FN"


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def entry(req, it):
    mock = f" · *Mockup:* {it['mockup'].replace('docs/', '')}" if it["mockup"] else ""
    acc = it["acceptance"] or "TODO — write: When <actor> <does what> on <screen>, then <a result a browser robot can observe>"
    if it["perf"] and it["perf"].lower() not in acc.lower():
        acc = acc.rstrip(".") + "; " + it["perf"]
    return (f'<a id="d-{req.lower()}"></a>\n- **{req}** — {it["title"]}. *BRD:* {it["id"]}{mock}\n'
            f"  - *Acceptance:* {acc}\n")


def config_phase():
    """appPhase from .tfcore/core-config.yaml; 1 when absent or null."""
    p = os.path.join(".tfcore", "core-config.yaml")
    if os.path.isfile(p):
        m = re.search(r"(?m)^appPhase:\s*(\d+)", read(p))
        if m:
            return int(m.group(1))
    return 1


def phase_names(app, phase):
    """(BRD path, checklist path) for a phase: plain names for phase 1, App-Pn- otherwise."""
    pfx = f"{app}-" if phase <= 1 else f"{app}-P{phase}-"
    return os.path.join("docs", f"{pfx}BRD.md"), os.path.join("docs", f"{pfx}Checklist.md")


def phases_listed(app):
    """Phase numbers from the Phases table of docs/<App>-Phases.md, in order."""
    p = os.path.join("docs", f"{app}-Phases.md")
    if not os.path.isfile(p):
        die(f"{p} does not exist; --all-phases needs the Phases document")
    nums = []
    for line in section(read(p), "Phases").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0].strip("`* ").isdigit():
            nums.append(int(cells[0].strip("`* ")))
    if not nums:
        die(f"{p} has no numbered rows in its Phases table")
    return nums


def other_phase_counters(app, own_cl, below=None):
    """Highest REQ number per prefix across the other phases' checklists, so ids run on.
    below=n counts only phases under n (an --all-phases run, which rewrites them in order);
    otherwise every other phase counts, so a single-phase run can never reuse an id."""
    counters = {"UI": 0, "FN": 0, "RAG": 0, "NFR": 0}
    if not os.path.isdir("docs"):
        return counters
    for f in os.listdir("docs"):
        m = re.fullmatch(rf"{re.escape(app)}(?:-P(\d+))?-Checklist\.md", f)
        if not m or os.path.join("docs", f) == own_cl:
            continue
        if below is not None and int(m.group(1) or 1) >= below:
            continue
        for r in re.finditer(r"REQ-(UI|FN|RAG|NFR)-(\d{3})", read(os.path.join("docs", f))):
            counters[r.group(1)] = max(counters[r.group(1)], int(r.group(2)))
    return counters


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    app = argv[1]
    force = "--force" in argv
    add_missing = "--add-missing" in argv
    phase = None
    if "--phase" in argv:
        i = argv.index("--phase")
        if i + 1 >= len(argv) or not argv[i + 1].isdigit() or int(argv[i + 1]) < 1:
            die("--phase needs a number from 1 upwards")
        phase = int(argv[i + 1])
    if "--all-phases" in argv:
        rc = 0
        for n in phases_listed(app):
            rc = max(rc, run(app, n, force, add_missing, in_order=True))
        return rc
    return run(app, phase if phase else config_phase(), force, add_missing)


def run(app, phase, force, add_missing, in_order=False):
    brd_p, cl_p = phase_names(app, phase)
    if not os.path.isfile(brd_p):
        die(f"{brd_p} does not exist" + (f" (phase {phase}; phase 1 is docs/{app}-BRD.md)" if phase > 1 else ""))
    brd = read(brd_p)
    items = ledger(brd)
    if not items:
        die(f"{brd_p} has no **BRD-N** items in its Requirements section")
    scr = screens(brd)
    routes = {s.lower(): r for s, r in scr}
    size = header_field(brd, "Size") or "Small"
    phase_label = header_field(brd, "Phase")

    existing = read(cl_p) if os.path.isfile(cl_p) else ""
    if existing and not force and not add_missing:
        die(f"{cl_p} already exists; use --add-missing to append rows for new BRD items, or --force to rewrite", 1)
    # A BRD item already has a row when any row names it: on its `*BRD:*` detail line, or anywhere on
    # its status-table line. The table form used to be read only as a bracket holding exactly one id,
    # so "(BRD-76, Phase 3)" and "(BRD-118, BRD-120, Phase 3)" were invisible and --add-missing
    # appended 44 rows to TfLens phase 3 for 13 new items, 31 of them copies of Verified rows (TF-025).
    mapped = {b for line in re.findall(r"(?m)^.*\*BRD:\*.*$", existing) for b in re.findall(r"BRD-\d+", line)}
    mapped |= {b for row in re.findall(r"(?m)^\|\s*REQ-.*$", existing) for b in re.findall(r"BRD-\d+", row)}
    counters = other_phase_counters(app, cl_p, below=phase if in_order else None)
    if add_missing:
        for m in re.finditer(r"REQ-(UI|FN|RAG|NFR)-(\d{3})", existing):
            counters[m.group(1)] = max(counters[m.group(1)], int(m.group(2)))
    new_counts = {"UI": 0, "FN": 0, "RAG": 0, "NFR": 0}

    rows, entries = [], {}
    for it in items:
        if add_missing and it["id"] in mapped:
            continue
        cls = classify(it)
        counters[cls] += 1
        new_counts[cls] += 1
        req = f"REQ-{cls}-{counters[cls]:03d}"
        rows.append(f"| {req} | {it['title']} | Not Started | 0% | — | [view](#d-{req.lower()}) |")
        key = ("Non-functional" if cls == "NFR" else "RAG / AI requirements" if cls == "RAG"
               else (it["screen"] or "Other"))
        entries.setdefault(key, []).append(entry(req, it))

    if add_missing and existing:
        if not rows:
            print(f"tf-split-brd: every BRD item already has a row in {cl_p}; nothing to add")
            return 0
        text = existing
        m = re.search(r"(?ms)^## Requirements Status\s*\n.*?(?=^## |\Z)", text)
        if not m:
            die(f"{cl_p} has no Requirements Status section")
        tbl_end = m.end()
        # insert rows after the last table row of the status table
        seg = text[m.start():tbl_end]
        last_row = list(re.finditer(r"(?m)^\|\s*REQ-[^\n]*$", seg))
        if last_row:
            pos = m.start() + last_row[-1].end()
            text = text[:pos] + "\n" + "\n".join(rows) + text[pos:]
        for key, ents in entries.items():
            hm = re.search(rf"(?ms)^##\s+(?:Page:\s*)?{re.escape(key)}\b[^\n]*\n.*?(?=^## |\Z)", text)
            block = "\n".join(ents)
            if hm:
                text = text[:hm.end()].rstrip("\n") + "\n\n" + block + "\n" + text[hm.end():]
            else:
                heading = key if key in ("Non-functional", "RAG / AI requirements") else f"Page: {key}" + (f" (`{routes[key.lower()]}`)" if key.lower() in routes else "")
                text = text.rstrip("\n") + f"\n\n## {heading}\n\n{block}\n"
        with open(cl_p, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"tf-split-brd: appended {len(rows)} row(s) to {cl_p}: " + ", ".join(r.split("|")[1].strip() for r in rows))
        return 0

    goal = re.sub(r"\s+", " ", section(brd, "Summary").strip().split("\n\n")[0]).strip() or f"Build {app} as the BRD describes."
    title = f"# {app} — Checklist" + (f" (phase {phase})" if phase_label else "")
    out = [title, "", "| | |", "|---|---|", f"| App | {app} |", f"| Size | {size} |"]
    if phase_label:
        out.append(f"| Phase | {phase_label} |")
    out += ["", "## Goal", "", goal + (" This checklist is the whole work list of this phase." if phase_label else " This single checklist is the whole work list."), "",
           "## Requirements Status", "",
           "| ID | Requirement | Status | % | Remarks | Details |", "|----|-------------|--------|---|---------|---------|"]
    out += rows
    out += ["", STATUS_LINE, ""]
    ordered = [s for s, _ in scr if s in entries] + [k for k in entries if k not in dict(scr) and k not in ("RAG / AI requirements", "Non-functional")]
    for key in ordered:
        route = routes.get(key.lower(), "")
        out.append(f"## Page: {key}" + (f" (`{route}`)" if route else ""))
        out.append("")
        out.append("\n".join(entries[key]))
    for key in ("RAG / AI requirements", "Non-functional"):
        if key in entries:
            out += [f"## {key}", "", "\n".join(entries[key])]
    with open(cl_p, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out).rstrip("\n") + "\n")
    n = {k: v for k, v in new_counts.items() if v}
    todo = sum(1 for it in items if not it["acceptance"] and not it["nfr"])
    print(f"tf-split-brd: wrote {cl_p}: {len(rows)} rows (" + ", ".join(f"{k} {v}" for k, v in n.items()) + f"), {len(ordered)} screen section(s)"
          + (f"; {todo} item(s) had no acceptance line and carry a TODO the checker will refuse" if todo else ""))
    print("tf-split-brd: correct any class the guess got wrong, then run: bash .tfcore/utils/tf-doc-check.sh --app " + app)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as e:
        die(str(e))

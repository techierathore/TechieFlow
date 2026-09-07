#!/usr/bin/env python3
"""tf-verify-list.py — the working list of a verify run (see tf-verify-list.sh).

    bash .tfcore/utils/tf-verify-list.sh <App> <scope> [--phase N] [--json-out <file>]

scope: ui (REQ-UI rows) · functional (REQ-FN, REQ-NFR, REQ-RAG) · all · a comma list of ids.
Reads the phase's checklist, the UIDesign, the BRD screens table and the UsageGuide, and prints:
  - every row in scope with its status, acceptance line, screen, route, mockup and perf budget;
    N/A rows are skipped, every other status is graded (a Verified row is re-confirmed)
  - the screens to drive, each with its route, its mockup and the rows it owns; a dialog row
    is listed under its parent screen (Schemas §2: a dialog is verified on its page)
  - rows whose screen could not be resolved (graded by their test only)
  - the test users from the UsageGuide
Writes the same as JSON (default tests/.artifacts/verify/list.json) for the other verify scripts.
Python 3 standard library only. Exit 0 printed, 2 could not run.
"""
import json
import os
import re
import sys

NA = {"n/a"}


def die(msg):
    print(f"tf-verify-list: {msg}", file=sys.stderr)
    sys.exit(2)


def read(p):
    with open(p, encoding="utf-8-sig", errors="replace") as f:
        return f.read()


def cfg(key, default):
    p = os.path.join(".tfcore", "core-config.yaml")
    if os.path.isfile(p):
        m = re.search(rf"(?m)^{key}:\s*(\S+)", read(p))
        if m and m.group(1) not in ("null", "~"):
            return m.group(1).strip("'\"")
    return default


def norm_status(s):
    s = s.strip().strip("`* ").lower()
    return re.sub(r"\s*\(.*$", "", s).strip()


def norm_name(s):
    s = re.sub(r"\(.*?\)", "", s or "")           # "Today (home)" -> "Today"
    s = re.sub(r"\b(screen|page|dialog)\b", "", s, flags=re.I)
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def rows_of(text):
    rows = []
    for line in text.splitlines():
        if re.match(r"^\s*\|\s*`?REQ-", line):
            c = [x.strip() for x in line.strip().strip("|").split("|")]
            if len(c) >= 3:
                rid = c[0].strip("`* ").upper()
                pct = re.sub(r"[^0-9]", "", c[3]) if len(c) > 3 else ""
                rows.append({"id": rid, "class": re.match(r"REQ-([A-Z]+)-", rid).group(1) if re.match(r"REQ-([A-Z]+)-", rid) else "FN",
                             "title": c[1].strip("`* "), "status_raw": c[2].strip(), "status": norm_status(c[2]),
                             "pct": int(pct) if pct.isdigit() else None, "remarks": c[4] if len(c) > 4 else ""})
    return rows


def entries_of(text):
    """id -> {section, acceptance, mockup, brd, perf_budget}"""
    out, current = {}, ""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r"^##\s+(.+)$", line)
        if m:
            current = re.sub(r"^(?:page|screen)\s*:\s*", "", m.group(1).strip(), flags=re.I)
            continue
        a = re.search(r"<a id=['\"]d-(req-[a-z]+-\d+)['\"]", line, re.I)
        if a:
            rid = a.group(1).upper()
            e = {"section": current, "acceptance": "", "mockup": "", "brd": "", "perf_budget": ""}
            for j in range(i, min(i + 14, len(lines))):
                l = lines[j]
                if re.search(r"\*Acceptance:?\*|^\s*[-*]\s*Acceptance:", l, re.I) and not e["acceptance"]:
                    e["acceptance"] = re.sub(r"^\s*[-*]\s*\*?Acceptance:?\*?:?\s*", "", l).strip()
                mm = re.search(r"((?:docs/)?mockups/[\w./-]+\.html)", l)
                if mm and not e["mockup"]:
                    e["mockup"] = mm.group(1) if mm.group(1).startswith("docs/") else "docs/" + mm.group(1)
                bm = re.search(r"BRD-\d+", l)
                if bm and not e["brd"]:
                    e["brd"] = bm.group(0)
                pb = re.search(r"perf-budget:\s*([^|`]+)", l)
                if pb and not e["perf_budget"]:
                    e["perf_budget"] = pb.group(1).strip()
                if j > i and re.match(r"^\s*(?:[-*]\s*)?<a id=|^## ", l):
                    break   # the next entry starts: nothing below belongs to this row
            out[rid] = e
    return out


def screens_of_uidesign(path):
    """[{name, route, mockup}] from '### Screen: Name (/route)' sections."""
    out = []
    if not os.path.isfile(path):
        return out
    txt = read(path)
    parts = re.split(r"(?m)^(?=###\s+Screen:)", txt)
    for p in parts:
        m = re.match(r"###\s+Screen:\s*(.+?)\s*\(`?([^)`]+)`?\)\s*$", p.splitlines()[0] if p.strip() else "")
        if not m:
            continue
        mk = re.search(r"((?:docs/)?mockups/[\w./-]+\.html)", p)
        mock = mk.group(1) if mk else ""
        if mock and not mock.startswith("docs/"):
            mock = "docs/" + mock
        out.append({"name": m.group(1).strip(), "route": m.group(2).strip(), "mockup": mock})
    return out


def dialogs_of_brd(path):
    """name -> parent route, from the BRD screens table rows whose Route cell reads 'on /route'."""
    out = {}
    if not os.path.isfile(path):
        return out
    for line in read(path).splitlines():
        if not line.startswith("|"):
            continue
        c = [x.strip().strip("`* ") for x in line.strip().strip("|").split("|")]
        if len(c) >= 2 and re.match(r"(?i)^on\s+/", c[1]):
            out[norm_name(c[0])] = re.sub(r"(?i)^on\s+", "", c[1]).strip()
    return out


def test_users(path):
    users = []
    if not os.path.isfile(path):
        return users
    m = re.search(r"(?ms)^##\s+(?:\d+[.)]\s*)?Test users[^\n]*\n(.*?)(?=^## |\Z)", read(path))
    if not m:
        return users
    for line in m.group(1).splitlines():
        c = [x.strip().strip("`* ") for x in line.strip().strip("|").split("|")]
        if len(c) >= 4 and c[0].isdigit():
            users.append({"user": c[1], "password_source": c[2], "role": c[3]})
    return users


def in_scope(rid, scope):
    s = scope.strip().lower()
    if s == "all":
        return True
    if s == "ui":
        return rid.startswith("REQ-UI-")
    if s == "functional":
        return rid.startswith(("REQ-FN-", "REQ-NFR-", "REQ-RAG-"))
    ids = {x.strip().upper() for x in re.split(r"[,\s]+", scope) if x.strip()}
    return rid in ids


def screen_from_acceptance(acc):
    """'When the user taps Save on Entry Editor, then ...' -> 'Entry Editor'."""
    if not acc:
        return ""
    head = re.split(r",\s*then\b|\bthen\b", acc, maxsplit=1)[0]
    hits = re.findall(r"\bon\s+(?:the\s+)?([A-Z][\w'()/&-]*(?:\s+[\w'()/&-]+){0,4}?)(?=\s*(?:,|$|\s+(?:and|with|for|then)\b))", head)
    return hits[-1].strip() if hits else ""


def main(argv):
    if len(argv) < 3 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    app, scope = argv[1], argv[2]
    phase = int(cfg("appPhase", "1"))
    if "--phase" in argv:
        phase = int(argv[argv.index("--phase") + 1])
    out_path = os.path.join("tests", ".artifacts", "verify", "list.json")
    if "--json-out" in argv:
        out_path = argv[argv.index("--json-out") + 1]
    pfx = f"{app}-" if phase <= 1 else f"{app}-P{phase}-"
    cl = os.path.join("docs", f"{pfx}Checklist.md")
    if not os.path.isfile(cl):
        die(f"{cl} does not exist")
    text = read(cl)
    rows = rows_of(text)
    if not rows:
        die(f"{cl} has no REQ rows")
    ent = entries_of(text)
    screens = screens_of_uidesign(os.path.join("docs", f"{pfx}UIDesign.md"))
    dialogs = dialogs_of_brd(os.path.join("docs", f"{pfx}BRD.md"))
    users = test_users(os.path.join("docs", f"{app}-UsageGuide.md"))
    by_name = {norm_name(s["name"]): s for s in screens}
    by_mock = {s["mockup"]: s for s in screens if s["mockup"]}
    by_route = {s["route"].lower(): s for s in screens}

    work, skipped, unresolved = [], 0, []
    for r in rows:
        if not in_scope(r["id"], scope):
            continue
        if r["status"] in NA:
            skipped += 1
            continue
        e = ent.get(r["id"], {"section": "", "acceptance": "", "mockup": "", "brd": "", "perf_budget": ""})
        row = dict(r, acceptance=e["acceptance"], mockup=e["mockup"], brd=e["brd"], perf_budget=e["perf_budget"],
                   section=e["section"], screen="", route="", dialog="")
        cand = [screen_from_acceptance(e["acceptance"]), e["section"], r["title"]]
        for c in cand:
            n = norm_name(c)
            if not n:
                continue
            if n in by_name:
                row["screen"], row["route"] = by_name[n]["name"], by_name[n]["route"]
                break
            if n in dialogs and dialogs[n].lower() in by_route:
                s = by_route[dialogs[n].lower()]
                row["screen"], row["route"], row["dialog"] = s["name"], s["route"], c.strip()
                break
        if not row["screen"] and e["mockup"] in by_mock:
            s = by_mock[e["mockup"]]
            row["screen"], row["route"] = s["name"], s["route"]
        if not row["screen"] and row["class"] != "NFR":
            unresolved.append(row["id"])
        work.append(row)

    screen_list = []
    for s in screens:
        owned = [r["id"] for r in work if r["screen"] == s["name"]]
        if owned:
            screen_list.append(dict(s, rows=owned))

    print(f"# tf-verify-list — {app} — {cl} — phase {phase} — scope {scope}")
    counts = {}
    for r in work:
        counts[r["status_raw"] or "?"] = counts.get(r["status_raw"] or "?", 0) + 1
    print(f"Rows to grade: {len(work)} ({', '.join(f'{v} {k}' for k, v in sorted(counts.items()))}); {skipped} N/A skipped; {len(rows)} in the checklist")
    if not work:
        print("NOTHING: no row in scope. Run the status gate and stop.")
    print()
    print(f"## Screens to drive ({len(screen_list)} of {len(screens)} in the UIDesign)")
    for s in screen_list:
        print(f"- {s['name']} ({s['route']}) — mockup {s['mockup'] or 'none'} — rows {', '.join(s['rows'])}")
    print()
    print("## Rows")
    for r in work:
        where = f"{r['screen']} {r['route']}" + (f" — dialog {r['dialog']}" if r["dialog"] else "") if r["screen"] else "no screen resolved"
        extra = f" — perf-budget: {r['perf_budget']}" if r["perf_budget"] else ""
        print(f"- {r['id']} [{r['status_raw']}] {r['title']} — {where}{extra}")
        print(f"    acceptance: {r['acceptance'] or 'MISSING — the row cannot be graded; fix the checklist'}")
    if unresolved:
        print()
        print(f"## No screen resolved ({len(unresolved)}): graded by their test only — " + ", ".join(unresolved))
    print()
    print("## Test users (UsageGuide)")
    for u in users:
        print(f"- {u['user']} — {u['role']} — password: {u['password_source']}")
    if not users:
        print("- none in the UsageGuide: the smoke policy says what to do")

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"app": app, "scope": scope, "phase": phase, "kind": cfg("appKind", "app"), "checklist": cl,
                   "rows": work, "screens": screen_list, "unresolved": unresolved, "test_users": users,
                   "skipped_na": skipped, "total": len(rows)}, f, indent=1)
    print()
    print(f"JSON: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

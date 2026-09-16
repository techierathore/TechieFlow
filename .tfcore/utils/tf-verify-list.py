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
        # a heading one level down (`### Page: …` under `## UI / Pages`) names the section too, and any
        # other one (`### Cross-page: …`) ends the page above it
        m = re.match(r"^#{2,3}\s+(.+)$", line)
        if m:
            current = re.sub(r"^(?:page|screen)\s*:\s*", "", m.group(1).strip(), flags=re.I)
            continue
        a = re.search(r"<a id=['\"]d-(req-[a-z]+-\d+)['\"]", line, re.I)
        if a:
            rid = a.group(1).upper()
            # an anchor written above its own page heading belongs to that page, not the one before
            # (AppManager's older entries: `<a id>` then `### Page:` then the row)
            nxt = next((l for l in lines[i + 1:i + 3] if l.strip()), "")
            h = re.match(r"^#{2,3}\s+(?:page|screen)\s*:\s*(.+)$", nxt, re.I)
            if h:
                current = h.group(1).strip()
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


def screens_of_checklist(text, ent):
    """[{name, route, mockup}] from the checklist's own '## Page: Name (`/route`, …)' headings, at ## or
    ###, for a project with no UIDesign: the first route that can be opened as typed (no `{id}`),
    the mockup from the first entry under the heading. A heading with no such route names no screen.
    Without this every UI row of such a project was graded by its test only (AppManager TF-016)."""
    out, seen = [], set()
    for line in text.splitlines():
        m = re.match(r"^#{2,3}\s+(?:page|screen)\s*:\s*(.+?)\s*\((.*)\)\s*$", line, re.I)
        if not m or norm_name(m.group(1)) in seen:
            continue
        inner = m.group(2)
        cands = re.findall(r"`([^`]+)`", inner) or re.split(r"\s*,\s*", inner)
        route = next((c.strip() for c in cands if c.strip().startswith("/") and "{" not in c and " " not in c.strip()), "")
        if not route:
            continue
        section = re.sub(r"^#+\s+(?:page|screen)\s*:\s*", "", line.strip(), flags=re.I)
        mock = next((e["mockup"] for e in ent.values() if e["section"] == section and e["mockup"]), "")
        seen.add(norm_name(m.group(1)))
        out.append({"name": m.group(1).strip(), "route": route, "mockup": mock, "section": section})
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


def usage_guide(app):
    """docs/{App}-UsageGuide.md, or docs/{App}-Usage-Guide.md: the two spellings tf-doc-check.py
    accepts. Only the first was looked for, so AppManager's guide read as having no test users
    (AppManager TF-009)."""
    for name in (f"{app}-UsageGuide.md", f"{app}-Usage-Guide.md"):
        p = os.path.join("docs", name)
        if os.path.isfile(p):
            return p
    return os.path.join("docs", f"{app}-UsageGuide.md")


def test_users(path):
    """The rows of the guide's Test users table. The heading may sit at ## or ### (a guide that
    numbers its chapters nests it one level down), and the table may be the template's
    `| # | User | Password source | Role |` or any table whose header names a user or email column
    and a role column, read by those names (AppManager TF-009)."""
    users = []
    if not os.path.isfile(path):
        return users
    m = re.search(r"(?ms)^#{2,3}\s+(?:\d+[.)]\s*)?Test users[^\n]*\n(.*?)(?=^#{1,3} |\Z)", read(path))
    if not m:
        return users
    cols = None
    for line in m.group(1).splitlines():
        if not line.strip().startswith("|"):
            continue
        c = [x.strip().strip("`* ") for x in line.strip().strip("|").split("|")]
        if cols is None:
            low = [x.lower() for x in c]
            def col(*names):
                return next((i for i, h in enumerate(low) if any(n in h for n in names)), None)
            cols = {"user": col("user", "email", "login", "account"), "pw": col("password", "secret"), "role": col("role")}
            if cols["user"] is None or cols["role"] is None:
                cols = {"user": 1, "pw": 2, "role": 3}      # the template's numbered shape
            continue
        if set("".join(c)) <= set("-: "):
            continue                                        # the header rule
        if len(c) > max(cols["user"], cols["role"]) and c[cols["user"]] and not c[cols["user"]].isdigit():
            users.append({"user": c[cols["user"]],
                          "password_source": c[cols["pw"]] if cols["pw"] is not None and len(c) > cols["pw"] else "",
                          "role": c[cols["role"]]})
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
    screens, source = screens_of_uidesign(os.path.join("docs", f"{pfx}UIDesign.md")), "UIDesign"
    if not screens:
        screens, source = screens_of_checklist(text, ent), "checklist's Page headings"
    dialogs = dialogs_of_brd(os.path.join("docs", f"{pfx}BRD.md"))
    users = test_users(usage_guide(app))
    by_name = {norm_name(s["name"]): s for s in screens}
    by_mock = {s["mockup"]: s for s in screens if s["mockup"]}
    by_route = {s["route"].lower(): s for s in screens}
    by_section = {s["section"]: s for s in screens if s.get("section")}

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
        if e["section"] in by_section:     # a screen read from the checklist: the heading the row sits under
            s = by_section[e["section"]]
            row["screen"], row["route"] = s["name"], s["route"]
            cand = []
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
    print(f"## Screens to drive ({len(screen_list)} of {len(screens)} in the {source})")
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
                   "rows": work, "screens": screen_list, "screens_source": source, "unresolved": unresolved, "test_users": users,
                   "skipped_na": skipped, "total": len(rows)}, f, indent=1)
    print()
    print(f"JSON: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

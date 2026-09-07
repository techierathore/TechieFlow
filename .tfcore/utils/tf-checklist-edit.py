#!/usr/bin/env python3
"""tf-checklist-edit.py — the checklist edits the bug scripts share (Sitting 4c, 2026-09-06).

Imported by tf-triage.py and tf-log-miss.py; not run on its own. Every function takes the
checklist path, edits the file in place and returns what it did. The shapes follow
docs/TechieFlow-Document-Schemas.md §3.4: the six-cell row, the `<a id="d-req-…">` entry, one
acceptance line, a Remarks cell of at most 60 words.
"""
import datetime
import os
import re

ROW = re.compile(r"^(\s*\|\s*`?)(REQ-[A-Z]+-\d+)(`?\s*\|)")
TODAY = datetime.date.today().isoformat()


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


def words(s, n=60):
    w = s.split()
    return s if len(w) <= n else " ".join(w[:n]) + "…"   # the ellipsis rides on the last word: the checker counts words, and a bare "…" was a 61st (miss 29)


def rows(text):
    """id -> {status, pct, remarks, title, line_no}"""
    out = {}
    for i, line in enumerate(text.splitlines()):
        m = ROW.match(line)
        if m:
            c = [x.strip() for x in line.strip().strip("|").split("|")]
            if len(c) >= 6:
                pct = re.sub(r"[^0-9]", "", c[3])
                out[m.group(2).upper()] = {"status": c[2].strip("`* "), "pct": int(pct) if pct.isdigit() else None,
                                           "remarks": c[4], "title": c[1].strip("`* "), "line_no": i}
    return out


def set_cells(path, rid, status=None, pct=None, remark=None, append_remark=None):
    """rewrite the Status, % and Remarks cells of one row; returns the prior cells or None"""
    text = read(path)
    lines = text.splitlines(keepends=True)
    prior = None
    for i, line in enumerate(lines):
        m = ROW.match(line)
        if not m or m.group(2).upper() != rid.upper():
            continue
        nl = "\r\n" if line.endswith("\r\n") else "\n"
        c = line.rstrip("\r\n").strip().strip("|").split("|")
        if len(c) < 6:
            break
        prior = {"status": c[2].strip().strip("`* "), "pct": c[3].strip(), "remarks": c[4].strip()}
        if status is not None:
            c[2] = f" {status} "
        if pct is not None:
            c[3] = f" {pct}% " if "%" in c[3] or c[3].strip() == "" else f" {pct} "
        if remark is not None:
            c[4] = f" {words(remark.replace('|', '/'))} "
        elif append_remark:
            c[4] = f" {words((prior['remarks'] + ' ' + append_remark.replace('|', '/')).strip())} "
        lines[i] = "|" + "|".join(c) + "|" + nl
        break
    if prior is not None:
        write(path, "".join(lines))
    return prior


def next_id(text, prefix):
    ids = [int(m.group(1)) for m in re.finditer(rf"REQ-{prefix}-(\d{{3}})", text)]
    return f"REQ-{prefix}-{(max(ids) + 1 if ids else 1):03d}"


def add_row(path, prefix, title, acceptance, section=None, remark=None, status="Not Started", mockup=None, brd="BRD-pending"):
    """append a row to the Requirements Status table and a detail entry under `section`
    (a new section at the end when it does not exist); returns the new id"""
    text = read(path)
    rid = next_id(text, prefix)
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(nl)
    # the table: after the last REQ row
    last = max((i for i, l in enumerate(lines) if ROW.match(l)), default=None)
    if last is None:
        raise SystemExit("no Requirements Status table with REQ rows in " + path)
    remark = words((remark or f"logged from UAT {TODAY}").replace("|", "/"))
    anchor = f"d-{rid.lower()}"
    lines.insert(last + 1, f"| {rid} | {title.replace('|', '/')} | {status} | 0% | {remark} | [d](#{anchor}) |")
    # the entry
    entry = [f"- <a id=\"{anchor}\"></a> **{rid}** ({brd}) {title}" + (f" Mockup: {mockup}" if mockup else ""),
             f"  - *Acceptance:* {acceptance}", ""]
    sec_idx = None
    if section:
        for i, l in enumerate(lines):
            if re.match(rf"^##\s+(?:page|screen)?\s*:?\s*{re.escape(section)}\s*$", l, re.I):
                sec_idx = i
                break
    if sec_idx is not None:
        # after the last entry of that section: the line before the next "## " heading
        j = sec_idx + 1
        while j < len(lines) and not lines[j].startswith("## "):
            j += 1
        while j > sec_idx + 1 and lines[j - 1].strip() == "":
            j -= 1
        lines[j:j] = [""] + entry[:-1]
    else:
        heading = f"## {section}" if section else "## Logged from UAT"
        if not any(l.strip() == heading for l in lines):
            lines += ["", heading, ""]
        lines += entry[:-1]
    write(path, nl.join(lines).rstrip(nl) + nl)
    return rid


def demote(path, rid, symptom, kind=None, evidence=None, source="owner", prefix="⚠ UAT bug"):
    """Needs re-verify, % capped at 75, a dated Remark; returns the prior cells"""
    r = rows(read(path)).get(rid.upper())
    if not r:
        return None
    pct = min(r["pct"] if r["pct"] is not None else 75, 75)
    ev = f"evidence: {evidence}" if evidence else f"evidence: {source} report"
    remark = f"{prefix} {TODAY}: {symptom} ({ev}" + (f"; kind: {kind}" if kind else "") + ")"
    return set_cells(path, rid, status="Needs re-verify", pct=pct, remark=remark)


def note(path, rid, text):
    """a dated remark, no status change"""
    return set_cells(path, rid, append_remark=f"{TODAY} triage: {text}")

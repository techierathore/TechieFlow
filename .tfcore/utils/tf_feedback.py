#!/usr/bin/env python3
"""tf_feedback.py — the one reader of a project's upstream feedback files (2026-09-11).

    bash .tfcore/utils/tf-feedback.sh <App>                       every entry and its state
    bash .tfcore/utils/tf-feedback.sh <App> --waiting             fixed upstream, not yet re-checked here
    bash .tfcore/utils/tf-feedback.sh <App> --close <ID> "<what you ran and what it showed>"

An entry is one of three things, and every script that reports on these files reads them here:

  open     nobody upstream has answered it
  fixed    the upstream team's reply ("## Resolution status (…, <date>)") lists it, or its own body
           says "fixed upstream" — the fix exists, and this project has not yet re-checked it
  closed   this project re-checked it and marked it closed (✅, "Closed <date>", "will not fix")

Why one reader. Until 2026-09-11 three scripts read these files three ways, and the one that writes
PROJECT-STATUS counted every `###` heading as an entry and accepted only a closing format no file
used: TfLens's status read "TechieFlow: 62 open of 62" for a file of 27 entries with 16 fixed, and
the agent reported two fixed problems to the owner as open (MISS-TechieFlow-20260911-04).

--close writes one line under the entry's heading and nothing else. Python 3 standard library only.
"""
from __future__ import annotations

import datetime
import glob
import os
import re
import sys

# a heading is one line: [ \t], never \s, which runs past the line break and makes the next line
# of a bare "## TF-013" its title — its closing line included (TF-028)
ENTRY_HEAD = re.compile(r"(?m)^(#{2,3})[ \t]+`?([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-\d+)\b[` \t—–-]*(.*)$")
REPLY_HEAD = re.compile(r"(?mi)^([ \t]*>[ \t]*)?#{2,3}[ \t]+[^\n]*\b(?:resolution status|resolved|repl(?:y|ies) from)\b[^\n]*")
ANY_ID = re.compile(r"(?<![\w-])([A-Z][A-Z0-9]*(?:-[A-Z]+)*-\d{2,})(?!\d)")
FIXED_WORDS = re.compile(r"(?i)\b(fixed|resolved|corrected|closes|closed|wired)\b")
EVERYTHING = re.compile(r"(?i)\beverything else is (?:now )?fixed\b|\ball (?:the )?others? (?:are )?(?:now )?fixed\b")
# a project's own mark that it re-checked the fix, that it will never be fixed, or that the entry
# was folded into another
CLOSED = re.compile(r"(?i)(✅|\bclosed (?:on )?\d{4}-\d{2}-\d{2}|is \*\*closed\*\*|\bwill not fix\b|\bwont-fix\b)")
MERGED = re.compile(r"(?i)^\s*merged into\b")
FIXED_IN_BODY = re.compile(r"(?i)\bfixed upstream\b")
STILL_OPEN = re.compile(r"(?i)\bopen\b|\bnot (?:yet )?(?:fixed|resolved)\b|\bunfixed\b")
BLOCKS = re.compile(r"(?im)^\s*[-*]\s*\*\*Blocks:?\*\*:?\s*(yes|no)\b")


def ids_in(t):
    """Every id the text names, shorthand included: "TR-RAG-028/029/030" and "TR-RAG-031..034"
    (or "031–034") name each id they cover, not only the first."""
    out = []
    for m in re.finditer(r"(?<![\w-])([A-Z][A-Z0-9]*(?:-[A-Z]+)*)-(\d{2,})(?!\d)((?:/\d{2,})+|(?:\.\.|…|–|—)\d{2,})?", t):
        pre, n, tail = m.group(1), m.group(2), m.group(3) or ""
        out.append(f"{pre}-{n}")
        w = len(n)
        if tail.startswith("/"):
            out += [f"{pre}-{x.zfill(w)}" for x in tail.strip("/").split("/")]
        elif tail:
            hi = int(re.sub(r"^\D+", "", tail))
            if int(n) < hi <= int(n) + 50:
                out += [f"{pre}-{str(x).zfill(w)}" for x in range(int(n) + 1, hi + 1)]
    return out


def unquoted(t):
    """The text without fenced code, inline code and double-quoted phrases."""
    t = re.sub(r"(?ms)^[ \t]*```.*?^[ \t]*```", "", t)
    t = re.sub(r"`[^`\n]*`", "", t)
    return re.sub(r"[\"“][^\"”\n]*[\"”]", "", t)


def entries(path):
    """-> [{id, title, state, since, blocks, start, end}] in file order."""
    text = open(path, encoding="utf-8", errors="replace").read()
    heads = list(ENTRY_HEAD.finditer(text))
    out = {}
    for i, m in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        nxt = re.search(r"(?m)^#{1,%d}\s" % len(m.group(1)), text[m.end():end])
        body = text[m.end(): m.end() + nxt.start()] if nxt else text[m.end():end]
        # quoted or code text is somebody's words, not a mark: `fixed upstream` in a repro, a test name
        head = unquoted(body[:2500])
        title = unquoted(m.group(3))
        # the mark is read in the heading as well (TechieRag TF-001: "— **fixed upstream 2026-10-03**")
        state = ("closed" if CLOSED.search(head) or CLOSED.search(title) or MERGED.search(m.group(3))
                 else "fixed" if FIXED_IN_BODY.search(head) or FIXED_IN_BODY.search(title) else "open")
        b = BLOCKS.search(body)
        out.setdefault(m.group(2), {"id": m.group(2), "title": m.group(3).strip(" `"), "state": state,
                                    "since": "", "blocks": b.group(1).lower() if b else "",
                                    "start": m.start(), "end": m.end() + len(body)})
    # the upstream team's replies, in the shapes they have actually been written in
    for rid, date in replied_fixed(text, list(out)):
        e = out.get(rid)
        if e and e["state"] == "open":
            e["state"] = "fixed"
        if e and not e["since"] and date:
            e["since"] = date
    return list(out.values())


def reply_blocks(text):
    """-> [(date, block text)]. A reply is a heading naming a resolution or a reply —
    "## Resolution status (TechieFlow team, 2026-09-09)", "## Replies from …", or a quoted
    "> ## ✅ RESOLVED LIBRARY-SIDE 2026-08-31" — and runs to the next heading of its level,
    or, when quoted, to the end of the quote."""
    out, seen = [], set()
    date_of = lambda h: (re.search(r"\d{4}-\d{2}-\d{2}", h) or [""])[0]
    for m in REPLY_HEAD.finditer(text):
        if m.start() in seen:
            continue
        rest = text[m.end():]
        if m.group(1):   # quoted: the block is the run of '>' lines after the heading's own line
            rest = rest[1:] if rest.startswith("\n") else rest
            q = re.match(r"(?:[ \t]*>[^\n]*\n?)*", rest)
            out.append((date_of(m.group(0)), re.sub(r"(?m)^[ \t]*>[ \t]?", "", q.group(0))))
            continue
        level = len(re.match(r"[ \t]*(#+)", m.group(0)).group(1))
        nxt = re.search(r"(?m)^#{1,%d}\s" % level, rest)
        section = rest[: nxt.start()] if nxt else rest
        if level == 2:
            # A "## Replies from …" section holds dated "### " blocks, written months apart. Each is its
            # own reply: an "all others fixed" kept in an old one must not reach entries a newer block
            # merely names (TechieRag TF-001: Sevak's TR-RAG-047 read fixed when TR-RAG-048 was replied to).
            subs = list(re.finditer(r"(?m)^###[ \t]+[^\n]*", section))
            out.append((date_of(m.group(0)), section[: subs[0].start()] if subs else section))
            for j, sm in enumerate(subs):
                end = subs[j + 1].start() if j + 1 < len(subs) else len(section)
                seen.add(m.end() + sm.start())
                # the heading line stays in: "### TF-025 — fixed 2026-09-19" names the entry it answers
                out.append((date_of(sm.group(0)) or date_of(m.group(0)), section[sm.start(): end]))
        else:
            out.append((date_of(m.group(0)), section))
    return out


def replied_fixed(text, known):
    """-> [(id, date)] for every entry a reply says is fixed. Inside a reply, an item — a table
    row, a bullet, or a paragraph — fixes the ids it names when it is a table row or says fixed,
    resolved, corrected or closes; "everything else is fixed" covers every entry up to the highest
    number the reply mentions (entries filed after it stay open)."""
    out = []
    for date, body in reply_blocks(text):
        items = re.split(r"\n\s*\n|\n(?=\s*[-*]\s)|\n(?=\s*\|)", body)
        mentioned = []
        for it in items:
            ids = ids_in(it)
            mentioned += ids
            if not ids:
                continue
            if it.lstrip().startswith("|"):
                first = ids_in(it.split("|")[1] if it.count("|") > 1 else "")
                out += [(i, date) for i in first]
            elif FIXED_WORDS.search(unquoted(it)) and not EVERYTHING.search(unquoted(it)):
                # "Open: TR-RAG-001, TR-RAG-002. All others fixed": the ids are the exceptions.
                # Read clause by clause: "1 OPEN: TR-RAG-001 …; 2 FIXED: TR-RAG-005 …" fixes 005 only,
                # and "TR-RAG-035 (minor, OPEN)" beside "TR-RAG-034 (minor, FIXED)" stays open.
                # A "fixed" clause naming no id answers the clause before it: "TR-RAG-010: every
                # assembly carries its version. Fixed in 1.1.2." And "TR-RAG-017/019 → BRD-126 (fixed);
                # TR-RAG-020…022 → BRD-127" fixes 017 and 019 only.
                prev = []
                for cl in re.split(r"(?<=[.;])\s+|\s+·\s+", it):
                    own_ids = ids_in(cl)
                    bare = unquoted(cl)
                    if FIXED_WORDS.search(bare) and not STILL_OPEN.search(bare):
                        out += [(i, date) for i in (own_ids or prev)]
                    if own_ids:
                        prev = [] if STILL_OPEN.search(bare) else own_ids
        for it in items:
            # a quoted or code "all others fixed" is somebody's words being cited, not this reply's
            # claim: "…only because of the July "All others fixed app-side" line" fixed 13 entries the
            # same block listed as still open (TechieRag TF-002)
            if EVERYTHING.search(unquoted(it)) and mentioned:
                # bounded by the ids of its own item, which it never covers ("all others"); an item
                # naming none takes the block's. A running log in one block once let a July "all
                # others fixed" reach every entry its later lines named (TechieRag TF-001).
                own = ids_in(it)
                top = {}
                for i in own or mentioned:
                    p, n = i.rsplit("-", 1)
                    top[p] = max(top.get(p, 0), int(n))
                for k in known:
                    p, n = k.rsplit("-", 1)
                    if p in top and int(n) <= top[p] and k not in own:
                        out.append((k, date))
    return out


def files(root, app=None):
    pat = f"{app}-*-Feedback.md" if app else "*-Feedback.md"
    return sorted(glob.glob(os.path.join(root, "docs", pat)))


def upstream_of(path, app=None):
    base = os.path.basename(path)
    m = re.match(rf"^{re.escape(app)}-(.+)-Feedback\.md$", base) if app else re.match(r"^[^-]+-(.+)-Feedback\.md$", base)
    return m.group(1) if m else base


def state_map(root):
    """Every entry id across the project's feedback files -> (state, "<file>, <date>")."""
    out = {}
    for f in files(root):
        rel = os.path.relpath(f, root).replace(os.sep, "/")
        for e in entries(f):
            out[e["id"]] = (e["state"], f"{rel}" + (f", Resolution status {e['since']}" if e["since"] else ""))
    return out


def summary_line(path, app):
    es = entries(path)
    n = {s: [e["id"] for e in es if e["state"] == s] for s in ("open", "fixed", "closed")}
    rel = "docs/" + os.path.basename(path)
    parts = [f"{len(n['open'])} open"]
    if n["fixed"]:
        ids = ", ".join(n["fixed"][:3]) + (" …" if len(n["fixed"]) > 3 else "")
        parts.append(f"{len(n['fixed'])} fixed upstream, not yet re-checked ({ids})")
    parts.append(f"{len(n['closed'])} closed")
    return f"- {upstream_of(path, app)}: " + " · ".join(parts) + f" — {rel}"


def close(path, rid, evidence):
    text = open(path, encoding="utf-8").read()
    e = next((x for x in entries(path) if x["id"] == rid), None)
    if not e:
        return f"tf-feedback: no entry {rid} in {os.path.basename(path)}", 2
    if e["state"] == "closed":
        return f"tf-feedback: {rid} is already closed; nothing written", 0
    if not evidence.strip():
        return "tf-feedback: say what you ran and what it showed; a close with no evidence is refused", 2
    line_end = text.index("\n", e["start"]) + 1
    today = datetime.date.today().isoformat()
    mark = f"\n> ✅ **Closed {today}** — re-checked here: {evidence.strip()}\n"
    open(path, "w", encoding="utf-8").write(text[:line_end] + mark + text[line_end:])
    return f"tf-feedback: {rid} closed in {os.path.basename(path)}", 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    app, rest = argv[0], argv[1:]
    root = os.getcwd()
    fs = files(root, app)
    if not fs:
        print(f"tf-feedback: no docs/{app}-*-Feedback.md here")
        return 0
    if rest[:1] == ["--close"]:
        if len(rest) < 3:
            print('usage: tf-feedback.sh <App> --close <ID> "<what you ran and what it showed>"')
            return 2
        for f in fs:
            if any(e["id"] == rest[1] for e in entries(f)):
                msg, rc = close(f, rest[1], rest[2])
                print(msg)
                return rc
        print(f"tf-feedback: no entry {rest[1]} in any docs/{app}-*-Feedback.md")
        return 2
    waiting = rest[:1] == ["--waiting"]
    for f in fs:
        es = entries(f)
        if waiting:
            for e in es:
                if e["state"] == "fixed":
                    print(f"{e['id']}  fixed upstream{' ' + e['since'] if e['since'] else ''}, waiting to be "
                          f"re-checked here — {os.path.basename(f)}")
            continue
        print(summary_line(f, app))
        for e in es:
            print(f"  {e['id']:<12} {e['state']:<7} {e['since'] or '':<10} {e['title'][:80]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

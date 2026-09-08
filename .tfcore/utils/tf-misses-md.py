#!/usr/bin/env python3
"""tf-misses-md.py — the readable miss list, docs/<App>-Misses.md (Session 5, 2026-09-07; FR-31).

    python3 .tfcore/utils/tf-misses-md.py [--root <repo>] [--app <App>] [--quiet]

Rebuilds docs/<App>-Misses.md from docs/metrics/misses.jsonl: one row per `miss` record, newest first,
in three tables (open, fixed, will not fix), each row holding the miss id, the owning row, when and
by whom it was found, whose gap it was (the `sort` field, folded from any miss-amend) and the `what`
sentence. Markdown only — there is no HTML sibling: the miss log is read by agents and by the owner
in markdown, and tf-render-html.py refuses it (owner, 2026-09-08; an HTML copy nobody opened was
being re-rendered on every miss in every project). tf-emit.sh calls this after every write to the
misses stream, so the file is never older than the record; run it by hand once on a project whose
stream predates it. The file is derived: never edit it, edit nothing, log a miss.
Exit 0 always (telemetry has no veto); the reason for a skipped write is printed unless --quiet.
"""
import datetime
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

SORT_WORDS = {
    "spec": "the app's spec",
    "unsaid": "the framework never said it",
    "weak-check": "the check was too weak",
    "ignored": "said and ignored",
}
SORT_LEGEND = ("**Whose gap** answers the four questions of the miss protocol: "
               "**the app's spec** did not say it, so the checklist line is fixed; "
               "**the framework never said it**, so one requirement line and a check are added; "
               "**the check was too weak** (a review, or a script that did not fire), so the check is fixed; "
               "**said and ignored**, so the rule becomes a hook or is deleted. "
               "**not sorted** means the record predates the sort or nobody has answered yet; "
               "`bash .tfcore/utils/tf-emit.sh --amend <miss> sort <spec|unsaid|weak-check|ignored>` completes it.")


def find_root(explicit):
    if explicit and os.path.isdir(explicit):
        return os.path.abspath(explicit)
    for k in ("TF_METRICS_ROOT", "CLAUDE_PROJECT_DIR"):
        v = os.environ.get(k)
        if v and os.path.isdir(v):
            return os.path.abspath(v)
    d = os.getcwd()
    while d and d != os.path.dirname(d):
        if os.path.isdir(os.path.join(d, ".tfcore")) or os.path.isdir(os.path.join(d, "docs")):
            return d
        d = os.path.dirname(d)
    return os.getcwd()


def app_name(root, explicit):
    if explicit:
        return explicit
    hits = [h for h in glob.glob(os.path.join(root, "docs", "*-Checklist.md"))
            if not re.search(r"-(Deployment|P\d+)-Checklist\.md$", h)]
    if len(hits) == 1:
        return os.path.basename(hits[0])[: -len("-Checklist.md")]
    return os.path.basename(os.path.abspath(root))


def load(path):
    out = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except Exception:
                    pass
    except FileNotFoundError:
        pass
    return out


def cell(text):
    text = (text or "").replace("\r", " ").replace("\n", " ").replace("|", "\\|").strip()
    return text or "—"


def day(ts):
    return (ts or "")[:10] or "—"


def build(root, app):
    recs = load(os.path.join(root, "docs", "metrics", "misses.jsonl"))
    misses = [r for r in recs if r.get("kind") == "miss"]
    by_id = {}
    for i, m in enumerate(misses):
        if not m.get("miss_id"):            # a record from before the emitter required an id: still a miss, still a row
            m["miss_id"] = f"(no id, record {i + 1})"
        by_id.setdefault(m["miss_id"], m)
    for a in sorted((r for r in recs if r.get("kind") == "miss-amend"), key=lambda r: r.get("ts") or ""):
        p = by_id.get(a.get("miss_id"))
        if p is not None and a.get("field") and p.get(a["field"]) is None:
            p[a["field"]] = a.get("value")
    latest = {}
    for f in recs:
        if f.get("kind") != "miss-fix" or not f.get("miss_id"):
            continue
        prev = latest.get(f["miss_id"])
        if prev is None or (f.get("ts") or "") >= (prev.get("ts") or ""):
            latest[f["miss_id"]] = f

    def state(m):
        v = (latest.get(m["miss_id"]) or {}).get("verdict_after")
        return "fixed" if v == "Verified" else "wont-fix" if v == "wont-fix" else "open"

    groups = {"open": [], "fixed": [], "wont-fix": []}
    for m in sorted(by_id.values(), key=lambda r: (r.get("miss_id") or "", r.get("ts") or ""), reverse=True):
        groups[state(m)].append(m)

    def what(m):
        w = (m.get("what") or "").strip()
        if w:
            return cell(w)
        bits = [m.get("miss_class") or "?", m.get("artifact") or "?"]
        if m.get("why_missed"):
            bits.append("why: " + m["why_missed"])
        return "no sentence recorded (" + ", ".join(bits) + ")"

    def found(m):
        who = m.get("found_by") or "?"
        return f"{day(m.get('ts'))} by {who}"

    def gap(m):
        return SORT_WORDS.get(m.get("sort") or "", "not sorted")

    def ident(m):
        return m["miss_id"] + (f" ({m['req_id']})" if m.get("req_id") else "")

    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    n = len(by_id)
    lines = [f"# {app} — Misses", "", "| | |", "|---|---|", f"| App | {app} |",
             f"| Count | {n} logged: {len(groups['open'])} open, {len(groups['fixed'])} fixed, {len(groups['wont-fix'])} will not fix |",
             "| Source | `docs/metrics/misses.jsonl`, one row per miss record. Rewritten by `tf-misses-md.sh` on every new record. Never edit it: a wrong row is corrected by a new record. |",
             f"| Updated | {today} |", "", SORT_LEGEND, ""]
    if not n:
        lines += ["No miss has been logged yet.", ""]
    for key, title in (("open", "Open"), ("fixed", "Fixed"), ("wont-fix", "Will not fix")):
        rows = groups[key]
        if not rows:
            continue
        lines += [f"## {title} ({len(rows)})", ""]
        if key == "open":
            lines += ["| Miss | Found | Whose gap | What went wrong |", "|---|---|---|---|"]
            for m in rows:
                lines.append(f"| {ident(m)} | {found(m)} | {gap(m)} | {what(m)} |")
        else:
            lines += ["| Miss | Found | Closed | Whose gap | What went wrong |", "|---|---|---|---|---|"]
            for m in rows:
                f = latest.get(m["miss_id"]) or {}
                closed = day(f.get("ts")) + (f" by {f['fix_cmd']}" if f.get("fix_cmd") else "")
                lines.append(f"| {ident(m)} | {found(m)} | {closed} | {gap(m)} | {what(m)} |")
        lines.append("")
    return "\n".join(lines), n


def main(argv):
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    quiet = "--quiet" in argv

    def opt(name):
        return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None

    try:
        root = find_root(opt("--root"))
        app = app_name(root, opt("--app"))
        text, n = build(root, app)
        rel = os.path.join("docs", f"{app}-Misses.md")
        out = os.path.join(root, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        old = None
        try:
            with open(out, encoding="utf-8") as fh:
                old = fh.read()
        except FileNotFoundError:
            pass
        stale = out[:-3] + ".html"                 # left by a pre-2026-09-08 run, before the miss
        gone = ""                                  # log was ruled an agent document (owner)
        if os.path.isfile(stale):
            os.remove(stale)
            gone = "; removed the stale HTML copy"
        same = lambda s: re.sub(r"\| Updated \| [0-9-]+ \|", "", s)   # everything but the date must match
        if old is not None and same(old) == same(text):
            if not quiet:
                print(f"tf-misses-md: {rel} unchanged ({n} misses){gone}")
            return 0
        with open(out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        if not quiet:
            print(f"tf-misses-md: wrote {rel} ({n} misses){gone}")
    except Exception as e:
        if not quiet:
            print(f"tf-misses-md: nothing written ({e})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

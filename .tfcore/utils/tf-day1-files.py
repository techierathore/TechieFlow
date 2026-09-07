#!/usr/bin/env python3
"""tf-day1-files.py — the mechanical part of day-1 (see tf-day1-files.sh).

    bash .tfcore/utils/tf-day1-files.sh <App> [--size S|M|L] [--kind app|library] [--prefix obj|none] [--phase N]
    bash .tfcore/utils/tf-day1-files.sh --archive <file> [<file> ...]

Default mode, for <App>:
  - .tfcore/core-config.yaml: customTechnicalDocuments (brd, architecture, codingStandards),
    devLoadAlwaysFiles, and appSize / appKind / appPhase when given.
  - --size L also writes docs/<App>-Phases.md from app-phases-tmpl.md when it does not exist
    (the Large layout: docs/TechieFlow-Document-Schemas.md §2, §3.11). The agent fills the table.
  - --phase N sets appPhase, the phase being worked (handoff moves it on).
  - .editorconfig from app-editorconfig-tmpl.editorconfig (overwritten; machine config).
  - AGENTS.md and CLAUDE.md from their templates with {AppName} substituted and the
    field-prefix line resolved (--prefix, default obj). An existing copy is archived first.
--archive: move each file (and its sibling .html) to docs/OldDocs/, date-suffixed when a
file of that name is already there. Never asks; never writes a -v2 variant.

Prints one line per thing done. Python 3 standard library only. Exit 0 done, 2 could not run.
"""
import datetime
import os
import re
import shutil
import sys

TPL = os.path.join(".tfcore", "templates", "v4custom")
PREFIX_TEXT = {
    "obj": "`obj` prefix on instance fields (e.g. `private readonly ILogger<X> objLogger;`)",
    "none": "bare PascalCase, no prefix",
}


def die(msg):
    print(f"tf-day1-files: {msg}", file=sys.stderr)
    sys.exit(2)


def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(s)


def archive(path):
    """Move path (and its sibling .html) to docs/OldDocs/, date-suffixed on collision."""
    if not os.path.isfile(path):
        return
    old = os.path.join("docs", "OldDocs")
    os.makedirs(old, exist_ok=True)
    for p in (path, os.path.splitext(path)[0] + ".html"):
        if not os.path.isfile(p):
            continue
        dest = os.path.join(old, os.path.basename(p))
        if os.path.exists(dest):
            stem, ext = os.path.splitext(os.path.basename(p))
            dest = os.path.join(old, f"{stem}-{datetime.date.today().strftime('%Y%m%d')}{ext}")
            n = 1
            while os.path.exists(dest):
                n += 1
                dest = os.path.join(old, f"{stem}-{datetime.date.today().strftime('%Y%m%d')}-{n}{ext}")
        shutil.move(p, dest)
        print(f"tf-day1-files: archived {p} -> {dest}")


def set_key(text, key, value_lines):
    """Replace a top-level YAML key (scalar or block) with the given lines; append if absent."""
    lines = text.splitlines()
    out, i, done = [], 0, False
    while i < len(lines):
        if re.match(rf"^{re.escape(key)}:", lines[i]):
            out.extend(value_lines)
            i += 1
            while i < len(lines) and (lines[i].startswith((" ", "\t")) or lines[i].strip() == "" and i + 1 < len(lines) and lines[i + 1].startswith(" ")):
                i += 1
            done = True
            continue
        out.append(lines[i])
        i += 1
    if not done:
        out.extend(value_lines)
    return "\n".join(out) + "\n"


def update_config(app, size, kind, phase):
    p = os.path.join(".tfcore", "core-config.yaml")
    if not os.path.isfile(p):
        die(f"{p} does not exist at its literal path; is the framework installed here?")
    s = read(p)
    s = set_key(s, "customTechnicalDocuments", [
        "customTechnicalDocuments:",
        f"  brd: docs/{app}-BRD.md",
        f"  architecture: docs/{app}-Architecture.md",
        f"  codingStandards: docs/{app}-Coding-Standards.md",
    ])
    s = set_key(s, "devLoadAlwaysFiles", [
        "devLoadAlwaysFiles:",
        f"  - docs/{app}-Coding-Standards.md",
        f"  - docs/{app}-Architecture.md",
    ])
    if size:
        s = set_key(s, "appSize", [f"appSize: {size}"])
    if kind:
        s = set_key(s, "appKind", [f"appKind: {kind}"])
    if phase:
        s = set_key(s, "appPhase", [f"appPhase: {phase}"])
    write(p, s)
    print(f"tf-day1-files: .tfcore/core-config.yaml updated (documents for {app}"
          + (f", appSize {size}" if size else "") + (f", appKind {kind}" if kind else "")
          + (f", appPhase {phase}" if phase else "") + ")")


def write_phases_doc(app):
    """docs/<App>-Phases.md from its template, only when absent (Large projects)."""
    dest = os.path.join("docs", f"{app}-Phases.md")
    if os.path.isfile(dest):
        print(f"tf-day1-files: {dest} already exists; left as is")
        return
    src = os.path.join(TPL, "app-phases-tmpl.md")
    if not os.path.isfile(src):
        die(f"template {src} does not exist at its literal path")
    os.makedirs("docs", exist_ok=True)
    body = read(src).replace("{App}", app).replace("{YYYY-MM-DD}", datetime.date.today().isoformat())
    write(dest, body)
    print(f"tf-day1-files: wrote {dest} skeleton; fill the Phases table (one row per phase, each within Medium)")


def write_from_template(app, tmpl, dest, prefix):
    src = os.path.join(TPL, tmpl)
    if not os.path.isfile(src):
        die(f"template {src} does not exist at its literal path")
    body = read(src).replace("{AppName}", app)
    if prefix:
        body = re.sub(r"\{obj prefix on instance fields[^}]*\| bare PascalCase, no prefix\}", PREFIX_TEXT[prefix], body)
    if os.path.isfile(dest) and read(dest) == body:
        print(f"tf-day1-files: {dest} already current")
        return
    if dest != ".editorconfig":
        archive(dest)
    write(dest, body)
    print(f"tf-day1-files: wrote {dest}")


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[1] == "--archive":
        if len(argv) < 3:
            die("--archive needs at least one file")
        for f in argv[2:]:
            if os.path.isfile(f):
                archive(f)
            else:
                print(f"tf-day1-files: {f} does not exist; nothing to archive")
        return 0
    app = argv[1]
    if not re.fullmatch(r"[A-Z][A-Za-z0-9]*", app):
        die(f"app name {app!r} must be PascalCase with no spaces")
    size = kind = phase = None
    prefix = "obj"
    args = argv[2:]
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--size" and i + 1 < len(args):
            v = args[i + 1].strip().upper()[:1]
            if v not in ("S", "M", "L"):
                die("--size must be S, M or L")
            size = v
            i += 2
        elif a == "--phase" and i + 1 < len(args):
            if not args[i + 1].isdigit() or int(args[i + 1]) < 1:
                die("--phase must be a number from 1 upwards")
            phase = int(args[i + 1])
            i += 2
        elif a == "--kind" and i + 1 < len(args):
            kind = args[i + 1].strip().lower()
            if kind not in ("app", "library"):
                die("--kind must be app or library")
            i += 2
        elif a == "--prefix" and i + 1 < len(args):
            prefix = args[i + 1].strip().lower()
            if prefix not in PREFIX_TEXT:
                die("--prefix must be obj or none")
            i += 2
        else:
            die(f"unknown argument {a!r}")
    update_config(app, size, kind, phase)
    if size == "L":
        write_phases_doc(app)
    write_from_template(app, "app-editorconfig-tmpl.editorconfig", ".editorconfig", None)
    write_from_template(app, "app-agents-md-tmpl.md", "AGENTS.md", prefix)
    write_from_template(app, "app-claude-md-tmpl.md", "CLAUDE.md", prefix)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as e:
        die(str(e))

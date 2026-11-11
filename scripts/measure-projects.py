#!/usr/bin/env python3
"""scripts/measure-projects.py — what a framework change would do to every project, before a deploy.

    python3 scripts/measure-projects.py [--base v1.3.0|deployed] [--roots DIR,DIR] [--only App,App]
                                        [--out FILE.md] [--keep]

Read only: no project file is written, no app is booted, nothing is deployed. For every folder
under the roots that holds a .tfcore, the project's documents, spec files and saved verify records
are copied to a throw-away folder twice. One copy gets the OLD scripts (--base: a git tag or commit
of this repository, or `deployed` for the copy the project runs today), the other gets the scripts
in this working tree. The same checks run in both and the answers are compared:

  rows       tf-verify-verdict.py over the saved records of the project's last verify
             (tests/.artifacts/verify/*.json): the rows whose verdict would move
  tests      the spec files under tests/verify, read as text: the tests a phase verify would leave
             out because nothing in their name, their group or their file carries a row id
  findings   tf-doc-check.py --app and tf-test-users-check.py: FAIL lines that appear or go
  lists      tf-build-list.py per phase (what a builder is handed) and the next command
             tf-status-facts.py prints
  boot       the browser-side scripts that differ (screen, mockup, menu, sign-in, asset checks):
             their result needs the running app, so it is named here and not measured

Prints one table, then the detail per project. Exit 0 always measured, 2 could not run.
Roots, first that is given: --roots, TF_PROJECT_ROOTS (a colon list), the lines of the per-machine
file ~/.techieflow/project-roots.txt, the folder this repository sits in. Python 3 standard library only.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BROWSER_SIDE = ["tf-verify-screens.mjs", "tf-mockup-parity.mjs", "tf-menus.mjs", "tf-login.mjs", "tf-theme.mjs",
                "tf-assets.sh", "tf-assets-browser.mjs", "tf-verify-native.mjs", "tf-verify-boot.sh", "tf-verify-tests.sh"]
DOC_KEEP = (".md", ".json", ".jsonl", ".yaml", ".yml")
SKIP_DIRS = {"node_modules", ".artifacts", "bin", "obj", "test-results", "playwright-report", ".git", "__pycache__"}
ENV = {k: v for k, v in os.environ.items()
       if k not in ("CLAUDE_PROJECT_DIR", "TF_PROJECT_DIR", "TF_METRICS_ROOT", "TF_YOLO")}
ENV.update(TF_SKIP_SELFCHECK="1", PYTHONDONTWRITEBYTECODE="1", TF_TEST_USERS="1")


def die(msg):
    print(f"measure-projects: {msg}", file=sys.stderr)
    sys.exit(2)


def arg(argv, name, default=None):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


def find_projects(roots):
    out = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for name in sorted(os.listdir(root)):
            p = os.path.join(root, name)
            if os.path.isdir(os.path.join(p, ".tfcore")) and os.path.realpath(p) != os.path.realpath(REPO):
                out.append(p)
    return out


def app_of(project):
    """the app name its checklists carry, and the phases that have a checklist"""
    docs = os.path.join(project, "docs")
    names = sorted(f for f in (os.listdir(docs) if os.path.isdir(docs) else [])
                   if f.endswith("-Checklist.md") and "Deployment-Checklist" not in f)
    if not names:
        return None, []
    app = min((re.sub(r"(-P\d+)?-Checklist\.md$", "", f) for f in names), key=len)
    phases = sorted({int(m.group(1)) if m.group(1) else 1
                     for f in names for m in [re.match(re.escape(app) + r"(?:-P(\d+))?-Checklist\.md$", f)] if m})
    return app, phases


def base_tree(base, work):
    """-> folder holding the base's .tfcore, or None for `deployed` (each project's own)"""
    if base == "deployed":
        return None
    dest = os.path.join(work, "base-tree")
    os.makedirs(dest)
    git = subprocess.run(["git", "-C", REPO, "archive", base, ".tfcore"], capture_output=True)
    if git.returncode != 0:
        die(f"git cannot read {base}: {git.stderr.decode(errors='replace').strip()[:200]}")
    tar = subprocess.run(["tar", "-x", "-C", dest], input=git.stdout, capture_output=True)
    if tar.returncode != 0:
        die("could not unpack the base scripts")
    return os.path.join(dest, ".tfcore")


def copy_tree(src, dst, keep):
    for cur, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            full = os.path.join(cur, f)
            if keep(full) and not f.endswith(".Local.json") and os.path.getsize(full) < 20_000_000:
                to = os.path.join(dst, os.path.relpath(full, src))
                os.makedirs(os.path.dirname(to), exist_ok=True)
                shutil.copyfile(full, to)


def sandbox(project, tfcore, dest):
    """the project's documents, test files and saved verify records, with the scripts of one version"""
    os.makedirs(dest)
    docs = os.path.join(project, "docs")
    if os.path.isdir(docs):
        copy_tree(docs, os.path.join(dest, "docs"),
                  lambda p: p.endswith(DOC_KEEP) or (os.sep + "mockups" + os.sep in p and p.endswith((".html", ".css"))))
    for f in ("PROJECT-STATUS.md",):
        if os.path.isfile(os.path.join(project, f)):
            shutil.copyfile(os.path.join(project, f), os.path.join(dest, f))
    tests = os.path.join(project, "tests")
    if os.path.isdir(tests):
        copy_tree(tests, os.path.join(dest, "tests"),
                  lambda p: p.endswith((".ts", ".js", ".mjs", ".tsx", ".jsx", ".cs", ".py", ".json", ".csproj")))
    ev = os.path.join(tests, ".artifacts", "verify")
    if os.path.isdir(ev):
        for cur, dirs, files in os.walk(ev):
            dirs[:] = [d for d in dirs if d == "perf"]
            for f in files:
                if f.endswith(".json") and not re.match(r"(boot-\d+|playwright)", f):
                    to = os.path.join(dest, "tests", ".artifacts", "verify", os.path.relpath(os.path.join(cur, f), ev))
                    os.makedirs(os.path.dirname(to), exist_ok=True)
                    shutil.copyfile(os.path.join(cur, f), to)
    shutil.copytree(tfcore, os.path.join(dest, ".tfcore"),
                    ignore=shutil.ignore_patterns(".session", "__pycache__", "core-config.yaml", "routing.yaml"))
    for f in ("core-config.yaml", "routing.yaml"):
        if os.path.isfile(os.path.join(project, ".tfcore", f)):
            shutil.copyfile(os.path.join(project, ".tfcore", f), os.path.join(dest, ".tfcore", f))


def run(box, script, *args):
    p = os.path.join(box, ".tfcore", "utils", script)
    if not os.path.isfile(p):
        return None
    try:
        r = subprocess.run(["python3", p, *args], cwd=box, env=ENV, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    return (r.stdout or "") + (r.stderr or "")


def fails(text):
    """FAIL lines with dates and line numbers taken out, so the same finding compares equal"""
    return {re.sub(r"\s+", " ", l).strip() for l in (text or "").splitlines() if l.startswith("FAIL")}


def spec_tests(box, utils):
    """-> [(file, title, text grep sees)] for every test under tests/verify, read as text"""
    out, root = [], os.path.join(box, "tests", "verify")
    for cur, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in sorted(files):
            if not re.search(r"\.spec\.(ts|js|mjs|tsx|jsx)$", f):
                continue
            rel = os.path.relpath(os.path.join(cur, f), box)
            src = open(os.path.join(cur, f), encoding="utf-8", errors="replace").read()
            groups = " ".join(g for _q, g in re.findall(r"\bdescribe(?:\.\w+)*\(\s*(['\"`])(.*?)\1", src))
            for _q, title in re.findall(r"(?m)^\s*(?:test|it)(?:\.(?:only|fixme|slow))?\(\s*(['\"`])(.*?)\1", src):
                out.append((rel, title, f"{rel} {groups} {title}"))
    return out


def measure(box, app, phases):
    """every answer one version of the scripts gives for one project"""
    m = {"doc": fails(run(box, "tf-doc-check.py", "--root", ".", "--app", app, "--quiet")),
         "users": fails(run(box, "tf-test-users-check.py", "--app", app)),
         "build": {}, "next": "", "rows": {}, "verdict_note": "", "left_out": None}
    for n in phases:
        out = run(box, "tf-build-list.py", app, "--phase", str(n)) or ""
        line = next((l for l in out.splitlines() if l.startswith("Mode:")), out.strip().splitlines()[-1] if out.strip() else "")
        m["build"][n] = re.sub(r"\s+—\s+REQ-.*$", "", line)
    out = run(box, "tf-status-facts.py", app) or ""
    nxt = re.search(r"## Next command to run\s*\nClaude Code:\s*\n```\s*\n(.*?)\n```", out)
    m["next"] = nxt.group(1).strip() if nxt else ""
    ev = os.path.join(box, "tests", ".artifacts", "verify")
    if os.path.isfile(os.path.join(ev, "list.json")):
        try:   # when the saved verify ran, read before the verdict script writes its own file over it
            was = json.load(open(os.path.join(ev, "verdicts.json"), encoding="utf-8")).get("date")
        except Exception:
            was = None
        out = run(box, "tf-verify-verdict.py", app, "--dir", os.path.join("tests", ".artifacts", "verify")) or ""
        try:
            v = json.load(open(os.path.join(ev, "verdicts.json"), encoding="utf-8"))
            m["rows"] = {r["id"]: (r.get("verdict"), r.get("status")) for r in v.get("rows", [])}
            m["scope"] = f"scope {v.get('scope')}, phase {v.get('phase')}, {was or 'date not saved'}"
        except Exception:
            m["verdict_note"] = "the verdict script could not grade the saved records: " + (out.strip().splitlines() or ["no output"])[-1][:140]
    else:
        m["verdict_note"] = "no saved verify records"
    # the phase filter: on a project with two or more checklists a verify keeps the tests carrying a
    # row id of the graded phase. A test nothing ties to any phase's row is run by no phase verify.
    tests_sh = os.path.join(box, ".tfcore", "utils", "tf-verify-tests.sh")
    has_filter = os.path.isfile(tests_sh) and '"phase%s "' in open(tests_sh, encoding="utf-8", errors="replace").read()
    tests = spec_tests(box, os.path.join(box, ".tfcore", "utils"))
    m["tests"] = len(tests)
    if has_filter and len(phases) >= 2:
        ids = set()
        for f in os.listdir(os.path.join(box, "docs")):
            if f.endswith("-Checklist.md") and "Deployment" not in f:
                ids |= {x.upper() for x in re.findall(r"(?m)^\s*\|\s*[`*]*(REQ-[A-Z]+-\d+)", open(os.path.join(box, "docs", f), encoding="utf-8", errors="replace").read())}
        named = lambda text: {x.upper() for x in re.findall(r"REQ-[A-Za-z]+-\d+", text)} & ids
        m["left_out"] = sorted((f, t) for f, t, text in tests if not named(text))
        # the surest part of that count: files that name no row id anywhere in their text
        m["no_id_files"] = sorted(f for f in {f for f, _t, _x in tests}
                                  if not named(open(os.path.join(box, f), encoding="utf-8", errors="replace").read()))
    return m


def compare(old, new):
    """-> the cells of one table row and the detail lines under it"""
    detail = []
    moved = [(rid, old["rows"][rid], new["rows"][rid]) for rid in sorted(set(old["rows"]) & set(new["rows"]))
             if old["rows"][rid] != new["rows"][rid]]
    only = sorted(set(old["rows"]) ^ set(new["rows"]))
    if new["verdict_note"] or old["verdict_note"]:
        rows_cell = new["verdict_note"] or old["verdict_note"]
        rows_cell = "not measured" if rows_cell == "no saved verify records" else "not measured (see below)"
        if "not measured (" in rows_cell:
            detail.append(f"rows: {new['verdict_note'] or old['verdict_note']}")
    else:
        rows_cell = f"{len(moved)} of {len(new['rows'])}" if moved else f"0 of {len(new['rows'])}"
        for rid, o, n in moved[:12]:
            detail.append(f"row {rid}: {o[0]} ({o[1]}) → {n[0]} ({n[1]})")
        if len(moved) > 12:
            detail.append(f"… and {len(moved) - 12} more rows")
        if only:
            detail.append(f"rows graded by one version only: {', '.join(only[:8])}")
    lo_old, lo_new = old["left_out"] or [], new["left_out"] or []
    stop = [t for t in lo_new if t not in lo_old]
    back = [t for t in lo_old if t not in lo_new]
    if not new["tests"] or (new["left_out"] is None and old["left_out"] is None):
        tests_cell = f"0 of {new['tests']}" if new["tests"] else "no spec files"
    else:
        files_all = {f for f, _t in lo_new}
        tests_cell = f"{len(stop)} of {new['tests']} stop" + (f", {len(back)} run again" if back else "") \
            + (f" ({len(lo_new)} left out in all, in {len(files_all)} file(s))" if len(lo_new) != len(stop) else f" (in {len(files_all)} file(s))" if stop else "") \
            + (f"; {len(new.get('no_id_files') or [])} file(s) name no row id at all" if lo_new else "")
        for f, t in stop[:10]:
            detail.append(f"stops running: {f} — \"{t[:80]}\"")
        if len(stop) > 10:
            detail.append(f"… and {len(stop) - 10} more tests")
    cells = []
    for key, label in (("doc", "document"), ("users", "test-users")):
        add, gone = sorted(new[key] - old[key]), sorted(old[key] - new[key])
        if add or gone:
            cells.append(f"{label}: +{len(add)} −{len(gone)}")
        for l in add[:6]:
            detail.append(f"appears ({label}): {l[:200]}")
        for l in gone[:6]:
            detail.append(f"goes ({label}): {l[:200]}")
        if len(add) > 6 or len(gone) > 6:
            detail.append(f"… {max(0, len(add) - 6)} more appear, {max(0, len(gone) - 6)} more go ({label})")
    find_cell = "; ".join(cells) or "none"
    lists = []
    for n in sorted(new["build"]):
        if old["build"].get(n) != new["build"][n]:
            lists.append(f"build list, phase {n}")
            detail.append(f"build list phase {n}: was «{(old['build'].get(n) or 'nothing')[:150]}» now «{new['build'][n][:150]}»")
    if old["next"] != new["next"]:
        lists.append("next command")
        detail.append(f"next command: was «{old['next'][:120]}» now «{new['next'][:120]}»")
    return [rows_cell, tests_cell, find_cell, ", ".join(lists) or "same"], detail


def digest(path):
    try:
        return hashlib.sha1(open(path, "rb").read()).hexdigest()
    except OSError:
        return None


def main(argv):
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    base = arg(argv, "--base", "deployed")
    roots = arg(argv, "--roots") or os.environ.get("TF_PROJECT_ROOTS", "").replace(":", ",")
    roots_file = os.path.expanduser("~/.techieflow/project-roots.txt")
    if roots:
        roots = [r for r in roots.split(",") if r]
    elif os.path.isfile(roots_file):
        roots = [l.strip() for l in open(roots_file, encoding="utf-8") if l.strip() and not l.startswith("#")]
    else:
        roots = [os.path.dirname(REPO)]
    only = set((arg(argv, "--only") or "").split(",")) - {""}
    work = tempfile.mkdtemp(prefix="tf-measure.")
    new_tfcore = os.path.join(REPO, ".tfcore")
    base_tfcore = base_tree(base, work)
    lines, details, skipped = [], [], []
    try:
        for project in find_projects(roots):
            name = os.path.basename(project)
            app, phases = app_of(project)
            if only and name not in only and app not in only:
                continue
            if not app:
                skipped.append(name)
                continue
            old_tfcore = base_tfcore or os.path.join(project, ".tfcore")
            sandbox(project, old_tfcore, os.path.join(work, name, "old"))
            sandbox(project, new_tfcore, os.path.join(work, name, "new"))
            old = measure(os.path.join(work, name, "old"), app, phases)
            new = measure(os.path.join(work, name, "new"), app, phases)
            cells, detail = compare(old, new)
            boot = [s for s in BROWSER_SIDE
                    if digest(os.path.join(old_tfcore, "utils", s)) != digest(os.path.join(new_tfcore, "utils", s))]
            has_ev = os.path.isfile(os.path.join(project, "tests", ".artifacts", "verify", "screens.json")) \
                or os.path.isfile(os.path.join(project, "tests", ".artifacts", "verify", "parity.json"))
            cells.append(f"{len(boot)} script(s)" if boot and (has_ev or new["tests"]) else "nothing to boot" if boot else "none changed")
            lines.append(f"| {name} | {len(phases)} | " + " | ".join(cells) + " |")
            if detail:
                details.append((name + (f" (last verify: {new.get('scope')})" if new.get("scope") else ""), detail))
            print(f"measured {name}", file=sys.stderr)
            if "--keep" not in argv:
                shutil.rmtree(os.path.join(work, name), ignore_errors=True)
        changed = [s for s in BROWSER_SIDE if base_tfcore and digest(os.path.join(base_tfcore, "utils", s)) != digest(os.path.join(new_tfcore, "utils", s))]
    finally:
        if "--keep" not in argv:
            shutil.rmtree(work, ignore_errors=True)
        else:
            print(f"kept: {work}", file=sys.stderr)
    out = [f"## What this change does to each project — old scripts: {base}, new scripts: this working tree", "",
           "| Project | Phase checklists | Rows whose verdict moves | Tests a phase verify stops running | Findings that appear or go | Build list, next command | Needs a boot to measure |",
           "|---|---|---|---|---|---|---|"] + lines + [""]
    if changed:
        out += ["Browser-side scripts that differ, not measured here (their result needs the running app): " + ", ".join(changed) + ".", ""]
    if skipped:
        out += ["No checklist yet, nothing to measure: " + ", ".join(skipped) + ".", ""]
    for name, detail in details:
        out += [f"**{name}**", ""] + [f"- {d}" for d in detail] + [""]
    text = "\n".join(out)
    print(text)
    if arg(argv, "--out"):
        open(arg(argv, "--out"), "w", encoding="utf-8").write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

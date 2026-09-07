#!/usr/bin/env python3
"""tf-devguide-list.py — the work list for *devguide (see tf-devguide-list.sh).

    bash .tfcore/utils/tf-devguide-list.sh <App> [--phase N] [--update]

Reads appKind and appPhase from .tfcore/core-config.yaml and prints:
  app             every routed page found in the code (route, file), matched to the phase's
                  UIDesign screens and to the roles in the UsageGuide's Test users table;
                  UIDesign screens with no code (a defect), routes with no UIDesign screen
  ui library      every public component under src/ (not the samples), with the sample page
                  that shows it, or "no sample" (a gap)
  service library every public service: DI registration methods, public interfaces and
                  classes under src/, with the sample that calls it, or "no sample"
  --update        which existing guide entries have files newer than the guide's "Verified on"
Prints NOTHING when no code is found. Writes nothing. Python 3 standard library only.
"""
import os
import re
import sys

SKIP = ("/bin/", "/obj/", "/node_modules/", "/.artifacts/", "/OldDocs/", "/.git/", "/dist/", "/wwwroot/lib/")
SAMPLE_DIRS = ("samples", "sample", "demos", "demo", "apps", "examples", "tests")
ROUTE_PATTERNS = [   # (file pattern, route pattern, page or endpoint)
    (r"\.(razor|cshtml)$", re.compile(r'(?m)^\s*@page\s+"([^"]+)"'), "page"),
    (r"\.cs$", re.compile(r'\[(?:Http(?:Get|Post|Put|Delete)|Route)\(\s*"([^"]+)"'), "endpoint"),
    (r"\.(ts|tsx|js|jsx|vue)$", re.compile(r'''\bpath\s*:\s*['"]([^'"]+)['"]'''), "page"),
    (r"\.(tsx|jsx)$", re.compile(r'''<Route\b[^>]*\bpath\s*=\s*['"]([^'"]+)['"]'''), "page"),
]


def die(msg):
    print(f"tf-devguide-list: {msg}", file=sys.stderr)
    sys.exit(2)


def read(p):
    with open(p, encoding="utf-8-sig", errors="replace") as f:   # -sig: a byte-order mark never hides line 1
        return f.read()


def cfg(key, default):
    p = os.path.join(".tfcore", "core-config.yaml")
    if os.path.isfile(p):
        m = re.search(rf"(?m)^{key}:\s*(\S+)", read(p))
        if m and m.group(1) not in ("null", "~"):
            return m.group(1).strip("'\"")
    return default


PRUNE = {"bin", "obj", "node_modules", ".git", ".artifacts", "OldDocs", "dist", ".tfcore", ".claude", ".opencode", "packages", "TestResults"}


def walk(root, exts, skip_samples=False):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in PRUNE]   # prune in place: never descend into build output
        dd = d.replace("\\", "/") + "/"
        if any(s in dd for s in SKIP):
            continue
        if skip_samples and any(f"/{s}/" in dd or dd.endswith(f"/{s}/") for s in SAMPLE_DIRS):
            continue
        for f in files:
            if f.lower().endswith(exts):
                yield os.path.join(d, f).replace("\\", "/").lstrip("./")


def roles_from_usageguide(app):
    p = os.path.join("docs", f"{app}-UsageGuide.md")
    roles = []
    if os.path.isfile(p):
        m = re.search(r"(?ms)^##\s+(?:\d+[.)]\s*)?Test users[^\n]*\n(.*?)(?=^## |\Z)", read(p))
        if m:
            for line in m.group(1).splitlines():
                c = [x.strip() for x in line.strip().strip("|").split("|")]
                if len(c) >= 4 and c[0].strip("`* ").isdigit():
                    roles.append((c[1].strip("`* "), c[3].strip("`* ")))
    return roles


def screens_from_uidesign(app, phase):
    pfx = f"{app}-" if phase <= 1 else f"{app}-P{phase}-"
    p = os.path.join("docs", f"{pfx}UIDesign.md")
    out = []
    if os.path.isfile(p):
        for m in re.finditer(r"(?m)^###\s+Screen:\s*(.+?)\s*\(`?([^)`]+)`?\)\s*$", read(p)):
            out.append((m.group(1).strip(), m.group(2).strip()))
    return out, p


def routes_in_code():
    found = []
    for f in walk(".", (".razor", ".cshtml", ".cs", ".ts", ".tsx", ".js", ".jsx", ".vue")):
        if "/" not in f:
            continue   # a top-level file is never a page
        txt = read(f)
        for ext_re, pat, what in ROUTE_PATTERNS:
            if re.search(ext_re, f, re.I):
                for m in pat.finditer(txt):
                    r = m.group(1).strip()
                    if r and not r.startswith("http") and "[" not in r:   # "[controller]/[action]" is a template, not a page
                        found.append((r, f, what))
    return found


def norm_route(r):
    """'/ManageAccount/{PageId:int}' -> '/manageaccount' : parameters and case never decide a match."""
    r = r.strip().rstrip("/").lower()
    r = re.sub(r"/\{[^}]+\}|/:[a-z_]+", "", r)
    return r or "/"


def sample_files(exts):
    """Files under the sample folders only (samples/, demos/, apps/, examples/), never the whole tree."""
    out = []
    for d in SAMPLE_DIRS:
        if d == "tests":
            continue
        if os.path.isdir(d):
            out += list(walk(d, exts))
    return out


def existing_entries(app, phase):
    pfx = f"{app}-" if phase <= 1 else f"{app}-P{phase}-"
    p = os.path.join("docs", f"{pfx}DevGuide.md")
    if not os.path.isfile(p):
        return p, None, []
    txt = read(p)
    m = re.search(r"(?im)^\|\s*Verified on\s*\|\s*([^|]+?)\s*\|", txt)
    return p, (m.group(1).strip() if m else None), re.findall(r"(?m)^###\s+(.+)$", txt)


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    app = argv[1]
    update = "--update" in argv
    phase = int(argv[argv.index("--phase") + 1]) if "--phase" in argv and argv.index("--phase") + 1 < len(argv) else int(cfg("appPhase", "1"))
    kind = cfg("appKind", "app").lower()
    if "--kind" in argv and argv.index("--kind") + 1 < len(argv):
        kind = argv[argv.index("--kind") + 1].lower()   # override for a project whose config lacks it
    sub = "app"
    if kind.startswith("lib"):
        razors = [f for f in walk("src", (".razor",), skip_samples=True)] if os.path.isdir("src") else []
        sub = "ui-library" if razors else "service-library"
    print(f"# tf-devguide-list — {app} — kind {sub} — phase {phase}")
    print()

    if sub == "app":
        screens, uip = screens_from_uidesign(app, phase)
        routes = routes_in_code()
        if not routes:
            print("NOTHING: no routed page found in the code (no @page, [Route], or path: declaration outside samples and tests). Build first.")
            return 0
        roles = roles_from_usageguide(app)
        by_route, endpoints = {}, {}
        for r, f, what in routes:
            if what == "endpoint":
                endpoints.setdefault(norm_route(r), []).append(f)
            else:
                by_route.setdefault(norm_route(r), []).append(f)
        if not by_route:
            print("NOTHING: no routed page found in the code; only API endpoints. Build the screens first.")
            return 0
        print(f"## Work list — {len(by_route)} route(s) in code, {len(screens)} screen(s) in {os.path.basename(uip)}, roles: " + (", ".join(sorted({r for _u, r in roles})) or "none in the UsageGuide"))
        matched = set()
        for name, route in screens:
            key = norm_route(route)
            files = by_route.get(key)
            if files:
                matched.add(key)
                print(f"- {name} ({route}) — {', '.join(sorted(set(files))[:3])}")
            else:
                print(f"- {name} ({route}) — NO CODE FOUND for this route: log it as a defect on the screen's row")
        extra = [k for k in by_route if k not in matched]
        if extra:
            print()
            print("## Pages in code with no UIDesign screen (document them, and tell the analyst)")
            for k in sorted(extra):
                print(f"- {k} — {', '.join(sorted(set(by_route[k]))[:3])}")
        if endpoints:
            print()
            print(f"## API endpoints ({len(endpoints)}; not screens, the call chains end here)")
            for k in sorted(endpoints):
                print(f"- {k} — {', '.join(sorted(set(endpoints[k]))[:2])}")
    elif sub == "ui-library":
        comps = [f for f in walk("src", (".razor",), skip_samples=True)]
        if not comps:
            print("NOTHING: no component under src/. Build first.")
            return 0
        samples = sample_files((".razor", ".cshtml", ".html"))
        stxt = {f: read(f) for f in samples}
        print(f"## Work list — {len(comps)} component(s), grouped by folder; {len(samples)} sample page(s)")
        for f in sorted(comps):
            name = os.path.splitext(os.path.basename(f))[0]
            shown = [s for s, t in stxt.items() if re.search(rf"<{re.escape(name)}\b", t)]
            print(f"- {os.path.dirname(f).split('/')[-1]} / {name} — {f} — " + (f"shown in {shown[0]}" + (f" (+{len(shown)-1})" if len(shown) > 1 else "") if shown else "NO SAMPLE shows it: a sample gap to log"))
    else:
        files = [f for f in walk("src", (".cs", ".ts", ".py", ".go", ".java"), skip_samples=True)]
        if not files:
            print("NOTHING: no source under src/. Build first.")
            return 0
        items = []
        for f in files:
            t = read(f)
            for m in re.finditer(r"public\s+static\s+\w[\w<>,\s]*\s+(Add\w+)\s*\(\s*this\s+", t):
                items.append(("registration", m.group(1), f))
            for m in re.finditer(r"public\s+(?:partial\s+)?interface\s+(I\w+)", t):
                items.append(("interface", m.group(1), f))
            for m in re.finditer(r"public\s+(?:sealed\s+|abstract\s+)?(?:partial\s+)?class\s+(\w+)", t):
                items.append(("class", m.group(1), f))
        samples = sample_files((".cs", ".razor", ".ts", ".py"))
        stxt = {f: read(f) for f in samples}
        items = sorted(set(items), key=lambda x: (x[0] != "registration", x[0] != "interface", x[1]))   # overloads once
        print(f"## Work list — {len(items)} public item(s) under src/, {len(samples)} sample file(s)")
        for kind_, name, f in items:
            used = [s for s, t in stxt.items() if re.search(rf"\b{re.escape(name)}\b", t)]
            print(f"- {kind_} {name} — {f} — " + (f"called in {used[0]}" + (f" (+{len(used)-1})" if len(used) > 1 else "") if used else "NO SAMPLE calls it: a sample gap to log"))

    if update:
        gp, ver, entries = existing_entries(app, phase)
        print()
        if ver is None:
            print(f"## --update: no existing guide at {gp} (or no \"Verified on\"); everything is new")
        else:
            print(f"## --update: existing guide {gp}, Verified on {ver}, {len(entries)} entries")
            try:
                import datetime
                cutoff = datetime.datetime.strptime(ver[:10], "%Y-%m-%d").timestamp()
            except Exception:
                cutoff = None
            if cutoff:
                changed = [f for f in walk(".", (".razor", ".cshtml", ".cs", ".ts", ".tsx", ".js", ".py"), skip_samples=False)
                           if f.startswith(("src/",)) and os.path.getmtime(f) > cutoff]
                print(f"- {len(changed)} source file(s) changed since then; remap the entries they serve, keep the rest verbatim")
                for f in changed[:30]:
                    print(f"  - {f}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except BrokenPipeError:
        sys.exit(0)   # piped into head: not an error
    except Exception as e:
        die(str(e))

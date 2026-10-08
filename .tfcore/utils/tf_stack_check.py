#!/usr/bin/env python3
"""tf_stack_check.py — does the code use the packages the Architecture requires? (2026-10-08)

    bash .tfcore/utils/tf-stack-check.sh <App> [--json-out <file>]

Reads the `Required packages:` line of docs/<App>-Architecture.md (Stack decisions), which copies the
answer set's own line: each package in backticks, or "none". Then looks for each package in the
project's dependency files, whatever the stack: .csproj/.fsproj/.vbproj, Directory.*.props,
packages.config, package.json, requirements*.txt, pyproject.toml, Pipfile, go.mod, Cargo.toml, Gemfile,
pom.xml, build.gradle(.kts), composer.json, pubspec.yaml. Build output, dependencies, tests/.artifacts
and the framework itself are not searched.

Why: in the first *develop-end-to-end proof on OpenCode the model searched for a package by the wrong
name, decided the mandated UI library was not published, built the screen with plain components and
had every row Verified. Nothing checked that the code used what the Stack decisions named.

Prints PASS (every package referenced), FAIL (with the packages missing), or NONE (no line, or
"none"). tf-verify-verdict.py runs it itself and fails every row's build check on FAIL.
Exit 0 PASS or NONE · 1 FAIL · 2 could not run. Python 3 standard library only.
"""
import json
import os
import re
import sys

PRUNE = {"bin", "obj", "node_modules", ".git", ".artifacts", ".tfcore", ".claude", ".opencode", "dist",
         "packages", "TestResults", ".venv", "venv", "target", "vendor", "OldDocs"}
NAMES = re.compile(r"(?i)^(?:.*\.(?:cs|fs|vb)proj|directory\.(?:packages|build)\.props|packages\.config|package\.json|"
                   r"requirements[\w.-]*\.txt|pyproject\.toml|pipfile|go\.mod|cargo\.toml|gemfile|pom\.xml|"
                   r"build\.gradle(?:\.kts)?|composer\.json|pubspec\.yaml)$")


def required(root, app):
    """-> (list of packages, the Architecture path) ; [] when there is no line or it says none."""
    p = os.path.join(root, "docs", f"{app}-Architecture.md")
    if not os.path.isfile(p):
        return [], p
    for line in open(p, encoding="utf-8", errors="replace"):
        m = re.match(r"\s*(?:[-*]\s*)?\**Required packages:?\**:?\s*(.*)$", line, re.I)
        if m:
            return re.findall(r"`([^`\s]+)`", m.group(1)), p
    return [], p


def manifests(root):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in PRUNE and not x.startswith(".")]
        for f in files:
            if NAMES.match(f):
                yield os.path.join(d, f)


def check(root, app):
    pkgs, arch = required(root, app)
    if not pkgs:
        return {"verdict": "NONE", "architecture": os.path.relpath(arch, root), "required": [], "missing": [], "found": {}}
    found = {}
    files = list(manifests(root))
    for f in files:
        try:
            text = open(f, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for pk in pkgs:
            if re.search(r"(?<![A-Za-z0-9._-])%s(?![A-Za-z0-9._-])" % re.escape(pk), text, re.I):
                found.setdefault(pk, os.path.relpath(f, root))
    missing = [pk for pk in pkgs if pk not in found]
    return {"verdict": "FAIL" if missing else "PASS", "architecture": os.path.relpath(arch, root),
            "required": pkgs, "missing": missing, "found": found, "files_searched": len(files)}


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if len(argv) >= 2 else 2
    app = argv[1]
    r = check(os.getcwd(), app)
    if "--json-out" in argv:
        out = argv[argv.index("--json-out") + 1]
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        json.dump(r, open(out, "w"), indent=1)
    if r["verdict"] == "NONE":
        print(f"NONE {app}: {r['architecture']} lists no required packages")
    elif r["verdict"] == "PASS":
        print(f"PASS {app}: " + ", ".join(f"{k} in {v}" for k, v in r["found"].items()))
    else:
        print(f"FAIL {app}: the Architecture requires {', '.join(r['missing'])}; no project file references "
              + ("it" if len(r["missing"]) == 1 else "them") + f" ({r['files_searched']} searched). Add the package; never replace it with a workaround")
    return 1 if r["verdict"] == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

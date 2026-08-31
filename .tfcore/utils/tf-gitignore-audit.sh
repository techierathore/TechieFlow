#!/usr/bin/env bash
# TechieFlow — build-output ignore audit. Run by the scaffolds and by
# update-framework.sh on every refresh; safe to run by hand at any time.
#
#   bash .tfcore/utils/tf-gitignore-audit.sh [<repo>] [--fix] [--dry-run]
#
# WHAT IT ASKS, and it is two questions rather than one:
#
#   1. Does .gitignore carry build-output rules for THE STACK THIS REPO IS
#      ACTUALLY WRITTEN IN?
#   2. Is that build output already TRACKED?
#
# The second half is the half that is usually forgotten, and it is the half that
# matters: **a tracked file is never ignored, no matter what the ignore file
# says.** Adding the rule later fixes nothing on its own.
#
# WHY IT EXISTS (TfLens TF-007 companion 1, located 2026-08-29). The day-1 scaffold
# generated a complete, careful `.gitignore` — `.tfcore/`, `.claude/`,
# `node_modules/`, `tests/.artifacts/`, `playwright-report/`, `logs/` — every
# section framework-managed and labelled as such. It contained **no `bin/`, no
# `obj/`, and no rule of any kind for the stack the project was written in**, in a
# repository whose `core-config.yaml` and four `.csproj` files said .NET throughout.
#
# The consequence was mechanical and immediate: the first build produced build
# output, and a commit named — with some irony — "Updated git ignore" swept **1,041**
# build-output files into the index. Four later commits reached **1,962**.
#
# That is not merely untidy. Those files carry the static-web-assets manifest, whose
# content roots are MACHINE-ABSOLUTE: `/mnt/c/…` + `/home/<user>/.nuget/…` after a
# WSL build, `C:\…` + `C:\Users\<user>\.nuget\…` after a Windows build. Committing
# them ships one machine's absolute paths to another — a plausible route to exactly
# the asset 404 that TF-007 itself is about.
#
# WHOSE FAULT IT IS, stated plainly because it was first stated wrongly. The agent
# that ran day-1 generated that file and did not read it, having just chosen the
# stack and written the solution itself. **That agent is responsible.** This script
# makes the mistake harder to make — which is worth doing precisely because it is so
# easy to make — but a generator's omission is never a defence for the agent
# operating the generator.
#
# NO GIT. This script contains no git command and never will: `_metrics-emit-gate.md`
# constraint 1 reserves that for `tf-metrics.sh` alone, and `block-git.sh` is right to
# block it. The tracked-file check reads `.git/index` directly — a binary file with a
# documented format, and reading a file is not a git operation. Remediation is PRINTED
# for the owner to run, never executed.
#
# Exit codes: 0 clean (or --fix applied) · 1 rules missing · 2 build output is TRACKED
#             (owner action required) · 3 both.

set -uo pipefail

REPO="."; FIX=0; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)      FIX=1; shift ;;
    --dry-run)  DRY=1; shift ;;
    -h|--help)  sed -n '2,45p' "$0"; exit 0 ;;
    *)          REPO="$1"; shift ;;
  esac
done
[[ -d "$REPO" ]] || { echo "tf-gitignore-audit: not a directory: $REPO" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "tf-gitignore-audit: python3 required" >&2; exit 0; }

TF_REPO="$REPO" TF_FIX="$FIX" TF_DRY="$DRY" python3 - <<'PY'
import os, struct, sys

REPO = os.path.abspath(os.environ["TF_REPO"])
FIX  = os.environ["TF_FIX"] == "1"
DRY  = os.environ["TF_DRY"] == "1"

# --- the stacks, and what each one leaves behind ---------------------------
# Detected FROM THE TREE, never from a config value: a scaffold copies
# core-config.yaml between projects, and the day-1 tasks that write it are the very
# ones this audit exists to catch. The file system is the fact.
STACKS = [
    ("dotnet", (".csproj", ".fsproj", ".vbproj", ".sln", ".slnx"),
     ["bin/", "obj/", "*.user", "TestResults/"]),
    ("node",   ("package.json",),        ["dist/", "build/", ".next/", ".nuxt/", ".turbo/"]),
    ("python", ("pyproject.toml", "setup.py", "requirements.txt"),
     ["__pycache__/", "*.py[cod]", ".venv/", "venv/", ".pytest_cache/", "*.egg-info/"]),
    ("go",     ("go.mod",),              ["/bin/", "*.test"]),
    ("rust",   ("Cargo.toml",),          ["target/"]),
    ("java",   ("pom.xml", "build.gradle", "build.gradle.kts"), ["target/", "build/", ".gradle/"]),
]

# `package.json` alone does NOT make a repo a Node project, and this exception is
# load-bearing rather than fussy: verify-phase §1 runs `npm init -y` in EVERY repo
# to provision Playwright, so a bare package.json sits in essentially every .NET
# project the framework has ever touched. Treating that as a Node stack would append
# `dist/`, `build/`, `.next/`, `.nuxt/`, `.turbo/` to 19 repos that build none of
# them — noise in a file the owner reads, and `build/` is a plausible real directory
# name to shadow by accident.
#
# So Node is claimed only on evidence of an actual build: a `build` script, or a
# bundler/framework config on disk. This was caught by the dry run before the
# propagation, which is what dry runs are for.
BUNDLER_CONFIGS = ("next.config.js", "next.config.mjs", "next.config.ts",
                   "nuxt.config.js", "nuxt.config.ts", "vite.config.js",
                   "vite.config.ts", "webpack.config.js", "angular.json",
                   "svelte.config.js", "rollup.config.js", "gatsby-config.js",
                   "remix.config.js", "astro.config.mjs")


def _is_real_node(root, files):
    if any(f in BUNDLER_CONFIGS for f in files):
        return True
    pj = os.path.join(root, "package.json")
    try:
        import json as _json
        data = _json.load(open(pj, encoding="utf-8"))
    except Exception:
        return False
    scripts = data.get("scripts") or {}
    # `npm init -y` writes exactly one script: a `test` stub that echoes and exits 1.
    return any(k in scripts for k in ("build", "dist", "bundle", "compile"))

SKIP_DIRS = {".git", "node_modules", ".tfcore", "bin", "obj", "target", "dist",
             "build", ".venv", "venv", "__pycache__", ".next"}


def detect():
    found = set()
    for root, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        if root.count(os.sep) - REPO.count(os.sep) > 3:
            dirs[:] = []
        for name, markers, _ in STACKS:
            for f in files:
                if f in markers or any(f.endswith(m) for m in markers if m.startswith(".")):
                    if name == "node" and not _is_real_node(root, files):
                        continue        # a Playwright-only package.json is not a Node app
                    found.add(name)
    return found


def gitignore_lines():
    p = os.path.join(REPO, ".gitignore")
    try:
        return [l.strip().replace("\r", "") for l in open(p, encoding="utf-8", errors="replace")]
    except FileNotFoundError:
        return []


def covered(rule, lines):
    """Is this rule already expressed? Match tolerantly — an owner may legitimately
    have written `**/bin/`, `/bin`, or `bin` — and NEVER rewrite existing content."""
    core = rule.strip("/*").rstrip("/")
    for l in lines:
        if not l or l.startswith("#"):
            continue
        c = l.lstrip("!").strip().replace("**/", "").strip("/")
        if c == core or c == rule.strip("/") or c.rstrip("/") == core:
            return True
    return False


def tracked_paths():
    """Read .git/index directly. Returns the set of tracked paths, or None when the
    index cannot be read (a bare repo, a worktree file, a version we do not know) —
    None means 'not checked', never 'nothing tracked'."""
    gitdir = os.path.join(REPO, ".git")
    if os.path.isfile(gitdir):                      # a worktree: .git is a pointer file
        try:
            for line in open(gitdir, encoding="utf-8"):
                if line.startswith("gitdir:"):
                    gd = line.split(":", 1)[1].strip()
                    gitdir = gd if os.path.isabs(gd) else os.path.join(REPO, gd)
                    break
        except Exception:
            return None
    idx = os.path.join(gitdir, "index")
    try:
        raw = open(idx, "rb").read()
    except Exception:
        return None
    if len(raw) < 12 or raw[:4] != b"DIRC":
        return None
    ver, n = struct.unpack(">II", raw[4:12])
    if ver not in (2, 3, 4):
        return None
    if ver == 4:
        return None                                  # path-compressed; not worth guessing
    out, pos = set(), 12
    try:
        for _ in range(n):
            start = pos
            pos += 62                                # fixed entry header
            end = raw.index(b"\x00", pos)
            out.add(raw[pos:end].decode("utf-8", "replace"))
            pos = end + 1
            pos = start + ((pos - start + 7) // 8) * 8   # 8-byte padding
    except Exception:
        return None
    return out


def matches(path, rule):
    core = rule.strip("/*").rstrip("/")
    if rule.startswith("*."):
        return path.endswith(rule[1:])
    if "[" in rule:
        return path.endswith((".pyc", ".pyo", ".pyd"))
    parts = path.split("/")
    return core in parts[:-1] or parts[-1] == core


stacks = detect()
lines = gitignore_lines()
wanted = []
for name, _, rules in STACKS:
    if name in stacks:
        wanted += [(name, r) for r in rules]

missing = [(s, r) for s, r in wanted if not covered(r, lines)]

tracked = tracked_paths()
offenders = {}
if tracked is not None:
    for s, r in wanted:
        hits = [p for p in tracked if matches(p, r)]
        if hits:
            offenders[r] = hits

label = ", ".join(sorted(stacks)) or "none detected"
print("  gitignore audit — stack: %s" % label)

rc = 0
if not stacks:
    print("    no application stack detected yet (docs-only repo, or day-1 has not run)")
elif not missing:
    print("    build-output rules present for every detected stack")
else:
    rc |= 1
    names = " ".join(r for _, r in missing)
    if FIX and not DRY:
        with open(os.path.join(REPO, ".gitignore"), "a", encoding="utf-8", newline="\n") as fh:
            fh.write("\n# Build output — %s (managed by scaffold/update-framework.sh)\n" % label)
            fh.write("\n".join(r for _, r in missing) + "\n")
        print("    ADDED build-output rules: %s" % names)
        rc &= ~1
    elif DRY:
        print("    WOULD add build-output rules: %s" % names)
    else:
        print("    ⚠ MISSING build-output rules: %s" % names)
        print("      add them with: bash .tfcore/utils/tf-gitignore-audit.sh . --fix")

if tracked is None:
    print("    tracked-file check skipped (no readable .git/index) — rules alone do not")
    print("    prove build output is untracked; re-run where the index is readable")
elif offenders:
    rc |= 2
    total = sum(len(v) for v in offenders.values())
    print("    ⚠ %d build-output file(s) are ALREADY TRACKED. An ignore rule does NOT" % total)
    print("      untrack a file — until these are removed from the index, every rule")
    print("      above is inert and one machine's absolute paths keep shipping to the next.")
    for r, hits in sorted(offenders.items()):
        ex = sorted(hits)[:3]
        print("        %-14s %4d file(s)   e.g. %s" % (r, len(hits), ", ".join(ex)))
    print("      OWNER ACTION (this script never runs git, and never will):")
    # The path printed must be the OUTPUT directory itself, never an ancestor:
    # `git rm -r --cached src/App` would untrack the source alongside the artefacts,
    # which is a far worse outcome than the problem being fixed.
    targets = set()
    for r, hits in sorted(offenders.items()):
        core = r.strip("/*").rstrip("/")
        for h in hits:
            parts = h.split("/")
            if core in parts[:-1]:
                targets.add("/".join(parts[:parts.index(core) + 1]))
            else:
                targets.add(h)                      # a file rule (*.user, *.test)
    for t in sorted(targets)[:12]:
        print("        git rm -r --cached '%s'" % t)
    if len(targets) > 12:
        print("        ... and %d more path(s); see the full list above" % (len(targets) - 12))
    print("      then commit. The working files stay on disk; only the index entries go.")
else:
    print("    no build output is tracked")

raise SystemExit(rc)
PY

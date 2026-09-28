#!/usr/bin/env bash
# TechieFlow hook — automatic sweep of expired run material (added 2026-08-26).
#
# Wired as a SessionStart hook in .claude/settings.json (Claude Code), as
# on the first root
# `session.created` in .opencode/plugin/techieflow.js (OpenCode).
#
# WHY: verify-phase.md §1 pins every run artifact under tests/.artifacts/ and
# the guard-artifacts.sh PreToolUse hook enforces it. That fixed WHERE the
# material lands but not that it ever leaves: Playwright wipes only its own
# outputDir, so per-cluster subfolders, harness scripts and multi-hundred-MB
# host logs accumulate forever (TechieBlog: 1.1 GB under tests/.artifacts/ +
# 101 MB of .verify/*.log, most of it two weeks stale). Run material is only
# needed until its verify pass has written the checklist Remarks — after that
# it is litter. This hook deletes it once it ages out, so nobody has to.
#
# POLICY
#   Sweep roots (all gitignored, all machine-generated, never work product):
#     tests/.artifacts/        .verify/
#   Files older than the retention window are deleted; directories left empty
#   are removed. Newer files are untouched — a run in flight is never disturbed
#   (its files are minutes old), and a mixed-age dir like tests/.artifacts/harness/
#   keeps its recent scripts and loses its stale ones.
#   Repo-root legacy dirs (banned outright by the artifact-location rule, kept
#   only by the .gitignore for legacy trees) are removed REGARDLESS of age:
#     test-results/  test-results-*/  scripts-*/  playwright-report/
#   The project's own tracked scripts/ is never touched (needs the hyphen).
#   tests/verify/ (promoted, tracked specs) is never touched (outside the roots).
#   A file under the roots that a test names by path (tests/.artifacts/<folder>/<name>) is kept at
#   any age, with everything below it (Lekhak TF-004); the summary says how many were kept.
#
# RETENTION: default 7 days. Override per project with `artifactRetentionDays: N`
# in .tfcore/core-config.yaml, or per run with TF_ARTIFACT_RETENTION_DAYS=N.
# 0 disables the age sweep (legacy root dirs are still removed).
# TF_SWEEP_DRY_RUN=1 prints what would go and deletes nothing.
# Throttled to one sweep per hour per project via .tfcore/.session/sweep.stamp
# (TF_SWEEP_FORCE=1 bypasses) so harnesses that re-fire session-start per prompt
# do not walk the tree every turn.
#
# HARD RULES — NO VETO, NO ESCAPE. Exits 0 unconditionally (a sweep that fails
# must never block a session). Every path is resolved and checked to sit under
# the project root; symlinks are never followed; nothing outside the listed
# roots is ever considered. stdout (a one-line summary, only when something was
# removed) is surfaced into the session so the agent knows the sweep ran.

INPUT="$(cat 2>/dev/null)"
command -v python3 >/dev/null 2>&1 || exit 0

TF_HOOK_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null
import json, os, re, shutil, sys, time, fnmatch

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT") or "{}")
except Exception:
    data = {}

root = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("TF_PROJECT_DIR") or data.get("cwd") or ""
if not root or not os.path.isdir(os.path.join(root, ".tfcore")):
    raise SystemExit(0)
root = os.path.realpath(root)

DRY = os.environ.get("TF_SWEEP_DRY_RUN") == "1"

# Throttle: at most one sweep per hour per project, whichever harness fires it
# (a harness may re-fire session-start on every prompt; a walk of a big tree on every
# turn is waste). TF_SWEEP_FORCE=1 bypasses. Dry runs never touch the stamp.
stamp = os.path.join(root, ".tfcore", ".session", "sweep.stamp")
if not DRY and os.environ.get("TF_SWEEP_FORCE") != "1":
    try:
        if time.time() - os.stat(stamp).st_mtime < 3600:
            raise SystemExit(0)
    except FileNotFoundError:
        pass
    try:
        os.makedirs(os.path.dirname(stamp), exist_ok=True)
        with open(stamp, "w") as fh:
            fh.write(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + "\n")
    except Exception:
        pass

# ---- retention -------------------------------------------------------------
def retention_days():
    env = os.environ.get("TF_ARTIFACT_RETENTION_DAYS")
    if env is not None and env.strip() != "":
        try:
            return max(0, int(env))
        except ValueError:
            pass
    try:
        with open(os.path.join(root, ".tfcore", "core-config.yaml"), encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = re.match(r"^\s*artifactRetentionDays\s*:\s*(\d+)\s*(#.*)?$", line)
                if m:
                    return max(0, int(m.group(1)))
    except Exception:
        pass
    return 7

DAYS = retention_days()
CUTOFF = time.time() - DAYS * 86400

SWEEP_ROOTS = [os.path.join("tests", ".artifacts"), ".verify"]

# ---- what a test names is not litter (Lekhak TF-004) ---------------------------
# A spec that reads tests/.artifacts/harness/hindi-src lost it on the eighth day, and two rows failed
# "the crawl produced no result" on a working product. Any path under the sweep roots that a file of
# the project's tests (or its Playwright config) names is kept, with everything below it, whatever its
# age. The right home for a fixture is still tests/verify/fixtures/, outside the sweep.
# Only a NAMED thing inside a folder counts (tests/.artifacts/<folder>/<name>): a folder a test writes
# into is named with a variable after it (`shots/${name}.png`), which the pattern stops at, and the
# framework's own output folders are never kept. The Playwright config is not read: it names outputs.
KEEP_RE = re.compile(r"(?:tests[/\\]+\.artifacts|\.verify)[/\\]+[^'\"`\s)\]},;*?<>|${}+]+")
OUTPUTS = ("tests/.artifacts/verify/", "tests/.artifacts/build/", "tests/.artifacts/test-results",
           "tests/.artifacts/playwright", "tests/.artifacts/regression", "tests/.artifacts/doc-check/")
TEXT_EXT = (".ts", ".js", ".mjs", ".cjs", ".cs", ".py", ".json", ".sh", ".cmd", ".ps1", ".yaml", ".yml", ".txt", ".md")
keep = set()
def scan_refs(fp):
    try:
        if os.path.getsize(fp) > 2 * 1024 * 1024:
            return
        with open(fp, encoding="utf-8", errors="replace") as fh:
            for m in KEEP_RE.finditer(fh.read()):
                k = re.sub(r"/+", "/", m.group(0).replace("\\", "/")).rstrip("/.")
                if k.count("/") >= (2 if k.startswith(".verify/") else 3) and not (k + "/").startswith(OUTPUTS):
                    keep.add(k)
    except Exception:
        pass
tests_dir = os.path.join(root, "tests")
if os.path.isdir(tests_dir) and not os.path.islink(tests_dir):
    for dp, dns, fns in os.walk(tests_dir, followlinks=False):
        dns[:] = [d for d in dns if d not in (".artifacts", "node_modules", "bin", "obj", ".git")]
        for f in fns:
            if f.endswith(TEXT_EXT):
                scan_refs(os.path.join(dp, f))
kept_n = 0
def kept(fp):
    rel = os.path.relpath(fp, root).replace(os.sep, "/")
    return any(rel == k or rel.startswith(k + "/") for k in keep)
LEGACY_ROOT_GLOBS = ["test-results", "test-results-*", "scripts-*", "playwright-report"]

removed_files = 0
removed_dirs = 0
removed_bytes = 0
legacy = []

def inside(p):
    rp = os.path.realpath(p)
    return rp == root or rp.startswith(root + os.sep)

def rm_file(p):
    global removed_files, removed_bytes
    try:
        sz = os.lstat(p).st_size
        if not DRY:
            os.unlink(p)
        removed_files += 1
        removed_bytes += sz
    except Exception:
        pass

def rm_tree(p):
    """Delete a directory tree. Symlinks are unlinked, never followed."""
    global removed_dirs, removed_bytes, removed_files
    if os.path.islink(p):
        rm_file(p)
        return
    for dp, dns, fns in os.walk(p, topdown=False, followlinks=False):
        for f in fns:
            rm_file(os.path.join(dp, f))
        for d in dns:
            fp = os.path.join(dp, d)
            if os.path.islink(fp):
                rm_file(fp)
            else:
                try:
                    if not DRY:
                        os.rmdir(fp)
                except Exception:
                    pass
    try:
        if not DRY:
            os.rmdir(p)
        removed_dirs += 1
    except Exception:
        pass

# ---- 1. age sweep under the sanctioned roots --------------------------------
if DAYS > 0:
    for rel in SWEEP_ROOTS:
        top = os.path.join(root, rel)
        if os.path.islink(top) or not os.path.isdir(top) or not inside(top):
            continue
        for dp, dns, fns in os.walk(top, topdown=False, followlinks=False):
            if not inside(dp):
                continue
            for f in fns:
                fp = os.path.join(dp, f)
                try:
                    st = os.lstat(fp)
                except Exception:
                    continue
                if st.st_mtime < CUTOFF:
                    if keep and kept(fp):
                        kept_n += 1
                        continue
                    rm_file(fp)
            # remove dirs emptied by this sweep (never the root itself)
            if dp != top:
                try:
                    if not os.listdir(dp):
                        if not DRY:
                            os.rmdir(dp)
                        removed_dirs += 1
                except Exception:
                    pass

# ---- 2. banned repo-root legacy dirs — any age -------------------------------
try:
    for name in os.listdir(root):
        p = os.path.join(root, name)
        if not os.path.isdir(p) or os.path.islink(p):
            continue
        if any(fnmatch.fnmatch(name, g) for g in LEGACY_ROOT_GLOBS) and inside(p):
            legacy.append(name)
            rm_tree(p)
except Exception:
    pass

# ---- summary (stdout -> session context) -------------------------------------
if removed_files or removed_dirs or legacy:
    mb = removed_bytes / (1024 * 1024)
    parts = [f"TechieFlow sweep-artifacts{' (DRY RUN)' if DRY else ''}: removed {removed_files} file(s), "
             f"{removed_dirs} dir(s), {mb:.1f} MB — run material older than {DAYS}d under "
             f"tests/.artifacts/ and .verify/"]
    if legacy:
        parts.append("banned repo-root legacy dirs removed: " + ", ".join(sorted(legacy)))
    if kept_n:
        parts.append(f"kept {kept_n} old file(s) a test names by path (move them to tests/verify/fixtures/)")
    print("; ".join(parts))
elif kept_n:
    print(f"TechieFlow sweep-artifacts: kept {kept_n} file(s) older than {DAYS}d because a test names them by path; "
          "move them to tests/verify/fixtures/")
PY
exit 0

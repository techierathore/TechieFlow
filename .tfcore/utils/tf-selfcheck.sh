#!/usr/bin/env bash
# TechieFlow — the framework's own scripts, run against THIS project's real files.
#
#   bash .tfcore/utils/tf-selfcheck.sh [<repo>] [--report]
#
# WHY IT EXISTS. Nine framework defects reached TfLens in three weeks. Every one was
# found mid-build, in the application's repository, and could only be fixed in the
# framework's — so each cost a switch between repos, a feedback entry, a maintenance
# sitting and a re-deploy. The defects were not exotic: a checklist with a row that
# could never clear, a BRD carrying the anchors its own link checker demands, a metrics
# file holding the framework's own verdicts. They were simply never run against a real
# project's real files before the project ran them (MISS-TechieFlow-20260909-01).
#
# So this runs them here, first, and says which are broken ON THIS PROJECT. A FAIL is a
# FRAMEWORK defect, never the project's: nothing here grades the application.
#
# Run it before a build pass, or any time. It writes nothing, boots nothing, and never
# runs git. Python 3 standard library only.
#
# --report prints a ready-to-paste entry for the project's framework-feedback file, so
# filing costs one paste instead of a page.
#
# EXIT: 0 every framework script works here · 1 at least one is broken · 3 cannot run.

set -uo pipefail
REPO="."; REPORT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)  REPORT=1; shift ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         REPO="$1"; shift ;;
  esac
done
[[ -d "$REPO" ]] || { echo "tf-selfcheck: not a directory: $REPO" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "tf-selfcheck: python3 required" >&2; exit 3; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TF_REPO="$REPO" TF_UTILS="$HERE" TF_REPORT="$REPORT" python3 - <<'PY'
import json, os, re, subprocess, sys

REPO = os.path.abspath(os.environ["TF_REPO"])
UTILS = os.environ["TF_UTILS"]
TELEM = os.path.join(os.path.dirname(UTILS), "telemetry")
REPORT = os.environ["TF_REPORT"] == "1"
findings = []          # (script, what is wrong, the one-line fix hint)
lines = []


def ok(script, msg):
    lines.append("ok    %-20s %s" % (script, msg))


def broken(script, msg, hint=""):
    lines.append("FAIL  %-20s %s" % (script, msg))
    findings.append((script, msg, hint))


def skip(script, msg):
    lines.append("--    %-20s %s" % (script, msg))


def run(cmd, cwd=REPO, timeout=120):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except Exception as e:
        return 99, str(e)


def app_names():
    """Every application this repo holds a checklist for. The checklist is the framework's
    single source of truth, so its name is the app's name — no config value is trusted,
    because core-config.yaml is rsynced between projects and is the thing most likely to
    be stale (the same reason tf-gitignore-audit detects the stack from the tree)."""
    d = os.path.join(REPO, "docs")
    out = []
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            m = re.match(r"^(.+?)(?:-P(\d+))?-Checklist\.md$", f)
            if m and "Deployment" not in f:
                out.append((m.group(1), int(m.group(2) or 1), os.path.join(d, f)))
    return out


# ---- 1. the deployed copy is intact ----------------------------------------------------
# A framework script that will not even parse is the cheapest possible thing to catch and
# the most expensive to meet mid-build.
# Parsed in-process and the shells checked in ONE bash, not one subprocess per file:
# 54 scripts meant 54 process launches and ten seconds, which is enough to make a check
# that should run at the top of every command feel like a tax and get skipped.
bad_parse, shells = [], []
for folder in (UTILS, TELEM):
    if not os.path.isdir(folder):
        continue
    for f in sorted(os.listdir(folder)):
        full = os.path.join(folder, f)
        if f.endswith(".py"):
            try:
                import ast
                ast.parse(open(full, encoding="utf-8", errors="replace").read(), filename=full)
            except SyntaxError:
                bad_parse.append(f)
        elif f.endswith(".sh"):
            shells.append(full)
if shells:
    script = "for f in " + " ".join('"%s"' % x for x in shells) + \
             '; do bash -n "$f" 2>/dev/null || echo "$f"; done'
    rc, out = run(["bash", "-c", script])
    bad_parse += [os.path.basename(x) for x in out.split() if x.strip()]
if bad_parse:
    broken("deployed copy", "%d script(s) do not parse: %s" % (len(bad_parse), ", ".join(bad_parse[:6])),
           "re-run update-framework.sh; if it persists the framework shipped a broken script")
else:
    ok("deployed copy", "every framework script parses")

# ---- 2. the working list accounts for every checklist row ------------------------------
# TF-019: a row can sit at `Needs re-verify` forever, which pinned the mode and dropped
# every not-started row out of the list AND out of the counts, so a build pass could report
# a phase finished with rows at 0%. The arithmetic is the check: every row lands in exactly
# one of open / terminal / Blocked.
apps = app_names()
if not apps:
    skip("tf-build-list", "no checklist in docs/ yet")
for app, phase, path in apps:
    rc, out = run(["bash", os.path.join(UTILS, "tf-build-list.sh"), app] +
                  ([] if phase <= 1 else ["--phase", str(phase)]))
    label = "%s p%d" % (app, phase)
    if rc not in (0, 2):
        broken("tf-build-list", "%s: exited %d" % (label, rc), out.strip().splitlines()[0][:120] if out.strip() else "")
        continue
    m = re.search(r"Mode: (\w+) — (\d+) row\(s\) to build; (\d+) terminal, (\d+) Blocked, (\d+) total", out)
    if not m:
        if "has no REQ rows" in out:
            skip("tf-build-list", "%s: checklist has no requirement rows yet" % label)
        else:
            broken("tf-build-list", "%s: no counts line to check" % label,
                   "the output shape changed; the arithmetic can no longer be verified")
        continue
    mode, work, term, blocked, total = m.group(1), *(int(x) for x in m.groups()[1:])
    if work + term + blocked != total:
        broken("tf-build-list",
               "%s: %d rows are in no category (%d open + %d terminal + %d blocked ≠ %d total)"
               % (label, total - work - term - blocked, work, term, blocked, total),
               "a build pass trusting this list would leave those rows at 0%")
    else:
        ok("tf-build-list", "%s: %d rows, all accounted for (%s)" % (label, total, mode))

# ---- 3. the BRD this project actually wrote can be read --------------------------------
# TF-017: the ledger regex required **BRD-N** immediately after the bullet, and a real BRD
# carries an <a id> anchor there because §9 cross-links need one. It matched 0 of 179 items.
sys.path.insert(0, UTILS)
for app, phase, _cl in apps:
    brd = os.path.join(REPO, "docs", "%s-BRD.md" % app if phase <= 1 else "%s-P%d-BRD.md" % (app, phase))
    if not os.path.isfile(brd):
        continue
    text = open(brd, encoding="utf-8", errors="replace").read()
    # A struck-through item (~~**BRD-3**~~ *(removed …)*) is deliberately not a live
    # requirement, and the ledger is right to skip it. Counting it as unread would make
    # this check cry wolf on every mature BRD -- and a check that cries wolf is the one
    # that gets skimmed (TF-012 failed 8 of 10 screens identically and trained exactly that).
    # UNIQUE ids, not occurrences: an id named again in a cross-reference is the same
    # requirement, and counting mentions made every BRD look short by however many times
    # it referred to itself.
    written_ids = {m.group(1) for m in re.finditer(r"\*\*(BRD-\d+)\*\*", text)
                   if not re.search(r"~~\s*$", text[max(0, m.start() - 3):m.start()])}
    written = len(written_ids)
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("_sb", os.path.join(UTILS, "tf-split-brd.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        read = len({(i["id"] if isinstance(i, dict) else i[0]) for i in mod.ledger(text)})
    except Exception as e:
        broken("tf-split-brd", "%s: could not read the BRD at all (%s)" % (app, type(e).__name__),
               "*amend-docs --add-missing cannot append checklist rows")
        continue
    if written and read < written:
        broken("tf-split-brd", "%s: reads %d of %d BRD items" % (app, read, written),
               "new requirements must be added to the checklist by hand until this is fixed")
    elif written:
        ok("tf-split-brd", "%s: reads all %d BRD items" % (app, written))

# ---- 4. the streams this project's figures are built on --------------------------------
# TF-015: a run whose `ended` precedes its `started` was stored with a negative or invented
# duration, and the two readers of the stream then disagreed about the same record.
runs_p = os.path.join(REPO, "docs", "metrics", "runs.jsonl")
if not os.path.isfile(runs_p):
    skip("runs.jsonl", "no telemetry in this project yet")
else:
    neg = impossible = total_r = badline = 0
    for l in open(runs_p, encoding="utf-8", errors="replace"):
        l = l.strip()
        if not l:
            continue
        try:
            r = json.loads(l)
        except Exception:
            badline += 1
            continue
        total_r += 1
        d = r.get("duration_s")
        if isinstance(d, (int, float)) and d < 0:
            neg += 1
        s, e = r.get("started"), r.get("ended")
        if isinstance(s, str) and isinstance(e, str) and e < s:
            impossible += 1
    if badline:
        broken("runs.jsonl", "%d line(s) are not valid JSON" % badline, "those records are invisible to every figure")
    if impossible or neg:
        # NOT a failure. The emitter refuses these now and the reader discards them and
        # prints how many -- so nothing is wrong with the framework here, and nothing can
        # be done about the records either: the stream is append-only and the true start
        # times are gone. Reported once as history, because calling it broken on every
        # command for the life of the project is how a check earns being skimmed.
        skip("runs.jsonl", "%d old record(s) end before they start — discarded from every "
                           "duration figure, and the report says so" % impossible)
    elif total_r:
        ok("runs.jsonl", "%d run record(s), none impossible" % total_r)

# ---- 5. the framework's own verdicts are not counted as this project's -----------------
# TF-020: an FR verdict grades a framework requirement, not a screen, and pooling it into
# an application segment raises that segment's first-pass rate with nothing on the output
# to show it happened. SCHEMA §3 states the rule; the rollup has to apply it.
gates_p = os.path.join(REPO, "docs", "metrics", "gates.jsonl")
if not os.path.isfile(gates_p):
    skip("tf-metrics", "no gate records in this project yet")
else:
    has_fr = False
    for l in open(gates_p, encoding="utf-8", errors="replace"):
        if '"req_class"' in l and '"FR"' in l:
            has_fr = True
            break
    rc, out = run(["bash", os.path.join(TELEM, "tf-metrics.sh"), "--rollup", REPO, "--json"])
    try:
        data = json.loads(out)
    except Exception:
        broken("tf-metrics", "--rollup did not return readable JSON (exit %d)" % rc,
               "no figure this project publishes can be checked against the reference")
        data = None
    if data is not None:
        segs = data.get("live") or {}
        if has_fr and "framework-requirement" not in segs:
            broken("tf-metrics", "framework verdicts are pooled into %s" % ", ".join(sorted(segs) or ["nothing"]),
                   "this project's first-pass rate is overstated")
        else:
            ok("tf-metrics", "rollup reads; %d segment(s), framework verdicts separate" % len(segs))

# ---- 6. amendments to the miss log still fold -------------------------------------------
# TF-006 and TF-018: a field added after a record was written can only be completed by an
# amendment, and an amendment the reader will not fold is a fact silently lost.
miss_p = os.path.join(REPO, "docs", "metrics", "misses.jsonl")
if not os.path.isfile(miss_p):
    skip("misses.jsonl", "no miss records in this project yet")
else:
    ids, amends, orphan = set(), 0, 0
    for l in open(miss_p, encoding="utf-8", errors="replace"):
        l = l.strip()
        if not l:
            continue
        try:
            r = json.loads(l)
        except Exception:
            continue
        if r.get("kind") == "miss":
            ids.add(r.get("miss_id"))
        elif r.get("kind") == "miss-amend":
            amends += 1
            if r.get("miss_id") not in ids:
                orphan += 1
    if orphan:
        broken("misses.jsonl", "%d amendment(s) name a miss that is not on this stream" % orphan,
               "the information in them is not reaching any figure")
    else:
        ok("misses.jsonl", "%d miss(es), %d amendment(s), none orphaned" % (len(ids), amends))

# ---- 7. the checks that read this project's documents run at all -----------------------
for name, cmd in (("tf-doc-check", ["bash", os.path.join(UTILS, "tf-doc-check.sh")] +
                   (["--app", apps[0][0]] if apps else []) + ["--warn"]),
                  ("tf-gitignore-audit", ["bash", os.path.join(UTILS, "tf-gitignore-audit.sh"), REPO, "--dry-run"])):
    if name == "tf-doc-check" and not apps:
        skip(name, "no application documents yet")
        continue
    rc, out = run(cmd)
    if rc in (99,) or "Traceback" in out:
        broken(name, "crashed on this project's files",
               (out.strip().splitlines() or [""])[-1][:120])
    else:
        first = next((l for l in out.splitlines() if l.strip()), "")
        ok(name, "runs (exit %d)" % rc)

# ---- output -----------------------------------------------------------------------------
proj = os.path.basename(REPO.rstrip(os.sep))
print("# tf-selfcheck — %s — the framework's own scripts against this project's real files" % proj)
for l in lines:
    print(l)
print()
if not findings:
    print("Every framework script works on this project. Nothing to file.")
    raise SystemExit(0)

print("%d framework defect(s) found. These are the FRAMEWORK's, not this project's —" % len(findings))
print("nothing here graded the application. Do not work around them silently: file them,")
print("and carry on (a framework defect blocks a row only when it stops the work).")
if REPORT:
    print()
    print("--- paste into docs/%s-TechieFlow-Feedback.md ---" % proj)
    for i, (script, msg, hint) in enumerate(findings, 1):
        print()
        print("## TF-xxx — %s: %s" % (script, msg))
        print()
        print("- **Severity:** major")
        print("- **Blocks:** no")
        print("- **Repro:** `bash .tfcore/utils/tf-selfcheck.sh` in this repository")
        print("- **Expected:** the script works on this project's files")
        print("- **Actual:** %s" % msg)
        print("- **Encountered in:** tf-selfcheck, %s" % proj)
        if hint:
            print("- **Consequence:** %s" % hint)
        print("- **Not fixable here** — `.tfcore/` is framework-owned and is replaced on the next update.")
else:
    print("Run again with --report for entries you can paste into the feedback file.")
raise SystemExit(1)
PY

#!/usr/bin/env bash
# TechieFlow — effort ESTIMATE for one phase, in tokens and time, from the repo's own run history.
#
#   bash .tfcore/telemetry/tf-estimate.sh <repo> --phase N [--family <repo> ...] [--dry-run] [--json]
#
# WHAT IT DOES (SCHEMA.md §2.8; the task is .tfcore/tasks/estimate-phase.md)
#   1. Reads phase N's checklist rows: docs/<App>-Checklist.md for phase 1, docs/<App>-P<N>-Checklist.md
#      for the others (the same naming *verify --phase uses).
#   2. Reads the repo's LIVE run records (never backfilled, never voided) of build-phase, verify-phase,
#      fix-issues and the after-handoff step, and the checklists of its OTHER phases.
#   3. THE UNIT OF HISTORY IS A FINISHED PHASE, NOT A RUN (2026-11-19). For each other phase that was built
#      (a build-phase run touched its rows), per cmd and per row prefix (REQ-UI, REQ-FN ...): what that step
#      spent on the phase's rows of that prefix — each run counting the share of its tokens and time its rows
#      there make up, every re-verify and every fix included — divided by those rows. A row that no fix ever
#      touched counts as nothing spent. Over those phases: low and high are the first and third quartile,
#      mid is the mean (a phase total is a sum, so the average phase is its expected cost; low/high widen to
#      take it in). Each row of the prefix gets that figure.
#      Why: pricing every row at one pass of the median run put verify at 0.15 and fix at 4.5 times what 28
#      built phases of ten repos spent (TechieBlog phase 1: 39 times too low, 6 times too high); a phase is
#      re-verified many times and fixes few rows. This way gives 0.99 and 0.99 on the same phases.
#   4. Fewer than three such phases for a cmd and prefix in this repo: the phases of the --family repos are
#      added and the basis is "family". Still fewer than three: "no precedent" — never a number. A phase
#      whose step on those rows has a run with no measured tokens or time is left out for that step, counted.
#   5. Writes one estimate record per row per cmd and one per phase total per cmd to
#      docs/metrics/estimates.jsonl through tf-emit.sh (nothing on --dry-run), then prints the table:
#      per row and per phase, build, machine QA (verify + fix) and the total, each low / mid / high,
#      the basis and the model that made the estimate. Owner UAT time has no stream: "not measured".
#
# WHAT IT NEVER DOES
#   - It never writes to runs.jsonl or any other measured stream. An estimate is not a measurement and
#     never pools with one (SCHEMA.md §6, fourth separation; DECISIONS.md 2026-11-08).
#   - It never estimates a row's cost per feature as a headline: a row figure is an input to the phase
#     total, and the reconciliation (tf-metrics.sh --estimates) is per phase (SCHEMA.md §0 non-goal).
#   - It never runs git.
#
# Exit 0 on success, 2 on a usage error or when the phase has no checklist.
# bash 3.2 and BSD-tool clean: everything past argument checks is the embedded python.
set -uo pipefail

command -v python3 >/dev/null 2>&1 || { echo "tf-estimate: python3 is required." >&2; exit 2; }

TF_ESTIMATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" exec python3 - "$@" <<'PYEOF'
import glob
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

CMDS = ("build-phase", "verify-phase", "fix-issues", "triage")
# "triage" is the after-handoff step: the runs of *triage-and-fix and *triage-issues, pooled. Bugs a person
# found after the checks passed are never folded into machine QA's fix-issues (owner, 2026-11-08).
STEP_OF = {"build-phase": "build-phase", "verify-phase": "verify-phase", "fix-issues": "fix-issues",
           "triage-and-fix": "triage", "triage-issues": "triage"}
MIN_N = 3
HERE = os.environ.get("TF_ESTIMATE_DIR", ".")
EMIT = os.path.normpath(os.path.join(HERE, "..", "utils", "tf-emit.sh"))
ROW = re.compile(r"^\|\s*(REQ-[A-Z]+-\d+)\s*\|")
PREFIX = re.compile(r"^(REQ-[A-Z]+)-\d+$")


def usage(msg=None):
    if msg:
        sys.stderr.write("tf-estimate: %s\n" % msg)
    sys.stderr.write("usage: tf-estimate.sh <repo> --phase N [--app <App>] [--family <repo> ...] [--dry-run] [--json]\n")
    raise SystemExit(2)


# ------------------------------------------------------------------ arguments
argv = sys.argv[1:]
if not argv or argv[0] in ("-h", "--help"):
    usage()
repo, phase, family, dry, as_json, app_arg = None, None, [], False, False, None
i = 0
while i < len(argv):
    a = argv[i]
    if a == "--phase":
        i += 1
        try:
            phase = int(argv[i])
        except Exception:
            usage("--phase takes a whole number")
    elif a == "--family":
        i += 1
        while i < len(argv) and not argv[i].startswith("--"):
            family.append(argv[i])
            i += 1
        continue
    elif a == "--dry-run":
        dry = True
    elif a == "--app":
        i += 1
        app_arg = argv[i] if i < len(argv) else usage("--app takes the app's name")
    elif a == "--json":
        as_json = True
    elif a.startswith("--"):
        usage("unknown flag %s" % a)
    elif repo is None:
        repo = a
    else:
        usage("one repo only; family repos go after --family")
    i += 1
if repo is None or phase is None or phase < 1:
    usage("a repo and --phase N are required")
for r in [repo] + family:
    if not os.path.isdir(r):
        usage("not a directory: %s" % r)
repo = os.path.abspath(repo)
family = [os.path.abspath(f) for f in family if os.path.abspath(f) != os.path.abspath(repo)]


# ------------------------------------------------------------------ the phase's rows
def app_of(r, given=None, family_repo=False):
    """The app whose checklist this is, resolved the way the rest of the framework names it — never the first
    *-Checklist.md found. TechieBlog has Prod-Deploy-Checklist.md beside TechieBlog-Checklist.md, and the first
    by name was taken as the app, so every row read "no precedent" (owner, 2026-11-08). In order:
      1. --app <App>, which *estimate-phase passes from {App}, as the verifier is given it;
      2. core-config.yaml customTechnicalDocuments.brd (docs/<App>-BRD.md), when it names a checklist that exists;
      3. the one <X>-Checklist.md (not -P<n>-, not -Deployment-) that has its own docs/<X>-BRD.md;
      4. otherwise none: the caller is told to pass --app, and nothing is guessed."""
    docs = os.path.join(r, "docs")
    if given:
        return given, "--app"
    try:
        with open(os.path.join(r, ".tfcore", "core-config.yaml"), encoding="utf-8", errors="replace") as fh:
            m = re.search(r"(?m)^\s+brd:\s*['\"]?docs/(.+?)-BRD\.md", fh.read())
        if m and os.path.isfile(os.path.join(docs, m.group(1) + "-Checklist.md")):
            return m.group(1), "core-config.yaml"
    except OSError:
        pass
    names = sorted(os.path.basename(p)[:-len("-Checklist.md")] for p in glob.glob(os.path.join(docs, "*-Checklist.md")))
    names = [n for n in names if not re.search(r"-(P\d+|Deployment)$", n)]
    own = [n for n in names if os.path.isfile(os.path.join(docs, n + "-BRD.md"))]
    if len(own) == 1:
        return own[0], "its BRD"
    if len(names) == 1:
        return names[0], "the only checklist"
    if family_repo:
        return None, None
    usage("cannot tell which checklist is the app's (%s): pass --app <App>" % (", ".join(n + "-Checklist.md" for n in names) or "none under docs/"))


APP, APP_FROM = app_of(repo, app_arg)
CHECKLIST = os.path.join(repo, "docs", ("%s-Checklist.md" % APP) if phase == 1 else ("%s-P%d-Checklist.md" % (APP, phase)))
if not os.path.isfile(CHECKLIST):
    usage("phase %d has no checklist: %s" % (phase, os.path.relpath(CHECKLIST, repo)))


def rows_of(path):
    """REQ ids of the Requirements Status table, in order; the whole file when there is no such heading."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    start = next((n for n, l in enumerate(lines) if re.match(r"^#+\s*Requirements Status", l)), None)
    scope = lines
    if start is not None:
        end = next((n for n in range(start + 1, len(lines)) if re.match(r"^#{1,2}\s", lines[n])), len(lines))
        scope = lines[start:end]
    out = []
    for l in scope:
        m = ROW.match(l)
        if m and m.group(1) not in out:
            out.append(m.group(1))
    return out


ROWS = rows_of(CHECKLIST)
PHASE_SET = set(ROWS)


# ------------------------------------------------------------------ run history
def _span(r):
    a, b = r.get("started"), r.get("ended")
    try:
        fmt = "%Y-%m-%dT%H:%M:%SZ"
        return int((datetime.strptime(b, fmt) - datetime.strptime(a, fmt)).total_seconds())
    except Exception:
        return None


def _dur(r):
    """The timestamps win over a stored duration_s; an impossible span is no duration (tf-metrics.sh _dur)."""
    span = _span(r)
    if span is not None:
        return span if span > 0 else None
    d = r.get("duration_s")
    return d if isinstance(d, (int, float)) and d > 0 else None


def checklists(r, app):
    """{phase: rows} of one repo's phase checklists, named as *verify --phase names them."""
    out = {}
    for path in glob.glob(os.path.join(r, "docs", "*-Checklist.md")):
        m = re.match(r"^%s(?:-P(\d+))?-Checklist\.md$" % re.escape(app), os.path.basename(path))
        if m:
            out[int(m.group(1) or 1)] = set(rows_of(path))
    return out


def history(r, app, skip_phase=None, mine=frozenset()):
    """Per cmd, one sample per finished phase and prefix: (prefix, tokens per row, seconds per row, phase key,
    run keys). skip_phase is the phase being estimated; mine its rows (runs on them make the estimate retro)."""
    recs = []
    try:
        with open(os.path.join(r, "docs", "metrics", "runs.jsonl"), encoding="utf-8") as fh:
            for line in fh:
                try:
                    recs.append(json.loads(line))
                except Exception:
                    pass
    except FileNotFoundError:
        pass
    voided = {(v.get("cmd"), v.get("started")) for v in recs if v.get("kind") == "run-void"}
    out = {c: [] for c in CMDS}
    skipped = {"backfilled": 0, "voided": 0, "no_reqs": 0, "this_phase": 0, "no_tokens": 0, "phases_not_built": 0,
               "steps_unmeasured": 0}
    live = []
    for x in recs:
        if x.get("kind") != "run" or x.get("cmd") not in STEP_OF:
            continue
        if (x.get("cmd"), x.get("started")) in voided:
            skipped["voided"] += 1
            continue
        reqs = {q for q in (x.get("reqs_touched") or []) if isinstance(q, str)}
        n = x.get("reqs_count") if isinstance(x.get("reqs_count"), int) and x.get("reqs_count") > 0 else len(reqs)
        if n <= 0 or not reqs:
            skipped["no_reqs"] += 1
            continue
        if mine.intersection(reqs):
            skipped["this_phase"] += 1
        tok, dur = x.get("tokens_out"), _dur(x)
        ok = (not x.get("backfilled") and isinstance(tok, (int, float)) and x.get("tokens_scope") not in (None, "none")
              and dur is not None)
        skipped["backfilled" if x.get("backfilled") else "no_tokens"] += 0 if ok else 1
        live.append((STEP_OF[x["cmd"]], reqs, n, tok if ok else None, dur, ok,
                     "%s %s %s" % (os.path.basename(r), x["cmd"], x.get("started"))))
    for ph, rows in sorted(checklists(r, app).items()):
        if ph == skip_phase or not rows:
            continue
        if not any(s == "build-phase" and rows & q for s, q, *_ in live):
            skipped["phases_not_built"] += 1
            continue
        for pfx in sorted({PREFIX.match(q).group(1) for q in rows if PREFIX.match(q)}):
            mine_rows = {q for q in rows if q.startswith(pfx + "-")}
            for c in CMDS:
                tok = dur = 0.0
                keys, whole = set(), True
                for s, q, n, t, d, ok, key in live:
                    hit = len(q & mine_rows)
                    if s != c or not hit:
                        continue
                    whole = whole and ok
                    if ok:
                        tok, dur = tok + t * min(1.0, float(hit) / n), dur + d * min(1.0, float(hit) / n)
                        keys.add(key)
                if not whole:
                    skipped["steps_unmeasured"] += 1
                    continue
                out[c].append((pfx, tok / len(mine_rows), dur / len(mine_rows),
                               "%s P%d" % (os.path.basename(r), ph), keys))
    return out, skipped


HIST, SKIPPED = history(repo, APP, phase, PHASE_SET)
# Estimated after the fact: runs on this phase's own rows already exist, so the figure is hindsight, not a
# forecast. Its records carry basis_note "retro" and every table says so (owner, 2026-11-08; SCHEMA.md §2.8).
RETRO = SKIPPED["this_phase"] > 0
FAM, FAM_UNNAMED = [], []
for f in family:
    fapp, _ = app_of(f, family_repo=True)
    if not fapp:
        FAM_UNNAMED.append(os.path.basename(f))
        continue
    h, _ = history(f, fapp)
    FAM.append(h)


def quartiles(xs):
    """low/high the first and third quartile; mid the MEAN, since a phase total is a sum of rows and the average
    phase is its expected cost. When the mean falls outside the middle half, the range widens to take it in."""
    xs = sorted(xs)
    def q(p):
        k = (len(xs) - 1) * p
        lo = int(k)
        hi = min(lo + 1, len(xs) - 1)
        return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)
    mid = sum(xs) / float(len(xs))
    return {"low": min(q(0.25), mid), "mid": mid, "high": max(q(0.75), mid)}


def rnd(d):
    if not d:
        return None
    r = {k: int(round(v)) for k, v in d.items()}
    r["low"], r["high"] = min(r["low"], r["mid"]), max(r["high"], r["mid"])
    return r


def estimate(cmd, prefix):
    own = [s for s in HIST[cmd] if s[0] == prefix]
    basis, pool = "repo", own
    if len(own) < MIN_N:
        basis = "family"
        pool = own + [s for h in FAM for s in h[cmd] if s[0] == prefix]
    if len(pool) < MIN_N or (basis == "family" and not FAM):
        return {"basis": "none", "basis_runs": len({k for s in pool for k in s[4]}), "basis_phases": len(pool),
                "tokens_out": None, "duration_s": None, "runs": set(), "phases": set()}
    runs = {k for s in pool for k in s[4]}
    return {"basis": basis, "basis_runs": len(runs), "basis_phases": len(pool),
            "tokens_out": rnd(quartiles([s[1] for s in pool])),
            "duration_s": rnd(quartiles([s[2] for s in pool])),
            "runs": runs, "phases": {s[3] for s in pool}}


# ------------------------------------------------------------------ the model that estimates
def current_model():
    if not os.path.isfile(EMIT):
        return None
    try:
        out = subprocess.run(["bash", EMIT, "--current-model"], capture_output=True, text=True, timeout=60,
                             env=dict(os.environ, TF_METRICS_ROOT=repo))
        return (out.stdout or "").strip() or None
    except Exception:
        return None


MODEL = current_model()
TS = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# ------------------------------------------------------------------ rows and totals
rows = []
cache = {}
for req in ROWS:
    pfx = PREFIX.match(req).group(1)
    per = {}
    for c in CMDS:
        if (c, pfx) not in cache:
            cache[(c, pfx)] = estimate(c, pfx)
        per[c] = cache[(c, pfx)]
    rows.append({"req_id": req, "prefix": pfx, "per_cmd": per})

totals = {}
for c in CMDS:
    have = [r["per_cmd"][c] for r in rows if r["per_cmd"][c]["basis"] != "none"]
    runs, phs = set(), set()
    for e in have:
        runs |= e["runs"]
        phs |= e["phases"]
    t = {"rows_n": len(rows), "rows_no_precedent_n": len(rows) - len(have), "basis_runs": len(runs),
         "basis_phases": len(phs)}
    if have:
        t["basis"] = "family" if any(e["basis"] == "family" for e in have) else "repo"
        for f in ("tokens_out", "duration_s"):
            t[f] = {k: sum(e[f][k] for e in have) for k in ("low", "mid", "high")}
    else:
        t.update({"basis": "none", "tokens_out": None, "duration_s": None})
    totals[c] = t


def add(*parts):
    """Sum of figures, or None when any part has no precedent: never a total with a part silently left out."""
    if any(p is None for p in parts):
        return None
    return {k: sum(p[k] for p in parts) for k in ("low", "mid", "high")}


# ------------------------------------------------------------------ records
records = []
for r in rows:
    for c in CMDS:
        e = r["per_cmd"][c]
        records.append({"kind": "estimate", "ts": TS, "app": APP, "phase": phase, "req_id": r["req_id"], "cmd": c,
                        "tokens_out": e["tokens_out"], "duration_s": e["duration_s"], "basis": e["basis"],
                        "basis_runs": e["basis_runs"], "basis_phases": e["basis_phases"], "model": MODEL})
        if RETRO:
            records[-1]["basis_note"] = "retro"
for c in CMDS:
    t = totals[c]
    records.append({"kind": "estimate", "ts": TS, "app": APP, "phase": phase, "req_id": None, "cmd": c,
                    "tokens_out": t["tokens_out"], "duration_s": t["duration_s"], "basis": t["basis"],
                    "basis_runs": t["basis_runs"], "basis_phases": t["basis_phases"], "model": MODEL,
                    "rows_n": t["rows_n"], "rows_no_precedent_n": t["rows_no_precedent_n"]})
    if RETRO:
        records[-1]["basis_note"] = "retro"

written = 0
if not dry and records:
    payload = "".join(json.dumps(x, separators=(",", ":"), ensure_ascii=False) + "\n" for x in records)
    try:
        before = os.path.getsize(os.path.join(repo, "docs", "metrics", "estimates.jsonl"))
    except OSError:
        before = 0
    try:
        out = subprocess.run(["bash", EMIT, "estimates"], input=payload, capture_output=True, text=True, timeout=120,
                             env=dict(os.environ, TF_METRICS_ROOT=repo))
        if out.stdout.strip():
            sys.stderr.write(out.stdout)
    except Exception as e:
        sys.stderr.write("tf-estimate: tf-emit.sh could not be run (%s): nothing was written\n" % e)
    try:
        with open(os.path.join(repo, "docs", "metrics", "estimates.jsonl"), encoding="utf-8") as fh:
            fh.seek(before)
            written = sum(1 for l in fh if l.strip())
    except OSError:
        written = 0

# ------------------------------------------------------------------ output
summary = {
    "app": APP, "app_from": APP_FROM, "retro": RETRO, "phase": phase, "checklist": os.path.relpath(CHECKLIST, repo), "model": MODEL, "ts": TS,
    "dry_run": dry, "records": len(records), "records_written": written,
    "family": [os.path.basename(f) for f in family],
    "history_samples": {c: len(HIST[c]) for c in CMDS}, "family_unnamed": FAM_UNNAMED, "history_skipped": SKIPPED,
    "rows": [{"req_id": r["req_id"], **{c: {k: v for k, v in r["per_cmd"][c].items() if k not in ("runs", "phases")}
                                         for c in CMDS}}
             for r in rows],
    "totals": totals,
    "owner_uat": "not measured",
}


def column(pick):
    """The sum of one printed column over the rows where it is a number, and how many rows that is."""
    vals = [pick(r["per_cmd"]) for r in rows]
    vals = [v for v in vals if v is not None]
    return (add(*vals) if vals else None), len(vals)


summary["phase_columns"] = {}
for f in ("tokens_out", "duration_s"):
    b = lambda p, f=f: p["build-phase"][f]
    q = lambda p, f=f: add(p["verify-phase"][f], p["fix-issues"][f])
    a = lambda p, f=f: p["triage"][f]
    t = lambda p, f=f: add(p["build-phase"][f], add(p["verify-phase"][f], p["fix-issues"][f]))
    for col, pick in (("build", b), ("machine_qa", q), ("after_handoff", a), ("total", t)):
        d, n = column(pick)
        summary["phase_columns"].setdefault(col, {})[f] = d
        summary["phase_columns"][col]["rows"] = n

if as_json:
    print(json.dumps(summary, indent=2))
    raise SystemExit(0)


def k(n):
    n = float(n)
    for unit, div in (("M", 1e6), ("k", 1e3)):
        if abs(n) >= div:
            return "%.1f%s" % (n / div, unit)
    return "%d" % n


def hms(s):
    s = int(s)
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return ("%dh%02dm" % (h, m)) if h else ("%dm%02ds" % (m, sec))


def fig(d, fmt):
    if d is None:
        return "no precedent"
    return "%s (%s–%s)" % (fmt(d["mid"]), fmt(d["low"]), fmt(d["high"]))


def basis_word(per):
    b = [per[c]["basis"] for c in CMDS]
    n = [str(per[c]["basis_phases"]) for c in CMDS]
    return "%s phases=%s" % ("/".join(b), "/".join(n))


W = 160
print("=" * W)
print("Estimate — %s phase %d (%s), %d row(s)%s" % (APP, phase, summary["checklist"], len(rows),
                                                  "  [dry run: nothing written]" if dry else ""))
print("Estimating model: %s.  Figures are mid (low–high) = mean (first–third quartile) per row." % (MODEL or "unknown"))
print("App: %s (from %s)." % (APP, APP_FROM))
if RETRO:
    print("ESTIMATED AFTER THE FACT: %d run(s) on this phase's own rows already exist, so this is hindsight, not a"
          % SKIPPED["this_phase"])
    print("forecast. Its records carry basis_note \"retro\" and the reconciliation labels it.")
print("=" * W)
for title, f, fmt in (("TOKENS OUT", "tokens_out", k), ("TIME", "duration_s", hms)):
    print("%-12s %-30s %-30s %-30s %-30s %s" % (title, "build", "machine QA (verify+fix)", "after handoff (triage)",
                                                 "build + machine QA", "basis b/v/f/t"))
    for r in rows:
        p = r["per_cmd"]
        b = p["build-phase"][f]
        qa = add(p["verify-phase"][f], p["fix-issues"][f])
        print("%-12s %-30s %-30s %-30s %-30s %s" % (r["req_id"], fig(b, fmt), fig(qa, fmt), fig(p["triage"][f], fmt),
                                                    fig(add(b, qa), fmt), basis_word(p)))
    cols = []
    for col in ("build", "machine_qa", "after_handoff", "total"):
        d, n = summary["phase_columns"][col][f], summary["phase_columns"][col]["rows"]
        cols.append(fig(d, fmt) + ("" if n == len(rows) else " [%d/%d]" % (n, len(rows))))
    print("%-12s %-30s %-30s %-30s %-30s" % ("PHASE " + str(phase), cols[0], cols[1], cols[2], cols[3]))
    print("-" * W)
short = [c for c in CMDS if totals[c]["rows_no_precedent_n"]]
if short:
    print("  No precedent: %s. A phase figure is the sum of the numbers in its column; [n/m rows] says how"
          % "; ".join("%s %d of %d rows" % (c, totals[c]["rows_no_precedent_n"], totals[c]["rows_n"]) for c in short))
    print("  many rows it covers, so it is never read as the whole phase. Those rows get a Remark (estimate-phase.md).")
print("  Owner UAT time: not measured (no stream records it).")
print("  History: %s finished phase-and-prefix sample(s) (build/verify/fix/triage) in %s; left out: %s."
      % ("/".join(str(len(HIST[c])) for c in CMDS), APP,
         ", ".join("%d %s" % (v, kk.replace("_", " ")) for kk, v in SKIPPED.items() if v) or "none"))
if family:
    print("  Family: %s.%s" % (", ".join(os.path.basename(f) for f in family),
          (" Left out, no checklist that names the app: %s." % ", ".join(FAM_UNNAMED)) if FAM_UNNAMED else ""))
print("  A row's figure is what built phases spent per row on that step, every re-verify and fix included (a row")
print("  no fix touched counts as nothing): mid the average phase, low-high the middle half of phases.")
print("  After handoff = *triage-and-fix + *triage-issues on bugs a person found; never inside machine QA, and kept")
print("  out of \"build + machine QA\" so a phase with no triage history still has a total.")
if not dry:
    print("  Written: %d of %d estimate record(s) to docs/metrics/estimates.jsonl." % (written, len(records)))
print("=" * W)
PYEOF

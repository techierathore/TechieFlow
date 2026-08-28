#!/usr/bin/env bash
# TechieFlow telemetry — owner-run reporting & backfill tool.
#
#   ⚠ THIS IS THE ONLY FILE IN THE FRAMEWORK ALLOWED TO CONTAIN GIT COMMANDS.
#
#     --backfill-commits   OWNER-RUN ONLY. Invokes git. An agent must NEVER run it.
#     --backfill-gates     OWNER-RUN ONLY. Writes reconstructed history; only the
#                          owner decides that a repo's past gets synthesised.
#     --report / --rollup  READ-ONLY. No git, no writes. The *metrics task
#                          (.tfcore/tasks/metrics-report.md) invokes these, and
#                          should — the provenance separations of SCHEMA.md §6 are
#                          enforced HERE, in code, so no agent has to be trusted
#                          to resist producing the combined figure by hand.
#
# USAGE
#   tf-metrics.sh --report            [<repo>] [--json]
#   tf-metrics.sh --backfill-commits  [<repo>] [--dry-run]
#   tf-metrics.sh --backfill-gates    [<repo>] [--dry-run]
#   tf-metrics.sh --rollup <repo> [<repo> ...] [--json]
#
# PROVENANCE RULE (SCHEMA.md §6) — enforced here, not just documented:
#   live and backfilled records NEVER pool, and app/library/docs NEVER pool, for
#   first-pass rate, gate catch distribution, or escape rate. There is no flag to
#   turn that off. Commit-derived metrics are exempt (git log is a real log).
set -uo pipefail

command -v python3 >/dev/null 2>&1 || { echo "tf-metrics: python3 is required." >&2; exit 1; }

exec python3 - "$@" <<'PYEOF'
import glob
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict, OrderedDict

STREAMS = ("runs", "gates", "sessions", "commits", "misses")
VERDICTS = ("Verified", "Needs re-verify", "FAIL", "Blocked", "Implemented", "Done (pre-existing)")
GATE_ORDER = ("build", "acceptance", "render", "visual", "perf", "standards", "escaped")

# Gates that entered the enum after gates.jsonl started collecting. Their share of a raw
# distribution is structurally understated — records written before the date never had the
# chance to record them, and (for `perf`) most records after it still do not run the gate.
# The honest denominator is "records that actually ran it", i.e. gates_run membership.
# SCHEMA.md §3.5. Keep this table in sync when a gate is added.
LATE_GATES = {"perf": "2026-08-10"}

# The same hazard as LATE_GATES, one stream over: an OPTIONAL FIELD added after a
# stream started collecting. A record written before the date had no such field to
# fill, so counting it as "not assessed" understates the practice being measured.
# It leaves that field's denominator and is reported separately. SCHEMA.md §5.5.6 /
# §3.5. Keep this table in sync when an optional field is added to any stream.
FIELD_SINCE = {"why_missed": "2026-08-28"}

# Fields a `miss-amend` record may complete, and their closed vocabularies.
# Kept identical to tf-emit.sh's `_AMENDABLE`; the emitter enforces it on write and
# this enforces it again on read, because a merged stream can carry records this
# machine's emitter never saw. SCHEMA.md §5.5.7 states the rule for extending it.
AMENDABLE_FIELDS = {
    "why_missed": ("missing-checklist-item", "insufficient-verify-method",
                   "code-audit-limitation", "ambiguous-acceptance",
                   "dependency-not-declared", "instruction-ignored", "other"),
}
MIN_N = 3  # fewer supporting records than this -> "insufficient data", never a number


# ---------------------------------------------------------------- utilities
def die(msg):
    sys.stderr.write("tf-metrics: %s\n" % msg)
    raise SystemExit(1)


def metrics_dir(repo):
    return os.path.join(repo, "docs", "metrics")


def read_stream(repo, stream):
    path = os.path.join(metrics_dir(repo), stream + ".jsonl")
    out = []
    try:
        with open(path, encoding="utf-8") as fh:
            for n, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except Exception:
                    sys.stderr.write("  ! %s:%d is not valid JSON — skipped\n" % (path, n))
    except FileNotFoundError:
        pass
    return out


def emit(repo, stream, records, dry_run, quiet=False):
    """Append via tf-emit.sh — the single append primitive. Never write JSONL directly.

    The whole batch goes down ONE pipe as JSONL. The pre-commit hook reconciles
    on every commit, so the per-record process spawn this used to do turned a
    first-run catch-up of a few hundred commits into a visible stall inside the
    owner's `git commit`."""
    if not records:
        return
    emitter = os.path.join(repo, ".tfcore", "utils", "tf-emit.sh")
    if dry_run:
        for r in records[:3]:
            print("  WOULD append: " + json.dumps(r, separators=(",", ":")))
        if len(records) > 3:
            print("  WOULD append: ... and %d more" % (len(records) - 3))
        return
    if not os.path.isfile(emitter):
        if quiet:
            return
        die("no %s — run update-framework.sh on this repo first" % emitter)
    env = dict(os.environ, TF_METRICS_ROOT=os.path.abspath(repo))
    payload = "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in records)
    p = subprocess.Popen(["bash", emitter, stream], stdin=subprocess.PIPE, env=env)
    p.communicate(payload.encode("utf-8"))


def dedupe_commits(records):
    """Collapse commit records that share a sha, keeping the first.

    Duplicates are EXPECTED, not corruption. A commit made on machine A is
    recorded there by the hook; if that record has not been pushed when machine B
    pulls the commit itself, B's reconcile reconstructs the same record from the
    log. Both are then real lines in two branches of the same file, and
    `merge=union` — which exists so that no record is ever lost to a hand-resolved
    conflict — keeps both. De-duplicating on read is the other half of that trade:
    union merge guarantees nothing is dropped, this guarantees nothing is counted
    twice. `sha` is the natural key; a commit happens once.

    Scope note (corrected 2026-08-27, TfLens TF-001): this reasoning is about
    UNION-MERGE duplicates specifically. runs/gates record events that happen on
    ONE machine and are never independently reconstructible, so union merge
    cannot manufacture a second copy of them. Sessions are NOT in that set —
    they have their own, unrelated duplication source (the OpenCode plugin's
    cumulative snapshots, SCHEMA.md §4) and are handled by dedupe_sessions
    below. The original wording reasoned about one source of duplication and
    concluded there were none at all, which silently overstated every session
    and token figure."""
    seen, out, dupes = set(), [], 0
    for r in records:
        sha = r.get("sha")
        if sha is None:
            out.append(r)
            continue
        if sha in seen:
            dupes += 1
            continue
        seen.add(sha)
        out.append(r)
    return out, dupes


def dedupe_sessions(records):
    """Collapse session records that share a session_id, keeping the completest.

    Duplicates are EXPECTED here too, but for a different reason than commits.
    The OpenCode plugin appends a CUMULATIVE snapshot at every root-session idle
    (SCHEMA.md §4 — a TUI session idles after each turn), so one session
    legitimately produces several records and only the largest is complete. The
    documented consumer rule is to take the record with the highest
    output_tokens per session_id, ties broken on the latest ts.

    Claude Code records stay one-per-session via SessionEnd, so they are
    unaffected: a session_id seen once keeps its single record untouched.

    Call this PER REPO, exactly as commits are — two repos may legitimately
    carry the same session_id and collapsing across them would under-count."""
    rank = lambda r: ((r.get("output_tokens") or 0), r.get("ts") or "")
    best, order, dupes = {}, [], 0
    for r in records:
        sid = r.get("session_id")
        if sid is None:          # no natural key: pass through, as commits does
            order.append(r)
            continue
        if sid in best:
            dupes += 1
            if rank(r) > rank(best[sid]):
                best[sid] = r
        else:
            best[sid] = r
            order.append(sid)    # placeholder, resolved on the way out
    return [x if isinstance(x, dict) else best[x] for x in order], dupes


def analyse_misses(misses):
    """The §5.5 stream, with the THIRD provenance separation enforced here in code.

    Two exclusions, both APPLIED AND DISPLAYED (SCHEMA.md §6):

      origin_confidence != "linked"  -> excluded from every per-phase / per-model /
          per-agent miss rate. A routing decision made on guessed attributions is a
          decision made on invented evidence, and nothing in the output would show it.

      cost_attribution != "sole"     -> excluded from the headline cost figures. A run
          that fixed three misses has ONE token window; dividing it three ways is
          arithmetic, not measurement. The apportioned total is carried separately so
          it can be shown in a labelled column, never summed into the headline.

    Raw counts and the miss-class distribution ARE poolable: a miss counts as a miss
    whoever missed it; only its attribution is confidence-bounded."""
    opened = [m for m in misses if m.get("kind") == "miss" and not m.get("backfilled")]
    fixes = [m for m in misses if m.get("kind") == "miss-fix" and not m.get("backfilled")]
    amends = [m for m in misses if m.get("kind") == "miss-amend"]

    # ---- fold amendments into their parents BEFORE anything is counted (§5.5.7).
    # An amend completes a field the miss left null; it can never overwrite one, so
    # folding cannot change a value that was already recorded. The null-check is
    # repeated here rather than trusted from the emitter: this reader also sees
    # streams merged from another machine, where an amend and a later-written value
    # could arrive in either order.
    opened_by_id = {}
    for m in opened:
        if m.get("miss_id"):
            opened_by_id.setdefault(m["miss_id"], m)
    amended, orphan_amends = 0, 0
    for a in sorted(amends, key=lambda r: r.get("ts") or ""):
        parent = opened_by_id.get(a.get("miss_id"))
        fld = a.get("field")
        if parent is None or fld not in AMENDABLE_FIELDS:
            orphan_amends += 1
            continue
        if parent.get(fld) is None and a.get("value") in AMENDABLE_FIELDS[fld]:
            parent[fld] = a["value"]
            amended += 1

    # ---- eligibility floor for optional fields added mid-stream (SCHEMA.md §3.5,
    # the same rule the `perf` gate established, arriving on a different stream).
    # A record written before a field existed had ZERO chance of carrying it, so it
    # is not evidence that the field was skipped. It leaves the denominator and is
    # reported separately — never silently, and never backfilled with a value
    # nobody assessed at the time.
    def _eligible(rec, field):
        since = FIELD_SINCE.get(field)
        return not since or (rec.get("ts") or "") >= since

    # Latest fix per miss decides open/closed; a fix naming no known miss is an orphan.
    known = {m.get("miss_id") for m in opened}
    latest = {}
    orphans = 0
    for f in fixes:
        mid = f.get("miss_id")
        if mid not in known:
            orphans += 1
            continue
        prev = latest.get(mid)
        if prev is None or (f.get("ts") or "") >= (prev.get("ts") or ""):
            latest[mid] = f
    # TWO DIFFERENT QUESTIONS, DELIBERATELY NOT THE SAME PREDICATE.
    #
    #   "is this defect still live?"      -> the COLLAPSE check in tf-emit.sh --open-miss.
    #                                        A wont-fix defect is still live: the next verify
    #                                        failure on that REQ is the SAME defect and must not
    #                                        open a second record. So --open-miss keeps its
    #                                        `verdict_after != "Verified"` predicate. Do not
    #                                        "fix" the two to agree — they are asking different
    #                                        things and agreeing would break one of them.
    #
    #   "how much work is outstanding?"   -> THIS count, which the owner reads as a backlog.
    #                                        `wont-fix` is a decision, not a backlog item, so it
    #                                        gets its own bucket. `deferred` IS outstanding —
    #                                        postponed work is still work — so it stays open.
    def _verdict(m):
        return (latest.get(m.get("miss_id")) or {}).get("verdict_after")

    open_misses = [m for m in opened if _verdict(m) not in ("Verified", "wont-fix")]
    wont_fix = [m for m in opened if _verdict(m) == "wont-fix"]
    resolved = [m for m in opened if _verdict(m) == "Verified"]

    linked = [m for m in opened if m.get("origin_confidence") == "linked"]
    excluded = len(opened) - len(linked)

    sole = [f for f in fixes if f.get("cost_attribution") == "sole"]
    shared = [f for f in fixes if str(f.get("cost_attribution") or "").startswith("shared:")]
    unattributable = sum(1 for f in fixes if f.get("cost_attribution") == "none")

    def tok(fs):
        return sum((f.get("tokens_out") or 0) for f in fs)

    # Dollars exist ONLY where a harness measured them. Claude Code and Codex carry
    # cost_usd:null permanently (SCHEMA.md §4) and are never priced from a rate card
    # here — a pooled sum over mixed harnesses would silently under-report.
    paid = [f for f in sole if f.get("cost_usd") is not None]
    escaped = [m for m in opened if m.get("found_by") in ("owner", "production")]
    design = [m for m in opened if m.get("miss_class") == "unspecified-gap"]

    return {
        "misses_total": len(opened),
        "miss_fixes_total": len(fixes),
        "orphan_fixes": orphans,
        "open_misses": len(open_misses),
        "wont_fix": len(wont_fix),
        "resolved_misses": len(resolved),
        "amendments_applied": amended,
        "orphan_amends": orphan_amends,
        # Denominator is records that CARRY the field — why_missed is optional (§5.5.6)
        # and a missing value means "not assessed", never a zero for some category —
        # AND records that COULD have carried it: one written before 2026-08-28 had no
        # such field to fill, so counting it as unassessed understates the practice.
        "why_missed_n": sum(1 for m in opened if m.get("why_missed")),
        "why_missed_eligible": sum(1 for m in opened if _eligible(m, "why_missed")),
        "why_missed_predates_field": sum(1 for m in opened if not _eligible(m, "why_missed")),
        "why_missed": OrderedDict(
            sorted(Counter(m["why_missed"] for m in opened if m.get("why_missed")).items(),
                   key=lambda kv: (-kv[1], kv[0]))),
        # An escape with no why_missed wastes the most valuable record in the stream:
        # something got past every gate and nobody recorded why nothing caught it.
        "escapes_missing_why": sum(1 for m in opened
                                   if m.get("found_by") in ("owner", "production")
                                   and not m.get("why_missed")
                                   and _eligible(m, "why_missed")),
        "class_distribution": OrderedDict(
            sorted(Counter(m.get("miss_class") or "?" for m in opened).items(),
                   key=lambda kv: (-kv[1], kv[0]))),
        "found_by": OrderedDict(
            sorted(Counter(m.get("found_by") or "?" for m in opened).items(),
                   key=lambda kv: (-kv[1], kv[0]))),
        "design_miss_share": pct(len(design), len(opened)) if len(opened) >= MIN_N
                             else "insufficient data (n=%d)" % len(opened),
        "escape_share": pct(len(escaped), len(opened)) if len(opened) >= MIN_N
                        else "insufficient data (n=%d)" % len(opened),
        # Attribution-bounded. The denominator is `linked` records ONLY.
        "attributed_n": len(linked),
        "attribution_excluded": excluded,
        "by_origin_phase": OrderedDict(
            sorted(Counter(m.get("origin_phase") or "?" for m in linked).items(),
                   key=lambda kv: (-kv[1], kv[0]))),
        "by_origin_model": OrderedDict(
            sorted(Counter(m.get("origin_model") or "?" for m in linked).items(),
                   key=lambda kv: (-kv[1], kv[0]))),
        "by_origin_agent": OrderedDict(
            sorted(Counter(m.get("origin_agent") or "?" for m in linked).items(),
                   key=lambda kv: (-kv[1], kv[0]))),
        # Cost-attribution-bounded. Measured and apportioned NEVER combine.
        "cost_sole_n": len(sole),
        "cost_shared_n": len(shared),
        "cost_unattributable_n": unattributable,
        "tokens_per_miss_measured": round(float(tok(sole)) / len(sole), 1)
                                    if len(sole) >= MIN_N else None,
        "tokens_per_miss_apportioned": round(
            sum(float(f.get("tokens_out") or 0) / int(str(f["cost_attribution"]).split(":")[1])
                for f in shared) / len(shared), 1) if len(shared) >= MIN_N else None,
        "cost_usd_per_miss_measured": round(
            sum(f["cost_usd"] for f in paid) / len(paid), 4) if len(paid) >= MIN_N else None,
        "cost_usd_records": len(paid),
    }


def app_name(repo):
    hits = glob.glob(os.path.join(repo, "docs", "*-Checklist.md"))
    if len(hits) == 1:
        return os.path.basename(hits[0])[: -len("-Checklist.md")]
    return os.path.basename(os.path.abspath(repo))


def project_type(repo):
    # Structural signal first and authoritative — see tf-emit.sh _project_type()
    # for why the framework repo is detected from its tree shape rather than from
    # core-config.yaml (that file is rsynced into every new app, so a value written
    # there would misclassify all of them). Not inferred: this is a fact about the
    # tree, so it never carries project_type_inferred.
    if (os.path.isfile(os.path.join(repo, "scaffold-brownfield.sh"))
            and os.path.isdir(os.path.join(repo, ".tfcore", "tasks"))):
        return "framework", False
    cfg = os.path.join(repo, ".tfcore", "core-config.yaml")
    try:
        text = open(cfg, encoding="utf-8").read()
    except Exception:
        return "app", True
    m = re.search(
        r"^metrics:[ \t]*$(?:\n(?:[ \t]+.*|[ \t]*))*?\n[ \t]+project_type:[ \t]*"
        r"[\"']?(app|library|docs|framework)[\"']?[ \t]*$",
        text, re.M,
    )
    return (m.group(1), False) if m else ("app", True)


def has_commit_hook(repo):
    """Is the commit-telemetry hook installed in THIS clone? A filesystem read,
    never a git call, so --report stays agent-safe. The hook lives in .git/, which
    is not part of the repository, so every clone needs its own — a machine that
    never ran update-framework.sh records nothing until it does."""
    git = os.path.join(repo, ".git")
    hooks = None
    if os.path.isdir(git):
        hooks = os.path.join(git, "hooks")
    elif os.path.isfile(git):
        try:
            for line in open(git, encoding="utf-8"):
                if line.startswith("gitdir:"):
                    gd = line.split(":", 1)[1].strip()
                    if not os.path.isabs(gd):
                        gd = os.path.join(repo, gd)
                    hooks = os.path.join(gd, "hooks")
                    break
        except Exception:
            return None
    if not hooks:
        return None          # not a work tree — say nothing rather than warn
    # pre-commit since 2026-08-11; post-commit is the retired form, still counted
    # so a clone that has not been refreshed does not read as "no telemetry".
    return any(os.path.isfile(os.path.join(hooks, h))
               for h in ("pre-commit", "post-commit"))


def run_git(repo, args, soft=False):
    try:
        out = subprocess.run(["git"] + args, cwd=repo, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, check=True)
        return out.stdout.decode("utf-8", "replace")
    except Exception as e:
        if soft:
            return None      # the hook path: a commit must never fail over telemetry
        die("git failed in %s: %s" % (repo, e))


# ------------------------------------------------------- backfill: commits
PREFIX_RE = re.compile(r"^(feat|fix|docs|chore|refactor|test|build)([(!: ]|$)")
SHORTSTAT_RE = re.compile(r"(\d+) files? changed(?:, (\d+) insertions?\(\+\))?(?:, (\d+) deletions?\(-\))?")


def backfill_commits(repo, dry_run, limit=None, quiet=False):
    """Reconcile commits.jsonl against `git log` — the ONE source that is already
    replicated to every machine by push/pull.

    git log is itself an append-only log, so these records are as trustworthy as
    live ones. They are NOT flagged backfilled and need no separation in reporting.

    Idempotent and gap-filling: every sha already in the stream is skipped, so
    running this repeatedly is free, and a commit made on another machine (or on
    this one before the hook existed) is picked up the next time it runs. That is
    what makes the post-commit hook a reconciler rather than a lossy appender."""
    app = app_name(repo)
    existing = {r.get("sha") for r in read_stream(repo, "commits")}
    branch = run_git(repo, ["rev-parse", "--abbrev-ref", "HEAD"], soft=quiet)
    if branch is None:
        return 0
    branch = branch.strip() or "detached"
    log_args = ["log", "--reverse", "--shortstat", "--date=format-local:%Y-%m-%dT%H:%M:%SZ",
                "--format=\x01%h\x02%cd\x02%s"]
    if limit:
        log_args.insert(1, "-n%d" % limit)
    raw = run_git(repo, log_args, soft=quiet)
    if raw is None:
        return 0
    records, skipped = [], 0
    for chunk in raw.split("\x01"):
        if not chunk.strip():
            continue
        head, _, rest = chunk.partition("\n")
        parts = head.split("\x02")
        if len(parts) < 3:
            continue
        sha, when, subject = parts[0], parts[1], parts[2]
        if sha in existing:
            skipped += 1
            continue
        m = SHORTSTAT_RE.search(rest)
        files = int(m.group(1)) if m else 0
        ins = int(m.group(2) or 0) if m else 0
        dele = int(m.group(3) or 0) if m else 0
        pm = PREFIX_RE.match(subject.strip())
        records.append(OrderedDict([
            ("v", 1), ("ts", when), ("kind", "commit"), ("app", app),
            ("sha", sha), ("files", files), ("insertions", ins), ("deletions", dele),
            ("subject_prefix", pm.group(1) if pm else None),  # subject itself is DISCARDED
            ("branch", branch),
        ]))
    if not quiet:
        print("→ backfill-commits %s: %d new, %d already recorded" % (repo, len(records), skipped))
    emit(repo, "commits", records, dry_run, quiet=quiet)
    return len(records)


# --------------------------------------------------------- backfill: gates
ROW_RE = re.compile(r"^\|\s*(REQ-(UI|FN|RAG|NFR)-\d+)\s*\|(.*)$")
DATE_RE = re.compile(r"(20\d\d-\d\d-\d\d)")

# Remark markers -> (gate, failure_class). Matched against the Remarks cell ONLY to
# CLASSIFY it. The remark text itself is never stored — it is requirement prose.
REMARK_MARKERS = [
    (re.compile(r"⚠\s*visual", re.I), "visual", None),
    (re.compile(r"visual[- ]fail|overlap|off-?viewport|clipped|mockup[- ]drift", re.I), "visual", None),
    (re.compile(r"⚠\s*render gate|render-?empty|render-?error|renders empty", re.I), "render", "blank-data"),
    (re.compile(r"⚠\s*UAT bug", re.I), "escaped", None),
    (re.compile(r"build (error|failed)|NETSDK|compile error", re.I), "build", "build-error"),
    (re.compile(r"naming|prefix violation|coding[- ]standard", re.I), "standards", "naming"),
    (re.compile(r"assert|expected .* got|spec failed|test failed", re.I), "acceptance", "assert-fail"),
]
CLASS_MARKERS = [
    (re.compile(r"overlap", re.I), "overlap"),
    (re.compile(r"clip", re.I), "clipped"),
    (re.compile(r"off-?viewport|off-?screen", re.I), "offscreen"),
    (re.compile(r"zero rows|no rows|0 rows", re.I), "zero-rows"),
    (re.compile(r"blank|empty", re.I), "blank-data"),
    (re.compile(r"exception|unhandled", re.I), "exception"),
]

STATUS_TO_VERDICT = {
    "verified": "Verified",
    "done (pre-existing)": "Done (pre-existing)",
    "needs re-verify": "Needs re-verify",
    "fail": "FAIL",
    "blocked": "Blocked",
    "implemented": "Implemented",
}


def classify(remark):
    gate, fclass = None, None
    for rx, g, fc in REMARK_MARKERS:
        if rx.search(remark):
            gate, fclass = g, fc
            break
    if gate and not fclass:
        for rx, fc in CLASS_MARKERS:
            if rx.search(remark):
                fclass = fc
                break
        fclass = fclass or "other"
    return gate, fclass


def backfill_gates(repo, dry_run):
    """The Requirements Status table is a mutated-in-place SNAPSHOT, not a log.
    A REQ that failed three times then passed is indistinguishable from one that
    passed first try. `attempt` is NOT recoverable — it is assumed, always, and
    always listed in `inferred`. This data is context and volume, never evidence
    for a published rate."""
    app = app_name(repo)
    ptype, ptype_inf = project_type(repo)
    checklists = glob.glob(os.path.join(repo, "docs", "*-Checklist.md"))
    if not checklists:
        die("no docs/*-Checklist.md in %s" % repo)

    already = {r.get("req_id") for r in read_stream(repo, "gates") if r.get("backfilled")}
    records, skipped_status, skipped_dup = [], Counter(), 0

    for path in checklists:
        for line in open(path, encoding="utf-8"):
            m = ROW_RE.match(line.rstrip("\n"))
            if not m:
                continue
            req_id, req_class = m.group(1), m.group(2)
            cells = [c.strip() for c in m.group(3).split("|")]
            if len(cells) < 3:
                continue
            status = re.sub(r"[*`_]", "", cells[1]).strip()
            remark = cells[3] if len(cells) > 3 else ""
            verdict = STATUS_TO_VERDICT.get(status.lower())
            if not verdict:
                skipped_status[status or "(blank)"] += 1
                continue
            if req_id in already:
                skipped_dup += 1
                continue

            date = DATE_RE.search(remark)
            ts = (date.group(1) if date else "1970-01-01") + "T00:00:00Z"
            inferred = ["attempt"]

            # A remark that names a failure is evidence of a PRIOR attempt that the
            # snapshot no longer shows. It is the only extra history recoverable.
            gate, fclass = classify(remark)
            attempt = 1
            if gate and verdict in ("Verified", "Done (pre-existing)"):
                records.append(OrderedDict([
                    ("v", 1), ("ts", ts), ("kind", "gate"), ("app", app),
                    ("project_type", ptype), ("run_id", "backfill"),
                    ("req_id", req_id), ("req_class", req_class), ("attempt", 1),
                    ("verdict", "Needs re-verify"), ("gate", gate),
                    ("gates_run", []), ("failure_class", fclass), ("prior_verdict", None),
                    ("backfilled", True),
                    ("inferred", ["attempt", "gate", "failure_class", "gates_run", "verdict"]),
                ]))
                attempt = 2

            rec = OrderedDict([
                ("v", 1), ("ts", ts), ("kind", "gate"), ("app", app),
                ("project_type", ptype), ("run_id", "backfill"),
                ("req_id", req_id), ("req_class", req_class), ("attempt", attempt),
                ("verdict", verdict),
                ("gate", gate if verdict not in ("Verified", "Done (pre-existing)") else None),
                ("gates_run", []),           # unknown — the snapshot never recorded which gates ran
                ("failure_class", fclass if verdict not in ("Verified", "Done (pre-existing)") else None),
                ("prior_verdict", None),
                ("backfilled", True),
            ])
            if rec["gate"]:
                inferred += ["gate", "failure_class"]
            inferred += ["gates_run", "prior_verdict"]
            if not date:
                inferred.append("ts")
            rec["inferred"] = inferred
            if ptype_inf:
                rec["project_type_inferred"] = True
            records.append(rec)

    print("→ backfill-gates %s (project_type=%s%s)" % (repo, ptype, ", INFERRED" if ptype_inf else ""))
    print("   %d records to write, %d REQs already backfilled (skipped)" % (len(records), skipped_dup))
    if skipped_status:
        print("   rows skipped — status is not a verify verdict: " +
              ", ".join("%s×%d" % (k, v) for k, v in sorted(skipped_status.items())))
    print("   EVERY record is flagged backfilled:true. `attempt` is INFERRED on all of them.")
    print("   This set CANNOT support a published first-pass rate. See SCHEMA.md §7.")
    emit(repo, "gates", records, dry_run)
    return len(records)


# ------------------------------------------------------------------ report
def pct(num, den):
    return "—" if not den else "%.0f%%" % (100.0 * num / den)


def median(xs):
    xs = sorted(xs)
    if not xs:
        return None
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2.0


def analyse(repos):
    """Returns a dict of segmented figures. Segmentation is structural: the
    live-only metrics are computed PER (project_type) over LIVE records only,
    and there is no code path that produces a combined figure."""
    gates, runs, sessions, commits, misses = [], [], [], [], []
    per_repo = []
    commit_dupes = 0
    session_dupes = 0
    for repo in repos:
        g = read_stream(repo, "gates")
        r = read_stream(repo, "runs")
        misses += read_stream(repo, "misses")
        # Per repo, not across them (SCHEMA.md §4): the OpenCode plugin
        # appends a cumulative snapshot at every root-session idle.
        s, sd = dedupe_sessions(read_stream(repo, "sessions"))
        session_dupes += sd
        # Per repo, not across them: two repos may legitimately share a short sha.
        c, d = dedupe_commits(read_stream(repo, "commits"))
        commit_dupes += d
        gates += g; runs += r; sessions += s; commits += c
        per_repo.append({"repo": repo, "app": app_name(repo),
                         "project_type": project_type(repo)[0],
                         "gates": len(g), "gates_backfilled": sum(1 for x in g if x.get("backfilled")),
                         "runs": len(r), "sessions": len(s), "commits": len(c),
                         "misses": sum(1 for x in read_stream(repo, "misses")
                                       if x.get("kind") == "miss"),
                         # A repo reclassified after records were written (most often a
                         # greenfield project born `docs` and upgraded once it grew a head)
                         # keeps the OLD value on every existing record — append-only means
                         # corrections happen at read time, never by rewriting history. Say
                         # so: otherwise one project silently occupies two segments that,
                         # by §6, are never allowed to pool, and neither is the whole story.
                         "stale_types": sorted(
                             {x.get("project_type") for x in (g + r)
                              if x.get("project_type")
                              and x.get("project_type") != project_type(repo)[0]}),
                         "commit_hook": has_commit_hook(repo)})

    def seg(records):
        d = defaultdict(list)
        for r in records:
            key = "unclassified" if r.get("project_type_inferred") else r.get("project_type", "app")
            d[key].append(r)
        return d

    live = [g for g in gates if not g.get("backfilled")]
    back = [g for g in gates if g.get("backfilled")]

    # REQs with ANY backfilled record are excluded from the live first-pass rate:
    # their live `attempt` numbering restarts at 1 (SCHEMA.md §3.1).
    tainted = {g.get("req_id") for g in back}

    out = {"per_repo": per_repo, "tainted_reqs": sorted(x for x in tainted if x),
           "live": {}, "backfilled": {}, "pooled": {},
           "misses": analyse_misses(misses)}

    for label, bucket in (("live", live), ("backfilled", back)):
        for ptype, recs in sorted(seg(bucket).items()):
            eligible = [r for r in recs if label == "backfilled" or r.get("req_id") not in tainted]
            reqs = {r.get("req_id") for r in eligible}
            first_pass = {r.get("req_id") for r in eligible
                          if r.get("attempt") == 1 and r.get("verdict") == "Verified"}
            failures = [r for r in recs if r.get("verdict") not in ("Verified", "Done (pre-existing)")]
            dist = Counter(r.get("gate") or "unattributed" for r in failures)
            escaped_reqs = {r.get("req_id") for r in recs if r.get("gate") == "escaped"}
            failed_reqs = {r.get("req_id") for r in failures}
            out[label][ptype] = {
                "records": len(recs),
                "reqs_scored": len(reqs),
                "reqs_excluded_backfill_taint":
                    len({r.get("req_id") for r in recs if r.get("req_id") in tainted})
                    if label == "live" else 0,
                "first_pass_n": len(first_pass),
                "first_pass_rate": pct(len(first_pass), len(reqs)) if len(reqs) >= MIN_N else "insufficient data (n=%d)" % len(reqs),
                "gate_distribution": OrderedDict(
                    (g, dist.get(g, 0)) for g in GATE_ORDER + ("unattributed",) if dist.get(g)),
                "gate_distribution_n": len(failures),
                "gate_distribution_note": None if len(failures) >= MIN_N else "insufficient data (n=%d)" % len(failures),
                # Coverage for late-added gates: how many records actually RAN each one.
                # Reported beside the count so nobody reads a share off the wrong denominator.
                "late_gate_coverage": OrderedDict(
                    (g, {"ran": sum(1 for r in recs if g in (r.get("gates_run") or [])),
                         "caught": dist.get(g, 0), "since": since})
                    for g, since in LATE_GATES.items()),
                "escape_rate": pct(len(escaped_reqs), len(failed_reqs)) if len(failed_reqs) >= MIN_N
                               else "insufficient data (n=%d)" % len(failed_reqs),
            }

    # ---- poolable metrics: runs, cadence, tokens. Exempt from both separations.
    build_runs = [r for r in runs if r.get("cmd") == "build-phase"]
    fix_runs = [r for r in runs if r.get("mode") == "fix"]
    throughput = [float(r["reqs_count"]) / r["duration_s"]
                  for r in runs if r.get("duration_s") and r.get("reqs_count")]
    batch = [r["reqs_count"] for r in build_runs if r.get("reqs_count") is not None]
    verified_transitions = sum(1 for g in gates if g.get("verdict") == "Verified")
    tok = sum((s.get("input_tokens") or 0) + (s.get("output_tokens") or 0) for s in sessions)
    days = {c.get("ts", "")[:10] for c in commits if c.get("ts")}
    out["pooled"] = {
        "runs_total": len(runs),
        "runs_by_cmd": OrderedDict(sorted(Counter(r.get("cmd") or "?" for r in runs).items())),
        "rework_ratio": pct(len(fix_runs), len(build_runs)) if len(build_runs) >= MIN_N
                        else "insufficient data (n=%d build-phase runs)" % len(build_runs),
        "throughput_median_reqs_per_hour": round(median(throughput) * 3600, 2) if len(throughput) >= MIN_N else None,
        "batch_size_median": median(batch) if len(batch) >= MIN_N else None,
        "sessions": len(sessions),
        "tokens_total": tok,
        "tokens_per_verified_req": round(float(tok) / verified_transitions, 1)
                                   if verified_transitions >= MIN_N and tok else None,
        "cost_usd": None,  # never estimated — see SCHEMA.md §4
        "commits": len(commits),
        "commit_duplicates_collapsed": commit_dupes,
        "session_duplicates_collapsed": session_dupes,
        "active_days": len(days),
        "commits_per_active_day": round(float(len(commits)) / len(days), 2) if days else None,
    }
    return out


def print_report(a, repos):
    W = 78
    print("=" * W)
    print("TechieFlow development telemetry")
    print("=" * W)
    for r in a["per_repo"]:
        print("  %-16s %-10s gates %4d (%d backfilled)  runs %3d  sessions %3d  commits %4d  misses %3d"
              % (r["app"], r["project_type"], r["gates"], r["gates_backfilled"],
                 r["runs"], r["sessions"], r["commits"], r.get("misses", 0)))
    # The hook is per-CLONE (.git/ is not part of the repository), so a machine
    # that has never been refreshed silently records no commits at all. Say so —
    # this is the one telemetry gap the owner cannot see by reading the files.
    stale = [r for r in a["per_repo"] if r.get("stale_types")]
    if stale:
        print("")
        for r in stale:
            print("  ⚠ %s is classified '%s' now, but %s record(s) already written carry %s."
                  % (r["app"], r["project_type"], "some",
                     " / ".join("'%s'" % t for t in r["stale_types"])))
        print("    Those records keep the old value — the streams are append-only and a")
        print("    correction is applied at READ time, never by rewriting history. So this")
        print("    project appears under BOTH project_type segments below, and §6 forbids")
        print("    pooling them: read each as a period of the project, not as the whole of it.")
        print("    New records carry the corrected value from here on.")

    missing = [r["app"] for r in a["per_repo"] if r["commit_hook"] is False]
    if missing:
        print("")
        print("  ⚠ no commit-telemetry hook in THIS clone of: %s" % ", ".join(missing))
        print("    Commit telemetry is not being written here. Fix it for good with")
        print("    update-framework.sh <repo>, or reconcile what is already in the log:")
        print("      .tfcore/telemetry/tf-metrics.sh --backfill-commits <repo>")
    print("")

    for label in ("live", "backfilled"):
        if not a[label]:
            continue
        print("-" * W)
        if label == "live":
            print("LIVE records — written at the moment of the event")
        else:
            print("BACKFILLED records — RECONSTRUCTED. Context and volume only.")
            print("  `attempt` is inferred on every one of these. They CANNOT support a")
            print("  published first-pass rate. They are never summed with live figures.")
        print("-" * W)
        for ptype, m in a[label].items():
            print("  [%s]  %d records, %d REQs scored" % (ptype, m["records"], m["reqs_scored"]))
            print("     first-pass rate     : %s" % m["first_pass_rate"])
            print("     escape rate         : %s" % m["escape_rate"])
            if m["gate_distribution_note"]:
                print("     gate catch dist.    : %s" % m["gate_distribution_note"])
            else:
                total = m["gate_distribution_n"]
                print("     gate catch dist.    : (%d failures)" % total)
                for g, n in m["gate_distribution"].items():
                    tag = "  <- escaped: NO gate caught it" if g == "escaped" else ""
                    if g in LATE_GATES:
                        tag = "  <- see coverage below (added %s)" % LATE_GATES[g]
                    print("         %-14s %4d  %s%s" % (g, n, pct(n, total), tag))
            # A late-added gate's share of the total above is NOT its catch rate. Print the
            # real denominator, or say plainly that the gate has not run yet. SCHEMA.md §3.5.
            for g, cov in m.get("late_gate_coverage", {}).items():
                if cov["ran"] == 0 and cov["caught"] == 0:
                    print("     %-19s: not yet run on this data (gate added %s)" % (g + " gate", cov["since"]))
                else:
                    rate = (pct(cov["caught"], cov["ran"]) if cov["ran"] >= MIN_N
                            else "insufficient data (n=%d)" % cov["ran"])
                    print("     %-19s: ran on %d records, caught %d -> %s"
                          % (g + " gate", cov["ran"], cov["caught"], rate))
                    print("                          (share of the distribution above is NOT this rate)")
            print("")

    if len(a["live"]) > 1 or (a["live"] and a["backfilled"]):
        print("  NOTE: the figures above are deliberately NOT combined. Merging them")
        print("        across project_type or across live/backfilled would produce a")
        print("        number that cannot be defended. See SCHEMA.md §6.")
        print("")
    if a["tainted_reqs"]:
        print("  %d REQ(s) excluded from the LIVE first-pass rate because they carry"
              % len(a["tainted_reqs"]))
        print("  backfilled history, so their live attempt numbering restarts at 1:")
        print("    " + ", ".join(a["tainted_reqs"][:12]) +
              (" ..." if len(a["tainted_reqs"]) > 12 else ""))
        print("")

    p = a["pooled"]
    print("-" * W)
    print("POOLABLE — comparable across project_type and provenance")
    print("-" * W)
    print("  runs total          : %d   %s" % (p["runs_total"],
          " ".join("%s=%d" % kv for kv in p["runs_by_cmd"].items())))
    print("  rework ratio        : %s   (fix-mode runs / build-phase runs)" % p["rework_ratio"])
    print("  batch size (median) : %s REQs per build-phase run" %
          (p["batch_size_median"] if p["batch_size_median"] is not None else "insufficient data"))
    print("  REQ throughput      : %s REQs/hour (median across runs)" %
          (p["throughput_median_reqs_per_hour"] if p["throughput_median_reqs_per_hour"] is not None else "insufficient data"))
    print("  sessions / tokens   : %d sessions, %s total tokens" % (p["sessions"], "{:,}".format(p["tokens_total"])))
    print("  tokens per Verified : %s   (cost in USD is NEVER estimated — SCHEMA.md §4)" %
          (p["tokens_per_verified_req"] if p["tokens_per_verified_req"] is not None else "insufficient data"))
    print("  commit cadence      : %s commits/active day (%d commits over %d days)" %
          (p["commits_per_active_day"] if p["commits_per_active_day"] is not None else "—",
           p["commits"], p["active_days"]))
    if p.get("session_duplicates_collapsed"):
        print("                        (%d duplicate session_id(s) collapsed — normal for"
              % p["session_duplicates_collapsed"])
        print("                         OpenCode, which snapshots cumulatively; SCHEMA.md §4)")
    if p["commit_duplicates_collapsed"]:
        print("                        (%d duplicate sha(s) collapsed — normal after a union"
              % p["commit_duplicates_collapsed"])
        print("                         merge; the same commit was recorded on two machines)")

    print_misses(a["misses"], W)
    print("=" * W)


def print_misses(m, W):
    """The §5.5 block. Two exclusions are printed with the figures they bound —
    an exclusion the reader cannot see is indistinguishable from a bug."""
    if not m["misses_total"] and not m["miss_fixes_total"]:
        return
    print("")
    print("-" * W)
    print("MISSES — what was missed, who missed it, what the fix cost (SCHEMA.md §5.5)")
    print("-" * W)
    print("  misses logged       : %d   (%d open, %d resolved, %d wont-fix; %d fix records)"
          % (m["misses_total"], m["open_misses"], m["resolved_misses"],
             m["wont_fix"], m["miss_fixes_total"]))
    if m["wont_fix"]:
        print("                        (wont-fix is a DECISION, not a backlog item, so it is not")
        print("                         counted as open. The collapse check still treats it as a")
        print("                         live defect, so a repeat failure will not open a duplicate.)")
    if m["orphan_fixes"]:
        print("     ⚠ %d miss-fix record(s) name a miss_id with no opening record" % m["orphan_fixes"])
    print("  design-miss share   : %s   (miss_class=unspecified-gap — the spec, not the build)"
          % m["design_miss_share"])
    print("  found by a human    : %s   (found_by owner/production — reported BESIDE the"
          % m["escape_share"])
    print("                        gates.jsonl escape rate above, never merged with it)")
    if m["class_distribution"]:
        print("  miss classes        :")
        for k, n in m["class_distribution"].items():
            print("      %-24s %4d  %s" % (k, n, pct(n, m["misses_total"])))
    if m["found_by"]:
        print("  found by            : " +
              "  ".join("%s=%d" % kv for kv in m["found_by"].items()))
    # which PRACTICE failed — the field that says whether specification or verification
    # is the weak one. Optional, so it is reported against its own denominator.
    if m["why_missed"]:
        print("  why it was missed   : (%d of %d misses assessed)"
              % (m["why_missed_n"], m["why_missed_eligible"]))
        for k, n in m["why_missed"].items():
            print("      %-26s %4d  %s" % (k, n, pct(n, m["why_missed_n"])))
    if m["why_missed_predates_field"]:
        print("     %d miss(es) predate the field (added %s) and are outside that"
              % (m["why_missed_predates_field"], FIELD_SINCE["why_missed"]))
        print("     denominator — they had no field to fill, which is not the same as")
        print("     leaving one empty (SCHEMA.md §3.5, §5.5.6).")
    if m["escapes_missing_why"]:
        print("     ⚠ %d escape(s) carry no why_missed — something got past every gate and"
              % m["escapes_missing_why"])
        print("       nothing recorded why. That is the most valuable record in the stream.")
        print("       Complete it: tf-emit.sh --amend <miss_id> why_missed <value>  (§5.5.7)")
    if m["amendments_applied"]:
        print("  amendments folded   : %d field(s) completed by miss-amend records (§5.5.7)"
              % m["amendments_applied"])
    if m["orphan_amends"]:
        print("     ⚠ %d miss-amend record(s) name no known miss, or a field outside the"
              % m["orphan_amends"])
        print("       allowlist — counted, never applied")

    # ---- attribution-bounded figures
    print("")
    print("  ATTRIBUTION — linked records only (%d of %d; %d excluded as inferred/unknown)"
          % (m["attributed_n"], m["misses_total"], m["attribution_excluded"]))
    if m["attribution_excluded"]:
        print("     Excluded records named a phase no runs.jsonl record backs, so their model")
        print("     is unknown. A per-model rate computed from guesses is a routing decision")
        print("     made on invented evidence — SCHEMA.md §6, third separation.")
    if m["attributed_n"] < MIN_N:
        print("     insufficient data (n=%d)" % m["attributed_n"])
    else:
        for label, key in (("by origin phase", "by_origin_phase"),
                           ("by origin agent", "by_origin_agent"),
                           ("by origin model", "by_origin_model")):
            if m[key]:
                print("     %-16s: " % label +
                      "  ".join("%s=%d" % kv for kv in m[key].items()))

    # ---- cost, measured and apportioned, NEVER combined
    print("")
    print("  REWORK COST — measured and apportioned are separate columns, never one number")
    print("     sole (measured)   : %d fix records" % m["cost_sole_n"])
    print("        tokens out per miss : %s" %
          (m["tokens_per_miss_measured"] if m["tokens_per_miss_measured"] is not None
           else "insufficient data (n=%d)" % m["cost_sole_n"]))
    if m["cost_usd_per_miss_measured"] is not None:
        print("        USD per miss        : $%s  (MEASURED — %d OpenCode records)"
              % (m["cost_usd_per_miss_measured"], m["cost_usd_records"]))
    else:
        print("        USD per miss        : no measured dollars (%d priced records)"
              % m["cost_usd_records"])
        print("           Claude Code and Codex carry cost_usd:null permanently and are NEVER")
        print("           priced from a rate card here (SCHEMA.md §4). Real dollars come from")
        print("           OpenCode runs; token counts are the honest figure everywhere else.")
    print("     shared (apportioned): %d fix records — equal division, NOT a measurement"
          % m["cost_shared_n"])
    print("        tokens out per miss : %s" %
          (m["tokens_per_miss_apportioned"] if m["tokens_per_miss_apportioned"] is not None
           else "insufficient data (n=%d)" % m["cost_shared_n"]))
    print("     unattributable    : %d fix records with no usable token window"
          % m["cost_unattributable_n"])
    if m["cost_unattributable_n"]:
        print("        A miss fixed inline, with no distinct run record, cannot be costed.")
        print("        It counts toward the miss count and contributes nothing to the money.")


# -------------------------------------------------------------------- main
def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print("tf-metrics.sh — OWNER-RUN telemetry reporting & backfill (the only file")
        print("                in the framework allowed to contain git commands).")
        print("")
        print("  --report           [<repo>] [--json]   roll up one repo to stdout")
        print("  --rollup <repo>...          [--json]   cross-project view, still segmented")
        print("  --backfill-commits [<repo>] [--limit N] [--quiet] [--dry-run]")
        print("                     reconcile commits.jsonl against git log — idempotent,")
        print("                     gap-filling, and safe to run on any machine at any time.")
        print("                     This is how commits made on ANOTHER machine get recorded.")
        print("  --backfill-gates   [<repo>] [--dry-run]  parse the checklist -> gates.jsonl")
        print("")
        print("Live and backfilled figures are NEVER combined, and app/library/docs are")
        print("never pooled, for first-pass rate / gate distribution / escape rate.")
        print("There is no flag to turn that off. See .tfcore/telemetry/SCHEMA.md §6.")
        return 0

    mode = argv[0]
    rest = argv[1:]
    dry_run = "--dry-run" in rest
    as_json = "--json" in rest
    quiet = "--quiet" in rest
    limit = None
    for i, a in enumerate(rest):
        if a == "--limit" and i + 1 < len(rest):
            try:
                limit = int(rest[i + 1])
            except ValueError:
                die("--limit takes an integer")
    skip = set()
    for i, a in enumerate(rest):
        if a == "--limit":
            skip.add(i + 1)
    repos = [a for i, a in enumerate(rest) if not a.startswith("--") and i not in skip] or ["."]
    for r in repos:
        if not os.path.isdir(r):
            die("not a directory: %s" % r)

    if mode == "--backfill-commits":
        backfill_commits(repos[0], dry_run, limit=limit, quiet=quiet)
    elif mode == "--backfill-gates":
        backfill_gates(repos[0], dry_run)
    elif mode in ("--report", "--rollup"):
        a = analyse(repos)
        if as_json:
            print(json.dumps(a, indent=2))
        else:
            print_report(a, repos)
    else:
        die("unknown mode '%s' — see --help" % mode)
    return 0


raise SystemExit(main(sys.argv[1:]))
PYEOF

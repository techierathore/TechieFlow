#!/usr/bin/env bash
# TechieFlow telemetry — THE append primitive.
#
# Every component that writes telemetry calls this and ONLY this. Schema:
# .tfcore/telemetry/SCHEMA.md. Doctrine: .tfcore/tasks/_metrics-emit-gate.md.
#
# USAGE
#   echo '{"kind":"run","app":"TrSetup","cmd":"build-phase"}' | tf-emit.sh runs
#   tf-emit.sh --next-attempt REQ-UI-004        # prints an integer on stdout (gate attempt per REQ)
#   tf-emit.sh --next-run-attempt fix-issues REQ-UI-004 [REQ-...]
#                                               # prints an integer: the `attempt` the NEXT run record for
#                                               # this cmd + these REQs would get — the launch-time read
#                                               # behind routing.yaml `escalation:` (advisory)
#   tf-emit.sh --next-miss-id                   # prints MISS-<app>-<YYYYMMDD>-<NN> (SCHEMA.md §5.5.1)
#   tf-emit.sh --next-fix-attempt MISS-App-20260828-03   # prints an integer
#   tf-emit.sh --open-miss REQ-UI-014           # prints "<miss_id> <miss_class>" if a miss on that REQ
#                                               # is still open, nothing otherwise (the §5.5.4 collapse
#                                               # check — one defect is one miss, however often it fails)
#   tf-emit.sh --amend MISS-App-20260828-01 why_missed missing-checklist-item
#                                               # fills a field that is still null on a miss already on
#                                               # the stream (SCHEMA.md §5.5.7). Never overwrites.
#   tf-emit.sh --where                          # prints the resolved docs/metrics dir
#
# STREAMS: runs | gates | sessions | commits | misses   (anything else is dropped)
#
# misses.jsonl is the one stream carrying THREE record kinds — `miss` (opened),
# `miss-fix` (closed, linked by miss_id) and `miss-amend` (completes a field the
# `miss` left null — never overwrites one, so it can add information to the
# history without altering it). SCHEMA.md §5.5.
#
# ONE RECORD OR MANY. stdin is normally a single JSON object. It may also be a
# JSONL *stream* — one object per line — and every line is appended in ONE
# process. That exists for the reconcilers (the post-commit hook and
# tf-metrics.sh --backfill-*), which can have hundreds of records to write and
# used to pay a bash+python startup per record. A malformed line is dropped on
# its own; the rest of the batch still lands.
#
# WHAT IT INJECTS when the record does not already carry them:
#   v                       -> 1
#   ts                      -> now, ISO-8601 UTC, second precision, Z suffix
#   project_type            -> core-config.yaml : metrics.project_type
#   project_type_inferred   -> true, ONLY when metrics.project_type was absent
#   app                     -> inferred from docs/<App>-Checklist.md, else repo dir name
#   harness                 -> claude-code | opencode | null, DETECTED not declared
#                              (a task template cannot know which harness is running it,
#                              so it must never hard-code this; null when undeterminable,
#                              because a wrong harness label is worse than a missing one)
#   origin_model            -> on `miss` records: LOOKED UP from the runs.jsonl record whose
#   origin_harness             `started` == origin_run_id. Never written by an agent, for the
#                              same reason as `harness`: shared task markdown cannot know it,
#                              and a wrong model label corrupts every per-model comparison.
#   tokens_* / cost_usd     -> on `miss-fix` records: COPIED from the runs.jsonl record whose
#   tokens_scope / model       `started` == fix_run_id (that run's own window, already
#                              enriched at its append). Never recomputed, never estimated.
# Nothing else is ever added, reordered, or rewritten.
#
# HARD RULE — TELEMETRY HAS NO VETO. This script exits 0 UNCONDITIONALLY:
# missing dir, unreadable file, malformed JSON, absent python3, full disk. On any
# error the event is DROPPED and the caller continues, exactly the way
# guard-status.sh / guard-verify.sh already fail open. A telemetry bug must never
# cost the owner a working session.
#   TF_METRICS_DEBUG=1  -> explain a drop on stderr (still exits 0).
#
# NO GIT. This script never invokes git, and neither does anything that calls it.
# The only git-derived stream comes from the owner's own post-commit hook.

set +e

TF_DEBUG="${TF_METRICS_DEBUG:-}"
_warn() { [[ -n "$TF_DEBUG" ]] && printf 'tf-emit: %s\n' "$1" >&2; return 0; }
# Where python's stderr goes: nowhere unless the owner asked to see it.
TF_ERR=/dev/null
[[ -n "$TF_DEBUG" ]] && TF_ERR=/dev/stderr

# --- resolve the app repo root -------------------------------------------
# Explicit override first, then the harness's project dir, then walk up looking
# for a TechieFlow-shaped repo, then give up on the cwd.
_find_root() {
  if [[ -n "$TF_METRICS_ROOT" && -d "$TF_METRICS_ROOT" ]]; then
    printf '%s' "$TF_METRICS_ROOT"; return 0
  fi
  if [[ -n "$CLAUDE_PROJECT_DIR" && -d "$CLAUDE_PROJECT_DIR" ]]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"; return 0
  fi
  local d; d="$(pwd -P 2>/dev/null)" || return 1
  while [[ -n "$d" && "$d" != "/" ]]; do
    if [[ -d "$d/.tfcore" || -d "$d/docs" ]]; then printf '%s' "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  pwd -P 2>/dev/null
}

ROOT="$(_find_root)" || { _warn "cannot resolve repo root"; exit 0; }
[[ -n "$ROOT" ]] || { _warn "empty repo root"; exit 0; }
MET_DIR="$ROOT/docs/metrics"

case "$1" in
  --where) printf '%s\n' "$MET_DIR"; exit 0 ;;
esac

command -v python3 >/dev/null 2>&1 || { _warn "python3 absent — event dropped"; exit 0; }

# --- read helper: next attempt number for a REQ --------------------------
# attempt = 1 + count of prior NON-BACKFILLED gate records for this req_id.
# Backfilled records are excluded on purpose (SCHEMA.md §3.1) — a backfilled
# attempt is itself inferred, and counting it would propagate a guess into a
# live record. Prints an integer; prints 1 on any failure (never blocks).
if [[ "$1" == "--next-attempt" ]]; then
  REQ="$2"
  [[ -n "$REQ" ]] || { echo 1; exit 0; }
  python3 - "$MET_DIR/gates.jsonl" "$REQ" 2>"$TF_ERR" <<'PY' || echo 1
import json, sys
path, req = sys.argv[1], sys.argv[2]
n = 0
try:
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("kind") == "gate" and r.get("req_id") == req and not r.get("backfilled"):
                n += 1
except FileNotFoundError:
    pass
print(n + 1)
PY
  exit 0
fi

# --- read helper: next RUN attempt number for a cmd + REQ set ------------
# run attempt = 1 + count of prior NON-BACKFILLED `run` records with the same
# cmd whose reqs_touched intersects the given REQ IDs. Same counting rule that
# enrich_run() below stamps into `attempt` at append time, exposed so the
# escalation policy in routing.yaml can be applied BEFORE a run is launched
# (advisory; DECISIONS.md 2026-08-21). Prints 1 on any failure (never blocks).
if [[ "$1" == "--next-run-attempt" ]]; then
  CMD="$2"; shift 2 2>/dev/null
  [[ -n "$CMD" && $# -gt 0 ]] || { echo 1; exit 0; }
  python3 - "$MET_DIR/runs.jsonl" "$CMD" "$@" 2>"$TF_ERR" <<'PY' || echo 1
import json, sys
path, cmd, reqs = sys.argv[1], sys.argv[2], set(sys.argv[3:])
n = 0
try:
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if (r.get("kind") == "run" and r.get("cmd") == cmd and not r.get("backfilled")
                    and reqs & set(r.get("reqs_touched") or [])):
                n += 1
except FileNotFoundError:
    pass
print(n + 1)
PY
  exit 0
fi

# --- read helper: the next miss id ---------------------------------------
# MISS-<app>-<YYYYMMDD>-<NN>, NN = 1 + today's existing miss records for this app.
# An agent must never invent one: miss_id is the join key between a `miss` and its
# `miss-fix`, and a collision would silently merge two defects into one lifecycle.
if [[ "$1" == "--next-miss-id" ]]; then
  python3 - "$MET_DIR/misses.jsonl" "$ROOT" 2>"$TF_ERR" <<'PY' || true
import datetime, glob, json, os, sys
path, root = sys.argv[1], sys.argv[2]
hits = glob.glob(os.path.join(root, "docs", "*-Checklist.md"))
app = (os.path.basename(hits[0])[: -len("-Checklist.md")] if len(hits) == 1
       else os.path.basename(os.path.abspath(root)))
day = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d")
stem = "MISS-%s-%s-" % (app, day)
n = 0
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            mid = r.get("miss_id") or ""
            if r.get("kind") == "miss" and mid.startswith(stem):
                try:
                    n = max(n, int(mid[len(stem):]))
                except ValueError:
                    pass
except FileNotFoundError:
    pass
print("%s%02d" % (stem, n + 1))
PY
  exit 0
fi

# --- read helper: next fix attempt for a miss ----------------------------
if [[ "$1" == "--next-fix-attempt" ]]; then
  MID="$2"
  [[ -n "$MID" ]] || { echo 1; exit 0; }
  python3 - "$MET_DIR/misses.jsonl" "$MID" 2>"$TF_ERR" <<'PY' || echo 1
import json, sys
path, mid = sys.argv[1], sys.argv[2]
n = 0
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("kind") == "miss-fix" and r.get("miss_id") == mid:
                n += 1
except FileNotFoundError:
    pass
print(n + 1)
PY
  exit 0
fi

# --- read helper: is a miss on this REQ still open? -----------------------
# SCHEMA.md §5.5.4 — the collapse check. A REQ that fails three verify passes
# must produce ONE miss, not three; otherwise the miss count measures retry
# patience rather than quality. Open = no miss-fix, or the latest miss-fix
# closed with a verdict_after other than "Verified". Prints "<miss_id>
# <miss_class>" for the most recent open miss, or nothing at all.
if [[ "$1" == "--open-miss" ]]; then
  REQ="$2"
  [[ -n "$REQ" ]] || exit 0
  python3 - "$MET_DIR/misses.jsonl" "$REQ" 2>"$TF_ERR" <<'PY' || true
import json, sys
path, req = sys.argv[1], sys.argv[2]
opened, fixes = [], {}
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("kind") == "miss" and r.get("req_id") == req:
                opened.append(r)
            elif r.get("kind") == "miss-fix":
                mid = r.get("miss_id")
                if mid:
                    prev = fixes.get(mid)
                    if prev is None or (r.get("ts") or "") >= (prev.get("ts") or ""):
                        fixes[mid] = r
except FileNotFoundError:
    pass
for r in reversed(opened):                     # most recent first
    fix = fixes.get(r.get("miss_id"))
    if fix is None or fix.get("verdict_after") != "Verified":
        print("%s %s" % (r.get("miss_id"), r.get("miss_class") or "other"))
        break
PY
  exit 0
fi

# --- write helper: complete a field that was left null --------------------
# SCHEMA.md §5.5.7. The ONLY sanctioned way to fill a field on a record that is
# already on the stream — and the reason constraint 5's "the correction is a new
# record, never an edit" now names something that exists for this stream.
#
#   tf-emit.sh --amend MISS-App-20260828-01 why_missed missing-checklist-item
#
# Refuses, out loud and on stdout, when the field is not amendable, the value is
# outside its closed vocabulary, no parent miss exists, or the field already has
# a value. It COMPLETES a record; it never alters a fact. Exits 0 either way —
# telemetry has no veto (§10), and neither does a refused amend.
if [[ "$1" == "--amend" ]]; then
  AMID="$2"; AFLD="$3"; AVAL="$4"
  if [[ -z "$AMID" || -z "$AFLD" || -z "$AVAL" ]]; then
    echo "tf-emit: --amend needs <miss_id> <field> <value>"
    exit 0
  fi
  AREC="$(python3 - "$MET_DIR/misses.jsonl" "$AMID" "$AFLD" "$AVAL" 2>"$TF_ERR" <<'PY' || true
import json, sys
path, mid, fld, val = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# THE ALLOWLIST, and the rule for extending it (SCHEMA.md §5.5.7).
# A field is amendable only when it is (a) a closed-vocabulary JUDGEMENT that a
# reader can still make correctly later, and (b) not derived by this emitter.
# An OBSERVATION is never amendable — §3.5's rule for a gate added mid-stream
# ("never backfill the old records with a verdict they never had") is the same
# rule seen from the other side: `why_missed` is a classification an analyst can
# still make honestly next week; `found_gate` is a fact about a run that is over.
# Attribution and cost fields are excluded outright: the emitter derives those,
# and an amend that could set them would be a hole straight through §5.5.1.
AMENDABLE = {
    "why_missed": ("missing-checklist-item", "insufficient-verify-method",
                   "code-audit-limitation", "ambiguous-acceptance",
                   "dependency-not-declared", "instruction-ignored", "other"),
}
if fld not in AMENDABLE:
    print("REFUSED %s is not an amendable field (SCHEMA.md §5.5.7)" % fld); raise SystemExit(0)
if val not in AMENDABLE[fld]:
    print("REFUSED %r is not in the closed vocabulary for %s" % (val, fld)); raise SystemExit(0)

parent, current = None, None
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("kind") == "miss" and r.get("miss_id") == mid:
                parent = r
                current = r.get(fld)
            elif (r.get("kind") == "miss-amend" and r.get("miss_id") == mid
                  and r.get("field") == fld):
                current = r.get("value")          # an earlier amend already set it
except FileNotFoundError:
    pass

if parent is None:
    print("REFUSED no miss record %s on this stream" % mid); raise SystemExit(0)
if current is not None:
    print("REFUSED %s is already %r on %s — an amend completes a record, never "
          "overwrites a value" % (fld, current, mid)); raise SystemExit(0)

print("OK " + json.dumps({"kind": "miss-amend", "miss_id": mid,
                          "field": fld, "value": val},
                         separators=(",", ":"), ensure_ascii=False))
PY
)"
  case "$AREC" in
    "OK "*) printf '%s' "${AREC#OK }" | bash "${BASH_SOURCE[0]}" misses
            echo "tf-emit: amended $AMID — $AFLD = $AVAL" ;;
    "REFUSED "*) echo "tf-emit: amend refused — ${AREC#REFUSED }" ;;
    *) echo "tf-emit: amend could not be evaluated — nothing written" ;;
  esac
  exit 0
fi

# --- append path ----------------------------------------------------------
STREAM="$1"
case "$STREAM" in
  runs|gates|sessions|commits|misses) ;;
  *) _warn "unknown stream '${STREAM:-<none>}' — event dropped"; exit 0 ;;
esac

# The program is captured into a variable rather than fed on stdin — a heredoc
# on `python3 -` would REPLACE the caller's piped JSON and silently drop every event.
TF_PROG="$(cat <<'PY'
import json, os, sys, datetime, glob, re

met_dir, stream, root = sys.argv[1], sys.argv[2], sys.argv[3]
dbg = os.environ.get("TF_METRICS_DEBUG")

def warn(msg):
    if dbg:
        sys.stderr.write("tf-emit: %s\n" % msg)

raw = sys.stdin.read()
if not raw.strip():
    warn("empty stdin — event dropped")
    raise SystemExit(0)

# One object, or a JSONL stream of them. The single-object form is tried first so
# a pretty-printed record spanning several lines still works exactly as before;
# only if that fails is the input read line-by-line as a batch.
records = []
try:
    one = json.loads(raw)
    records = one if isinstance(one, list) else [one]
except Exception as whole_err:
    for n, line in enumerate(raw.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except Exception as e:
            warn("stdin line %d is not valid JSON (%s) — line dropped" % (n, e))
    if not records:
        warn("stdin is not valid JSON (%s) — event dropped" % whole_err)
        raise SystemExit(0)

records = [r for r in records if isinstance(r, dict)]
if not records:
    warn("no JSON object in stdin — event dropped")
    raise SystemExit(0)

# --- values resolved ONCE for the whole batch ----------------------------
# project_type, harness and app are properties of the repo and the process, not
# of the individual record, so a 400-record reconcile reads core-config.yaml and
# walks the process tree once rather than 400 times.

# project_type from core-config.yaml : metrics.project_type
#   metrics:
#     project_type: app
def _project_type():
    # STRUCTURAL SIGNAL FIRST, and it is authoritative. A repo carrying the
    # scaffold scripts beside .tfcore/tasks/ IS the framework template — nothing
    # else can be, and a scaffolded app never has them at its root.
    #
    # This is checked ahead of core-config.yaml, and deliberately: the framework's
    # own core-config.yaml is the file the scaffolds rsync into a new app with
    # --ignore-existing, so recording `project_type: framework` in it would stamp
    # `framework` on every app created afterwards, and install-metrics.sh would
    # then never re-guess (an existing classification always wins). Detecting it
    # from the tree shape instead means the framework can classify itself without
    # anything to leak. install-metrics.sh knows the same rule and writes nothing.
    try:
        if (os.path.isfile(os.path.join(root, "scaffold-brownfield.sh"))
                and os.path.isdir(os.path.join(root, ".tfcore", "tasks"))):
            return "framework"
    except Exception:
        pass
    cfg = os.path.join(root, ".tfcore", "core-config.yaml")
    try:
        with open(cfg, "r", encoding="utf-8") as fh:
            text = fh.read()
        m = re.search(
            r"^metrics:[ \t]*$(?:\n(?:[ \t]+.*|[ \t]*))*?\n[ \t]+project_type:[ \t]*"
            r"[\"']?(app|library|docs|framework)[\"']?[ \t]*$",
            text,
            re.M,
        )
        if m:
            return m.group(1)
    except Exception:
        pass
    return None

PTYPE = _project_type()

# harness — DETECTED, never taken on trust. The task markdown is shared by all
# harnesses, so an agent copying a template literal would stamp whichever harness
# the example happened to name. Detection order: harness env vars, then the parent
# process chain (OpenCode sets no OPENCODE_* vars, so the process name is the only
# honest signal). Undeterminable -> null: a wrong label silently corrupts any
# per-harness comparison, a missing one is merely missing.
def _detect_harness():
    # TF_HARNESS is set by the harness bridge itself (the OpenCode plugin's
    # shell.env / guard spawns — .opencode/plugin/techieflow.js), never by an
    # agent, and beats the marker-variable scan: a process launched from inside
    # the OTHER harness inherits that harness's markers (e.g. OpenCode started
    # from a Claude Code bash still carries CLAUDE_PROJECT_DIR).
    tf = os.environ.get("TF_HARNESS")
    if tf in ("claude-code", "opencode", "codex"):
        return tf
    for k in ("CODEX_THREAD_ID", "CODEX_SESSION_ID"):
        if os.environ.get(k):
            return "codex"
    for k in ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID",
              "CLAUDE_PROJECT_DIR"):
        if os.environ.get(k):
            return "claude-code"
    for k in os.environ:
        if k.startswith("OPENCODE"):
            return "opencode"
    # Walk the process ancestry (bounded). Linux/WSL via /proc; macOS via ps.
    try:
        pid, seen = os.getppid(), 0
        while pid and pid > 1 and seen < 12:
            seen += 1
            name = ppid = None
            try:
                with open("/proc/%d/stat" % pid) as fh:
                    stat = fh.read()
                name = stat[stat.find("(") + 1: stat.rfind(")")]
                ppid = int(stat[stat.rfind(")") + 2:].split()[1])
            except Exception:
                import subprocess
                out = subprocess.run(["ps", "-o", "comm=,ppid=", "-p", str(pid)],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                parts = out.stdout.decode("utf-8", "replace").split()
                if len(parts) >= 2:
                    name, ppid = os.path.basename(parts[0]), int(parts[1])
            if name and "opencode" in name.lower():
                return "opencode"
            if name and "codex" in name.lower():
                return "codex"
            if name and "claude" in name.lower():
                return "claude-code"
            pid = ppid
    except Exception:
        pass
    return None

try:
    HARNESS = _detect_harness()
except Exception:
    HARNESS = None

# app name — inferred from the one checklist, else the repo directory name
def _app_name():
    try:
        hits = glob.glob(os.path.join(root, "docs", "*-Checklist.md"))
        if len(hits) == 1:
            return os.path.basename(hits[0])[: -len("-Checklist.md")]
    except Exception:
        pass
    return None

APP = _app_name() or os.path.basename(os.path.abspath(root))

NOW = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def enrich(rec):
    """Fill the injected fields on ONE record. Nothing else is ever added,
    reordered, or rewritten — except the per-run window/tier fields added by
    enrich_run() below for runs/gates records (docs/Telemetry-Hooks.md §2-§4,
    DECISIONS.md 2026-08-20)."""
    rec.setdefault("v", 1)
    rec.setdefault("ts", NOW)
    if "project_type" not in rec:
        if PTYPE:
            rec["project_type"] = PTYPE
        else:
            # Default, but NEVER silently — the report labels these unclassified.
            rec["project_type"] = "app"
            rec["project_type_inferred"] = True
    rec.setdefault("harness", HARNESS)
    rec.setdefault("app", APP)
    return rec

# --- per-run tier + token-window enrichment (runs/gates only) -------------
# Declared tier comes from .tfcore/routing.yaml (only when enabled: true).
# Observed model/tokens come from the harness's own store, windowed on the
# record's started/ended: Claude Code = the transcript named by the session
# pointer .tfcore/.session/claude-code.json (main thread only -> scope "main");
# OpenCode = opencode.db messages for the pointer session + its descendants
# (scope "tree", real cost). Every failure degrades to tokens_scope:"none" —
# tokens are NEVER estimated. Dollars are never computed on Claude (no source).

def _routing():
    out = {"enabled": False, "phases": {}, "subagents": {}, "tiers": {}}
    try:
        sect, tier = None, None
        with open(os.path.join(root, ".tfcore", "routing.yaml"), encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                if not line.startswith(" "):
                    key, _, val = line.partition(":")
                    sect, tier = key.strip(), None
                    if sect == "enabled":
                        out["enabled"] = val.strip() == "true"
                elif sect == "tiers":
                    if re.match(r"^  [a-z-]+:\s*$", line):
                        tier = line.strip()[:-1]
                        out["tiers"][tier] = {}
                    elif tier and line.startswith("    "):
                        k, _, v = line.strip().partition(":")
                        out["tiers"][tier][k.strip()] = v.strip()
                elif sect in ("phases", "subagents"):
                    k, _, v = line.strip().partition(":")
                    out[sect][k.strip()] = v.strip()
    except Exception:
        pass
    return out

ROUTING = _routing()

def _iso_ms(s):
    try:
        return int(datetime.datetime.strptime(
            s.replace("Z", "+0000"), "%Y-%m-%dT%H:%M:%S%z").timestamp() * 1000)
    except Exception:
        return None

def _pointer(name):
    try:
        with open(os.path.join(root, ".tfcore", ".session", name + ".json"),
                  encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None

def _sum_claude_transcript(path, t0, t1, tot, models):
    """Sum one transcript's in-window assistant messages. Returns the OUTPUT tokens
    this transcript alone contributed, so the caller can split main from subagents
    (SCHEMA.md §2.5 `tokens_out_subagents`) without walking the file twice."""
    before = tot["out"]
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if '"assistant"' not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("type") != "assistant":
                continue
            ts = _iso_ms((r.get("timestamp") or "").split(".")[0].rstrip("Z") + "Z")
            if ts is None or ts < t0 or ts > t1:
                continue
            msg = r.get("message") or {}
            u = msg.get("usage") or {}
            o = u.get("output_tokens") or 0
            tot["in"] += u.get("input_tokens") or 0
            tot["out"] += o
            tot["cr"] += u.get("cache_read_input_tokens") or 0
            tot["cw"] += u.get("cache_creation_input_tokens") or 0
            m = msg.get("model")
            if m:
                models[m] = models.get(m, 0) + o
    return tot["out"] - before

def _window_claude(t0, t1):
    ptr = _pointer("claude-code")
    if not ptr:
        return None
    path = ptr.get("transcript_path")
    if not path or not os.path.isfile(path):
        return None
    tot = {"in": 0, "out": 0, "cr": 0, "cw": 0}
    models = {}
    scope = "main"
    sub_runs, sub_out = 0, 0
    try:
        _sum_claude_transcript(path, t0, t1, tot, models)
        # Subagent transcripts live at a deterministic path beside the parent's:
        # <transcript-dir>/<session-id>/subagents/agent-*.jsonl (same JSONL
        # format; verified 2026-08-20 via a SubagentStop payload's
        # agent_transcript_path — DECISIONS.md 2026-08-20). Including them
        # upgrades the window from "main" to "tree" with no hook needed.
        if path.endswith(".jsonl"):
            subdir = os.path.join(path[:-len(".jsonl")], "subagents")
            if os.path.isdir(subdir):
                scope = "tree"
                for sub in glob.glob(os.path.join(subdir, "*.jsonl")):
                    try:
                        # A transcript that produced NOTHING inside this run's
                        # window belongs to a different run in the same session —
                        # counting it would make every later phase look like it
                        # fanned out as widely as the busiest one before it. Only
                        # a transcript with in-window output is this run's.
                        got = _sum_claude_transcript(sub, t0, t1, tot, models)
                        if got > 0:
                            sub_runs += 1
                            sub_out += got
                    except Exception:
                        pass
    except Exception:
        return None
    if tot["in"] + tot["out"] == 0:
        return None
    return {"tot": tot, "models": models, "cost": None, "scope": scope,
            "sub_runs": sub_runs, "sub_out": sub_out}

def _window_opencode(t0, t1):
    ptr = _pointer("opencode")
    if not ptr:
        return None
    dbp = ptr.get("db_path")
    sid = ptr.get("session_id")
    if not dbp or not sid or not os.path.isfile(dbp):
        return None
    try:
        import sqlite3
        db = sqlite3.connect("file:%s?mode=ro" % dbp, uri=True)
        pairs = db.execute("SELECT id, parent_id FROM session").fetchall()
        kids = {}
        for i, p in pairs:
            kids.setdefault(p, []).append(i)
        tree, queue = {sid}, [sid]
        while queue:
            for c in kids.get(queue.pop(), []):
                if c not in tree:
                    tree.add(c)
                    queue.append(c)
        tot = {"in": 0, "out": 0, "cr": 0, "cw": 0}
        models = {}
        cost = 0.0
        # Same rule as the Claude branch: a CHILD session counts as a subagent run
        # for THIS window only if it produced output inside it.
        child_out = {}
        q = "SELECT session_id, data FROM message WHERE time_created BETWEEN ? AND ?"
        for msid, data in db.execute(q, (t0, t1)):
            if msid not in tree:
                continue
            try:
                d = json.loads(data)
            except Exception:
                continue
            if d.get("role") != "assistant":
                continue
            t = d.get("tokens") or {}
            cache = t.get("cache") or {}
            o = t.get("output") or 0
            tot["in"] += t.get("input") or 0
            tot["out"] += o
            tot["cr"] += cache.get("read") or 0
            tot["cw"] += cache.get("write") or 0
            cost += d.get("cost") or 0
            if msid != sid and o:
                child_out[msid] = child_out.get(msid, 0) + o
            m = (d.get("providerID", "") + "/" if d.get("providerID") else "") + (d.get("modelID") or "")
            if m:
                models[m] = models.get(m, 0) + o
        db.close()
    except Exception:
        return None
    if tot["in"] + tot["out"] == 0:
        return None
    return {"tot": tot, "models": models, "cost": round(cost, 6), "scope": "tree",
            "sub_runs": len(child_out), "sub_out": sum(child_out.values())}

# --- per-run `attempt` (runs only; added 2026-08-21, SCHEMA.md §2.5) ------
# attempt = 1 + prior NON-BACKFILLED `run` records with the same cmd whose
# reqs_touched intersects this record's. Stamped only on live records that
# carry a non-empty reqs_touched; backfilled records are left as the
# reconciler wrote them. This is the counter routing.yaml `escalation:` reads
# at launch (advisory — tf-emit never changes a model, it only records).
_PRIOR_RUNS = None

def _prior_runs():
    global _PRIOR_RUNS
    if _PRIOR_RUNS is None:
        _PRIOR_RUNS = []
        try:
            with open(os.path.join(met_dir, "runs.jsonl"), encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if r.get("kind") == "run" and not r.get("backfilled"):
                        _PRIOR_RUNS.append((r.get("cmd"), set(r.get("reqs_touched") or [])))
        except Exception:
            pass
    return _PRIOR_RUNS

def stamp_attempt(rec):
    if stream != "runs" or "attempt" in rec or rec.get("backfilled"):
        return rec
    try:
        reqs = set(rec.get("reqs_touched") or [])
        cmd = rec.get("cmd")
        if not reqs or not cmd or rec.get("kind", "run") != "run":
            return rec
        prior = _prior_runs()
        rec["attempt"] = 1 + sum(1 for c, rs in prior if c == cmd and (rs & reqs))
        prior.append((cmd, reqs))  # later records in the same batch count this one
    except Exception as e:
        warn("attempt stamp failed (%s) — record kept without it" % e)
    return rec

def enrich_run(rec):
    if stream not in ("runs", "gates"):
        return rec
    try:
        cmd = rec.get("cmd")
        if ROUTING["enabled"] and cmd and "tier" not in rec:
            tier = ROUTING["phases"].get(cmd)
            if tier and tier != "inherit":
                rec["tier"] = tier
                key = {"claude-code": "claude", "opencode": "opencode", "codex": "codex"}.get(HARNESS)
                tm = ROUTING["tiers"].get(tier, {}).get(key) if key else None
                if tm:
                    rec["tier_model"] = tm
        if rec.get("started") and rec.get("ended") and "tokens_scope" not in rec:
            t0, t1 = _iso_ms(rec["started"]), _iso_ms(rec["ended"])
            win = None
            if t0 is not None and t1 is not None and t1 >= t0:
                if HARNESS == "claude-code":
                    win = _window_claude(t0, t1)
                elif HARNESS == "opencode":
                    win = _window_opencode(t0, t1)
            if win:
                models = sorted(win["models"], key=win["models"].get, reverse=True)
                if models:
                    rec["model"] = models[0]
                    if len(models) > 1:
                        rec["models"] = models
                    # The per-model OUTPUT split, not just the winner's name. A run
                    # that spent 90% of its output on one model and 10% on another
                    # is a different fact from one that split evenly, and `model` +
                    # `models` cannot tell them apart. Effort-per-phase-per-model is
                    # unanswerable without it (SCHEMA.md §2.6).
                    rec["model_tokens_out"] = {m: win["models"][m] for m in models}
                rec["tokens_in"] = win["tot"]["in"]
                rec["tokens_out"] = win["tot"]["out"]
                rec["tokens_cache_read"] = win["tot"]["cr"]
                rec["tokens_cache_write"] = win["tot"]["cw"]
                rec["cost_usd"] = win["cost"]
                rec["tokens_scope"] = win["scope"]
                # MEASURED fan-out, never self-reported (SCHEMA.md §2.6). `subagents`
                # is a list of names an agent types and cannot be trusted to keep in
                # step with what it actually spawned; these two are counted from the
                # harness's own store — the subagent transcripts beside the parent's
                # on Claude, the child sessions in opencode.db on OpenCode. Absent
                # whenever the window could not be computed: absent means "not
                # captured", never 0.
                rec["subagent_runs"] = win.get("sub_runs", 0)
                rec["tokens_out_subagents"] = win.get("sub_out", 0)
                if rec.get("tier_model") and rec.get("model"):
                    rec["routed"] = rec["model"] == rec["tier_model"]
            else:
                rec["tokens_scope"] = "none"
    except Exception as e:
        warn("run enrichment failed (%s) — record kept unenriched" % e)
    return rec

# --- miss enrichment (misses only; SCHEMA.md §5.5) ------------------------
# Two lookups, both against runs.jsonl, both replacing an agent judgement with a
# fact the emitter can check:
#
#   `miss`      origin_run_id -> origin_model / origin_harness, and
#               origin_confidence DERIVED (linked | inferred | unknown).
#               An agent cannot know which model ran a phase two days ago, and a
#               copied literal would corrupt every per-model comparison — the same
#               reasoning that makes `harness` detected rather than declared.
#
#   `miss-fix`  fix_run_id -> that run's already-enriched token window, copied
#               verbatim, plus cost_attribution DERIVED from its reqs_touched.
#               Never recomputed and never estimated: if the run carried no
#               window, this record carries no numbers (SCHEMA.md §5.5.3).
_RUNS_BY_START = None

def _fixes_on_run(fix_run_id, this_miss_id):
    """How many DISTINCT misses this fix run has closed, counting the one being
    written. The divisor for a repo with no REQs (see the miss-fix branch below).
    Counts miss_ids, not records, so a re-attempt on the same miss never inflates
    it. Returns 1 on any failure — the run measured a window and closed at least
    this miss, so 1 is the floor, and a floor understates the share rather than
    inventing one."""
    n = {this_miss_id} if this_miss_id else set()
    try:
        with open(os.path.join(met_dir, "misses.jsonl"), encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("kind") == "miss-fix" and r.get("fix_run_id") == fix_run_id \
                        and r.get("miss_id"):
                    n.add(r["miss_id"])
    except Exception:
        pass
    return max(len(n), 1)


def _runs_by_start():
    global _RUNS_BY_START
    if _RUNS_BY_START is None:
        _RUNS_BY_START = {}
        try:
            with open(os.path.join(met_dir, "runs.jsonl"), encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if r.get("kind") == "run" and r.get("started"):
                        _RUNS_BY_START[r["started"]] = r
        except Exception:
            pass
    return _RUNS_BY_START

_COST_FIELDS = ("tokens_in", "tokens_out", "tokens_cache_read", "tokens_cache_write",
                "cost_usd", "tokens_scope", "model")

# Kept identical to the --amend branch above. Two doors, ONE enforcement: an
# agent that hand-writes a miss-amend record onto the stream faces the same
# checks as one that calls --amend, because the invariant belongs to the
# emitter and not to whichever path reached it (SCHEMA.md §5.5.7).
_AMENDABLE = {
    "why_missed": ("missing-checklist-item", "insufficient-verify-method",
                   "code-audit-limitation", "ambiguous-acceptance",
                   "dependency-not-declared", "instruction-ignored", "other"),
}

def _amend_ok(rec):
    """True when this miss-amend may be appended. Returning False DROPS it —
    an invalid amend writes nothing rather than landing as a record the reader
    then has to defend itself against."""
    mid, fld, val = rec.get("miss_id"), rec.get("field"), rec.get("value")
    if fld not in _AMENDABLE or val not in _AMENDABLE[fld] or not mid:
        warn("amend refused — %r/%r outside the §5.5.7 allowlist" % (fld, val))
        return False
    parent, current = None, None
    try:
        with open(os.path.join(met_dir, "misses.jsonl"), encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("kind") == "miss" and r.get("miss_id") == mid:
                    parent, current = r, r.get(fld)
                elif (r.get("kind") == "miss-amend" and r.get("miss_id") == mid
                      and r.get("field") == fld):
                    current = r.get("value")
    except FileNotFoundError:
        pass
    if parent is None:
        warn("amend refused — no miss record %s on this stream" % mid)
        return False
    if current is not None:
        warn("amend refused — %s already set on %s" % (fld, mid))
        return False
    return True

# The closed vocabularies of SCHEMA.md §5.5.1 / §5.5.2 / §3.3, enforced ON WRITE.
#
# Until 2026-08-31 the emitter validated the miss-amend allowlist meticulously and
# validated a `miss` record's own enums NOT AT ALL — so a typo in miss_class landed
# permanently on an append-only stream, invented a bucket in every distribution built
# on it, and could not be corrected: `miss_class` is not amendable (§5.5.7 allows only
# closed-vocabulary JUDGEMENTS the emitter does not derive), and constraint 5 forbids
# editing the file. The only remaining move was to report it.
#
# That is the asymmetry this closes. Dropping an invalid record is the SAME choice
# _amend_ok() already makes and for the same reason: a record the reader has to
# defend itself against is worse than no record. The refusal is printed on stdout —
# an agent that believes it logged a miss and did not is worse off than one told no.
_MISS_ENUMS = {
    "miss_class": ("missed-requirement", "partial-implementation", "wrong-behaviour",
                   "regression", "unspecified-gap", "spec-contradiction", "scope-creep",
                   "hallucinated-api", "standards-violation", "other"),
    "artifact": ("brd", "architecture", "uidesign", "checklist", "devguide", "src",
                 "tests", "config", "other"),
    "severity": ("blocker", "major", "minor"),
    "found_by": ("gate", "self-smoke", "owner", "production", "agent-review",
                 "library-feedback"),
    "why_missed": ("missing-checklist-item", "insufficient-verify-method",
                   "code-audit-limitation", "ambiguous-acceptance",
                   "dependency-not-declared", "instruction-ignored", "other"),
}
_FIX_ENUMS = {
    "verdict_after": ("Verified", "Needs re-verify", "FAIL", "deferred", "wont-fix"),
    "fix_cmd": ("fix-issues", "build-phase", "triage-issues", "amend-docs", "log-miss"),
}


def _enums_ok(rec, table):
    """False -> DROP. Prints the refusal on stdout as --amend does; still exits 0,
    because telemetry has no veto (§10) and neither does a refused record."""
    for field, vocab in table.items():
        val = rec.get(field)
        if val is None:                     # optional and absent is always fine
            continue
        if val not in vocab:
            sys.stdout.write(
                "tf-emit: REFUSED — %r is not in the closed vocabulary for %s "
                "(SCHEMA.md §5.5). Nothing was appended. Allowed: %s\n"
                % (val, field, ", ".join(vocab)))
            return False
    return True


def enrich_miss(rec):
    if stream != "misses":
        return rec
    if rec.get("kind") == "miss-amend":
        return rec if _amend_ok(rec) else None
    if rec.get("kind") == "miss" and not _enums_ok(rec, _MISS_ENUMS):
        return None
    if rec.get("kind") == "miss-fix" and not _enums_ok(rec, _FIX_ENUMS):
        return None
    try:
        kind = rec.get("kind")
        runs = _runs_by_start()
        if kind == "miss":
            src = runs.get(rec.get("origin_run_id")) if rec.get("origin_run_id") else None
            if src:
                rec["origin_confidence"] = "linked"
                rec["origin_model"] = src.get("model")
                rec["origin_harness"] = src.get("harness")
            else:
                # Named a phase but no run record backs it -> inferred. Named
                # nothing -> unknown. Either way the model is FORCED to null,
                # overwriting anything the caller put there: a guess here is worse
                # than a gap, because nothing downstream can see that it was one.
                rec["origin_confidence"] = "inferred" if rec.get("origin_phase") else "unknown"
                rec["origin_model"] = None
                rec["origin_harness"] = None
        elif kind == "miss-fix":
            src = runs.get(rec.get("fix_run_id")) if rec.get("fix_run_id") else None
            if src:
                for f in _COST_FIELDS:
                    if f in src and f not in rec:
                        rec[f] = src[f]
                if "cost_attribution" not in rec:
                    touched = src.get("reqs_touched") or []
                    if rec.get("tokens_scope") == "none" or not rec.get("tokens_scope"):
                        rec["cost_attribution"] = "none"
                    elif len(touched) == 1 and touched[0] == rec.get("req_id"):
                        rec["cost_attribution"] = "sole"
                    elif len(touched) > 1:
                        rec["cost_attribution"] = "shared:%d" % len(touched)
                    else:
                        # reqs_touched is EMPTY but the run resolved and measured a
                        # real window. Until 2026-08-28 this fell through to "none",
                        # which §5.5.3 defines as "tokens_scope was none, or the
                        # fix_run_id matched no run" — neither is true here, so the
                        # stream was calling a measured window unattributable and
                        # every cost figure for these repos was structurally zero.
                        # A `framework` or `docs` project has no REQs to touch AT
                        # ALL, so keying the divisor on reqs_touched can never work
                        # there (the same blind spot as project_type:"framework",
                        # fixed earlier the same day). The divisor is instead the
                        # number of misses this run closed. That count is only
                        # complete once the batch is on the stream, so what is
                        # stored here is the count SO FAR and `tf-metrics.sh`
                        # recomputes it per fix_run_id at report time (§8: derived
                        # metrics are computed, never trusted from storage).
                        _n = _fixes_on_run(rec.get("fix_run_id"), rec.get("miss_id"))
                        rec["cost_attribution"] = "sole" if _n == 1 else "shared:%d" % _n
            else:
                rec.setdefault("cost_attribution", "none")
                rec.setdefault("tokens_scope", "none")
    except Exception as e:
        warn("miss enrichment failed (%s) — record kept unenriched" % e)
    return rec

# --- append --------------------------------------------------------------
# newline="\n" is NOT optional. Python's text mode translates "\n" to the
# platform separator, so on native Windows every append would land as CRLF —
# mixing line endings inside an append-only log, and tripping Git's
# "this file uses LF but will be checked out as CRLF" warning on a stream the
# .gitattributes block pins to LF. These files are LF on every platform.
lines = []
for rec in records:
    out = enrich_miss(enrich_run(stamp_attempt(enrich(rec))))
    if out is None:                 # a refused miss-amend (§5.5.7) — dropped, never appended
        continue
    line = json.dumps(out, separators=(",", ":"), ensure_ascii=False)
    if "\n" in line or "\r" in line:
        warn("record serialised with a newline — record dropped")
        continue
    lines.append(line + "\n")

if not lines:
    raise SystemExit(0)

try:
    os.makedirs(met_dir, exist_ok=True)
    with open(os.path.join(met_dir, stream + ".jsonl"), "a",
              encoding="utf-8", newline="\n") as fh:
        fh.write("".join(lines))
except Exception as e:
    warn("append failed (%s) — event dropped" % e)
    raise SystemExit(0)
PY
)"
python3 -c "$TF_PROG" "$MET_DIR" "$STREAM" "$ROOT" 2>"$TF_ERR"

exit 0

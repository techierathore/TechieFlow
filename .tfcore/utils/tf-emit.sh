#!/usr/bin/env bash
# TechieFlow telemetry — THE append primitive.
#
# Every component that writes telemetry calls this and ONLY this. Schema:
# .tfcore/telemetry/SCHEMA.md. Doctrine: .tfcore/tasks/_metrics-emit-gate.md.
#
# USAGE
#   echo '{"kind":"run","app":"TrSetup","cmd":"build-phase"}' | tf-emit.sh runs
#   tf-emit.sh --next-attempt REQ-UI-004        # prints an integer on stdout
#   tf-emit.sh --where                          # prints the resolved docs/metrics dir
#
# STREAMS: runs | gates | sessions | commits   (anything else is dropped)
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

# --- append path ----------------------------------------------------------
STREAM="$1"
case "$STREAM" in
  runs|gates|sessions|commits) ;;
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

# harness — DETECTED, never taken on trust. The task markdown is shared by both
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
    if tf in ("claude-code", "opencode"):
        return tf
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
                        _sum_claude_transcript(sub, t0, t1, tot, models)
                    except Exception:
                        pass
    except Exception:
        return None
    if tot["in"] + tot["out"] == 0:
        return None
    return {"tot": tot, "models": models, "cost": None, "scope": scope}

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
            m = (d.get("providerID", "") + "/" if d.get("providerID") else "") + (d.get("modelID") or "")
            if m:
                models[m] = models.get(m, 0) + o
        db.close()
    except Exception:
        return None
    if tot["in"] + tot["out"] == 0:
        return None
    return {"tot": tot, "models": models, "cost": round(cost, 6), "scope": "tree"}

def enrich_run(rec):
    if stream not in ("runs", "gates"):
        return rec
    try:
        cmd = rec.get("cmd")
        if ROUTING["enabled"] and cmd and "tier" not in rec:
            tier = ROUTING["phases"].get(cmd)
            if tier and tier != "inherit":
                rec["tier"] = tier
                key = {"claude-code": "claude", "opencode": "opencode"}.get(HARNESS)
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
                rec["tokens_in"] = win["tot"]["in"]
                rec["tokens_out"] = win["tot"]["out"]
                rec["tokens_cache_read"] = win["tot"]["cr"]
                rec["tokens_cache_write"] = win["tot"]["cw"]
                rec["cost_usd"] = win["cost"]
                rec["tokens_scope"] = win["scope"]
                if rec.get("tier_model") and rec.get("model"):
                    rec["routed"] = rec["model"] == rec["tier_model"]
            else:
                rec["tokens_scope"] = "none"
    except Exception as e:
        warn("run enrichment failed (%s) — record kept unenriched" % e)
    return rec

# --- append --------------------------------------------------------------
# newline="\n" is NOT optional. Python's text mode translates "\n" to the
# platform separator, so on native Windows every append would land as CRLF —
# mixing line endings inside an append-only log, and tripping Git's
# "this file uses LF but will be checked out as CRLF" warning on a stream the
# .gitattributes block pins to LF. These files are LF on every platform.
lines = []
for rec in records:
    line = json.dumps(enrich_run(enrich(rec)), separators=(",", ":"), ensure_ascii=False)
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

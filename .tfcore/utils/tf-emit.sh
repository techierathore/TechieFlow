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

try:
    rec = json.loads(raw)
except Exception as e:
    warn("stdin is not valid JSON (%s) — event dropped" % e)
    raise SystemExit(0)

if not isinstance(rec, dict):
    warn("record is not a JSON object — event dropped")
    raise SystemExit(0)

# --- injected fields -----------------------------------------------------
rec.setdefault("v", 1)
rec.setdefault(
    "ts",
    datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
)

# project_type from core-config.yaml : metrics.project_type
#   metrics:
#     project_type: app
if "project_type" not in rec:
    ptype = None
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
            ptype = m.group(1)
    except Exception:
        ptype = None
    if ptype:
        rec["project_type"] = ptype
    else:
        # Default, but NEVER silently — the report labels these unclassified.
        rec["project_type"] = "app"
        rec["project_type_inferred"] = True

# harness — DETECTED, never taken on trust. The task markdown is shared by both
# harnesses, so an agent copying a template literal would stamp whichever harness
# the example happened to name. Detection order: harness env vars, then the parent
# process chain (OpenCode sets no OPENCODE_* vars, so the process name is the only
# honest signal). Undeterminable -> null: a wrong label silently corrupts any
# per-harness comparison, a missing one is merely missing.
if "harness" not in rec:
    def _detect_harness():
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
        rec["harness"] = _detect_harness()
    except Exception:
        rec["harness"] = None

# app name — inferred from the one checklist, else the repo directory name
if "app" not in rec:
    app = None
    try:
        hits = glob.glob(os.path.join(root, "docs", "*-Checklist.md"))
        if len(hits) == 1:
            app = os.path.basename(hits[0])[: -len("-Checklist.md")]
    except Exception:
        app = None
    rec["app"] = app or os.path.basename(os.path.abspath(root))

# --- append --------------------------------------------------------------
try:
    os.makedirs(met_dir, exist_ok=True)
    line = json.dumps(rec, separators=(",", ":"), ensure_ascii=False)
    if "\n" in line or "\r" in line:
        warn("record serialised with a newline — event dropped")
        raise SystemExit(0)
    with open(os.path.join(met_dir, stream + ".jsonl"), "a", encoding="utf-8") as fh:
        fh.write(line + "\n")
except SystemExit:
    raise
except Exception as e:
    warn("append failed (%s) — event dropped" % e)
    raise SystemExit(0)
PY
)"
python3 -c "$TF_PROG" "$MET_DIR" "$STREAM" "$ROOT" 2>"$TF_ERR"

exit 0

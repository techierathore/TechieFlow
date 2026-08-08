#!/usr/bin/env bash
# TechieFlow telemetry — SessionEnd hook -> docs/metrics/sessions.jsonl
#
# Wired in .claude/settings.json → hooks.SessionEnd (no matcher — SessionEnd has
# no tool to match on). The event name was verified against the installed Claude
# Code version (2.1.226) rather than assumed; see DECISIONS.md.
#
# Reads the hook payload on stdin: {"session_id","transcript_path","cwd",
# "hook_event_name","reason"}. Locates the transcript, sums token usage, emits ONE
# session record through tf-emit.sh.
#
# SILENT ON ANY FAILURE — exits 0 unconditionally, prints nothing. Telemetry has
# no veto: a SessionEnd hook that errors would surface noise at the exact moment
# the owner is closing a session. Same fail-open posture as guard-status.sh /
# guard-verify.sh. TF_METRICS_DEBUG=1 to see why an event was dropped.
#
# PRIVACY: reads the transcript ONLY for usage counters, model id, and timestamps.
# No message content, no prompt text, no tool input is ever read out or stored.

INPUT="$(cat 2>/dev/null)"
[[ -n "$INPUT" ]] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

TF_ERR=/dev/null
[[ -n "${TF_METRICS_DEBUG:-}" ]] && TF_ERR=/dev/stderr

PROG="$(cat <<'PY'
import json, os, sys

def bail(msg):
    if os.environ.get("TF_METRICS_DEBUG"):
        sys.stderr.write("metrics-session: %s\n" % msg)
    raise SystemExit(0)

try:
    payload = json.loads(sys.stdin.read())
except Exception as e:
    bail("payload is not JSON (%s)" % e)

root = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ""
if not root or not os.path.isdir(root):
    bail("no usable cwd in payload")

# Only emit into a repo the framework has actually set up — the scaffold/update
# scripts create docs/metrics/. Without it, a session in an unrelated directory
# would litter.
met = os.path.join(root, "docs", "metrics")
if not os.path.isdir(met):
    bail("no docs/metrics in %s — framework refresh has not run here" % root)

tpath = payload.get("transcript_path") or ""
if not tpath or not os.path.isfile(tpath):
    bail("transcript not found at %r" % tpath)

model = None
inp = out = cread = ccreate = 0
first = last = None
try:
    with open(tpath, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            ts = r.get("timestamp")
            if ts:
                if first is None:
                    first = ts
                last = ts
            if r.get("type") != "assistant":
                continue
            m = r.get("message") or {}
            if m.get("model"):
                model = m["model"]
            u = m.get("usage") or {}
            inp     += u.get("input_tokens") or 0
            out     += u.get("output_tokens") or 0
            cread   += u.get("cache_read_input_tokens") or 0
            ccreate += u.get("cache_creation_input_tokens") or 0
except Exception as e:
    bail("could not read transcript (%s)" % e)

def secs(a, b):
    try:
        import datetime
        f = lambda s: datetime.datetime.strptime(s.replace("Z", "+0000")[:19] + "+0000",
                                                 "%Y-%m-%dT%H:%M:%S%z")
        return max(0, int((f(b) - f(a)).total_seconds()))
    except Exception:
        return None

rec = {
    "kind": "session",
    "session_id": payload.get("session_id"),
    "harness": "claude-code",
    "model": model,
    "duration_s": secs(first, last) if (first and last) else None,
    "input_tokens": inp,
    "output_tokens": out,
    "cache_read_tokens": cread,
    "cache_creation_tokens": ccreate,
    # NEVER estimated from a rate card — the transcript carries no cost. SCHEMA.md §4.
    "cost_usd": None,
}
if last:
    rec["ts"] = last[:19] + "Z"

sys.stdout.write(json.dumps(rec, separators=(",", ":")))
sys.stdout.write("\n")
sys.stdout.write(root)
sys.stdout.write("\n")
PY
)"

OUT="$(printf '%s' "$INPUT" | python3 -c "$PROG" 2>"$TF_ERR")" || exit 0
[[ -n "$OUT" ]] || exit 0

REC="$(printf '%s' "$OUT" | sed -n '1p')"
ROOT="$(printf '%s' "$OUT" | sed -n '2p')"
[[ -n "$REC" && -n "$ROOT" ]] || exit 0

EMIT="$ROOT/.tfcore/utils/tf-emit.sh"
[[ -f "$EMIT" ]] || exit 0
printf '%s' "$REC" | TF_METRICS_ROOT="$ROOT" bash "$EMIT" sessions >/dev/null 2>"$TF_ERR"

exit 0

#!/usr/bin/env bash
# TechieFlow hook — records the Claude Code session pointer so telemetry can
# attribute tokens to a run (docs/Telemetry-Hooks.md §2; DECISIONS.md 2026-08-20).
#
# Wired in .claude/settings.json → hooks.SessionStart + hooks.UserPromptSubmit.
# Payload carries {session_id, transcript_path, cwd, hook_event_name, model?}.
# Writes .tfcore/.session/claude-code.json = {session_id, transcript_path,
# model?, ts} (gitignored; last-writer-wins is fine for a single-owner repo).
# tf-emit.sh reads it to compute a per-run token window over the transcript.
#
# HARD RULE — NO VETO. Exits 0 unconditionally; on any failure the pointer is
# simply not refreshed and the run record degrades to tokens_scope:"none".
# The OpenCode equivalent is written by .opencode/plugin/techieflow.js.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

TF_HOOK_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null
import json, os, datetime

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    raise SystemExit(0)

root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or ""
if not root or not os.path.isdir(os.path.join(root, ".tfcore")):
    raise SystemExit(0)

sid = data.get("session_id")
tpath = data.get("transcript_path")
if not sid or not tpath:
    raise SystemExit(0)

rec = {
    "session_id": sid,
    "transcript_path": tpath,
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
if data.get("model"):
    rec["model"] = data["model"]

d = os.path.join(root, ".tfcore", ".session")
try:
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "claude-code.json"), "w") as fh:
        json.dump(rec, fh)
        fh.write("\n")
except Exception:
    pass
PY
exit 0

#!/usr/bin/env bash
# TechieFlow PreToolUse hook — in YOLO mode a build, test or app run stays in the FOREGROUND.
#
# Why a hook (owner, 2026-09-06; FR-46): twice in one build (MISS-TechieFlow-20260905-23 and
# MISS-TechieFlow-20260906-05) the agent started the build as a background job and ended its
# turn "waiting for the build". The turn ending kills the job; the supervisor only re-prompts;
# three cycles were lost that way. A rule ignored twice becomes a hook, not a third paragraph.
#
# What it refuses, only while YOLO is on (TF_YOLO=1, the yolo.json flag, or a harness in
# bypass / --auto mode):
#   - a Bash call with run_in_background true whose command builds, tests, runs or publishes:
#     tf-build.sh, dotnet build|test|run|publish|watch, msbuild, npm|pnpm|yarn build|test|start,
#     also through winrun / cmd.exe / powershell.exe
#   - the same commands backgrounded inside the command text: nohup, setsid, disown, or a
#     trailing / inline `&` (not `&&`)
# Everything else passes. Outside YOLO nothing changes (the owner may background what they like).
#
# Wired in .claude/settings.json → hooks.PreToolUse (matcher "Bash"); OpenCode via
# .opencode/plugin/techieflow.js. Exit 2 + stderr = block the call and tell the agent why.
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0
ROOT="${CLAUDE_PROJECT_DIR:-${TF_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"

yolo=0
if [[ "${TF_YOLO:-0}" == "1" ]]; then yolo=1
elif [[ -f "$ROOT/.tfcore/utils/tf-yolo.sh" ]] && CLAUDE_PROJECT_DIR="$ROOT" bash "$ROOT/.tfcore/utils/tf-yolo.sh" is-on >/dev/null 2>&1; then yolo=1
fi

TF_HOOK_INPUT="$INPUT" TF_YOLO_ON="$yolo" python3 - <<'PY'
import json, os, re, sys

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)
ti = data.get("tool_input") or {}
cmd = ti.get("command")
if not isinstance(cmd, str) or not cmd.strip():
    sys.exit(0)

yolo = os.environ.get("TF_YOLO_ON") == "1" or str(data.get("permission_mode", "")) in ("bypassPermissions", "auto")
if not yolo:
    sys.exit(0)

BUILD = (r"\btf-build\.sh\b"
         r"|\bdotnet\s+(build|test|run|publish|watch)\b"
         r"|\bmsbuild\b"
         r"|\b(npm|pnpm|yarn)\s+(run\s+)?(build|test|start|dev)\b"
         # the verify tooling (Sitting 4c, MISS-TechieFlow-20260906-22): a backgrounded browser
         # test run ended a verify turn "waiting for the tests" on 2026-09-06
         r"|\b(npx\s+)?playwright\s+test\b"
         r"|\btf-verify-(tests|screens|boot|env)\.sh\b"
         r"|\btf-(assets|mockup-parity|perf)\.sh\b"
         r"|\bpytest\b")
low = cmd.lower()
if not re.search(BUILD, low):
    sys.exit(0)

bg_flag = bool(ti.get("run_in_background"))
# `&` that is not `&&` and not inside `2>&1` / `>&2`
inline_bg = bool(re.search(r"(?<![&>\d])&(?![&\d])", low)) or bool(re.search(r"\b(nohup|setsid|disown)\b", low))
if not (bg_flag or inline_bg):
    sys.exit(0)

how = "run_in_background" if bg_flag else "nohup / setsid / a trailing &"
print("BLOCKED by TechieFlow policy: in YOLO mode a build, test or app run is NEVER started in "
      f"the background ({how} here). Ending the turn to wait for it kills the job, and nobody "
      "wakes you; three build cycles were lost that way on 2026-09-06. Run it in the "
      "foreground and wait: bash .tfcore/utils/tf-build.sh [build|test], npx playwright test, or the "
      "tf-verify-*.sh scripts (a timeout of ten minutes is fine), then act on the result line. Owner rule 2026-09-06 (FR-46).",
      file=sys.stderr)
sys.exit(2)
PY
exit $?

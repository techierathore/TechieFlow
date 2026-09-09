#!/usr/bin/env bash
# TechieFlow PreToolUse hook — the telemetry streams are written ONLY by tf-emit.sh.
#
# docs/metrics/*.jsonl are append-only histories (SCHEMA.md §10, _metrics-emit-gate.md).
# This hook refuses every other way of writing them:
#   - Write / Edit / MultiEdit whose file_path is a docs/metrics/*.jsonl file
#   - a shell command that writes one: redirection (> >>), tee, cp/mv/install onto
#     it, sed -i / perl -i, a python/node one-liner naming it, truncate/dd
# Reading them is fine. `bash .tfcore/utils/tf-emit.sh <stream>` never names the
# file on the command line, so it passes; so do tf-metrics.sh --report/--rollup.
#
# Wired in .claude/settings.json -> hooks.PreToolUse (matcher "Write|Edit|MultiEdit"
# AND matcher "Bash"); OpenCode via .opencode/plugin/techieflow.js.
# Exit 2 + stderr = block the call and feed the message back to the agent.
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

TF_HOOK_INPUT="$INPUT" python3 - <<'PY'
import json, os, re, sys

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

ti = data.get("tool_input") or {}
STREAM = r"docs/metrics/[\w.-]+\.jsonl"
# What makes a python/node command a WRITE rather than a read: an explicit write mode,
# something that emits, or a move onto the path. A read names none of these.
WRITEY = (r"(?:['\"][wax]b?\+?['\"]|\.write\b|\.writelines\b|json\.dump\b|"
          r"\btruncate\b|\bos\.rename\b|\bos\.replace\b|\bshutil\.(?:copy|move)\b|"
          r"createWriteStream|writeFileSync|appendFileSync)")

MSG = ("BLOCKED by TechieFlow policy: docs/metrics/*.jsonl are append-only telemetry "
       "streams written only through bash .tfcore/utils/tf-emit.sh <stream> (stdin JSON). "
       "Never Write, Edit, redirect or copy onto them. A wrong record is corrected by a "
       "new record (miss-fix, miss-amend, a later gate), never by an edit.")

fp = ti.get("file_path") or ti.get("filePath")
if isinstance(fp, str) and re.search(STREAM + r"$", fp.replace("\\", "/"), re.I):
    print(MSG, file=sys.stderr)
    sys.exit(2)

cmd = ti.get("command")
if isinstance(cmd, str) and re.search(STREAM, cmd, re.I):
    if re.search(
        r"(>>?\s*[\"']?[^\s|;&]*" + STREAM + r")"
        r"|(\btee\b[^|;&]*" + STREAM + r")"
        r"|(\b(cp|mv|install)\b[^|;&]*" + STREAM + r")"
        r"|(\b(sed|perl)\b[^|;&]*\s-[a-zA-Z]*i[a-zA-Z]*\b[^|;&]*" + STREAM + r")"
        # A python/node command NAMING a stream used to be blocked outright, which also
        # refused every READ -- and this file's own header says reading is fine. Checking
        # a stream with a one-liner is a normal, frequent thing to do, and a guard that
        # blocks it teaches people to route around the guard. So the clause now needs a
        # write in the command as well as the path. MISS-TechieFlow-20260909-03.
        r"|(\b(python3?|node)\b[^|;&]*" + STREAM + r"[^|;&]*" + WRITEY + r")"
        r"|(\b(python3?|node)\b[^|;&]*" + WRITEY + r"[^|;&]*" + STREAM + r")"
        r"|(\b(truncate|dd)\b[^|;&]*" + STREAM + r")",
        cmd, re.I,
    ):
        print(MSG, file=sys.stderr)
        sys.exit(2)

sys.exit(0)
PY
exit $?

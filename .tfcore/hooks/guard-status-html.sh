#!/usr/bin/env bash
# TechieFlow Stop hook — refuses to end a turn while the status gate is incomplete.
#
# The gate (_status-update-gate.md) is six steps an agent can forget. This hook
# checks the RESULT of each step, so a forgotten step cannot end the turn. It
# prints one line per outstanding item, each naming the one command to run.
#
#   1. PROJECT-STATUS.html missing or older than PROJECT-STATUS.md
#        -> bash .tfcore/utils/tf-render-html.sh PROJECT-STATUS.md
#   Only when PROJECT-STATUS.md was written in this session (newer than the
#   session pointer .tfcore/.session/<harness>.json):
#   2. tf-doc-check.sh FAILs on PROJECT-STATUS.md      -> fix the file, re-run the check
#   3. docs/<App>-BRD.md older than docs/<App>-Checklist.md
#        -> bash .tfcore/utils/tf-brd-status.sh <App>
#   4. no runs.jsonl record after the status write     -> the run record (_metrics-emit-gate.md)
#   Only on the turn that wrote PROJECT-STATUS.md (a command's closing turn):
#   5. tf-owner-text.sh FAILs on the closing message or a free-form document it
#      hands the owner                                  -> rewrite it for the owner
#
# Wired in .claude/settings.json -> hooks.Stop; OpenCode via
# .opencode/plugin/techieflow.js session.idle (a nudge: OpenCode has no blocking
# Stop hook). Exit 2 + stderr = block the stop and feed the message to the agent.
# Honours stop_hook_active so a wedged turn can still end (no loop).
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

TF_HOOK_INPUT="$INPUT" TF_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}" python3 - <<'PY'
import datetime
import glob
import json
import os
import re
import subprocess
import sys

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

if data.get("stop_hook_active"):
    sys.exit(0)

root = os.environ.get("TF_PROJECT_DIR") or os.getcwd()
md = os.path.join(root, "PROJECT-STATUS.md")
html = os.path.join(root, "PROJECT-STATUS.html")
if not os.path.isfile(md):
    sys.exit(0)

problems = []
md_mtime = os.path.getmtime(md)

# 1. HTML present and current
if not os.path.isfile(html):
    problems.append("PROJECT-STATUS.html does not exist. Run: bash .tfcore/utils/tf-render-html.sh PROJECT-STATUS.md")
elif md_mtime > os.path.getmtime(html):
    problems.append("PROJECT-STATUS.html is older than PROJECT-STATUS.md. Run: bash .tfcore/utils/tf-render-html.sh PROJECT-STATUS.md")


def session_start():
    """mtime of the harness's session pointer; None when there is none (checks 2-4 skipped)."""
    d = os.path.join(root, ".tfcore", ".session")
    if any(k.startswith("OPENCODE") for k in os.environ):
        cands = [os.path.join(d, "opencode.json")]
    elif os.environ.get("CLAUDECODE") or any(k.startswith("CLAUDE_CODE") for k in os.environ):
        cands = [os.path.join(d, "claude-code.json")]
    else:
        cands = [os.path.join(d, "claude-code.json"), os.path.join(d, "opencode.json")]
    times = [os.path.getmtime(p) for p in cands if os.path.isfile(p)]
    return max(times) if times else None


start = session_start()
written_this_session = start is not None and md_mtime >= start

if written_this_session:
    # 2. the checker passes on the status file
    try:
        chk = os.path.join(root, ".tfcore", "utils", "tf-doc-check.sh")
        if os.path.isfile(chk):
            out = subprocess.run(["bash", chk, "--quiet", "PROJECT-STATUS.md"], cwd=root,
                                 capture_output=True, text=True, timeout=60).stdout
            fails = [l for l in out.splitlines() if l.startswith("FAIL")]
            if fails:
                problems.append(f"PROJECT-STATUS.md fails the document check ({len(fails)} line(s)). Fix it, then run: bash .tfcore/utils/tf-doc-check.sh PROJECT-STATUS.md")
                problems.extend("  " + l for l in fails[:5])
    except Exception:
        pass

    # 2b. the checker passes on every checklist written this session. Until 2026-09-06 only
    # PROJECT-STATUS was checked here, so a build closed its gate with three Remarks cells over
    # 60 words in the checklist and nothing refused the stop (MISS-TechieFlow-20260906-06).
    try:
        chk = os.path.join(root, ".tfcore", "utils", "tf-doc-check.sh")
        if os.path.isfile(chk):
            for cl in sorted(glob.glob(os.path.join(root, "docs", "*-Checklist.md"))):
                if os.path.getmtime(cl) < start:
                    continue
                rel = os.path.relpath(cl, root)
                out = subprocess.run(["bash", chk, "--quiet", rel], cwd=root,
                                     capture_output=True, text=True, timeout=120).stdout
                fails = [l for l in out.splitlines() if l.startswith("FAIL")]
                if fails:
                    problems.append(f"{rel} fails the document check ({len(fails)} line(s)). Fix the rows, then run: bash .tfcore/utils/tf-doc-check.sh {rel}")
                    problems.extend("  " + l for l in fails[:5])
    except Exception:
        pass

    # 3. the BRD's Development status table is not older than the checklist
    try:
        for cl in glob.glob(os.path.join(root, "docs", "*-Checklist.md")):
            app = os.path.basename(cl)[: -len("-Checklist.md")]
            brd = os.path.join(root, "docs", f"{app}-BRD.md")
            if os.path.isfile(brd) and os.path.getmtime(cl) > os.path.getmtime(brd):
                problems.append(f"docs/{app}-BRD.md is older than docs/{app}-Checklist.md. Run: bash .tfcore/utils/tf-brd-status.sh {app}")
    except Exception:
        pass

    # 4. a run record follows the status write (5 minutes of tolerance for emit-before-write)
    try:
        runs = os.path.join(root, "docs", "metrics", "runs.jsonl")
        last = None
        if os.path.isfile(runs):
            with open(runs, encoding="utf-8", errors="replace") as f:
                for line in f:
                    try:
                        ts = json.loads(line).get("ts")
                    except Exception:
                        continue
                    if ts:
                        last = ts
        last_epoch = None
        if last:
            last_epoch = datetime.datetime.strptime(last[:19], "%Y-%m-%dT%H:%M:%S").replace(
                tzinfo=datetime.timezone.utc).timestamp()
        if last_epoch is None or last_epoch < md_mtime - 300:
            problems.append("PROJECT-STATUS.md was written but no run record follows it in docs/metrics/runs.jsonl. Append the run record: .tfcore/tasks/_metrics-emit-gate.md")
    except Exception:
        pass

    # 5. what the owner reads when a command ends: the closing message, and every free-form
    # document it hands over that this turn wrote, through tf-owner-text.sh. TfLens's hand-off of
    # 2026-09-11 reached the owner in jargon, named upstream problems with no word on what they
    # touch, called two fixed ones open, and gave no prompt (MISS-TechieFlow-20260911-03). Only on
    # the turn that closed a command -- PROJECT-STATUS written after this turn's prompt -- so an
    # ordinary conversation is never held to a hand-off's shape. Claude Code hands the hook the
    # message; the OpenCode plugin passes the same two fields.
    try:
        message = data.get("last_assistant_message") or ""
        turn = data.get("turn_started")
        if turn is None and data.get("transcript_path") and os.path.isfile(data["transcript_path"]):
            with open(data["transcript_path"], encoding="utf-8", errors="replace") as f:
                for line in f:
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    c = (r.get("message") or {}).get("content")
                    prompt = r.get("type") == "user" and not r.get("isMeta") and (
                        isinstance(c, str) or (isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "text" for x in c)))
                    if prompt and r.get("timestamp"):
                        turn = r["timestamp"]
        if isinstance(turn, str):
            turn = datetime.datetime.strptime(turn[:19], "%Y-%m-%dT%H:%M:%S").replace(
                tzinfo=datetime.timezone.utc).timestamp()
        elif isinstance(turn, (int, float)) and turn > 1e12:
            turn = turn / 1000.0
        chk = os.path.join(root, ".tfcore", "utils", "tf-owner-text.sh")
        if message.strip() and turn and md_mtime >= turn - 2 and os.path.isfile(chk):
            handed = []
            for m in set(re.findall(r"(?<![\w/.-])((?:docs/)?[\w.-]+\.md)\b", message)):
                p = os.path.join(root, m if m.startswith("docs/") else os.path.join("docs", m))
                if os.path.isfile(p) and os.path.getmtime(p) >= turn - 2:
                    handed.append(os.path.relpath(p, root))
            res = subprocess.run(["bash", chk, "--root", root, "--final", "--stdin"] + sorted(handed), cwd=root,
                                 input=message, capture_output=True, text=True, timeout=60)
            fails = [l for l in res.stdout.splitlines() if l.startswith("FAIL")]
            if fails:
                problems.append(f"what you are handing the owner is not written for the owner ({len(fails)} line(s)). "
                                "Fix each, then write the closing message again — plain words, every upstream problem "
                                "with what it affects and its prompt, and the next prompt in a code block:")
                problems.extend("  " + l for l in fails[:8])
    except Exception:
        pass

if not problems:
    sys.exit(0)

print("BLOCKED by TechieFlow policy: the status gate is not complete (_status-update-gate.md).", file=sys.stderr)
for p in problems:
    print(" - " + p, file=sys.stderr)
sys.exit(2)
PY
exit $?

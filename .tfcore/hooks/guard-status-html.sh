#!/usr/bin/env bash
# TechieFlow Stop hook — refuses to end a turn while PROJECT-STATUS.html is stale.
#
# _status-update-gate.md §8: "If you edited PROJECT-STATUS.md you re-render
# PROJECT-STATUS.html in the same turn, full stop." The owner reads the .html; a
# markdown-only update leaves the page the human actually looks at stale, which
# defeats the entire purpose of the gate.
#
# The prose rule kept failing silently: on 2026-08-25 the owner was reading a
# PROJECT-STATUS.html rendered 4.5 hours earlier that still listed REQ-FN-062 as
# blocked and repeated three "owner actions" he had already completed. guard-status.sh
# already enforces the SHAPE of the markdown; nothing checked that the sibling HTML
# was current. This closes that gap.
#
# Stop (not PostToolUse) is the right trigger because the rule is about the TURN,
# not the edit — an agent legitimately writes the .md and then renders the .html
# a few tool calls later. This only complains when the turn is actually ending
# with the two files out of sync.
#
# Wired in .claude/settings.json → hooks.Stop; Codex via .codex/hooks.json Stop →
# codex-adapter.py stop; OpenCode via .opencode/plugin/techieflow.js session.idle
# (one-shot nudge — OpenCode has no blocking Stop hook).
# Exit 2 + stderr = block the stop and feed the message back to the agent.
# Honours stop_hook_active so a wedged turn can still terminate (no loop).
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

TF_HOOK_INPUT="$INPUT" TF_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}" python3 - <<'PY'
import json, os, sys

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

# Already re-invoked once for this stop — let the turn end rather than loop.
if data.get("stop_hook_active"):
    sys.exit(0)

root = os.environ.get("TF_PROJECT_DIR") or os.getcwd()
md = os.path.join(root, "PROJECT-STATUS.md")
html = os.path.join(root, "PROJECT-STATUS.html")

if not os.path.isfile(md):
    sys.exit(0)

md_mtime = os.path.getmtime(md)

if not os.path.isfile(html):
    print(
        "BLOCKED by TechieFlow policy: PROJECT-STATUS.md exists but "
        "PROJECT-STATUS.html does not. The owner reads the HTML "
        "(_status-update-gate.md §8) — render it before ending the turn, using "
        ".tfcore/templates/v4custom/html-render-shell.md. Never hand-roll a "
        "different scaffold.",
        file=sys.stderr,
    )
    sys.exit(2)

html_mtime = os.path.getmtime(html)

if md_mtime > html_mtime:
    drift = int(md_mtime - html_mtime)
    if drift >= 3600:
        ago = f"{drift // 3600}h {(drift % 3600) // 60}m"
    elif drift >= 60:
        ago = f"{drift // 60}m"
    else:
        ago = f"{drift}s"
    print(
        "BLOCKED by TechieFlow policy: PROJECT-STATUS.html is STALE — "
        f"PROJECT-STATUS.md is {ago} newer (_status-update-gate.md §8).",
        file=sys.stderr,
    )
    print(
        " - The owner reads the .html. A markdown-only update is an INCOMPLETE "
        "update: it leaves the page the human actually looks at showing the "
        "previous run's reality (closed REQs still open, retracted owner-actions "
        "still listed, the wrong next command).",
        file=sys.stderr,
    )
    print(
        " - Re-render PROJECT-STATUS.html from the markdown NOW, in this turn, "
        "using the shared scaffold in "
        ".tfcore/templates/v4custom/html-render-shell.md (§1 slug rule, §2 CSS, "
        "§3 skeleton, §4 anchors, §7 JS). Keep the existing shell — update the "
        "body sections, the subtitle's current_phase/last-updated line, and add "
        "the new Verification-log row. Sidebar TOC iff >6 H2s.",
        file=sys.stderr,
    )
    print(
        " - Then confirm parity: same H2 set and same slugs in both files, and no "
        "string surviving in the HTML that the markdown no longer says.",
        file=sys.stderr,
    )
    sys.exit(2)

sys.exit(0)
PY
exit $?

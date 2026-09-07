#!/usr/bin/env bash
# TechieFlow PreToolUse hook — a `Verified` cell is written only by an executed verify run.
#
# `Verified` is the verifier's verdict. Since Sitting 4c (2026-09-06) the verify run's own script,
# tf-verify-verdict.sh, writes the cells from the evidence it collected and writes the ledger
# docs/.last-verify.json with every row's verdict. This hook refuses any Write/Edit/MultiEdit of a
# *-Checklist.md that INTRODUCES a `Verified` cell unless a ledger dated today lists that row as
# PASS. Owner decision 2026-09-06: a hand-written Verified the ledger does not list is refused.
# Two older ledger shapes still unlock: {"mode":"reconcile"} written by *refresh-status for a row
# whose Remarks already carry dated evidence, and a same-day ledger without a `rows` map from a
# framework version before this sitting (the row is then checked by date only, as before).
#
# Wired in .claude/settings.json → hooks.PreToolUse (matcher "Write|Edit|MultiEdit") and in the
# OpenCode plugin. Exit 2 + stderr = block the call and feed the message back to the agent.
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

TF_HOOK_INPUT="$INPUT" python3 - <<'PY'
import datetime, json, os, re, sys

try:
    data = json.loads(os.environ.get("TF_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

ti = data.get("tool_input") or {}
path = (ti.get("file_path") or "").replace("\\", "/")
if not path.rsplit("/", 1)[-1].lower().endswith("-checklist.md"):
    sys.exit(0)

CELL = re.compile(r"\|\s*\**Verified\**\s*(?:\([^)|]*\))?\s*\|")
ROW = re.compile(r"^\s*\|\s*`?(REQ-[A-Z]+-\d+)`?\s*\|", re.I)


def verified_ids(text):
    """the row ids whose STATUS cell reads Verified, in a piece of checklist text"""
    out = set()
    for line in text.splitlines():
        m = ROW.match(line)
        if m and CELL.search(line):
            out.add(m.group(1).upper())
    return out


new_pieces, old_pieces = [], []
if isinstance(ti.get("content"), str):
    new_pieces.append(ti["content"])
if isinstance(ti.get("new_string"), str):
    new_pieces.append(ti["new_string"])
if isinstance(ti.get("old_string"), str):
    old_pieces.append(ti["old_string"])
for e in ti.get("edits") or []:
    if isinstance(e, dict):
        if isinstance(e.get("new_string"), str):
            new_pieces.append(e["new_string"])
        if isinstance(e.get("old_string"), str):
            old_pieces.append(e["old_string"])

n_new = sum(len(CELL.findall(p)) for p in new_pieces)
n_old = sum(len(CELL.findall(p)) for p in old_pieces)
if isinstance(ti.get("content"), str):
    # a whole-file write: what is Verified on disk already does not count as new
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            n_old = len(CELL.findall(f.read()))
    except FileNotFoundError:
        n_old = 0
if n_new <= n_old:
    sys.exit(0)  # no NEW Verified cell (a demotion, a move, another edit)

new_ids = set().union(*(verified_ids(p) for p in new_pieces)) if new_pieces else set()
old_ids = set().union(*(verified_ids(p) for p in old_pieces)) if old_pieces else set()
if isinstance(ti.get("content"), str):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            old_ids = verified_ids(f.read())
    except FileNotFoundError:
        old_ids = set()
introduced = new_ids - old_ids

ledger_path = os.path.join(os.path.dirname(path) or ".", ".last-verify.json")
today = datetime.date.today().isoformat()
try:
    with open(ledger_path, "r", encoding="utf-8") as f:
        ledger = json.load(f)
except FileNotFoundError:
    ledger, problem = None, "does not exist"
except Exception:
    ledger, problem = None, "exists but is not valid JSON"

if ledger is not None:
    if str(ledger.get("date", "")).strip() != today:
        problem = f"exists but is dated {ledger.get('date')!r}, not today"
    elif ledger.get("mode") == "reconcile":
        sys.exit(0)  # *refresh-status reconciling a row to dated evidence already in its Remarks
    elif "rows" not in ledger:
        sys.exit(0)  # a same-day ledger from a framework version before Sitting 4c: date unlocks
    else:
        rows = ledger.get("rows") or {}
        not_listed = sorted(i for i in introduced if rows.get(i) != "PASS")
        if not introduced:
            # a Verified cell without a readable row id (a malformed line): refuse, nothing can vouch for it
            not_listed = ["(row id not readable)"]
        if not not_listed:
            sys.exit(0)
        problem = ("lists these rows as " + ", ".join(f"{i}: {rows.get(i, 'absent')}" for i in not_listed)
                   + ", not PASS")

print(
    "BLOCKED by TechieFlow policy: this write INTRODUCES a `Verified` status, "
    f"but the verify ledger {ledger_path} {problem}.",
    file=sys.stderr,
)
print(
    " - `Verified` is written by the verify run's own script from the evidence it collected: "
    "bash .tfcore/utils/tf-verify-verdict.sh <App> --apply, after boot, tests, screens, assets, "
    "parity and perf have run (.tfcore/tasks/verify-phase.md). Writing it by hand is refused.",
    file=sys.stderr,
)
print(
    " - A build, a fix or a smoke reaches at most `Implemented`; chain the verifier by executing "
    "verify-phase.md. *refresh-status may reconcile a row that already carries dated verify evidence "
    'by writing the ledger {"date":"<today>","mode":"reconcile","evidence":"<that date>"} first.',
    file=sys.stderr,
)
sys.exit(2)
PY
exit $?

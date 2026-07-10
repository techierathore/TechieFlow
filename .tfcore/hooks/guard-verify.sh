#!/usr/bin/env bash
# TechieFlow PreToolUse hook — blocks self-attested `Verified` verdicts.
#
# `Verified` is the verifier's verdict, written ONLY by an EXECUTED verify-phase
# run (chained inline by build-phase §6b, or a standalone `*verify`). On
# 2026-07-09 a build orchestrator did its own smoke and wrote `Verified`
# verdicts itself — the prose rule ("chain the verifier") was skipped silently.
# This hook makes the gate MECHANICAL, the same way block-git.sh made the git
# ban mechanical and guard-status.sh made the status shape mechanical.
#
# How it works: verify-phase §6 writes a run ledger `docs/.last-verify.json`
# ({"date","app","scope","booted","gates","evidence"}) immediately before it
# records verdicts — after actually booting the app and running the gates.
# Any Write/Edit/MultiEdit to a `*-Checklist.md` that INTRODUCES a `Verified`
# status cell is blocked unless a same-day ledger sits next to the checklist.
#
# Wired in .claude/settings.json → hooks.PreToolUse (matcher "Write|Edit|MultiEdit").
# Exit 2 + stderr = block the call and feed the message back to the agent.
# Fails OPEN (exit 0) if python3 or parseable JSON is unavailable.

INPUT="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0

# stdin feeds python the SCRIPT (heredoc), so the payload travels via env var.
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

# A `Verified` STATUS CELL: a table cell holding exactly Verified (optional
# bold / trailing date qualifier). Remarks prose like "VERIFIED 2026-07-07"
# or "Needs re-verify" does not match.
CELL = re.compile(r"\|\s*\**Verified\**\s*(?:\([^)|]*\))?\s*\|")

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
if n_new <= n_old:
    sys.exit(0)  # no NEW Verified cell introduced (demotions, moves, other edits)

# Introducing `Verified` — require a same-day run ledger next to the checklist.
ledger_path = os.path.join(os.path.dirname(path), ".last-verify.json")
try:
    with open(ledger_path, "r", encoding="utf-8") as f:
        ledger = json.load(f)
    if str(ledger.get("date", "")).strip() == datetime.date.today().isoformat():
        sys.exit(0)  # fresh ledger — an executed verify-phase (or documented reconcile) unlocked it
    stale = f"exists but is dated {ledger.get('date')!r}, not today"
except FileNotFoundError:
    stale = "does not exist"
except Exception:
    stale = "exists but is not valid JSON"

print(
    "BLOCKED by TechieFlow policy: this write INTRODUCES a `Verified` status, "
    f"but the verify run ledger {ledger_path} {stale}.",
    file=sys.stderr,
)
print(
    " - `Verified` is the VERIFIER'S verdict. It is written only downstream of an "
    "EXECUTED .tfcore/tasks/verify-phase.md run — boot the app, run the scoped "
    "tests, apply the §4a data-render + §4b visual-truth gates, write the run "
    "ledger (verify-phase §6), THEN record verdicts.",
    file=sys.stderr,
)
print(
    " - If you are the build orchestrator after your self-smoke: your ceiling is "
    "`Implemented` (build-phase §6a / _smoke-test-policy). Chain the verifier by "
    "EXECUTING verify-phase inline (build-phase §6b) — summarizing your smoke as "
    "a verdict is self-attestation, the exact failure this hook exists to stop.",
    file=sys.stderr,
)
print(
    " - If you are *refresh-status* reconciling a status column to PRE-EXISTING "
    "dated VERIFIED evidence already in that row's Remarks: write the ledger with "
    '{"date":"<today>","mode":"reconcile","evidence":"<the pre-existing remark '
    'date>"} first (refresh-status §4).',
    file=sys.stderr,
)
print(
    " - Writing the ledger WITHOUT having run verify-phase's steps is falsifying "
    "the audit record.",
    file=sys.stderr,
)
sys.exit(2)
PY
exit $?

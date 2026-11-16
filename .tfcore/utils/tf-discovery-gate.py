#!/usr/bin/env python3
"""tf-discovery-gate.py — the status gate's check that a miss whose finding cost was not measured is said out loud.

    python3 .tfcore/utils/tf-discovery-gate.py --root <project> --since <epoch> < closing-message

Called by .tfcore/hooks/guard-status-html.sh on the turn that closes a command. Prints one line per problem
(nothing when there is none) and never writes anything.

WHY (owner, 14 Nov 2026). The cost of finding a root cause is the window from the moment the agent starts on a
problem (`tf-triage.sh <App> look "<problem>"`) to the moment it logs the miss. In both runs of that day it was
lost: Lekhak's agent logged ten causes together at the end, Chatur's set its marks only from its fourth problem.
A mark set by a script cannot fix that: no script sees when the agent moves from one problem to the next, so an
automatic mark at the first step would measure the first problem and guess the rest, and a guessed window is a
wrong record that looks measured. The one honest place is the end: every miss of the command that closes whose
finding cost reads "not measured" is named in the closing message, so the owner reads which figures are missing,
or the gate refuses to pass.

Which misses: those of the last triage or fix command logged since --since (the session's start): kind miss, not
voided, found in triage-and-fix, fix-issues, triage-issues or log-miss, with no discovery_started. A miss a rule
check found at the close ("found by a rule check") is no search and is left out, and so is one a verify gate found
(its window is the verify's).
"""
import json
import os
import sys

PHASES = ("triage-and-fix", "fix-issues", "triage-issues", "log-miss")


def main(argv):
    root = argv[argv.index("--root") + 1] if "--root" in argv else "."
    since = float(argv[argv.index("--since") + 1]) if "--since" in argv else 0.0
    message = sys.stdin.read() if not sys.stdin.isatty() else ""
    path = os.path.join(root, "docs", "metrics", "misses.jsonl")
    if not os.path.isfile(path):
        return 0
    import datetime
    cut = datetime.datetime.fromtimestamp(since, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if since else ""
    misses, voided = [], set()
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("kind") == "miss-void":
            voided.add(r.get("miss_id"))
        elif r.get("kind") == "miss" and (r.get("ts") or "") >= cut and r.get("found_phase") in PHASES:
            misses.append(r)
    misses = [m for m in misses if m.get("miss_id") not in voided]
    if not misses:
        return 0
    last = max(m.get("found_run_id") or "" for m in misses)          # the command that closes now
    unmeasured = [m for m in misses if (m.get("found_run_id") or "") == last and not m.get("discovery_started")
                  and not (m.get("discovery_why") or "").startswith(("found by a rule check", "found in the same investigation as"))]
    unsaid = [m for m in unmeasured if m.get("miss_id") and m["miss_id"] not in message]
    if not unsaid:
        return 0
    print(f"the finding cost of {len(unsaid)} miss(es) this command logged reads \"not measured\", and the closing message "
          f"does not say so. Name each in it, with why it has no window, so the owner knows which figures are missing:")
    for m in unsaid[:12]:
        print(f"  {m['miss_id']} ({m.get('req_id') or 'no row'}): {(m.get('discovery_why') or 'no look mark was set before it was logged')[:140]}")
    print("  Next time: run bash .tfcore/utils/tf-triage.sh <App> look \"<the problem>\" as you start on each problem, "
          "and log each miss as soon as its cause is found, not all together at the end.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

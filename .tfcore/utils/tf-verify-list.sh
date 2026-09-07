#!/usr/bin/env bash
# tf-verify-list.sh — the working list of a verify run (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-list.sh <App> <scope> [--phase N] [--json-out <file>]
#
# scope: ui · functional · all · a comma list of REQ ids. Prints every row to grade with its
# acceptance line, screen, route, mockup and perf budget, the screens to drive, and the test
# users; writes tests/.artifacts/verify/list.json for the other verify scripts. Skips N/A rows
# only. Writes nothing else. See tf-verify-list.py for the details.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "tf-verify-list: python3 is required" >&2; exit 2; }
exec python3 "$HERE/tf-verify-list.py" "$@"

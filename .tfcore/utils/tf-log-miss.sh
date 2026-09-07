#!/usr/bin/env bash
# tf-log-miss.sh — one miss record from one sentence (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-log-miss.sh <App> --what "<the owner's sentence>" [--req REQ-UI-014 | --new "<title>" --acceptance "<When … on <screen>, then …>"]
#        [--class <miss_class>] [--why <why_missed>] [--artifact <artifact>] [--severity blocker|major|minor]
#        [--found-by owner|production] [--evidence <path>] [--fixed [--fix-run <ISO>]] [--started <ISO>]
#
# Duplicate check, origin lookup, the miss record carrying the sentence, the checklist line (a demotion,
# or a new Not Started row with BRD-pending), a miss-fix instead of a demotion with --fixed, then the run
# record. Never boots, never fixes, never argues. Details: tf-log-miss.py.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "tf-log-miss: python3 is required" >&2; exit 2; }
exec python3 "$HERE/tf-log-miss.py" "$@"

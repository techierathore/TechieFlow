#!/usr/bin/env bash
# tf-brd-status.sh — rewrite the BRD's "Development status" table from the checklist.
#
#   bash .tfcore/utils/tf-brd-status.sh MyApp            # writes the table, re-renders the BRD HTML
#   bash .tfcore/utils/tf-brd-status.sh MyApp --no-render
#
# One row per screen (Screen | Requirements | Verified | Open | Status) with a
# "Snapshot as of <today>" line, computed from docs/MyApp-Checklist.md. Nothing
# else in the BRD is touched. Step 5 of _status-update-gate.md; the Stop hook
# refuses to end a turn while the BRD is older than the checklist.
#
# Thin wrapper over tf-brd-status.py. Python 3 standard library only.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "tf-brd-status: python3 is required (standard library only)." >&2
  exit 2
fi
exec python3 "$SELF_DIR/tf-brd-status.py" "$@"

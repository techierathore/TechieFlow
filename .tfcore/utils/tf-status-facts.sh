#!/usr/bin/env bash
# tf-status-facts.sh — print the facts PROJECT-STATUS.md is written from.
#
#   bash .tfcore/utils/tf-status-facts.sh MyApp "build-phase"
#
# Prints the frontmatter values, the next command in both harness forms, the
# Open requirements section, the Verification log with its new row, and the
# library feedback lines, all copy-ready for the template
# .tfcore/templates/v4custom/app-project-status-tmpl.md. Writes nothing:
# PROJECT-STATUS.md is written with the harness Write tool (guard-status.sh
# refuses a shell write). Step 1 of _status-update-gate.md.
#
# Thin wrapper over tf-status-facts.py. Python 3 standard library only.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "tf-status-facts: python3 is required (standard library only)." >&2
  exit 2
fi
exec python3 "$SELF_DIR/tf-status-facts.py" "$@"

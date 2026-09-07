#!/usr/bin/env bash
# tf-day1-files.sh — the mechanical part of day-1.
#
#   bash .tfcore/utils/tf-day1-files.sh MyApp --size S --kind app          # config entries (stage 1)
#   bash .tfcore/utils/tf-day1-files.sh MyApp --prefix obj                 # .editorconfig, AGENTS.md, CLAUDE.md (stage 2)
#   bash .tfcore/utils/tf-day1-files.sh --archive docs/MyApp-BRD.md ...    # move old copies to docs/OldDocs/
#   bash .tfcore/utils/tf-day1-files.sh MyApp --phase 2                    # Large project: the phase being worked
#
# Writes core-config.yaml keys (customTechnicalDocuments, devLoadAlwaysFiles,
# appSize, appKind, appPhase), writes docs/MyApp-Phases.md from its template on
# --size L when absent, and copies the three scaffold files from their templates
# with {AppName} substituted. Archives an existing AGENTS.md / CLAUDE.md first.
# Never asks a question. Thin wrapper over tf-day1-files.py; Python 3 stdlib only.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "tf-day1-files: python3 is required (standard library only)." >&2
  exit 2
fi
exec python3 "$SELF_DIR/tf-day1-files.py" "$@"

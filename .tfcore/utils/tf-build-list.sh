#!/usr/bin/env bash
# tf-build-list.sh — the mechanical start of a build pass.
#
#   bash .tfcore/utils/tf-build-list.sh MyApp               # mode (FIX / FRESH / NOTHING), clusters, working list
#   bash .tfcore/utils/tf-build-list.sh MyApp --prompts     # plus one ready sub-agent prompt per cluster
#   bash .tfcore/utils/tf-build-list.sh MyApp --phase 2     # a later phase of a Large project
#
# Reads the phase's checklist (appPhase in core-config.yaml unless --phase). Rows FAIL /
# PARTIAL / In Progress / Needs re-verify make it FIX mode over exactly those rows; else every
# open row is FRESH; Blocked rows pass through. Clusters follow the checklist's page sections,
# each with its builder from the prefix (UI -> trblazeui, RAG -> techierag, FN/NFR -> builder).
# Prompts are filled from .tfcore/templates/v4custom/build-subagent-prompt.md.
# Writes nothing. Thin wrapper over tf-build-list.py; Python 3 stdlib only.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "tf-build-list: python3 is required (standard library only)." >&2
  exit 2
fi
exec python3 "$SELF_DIR/tf-build-list.py" "$@"

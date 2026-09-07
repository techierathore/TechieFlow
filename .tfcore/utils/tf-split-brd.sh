#!/usr/bin/env bash
# tf-split-brd.sh — draft docs/<App>-Checklist.md from the BRD ledger.
#
#   bash .tfcore/utils/tf-split-brd.sh MyApp                # write it (refuses if one exists)
#   bash .tfcore/utils/tf-split-brd.sh MyApp --force        # rewrite
#   bash .tfcore/utils/tf-split-brd.sh MyApp --add-missing  # append rows for BRD items with no row (amend-docs)
#   bash .tfcore/utils/tf-split-brd.sh MyApp --phase 2      # a later phase of a Large project (docs/MyApp-P2-BRD.md)
#   bash .tfcore/utils/tf-split-brd.sh MyApp --all-phases   # every phase listed in docs/MyApp-Phases.md
#
# Without --phase the phase is appPhase in core-config.yaml (1 when absent).
# REQ numbers run on across phases; an id is never reused.
#
# One row per BRD item in the template shape, acceptance lines copied verbatim,
# class guessed (UI / FN / RAG / NFR) for the agent to correct. Then run
# tf-doc-check.sh --app MyApp. Thin wrapper over tf-split-brd.py; Python 3 stdlib only.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "tf-split-brd: python3 is required (standard library only)." >&2
  exit 2
fi
exec python3 "$SELF_DIR/tf-split-brd.py" "$@"

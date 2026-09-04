#!/usr/bin/env bash
# tf-doc-check.sh — check TechieFlow human documents against their template schemas.
#
#   bash .tfcore/utils/tf-doc-check.sh docs/MyApp-BRD.md [more.md ...]
#   bash .tfcore/utils/tf-doc-check.sh --app MyApp            # every document of the app + PROJECT-STATUS.md
#   bash .tfcore/utils/tf-doc-check.sh --app MyApp --warn     # report mode: findings as WARN, exit 0
#   bash .tfcore/utils/tf-doc-check.sh --size Medium docs/MyApp-BRD.md
#
# Each template under .tfcore/templates/v4custom/ opens with a `<!-- tf-schema -->`
# block (required sections in order, budgets per size, row rules). This script
# prints one line per problem — FAIL blocks the phase, WARN does not — and exits
# 0 when nothing FAILs, 1 when something does, 2 when it could not run.
#
# Run by the status gate (_status-update-gate.md) on every human document a
# command wrote, before the HTML render. Readable version of the rules:
# docs/TechieFlow-Document-Schemas.md.
#
# Thin wrapper over tf-doc-check.py, matching the tf-render-html.sh idiom.
# Python 3 standard library only.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "tf-doc-check: python3 is required (standard library only)." >&2
  exit 2
fi

exec python3 "$SELF_DIR/tf-doc-check.py" "$@"

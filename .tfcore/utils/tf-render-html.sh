#!/usr/bin/env bash
# tf-render-html.sh — render framework Markdown docs to the shared HTML shell.
#
#   bash .tfcore/utils/tf-render-html.sh docs/MyApp-BRD.md [more.md ...]
#   bash .tfcore/utils/tf-render-html.sh PROJECT-STATUS.md --quiet
#
# Writes a sibling <file>.html for each input, implementing
# .tfcore/templates/v4custom/html-render-shell.md — which stays the SPEC: the
# CSS (§2), theme script (§3) and JS (§7) are extracted from it at render time,
# so the shell can never drift from its own documentation.
#
# Thin wrapper over tf-render-html.py, matching the tf-emit.sh / tf-perf.sh
# invocation idiom. Python 3 standard library only — no pandoc, no node, no pip.
#
# Exit: 0 rendered · 1 a render failed · 2 refused (checklist / spec missing)
#
# NOTE: checklists are NEVER rendered (html-render-shell §0). Passing a
# *-Checklist.md is refused, not silently skipped.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "tf-render-html: python3 is required (standard library only)." >&2
  exit 1
fi

exec python3 "$SELF_DIR/tf-render-html.py" "$@"

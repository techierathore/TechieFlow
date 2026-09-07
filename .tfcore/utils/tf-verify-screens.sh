#!/usr/bin/env bash
# tf-verify-screens.sh — drive every screen and check render and visual truth (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-screens.sh --list tests/.artifacts/verify/list.json --base http://localhost:5099 \
#        [--login-path /login --user ravi --password '…'] [--cookie 'k=v'] [--storage-state file]
#   bash .tfcore/utils/tf-verify-screens.sh --screen home=/ --screen posts=/posts --base URL   # a smoke: changed screens only
#   bash .tfcore/utils/tf-verify-screens.sh --list … --cdp http://172.18.144.1:9223               # a Blazor Hybrid Windows head
#
# For every screen, at 1280 and 390 px: every control the mockup anchors is present and shows
# something, no header-only table, no blank page, no Blazor or console error (render); nothing
# overlaps, nothing has zero size or sits off-screen, no sideways scroll, a stylesheet is loaded
# (visual). Saves a screenshot per screen and width under tests/.artifacts/verify/screens/ and
# writes tests/.artifacts/verify/screens.json; that JSON is the evidence a smoke names before a
# row is written Implemented, and what the verdict script reads. It decides no row's status.
# Exit 0 every screen OK · 5 a screen failed · 2 the app was unreachable · 4 Playwright missing.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in -h|--help|"") sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:+0}${1:-3}" ;; esac
command -v node >/dev/null 2>&1 || { echo "tf-verify-screens: node is required (bash .tfcore/utils/tf-verify-env.sh)" >&2; exit 4; }
node -e "import('playwright').then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>/dev/null || {
  echo "tf-verify-screens: the 'playwright' package is not resolvable from this folder; run bash .tfcore/utils/tf-verify-env.sh" >&2; exit 4; }
exec node "$HERE/tf-verify-screens.mjs" "$@"

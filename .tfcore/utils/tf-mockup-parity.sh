#!/usr/bin/env bash
# TechieFlow — mockup-parity gate launcher. Feeds verify-phase §4b2.
#
#   bash .tfcore/utils/tf-mockup-parity.sh --base http://localhost:5099 \
#        --screen login=/login --screen harness=/harness --screen export=/export \
#        --cookie 'AuthCookie=<value from your Playwright login>' \
#        --json-out tests/.artifacts/mockup-parity/run.json
#
# WHAT IT ASKS: "does the built screen carry the structure its approved mockup
# draws?" — at the same viewports, comparing STRUCTURE, never pixels. Pixel diffing
# on live data is unusable and would be ignored within a week.
#
# WHY IT EXISTS (TfLens TF-008, 2026-08-29). A checklist reading 145 `Verified` sat
# over a running app with structural drift on 13 of 14 comparable screens — 20
# findings, 15 REQs demoted in one sitting, all found by a human comparing 18
# screenshots by hand. No gate could have caught any of it, because of what the
# gates measure rather than because of a bug in them:
#
#   §4a data-render   asks "does the control show data?" A badge rendered as plain
#                     text HAS text.
#   §4b visual-truth  asks "do controls overlap, clip, or leave the viewport?" A
#                     header wrapped to two rows overlaps nothing. A 71px value
#                     column that splits `2,287,975,139` across three lines, mid
#                     number, overlaps nothing either. A missing icon is nothing to
#                     measure.
#
# Adding acceptance criteria does not help: in every one of those cases the
# acceptance existed and was met. The missing thing was a gate that could fail.
#
# THE SEVEN CLASSES it grades: badge · icon · color · wrap · clip · token ·
# **stroke** (border style — TF-009), plus a document-height assertion (TF-008 §2).
#
# COVERAGE IS PUBLISHED AND A BARE PASS HAS A FLOOR (TF-011). Every screen reports
# `{compared, content_graded, app_controls, mockup_anchors}` and a screen where no
# clause reaching INSIDE a container ever fired is **UNGRADEABLE**, never PASS. That
# closes the failure mode that is both silent and inverted — the less of a screen
# the gate can see, the cleaner its verdict looks — which caused a real false
# statement upstream: "mockup-parity 10 PASS / 2 FAIL / 0 findings" with eight UI
# rows written `Verified` on that basis, while one screen was visibly wrong.
#
# Exit codes: 0 every screen graded and clean · 3 bad arguments · 4 Playwright not
#             installed (run verify-phase §1 first) · 5 at least one screen FAILED
#             · 6 nothing failed but at least one screen was UNGRADEABLE or had no
#               mockup — exit 0 must never be readable as "everything was graded".

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in -h|--help) sed -n '2,42p' "$0"; exit 0 ;; esac

command -v node >/dev/null 2>&1 || {
  echo "tf-mockup-parity: node is required (verify-phase §1 installs the verify environment)." >&2
  exit 4
}

# Playwright is the verify environment's own dependency — verify-phase §1 already
# ensures it before any gate runs. Say which step to run rather than failing bare.
node -e "import('playwright').then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>/dev/null || {
  echo "tf-mockup-parity: the 'playwright' package is not resolvable from this repo." >&2
  echo "  Run verify-phase §1 (npm install -D @playwright/test && npx playwright install chromium)." >&2
  exit 4
}

exec node "$HERE/tf-mockup-parity.mjs" "$@"

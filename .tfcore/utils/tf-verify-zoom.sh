#!/usr/bin/env bash
# tf-verify-zoom.sh — presses the OS zoom keys on a booted Blazor Hybrid head and says what they did
# (coding-standards-dotnet.md §9b; Lekhak, 2026-10-11).
#
#   bash .tfcore/utils/tf-verify-zoom.sh --appium http://localhost:4723 [--leave 3] [--expect-restored 1.3]
#        a Mac Catalyst head booted by tf-verify-boot.sh (its .app and bundle come from boot.json)
#   bash .tfcore/utils/tf-verify-zoom.sh --cdp <the boot url> [--leave 3] [--expect-restored 1.3]
#        a Windows (WebView2) head, or any Chromium web view, over its debugging address
#
# Checks, in order: (Mac) View › Zoom In, Zoom Out and Actual Size are in the menu bar; the level the
# app opened at is printed, then Cmd/Ctrl+0 is actual size; zoom in 3 times reads 130%, zoom out once
# 120%, actual size 100%; (Windows) Ctrl+wheel up reads 110%. The kept level across a restart is two
# runs: the first with --leave 3 (it ends at 130%), then stop and start the head, then the second with
# --expect-restored 1.3. Pictures go to tests/.artifacts/verify/zoom/. The Mac level is measured from
# the window's pictures, because a WKWebView's accessibility tree does not follow its page zoom.
# Exit 0 every check passed · 5 one failed · 2 nothing to drive · 3 usage · 4 Playwright missing (--cdp).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "")        sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 3 ;;
esac
command -v node >/dev/null 2>&1 || { echo "tf-verify-zoom: node is required (bash .tfcore/utils/tf-verify-env.sh)" >&2; exit 4; }
case " $* " in *" --cdp "*)
  node -e "import('playwright').then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>/dev/null || {
    echo "tf-verify-zoom: the 'playwright' package is not resolvable from this folder; run bash .tfcore/utils/tf-verify-env.sh" >&2; exit 4; } ;;
esac
source "$HERE/tf-lock.sh"; tf_take_lock verify-screens   # one check drives the app at a time
node "$HERE/tf-verify-zoom.mjs" "$@"

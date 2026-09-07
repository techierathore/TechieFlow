#!/usr/bin/env bash
# tf-misses-md.sh — rebuild the readable miss list docs/<App>-Misses.md and its HTML from the
# misses stream (Session 5, 2026-09-07; FR-31). tf-emit.sh runs it after every write to that
# stream; run it by hand once on a project whose stream is older than this script.
#
#   bash .tfcore/utils/tf-misses-md.sh [--root <repo>] [--app <App>] [--no-html] [--quiet]
#
# Exit 0 always. Details: tf-misses-md.py.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "tf-misses-md: python3 is required" >&2; exit 0; }
python3 "$HERE/tf-misses-md.py" "$@"
exit 0

#!/usr/bin/env bash
# tf-feedback.sh — the state of every entry in this project's upstream feedback files, and the
# one way to mark an entry closed once its fix has been re-checked here (2026-09-11).
#
#   bash .tfcore/utils/tf-feedback.sh <App>                     every entry: open, fixed upstream, closed
#   bash .tfcore/utils/tf-feedback.sh <App> --waiting           fixed upstream, not yet re-checked here
#   bash .tfcore/utils/tf-feedback.sh <App> --close <ID> "<what you ran and what it showed>"
#
# Details: tf_feedback.py. Writes nothing except the one closing line --close adds.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "tf-feedback: python3 is required" >&2; exit 2; }
exec python3 "$HERE/tf_feedback.py" "$@"

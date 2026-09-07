#!/usr/bin/env bash
# tf-triage.sh — log reported bugs in the checklist and the telemetry (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-triage.sh <App> demote <REQ> "<symptom>" [--kind layout|render-empty|data-logic|rag] [--evidence <path>] [--source owner|production] [--why <why_missed>]
#   bash .tfcore/utils/tf-triage.sh <App> new "<title>" "<When … on <screen>, then …>" [--prefix UI|FN|NFR|RAG] [--section "<screen>"] [--evidence <path>] [--mockup <file>]
#   bash .tfcore/utils/tf-triage.sh <App> note <REQ> "<could not reproduce: what was tried>"
#   bash .tfcore/utils/tf-triage.sh <App> close [--started <ISO>] [--cmd triage-issues|fix-issues]
#
# demote: Needs re-verify with a dated Remark in the reporter's words. new: a Not Started row with its
# acceptance line and BRD-pending. note: a remark, no status change. close: the escaped gate records,
# one miss per row (found by the owner, the symptom as `what`, duplicates collapsed), the run record,
# and a warning plus a miss when code changed during the triage. Details: tf-triage.py.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "tf-triage: python3 is required" >&2; exit 2; }
exec python3 "$HERE/tf-triage.py" "$@"

#!/usr/bin/env bash
# tf-verify-verdict.sh — one verdict per row from a verify run's evidence (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-verdict.sh <App> [--apply] [--dir tests/.artifacts/verify] [--started <ISO>]
#
# Reads list.json, boot.json, tests.json, screens.json, assets.json, parity.json and perf/<REQ>.json
# from the evidence folder, applies the seven checks in order, records the first that fails, writes
# docs/.last-verify.json (the ledger the verify hook reads, with every row's verdict) and verdicts.json,
# and with --apply rewrites the Status, % and Remarks cells of the graded rows in the checklist.
# A row is Verified only when everything that ran passed; a row whose screen was never driven keeps
# its status and says so. Details: tf-verify-verdict.py.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "tf-verify-verdict: python3 is required" >&2; exit 2; }
exec python3 "$HERE/tf-verify-verdict.py" "$@"

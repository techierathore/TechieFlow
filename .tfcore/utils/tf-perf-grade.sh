#!/usr/bin/env bash
# tf-perf-grade.sh — grade a tf-perf.sh measurement against a row's declared budget (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-perf-grade.sh --budget "p95 ttfb <= 500ms @ concurrency 50" \
#        --json tests/.artifacts/verify/perf/REQ-NFR-001.json [--json-out <file>]
#
# Prints PERF-OK, PERF-MARGINAL, PERF-FAIL or PERF-UNMEASURED with the reason. Never invents a budget.
# Exit 0 OK or MARGINAL · 1 FAIL · 2 UNMEASURED · 3 usage. Details: tf-perf-grade.py.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "PERF-UNMEASURED reason=python3 is required"; exit 2; }
exec python3 "$HERE/tf-perf-grade.py" "$@"

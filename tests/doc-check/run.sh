#!/usr/bin/env bash
# Self-test for .tfcore/utils/tf-doc-check.sh (FR-14): a clean Small-app document set
# must pass with no findings; a deliberately broken twin must fail; --warn must exit 0.
#   bash tests/doc-check/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export TF_FIXTURE_DIR="$ROOT/tests/.artifacts/doc-check"
python3 "$HERE/make-fixtures.py" >/dev/null || { echo "could not build fixtures"; exit 2; }
CHK="$ROOT/.tfcore/utils/tf-doc-check.sh"
fail=0
out="$(bash "$CHK" --root "$TF_FIXTURE_DIR/fx-good" --app MyDiary --quiet)"; rc=$?
if [[ $rc -ne 0 || "$out" != *"0 FAIL, 0 WARN"* ]]; then echo "FAIL good set: exit $rc"; echo "$out"; fail=1; else echo "ok   good set passes clean"; fi
out="$(bash "$CHK" --root "$TF_FIXTURE_DIR/fx-bad" --app MyDiary --quiet)"; rc=$?
n="$(echo "$out" | grep -c '^FAIL')"
if [[ $rc -ne 1 || $n -lt 12 ]]; then echo "FAIL bad set: exit $rc, $n FAIL lines"; echo "$out"; fail=1; else echo "ok   bad set fails ($n findings)"; fi
out="$(bash "$CHK" --root "$TF_FIXTURE_DIR/fx-bad" --app MyDiary --quiet --warn)"; rc=$?
if [[ $rc -ne 0 ]]; then echo "FAIL --warn should exit 0, got $rc"; fail=1; else echo "ok   --warn exits 0"; fi
exit $fail

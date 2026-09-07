#!/usr/bin/env bash
# Self-test for .tfcore/utils/tf-doc-check.sh (FR-14): a clean Small-app document set
# must pass with no findings; a deliberately broken twin must fail; --warn must exit 0.
# Since Sitting 4b (2026-09-05) also a Large two-phase set (Schemas §2, §3.11): clean set
# passes, broken twin fails on the phase rules, and the phase-aware scripts (tf-split-brd,
# tf-status-facts, tf-brd-status) run on it for real.
#   bash tests/doc-check/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export TF_FIXTURE_DIR="$ROOT/tests/.artifacts/doc-check"
python3 "$HERE/make-fixtures.py" >/dev/null || { echo "could not build fixtures"; exit 2; }
CHK="$ROOT/.tfcore/utils/tf-doc-check.sh"
UTILS="$ROOT/.tfcore/utils"
fail=0
out="$(bash "$CHK" --root "$TF_FIXTURE_DIR/fx-good" --app MyDiary --quiet)"; rc=$?
if [[ $rc -ne 0 || "$out" != *"0 FAIL, 0 WARN"* ]]; then echo "FAIL good set: exit $rc"; echo "$out"; fail=1; else echo "ok   good set passes clean"; fi
out="$(bash "$CHK" --root "$TF_FIXTURE_DIR/fx-bad" --app MyDiary --quiet)"; rc=$?
n="$(echo "$out" | grep -c '^FAIL')"
if [[ $rc -ne 1 || $n -lt 12 ]]; then echo "FAIL bad set: exit $rc, $n FAIL lines"; echo "$out"; fail=1; else echo "ok   bad set fails ($n findings)"; fi
out="$(bash "$CHK" --root "$TF_FIXTURE_DIR/fx-bad" --app MyDiary --quiet --warn)"; rc=$?
if [[ $rc -ne 0 ]]; then echo "FAIL --warn should exit 0, got $rc"; fail=1; else echo "ok   --warn exits 0"; fi

# --- Large, two phases ---------------------------------------------------------------
L="$TF_FIXTURE_DIR/fx-large"
out="$(bash "$CHK" --root "$L" --app BigApp --quiet)"; rc=$?
if [[ $rc -ne 0 || "$out" != *"0 FAIL, 0 WARN"* ]]; then echo "FAIL large set: exit $rc"; echo "$out"; fail=1; else echo "ok   large set passes clean (two phases)"; fi
out="$(bash "$CHK" --root "$TF_FIXTURE_DIR/fx-large-bad" --app BigApp --quiet)"; rc=$?
n="$(echo "$out" | grep -c '^FAIL')"
want=("in phase 1 and phase 2" "must be planned, building or done" "phase 3 has no BRD" 'needs the header row "Phase | 1 of' "says 1 but the file name says phase 2" "is also in phase 1's BRD" "outside phase 2's range" "REQ-UI-001 is also in phase 1's checklist")
miss=0
for w in "${want[@]}"; do echo "$out" | grep -q -- "$w" || { echo "     missing finding: $w"; miss=1; }; done
if [[ $rc -ne 1 || $miss -ne 0 ]]; then echo "FAIL large bad set: exit $rc, $n FAIL lines"; echo "$out"; fail=1; else echo "ok   large bad set fails on the phase rules ($n findings)"; fi

# the splitter writes phase 2's checklist with numbers running on from phase 1
rm -f "$L/docs/BigApp-P2-Checklist.md"
out="$(cd "$L" && bash "$UTILS/tf-split-brd.sh" BigApp --phase 2 2>&1)"; rc=$?
if [[ $rc -ne 0 || ! -f "$L/docs/BigApp-P2-Checklist.md" ]] || ! grep -q "REQ-UI-002" "$L/docs/BigApp-P2-Checklist.md" || grep -q "REQ-UI-001" "$L/docs/BigApp-P2-Checklist.md" || ! grep -q "| Phase | 2 of 2 |" "$L/docs/BigApp-P2-Checklist.md"; then
  echo "FAIL tf-split-brd --phase 2: exit $rc"; echo "$out"; fail=1
else echo "ok   tf-split-brd --phase 2 writes BigApp-P2-Checklist.md, ids run on (REQ-UI-002)"; fi
# a raw split leaves a TODO acceptance line on every item the BRD gave none (the NFR row here);
# the checker must refuse exactly those and nothing else
out="$(bash "$CHK" --root "$L" --app BigApp --quiet)"; rc=$?
todo="$(grep -c 'TODO' "$L/docs/BigApp-P2-Checklist.md")"
nf="$(echo "$out" | grep -c '^FAIL')"; na="$(echo "$out" | grep -c 'acceptance line does not read')"
if [[ $rc -ne 1 || $nf -ne $todo || $na -ne $nf ]]; then echo "FAIL large set after split: exit $rc, $nf FAIL for $todo TODO"; echo "$out"; fail=1; else echo "ok   after the split the checker refuses only the $todo TODO acceptance line(s)"; fi
# --all-phases rewrites both from the Phases table
out="$(cd "$L" && bash "$UTILS/tf-split-brd.sh" BigApp --all-phases --force 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] || ! grep -q "REQ-UI-001" "$L/docs/BigApp-Checklist.md" || ! grep -q "REQ-UI-002" "$L/docs/BigApp-P2-Checklist.md"; then
  echo "FAIL tf-split-brd --all-phases: exit $rc"; echo "$out"; fail=1
else echo "ok   tf-split-brd --all-phases writes both checklists"; fi
# the facts script reads the phase from core-config (appPhase: 2) and names it
out="$(cd "$L" && bash "$UTILS/tf-status-facts.sh" BigApp "build-phase" 2>&1)"; rc=$?
if [[ $rc -ne 0 || "$out" != *"Phase 2 of 2 (Reports)"* || "$out" != *"docs/BigApp-P2-Checklist.md"* ]]; then echo "FAIL tf-status-facts on phase 2: exit $rc"; echo "$out"; fail=1; else echo "ok   tf-status-facts reads appPhase 2 and names the phase"; fi
out="$(cd "$L" && bash "$UTILS/tf-status-facts.sh" BigApp "build-phase" --phase 1 2>&1)"; rc=$?
if [[ $rc -ne 0 || "$out" != *"Phase 1 of 2 (Core)"* || "$out" != *"docs/BigApp-Checklist.md"* ]]; then echo "FAIL tf-status-facts --phase 1: exit $rc"; echo "$out"; fail=1; else echo "ok   tf-status-facts --phase 1 reads the plain names"; fi
# the BRD status table is written into the phase's BRD
out="$(cd "$L" && bash "$UTILS/tf-brd-status.sh" BigApp --no-render 2>&1)"; rc=$?
if [[ $rc -ne 0 || "$out" != *"docs/BigApp-P2-BRD.md Development status updated"* ]]; then echo "FAIL tf-brd-status on phase 2: exit $rc"; echo "$out"; fail=1; else echo "ok   tf-brd-status writes phase 2's BRD"; fi
# --size L writes the Phases skeleton and --phase sets appPhase (the script reads templates from cwd)
rm -f "$L/docs/BigApp-Phases.md"
mkdir -p "$L/.tfcore/templates" && cp -r "$ROOT/.tfcore/templates/v4custom" "$L/.tfcore/templates/"
out="$(cd "$L" && bash "$UTILS/tf-day1-files.sh" BigApp --size L --phase 1 2>&1)"; rc=$?
if [[ $rc -ne 0 || ! -f "$L/docs/BigApp-Phases.md" ]] || ! grep -q "^appPhase: 1" "$L/.tfcore/core-config.yaml"; then echo "FAIL tf-day1-files --size L --phase 1: exit $rc"; echo "$out"; fail=1; else echo "ok   tf-day1-files --size L writes the Phases skeleton, --phase sets appPhase"; fi
exit $fail

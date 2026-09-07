#!/usr/bin/env bash
# tests/requirements/checks.sh — the checks that prove a framework requirement line, for the
# lines whose Check column described a script in prose that nobody had written (2026-09-07).
#
# One function per requirement: fr_NN. Exit 0 = the line holds, non-zero = it does not.
# tests/requirements/run.sh calls whichever functions exist and records the verdict.
#
# The bar for a function living here: it must prove the WHOLE line, mechanically, without a
# person and without a real project. A line that needs a fixture run or a review is left out
# and stays ungraded, because a check covering half a requirement and reporting it as passed
# is worse than no check at all.
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRATCH="${TMPDIR:-/tmp}/tf-fr-checks.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

_emit_fixture() {   # a throwaway repo the emitter can write into
  local d="$SCRATCH/emitfx-$1"; rm -rf "$d"; mkdir -p "$d/docs/metrics"
  : > "$d/docs/metrics/runs.jsonl"; : > "$d/docs/metrics/misses.jsonl"
  printf '%s' "$d"
}
_hook() {           # _hook <hook.sh> <json payload>  -> the hook's exit status
  printf '%s' "$2" | CLAUDE_PROJECT_DIR="$ROOT" bash "$ROOT/.tfcore/hooks/$1" >/dev/null 2>&1
}

# --- A. Technology neutrality -----------------------------------------------------------
# FR-03: no language, database, UI-library or host name in any persona, task or shared rule.
fr_03() {
  python3 - "$ROOT" <<'PY'
import re, sys, pathlib
# split so this file does not itself trip the database guard on a tool name
names = ["dotnet","blazor","maui","postgres","serilog","xunit","dapper","db"+"up","trblazeui","bluehost"]
pat = re.compile(r'\b(' + "|".join(names) + r')\b', re.I)
root = pathlib.Path(sys.argv[1])
hits = []
for sub in ("agents", "tasks"):
    for f in (root / ".tfcore" / sub).glob("*.md"):
        for line in f.read_text(errors="replace").splitlines():
            if pat.search(line) and "example" not in line.lower():
                hits.append(f"{f.name}: {line.strip()[:70]}")
if hits:
    print("\n".join(hits[:5]), file=sys.stderr)
raise SystemExit(1 if hits else 0)
PY
}

# --- B. Day-1 and documents --------------------------------------------------------------
# FR-16: one checklist per app, markdown only; never a dated qa/verify folder or a -v2 copy.
fr_16() {
  local bad=0
  for pat in "docs/qa" "docs/verify"; do
    [[ -d "$ROOT/$pat" ]] && { echo "$pat exists" >&2; bad=1; }
  done
  # a -v2 document or a rendered checklist, anywhere the framework owns
  while IFS= read -r f; do echo "banned file: $f" >&2; bad=1; done < <(
    find "$ROOT/docs" "$ROOT/.tfcore" -maxdepth 3 \( -name '*-v2.*' -o -name '*-Checklist.html' \) 2>/dev/null)
  return $bad
}

# --- C. Build -----------------------------------------------------------------------------
# FR-19: a write that introduces `Verified` into a checklist is refused without a same-day ledger.
fr_19() {
  local d="$SCRATCH/verifyfx"; rm -rf "$d"; mkdir -p "$d/docs"
  cat > "$d/docs/App-Checklist.md" <<'EOF'
| ID | Requirement | Status | % | Remarks | Details |
|---|---|---|---|---|---|
| REQ-UI-001 | Sign in | Implemented | 75 | — | [d](#d) |
EOF
  # no ledger: a write that introduces Verified must be refused
  local payload
  payload=$(python3 - "$d" <<'PY'
import json, sys, pathlib
d = pathlib.Path(sys.argv[1])
new = (d / "docs/App-Checklist.md").read_text().replace("Implemented", "Verified")
print(json.dumps({"tool_name": "Write",
                  "tool_input": {"file_path": str(d / "docs/App-Checklist.md"), "content": new}}))
PY
)
  if printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$d" bash "$ROOT/.tfcore/hooks/guard-verify.sh" >/dev/null 2>&1; then
    echo "guard-verify allowed a Verified write with no verify ledger" >&2; return 1
  fi
  # with a same-day ledger it must be allowed
  mkdir -p "$d/docs"
  python3 - "$d" <<'PY'
import json, sys, datetime, pathlib
d = pathlib.Path(sys.argv[1])
json.dump({"date": datetime.date.today().isoformat(), "app": "App", "scope": "all",
           "booted": "static", "gates": ["build"], "rows": {"REQ-UI-001": "PASS"}},
          open(d / "docs/.last-verify.json", "w"))
PY
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$d" bash "$ROOT/.tfcore/hooks/guard-verify.sh" >/dev/null 2>&1 \
    || { echo "guard-verify refused a Verified write that HAS a same-day ledger" >&2; return 1; }
  return 0
}

# FR-23: run artefacts live under tests/.artifacts/, never at the repository root.
fr_23() {
  _hook guard-artifacts.sh '{"tool_name":"Bash","tool_input":{"command":"npx playwright test --output test-results-cluster-a"}}' \
    && { echo "guard-artifacts allowed a root-level --output" >&2; return 1; }
  _hook guard-artifacts.sh '{"tool_name":"Bash","tool_input":{"command":"mkdir -p test-results"}}' \
    && { echo "guard-artifacts allowed mkdir of a root artefact dir" >&2; return 1; }
  _hook guard-artifacts.sh '{"tool_name":"Bash","tool_input":{"command":"npx playwright test --output tests/.artifacts/run-a"}}' \
    || { echo "guard-artifacts refused the sanctioned tests/.artifacts/ form" >&2; return 1; }
  return 0
}

# --- F. Telemetry --------------------------------------------------------------------------
# FR-35: every new run record says whether YOLO mode was on.
fr_35() {
  local d; d="$(_emit_fixture yolo)"
  ( cd "$d" && echo '{"kind":"run","app":"Fx","cmd":"devguide","started":"2026-09-07T07:00:00Z"}' \
      | bash "$ROOT/.tfcore/utils/tf-emit.sh" runs >/dev/null 2>&1 )
  python3 - "$d" <<'PY'
import json, sys, pathlib
lines = [l for l in (pathlib.Path(sys.argv[1]) / "docs/metrics/runs.jsonl").read_text().splitlines() if l.strip()]
if not lines: print("no record written", file=sys.stderr); raise SystemExit(1)
r = json.loads(lines[-1])
if "yolo" not in r:
    print("the appended run record carries no `yolo` field", file=sys.stderr); raise SystemExit(1)
PY
}

# FR-36: a review record is refused without a phase from the list, or without a corrections count.
fr_36() {
  local d out; d="$(_emit_fixture review)"
  out=$( cd "$d" && echo '{"kind":"review","phase":"not-a-phase","corrections":2}' \
         | bash "$ROOT/.tfcore/utils/tf-emit.sh" misses 2>&1 )
  grep -qi 'refus' <<<"$out" || { echo "a review with a bogus phase was not refused: $out" >&2; return 1; }
  out=$( cd "$d" && echo '{"kind":"review","phase":"day1-review"}' \
         | bash "$ROOT/.tfcore/utils/tf-emit.sh" misses 2>&1 )
  grep -qi 'refus' <<<"$out" || { echo "a review with no corrections count was not refused: $out" >&2; return 1; }
  return 0
}

# FR-37: framework maintenance is recordable — the schema lists the value and the report accepts it.
fr_37() {
  grep -q 'framework-reset' "$ROOT/.tfcore/telemetry/SCHEMA.md" \
    || { echo "SCHEMA.md does not list framework-reset" >&2; return 1; }
  bash "$ROOT/.tfcore/telemetry/tf-metrics.sh" --report "$ROOT" 2>/dev/null | grep -q 'framework-reset' \
    || { echo "the report does not carry framework-reset" >&2; return 1; }
  return 0
}

# FR-55: a run's `ended` is when the record is written, never a value the agent guessed.
fr_55() {
  local d; d="$(_emit_fixture ended)"
  ( cd "$d" && echo '{"kind":"run","app":"Fx","cmd":"devguide","started":"2026-09-07T07:00:00Z","ended":"2099-01-01T00:00:00Z"}' \
      | bash "$ROOT/.tfcore/utils/tf-emit.sh" runs >/dev/null 2>&1 )
  ( cd "$d" && echo '{"kind":"run","app":"Fx","cmd":"mockups","started":"2026-09-07T07:00:00Z"}' \
      | bash "$ROOT/.tfcore/utils/tf-emit.sh" runs >/dev/null 2>&1 )
  python3 - "$d" <<'PY'
import json, sys, pathlib
rs = [json.loads(l) for l in (pathlib.Path(sys.argv[1]) / "docs/metrics/runs.jsonl").read_text().splitlines() if l.strip()]
lying = [r for r in rs if r.get("cmd") == "devguide"]
missing = [r for r in rs if r.get("cmd") == "mockups"]
if not lying or lying[-1].get("ended", "").startswith("2099"):
    print("an `ended` in the future was stored as given", file=sys.stderr); raise SystemExit(1)
if not missing or not missing[-1].get("ended") or missing[-1].get("duration_s") is None:
    print("a record with no `ended` got neither one nor a duration", file=sys.stderr); raise SystemExit(1)
PY
}

# FR-56: a database write happens only from build-phase or fix-issues, through the migration path.
fr_56() {
  _hook guard-db.sh '{"tool_name":"Bash","tool_input":{"command":"psql -c \"UPDATE users SET a=1\""}}' \
    && { echo "guard-db allowed a direct SQL write" >&2; return 1; }
  _hook guard-db.sh '{"tool_name":"Bash","tool_input":{"command":"psql -c \"SELECT 1\""}}' \
    || { echo "guard-db refused a read" >&2; return 1; }
  return 0
}

# --- I. Distribution ------------------------------------------------------------------------
# FR-50: the release pipeline runs its checks BEFORE it publishes.
fr_50() {
  local wf="$ROOT/.github/workflows/release.yml"
  [[ -f $wf ]] || { echo "no release workflow" >&2; return 1; }
  python3 - "$wf" <<'PY'
import sys
text = open(sys.argv[1]).read()
pub = text.find("npm publish")
if pub < 0:
    print("the workflow never publishes", file=sys.stderr); raise SystemExit(1)
before = text[:pub]
for needed in ("npm run validate", "npm run test:install"):
    if needed not in before:
        print(f"{needed} does not run before npm publish", file=sys.stderr); raise SystemExit(1)
PY
}

# FR-04: the two standing rules of Q11 — logs under the build output folder, and no run litter
# at the repository root.
fr_04() {
  local bad=0
  while IFS= read -r f; do echo "log file at the repository root: $f" >&2; bad=1; done < <(
    find "$ROOT" -maxdepth 1 -name '*.log' 2>/dev/null)
  while IFS= read -r d; do echo "run litter at the repository root: $d" >&2; bad=1; done < <(
    find "$ROOT" -maxdepth 1 -type d \( -name 'test-results*' -o -name 'scripts-*' \
         -o -name 'playwright-report' -o -name 'logs' \) 2>/dev/null)
  return $bad
}

# FR-34: every command emits a run record. Checked statically: a task file that never mentions
# the phase marker, the status gate or the emitter cannot be writing one. That is a floor, not
# a ceiling — it proves the wiring exists, not that a real run wrote the record.
fr_34() {
  local bad=0 b
  for f in "$ROOT"/.tfcore/tasks/*.md; do
    b="$(basename "$f")"
    [[ "$b" == _* ]] && continue
    grep -qE 'tf-phase\.sh|_status-update-gate|tf-emit\.sh|status gate' "$f" \
      || { echo "$b wires no run record" >&2; bad=1; }
  done
  return $bad
}

#!/usr/bin/env bash
# tests/faults/run.sh — one case per fault found by READING the code, not by a project meeting it.
#
# tests/regression/run.sh holds the defects a project reported. It is over the test-file size limit
# (tests/mirror/size-check.py), so it may not grow; cases written from 2026-11-11 on live here.
# The bar is the same: a case must FAIL against the script as it was before the fix.
#
#   bash tests/faults/run.sh                # all
#   bash tests/faults/run.sh marker_age     # one
#
# Exit 0 all held, 1 a case failed. Python 3 standard library only. Never runs git.
set -u
# a case's records go to its own fixture, never this repository's docs/metrics/
unset CLAUDE_PROJECT_DIR TF_METRICS_ROOT TF_PROJECT_DIR TF_YOLO TF_YOLO_TTL_HOURS
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UTILS="${TF_REGRESSION_UTILS:-$ROOT/.tfcore/utils}"
HOOKS="${TF_REGRESSION_HOOKS:-$ROOT/.tfcore/hooks}"
TASKS="$ROOT/.tfcore/tasks"; TPL="$ROOT/.tfcore/templates/v4custom"
source "$ROOT/.tfcore/utils/tf-portable.sh"   # tf_date_from, tf_sed_inplace, tf_timeout: so a stock Mac runs this suite
SCRATCH="$ROOT/tests/.artifacts/faults.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT
export TF_SKIP_SELFCHECK=1
fail=0
only="${1:-}"

ok()   { printf 'ok   %s — %s\n' "$1" "$2"; }
bad()  { printf 'FAIL %s — %s\n' "$1" "$2"; fail=1; }
note() { printf '     %s\n' "$1"; }
aged() { touch -t "$(tf_date_from "$2" +%Y%m%d%H%M.%S)" "$1"; }   # <file> <'-3 days'>: set its age

# --- guard-status.sh refused every python or node command that named the status file, a read included ---
# The hook's own header says "Reading it is fine", and its block message tells the agent to run the
# document check on the file. guard-metrics.sh had the same fault and was fixed on 2026-09-09.
status_read() {
  local rc n=0 cmd
  _hook() { python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1" | bash "$HOOKS/guard-status.sh" >/dev/null 2>&1; }
  while IFS= read -r cmd; do
    _hook "$cmd"; rc=$?
    [[ $rc -eq 0 ]] || { n=$((n+1)); note "refused a read: $cmd"; }
  done <<'EOF'
python3 -c "print(open('PROJECT-STATUS.md').read()[:200])"
python3 .tfcore/utils/tf-doc-check.py PROJECT-STATUS.md
node -e "console.log(require('fs').readFileSync('PROJECT-STATUS.md','utf8').length)"
python3 -c "import re;print(len(re.findall('REQ-', open('PROJECT-STATUS.md', encoding='utf-8').read())))" | tee /tmp/count.txt
EOF
  [[ $n -eq 0 ]] && ok status_read_a "a python or node command that only reads PROJECT-STATUS.md is let through" \
                 || bad status_read_a "the status guard refused $n command(s) that only read the file"
  n=0
  while IFS= read -r cmd; do
    _hook "$cmd"; rc=$?
    [[ $rc -eq 2 ]] || { n=$((n+1)); note "let a write through (exit $rc): $cmd"; }
  done <<'EOF'
python3 -c "open('PROJECT-STATUS.md','w').write('x')"
python3 -c "import pathlib; pathlib.Path('PROJECT-STATUS.md').write_text('x')"
node -e "require('fs').writeFileSync('PROJECT-STATUS.md','x')"
node -e "require('fs').appendFileSync('PROJECT-STATUS.md','x')"
python3 -c "import shutil; shutil.copy('/tmp/s.md','PROJECT-STATUS.md')"
echo done > PROJECT-STATUS.md
perl -pi -e 's/a/b/' PROJECT-STATUS.md
EOF
  [[ $n -eq 0 ]] && ok status_read_b "a shell, python or node command that writes PROJECT-STATUS.md is still refused" \
                 || bad status_read_b "$n write(s) to the status file passed the guard"
}

# --- three readers used a command marker of any age -----------------------------------------------
# tf-phase.sh says a marker older than 24 hours is ignored (a killed session must not keep a grant
# alive). tf-emit.sh, tf-test-users-check.py and tf-register-test-users.mjs read it without looking.
_marker() {  # <dir> <cmd> <started> <age or ''>
  mkdir -p "$1/.tfcore/.session" "$1/docs"
  printf '{"cmd":"%s","app":"Fx","started":"%s"}\n' "$2" "$3" > "$1/.tfcore/.session/phase.json"
  [[ -n "$4" ]] && aged "$1/.tfcore/.session/phase.json" "$4"
  return 0
}
marker_age() {
  local d="$SCRATCH/mk" old="2026-11-01T00:00:00Z" recent out rc
  recent="$(tf_date_from -u '-10 min' +%Y-%m-%dT%H:%M:%SZ)"
  # (a) the run record's start
  _marker "$d/e1" build-phase "$old" '-3 days'
  out="$(cd "$d/e1" && printf '{"kind":"run","app":"Fx","cmd":"build-phase","reqs_touched":[],"reqs_count":0}\n' | bash "$UTILS/tf-emit.sh" runs 2>&1)"
  ! grep -q "$old" "$d/e1/docs/metrics/runs.jsonl" 2>/dev/null && ! grep -q 'started taken from the command marker' <<<"$out" \
    && ok marker_age_a "a run record takes no start time from a marker a killed session left three days ago" \
    || { bad marker_age_a "tf-emit.sh stamped a run with the start of a three-day-old marker"; note "$(tail -1 "$d/e1/docs/metrics/runs.jsonl" 2>/dev/null | cut -c1-200)"; }
  _marker "$d/e2" build-phase "$recent" ''
  out="$(cd "$d/e2" && printf '{"kind":"run","app":"Fx","cmd":"build-phase","reqs_touched":[],"reqs_count":0}\n' | bash "$UTILS/tf-emit.sh" runs 2>&1)"
  grep -q "\"started\": *\"$recent\"" "$d/e2/docs/metrics/runs.jsonl" 2>/dev/null \
    && ok marker_age_b "a marker written ten minutes ago still gives the run record its start" \
    || { bad marker_age_b "a live marker no longer gives the run record its start"; note "${out:0:200}"; }
  # (b) the register script's "a verify is running" refusal
  if command -v node >/dev/null 2>&1; then
    _marker "$d/r1" verify-phase "$old" '-3 days'
    ( cd "$d/r1" && node "$UTILS/tf-register-test-users.mjs" --dry-run >/dev/null 2>&1 ); rc=$?
    [[ $rc -ne 3 ]] && ok marker_age_c "the register script is not refused because of a verify marker three days old (exit $rc)" \
                    || bad marker_age_c "a three-day-old verify marker still refuses the owner's register script"
    _marker "$d/r2" verify-phase "$recent" ''
    ( cd "$d/r2" && node "$UTILS/tf-register-test-users.mjs" --dry-run >/dev/null 2>&1 ); rc=$?
    [[ $rc -eq 3 ]] && ok marker_age_d "inside a verify that is running now, the register script is still refused" \
                    || bad marker_age_d "the register script ran inside a live verify (exit $rc)"
  else printf 'skip marker_age_c, marker_age_d — node is not installed here\n'; fi
  # (c) the build gate's records
  local t="$d/t1"; _marker "$t" build-phase "$old" '-3 days'; mkdir -p "$t/tests/verify"
  printf 'appSize: S\nappKind: app\nappPhase: 1\n' > "$t/.tfcore/core-config.yaml"
  printf '# Fx — Checklist\n' > "$t/docs/Fx-Checklist.md"
  printf '# Fx — Architecture\n\n| Area | Choice |\n|---|---|\n| Q4 Authentication | AppManager at https://appmgr.example (shared) |\n' > "$t/docs/Fx-Architecture.md"
  printf '# Fx — Usage Guide\n\n## Test users\n\n| # | User | Password source | Role | Exists |\n|---|---|---|---|---|\n| 1 | fx-owner@fx.app | settings | Owner | yes |\n\n## Execution guide\n' > "$t/docs/Fx-UsageGuide.md"
  cat > "$t/tests/verify/register.spec.ts" <<'TS'
import { test, expect } from '@playwright/test';
test('REQ-FN-004 register with a valid password creates the account', async ({ page }) => {
  const vEmail = `fx-verify-${Date.now()}@fx.app`;
  await page.goto('/register');
  await page.getByTestId('input-email').fill(vEmail);
  await page.getByTestId('register-submit').click();
});
TS
  out="$(cd "$t" && python3 "$UTILS/tf-test-users-check.py" --app Fx --emit build-phase 2>&1)"
  grep -q '"req_id": *"REQ-FN-004"' "$t/docs/metrics/gates.jsonl" 2>/dev/null && ! grep -q "$old" "$t/docs/metrics/gates.jsonl" \
    && ok marker_age_e "the test-users gate record carries no run id from a three-day-old marker" \
    || { bad marker_age_e "the test-users gate record was tied to a run that ended three days ago, or was not written"; note "$(tail -1 "$t/docs/metrics/gates.jsonl" 2>/dev/null | cut -c1-200) // ${out:0:120}"; }
}

# --- tf-emit.sh typed in 24 hours for "is YOLO on" and ignored TF_YOLO_TTL_HOURS ------------------
# tf-yolo.sh, block-git.sh and the OpenCode plugin read the variable (0 = never expires).
yolo_ttl() {
  local d="$SCRATCH/yolo" out
  _yolo() {  # <name> <flag age> <ttl> -> the "yolo" value the run record got
    mkdir -p "$d/$1/.tfcore/.session" "$d/$1/docs"
    printf '{"on":true,"since":"2026-11-01T00:00:00Z","source":"tfyolo"}\n' > "$d/$1/.tfcore/.session/yolo.json"
    aged "$d/$1/.tfcore/.session/yolo.json" "$2"
    ( cd "$d/$1" && printf '{"kind":"run","app":"Fx","cmd":"build-phase","started":"%s","reqs_touched":[],"reqs_count":0}\n' "$(tf_date_from -u '-5 min' +%Y-%m-%dT%H:%M:%SZ)" \
        | TF_YOLO_TTL_HOURS="$3" bash "$UTILS/tf-emit.sh" runs >/dev/null 2>&1 )
    python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).read().splitlines()[-1]).get("yolo"))' "$d/$1/docs/metrics/runs.jsonl" 2>/dev/null
  }
  out="$(_yolo short '-2 hours' 1)"
  [[ "$out" == "False" ]] && ok yolo_ttl_a "with a one-hour expiry, a flag two hours old does not mark the run as YOLO" \
                          || { bad yolo_ttl_a "tf-emit.sh ignored TF_YOLO_TTL_HOURS=1"; note "yolo: $out"; }
  out="$(_yolo never '-3 days' 0)"
  [[ "$out" == "True" ]] && ok yolo_ttl_b "with expiry switched off (0), a flag three days old still marks the run as YOLO" \
                         || { bad yolo_ttl_b "tf-emit.sh ignored TF_YOLO_TTL_HOURS=0"; note "yolo: $out"; }
}

# --- tf-emit.sh never read TF_PROJECT_DIR ---------------------------------------------------------
# The OpenCode plugin and tf-goal.sh hand the project folder to every command in that variable, and
# tf-harness.sh reads it first. tf-emit.sh walked up from the folder it ran in instead, and stopped at
# the first one holding a docs/ folder.
emit_root() {
  local d="$SCRATCH/root" where; mkdir -p "$d/app/src/docs" "$d/app/docs" "$d/app/.tfcore"
  where="$(cd "$d/app/src" && TF_PROJECT_DIR="$d/app" bash "$UTILS/tf-emit.sh" --where 2>/dev/null)"
  [[ "$where" == "$d/app/docs/metrics" ]] && ok emit_root "run from a sub-folder that has its own docs/, records still go to the project TF_PROJECT_DIR names" \
                                          || { bad emit_root "tf-emit.sh ignored TF_PROJECT_DIR"; note "writes to: $where"; }
}

# --- tf-doc-check.py did not see a checklist row whose id is in backticks --------------------------
# Every other reader of the table does (tf-build-list.py, tf-verify-list.py, tf-status-facts.py).
backtick_row() {
  local fx="$SCRATCH/dc" out
  TF_FIXTURE_DIR="$fx" python3 "$ROOT/tests/doc-check/make-fixtures.py" >/dev/null 2>&1 || { bad backtick_row "could not build the document fixtures"; return; }
  local cl="$fx/fx-good/docs/MyDiary-Checklist.md"
  tf_sed_inplace 's/^| REQ-FN-001 | Search entries | Not Started |/| `REQ-FN-001` | Search entries | Half Done |/' "$cl"
  out="$(bash "$UTILS/tf-doc-check.sh" --root "$fx/fx-good" "$cl" 2>&1)"
  grep -q '^FAIL.*REQ-FN-001.*Half Done' <<<"$out" \
    && ok backtick_row "a row written as | \`REQ-FN-001\` | is read: its wrong status is reported" \
    || { bad backtick_row "the document check skipped a row whose id is in backticks"; note "$(grep -c '^FAIL' <<<"$out") FAIL line(s): $(grep '^FAIL' <<<"$out" | head -2 | cut -c1-160 | tr '\n' ';')"; }
}

# --- an Owner-UAT row went on the builder's working list -------------------------------------------
# tf-status-facts.py treats it as the owner's ("only the owner can close it"); tf-build-list.py had no
# such status, so the row was handed to a builder as not yet built.
_bl_fx() {  # <dir> <core-config appPhase value> <checklist file name>
  mkdir -p "$1/docs" "$1/.tfcore"; printf 'appSize: S\nappKind: app\nappPhase: %s\n' "$2" > "$1/.tfcore/core-config.yaml"
  cat > "$1/docs/$3" <<'MD'
# Fx — Requirements Checklist

## Requirements Status

| ID | Title | Status | % | Remarks | Detail |
|---|---|---|---|---|---|
| REQ-FN-001 | Export | Owner-UAT | 90% | waits for the owner's walkthrough | [view](#d-req-fn-001) |
| REQ-FN-002 | Import | Not Started | 0% | — | [view](#d-req-fn-002) |
| REQ-FN-003 | Print | Verified | 100% | — | [view](#d-req-fn-003) |

## Coverage

- <a id="d-req-fn-001"></a>**REQ-FN-001** — Export
  - Acceptance: When a user clicks Export on Export, then a file downloads.
- <a id="d-req-fn-002"></a>**REQ-FN-002** — Import
  - Acceptance: When a user clicks Import on Import, then the file is read.
- <a id="d-req-fn-003"></a>**REQ-FN-003** — Print
  - Acceptance: When a user clicks Print on Print, then the page prints.
MD
}
owner_uat() {
  local d="$SCRATCH/uat" out; _bl_fx "$d" 1 Fx-Checklist.md
  out="$(cd "$d" && python3 "$UTILS/tf-build-list.py" Fx 2>&1)"
  grep -q '^Mode: FRESH — 1 row(s) to build' <<<"$out" && ! grep -q 'in no category' <<<"$out" && grep -q 'Owner-UAT.*REQ-FN-001' <<<"$out" \
    && ok owner_uat "an Owner-UAT row is not on the builder's list; it is named as the owner's and every row is still counted" \
    || { bad owner_uat "an Owner-UAT row was handed to the builder"; note "$(grep -m1 '^Mode:' <<<"$out" | cut -c1-200)"; }
}

# --- appPhase written in quotes read as phase 1 ----------------------------------------------------
# `appPhase: "2"` is the same YAML value as `appPhase: 2`. tf-theme.mjs and the document check read
# it as 2; seven scripts read 1 and opened the wrong phase's checklist.
quoted_phase() {
  local d="$SCRATCH/qp" out n=0 f; _bl_fx "$d" '"2"' Fx-P2-Checklist.md
  out="$(cd "$d" && python3 "$UTILS/tf-build-list.py" Fx 2>&1)"
  grep -q 'Fx-P2-Checklist.md — phase 2' <<<"$out" \
    && ok quoted_phase_a "appPhase: \"2\" opens the phase 2 checklist in the build list" \
    || { bad quoted_phase_a "the build list read appPhase: \"2\" as phase 1"; note "${out:0:160}"; }
  out="$(cd "$d" && python3 "$UTILS/tf-status-facts.py" Fx build-phase 2>&1)"
  grep -q 'Fx-P2-Checklist.md' <<<"$out" \
    && ok quoted_phase_b "appPhase: \"2\" opens the phase 2 checklist in the status facts" \
    || { bad quoted_phase_b "the status facts read appPhase: \"2\" as phase 1"; note "$(head -2 <<<"$out" | cut -c1-160 | tr '\n' ';')"; }
  for f in tf-brd-status.py tf-build-list.py tf-log-miss.py tf-split-brd.py tf-status-facts.py tf-triage.py tf-status-evidence.sh; do
    grep -E '\^appPhase:' "$UTILS/$f" | grep -qE "\[.?\"'\]\?" || { n=$((n+1)); note "$f reads appPhase without allowing a quote"; }
  done
  [[ $n -eq 0 ]] && ok quoted_phase_c "all seven readers of appPhase accept the value in quotes" \
                 || bad quoted_phase_c "$n reader(s) of appPhase still take a quoted value as phase 1"
}

# --- handoff-phase.md told the model to write what tf-doc-check.py fails ---------------------------
# The task described the usage guide, the status file and the feedback files by hand, and the
# templates had moved on: following the task as written produced FAIL lines at the status gate.
handoff_prose() {
  local t="$TASKS/handoff-phase.md" out n
  # (a) every usage-guide section the task names is a section of the template
  out="$(python3 - "$t" "$TPL/app-usageguide-tmpl.md" <<'PY'
import re, sys
task, tpl = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
declared = {m.strip().lower() for m in re.findall(r"(?m)^section:\s*([^|\n]+)", tpl)}
part = re.search(r"(?ms)^### 1\..*?(?=^### 2\.)", task).group(0)
named = re.findall(r"(?m)^- \*\*([^*:]+)\*\*:", part)
print(len(named), ", ".join(n for n in named if n.strip().lower() not in declared) or "-")
PY
)"
  [[ "${out#* }" == "-" && "${out%% *}" -ge 3 ]] && ok handoff_prose_a "every usage-guide section the hand-off task names is in the template (${out%% *} named)" \
    || { bad handoff_prose_a "the hand-off task names usage-guide sections the document check refuses"; note "not in the template: ${out#* }"; }
  # (b) the next-command instruction asks for the two blocks the check wants
  out="$(grep -n '"Next command to run"' "$t" | head -1)"
  grep -q 'Claude Code' <<<"$out" && grep -q 'OpenCode' <<<"$out" \
    && ok handoff_prose_b "the task asks for the two command blocks, Claude Code then OpenCode" \
    || { bad handoff_prose_b "the task asks for one next-command line; the document check wants two labelled blocks"; note "${out:0:160}"; }
  # (c) every field the check needs in a feedback entry is named, and the Summary it shows passes
  local fx="$SCRATCH/hp"; mkdir -p "$fx/docs"
  printf '# TechieFlow feedback — found while building Fx\n\n| | |\n|---|---|\n| App | Fx |\n| Upstream | TechieFlow |\n| Updated | 2026-11-11 |\n\n## Summary\n\n%s\n\n## Entries\n\n### TF-001 — a thing is wrong\n\nIt is wrong.\n' \
    "$(python3 - "$t" <<'PY'
import re, sys
task = open(sys.argv[1], encoding="utf-8").read()
part = re.search(r"(?ms)^### 4\..*?(?=^### 5\.)", task).group(0)
m = re.search(r"(?ms)^\s*```markdown\n\s*## Summary\n(.*?)^\s*```", part)
print(re.sub(r"(?m)^\s+", "", m.group(1)).strip() if m else "(the task shows no Summary block)")
PY
)" > "$fx/docs/Fx-TechieFlow-Feedback.md"
  out="$(bash "$UTILS/tf-doc-check.sh" --root "$fx" "$fx/docs/Fx-TechieFlow-Feedback.md" 2>&1)"
  n=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    sed -n '/^### 4\./,/^### 5\./p' "$t" | grep -qF "$f" || { n=$((n+1)); note "the task's field list leaves out: $f"; }
  done < <(grep -o 'has no "[^"]*:" line' <<<"$out" | sed 's/has no "//; s/:" line//' | sort -u)
  [[ $n -eq 0 && "$(grep -c 'has no "' <<<"$out")" -ge 8 ]] && ok handoff_prose_c "the task names every field the document check needs in a feedback entry" \
    || bad handoff_prose_c "the task's feedback field list is not the document check's ($n missing)"
  ! grep -q 'Summary must say how many entries are blocking' <<<"$out" \
    && ok handoff_prose_d "the Summary shape the task shows passes the document check" \
    || bad handoff_prose_d "the Summary block the task shows is refused by the document check (it never says what is blocking)"
  # (d) the task starts the command marker like every other command
  n=0
  for f in "$TASKS"/*.md; do
    case "$(basename "$f")" in _*) continue ;; esac
    grep -q 'tf-emit.sh runs' "$f" || continue
    grep -q 'tf-phase.sh start' "$f" || { n=$((n+1)); note "$(basename "$f") writes a run record and never starts the command marker"; }
  done
  [[ $n -eq 0 ]] && ok handoff_prose_e "every task that writes a run record starts the command marker first" \
                 || bad handoff_prose_e "$n task(s) write a run record with no tf-phase.sh start"
}

# --- Sevak TF-025: a library's Select failed the icon clause beside the mockup's native select ----------
# The mockup draws `<select class="input">`; Chromium paints its chevron itself, so the computed style
# carries no icon. TrBlazeUI's SelectTrigger is a role="combobox" button that draws the same chevron as an
# <svg>: "app carries an icon the mockup does not" on Sevak's Support at both widths and themes. A select
# is compared as a select, the way TF-023 compares a checkbox: its icon clause is not applicable, and its
# chevron is no icon of the boxes around it. An icon on an ordinary control is still reported.
_pw_dir() { local c; for c in "${TF_PLAYWRIGHT_DIR:-}" "$ROOT"; do [[ -n "$c" && -d "$c/node_modules/playwright" ]] && { printf '%s' "$c"; return; }; done; }
sv_025() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then printf 'skip sv_025 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'; return; fi
  local d="$SCRATCH/sv025"; mkdir -p "$d/docs/mockups" "$d/site/support"
  local css='<style>body{margin:0;font:14px/20px system-ui;padding:16px;background:#fff;color:#111} .bar{border:1px solid #ccc;border-radius:8px;padding:12px;width:600px} .input{height:36px;width:200px;border:1px solid #999;border-radius:6px;background:#fff;color:#111;padding:0 8px;font:inherit;display:inline-flex;align-items:center;justify-content:space-between}</style>'
  local chev='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"></polyline></svg>'
  local page='<!doctype html><html><head><meta charset="utf-8">%s</head><body><h1>Support</h1>%s</body></html>\n'
  printf "$page" "$css" '<div class="bar" data-testid="support-filters"><select class="input" data-testid="support-status-filter"><option>Open</option></select></div><p><span data-testid="plain">Issues</span></p>' > "$d/docs/mockups/support.html"
  printf "$page" "$css" "<div class=\"bar\" data-testid=\"support-filters\"><button type=\"button\" class=\"input\" role=\"combobox\" aria-expanded=\"false\" data-testid=\"support-status-filter\"><span>Open</span>$chev</button></div><p><span data-testid=\"plain\">Issues $chev</span></p>" > "$d/site/support/index.html"
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-login.mjs" "$UTILS/tf-theme.mjs" $(ls "$UTILS/tf-menus.mjs" 2>/dev/null) "$UTILS/tf-mockup-parity.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & local srv=$!
  sleep 1
  ( cd "$d" && tf_timeout 120 node tf-mockup-parity.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen support=/support/ --widths 1280,390 --json-out "$d/parity.json" >/dev/null 2>&1 )
  kill "$srv" 2>/dev/null
  local par
  par="$(python3 -c "
import json
for s in json.load(open('$d/parity.json'))['screens']:
    for f in s.get('findings', []): print(f.get('width'), f['key'], f['class'], f['detail'][:50])" 2>&1)"
  [[ -f "$d/parity.json" ]] && ! grep -qE ' (support-status-filter|support-filters)( |$)' <<<"$par" \
    && ok sv_025a "a native select beside a library's role=combobox trigger: no icon finding on it or on the box around it" \
    || { bad sv_025a "a select was compared by its chevron: $(tr '\n' '|' <<<"$par" | cut -c1-300)"; }
  grep -q '^1280 plain icon app carries an icon the mockup does not' <<<"$par" && grep -q '^390 plain icon ' <<<"$par" \
    && ok sv_025b "an icon the app adds to an ordinary control is still reported, at both widths" \
    || { bad sv_025b "the icon finding on an ordinary control was lost: $(tr '\n' '|' <<<"$par" | cut -c1-300)"; }
}

# --- the asset check did not read the sign-in from the test settings ------------------------------
# The screen and mockup checks take Verify:Login:Path / User / Password from tests/verify/testsettings.json
# when the command line names no sign-in; the verify task runs tf-assets.sh with --base and --paths only,
# so on an app with a sign-in page the asset check measured the sign-in page for every route.
assets_login() {
  local d="$SCRATCH/al" port srv; mkdir -p "$d/site" "$d/bin" "$d/with/tests/verify" "$d/without"
  printf '<!doctype html><html><head><title>x</title></head><body>ok</body></html>\n' > "$d/site/index.html"
  printf '{"Verify":{"Login":{"Path":"/signin","User":"owner@fx.app","Password":"not-a-real-one"}}}\n' > "$d/with/tests/verify/testsettings.json"
  # a stand-in for node: says playwright is there, records what the browser step was asked, writes no pages
  cat > "$d/bin/node" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-e" ]] && exit 0
echo "$*" >> "$TF_FAKE_NODE_LOG"
while [[ $# -gt 0 ]]; do [[ "$1" == "--json-out" ]] && printf '{"login":{"attempted":true,"ok":true},"pages":{}}' > "$2"; shift; done
SH
  chmod +x "$d/bin/node"
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d/with" && TF_FAKE_NODE_LOG="$d/with.log" PATH="$d/bin:$PATH" bash "$UTILS/tf-assets.sh" --base "http://127.0.0.1:$port" --paths / --json-out "$d/with.json" >/dev/null 2>&1 )
  ( cd "$d/without" && TF_FAKE_NODE_LOG="$d/without.log" PATH="$d/bin:$PATH" bash "$UTILS/tf-assets.sh" --base "http://127.0.0.1:$port" --paths / --json-out "$d/without.json" >/dev/null 2>&1 )
  kill "$srv" 2>/dev/null
  grep -q -- '--login-path /signin' "$d/with.log" 2>/dev/null && ! grep -q 'not-a-real-one' "$d/with.log" \
    && ok assets_login_a "with a sign-in in the test settings the asset check opens the pages signed in, and the password is not put on a command line" \
    || { bad assets_login_a "the asset check ignored the sign-in in tests/verify/testsettings.json"; note "browser step: $(cat "$d/with.log" 2>/dev/null | cut -c1-160)"; }
  [[ ! -s "$d/without.log" && -s "$d/without.json" ]] \
    && ok assets_login_b "with no sign-in anywhere the asset check fetches the pages itself, as before" \
    || { bad assets_login_b "a project with no sign-in was sent through the browser"; note "$(cat "$d/without.log" 2>/dev/null | cut -c1-160)"; }
}

# --- the mockup check on Sevak's screens, 2026-11-12: one fixture per entry, one run each ------------
# _parity <dir> <screen> <route>: the check run on <dir>/docs/mockups/<screen>.html against <dir>/site,
# at 1280 and 390; prints one line per finding: <width> <key> <class> <detail>
_parity() {
  local d="$1" pw port srv; pw="$(_pw_dir)"
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-login.mjs" "$UTILS/tf-theme.mjs" $(ls "$UTILS/tf-menus.mjs" 2>/dev/null) "$UTILS/tf-mockup-parity.mjs" "$d/"
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d" && tf_timeout 120 node tf-mockup-parity.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen "$2=$3" --widths 1280,390 --json-out "$d/parity.json" >/dev/null 2>&1 )
  kill "$srv" 2>/dev/null
  [[ -f "$d/parity.json" ]] || { echo "NO-RESULT"; return; }
  python3 -c "
import json
for s in json.load(open('$d/parity.json'))['screens']:
    for f in s.get('findings', []): print(f.get('width'), f['key'], f['class'], f['detail'][:60])" 2>&1
}
_pages() {   # <dir> <screen> <mockup body> <app body>: the two pages, with one stylesheet
  local css='<style>body{margin:0;font:14px/20px system-ui;padding:16px;background:#fff;color:#111} .bar{border:1px solid #ccc;border-radius:8px;padding:12px;width:600px} .input{height:36px;width:180px;border:1px solid #999;border-radius:6px;background:#fff;color:#111;padding:0 8px;font:inherit;display:inline-flex;align-items:center;gap:6px} .pill{display:inline-block;padding:2px 8px;border-radius:999px;font-size:12px} .blue{background:#dbeafe;color:#1e40af} .green{background:#dcfce7;color:#166534} .amber{background:#fef3c7;color:#92400e} .red{background:#fee2e2;color:#991b1b}</style>'
  local page='<!doctype html><html><head><meta charset="utf-8">%s</head><body><h1>Screen</h1>%s</body></html>\n'
  mkdir -p "$1/docs/mockups" "$1/site/$2"
  printf "$page" "$css" "$3" > "$1/docs/mockups/$2.html"
  printf "$page" "$css" "$4" > "$1/site/$2/index.html"
}
SVG='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"></rect></svg>'

# --- Sevak TF-027: a library's date picker failed the icon clause beside the mockup's native date box -----
# Chromium paints a native <input type="date">'s calendar itself; TrBlazeUI's DatePicker is a button with
# the calendar as an <svg>, inside the anchored span: "app carries an icon the mockup does not", 4 findings
# per box on Event log. The pair's icon clause is not applicable and the picker's svg is no box's icon.
sv_027() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skip sv_027 — playwright is not installed here\n'; return; }
  local d="$SCRATCH/sv027" par
  _pages "$d" events \
    '<div class="bar" data-testid="events-filters"><input class="input" type="date" value="2026-07-10" data-testid="events-filter-from"><input class="input" type="time" value="10:00" data-testid="events-filter-at"></div><p><span data-testid="plain">Events</span></p>' \
    "<div class=\"bar\" data-testid=\"events-filters\"><span data-testid=\"events-filter-from\"><button type=\"button\" class=\"input\" aria-haspopup=\"true\">$SVG<span>July 10, 2026</span></button></span><span data-testid=\"events-filter-at\"><button type=\"button\" class=\"input\">$SVG<span>10:00</span></button></span></div><p><span data-testid=\"plain\">Events $SVG</span></p>"
  par="$(_parity "$d" events /events/)"
  [[ "$par" != NO-RESULT ]] && ! grep -qE ' (events-filter-from|events-filter-at|events-filters)( > [^ ]+)? (icon|missing) ' <<<"$par" \
    && ok sv_027a "a native date or time box beside a library's picker with an svg calendar: no icon finding on it or on the bar around it" \
    || bad sv_027a "a date box was compared by its calendar: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
  grep -q '^1280 plain icon app carries an icon the mockup does not' <<<"$par" && grep -q '^390 plain icon ' <<<"$par" \
    && ok sv_027b "an icon the app adds to an ordinary control is still reported, at both widths" \
    || bad sv_027b "the icon finding on an ordinary control was lost: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
}

# --- Sevak TF-028: icons inside hidden tab panels were counted as icons of the page ---------------------
# App settings keeps its other tab panels mounted and hidden, so a half-filled form survives a tab switch.
# The mockup marks its hidden panels data-tf-state; on the app side every svg under the anchor counted, a
# 0×0 one included: "appset-page: app carries an icon the mockup does not". An icon nobody sees is no
# box's icon, on either side; a visible icon the mockup lacks is still reported.
sv_028() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skip sv_028 — playwright is not installed here\n'; return; }
  local d="$SCRATCH/sv028" par
  _pages "$d" appset \
    '<div class="bar" data-testid="appset-page"><div role="tabpanel">General <span>name</span></div><div role="tabpanel" data-tf-state="tab-branding">Branding</div></div><div class="bar" data-testid="appset-other"><span>Other</span></div>' \
    "<div class=\"bar\" data-testid=\"appset-page\"><div role=\"tabpanel\" data-state=\"active\">General <span>name</span></div><div role=\"tabpanel\" data-state=\"inactive\" hidden>Branding $SVG</div><div role=\"tabpanel\" data-state=\"inactive\" style=\"display:none\">Updates <i class=\"icon-refresh\">r</i></div></div><div class=\"bar\" data-testid=\"appset-other\"><span>Other $SVG</span></div>"
  par="$(_parity "$d" appset /appset/)"
  [[ "$par" != NO-RESULT ]] && ! grep -qE ' appset-page( |$)' <<<"$par" \
    && ok sv_028a "icons inside the app's hidden tab panels (hidden, display:none) are no icons of the page around them" \
    || bad sv_028a "a hidden panel's icons were counted: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
  grep -qE '^1280 appset-other( > [^ ]+)? icon ' <<<"$par" && grep -qE '^390 appset-other( > [^ ]+)? icon ' <<<"$par" \
    && ok sv_028b "a visible icon the mockup does not draw is still reported, at both widths" \
    || bad sv_028b "a visible icon finding was lost: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
}

# --- Sevak TF-029: a sample row's pill was compared by colour when it showed another value ---------------
# The mockup's sample job rows (data-tf-sample) show Running (blue) and Completed (green); after the
# tests the app's rows are real runs that ingested nothing (amber). The pills carry anchors of their own,
# so the rule "inside a sample box the colour is the data's" missed them: "semantic colour differs —
# mockup accent, app warning". Compared only when the pill says what the sample says.
sv_029() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skip sv_029 — playwright is not installed here\n'; return; }
  local d="$SCRATCH/sv029" par
  row() { printf '<div class="bar" data-tf-sample data-testid="conn-job-row-%s"><span>Job %s</span> <span class="pill %s" data-testid="conn-job-status-%s">%s</span></div>' "$1" "$1" "$2" "$1" "$3"; }
  _pages "$d" conn "$(row 1 blue Running)$(row 2 green Completed)$(row 3 red Failed)" \
    "$(row 1 amber 'Nothing ingested')$(row 2 amber 'Nothing ingested')$(row 3 green Failed)"
  par="$(_parity "$d" conn /conn/)"
  [[ "$par" != NO-RESULT ]] && ! grep -qE ' conn-job-status-[12] ' <<<"$par" \
    && ok sv_029a "a pill in a sample row that shows another value than the sample is not compared by colour" \
    || bad sv_029a "a sample pill showing another value was compared: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
  grep -qE '^1280 conn-job-status-3 color semantic colour differs — mockup negative, app positive' <<<"$par" \
    && ok sv_029b "a pill that shows the sample's own value in another colour is still reported" \
    || bad sv_029b "the colour of a pill with the sample's value was not compared: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
}

# --- TfLens TF-057: ending a command run inside another one deleted the outer command's marker -----------
# *triage-and-fix ran *amend-docs inline; `tf-phase.sh end amend-docs` removed phase.json whatever it held,
# and the triage's start, which tf-triage.sh close and the emitter read, was gone. The inner end now gives
# the marker back to the outer command; a command run on its own still ends with no marker.
tf_057() {
  local d="$SCRATCH/tf057" f out
  mkdir -p "$d/.tfcore/utils" "$d/.tfcore/.session"; cp "$UTILS/tf-phase.sh" "$d/.tfcore/utils/"; f="$d/.tfcore/.session/phase.json"
  printf '{"cmd":"triage-and-fix","app":"Fx","started":"2026-11-12T10:00:00Z"}\n' > "$f"
  bash "$d/.tfcore/utils/tf-phase.sh" start amend-docs Fx >/dev/null 2>&1
  grep -q '^{"outer":{"cmd":"triage-and-fix"' "$f" || { bad tf_057a "the fixture's nested start wrote no outer: $(cat "$f")"; return; }
  out="$(bash "$d/.tfcore/utils/tf-phase.sh" end amend-docs Fx 2>&1)"
  [[ "$(cat "$f" 2>/dev/null)" == '{"cmd":"triage-and-fix","app":"Fx","started":"2026-11-12T10:00:00Z"}' ]] \
    && ok tf_057a "ending the inner command gives the marker back to the outer one, its start unchanged" \
    || bad tf_057a "the outer marker was lost ($out): $(cat "$f" 2>/dev/null || echo 'no marker')"
  bash "$d/.tfcore/utils/tf-phase.sh" end triage-and-fix Fx >/dev/null 2>&1
  [[ ! -f "$f" ]] && bash "$d/.tfcore/utils/tf-phase.sh" start fix-issues Fx >/dev/null 2>&1 && bash "$d/.tfcore/utils/tf-phase.sh" end >/dev/null 2>&1 && [[ ! -f "$f" ]] \
    && ok tf_057b "a command run on its own, and the outer one after its inner, still ends with no marker" \
    || bad tf_057b "a lone command's end left a marker: $(cat "$f" 2>/dev/null)"
}

# --- Sevak TF-032: the icons of rows past the 200th anchor were counted as the box's own -------------------
# Assistant's mockup draws sample turns (data-tf-sample, anchor assistant-turn), the answers holding a Speak
# button with an svg. The app's rows of the same anchor, however many, are left out of the box around them;
# the list of anchors inside a box stopped at 200, so after ~95 answers the later Speak icons stayed on the
# box: "assistant-conversation: app carries an icon the mockup does not". A box's own icon still counts.
sv_032() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skip sv_032 — playwright is not installed here\n'; return; }
  local d="$SCRATCH/sv032" par i rows="" spk="<button data-testid=\"assistant-speak\">$SVG Speak</button>"
  for ((i = 0; i < 120; i++)); do rows+="<div data-testid=\"assistant-turn\">q $i</div><div data-testid=\"assistant-turn\">answer $i $spk</div>"; done
  _pages "$d" assistant \
    "<div class=\"bar\" data-testid=\"assistant-conversation\"><div data-testid=\"assistant-turn\" data-tf-sample>today</div><div data-testid=\"assistant-turn\" data-tf-sample>Saturday $spk</div></div><div class=\"bar\" data-testid=\"assistant-side\"><div data-testid=\"assistant-turn\" data-tf-sample>Saturday $spk</div></div>" \
    "<div class=\"bar\" data-testid=\"assistant-conversation\">$rows</div><div class=\"bar\" data-testid=\"assistant-side\"><b>$SVG</b>$rows</div>"
  par="$(_parity "$d" assistant /assistant/)"
  [[ "$par" != NO-RESULT ]] && ! grep -qE ' assistant-conversation( |$)' <<<"$par" \
    && ok sv_032a "the Speak icons of 120 answers repeating the mockup's sample turn are no icons of the conversation box" \
    || bad sv_032a "rows past the sample were counted as the box's icons: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
  grep -qE '^1280 assistant-side icon app carries an icon the mockup does not' <<<"$par" && grep -qE '^390 assistant-side icon ' <<<"$par" \
    && ok sv_032b "an icon the box draws of its own, beside 120 such rows, is still reported at both widths" \
    || bad sv_032b "the box's own extra icon was lost: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
}

# --- Chatur TF-027: a picker's own arrow was counted on the mockup's side only ----------------------------
# The mockup draws a tier picker as a plain button with a chevron svg (button.pick); the app's TrBlazeUI
# Select is a [role=combobox] button with the same chevron, which the check never counts (TF-025). So
# "analyst-tier: mockup carries an icon here; the app does not" on 32 Chatur rows. Everything inside a
# picker's trigger is the picker's own on both sides: the mockup element paired with a select or combobox
# gives up its icons too. A plain button's chevron the app does not draw, and an icon beside the picker
# in the same box, are still reported.
ch_027() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skip ch_027 — playwright is not installed here\n'; return; }
  local d="$SCRATCH/ch027" par chev='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"></polyline></svg>'
  _pages "$d" routing \
    "<div class=\"bar\" data-testid=\"mode-choices\"><div class=\"popwrap\" data-testid=\"analyst-tier\"><button type=\"button\" class=\"input pick\"><span>Tier 3</span>$chev</button></div><div data-testid=\"tester-tier\"><button type=\"button\" class=\"input pick\"><span>Tier 2</span>$chev</button></div></div><div class=\"bar\" data-testid=\"other-box\"><span>Model</span> $SVG <div data-testid=\"plain-pick\"><button type=\"button\" class=\"input\"><span>More</span>$chev</button></div></div>" \
    "<div class=\"bar\" data-testid=\"mode-choices\"><div data-testid=\"analyst-tier\"><button type=\"button\" class=\"input\" role=\"combobox\" aria-expanded=\"false\"><span>Tier 3</span>$chev</button></div><div data-testid=\"tester-tier\"><select class=\"input\"><option>Tier 2</option></select></div></div><div class=\"bar\" data-testid=\"other-box\"><span>Model</span> <div data-testid=\"plain-pick\"><button type=\"button\" class=\"input\"><span>More</span></button></div></div>"
  par="$(_parity "$d" routing /routing/)"
  [[ "$par" != NO-RESULT ]] && ! grep -qE ' (analyst-tier|tester-tier|mode-choices)( > [^ ]+)? (icon|missing) ' <<<"$par" \
    && ok ch_027a "a mockup's plain picker button beside the app's combobox or native select: its arrow counts on neither side, nor on the box around it" \
    || bad ch_027a "a picker's arrow was counted on one side: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
  grep -qE '^1280 plain-pick( > [^ ]+)? icon mockup carries an icon here' <<<"$par" && grep -qE '^1280 other-box icon mockup carries an icon here' <<<"$par" && grep -qE '^390 other-box icon ' <<<"$par" \
    && ok ch_027b "a plain button's chevron the app does not draw, and an icon beside the picker, are still reported" \
    || bad ch_027b "a real icon finding was lost: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
}

# --- Chatur TF-026: the menu walk left the app on another project ---------------------------------------
# Since TF-023 the walk reaches Start through File › Recent projects ▸ and clicks every row of that submenu,
# each of which opens its project; it ended on AlphaApp, and the later screens and their seeds ran there.
# A submenu row the page itself shows outside the menus at the start (the open project's name in the menu
# bar) is the state the walk found, and is chosen again after the rows; Project list is still clicked.
ch_026() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skip ch_026 — playwright is not installed here\n'; return; }
  local d="$SCRATCH/ch026" port srv log out; mkdir -p "$d"
  bash "$ROOT/tests/faults/ch026/make.sh" "$d"
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"
  cp "$UTILS/tf-login.mjs" "$UTILS/tf-theme.mjs" "$UTILS/tf-menus.mjs" "$UTILS/tf-verify-screens.mjs" "$d/"
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 "$d/server.py" "$port" "$d" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d" && tf_timeout 300 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen main=/main/ --screen start=/start/ \
      --widths 1280 --themes light --render-wait 500 --wait 300 --json-out "$d/s.json" --shots-dir "$d/shots" > "$d/s.log" 2>&1 )
  kill "$srv" 2>/dev/null
  log="$(tr '\n' ' ' < "$d/opens.log" 2>/dev/null)"
  out="$(python3 -c "
import json
for c in json.load(open('$d/s.json')).get('menus', {}).get('clicks', []): print(c.get('menu'), '|', c.get('label'), '|', c.get('effect'))" 2>&1)"
  grep -q AlphaApp <<<"$log" && grep -q BetaTool <<<"$log" && [[ "$log" == *"WbA " ]] \
    && ok ch_026a "the walk still opens every recent project, and the last one opened is WbA, the project open at the start" \
    || { bad ch_026a "the menu walk left the app on another project"; note "opens: ${log:-none}"; }
  grep -q 'Recent projects | Project list | navigated' <<<"$out" \
    && ok ch_026b "Project list, the way into Start, is still clicked and graded" \
    || { bad ch_026b "the submenu's way in was not clicked"; note "$(tr '\n' '|' <<<"$out" | cut -c1-300)"; }
}

# --- Chatur TF-028: a run record could not say which provider and model the checks ran on ----------------
# Chatur's browser tests call a real model through tests/verify/test-settings.json's testProvider. The run
# record had `model` (the agent's) only, and an unknown field was refused. checks_provider and checks_model
# now go on the verify's and the fix's run records; the key beside them never does; a project naming no
# provider gets neither field, and a record without them is still taken.
ch_028() {
  local d="$SCRATCH/ch028" t1="2026-11-13T09:00:00Z" r x
  for x in with/v with/f none/v none/f; do x="$d/$x"
    mkdir -p "$x/.tfcore/.session" "$x/docs/metrics" "$x/tests/verify" "$x/tests/.artifacts/verify"; cp -r "$UTILS" "$x/.tfcore/"
    python3 -c "import json,sys; json.dump({'app':'Fx','scope':'REQ-UI-100','build_result':'pass','rows':[{'id':'REQ-UI-100','class':'UI','verdict':'PASS','gate':None,'gates_run':['build','acceptance'],'failure_class':None,'prior_verdict':'Implemented','status':'Verified','emit_gate':True}]}, open(sys.argv[1],'w'))" "$x/tests/.artifacts/verify/verdicts.json"
    if [[ "$x" == */with/* ]]; then printf '{"testUsers":[],"testProvider":{"name":"Anthropic","connector":"anthropic","baseUrl":"https://example.invalid","model":"claude-sonnet-5-5","key":"FAKE-KEY-ch028-do-not-print"}}\n' > "$x/tests/verify/test-settings.json"
    else printf '{"Verify":{"Login":{"Path":"/signin"}}}\n' > "$x/tests/verify/testsettings.json"; fi
    printf '{"cmd":"fix-issues","app":"Fx","started":"%s"}\n' "$t1" > "$x/.tfcore/.session/phase.json"
    if [[ "$x" == */v ]]; then ( cd "$x" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$x" bash .tfcore/utils/tf-verify-emit.sh Fx --started "$t1" >/dev/null 2>&1 )
    else ( cd "$x" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$x" bash .tfcore/utils/tf-fix-close.sh Fx --started "$t1" --reqs REQ-UI-100 --build pass >/dev/null 2>&1 ); fi
  done
  _cm() { cat "$d/$1"/*/docs/metrics/runs.jsonl 2>/dev/null | python3 -c "import json,sys
for l in sys.stdin: j=json.loads(l); print(j.get('cmd'), j.get('checks_provider', '-'), j.get('checks_model', '-'))" 2>&1; }
  r="$(_cm with)"
  grep -q '^verify-phase Anthropic claude-sonnet-5-5$' <<<"$r" && grep -q '^fix-issues Anthropic claude-sonnet-5-5$' <<<"$r" && ! cat "$d"/with/*/docs/metrics/*.jsonl | grep -q FAKE-KEY \
    && ok ch_028a "the verify's and the fix's run records carry checks_provider and checks_model from the test settings, and never the key" \
    || { bad ch_028a "the provider and model of the checks are not on the run records"; note "$(tr '\n' '|' <<<"$r")"; }
  r="$(_cm none)"
  grep -q '^verify-phase - -$' <<<"$r" && grep -q '^fix-issues - -$' <<<"$r" \
    && ok ch_028b "a project that names no provider for its checks gets run records without either field, as before" \
    || { bad ch_028b "a project with no test provider lost its run records or got the fields"; note "$(tr '\n' '|' <<<"$r")"; }
}

# --- TfLens TF-058: no check opened a dropdown, so a list too narrow to read passed every gate ---------------
# TfLens's repository picker (a TrBlazeUI Select) opened a list as narrow as "All repos": every name read
# "techierathore/". The screen check graded the closed trigger. Each [role=combobox] trigger is now opened
# once and its listbox graded: an option cut short is a visual finding. A list whose options fit is not
# reported, and a finding the check already made (a zero-width control) still is.
tf_058() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skip tf_058 — playwright is not installed here\n'; return; }
  local d="$SCRATCH/tf058" port srv out
  mkdir -p "$d/docs/mockups" "$d/site/repos"
  local css='<style>body{margin:0;font:14px/20px system-ui;padding:16px} .pick{position:relative;display:block;margin-bottom:120px} [role=listbox]{position:absolute;top:36px;left:0;background:#fff;border:1px solid #ccc;display:none} [role=listbox].open{display:block} [role=option]{padding:4px 8px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis} .narrow [role=listbox]{width:90px} .wide [role=listbox]{width:320px}</style>'
  local mock='<!doctype html><html><head><meta charset="utf-8"></head><body><h1>Estimates</h1><div data-testid="repo-pick"><button>All repos</button></div><div data-testid="wide-pick"><button>All runs</button></div><span data-testid="zero">z</span></body></html>'
  printf '%s\n' "$mock" > "$d/docs/mockups/repos.html"
  pick() { printf '<div class="pick %s" data-testid="%s"><button role="combobox" aria-controls="%s-list" aria-expanded="false" onclick="tg(this)">All</button><div role="listbox" id="%s-list"><div role="option">All repos</div><div role="option">techierathore/TechieFlow</div><div role="option">techierathore/TfLens</div></div></div>' "$1" "$2" "$2" "$2"; }
  printf '<!doctype html><html><head><meta charset="utf-8">%s</head><body><h1>Estimates</h1>%s%s<span data-testid="zero" style="display:inline-block;width:0;overflow:hidden">z</span><script>function tg(b){var l=document.getElementById(b.getAttribute("aria-controls"));l.classList.toggle("open");b.setAttribute("aria-expanded",l.classList.contains("open"))}document.addEventListener("keydown",function(e){if(e.key==="Escape")document.querySelectorAll("[role=listbox].open").forEach(function(l){l.classList.remove("open")})})</script></body></html>\n' "$css" "$(pick narrow repo-pick)" "$(pick wide wide-pick)" > "$d/site/repos/index.html"
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"
  cp "$UTILS/tf-login.mjs" "$UTILS/tf-theme.mjs" "$UTILS/tf-menus.mjs" "$UTILS/tf-verify-screens.mjs" $(ls "$UTILS/tf-dropdowns.mjs" 2>/dev/null) "$d/"
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d" && tf_timeout 300 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen repos=/repos/ --widths 1280,390 --themes light \
      --render-wait 500 --wait 300 --no-menus --json-out "$d/s.json" --shots-dir "$d/shots" > "$d/s.log" 2>&1 )
  kill "$srv" 2>/dev/null
  out="$(python3 -c "
import json
for s in json.load(open('$d/s.json'))['screens']:
    for w in s['widths']:
        for f in w['findings']: print(w.get('width'), f['check'], f['class'], f['detail'][:90])" 2>&1)"
  grep -qE '^1280 visual clipped the list of "repo-pick" cuts 2 option' <<<"$out" && grep -qE '^390 visual clipped the list of "repo-pick"' <<<"$out" && ! grep -q 'wide-pick' <<<"$out" \
    && ok tf_058a "a dropdown whose list cuts its options short is a visual finding at both widths; a list whose options fit is not" \
    || bad tf_058a "a narrow dropdown list passed the screen check: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  grep -qE '^1280 visual clipped anchored control "zero" has zero width' <<<"$out" \
    && ok tf_058b "a finding the screen check already made (a zero-width control) is still reported beside it" \
    || bad tf_058b "an existing visual finding was lost: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- Sevak 13 Nov (TF-033 to TF-035 in its file): the miss stream's discovery, fix cost and corrections ------
_mfx() {   # <dir>: a project with the scripts, empty streams and a running triage-and-fix started 40 min ago
  mkdir -p "$1/.tfcore/.session" "$1/docs/metrics" "$1/tests/.artifacts/verify"; cp -r "$UTILS" "$1/.tfcore/"
  for s in runs gates sessions commits misses; do : > "$1/docs/metrics/$s.jsonl"; done
  printf '{"cmd":"triage-and-fix","app":"Fx","started":"%s"}\n' "$(tf_date_from -u '-40 min' +%Y-%m-%dT%H:%M:%SZ)" > "$1/.tfcore/.session/phase.json"
}
_lm() { ( cd "$1" && shift && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$PWD" bash .tfcore/utils/tf-log-miss.sh Fx --sort weak-check --found-by owner "$@" 2>&1 ); }
_last() { python3 -c "import json,sys; r=[json.loads(l) for l in open(sys.argv[1]) if '\"kind\":\"miss\"' in l][-1]; print(r.get('discovery_started') or '-', r.get('discovery_why') or '-')" "$1/docs/metrics/misses.jsonl" 2>&1; }

# TF-033: tf-log-miss.sh never read the `tf-triage.sh look` marks, so every miss said "not measured".
sv_033() {
  local d="$SCRATCH/sv033" look r
  _mfx "$d/a"; _mfx "$d/b"
  look="$(tf_date_from -u '-25 min' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"actions":[{"verb":"look","symptom":"the Assistant answer is cut","ts":"%s"}]}\n' "$look" > "$d/a/tests/.artifacts/verify/triage.json"
  _lm "$d/a" --what "The Assistant cuts its answer at 200 words" >/dev/null; r="$(_last "$d/a")"
  [[ "$r" == "$look "* && "$r" != *"found by the owner"* ]] \
    && ok sv_033a "a miss logged after a look mark carries its discovery window from that mark" \
    || bad sv_033a "the look mark was not read: $r"
  _lm "$d/b" --what "The Assistant cuts its answer at 200 words" >/dev/null; r="$(_last "$d/b")"
  _lm "$d/a" --what "The Assistant loses the Speak button" >/dev/null; local r2; r2="$(_last "$d/a")"
  [[ "$r" == "- found by the owner"* && "$r2" == "- found together with MISS-"* ]] \
    && ok sv_033b "with no look mark the miss still says why it has no window; a second miss right after the first is 'found together', not given the same window" \
    || bad sv_033b "a miss with no mark of its own got a window: [$r] [$r2]"
}

# TF-034: a fix recorded in segments around its chained verifies gave each miss it closed the first segment only.
sv_034() {
  local d="$SCRATCH/sv034" r
  _mfx "$d"
  run() { printf '{"v":1,"kind":"run","app":"Fx","cmd":"%s","mode":"fix","started":"2026-11-13T%s:00Z","ended":"2026-11-13T%s:00Z","reqs_touched":%s,"tokens_in":1,"tokens_out":%s,"tokens_cache_read":0,"tokens_cache_write":0,"cost_usd":null,"tokens_scope":"main","model":"m"}\n' "$@"; }
  { run triage-and-fix 05:43 05:44 '["REQ-UI-089"]' 100; run verify-phase 05:44 07:19 '[]' 5000; run triage-and-fix 07:19 07:20 '[]' 200
    run verify-phase 07:20 07:25 '[]' 900; run triage-and-fix 07:25 07:34 '[]' 300; run triage-and-fix 07:34 07:50 '["REQ-UI-090"]' 7000; } > "$d/docs/metrics/runs.jsonl"
  printf '%s\n' '{"v":1,"kind":"miss","miss_id":"MISS-Fx-20261112-21","app":"Fx","req_id":"REQ-UI-089","miss_class":"wrong-behaviour","artifact":"src","severity":"minor","found_by":"owner","ts":"2026-11-12T10:00:00Z"}' \
    '{"v":1,"kind":"miss","miss_id":"MISS-Fx-20261112-22","app":"Fx","req_id":"REQ-UI-090","miss_class":"wrong-behaviour","artifact":"src","severity":"minor","found_by":"owner","ts":"2026-11-12T10:00:00Z"}' >> "$d/docs/metrics/misses.jsonl"
  for x in "21 05:43" "22 07:34"; do set -- $x
    printf '{"kind":"miss-fix","app":"Fx","miss_id":"MISS-Fx-20261112-%s","fix_cmd":"triage-and-fix","fix_attempt":1,"verdict_after":"Verified","reopened":false,"fix_run_id":"2026-11-13T%s:00Z"}' "$1" "$2" \
      | ( cd "$d" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d" bash .tfcore/utils/tf-emit.sh misses >/dev/null 2>&1 )
  done
  r="$(python3 -c "import json,sys
print(' '.join('%s=%s' % (x['miss_id'][-2:], x.get('tokens_out')) for x in map(json.loads, open(sys.argv[1])) if x.get('kind')=='miss-fix'))" "$d/docs/metrics/misses.jsonl" 2>&1)"
  [[ "$r" == *"21=600"* ]] && ok sv_034a "a fix recorded in three segments around two chained verifies: its miss-fix carries all three (600 tokens out), not the first (100), and no verify" \
    || bad sv_034a "the miss-fix does not carry the whole fix: $r"
  [[ "$r" == *"22=7000"* ]] && ok sv_034b "the next fix, which starts where that one ended, is its own: 7000, not added to the first" \
    || bad sv_034b "a fix of one record was changed: $r"
}

# TF-035: a duplicate check wrote one miss's why_missed and sort onto MISS-Sevak-20261112-21 and nothing could undo it.
sv_035() {
  local d="$SCRATCH/sv035" o1 o2 o3 r
  _mfx "$d"
  printf '%s\n' '{"v":1,"kind":"miss","miss_id":"MISS-Fx-20261112-21","app":"Fx","req_id":"REQ-UI-089","miss_class":"partial-implementation","artifact":"src","severity":"major","found_by":"gate","ts":"2026-11-12T15:46:15Z"}' \
    '{"v":1,"kind":"miss-amend","miss_id":"MISS-Fx-20261112-21","field":"why_missed","value":"insufficient-verify-method","ts":"2026-11-13T07:33:33Z"}' \
    '{"v":1,"kind":"miss-amend","miss_id":"MISS-Fx-20261112-21","field":"sort","value":"weak-check","ts":"2026-11-13T07:33:33Z"}' >> "$d/docs/metrics/misses.jsonl"
  em() { ( cd "$d" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d" bash .tfcore/utils/tf-emit.sh "$@" 2>&1 ); }
  o1="$(em --amend MISS-Fx-20261112-21 why_missed none "the cause of MISS-Fx-20261113-01, written here by a duplicate check")"
  o2="$(em --amend MISS-Fx-20261112-21 sort spec "the sort of MISS-Fx-20261113-01, written here by a duplicate check")"
  r="$(cd "$d" && python3 .tfcore/utils/tf-misses-md.py --root "$d" --app Fx --quiet >/dev/null 2>&1; grep 'MISS-Fx-20261112-21' "$d/docs/Fx-Misses.md" 2>/dev/null | head -1)"
  local fold; fold="$(python3 -c "import json,sys
recs=[json.loads(l) for l in open(sys.argv[1])]
c=[x for x in recs if x.get('kind')=='miss-amend' and x.get('reason')]
print(len(c), [x['value'] for x in c])" "$d/docs/metrics/misses.jsonl" 2>&1)"
  [[ "$o1" == *"corrected MISS-Fx-20261112-21"* && "$o2" == *corrected* && "$fold" == "2 [None, 'spec']" ]] && [[ "$r" == *spec* && "$r" != *weak-check* ]] \
    && ok sv_035a "a wrong why_missed and sort are corrected with a reason; both corrections stay on the stream and the readable list shows the new sort" \
    || bad sv_035a "no supported correction: [$(cut -c1-120 <<<"$o1")] [$fold] md=$r"
  o3="$(em --amend MISS-Fx-20261112-21 sort ignored)"
  [[ "$o3" == *"amend refused"* ]] \
    && ok sv_035b "an amend without a reason still never overwrites a value that is set" \
    || bad sv_035b "a plain amend overwrote a set value: $o3"
}

# --- Sevak TF-030: the screen the app's root opens could not be measured at its second width ------------
# In Sevak '/' draws Today. A desktop head already on /today was moved to '/' and back so the screen is
# drawn afresh (Lekhak TF-038), but '/' is Today too: no control of the screen was new on the way back, and
# the check gave up, "not measured: the app did not move to /today". The hop now goes to a route no page
# answers when the first one leaves the screen's controls in place.
sv_030() {
  local pw; pw="$(_pw_dir)"
  [[ -n "$pw" ]] || { printf 'skip sv_030 — playwright is not installed here\n'; return; }
  local d="$SCRATCH/sv030" port srv out
  mkdir -p "$d/site/today"
  cat > "$d/site/today/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"></head><body><script>
function draw() {
  const p = location.pathname.replace(/\/+$/, '') || '/';
  document.body.innerHTML = '<p>loading</p>';
  setTimeout(() => { document.body.innerHTML = (p === '/' || p === '/today')
    ? '<h1>Today</h1><div data-testid="today-a">A</div><div data-testid="today-b">B</div>' : '<h1>Not found</h1>'; }, 150);
}
addEventListener('popstate', draw); draw();
</script></body></html>
HTML
  ln -sfn "$pw/node_modules" "$d/node_modules"; cp "$UTILS/tf-login.mjs" "$d/"
  cat > "$d/run.mjs" <<'JS'
import { chromium } from 'playwright';
import { openFresh } from './tf-login.mjs';
const b = await chromium.launch(); const p = await b.newPage();
await p.goto(process.argv[2] + '/today/'); await p.waitForSelector('[data-testid="today-a"]');
// the mockup anchors a third control the app draws only with data, as Today's do
const a = await openFresh(p, '/today', ['today-a', 'today-b', 'today-sample'], { renderWait: 2000 });
console.log(JSON.stringify({ arrived: a.arrived, reset: a.reset, path: await p.evaluate(() => location.pathname) }));
await b.close();
JS
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  out="$(cd "$d" && tf_timeout 90 node run.mjs "http://127.0.0.1:$port" 2>&1 | tail -1)"
  kill "$srv" 2>/dev/null
  grep -q '"arrived":true,"reset":true,"path":"/today"' <<<"$out" \
    && ok sv_030 "a screen the app's root also draws is opened afresh: the hop away lands on a page that is not the screen" \
    || bad sv_030 "the screen the root opens was not seen to arrive: $out"
}

# --- Sevak TF-026 and the set-up rule (owner, 2026-11-11 19:07): what the test step does around a run ---
# _fx_tests <dir>: a project whose tf-verify-tests.sh runs against stand-ins: npx (Playwright), node's
# @playwright/test, powershell.exe and tf-build.sh log what they were asked; a desktop head's debugging
# address answers /json/version, and boot.json records it with one Windows process id.
_fx_tests() {
  local d="$1" port
  mkdir -p "$d/bin" "$d/tests/verify" "$d/tests/.artifacts/verify" "$d/.tfcore/utils" "$d/node_modules/@playwright/test" "$d/cdp/json"
  cp "$UTILS"/tf-verify-tests.sh "$UTILS"/tf-portable.sh "$UTILS"/tf-lock.sh "$UTILS"/tf-req-ids.py "$UTILS"/tf-login.mjs "$d/.tfcore/utils/"
  for f in tf-verify-around.sh tf-verify-settings.py; do [[ -f "$UTILS/$f" ]] && cp "$UTILS/$f" "$d/.tfcore/utils/"; done
  printf '#!/usr/bin/env bash\necho "tf-build $*" >> "$TF_FX_LOG"; echo "PASS 0 tests"\n' > "$d/.tfcore/utils/tf-build.sh"
  printf '{"name":"@playwright/test","main":"index.js"}' > "$d/node_modules/@playwright/test/package.json"; : > "$d/node_modules/@playwright/test/index.js"
  printf "test('REQ-UI-001 shows', async () => { process.env.CDP_URL; process.env.BASE_URL });\n" > "$d/tests/verify/a.spec.ts"
  printf "test('phase 2 set-up: choose the language @setup', async () => {});\n" > "$d/tests/verify/set-language.spec.ts"
  printf '{"webSocketDebuggerUrl":"ws://x"}' > "$d/cdp/json/version"
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  printf '{"mode":"cdp","url":"http://127.0.0.1:%s","win_pids":[4242]}' "$port" > "$d/tests/.artifacts/verify/boot.json"
  printf '%s' "$port" > "$d/port"
  printf '#!/usr/bin/env bash\necho "powershell $*" >> "$TF_FX_LOG"\n' > "$d/bin/powershell.exe"
  # npx playwright test …: --list names three tests, a --grep @setup run passes the set-up one, any other passes the row's
  cat > "$d/bin/npx" <<'SH'
#!/usr/bin/env bash
echo "npx $*" >> "$TF_FX_LOG"
spec() { printf '{"title":"%s","file":"%s","tags":[],"tests":[{"results":[{"status":"%s"}]}]}' "$1" "$2" "$3"; }
if [[ " $* " == *" --list "* ]]; then body="$(spec 'REQ-UI-001 shows' a.spec.ts passed),$(spec 'phase 2 set-up: choose the language @setup' set-language.spec.ts passed),$(spec 'untitled check' b.spec.ts passed)"
elif [[ " $* " == *" @setup "* ]]; then body="$(spec 'phase 2 set-up: choose the language @setup' set-language.spec.ts passed)"
else body="$(spec 'REQ-UI-001 shows' a.spec.ts passed)"; sleep 3; fi
printf '{"suites":[{"title":"x","file":"x","specs":[%s]}]}' "$body" > "$PLAYWRIGHT_JSON_OUTPUT_NAME"
SH
  chmod +x "$d/bin/npx" "$d/bin/powershell.exe" "$d/.tfcore/utils/tf-build.sh"
}
_run_tests() {   # <dir> <args…>: tf-verify-tests.sh in the fixture, with its cdp address up; prints its output
  local d="$1" srv; shift
  python3 -m http.server "$(cat "$d/port")" --bind 127.0.0.1 --directory "$d/cdp" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d" && TF_FX_LOG="$d/log" PATH="$d/bin:$PATH" NODE_PATH="$d/node_modules" tf_timeout 120 bash .tfcore/utils/tf-verify-tests.sh "$@" 2>&1 )
  kill "$srv" 2>/dev/null
}
sv_026() {
  command -v node >/dev/null 2>&1 || { printf 'skip sv_026 — node is not installed here\n'; return; }
  local d="$SCRATCH/sv026a" out
  _fx_tests "$d"; out="$(_run_tests "$d" --no-unit)"
  grep -q 'powershell .*IsIconic.*4242' "$d/log" 2>/dev/null \
    && ok sv_026a "while the browser tests run, the desktop head's window is restored whenever it is minimized" \
    || { bad sv_026a "nothing watched the head's window during the test run"; note "$(tr '\n' '|' < "$d/log" 2>/dev/null | cut -c1-200)"; }
  d="$SCRATCH/sv026b"; _fx_tests "$d"; : > "$d/x.sln"
  out="$(_run_tests "$d" --no-browser)"
  ! grep -q '^tf-build' "$d/log" 2>/dev/null && grep -q 'unit tests: NOT RUN — the desktop head at .* is up' <<<"$out" \
    && ok sv_026b "unit tests are not built while a desktop head is up; the line says to run them before the boot" \
    || { bad sv_026b "the unit tests were built while the head held its files"; note "$(tr '\n' '|' <<<"$out" | cut -c1-200)"; }
  d="$SCRATCH/sv026c"; mkdir -p "$d/docs"
  cat > "$d/docs/Fx-Checklist.md" <<'MD'
# Fx — Checklist

| ID | Title | Status | % | Remarks | Details |
|---|---|---|---|---|---|
| REQ-UI-001 | Today | Done | 90% | | [view](#d-req-ui-001) |
| REQ-UI-002 | Today in Hindi | Done | 90% | | [view](#d-req-ui-002) |

<a id="d-req-ui-001"></a>
- **REQ-UI-001** — Today. *Acceptance:* Today shows the day.

<a id="d-req-ui-002"></a>
- **REQ-UI-002** — Today in Hindi. *Acceptance:* after the language is set to Hindi, Today reads in Hindi.
  - needs-boot: relaunch (the language applies at the next launch)
MD
  out="$(cd "$d" && python3 "$UTILS/tf-verify-list.py" Fx ui --json-out tests/.artifacts/verify/list.json 2>&1)"
  grep -q '^- needs-boot relaunch (1): REQ-UI-002$' <<<"$out" && grep -q -- '--list tests/.artifacts/verify/list-relaunch.json' <<<"$out" \
    && python3 -c "import json,sys; j=json.load(open('$d/tests/.artifacts/verify/list-relaunch.json')); sys.exit(0 if j['scope']=='REQ-UI-002' and [r['id'] for r in j['rows']]==['REQ-UI-002'] else 1)" 2>/dev/null \
    && ok sv_026c "a row noted needs-boot is listed as a part of its own, with a list for that boot and the line that runs and merges it" \
    || { bad sv_026c "a row that needs another boot is not listed apart"; note "$(grep -i boot <<<"$out" | head -3 | tr '\n' '|')"; }
}
# --- Sevak TF-031: the second install's run took every test of the row, the first install's half too --------
# REQ-FN-046 exports on the first install and restores on a second one. The run of list-install.json kept
# every test carrying the id: the export ran again on the second install, and the restore then met its own
# install's archive and skipped. A test tagged @boot:install now runs only there, alone of its row, and the
# main run leaves it out. The stand-in npx applies --grep and --grep-invert to the titles as Playwright does.
sv_031() {
  command -v node >/dev/null 2>&1 || { printf 'skip sv_031 — node is not installed here\n'; return; }
  local d="$SCRATCH/sv031"
  _fx_tests "$d"; rm -f "$d/tests/verify/a.spec.ts"
  printf "test('REQ-FN-046 one workspace exported', async () => { process.env.CDP_URL; process.env.BASE_URL });\n" > "$d/tests/verify/f.spec.ts"
  printf "test('REQ-FN-046 the archive restores on another install', { tag: '@boot:install' }, async () => {});\n" > "$d/tests/verify/g.spec.ts"
  printf '#!/usr/bin/env bash\nexec node "$(dirname "$0")/npx.cjs" "$@"\n' > "$d/bin/npx"
  cat > "$d/bin/npx.cjs" <<'JS'
const fs = require('fs'), a = process.argv.slice(2), arg = (k) => (a.indexOf(k) >= 0 ? new RegExp(a[a.indexOf(k) + 1], 'i') : null);
fs.appendFileSync(process.env.TF_FX_LOG, 'npx ' + a.join(' ') + '\n');
const all = [['f.spec.ts', 'REQ-FN-046 one workspace exported'], ['g.spec.ts', 'REQ-FN-046 the archive restores on another install @boot:install'],
  ['set-language.spec.ts', 'phase 2 set-up: choose the language @setup']];
const g = arg('--grep'), v = arg('--grep-invert');
const run = all.filter(([f, t]) => (!g || g.test(f + ' ' + t)) && (!v || !v.test(f + ' ' + t)));
const exported = run.some(([f]) => f === 'f.spec.ts');   // an export on this boot makes this boot's own archive
const st = (f) => (f !== 'g.spec.ts' ? 'passed' : exported ? 'skipped' : process.env.TF_FX_RESTORE || 'passed');
const specs = run.map(([f, t]) => ({ title: t.replace(/ @boot:\w+/, ''), file: f, tags: [], tests: [{ results: [{ status: st(f) }] }] }));
fs.writeFileSync(process.env.PLAYWRIGHT_JSON_OUTPUT_NAME, JSON.stringify({ suites: [{ title: 'x', file: 'x', specs }] }));
JS
  chmod +x "$d/bin/npx"
  printf '{"scope":"REQ-FN-046","phase":2,"phases":[2],"needs_boot":"install","rows":[{"id":"REQ-FN-046","screen":"Automations"}]}' > "$d/tests/.artifacts/verify/list-install.json"
  printf '{"scope":"REQ-FN-046","phase":2,"phases":[2],"rows":[{"id":"REQ-FN-046","screen":"Automations"}]}' > "$d/tests/.artifacts/verify/list.json"
  _run_tests "$d" --no-unit --json-out tests/.artifacts/verify/tests-main.json >/dev/null
  _run_tests "$d" --no-unit --list tests/.artifacts/verify/list-install.json --json-out tests/.artifacts/verify/tests-install.json >/dev/null
  r() { python3 -c "import json,sys; o=json.load(open(sys.argv[1]))['reqs'].get('REQ-FN-046',{}).get('outcomes',{}); print(' '.join(sorted(n.split()[1]+'='+x['outcome'] for n,x in o.items())))" "$d/tests/.artifacts/verify/$1" 2>/dev/null; }
  [[ "$(r tests-main.json)" == "one=pass" && "$(r tests-install.json)" == "the=pass" ]] \
    && ok sv_031a "the second install runs only the row's @boot:install test, and the main boot leaves it out" \
    || { bad sv_031a "main boot ran: $(r tests-main.json); second install ran: $(r tests-install.json)"; note "$(grep '^npx' "$d/log" | grep -v @setup | tr '\n' '|' | cut -c1-300)"; }
  d="$SCRATCH/sv031b"; cp -r "$SCRATCH/sv031" "$d"; rm -rf "$d/tests/.artifacts/verify/tests-"*; : > "$d/log"
  TF_FX_RESTORE=failed _run_tests "$d" --no-unit --list tests/.artifacts/verify/list-install.json --json-out tests/.artifacts/verify/tests-install.json >/dev/null
  python3 -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))['reqs']['REQ-FN-046']['result']=='FAIL' else 1)" "$d/tests/.artifacts/verify/tests-install.json" 2>/dev/null \
    && ok sv_031b "a restore that fails on the second install still fails the row" \
    || bad sv_031b "the failed restore was not reported: $(r tests-install.json)"
}
# --- AstroLyfe 13 Nov (TF-001 in its file): the boot address reached the tests only as an environment variable ---
# AstroLyfe's tests take every setting from tests/verify/testsettings.json with testsettings.Local.json laid
# over it. The address now goes into the Local file's Verify:BaseUrl (Verify:CdpUrl for a desktop head) for
# the run and the file is put back after; BASE_URL and CDP_URL are still set for one release. The test-users
# check also reads the "Test User Accounts" section of docs/<App>-TestNUsageDoc.md.
as_001() {
  command -v node >/dev/null 2>&1 || { printf 'skip as_001 — node is not installed here\n'; return; }
  local d="$SCRATCH/as001" out seen
  _fx_tests "$d"
  printf '{"Verify":{"BaseUrl":"http://localhost:5099","Login":{"User":"owner@fx.app","Password":"FAKE-PW-as001"}}}\n' > "$d/tests/verify/testsettings.Local.json"
  cat > "$d/bin/npx" <<'SH'
#!/usr/bin/env bash
python3 -c 'import json,os; v=json.load(open("tests/verify/testsettings.Local.json"))["Verify"]; print("seen", v.get("BaseUrl"), v.get("CdpUrl"), os.environ.get("BASE_URL"))' >> "$TF_FX_LOG"
printf '{"suites":[{"title":"x","file":"a.spec.ts","specs":[{"title":"REQ-UI-001 shows","file":"a.spec.ts","tags":[],"tests":[{"results":[{"status":"passed"}]}]}]}]}' > "$PLAYWRIGHT_JSON_OUTPUT_NAME"
SH
  chmod +x "$d/bin/npx"
  out="$(_run_tests "$d" --no-unit)"
  seen="$(grep '^seen' "$d/log" | head -1)"; local url="http://127.0.0.1:$(cat "$d/port")"
  [[ "$seen" == "seen $url $url $url" ]] \
    && ok as_001a "during the browser run the Local settings file holds Verify:BaseUrl and Verify:CdpUrl, and BASE_URL is still set (one release)" \
    || { bad as_001a "the address did not reach the settings file: ${seen:-no test run}"; note "$(grep -i 'settings' <<<"$out" | head -2 | tr '\n' '|')"; }
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d=={'Verify':{'BaseUrl':'http://localhost:5099','Login':{'User':'owner@fx.app','Password':'FAKE-PW-as001'}}} else 1)" "$d/tests/verify/testsettings.Local.json" \
    && ! grep -q 'FAKE-PW' <<<"$out" \
    && ok as_001b "after the run the Local file is as it was, its own BaseUrl and sign-in kept, and nothing of it is printed" \
    || bad as_001b "the Local settings file was not put back: $(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["Verify"]))' "$d/tests/verify/testsettings.Local.json" 2>&1)"
  local u="$SCRATCH/as001u"; mkdir -p "$u/docs" "$u/tests/verify"
  printf '# Fx - Test & Usage Document\n\n## 2. Test User Accounts\n\n### Account Setup\n\nThese accounts live on AppManager.\n\n| # | Email |\n|---|---|\n| 1 | admin@fx.app |\n\n## 3. Screens\n' > "$u/docs/Fx-TestNUsageDoc.md"
  printf "test('REQ-UI-001 signs in', async ({ page }) => { await page.fill('#e', 'admin@fx.app'); });\ntest('REQ-UI-002 types', async ({ page }) => { await page.fill('#e', \`u\${Date.now()}@fx.app\`); });\n" > "$u/tests/verify/a.spec.ts"
  out="$(cd "$u" && python3 "$UTILS/tf-test-users-check.py" --app Fx --all --json-out "$u/tu.json" 2>&1)"
  python3 -c "import json,sys; j=json.load(open(sys.argv[1])); sys.exit(0 if j.get('test_users')==['admin@fx.app'] else 1)" "$u/tu.json" 2>/dev/null \
    && grep -q 'a.spec.ts:2 email: builds an address at run time' <<<"$out" \
    && ok as_001c "the test users of docs/<App>-TestNUsageDoc.md's Test User Accounts section are read; an address built at run time is still a finding" \
    || bad as_001c "the TestNUsageDoc test users were not read: $(tr '\n' '|' <<<"$out" | cut -c1-260)"
}

# --- AppManager 13 Nov (TF-031 in its file): tf-verify-list.sh printed the test users' passwords -----------
# The UsageGuide's Test users table held the passwords themselves, and the list printed them into the
# session. No framework script prints a password, key, token or connection string: the user, the role and
# whether a password is set. tests/faults/secrets/scan.py runs every script in .tfcore/utils against a project
# holding fake secrets everywhere a project keeps one; its control is a planted script that prints one.
am_031() {
  local d="$SCRATCH/am031" out
  out="$(python3 "$ROOT/tests/faults/secrets/scan.py" "$UTILS" "$d" 2>&1)"
  grep -q '^scanned .* 0 leak(s)$' <<<"$out" \
    && ok am_031a "no script in .tfcore/utils prints a password, key, token or connection string ($(tail -1 <<<"$out" | cut -d, -f1))" \
    || bad am_031a "a script printed a secret: $(grep '^LEAK' <<<"$out" | head -5 | tr '\n' '|')"
  grep -q -- '- admin@fx.app — Admin — password: set' <<<"$(cd "$d/fx" && TF_SKIP_SELFCHECK=1 python3 .tfcore/utils/tf-verify-list.py Fx all 2>&1)" \
    && ok am_031b "the verify list still names each test user and role, and says the password is set" \
    || bad am_031b "the verify list lost its test users"
  mkdir -p "$d/leaky"; cp -r "$UTILS"/. "$d/leaky/"; printf '#!/usr/bin/env bash\ncat docs/*UsageGuide.md 2>/dev/null\n' > "$d/leaky/tf-zz-leaky.sh"
  out="$(python3 "$ROOT/tests/faults/secrets/scan.py" "$d/leaky" "$d/l" 2>&1)"
  grep -q '^LEAK tf-zz-leaky.sh (no arguments): usage-guide password$' <<<"$out" && [[ "$(grep -c '^LEAK tf-zz-leaky.sh ' <<<"$out")" == 4 ]] \
    && ok am_031c "a script that prints the guide's password is caught, under every argument set" \
    || bad am_031c "the scan missed a planted leak: $(tail -3 <<<"$out" | tr '\n' '|')"
}

# --- AppManager 13 Nov (TF-032 in its file): a row moved to a new phase 2 left phase 1's BRD stale ----------
# Moving a row from phase 1 to phase 2 changed both checklists; tf-brd-status.sh refreshed only appPhase's
# BRD, and the status gate (guard-status-html.sh) kept blocking on phase 1's. Without --phase it now
# refreshes every phase whose checklist is newer than its BRD. A phase whose BRD is current is untouched,
# and the gate still names a BRD left older than its checklist.
am_032() {
  local d="$SCRATCH/am032" n out; mkdir -p "$d/docs" "$d/.tfcore/.session" "$d/.tfcore/utils"
  printf 'appPhase: 2\n' > "$d/.tfcore/core-config.yaml"
  cp "$UTILS/tf-brd-status.py" "$UTILS/tf-brd-status.sh" "$d/.tfcore/utils/"
  for n in 1 2 3; do
    local p; [[ $n == 1 ]] && p="Fx" || p="Fx-P$n"
    printf '# Fx — BRD phase %s\n\n## 7. Development status\n\nold\n' "$n" > "$d/docs/$p-BRD.md"
    printf '# Fx — Phase %s Checklist\n\n## Requirements Status\n\n| ID | Title | Status | %% | Remarks | Detail |\n|---|---|---|---|---|---|\n| REQ-FN-%s01 | Export | Verified | 100%% | | [view](#d) |\n\n## Page: Export (`/export`)\n\n<a id="d"></a>\n- **REQ-FN-%s01** — Export.\n  - *Acceptance:* When a user clicks Export on Export, then a file downloads.\n' "$n" "$n" "$n" > "$d/docs/$p-Checklist.md"
  done
  touch -t "$(tf_date_from '-30 min' +%Y%m%d%H%M.%S)" "$d/docs/Fx-BRD.md" "$d/docs/Fx-P2-BRD.md" "$d/docs/Fx-P3-Checklist.md"
  ( cd "$d" && bash .tfcore/utils/tf-brd-status.sh Fx --no-render >/dev/null 2>&1 )
  grep -q 'Snapshot as of' "$d/docs/Fx-BRD.md" && grep -q 'Snapshot as of' "$d/docs/Fx-P2-BRD.md" \
    && ok am_032a "a run that changed the phase 1 and phase 2 checklists refreshes both BRDs, not only appPhase's" \
    || bad am_032a "phase 1's BRD was left stale: $(grep -c Snapshot "$d/docs/Fx-BRD.md") snapshot(s) in docs/Fx-BRD.md"
  printf '{}' > "$d/.tfcore/.session/claude-code.json"; touch -t "$(tf_date_from '-10 min' +%Y%m%d%H%M.%S)" "$d/.tfcore/.session/claude-code.json"
  printf '# Fx — Project status\n' > "$d/PROJECT-STATUS.md"; cp "$d/PROJECT-STATUS.md" "$d/PROJECT-STATUS.html"
  touch -t "$(tf_date_from '-20 min' +%Y%m%d%H%M.%S)" "$d/docs/Fx-P3-BRD.md"; touch "$d/docs/Fx-P3-Checklist.md"
  out="$(printf '{}' | CLAUDE_PROJECT_DIR="$d" CLAUDECODE=1 bash "$HOOKS/guard-status-html.sh" 2>&1)"
  ! grep -qE 'Fx(-P2)?-BRD.md is older' <<<"$out" && grep -qF 'Run: bash .tfcore/utils/tf-brd-status.sh Fx --phase 3' <<<"$out" \
    && ok am_032b "the gate no longer blocks on phase 1 or 2, and still names a phase 3 BRD left older than its checklist" \
    || bad am_032b "the gate's BRD lines: $(grep -o 'docs/[^ ]*-BRD.md is older' <<<"$out" | tr '\n' ' ')"
}

setup_first() {
  command -v node >/dev/null 2>&1 || { printf 'skip setup_first — node is not installed here\n'; return; }
  local d="$SCRATCH/setup" out
  _fx_tests "$d"
  printf '{"scope":"all","phase":2,"phases":[1,2],"rows":[{"id":"REQ-UI-001","screen":"Today"}]}' > "$d/tests/.artifacts/verify/list.json"
  out="$(_run_tests "$d" --no-unit)"
  local order; order="$(grep '^npx' "$d/log" | grep -v -- '--list' | awk '{ for (i = 1; i < NF; i++) if ($i == "--grep") printf "%s ", $(i + 1) }')"
  [[ "$order" == "@setup REQ-UI-001 " ]] && grep -q 'SET-UP set-language.spec.ts' <<<"$out" \
    && ok setup_first_a "a test tagged @setup runs before the row tests in a phase verify, and is named as set-up" \
    || { bad setup_first_a "the set-up test did not run first (runs: $order)"; note "$(grep -i 'set-up' <<<"$out" | head -2 | tr '\n' '|')"; }
  grep -q 'NOT RUN (no row id) b.spec.ts' <<<"$out" && ! grep -q 'NOT RUN (no row id) set-language' <<<"$out" \
    && python3 -c "import json,sys; sys.exit(0 if list(json.load(open('$d/tests/.artifacts/verify/tests.json'))['reqs'])==['REQ-UI-001'] else 1)" \
    && ok setup_first_b "a set-up test is not listed as 'no row id' and grades no row; a test with no id still is listed" \
    || { bad setup_first_b "the set-up test was listed as having no row id, or graded"; note "$(grep 'NOT RUN' <<<"$out" | tr '\n' '|')"; }
}

# --- run ----------------------------------------------------------------------------------
echo "# tests/faults — one case per fault found by reading the code"
for t in status_read marker_age yolo_ttl emit_root backtick_row owner_uat quoted_phase handoff_prose assets_login sv_025 ch_026 ch_027 ch_028 tf_058 sv_033 sv_034 sv_035 sv_027 sv_028 sv_029 sv_030 sv_032 tf_057 sv_026 sv_031 as_001 am_031 am_032 setup_first; do
  [[ -n "$only" && "$only" != "$t" ]] && continue
  "$t"
done
[[ $fail -eq 0 ]] && echo "# all fault cases hold" || echo "# fault cases FAILED"
exit $fail

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

# --- run ----------------------------------------------------------------------------------
echo "# tests/faults — one case per fault found by reading the code"
for t in status_read marker_age yolo_ttl emit_root backtick_row owner_uat quoted_phase handoff_prose assets_login sv_025; do
  [[ -n "$only" && "$only" != "$t" ]] && continue
  "$t"
done
[[ $fail -eq 0 ]] && echo "# all fault cases hold" || echo "# fault cases FAILED"
exit $fail

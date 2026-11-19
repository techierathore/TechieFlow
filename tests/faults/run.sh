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
# Exit 0 all held, 1 a case failed. Python 3 standard library only. git runs only in a case's own scratch repositories (n16-cases.sh).
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
trap '[[ -n "${TF_KEEP:-}" ]] || rm -rf "$SCRATCH"' EXIT
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
  if [[ -z "$pw" ]]; then printf 'skipped: sv_025 — needs playwright (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'; return; fi
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
  ( cd "$d" && tf_timeout 120 node tf-mockup-parity.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen "$2=$3" --widths 1280,390 --json-out "$d/parity.json" ${TF_PARITY_ARGS:-} >/dev/null 2>&1 )
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
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_027 — needs playwright\n'; return; }
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
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_028 — needs playwright\n'; return; }
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
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_029 — needs playwright\n'; return; }
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
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_032 — needs playwright\n'; return; }
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
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_027 — needs playwright\n'; return; }
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
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_026 — needs playwright\n'; return; }
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
    # a chained verify carries its own mark since 14 Nov (verify_mark); its record is refused without one
    [[ "$x" == */v ]] && printf '{"outer":{"cmd":"fix-issues","app":"Fx","started":"%s"},"cmd":"verify-phase","app":"Fx","started":"2026-11-13T09:30:00Z"}\n' "$t1" > "$x/.tfcore/.session/phase.json"
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
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: tf_058 — needs playwright\n'; return; }
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
_win() { python3 -c "import json,sys; r=[json.loads(l) for l in open(sys.argv[1]) if '\"kind\":\"miss\"' in l][-1]; print(r.get('discovery_started') or '-', r.get('discovery_ended') or '-', r.get('found_run_id'))" "$1/docs/metrics/misses.jsonl" 2>&1; }

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
  [[ "$r" == "- found by the owner"* && "$r2" == "- found in the same investigation as MISS-"* ]] \
    && ok sv_033b "with no look mark the miss still says why it has no window; a second miss after the same mark names the first, which carries the time (Chatur TF-036), and is not given the same window" \
    || bad sv_033b "a miss with no mark of its own got a window: [$r] [$r2]"
}

# --- Chatur TF-036, Sevak TF-039: a finding took the time of a mark that was not its own -------------------
# Both scripts read "the latest look mark at or before the finding" from the clock. Chatur: a mark set in the
# same second as the last demote took that row's time (0 s) and the next two rows read "found together".
# Sevak: a cause logged after the next investigation began got that one's time. One rule now (tf_looks.py):
# by the order of the calls or the mark --look names; a wrong figure already recorded can be marked.
ch_036() {
  local d="$SCRATCH/ch036" r a b c n1 n2 mid out
  a="$(tf_date_from -u '-30 min' +%Y-%m-%dT%H:%M:%SZ)"; b="$(tf_date_from -u '-12 min' +%Y-%m-%dT%H:%M:%SZ)"; c="$(tf_date_from -u '-2 min' +%Y-%m-%dT%H:%M:%SZ)"
  dem() { printf '{"verb":"demote","req_id":"%s","symptom":"s","kind":null,"source":"owner","why":"other","sort":"weak-check","prior":"Verified","ts":"%s"}' "$1" "$2"; }
  lk() { printf '{"verb":"look","symptom":"%s","ts":"%s"}' "$1" "$2"; }
  _mfx "$d/t"
  printf '{"actions":[%s,%s,%s,%s,%s]}\n' "$(lk 'blank screen' "$a")" "$(dem REQ-UI-055 "$b")" "$(lk 'pill shape' "$b")" "$(dem REQ-FN-018 "$c")" "$(dem REQ-UI-049 "$c")" > "$d/t/tests/.artifacts/verify/triage.json"
  ( cd "$d/t" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$PWD" bash .tfcore/utils/tf-triage.sh Fx close --cmd triage-and-fix >/dev/null 2>&1 )
  r="$(python3 -c "import json,sys
for m in map(json.loads, open(sys.argv[1])):
    if m.get('kind') == 'miss': print(m['req_id'], m.get('discovery_started') or '-', m.get('discovery_ended') or '-', '-' if m.get('discovery_started') else (m.get('discovery_why') or '-')[:34])" "$d/t/docs/metrics/misses.jsonl" 2>&1 | paste -s -d '|' -)"
  [[ "$r" == "REQ-UI-055 $a $b -|REQ-FN-018 $b $c -|REQ-UI-049 - - found in the same investigation as" ]] \
    && ok ch_036a "a mark set in the second of the last demote leaves that row its own 18 minutes; the next mark's first row carries its time and the second says it shares it" \
    || bad ch_036a "the rows took another mark's time (marks at $a and $b): $r"
  _mfx "$d/s"; printf '{"actions":[%s,%s]}\n' "$(lk 'cause A' "$a")" "$(lk 'cause B' "$b")" > "$d/s/tests/.artifacts/verify/triage.json"
  _lm "$d/s" --what "The cause of A, logged after B began" --look 1 --started "$c" > "$d/s.out"; n1="$(_win "$d/s")"
  _lm "$d/s" --what "The cause of B" >/dev/null; n2="$(_win "$d/s")"
  [[ "$n1" == "$a $b "* && "$n1" != *" $c" && "$n2" == "$b "* ]] && grep -q "^note: --started is the running command's start" "$d/s.out" \
    && ok ch_036b "a cause logged after the next investigation began, naming its mark with --look, carries its own investigation's time and the running command's start; the next cause carries the later mark's" \
    || bad ch_036b "cause A did not get mark 1's time ($a to $b): [$n1] [$n2]"
  _mfx "$d/u"; printf '{"actions":[%s,%s]}\n' "$(lk 'cause A' "$a")" "$(lk 'cause B' "$b")" > "$d/u/tests/.artifacts/verify/triage.json"
  _mfx "$d/v"; printf '{"actions":[%s,%s]}\n' "$(lk 'cause A' "$a")" "$(lk 'cause B' "$b")" > "$d/v/tests/.artifacts/verify/triage.json"
  printf '# Fx — Checklist\n\n| ID | Requirement | Status | %% | Remarks | Detail |\n|---|---|---|---|---|---|\n| REQ-UI-001 | A screen | Verified | 100%% | — | x |\n' > "$d/v/docs/Fx-Checklist.md"
  local dm; dm="$(cd "$d/v" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$PWD" bash .tfcore/utils/tf-triage.sh Fx look "a third problem" 2>&1; CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$PWD" bash .tfcore/utils/tf-triage.sh Fx demote REQ-UI-001 "the screen is blank" --look 3 2>&1)"
  _lm "$d/u" --what "A cause that names no mark while two are open" >/dev/null; n1="$(_last "$d/u")"
  mid=MISS-Fx-20261114-02   # a finding time recorded wrongly (0 s, another mark's): marked, and out of the report's average
  printf '{"v":1,"kind":"miss","miss_id":"%s","app":"Fx","project_type":"app","req_id":"REQ-UI-001","miss_class":"wrong-behaviour","artifact":"src","severity":"minor","found_by":"owner","found_phase":"triage-and-fix","discovery_started":"%s","discovery_ended":"%s","discovery_s":0,"discovery_scope":"main","discovery_tokens_out":900,"ts":"%s"}\n' "$mid" "$b" "$b" "$b" >> "$d/u/docs/metrics/misses.jsonl"
  out="$(cd "$d/u" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$PWD" bash .tfcore/utils/tf-emit.sh --amend "$mid" discovery_scope not-measured "took another mark's time; the true time is in the run summary" 2>&1; CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$PWD" bash .tfcore/utils/tf-emit.sh --amend "$mid" discovery_started "$a" 2>&1
    bash "$ROOT/.tfcore/telemetry/tf-metrics.sh" --report "$d/u" --json 2>/dev/null | python3 -c "import json,sys; print('measured', json.dumps(json.load(sys.stdin)).count('\"discovery\": \"measured\"'))")"
  [[ "$dm" == *"(mark 3;"*"REQ-UI-001: Verified → Needs re-verify"* && "$dm" != *"NOT MEASURED"* && "$n1" == "- 2 investigations were open"*"--look <number>"* && "$out" == *"corrected $mid — discovery_scope = not-measured"*"amend refused"*"measured 0" ]] \
    && ok ch_036c "with two marks open and none named the finding is not measured and says how to name one; a wrong finding time can be marked not measured with a reason, and never rewritten" \
    || bad ch_036c "demote with --look failed, a guess was recorded, or the figure could not be marked: [${dm:0:160}] [$n1] [$(tr '\n' ' ' <<<"$out" | cut -c1-200)]"
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
  [[ -n "$pw" ]] || { printf 'skipped: sv_030 — needs playwright\n'; return; }
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
  command -v node >/dev/null 2>&1 || { printf 'skipped: sv_026 — needs node\n'; return; }
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
  command -v node >/dev/null 2>&1 || { printf 'skipped: sv_031 — needs node\n'; return; }
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
  command -v node >/dev/null 2>&1 || { printf 'skipped: as_001 — needs node\n'; return; }
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
  command -v node >/dev/null 2>&1 || { printf 'skipped: setup_first — needs node\n'; return; }
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

# --- Chatur TF-030 (TF-027 reopened): the Board's picker, data-testid on a box around the Select -----------
# ch_027 passed and the Board did not: its mockup's popwrap held only the trigger, so the popwrap read as a
# trigger and paired. The Board's popwrap also holds its open list (data-tf-state) of three option buttons,
# four buttons in all, so it was no trigger, and the app's combobox sits one box deeper than the mockup's
# button.pick, so the two never met: "filter-phase: mockup carries an icon here; the app does not". The
# buttons of another state are no trigger's. A plain button's chevron in the same shape is still reported.
ch_030() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_030 — needs playwright\n'; return; }
  local d="$SCRATCH/ch030" par chev='<svg width="12" height="12" viewBox="0 0 12 12"><path d="M2 4l4 4 4-4" stroke="currentColor" fill="none"/></svg>'
  local pop='<div class="pop" data-tf-state="popup-open" style="display:none"><button type="button">Every phase</button><button type="button">Phase 1</button><button type="button">Phase 2</button></div>'
  local cb="<button role=\"combobox\" type=\"button\" aria-expanded=\"false\" class=\"input\"><span>Every phase</span>$chev</button>"
  _pages "$d" board \
    "<div class=\"bar\" data-testid=\"filters\"><div class=\"popwrap\" data-testid=\"filter-phase\"><button class=\"input pick\" type=\"button\">Phase 2 $chev</button>$pop</div><div class=\"popwrap\" data-testid=\"filter-status\"><button class=\"input pick\" type=\"button\">Any $chev</button>$pop</div></div><div class=\"bar\" data-testid=\"more-box\"><div class=\"popwrap\" data-testid=\"more-menu\"><button class=\"input\" type=\"button\">More $chev</button>$pop</div></div>" \
    "<div class=\"bar\" data-testid=\"filters\"><div data-testid=\"filter-phase\"><div class=\"relative\">$cb</div></div><div class=\"relative\" data-testid=\"filter-status\">$cb</div></div><div class=\"bar\" data-testid=\"more-box\"><div data-testid=\"more-menu\"><div><button class=\"input\" type=\"button\">More</button></div></div></div>"
  par="$(_parity "$d" board /board/)"
  [[ "$par" != NO-RESULT ]] && ! grep -qE ' (filter-phase|filter-status|filters)( > [^ ]+)? (icon|missing) ' <<<"$par" \
    && ok ch_030a "the Board's picker, its mockup popwrap holding an open list and its app combobox one box deeper: no arrow finding" \
    || bad ch_030a "a picker's arrow was counted: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
  grep -qE '^1280 more-menu( > [^ ]+)? (icon|missing) ' <<<"$par" && grep -qE '^390 more-menu( > [^ ]+)? (icon|missing) ' <<<"$par" \
    && ok ch_030b "a plain button's chevron the app does not draw, in the same popwrap shape, is still reported at both widths" \
    || bad ch_030b "the plain button's missing chevron was lost: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
}

# --- Lekhak TF-042: 2 px buttons read as pills, a near-black icon as accent ----------------------------------
# The mockup declares data-site-theme="fluent-modern"; Lekhak runs "minimal". The check draws the app in the
# mockup's site theme, where Lekhak's --radius makes rounded-md 6 px (2 px under minimal) and its link rule
# paints an <a> button blue (#1A1A1A under minimal). The owner measured the app as it runs, so the check and
# the page's own styles disagreed. A button is a pill only when fully rounded; every shape and colour finding
# prints what both sides measured and the site theme the app was drawn in. A real pill drawn plain is still one.
lk_042() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: lk_042 — needs playwright\n'; return; }
  local d="$SCRATCH/lk042" ic='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="m12 19l-7-7l7-7"/></svg>'
  mkdir -p "$d/docs/mockups" "$d/site/episodes"
  printf '<!doctype html><html data-site-theme="fluent-modern" data-theme="light"><head><meta charset="utf-8"><style>body{font:14px system-ui;padding:16px;color:#323130} .btn{display:inline-flex;gap:6px;align-items:center;height:34px;padding:0 12px;border-radius:4px;border:1px solid #e1e1e1;background:transparent;color:#323130;text-decoration:none} .pill{display:inline-block;padding:2px 8px;border-radius:999px;background:#dbeafe;color:#1e40af;font-size:12px}</style></head><body><div data-testid="episode-head"><a class="btn" href="#" data-testid="episode-back">%s Back</a> <button class="btn" data-testid="episode-text">%s Text</button></div><p data-testid="episode-state"><span class="pill">Draft</span></p></body></html>\n' "$ic" "$ic" > "$d/docs/mockups/episodes.html"
  printf '<!doctype html><html data-site-theme="minimal" data-theme="light"><head><meta charset="utf-8"><style>:root{--radius:8px;--primary:#0078D4} [data-site-theme="minimal"]{--radius:4px;--primary:#1A1A1A} body{font:14px system-ui;padding:16px;color:#323130} [data-site-theme="fluent-modern"] a{color:var(--primary)} [data-site-theme="minimal"] a{color:#1A1A1A} .b{display:inline-flex;gap:6px;align-items:center;height:36px;padding:0 12px;border-radius:calc(var(--radius) - 2px);border:.67px solid #999;background:rgb(250,250,250);color:#1a1a1a;text-decoration:none}</style></head><body><div data-testid="episode-head"><a class="b" href="#" data-testid="episode-back">%s Back</a> <button class="b" data-testid="episode-text">%s Text</button></div><p data-testid="episode-state"><span>Draft</span></p></body></html>\n' "$ic" "$ic" > "$d/site/episodes/index.html"
  local par; par="$(_parity "$d" episodes /episodes/)"
  local col; col="$(python3 -c "
import json
for s in json.load(open('$d/parity.json'))['screens']:
    for f in s.get('findings', []):
        if f['class'] == 'color' and f['key'].startswith('episode-back') and f.get('measured') and 'data-site-theme=\"fluent-modern\"' in f.get('drawn_in', '') and '\"minimal\"' in f['detail']: print(f['width'], f['detail'][-160:])" 2>/dev/null)"
  [[ "$par" != NO-RESULT ]] && ! grep -qE ' (episode-back|episode-text|episode-head)( > [^ ]+)? badge ' <<<"$par" && grep -q '^1280 ' <<<"$col" \
    && ok lk_042a "a button with a 6 px corner is no pill; the back link's colour finding prints both measured colours and the site theme the app was drawn in" \
    || bad lk_042a "a button read as a pill, or a colour finding without its measurements: $(tr '\n' '|' <<<"$par" | cut -c1-260) // ${col:0:120}"
  grep -qE '^1280 episode-state > span\[0\] (badge|missing) ' <<<"$par" && grep -qE '^390 episode-state > span\[0\] (badge|missing) ' <<<"$par" \
    && ok lk_042b "a real pill the app draws as plain text is still reported at both widths" \
    || bad lk_042b "the flattened pill was lost: $(tr '\n' '|' <<<"$par" | cut -c1-300)"
}

# --- Chatur TF-034: the box drawn around a text field read as a pill -------------------------------------------
# Sign in and Register kept failing after the app took the mockups' button shape: the mockup's field is a
# box (10 px corner on 34 px, a ring) around a borderless input, the app's a bare div around the library's
# input. Since 14 Nov a control is a pill only when fully rounded, but the box around one was still a pill at
# 6 px, and the app's input no longer answered for it. The box around a text field is judged as the field is.
ch_034() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_034 — needs playwright\n'; return; }
  local d="$SCRATCH/ch034" out box='style="border:1px solid #bbb;border-radius:10px;background:#fbf6f1;height:34px;display:flex"'
  _pages "$d" sign-in "<div data-testid=\"field-email\"><label>Email</label><div $box><input value=\"a@b.c\" style=\"width:100%;height:32px;padding:0 11px;border:0;background:none;outline:none\" data-testid=\"input-email\"></div></div><p data-testid=\"state\"><span class=\"pill green\">Active</span></p>" \
                      "<div data-testid=\"field-email\"><label>Email</label><div><input value=\"a@b.c\" class=\"input\" data-testid=\"input-email\"></div></div><p data-testid=\"state\"><span>Active</span></p>"
  out="$(_parity "$d" sign-in /sign-in/)"
  [[ "$out" != NO-RESULT ]] && ! grep -q 'field-email.* badge ' <<<"$out" \
    && ok ch_034a "a mockup's box around a text field, drawn by the app as the library's input, is no pill finding" \
    || bad ch_034a "the field box was read as a pill: $(grep -m2 'field-email' <<<"$out" | tr '\n' '|' | cut -c1-240)"
  grep -qE '^1280 state > span\[0\] (badge|missing) ' <<<"$out" \
    && ok ch_034b "a real status pill the app draws as plain text is still reported" \
    || bad ch_034b "the flattened pill was lost: $(tr '\n' '|' <<<"$out" | cut -c1-240)"
}

# --- TrStudio TF-002: a gradient button read "neutral, plain", the same button drawn solid "accent, pill" --------
# The fill was read from background-color alone, and a gradient is a background-image: the mockup's brand button
# had "no fill". The gradient's colour stops are measured and their mean is the fill, on both sides.
ts_002() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ts_002 — needs playwright\n'; return; }
  local d="$SCRATCH/ts002" out g='border:0;border-radius:999px;height:40px;padding:0 16px;font:inherit;color:#fff'
  _pages "$d" forgot "<p><button data-testid=\"btn-send\" style=\"background:linear-gradient(135deg,#6366f1,#a855f7);$g\">Send reset link</button> <button data-testid=\"btn-cancel\" style=\"background:linear-gradient(#e5e7eb,#d1d5db);$g;color:#111\">Cancel</button></p>" \
                     "<p><button data-testid=\"btn-send\" style=\"background:#6366f1 linear-gradient(135deg,#6366f1,#a855f7);$g\">Send reset link</button> <button data-testid=\"btn-cancel\" style=\"background:#dc2626;$g\">Cancel</button></p>"
  out="$(_parity "$d" forgot /forgot/)"
  [[ "$out" != NO-RESULT ]] && ! grep -q ' btn-send ' <<<"$out" \
    && ok ts_002a "a button filled with the brand gradient on both sides is one colour and one shape: no finding" \
    || bad ts_002a "the gradient button was read differently on the two sides: $(grep ' btn-send ' <<<"$out" | tr '\n' '|' | cut -c1-240)"
  grep -q '^1280 btn-cancel color ' <<<"$out" \
    && ok ts_002b "a grey gradient in the mockup against a solid red in the app is still a colour finding" \
    || bad ts_002b "a real colour difference behind a gradient was lost: $(tr '\n' '|' <<<"$out" | cut -c1-240)"
}

# --- Chatur TF-034, the table: "0 rows move" where 17 screens moved ----------------------------------------
# measure-projects.py replays the grading step over the records the project's last verify saved, which the
# OLD mockup check wrote: a rule changed in that check can show nothing there. A row with a screen now reads
# "not measured" when a script that measures screens differs, and the cell says how many rows that verify covered.
measure_rows() {
  local d="$SCRATCH/measure" out tool="${TF_MEASURE:-$ROOT/scripts/measure-projects.py}" row
  mkdir -p "$d/Fx/docs" "$d/Fx/tests/.artifacts/verify"; cp -r "$ROOT/.tfcore" "$d/Fx/.tfcore"; rm -rf "$d/Fx/.tfcore/.session"
  printf '# Fx — Checklist\n\n| ID | Requirement | Status |\n|---|---|---|\n| REQ-UI-001 | Sign in screen | Verified |\n| REQ-FN-002 | A rule with no screen | Verified |\n| REQ-FN-003 | Outside the last verify | Verified |\n' > "$d/Fx/docs/Fx-Checklist.md"
  printf '{"app":"Fx","scope":"all","phase":1,"rows":[{"id":"REQ-UI-001","screen":"Sign in","route":"/sign-in"},{"id":"REQ-FN-002","screen":""}]}\n' > "$d/Fx/tests/.artifacts/verify/list.json"
  printf '{"app":"Fx","scope":"all","phase":1,"date":"2026-11-14","rows":[{"id":"REQ-UI-001","verdict":"PASS","status":"Verified"},{"id":"REQ-FN-002","verdict":"PASS","status":"Verified"}]}\n' > "$d/Fx/tests/.artifacts/verify/verdicts.json"
  printf '\n// the mockup check this project runs today: one rule older\n' >> "$d/Fx/.tfcore/utils/tf-mockup-parity.mjs"
  out="$(python3 "$tool" --base deployed --roots "$d" 2>/dev/null)"; row="$(grep '^| Fx |' <<<"$out")"
  grep -q '| not measured for 1 row(s) with a screen; 0 of 1 without one (the last verify covered 2 of the project.s 3 rows; the others are not measured) |' <<<"$row" \
    && ok measure_rows_a "a project whose mockup check differs: its row with a screen reads \"not measured\", never 0, and the cell says the last verify covered 2 of 3 rows" \
    || bad measure_rows_a "the table claims a measurement it did not make: ${row:0:260}"
  cp "$ROOT/.tfcore/utils/tf-mockup-parity.mjs" "$d/Fx/.tfcore/utils/"; printf '\n# the same checks, another build script\n' >> "$d/Fx/.tfcore/utils/tf-doc-tests.sh"
  row="$(python3 "$tool" --base deployed --roots "$d" 2>/dev/null | grep '^| Fx |')"
  grep -q '^| Fx | 1 | 0 of 2 (the last verify covered 2 of' <<<"$row" \
    && ok measure_rows_b "with no screen-measuring script changed, the same rows are measured and counted: 0 of 2" \
    || bad measure_rows_b "rows that could be measured were not: ${row:0:260}"
}

# --- TrStudio TF-001: the Mac boot missed "Automation Mode asks for a password" and named the wrong fix -----
# macOS 27.2 prints "This device requires user authentication" in small letters; the boot script matched only
# the capitals of macOS 26, so it built the app, the driver's helper stopped (xcodebuild code 65) and the
# reason pointed at Accessibility. The checks moved to tf-mac-host-check.sh, which reads the tools on PATH,
# so stand-in tools prove it on any machine; the boot itself runs only on a Mac (tests/regression lk_026).
ts_001() {
  local d="$SCRATCH/ts001" o1 o2 o3 o4 rc1 rc2 hc="$UTILS/tf-mac-host-check.sh" want='sudo automationmodetool enable-automationmode-without-authentication'
  mkdir -p "$d/bin"; printf '#!/bin/sh\necho "Automation Mode is disabled."\necho "This device requires user authentication to enable Automation Mode."\n' > "$d/bin/automationmodetool"
  printf '#!/bin/sh\necho "{\\"mac2\\": {\\"version\\": \\"4.1.2\\"}}"\n' > "$d/bin/appium"; printf '#!/bin/sh\necho "Xcode 27.2"\n' > "$d/bin/xcodebuild"; chmod +x "$d/bin/"*
  o1="$(PATH="$d/bin:$PATH" bash "$hc" 2>&1)"; rc1=$?
  printf 'Timed out while enabling automation mode.\n' > "$d/appium.log"
  o2="$(bash "$hc" --session "xcodebuild failed with code 65" session "$d/appium.log" 2>&1)"
  local at build; at="$(grep -n 'tf-mac-host-check.sh")" || mac_none' "$UTILS/tf-verify-boot.sh" | head -1 | cut -d: -f1)"; build="$(grep -n 'nohup appium ' "$UTILS/tf-verify-boot.sh" | head -1 | cut -d: -f1)"
  [[ $rc1 -eq 1 && "$o1" == "macOS asks for a password before Automation Mode comes on"*"$want" && "$o2" == "; run once, with an administrator password: $want" && -n "$at" && "$at" -lt "${build:-0}" ]] \
    && ok ts_001a "Automation Mode behind a password, as macOS 27.2 words it, stops the boot before the driver is started, with the one-time command; a helper that timed out enabling it gets the same fix" \
    || bad ts_001a "the password check was missed or the wrong fix named: exit $rc1 [${o1:0:140}] [${o2:0:140}] (check at line ${at:-none}, driver started at ${build:-none})"
  printf '#!/bin/sh\necho "This device does not require user authentication to enable Automation Mode."\n' > "$d/bin/automationmodetool"
  o3="$(PATH="$d/bin:$PATH" bash "$hc" 2>&1)"; rc2=$?
  printf '#!/bin/sh\necho "{\\"mac2\\": {\\"version\\": \\"4.0.4\\"}}"\n' > "$d/bin/appium"
  o4="$(PATH="$d/bin:$PATH" bash "$hc" 2>&1)"; o2="$(bash "$hc" --session "xcodebuild failed with code 65" session "$d/none.log" 2>&1)"
  [[ $rc2 -eq 0 && -z "$o3" && "$o4" == "the mac2 driver 4.0.4 cannot build its helper with Xcode 27"*"appium driver uninstall mac2; appium driver install mac2" && "$o2" == *"cannot build its helper"* ]] \
    && ok ts_001b "a Mac that needs no password passes the check; a driver too old for Xcode 27, and a helper that fails to build for another reason, still name the reinstall" \
    || bad ts_001b "exit $rc2 [${o3:0:100}] [${o4:0:140}] [${o2:0:100}]"
}

# --- Chatur TF-035, Lekhak TF-045: both checks measured a screen before its content arrived ------------------
# The screen check waited for any one control, and a tab screen's mockup names the window around it too, drawn
# at once; the mockup check did not wait. One rule now (tf-login.mjs waitLoaded): half of the screen's controls
# on the page, no loading sign, the count quiet for 300 ms; up to --render-wait, once more while a loading sign
# shows. Fixture: tests/faults/loading/make.sh (content after 3.2 s; "Loading board…" for good; nothing; no icons).
ch_035() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_035 — needs playwright\n'; return; }
  local d="$SCRATCH/ch035" port srv sc pa a="--screen board=/board/ --screen never=/never/ --screen broken=/broken/ --screen plain=/plain/ --widths 1280 --themes light --render-wait 4500 --mockups docs/mockups"
  bash "$ROOT/tests/faults/loading/make.sh" "$d"
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"; cp "$UTILS"/tf-*.mjs "$d/"
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d" && tf_timeout 200 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" $a --no-menus --json-out "$d/s.json" --shots-dir "$d/shots" > "$d/s.log" 2>&1
    tf_timeout 200 node tf-mockup-parity.mjs --base "http://127.0.0.1:$port" $a --json-out "$d/p.json" > "$d/p.log" 2>&1 )
  kill "$srv" 2>/dev/null
  sc="$(python3 -c "
import json
for s in json.load(open('$d/s.json'))['screens']: print(s['name'], s['render'], 'still-loading' if 'still loading after' in json.dumps(s) else '-')" 2>&1 | paste -s -d ' ' -)"
  pa="$(python3 -c "
import json
for s in json.load(open('$d/p.json'))['screens']: print(s['screen'], s['verdict'], 'still-loading' if 'still loading after' in json.dumps(s) else '-')" 2>&1 | paste -s -d ' ' -)"
  [[ "$sc" == "board OK - "* && "$pa" == "board PASS - "* ]] \
    && ok ch_035a "a tab screen whose content arrives 3 s after the window's frame is waited for by both checks: render OK, mockup PASS" \
    || bad ch_035a "the screen was measured before its content: screen check «$sc» // mockup check «$pa»"
  [[ "$sc" == *" never EMPTY still-loading "* && "$pa" == *" never NOT-MEASURED still-loading "* ]] \
    && ok ch_035b "a screen still showing \"Loading board…\" when the wait ends is not compared with the mockup (not measured), and the screen check's finding says it was still loading" \
    || bad ch_035b "a screen that never left its loading sign: screen check «$sc» // mockup check «$pa»"
  [[ "$sc" == *" broken EMPTY - plain OK -" && "$pa" == *" plain FAIL -" ]] \
    && ok ch_035c "a screen that never draws its content and shows no loading sign is still EMPTY; a loaded screen missing its mockup's icons still fails the mockup check" \
    || bad ch_035c "a real finding was lost: screen check «$sc» // mockup check «$pa»"
}

# --- Chatur TF-029, Sevak TF-037: a test filter "A|B" was cut by the Windows shells ------------------------
# tf-build.sh joined the extra arguments into one string for cmd.exe, winrun and PowerShell, which read the
# `|` as a pipe ("'B' is not recognized ..."), so a MAUI tree's test run stopped NOT-RUN and a tree with a WSL
# rung fell to it, whose restore left obj/ with Linux paths and broke the next Windows build (NETSDK1064).
# The stand-in shells below cut at an unescaped | (cmd.exe) or one outside single quotes (PowerShell), as the
# real ones do (both proved on this machine's own cmd.exe and powershell.exe on 2026-11-14).
_win_stubs() {   # <dir>: cmd.exe, winrun, powershell.exe that run "dotnet …" the way those shells parse it
  mkdir -p "$1/bin" "$1/home/.dotnet"
  cat > "$1/bin/fx-dotnet" <<'SH'
#!/usr/bin/env bash
# @file is read one argument a line, as dotnet reads it; a third bare word is a second project (MSB1008)
a=(); for x in "$@"; do if [[ "$x" == @* && -f "${x#@}" ]]; then while IFS= read -r l; do a+=("$l"); done < "${x#@}"; else a+=("$x"); fi; done
set -- "${a[@]}"; printf '%s\n' "$*" >> "$TF_FX_DIR/received"
n=0; p=""; for x in "$@"; do [[ "$p" == --filter || "$x" == -* ]] || n=$((n+1)); p="$x"; done
[[ $n -gt 2 || -n "${TF_FX_REFUSE:-}" ]] && { echo "MSBUILD : error MSB1008: Only one project can be specified."; exit 1; }
case "$*" in *Broken*) echo "Failed!  - Failed: 1, Passed: 0"; exit 1 ;; esac
echo "Passed!  - Failed: 0, Passed: 2"; exit 0
SH
  cat > "$1/bin/cmd.exe" <<'SH'
#!/usr/bin/env bash
[[ "$1" == /c ]] && shift
s="$*"; plain="${s//^|/}"
if [[ "$plain" == *"|"* ]]; then w="${plain#*|}"; echo "'${w%% *}' is not recognized as an internal or external command,"; exit 255; fi
s="${s//^|/|}"; s="${s//^&/&}"; s="${s//^</<}"; s="${s//^>/>}"; s="${s//^^/^}"
set -f; set -- ${s#dotnet }; exec "$(dirname "$0")/fx-dotnet" "$@"
SH
  cat > "$1/bin/powershell.exe" <<'SH'
#!/usr/bin/env bash
[[ "$1" == -Command ]] && shift
s="$*"; out="$(printf '%s' "$s" | sed "s/'[^']*'//g")"
if [[ "$out" == *"|"* ]]; then w="${out#*|}"; echo "${w%% *} : The term '${w%% *}' is not recognized as the name of a cmdlet"; exit 1; fi
s="${s//\'/}"; set -f; set -- ${s#dotnet }; exec "$(dirname "$0")/fx-dotnet" "$@"
SH
  cp "$1/bin/powershell.exe" "$1/bin/winrun"
  chmod +x "$1/bin/"*
}
ch_029() {
  local d="$SCRATCH/ch029" out rcv
  mkdir -p "$d/m/obj"; _win_stubs "$d"
  printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><UseMaui>true</UseMaui></PropertyGroup></Project>\n' > "$d/m/Fx.Tests.csproj"
  _b() { ( cd "$d" && TF_FX_DIR="$d" HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" TF_BUILD_PLATFORM=wsl TF_BUILD_LOCK_WAIT=0 bash "$UTILS/tf-build.sh" "$@" 2>&1 ); }
  : > "$d/received"; out="$(_b test m/Fx.Tests.csproj -- --filter "DisplayName~REQ-FN-018|DisplayName~REQ-FN-019")"
  rcv="$(head -1 "$d/received")"
  grep -q '^PASS  test on wsl via cmd.exe /c dotnet (rung 1)' <<<"$out" && [[ "$rcv" == "test m/Fx.Tests.csproj --filter DisplayName~REQ-FN-018|DisplayName~REQ-FN-019" ]] \
    && ok ch_029a "a filter joining two names with | reaches dotnet whole on the cmd.exe rung, and the run passes there" \
    || bad ch_029a "the filter was cut: $(grep -m1 -E '^(PASS|FAIL|NOT-RUN)' <<<"$out" | cut -c1-160) // received: ${rcv:-nothing}"
  : > "$d/received"; out="$(TF_BUILD_SIDE=windows _b test m/Fx.Tests.csproj -- --filter "DisplayName~REQ-UI-0|DisplayName~Broken")"
  grep -q '^FAIL  tests failed on wsl via cmd.exe' <<<"$out" \
    && ok ch_029b "a failing test behind the same filter is still a FAIL on the Windows rung" \
    || bad ch_029b "a real test failure was not reported: $(grep -m1 -E '^(PASS|FAIL|NOT-RUN)' <<<"$out" | cut -c1-160)"
  # a tree the Windows side built last, whose Windows rungs fail as wrong ones: the WSL rung passes and leaves
  # no Linux-path restore files behind for the next Windows build
  local e="$d/w"; mkdir -p "$e/obj"; echo windows > "$e/obj/.tf-build-side"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$e/Fx.csproj"
  printf '#!/usr/bin/env bash\necho "error NETSDK1178: wrong rung"; exit 1\n' > "$d/bin/cmd.exe"; cp "$d/bin/cmd.exe" "$d/bin/winrun"; cp "$d/bin/cmd.exe" "$d/bin/powershell.exe"
  printf '#!/usr/bin/env bash\nmkdir -p w/obj; echo "{\\"packageFolders\\":{\\"/home/u/.nuget/packages/\\":{}}}" > w/obj/project.assets.json; : > w/obj/Fx.csproj.nuget.g.props\necho "Build succeeded."; exit 0\n' > "$d/bin/dotnet"
  chmod +x "$d/bin/"*
  out="$(_b build w/Fx.csproj)"
  grep -q '^PASS  build on wsl via dotnet' <<<"$out" && [[ ! -e "$e/obj/project.assets.json" && ! -e "$e/obj/Fx.csproj.nuget.g.props" ]] \
    && ok ch_029c "a WSL rung on a tree the Windows side builds passes and removes the restore files it wrote with Linux paths" \
    || bad ch_029c "the WSL rung left its restore files for the Windows side: $(grep -m1 -E '^(PASS|FAIL|NOT-RUN)' <<<"$out" | cut -c1-120) // $(ls "$e/obj" | tr '\n' ' ')"
}

# --- Lekhak TF-044: cmd.exe split a test filter at its space, and the refused run went on to the next rung ----
# "DisplayName~REQ-RAG-114 TestDbChapterOne" reached dotnet as a filter and a second project (MSB1008). The
# script Lekhak had then tried winrun and PowerShell, which cut the command at the `;` of the logger argument
# and ran `dotnet test <solution>`: every test, the paid real-model ones included, twice (reproduced on this
# machine's cmd.exe and powershell.exe with dotnet 10 on 2026-11-15). The stand-in cmd.exe splits at a space
# as the real one does; the stand-in dotnet reads @file a line an argument and refuses a second project.
lk_044() {
  local d="$SCRATCH/lk044" out f n=0 rc
  mkdir -p "$d/m"; _win_stubs "$d"
  printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><UseMaui>true</UseMaui></PropertyGroup></Project>\n' > "$d/m/Fx.Tests.csproj"
  _b() { ( cd "$d" && TF_FX_DIR="$d" HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" TF_BUILD_PLATFORM=wsl TF_BUILD_LOCK_WAIT=0 "$@" 2>&1 ); }
  while IFS= read -r f; do
    : > "$d/received"; out="$(_b bash "$UTILS/tf-build.sh" test m/Fx.Tests.csproj -- --filter "$f")"
    [[ "$(cat "$d/received")" == "test m/Fx.Tests.csproj --filter ${f//\"/%22}" ]] && grep -q '^PASS  test on wsl via cmd.exe /c dotnet (rung 1)' <<<"$out" \
      || { n=$((n+1)); note "filter «$f»: $(grep -m1 -E '^(PASS|FAIL|NOT-RUN)' <<<"$out" | cut -c1-110) // dotnet received: $(paste -s -d '/' "$d/received")"; }
  done <<'EOF'
DisplayName~REQ-RAG-114 TestDbChapterOne
DisplayName~REQ-RAG-114 TestDbChapterOne|DisplayName~REQ-RAG-115 TestDbChapterTwo
DisplayName~Says "hi" it's
FullyQualifiedName~Fx.Tests.Chapter One & Two
EOF
  [[ $n -eq 0 ]] && ok lk_044a "a filter holding a space, a |, quotes or a ~ reaches dotnet as one argument on the cmd.exe rung, through a file" \
                 || bad lk_044a "$n of 4 filters did not reach dotnet whole on the first rung"
  # dotnet refuses the arguments: one FAIL line, one rung, and the test step says nothing ran
  : > "$d/received"; out="$(_b bash "$UTILS/tf-build.sh" test m/Fx.Tests.csproj -- Other.csproj)"
  grep -q '^FAIL  dotnet refused its arguments on cmd.exe /c dotnet (rung 1): MSBUILD : error MSB1008' <<<"$out" && [[ "$(grep -c . "$d/received")" == 1 ]] \
    && ok lk_044b "arguments dotnet refuses are one FAIL line naming MSB1008, and no other rung is started" \
    || bad lk_044b "a refused run went on: $(grep -m1 -E '^(PASS|FAIL|NOT-RUN)' <<<"$out" | cut -c1-120) // dotnet was started $(grep -c . "$d/received") time(s)"
  : > "$d/received"; out="$(TF_FX_REFUSE=1 _b bash "$UTILS/tf-verify-tests.sh" --target m/Fx.Tests.csproj --filter "DisplayName~REQ-RAG-114 TestDbChapterOne")"; rc=$?
  grep -q '^unit tests: FAIL  dotnet refused its arguments' <<<"$out" && [[ $rc -eq 2 && "$(grep -c . "$d/received")" == 1 ]] && ! grep -qv -- '--filter' "$d/received" \
    && ok lk_044c "tf-verify-tests.sh prints FAIL and exits 2 when dotnet refuses the filter; nothing runs without the filter" \
    || bad lk_044c "the test step (exit $rc) said: $(grep -m1 '^unit tests' <<<"$out" | cut -c1-120) // dotnet was started $(grep -c . "$d/received") time(s)"
  # control: a failing test behind a filter with a space is still a test failure; a wrong rung still moves on
  out="$(_b bash "$UTILS/tf-build.sh" test m/Fx.Tests.csproj -- --filter "DisplayName~Broken one")"
  printf '#!/usr/bin/env bash\necho "error NETSDK1178: wrong rung"; exit 1\n' > "$d/bin/cmd.exe"
  f="$(_b bash "$UTILS/tf-build.sh" test m/Fx.Tests.csproj -- --filter "DisplayName~REQ-RAG-114 TestDbChapterOne")"
  grep -q '^FAIL  tests failed on wsl via cmd.exe' <<<"$out" && grep -q '^PASS  test on wsl via winrun dotnet (rung 2)' <<<"$f" \
    && ok lk_044d "a failing test behind such a filter is still FAIL, and a wrong rung still hands the same file to the next one" \
    || bad lk_044d "$(grep -m1 -E '^(PASS|FAIL|NOT-RUN)' <<<"$out" | cut -c1-100) // $(grep -m1 -E '^(PASS|FAIL|NOT-RUN)' <<<"$f" | cut -c1-100)"
}

# --- Sevak TF-036: a miss logged with the wrong class could not be corrected ------------------------------
# MISS-Sevak-20261113-05 was logged `regression` (a test that failed on a right app: wrong-behaviour) because
# the duplicate check would have folded it into the open wrong-behaviour miss on the row. `--amend` refused
# miss_class outright. A correction with a reason now replaces it; the report, the readable list and the
# duplicate check read the corrected class. A plain amend, a value outside the vocabulary, or clearing it
# with `none` is still refused.
sv_036() {
  local d="$SCRATCH/sv036" o1 o2 o3 o4 r om
  _mfx "$d"
  printf '%s\n' '{"v":1,"kind":"miss","miss_id":"MISS-Fx-20261113-05","app":"Fx","req_id":"REQ-UI-089","miss_class":"regression","artifact":"tests","severity":"minor","found_by":"owner","ts":"2026-11-13T09:00:00Z"}' >> "$d/docs/metrics/misses.jsonl"
  em() { ( cd "$d" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d" bash .tfcore/utils/tf-emit.sh "$@" 2>&1 ); }
  o1="$(em --amend MISS-Fx-20261113-05 miss_class wrong-behaviour "a test that failed on a right app is a wrong behaviour of the test, never a regression")"
  om="$(em --open-miss REQ-UI-089 wrong-behaviour)"
  r="$(cd "$d" && python3 .tfcore/utils/tf-misses-md.py --root "$d" --app Fx --quiet >/dev/null 2>&1; grep 'MISS-Fx-20261113-05' "$d/docs/Fx-Misses.md" 2>/dev/null | head -1)"
  [[ "$o1" == *"corrected MISS-Fx-20261113-05"* && "$om" == "MISS-Fx-20261113-05 wrong-behaviour" && "$r" == *wrong-behaviour* ]] \
    && ok sv_036a "a wrong class is corrected with a reason; the duplicate check and the readable list read the new class" \
    || bad sv_036a "the class could not be corrected: [$(cut -c1-140 <<<"$o1")] open-miss=[$om] md=[${r:0:120}]"
  o2="$(em --amend MISS-Fx-20261113-05 miss_class missed-requirement)"
  o3="$(em --amend MISS-Fx-20261113-05 miss_class none "nobody knows")"
  o4="$(em --amend MISS-Fx-20261113-05 miss_class flaky "made up")"
  [[ "$o2" == *"amend refused"* && "$o3" == *"amend refused"* && "$o4" == *"amend refused"* ]] && [[ "$(grep -c '"field":"miss_class"' "$d/docs/metrics/misses.jsonl")" == 1 ]] \
    && ok sv_036b "a class amend without a reason, one clearing the class, and one outside the vocabulary are still refused" \
    || bad sv_036b "a class amend that should be refused was written: [$o2] [$o3] [$o4]"
}

# --- the dropdown check on the pages of 14 Nov (Chatur TF-031, Lekhak TF-041, Sevak TF-038) ----------------
# _screens <dir> <screen>: the screen check over <dir>/site/<screen>/ against docs/mockups/<screen>.html at
# 1280 and 390, light only; prints one line per finding (<width> <class> <detail>) and the screen's
# `DD opened=<n> not_reached=<ids>` line from its JSON.
_screens() {
  local d="$1" port srv
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"
  cp "$UTILS/tf-login.mjs" "$UTILS/tf-theme.mjs" "$UTILS/tf-menus.mjs" "$UTILS/tf-verify-screens.mjs" $(ls "$UTILS/tf-dropdowns.mjs" 2>/dev/null) "$d/"
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d" && tf_timeout 300 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen "$2=/$2/" --widths 1280,390 --themes light \
      --render-wait 500 --wait 300 --no-menus --json-out "$d/s.json" --shots-dir "$d/shots" > "$d/s.log" 2>&1 )
  kill "$srv" 2>/dev/null
  python3 -c "
import json
for s in json.load(open('$d/s.json'))['screens']:
    for w in s['widths']:
        for f in w['findings']: print(w.get('width'), f['class'], f['detail'][:150])
    dd = s.get('dropdowns')
    print('DD', 'opened=%s' % (dd or {}).get('opened', '-'), 'not_reached=%s' % ','.join((dd or {}).get('not_reached', [])))" 2>&1
}
_ddpage() {   # <dir> <screen> <mockup body> <app body>: the pages, with a script that opens and closes lists
  local js='<script>function tg(b){var l=document.getElementById(b.getAttribute("aria-controls"));var o=!l.classList.contains("open");document.querySelectorAll(".open").forEach(function(x){if(x.getAttribute("role")!=="dialog")x.classList.remove("open")});if(o)l.classList.add("open");b.setAttribute("aria-expanded",o)}document.addEventListener("keydown",function(e){if(e.key==="Escape"){var x=document.querySelector("[role=listbox].open,[role=menu].open");if(x)x.classList.remove("open");else document.querySelectorAll("[role=dialog].open").forEach(function(d){d.classList.remove("open")})}})</script>'
  local css='<style>body{margin:0;font:14px/20px system-ui;padding:16px} .pick{position:relative;display:block;width:max-content;margin:0 0 40px 0} [role=listbox],[role=menu]{position:absolute;top:36px;left:0;background:#fff;border:1px solid #ccc;display:none} .open{display:block!important} [role=option],[role=menuitem]{padding:4px 8px} [role=dialog]{display:none;position:fixed;top:40px;left:40px;background:#fff;border:1px solid #888;padding:16px;width:300px}</style>'
  mkdir -p "$1/docs/mockups" "$1/site/$2"
  printf '<!doctype html><html><head><meta charset="utf-8"></head><body><h1>Screen</h1>%s</body></html>\n' "$3" > "$1/docs/mockups/$2.html"
  printf '<!doctype html><html><head><meta charset="utf-8">%s</head><body><h1>Screen</h1>%s%s</body></html>\n' "$css" "$4" "$js" > "$1/site/$2/index.html"
}
_dd() { printf '<div class="pick" data-testid="%s"><button role="combobox" aria-controls="%s-l" aria-expanded="false" onclick="tg(this)">%s</button><div role="listbox" id="%s-l" style="width:%s">%s</div></div>' "$1" "$1" "$1" "$1" "$2" "$3"; }

# Chatur TF-031: every tier option wrapped onto two lines in a 160 px list; a project picker built as a menu
# (aria-haspopup="menu") ran past the window and was never opened. A wrapped option in a list narrower than
# the window, and a menu-built picker, are graded now, and the screen says how many lists it opened.
ch_031() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_031 — needs playwright\n'; return; }
  local d="$SCRATCH/ch031" out items="" i
  for ((i = 1; i <= 50; i++)); do items+="<div role=\"menuitem\">Project $i</div>"; done
  local o='<div role="option">Tier 1 — the strongest model you have</div><div role="option">Tier 2 — a strong and cheaper model</div>'
  _ddpage "$d" routing '<div data-testid="analyst-tier">a</div><div data-testid="start-project">p</div><div data-testid="two-line">t</div><div data-testid="cut-pick">c</div>' \
    "$(_dd analyst-tier 160px "$o")<div class=\"pick\" data-testid=\"start-project\"><button aria-haspopup=\"menu\" aria-controls=\"pm\" onclick=\"tg(this)\">Project</button><div role=\"menu\" id=\"pm\" style=\"width:200px\">$items</div></div>$(_dd two-line 200px '<div role="option"><div>Tier 1</div><div>the strongest model</div></div>')$(_dd cut-pick 60px '<div role="option" style="white-space:nowrap;overflow:hidden">techierathore/TechieFlow</div>')"
  out="$(_screens "$d" routing)"
  grep -qE '^1280 clipped the list of "analyst-tier" is too narrow: 2 of 2 option\(s\) wrap' <<<"$out" && grep -qE '^390 clipped the list of "analyst-tier" is too narrow' <<<"$out" \
    && grep -qE '^1280 offscreen the list of "start-project" opens outside the window' <<<"$out" && grep -q '^DD opened=8 ' <<<"$out" && ! grep -q '"two-line"' <<<"$out" \
    && ok ch_031a "a list whose options wrap and a menu-built picker past the window are reported; 8 lists opened over two widths is said; a label over a description is no wrap" \
    || bad ch_031a "a wrapped list or a menu picker passed, or the count is missing: $(tr '\n' '|' <<<"$out" | cut -c1-360)"
  grep -qE '^1280 clipped the list of "cut-pick" cuts 1 option' <<<"$out" \
    && ok ch_031b "a list that cuts its option short is still reported" \
    || bad ch_031b "the cut list finding was lost: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# Lekhak TF-041: a closed native select 144 px wide read "Moderate (Sensual" and passed; selects were left out.
lk_041() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: lk_041 — needs playwright\n'; return; }
  local d="$SCRATCH/lk041" out
  _ddpage "$d" studio '<div data-testid="content-type">c</div><div data-testid="wide-type">w</div><div data-testid="cut-pick">p</div>' \
    "<label data-testid=\"content-type\">Content Type <select style=\"width:144px;font:16px serif\"><option>Mild (Romantic)</option><option selected>Moderate (Sensual)</option><option>Explicit (Adult)</option></select></label> <label data-testid=\"wide-type\">Kind <select style=\"width:260px;font:16px serif\"><option>Short</option><option>Long</option></select></label>$(_dd cut-pick 60px '<div role="option" style="white-space:nowrap;overflow:hidden">techierathore/TechieFlow</div>')"
  out="$(_screens "$d" studio)"
  grep -qE '^1280 clipped the select "content-type" cuts its text at 1280px: "Moderate \(Sensual\)" needs' <<<"$out" && grep -qE '^390 clipped the select "content-type"' <<<"$out" && ! grep -q '"wide-type"' <<<"$out" \
    && ok lk_041a "a closed select narrower than its longest option is reported at both widths; one that fits is not" \
    || bad lk_041a "the cut select passed: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  grep -qE '^1280 clipped the list of "cut-pick" cuts 1 option' <<<"$out" \
    && ok lk_041b "a list that cuts its option short is still reported beside it" \
    || bad lk_041b "the cut list finding was lost: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# Sevak TF-038: the New issue dialog's pickers appear only after support-new-issue is clicked, and the check
# collected its triggers once, before anything was clicked. A dialog trigger's dialog is opened and its pickers
# graded; a picker the mockup draws inside another state that no click reached is named, not passed silently.
sv_038() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_038 — needs playwright\n'; return; }
  local d="$SCRATCH/sv038" out
  _ddpage "$d" support '<div data-testid="support-status-filter">s</div><button data-testid="support-new-issue">New issue</button><div data-tf-state="dialog"><select data-testid="issue-type"><option>Bug</option></select></div><div data-tf-state="other-dialog"><select data-testid="issue-owner"><option>Me</option></select></div>' \
    "$(_dd support-status-filter 200px '<div role="option">Open</div>')<button data-testid=\"support-new-issue\" aria-haspopup=\"dialog\" aria-controls=\"dlg\" onclick=\"document.getElementById('dlg').classList.add('open')\">New issue</button><div role=\"dialog\" id=\"dlg\">$(_dd issue-type 60px '<div role="option" style="white-space:nowrap;overflow:hidden">A long option text that cannot fit</div>')</div><button onclick=\"1\">Assign</button>"
  out="$(_screens "$d" support)"
  grep -qE '^1280 clipped the list of "issue-type" cuts 1 option\(s\) short in the dialog "support-new-issue" at 1280px' <<<"$out" && grep -qE '^390 clipped the list of "issue-type"' <<<"$out" \
    && grep -q '^DD .*not_reached=issue-owner (other-dialog)$' <<<"$out" \
    && ok sv_038a "a picker inside a dialog is opened through its trigger and its cut list reported; a mockup picker in a state no click reached is named" \
    || bad sv_038a "a dialog's picker was never opened, or the unreached one not named: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  ! grep -q 'support-status-filter' <<<"$out" && grep -qE '^DD opened=[1-9]' <<<"$out" \
    && ok sv_038b "the first-view picker whose list fits is still opened and passes" \
    || bad sv_038b "the first-view picker was not opened or failed: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- Lekhak TF-040: on a desktop head over CDP, "Blazor has already started" failed the first screen measured --
# Whichever screen a run opened first failed "render ERROR", at its first width only, and passed when opened
# again; the fixture logs the error once, on the first route change, as the head did (its cause there is not
# known: a message replayed on attaching, Lekhak's guess, is not reproduced by stock Chromium). And a screen still
# drawing its data ("Loading …") when measured was EMPTY. A screen failed on console errors alone is now opened
# once more and charged only the errors that come back; an EMPTY screen on a desktop head is measured once more
# after a wait. An error a screen logs each time it opens, and a screen that never draws, still fail.
lk_040() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: lk_040 — needs playwright\n'; return; }
  local d="$SCRATCH/lk040" port cport exe srv br out s
  mkdir -p "$d/docs/mockups" "$d/site"
  for s in one slow never bad; do printf '<!doctype html><html><body><div data-testid="%s-box">%s</div></body></html>\n' "$s" "$s" > "$d/docs/mockups/$s.html"; done
  cat > "$d/site/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{font:14px system-ui}</style></head><body><div id="root"></div><script>
console.error('Blazor has already started.');
var started=false;
function draw(){var r=document.getElementById('root'),p=location.pathname;
 if(!started&&p!=='/'){started=true;console.error('Blazor has already started.');}
 if(p==='/one')r.innerHTML='<div data-testid="one-box">One</div>';
 else if(p==='/slow'){r.innerHTML='<div data-testid="slow-box"></div>';setTimeout(function(){var b=document.querySelector('[data-testid=slow-box]');if(b)b.textContent='Loaded';},2500);}
 else if(p==='/never')r.innerHTML='<div data-testid="never-box"></div>';
 else if(p==='/bad'){r.innerHTML='<div data-testid="bad-box">Bad</div>';console.error('a real error on this screen');}
 else r.innerHTML='<p>Home</p>';}
addEventListener('popstate',draw);draw();
</script></body></html>
HTML
  printf 'import http.server,sys\nclass H(http.server.SimpleHTTPRequestHandler):\n    def log_message(self,*a): pass\n    def translate_path(self,p): return sys.argv[2]\nhttp.server.ThreadingHTTPServer(("127.0.0.1",int(sys.argv[1])),H).serve_forever()\n' > "$d/serve.py"
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"
  cp "$UTILS/tf-login.mjs" "$UTILS/tf-theme.mjs" "$UTILS/tf-menus.mjs" "$UTILS/tf-verify-screens.mjs" "$d/"
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  cport="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 "$d/serve.py" "$port" "$d/site/index.html" >/dev/null 2>&1 & srv=$!
  exe="$(cd "$d" && node -e "import('playwright').then(p=>console.log(p.chromium.executablePath()))" 2>/dev/null)"
  "$exe" --headless=new --no-sandbox --remote-debugging-port="$cport" --user-data-dir="$d/profile" "http://127.0.0.1:$port/" >/dev/null 2>&1 & br=$!
  local i=0; while [[ $i -lt 30 ]] && ! curl -s -m 2 "http://127.0.0.1:$cport/json/version" | grep -q webSocketDebuggerUrl; do sleep 1; i=$((i+1)); done
  sleep 2
  ( cd "$d" && tf_timeout 300 node tf-verify-screens.mjs --cdp "http://127.0.0.1:$cport" --mockups docs/mockups --screen one=/one --screen slow=/slow --screen never=/never --screen bad=/bad \
      --widths 1280,390 --themes light --render-wait 1500 --no-menus --json-out "$d/s.json" --shots-dir "$d/shots" > "$d/s.log" 2>&1 )
  kill "$br" "$srv" 2>/dev/null; wait "$br" 2>/dev/null
  out="$(python3 -c "
import json
for s in json.load(open('$d/s.json'))['screens']: print(s['name'], s['render'], ' '.join(sorted({e for w in s['widths'] for e in w.get('console_errors', [])})))" 2>&1)"
  grep -q '^one OK' <<<"$out" && grep -q '^slow OK' <<<"$out" && ! grep -q 'already started' <<<"$out" \
    && ok lk_040a "an error logged once, on the run's first screen only, fails no screen; a screen still loading is measured again before it is called EMPTY" \
    || bad lk_040a "the first screen took a replayed error, or a loading screen failed: $(tr '\n' '|' <<<"$out" | cut -c1-260)"
  grep -q '^never EMPTY' <<<"$out" && grep -q '^bad ERROR a real error on this screen' <<<"$out" \
    && ok lk_040b "a screen that never draws is still EMPTY, and an error logged while a screen is open still fails it" \
    || bad lk_040b "a real render failure was lost: $(tr '\n' '|' <<<"$out" | cut -c1-260)"
}

# --- owner, 14 Nov (no entry): the cost of finding a root cause was lost in both runs of the day ------------
# Lekhak's agent logged ten causes together at the end, Chatur's set its look marks only from its fourth problem,
# and the run closed quietly with every one "not measured". No script sees when an agent moves to the next
# problem, so the mark cannot be made for it; the status gate now names every miss of the closing command whose
# finding cost is not measured and blocks until the closing message says so. A measured miss is never named.
find_cost() {
  local d="$SCRATCH/findcost" out now t0
  mkdir -p "$d/.tfcore/.session" "$d/docs/metrics"; cp -r "$UTILS" "$d/.tfcore/"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; t0="$(tf_date_from -u '-40 min' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{}\n' > "$d/.tfcore/.session/claude-code.json"; aged "$d/.tfcore/.session/claude-code.json" '-50 min'
  printf '%s\n' "{\"v\":1,\"kind\":\"miss\",\"miss_id\":\"MISS-Fx-20261114-01\",\"app\":\"Fx\",\"req_id\":\"REQ-UI-001\",\"miss_class\":\"wrong-behaviour\",\"found_by\":\"owner\",\"found_phase\":\"triage-and-fix\",\"found_run_id\":\"$t0\",\"discovery_started\":\"$t0\",\"discovery_ended\":\"$now\",\"ts\":\"$now\"}" \
    "{\"v\":1,\"kind\":\"miss\",\"miss_id\":\"MISS-Fx-20261114-02\",\"app\":\"Fx\",\"req_id\":\"REQ-UI-002\",\"miss_class\":\"wrong-behaviour\",\"found_by\":\"owner\",\"found_phase\":\"log-miss\",\"found_run_id\":\"$t0\",\"discovery_why\":\"found together with MISS-Fx-20261114-03: logged within 120 s of it with no look between them\",\"ts\":\"$now\"}" > "$d/docs/metrics/misses.jsonl"
  printf '{"v":1,"kind":"run","app":"Fx","cmd":"triage-and-fix","started":"%s","ended":"%s","ts":"%s"}\n' "$t0" "$now" "$now" > "$d/docs/metrics/runs.jsonl"
  printf '# Fx — Project status\n' > "$d/PROJECT-STATUS.md"; cp "$d/PROJECT-STATUS.md" "$d/PROJECT-STATUS.html"
  hook() { python3 -c "import json,sys; print(json.dumps({'last_assistant_message': sys.argv[1], 'turn_started': sys.argv[2]}))" "$1" "$(tf_date_from -u '-5 min' +%Y-%m-%dT%H:%M:%SZ)" \
    | CLAUDE_PROJECT_DIR="$d" CLAUDECODE=1 bash "$HOOKS/guard-status-html.sh" 2>&1; }
  out="$(hook "Fixed REQ-UI-001 and REQ-UI-002. Next: the owner's re-check.")"
  grep -q 'finding cost of 1 miss(es) this command logged reads "not measured"' <<<"$out" && grep -q 'MISS-Fx-20261114-02 (REQ-UI-002)' <<<"$out" && ! grep -q 'MISS-Fx-20261114-01' <<<"$out" \
    && ok find_cost_a "the gate names the closing command's miss whose finding cost was not measured, and not the measured one" \
    || bad find_cost_a "the unmeasured miss closed quietly: $(grep -m2 -i 'miss' <<<"$out" | tr '\n' '|' | cut -c1-240)"
  out="$(hook "Fixed both. MISS-Fx-20261114-02's finding cost is not measured: it was logged together with another.")"
  ! grep -q 'not measured", and the closing message' <<<"$out" \
    && ok find_cost_b "a closing message that names the unmeasured miss passes this check" \
    || bad find_cost_b "the gate still blocked after the miss was named: $(grep -m1 'not measured' <<<"$out" | cut -c1-200)"
}

# --- owner, 14 Nov (no entry): Chatur's chained verifies had no start mark of their own -------------------------
# Their start was guessed from when list.json was last written, so three run records covered 5 to 8 seconds and
# their time was counted under triage-and-fix. tf-verify-list.sh, the verify's first script, now marks a verify
# whose step 0 was skipped, the emit records it from that mark and gives the marker back to the triage; a verify
# with no mark of its own gets no run record. A verify started properly is recorded from its own start as before.
verify_mark() {
  local d="$SCRATCH/vmark" t0 out rec
  mkdir -p "$d/.tfcore/.session" "$d/docs/metrics" "$d/tests/.artifacts/verify"; cp -r "$UTILS" "$d/.tfcore/"
  for s in runs gates sessions commits misses; do : > "$d/docs/metrics/$s.jsonl"; done
  printf 'appPhase: 1\nappKind: app\n' > "$d/.tfcore/core-config.yaml"
  printf '# Fx — Checklist\n\n| ID | Title | Status | %% | Remarks | Details |\n|---|---|---|---|---|---|\n| REQ-FN-001 | Add | Needs re-verify | 90%% | | |\n' > "$d/docs/Fx-Checklist.md"
  t0="$(tf_date_from -u '-40 min' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"cmd":"triage-and-fix","app":"Fx","started":"%s"}\n' "$t0" > "$d/.tfcore/.session/phase.json"
  vx() { ( cd "$d" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d" TF_SKIP_SELFCHECK=1 "$@" ) 2>&1; }
  python3 -c "import json,sys; json.dump({'app':'Fx','scope':'all','build_result':'pass','rows':[{'id':'REQ-FN-001','class':'FN','verdict':'PASS','gate':None,'gates_run':['build','acceptance'],'failure_class':None,'prior_verdict':'Needs re-verify','status':'Verified','emit_gate':True}]}, open(sys.argv[1],'w'))" "$d/tests/.artifacts/verify/verdicts.json"
  local mark; mark="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  vx bash .tfcore/utils/tf-verify-list.sh Fx all --phase 1 >/dev/null
  sleep 3; vx bash .tfcore/utils/tf-verify-list.sh Fx all --phase 1 >/dev/null   # listed again before the emit
  out="$(vx bash .tfcore/utils/tf-verify-emit.sh Fx --started "$t0")"
  rec="$(python3 -c "
import json, datetime
r = [json.loads(l) for l in open('$d/docs/metrics/runs.jsonl') if '\"verify-phase\"' in l]
s = lambda x: datetime.datetime.strptime(x, '%Y-%m-%dT%H:%M:%SZ').timestamp()
print(len(r), r[0]['started'] >= '$mark' and s(r[0]['ended']) - s(r[0]['started']) >= 3 if r else '-')" 2>&1)"
  [[ "$rec" == "1 True" ]] && grep -q '"cmd":"triage-and-fix"' "$d/.tfcore/.session/phase.json" && ! grep -q verify-phase "$d/.tfcore/.session/phase.json" \
    && ok verify_mark_a "a chained verify that skipped step 0 is marked by its list and recorded from that mark, not from the last list; the marker goes back to the triage" \
    || bad verify_mark_a "the verify's record is not its own window: $rec // marker $(cat "$d/.tfcore/.session/phase.json") // $(grep -m1 'runs:' <<<"$out")"
  # no mark at all: the gate records are written, the run record is not
  : > "$d/docs/metrics/runs.jsonl"; : > "$d/docs/metrics/gates.jsonl"
  out="$(vx bash .tfcore/utils/tf-verify-emit.sh Fx --started "$t0")"
  [[ ! -s "$d/docs/metrics/runs.jsonl" ]] && grep -q '"req_id":"REQ-FN-001"' "$d/docs/metrics/gates.jsonl" && grep -q 'no start mark of its own' <<<"$out" \
    && ok verify_mark_b "a verify with no start mark of its own writes its gate records and no run record of seconds, and says why" \
    || bad verify_mark_b "an unmarked verify was recorded: $(head -c 200 "$d/docs/metrics/runs.jsonl") // $(grep -m1 'runs' <<<"$out")"
  # step 0 done properly: recorded from its own start, as before
  : > "$d/docs/metrics/runs.jsonl"
  local own; own="$(vx bash .tfcore/utils/tf-phase.sh start verify-phase Fx | head -1)"
  vx bash .tfcore/utils/tf-verify-emit.sh Fx --started "$t0" >/dev/null
  grep -q "\"started\":\"$own\"" "$d/docs/metrics/runs.jsonl" \
    && ok verify_mark_c "a verify started at step 0 is still recorded from its own start" \
    || bad verify_mark_c "a properly started verify lost its record: $(head -c 200 "$d/docs/metrics/runs.jsonl")"
}

source "$(dirname "${BASH_SOURCE[0]}")/ts-cases.sh"   # TrStudio TF-003 to TF-007
source "$(dirname "${BASH_SOURCE[0]}")/n16-cases.sh"  # Chatur TF-037, Sevak TF-040 to TF-044
source "$(dirname "${BASH_SOURCE[0]}")/n19-cases.sh"  # the faults of 18 Nov from five projects
source "$(dirname "${BASH_SOURCE[0]}")/n19-metrics-cases.sh"  # the owner's two metrics faults of 19 Nov

# --- run ----------------------------------------------------------------------------------
echo "# tests/faults — one case per fault found by reading the code"
for t in status_read marker_age yolo_ttl emit_root backtick_row owner_uat quoted_phase handoff_prose assets_login sv_025 ch_026 ch_027 ch_030 lk_042 ch_034 measure_rows ts_001 ts_002 ts_003 ts_004 ts_005 ts_006 ts_007 ts_007e ch_035 ch_029 lk_044 ch_028 tf_058 lk_040 ch_031 lk_041 sv_038 sv_033 sv_034 ch_036 find_cost verify_mark sv_035 sv_036 sv_027 sv_028 sv_029 sv_030 sv_032 tf_057 sv_026 sv_031 as_001 am_031 am_032 setup_first ch_037 sv_040 sv_041 sv_042 sv_042c sv_042d sv_043 sv_044 ch_045 tf_059 ch_039 ch_038 sv_045 lk_046 lk_046c tf_060 ts_008 ts_010 ts_009 tokens_once estimate_phases ch_046 ch_047 ch_048; do
  [[ -n "$only" && "$only" != "$t" ]] && continue
  "$t" > "$SCRATCH/case.out" 2>&1; cat "$SCRATCH/case.out"; grep '^skipped:' "$SCRATCH/case.out" >> "$SCRATCH/skipped"
done
k="$(grep -c . "$SCRATCH/skipped" 2>/dev/null)"; [[ "${k:-0}" -gt 0 ]] && echo "# ${k} case(s) skipped, counted as skipped and not as passed: $(sed -E 's/^skipped: ([^ ]+) — needs ([^(]*[^ (]).*/\1 (\2)/' "$SCRATCH/skipped" | paste -s -d ' ' -)"
[[ $fail -eq 0 ]] && echo "# all fault cases hold" || echo "# fault cases FAILED"
exit $fail

#!/usr/bin/env bash
# tests/regression/run.sh — one case per defect a real project found in a shipped script.
#
# The reset proved every script on FINISHED projects and freshly generated fixtures, so the
# happy path was covered and nothing else was. Eight defects reached TfLens as a result
# (MISS-TechieFlow-20260909-01). Every fixture here is therefore a project MID-FLIGHT and
# slightly broken: a checklist with a row that can never clear, a BRD that has been amended
# once, an ignore rule covering a child of an open parent, a stream carrying an impossible
# record, a metrics file with the framework's own verdicts mixed into an application's.
#
# The bar for a case here: it must FAIL against the script as the reporting project found it.
# A case that passes both before and after the fix proves nothing and does not belong.
#
#   bash tests/regression/run.sh            # all
#   bash tests/regression/run.sh tf_019     # one
#   TF_REGRESSION_UTILS=<project>/.tfcore/utils bash tests/regression/run.sh tf_052
#                                           # one, against the copy a project has deployed
#
# Exit 0 all held, 1 a case failed. Python 3 standard library only. Never runs git.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UTILS="${TF_REGRESSION_UTILS:-$ROOT/.tfcore/utils}"
TELEM="$ROOT/.tfcore/telemetry"
SCRATCH="$ROOT/tests/.artifacts/regression.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT
fail=0
only="${1:-}"

ok()   { printf 'ok   %s — %s\n' "$1" "$2"; }
bad()  { printf 'FAIL %s — %s\n' "$1" "$2"; fail=1; }
note() { printf '     %s\n' "$1"; }

# --- fixture builders -------------------------------------------------------------------

# A checklist with the shape that pins the build list: one row that can never clear plus
# rows that have never been started. TfLens phase 3, 2026-09-09.
_checklist_fx() {
  local d="$SCRATCH/$1"; mkdir -p "$d/docs" "$d/.tfcore"
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  cat > "$d/docs/Fx-Checklist.md" <<'MD'
# Fx — Requirements Checklist

## Requirements Status

| ID | Title | Status | % | Remarks | Detail |
|---|---|---|---|---|---|
| REQ-FN-001 | Emits events | Needs re-verify | 40% | needs a repo that emits events.ndjson; none exists | [view](#d-req-fn-001) |
| REQ-FN-002 | Reads events | Needs re-verify | 40% | same gate | [view](#d-req-fn-002) |
| REQ-UI-010 | Coverage page | Not Started | 0% | added by amend-docs | [view](#d-req-ui-010) |
| REQ-UI-011 | Misses page | Not Started | 0% | added by amend-docs | [view](#d-req-ui-011) |
| REQ-FN-020 | Export | Verified | 100% | — | [view](#d-req-fn-020) |

## Coverage

- <a id="d-req-fn-001"></a>**REQ-FN-001** — Emits events
  - Acceptance: When a user opens Coverage on Coverage, then the event count shows.
- <a id="d-req-fn-002"></a>**REQ-FN-002** — Reads events
  - Acceptance: When a user opens Coverage on Coverage, then the stream is read.
- <a id="d-req-ui-010"></a>**REQ-UI-010** — Coverage page
  - Acceptance: When a user opens Coverage on Coverage, then the page renders.
- <a id="d-req-ui-011"></a>**REQ-UI-011** — Misses page
  - Acceptance: When a user opens Misses on Misses, then the page renders.
- <a id="d-req-fn-020"></a>**REQ-FN-020** — Export
  - Acceptance: When a user clicks Export on Export, then a file downloads.
MD
  printf '%s' "$d"
}

# Two run records a project may hold from before the emitter refused them: one ending
# before it starts, one honest. Written directly on purpose — the whole point is that
# tf-emit.sh will no longer produce the first, so only history can.
_seed_impossible() {
  python3 - "$1/docs/metrics/runs.jsonl" <<'PY'
import sys
bad = ('{"kind":"run","cmd":"fix-issues","app":"Fx","started":"2026-08-22T11:30:00Z",'
       '"ended":"2026-08-22T11:27:14Z","duration_s":-166,"ts":"2026-08-22T11:27:14Z"}')
good = ('{"kind":"run","cmd":"build-phase","app":"Fx","started":"2026-08-22T12:00:00Z",'
        '"ended":"2026-08-22T13:00:00Z","duration_s":3600,"ts":"2026-08-22T13:00:00Z"}')
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write(bad + "\n" + good + "\n")
PY
}

# Three run records: one impossible, one whose stored figure contradicts its own clocks,
# one honest. Written directly because the emitter now refuses the first two, so only a
# stream written before that check can hold them — which is exactly TechieBlog's position.
_seed_lying() {
  python3 - "$1/docs/metrics/runs.jsonl" <<'PY'
import sys
rows = [
    # start after end: impossible, carries no duration at all
    '{"kind":"run","cmd":"refresh-status","app":"Fx","started":"2026-08-22T20:05:00Z",'
    '"ended":"2026-08-22T17:59:39Z","duration_s":600,"ts":"2026-08-22T17:59:39Z"}',
    # stored 600 against a real 1800: the plausible round number that hid 13 of the 14
    '{"kind":"run","cmd":"fix-issues","app":"Fx","started":"2026-08-22T12:00:00Z",'
    '"ended":"2026-08-22T12:30:00Z","duration_s":600,"ts":"2026-08-22T12:30:00Z"}',
    # honest
    '{"kind":"run","cmd":"build-phase","app":"Fx","started":"2026-08-22T13:00:00Z",'
    '"ended":"2026-08-22T14:00:00Z","duration_s":3600,"ts":"2026-08-22T14:00:00Z"}',
]
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write("\n".join(rows) + "\n")
PY
}

# An amendment naming a miss that is not on this stream. A real defect rather than history:
# it carries information that reaches no figure at all, and unlike an impossible run record
# it can still be put right, by writing the parent it names.
_seed_orphan_amend() {
  python3 - "$1/docs/metrics/misses.jsonl" <<'PY'
import sys
rows = [
    '{"kind":"miss","miss_id":"MISS-Fx-20260907-01","app":"Fx","miss_class":"wrong-behaviour",'
    '"artifact":"src","severity":"minor","found_by":"owner","what":"export did nothing","sort":"spec"}',
    '{"kind":"miss-amend","miss_id":"MISS-Fx-20260907-99","field":"sort","value":"weak-check",'
    '"ts":"2026-09-08T10:00:00Z"}',
]
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write("\n".join(rows) + "\n")
PY
}

# A metrics repo: streams only, no git, the shape --rollup reads.
_metrics_fx() {
  local d="$SCRATCH/$1"; mkdir -p "$d/docs/metrics"
  for s in runs gates sessions commits misses; do : > "$d/docs/metrics/$s.jsonl"; done
  printf '%s' "$d"
}

# --- TF-013: verify must not provision, and must not repoint a dependency ----------------
tf_013() {
  local h="$ROOT/.tfcore/hooks/guard-verify-deps.sh"
  if [[ ! -f "$h" ]]; then
    bad tf_013 "no hook refuses a bare 'docker compose up' or a connection-string override"
    note "expected $h"
    return
  fi
  local out rc
  # a bare `up` (no service named) starts every service — TfLens 2026-09-01
  out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"docker compose up -d db || docker compose up -d"}}' \
        | CLAUDE_PROJECT_DIR="$ROOT" bash "$h" 2>&1)"; rc=$?
  [[ $rc -ne 0 ]] && ok tf_013a "bare 'docker compose up' is refused" \
                 || { bad tf_013a "bare 'docker compose up' was allowed"; note "$out"; }
  # repointing the app's tests at another database and reporting 689/689 pass
  out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"export FxDbConnection=Host=localhost;Port=5432 && dotnet test"}}' \
        | CLAUDE_PROJECT_DIR="$ROOT" bash "$h" 2>&1)"; rc=$?
  [[ $rc -ne 0 ]] && ok tf_013b "a connection-string env override is refused" \
                 || { bad tf_013b "a connection-string env override was allowed"; note "$out"; }
  # a named service is the sanctioned path and must still pass
  out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"docker start WinPostgre"}}' \
        | CLAUDE_PROJECT_DIR="$ROOT" bash "$h" 2>&1)"; rc=$?
  [[ $rc -eq 0 ]] && ok tf_013c "starting a named service is allowed" \
                 || { bad tf_013c "starting a named service was refused"; note "$out"; }
}

# --- TF-014: the audit cannot see the IDE state it exists to catch -----------------------
tf_014() {
  local d="$SCRATCH/gi"; mkdir -p "$d/src/App/.vs/ProjectEvaluation"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$d/src/App/App.csproj"
  printf 'x\n' > "$d/src/App/.vs/ProjectEvaluation/app.strings.v10.bin"
  # TfLens's real rule: the solution-named child is ignored, the parent is wide open
  printf 'bin/\nobj/\n*.user\nTestResults/\n/.vs/App.slnx\n' > "$d/.gitignore"
  local out; out="$(bash "$UTILS/tf-gitignore-audit.sh" "$d" 2>&1)"
  if grep -q '\.vs/' <<<"$out"; then
    ok tf_014a "the audit names .vs/ as an unignored IDE-state directory"
  else
    bad tf_014a "the audit is silent about a tracked .vs/ tree"; note "$out"
  fi
  if grep -qi 'covers a child\|parent' <<<"$out"; then
    ok tf_014b "a rule covering a child of an open parent is reported"
  else
    bad tf_014b "'/.vs/App.slnx' with .vs/ open was not reported"; note "$out"
  fi
}

# --- TF-015: an impossible run record, and a consumer that admits it ---------------------
tf_015() {
  local d; d="$(_metrics_fx emitfx)"
  # duration_s that bears no relation to the timestamps — 13 of the 14 TechieBlog records
  ( cd "$d" && printf '%s' '{"kind":"run","app":"Fx","cmd":"fix-issues","started":"2026-08-22T20:05:00Z","ended":"2026-08-22T17:59:39Z","duration_s":600}' \
      | bash "$UTILS/tf-emit.sh" runs >/dev/null 2>&1 )
  local stored
  stored="$(python3 - "$d/docs/metrics/runs.jsonl" <<'PY'
import json,sys
try:
    r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]
except Exception:
    print("none"); raise SystemExit
print(r.get("duration_s"))
PY
)"
  # not merely "different from 600" — an invented figure is the failure, not the cure.
  # Clamping `ended` to now and deriving from a weeks-old `started` gave 1,515,038s.
  if [[ "$stored" == "none" || "$stored" == "None" ]]; then
    ok tf_015a "a self-contradicting record carries no duration at all"
  else
    bad tf_015a "a duration of $stored was stored for a record whose ended precedes its started"
  fi
  # and a record whose timestamps agree keeps its measurement untouched
  ( cd "$d" && printf '%s' '{"kind":"run","app":"Fx","cmd":"build-phase","started":"2026-09-08T12:00:00Z","ended":"2026-09-08T12:30:00Z","duration_s":1800}' \
      | bash "$UTILS/tf-emit.sh" runs >/dev/null 2>&1 )
  local good
  good="$(python3 - "$d/docs/metrics/runs.jsonl" <<'PY'
import json,sys
r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]
print(r.get("duration_s"))
PY
)"
  [[ "$good" == "1800" ]] && ok tf_015c "an honest measurement is left alone" \
                          || bad tf_015c "a valid duration was rewritten to $good"
  # consumer side: a negative already on the stream must not reach a figure
  local m; m="$(_metrics_fx metricsfx)"
  cat > "$m/docs/metrics/runs.jsonl" <<'JS'
{"kind":"run","cmd":"fix-issues","app":"Fx","started":"2026-08-22T11:30:00Z","ended":"2026-08-22T11:27:14Z","duration_s":-166,"ts":"2026-08-22T11:27:14Z"}
{"kind":"run","cmd":"fix-issues","app":"Fx","started":"2026-08-22T12:00:00Z","ended":"2026-08-22T13:00:00Z","duration_s":3600,"ts":"2026-08-22T13:00:00Z"}
JS
  local tot
  tot="$(bash "$TELEM/tf-metrics.sh" --rollup "$m" --json 2>/dev/null \
        | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("phases",{}).get("duration_s_total","?"))' 2>/dev/null)"
  if [[ "$tot" == "3600" ]]; then
    ok tf_015b "a negative duration on the stream is excluded from the total"
  else
    bad tf_015b "duration_s_total is $tot; expected 3600 with the -166 record excluded"
  fi
  # The timestamps win over a stored figure that disagrees with them — the thirteen
  # TechieBlog records that hid behind a plausible round number, which reading the number
  # alone could never catch. And the reader must be TOLD what was dropped: a smaller total
  # presented without its exclusions is just a different wrong number.
  local q; q="$(_metrics_fx durfx)"
  _seed_lying "$q"
  local j; j="$(bash "$TELEM/tf-metrics.sh" --rollup "$q" --json 2>/dev/null)"
  local got; got="$(python3 - <<PY
import json
d = json.loads('''$j''') if '''$j'''.strip() else {}
p = d.get("phases", {})
print("%s|%s|%s|%s" % (p.get("duration_s_total"), p.get("duration_measured_n"),
                       p.get("duration_impossible_n"), p.get("duration_recomputed_n")))
PY
)"
  # seeded: one impossible (excluded), one storing 600 against a real 1800 (recomputed),
  # one honest 3600. Total must be 1800 + 3600, from 2 records, 1 excluded, 1 recomputed.
  if [[ "$got" == "5400|2|1|1" ]]; then
    ok tf_015d "the timestamps win, and the report says what it dropped"
  else
    bad tf_015d "expected total|used|excluded|recomputed = 5400|2|1|1, got $got"
  fi
}

# --- TF-016: a document miss can never be closed -----------------------------------------
tf_016() {
  local t="$ROOT/.tfcore/tasks/amend-docs.md"
  grep -q 'tf-fix-close' "$t" \
    && ok tf_016a "amend-docs has a step that closes what the amendment fixed" \
    || bad tf_016a "amend-docs.md never calls tf-fix-close.sh, so a document miss stays open forever"
  # the step is only worth having if the door it names exists — a task naming a flag no
  # script implements is the TF-006 defect, and it is what this case is really for
  local d; d="$(_metrics_fx docmiss)"
  ( cd "$d" && printf '%s' '{"kind":"miss","miss_id":"MISS-Fx-20260901-06","app":"Fx","req_id":"REQ-FN-090","miss_class":"wrong-behaviour","artifact":"brd","severity":"minor","found_by":"owner","what":"the BRD never said the export excludes drafts","sort":"spec"}' \
      | bash "$UTILS/tf-emit.sh" misses >/dev/null 2>&1 )
  local listed; listed="$(cd "$d" && bash "$UTILS/tf-emit.sh" --open-misses Fx --artifact-class doc 2>&1)"
  if grep -q 'MISS-Fx-20260901-06' <<<"$listed"; then
    ok tf_016b "the open document misses can be listed"
  else
    bad tf_016b "--open-misses lists nothing"; note "$listed"; return
  fi
  ( cd "$d" && bash "$UTILS/tf-fix-close.sh" Fx --misses MISS-Fx-20260901-06 \
      --fix-cmd amend-docs --verdict Verified >/dev/null 2>&1 )
  local still; still="$(cd "$d" && bash "$UTILS/tf-emit.sh" --open-misses Fx --artifact-class doc 2>&1)"
  if grep -q 'MISS-Fx-20260901-06' <<<"$still"; then
    bad tf_016c "the miss is still open after amend-docs closed it"; note "$still"
  else
    ok tf_016c "a document miss closes when the amendment lands"
  fi
}

# --- TF-017: the two halves of the framework disagree about a ledger line ----------------
tf_017() {
  local d="$SCRATCH/brd"; mkdir -p "$d/docs" "$d/.tfcore"
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  # the anchor is not decoration: §9 cross-links need it and tf-doc-check refuses a broken one
  cat > "$d/docs/Fx-BRD.md" <<'MD'
# Fx — Business Requirements

## Requirements

- <a id="brd-1"></a>**BRD-1** — User can see the coverage figure on Coverage.
- <a id="brd-2"></a>**BRD-2** — User can export the figures from Export.

## Screens

- Coverage — [BRD-1](#brd-1)
- Export — [BRD-2](#brd-2)
MD
  local out; out="$(cd "$d" && python3 - "$UTILS/tf-split-brd.py" <<'PY' 2>&1
import importlib.util, sys, io, contextlib
spec = importlib.util.spec_from_file_location("sb", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
items = m.ledger(open("docs/Fx-BRD.md", encoding="utf-8").read())
print("ITEMS", len(items))
PY
)"
  if [[ "$out" == *"ITEMS 2"* ]]; then
    ok tf_017a "an anchored ledger line is read (2 items)"
  else
    bad tf_017a "anchored ledger lines are invisible to tf-split-brd"; note "$out"
  fi
  # TfLens reported tf-doc-check as carrying the same blind spot. It does not -- it looks
  # for the bold id anywhere on the line, so an anchor does not hide it. Pinned anyway, so
  # that "aligning the two regexes" can never be done in the wrong direction.
  local n; n="$(python3 - "$UTILS/tf-doc-check.py" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'ids = re\.findall\(r"([^"]+)", clean\)', src)
if not m:
    print("no-pattern"); raise SystemExit
line = '- <a id="brd-1"></a>**BRD-1** — User can see the coverage figure on Coverage.'
print(len(re.findall(m.group(1), line)))
PY
)"
  if [[ "$n" == "1" ]]; then
    ok tf_017b "tf-doc-check reads an anchored ledger line (not affected)"
  else
    bad tf_017b "tf-doc-check's ledger pattern no longer matches an anchored line ($n)"
  fi
}

# --- TF-018: the sentence describing a miss can never be corrected ------------------------
tf_018() {
  local d; d="$(_metrics_fx amendfx)"
  cat > "$d/docs/metrics/misses.jsonl" <<'JS'
{"kind":"miss","miss_id":"MISS-Fx-20260907-01","app":"Fx","miss_class":"wrong-behaviour","artifact":"src","severity":"minor","found_by":"owner","ts":"2026-09-07T10:00:00Z"}
JS
  local out rc
  out="$( cd "$d" && bash "$UTILS/tf-emit.sh" --amend MISS-Fx-20260907-01 what "the export button did nothing" 2>&1 )"; rc=$?
  if grep -q 'amended' <<<"$out"; then
    ok tf_018a "a miss's own sentence can be filled in later"
  else
    bad tf_018a "tf-emit refuses to fill in 'what'"; note "$out"
  fi
  # and it must still refuse to OVERWRITE one that is already there
  out="$( cd "$d" && bash "$UTILS/tf-emit.sh" --amend MISS-Fx-20260907-01 what "something else" 2>&1 )"
  if grep -qi 'refus\|already' <<<"$out"; then
    ok tf_018b "an amendment still cannot overwrite a value that is already set"
  else
    bad tf_018b "an amendment overwrote an existing value"; note "$out"
  fi
  if grep -q '"what"' "$TELEM/tf-metrics.sh"; then
    ok tf_018c "the reference floors 'what' at the date it was added"
  else
    bad tf_018c "FIELD_SINCE has no floor for 'what', so old records dilute its denominator"
  fi
}

# --- TF-019: the working list silently omits every row that was never started ------------
tf_019() {
  local d; d="$(_checklist_fx bl)"
  local out; out="$(cd "$d" && bash "$UTILS/tf-build-list.sh" Fx 2>&1)"
  if grep -q 'REQ-UI-010' <<<"$out"; then
    ok tf_019 "the two Not Started rows are accounted for in the output"
  else
    bad tf_019 "REQ-UI-010 and REQ-UI-011 appear nowhere; a pass would report the phase finished"
    note "$(head -3 <<<"$out")"
  fi
}

# --- TF-020: the framework's own verdicts are counted as an application's ----------------
tf_020() {
  local d; d="$(_metrics_fx segfx)"
  cat > "$d/docs/metrics/gates.jsonl" <<'JS'
{"kind":"gate","app":"Fx","req_id":"REQ-UI-001","req_class":"UI","project_type":"app","gate":"acceptance","result":"fail","attempt":1,"ts":"2026-09-08T10:00:00Z"}
{"kind":"gate","app":"Fx","req_id":"REQ-UI-001","req_class":"UI","project_type":"app","gate":"acceptance","result":"pass","attempt":2,"ts":"2026-09-08T11:00:00Z"}
{"kind":"gate","app":"TechieFlow","req_id":"FR-01","req_class":"FR","project_type":"app","gate":"acceptance","result":"pass","attempt":1,"ts":"2026-09-08T12:00:00Z"}
{"kind":"gate","app":"TechieFlow","req_id":"FR-02","req_class":"FR","project_type":"app","gate":"acceptance","result":"pass","attempt":1,"ts":"2026-09-08T12:01:00Z"}
{"kind":"gate","app":"TechieFlow","req_id":"FR-03","req_class":"FR","project_type":"app","gate":"acceptance","result":"pass","attempt":1,"ts":"2026-09-08T12:02:00Z"}
JS
  bash "$TELEM/tf-metrics.sh" --rollup "$d" --json > "$d/out.json" 2>/dev/null
  local verdict; verdict="$(python3 - "$d/out.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unparsable"); raise SystemExit
segs = d.get("live") or {}
keys = sorted(segs)
if "framework-requirement" in keys:
    # and the application segment must not have absorbed them
    app = segs.get("app") or {}
    print("segregated" if app.get("records", 2) == 2 else "leaked:%s" % app.get("records"))
else:
    print("pooled:" + ",".join(keys) or "pooled:none")
PY
)"
  if [[ "$verdict" == "segregated" ]]; then
    ok tf_020 "FR verdicts sit in their own segment, never an application's"
  else
    bad tf_020 "FR verdicts are pooled into an application segment ($verdict)"
  fi
}

# --- guard_reads: the append-only guard refused reads as well as writes -------------------
# Found HERE while verifying the fixes above, not by a consuming project, so it carries no
# TF- number: those belong to the reporting project's feedback file and TF-021 is TfLens's
# screens defect below. Checking a stream with a python one-liner was blocked outright,
# though guard-metrics.sh's own header says "Reading them is fine." A guard that refuses
# legitimate work teaches people to route around the guard, so it now needs a write in the
# command as well as the path. MISS-TechieFlow-20260909-03.
guard_reads() {
  local h="$ROOT/.tfcore/hooks/guard-metrics.sh"
  _guard() {   # _guard <command string> -> the hook's exit status
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" \
      | CLAUDE_PROJECT_DIR="$ROOT" bash "$h" >/dev/null 2>&1
  }
  _guard 'python3 tools/check.py docs/metrics/runs.jsonl' \
    && ok gm_a "reading a stream with python is allowed" \
    || bad gm_a "a read of docs/metrics/runs.jsonl was blocked"
  _guard 'python3 -c open(docs/metrics/runs.jsonl, w).write(x)' \
    && bad gm_b "a python WRITE onto a stream was allowed" \
    || ok gm_b "writing a stream with python is still blocked"
  _guard 'echo x >> docs/metrics/runs.jsonl' \
    && bad gm_c "a redirect onto a stream was allowed" \
    || ok gm_c "redirection onto a stream is still blocked"
  _guard 'cp /tmp/x docs/metrics/misses.jsonl' \
    && bad gm_d "a copy onto a stream was allowed" \
    || ok gm_d "copying onto a stream is still blocked"
}

# --- TF-021: a screen that scrolls sideways inside a box, and one that paints late --------
# Two defects in one tool. It measured the box an element is LAID OUT in rather than the box
# it PAINTS in, so a 1167px table inside a 492px scroller "overlapped" the card beside it; and
# it read the page before a circuit-rendered screen had painted, so every anchored control was
# reported missing while its own screenshot showed them. TfLens /misses and /effort, 2026-09-09.
#
# It needs a real browser, so it runs only where playwright resolves: a project has it at its
# root, and TF_PLAYWRIGHT_DIR names one otherwise. Where it does not, the case says so and the
# suite carries on — a case that cannot run must never read as a case that passed.
_pw_dir() {
  local c
  for c in "${TF_PLAYWRIGHT_DIR:-}" "$ROOT"; do
    [[ -n "$c" && -d "$c/node_modules/playwright" ]] && { printf '%s' "$c"; return; }
  done
}
tf_021() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_021 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/screens"; mkdir -p "$d/docs/mockups"
  # a wide row inside a horizontal scroller, and a card beside the scroller it never covers
  cat > "$d/misses.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Misses</title><style>
 body{margin:0;font-family:system-ui,sans-serif}.r{display:flex;align-items:flex-start}
 .sx{width:492px;overflow-x:auto}.wide{width:1167px;height:60px;background:#eef}
 .card{width:400px;height:100px;margin-left:40px;background:#efe}h1{font-size:16px;margin:0 0 4px}
</style></head><body><h1 data-testid="page-title">Misses</h1><div class="r">
 <div class="sx"><div class="wide" data-testid="miss-origin">a wide row that scrolls sideways inside its own container</div></div>
 <div class="card" data-testid="miss-whymissed">why it was missed — missing checklist item</div>
</div><p>Ten misses are open here and none of them overlap anything.</p></body></html>
HTML
  # a screen that paints after the settle wait, the way a circuit-rendered one does
  cat > "$d/late.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Effort</title><style>
 body{margin:0;font-family:system-ui,sans-serif}.sb{width:200px;height:300px;background:#eee}
</style></head><body><div id="app">loading the circuit…</div><script>
 setTimeout(function(){document.getElementById('app').innerHTML=
  '<div class="sb" data-testid="app-sidebar">Effort · Misses</div><h1 data-testid="page-title">Effort</h1><p>Phase effort.</p>';},2500);
</script></body></html>
HTML
  # and one that really is broken, so the fix cannot buy its quiet by going blind
  cat > "$d/broken.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Broken</title><style>
 body{margin:0;font-family:system-ui,sans-serif;position:relative}
 .a{position:absolute;left:0;top:0;width:400px;height:100px;background:#fee}
 .b{position:absolute;left:200px;top:0;width:400px;height:100px;background:#eef}
</style></head><body><div class="a" data-testid="kpi-left">a card drawn under another one</div>
<div class="b" data-testid="kpi-right">the card that covers it</div><p>Genuinely broken.</p></body></html>
HTML
  cp "$d/misses.html" "$d/docs/mockups/misses.html"
  cp "$d/broken.html" "$d/docs/mockups/broken.html"
  printf '<html><body><div data-testid="app-sidebar">s</div><h1 data-testid="page-title">Effort</h1></body></html>\n' \
    > "$d/docs/mockups/late.html"
  # the shipped script, run where playwright resolves; the bytes are the shipped ones
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-verify-screens.mjs" "$d/screens.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  local out
  out="$( cd "$d" && node screens.mjs --base "http://127.0.0.1:$port" \
          --screen misses=/misses.html --screen late=/late.html --screen broken=/broken.html \
          --widths 1280 --json-out "$d/screens.json" 2>&1 )"
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  grep -q '^OK   misses' <<<"$out" \
    && ok tf_021a "a wide row inside a scroller does not overlap the card beside it" \
    || { bad tf_021a "the unclipped box is still measured"; note "$(grep misses <<<"$out" | head -1)"; }
  grep -q '^OK   late' <<<"$out" \
    && ok tf_021b "a screen that paints late is measured after it has painted" \
    || { bad tf_021b "the page was read before its first render"; note "$(grep late <<<"$out" | head -1)"; }
  grep -q 'kpi-left overlaps kpi-right' <<<"$out" \
    && ok tf_021c "a real overlap is still reported" \
    || bad tf_021c "the clip fix went blind to a genuine overlap"
}

# --- TF-022: a skipped clause was counted as a failing one --------------------------------
# `test.skip(!SEEDED, "needs the seeded dataset")` says the state does not exist in the data.
# That is not a pass and not a defect, and counting it as a failure put FAIL on rows no code
# could clear, then sent build-phase back into FIX mode against them. TfLens REQ-UI-039 and
# REQ-UI-034, 2026-09-09. The mapping is the shipped python, lifted out of tf-verify-tests.sh
# verbatim, so the case needs a playwright REPORT rather than a browser.
tf_022() {
  local d="$SCRATCH/tests22"; mkdir -p "$d"
  awk "/<<'PY'/{f=1;next} /^PY\$/{f=0} f" "$UTILS/tf-verify-tests.sh" > "$d/map.py"
  cat > "$d/pw.json" <<'JS'
{"suites":[{"title":"rows.spec.js","specs":[
 {"title":"REQ-UI-039 the misses page lists a miss","tests":[{"status":"expected","results":[{"status":"passed"}]}]},
 {"title":"REQ-UI-039 the seeded rework figure","tests":[{"status":"skipped","annotations":[{"type":"skip","description":"needs the seeded dataset"}],"results":[{"status":"skipped"}]}]},
 {"title":"REQ-UI-034 coverage reads events.ndjson","tests":[{"status":"skipped","annotations":[{"type":"skip","description":"no repository emits events.ndjson"}],"results":[{"status":"skipped"}]}]},
 {"title":"REQ-UI-050 a control that really is missing","tests":[{"status":"unexpected","results":[{"status":"failed","error":{"message":"expect(locator).toBeVisible() failed"}}]}]}
]}]}
JS
  TF_PWJSON="$d/pw.json" TF_UNITLOG="" TF_UNITLINE="" TF_OUT="$d/tests.json" python3 "$d/map.py" >/dev/null 2>&1
  local v; v="$(python3 - "$d/tests.json" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1]))["reqs"]
except Exception:
    print("unreadable"); raise SystemExit
print("%s|%s|%s" % (r.get("REQ-UI-039", {}).get("result"), r.get("REQ-UI-034", {}).get("result"),
                    r.get("REQ-UI-050", {}).get("result")))
PY
)"
  case "$v" in
    "PASS|NOT-TESTED|FAIL")
      ok tf_022a "a skipped clause is neither a pass nor a defect"
      ok tf_022b "a row whose every clause was skipped is NOT-TESTED, and a real failure still FAILs" ;;
    *) bad tf_022 "REQ-UI-039/034/050 graded $v, expected PASS|NOT-TESTED|FAIL" ;;
  esac
  # and the verdict script must never let NOT-TESTED become Verified
  local e="$SCRATCH/verdict22"; mkdir -p "$e/docs" "$e/tests/.artifacts/verify"
  cp "$d/tests.json" "$e/tests/.artifacts/verify/tests.json"
  cat > "$e/tests/.artifacts/verify/list.json" <<'JS'
{"app":"Fx","scope":"all","phase":1,"kind":"app","checklist":"docs/Fx-Checklist.md","screens":[],"unresolved":[],
 "rows":[{"id":"REQ-UI-034","class":"UI","title":"Coverage","screen":"","route":"","status_raw":"Implemented"},
         {"id":"REQ-UI-039","class":"UI","title":"Misses","screen":"","route":"","status_raw":"Implemented"}]}
JS
  printf '{"mode":"served","reason":"","reason_kind":"","head":"web","rung":"run","url":"http://127.0.0.1:1"}\n' \
    > "$e/tests/.artifacts/verify/boot.json"
  local vout; vout="$( cd "$e" && python3 "$UTILS/tf-verify-verdict.py" Fx --dir tests/.artifacts/verify 2>&1 )"
  if grep -q 'REQ-UI-034 | NOT-TESTED' <<<"$vout" && ! grep -q 'REQ-UI-034 |.*Verified' <<<"$vout"; then
    ok tf_022c "the verdict script reads it as not measured, never Verified"
  else
    bad tf_022c "a row whose tests were all skipped was graded on them"; note "$(grep REQ-UI-034 <<<"$vout" | head -1)"
  fi
}

# --- run-void: a wrong run record leaves the figures without leaving the stream -----------
# This maintainer wrote a run record with a GUESSED start time (2026-09-09), so it stored
# 18,674 s against a real nineteen minutes. Its own timestamps agreed with each other, so no
# reader could detect it, and the stream is append-only, so it could not be corrected. The
# answer is the §5.5.7 answer one stream over: another record. MISS-TechieFlow-20260909-06.
tf_void() {
  local d; d="$(_metrics_fx voidfx)"
  cat > "$d/docs/metrics/runs.jsonl" <<'JS'
{"kind":"run","cmd":"build-phase","app":"Fx","started":"2026-09-09T09:00:00Z","ended":"2026-09-09T10:00:00Z","duration_s":3600,"ts":"2026-09-09T10:00:00Z"}
{"kind":"run","cmd":"fix-issues","app":"Fx","started":"2026-09-09T11:40:00Z","ended":"2026-09-09T16:51:14Z","duration_s":18674,"ts":"2026-09-09T16:51:14Z"}
JS
  local out
  # a void that names nothing is refused, and writes nothing
  out="$( cd "$d" && bash "$UTILS/tf-emit.sh" --void-run build-phase 2020-01-01T00:00:00Z "no such run" 2>&1 )"
  if grep -qi 'refus' <<<"$out" && [[ "$(wc -l < "$d/docs/metrics/runs.jsonl")" == "2" ]]; then
    ok tf_void_a "a void that names no run is refused and appends nothing"
  else
    bad tf_void_a "a void about nothing was written"; note "$out"
  fi
  # the real one
  out="$( cd "$d" && bash "$UTILS/tf-emit.sh" --void-run fix-issues 2026-09-09T11:40:00Z "the start time was guessed, not measured" 2>&1 )"
  grep -q 'voided' <<<"$out" && ok tf_void_b "a wrong run can be voided" \
                             || { bad tf_void_b "the run could not be voided"; note "$out"; }
  # nothing was deleted: both records are still there
  [[ "$(grep -c '"kind":"run"' "$d/docs/metrics/runs.jsonl")" == "2" ]] \
    && ok tf_void_c "both records stay on the stream — a void is not a delete" \
    || bad tf_void_c "a record left the append-only stream"
  # and the reader drops it from every figure, and says how many it dropped
  bash "$TELEM/tf-metrics.sh" --rollup "$d" --json > "$d/out.json" 2>/dev/null
  local v; v="$(python3 - "$d/out.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unparsable"); raise SystemExit
ph = (d.get("phases") or {}).get("fix-issues")
print("%s|%s|%s" % (d.get("runs_voided_n"), "gone" if not ph else ph.get("runs"),
                    bool(d.get("runs_voided"))))
PY
)"
  [[ "$v" == "1|gone|True" ]] \
    && ok tf_void_d "the voided run is in no figure, and the count and reason are published" \
    || bad tf_void_d "the voided run still reaches the figures ($v)"
  # a second void on the same run is refused: one is enough
  out="$( cd "$d" && bash "$UTILS/tf-emit.sh" --void-run fix-issues 2026-09-09T11:40:00Z "again" 2>&1 )"
  grep -qi 'already voided' <<<"$out" && ok tf_void_e "a second void on the same run is refused" \
                                     || bad tf_void_e "a run can be voided twice"
  # an orphan void — one that arrived without its run — is counted, never silently ignored
  python3 - "$d/docs/metrics/runs.jsonl" <<'PY'
import sys
with open(sys.argv[1], "a", encoding="utf-8") as fh:
    fh.write('{"kind":"run-void","app":"Fx","cmd":"verify-phase","started":"2026-09-09T20:00:00Z",'
             '"reason":"written on another machine, its run never arrived"}\n')
PY
  bash "$TELEM/tf-metrics.sh" --rollup "$d" --json > "$d/out2.json" 2>/dev/null
  local o; o="$(python3 -c "
import json,sys
try: print(json.load(open(sys.argv[1])).get('run_voids_orphaned_n'))
except Exception: print('unparsable')" "$d/out2.json")"
  [[ "$o" == "1" ]] && ok tf_void_f "a void whose run never arrived is reported as an orphan" \
                    || bad tf_void_f "an orphaned void was silently ignored ($o)"
}

# --- a run may not start before the last one finished ------------------------------------
# `--void-run` gave a way to CORRECT a run record whose start time nobody measured; nothing
# refused one. So on the day the correction shipped, the same mistake was made twice more —
# two records starting before the previous record ended, adding 42 minutes and nearly three
# hours to every total that crossed them, invisibly. MISS-TechieFlow-20260910-04, sorted
# `ignored`: it was written down and not followed. The emitter refuses it now.
tf_overlap() {
  local d; d="$(_metrics_fx overlapfx)"
  local out n
  emit() { echo "$1" | ( cd "$d" && bash "$UTILS/tf-emit.sh" runs "${2:-}" ) 2>&1; }
  n() { grep -c '"kind":"run"' "$d/docs/metrics/runs.jsonl" 2>/dev/null || echo 0; }

  emit '{"kind":"run","app":"Fx","cmd":"build-phase","started":"2026-09-10T09:00:00Z","ended":"2026-09-10T10:00:00Z"}' >/dev/null
  [[ "$(n)" == "1" ]] && ok tf_overlap_a "a first run is appended" \
                      || bad tf_overlap_a "the first run was refused"

  out="$(emit '{"kind":"run","app":"Fx","cmd":"verify-phase","started":"2026-09-10T09:30:00Z","ended":"2026-09-10T11:00:00Z"}')"
  if grep -q 'REFUSED' <<<"$out" && [[ "$(n)" == "1" ]]; then
    ok tf_overlap_b "a run starting before the last one ended is refused, and nothing is appended"
  else
    bad tf_overlap_b "an overlapping run reached the stream"; note "$out"
  fi
  grep -q 'overlaps the build-phase run of Fx already on the stream (2026-09-10T09:00:00Z to 2026-09-10T10:00:00Z)' <<<"$out" \
    && ok tf_overlap_c "the refusal names the record it collides with and what to do" \
    || { bad tf_overlap_c "the refusal does not say what to do"; note "$out"; }

  emit '{"kind":"run","app":"Fx","cmd":"verify-phase","started":"2026-09-10T10:00:00Z","ended":"2026-09-10T11:00:00Z"}' >/dev/null
  [[ "$(n)" == "2" ]] && ok tf_overlap_d "the same run, started where the last one ended, is appended" \
                      || bad tf_overlap_d "a correctly-timed run was refused"

  # two machines on one merge=union stream: declared, so allowed
  emit '{"kind":"run","app":"Fx","cmd":"fix-issues","started":"2026-09-10T10:30:00Z","ended":"2026-09-10T11:30:00Z"}' --allow-overlap >/dev/null
  [[ "$(n)" == "3" ]] && ok tf_overlap_e "--allow-overlap admits a declared concurrent run" \
                      || bad tf_overlap_e "--allow-overlap did not work"

  # another app's timeline is its own
  emit '{"kind":"run","app":"Other","cmd":"build-phase","started":"2026-09-10T09:15:00Z","ended":"2026-09-10T09:45:00Z"}' >/dev/null
  [[ "$(n)" == "4" ]] && ok tf_overlap_f "the rule is per app, not per stream" \
                      || bad tf_overlap_f "another app's run was refused"

  # and the repair path still works: void the blocker, then the corrected record goes in
  emit '{"kind":"run","app":"Blk","cmd":"build-phase","started":"2026-09-10T09:00:00Z","ended":"2026-09-10T14:00:00Z"}' >/dev/null
  out="$(emit '{"kind":"run","app":"Blk","cmd":"verify-phase","started":"2026-09-10T10:00:00Z","ended":"2026-09-10T11:00:00Z"}')"
  grep -q 'REFUSED' <<<"$out" \
    && ok tf_overlap_g "a wrong record blocks the run that follows it — which is the point" \
    || bad tf_overlap_g "the wrong record did not block, so the repair path below is untested"
  ( cd "$d" && bash "$UTILS/tf-emit.sh" --void-run build-phase 2026-09-10T09:00:00Z "the end time was typed" ) >/dev/null 2>&1
  emit '{"kind":"run","app":"Blk","cmd":"verify-phase","started":"2026-09-10T10:00:00Z","ended":"2026-09-10T11:00:00Z"}' >/dev/null
  grep -q '"cmd":"verify-phase","app":"Blk"\|"app":"Blk","cmd":"verify-phase"' "$d/docs/metrics/runs.jsonl" \
    || python3 -c "
import json,sys
rows=[json.loads(l) for l in open(sys.argv[1])]
sys.exit(0 if any(r.get('app')=='Blk' and r.get('cmd')=='verify-phase' for r in rows) else 1)" "$d/docs/metrics/runs.jsonl"
  if [[ $? -eq 0 ]]; then
    ok tf_overlap_h "voiding the wrong record unblocks the corrected one — the repair path holds"
  else
    bad tf_overlap_h "after a void, the corrected record was still refused"
  fi
  unset -f emit n
}

# --- the ledger the status document stands on --------------------------------------------
# Two things, found together while answering the owner's question "when does a row whose test
# was skipped ever get built?". (1) tf-status-facts read only the LAST LINE of
# docs/.last-verify.json, which the verifier writes as one pretty-printed object, so it
# parsed the closing brace and every project reported `not-run` / `never` however many verify
# runs it had behind it. (2) A row the verifier could not MEASURE was reported as a row
# waiting for another verify run, which is a loop: the next run produces the same verdict.
# MISS-TechieFlow-20260909-07.
tf_ledger() {
  local d="$SCRATCH/ledger"; mkdir -p "$d/docs" "$d/.tfcore"
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  cat > "$d/docs/Fx-Checklist.md" <<'MD'
# Fx — Requirements Checklist

## Requirements Status

| ID | Title | Status | % | Remarks | Detail |
|---|---|---|---|---|---|
| REQ-UI-034 | Coverage page | Implemented | 60% | built, smoke passed | [view](#d-req-ui-034) |
| REQ-UI-039 | Misses page | Verified | 100% | — | [view](#d-req-ui-039) |

## Coverage

- <a id="d-req-ui-034"></a>**REQ-UI-034** — Coverage page
  - Acceptance: When a user opens Coverage on Coverage, then the event count shows.
- <a id="d-req-ui-039"></a>**REQ-UI-039** — Misses page
  - Acceptance: When a user opens Misses on Misses, then the page renders.
MD
  # exactly what tf-verify-verdict.py writes: one object, indent=1, many lines
  python3 - "$d/docs/.last-verify.json" <<'PY'
import json, sys
json.dump({"date": "2026-09-09", "app": "Fx", "scope": "all", "booted": True,
           "checks": ["build", "acceptance"], "evidence": "tests/.artifacts/verify",
           "rows": {"REQ-UI-034": "NOT-TESTED", "REQ-UI-039": "PASS"}},
          open(sys.argv[1], "w", encoding="utf-8"), indent=1)
PY
  local out; out="$( cd "$d" && bash "$UTILS/tf-status-facts.sh" Fx 2>&1 )"
  grep -q 'last_verified_date: 2026-09-09' <<<"$out" \
    && ok tf_ledger_a "a pretty-printed ledger is read, so the status names the real verify date" \
    || { bad tf_ledger_a "the ledger was not read; the status says never verified"
         note "$(grep last_verified <<<"$out" | head -2)"; }
  grep -q 'not measurable' <<<"$out" \
    && ok tf_ledger_b "a row the verifier could not measure is not reported as one more verify away" \
    || { bad tf_ledger_b "an unmeasurable row still points at another verify run"
         note "$(grep -i 'current_phase\|Why:' <<<"$out" | head -2)"; }
  # and it must NOT hide the row: it is still open work, and still in the build list
  local bl; bl="$( cd "$d" && bash "$UTILS/tf-build-list.sh" Fx 2>&1 )"
  grep -q 'REQ-UI-034' <<<"$bl" \
    && ok tf_ledger_c "the row is still open work — not verified, not terminal, still listed" \
    || bad tf_ledger_c "an unmeasurable row fell out of the build list"
}

# --- tf-selfcheck: the round trip itself -------------------------------------------------
# Every one of the defects above was found mid-build in an application's repository and could
# only be fixed here, so each cost a switch between repos. tf-selfcheck runs the framework's
# own scripts against a project's real files BEFORE a build, so the finding arrives while the
# owner is still standing in the project. These cases pin the two things that make it worth
# running: it must catch a broken framework, and it must stay silent on a healthy one -- a
# check that cries wolf is the one that gets skimmed.
tf_selfcheck() {
  local sc="$UTILS/tf-selfcheck.sh"
  [[ -x "$sc" || -f "$sc" ]] || { bad tf_sc "tf-selfcheck.sh does not exist"; return; }

  # 1. a healthy project: no findings, exit 0. Built from the same fixture as tf_019 but
  #    with the stuck rows cleared, which is what a project in good shape looks like.
  local d="$SCRATCH/scgood"; mkdir -p "$d/docs" "$d/.tfcore"
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  sed 's/Needs re-verify | 40%/Verified | 100%/' "$(_checklist_fx scsrc)/docs/Fx-Checklist.md" \
    > "$d/docs/Fx-Checklist.md"
  local out rc
  out="$(bash "$sc" "$d" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]] && grep -q 'Nothing to file' <<<"$out"; then
    ok tf_sc_a "a healthy project reports nothing to file"
  else
    bad tf_sc_a "a healthy project produced findings (exit $rc)"; note "$(grep '^FAIL' <<<"$out" | head -2)"
  fi

  # 2. a project carrying an impossible record — the TF-015 shape. The emitter refuses to
  #    WRITE one now, so the only way it can be on a stream is history: the data cannot be
  #    recovered, every figure over duration is affected, and the project needs telling.
  local e; e="$(_metrics_fx scbad)"; mkdir -p "$e/docs" "$e/.tfcore"
  printf 'appPhase: 1\n' > "$e/.tfcore/core-config.yaml"
  cp "$d/docs/Fx-Checklist.md" "$e/docs/Fx-Checklist.md"
  _seed_orphan_amend "$e"
  out="$(bash "$sc" "$e" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]] && grep -q 'not on this stream' <<<"$out"; then
    ok tf_sc_b "a real defect is named before the build starts"
  else
    bad tf_sc_b "the orphaned amendment was not reported (exit $rc)"; note "$(head -8 <<<"$out")"
  fi

  # History is reported AS history. Those records cannot leave an append-only stream, the
  # emitter refuses new ones and the reader already discards them and says how many — so
  # calling them a framework failure would fire on every command in TechieBlog forever,
  # which is precisely how a check earns being skimmed (TF-012 cost exactly that).
  _seed_impossible "$e"
  out="$(bash "$sc" "$e" 2>&1)"
  grep -q '^--.*end before they start' <<<"$out" \
    && ok tf_sc_e "old impossible records are reported as history, not as a failure" \
    || bad tf_sc_e "an unfixable historical record was called a framework failure"
  _seed_orphan_amend "$e"

  # 3. --report hands back something the owner can paste, so filing costs a paste and not
  #    a page. The round trip is not only the fix — it is the paperwork on the way there.
  out="$(bash "$sc" "$e" --report 2>&1)"
  grep -q 'Blocks:' <<<"$out" && grep -q 'Not fixable here' <<<"$out" \
    && ok tf_sc_c "--report prints a feedback entry in the file's own shape" \
    || bad tf_sc_c "--report did not print a pasteable entry"

  # 4. it must never grade the application: no verdict, no checklist write
  local before after
  before="$(md5sum "$e/docs/Fx-Checklist.md" | cut -d' ' -f1)"
  bash "$sc" "$e" >/dev/null 2>&1
  after="$(md5sum "$e/docs/Fx-Checklist.md" | cut -d' ' -f1)"
  [[ "$before" == "$after" ]] && ok tf_sc_d "it writes nothing in the project" \
                              || bad tf_sc_d "the checklist changed under tf-selfcheck"
}

# --- TF-024: a phase BRD graded against the whole-project BRD template ------------------------
# A phase-2 BRD carries its own screens and requirements and points back at phase 1 for scope,
# users, the whole-app non-functionals, constraints and risks. The checker demanded all six and
# called the pointer section a stranger: 20 findings on TfLens's two phase BRDs, none fixable
# without copying phase 1 into them. TfLens 2026-09-10.
tf_024() {
  local d="$SCRATCH/phasebrd"; mkdir -p "$d/docs/mockups" "$d/.tfcore"
  printf 'appSize: L\nappKind: app\nappPhase: 2\n' > "$d/.tfcore/core-config.yaml"
  printf '<html><body data-testid="shell"><a href="reports.html">Reports</a></body></html>' > "$d/docs/mockups/reports.html"
  cat > "$d/docs/Fx-P2-BRD.md" <<'MD'
# Fx — Business Requirements — Phase 2: Reports

| | |
|---|---|
| App | Fx |
| Kind | app |
| Size | Small |
| Phase | 2 of 2 |
| Status | Draft |
| Date | 2026-09-11 |

## 1. Summary

Phase 2 adds monthly reports.

## 2. Screens and flow

| Screen | Route | Role | Mockup | Fields |
|---|---|---|---|---|
| Reports | `/reports` | Writer | [mockup](mockups/reports.html) | month |

## 3. Requirements

- **BRD-4** — Monthly report. *Screen:* Reports · *Mockup:* [mockup](mockups/reports.html)
  - *Acceptance:* When the writer picks a month on Reports, then the entry count for that month shows.

## 5. Development status

| Screen | Requirements | Verified | Open | Status |
|---|---|---|---|---|
| Reports | 1 | 0 | 1 | Planned |

## 6. Where the rest lives

| What | Where |
|---|---|
| Scope, users, constraints and risks | [phase 1 BRD](Fx-BRD.md) |
MD
  printf '# Fx — Business Requirements\n' > "$d/docs/Fx-BRD.md"
  local out shape
  out="$(python3 "$UTILS/tf-doc-check.py" --root "$d" --strict "$d/docs/Fx-P2-BRD.md" 2>&1)"
  shape="$(grep -E '^FAIL.*(is missing|is not in the template|comes after)' <<<"$out")"
  if [[ -z "$shape" ]]; then
    ok tf_024a "a phase BRD in its own shape draws no section findings"
  else
    bad tf_024a "a correct phase BRD is graded against the whole-project template"; note "$(head -3 <<<"$shape")"
  fi
  # the pointer is the only thing standing in for the six sections, so it must lead somewhere
  sed -i 's/\[phase 1 BRD\](Fx-BRD.md)/the first phase/' "$d/docs/Fx-P2-BRD.md"
  out="$(python3 "$UTILS/tf-doc-check.py" --root "$d" --strict "$d/docs/Fx-P2-BRD.md" 2>&1)"
  grep -q 'does not link to the phase-1 document (Fx-BRD.md)' <<<"$out" \
    && ok tf_024b "a phase BRD that points nowhere is refused" \
    || { bad tf_024b "a phase BRD with no link to phase 1 passed"; note "$(grep '^FAIL' <<<"$out" | head -2)"; }
  # not affected: phase 1 is still the whole-project BRD and still owes Scope
  out="$(python3 "$UTILS/tf-doc-check.py" --root "$d" --strict "$d/docs/Fx-BRD.md" 2>&1)"
  grep -q 'section "Scope" is missing' <<<"$out" \
    && ok tf_024c "the phase-1 BRD is still held to the whole-project template" \
    || { bad tf_024c "the phase-1 BRD escaped the whole-project template"; note "$(grep '^FAIL' <<<"$out" | head -2)"; }
  # the same for a phase UIDesign: the library, theme, design system and flow belong to phase 1.
  # TfLens's two phase UIDesigns drew 10 findings for leaving them out (owner, 2026-09-11)
  cat > "$d/docs/Fx-P2-UIDesign.md" <<'MD'
# Fx — UI Design — Phase 2: Reports

| | |
|---|---|
| App | Fx |
| Kind | app |
| Size | Small |
| Phase | 2 of 2 |

## Screens

### Screen: Reports (`/reports`)

**Mockup:** [mockups/reports.html](mockups/reports.html) · **Roles:** Writer · **BRD:** BRD-4

| Region | Control | Shows or binds |
|---|---|---|
| Month picker | Select | month |

| Field | Type | Required | Validation |
|---|---|---|---|
| Month | select | yes | a past month |

**States:** empty: no entries · loading: skeleton · error: alert

## Where the rest lives

| What | Where |
|---|---|
| Design system and the click-through flow | [phase 1 UI design](Fx-UIDesign.md) |
MD
  printf '# Fx — UI Design\n' > "$d/docs/Fx-UIDesign.md"
  out="$(python3 "$UTILS/tf-doc-check.py" --root "$d" --strict "$d/docs/Fx-P2-UIDesign.md" 2>&1)"
  shape="$(grep -E '^FAIL.*(is missing|is not in the template|comes after)' <<<"$out")"
  [[ -z "$shape" ]] && ok tf_024d "a phase UIDesign in its own shape draws no section or header findings" \
                    || { bad tf_024d "a correct phase UIDesign is graded against the whole-project template"; note "$(head -3 <<<"$shape")"; }
}

# --- a hand-off the owner could not use ---------------------------------------------------
# TfLens's closing message of 2026-09-11 was written in jargon, named two upstream problems
# without saying what they touch, called two problems fixed upstream on 2026-09-09 open, and
# said verify was pending with no line to paste. The Stop hook let it through: it checked the
# status file and never what the owner reads (MISS-TechieFlow-20260911-03).
owner_handoff() {
  local d="$SCRATCH/handoff"; mkdir -p "$d/docs/metrics" "$d/.tfcore/utils" "$d/.tfcore/standards" "$d/.tfcore/.session"
  cp "$UTILS"/tf-owner-text.* "$UTILS"/tf_feedback.py "$d/.tfcore/utils/" 2>/dev/null
  cp "$ROOT/.tfcore/standards/owner-words.txt" "$d/.tfcore/standards/" 2>/dev/null
  cat > "$d/docs/Fx-TechieFlow-Feedback.md" <<'MD'
# Fx — TechieFlow framework feedback

## Resolution status (TechieFlow team, 2026-09-09)

| ID | Fix | Verify from here |
|----|-----|------------------|
| **TF-022** | a skipped test is no longer a failure | re-run verify |

## TF-022 — a skipped test is counted as a failing one

- **Blocks:** no

## TF-024 — a phase BRD is graded against the whole-project template

- **Blocks:** no
MD
  printf '{"session_id":"x"}\n' > "$d/.tfcore/.session/claude-code.json"
  touch -d '-10 min' "$d/.tfcore/.session/claude-code.json"
  printf '# Fx — Status\n\n## Next command to run\n\n```\n/TechieFlow:agents:verifier *verify Fx all\n```\n' > "$d/PROJECT-STATUS.md"
  touch -d '-2 min' "$d/PROJECT-STATUS.md"; printf '<html></html>' > "$d/PROJECT-STATUS.html"
  printf '{"kind":"run","app":"Fx","cmd":"build-phase","ts":"%s"}\n' "$(date -u +%FT%TZ)" > "$d/docs/metrics/runs.jsonl"
  local tr="$d/transcript.jsonl"
  printf '{"type":"user","message":{"role":"user","content":"*build-phase Fx"},"timestamp":"%s.000Z"}\n' "$(date -u -d '-5 min' +%FT%T)" > "$tr"
  local bad='Done. TF-022 puts wrong FAILs into the checklist and TF-024 is filed too. The denominator now excludes voided runs. *verify has not been run.'
  local good='Built, and nothing is blocked.

| Problem | What it affects | Does it block or break anything? |
|---|---|---|
| TF-024 — the document check uses the wrong template for a phase BRD | Noise in the document check | No |

TF-022 was fixed upstream on 2026-09-09; the verify below re-checks it here.

```
/TechieFlow:agents:verifier *verify Fx all
```
In a TechieFlow window:
```
Fix TF-024 from docs/Fx-TechieFlow-Feedback.md in the Fx repo.
```'
  _stop() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"Stop","stop_hook_active":False,"last_assistant_message":sys.argv[1],"transcript_path":sys.argv[2]}))' "$1" "$tr" \
            | CLAUDE_PROJECT_DIR="$d" CLAUDECODE=1 bash "$ROOT/.tfcore/hooks/guard-status-html.sh" 2>&1; }
  local out rc
  out="$(_stop "$bad")"; rc=$?
  local miss=""
  for w in '"denominator"' 'TF-024 is named without saying what it affects' 'TF-022 is written about as an open problem' \
           '*verify is named, but no code block' 'gives no next prompt'; do
    grep -qF -- "$w" <<<"$out" || miss="$miss [$w]"
  done
  if [[ $rc -eq 2 && -z "$miss" ]]; then
    ok owner_handoff_a "TfLens's closing message is refused, and every one of its four faults is named"
  else
    bad owner_handoff_a "the closing message got through (exit $rc), or a fault went unnamed:$miss"; note "$(head -3 <<<"$out")"
  fi
  out="$(_stop "$good")"; rc=$?
  [[ $rc -eq 0 ]] && ok owner_handoff_b "the same news, written for the owner, ends the turn" \
                  || { bad owner_handoff_b "a closing message written for the owner was refused"; note "$(sed -n 2,4p <<<"$out")"; }
  # not affected: a later turn of ordinary conversation is not held to a hand-off's shape
  printf '{"type":"user","message":{"role":"user","content":"thanks"},"timestamp":"%s.000Z"}\n' "$(date -u -d '+1 min' +%FT%T)" >> "$tr"
  out="$(_stop "$bad")"; rc=$?
  [[ $rc -eq 0 ]] && ok owner_handoff_c "a turn that closed no command is left alone" \
                  || { bad owner_handoff_c "an ordinary reply was held to the hand-off check"; note "$(sed -n 2,3p <<<"$out")"; }
}

# --- the status file said every upstream problem was open ----------------------------------
# tf-status-facts counted every ### heading as an entry and accepted only a closing line no file
# used, so TfLens's PROJECT-STATUS read "TechieFlow: 62 open of 62" for 27 entries, 19 of them
# fixed or closed, and "TrBlazeUI: 2 open of 2" for 28. The agent reported two problems fixed two
# days earlier to the owner as open, and its self-check said "clean" (MISS-TechieFlow-20260911-04).
feedback_state() {
  local d="$SCRATCH/feedback"; mkdir -p "$d/docs"
  cat > "$d/docs/Fx-TechieFlow-Feedback.md" <<'MD'
# Fx — TechieFlow framework feedback

## Summary

**Nothing is blocked.** 3 entries, 3 open.

## Resolution status (TechieFlow team, 2026-09-09)

| ID | Fix | Verify from here |
|----|-----|------------------|
| **TF-019** | the list now holds every open row | run tf-build-list |

## TF-001 — the sessions stream is never de-duplicated

> ✅ **Closed 2026-08-28** — re-checked here: totals match.

### Repro
### Expected

## TF-019 — a gated row pins the build list

- **Blocks:** no

### Detail

## TF-025 — split-brd appends copies

- **Blocks:** no
MD
  cat > "$d/docs/Fx-TrBlazeUI-Feedback.md" <<'MD'
# Fx — TrBlazeUI feedback

> ## ✅ RESOLVED LIBRARY-SIDE 2026-08-31 — ships in the next release
>
> | Entry | Reported as | Reality |
> |---|---|---|
> | **TR-002** | no responsive variants | present on 2.1.0 |
>
> **Everything else is now fixed.**
>
> - **TR-003** — confirmed and fixed.

## Summary

- **3 entries, all 3 open.** None is fixed upstream.

## TR-002 — no responsive variants
## TR-003 — DataTable truncates
## TR-004 — merged into TR-002 (same defect)
## TR-009 — Badge wraps mid-phrase
MD
  local out
  out="$(cd "$d" && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import importlib.util as u
s = u.spec_from_file_location("sf", sys.argv[1] + "/tf-status-facts.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
print("\n".join(m.feedback_lines(".", "Fx")))' "$UTILS" 2>&1)"
  if grep -q "TechieFlow: 1 open · 1 fixed upstream, not yet re-checked (TF-019) · 1 closed" <<<"$out" \
     && grep -q "TrBlazeUI: 1 open · 2 fixed upstream, not yet re-checked (TR-002, TR-003) · 1 closed" <<<"$out"; then
    ok feedback_state_a "the status file counts entries, not headings, and names what is fixed upstream"
  else
    bad feedback_state_a "the status file miscounts the feedback files"; note "$(head -2 <<<"$out")"
  fi
  out="$(bash "$UTILS/tf-selfcheck.sh" "$d" 2>&1)"
  grep -q "TF-019 .*fixed 2026-09-09" <<<"$out" && grep -q "never report these as open" <<<"$out" \
    && ok feedback_state_b "the self-check names every fix waiting to be re-checked" \
    || { bad feedback_state_b "the self-check says nothing about fixes waiting here"; note "$(tail -3 <<<"$out")"; }
  out="$(cd "$d" && bash "$UTILS/tf-feedback.sh" Fx --close TF-019 "ran tf-build-list; all four rows listed" && bash "$UTILS/tf-feedback.sh" Fx)"
  grep -q "TechieFlow: 1 open · 2 closed" <<<"$out" \
    && ok feedback_state_c "a re-checked fix is closed with one command, and counted closed" \
    || { bad feedback_state_c "closing a re-checked entry did not take"; note "$(head -2 <<<"$out")"; }
  out="$(python3 "$UTILS/tf-doc-check.py" --root "$d" --strict "$d/docs/Fx-TrBlazeUI-Feedback.md" 2>&1)"
  grep -q "the Summary's counts are not the entries'" <<<"$out" \
    && ok feedback_state_d "a Summary that still says every entry is open is refused" \
    || { bad feedback_state_d "a stale Summary passed the document check"; note "$(grep FAIL <<<"$out" | head -2)"; }
}

# --- a fix nobody told the project about -------------------------------------------------
# TF-013 to TF-017 were fixed here on 2026-09-09 with a case each below, and the reply written
# into TfLens's feedback file listed only TF-018 onward; TfLens's file still showed all five open
# two days later. A problem this suite holds a case for has been fixed, so the framework's copy
# of the project's feedback file (docs/<App>-TechieFlow-Feedback.md here, which the owner copies
# across) must not read it as open (MISS-TechieFlow-20260911-04).
replies_complete() {
  local out
  out="$(python3 - "$ROOT" "$0" <<'PY'
import glob, os, re, sys
root, suite = sys.argv[1], open(sys.argv[2], encoding="utf-8").read()
sys.path.insert(0, os.path.join(root, ".tfcore", "utils"))
import tf_feedback
cased = {"TF-%s" % n for n in re.findall(r"(?m)^tf_0?(\d{2,3})\(\)", suite)}
cased = {("TF-%03d" % int(c[3:])) for c in cased}
# a project whose own numbering overlaps TfLens's has its cases under its own prefix
own = {"AppManager": {"TF-%03d" % int(n) for n in re.findall(r"(?m)^am_0?(\d{2,3})\(\)", suite)}}
for f in sorted(glob.glob(os.path.join(root, "docs", "*-TechieFlow-Feedback.md"))):
    app = os.path.basename(f).split("-")[0]
    for e in tf_feedback.entries(f):
        if e["id"] in own.get(app, cased) and e["state"] == "open":
            print("%s %s" % (os.path.basename(f), e["id"]))
PY
)"
  [[ -z "$out" ]] && ok replies_complete "every problem fixed here is answered in the project's feedback file" \
                  || { bad replies_complete "fixed here, still open in the project's file: $(tr '\n' ' ' <<<"$out")"; }
}

# --- TF-025: --add-missing copies rows it cannot see -------------------------------------
# A row naming its item inside a longer bracket — "(BRD-76, Phase 3)", "(BRD-118, BRD-120, Phase 3)"
# — with no *BRD:* detail line was invisible, so one new BRD item made --add-missing append a copy
# of every such row: 44 rows on TfLens phase 3 for 13 new items, 31 of them copies of Verified rows.
tf_025() {
  local d="$SCRATCH/addmissing"; mkdir -p "$d/docs" "$d/.tfcore"
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  cat > "$d/docs/Fx-BRD.md" <<'MD'
# Fx — Business Requirements

| | |
|---|---|
| Size | Small |

## Screens and flow

| Screen | Route | Role | Mockup | Fields |
|---|---|---|---|---|
| Coverage | `/coverage` | User | [m](mockups/coverage.html) | x |

## Requirements

- **BRD-76** — Coverage figure. *Screen:* Coverage
  - *Acceptance:* When a user opens Coverage on Coverage, then the figure shows.
- **BRD-118** — Coverage filter. *Screen:* Coverage
  - *Acceptance:* When a user filters on Coverage, then the rows narrow.
- **BRD-120** — Coverage export. *Screen:* Coverage
  - *Acceptance:* When a user exports on Coverage, then a file downloads.
- **BRD-189** — Coverage legend. *Screen:* Coverage
  - *Acceptance:* When a user opens Coverage on Coverage, then a legend shows.
MD
  cat > "$d/docs/Fx-Checklist.md" <<'MD'
# Fx — Checklist

## Requirements Status

| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-FN-068 | Coverage figure (BRD-76, Phase 3) | Verified | 100% | — | [view](#d-req-fn-068) |
| REQ-FN-070 | Coverage filter and export (BRD-118, BRD-120, Phase 3) | Verified | 100% | — | [view](#d-req-fn-070) |

## Page: Coverage

<a id="d-req-fn-068"></a>
- **REQ-FN-068** — Coverage figure
  - *Acceptance:* When a user opens Coverage on Coverage, then the figure shows.
MD
  local out; out="$(cd "$d" && python3 "$UTILS/tf-split-brd.py" Fx --add-missing 2>&1)"
  local n; n="$(grep -c '^| REQ-' "$d/docs/Fx-Checklist.md")"
  if [[ "$n" == "3" ]] && grep -q "Coverage legend" "$d/docs/Fx-Checklist.md"; then
    ok tf_025 "only the one new item is appended; rows naming items inside a longer bracket are seen"
  else
    bad tf_025 "--add-missing appended $((n - 2)) row(s) for 1 new item"; note "$out"
  fi
}

# --- TF-026: a stylesheet rule read as a control the page must carry ------------------------
# TfLens's shared mockup stylesheet styles the Add-source dialog with [data-testid="source-mode"]
# .tab{…}; the screen check read the whole file and reported "anchored control source-mode is not
# on the page" on /misses and /effort, which draw no such dialog.
tf_026() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_026 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/cssanchor"; mkdir -p "$d/docs/mockups"
  cat > "$d/docs/mockups/misses.html" <<'HTML'
<!doctype html><html><head><style>[data-testid="source-mode"] .tab{padding:4px}</style>
<script>var dialog = '[data-testid="source-picker"]';</script></head>
<body><!-- <div data-testid="old-banner"></div> --><h1 data-testid="page-title">Misses</h1>
<div data-testid="miss-table">rows</div><div data-testid="miss-legend">legend</div></body></html>
HTML
  # the app draws the title and the table, and genuinely lacks the legend
  cat > "$d/misses.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;font-family:system-ui">
<h1 data-testid="page-title">Misses</h1><div data-testid="miss-table">rows of misses</div></body></html>
HTML
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-verify-screens.mjs" "$d/screens.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  local out
  out="$( cd "$d" && node screens.mjs --base "http://127.0.0.1:$port" --screen "misses=/misses.html" \
          --widths 1280 --json-out "$d/screens.json" 2>&1 )"
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  if grep -qE '"(source-mode|source-picker|old-banner)"' <<<"$out"; then
    bad tf_026a "a name in the mockup's stylesheet, script or a comment was demanded of the page"; note "$(grep -E 'source-|old-banner' <<<"$out" | head -1)"
  else
    ok tf_026a "only anchors on the mockup's elements are demanded of the page"
  fi
  grep -q '"miss-legend" is not on the page' <<<"$out" \
    && ok tf_026b "a control the mockup really draws and the page lacks is still reported" \
    || { bad tf_026b "a genuinely missing control went unreported"; note "$(grep misses <<<"$out" | head -2)"; }
}

# --- TF-027: an icon one wrapper deeper, and a colour written in oklch() ---------------------
# mockup-parity pairs elements by position, so an icon the component library wraps in one more
# element was "missing" on every sidebar group and tile; and a tile themed in oklch() read as
# neutral because the colour string was parsed as r/g/b numbers — 136 findings at 1280 px on two
# TfLens screens, most of them describing icons and colours plainly on screen.
tf_027() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_027 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/parity"; mkdir -p "$d/docs/mockups"
  local ico='<svg width="16" height="16" viewBox="0 0 16 16"><rect width="16" height="16"/></svg>'
  cat > "$d/docs/mockups/effort.html" <<HTML
<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font-family:system-ui}
.tile{width:200px;height:60px;background:rgb(239,68,68);color:#fff}nav a{display:block;height:24px}</style></head>
<body><nav data-testid="app-sidebar"><div><a href="#">${ico}Misses</a><a href="#">${ico}Effort</a></div></nav>
<div data-testid="kpi-rework" class="tile">Rework 12</div></body></html>
HTML
  # the app: the library wraps the links in one more element; the first keeps its icon, the second
  # has really lost it, and the tile is red in oklch()
  cat > "$d/effort.html" <<HTML
<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font-family:system-ui}
.tile{width:200px;height:60px;background:oklch(0.637 0.237 25.331);color:#fff}nav a{display:block;height:24px}</style></head>
<body><nav data-testid="app-sidebar"><div><div class="group"><a href="#">${ico}Misses</a><a href="#">Effort</a></div></div></nav>
<div data-testid="kpi-rework" class="tile">Rework 12</div></body></html>
HTML
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-mockup-parity.mjs" "$d/parity.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  ( cd "$d" && node parity.mjs --base "http://127.0.0.1:$port" --screen "effort=/effort.html" --widths 1280 \
      --json-out "$d/parity.json" >/dev/null 2>&1 )
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  local out; out="$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for s in d["screens"]:
    for f in s.get("findings") or []:
        print(f["class"], f["key"], "|", f["detail"])' "$d/parity.json" 2>&1)"
  if grep -q "semantic colour differs" <<<"$out"; then
    bad tf_027a "a tile red in oklch() is read as another colour"; note "$(grep 'semantic colour' <<<"$out" | head -1)"
  else
    ok tf_027a "a colour written in oklch() is read as the colour it is"
  fi
  local missing; missing="$(grep -c '^missing' <<<"$out")"
  if [[ "$missing" == "1" ]]; then
    ok tf_027b "an icon one wrapper deeper is found; the one really gone is still reported"
  else
    bad tf_027b "$missing missing-icon finding(s) where exactly one icon is gone"; note "$(grep '^missing' <<<"$out" | head -3)"
  fi
}

# --- TF-028: a closing line under a heading with no title --------------------------------
# TfLens's `## TF-013` had no title. The reader's heading pattern let `\s` run past the line
# break and took the next line with text as the title — after --close, the closing line itself —
# so --close printed "TF-013 closed" and the entry still read fixed (2026-09-11).
tf_028() {
  local d="$SCRATCH/tf028"; mkdir -p "$d/docs"
  cat > "$d/docs/Fx-TechieFlow-Feedback.md" <<'MD'
# Fx — TechieFlow Feedback

## Resolution status (TechieFlow team, 2026-09-09)

| Entry | Fix |
|---|---|
| TF-001 | fixed |
| TF-002 | fixed |

## TF-001

- **Severity:** major
- **Blocks:** no

## TF-002 — a titled entry

- **Severity:** minor
MD
  local out; out="$(cd "$d" && bash "$UTILS/tf-feedback.sh" Fx)"
  if grep -qE "^  TF-001 +fixed +2026-09-09 *$" <<<"$out"; then
    ok tf_028a "a heading with no title has no title, not the line after it"
  else
    bad tf_028a "a bare heading took the next line as its title"; note "$(grep 'TF-001' <<<"$out" | tail -1)"
  fi
  out="$(cd "$d" && bash "$UTILS/tf-feedback.sh" Fx --close TF-001 "ran the check; it passed" && bash "$UTILS/tf-feedback.sh" Fx)"
  if grep -q "TechieFlow: 0 open · 1 fixed upstream, not yet re-checked (TF-002) · 1 closed" <<<"$out"; then
    ok tf_028b "a closing line under a heading with no title is read as closed"
  else
    bad tf_028b "--close wrote its line and the entry still does not read closed"; note "$(head -1 <<<"$out")"
  fi
}

# --- TF-029: a miss logged inside another command, and a marker left by a dead session ----
# *amend-docs step 10 logs a miss. tf-log-miss took its run's start from the command marker
# whatever command owned it, so it wrote a log-miss run over the amendment's own window; the
# amendment's record was then refused for overlap, and TfLens voided the log-miss one by hand
# (2026-09-11). It also read a marker of any age, where every other reader ignores one past 24 h.
tf_029() {
  local d; d="$(_metrics_fx logmissfx)"
  mkdir -p "$d/.tfcore/.session"; cp -r "$UTILS" "$d/.tfcore/"
  local t0; t0="$(date -u -d '-10 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"cmd":"amend-docs","app":"Fx","started":"%s"}\n' "$t0" > "$d/.tfcore/.session/phase.json"
  lm() { ( cd "$d" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d" bash .tfcore/utils/tf-log-miss.sh Fx --what "$1" \
           --sort spec --class unspecified-gap --artifact brd --severity minor --fixed ) 2>&1; }
  lm "the BRD never said the export names its columns" >/dev/null
  lm "the BRD never said the filter survives a reload" >/dev/null
  local runs; runs="$(grep -c '"kind":"run"' "$d/docs/metrics/runs.jsonl")"
  [[ "$runs" == "0" ]] && ok tf_029a "a miss logged inside *amend-docs writes no run record of its own" \
                       || { bad tf_029a "$runs log-miss run record(s) written over the amendment's window"; note "$(grep '"kind":"run"' "$d/docs/metrics/runs.jsonl" | head -1 | cut -c1-160)"; }
  local out; out="$(echo "{\"kind\":\"run\",\"app\":\"Fx\",\"cmd\":\"amend-docs\",\"started\":\"$t0\"}" \
                   | ( cd "$d" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d" bash .tfcore/utils/tf-emit.sh runs ) 2>&1)"
  if ! grep -q REFUSED <<<"$out" && grep -q '"cmd":"amend-docs"' "$d/docs/metrics/runs.jsonl"; then
    ok tf_029b "the amendment's own run record is accepted afterwards"
  else
    bad tf_029b "the amendment's run record was refused"; note "$(grep REFUSED <<<"$out" | head -1 | cut -c1-160)"
  fi
  local misses; misses="$(grep -c "\"found_run_id\":\"$t0\"" "$d/docs/metrics/misses.jsonl")"
  [[ "$misses" == "2" ]] && ok tf_029c "both misses are recorded, each naming the amendment's start" \
                         || bad tf_029c "$misses of 2 misses carry the amendment's start"
  # a *log-miss marker three days old: the session died; the run starts now, not three days ago
  local d2; d2="$(_metrics_fx logmissstale)"
  mkdir -p "$d2/.tfcore/.session"; cp -r "$UTILS" "$d2/.tfcore/"
  printf '{"cmd":"log-miss","app":"Fx","started":"%s"}\n' "$(date -u -d '-3 days' +%Y-%m-%dT%H:%M:%SZ)" > "$d2/.tfcore/.session/phase.json"
  ( cd "$d2" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d2" bash .tfcore/utils/tf-log-miss.sh Fx --what "the page title is wrong" \
      --sort spec --severity minor --fixed ) >/dev/null 2>&1
  local st; st="$(python3 -c "import json,sys
r=[json.loads(l) for l in open(sys.argv[1]) if '\"kind\":\"run\"' in l]
print(r[0]['started'] if r else 'none')" "$d2/docs/metrics/runs.jsonl")"
  if [[ "$st" != "none" && "$st" > "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)" ]]; then
    ok tf_029d "a *log-miss run still gets its record, and a marker from a dead session is ignored"
  else
    bad tf_029d "the log-miss run started at $st, from a marker three days old"
  fi
}

# --- TF-030: a screen named only inside a requirement ------------------------------------
# TfLens's BRD-200 added "a **Price providers** screen" with no row in the Screens and flow
# table. The checker compared only that table with the UI design, so it never saw the screen;
# the one related finding was on the checklist and passed as old. The page was built and
# verified with no design (2026-09-11).
tf_030() {
  local d="$SCRATCH/tf030"; mkdir -p "$d/docs" "$d/.tfcore/.session"
  cp -r "$UTILS" "$ROOT/.tfcore/templates" "$d/.tfcore/"
  cat > "$d/docs/Fx-BRD.md" <<'MD'
# Fx — BRD

## 4. Screens and flow

| Screen | Route | Role | Mockup | Fields |
|---|---|---|---|---|
| Repos | `/repos` | User | [mockup](mockups/repos.html) | name |

## 5. Requirements

- **BRD-1** — User can list repos. *Screen:* Repos · *Mockup:* [mockup](mockups/repos.html)
MD
  cat > "$d/docs/Fx-P3-BRD.md" <<'MD'
# Fx — Phase 3 BRD

## 2. Screens and flow

| Screen | Route | Role | Mockup | Fields |
|---|---|---|---|---|
| Misses | `/misses` | User | [mockup](mockups/misses.html) | what |

## 3. Requirements

- **BRD-200** — User can see, on a **Price providers** screen, every provider a rate comes from.
- **BRD-201** — User can change a rate. *Screen:* Settings · *Mockup:* [mockup](mockups/settings.html)
- **BRD-202** — User can open a repo from the **Repos** screen, which phase 1 owns.
- **BRD-203** — Every figure on **every** screen shows its denominator.
MD
  local out; out="$(python3 "$d/.tfcore/utils/tf-doc-check.py" --root "$d" --strict "$d/docs/Fx-P3-BRD.md" 2>&1)"
  if grep -q 'BRD-200 names the screen "Price providers"' <<<"$out" && grep -q 'BRD-201 names the screen "Settings"' <<<"$out"; then
    ok tf_030a "a screen named only inside a requirement, in either form, is refused by name"
  else
    bad tf_030a "the checker did not see a screen named only inside a requirement"; note "$(grep FAIL <<<"$out" | head -2)"
  fi
  if grep -qE 'names the screen "(Repos|every)"' <<<"$out"; then
    bad tf_030b "a screen another phase owns, or the word 'every', was reported"; note "$(grep 'names the screen' <<<"$out" | head -2)"
  else
    ok tf_030b "a screen another phase's BRD owns is not reported, nor is 'every screen'"
  fi
  # the end-of-turn hook: a turn that wrote the BRD cannot end with the screen unfinished
  printf '{}' > "$d/.tfcore/.session/claude-code.json"; cp "$d/.tfcore/.session/claude-code.json" "$d/.tfcore/.session/opencode.json"
  touch -d '-10 minutes' "$d/.tfcore/.session/claude-code.json" "$d/.tfcore/.session/opencode.json"
  printf '# Fx — Project status\n' > "$d/PROJECT-STATUS.md"; cp "$d/PROJECT-STATUS.md" "$d/PROJECT-STATUS.html"; touch "$d/docs/Fx-P3-BRD.md"
  local rc; out="$(printf '{}' | CLAUDE_PROJECT_DIR="$d" bash "$ROOT/.tfcore/hooks/guard-status-html.sh" 2>&1)"; rc=$?
  if [[ $rc -eq 2 ]] && grep -q "has no row, UI design entry or mockup" <<<"$out" && grep -q 'Price providers' <<<"$out"; then
    ok tf_030c "the turn that wrote the BRD cannot end while the screen has no row, design entry or mockup"
  else
    bad tf_030c "the end-of-turn hook let the unfinished screen through (exit $rc)"; note "$(grep -i screen <<<"$out" | head -2)"
  fi
}

# --- TF-031: --base never reached the browser tests --------------------------------------
# tf-verify-tests.sh passed --base as BASE_URL, which Playwright never reads by itself, and the
# config tf-verify-env.sh wrote had no baseURL. TfLens booted on 5014 and every test opened 5099;
# with an older build still on 5099, its passes would have been recorded for the new one (2026-09-11).
tf_031() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_031 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  _pwfx() { local d="$SCRATCH/$1"; mkdir -p "$d/tests/verify"; ln -sfn "$pw/node_modules" "$d/node_modules"
            printf '{"name":"fx","version":"1.0.0"}\n' > "$d/package.json"; printf '%s' "$d"; }
  local d out
  d="$(_pwfx tf031a)"; ( cd "$d" && bash "$UTILS/tf-verify-env.sh" ) >/dev/null 2>&1
  grep -q "baseURL: process.env.BASE_URL" "$d/playwright.config.ts" 2>/dev/null \
    && ok tf_031a "the config the framework writes opens the address --base gives" \
    || bad tf_031a "the written config has no baseURL read from BASE_URL"
  d="$(_pwfx tf031b)"
  printf "import { defineConfig } from '@playwright/test';\nexport default defineConfig({\n  testDir: './tests/verify',\n  outputDir: './tests/.artifacts/test-results',\n  use: { baseURL: 'http://localhost:5099', headless: true },\n});\n" > "$d/playwright.config.ts"
  ( cd "$d" && bash "$UTILS/tf-verify-env.sh" ) >/dev/null 2>&1
  grep -q "baseURL: process.env.BASE_URL || 'http://localhost:5099'" "$d/playwright.config.ts" \
    && ok tf_031b "a project's own baseURL now reads BASE_URL first and keeps its address as the fallback" \
    || { bad tf_031b "a config with its own baseURL still ignores --base"; note "$(grep baseURL "$d/playwright.config.ts")"; }
  # a config nobody repaired: the runner refuses rather than test the default port
  d="$(_pwfx tf031c)"
  printf "import { defineConfig } from '@playwright/test';\nexport default defineConfig({ testDir: './tests/verify', use: { baseURL: 'http://127.0.0.1:9' } });\n" > "$d/playwright.config.ts"
  printf "import { test } from '@playwright/test';\ntest('REQ-UI-001 opens', async ({ page }) => { await page.goto('/'); });\n" > "$d/tests/verify/fx.spec.ts"
  out="$(cd "$d" && timeout 120 bash "$UTILS/tf-verify-tests.sh" --base http://127.0.0.1:5014 --no-unit 2>&1)"
  if grep -q "NOT RUN — nothing reads BASE_URL" <<<"$out" && ! grep -q "browser tests: ran" <<<"$out"; then
    ok tf_031c "a run with --base refuses when nothing reads BASE_URL, instead of testing another address"
  else
    bad tf_031c "the tests ran against the config's own address, not --base"; note "$(grep 'browser tests' <<<"$out")"
  fi
}

# --- TF-032 and TF-033: a sidebar the mockup hides on a phone, and a sign-in that never submitted -
# TF-032: every anchor in the mockup's markup was owed at every width, so a sidebar the mockup hides
# below 768px failed /misses and /effort at 390px — twelve RENDER-FAIL rows on TfLens (2026-09-11).
# TF-033: the sign-in button was the first test id containing "login", which was the email field.
tf_032() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_032 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/tf032"; mkdir -p "$d/docs/mockups"
  cat > "$d/docs/mockups/misses.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font-family:system-ui}
aside{width:200px;height:300px;background:#eee}@media (max-width:767px){aside{display:none}}
.dialog{display:none}</style></head><body><aside data-testid="app-sidebar">Misses · Effort</aside>
<h1 data-testid="page-title">Misses</h1><button data-testid="export-btn">Export</button>
<div class="dialog" data-testid="confirm-dialog">Sure?</div></body></html>
HTML
  # the app: the sidebar is added only on a wide screen (on a phone the menu button opens it); the
  # export button and the dialog were never built, so both must still be reported
  cat > "$d/misses.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font-family:system-ui}
aside{width:200px;height:300px;background:#eee}</style></head><body>
<script>if (innerWidth >= 768) document.write('<aside data-testid="app-sidebar">Misses · Effort</aside>');</script>
<h1 data-testid="page-title">Misses</h1><p>Ten misses are open.</p></body></html>
HTML
  cat > "$d/login.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:system-ui}</style></head><body>
<form action="/misses.html" method="get"><input data-testid="login-email" name="u" type="email">
<input data-testid="login-pass" name="p" type="password"><button data-testid="login-submit" type="submit">Sign in</button></form></body></html>
HTML
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-verify-screens.mjs" "$d/screens.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  local out
  out="$( cd "$d" && timeout 180 node screens.mjs --base "http://127.0.0.1:$port" --screen misses=/misses.html \
          --widths 1280,390 --login-path /login.html --user a@b.c --password x --render-wait 1000 --json-out "$d/screens.json" 2>&1 )"
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  local w390; w390="$(python3 -c "import json,sys
r=json.load(open(sys.argv[1]))['screens'][0]
print(' | '.join(f['detail'] for w in r['widths'] if w['width']==390 for f in w.get('findings',[])))" "$d/screens.json" 2>/dev/null)"
  if ! grep -q 'app-sidebar' <<<"$w390"; then
    ok tf_032a "a sidebar the mockup hides on a phone is not owed at 390px"
  else
    bad tf_032a "the sidebar the mockup hides on a phone is still required at 390px"; note "$w390"
  fi
  if grep -q '"export-btn" is not on the page' <<<"$w390" && grep -q '"confirm-dialog" is not on the page' <<<"$w390"; then
    ok tf_032b "a control the mockup shows at 390px, and a dialog it hides at every width, are still owed"
  else
    bad tf_032b "the width fix excused controls it should not"; note "$w390"
  fi
  if ! grep -q 'LOGIN failed' <<<"$out" && python3 -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))['login'].get('ok') else 1)" "$d/screens.json" 2>/dev/null; then
    ok tf_033 "sign-in presses the submit button, not the first field whose test id says login"
  else
    bad tf_033 "sign-in clicked a field and never submitted"; note "$(grep LOGIN <<<"$out")"
  fi
}

# --- TF-034: two builders booting side by side --------------------------------------------
# One state file and one log for the whole repository: the second start emptied the first's log
# and a bare `stop` killed whichever app was named last — one TfLens builder stopped another's app
# on port 5147 (2026-09-11). Proved with the static head, which boots in a second.
tf_034() {
  local d="$SCRATCH/tf034"; mkdir -p "$d/a" "$d/b"; echo '<p>a</p>' > "$d/a/index.html"; echo '<p>b</p>' > "$d/b/index.html"
  local p1 p2; p1="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  p2="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  up() { curl -s -o /dev/null -m 2 "http://localhost:$1/" 2>/dev/null; }
  ( cd "$d" && bash "$UTILS/tf-verify-boot.sh" start --static a --port "$p1" ) >/dev/null 2>&1
  ( cd "$d" && bash "$UTILS/tf-verify-boot.sh" start --static b --port "$p2" ) >/dev/null 2>&1
  if [[ -f "$d/tests/.artifacts/verify/boot-$p1.json" && -f "$d/tests/.artifacts/verify/boot-$p2.json" && -s "$d/tests/.artifacts/verify/app-$p1.log" ]]; then
    ok tf_034a "each app has its own state file and log, and the second start leaves the first's log alone"
  else
    bad tf_034a "the second start overwrote the first app's state or emptied its log"
  fi
  local out; out="$(cd "$d" && bash "$UTILS/tf-verify-boot.sh" stop 2>&1)"
  if grep -q "NOT-STOPPED 2 apps are running" <<<"$out" && up "$p1" && up "$p2"; then
    ok tf_034b "a bare stop while two apps run refuses and names the ports, and stops neither"
  else
    bad tf_034b "a bare stop with two apps running stopped one of them"; note "$out"
  fi
  ( cd "$d" && bash "$UTILS/tf-verify-boot.sh" stop --port "$p2" ) >/dev/null 2>&1; sleep 1
  if up "$p1" && ! up "$p2"; then
    ok tf_034c "stop --port stops that app and leaves the other builder's running"
  else
    bad tf_034c "stop --port did not stop only its own app"
  fi
  ( cd "$d" && bash "$UTILS/tf-verify-boot.sh" stop --port "$p1"; bash "$UTILS/tf-verify-boot.sh" stop ) >/dev/null 2>&1
  pkill -f "http.server $p1" 2>/dev/null; pkill -f "http.server $p2" 2>/dev/null; true
}

# --- TF-035: a locked output file, and a build that changes side over one obj/ --------------
# MSB3021 "Access to the path … is denied" matched neither the code-error nor the wrong-rung
# pattern, so the loop fell to the Windows rung, which built in the same obj/; the scoped
# stylesheets kept the WSL names while the dll carried the Windows ones, and every page's own styles
# stopped applying on TfLens (2026-09-11). Stand-in dotnet and cmd.exe on PATH; nothing is built.
tf_035() {
  local d="$SCRATCH/tf035"; mkdir -p "$d/bin" "$d/home" "$d/p/obj/Debug/net10.0/scopedcss/bundle"
  printf '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>\n' > "$d/p/Fx.csproj"
  printf '.b-wsl1{}\n' > "$d/p/obj/Debug/net10.0/scopedcss/bundle/Fx.styles.css"
  printf '#!/usr/bin/env bash\necho "Fx -> ok"; echo called >> "%s/cmd.calls"; exit 0\n' "$d" > "$d/bin/cmd.exe"
  printf '#!/usr/bin/env bash\necho "error MSB3021: Unable to copy file \\"obj/Fx.dll\\" to \\"bin/Fx.dll\\". Access to the path '"'"'bin/Fx.dll'"'"' is denied."; exit 1\n' > "$d/bin/dotnet"
  chmod +x "$d/bin/"*
  run_b() { ( cd "$d" && HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" TF_BUILD_PLATFORM=wsl TF_BUILD_LOCK_WAIT=0 \
              bash "$UTILS/tf-build.sh" build p/Fx.csproj ) 2>&1; }
  local out; out="$(run_b)"
  if grep -q "^NOT-RUN the build output is held by a running process" <<<"$out" && [[ ! -f "$d/cmd.calls" ]]; then
    ok tf_035a "a locked output file is reported as a lock, and no other rung builds over the same obj/"
  else
    bad tf_035a "a locked output file fell through to the Windows rung"; note "$(tail -1 <<<"$out")"
  fi
  # a rung that really is wrong on the WSL side: the Windows rung builds, and first clears what WSL built
  printf '#!/usr/bin/env bash\necho "error NETSDK1178: workload missing"; exit 1\n' > "$d/bin/dotnet"
  echo wsl > "$d/p/obj/.tf-build-side"
  out="$(run_b)"
  if grep -q "^PASS" <<<"$out" && [[ ! -d "$d/p/obj/Debug/net10.0/scopedcss" ]] && [[ "$(cat "$d/p/obj/.tf-build-side")" == windows ]]; then
    ok tf_035b "a build that moves to the Windows side first clears the scoped stylesheets the WSL side built"
  else
    bad tf_035b "the Windows rung built over scoped stylesheets the WSL side had named"; note "$(head -2 <<<"$out")"
  fi
}

# --- TF-037: a note line read as the build's verdict ---------------------------------------
# tf-verify-tests kept the FIRST line tf-build.sh printed. Yesterday's TF-035 fix added a note
# line before the verdict, so 975 passing TfLens unit tests were recorded as never run and 17 rows
# lost their only test. The same fix counted a log file that does not exist yet, and the shell's
# error about it became the first line (2026-09-11).
tf_037() {
  local d="$SCRATCH/tf037"; mkdir -p "$d/.tfcore" "$d/tests/verify" "$d/tests/.artifacts/build" "$d/tests/Fx.Tests"
  cp -r "$UTILS" "$d/.tfcore/"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$d/tests/Fx.Tests/Fx.Tests.csproj"
  cat > "$d/tests/.artifacts/build/unit.log" <<'LOG'
  Passed REQ-FN-072 reads the stream [12 ms]
Passed!  - Failed: 0, Passed: 975, Skipped: 0, Total: 975
LOG
  cat > "$d/.tfcore/utils/tf-build.sh" <<'SH'
#!/usr/bin/env bash
echo "note  the scoped stylesheets were built on the other side of this machine; cleared so the windows build names them itself"
echo "PASS  test on wsl via cmd.exe /c dotnet (rung 4) — 0 warning line(s); log tests/.artifacts/build/unit.log"
SH
  local out; out="$( cd "$d" && bash .tfcore/utils/tf-verify-tests.sh --no-browser --json-out tests/.artifacts/verify/tests.json 2>&1 )"
  local ran; ran="$(python3 -c "import json,sys
try: print(json.load(open(sys.argv[1]))['unit'].get('ran'))
except Exception as e: print('none')" "$d/tests/.artifacts/verify/tests.json")"
  if [[ "$ran" == "True" ]]; then
    ok tf_037a "the build's verdict line is read, not a note printed before it"
  else
    bad tf_037a "a note line was taken for the verdict, so the unit tests read as never run"; note "$(grep -i unit <<<"$out" | head -1)"
  fi
  # and the build script itself says nothing before its verdict when its log is not there yet
  local e="$SCRATCH/tf037b"; mkdir -p "$e/bin"
  printf '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>\n' > "$e/Fx.csproj"
  printf '#!/usr/bin/env bash\necho "Build succeeded."; exit 0\n' > "$e/bin/dotnet"; chmod +x "$e/bin/dotnet"
  local first; first="$( cd "$e" && PATH="$e/bin:/usr/bin:/bin" HOME="$e" TF_BUILD_PLATFORM=wsl bash "$UTILS/tf-build.sh" build Fx.csproj 2>&1 | head -1 )"
  if grep -qE '^(PASS|FAIL|NOT-RUN)' <<<"$first"; then
    ok tf_037b "the build's first line is its verdict, not a shell error about a log not yet written"
  else
    bad tf_037b "the build printed something before its verdict"; note "$first"
  fi
}

# --- TF-038 and TF-039: a transparent border, and a table scrolling inside its card ----------
# A `border: 1px solid transparent` counted as a drawn border, so every ghost button read as a
# badge with a solid ring, and a borderless icon took its colour from a reset's border-color:
# 13 of 15 findings on TfLens /prices. The clip clause measured descendants unclipped, so a table
# scrolling inside its wrapper read as a card cut off at 390px (2026-09-11).
tf_038() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_038 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/tf038"; mkdir -p "$d/docs/mockups"
  # The mockup: a transparent border reserving space, an icon coloured by `color`, and a wide table
  # scrolling inside its card. The app draws the same things — no border at all, the same icon
  # colour, the same scrolling table — but carries a reset that sets border-color on everything and
  # a screen-reader-only span inside the card, which is what sent the old tool down both wrong paths.
  cat > "$d/docs/mockups/prices.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>
 body{margin:0;font-family:system-ui;width:340px}
 .btn{border:1px solid transparent;height:28px;border-radius:8px;padding:0 8px;background:none}
 .card{width:340px}.scroller{overflow-x:auto}table{width:900px;border-collapse:collapse}td{padding:4px}
 .chip{background:#dbeafe;display:inline-block}svg{width:16px;height:16px;color:#2563eb}
</style></head><body>
 <button data-testid="btn-ghost" class="btn">Add a provider</button>
 <span data-testid="chip" class="chip"><svg data-testid="chip-icon" viewBox="0 0 16 16"><path d="M1 1h14v14H1z" fill="currentColor"/></svg></span>
 <div data-testid="effort-phases" class="card"><div class="scroller"><table><tr><td>one</td><td>two</td><td>three</td><td>four</td><td>five</td></tr></table></div></div>
</body></html>
HTML
  cat > "$d/prices.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>
 *{border-color:#9ca3af}body{margin:0;font-family:system-ui;width:340px}
 .btn{border:none;height:28px;border-radius:8px;padding:0 8px;background:none}
 .card{width:340px}.scroller{overflow-x:auto}table{width:900px;border-collapse:collapse}td{padding:4px}
 .chip{background:#dbeafe;display:inline-block}svg{width:16px;height:16px;color:#2563eb}
 .sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}
</style></head><body>
 <button data-testid="btn-ghost" class="btn">Add a provider</button>
 <span data-testid="chip" class="chip"><svg data-testid="chip-icon" viewBox="0 0 16 16"><path d="M1 1h14v14H1z" fill="currentColor"/></svg></span>
 <div data-testid="effort-phases" class="card"><span class="sr">five rows</span><div class="scroller"><table><tr><td>one</td><td>two</td><td>three</td><td>four</td><td>five</td></tr></table></div></div>
</body></html>
HTML
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-mockup-parity.mjs" "$d/parity.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  local out; out="$( cd "$d" && timeout 180 node parity.mjs --base "http://127.0.0.1:$port" --screen prices=/prices.html \
                     --widths 390 --json-out "$d/parity.json" 2>&1 )"
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  if ! grep -qE 'border style differs|badge/pill' <<<"$out"; then
    ok tf_038a "a border of transparent pixels is not read as a drawn one"
  else
    bad tf_038a "a transparent border still reads as a ring"; note "$(grep -E 'border|badge' <<<"$out" | head -2)"
  fi
  if ! grep -q 'semantic colour differs' <<<"$out"; then
    ok tf_038b "a borderless icon takes its colour from what it draws, not from a reset's border-color"
  else
    bad tf_038b "the reset's border colour is still read as the icon's"; note "$(grep 'semantic colour' <<<"$out" | head -1)"
  fi
  if ! grep -q 'cut off horizontally' <<<"$out"; then
    ok tf_039 "a table scrolling inside its own card is not reported as cut off"
  else
    bad tf_039 "the clip clause still measures descendants unclipped"; note "$(grep 'cut off' <<<"$out" | head -1)"
  fi
}

# --- TF-040: a command that chains another one, and its own first segment -------------------
# The rule compared a new record against the NEWEST record only, so *build-phase, which chains
# *verify inside itself and finishes after it, could never record the 80 minutes and five builder
# clusters it ran BEFORE the verify started (TfLens, 2026-09-11). Windows are compared now.
tf_040() {
  local d; d="$(_metrics_fx overlapgap)"
  emit40() { echo "$1" | ( cd "$d" && bash "$UTILS/tf-emit.sh" runs ) 2>&1; }
  n40() { grep -c '"kind":"run"' "$d/docs/metrics/runs.jsonl" 2>/dev/null || echo 0; }
  # the chained verify writes its record first, as it does today
  emit40 '{"kind":"run","app":"Fx","cmd":"verify-phase","started":"2026-09-11T18:13:36Z","ended":"2026-09-11T21:13:15Z"}' >/dev/null
  local out; out="$(emit40 '{"kind":"run","app":"Fx","cmd":"build-phase","started":"2026-09-11T16:53:16Z","ended":"2026-09-11T18:13:36Z"}')"
  if ! grep -q REFUSED <<<"$out" && [[ "$(n40)" == "2" ]]; then
    ok tf_040a "the outer command records the segment it ran before the run it chained"
  else
    bad tf_040a "a record wholly before the newest one was refused"; note "$(head -1 <<<"$out")"
  fi
  # and a record that really does overlap an older one is still refused
  out="$(emit40 '{"kind":"run","app":"Fx","cmd":"fix-issues","started":"2026-09-11T17:30:00Z","ended":"2026-09-11T19:00:00Z"}')"
  if grep -qE "overlaps the (build-phase|verify-phase) run of Fx" <<<"$out" && [[ "$(n40)" == "2" ]]; then
    ok tf_040b "a record that overlaps an earlier one is still refused, and says which"
  else
    bad tf_040b "an overlapping record reached the stream"; note "$(head -1 <<<"$out")"
  fi
}

# --- TF-041: the Phases document is on disk but was not named ------------------------------
# The cross-phase rule read the documents named on the command line only, so a status gate that
# named the checklists and not docs/<App>-Phases.md was told to write a file that is there — over
# the top of the real one (TfLens, 2026-09-11).
tf_041() {
  local d="$SCRATCH/tf041"; mkdir -p "$d/docs"
  cat > "$d/docs/Fx-Phases.md" <<'MD'
# Fx — Phases

| | |
|---|---|
| App | Fx |
| Kind | app |
| Size | Large |
| Date | 2026-09-11 |

## Phases

| Phase | Name | Screens | BRD range | Status |
|---|---|---|---|---|
| 1 | Core | Repos | BRD-1 to BRD-50 | done |
| 2 | Reports | Misses | BRD-51 to BRD-99 | building |
MD
  for n in "" "-P2"; do
    cat > "$d/docs/Fx${n}-Checklist.md" <<'MD'
# Fx — Requirements Checklist

## Requirements Status

| ID | Title | Status | % | Remarks | Detail |
|---|---|---|---|---|---|
| REQ-FN-001 | Lists repos | Verified | 100% | — | [view](#d-req-fn-001) |

## Coverage

- <a id="d-req-fn-001"></a>**REQ-FN-001** — Lists repos (BRD-1)
  - Acceptance: When a user opens Repos on Repos, then the list shows.
MD
  done
  sed -i 's/REQ-FN-001/REQ-FN-002/g; s/req-fn-001/req-fn-002/g' "$d/docs/Fx-P2-Checklist.md"
  local out
  out="$(python3 "$UTILS/tf-doc-check.py" --root "$d" --quiet "$d/docs/Fx-Checklist.md" "$d/docs/Fx-P2-Checklist.md" 2>&1)"
  if ! grep -q "Phases document" <<<"$out"; then
    ok tf_041a "the Phases document on disk is read, not reported as missing"
  else
    bad tf_041a "a Phases document that is there was reported as not existing"; note "$(grep Phases <<<"$out" | head -1)"
  fi
  rm -f "$d/docs/Fx-Phases.md"
  out="$(python3 "$UTILS/tf-doc-check.py" --root "$d" --quiet "$d/docs/Fx-Checklist.md" "$d/docs/Fx-P2-Checklist.md" 2>&1)"
  if grep -q "no Phases document is on disk" <<<"$out"; then
    ok tf_041b "a Phases document that really is absent is still reported"
  else
    bad tf_041b "a missing Phases document went unreported"; note "$(head -2 <<<"$out")"
  fi
}

# --- TF-042: overflow that nothing clips ---------------------------------------------------
# The clip clause read scrollWidth alone, so a sidebar whose rail handle straddles its edge by 8px
# was "cut off" on every TfLens screen with nothing clipped up to <html> (2026-09-12). And from
# TF-039 until this fix a card that really clips, holding screen-reader text, cut its own content
# before measuring it, so it read as holding everything.
tf_042() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_042 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/tf042"; mkdir -p "$d/docs/mockups"
  cat > "$d/docs/mockups/shell.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>
 body{margin:0;font-family:system-ui}
 aside{width:255px;height:200px;overflow-x:hidden;background:#f4f4f5;position:relative}
 .card{width:200px;height:60px;margin:8px;background:#eef}
</style></head><body>
 <aside data-testid="app-sidebar"><nav>Misses · Effort</nav></aside>
 <div data-testid="kpi-card" class="card"><div>Rework</div></div>
</body></html>
HTML
  cat > "$d/shell.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>
 body{margin:0;font-family:system-ui}
 aside{width:255px;height:200px;overflow-x:visible;background:#f4f4f5;position:relative}
 .rail{position:absolute;top:80px;right:-8px;width:16px;height:30px;border:0;background:#ccc}
 .card{width:200px;height:60px;margin:8px;background:#eef;overflow:hidden}
 .wide{width:420px;height:20px}
 .sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap}
</style></head><body>
 <aside data-testid="app-sidebar"><nav>Misses · Effort</nav><button class="rail" aria-label="Toggle sidebar"></button></aside>
 <div data-testid="kpi-card" class="card"><span class="sr">rework in dollars</span><div class="wide">Rework</div></div>
</body></html>
HTML
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-mockup-parity.mjs" "$d/parity.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  ( cd "$d" && timeout 180 node parity.mjs --base "http://127.0.0.1:$port" --screen shell=/shell.html \
      --widths 1280 --json-out "$d/parity.json" >/dev/null 2>&1 )
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  local clips; clips="$(python3 -c "import json,sys
try: s=json.load(open(sys.argv[1]))['screens'][0]
except Exception: print('no-output'); sys.exit()
print(' '.join(f['key'] for f in s.get('findings',[]) if f['class']=='clip'))" "$d/parity.json")"
  if [[ "$clips" != "no-output" ]] && ! grep -qw 'app-sidebar' <<<"$clips"; then
    ok tf_042a "a control straddling an edge that clips nothing is not reported as cut off"
  else
    bad tf_042a "overflow nothing clips is still reported as cut off"; note "clip findings: ${clips:-none}"
  fi
  if grep -qw 'kpi-card' <<<"$clips"; then
    ok tf_042b "a card that clips its content is reported, screen-reader text inside it or not"
  else
    bad tf_042b "a card that really clips read as holding everything"; note "clip findings: ${clips:-none}"
  fi
}

# --- TF-043: builders side by side, one shared build output --------------------------------
# Every start ran `dotnet run` over the same bin/ and obj/, which the next builder rewrote under the
# running app: on TfLens (2026-09-12) one app served its stylesheet as 200 with 0 bytes, one answered
# 500, one ran a dll older than its source. Builds overlapped freely, and an app whose starter died
# could not be stopped. Stand-in dotnet on PATH; nothing is built.
_tf043_fx() {
  local d="$SCRATCH/$1"; mkdir -p "$d/bin" "$d/home" "$d/p/Properties"
  printf '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>\n' > "$d/p/Fx.csproj"
  cat > "$d/bin/dotnet" <<'SH'
#!/usr/bin/env bash
log="__D__/calls"
urlport() { local u=""; while [[ $# -gt 0 ]]; do [[ "$1" == "--urls" ]] && u="$2"; shift; done; echo "${u##*:}"; }
case "$1" in
  publish)
    out=""; for ((i=1; i<=$#; i++)); do [[ "${!i}" == "-o" ]] && { j=$((i+1)); out="${!j}"; }; done
    echo "start $(date +%s.%N) publish" >> "$log"; sleep 1; mkdir -p "$out"; echo dll > "$out/Fx.dll"
    echo "end $(date +%s.%N) publish" >> "$log"; echo "Fx -> $out"; exit 0 ;;
  build)
    echo "start $(date +%s.%N) build" >> "$log"; sleep 1; echo "end $(date +%s.%N) build" >> "$log"; echo "Build succeeded."; exit 0 ;;
  run)
    echo "run-shared $*" >> "$log"; exec python3 -m http.server "$(urlport "$@")" --bind 127.0.0.1 ;;
  *.dll)
    echo "run-copy $1" >> "$log"; exec python3 -m http.server "$(urlport "$@")" --bind 127.0.0.1 --directory "$(dirname "$1")/" ;;
esac
SH
  sed -i "s#__D__#$d#" "$d/bin/dotnet"; chmod +x "$d/bin/dotnet"
  printf '%s' "$d"
}
tf_043() {
  local d; d="$(_tf043_fx tf043)"
  local p1 p2; p1="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  p2="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  boot() { ( cd "$d" && HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" bash "$UTILS/tf-verify-boot.sh" "$@" ) 2>&1; }
  up() { curl -s -o /dev/null -m 2 "http://localhost:$1/" 2>/dev/null; }
  # read through a pipe, as an agent's shell reads it: a started app left holding the script's output
  # made the caller wait for ever (the first TF-043 fix did exactly that, caught on a real app)
  local o1 o2 rc1 rc2
  o1="$(timeout 60 cat < <(boot start --project p/Fx.csproj --port "$p1"))"; rc1=$?
  o2="$(timeout 60 cat < <(boot start --project p/Fx.csproj --port "$p2"))"; rc2=$?
  if [[ $rc1 -eq 0 && $rc2 -eq 0 ]] && grep -q '^BOOTED' <<<"$o1" && grep -q '^BOOTED' <<<"$o2"; then
    ok tf_043e "start returns its BOOTED line and lets go of its output, so a caller reading it is not held"
  else
    bad tf_043e "start kept its output open after the app came up, so a caller reading it waited for ever"; note "exit $rc1/$rc2: $(head -1 <<<"$o1")"
  fi
  if grep -q "run-copy $d/tests/.artifacts/verify/run-$p1/Fx.dll" "$d/calls" 2>/dev/null \
     && grep -q "run-copy $d/tests/.artifacts/verify/run-$p2/Fx.dll" "$d/calls" && ! grep -q run-shared "$d/calls" && up "$p1" && up "$p2"; then
    ok tf_043a "each app runs from a published copy of its own, never from the build output the next builder rewrites"
  else
    bad tf_043a "two apps were started over the same build output"; note "$(grep run- "$d/calls" 2>/dev/null | head -2)"
  fi
  # an app whose starter died: its pid is gone from the state file, and stop still finds it by its copy
  python3 -c "import json,sys; p=sys.argv[1]; s=json.load(open(p)); s['pids']=[999999]; json.dump(s,open(p,'w'))" "$d/tests/.artifacts/verify/boot-$p1.json" 2>/dev/null
  boot stop --port "$p1" >/dev/null; sleep 1
  if ! up "$p1" && up "$p2"; then
    ok tf_043b "stop --port stops an app whose starter died, found by the copy it runs from, and leaves the other"
  else
    bad tf_043b "an app nobody's child any more kept its port after stop"
  fi
  boot stop --port "$p2" >/dev/null
  pkill -f "http.server $p1" 2>/dev/null; pkill -f "http.server $p2" 2>/dev/null
  # two builds at once in one repository: the second waits for the first
  local e; e="$(_tf043_fx tf043c)"
  ( cd "$e" && HOME="$e/home" PATH="$e/bin:/usr/bin:/bin" bash "$UTILS/tf-build.sh" build p/Fx.csproj >/dev/null 2>&1 ) &
  local b1=$!
  ( cd "$e" && HOME="$e/home" PATH="$e/bin:/usr/bin:/bin" bash "$UTILS/tf-build.sh" build p/Fx.csproj >/dev/null 2>&1 ) &
  wait "$b1" $!
  local order; order="$(cut -d' ' -f1 "$e/calls" 2>/dev/null | tr '\n' ' ')"
  if [[ "$order" == "start end start end " ]]; then
    ok tf_043c "two builds started together run one after the other"
  else
    bad tf_043c "two builds wrote the same output at the same time"; note "order: $order"
  fi
  # a lock left by a build that died is taken over, not waited on for half an hour
  : > "$e/calls"; mkdir -p "$e/tests/.artifacts/build/.lock"
  echo "999999 $(hostname) build 2026-09-12T00:00:00Z" > "$e/tests/.artifacts/build/.lock/owner"
  local out; out="$( cd "$e" && HOME="$e/home" PATH="$e/bin:/usr/bin:/bin" TF_BUILD_LOCK_MAX=20 timeout 60 bash "$UTILS/tf-build.sh" build p/Fx.csproj 2>/dev/null )"
  if grep -q '^PASS' <<<"$out" && [[ ! -d "$e/tests/.artifacts/build/.lock" ]]; then
    ok tf_043d "a lock whose build has died is taken over, and let go when the build ends"
  else
    bad tf_043d "a dead build's lock stopped the next build"; note "$(tail -1 <<<"$out")"
  fi
}

# --- TF-044: a sign-in page that becomes interactive after it is drawn ----------------------
# The tool typed the moment the page's markup arrived and pressed at once: the page's first
# interactive render replaced the fields, the email was gone, and every screen of TfLens graded
# UNREACHABLE (2026-09-12). And the user field was the first match in page order, so a search box
# before the email field took the email.
tf_044() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_044 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/tf044"; mkdir -p "$d"
  printf '<!doctype html><html><body><h1 data-testid="page-title">Home</h1><p>Signed in.</p></body></html>\n' > "$d/home.html"
  # drawn first, interactive 1.5 s later: a press before then does nothing, and becoming interactive redraws the fields
  cat > "$d/login-race.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"></head><body>
<form id="f"><input data-testid="login-email" type="text"><input data-testid="login-pass" type="password">
<button data-testid="login-submit" type="submit">Sign in</button></form>
<script>
 let live = false; const f = document.getElementById('f');
 f.addEventListener('submit', (e) => { e.preventDefault(); if (live && f.querySelector('[data-testid="login-email"]').value) location.href = '/home.html'; });
 setTimeout(() => { f.innerHTML = f.innerHTML; live = true; }, 1500);
</script></body></html>
HTML
  cat > "$d/login-search.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"></head><body>
<header><input type="text" placeholder="Search"></header>
<form id="f"><input name="email" type="text"><input name="password" type="password"><button type="submit">Sign in</button></form>
<script>const f = document.getElementById('f');
 f.addEventListener('submit', (e) => { e.preventDefault(); if (f.email.value) location.href = '/home.html'; });</script>
</body></html>
HTML
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-verify-screens.mjs" "$d/screens.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  signed() { # login page -> "ok" or the tool's error
    ( cd "$d" && timeout 180 node screens.mjs --base "http://127.0.0.1:$port" --screen home=/home.html --widths 1280 \
        --login-path "/$1" --user a@b.c --password x --render-wait 300 --json-out "$d/$1.json" >/dev/null 2>&1 )
    python3 -c "import json,sys
try: l=json.load(open(sys.argv[1])).get('login') or {}
except Exception: l={'error':'no output'}
print('ok' if l.get('ok') else (l.get('error') or 'still on the sign-in page'))" "$d/$1.json"
  }
  local r
  r="$(signed login-race.html)"
  [[ "$r" == ok ]] && ok tf_044a "sign-in types again when the page redraws its fields, and presses once the values stay" \
                   || { bad tf_044a "sign-in lost to a page that becomes interactive after it is drawn"; note "$r"; }
  r="$(signed login-search.html)"
  [[ "$r" == ok ]] && ok tf_044b "the email goes into the email field, not a search box standing before it" \
                   || { bad tf_044b "the first text box in the page took the email"; note "$r"; }
  kill "$(cat "$d/srv.pid")" 2>/dev/null
}

# --- TF-045: the same badge one wrapper deeper ---------------------------------------------
# Elements were paired by tag and position, so a component library that wraps a card header's
# contents in one more <div> made every badge in it "missing — flattened into plain text" while the
# page drew it: 32 findings on three TfLens screens (2026-09-13). A deep amber also read as
# "negative" beside a light one reading "warning".
tf_045() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_045 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/tf045"; mkdir -p "$d/docs/mockups"
  local css='body{margin:0;font-family:system-ui;width:900px}
.card{border:1px solid #e4e4e7;border-radius:12px;margin:8px;padding:8px}
.card-h{display:flex;justify-content:space-between;align-items:flex-start}
.badge{display:inline-block;border:1px solid #d4d4d8;border-radius:9999px;padding:2px 8px;font-size:12px;line-height:16px}
.tile{width:120px;height:60px}'
  card() { # testid title badge-markup wrapper(0|1)
    if [[ "$4" == 1 ]]; then printf '<div class="card" data-testid="%s"><div class="card-h"><div class="flex"><div><div>%s</div></div>%s</div></div></div>\n' "$1" "$2" "$3"
    else printf '<div class="card" data-testid="%s"><div class="card-h"><div><div>%s</div></div>%s</div></div>\n' "$1" "$2" "$3"; fi
  }
  { printf '<!doctype html><html><head><meta charset="utf-8"><style>%s</style></head><body>\n' "$css"
    card miss-origin "Origin phase" '<span class="badge">linked only</span>' 0
    card miss-whymissed "Why it was missed" '<span class="badge">39 of 41 misses assessed</span>' 0
    card miss-review-cost "Review cost" '<span class="badge">copied · never computed</span>' 0
    card miss-estimate "Estimate" '<span class="badge">estimate</span>' 0
    card miss-draft "Draft notes" '<span class="badge">draft</span>' 0
    printf '<div class="tile" data-testid="tile-warn" style="background:#f59e0b">3 open</div></body></html>\n'
  } > "$d/docs/mockups/misses.html"
  { printf '<!doctype html><html><head><meta charset="utf-8"><style>%s</style></head><body>\n' "$css"
    card miss-origin "Origin phase" '<span class="badge">linked only</span>' 1
    card miss-whymissed "Why it was missed" '<span class="badge">87 of 91 misses assessed</span>' 1
    card miss-review-cost "Review cost" '<span class="badge">copied</span>' 1
    card miss-estimate "Estimate" '' 1
    card miss-draft "Draft notes" '<span>draft</span>' 1
    printf '<div class="tile" data-testid="tile-warn" style="background:#b45309">3 open</div></body></html>\n'
  } > "$d/misses.html"
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-mockup-parity.mjs" "$d/parity.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  ( cd "$d" && timeout 180 node parity.mjs --base "http://127.0.0.1:$port" --screen misses=/misses.html \
      --widths 1280 --json-out "$d/parity.json" >/dev/null 2>&1 )
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  local f; f="$(python3 -c "import json,sys
try: s=json.load(open(sys.argv[1]))['screens'][0]
except Exception: print('no-output'); sys.exit()
for x in s.get('findings',[]): print(x['key'].split(' > ')[0], x['class'], x['detail'])" "$d/parity.json")"
  if [[ "$f" != "no-output" ]] && ! grep -qE '^miss-(origin|whymissed|review-cost) ' <<<"$f"; then
    ok tf_045a "a badge drawn one wrapper deeper is found, by its text or by the parent's count, and not reported missing"
  else
    bad tf_045a "badges one wrapper deeper are still reported missing"; note "$(grep -E '^miss-(origin|whymissed|review-cost) ' <<<"$f" | head -2)"
  fi
  if grep -qE '^miss-estimate missing .*could not be located' <<<"$f" && grep -qE '^miss-draft (badge|missing) ' <<<"$f"; then
    ok tf_045b "a badge the app does not draw is still reported, and says it could not be located rather than naming a cause"
  else
    bad tf_045b "a missing or flattened badge went unreported, or the message still guesses a cause"; note "$(grep -E '^miss-(estimate|draft) ' <<<"$f" | head -2)"
  fi
  if ! grep -qE '^tile-warn color ' <<<"$f"; then
    ok tf_045c "a deep amber and a light amber are the same warning colour"
  else
    bad tf_045c "a deep amber still reads as a different colour from a light one"; note "$(grep '^tile-warn' <<<"$f")"
  fi
}

# --- TF-046: one extra icon, reported at every element that contains it ----------------------
# The icon clause asks "is there an icon anywhere inside?", so the chevron of a Select the mockup draws
# as a native <select> was reported on the anchor and on each wrapper above it: 14 of 26 icon findings
# on TfLens /misses, /effort and /prices (2026-09-14) were an ancestor repeating a descendant.
tf_046() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_046 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/tf046"; mkdir -p "$d/docs/mockups"
  local ico='<svg width="12" height="12" viewBox="0 0 12 12"><path d="M2 4l4 4 4-4"/></svg>'
  local css='body{margin:0;font-family:system-ui;width:900px} div{padding:4px} select{width:160px}'
  # app: a chevron inside fx-period only; fx-card has one icon of its own beside a nested one;
  # fx-legend lost the icon the mockup draws two levels down
  { printf '<!doctype html><html><head><meta charset="utf-8"><style>%s</style></head><body>\n' "$css"
    printf '<div data-testid="fx-page"><div><h1>Misses</h1><div><div data-testid="fx-period"><select><option>All history</option></select></div></div></div></div>\n'
    printf '<div data-testid="fx-card"><div><span>Every miss</span><div><span>41 records</span></div></div></div>\n'
    printf '<div data-testid="fx-legend"><div><div>%s<span>key</span></div></div></div>\n' "$ico"
    printf '</body></html>\n'
  } > "$d/docs/mockups/misses.html"
  { printf '<!doctype html><html><head><meta charset="utf-8"><style>%s</style></head><body>\n' "$css"
    printf '<div data-testid="fx-page"><div><h1>Misses</h1><div><div data-testid="fx-period"><span>All history</span>%s</div></div></div></div>\n' "$ico"
    printf '<div data-testid="fx-card"><div>%s<span>Every miss</span><div>%s<span>133 records</span></div></div></div>\n' "$ico" "$ico"
    printf '<div data-testid="fx-legend"><div><div><span>key</span></div></div></div>\n'
    printf '</body></html>\n'
  } > "$d/misses.html"
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-mockup-parity.mjs" "$d/parity.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  ( cd "$d" && timeout 180 node parity.mjs --base "http://127.0.0.1:$port" --screen misses=/misses.html \
      --widths 1280 --json-out "$d/parity.json" >/dev/null 2>&1 )
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  local f; f="$(python3 -c "import json,sys
try: s=json.load(open(sys.argv[1]))['screens'][0]
except Exception: print('no-output'); sys.exit()
print('\n'.join(sorted(x['key'] for x in s.get('findings',[]) if x['class']=='icon')))" "$d/parity.json")"
  has() { grep -qFx "$1" <<<"$f"; }
  local seen; seen="$(tr '\n' ',' <<<"$f")"
  if has "fx-period" && ! grep -q '^fx-page' <<<"$f"; then
    ok tf_046a "an extra icon is reported once, on the innermost element that carries it"
  else
    bad tf_046a "an extra icon is still reported at the elements that contain it"; note "icon findings: $seen"
  fi
  if has "fx-card > div[0]" && has "fx-card > div[0] > div[0]" && ! has "fx-card"; then
    ok tf_046b "a container holding a second extra icon of its own is still reported"
  else
    bad tf_046b "a container's own extra icon was dropped, or its anchor still repeats it"; note "icon findings: $seen"
  fi
  if has "fx-legend > div[0] > div[0]" && ! has "fx-legend" && ! has "fx-legend > div[0]"; then
    ok tf_046c "an icon the app lost is reported once, on the innermost element the mockup draws it in"
  else
    bad tf_046c "an icon the app lost is still reported at every element above it"; note "icon findings: $f"
  fi
}

# --- TF-047: the treatment one element away, the icon in another child, wrap on other text -----
# Keys pair by position. TfLens's library draws the active link's fill on the <a> inside a <li>, and
# the filter's ring on the InputGroup around the input; its card header has one more wrapper, so the
# mockup's description paired with the app's toolbar and its icon read as extra; and `wrap` compared
# row counts of texts that read differently. 15 findings on 13 correct rows (2026-09-14).
tf_047() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_047 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/tf047"; mkdir -p "$d/docs/mockups"
  local ico='<svg width="12" height="12" viewBox="0 0 12 12"><path d="M2 4l4 4 4-4"/></svg>'
  local css='body{margin:0;font:14px/20px system-ui;width:1000px;background:#000;color:#eee}
.nav a{display:flex;height:36px;align-items:center;gap:6px;padding:0 10px;border-radius:8px;color:#eee;text-decoration:none} .nav a.on{background:#1f1f1f}
.nav ul{list-style:none;margin:0;padding:0} .nav li{margin:0;padding:0}
.inwrap{position:relative;width:280px} .inwrap svg{position:absolute;left:10px;top:12px}
.input{box-sizing:border-box;width:280px;height:36px;border:1px solid #888;border-radius:8px;padding:0 12px 0 36px;background:#0a0a0a;color:#eee}
.group{display:flex;align-items:center;box-sizing:border-box;width:280px;height:36px;border:1px solid #888;border-radius:8px;background:#0a0a0a} .group svg{margin-left:10px}
.group input{box-sizing:border-box;border:0;background:transparent;height:36px;flex:1;padding:8px 12px 8px 4px;color:#eee}
.h{display:flex;justify-content:space-between;padding:8px} .h .h{padding:0;flex:1}
.note{width:300px;padding:4px;margin:8px 0} .narrow{width:200px}'
  # mockup: the active link is the badge; the filter input carries the ring; the one icon in the
  # card header sits beside the description; notes with sample text
  { printf '<!doctype html><html><head><meta charset="utf-8"><style>%s</style></head><body>\n' "$css"
    printf '<div data-testid="fx-sidebar"><nav class="nav"><a class="on" href="#">%s<span>Misses</span></a><a href="#">%s<span>Effort</span></a></nav></div>\n' "$ico" "$ico"
    printf '<div data-testid="fx-card"><div class="h"><div><div>Every miss</div><div>41 records · each row carries one sentence</div></div><div><div class="inwrap">%s<input class="input" placeholder="Filter"></div></div></div></div>\n' "$ico"
    printf '<div data-testid="fx-plain"><div class="h"><div><div>Phase effort</div><div>22 phases</div></div><div><button>Export</button></div></div></div>\n'
    printf '<div class="inwrap">%s<input class="input" data-testid="fx-filter" placeholder="Filter models"></div>\n' "$ico"
    printf '<p class="note" data-testid="fx-note">The coverage page counted an imported source as stale from its newest record.</p>\n'
    printf '<p class="note" data-testid="fx-same">5 of 41 misses excluded from every per-origin figure because their origin is not linked.</p>\n'
    printf '</body></html>\n'
  } > "$d/docs/mockups/misses.html"
  # app: the link sits in a <li> with its own test id, the ring is on the group around the input,
  # the header has one more wrapper with the icon in the toolbar; fx-plain really adds an icon;
  # fx-note reads differently; fx-same reads the same in a narrower box
  { printf '<!doctype html><html><head><meta charset="utf-8"><style>%s</style></head><body>\n' "$css"
    printf '<div data-testid="fx-sidebar"><div class="nav"><ul><li><a class="on" data-testid="nav-misses" href="#">%s<span>Misses</span></a></li><li><a data-testid="nav-effort" href="#">%s<span>Effort</span></a></li></ul></div></div>\n' "$ico" "$ico"
    printf '<div data-testid="fx-card"><div class="h"><div class="h"><div><div>Every miss</div><div>133 records · each row carries one sentence</div></div><div><div class="group">%s<input placeholder="Filter"></div></div></div></div></div>\n' "$ico"
    printf '<div data-testid="fx-plain"><div class="h"><div class="h"><div><div>Phase effort</div><div>80 phases</div></div><div><button>%s Export</button></div></div></div></div>\n' "$ico"
    printf '<div class="group">%s<input data-testid="fx-filter" placeholder="Filter models"></div>\n' "$ico"
    printf '<p class="note" data-testid="fx-note">The mockups were drawn without the sidebar rail, so every screen was wider than the app draws it and the header wrapped to two rows.</p>\n'
    printf '<p class="note narrow" data-testid="fx-same">41 of 133 misses excluded from every per-origin figure because their origin is not linked.</p>\n'
    printf '</body></html>\n'
  } > "$d/misses.html"
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-mockup-parity.mjs" "$d/parity.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  ( cd "$d" && timeout 180 node parity.mjs --base "http://127.0.0.1:$port" --screen misses=/misses.html \
      --widths 1280 --json-out "$d/parity.json" >/dev/null 2>&1 )
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  local f; f="$(python3 -c "import json,sys
try: s=json.load(open(sys.argv[1]))['screens'][0]
except Exception: print('no-output'); sys.exit()
for x in s.get('findings',[]): print(x['class'], x['key'])" "$d/parity.json")"
  local seen; seen="$(tr '\n' ',' <<<"$f")"
  if [[ "$f" != "no-output" ]] && ! grep -qE '^badge fx-sidebar' <<<"$f" && ! grep -qE '^(badge|stroke) fx-filter$' <<<"$f"; then
    ok tf_047a "a fill or ring drawn on the box around the control, or on the one inside it, is the same treatment"
  else
    bad tf_047a "a treatment one element away is still reported as missing"; note "findings: $seen"
  fi
  if ! grep -qE '^icon fx-card' <<<"$f" && grep -qFx 'icon fx-plain > div[0] > div[0] > div[1]' <<<"$f"; then
    ok tf_047b "an icon under the same header, in another child, is not reported; a header that really gains one still is"
  else
    bad tf_047b "an icon moved by one wrapper is still reported, or a real extra icon was dropped"; note "findings: $seen"
  fi
  if ! grep -qFx 'wrap fx-note' <<<"$f" && grep -qFx 'wrap fx-same' <<<"$f"; then
    ok tf_047c "wrap is graded only on text that reads the same; the same text in a narrower box is still reported"
  else
    bad tf_047c "wrap still compares row counts of different texts, or lost the finding on the same text"; note "findings: $seen"
  fi
}

# --- TF-048: browser checks side by side share one signed-in user ---------------------------
# The acceptance tests changed the user's settings and window under a parity run: 11 false findings.
# The three verify wrappers now take tf-build.sh's repository lock (tf-lock.sh).
tf_048() {
  local d="$SCRATCH/tf048" out; mkdir -p "$d"
  for s in tf-verify-screens.sh tf-mockup-parity.sh tf-verify-tests.sh tf-build.sh; do
    grep -q 'tf_take_lock' "$UTILS/$s" || { bad tf_048a "$s does not take the repository lock"; return; }
  done
  ok tf_048a "tf-verify-tests.sh, tf-verify-screens.sh, tf-mockup-parity.sh and tf-build.sh take one lock"
  out="$(cd "$d" && bash -c 'source "$0"/tf-lock.sh; tf_take_lock outer; bash -c "source $0/tf-lock.sh; TF_BUILD_LOCK_MAX=3 tf_take_lock inner && echo nested-ok"' "$UTILS" 2>&1)"
  [[ "$out" == "nested-ok" ]] && ok tf_048b "a script the holder starts (tf-verify-tests running tf-build) shares the lock" \
    || { bad tf_048b "a script started by the lock's holder waits on its own lock"; note "$out"; }
  ( cd "$d" && bash -c 'source "$0"/tf-lock.sh; tf_take_lock holder; sleep 8' "$UTILS" & ); sleep 1
  out="$(cd "$d" && TF_BUILD_LOCK_MAX=3 bash -c 'source "$0"/tf-lock.sh; tf_take_lock second; echo took-it' "$UTILS" 2>&1)"
  grep -q '^wait  another build or browser check' <<<"$out" && grep -q '^NOT-RUN' <<<"$out" && ! grep -q took-it <<<"$out" \
    && ok tf_048c "a second check waits on the held lock and says so, and gives up at the limit" \
    || { bad tf_048c "a second check ran beside the holder"; note "$out"; }
  sleep 8
}

# --- TF-049: handoff-phase names `tf-build.sh --print`, which did not exist -------------------
tf_049() {
  local d="$SCRATCH/tf049" out; mkdir -p "$d"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$d/Fx.csproj"
  out="$(cd "$d" && bash "$UTILS/tf-build.sh" --print 2>&1)"; local rc=$?
  [[ "$out" == "dotnet build Fx.csproj" && $rc -eq 0 && ! -d "$d/tests/.artifacts/build/.lock" ]] \
    && ok tf_049a "--print prints the build command this repository uses and runs nothing" \
    || { bad tf_049a "--print does not print the command"; note "$out (exit $rc)"; }
  out="$(cd "$d" && bash "$UTILS/tf-build.sh" test --print 2>&1)"
  [[ "$out" == "dotnet test Fx.csproj" ]] && ok tf_049b "--print after a mode prints that mode's command" \
    || { bad tf_049b "test --print is wrong"; note "$out"; }
  grep -q 'tf-build.sh --print' "$ROOT/.tfcore/tasks/handoff-phase.md" && ok tf_049c "handoff-phase names the option that now exists" \
    || bad tf_049c "handoff-phase no longer names --print"
}

# --- TF-050: a Playwright spec's `path:` read as a page route -------------------------------
tf_050() {
  local d="$SCRATCH/tf050" out; mkdir -p "$d/src/Fx/Pages" "$d/tests/verify" "$d/src/Fx/ClientApp"
  printf '@page "/misses"\n<h1>Misses</h1>\n' > "$d/src/Fx/Pages/Misses.razor"
  printf "await page.screenshot({ path: 'tests/.artifacts/parity/export-banner.png' });\n" > "$d/tests/verify/parity-gate-smoke.spec.ts"
  printf "const routes = [{ path: '/prices', component: Prices }];\n" > "$d/src/Fx/ClientApp/routes.ts"
  out="$(cd "$d" && python3 -c "
import importlib.util
s=importlib.util.spec_from_file_location('dl','$UTILS/tf-devguide-list.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(' '.join(sorted(r for r, _f, _w in m.routes_in_code())))" 2>&1)"
  [[ "$out" == "/misses /prices" ]] && ok tf_050 "a spec's screenshot path is not a route; @page and a client route list still are" \
    || { bad tf_050 "routes in code still include a test's screenshot path, or lost a real route"; note "$out"; }
}

# --- TF-051: demote a row of an earlier phase's checklist ------------------------------------
# tf-triage.py read only the appPhase checklist, so with appPhase 3 a Phase 1 row the Phase 3
# verify found failing could not be demoted: "REQ-NFR-003 is not a row of docs/TfLens-P3-Checklist.md"
# (TfLens *fix-issues, 2026-09-15). tf-verify-list already took --phase.
tf_051() {
  local d="$SCRATCH/tf051" out rc; mkdir -p "$d/docs" "$d/.tfcore"
  printf 'appPhase: 3\n' > "$d/.tfcore/core-config.yaml"
  printf '%s\n' '# Fx — Requirements Checklist' '' '## Requirements Status' '' \
    '| ID | Title | Status | % | Remarks | Detail |' '|---|---|---|---|---|---|' \
    '| REQ-NFR-003 | Secret hygiene | Verified | 100% | — | [view](#d-req-nfr-003) |' '' '## Security' '' \
    '- <a id="d-req-nfr-003"></a>**REQ-NFR-003** — Secret hygiene' '  - Acceptance: When a build runs on Repos, then no secret is in the output.' > "$d/docs/Fx-Checklist.md"
  printf '%s\n' '# Fx — Phase 3 Checklist' '' '## Requirements Status' '' \
    '| ID | Title | Status | % | Remarks | Detail |' '|---|---|---|---|---|---|' \
    '| REQ-UI-100 | Prices page | Verified | 100% | — | [view](#d-req-ui-100) |' '' '## Prices' '' \
    '- <a id="d-req-ui-100"></a>**REQ-UI-100** — Prices page' '  - Acceptance: When a user opens Prices on Prices, then the rates show.' > "$d/docs/Fx-P3-Checklist.md"
  tri() { ( cd "$d" && bash "$UTILS/tf-triage.sh" Fx "$@" ) 2>&1; }
  out="$(tri demote REQ-NFR-003 "the secret-hygiene test fails" --kind data-logic)"; rc=$?
  if [[ $rc -eq 0 ]] && grep -q '^| REQ-NFR-003 | Secret hygiene | Needs re-verify |' "$d/docs/Fx-Checklist.md" \
     && out2="$(tri demote REQ-UI-100 "the rates are blank")" && grep -q '^| REQ-UI-100 | Prices page | Needs re-verify |' "$d/docs/Fx-P3-Checklist.md"; then
    ok tf_051a "demote reaches a Phase 1 row with appPhase 3, and a Phase 3 row as before"
  else
    bad tf_051a "a row of an earlier phase's checklist cannot be demoted"; note "$(head -1 <<<"$out")"
  fi
  tri note REQ-NFR-003 "could not reproduce on a clean build" --phase 1 >/dev/null
  tri new "Stale cache" "When a user reloads Repos on Repos, then the new count shows." --prefix NFR --phase 1 >/dev/null
  if grep -q 'triage: could not reproduce' "$d/docs/Fx-Checklist.md" && grep -q '^| REQ-NFR-004 | Stale cache |' "$d/docs/Fx-Checklist.md" \
     && ! grep -q 'Stale cache' "$d/docs/Fx-P3-Checklist.md"; then
    ok tf_051b "note and new take --phase 1 and write to that phase's checklist"
  else
    bad tf_051b "--phase is ignored: note or new wrote to the appPhase checklist"
  fi
  out="$(tri demote REQ-FN-999 "nothing")"; rc=$?
  [[ $rc -eq 2 ]] && grep -q 'Fx-Checklist.md' <<<"$out" && grep -q 'Fx-P3-Checklist.md' <<<"$out" \
    && ok tf_051c "an id in no checklist is refused, naming every checklist searched" \
    || { bad tf_051c "an unknown id was not refused with the checklists named"; note "$out (exit $rc)"; }
}

# --- TF-052: the verify a fix chains, and the fix's own run record --------------------------
# *fix-issues runs *verify inline; the verify was handed the fix's start as "the step-0 time", so its
# record covered the fix's whole window and tf-fix-close's record was refused for overlap. And the
# ledger holds one scoped verify, so after a Phase 3 verify then a --phase 1 verify the Phase 3 rows
# read as absent and their open misses got "Needs re-verify" (TfLens, 2026-09-15).
tf_052() {
  local d; d="$(_metrics_fx tf052)"; mkdir -p "$d/.tfcore/.session" "$d/tests/.artifacts/verify"; cp -r "$UTILS" "$d/.tfcore/"
  local t1 t2 t3 t4 t5; t1="$(date -u -d '-50 minutes' +%Y-%m-%dT%H:%M:%SZ)"; t2="$(date -u -d '-40 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  t3="$(date -u -d '-30 minutes' +%Y-%m-%dT%H:%M:%SZ)"; t4="$(date -u -d '-20 minutes' +%Y-%m-%dT%H:%M:%SZ)"; t5="$(date -u -d '-10 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  in52() { ( cd "$d" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d" TF_SKIP_SELFCHECK=1 "$@" ) 2>&1; }
  # the verify's step 0 inside the fix keeps the fix as "outer", and a greedy read still takes the verify's start
  printf '{"cmd":"fix-issues","app":"Fx","started":"%s"}\n' "$t1" > "$d/.tfcore/.session/phase.json"
  local own; own="$(in52 bash .tfcore/utils/tf-phase.sh start verify-phase Fx | head -1)"
  if python3 -c "import json,sys; m=json.load(open(sys.argv[1])); sys.exit(0 if m['cmd']=='verify-phase' and m['started']==sys.argv[3] and m.get('outer',{}).get('started')==sys.argv[2] else 1)" \
       "$d/.tfcore/.session/phase.json" "$t1" "$own" && [[ "$(sed -n 's/.*"started":"\([^"]*\)".*/\1/p' "$d/.tfcore/.session/phase.json")" == "$own" ]]; then
    ok tf_052a "a verify started inside a fix keeps the fix as outer; its own start is what every reader takes"
  else
    bad tf_052a "the verify's marker lost the fix's start, or a reader takes the wrong one"; note "$(cat "$d/.tfcore/.session/phase.json")"
  fi
  # tf-verify-emit handed the fix's start records the verify from its own
  printf '{"outer":{"cmd":"fix-issues","app":"Fx","started":"%s"},"cmd":"verify-phase","app":"Fx","started":"%s"}\n' "$t1" "$t4" > "$d/.tfcore/.session/phase.json"
  python3 - "$d/tests/.artifacts/verify/verdicts.json" <<'PY'
import json, sys
json.dump({"app": "Fx", "scope": "REQ-UI-100", "build_result": "pass", "rows": [{"id": "REQ-UI-100", "class": "UI", "verdict": "PASS",
           "gate": None, "gates_run": ["build", "acceptance"], "failure_class": None, "prior_verdict": "Needs re-verify",
           "status": "Verified", "emit_gate": True}]}, open(sys.argv[1], "w"))
PY
  in52 bash .tfcore/utils/tf-verify-emit.sh Fx --started "$t1" >/dev/null
  grep -q "\"cmd\":\"verify-phase\".*\"started\":\"$t4\"\|\"started\":\"$t4\".*\"cmd\":\"verify-phase\"" "$d/docs/metrics/runs.jsonl" \
    && ok tf_052b "the chained verify's run record starts at the verify's own start, not the fix's" \
    || { bad tf_052b "the chained verify's record took the fix's start"; note "$(grep verify-phase "$d/docs/metrics/runs.jsonl" | cut -c1-160)"; }
  # the close: two chained verifies on the stream, a Phase 3 one then a --phase 1 one; the ledger holds the second
  local d2; d2="$(_metrics_fx tf052close)"; mkdir -p "$d2/.tfcore/.session"; cp -r "$UTILS" "$d2/.tfcore/"
  for w in "$t2 $t3" "$t4 $t5"; do set -- $w
    echo "{\"kind\":\"run\",\"app\":\"Fx\",\"cmd\":\"verify-phase\",\"started\":\"$1\",\"ended\":\"$2\"}" \
      | ( cd "$d2" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d2" bash .tfcore/utils/tf-emit.sh runs ) >/dev/null 2>&1
  done
  printf '%s\n' "{\"kind\":\"gate\",\"app\":\"Fx\",\"run_id\":\"$t1\",\"req_id\":\"REQ-UI-100\",\"verdict\":\"Needs re-verify\",\"gate\":\"escaped\"}" \
    "{\"kind\":\"gate\",\"app\":\"Fx\",\"run_id\":\"$t2\",\"req_id\":\"REQ-UI-100\",\"verdict\":\"Verified\",\"gate\":null}" \
    "{\"kind\":\"gate\",\"app\":\"Fx\",\"run_id\":\"$t4\",\"req_id\":\"REQ-NFR-003\",\"verdict\":\"FAIL\",\"gate\":\"acceptance\"}" >> "$d2/docs/metrics/gates.jsonl"
  printf '%s\n' '{"kind":"miss","miss_id":"MISS-Fx-20260911-39","app":"Fx","req_id":"REQ-UI-100","miss_class":"wrong-behaviour","artifact":"src","severity":"minor","found_by":"owner","ts":"2026-09-11T10:00:00Z"}' \
    '{"kind":"miss","miss_id":"MISS-Fx-20260915-01","app":"Fx","req_id":"REQ-NFR-003","miss_class":"wrong-behaviour","artifact":"src","severity":"minor","found_by":"owner","ts":"2026-09-15T10:00:00Z"}' >> "$d2/docs/metrics/misses.jsonl"
  printf '{"date":"2026-09-15","app":"Fx","scope":"REQ-NFR-003","run_id":"%s","rows":{"REQ-NFR-003":"FAIL"}}\n' "$t4" > "$d2/docs/.last-verify.json"
  printf '{"outer":{"cmd":"fix-issues","app":"Fx","started":"%s"},"cmd":"verify-phase","app":"Fx","started":"%s"}\n' "$t1" "$t4" > "$d2/.tfcore/.session/phase.json"
  local out; out="$(cd "$d2" && CLAUDE_PROJECT_DIR= TF_METRICS_ROOT="$d2" bash .tfcore/utils/tf-fix-close.sh Fx --started "$t1" --reqs REQ-UI-100,REQ-NFR-003 --build pass 2>&1)"
  local segs; segs="$(python3 -c "import json,sys
r=[json.loads(l) for l in open(sys.argv[1]) if '\"fix-issues\"' in l]
print(' '.join('%s-%s:%d' % (x['started'], x['ended'], len(x['reqs_touched'])) for x in r))" "$d2/docs/metrics/runs.jsonl")"
  if ! grep -q 'not written' <<<"$out" && [[ "$segs" == "$t1-$t2:2 $t3-$t4:0 $t5-"* && "$(wc -w <<<"$segs")" == "3" ]]; then
    ok tf_052c "the fix is recorded around both chained verifies, rows on its first segment, nothing refused"
  else
    bad tf_052c "the fix's run record was refused or covers a chained verify"; note "$(grep -m1 'not written' <<<"$out" | cut -c1-160)"; note "segments: $segs"
  fi
  local v; v="$(python3 -c "import json,sys
print(' '.join('%s=%s' % (x['req_id'], x['verdict_after']) for x in map(json.loads, open(sys.argv[1])) if x.get('kind')=='miss-fix'))" "$d2/docs/metrics/misses.jsonl")"
  [[ "$v" == "REQ-UI-100=Verified REQ-NFR-003=FAIL" ]] \
    && ok tf_052d "each row's miss-fix carries the verdict of the verify that graded it, not the last ledger's absence" \
    || { bad tf_052d "a row verified by the earlier scope got the wrong verdict"; note "$v"; }
}

# --- TF-036: two wrapped sentences that share a line ----------------------------------------
# An inline element's bounding box is the union of its line fragments, so two sentences sharing a
# line "overlapped" across a tile's width on TfLens /effort (2026-09-11) with 0 px² in common.
tf_036() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip tf_036 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/tf036"; mkdir -p "$d"
  cat > "$d/effort.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font:16px/20px system-ui}
.tile{width:220px;margin:10px;padding:4px;background:#eef}</style></head><body>
<p class="tile"><b data-testid="kpi-derived">72.9 hours from the start and end times on each run record</b> ·
<span data-testid="kpi-recomputed">79.0 hours when every duration is worked out again from the stream itself</span></p>
<p class="tile"><span data-testid="note-one">the first note wraps over several lines of this narrow tile here</span></p>
<p class="tile" style="margin-top:-60px"><span data-testid="note-two">the second note is pulled up so its lines are drawn over the first</span></p>
</body></html>
HTML
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-verify-screens.mjs" "$d/screens.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  local out; out="$( cd "$d" && timeout 120 node screens.mjs --base "http://127.0.0.1:$port" --screen effort=/effort.html \
                     --widths 1280 --render-wait 500 --json-out "$d/screens.json" 2>&1 )"
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  grep -q 'kpi-derived overlaps kpi-recomputed' <<<"$out" \
    && { bad tf_036a "two wrapped sentences sharing a line are reported as overlapping"; note "$(grep effort <<<"$out" | head -1)"; } \
    || ok tf_036a "two wrapped sentences that share a line do not overlap"
  grep -qE 'note-(one|two) overlaps note-(one|two)' <<<"$out" \
    && ok tf_036b "two wrapped inline elements drawn over each other are still reported" \
    || { bad tf_036b "the fragment comparison went blind to a real overlap"; note "$(grep effort <<<"$out" | head -1)"; }
}

# === AppManager's feedback file (docs/AppManager-TechieFlow-Feedback.md, 2026-09-13) =========
# AppManager numbers its entries TF-001 to TF-006 as well, so its cases are am_NNN.

# --- AppManager TF-001: --add-missing could not see a migrated checklist's BRD ids -------------
# A checklist migrated from an older plan names its items on the requirement line, "(BRD-1, BRD-2)"
# or "*(BRD-84, BRD-85)*", with no *BRD:* line and no id in the status table: one run appended a row
# for all 88 BRD items.
am_001() {
  local d="$SCRATCH/am001"; mkdir -p "$d/docs" "$d/.tfcore"
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  cat > "$d/docs/Fx-BRD.md" <<'MD'
# Fx — Business Requirements

| | |
|---|---|
| Size | Small |

## Requirements

- **BRD-1** — Applications can be created. *Screen:* Applications
- **BRD-2** — Applications can be edited. *Screen:* Applications
- **BRD-3** — Users can be listed. *Screen:* Users
- **BRD-4** — Devices can be blocked. *Screen:* Devices
MD
  cat > "$d/docs/Fx-Checklist.md" <<'MD'
# Fx — Checklist

## Requirements Status

| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-FN-001 | Application create and edit (P1) | Done (pre-existing) | 100% | — | [view](#d-req-fn-001) |
| REQ-UI-001 | Users list (P1) | Done (pre-existing) | 100% | — | [view](#d-req-ui-001) |

## Functional

<a id="d-req-fn-001"></a>
- **REQ-FN-001** — Application create and edit with a testable connection. (BRD-1, BRD-2)

<a id="d-req-ui-001"></a>
### Page: Users (`/users`)
- **REQ-UI-001** — Users list with search. *(BRD-3)*
MD
  local out; out="$(cd "$d" && python3 "$UTILS/tf-split-brd.py" Fx --add-missing 2>&1)"
  local n; n="$(grep -c '^| REQ-' "$d/docs/Fx-Checklist.md")"
  if [[ "$n" == "3" ]] && grep -q "Devices can be blocked" "$d/docs/Fx-Checklist.md"; then
    ok am_001 "a migrated checklist's ids on the requirement line are seen; only the one new item is appended"
  else
    bad am_001 "--add-missing appended $((n - 2)) row(s) for 1 new item"; note "$(head -c 200 <<<"$out")"
  fi
}

# --- AppManager TF-002: a "### Page:" heading under the anchor cut the entry off ----------------
am_002() {
  local d="$SCRATCH/am002"; mkdir -p "$d/docs/mockups"
  echo '<p>users</p>' > "$d/docs/mockups/users.html"
  cat > "$d/docs/Fx-Checklist.md" <<'MD'
# Fx — Requirements Checklist

## Requirements Status

| ID | Title | Status | % | Remarks | Detail |
|---|---|---|---|---|---|
| REQ-UI-001 | Users list | Verified | 100% | — | [view](#d-req-ui-001) |
| REQ-FN-002 | Users export | Verified | 100% | — | [view](#d-req-fn-002) |

## Coverage

<a id="d-req-ui-001"></a>
### Page: Users (`/users`)
- **REQ-UI-001** — Users list (BRD-1)
  - Acceptance: When a user opens Users on Users, then the list shows.
  - *Mockup:* [mockups/users.html](mockups/users.html)

<a id="d-req-fn-002"></a>
- **REQ-FN-002** — Users export
  - Acceptance: When a user exports on Users, then a file downloads.
MD
  local out; out="$(python3 "$UTILS/tf-doc-check.py" --root "$d" --quiet "$d/docs/Fx-Checklist.md" 2>&1)"
  # REQ-FN-002 really names no BRD item: that finding proves the entries were read at all, and that
  # REQ-UI-001's reading stopped where REQ-FN-002 begins
  if grep -q 'REQ-FN-002 detail entry does not name its BRD-N item' <<<"$out" \
     && ! grep -qE 'REQ-UI-001 (must have exactly one acceptance line|detail entry does not name|is a UI row without a mockup link)' <<<"$out"; then
    ok am_002 "an entry with its page heading under the anchor is read whole, and the next entry still ends it"
  else
    bad am_002 "the entry was cut at its own heading"; note "$(grep -E 'REQ-(UI-001|FN-002)' <<<"$out" | head -2)"
  fi
}

# --- AppManager TF-003: Done (pre-existing) rows on the working list ---------------------------
am_003() {
  local d="$SCRATCH/am003"; mkdir -p "$d/docs" "$d/.tfcore"
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  cat > "$d/docs/Fx-Checklist.md" <<'MD'
# Fx — Checklist

## Requirements Status

| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-FN-005 | Account lockout (P1) | Done (pre-existing) | 100% | — | [view](#d-req-fn-005) |
| REQ-FN-006 | Password reset | Not Started | 0% | — | [view](#d-req-fn-006) |

## Functional

<a id="d-req-fn-005"></a>
- **REQ-FN-005** — Account lockout (BRD-5)
<a id="d-req-fn-006"></a>
- **REQ-FN-006** — Password reset (BRD-6)
  - *Acceptance:* When a user asks for a reset on Sign-in, then an email is sent.
MD
  local out; out="$(cd "$d" && python3 "$UTILS/tf-build-list.py" Fx 2>&1)"
  if grep -q '1 row(s) to build; 1 terminal' <<<"$out" && ! grep -q 'REQ-FN-005 \[' <<<"$out"; then
    ok am_003 "a Done (pre-existing) row is finished: it is not on the working list and is not asked for an acceptance line"
  else
    bad am_003 "a Done (pre-existing) row was put on the working list"; note "$(grep -E '^Mode|REQ-FN-005' <<<"$out" | head -2)"
  fi
}

# --- AppManager TF-004: a Web API answers 404 at /, and the other side's asset lists -------------
am_004() {
  local d; d="$(_tf043_fx am004)"
  # the app answers every request with 404, as a Web API with nothing at / does
  cat > "$d/bin/dotnet" <<'SH'
#!/usr/bin/env bash
urlport() { local u=""; while [[ $# -gt 0 ]]; do [[ "$1" == "--urls" ]] && u="$2"; shift; done; echo "${u##*:}"; }
case "$1" in
  publish) out=""; for ((i=1; i<=$#; i++)); do [[ "${!i}" == "-o" ]] && { j=$((i+1)); out="${!j}"; }; done
           mkdir -p "$out"; echo dll > "$out/Fx.dll"; echo "Fx -> $out"; exit 0 ;;
  build) echo "Build succeeded."; exit 0 ;;
  *.dll) exec python3 -c 'import http.server,sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self): self.send_response(404); self.send_header("Content-Length","0"); self.end_headers()
    def log_message(self,*a): pass
http.server.HTTPServer(("127.0.0.1",int(sys.argv[1])),H).serve_forever()' "$(urlport "$@")" "$1" ;;
esac
SH
  chmod +x "$d/bin/dotnet"
  local p; p="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  local out; out="$(timeout 200 cat < <(cd "$d" && HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" bash "$UTILS/tf-verify-boot.sh" start --project p/Fx.csproj --port "$p" 2>&1))"
  if grep -q '^BOOTED' <<<"$out"; then
    ok am_004a "an app that answers 404 at / is up: any HTTP answer counts"
  else
    bad am_004a "an app answering 404 was reported as not brought up"; note "$(grep -E '^(BOOTED|NONE)' <<<"$out" | cut -c1-160)"
  fi
  ( cd "$d" && HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" bash "$UTILS/tf-verify-boot.sh" stop --port "$p" ) >/dev/null 2>&1
  pkill -f "Fx.dll" 2>/dev/null
  # a web head whose referenced library was last built on the Windows side, with Windows paths in its asset list
  local e="$SCRATCH/am004b"; mkdir -p "$e/bin" "$e/home" "$e/p" "$e/lib/obj/Debug/net10.0"
  printf '<Project Sdk="Microsoft.NET.Sdk.Web"><ItemGroup><ProjectReference Include="..\\lib\\Lib.csproj" /></ItemGroup></Project>\n' > "$e/p/Fx.csproj"
  printf '<Project Sdk="Microsoft.NET.Sdk.Razor"></Project>\n' > "$e/lib/Lib.csproj"
  printf '{"ContentRoot":"C:\\\\1MyCode\\\\Fx\\\\lib\\\\wwwroot\\\\"}\n' > "$e/lib/obj/Debug/net10.0/staticwebassets.publish.json"
  echo windows > "$e/lib/obj/.tf-build-side"
  printf '#!/usr/bin/env bash\necho "Build succeeded."; exit 0\n' > "$e/bin/dotnet"; chmod +x "$e/bin/dotnet"
  ( cd "$e" && HOME="$e/home" PATH="$e/bin:/usr/bin:/bin" TF_BUILD_PLATFORM=wsl bash "$UTILS/tf-build.sh" build p/Fx.csproj ) >/dev/null 2>&1
  if [[ ! -f "$e/lib/obj/Debug/net10.0/staticwebassets.publish.json" && "$(cat "$e/lib/obj/.tf-build-side" 2>/dev/null)" == wsl ]]; then
    ok am_004b "a build that changes side clears the referenced library's asset lists the other side wrote"
  else
    bad am_004b "a Windows-written asset list in a referenced library survived a WSL build"
  fi
}

# --- AppManager TF-005: a Testing Platform project prints no line per test ----------------------
am_005() {
  local d="$SCRATCH/am005"; mkdir -p "$d/.tfcore" "$d/tests/Fx.Tests"
  cp -r "$UTILS" "$d/.tfcore/"
  printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TestingPlatformDotnetTestSupport>true</TestingPlatformDotnetTestSupport></PropertyGroup><ItemGroup><PackageReference Include="xunit.v3" Version="3.2.2" /></ItemGroup></Project>\n' > "$d/tests/Fx.Tests/Fx.Tests.csproj"
  cat > "$d/.tfcore/utils/tf-build.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" > __D__/build.args
sleep 1
mkdir -p __D__/tests/Fx.Tests/bin/Debug/net10.0/TestResults __D__/tests/.artifacts/build
cat > __D__/tests/Fx.Tests/bin/Debug/net10.0/TestResults/fx.trx <<'X'
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>
<UnitTestResult testName="REQ-NFR-007 the whole suite finishes" outcome="Passed" />
<UnitTestResult testName="REQ-FN-003 an invite answers 201" outcome="Failed"><Output><ErrorInfo><Message>expected 201, got 500</Message></ErrorInfo></Output></UnitTestResult>
</Results></TestRun>
X
echo "Passed! - Failed: 1, Passed: 1, Skipped: 0, Total: 2" > __D__/tests/.artifacts/build/unit.log
echo "FAIL  tests failed on wsl via dotnet (rung 1); log tests/.artifacts/build/unit.log"
SH
  sed -i "s#__D__#$d#g" "$d/.tfcore/utils/tf-build.sh"
  ( cd "$d" && bash .tfcore/utils/tf-verify-tests.sh --no-browser --json-out tests/.artifacts/verify/tests.json ) >/dev/null 2>&1
  local got; got="$(python3 -c "import json,sys
try: r=json.load(open(sys.argv[1]))['reqs']
except Exception: print('no-output'); sys.exit()
print(r.get('REQ-NFR-007',{}).get('result'), r.get('REQ-FN-003',{}).get('result'), r.get('REQ-FN-003',{}).get('reason',''))" "$d/tests/.artifacts/verify/tests.json")"
  if grep -q -- '-p:TestingPlatformCommandLineArguments=--report-xunit-trx' "$d/build.args" 2>/dev/null; then
    ok am_005a "a Testing Platform project on xunit.v3 is asked for a TRX report"
  else
    bad am_005a "no report switch reached the Testing Platform project"; note "$(cat "$d/build.args" 2>/dev/null)"
  fi
  if [[ "$got" == "PASS FAIL unit test failed: expected 201, got 500" ]]; then
    ok am_005b "unit tests are mapped to rows from the TRX report, failures with their message"
  else
    bad am_005b "the TRX report was not read into the rows"; note "$got"
  fi
}

# --- AppManager TF-006: a signed-in screen whose document answers 401 -------------------------
# The sign-in lives in the page, not in a cookie: the document answers 401, then the page draws the
# screen from the session it keeps in the tab, or only once opened from inside the page.
am_006() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip am_006 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/am006"; mkdir -p "$d"
  cat > "$d/app.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Fx</title></head><body><main id="root"></main>
<script>
 let live = false;                                   // a sign-in held only by this page
 const root = document.getElementById('root');
 function draw() {
   const p = location.pathname, kept = sessionStorage.getItem('signed') === '1';
   if (p.startsWith('/login')) {
     root.innerHTML = '<form id="f"><input name="email" type="email"><input name="password" type="password"><button type="submit">Sign in</button></form>';
     document.getElementById('f').addEventListener('submit', (e) => { e.preventDefault(); live = true; sessionStorage.setItem('signed', '1'); history.pushState({}, '', '/'); draw(); });
     return;
   }
   const ok = p.startsWith('/vault') ? live : (live || kept);
   root.innerHTML = ok ? `<h1>${p}</h1><p>Signed in, showing ${p} with its rows and figures.</p>` : '<p>Please sign in.</p><form><input type="password"></form>';
 }
 addEventListener('popstate', draw);
 setTimeout(draw, 600);                              // the page's live connection attaches a moment later
</script></body></html>
HTML
  cat > "$d/server.py" <<'PY'
import http.server, sys
APP = open(sys.argv[2], "rb").read()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(401 if self.path.startswith(("/users", "/vault")) else 200)
        self.send_header("Content-Type", "text/html; charset=utf-8"); self.send_header("Content-Length", str(len(APP))); self.end_headers()
        self.wfile.write(APP)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-verify-screens.mjs" "$d/screens.mjs"; cp "$UTILS/tf-login.mjs" "$d/"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 "$d/server.py" "$port" "$d/app.html" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  ( cd "$d" && timeout 240 node screens.mjs --base "http://127.0.0.1:$port" --screen user-devices=/users/66 --screen vault=/vault \
      --widths 1280 --login-path /login --user a@b.c --password x --render-wait 2000 --json-out "$d/screens.json" >/dev/null 2>&1 )
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  local r; r="$(python3 -c "import json,sys
try: s=json.load(open(sys.argv[1]))['screens']
except Exception: print('no-output'); sys.exit()
print(' '.join(x['name']+'='+x['render'] for x in s))" "$d/screens.json")"
  grep -q 'user-devices=OK' <<<"$r" && ok am_006a "a screen whose document answers 401 and then draws signed in is graded, not unreachable" \
                                    || { bad am_006a "a 401 document was graded unreachable though the page drew the screen"; note "$r"; }
  grep -q 'vault=OK' <<<"$r" && ok am_006b "a screen whose sign-in lives only in the page is opened from inside the page after signing in" \
                             || { bad am_006b "a sign-in held by the page was lost to a fresh page load"; note "$r"; }
}

# --- AppManager TF-007: a .slnx-only solution, and a test project two folders under tests/ ------
# `ls *.sln *.slnx` failed whenever there was no .sln, and `tests/*/*.csproj` looked one folder deep,
# so AppManager (AppManager.slnx, tests/unit/AppManager.UnitTests/) ran no unit test at all.
_am007_fx() {   # $1 folder: the utils, with tf-build.sh replaced by one that records its arguments
  mkdir -p "$1/.tfcore" "$1/tests/unit/Fx.UnitTests"
  cp -r "$UTILS" "$1/.tfcore/"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$1/tests/unit/Fx.UnitTests/Fx.UnitTests.csproj"
  cat > "$1/.tfcore/utils/tf-build.sh" <<SH
#!/usr/bin/env bash
echo "\$*" > $1/build.args
mkdir -p $1/tests/.artifacts/build
echo "  Passed REQ-NFR-007 the whole suite finishes [12 ms]" > $1/tests/.artifacts/build/unit.log
echo "PASS  tests passed on wsl via dotnet (rung 1); log tests/.artifacts/build/unit.log"
SH
}
am_007() {
  local d="$SCRATCH/am007" got out
  _am007_fx "$d/a"; : > "$d/a/Fx.slnx"
  ( cd "$d/a" && bash .tfcore/utils/tf-verify-tests.sh --no-browser ) >/dev/null 2>&1
  got="$(python3 -c "import json,sys
try: print(json.load(open(sys.argv[1]))['reqs'].get('REQ-NFR-007',{}).get('result'))
except Exception: print('no-output')" "$d/a/tests/.artifacts/verify/tests.json")"
  [[ "$got" == PASS ]] && ok am_007a "a root holding only a .slnx runs the unit tests and maps them to rows" \
                       || { bad am_007a "a .slnx-only solution was read as no solution"; note "REQ-NFR-007: $got"; }
  _am007_fx "$d/b"
  ( cd "$d/b" && bash .tfcore/utils/tf-verify-tests.sh --no-browser ) >/dev/null 2>&1
  grep -q 'test tests/unit/Fx.UnitTests/Fx.UnitTests.csproj' "$d/b/build.args" 2>/dev/null \
    && ok am_007b "with no solution, the only test project two folders under tests/ is the target" \
    || { bad am_007b "a test project two folders under tests/ was not found"; note "$(cat "$d/b/build.args" 2>/dev/null || echo 'tf-build.sh never called')"; }
  _am007_fx "$d/c"; mkdir -p "$d/c/tests/integration/Fx.IntTests"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$d/c/tests/integration/Fx.IntTests/Fx.IntTests.csproj"
  out="$( cd "$d/c" && bash .tfcore/utils/tf-verify-tests.sh --no-browser 2>&1 )"
  if grep -q 'NOT RUN — no solution here and 2 test projects' <<<"$out" && [[ ! -f "$d/c/build.args" ]]; then
    ok am_007c "two test projects and no solution: both are named and none is guessed"
  else
    bad am_007c "several test projects without a solution were not named"; note "$(grep -m1 'unit tests' <<<"$out")"
  fi
}

# --- AppManager TF-008: UI rows sent to trblazeui in a project that does not use TrBlazeUI ------
# Every project is given .trblazeui/ by the framework, so the label must come from the project's files.
am_008() {
  local d="$SCRATCH/am008" out
  mkdir -p "$d/docs" "$d/.tfcore" "$d/.trblazeui" "$d/src/Fx"
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  cat > "$d/docs/Fx-Checklist.md" <<'MD'
# Fx — Checklist

## Requirements Status

| ID | Requirement | Status | % | Remarks | Details |
|----|-------------|--------|---|---------|---------|
| REQ-UI-001 | Sign-in page | Not Started | 0% | — | [view](#d-req-ui-001) |

## Page: Sign-in

<a id="d-req-ui-001"></a>
- **REQ-UI-001** — Sign-in page (BRD-1)
  - *Acceptance:* When a user submits the form on Sign-in, then the dashboard opens.
MD
  printf '<Project Sdk="Microsoft.NET.Sdk.Web"><ItemGroup><PackageReference Include="Dapper" Version="2.1.66" /></ItemGroup></Project>\n' > "$d/src/Fx/Fx.csproj"
  out="$(cd "$d" && python3 "$UTILS/tf-build-list.py" Fx 2>&1)"
  grep -q 'Cluster A \[builder\]: REQ-UI-001' <<<"$out" \
    && ok am_008a "a project with no TrBlazeUI reference has its UI cluster labelled builder" \
    || { bad am_008a "a UI cluster was sent to trblazeui in a project that does not use it"; note "$(grep -m1 '^Cluster' <<<"$out")"; }
  printf '<Project Sdk="Microsoft.NET.Sdk.Web"><ItemGroup><PackageReference Include="TrBlazeUI.Components" Version="2.0.3" /></ItemGroup></Project>\n' > "$d/src/Fx/Fx.csproj"
  out="$(cd "$d" && python3 "$UTILS/tf-build-list.py" Fx 2>&1)"
  grep -q 'Cluster A \[trblazeui\]: REQ-UI-001' <<<"$out" \
    && ok am_008b "a project referencing TrBlazeUI keeps its UI cluster on trblazeui" \
    || { bad am_008b "a TrBlazeUI project lost the trblazeui label"; note "$(grep -m1 '^Cluster' <<<"$out")"; }
  rm -rf "$d/src"; printf '# Fx — Architecture\n\nUI library: TrBlazeUI.\n' > "$d/docs/Fx-Architecture.md"
  out="$(cd "$d" && python3 "$UTILS/tf-build-list.py" Fx 2>&1)"
  grep -q 'Cluster A \[trblazeui\]: REQ-UI-001' <<<"$out" \
    && ok am_008c "before any project file exists, the Architecture document naming TrBlazeUI decides" \
    || { bad am_008c "a first build of a TrBlazeUI project lost the trblazeui label"; note "$(grep -m1 '^Cluster' <<<"$out")"; }
}

# --- AppManager TF-009: the usage guide named {App}-Usage-Guide.md, Test users at ### --------------
# Only {App}-UsageGuide.md was looked for, the heading only at ##, and only the template's numbered
# table was read, so AppManager's two test users read as "none in the UsageGuide".
am_009() {
  local d="$SCRATCH/am009" out
  mkdir -p "$d/docs"
  cat > "$d/docs/Fx-Usage-Guide.md" <<'MD'
# Fx Usage Guide

## 4. Default Login Credentials

### Test users

| Role | Email | Password | Scope |
|------|-------|----------|-------|
| Admin | `admin@fx.local` | `Admin@123!` | All |
| Manager | `tester@fx.local` | `Tester@123!` | One application |

## 5. Authentication
MD
  out="$(cd "$d" && python3 -c "
import importlib.util
s=importlib.util.spec_from_file_location('vl','$UTILS/tf-verify-list.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(' '.join(u['user']+'/'+u['role'] for u in m.test_users(m.usage_guide('Fx'))))" 2>&1)"
  [[ "$out" == "admin@fx.local/Admin tester@fx.local/Manager" ]] \
    && ok am_009a "a guide named {App}-Usage-Guide.md with Test users at ### and a Role/Email table is read" \
    || { bad am_009a "the test users of a {App}-Usage-Guide.md were not read"; note "$out"; }
  cat > "$d/docs/Fy-UsageGuide.md" <<'MD'
# Fy

## Test users

| # | User | Password source | Role | Exists |
|---|---|---|---|---|
| 1 | admin@fy.test | user secrets | Admin | yes |
MD
  out="$(cd "$d" && python3 -c "
import importlib.util
s=importlib.util.spec_from_file_location('vl','$UTILS/tf-verify-list.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(' '.join(u['user']+'/'+u['password_source']+'/'+u['role'] for u in m.test_users(m.usage_guide('Fy'))))" 2>&1)"
  [[ "$out" == "admin@fy.test/user secrets/Admin" ]] \
    && ok am_009b "the template's numbered Test users table still reads as before" \
    || { bad am_009b "the template's numbered table no longer reads"; note "$out"; }
  out="$(cd "$d" && python3 -c "
import importlib.util
s=importlib.util.spec_from_file_location('dl','$UTILS/tf-devguide-list.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
print('roles: ' + ', '.join(sorted({r for _u, r in m.roles_from_usageguide('Fx')})))" 2>&1)"
  [[ "$out" == "roles: Admin, Manager" ]] \
    && ok am_009c "tf-devguide-list reads the same guide for its roles" \
    || { bad am_009c "tf-devguide-list still finds no roles in a {App}-Usage-Guide.md"; note "$out"; }
}

# --- AppManager TF-010: two web projects, the first in sorted order booted -----------------------
# AppManagerApi sorts before AppManagerWeb and has no screens; the admin site was never booted.
am_010() {
  local d="$SCRATCH/am010" out
  mkdir -p "$d/src/FxApi" "$d/src/FxWeb/Components/Pages" "$d/src/FxUi" "$d/tests/.artifacts/verify"
  printf '<Project Sdk="Microsoft.NET.Sdk.Web"></Project>\n' > "$d/src/FxApi/FxApi.csproj"
  printf '<Project Sdk="Microsoft.NET.Sdk.Web"><ItemGroup><ProjectReference Include="..\\FxUi\\FxUi.csproj" /></ItemGroup></Project>\n' > "$d/src/FxWeb/FxWeb.csproj"
  printf '<Project Sdk="Microsoft.NET.Sdk.Razor"></Project>\n' > "$d/src/FxUi/FxUi.csproj"
  printf '@page "/"\n<h1>Home</h1>\n' > "$d/src/FxWeb/Components/Pages/Home.razor"
  out="$(cd "$d" && bash "$UTILS/tf-verify-boot.sh" start --dry-run 2>&1 | tail -1)"
  [[ "$out" == "PICK head=web project=src/FxWeb/FxWeb.csproj" ]] \
    && ok am_010a "with two web projects the one that serves screens is booted" \
    || { bad am_010a "the first web project in sorted order is still booted"; note "$out"; }
  rm -rf "$d/src/FxWeb/Components"; sed -i 's#<ItemGroup>.*</ItemGroup>##' "$d/src/FxWeb/FxWeb.csproj"
  out="$(cd "$d" && bash "$UTILS/tf-verify-boot.sh" start --dry-run 2>&1 | tail -1)"
  [[ "$out" == NONE*"2 web projects"*"name one with --project"* ]] \
    && ok am_010b "two web projects and none serving screens stops with the candidates named" \
    || { bad am_010b "a guess was made between two web projects"; note "$out"; }
  out="$(cd "$d" && bash "$UTILS/tf-verify-boot.sh" start --dry-run --project src/FxApi/FxApi.csproj 2>&1 | tail -1)"
  [[ "$out" == "PICK head=web project=src/FxApi/FxApi.csproj" ]] \
    && ok am_010c "--project still names the project" \
    || { bad am_010c "--project no longer decides"; note "$out"; }
}

# --- AppManager TF-011 and TF-012: a sign-in the page keeps for itself ---------------------------
# The document of every signed-in screen answers 401 and the app sets no cookie. tf-assets and
# tf-mockup-parity took only --cookie, so neither could grade anything; and tf-verify-screens read a
# signed-in form with a password field (Create user) as the sign-in page and graded it unreachable.
_inpage_server() { # dir port -> starts the fixture app, pid in $dir/srv.pid
  cat > "$1/server.py" <<'PY'
import http.server, sys
PORT = int(sys.argv[1])
CSS = "body{margin:0;font:14px/20px system-ui} .badge{display:inline-block;border-radius:8px;background:#2563eb;color:#fff;padding:2px 8px;height:20px}"
APP = """<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="/app.css"><link rel="stylesheet" href="/missing.css"><script src="/app.js"></script></head>
<body><div id="root"></div><script>
function draw(){var p=location.pathname,r=document.getElementById('root');
 if(!sessionStorage.getItem('fx')){r.innerHTML='<form data-testid="login-form"><input data-testid="login-email" type="email"><input data-testid="login-pass" type="password"><button type="submit">Sign in</button></form>';return;}
 if(p==='/users/create'){r.innerHTML='<h1 data-testid="page-title">Create user</h1><form data-testid="user-form"><label>Email <input data-testid="user-email" type="email"></label><label>Password <input data-testid="user-password" type="password"></label><button data-testid="user-save" type="button">Create</button></form>';return;}
 r.innerHTML='<div data-testid="dash-header"><h1>Dashboard</h1><span class="badge">3 open</span></div><table data-testid="dash-table"><tr><th>Name</th><th>Count</th></tr><tr><td>Alpha</td><td>12</td></tr></table>';}
window.addEventListener('popstate',draw);draw();
</script></body></html>"""
LOGIN = """<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="/app.css"></head><body>
<form data-testid="login-form" onsubmit="sessionStorage.setItem('fx','1');location.href='/dashboard';return false">
<input data-testid="login-email" type="email"><input data-testid="login-pass" type="password"><button type="submit">Sign in</button></form></body></html>"""
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, ctype="text/html; charset=utf-8"):
        b = body.encode("utf-8"); self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/login": self.send(200, LOGIN)
        elif p == "/app.css": self.send(200, CSS, "text/css")
        elif p == "/app.js": self.send(200, "window.fxLoaded=1;", "text/javascript")
        elif p == "/missing.css": self.send(404, "not here", "text/plain")
        else: self.send(401, APP)
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY
  python3 "$1/server.py" "$2" >/dev/null 2>&1 & echo $! > "$1/srv.pid"
  sleep 1
}
am_011() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip am_011 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/am011"; mkdir -p "$d/docs/mockups"
  printf '<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font:14px/20px system-ui} .badge{display:inline-block;border-radius:8px;background:#2563eb;color:#fff;padding:2px 8px;height:20px}</style></head><body><div data-testid="dash-header"><h1>Dashboard</h1><span class="badge">3 open</span></div><table data-testid="dash-table"><tr><th>Name</th><th>Count</th></tr><tr><td>Alpha</td><td>12</td></tr></table></body></html>\n' > "$d/docs/mockups/dashboard.html"
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-login.mjs" "$UTILS/tf-mockup-parity.mjs" "$UTILS/tf-assets-browser.mjs" "$UTILS/tf-assets.sh" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  _inpage_server "$d" "$port"
  local out
  out="$( cd "$d" && timeout 120 bash ./tf-assets.sh --base "http://127.0.0.1:$port" --paths /dashboard --login-path /login --user a@b.c --password x --json-out "$d/assets.json" >/dev/null 2>&1; python3 -c "
import json; d=json.load(open('$d/assets.json')); p=d['pages'][0]
print(d['status'], p['status'], p.get('document_status'), p['declared'], p['graded'], ' '.join(f['problem'] for f in d['findings']))" 2>&1 )"
  [[ "$out" == "failed 200 401 3 3 status-404" ]] \
    && ok am_011a "tf-assets signs in through the form, grades the signed-in page's assets and still sees the 404" \
    || { bad am_011a "tf-assets could not get past an in-page sign-in"; note "$out"; }
  out="$( cd "$d" && timeout 120 node tf-mockup-parity.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen dashboard=/dashboard --widths 1280 --login-path /login --user a@b.c --password x --json-out "$d/parity.json" >/dev/null 2>&1; python3 -c "
import json; s=json.load(open('$d/parity.json'))['screens'][0]; w=s['widths'][0]
print(s['verdict'], w['compared'] > 0, w.get('reached','')[:23])" 2>&1 )"
  [[ "$out" == "PASS True answered HTTP 401, then" ]] \
    && ok am_011b "tf-mockup-parity signs in the same way, grades the screen and records how it was reached" \
    || { bad am_011b "tf-mockup-parity still stops at HTTP 401"; note "$out"; }
  kill "$(cat "$d/srv.pid")" 2>/dev/null
}
am_012() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip am_012 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/am012"; mkdir -p "$d/tests/.artifacts/verify"
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-login.mjs" "$UTILS/tf-verify-screens.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  _inpage_server "$d" "$port"
  local out
  out="$( cd "$d" && timeout 120 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --screen user-create=/users/create --screen dash=/dashboard \
           --login-path /login --user a@b.c --password x --widths 1280 --json-out "$d/screens.json" --shots-dir "$d/shots" 2>&1 | grep -E '^(OK|FAIL) ' )"
  grep -q '^OK   user-create' <<<"$out" \
    && ok am_012a "a signed-in form with a password field for the new account is graded, not read as the sign-in page" \
    || { bad am_012a "a signed-in form with a password field is still unreachable"; note "$(head -2 <<<"$out")"; }
  grep -q '^OK   dash' <<<"$out" \
    && ok am_012b "a screen behind the in-page sign-in is still reached (TF-006 holds)" \
    || { bad am_012b "the in-page sign-in screen is no longer reached"; note "$(grep dash <<<"$out")"; }
  # signed OUT: the same tab without the sign-in draws the sign-in form at the screen's own address
  out="$( cd "$d" && timeout 120 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --screen dash=/dashboard \
           --login-path /login --user nobody --password x --widths 1280 --json-out "$d/screens2.json" --shots-dir "$d/shots" 2>&1 | grep -E '^(OK|FAIL) ' )"
  grep -q '^FAIL dash' <<<"$out" \
    && ok am_012c "a sign-in form drawn at the screen's own address still reads as signed out" \
    || { bad am_012c "a page showing the sign-in form was graded as the screen"; note "$out"; }
  kill "$(cat "$d/srv.pid")" 2>/dev/null
}

# --- AppManager TF-013: the whole browser suite in one command ---------------------------------
# No shard or file option, every run overwrote playwright.json and tests.json, so parts could not be
# combined through the script. --shard N/M and --spec run parts, --merge combines them.
am_013() {
  local d="$SCRATCH/am013" out
  mkdir -p "$d/tests/.artifacts/verify"
  cat > "$d/a.json" <<'J'
{"reqs":{"REQ-UI-001":{"result":"PASS","source":"browser","tests":["REQ-UI-001 opens"],"skipped":[],"passed":1,"failed":0,"reason":"","screenshot":""},"REQ-UI-002":{"result":"NOT-TESTED","source":"browser","tests":[],"skipped":["REQ-UI-002 seeded"],"passed":0,"failed":0,"reason":"skipped: needs seed","screenshot":""}},"browser":{"ran":true,"passed":1,"failed":0,"skipped":1,"tests":2},"unit":{"ran":false,"line":""}}
J
  cat > "$d/b.json" <<'J'
{"reqs":{"REQ-UI-001":{"result":"FAIL","source":"browser","tests":["REQ-UI-001 saves"],"skipped":[],"passed":0,"failed":1,"reason":"expected 1 got 0","screenshot":"tests/x.png"},"REQ-UI-002":{"result":"PASS","source":"browser","tests":["REQ-UI-002 lists"],"skipped":[],"passed":1,"failed":0,"reason":"","screenshot":""},"REQ-NFR-007":{"result":"PASS","source":"unit","tests":["REQ-NFR-007 unit"],"skipped":[],"passed":3,"failed":0,"reason":"","screenshot":""}},"browser":{"ran":true,"passed":1,"failed":1,"skipped":0,"tests":2},"unit":{"ran":true,"line":"PASS unit"}}
J
  out="$(cd "$d" && bash "$UTILS/tf-verify-tests.sh" --merge a.json b.json --json-out merged.json 2>&1 | head -1)"
  local rows; rows="$(python3 -c "
import json; d=json.load(open('$d/merged.json')); r=d['reqs']
print(r['REQ-UI-001']['result'], r['REQ-UI-001']['failed'], len(r['REQ-UI-001']['tests']), r['REQ-UI-002']['result'], r['REQ-NFR-007']['result'], d['browser']['tests'], d['unit']['ran'])" 2>&1)"
  [[ "$rows" == "FAIL 1 2 PASS PASS 4 True" ]] \
    && ok am_013a "--merge combines the parts' rows (FAIL wins, PASS over NOT-TESTED, counts add) and the totals" \
    || { bad am_013a "--merge does not combine the parts"; note "$rows"; }
  out="$(cd "$d" && bash "$UTILS/tf-verify-tests.sh" --shard 2/4 2>&1 | tail -1)"
  [[ "$out" == "JSON: tests/.artifacts/verify/tests-2of4.json" && -f "$d/tests/.artifacts/verify/tests-2of4.json" ]] \
    && ok am_013b "--shard N/M writes its own tests-NofM.json, so parts do not overwrite each other" \
    || { bad am_013b "a shard run still writes tests.json"; note "$out"; }
  out="$(cd "$d" && bash "$UTILS/tf-verify-tests.sh" --shard 2 2>&1 | head -1)"
  [[ "$out" == *"--shard takes N/M"* ]] \
    && ok am_013c "a malformed --shard is refused with the shape named" \
    || { bad am_013c "a malformed --shard was accepted"; note "$out"; }
}

# --- AppManager TF-014: "escaped the shell's scroll container" on an app whose document scrolls ---
am_014() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip am_014 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/am014"; mkdir -p "$d/docs/mockups"
  local page='<div data-testid="report-title"><h1>Adoption</h1></div><div data-testid="report-rows">'"$(printf '<p>row %s</p>' $(seq 1 120))"'</div>'
  printf '<!doctype html><html><head><meta charset="utf-8"></head><body>%s</body></html>\n' "$page" > "$d/docs/mockups/report.html"
  # the document is the only scroller: a long report, nothing escaped
  printf '<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0}</style></head><body><nav style="width:200px;height:300px;overflow-y:auto">menu</nav>%s</body></html>\n' "$page" > "$d/report.html"
  # a shell with a content scroll container, and the document scrolling as well
  printf '<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0}</style></head><body><main style="height:600px;overflow-y:auto">%s</main><div style="height:900px"></div></body></html>\n' "$page" > "$d/escaped.html"
  cp "$d/docs/mockups/report.html" "$d/docs/mockups/escaped.html"
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-mockup-parity.mjs" "$d/parity.mjs"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  ( cd "$d" && timeout 180 node parity.mjs --base "http://127.0.0.1:$port" --screen report=/report.html --screen escaped=/escaped.html \
      --widths 1280 --json-out "$d/parity.json" >/dev/null 2>&1 )
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  local f; f="$(python3 -c "import json
for s in json.load(open('$d/parity.json'))['screens']: print(s['screen'], ' '.join(x['class'] for x in s['findings']))" 2>&1)"
  grep -qx 'report ' <<<"$f" && ok am_014a "a document that is the app's only scroller gives no document-scroll finding" \
    || { bad am_014a "a long page whose document scrolls is still reported as escaped"; note "$f"; }
  grep -q '^escaped .*document-scroll' <<<"$f" && ok am_014b "a document scrolling beside a content scroll container is still reported" \
    || { bad am_014b "a page that escaped its scroll container went unreported"; note "$f"; }
}

# --- AppManager TF-015: a padded one-line badge read as two rows -------------------------------
# lineCount divided the border box by the line height, so a badge with 4px padding top and bottom
# and `line-height: 1` measured 18 / 9.756 = 1.85, rounded to 2: "wraps to 2 rows where the mockup
# keeps it on 1" on AppManager's adoption report, whose badges all sit on one line (2026-09-15).
am_015() {
  local pw; pw="$(_pw_dir)"
  if [[ -z "$pw" ]]; then
    printf 'skip am_015 — playwright is not installed here (set TF_PLAYWRIGHT_DIR=<a repo that has it>)\n'
    return
  fi
  local d="$SCRATCH/am015"; mkdir -p "$d/docs/mockups"
  local head='<!doctype html><html><head><meta charset="utf-8"><style>'
  printf '<!doctype html><html><head><meta charset="utf-8"></head><body><div data-testid="status"><span>Not adopted</span></div></body></html>\n' > "$d/docs/mockups/badge.html"
  printf '%s%s</style></head><body><div data-testid="status"><span class="b">Not adopted</span></div></body></html>\n' "$head" \
    '.b{display:inline-block;padding:4px 8px;line-height:1;font-size:9.756px;white-space:nowrap}' > "$d/badge.html"
  printf '<!doctype html><html><head><meta charset="utf-8"></head><body><div data-testid="note"><span>Not adopted on any device</span></div></body></html>\n' > "$d/docs/mockups/wrapped.html"
  printf '%s%s</style></head><body><div data-testid="note"><span class="w">Not adopted on any device</span></div></body></html>\n' "$head" \
    '.w{display:inline-block;width:40px;padding:4px;line-height:1;font-size:10px}' > "$d/wrapped.html"
  ln -sfn "$pw/node_modules" "$d/node_modules"
  cp "$UTILS/tf-mockup-parity.mjs" "$d/parity.mjs"; cp "$UTILS/tf-login.mjs" "$d/"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d" >/dev/null 2>&1 & echo $! > "$d/srv.pid"
  sleep 1
  ( cd "$d" && timeout 180 node parity.mjs --base "http://127.0.0.1:$port" --screen badge=/badge.html --screen wrapped=/wrapped.html \
      --widths 1280 --json-out "$d/parity.json" >/dev/null 2>&1 )
  kill "$(cat "$d/srv.pid")" 2>/dev/null
  local f; f="$(python3 -c "import json
for s in json.load(open('$d/parity.json'))['screens']: print(s['screen'], ' '.join(x['class'] for x in s['findings']))" 2>&1)"
  grep -qx 'badge ' <<<"$f" && ok am_015a "a padded badge on one line is not reported as wrapping" \
    || { bad am_015a "a one-line badge's padding is still counted as a text row"; note "$f"; }
  grep -q '^wrapped .*wrap' <<<"$f" && ok am_015b "text that really wraps inside a padded box is still reported" \
    || { bad am_015b "a real wrap inside a padded box went unreported"; note "$f"; }
}

# --- the ignore file that grew by one block per update -----------------------------------
# `tr -d '\r' < .gitignore | grep -qE …` under `set -o pipefail`: grep -q stops at the first
# match, tr dies writing the rest, the pipeline reports failure, and the framework block is
# appended again. On the Windows drive it happened on every run once the file was large:
# TechieBlog's .gitignore held the block 50 times, TfLens's 30, a private project's 10. Proved on a copy of
# TechieBlog's file on /mnt/c: the old updater appended one block per run, the fixed one none.
# The race needs that drive and a full update to show, so the case pins the shape instead.
gitignore_once() {
  local hits; hits="$(grep -nE "< *\.git(ignore|attributes) *\| *grep -q" "$ROOT/update-framework.sh" "$ROOT"/scaffold-*.sh 2>/dev/null)"
  [[ -z "$hits" ]] && ok gitignore_once "no delivery script decides 'already there' through a pipe that grep -q can cut" \
                   || { bad gitignore_once "a delivery script can append its block again on every run"; note "$(head -2 <<<"$hits")"; }
}

# --- run ----------------------------------------------------------------------------------
echo "# tests/regression — the unhappy path, one case per defect a real project found"
for t in tf_013 tf_014 tf_015 tf_016 tf_017 tf_018 tf_019 tf_020 tf_021 tf_022 tf_024 tf_025 tf_026 tf_027 tf_028 tf_029 tf_030 tf_031 tf_032 tf_034 tf_035 tf_036 tf_037 tf_038 tf_040 tf_041 tf_042 tf_043 tf_044 tf_045 tf_046 tf_047 tf_048 tf_049 tf_050 tf_051 tf_052 am_001 am_002 am_003 am_004 am_005 am_006 am_007 am_008 am_009 am_010 am_011 am_012 am_013 am_014 am_015 owner_handoff feedback_state replies_complete gitignore_once tf_void tf_overlap tf_ledger guard_reads tf_selfcheck; do
  [[ -n "$only" && "$only" != "$t" ]] && continue
  "$t"
done
[[ $fail -eq 0 ]] && echo "# all regression cases hold" || echo "# regression cases FAILED"
exit $fail

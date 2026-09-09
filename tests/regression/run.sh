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
#
# Exit 0 all held, 1 a case failed. Python 3 standard library only. Never runs git.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UTILS="$ROOT/.tfcore/utils"
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
  cp "$UTILS/tf-verify-screens.mjs" "$d/screens.mjs"
  local port; port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  ( cd "$d" && python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 & echo $! > "$d/srv.pid" )
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

# --- run ----------------------------------------------------------------------------------
echo "# tests/regression — the unhappy path, one case per defect a real project found"
for t in tf_013 tf_014 tf_015 tf_016 tf_017 tf_018 tf_019 tf_020 tf_021 tf_022 tf_void tf_ledger guard_reads tf_selfcheck; do
  [[ -n "$only" && "$only" != "$t" ]] && continue
  "$t"
done
[[ $fail -eq 0 ]] && echo "# all regression cases hold" || echo "# regression cases FAILED"
exit $fail

#!/usr/bin/env bash
# tests/estimate/run.sh — effort estimates in tokens, and their reconciliation (SCHEMA.md §2.8).
#
# Three fixture repos, built here from nothing:
#   enough  — four or more live runs of every cmd on UI and FN rows: basis "repo", known quartiles
#   family  — one build run of its own: the build figure comes from the family repo, basis "family"
#   none    — no runs at all and no family: "no precedent", never a number
# Then: --dry-run writes nothing, a real run writes one record per row per cmd plus three totals
# through tf-emit.sh and never touches runs.jsonl, tf-emit.sh refuses a malformed estimate,
# --current-model reads the session pointer, and tf-metrics.sh --estimates sets the estimate
# beside the actual (apportioned runs labelled, fewer than three runs = insufficient data).
#
#   bash tests/estimate/run.sh
# Exit 0 = every case passed. bash 3.2 clean; nothing outside tests/.artifacts/ is written.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
EST="$ROOT/.tfcore/telemetry/tf-estimate.sh"
MET="$ROOT/.tfcore/telemetry/tf-metrics.sh"
EMIT="$ROOT/.tfcore/utils/tf-emit.sh"
SCRATCH="$ROOT/tests/.artifacts/estimate.$$"
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT
# never let a fixture's records reach the repo this suite runs in (suites leak telemetry under Claude Code)
unset CLAUDE_PROJECT_DIR
fail=0
ok()   { echo "ok   $1 — $2"; }
bad()  { echo "FAIL $1 — $2"; fail=1; }
note() { echo "     $1"; }

# ---- fixtures ----------------------------------------------------------------------------
# mkrepo <dir> <app> <phase> <rows...> : a checklist for the phase; runs come from mkruns
mkrepo() {
  local d="$1" app="$2" ph="$3"; shift 3
  mkdir -p "$d/docs/metrics"
  local f="$d/docs/$app-Checklist.md"
  [[ "$ph" != "1" ]] && { printf '# %s — Checklist\n\n## Requirements Status\n\n| ID | Requirement | Status |\n|----|----|----|\n| REQ-UI-001 | a | Verified |\n' "$app" > "$f"; f="$d/docs/$app-P$ph-Checklist.md"; }
  { printf '# %s — Checklist (phase %s)\n\n## Requirements Status\n\n| ID | Requirement | Status | %% | Remarks |\n|----|----|----|----|----|\n' "$app" "$ph"
    for r in "$@"; do printf '| %s | row %s | Not started | 0%% | |\n' "$r" "$r"; done
    printf '\n## Page: Other\n\n| REQ-FN-999 | not in the status table | x |\n'
  } > "$f"
}

# mkruns <dir> <python list of (cmd, reqs, tokens_out, seconds[, extra-dict])>
mkruns() {
  python3 - "$1/docs/metrics/runs.jsonl" "$2" <<'PY'
import json, sys, datetime
path, spec = sys.argv[1], eval(sys.argv[2])
t = datetime.datetime(2026, 10, 1, 8, 0, 0)
with open(path, "a", encoding="utf-8") as fh:
    for row in spec:
        cmd, reqs, tok, sec = row[:4]
        extra = row[4] if len(row) > 4 else {}
        start = t
        t = t + datetime.timedelta(seconds=sec)
        rec = {"v": 1, "kind": "run", "app": "Fx", "cmd": cmd,
               "started": start.strftime("%Y-%m-%dT%H:%M:%SZ"), "ended": t.strftime("%Y-%m-%dT%H:%M:%SZ"),
               "duration_s": sec, "reqs_touched": reqs, "reqs_count": len(reqs),
               "tokens_out": tok, "tokens_scope": "tree"}
        rec.update(extra)
        fh.write(json.dumps(rec) + "\n")
        t = t + datetime.timedelta(seconds=60)
PY
}

E="$SCRATCH/enough"; mkrepo "$E" Fx 2 REQ-UI-101 REQ-FN-101
# UI build history, per row: 1000 2000 3000 4000 tokens and 100 200 300 400 s -> q1 1750, median 2500, q3 3250
mkruns "$E" "[
 ('build-phase', ['REQ-UI-001'], 1000, 100), ('build-phase', ['REQ-UI-002','REQ-UI-003'], 4000, 400),
 ('build-phase', ['REQ-UI-004'], 3000, 300), ('build-phase', ['REQ-UI-005','REQ-UI-006'], 8000, 800),
 ('build-phase', ['REQ-FN-001'], 500, 50), ('build-phase', ['REQ-FN-002'], 700, 70), ('build-phase', ['REQ-FN-003'], 900, 90),
 ('verify-phase', ['REQ-UI-001','REQ-FN-001'], 400, 40), ('verify-phase', ['REQ-UI-002','REQ-FN-002'], 600, 60),
 ('verify-phase', ['REQ-UI-003','REQ-FN-003'], 800, 80),
 ('fix-issues', ['REQ-UI-001','REQ-FN-001'], 200, 20), ('fix-issues', ['REQ-UI-002','REQ-FN-002'], 300, 30),
 ('fix-issues', ['REQ-UI-003','REQ-FN-003'], 400, 40),
 ('build-phase', ['REQ-UI-007'], 999999, 9999, {'backfilled': True}),
 ('build-phase', ['REQ-UI-008'], 888888, 8888, {'tokens_scope': 'none'}),
 ('fix-issues', [], 77777, 777),
 ('build-phase', ['REQ-UI-101','REQ-UI-009'], 50000, 1000),
 ('verify-phase', ['REQ-UI-101','REQ-FN-101','REQ-UI-001'], 9000, 900),
 ('verify-phase', ['REQ-UI-101'], 3000, 300), ('verify-phase', ['REQ-FN-101'], 1500, 150),
 ('triage-and-fix', ['REQ-UI-001','REQ-FN-001'], 1200, 120), ('triage-issues', ['REQ-UI-002','REQ-FN-002'], 1800, 180),
 ('triage-and-fix', ['REQ-UI-003','REQ-FN-003'], 2400, 240),
 ('triage-and-fix', ['REQ-UI-101'], 5000, 500), ('triage-issues', ['REQ-FN-101','REQ-UI-005'], 4000, 400),
 ('triage-and-fix', ['REQ-UI-101','REQ-FN-101'], 3000, 300), ('triage-and-fix', [], 7000, 700),
 ('build-phase', ['REQ-UI-010'], 555555, 555)
]"
# the last build run is voided: it must leave the history
printf '{"v":1,"kind":"run-void","app":"Fx","cmd":"build-phase","started":"%s","reason":"fixture: a wrong record"}\n' \
  "$(python3 -c "import json; print([json.loads(l) for l in open('$E/docs/metrics/runs.jsonl')][-1]['started'])")" >> "$E/docs/metrics/runs.jsonl"

F="$SCRATCH/family"; mkrepo "$F" Fy 1 REQ-UI-201 REQ-RAG-201
mkruns "$F" "[('build-phase', ['REQ-UI-050'], 1234, 60)]"

N="$SCRATCH/none"; mkrepo "$N" Fz 3 REQ-UI-301 REQ-NFR-301

# ---- 1. enough history: basis repo, the quartiles, the exclusions --------------------------
out="$(bash "$EST" "$E" --phase 2 --dry-run --json 2>&1)"
got="$(python3 - <<PY 2>&1
import json
d = json.loads('''$out''')
rows = {r["req_id"]: r for r in d["rows"]}
b = rows["REQ-UI-101"]["build-phase"]
print(sorted(rows), b["basis"], b["basis_runs"], b["tokens_out"], b["duration_s"], d["history_skipped"])
PY
)"
if grep -q "\['REQ-FN-101', 'REQ-UI-101'\] repo 4 {'low': 1750, 'mid': 2500, 'high': 3250} {'low': 175, 'mid': 250, 'high': 325}" <<<"$got"; then
  ok es_001 "four UI runs give the UI row its own quartiles, basis repo; the FN row in another table is not a row"
else
  bad es_001 "the UI row's figure is not the quartiles of the UI history"; note "$got"
fi
if grep -q "'backfilled': 1, 'voided': 1, 'no_reqs': 2, 'this_phase': 7, 'no_tokens': 1" <<<"$got"; then
  ok es_002 "backfilled, voided, row-less, token-less runs and runs on this phase's own rows all leave the history, counted"
else
  bad es_002 "the history kept a run it must leave out"; note "$got"
fi
fn="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); r=[x for x in d['rows'] if x['req_id']=='REQ-FN-101'][0]['build-phase']; print(r['basis'], r['tokens_out'])" <<<"$out")"
if [[ "$fn" == "repo {'low': 600, 'mid': 700, 'high': 800}" ]]; then
  ok es_003 "an FN row is estimated from FN history only, not from the UI runs beside it"
else
  bad es_003 "the FN row took another prefix's history"; note "$fn"
fi

# ---- 2. dry run writes nothing; a real run writes through tf-emit and never touches runs ----
before="$(cksum < "$E/docs/metrics/runs.jsonl")"
table="$(bash "$EST" "$E" --phase 2 --dry-run 2>&1)"
if [[ ! -e "$E/docs/metrics/estimates.jsonl" ]] && grep -q 'dry run: nothing written' <<<"$table" \
   && grep -q 'Owner UAT time: not measured' <<<"$table" && grep -q '^PHASE 2 ' <<<"$table" && grep -q 'machine QA (verify+fix)' <<<"$table"; then
  ok es_004 "--dry-run prints the table (build, machine QA, total, owner UAT not measured) and writes nothing"
else
  bad es_004 "--dry-run wrote a record or printed no table"; note "$(head -5 <<<"$table")"
fi
wrote="$(bash "$EST" "$E" --phase 2 2>&1)"
n="$(grep -c . "$E/docs/metrics/estimates.jsonl" 2>/dev/null)"
shape="$(python3 - "$E/docs/metrics/estimates.jsonl" <<'PY'
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1])]
ts = {r["ts"] for r in recs}
tot = [r for r in recs if r["req_id"] is None]
print(len(ts), len(tot), sorted({r["kind"] for r in recs}), sorted(r["cmd"] for r in tot),
      all(r["phase"] == 2 for r in recs), tot[0].get("rows_n"))
PY
)"
if [[ "$n" == "12" && "$shape" == "1 4 ['estimate'] ['build-phase', 'fix-issues', 'triage', 'verify-phase'] True 2" ]] \
   && [[ "$(cksum < "$E/docs/metrics/runs.jsonl")" == "$before" ]] && grep -q 'Written: 12 of 12' <<<"$wrote"; then
  ok es_005 "a real run writes 2 rows x 4 steps + 4 phase totals, one ts, to estimates.jsonl only; runs.jsonl unchanged"
else
  bad es_005 "the records written are not one batch of 9, or runs.jsonl changed"; note "n=$n shape=$shape"
fi

# ---- 3. family fallback ----------------------------------------------------------------------
fam="$(bash "$EST" "$F" --phase 1 --family "$E" --dry-run --json 2>&1)"
fr="$(python3 -c "
import json,sys; d=json.loads(sys.stdin.read()); r={x['req_id']:x for x in d['rows']}
u=r['REQ-UI-201']['build-phase']; g=r['REQ-RAG-201']['build-phase']
print(u['basis'], u['basis_runs'], g['basis'], g['tokens_out'], d['family'])" <<<"$fam" 2>&1)"
if [[ "$fr" == "family 6 none None ['enough']" ]]; then
  ok es_006 "one run of its own: the UI row adds the family's five UI build runs (basis family, 6 runs); a RAG row the family never built has no precedent"
else
  bad es_006 "the family fallback is wrong"; note "$fr"
fi

# ---- 4. no precedent -------------------------------------------------------------------------
np="$(bash "$EST" "$N" --phase 3 2>&1)"
recs="$(python3 - "$N/docs/metrics/estimates.jsonl" <<'PY' 2>&1
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1])]
print(len(recs), {r["basis"] for r in recs}, {str(r["tokens_out"]) for r in recs}, [r.get("rows_no_precedent_n") for r in recs if r["req_id"] is None])
PY
)"
if grep -q '^REQ-UI-301 *no precedent *no precedent *no precedent' <<<"$np" && ! grep -qE '^REQ-UI-301 .*[0-9]+(\.[0-9])?k' <<<"$np" \
   && [[ "$recs" == "12 {'none'} {'None'} [2, 2, 2, 2]" ]]; then
  ok es_007 "no runs and no family: every row prints no precedent, never a number, and its records say basis none"
else
  bad es_007 "a row with no precedent was given a number"; note "$(grep REQ-UI-301 <<<"$np") // $recs"
fi
miss="$(bash "$EST" "$N" --phase 7 2>&1)"; rc=$?
if [[ $rc -eq 2 ]] && grep -q 'phase 7 has no checklist: docs/Fz-P7-Checklist.md' <<<"$miss"; then
  ok es_008 "a phase with no checklist exits 2 and names the file it looked for"
else
  bad es_008 "a missing checklist was not refused (exit $rc)"; note "$miss"
fi

# ---- 5. tf-emit refuses a malformed estimate ---------------------------------------------------
R="$SCRATCH/refuse"; mkdir -p "$R/docs/metrics"
r1="$(printf '%s' '{"kind":"estimate","app":"Fx","phase":1,"req_id":"REQ-UI-001","cmd":"build-phase","tokens_out":{"low":5,"mid":3,"high":9},"duration_s":{"low":1,"mid":2,"high":3},"basis":"repo","basis_runs":4}' | TF_METRICS_ROOT="$R" bash "$EMIT" estimates)"
r2="$(printf '%s' '{"kind":"estimate","app":"Fx","phase":1,"req_id":"REQ-UI-001","cmd":"build-phase","tokens_out":{"low":1,"mid":2,"high":3},"duration_s":{"low":1,"mid":2,"high":3},"basis":"none","basis_runs":1}' | TF_METRICS_ROOT="$R" bash "$EMIT" estimates)"
r3="$(printf '%s' '{"kind":"estimate","app":"Fx","phase":1,"req_id":null,"cmd":"log-miss","tokens_out":null,"duration_s":null,"basis":"none","basis_runs":0}' | TF_METRICS_ROOT="$R" bash "$EMIT" estimates)"
r4="$(printf '%s' '{"kind":"run","app":"Fx","cmd":"build-phase"}' | TF_METRICS_ROOT="$R" bash "$EMIT" estimates)"
if grep -q 'low <= mid <= high' <<<"$r1" && grep -q 'basis none carries no figures' <<<"$r2" && grep -q "cmd must be build-phase, verify-phase, fix-issues or triage" <<<"$r3" \
   && grep -q "kind 'run' is not a record kind of the estimates stream" <<<"$r4" && [[ ! -s "$R/docs/metrics/estimates.jsonl" ]]; then
  ok es_009 "tf-emit refuses low > mid, a figure on basis none, a cmd outside the three, and a run record on the estimates stream"
else
  bad es_009 "tf-emit appended a malformed estimate"; note "$r1 // $r2 // $r3 // $r4"
fi

# ---- 6. the estimating model, from the session pointer ------------------------------------------
P="$SCRATCH/pointer"; mkdir -p "$P/.tfcore/.session" "$P/docs/metrics"
python3 - "$P" <<'PY'
import json, os, sys, datetime
p = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
tr = os.path.join(p, "transcript.jsonl")
with open(tr, "w") as fh:
    for i, (m, o) in enumerate((("claude-fx-small", 10), ("claude-fx-large", 900), ("claude-fx-old", 99999))):
        ts = now - datetime.timedelta(minutes=5 + i) if m != "claude-fx-old" else now - datetime.timedelta(hours=9)
        fh.write(json.dumps({"type": "assistant", "timestamp": ts.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
                             "message": {"model": m, "usage": {"output_tokens": o}}}) + "\n")
json.dump({"transcript_path": tr}, open(os.path.join(p, ".tfcore", ".session", "claude-code.json"), "w"))
PY
cm="$(TF_METRICS_ROOT="$P" bash "$EMIT" --current-model)"
if [[ "$cm" == "claude-fx-large" ]]; then
  ok es_010 "--current-model is the dominant model of the last six hours in the pointer's transcript, not an older one"
else
  bad es_010 "the estimating model was not read from the session pointer"; note "got '$cm'"
fi

# ---- 7. the reconciliation: estimate beside actual ----------------------------------------------
rec="$(bash "$MET" --estimates "$E" --json 2>&1)"
chk="$(python3 -c "
import json,sys; d=json.loads(sys.stdin.read()); p=d['phases'][0]; b=p['cmds']['build-phase']; v=p['cmds']['verify-phase']; f=p['cmds']['fix-issues']
print(p['phase'], p['rows_n'], b['estimate']['tokens_out']['mid'], b['actual']['tokens_out'], b['actual']['runs_n'], v['actual']['tokens_out'], v['actual']['apportioned_n'], f['actual']['tokens_out'])" <<<"$rec" 2>&1)"
# build: one run touching REQ-UI-101 + another row -> 50000 * 1/2 = 25000 over 1 run -> insufficient (n=1)
# verify: 9000 * 2/3 + 3000 + 1500 = 10500 over 3 runs, one apportioned
if [[ "$chk" == "2 2 3200 insufficient data (n=1) 1 10500 1 insufficient data (n=0)" ]]; then
  ok es_011 "--estimates: the estimate's mid beside the actual; a run's share is apportioned; fewer than 3 runs is insufficient data"
else
  bad es_011 "the reconciliation figures are wrong"; note "$chk"
fi
txt="$(bash "$MET" --report "$E" 2>&1)"
if grep -q 'ESTIMATE AGAINST ACTUAL' <<<"$txt" && grep -q 'an estimate never pools with a measurement' <<<"$txt" \
   && ! grep -qiE 'accuracy|ratio' <<<"$(sed -n '/ESTIMATE AGAINST ACTUAL/,$p' <<<"$txt")"; then
  ok es_012 "--report carries the estimates block as two columns, with no ratio or accuracy figure"
else
  bad es_012 "the report has no estimates block, or blends the two"; note "$(sed -n '/ESTIMATE/,+6p' <<<"$txt")"
fi
none_rep="$(bash "$MET" --estimates "$F" 2>&1)"
if grep -q 'no estimates yet' <<<"$none_rep"; then
  ok es_013 "a repo with no estimates says so, and prints no figure"
else
  bad es_013 "a repo with no estimates printed something else"; note "$none_rep"
fi

# ---- 7b. after handoff: triage, estimated and reconciled on its own line, never inside fix-issues ----
tri="$(python3 -c "
import json,sys; d=json.loads(sys.stdin.read()); r={x['req_id']:x for x in d['rows']}
u=r['REQ-UI-101']['triage']; f=r['REQ-FN-101']['triage']
print(u['basis'], u['basis_runs'], u['tokens_out'], f['tokens_out']['mid'], d['phase_columns']['after_handoff']['tokens_out'])" <<<"$out" 2>&1)"
# per-row triage history 600, 900, 1200 (triage-and-fix and triage-issues pooled) -> 750 / 900 / 1050
if [[ "$tri" == "repo 3 {'low': 750, 'mid': 900, 'high': 1050} 900 {'low': 1500, 'mid': 1800, 'high': 2100}" ]]; then
  ok es_015 "after handoff is estimated from triage-and-fix + triage-issues history by prefix, basis repo, its own column"
else
  bad es_015 "the after-handoff estimate is wrong"; note "$tri"
fi
ah="$(python3 -c "
import json,sys; p=json.loads(sys.stdin.read())['phases'][0]; t=p['cmds']['triage']['actual']; f=p['cmds']['fix-issues']['actual']; a=p['parts']['after_handoff']
print(t['tokens_out'], t['runs_n'], t['apportioned_n'], t['rowless_runs_in_repo_n'], f['tokens_out'], f['rowless_runs_in_repo_n'], a['estimate']['tokens_out']['mid'], a['actual']['tokens_out'], sorted(p['parts']))" <<<"$rec" 2>&1)"
# 5000 + 4000 x 1/2 + 3000 = 10000 over 3 runs, one apportioned; the row-less triage run is counted, not shared out
if [[ "$ah" == "10000 3 1 1 insufficient data (n=0) 1 1800 10000 ['after_handoff', 'build', 'machine_qa']" ]] \
   && grep -q 'after handoff' <<<"$txt" && grep -q 'PHASE 2 in three parts' <<<"$txt"; then
  ok es_016 "the reconciliation prints build, machine QA and after handoff as estimate beside actual; triage never reaches fix-issues"
else
  bad es_016 "the after-handoff reconciliation is wrong"; note "$ah"
fi

# ---- 7c. the app's checklist, never the first *-Checklist.md found (TechieBlog, 2026-11-08) -----------------
# TechieBlog keeps Prod-Deploy-Checklist.md beside TechieBlog-Checklist.md; "Prod-Deploy" sorts first and was read
# as the app (the fixture app is Tx so that Prod-Deploy sorts first, as it did there), so every row of phase 1 read "no precedent" even with a family.
two() { local d="$1"; mkrepo "$d" Tx 1 REQ-UI-401; printf '# deploy\n\n## Requirements Status\n\n| ID | x | y |\n|---|---|---|\n| REQ-NFR-900 | a | b |\n' > "$d/docs/Prod-Deploy-Checklist.md"; }
A1="$SCRATCH/two-config"; two "$A1"; mkdir -p "$A1/.tfcore"; printf 'customTechnicalDocuments:\n  brd: docs/Tx-BRD.md\n' > "$A1/.tfcore/core-config.yaml"
A2="$SCRATCH/two-brd"; two "$A2"; : > "$A2/docs/Tx-BRD.md"
A3="$SCRATCH/two-none"; two "$A3"
c1="$(bash "$EST" "$A1" --phase 1 --dry-run --json 2>&1 | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['app'], d['app_from'], [r['req_id'] for r in d['rows']])" 2>&1)"
c2="$(bash "$EST" "$A2" --phase 1 --dry-run --json 2>&1 | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['app'], d['app_from'])" 2>&1)"
c3="$(bash "$EST" "$A3" --phase 1 --dry-run 2>&1)"; r3=$?
c4="$(bash "$EST" "$A3" --phase 1 --app Tx --dry-run --json 2>&1 | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['app'], d['app_from'])" 2>&1)"
if [[ "$c1" == "Tx core-config.yaml ['REQ-UI-401']" && "$c2" == "Tx its BRD" && $r3 -eq 2 && "$c4" == "Tx --app" ]] \
   && grep -q 'cannot tell which checklist is the app.s (Prod-Deploy-Checklist.md, Tx-Checklist.md): pass --app' <<<"$c3"; then
  ok es_017 "a second checklist (Prod-Deploy) is never read as the app: core-config, then the app's own BRD, else --app is asked for"
else
  bad es_017 "the wrong checklist was read as the app's"; note "$c1 // $c2 // exit $r3 $(head -1 <<<"$c3") // $c4"
fi

# ---- 7d. a phase estimated after the fact is labelled, and never replaces the forecast ---------------------
retro="$(python3 - "$E/docs/metrics/estimates.jsonl" <<'PY'
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1])]
print(len(recs), {r.get("basis_note") for r in recs})
PY
)"
fresh="$(bash "$EST" "$F" --phase 1 --family "$E" --dry-run --json 2>&1 | python3 -c "import json,sys; print(json.load(sys.stdin)['retro'])" 2>&1)"
if [[ "$retro" == "12 {'retro'}" && "$fresh" == "False" ]] && grep -q 'ESTIMATED AFTER THE FACT' <<<"$wrote" \
   && grep -q 'estimated after the fact: hindsight, not a forecast' <<<"$(bash "$MET" --estimates "$E")"; then
  ok es_018 "an estimate made when the phase's rows already have runs carries basis_note retro and the reconciliation says so"
else
  bad es_018 "a hindsight estimate was not labelled"; note "$retro // fresh=$fresh"
fi
G="$SCRATCH/forecast"; mkrepo "$G" Fg 2 REQ-UI-501
mkruns "$G" "[('build-phase', ['REQ-UI-001'], 1000, 100), ('build-phase', ['REQ-UI-002'], 2000, 200), ('build-phase', ['REQ-UI-003'], 3000, 300)]"
bash "$EST" "$G" --phase 2 >/dev/null 2>&1; sleep 1
mkruns "$G" "[('build-phase', ['REQ-UI-501'], 9000, 900)]"
bash "$EST" "$G" --phase 2 >/dev/null 2>&1
fc="$(bash "$MET" --estimates "$G" --json | python3 -c "import json,sys; p=json.load(sys.stdin)['phases'][0]; print(p['retro'], p['cmds']['build-phase']['estimate']['tokens_out']['mid'])" 2>&1)"
nb="$(python3 -c "import json,sys; print(len({json.loads(l)['ts'] for l in open(sys.argv[1])}))" "$G/docs/metrics/estimates.jsonl")"
if [[ "$fc" == "False 2000" && "$nb" == "2" ]]; then
  ok es_019 "with a forecast and a later retro estimate of one phase, the reconciliation shows the forecast"
else
  bad es_019 "a later hindsight estimate replaced the forecast"; note "$fc (batches $nb)"
fi

# ---- 8. both routes ship it -----------------------------------------------------------------------
missing=""
for p in .tfcore/telemetry/tf-estimate.sh .tfcore/tasks/estimate-phase.md .claude/commands/TechieFlow/tasks/estimate-phase.md; do
  [[ -f "$ROOT/$p" ]] || missing="$missing $p"
done
cmp -s "$ROOT/.tfcore/tasks/estimate-phase.md" "$ROOT/.claude/commands/TechieFlow/tasks/estimate-phase.md" || missing="$missing (mirror differs)"
grep -q '"techieflow:tasks:estimate-phase"' "$ROOT/opencode.jsonc" || missing="$missing opencode.jsonc"
grep -q 'estimate-phase.md' "$ROOT/.tfcore/agents/flow-master.md" || missing="$missing flow-master"
grep -q 'estimate-phase' "$ROOT/.tfcore/tasks/build-phase.md" || missing="$missing build-phase.md"
grep -q 'tf-metrics.sh --estimates' "$ROOT/.tfcore/tasks/handoff-phase.md" || missing="$missing handoff-phase.md"
grep -q 'tf-metrics.sh --estimates' "$ROOT/.tfcore/tasks/triage-and-fix.md" || missing="$missing triage-and-fix.md"
if [[ -z "$missing" ]]; then
  ok es_014 "the task is registered for both harnesses, named in build-phase.md and printed by handoff-phase.md"
else
  bad es_014 "the task is not registered everywhere:$missing"
fi

if [[ $fail -eq 0 ]]; then echo "estimate: every case passed"; else echo "estimate: FAILED"; fi
exit $fail

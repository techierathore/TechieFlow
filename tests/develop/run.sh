#!/usr/bin/env bash
# tests/develop/run.sh — *develop-end-to-end on an app that already exists (owner's option A, 2026-11-19).
#
#   bash tests/develop/run.sh            # all
#   bash tests/develop/run.sh dev_nogit  # one
#
# A stand-in goal runner plays the agent (as dev_001 in tests/regression does): it writes a run record
# per step and logs which goal it was given, so a case sees which steps ran, in which order, with which
# appPhase. Each case fails on the tf-develop.sh of 4659972 and passes now. prove.sh in this folder is
# the long, paid run on a real harness; this file is the cheap check. Exit 0 all held, 1 a case failed.
set -u
unset CLAUDE_PROJECT_DIR TF_METRICS_ROOT TF_PROJECT_DIR TF_YOLO
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UTILS="${TF_REGRESSION_UTILS:-$ROOT/.tfcore/utils}"
SCRATCH="$ROOT/tests/.artifacts/develop.$$"
mkdir -p "$SCRATCH"
trap '[[ -n "${TF_KEEP:-}" ]] || rm -rf "$SCRATCH"' EXIT
fail=0; only="${1:-}"
ok()   { printf 'ok   %s — %s\n' "$1" "$2"; }
bad()  { printf 'FAIL %s — %s\n' "$1" "$2"; fail=1; }
_g() { GIT_CEILING_DIRECTORIES="$SCRATCH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
       GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com "$@"; }

FAKE="$SCRATCH/fake-goal.sh"
cat > "$FAKE" <<'SH'
#!/usr/bin/env bash
# stand-in for tf-goal.sh: the last argument is the goal, the one before it the app dir
dir="${@: -2:1}"; goal="${@: -1}"
case "$goal" in *--stage2*) p=day1-2 ;; *day1-greenfield*) p=day1 ;; *build-phase*) p=build ;; *handoff-phase*) p=handoff ;; *) p=other ;; esac
grep -q "develop mode" <<<"$goal" || exit 9
n="$(sed -n 's/.*for phase \([0-9]*\) of .*/\1/p' <<<"$goal")"; [[ -n "$n" ]] && p="$p-p$n"
ap="$(sed -n 's/^appPhase: *//p' "$dir/.tfcore/core-config.yaml" 2>/dev/null)"
only="$(sed -n 's/.*write only these, \([^,]*\), and keep.*/\1/p' <<<"$goal")"
echo "$p appPhase=${ap:-none}${only:+ only=$only}" >> "$dir/goals.log"
[[ -n "${TF_FAKE_BLOCK:-}" && "$p" == "$TF_FAKE_BLOCK" ]] && exit 3
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"kind":"run","app":"Fx","cmd":"%s","started":"%s","ended":"%s","duration_s":60,"tokens_in":10,"tokens_out":1000,"model":"m1"}\n' "$p" "$now" "$now" >> "$dir/docs/metrics/runs.jsonl"
sleep 1
SH
chmod +x "$FAKE"

# an app folder: the framework's scripts, the config, and the documents named (each file a stub)
app() {   # <dir> <doc>...
  local d="$1"; shift
  mkdir -p "$d/.tfcore/utils" "$d/docs/metrics" "$d/docs/mockups"
  cp "$UTILS/tf-develop.sh" "$UTILS/tf-day1-files.sh" "$UTILS/tf-day1-files.py" "$d/.tfcore/utils/"
  cp "$UTILS/tf-develop-plan.py" "$d/.tfcore/utils/" 2>/dev/null
  printf 'appSize: S\nappKind: app\n' > "$d/.tfcore/core-config.yaml"
  printf '.tfcore/.session/\ngoals.log\n' > "$d/.gitignore"
  local f; for f in "$@"; do printf '# %s\n' "$f" > "$d/$f"; done
}
STAGE1="docs/Fx-BRD.md docs/Fx-Architecture.md docs/Fx-UIDesign.md docs/mockups/home.html"
STAGE2="docs/Fx-Checklist.md docs/Fx-Coding-Standards.md docs/Fx-UsageGuide.md"
phases() {   # <dir> <status of phase 1> <status of phase 2>
  printf '# Fx — Phases\n\n## Phases\n\n| Phase | Name | Screens | BRD range | Status |\n|---|---|---|---|---|\n| 1 | Core | Home | BRD-1 to BRD-9 | %s |\n| 2 | More | Reports | BRD-10 to BRD-19 | %s |\n' "$2" "$3" > "$1/docs/Fx-Phases.md"
  printf '# x\n' > "$1/docs/Fx-P2-BRD.md"; printf '# x\n' > "$1/docs/Fx-P2-UIDesign.md"; printf '# x\n' > "$1/docs/Fx-P2-Checklist.md"
  printf 'appSize: L\nappKind: app\n' > "$1/.tfcore/core-config.yaml"
}
dev() { (cd "$1" && shift && _g env TF_DEVELOP_GOAL_SH="$FAKE" bash .tfcore/utils/tf-develop.sh . "$@" 2>&1); }
repo() { _g git -C "$1" init -q -b main && _g git -C "$1" add -A && _g git -C "$1" commit -q -m seed; }   # a repository of its own, no remote
printf 'A to-do app.\n' > "$SCRATCH/brief.md"
rep() { python3 -c "
import json, sys; r = json.load(open(sys.argv[1]))
print(r['status'], ','.join(p['phase'] + ':' + p['status'] for p in r['phases']))" "$1/docs/metrics/develop-report.json" 2>&1; }

# --- (1) an app whose documents are all written: Day 1 is skipped, no brief needed ----------------
dev_existing() {
  local d="$SCRATCH/existing" out rc
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2; repo "$d"
  out="$(dev "$d" --app Fx --no-push)"; rc=$?
  [[ $rc -eq 0 && "$(tr '\n' ' ' < "$d/goals.log" 2>/dev/null)" == "build appPhase=none handoff appPhase=none " ]] \
    && [[ "$(rep "$d")" == "uat-ready day1:skipped,day1-2:skipped,build:done,handoff:done" ]] && grep -q 'Ready for UAT' "$d/docs/Fx-Build-Report.md" \
    && ok dev_existing "an app whose documents are written runs with no brief: both Day-1 stages are skipped and shown so, the build and the handoff run, UAT-ready" \
    || bad dev_existing "rc=$rc; goals run: $(tr '\n' ';' < "$d/goals.log" 2>/dev/null); report: $(rep "$d"); $(tail -1 <<<"$out")"
  # only part of stage 1 written: day 1 runs for the missing document alone, and stage 2 runs whole
  d="$SCRATCH/partial"
  # shellcheck disable=SC2086
  app "$d" docs/Fx-BRD.md docs/Fx-UIDesign.md docs/mockups/home.html; repo "$d"
  out="$(dev "$d" --app Fx --brief "$SCRATCH/brief.md" --no-push)"; rc=$?
  [[ $rc -eq 0 && "$(head -2 "$d/goals.log" 2>/dev/null | tr '\n' ' ')" == "day1 appPhase=none only=docs/Fx-Architecture.md day1-2 appPhase=none " ]] \
    && ok dev_partial "with the Architecture alone missing, Day 1 runs for that document only and keeps the others; stage 2 runs whole" \
    || bad dev_partial "rc=$rc; goals run: $(tr '\n' ';' < "$d/goals.log" 2>/dev/null); $(tail -1 <<<"$out")"
  # no documents and no brief: refused, naming what is missing
  d="$SCRATCH/nothing"; app "$d"
  out="$(dev "$d" --app Fx)"; rc=$?
  [[ $rc -eq 2 ]] && grep -q 'brief' <<<"$out" && [[ ! -e "$d/goals.log" ]] \
    && ok dev_nobrief "a folder with no BRD and no brief is refused before anything runs" \
    || bad dev_nobrief "rc=$rc: $out"
}

# --- (2) a Large app: every phase of the Phases table, in order, each with its appPhase ---------
dev_phases() {
  local d="$SCRATCH/large" out rc want
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2; phases "$d" planned planned; repo "$d"
  out="$(dev "$d" --app Fx --brief "$SCRATCH/brief.md" --no-push)"; rc=$?
  want="build-p1 appPhase=1 handoff-p1 appPhase=1 build-p2 appPhase=2 handoff-p2 appPhase=2 "
  [[ $rc -eq 0 && "$(tr '\n' ' ' < "$d/goals.log" 2>/dev/null)" == "$want" ]] \
    && [[ "$(rep "$d")" == "uat-ready day1:skipped,day1-2:skipped,build-p1:done,handoff-p1:done,build-p2:done,handoff-p2:done" ]] \
    && grep -q 'Phase 2: handoff' "$d/docs/Fx-Build-Report.md" \
    && ok dev_phases "a two-phase Large app builds, verifies and hands off phase 1, then phase 2, appPhase set before each build; one report row per step" \
    || bad dev_phases "rc=$rc; goals run: $(tr '\n' ';' < "$d/goals.log" 2>/dev/null); report: $(rep "$d"); $(tail -1 <<<"$out")"
  # phase 1 done in the table: only phase 2 runs; a block in phase 2 stops the run, --resume finishes it
  d="$SCRATCH/large2"
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2; phases "$d" done planned; repo "$d"
  out="$(TF_FAKE_BLOCK=build-p2 dev "$d" --app Fx --brief "$SCRATCH/brief.md" --no-push)"; rc=$?
  local r1; r1="$(rep "$d")"
  out="$(dev "$d" --resume)"
  [[ $rc -eq 3 && "$r1" == "blocked day1:skipped,day1-2:skipped,build-p1:skipped,handoff-p1:skipped,build-p2:blocked" ]] \
    && [[ "$(tr '\n' ' ' < "$d/goals.log")" == "build-p2 appPhase=2 build-p2 appPhase=2 handoff-p2 appPhase=2 " && "$(rep "$d")" == uat-ready* ]] \
    && ok dev_phases_done "a phase the table marks done is skipped; a block in phase 2 stops the run and --resume finishes phase 2 alone" \
    || bad dev_phases_done "rc=$rc; first report: $r1; goals: $(tr '\n' ';' < "$d/goals.log" 2>/dev/null); last: $(rep "$d")"
}

# --- (3) --no-git: no commit, no push, no repository needed; every step still recorded ----------
dev_nogit() {
  local d="$SCRATCH/gitapp" remote="$SCRATCH/remote.git" out rc h0 h1 r0 r1
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2
  _g git init -q --bare "$remote"; _g git -C "$d" init -q -b main; _g git -C "$d" remote add origin "$remote"
  _g git -C "$d" add -A && _g git -C "$d" commit -q -m seed && _g git -C "$d" push -q -u origin main
  h0="$(_g git -C "$d" rev-parse HEAD)"; r0="$(_g git -C "$remote" rev-parse HEAD)"
  out="$(dev "$d" --app Fx --no-git)"; rc=$?
  h1="$(_g git -C "$d" rev-parse HEAD)"; r1="$(_g git -C "$remote" rev-parse HEAD)"
  [[ $rc -eq 0 && "$h0" == "$h1" && "$r0" == "$r1" && -n "$(_g git -C "$d" status --porcelain)" ]] \
    && grep -q 'left to the owner' "$d/docs/Fx-Build-Report.md" && [[ "$(rep "$d")" == uat-ready* ]] \
    && ok dev_nogit "--no-git in a repository with a remote: the run completes, no commit is made and nothing is pushed, the work is left uncommitted for the owner" \
    || bad dev_nogit "rc=$rc; HEAD $h0 → $h1; remote $r0 → $r1; $(tail -1 <<<"$out")"
  # a folder that is no repository at all: runs, and creates none
  d="$SCRATCH/norepo"
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2
  out="$(dev "$d" --app Fx --no-git)"; rc=$?
  [[ $rc -eq 0 && ! -e "$d/.git" && -f "$d/.tfcore/.session/develop-done.json" ]] && grep -q '"git": false' "$d/.tfcore/.session/develop-done.json" \
    && ok dev_nogit_b "--no-git in a folder that is no repository: it runs, records each step, and makes no repository" \
    || bad dev_nogit_b "rc=$rc; $(tail -1 <<<"$out")"
}

# --- (4) the dry run prints the plan and writes nothing ------------------------------------------
dev_dry() {
  local d="$SCRATCH/dry" out rc
  # shellcheck disable=SC2086
  app "$d" $STAGE1 $STAGE2; phases "$d" planned planned; repo "$d"
  out="$(dev "$d" --app Fx --brief "$SCRATCH/brief.md" --no-push --dry-run)"; rc=$?
  local order; order="$(grep -oE '^(day1|day1-2|build-p[0-9]|handoff-p[0-9]): (skip|run)' <<<"$out" | tr '\n' ' ')"
  [[ $rc -eq 0 && "$order" == "day1: skip day1-2: skip build-p1: run handoff-p1: run build-p2: run handoff-p2: run " ]] \
    && grep -q 'build-p2: set appPhase 2' <<<"$out" && grep -q 'then commit, no push' <<<"$out" \
    && dev "$d" --app Fx --no-git --dry-run | grep -q 'handoff-p2: then no commit and no push' \
    && [[ ! -e "$d/.tfcore/.session/develop.json" && ! -e "$d/goals.log" && "$(sed -n 's/^appSize: //p' "$d/.tfcore/core-config.yaml")" == L ]] \
    && ! grep -q appPhase "$d/.tfcore/core-config.yaml" \
    && ok dev_dry "the dry run prints the skipped Day-1 stages, then each phase's build and handoff in order with its appPhase and the git line, and writes nothing" \
    || bad dev_dry "rc=$rc; order: $order; $(head -3 <<<"$out" | tr '\n' ' ')"
}

# AppManager's shape (its own documents, read in a scratch copy on 19 Nov): the guide is docs/AppManager-Usage-Guide.md,
# and phase 1 is done with no UIDesign of its own. Neither is "missing": the plan wrote both until then.
dev_names() {
  local d="$SCRATCH/names" out
  app "$d" docs/Fx-BRD.md docs/Fx-Architecture.md docs/mockups/home.html docs/Fx-Checklist.md docs/Fx-Coding-Standards.md docs/Fx-Usage-Guide.md
  phases "$d" done planned
  out="$(dev "$d" --app Fx --no-git --dry-run)"
  grep -q '^day1: skip' <<<"$out" && grep -q '^day1-2: skip' <<<"$out" && grep -q '^build-p1: skip' <<<"$out" && grep -q '^build-p2: run' <<<"$out" \
    && ok dev_names "a guide named Usage-Guide and a done phase with no UIDesign are not written again; the open phase still runs" \
    || bad dev_names "$(grep -E '^(day1|day1-2|build-p[12]):' <<<"$out" | tr '\n' ' ' | cut -c1-300)"
}

echo "# tests/develop — *develop-end-to-end on an existing app"
for t in dev_existing dev_phases dev_nogit dev_dry dev_names; do
  [[ -n "$only" && "$only" != "$t" ]] && continue
  "$t"
done
[[ $fail -eq 0 ]] && echo "# all develop cases hold" || echo "# develop cases FAILED"
exit $fail

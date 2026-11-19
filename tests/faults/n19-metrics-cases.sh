# tests/faults/n19-metrics-cases.sh — sourced by tests/faults/run.sh; the owner's two metrics faults of 19 Nov 2026.
# Each case fails on the scripts of 18 Nov (the working tree on top of 4659972) and passes now, with a control half.

# --- one reply counted once per content block: 772,297 output tokens in three minutes --------------------------------
# Claude Code writes one transcript line per content block of a reply (thinking, text, each tool call), and every line
# repeats the whole reply's usage. tf-emit.sh's window and the SessionEnd hook added every line, so a reply with many
# tool calls was counted once per call: TechieBlog's estimate-phase of 2026-11-16 13:25 had one reply of 46 blocks and
# recorded 772,297 output tokens for 20,193. A reply now counts once, by its message id. Controls: two different
# replies with the same figures both count; a reply outside the window does not; a subagent's reply is its own.
tokens_once() {
  local d="$SCRATCH/tokens_once" tr rec ses
  mkdir -p "$d/docs/metrics" "$d/.tfcore/.session" "$d/t/s1/subagents"
  for f in runs gates sessions commits misses estimates; do : > "$d/docs/metrics/$f.jsonl"; done
  ln -s "$UTILS" "$d/.tfcore/utils"
  tr="$d/t/s1.jsonl"
  python3 - "$tr" "$d/t/s1/subagents/agent-a.jsonl" <<'PY'
import json, sys
main, sub = sys.argv[1], sys.argv[2]
def line(ts, mid, out, cr, block):
    return json.dumps({"type": "assistant", "timestamp": "2026-11-16T13:%s.000Z" % ts, "uuid": "%s-%s" % (mid, block),
                       "message": {"id": mid, "model": "claude-fx", "content": [{"type": block}],
                                   "usage": {"input_tokens": 1, "output_tokens": out, "cache_read_input_tokens": cr,
                                             "cache_creation_input_tokens": 0}}}) + "\n"
with open(main, "w") as fh:
    for b in ("thinking", "text", "tool_use", "tool_use"):          # one reply, four lines: 1000 once
        fh.write(line("26:01", "msg_A", 1000, 5000, b))
    fh.write(line("27:00", "msg_B", 200, 100, "text"))              # two replies with the same figures: both count
    fh.write(line("27:30", "msg_C", 200, 100, "text"))
    fh.write(line("40:00", "msg_D", 9000, 9000, "text"))            # outside the window
with open(sub, "w") as fh:
    for b in ("text", "tool_use"):                                    # a subagent reply of two lines: 300 once
        fh.write(line("28:00", "msg_S", 300, 0, b))
PY
  printf '{"session_id":"s1","transcript_path":"%s"}\n' "$tr" > "$d/.tfcore/.session/claude-code.json"
  printf '%s' '{"kind":"run","cmd":"estimate-phase","started":"2026-11-16T13:25:00Z","ended":"2026-11-16T13:30:00Z","reqs_touched":[],"reqs_count":0,"app":"Fx"}' \
    | TF_METRICS_ROOT="$d" TF_HARNESS=claude-code bash "$UTILS/tf-emit.sh" runs >/dev/null 2>&1
  rec="$(python3 -c "import json,sys; r=json.loads(open(sys.argv[1]).readline()); print(r.get('tokens_out'), r.get('tokens_out_subagents'), r.get('tokens_cache_read'), r.get('tokens_scope'))" "$d/docs/metrics/runs.jsonl" 2>&1)"
  [[ "$rec" == "1700 300 5200 tree" ]] \
    && ok tokens_once_a "a run's window counts each reply once, by message id: 1000 + 200 + 200 + a subagent's 300, not each content block" \
    || bad tokens_once_a "the run's window counted a reply once per content block (want 1700 300 5200 tree): $rec"
  printf '{"session_id":"s1","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionEnd"}' "$tr" "$d" \
    | bash "$HOOKS/metrics-session.sh" >/dev/null 2>&1
  ses="$(python3 -c "import json,sys; r=json.loads(open(sys.argv[1]).readline()); print(r.get('output_tokens'), r.get('cache_read_tokens'))" "$d/docs/metrics/sessions.jsonl" 2>&1)"
  [[ "$ses" == "10400 14200" ]] \
    && ok tokens_once_b "the session record counts each reply of the main transcript once (four replies: 1000 + 200 + 200 + 9000)" \
    || bad tokens_once_b "the session record counted a reply once per content block (want 10400 14200): $ses"
}

# --- the estimate charged every row one verify pass and one fix pass ----------------------------------------------
# tf-estimate.sh priced a row at one pass of the median earlier run (a run's tokens over its rows). A phase is
# re-verified many times and has few rows fixed, so on 28 built phases of ten repos the estimate put verify at 0.15
# and fix at 4.5 times what was spent (TechieBlog phase 1: 39 times too low, 6 times too high). The unit of history
# is now a finished phase: what each step spent per row of it. Here four built phases, each of 4 UI rows, built once
# (4000), verified five times (5 x 2000) and with one row fixed (8000): verify 2500 a row, fix 2000 a row. Control:
# build, one pass a row, gives the same 1000 a row either way; a phase never built is no history.
estimate_phases() {
  local d="$SCRATCH/estimate_phases" ph i r out
  mkdir -p "$d/docs/metrics"
  for ph in 1 2 3 4 5 6; do
    f="$d/docs/Fx-P$ph-Checklist.md"; [[ $ph == 1 ]] && f="$d/docs/Fx-Checklist.md"
    { printf '# Fx — Checklist\n\n## Requirements Status\n\n| ID | Requirement | Status |\n|----|----|----|\n'
      for i in 1 2 3 4; do printf '| REQ-UI-%d0%d | r | Verified |\n' "$ph" "$i"; done; } > "$f"
  done
  python3 - "$d/docs/metrics/runs.jsonl" <<'PY'
import json, sys, datetime
t = datetime.datetime(2026, 10, 1, 8, 0, 0)
def run(cmd, reqs, tok, sec):
    global t
    s, t = t, t + datetime.timedelta(seconds=sec)
    r = {"v": 1, "kind": "run", "app": "Fx", "cmd": cmd, "started": s.strftime("%Y-%m-%dT%H:%M:%SZ"),
         "ended": t.strftime("%Y-%m-%dT%H:%M:%SZ"), "reqs_touched": reqs, "reqs_count": len(reqs),
         "tokens_out": tok, "tokens_scope": "tree"}
    t += datetime.timedelta(seconds=60)
    return json.dumps(r) + "\n"
with open(sys.argv[1], "w") as fh:
    for ph in (1, 2, 3, 4):                      # phase 5 is the one estimated; phase 6 was never built
        rows = ["REQ-UI-%d0%d" % (ph, i) for i in (1, 2, 3, 4)]
        fh.write(run("build-phase", rows, 4000, 400))
        for _ in range(5):
            fh.write(run("verify-phase", rows, 2000, 200))
        fh.write(run("fix-issues", rows[:1], 8000, 800))
    fh.write(run("verify-phase", ["REQ-UI-601"], 99999, 999))  # a phase never built: none of its runs is history
PY
  out="$(bash "$UTILS/../telemetry/tf-estimate.sh" "$d" --phase 5 --app Fx --dry-run --json 2>&1 \
    | python3 -c "import json,sys; t=json.load(sys.stdin)['totals']; print(*[t[c]['tokens_out'] and t[c]['tokens_out']['mid'] for c in ('build-phase','verify-phase','fix-issues')])" 2>&1)"
  r=($out)
  [[ "${r[1]:-}" == "10000" && "${r[2]:-}" == "8000" ]] \
    && ok estimate_phases_a "a phase verified five times and with one row of four fixed is estimated as spent: verify 10000, fix 8000" \
    || bad estimate_phases_a "the estimate charged one verify and one fix pass a row (want verify 10000, fix 8000; got verify ${r[1]:-?}, fix ${r[2]:-?}): $out"
  [[ "${r[0]:-}" == "4000" ]] \
    && ok estimate_phases_b "build, one pass a row, is 4000 for 4 rows either way; the phase never built adds nothing" \
    || bad estimate_phases_b "the build estimate moved (want 4000): $out"
}

#!/usr/bin/env bash
# tf-goal.sh — unattended GOAL runner / supervisor for TechieFlow (rule: .tfcore/tasks/_yolo-mode.md)
#
# Runs a goal headless in YOLO mode and keeps it running until the agent itself
# declares the goal done — surviving the subscription 5-hour / weekly usage
# limits (sleeps until the stated reset + a buffer, then RESUMES THE SAME
# SESSION), crashes, and "I stopped early to ask you something" turns.
#
#   bash .tfcore/utils/tf-goal.sh [options] <app-dir> "<goal text>"
#   bash .tfcore/utils/tf-goal.sh [options] <app-dir> @goal.md
#
# Options
#   --harness claude|opencode   default: claude
#   --model <id>                claude: --model <id>; opencode: -m <provider/model>
#   --buffer-min <n>            minutes added after a stated limit-reset time (default 15)
#   --probe-min <n>             limit hit but NO reset time parseable → fire a one-turn probe every n
#                               minutes until the API answers again, then resume (default 15)
#   --probe-max-hours <n>       give up probing and resume anyway after n hours (default 8)
#   --default-wait-min <n>      (legacy) only used to stamp resume_at in goal.json when probing
#   --max-cycles <n>            give up after n launches (default 60)
#   --idle-retry-sec <n>        pause before re-prompting an agent that stopped without finishing (default 30)
#   --resume                    continue the last goal run recorded in .tfcore/.session/goal.json
#   --dry-run                   print the commands, run nothing
#
# Exit codes: 0 goal complete · 3 agent declared the goal BLOCKED (owner input
# needed) · 4 max cycles reached · 2 usage error.
#
# Files (all under <app-dir>/.tfcore/.session/, never committed):
#   yolo.json        YOLO flag (tf-yolo.sh on --source goal) — the hook reads it
#   goal.json        supervisor state: cycle, session_id, last_reason, resume_at
#   goal.log         everything the harness printed, all cycles, timestamped
#   goal-done.json   the agent's completion sentinel (tf-yolo.sh done [complete|blocked])
#
# How the agent is told to finish: the prompt preamble (below) instructs it to run
# `bash .tfcore/utils/tf-yolo.sh done complete "<summary>"` when the goal is met,
# or `... done blocked "<why>"` when only the owner can unblock it. A cycle that
# ends with neither sentinel is classified from its output: USAGE LIMIT → sleep
# until reset+buffer; CRASH/API error → exponential backoff (2m → 30m);
# otherwise the agent simply stopped (asked a question / summarised) → re-prompt.
#
# Harness invocation (verified flags — docs/Capability-Matrix.md):
#   claude   -p "<prompt>" --permission-mode bypassPermissions --output-format stream-json --verbose
#            resume: claude -p --resume <session_id> "<continue>"   (fallback: --continue)
#   opencode run --auto "<prompt>"      resume: opencode run --auto -c "<continue>"
#   Override either command line with TF_GOAL_CLAUDE_FLAGS / TF_GOAL_OPENCODE_FLAGS.

set -u

HARNESS="claude"; MODEL=""; BUFFER_MIN=15; DEFAULT_WAIT_MIN=60; MAX_CYCLES=60; IDLE_RETRY=30
PROBE_MIN=15; PROBE_MAX_H=8
RESUME=0; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --harness) HARNESS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --buffer-min) BUFFER_MIN="$2"; shift 2 ;;
    --default-wait-min) DEFAULT_WAIT_MIN="$2"; shift 2 ;;
    --probe-min) PROBE_MIN="$2"; shift 2 ;;
    --probe-max-hours) PROBE_MAX_H="$2"; shift 2 ;;
    --max-cycles) MAX_CYCLES="$2"; shift 2 ;;
    --idle-retry-sec) IDLE_RETRY="$2"; shift 2 ;;
    --resume) RESUME=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    --) shift; break ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
APP_DIR="${1:-}"; GOAL_ARG="${2:-}"
if [[ -z "$APP_DIR" || ( -z "$GOAL_ARG" && $RESUME -eq 0 ) ]]; then
  echo "usage: tf-goal.sh [options] <app-dir> \"<goal>\" | @goal.md   (or --resume <app-dir>)" >&2; exit 2
fi
APP_DIR="$(cd "$APP_DIR" 2>/dev/null && pwd)" || { echo "no such dir: $1" >&2; exit 2; }
[[ -d "$APP_DIR/.tfcore" ]] || { echo "$APP_DIR has no .tfcore/ — scaffold it first" >&2; exit 2; }
case "$HARNESS" in claude|opencode) ;; *) echo "--harness must be claude|opencode" >&2; exit 2 ;; esac
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }

STATE_DIR="$APP_DIR/.tfcore/.session"; mkdir -p "$STATE_DIR"
STATE="$STATE_DIR/goal.json"; LOG="$STATE_DIR/goal.log"; DONE="$STATE_DIR/goal-done.json"
YOLO_SH="$APP_DIR/.tfcore/utils/tf-yolo.sh"

if [[ "$GOAL_ARG" == @* ]]; then
  GOAL_FILE="${GOAL_ARG#@}"; [[ -f "$GOAL_FILE" ]] || { echo "goal file not found: $GOAL_FILE" >&2; exit 2; }
  GOAL="$(cat "$GOAL_FILE")"
else
  GOAL="$GOAL_ARG"
fi

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '[%s] tf-goal: %s\n' "$(ts)" "$*" | tee -a "$LOG" >&2; }

state_get() { python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2],""))
except Exception: print("")' "$STATE" "$1" 2>/dev/null; }
state_set() { # key value [key value ...]
  python3 - "$STATE" "$@" <<'PY' 2>/dev/null
import json, sys
p = sys.argv[1]; kv = sys.argv[2:]
try: d = json.load(open(p))
except Exception: d = {}
for k, v in zip(kv[::2], kv[1::2]):
    d[k] = int(v) if v.isdigit() else v
json.dump(d, open(p, "w"), indent=1)
PY
}

if [[ $RESUME -eq 1 ]]; then
  [[ -f "$STATE" ]] || { echo "--resume: no $STATE" >&2; exit 2; }
  [[ -z "$GOAL" ]] && GOAL="$(state_get goal)"
  HARNESS="$(state_get harness)"; HARNESS="${HARNESS:-claude}"
  CYCLE="$(state_get cycle)"; CYCLE="${CYCLE:-0}"
  SESSION_ID="$(state_get session_id)"
  log "resuming goal (cycle $CYCLE, session ${SESSION_ID:-none})"
else
  CYCLE=0; SESSION_ID=""
  state_set goal "$GOAL" harness "$HARNESS" cycle 0 session_id "" started "$(ts)" last_reason "start"
  rm -f "$DONE"
fi

# ---------------------------------------------------------------- prompts
read -r -d '' PREAMBLE <<'TXT'
UNATTENDED GOAL RUN — YOLO MODE IS ON (TechieFlow rule .tfcore/tasks/_yolo-mode.md; read it first).
- Nobody is watching. NEVER ask a question, NEVER pause for confirmation, NEVER end your turn with a plan, options, or "shall I…". Decide the sensible default yourself and record the decision in the checklist Remarks.
- Permissions: deletes and read-only git (status/log/diff/blame) are allowed; git WRITES (commit/push/add/reset/checkout/stash/tag) are blocked in every mode — never attempt them; the owner commits.
- Re-entry: start from PROJECT-STATUS.md + docs/*-Checklist.md (Requirements Status table) — continue from the weakest open REQ; do not redo terminal rows.
- A build pass means the WHOLE checklist: every open REQ reaches at least `Implemented` in this pass, then the verifier is chained inline, then FIX mode loops on FAIL rows until they pass. Never stop with "run build-phase again for the remaining REQs".
- When the goal is met (every in-scope REQ terminal, PROJECT-STATUS.md + .html updated, run record emitted): run
      bash .tfcore/utils/tf-yolo.sh done complete "<one-line summary>"
  If, and only if, something ONLY THE OWNER can resolve blocks every remaining REQ (credentials, a physical device, a paid account, a product decision you must not make): finish everything else, write the blocker into PROJECT-STATUS "Known blockers", then run
      bash .tfcore/utils/tf-yolo.sh done blocked "<what the owner must do>"
  Do not run either command before that point — the supervisor stops the moment you do.
TXT

CONTINUE_PROMPT="Continue the UNATTENDED GOAL RUN (YOLO ON). The previous turn ended without the goal-done sentinel — pick up from PROJECT-STATUS.md + the checklist Requirements Status table and keep going. Do not summarise, do not ask; work until the goal is met, then run: bash .tfcore/utils/tf-yolo.sh done complete \"<summary>\". The goal, again:
$GOAL"

FIRST_PROMPT="$PREAMBLE

THE GOAL:
$GOAL"

# ---------------------------------------------------------------- harness command
harness_cmd() { # $1 = first|resume ; prints the argv via NUL-separated echo
  local kind="$1" prompt
  if [[ "$kind" == first ]]; then prompt="$FIRST_PROMPT"; else prompt="$CONTINUE_PROMPT"; fi
  if [[ "$HARNESS" == claude ]]; then
    CMD=(claude -p --permission-mode bypassPermissions --output-format stream-json --verbose)
    [[ -n "$MODEL" ]] && CMD+=(--model "$MODEL")
    # shellcheck disable=SC2206
    [[ -n "${TF_GOAL_CLAUDE_FLAGS:-}" ]] && CMD+=($TF_GOAL_CLAUDE_FLAGS)
    if [[ "$kind" == resume ]]; then
      if [[ -n "$SESSION_ID" ]]; then CMD+=(--resume "$SESSION_ID"); else CMD+=(--continue); fi
    fi
    CMD+=("$prompt")
  else
    CMD=(opencode run --auto)
    [[ -n "$MODEL" ]] && CMD+=(-m "$MODEL")
    # shellcheck disable=SC2206
    [[ -n "${TF_GOAL_OPENCODE_FLAGS:-}" ]] && CMD+=($TF_GOAL_OPENCODE_FLAGS)
    if [[ "$kind" == resume ]]; then
      if [[ -n "$SESSION_ID" ]]; then CMD+=(-s "$SESSION_ID"); else CMD+=(-c); fi
    fi
    CMD+=("$prompt")
  fi
}

# ---------------------------------------------------------------- classification
# Reads the cycle's output file; prints one line: KIND<TAB>detail
#   LIMIT <epoch-to-resume>   CRASH <text>   IDLE <text>
classify_output() {
  TF_OUT="$1" TF_BUFFER_MIN="$BUFFER_MIN" TF_DEFAULT_WAIT_MIN="$DEFAULT_WAIT_MIN" TF_RC="$2" python3 - <<'PY'
import os, re, sys, json, time, datetime, calendar
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

path = os.environ["TF_OUT"]; buffer_min = int(os.environ["TF_BUFFER_MIN"]); default_wait = int(os.environ["TF_DEFAULT_WAIT_MIN"])
rc = int(os.environ.get("TF_RC") or 0)
try:
    text = open(path, errors="replace").read()
except Exception:
    text = ""
tail = text[-20000:]
now = time.time()

def out(kind, detail):
    print(f"{kind}\t{detail}"); sys.exit(0)

# ---- 1. usage limit?
LIMIT_PAT = re.compile(
    r"(usage limit|hit your limit|exceeded your .*limit|you've hit your (5-hour|weekly|usage) limit|rate[ _-]?limit(ed)?|"
    r"limit (has been )?(reached|exceeded)|too many requests|\b429\b|overloaded_error|quota exceeded|"
    r"out of extra usage|resets? (at|in)\b|weekly limit|session limit)", re.I)
m = LIMIT_PAT.search(tail)
if m:
    resume_at = None
    # a) legacy "Claude AI usage limit reached|<epoch>"
    e = re.search(r"limit reached\|(\d{10})", tail)
    if e:
        resume_at = int(e.group(1))
    # b) ISO timestamp near the match
    if resume_at is None:
        iso = re.search(r"(20\d\d-\d\d-\d\dT\d\d:\d\d(?::\d\d)?(?:\.\d+)?(?:Z|[+-]\d\d:?\d\d)?)", tail[m.start()-200:m.end()+300])
        if iso:
            s = iso.group(1).replace("Z", "+00:00")
            try:
                resume_at = datetime.datetime.fromisoformat(s).timestamp()
            except Exception:
                pass
    # c) "resets in 2h 14m" / "resets in 45 minutes" / "retry after 120"
    if resume_at is None:
        r = re.search(r"(?:resets?|try again|retry)\s+(?:in|after)[:\s]+(?:(\d+)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*m(?:in(?:utes?)?)?)?\s*(?:(\d+)\s*s(?:ec(?:onds?)?)?)?", tail, re.I)
        if r and any(r.groups()):
            h, mi, s = (int(x) if x else 0 for x in r.groups())
            resume_at = now + h*3600 + mi*60 + s
        else:
            r = re.search(r"retry[- ]after[:=\s]+(\d+)", tail, re.I)
            if r:
                resume_at = now + int(r.group(1))
    # d) "resets 3pm (Asia/Kolkata)" / "resets at 14:30" / "resets Tue 3pm"
    if resume_at is None:
        r = re.search(r"resets?\s+(?:at\s+)?(?:(mon|tue|wed|thu|fri|sat|sun)[a-z]*\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?:\s*\(([^)]+)\))?", tail, re.I)
        if r:
            dow, hh, mm, ampm, tzname = r.groups()
            hh = int(hh); mm = int(mm or 0)
            if ampm:
                if ampm.lower() == "pm" and hh != 12: hh += 12
                if ampm.lower() == "am" and hh == 12: hh = 0
            tz = None
            if tzname and ZoneInfo:
                try: tz = ZoneInfo(tzname.strip())
                except Exception: tz = None
            base = datetime.datetime.now(tz) if tz else datetime.datetime.now().astimezone()
            cand = base.replace(hour=hh, minute=mm, second=0, microsecond=0)
            if dow:
                want = ["mon","tue","wed","thu","fri","sat","sun"].index(dow.lower()[:3])
                delta = (want - cand.weekday()) % 7
                cand = cand + datetime.timedelta(days=delta)
            if cand.timestamp() <= now:
                cand = cand + datetime.timedelta(days=1 if not dow else 7)
            resume_at = cand.timestamp()
    if resume_at is None:
        # no parseable reset time → the supervisor PROBES instead of guessing
        out("LIMIT", f"{int(now + default_wait*60)}\tprobe")
    resume_at = max(resume_at, now + 60) + buffer_min*60
    out("LIMIT", f"{int(resume_at)}\tparsed")

# ---- 2. a crash / API error / auth problem?
if rc != 0 or re.search(r"(api_error|internal server error|\b5\d\d\b .*error|ECONNRESET|ETIMEDOUT|ENOTFOUND|socket hang up|"
                        r"authentication_error|invalid api key|not logged in|please run /login|error_during_execution|"
                        r"\"is_error\"\s*:\s*true|Error: .*(fetch|network|connect))", tail, re.I):
    out("CRASH", f"rc={rc}")

# ---- 3. otherwise the agent just stopped
out("IDLE", "no sentinel")
PY
}

extract_session_id() { # from a cycle's output file (claude stream-json / json)
  python3 - "$1" <<'PY' 2>/dev/null
import sys, json, re
sid = ""
for line in open(sys.argv[1], errors="replace"):
    line = line.strip()
    if not line.startswith("{"): continue
    try: d = json.loads(line)
    except Exception: continue
    if isinstance(d, dict) and d.get("session_id"): sid = d["session_id"]
if not sid:
    m = re.findall(r'"session_id"\s*:\s*"([0-9a-f-]{8,})"', open(sys.argv[1], errors="replace").read())
    sid = m[-1] if m else ""
print(sid)
PY
}

# Fallback when a limit message carries no parseable reset time: fire a one-turn
# probe every PROBE_MIN minutes until it comes back clean (exit 0 AND no limit
# wording in its output). Gives up after PROBE_MAX_H hours and resumes anyway.
probe_until_clear() {
  local deadline=$(( $(date +%s) + PROBE_MAX_H * 3600 )) n=0 pout prc
  pout="$STATE_DIR/goal-probe.out"
  while :; do
    n=$(( n + 1 ))
    if [[ "$HARNESS" == claude ]]; then
      ( cd "$APP_DIR" && claude -p --max-turns 1 --output-format text "Reply with the single word OK." ) > "$pout" 2>&1; prc=$?
    else
      ( cd "$APP_DIR" && opencode run --auto "Reply with the single word OK." ) > "$pout" 2>&1; prc=$?
    fi
    if [[ $prc -eq 0 ]] && ! grep -qiE 'usage limit|hit your limit|rate[ _-]?limit|limit (has been )?(reached|exceeded)|too many requests|\b429\b|overloaded|weekly limit|resets? (at|in)\b' "$pout"; then
      log "probe #$n OK"; return 0
    fi
    log "probe #$n still limited (rc=$prc: $(head -c 120 "$pout" | tr '\n' ' ')) — next in ${PROBE_MIN}m"
    state_set resume_at "probe #$((n+1)) at $(date -d "+${PROBE_MIN} min" '+%H:%M' 2>/dev/null)"
    if [[ $(date +%s) -ge $deadline ]]; then log "probe window (${PROBE_MAX_H}h) exhausted — resuming anyway"; return 1; fi
    sleep $(( PROBE_MIN * 60 ))
  done
}

sleep_until() { # epoch
  local target="$1" now left
  while :; do
    now=$(date +%s); left=$(( target - now )); [[ $left -le 0 ]] && break
    state_set resume_at "$(date -u -d "@$target" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$target")"
    if [[ $left -gt 300 ]]; then sleep 300; else sleep "$left"; fi
  done
  state_set resume_at ""
}

# Debug: `tf-goal.sh --classify <output-file> [rc] <app-dir> x` prints the classification and exits.
if [[ -n "${TF_GOAL_CLASSIFY:-}" ]]; then classify_output "$TF_GOAL_CLASSIFY" "${TF_GOAL_CLASSIFY_RC:-0}"; exit 0; fi

# ---------------------------------------------------------------- main loop
export TF_YOLO=1
# Pin the state dir to the APP (not the caller's cwd / a parent repo's CLAUDE_PROJECT_DIR).
CLAUDE_PROJECT_DIR="$APP_DIR" TF_PROJECT_DIR="$APP_DIR" bash "$YOLO_SH" on --source goal --goal "$GOAL" >/dev/null 2>&1 || true
BACKOFF=120
KIND=first; [[ $RESUME -eq 1 && $CYCLE -gt 0 ]] && KIND=resume

while :; do
  if [[ -f "$DONE" ]]; then
    OUTCOME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("outcome","complete"))' "$DONE" 2>/dev/null || echo complete)"
    log "goal-done sentinel present (outcome=$OUTCOME): $(cat "$DONE")"
    state_set last_reason "done:$OUTCOME" ended "$(ts)"
    [[ "$OUTCOME" == blocked ]] && exit 3 || exit 0
  fi
  if [[ $CYCLE -ge $MAX_CYCLES ]]; then log "max cycles ($MAX_CYCLES) reached — stopping"; state_set last_reason "max-cycles"; exit 4; fi
  CYCLE=$((CYCLE + 1)); state_set cycle "$CYCLE"
  harness_cmd "$KIND"
  OUT="$STATE_DIR/goal-cycle-$CYCLE.out"
  log "cycle $CYCLE ($KIND) → ${CMD[*]:0:6} … (prompt ${#CMD[-1]} chars)"
  if [[ $DRY -eq 1 ]]; then printf '  %q' "${CMD[@]}"; echo; exit 0; fi

  ( cd "$APP_DIR" && TF_YOLO=1 "${CMD[@]}" ) > >(tee -a "$LOG" > "$OUT") 2>&1
  RC=$?
  sleep 1  # let tee flush
  SID="$(extract_session_id "$OUT")"; [[ -n "$SID" ]] && { SESSION_ID="$SID"; state_set session_id "$SID"; }
  KIND=resume

  if [[ -f "$DONE" ]]; then continue; fi

  IFS=$'\t' read -r CLASS DETAIL HOW < <(classify_output "$OUT" "$RC")
  case "$CLASS" in
    LIMIT)
      if [[ "$HOW" == probe ]]; then
        log "USAGE LIMIT hit (cycle $CYCLE) but no reset time could be parsed from the message — probing every ${PROBE_MIN}m until the API answers again (max ${PROBE_MAX_H}h). Tail of the message:"
        tail -c 400 "$OUT" | tr '\n' ' ' | sed 's/^/    /' | tee -a "$LOG" >&2; echo >&2
        state_set last_reason "limit-probe" resume_at "probing every ${PROBE_MIN}m"
        probe_until_clear
        log "probe succeeded — resuming session ${SESSION_ID:-(--continue)} after a ${BUFFER_MIN}m buffer"
        sleep $(( BUFFER_MIN * 60 ))
      else
        WHEN="$(date -d "@$DETAIL" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || echo "$DETAIL")"
        log "USAGE LIMIT hit (cycle $CYCLE) — RETRY AT $WHEN (stated reset + ${BUFFER_MIN}m buffer). Sleeping."
        state_set last_reason "limit" resume_at "$WHEN"
        sleep_until "$DETAIL"
        log "limit window over — resuming session ${SESSION_ID:-(--continue)}"
      fi
      BACKOFF=120 ;;
    CRASH)
      log "harness/API error (cycle $CYCLE, $DETAIL) — backing off ${BACKOFF}s then resuming"
      state_set last_reason "crash:$DETAIL"
      sleep "$BACKOFF"; BACKOFF=$(( BACKOFF * 2 )); [[ $BACKOFF -gt 1800 ]] && BACKOFF=1800 ;;
    IDLE|*)
      log "agent stopped without the goal-done sentinel (cycle $CYCLE) — re-prompting in ${IDLE_RETRY}s"
      state_set last_reason "idle"
      sleep "$IDLE_RETRY"; BACKOFF=120 ;;
  esac
done

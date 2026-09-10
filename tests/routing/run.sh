#!/usr/bin/env bash
# tests/routing/run.sh — self-test for model fallback and billing mode (2026-09-10).
#
# Two owner-found gaps, one test:
#
#   MISS-TechieFlow-20260910-01  routing had one model per tier and no answer when that model's
#                                usage limit was reached. Proves: a parked model is skipped, the
#                                tier's `fallbacks:` chain is walked in order, the Claude alias
#                                and the full model id are the same model, an expired cooldown
#                                stops mattering, an exhausted chain says so instead of guessing,
#                                and the harness bindings move with the choice so the sub-agents
#                                do not fail behind a main agent that already moved.
#
#   MISS-TechieFlow-20260910-02  every model's cost was recorded the same way, so a flat-fee
#                                subscription's zero, a metered key's real dollars and a local
#                                model's absent bill all pooled into one number. Proves: the mode
#                                is resolved from OpenCode's own auth file and catalog, stamped on
#                                the run record by the emitter and not by an agent, and that the
#                                report tells an invoice, a plan's allowance and a flat fee apart.
#
# It also holds the three places the owner corrected the first cut (2026-09-10). The cooldown
# record belongs in the project's own `.tfcore`, because the framework is installed per project
# and has to be changeable for one project alone. Turning tokens into money is the REPORTING
# tool's job, not the framework's: a record stores what was measured — tokens, model, and whatever
# cost the provider itself reported — and `tf-metrics.sh` prices it at report time, which is why
# this file checks the report's arithmetic and checks that no priced field is ever written. And
# OpenCode Go is a $10/month plan with a per-model allowance, so the dollars it reports are
# allowance consumed, not an invoice — the very numbers that produce the limit the fallback chain
# exists for.
#
# Run: bash tests/routing/run.sh    (a few seconds; exit 0 = every check passed)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tf-routing-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/app"; mkdir -p "$APP/.tfcore/utils" "$APP/.tfcore/tasks" "$APP/docs/metrics"
cp "$ROOT/.tfcore/utils/tf-harness.sh" "$ROOT/.tfcore/utils/tf-model-pick.sh" \
   "$ROOT/.tfcore/utils/tf-routing-bind.sh" "$ROOT/.tfcore/utils/tf-emit.sh" "$APP/.tfcore/utils/"
for t in build-phase verify-phase metrics-report; do echo "task" > "$APP/.tfcore/tasks/$t.md"; done

PICK="bash $APP/.tfcore/utils/tf-model-pick.sh"
export TF_PROJECT_DIR="$APP"
export TF_MODEL_HEALTH_FILE="$WORK/cooldown.json"
export OPENCODE_AUTH="$WORK/auth.json"
export OPENCODE_MODELS="$WORK/models.json"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $*"; }
bad() { fail=$((fail+1)); echo "FAIL $*"; }
eq()  { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (got '$2', wanted '$3')"; fi; }

# ---- fixtures ---------------------------------------------------------------------
# A routing map with a two-deep chain on each harness, so "the fallback is limited too"
# is reachable without touching the framework's own file.
cat > "$APP/.tfcore/routing.yaml" <<'YAML'
enabled: true
tiers:
  frontier:
    claude: sonnet
    opencode: paid/big
  standard:
    claude: sonnet
    opencode: paid/big
  economy:
    claude: haiku
    opencode: plan/small
fallbacks:
  frontier:
    claude: opus, haiku
    opencode: plan/small
  standard:
    claude: haiku
    opencode: plan/small, lmstudio/tiny
  economy:
    claude: sonnet
    opencode: lmstudio/tiny
billing:
  claude: subscription
  opencode: auto
phases:
  build-phase: standard
  verify-phase: standard
  metrics-report: economy
subagents:
  tf-builder: standard
  tf-explorer: economy
effort:
  frontier: high
  standard: medium
  economy: low
YAML
# OpenCode's own two answers: which providers are signed in, and how.
cat > "$WORK/auth.json" <<'JSON'
{"paid": {"type": "api"}, "plan": {"type": "oauth"}, "opencode-go": {"type": "api"}}
JSON
cat > "$WORK/models.json" <<'JSON'
{"paid": {"id": "paid", "models": {"big": {"id": "big", "cost": {"input": 3, "output": 15}}}},
 "plan": {"id": "plan", "models": {"small": {"id": "small", "cost": {"input": 1, "output": 4}}}},
 "elsewhere": {"id": "elsewhere", "models": {"m": {"id": "m", "cost": {"input": 1, "output": 1}}}},
 "opencode-go": {"id": "opencode-go", "models": {"glm-5.3": {"id": "glm-5.3", "cost": {"input": 1.4, "output": 4.4, "cache_read": 0.26}}}},
 "anthropic": {"id": "anthropic", "models": {
   "claude-opus-5":   {"id": "claude-opus-5",   "cost": {"input": 5, "output": 25, "cache_read": 0.5, "cache_write": 6.25}},
   "claude-haiku-4-5":{"id": "claude-haiku-4-5","cost": {"input": 1, "output": 5,  "cache_read": 0.1, "cache_write": 1.25}}}}}
JSON

# ---- 1. the chain ------------------------------------------------------------------
eq "nothing parked: the tier's own model" "$($PICK pick standard opencode)" "paid/big"
$PICK cooldown opencode paid/big +90 "5-hour limit" >/dev/null
eq "tier model parked: the first fallback"  "$($PICK pick standard opencode)" "plan/small"
$PICK cooldown opencode plan/small +90 "monthly limit" >/dev/null
eq "fallback parked too: the second"        "$($PICK pick standard opencode)" "lmstudio/tiny"
$PICK cooldown opencode lmstudio/tiny +90 "no balance" >/dev/null
eq "whole chain parked: say so, never guess" "$($PICK pick standard opencode)" "inherit"
$PICK clear opencode >/dev/null
eq "cleared: back to the tier model"        "$($PICK pick standard opencode)" "paid/big"

# ---- 2. a Claude alias and a full model id are the same model -----------------------
$PICK cooldown claude claude-sonnet-5 +90 "weekly limit" >/dev/null
eq "parking claude-sonnet-5 parks 'sonnet'" "$($PICK pick standard claude)" "haiku"
eq "…and the frontier chain skips it too"   "$($PICK pick frontier claude)" "opus"
$PICK clear claude >/dev/null
eq "cleared by alias"                       "$($PICK pick standard claude)" "sonnet"

# ---- 3. an expired cooldown stops mattering ----------------------------------------
python3 - "$TF_MODEL_HEALTH_FILE" <<'PY'
import json, sys, time
p = sys.argv[1]
past = int(time.time()) - 600
json.dump({"cooldown": [{"harness": "opencode", "model": "paid/big",
                         "since_epoch": past - 600, "until_epoch": past,
                         "since": "", "until": "", "why": "old", "app": "t"}]},
          open(p, "w"), indent=1)
PY
eq "an expired cooldown is ignored"         "$($PICK pick standard opencode)" "paid/big"
rm -f "$TF_MODEL_HEALTH_FILE"

# ---- 4. billing mode, from OpenCode's own files ------------------------------------
eq "an API key is metered"        "$($PICK billing paid/big opencode | cut -f1)" "metered"
eq "OAuth is a subscription"      "$($PICK billing plan/small opencode | cut -f1)" "subscription"
eq "a model on this machine is local" "$($PICK billing lmstudio/tiny opencode | cut -f1)" "local"
eq "a provider with no credential is unknown, never invented" \
   "$($PICK billing elsewhere/m opencode | cut -f1)" "unknown"
eq "Claude Code is declared, not guessed" "$($PICK billing sonnet claude | cut -f1)" "subscription"
# The escape hatch: a named provider inside `billing:` beats the auto-detection.
python3 - "$APP/.tfcore/routing.yaml" add <<'PY'
import sys
p, mode = sys.argv[1], sys.argv[2]
lines = open(p, encoding="utf-8").read().splitlines(True)
lines = [l for l in lines if l.strip() != "elsewhere: metered"]
if mode == "add":
    i = next(n for n, l in enumerate(lines) if l.startswith("billing:"))
    lines.insert(i + 1, "  elsewhere: metered\n")
open(p, "w", encoding="utf-8", newline="\n").write("".join(lines))
PY
eq "a named provider in billing: overrides the guess" \
   "$($PICK billing elsewhere/m opencode | cut -f1)" "metered"
python3 - "$APP/.tfcore/routing.yaml" remove <<'PY'
import sys
p = sys.argv[1]
lines = [l for l in open(p, encoding="utf-8") if l.strip() != "elsewhere: metered"]
open(p, "w", encoding="utf-8", newline="\n").write("".join(lines))
PY

# ---- 5. the bindings move with the choice ------------------------------------------
$PICK cooldown opencode paid/big +90 "5-hour limit" >/dev/null
$PICK cooldown claude sonnet +90 "weekly limit" >/dev/null
bash "$APP/.tfcore/utils/tf-routing-bind.sh" "$APP" >/dev/null 2>&1
got="$(python3 -c "import json;d=json.load(open('$APP/.opencode/opencode.json'));print(d['command']['techieflow:tasks:build-phase']['model'], d['agent']['tf-builder']['model'])")"
eq "OpenCode command AND sub-agent bind the fallback" "$got" "plan/small plan/small"
eq "the Claude wrapper binds the fallback too" \
   "$(grep -h '^model:' "$APP/.claude/commands/tf/build-phase.md")" "model: haiku"
eq "an unaffected tier keeps its own model" \
   "$(grep -h '^model:' "$APP/.claude/commands/tf/metrics-report.md")" "model: haiku"

# ---- 6. the emitter stamps the mode, and the fallback, and an agent cannot --------
# Four runs, four CONSECUTIVE windows — a run may not start before the last one ended (FR-72),
# and a fixture that shares one window across four runs is a timeline that cannot happen.
S_EP=$(( $(date +%s) - 400 ))
W() { date -u -d "@$(( S_EP + $1 ))" +%Y-%m-%dT%H:%M:%SZ; }
STARTED="$(W 0)"; ENDED="$(W 60)"                    # run 1: the Claude window
S2="$(W 60)";  E2="$(W 120)"                          # run 2: metered OpenCode
S3="$(W 120)"; E3="$(W 180)"                          # run 3: subscription OpenCode
S4="$(W 180)"; E4="$(W 240)"                          # run 4: the monthly plan
# A real fallback run STARTS after the model was parked; this fixture parked it a second ago and
# the window below is five minutes old. Backdate the park rather than fake the clock.
python3 - "$TF_MODEL_HEALTH_FILE" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for e in d["cooldown"]:
    e["since_epoch"] -= 3600
json.dump(d, open(p, "w"), indent=1)
PY
mkdir -p "$APP/.tfcore/.session"
cat > "$APP/transcript.jsonl" <<EOF
{"type":"assistant","timestamp":"$(W 30)","message":{"model":"claude-haiku-4-5","usage":{"input_tokens":100,"output_tokens":900,"cache_read_input_tokens":50,"cache_creation_input_tokens":0}}}
EOF
echo "{\"transcript_path\":\"$APP/transcript.jsonl\"}" > "$APP/.tfcore/.session/claude-code.json"
emit() { CLAUDE_PROJECT_DIR="$APP" TF_HARNESS="$1" bash "$APP/.tfcore/utils/tf-emit.sh" runs >/dev/null; }
echo "{\"kind\":\"run\",\"app\":\"T\",\"cmd\":\"build-phase\",\"mode\":\"x\",\"started\":\"$STARTED\",\"ended\":\"$ENDED\",\"cost_usd\":999,\"billing_mode\":\"metered\"}" | emit claude-code
rec="$(tail -1 "$APP/docs/metrics/runs.jsonl")"
eq "Claude run: subscription, no cost source" \
   "$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);print(d.get('billing_mode'), d.get('cost_source'), d.get('cost_usd'))" "$rec")" \
   "subscription none None"
eq "a self-reported billing mode and cost are discarded, like every derived field" \
   "$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);print(d.get('cost_usd') is None)" "$rec")" "True"
eq "the tier model was parked, so routed:false is named as a fallback" \
   "$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);print(d.get('fallback_from'), d.get('routed'))" "$rec")" \
   "sonnet False"

# ---- 7. the report calls money only what is money ----------------------------------
python3 - "$APP" "$S_EP" <<'PY'
import sqlite3, json, os, sys
app, s = sys.argv[1], int(sys.argv[2])
db = os.path.join(app, "oc.db")
c = sqlite3.connect(db)
c.execute("CREATE TABLE session (id TEXT, parent_id TEXT)")
c.execute("CREATE TABLE message (session_id TEXT, time_created INTEGER, data TEXT)")
c.execute("INSERT INTO session VALUES ('root', NULL)")


def msg(prov, model, cost):
    return json.dumps({"role": "assistant", "providerID": prov, "modelID": model,
                       "tokens": {"input": 10, "output": 500, "cache": {"read": 0, "write": 0}},
                       "cost": cost})


# one metered window and one subscription window, each on its own session
c.execute("INSERT INTO message VALUES ('root', ?, ?)", ((s + 90) * 1000, msg("paid", "big", 0.5)))
c.execute("INSERT INTO session VALUES ('root2', NULL)")
c.execute("INSERT INTO message VALUES ('root2', ?, ?)", ((s + 150) * 1000, msg("plan", "small", 0.0)))
# and one on a monthly plan, whose dollars are allowance consumed rather than an invoice
c.execute("INSERT INTO session VALUES ('root3', NULL)")
c.execute("INSERT INTO message VALUES ('root3', ?, ?)", ((s + 210) * 1000, msg("opencode-go", "glm-5.3", 0.25)))
c.commit()
json.dump({"db_path": db, "session_id": "root"},
          open(os.path.join(app, ".tfcore", ".session", "opencode.json"), "w"))
PY
echo "{\"kind\":\"run\",\"app\":\"T\",\"cmd\":\"verify-phase\",\"mode\":\"x\",\"started\":\"$S2\",\"ended\":\"$E2\"}" | emit opencode
eq "OpenCode metered run: real dollars, from the db" \
   "$(python3 -c "import json,sys;d=json.loads(open(sys.argv[1]).read().strip().splitlines()[-1]);print(d.get('billing_mode'), d.get('cost_usd'), d.get('cost_source'))" "$APP/docs/metrics/runs.jsonl")" \
   "metered 0.5 opencode-db"
python3 - "$APP" <<'PY'
import json, os, sys
# the same run again on the subscription session — its zero must never join the money figure
p = os.path.join(sys.argv[1], ".tfcore", ".session", "opencode.json")
d = json.load(open(p)); d["session_id"] = "root2"; json.dump(d, open(p, "w"))
PY
echo "{\"kind\":\"run\",\"app\":\"T\",\"cmd\":\"verify-phase\",\"mode\":\"x\",\"started\":\"$S3\",\"ended\":\"$E3\"}" | emit opencode
out="$(bash "$ROOT/.tfcore/telemetry/tf-metrics.sh" --phases "$APP" --json 2>/dev/null)"
eq "money is summed over metered records only" \
   "$(python3 -c "import json,sys;d=json.loads(sys.stdin.read())['phases']['verify-phase'];print(d['money_usd'], d['money_records'])" <<<"$out")" \
   "0.5 1"
eq "the subscription run is counted, and counted apart" \
   "$(python3 -c "import json,sys;d=json.loads(sys.stdin.read())['phases']['verify-phase'];print(d['billing_modes'].get('subscription'))" <<<"$out")" "1"
eq "a monthly plan with a per-model allowance is not an invoice" \
   "$($PICK billing opencode-go/glm-5.3 opencode | cut -f1)" "plan"
python3 - "$APP" <<'PY'
import json, os, sys
p = os.path.join(sys.argv[1], ".tfcore", ".session", "opencode.json")
d = json.load(open(p)); d["session_id"] = "root3"; json.dump(d, open(p, "w"))
PY
echo "{\"kind\":\"run\",\"app\":\"T\",\"cmd\":\"verify-phase\",\"mode\":\"x\",\"started\":\"$S4\",\"ended\":\"$E4\"}" | emit opencode
out="$(bash "$ROOT/.tfcore/telemetry/tf-metrics.sh" --phases "$APP" --json 2>/dev/null)"
eq "plan dollars are reported as allowance used, never as money billed" \
   "$(python3 -c "import json,sys;d=json.loads(sys.stdin.read())['phases']['verify-phase'];print(d['plan_allowance_usd'], d['money_usd'])" <<<"$out")" \
   "0.25 0.5"
eq "the allowance is named per model, which is where the limit applies" \
   "$(python3 -c "import json,sys;d=json.loads(sys.stdin.read())['phases']['verify-phase'];print(list(d['plan_allowance_by_model']))" <<<"$out")" \
   "['opencode-go/glm-5.3']"
eq "per-model spend names the model that was actually billed" \
   "$(python3 -c "import json,sys;d=json.loads(sys.stdin.read())['phases']['verify-phase'];print(list(d['spend_by_model']))" <<<"$out")" \
   "['paid/big']"

# ---- 8. an older project's routing.yaml gains the blocks, and loses nothing ---------
# update-framework.sh never overwrites a project's own routing.yaml, so a block added to the
# framework default would otherwise never reach an existing project. Both delivery routes run
# tf-routing-bind.sh, so the migration lives there.
OLD="$WORK/old"; mkdir -p "$OLD/.tfcore/utils" "$OLD/.tfcore/tasks"
cp "$ROOT/.tfcore/utils/tf-harness.sh" "$ROOT/.tfcore/utils/tf-model-pick.sh" \
   "$ROOT/.tfcore/utils/tf-routing-bind.sh" "$OLD/.tfcore/utils/"
echo "task" > "$OLD/.tfcore/tasks/build-phase.md"
printf 'enabled: true\ntiers:\n  standard:\n    claude: sonnet\nphases:\n  build-phase: standard\n' \
  > "$OLD/.tfcore/routing.yaml"
bash "$OLD/.tfcore/utils/tf-routing-bind.sh" "$OLD" >"$WORK/mig1.out" 2>&1
bash "$OLD/.tfcore/utils/tf-routing-bind.sh" "$OLD" >"$WORK/mig2.out" 2>&1
eq "a pre-2026-09-10 routing.yaml gains the two blocks" \
   "$(grep -c '^fallbacks:\|^billing:' "$OLD/.tfcore/routing.yaml")" "2"
eq "the migration is idempotent" "$(grep -c 'added fallbacks' "$WORK/mig2.out")" "0"
eq "the project's own lines come first and are untouched" \
   "$(head -6 "$OLD/.tfcore/routing.yaml" | tr '\n' '|')" \
   "enabled: true|tiers:|  standard:|    claude: sonnet|phases:|  build-phase: standard|"
$PICK clear >/dev/null   # step 5 left models parked; this check is about the file, not a cooldown
eq "the migrated file answers the fallback question" \
   "$(TF_PROJECT_DIR="$OLD" bash "$OLD/.tfcore/utils/tf-model-pick.sh" pick standard claude)" "sonnet"
$PICK cooldown claude sonnet +90 "weekly limit" >/dev/null
eq "…and the block it gained is what the fallback comes from" \
   "$(TF_PROJECT_DIR="$OLD" bash "$OLD/.tfcore/utils/tf-model-pick.sh" pick standard claude)" "haiku"

# ---- 9. the cooldown record lives in the project, and the project can move it -------
# Owner, 2026-09-10: TechieFlow is installed per project through npm/npx, never at machine
# level, so its state belongs in .tfcore and has to be changeable for one project alone.
( unset TF_MODEL_HEALTH_FILE
  PROJ="$WORK/proj"; mkdir -p "$PROJ/.tfcore/utils"
  cp "$ROOT/.tfcore/utils/tf-harness.sh" "$ROOT/.tfcore/utils/tf-model-pick.sh" "$PROJ/.tfcore/utils/"
  cp "$APP/.tfcore/routing.yaml" "$PROJ/.tfcore/"
  TF_PROJECT_DIR="$PROJ" bash "$PROJ/.tfcore/utils/tf-model-pick.sh" cooldown claude sonnet +60 t >/dev/null
  [[ -f "$PROJ/.tfcore/.session/model-cooldown.json" ]] || exit 1
  printf 'cooldown_file: .tfcore/limits.json\n' >> "$PROJ/.tfcore/routing.yaml"
  TF_PROJECT_DIR="$PROJ" bash "$PROJ/.tfcore/utils/tf-model-pick.sh" cooldown claude sonnet +60 t >/dev/null
  [[ -f "$PROJ/.tfcore/limits.json" ]] || exit 1
  # and it is the moved file that answers, not the old one
  [[ "$(TF_PROJECT_DIR="$PROJ" bash "$PROJ/.tfcore/utils/tf-model-pick.sh" pick standard claude)" == "haiku" ]] || exit 1
) ; check_rc=$?
eq "the cooldown record defaults into .tfcore and routing.yaml can move it" "$check_rc" "0"

# ---- 10. list price: a price list applied to a measured token count ------------------
eq "a Claude model prices from the catalog" \
   "$($PICK rate claude-opus-5 claude | cut -f1,2)" "$(printf '5\t25')"
eq "a model nothing prices returns nothing, never a zero" \
   "$($PICK rate nosuch/model opencode >/dev/null 2>&1; echo $?)" "1"
eq "a placeholder that is not a model is not priced" \
   "$($PICK rate '<synthetic>' claude >/dev/null 2>&1; echo $?)" "1"
cat > "$APP/.tfcore/rate-card.json" <<'JSON'
{"paid/big": {"input": 1, "output": 2, "cache_read": 0.5, "cache_write": 0}}
JSON
eq "the project's own rate card wins over the catalog" \
   "$($PICK rate paid/big opencode | cut -f1,2,5)" "$(printf '1\t2\t.tfcore/rate-card.json')"
rm -f "$APP/.tfcore/rate-card.json"

# The framework STORES no computed money (owner, 2026-09-10: pricing is the reporting tool's job).
# The record carries the tokens and the model; the report turns them into a price.
eq "no computed price is written to the record" \
   "$(python3 -c "
import json,sys
recs=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print(any('cost_list_usd' in r for r in recs))" "$APP/docs/metrics/runs.jsonl")" "False"
eq "the measured bill is on the record, untouched" \
   "$(python3 -c "
import json,sys
recs=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
r=[x for x in recs if x.get('billing_mode')=='metered'][-1]
print(r.get('cost_usd'), r.get('cost_source'))" "$APP/docs/metrics/runs.jsonl")" "0.5 opencode-db"

# The window emitted in section 6 was 900 output tokens of claude-haiku-4-5 (1 / 5 / 0.1 / 1.25),
# 100 in and 50 cache-read. The report's arithmetic is checked, not just that a number appeared.
want="$(python3 -c "print(round((100*1 + 900*5 + 50*0.1 + 0*1.25)/1e6, 6))")"
out1="$(bash "$ROOT/.tfcore/telemetry/tf-metrics.sh" --phases "$APP" --json 2>/dev/null)"
eq "the report prices a run from the rate card and the measured tokens" \
   "$(python3 -c "
import json,sys
print(json.loads(sys.stdin.read())['phases']['build-phase']['list_usd'])" <<<"$out1")" "$want"

out2="$out1"
eq "the report carries list price beside the money" \
   "$(python3 -c "
import json,sys
d=json.loads(sys.stdin.read())['phases']['verify-phase']
print(d['list_usd_records'], d['money_usd'])" <<<"$out2")" "3 0.5"

echo
echo "routing self-test: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
exit 0

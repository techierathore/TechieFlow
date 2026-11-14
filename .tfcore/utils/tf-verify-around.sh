#!/usr/bin/env bash
# tf-verify-around.sh — what tf-verify-tests.sh does around a test run (Sevak TF-026, 2026-11-12).
# Sourced, never run: it only defines functions.
#
#   tf_setup_first NAME=VALUE…   set-up tests run first, never graded
#   tf_keep_drawing start <cdp url> | stop
#   tf_head_holds_build          prints the address of a desktop head that is up, else nothing
#   tf_boot_grep <list> <ids>    sets TF_BOOT_ARGS, the browser run's --grep for this boot
#
# SET-UP TESTS. A test whose title or tag carries `@setup` proves no row: it puts the app in the state the
# row tests need (Sevak's p2/set-language, p4/ready). A phase verify runs every one of them first, on the
# same boot and with the same settings as the row tests, records them in setup.json, never maps them to a
# row and never lists them as "no row id". `test('… @setup', …)` or `test('…', { tag: '@setup' }, …)`.
#
# A MINIMIZED WINDOW. A minimized desktop head draws no frames, and every click of a test waits for a
# control to be "stable" until it times out. While the tests run, the head's window is restored whenever
# it is minimized (tf-login.mjs keepDrawing; the head's process ids come from boot.json win_pids).
#
# UNIT TESTS BEFORE THE BOOT. A Windows desktop head runs from the build output, so a unit-test build
# while it is up fails on locked files (MSB3027, ten retries per project) and reports nothing new. The
# unit tests run before tf-verify-boot.sh start (--no-browser), and their part is merged afterwards.
#
# ANOTHER BOOT. A row noted `needs-boot: <kind>` may have a test for each boot (Sevak TF-031: REQ-FN-046
# exports on the first install and restores on the second). A test tagged `@boot:<kind>` runs only on the
# run of list-<kind>.json; there only the row's tests carrying that tag run, and the main run leaves every
# `@boot:` test out. With no test tagged for the kind, every test of the row runs on that boot, as before,
# and a line says so.

tf_setup_first() {
  grep -rqsE '@setup' tests/verify --include='*.spec.*' 2>/dev/null || return 0
  local out="tests/.artifacts/verify/setup${PART:+-$PART}.json" log="tests/.artifacts/verify/setup${PART:+-$PART}.log"
  env "$@" PLAYWRIGHT_JSON_OUTPUT_NAME="$out" npx playwright test --grep @setup --reporter=json > "$log" 2>&1
  python3 - "$out" "$log" <<'SETUPPY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("browser tests: set-up tests: could not run (log %s); the row tests run anyway" % sys.argv[2]); sys.exit(0)
done = []
def walk(s, f):
    f = s.get("file") or f
    for sp in s.get("specs", []):
        res = [r.get("status") for t in sp.get("tests", []) for r in t.get("results", [])[-1:]]
        done.append("%s — \"%s\" (%s)" % (sp.get("file") or f, sp.get("title", "")[:100], "/".join(x or "?" for x in res) or "not run"))
    for c in s.get("suites", []):
        walk(c, f)
for s in data.get("suites", []):
    walk(s, s.get("file", ""))
print("browser tests: %d set-up test(s) ran first, graded against no row (log %s)" % (len(done), sys.argv[2]))
for d in done:
    print("  SET-UP " + d)
SETUPPY
}

TF_KEEP_PID=""
tf_keep_drawing() {
  local stop="tests/.artifacts/verify/.keep-drawing"
  if [[ "$1" == start ]]; then
    [[ -n "${2:-}" ]] && command -v node >/dev/null 2>&1 || return 0
    : > "$stop"
    TF_KEEP_STOP="$stop" TF_KEEP_CDP="$2" node --input-type=module -e "import(process.argv[1]).then((m) => m.keepDrawing(process.env.TF_KEEP_STOP, process.env.TF_KEEP_CDP))" "$HERE/tf-login.mjs" &
    TF_KEEP_PID=$!
  else
    rm -f "$stop"
    [[ -n "$TF_KEEP_PID" ]] && wait "$TF_KEEP_PID" 2>/dev/null
    TF_KEEP_PID=""
  fi
  return 0
}

tf_head_holds_build() {
  local u
  u="$(python3 -c 'import json,sys
b = json.load(open(sys.argv[1]))
print(b.get("url", "") if b.get("mode") == "cdp" and not b.get("stopped") else "")' tests/.artifacts/verify/boot.json 2>/dev/null)"
  [[ -n "$u" ]] && curl -s -m 3 "${u%/}/json/version" 2>/dev/null | grep -q webSocketDebuggerUrl && printf '%s' "$u"
  return 0
}

tf_boot_grep() {
  local kind
  kind="$(python3 -c 'import json,sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("needs_boot") or "")' "$1" 2>/dev/null)"
  TF_BOOT_ARGS=(); [[ -n "$2" ]] && TF_BOOT_ARGS=(--grep "$2")
  if [[ -z "$kind" ]]; then
    grep -rqsE '@boot:' tests/verify --include='*.spec.*' && TF_BOOT_ARGS+=(--grep-invert '@boot:')
  elif grep -rqsE "@boot:$kind" tests/verify --include='*.spec.*'; then
    TF_BOOT_ARGS=(--grep "^(?=.*(${2:-.}))(?=.*@boot:$kind)")
  else
    echo "browser tests: no test is tagged @boot:$kind, so every test of the row runs on this boot, its other boot's half too (Sevak TF-031); tag the test that belongs here"
  fi
  return 0
}

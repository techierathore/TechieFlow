#!/usr/bin/env bash
# tf-verify-tests.sh — run the acceptance tests and map them to rows (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-tests.sh [--base URL] [--target <sln|csproj>] [--no-browser] [--no-unit]
#                                         [--json-out tests/.artifacts/verify/tests.json]
#
# Browser tests: `npx playwright test` over tests/verify/ (the JSON reporter). Unit tests:
# `tf-build.sh test` with normal console verbosity. A test belongs to a row when its name contains
# the row's id (REQ-UI-004 …). A row is PASS when a test carrying its id passed and none failed,
# FAIL when one failed (the reason and the screenshot, when the reporter kept one, are recorded),
# NOT-TESTED when every test carrying its id was SKIPPED, and absent when no test carries its id.
# A skipped clause is a third outcome, never a failure: `test.skip(!SEEDED, …)` says the state does
# not exist in the data, which is not a defect (TF-022). Writes tests/.artifacts/verify/tests.json.
# Exit 0 ran (whatever the results) · 2 nothing could run.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE=""; TARGET=""; BROWSER=1; UNIT=1; OUT="tests/.artifacts/verify/tests.json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --no-browser) BROWSER=0; shift ;;
    --no-unit) UNIT=0; shift ;;
    --json-out) OUT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "tf-verify-tests: unknown argument $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$(dirname "$OUT")" tests/.artifacts/verify
PWJSON="tests/.artifacts/verify/playwright.json"; PWLOG="tests/.artifacts/verify/playwright.log"; UNITLOG=""; UNITLINE=""
ran_any=0

if [[ $BROWSER -eq 1 ]]; then
  if ls tests/verify/*.spec.* >/dev/null 2>&1 || ls tests/verify/**/*.spec.* >/dev/null 2>&1; then
    # --base reaches the tests only as BASE_URL, which Playwright never reads by itself. When neither
    # the config nor a spec reads it, every test opens the config's own address, where an older build
    # may still be running and pass in the new one's name (TfLens TF-031, 2026-09-11): refuse instead.
    if [[ -n "$BASE" ]] && ! grep -qs "BASE_URL" playwright.config.* tests/verify/*.spec.* tests/verify/**/*.spec.*; then
      echo "browser tests: NOT RUN — nothing reads BASE_URL, so the tests would open another address than --base $BASE; run bash .tfcore/utils/tf-verify-env.sh, which makes playwright.config.ts read it"
      rm -f "$PWJSON"
    elif node -e "require.resolve('@playwright/test')" >/dev/null 2>&1; then
      BASE_URL="$BASE" PLAYWRIGHT_JSON_OUTPUT_NAME="$PWJSON" npx playwright test --reporter=json > "$PWLOG" 2>&1
      echo "browser tests: ran (log $PWLOG)"; ran_any=1
    else
      echo "browser tests: @playwright/test is not installed here (bash .tfcore/utils/tf-verify-env.sh); skipped"; rm -f "$PWJSON"
    fi
  else
    echo "browser tests: no spec under tests/verify/; skipped"; rm -f "$PWJSON"
  fi
else rm -f "$PWJSON"; fi

if [[ $UNIT -eq 1 ]]; then
  if [[ -n "$TARGET" ]] || ls *.sln *.slnx >/dev/null 2>&1 || ls tests/*/*.csproj >/dev/null 2>&1; then
    UNITLINE="$(bash "$HERE/tf-build.sh" test ${TARGET:+"$TARGET"} -- --logger "console;verbosity=normal" 2>&1 | head -1)"
    UNITLOG="$(sed -n 's/.*log \(tests\/\.artifacts\/build\/[^ ;]*\).*/\1/p' <<<"$UNITLINE" | head -1)"
    echo "unit tests: $UNITLINE"; [[ "$UNITLINE" != NOT-RUN* ]] && ran_any=1
  else
    echo "unit tests: no solution or test project found; skipped"
  fi
fi

TF_PWJSON="$PWJSON" TF_UNITLOG="$UNITLOG" TF_UNITLINE="$UNITLINE" TF_OUT="$OUT" python3 - <<'PY'
import json, os, re
ID = re.compile(r"(REQ-(?:UI|FN|NFR|RAG)-\d{3})", re.I)
reqs = {}
browser = {"ran": False, "passed": 0, "failed": 0, "skipped": 0, "tests": 0}
unit = {"ran": False, "line": os.environ.get("TF_UNITLINE", "")}

def add(rid, outcome, name, source, reason="", shot=""):
    """Record one test against a row. `outcome` is "pass", "fail" or "skip".

    A SKIPPED clause is the third outcome and neither of the other two. A conditional
    `test.skip(!SEEDED, "needs the seeded dataset")` says the state does not exist in the
    data yet: that is not a pass, and it is not a defect either. Counting it as a failure
    put FAIL on rows no code could clear and sent build-phase back into FIX mode against
    them (TF-022, TfLens 2026-09-09). A row whose clauses were ALL skipped ends
    NOT-TESTED, which the verdict script reads as not measured — never Verified, never a
    defect. tests/regression/run.sh tf_022."""
    r = reqs.setdefault(rid.upper(), {"result": "NOT-TESTED", "source": source, "tests": [],
                                      "skipped": [], "passed": 0, "failed": 0,
                                      "reason": "", "screenshot": ""})
    if outcome == "skip":
        r["skipped"].append(name)
        if not r["reason"]:
            r["reason"] = (reason or "the test was skipped")[:200]
        return
    r["tests"].append(name)
    if outcome == "pass":
        r["passed"] += 1
    else:
        if r["result"] != "FAIL":          # the first real failure owns the reason
            r["reason"] = reason[:200]
        r["failed"] += 1
        if shot and not r["screenshot"]:
            r["screenshot"] = shot
    r["result"] = "FAIL" if r["failed"] else "PASS"

pw = os.environ.get("TF_PWJSON", "")
if pw and os.path.isfile(pw):
    try:
        data = json.load(open(pw, encoding="utf-8"))
        browser["ran"] = True
        def walk(suite, path):
            for sp in suite.get("specs", []):
                title = " ".join(path + [sp.get("title", "")])
                for t in sp.get("tests", []):
                    res = t.get("results", [])
                    last = res[-1] if res else {}
                    status = last.get("status", t.get("status", "unexpected"))
                    # skipped is read FIRST: it is neither a pass nor a failure (TF-022)
                    if status == "skipped" or t.get("status") == "skipped":
                        outcome = "skip"
                    elif status in ("passed", "expected") or t.get("status") == "expected":
                        outcome = "pass"
                    else:
                        outcome = "fail"
                    browser["tests"] += 1
                    browser[{"pass": "passed", "fail": "failed", "skip": "skipped"}[outcome]] += 1
                    err = ""
                    if outcome == "skip":
                        why = [a.get("description") for a in (t.get("annotations") or [])
                               if a.get("type") == "skip" and a.get("description")]
                        err = "skipped" + (": " + str(why[0]) if why else "")
                    elif last.get("error"):
                        err = re.sub(r"\x1b\[[0-9;]*m", "", str(last["error"].get("message", "")).split("\n")[0])
                    shot = ""
                    for a in last.get("attachments", []):
                        if a.get("name") == "screenshot" and a.get("path"):
                            shot = a["path"].replace("\\", "/")
                            shot = shot[shot.find("tests/"):] if "tests/" in shot else shot
                            break
                    for rid in set(ID.findall(title)):
                        add(rid, outcome, title.strip(), "browser", err, shot)
            for s in suite.get("suites", []):
                walk(s, path + [s.get("title", "")] if s.get("title") and not s["title"].endswith(".ts") and not s["title"].endswith(".js") and not s["title"].endswith(".mjs") else path)
        for s in data.get("suites", []):
            walk(s, [])
    except Exception as e:
        browser["error"] = str(e)

ul = os.environ.get("TF_UNITLOG", "")
if ul and os.path.isfile(ul):
    unit["ran"] = True
    for line in open(ul, encoding="utf-8", errors="replace"):
        m = re.match(r"\s*(Passed|Failed|Skipped)\s+(\S.*?)\s*(\[[^\]]*\])?\s*$", line)
        if not m:
            continue
        # a skipped unit test is recorded as skipped, not dropped: the row then reads
        # NOT-TESTED with the evidence, rather than looking as if no test exists (TF-022)
        outcome = {"Passed": "pass", "Failed": "fail", "Skipped": "skip"}[m.group(1)]
        name = m.group(2).strip()
        for rid in set(ID.findall(name)):
            add(rid, outcome, name, "unit",
                ("unit test failed: " if outcome == "fail" else "unit test skipped: ") + name[:120])
unit["passed"] = sum(1 for r in reqs.values() if r["source"] == "unit" and r["result"] == "PASS")
unit["failed"] = sum(1 for r in reqs.values() if r["source"] == "unit" and r["result"] == "FAIL")
unit["not_tested"] = sum(1 for r in reqs.values() if r["source"] == "unit" and r["result"] == "NOT-TESTED")

json.dump({"reqs": reqs, "browser": browser, "unit": unit}, open(os.environ["TF_OUT"], "w"), indent=1)
p = sum(1 for r in reqs.values() if r["result"] == "PASS")
f = sum(1 for r in reqs.values() if r["result"] == "FAIL")
ns = sum(1 for r in reqs.values() if r["result"] == "NOT-TESTED")
print(f"rows with a test: {len(reqs)} — {p} PASS, {f} FAIL, {ns} NOT-TESTED (every clause skipped)"
      + (f" (browser {browser['passed']}/{browser['tests']} tests passed, {browser['skipped']} skipped)" if browser["ran"] else ""))
for rid, r in sorted(reqs.items()):
    if r["result"] == "FAIL":
        print(f"  FAIL {rid} — {r['reason']}" + (f" — {r['screenshot']}" if r["screenshot"] else ""))
    elif r["result"] == "NOT-TESTED":
        print(f"  NOT-TESTED {rid} — {len(r['skipped'])} test(s) skipped, none ran — {r['reason']}")
print(f"JSON: {os.environ['TF_OUT']}")
PY
[[ $ran_any -eq 1 ]] && exit 0 || exit 2

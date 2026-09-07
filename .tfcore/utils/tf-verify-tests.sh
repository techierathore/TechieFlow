#!/usr/bin/env bash
# tf-verify-tests.sh — run the acceptance tests and map them to rows (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-tests.sh [--base URL] [--target <sln|csproj>] [--no-browser] [--no-unit]
#                                         [--json-out tests/.artifacts/verify/tests.json]
#
# Browser tests: `npx playwright test` over tests/verify/ (the JSON reporter). Unit tests:
# `tf-build.sh test` with normal console verbosity. A test belongs to a row when its name contains
# the row's id (REQ-UI-004 …). A row is PASS when every test carrying its id passed, FAIL when one
# failed (the reason and the screenshot, when the reporter kept one, are recorded), and absent
# when no test carries its id. Writes tests/.artifacts/verify/tests.json for the verdict script.
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
    if node -e "require.resolve('@playwright/test')" >/dev/null 2>&1; then
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
reqs, browser, unit = {}, {"ran": False, "passed": 0, "failed": 0, "tests": 0}, {"ran": False, "line": os.environ.get("TF_UNITLINE", "")}

def add(rid, ok, name, source, reason="", shot=""):
    r = reqs.setdefault(rid.upper(), {"result": "PASS", "source": source, "tests": [], "reason": "", "screenshot": ""})
    r["tests"].append(name)
    if not ok:
        r["result"] = "FAIL"
        if not r["reason"]:
            r["reason"] = reason[:200]
        if shot and not r["screenshot"]:
            r["screenshot"] = shot

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
                    ok = status in ("passed", "expected") or t.get("status") == "expected"
                    browser["tests"] += 1
                    browser["passed" if ok else "failed"] += 1
                    err = ""
                    if last.get("error"):
                        err = re.sub(r"\x1b\[[0-9;]*m", "", str(last["error"].get("message", "")).split("\n")[0])
                    shot = ""
                    for a in last.get("attachments", []):
                        if a.get("name") == "screenshot" and a.get("path"):
                            shot = a["path"].replace("\\", "/")
                            shot = shot[shot.find("tests/"):] if "tests/" in shot else shot
                            break
                    for rid in set(ID.findall(title)):
                        add(rid, ok, title.strip(), "browser", err, shot)
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
        if not m or m.group(1) == "Skipped":
            continue
        name = m.group(2).strip()
        for rid in set(ID.findall(name)):
            add(rid, m.group(1) == "Passed", name, "unit", "unit test failed: " + name[:120])
unit["passed"] = sum(1 for r in reqs.values() if r["source"] == "unit" and r["result"] == "PASS")
unit["failed"] = sum(1 for r in reqs.values() if r["source"] == "unit" and r["result"] == "FAIL")

json.dump({"reqs": reqs, "browser": browser, "unit": unit}, open(os.environ["TF_OUT"], "w"), indent=1)
p = sum(1 for r in reqs.values() if r["result"] == "PASS"); f = len(reqs) - p
print(f"rows with a test: {len(reqs)} — {p} PASS, {f} FAIL" + (f" (browser {browser['passed']}/{browser['tests']} tests passed)" if browser["ran"] else ""))
for rid, r in sorted(reqs.items()):
    if r["result"] == "FAIL":
        print(f"  FAIL {rid} — {r['reason']}" + (f" — {r['screenshot']}" if r["screenshot"] else ""))
print(f"JSON: {os.environ['TF_OUT']}")
PY
[[ $ran_any -eq 1 ]] && exit 0 || exit 2

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
  # Each pattern on its own: `ls *.sln *.slnx` fails when either matches nothing, so a .slnx-only
  # solution read as none; and a test project may sit at any depth under tests/, not one folder down
  # (AppManager TF-007: tests/unit/AppManager.UnitTests/). tf-build.sh finds a root solution itself;
  # without one it is handed the only test project, and several are named rather than guessed between.
  ROOTSLN="$(compgen -G '*.sln'; compgen -G '*.slnx'; compgen -G '*.csproj')"
  mapfile -t TESTPROJ < <(find tests -name '*.csproj' -not -path 'tests/.artifacts/*' -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' 2>/dev/null | sort)
  [[ -z "$TARGET" && -z "$ROOTSLN" && ${#TESTPROJ[@]} -eq 1 ]] && TARGET="${TESTPROJ[0]}"
  if [[ -z "$TARGET" && -z "$ROOTSLN" && ${#TESTPROJ[@]} -gt 1 ]]; then
    echo "unit tests: NOT RUN — no solution here and ${#TESTPROJ[@]} test projects under tests/ (${TESTPROJ[*]}); name one with --target"
  elif [[ -n "$TARGET" || -n "$ROOTSLN" ]]; then
    # the VERDICT line, not the first line: tf-build.sh may print a note before it, and a note read
    # as the verdict left 975 passing TfLens tests recorded as never run (TF-037)
    # A test project on Microsoft.Testing.Platform ignores --logger and prints no line per test, so no
    # unit test ever reached a row (AppManager TF-005, xunit.v3, 286 tests). Such a project is asked for
    # a TRX report, the per-test record both platforms write, through the property `dotnet test` passes
    # to it. One switch serves every project or none is passed: an unknown switch stops a test app.
    MTP="$(python3 - <<'PY'
import os, re
flags, mtp = set(), 0
for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in ("bin", "obj", "node_modules", ".git") and not (root == "./tests" and d == ".artifacts")]
    for fn in files:
        if not fn.endswith(".csproj"):
            continue
        t = open(os.path.join(root, fn), encoding="utf-8", errors="replace").read()
        if not re.search(r"<(TestingPlatformDotnetTestSupport|UseMicrosoftTestingPlatformRunner|EnableMSTestRunner|EnableNUnitRunner)>\s*true", t, re.I) and 'Sdk="MSTest.Sdk' not in t:
            continue
        mtp += 1
        if re.search(r'Include="xunit\.v3"', t, re.I):
            flags.add("--report-xunit-trx")
        elif re.search(r'Include="Microsoft\.Testing\.Extensions\.TrxReport"|Sdk="MSTest\.Sdk', t, re.I):
            flags.add("--report-trx")
        else:
            flags.add("?")
print(next(iter(flags)) if mtp and len(flags) == 1 and "?" not in flags else ("mixed" if mtp else ""))
PY
)"
    UARGS=(--logger "console;verbosity=normal")
    case "$MTP" in
      --report-*) UARGS+=("-p:TestingPlatformCommandLineArguments=$MTP") ;;
      mixed) echo "unit tests: note  the Testing Platform projects here take different report switches, so none was passed; their tests are not mapped to rows" ;;
    esac
    STAMP="$(mktemp)"
    UNITLINE="$(bash "$HERE/tf-build.sh" test ${TARGET:+"$TARGET"} -- "${UARGS[@]}" 2>&1 | grep -m1 -E '^(PASS|FAIL|NOT-RUN)' || true)"
    UNITLOG="$(sed -n 's/.*log \(tests\/\.artifacts\/build\/[^ ;]*\).*/\1/p' <<<"$UNITLINE" | head -1)"
    TRX="$(find . -name '*.trx' -newer "$STAMP" -not -path '*/node_modules/*' 2>/dev/null)"; rm -f "$STAMP"
    echo "unit tests: $UNITLINE"; [[ "$UNITLINE" != NOT-RUN* ]] && ran_any=1
  else
    echo "unit tests: no solution or test project found; skipped"
  fi
fi

TF_PWJSON="$PWJSON" TF_UNITLOG="$UNITLOG" TF_UNITLINE="$UNITLINE" TF_TRX="${TRX:-}" TF_OUT="$OUT" python3 - <<'PY'
import json, os, re
import xml.etree.ElementTree as ET
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

seen = set()   # one test read from both a TRX report and the console is counted once
for trx in [p for p in os.environ.get("TF_TRX", "").splitlines() if p.strip()]:
    try:
        tree = ET.parse(trx).getroot()
    except Exception as e:
        unit.setdefault("trx_unreadable", []).append(f"{trx}: {str(e)[:80]}")
        continue
    unit["ran"] = True
    unit.setdefault("trx", []).append(trx)
    for el in tree.iter():
        if not el.tag.endswith("UnitTestResult"):
            continue
        name = (el.get("testName") or "").strip()
        oc = (el.get("outcome") or "").lower()          # Passed / Failed / NotExecuted …, any case (TF-005)
        outcome = "pass" if oc == "passed" else "skip" if oc in ("notexecuted", "inconclusive", "pending", "notrunnable", "disconnected") else "fail"
        if (name, outcome) in seen:
            continue
        seen.add((name, outcome))
        msg = next(((m.text or "").strip() for m in el.iter() if m.tag.endswith("Message") and (m.text or "").strip()), "")
        for rid in set(ID.findall(name)):
            add(rid, outcome, name, "unit",
                ("unit test failed: " + (msg.splitlines()[0] if msg else name))[:200] if outcome == "fail"
                else ("unit test skipped: " + name[:120]) if outcome == "skip" else "")

ul = os.environ.get("TF_UNITLOG", "")
if ul and os.path.isfile(ul):
    unit["ran"] = True
    for line in open(ul, encoding="utf-8", errors="replace"):
        # any case, and a "(133ms)" tail: the Testing Platform's own log writes "failed REQ-NFR-007 … (133ms)" (TF-005)
        m = re.match(r"\s*(passed|failed|skipped)\s+(\S.*?)\s*(?:\[[^\]]*\]|\(\d+(?:\.\d+)?\s*m?s\))?\s*$", line, re.I)
        if not m:
            continue
        # a skipped unit test is recorded as skipped, not dropped: the row then reads
        # NOT-TESTED with the evidence, rather than looking as if no test exists (TF-022)
        outcome = {"passed": "pass", "failed": "fail", "skipped": "skip"}[m.group(1).lower()]
        name = m.group(2).strip()
        if (name, outcome) in seen:
            continue
        seen.add((name, outcome))
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

#!/usr/bin/env bash
# tf-verify-tests.sh — run the acceptance tests and map them to rows (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-tests.sh [--base URL] [--target <sln|csproj>] [--no-browser] [--no-unit]
#                                         [--shard N/M] [--spec <file or glob>]… [--list <list.json>] [--all-specs]
#                                         [--json-out tests/.artifacts/verify/tests.json]
#   bash .tfcore/utils/tf-verify-tests.sh --merge <tests-a.json> <tests-b.json>… [--json-out tests/.artifacts/verify/tests.json]
#
# Browser tests: `npx playwright test` over tests/verify/ (the JSON reporter). Unit tests:
# `tf-build.sh test` with normal console verbosity. A test belongs to a row when its name contains
# the row's id (REQ-UI-004 …). A row is PASS when a test carrying its id passed and none failed,
# FAIL when one failed (the reason and the screenshot, when the reporter kept one, are recorded),
# NOT-TESTED when every test carrying its id was SKIPPED, and absent when no test carries its id.
# A skipped clause is a third outcome, never a failure: `test.skip(!SEEDED, …)` says the state does
# not exist in the data, which is not a defect (TF-022). Writes tests/.artifacts/verify/tests.json.
# A suite too long for one command runs in parts (AppManager TF-013): `--shard N/M` runs Playwright's
# shard N of M (browser only; run the unit tests once with --no-browser), `--spec` names files, and
# each part writes its own playwright-<part>.json and tests-<part>.json. `--merge` then combines the
# parts' rows and totals into one tests.json; a later run of the same test stands for it (Lekhak TF-007).
# When tf-verify-list.sh was given a list of ids, the browser run keeps only the tests carrying them
# (`--grep`), and is skipped when no row has a screen and no browser test names one (Lekhak TF-017).
# `--list` names another list.json; `--all-specs` runs every browser test whatever the scope.
# A desktop head's debugging address (--base answering /json/version, or boot.json mode=cdp) also
# reaches the tests as CDP_URL; a suite that reads it nowhere is refused, not run (Lekhak TF-021).
# A Mac Catalyst head (boot.json mode=appium) reaches them as APPIUM_URL, TF_BUNDLE_ID and TF_APP_PATH.
# Exit 0 ran (whatever the results) · 2 nothing could run.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/tf-portable.sh"   # tf_read_lines, for bash 3.2 on a stock Mac
BASE=""; TARGET=""; BROWSER=1; UNIT=1; OUT=""; SHARD=""; SPECS=(); MERGE=(); LIST="tests/.artifacts/verify/list.json"; ALLSPECS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --no-browser) BROWSER=0; shift ;;
    --no-unit) UNIT=0; shift ;;
    --shard) SHARD="${2:-}"; UNIT=0; shift 2 ;;
    --spec) SPECS+=("${2:-}"); shift 2 ;;
    --list) LIST="${2:-}"; shift 2 ;;
    --all-specs) ALLSPECS=1; shift ;;
    --merge) shift; while [[ $# -gt 0 && "$1" != --* ]]; do MERGE+=("$1"); shift; done ;;
    --json-out) OUT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "tf-verify-tests: unknown argument $1" >&2; exit 2 ;;
  esac
done
PART=""
if [[ -n "$SHARD" ]]; then
  [[ "$SHARD" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] || { echo "tf-verify-tests: --shard takes N/M, such as 2/4" >&2; exit 2; }
  PART="${BASH_REMATCH[1]}of${BASH_REMATCH[2]}"
fi
[[ -n "$OUT" ]] || OUT="tests/.artifacts/verify/tests${PART:+-$PART}.json"
mkdir -p "$(dirname "$OUT")" tests/.artifacts/verify

# ---- --merge: the parts into one tests.json, no test run ------------------------------------------
if [[ ${#MERGE[@]} -gt 0 ]]; then
  TF_OUT="$OUT" python3 - "${MERGE[@]}" <<'PY'
import json, os, re, sys
# Lekhak TF-007. The parts are read oldest first (by the time each ran, else in the order given), and
# a later run of the SAME test stands for it: a test that failed because its service was not started,
# run again once it was, clears the row. A later skip never replaces a run that happened. A part
# written before tests carried their own outcome counts each of its tests as the row's result.
loaded = []
for i, p in enumerate(sys.argv[1:]):
    try:
        loaded.append((json.load(open(p, encoding="utf-8")), i, p))
    except Exception as e:
        print(f"merge: {p} unreadable ({str(e)[:80]}); skipped")
loaded.sort(key=lambda x: (x[0].get("ran_at") or "", x[1]) if all(y[0].get("ran_at") for y in loaded) else (x[1],))
reqs, browser, unit, parts = {}, {"ran": False, "passed": 0, "failed": 0, "skipped": 0, "tests": 0}, {"ran": False, "line": ""}, []
outs, sources, superseded = {}, {}, 0
for d, _i, p in loaded:
    parts.append(p)
    for rid, r in d.get("reqs", {}).items():
        oc = r.get("outcomes")
        if oc is None:   # an older part: every test it lists carries the row's result
            res = {"PASS": "pass", "FAIL": "fail"}.get(r.get("result"), "skip")
            oc = {t: {"outcome": res, "reason": r.get("reason", "") if res == "fail" else "", "screenshot": r.get("screenshot", "")} for t in r.get("tests", [])}
            oc.update({t: {"outcome": "skip", "reason": r.get("reason", ""), "screenshot": ""} for t in r.get("skipped", [])})
        o = outs.setdefault(rid, {})
        for name, rec in oc.items():
            # a part written before outcomes carried their source: the row's, when it had only one
            if "source" not in rec:
                rec = dict(rec, source=r.get("source") if r.get("source") in ("browser", "unit") else "")
            old = o.get(name)
            if old and rec["outcome"] == "skip" and old["outcome"] != "skip":
                continue
            if old and old["outcome"] != rec["outcome"]:
                superseded += 1
            o[name] = rec
        src = sources.get(rid)
        sources[rid] = r.get("source", "") if src in (None, r.get("source", "")) else "browser+unit"
    b = d.get("browser", {})
    if b.get("ran"):
        browser["ran"] = True
        for k in ("passed", "failed", "skipped", "tests"):
            browser[k] += b.get(k, 0)
    u = d.get("unit", {})
    if u.get("ran") and not unit["ran"]:
        unit = u
for rid, o in outs.items():
    fails = [(n, x) for n, x in o.items() if x["outcome"] == "fail"]
    npass = sum(1 for x in o.values() if x["outcome"] == "pass")
    skips = [(n, x) for n, x in o.items() if x["outcome"] == "skip"]
    result = "FAIL" if fails else "PASS" if npass else "NOT-TESTED"
    reason = fails[0][1]["reason"] if fails else (skips[0][1]["reason"] if skips and not npass else "")
    # Sevak TF-004: a unit pass does not stand in for a row's on-app tests when they were all skipped
    app = [x for x in o.values() if x.get("source") == "browser"]
    if result == "PASS" and app and all(x["outcome"] == "skip" for x in app):
        why = next((x["reason"] for x in app if x["reason"]), "the test was skipped")
        result = "NOT-TESTED"
        reason = ("on-app test skipped (" + why + "); a unit test does not measure on-app acceptance")[:200]
    reqs[rid] = {"result": result, "source": sources.get(rid, ""), "tests": [n for n, x in o.items() if x["outcome"] != "skip"],
                 "skipped": [n for n, _ in skips], "passed": npass, "failed": len(fails), "reason": reason,
                 "screenshot": fails[0][1].get("screenshot", "") if fails else "", "outcomes": o}
json.dump({"reqs": reqs, "browser": browser, "unit": unit, "merged_from": parts, "superseded": superseded},
          open(os.environ["TF_OUT"], "w"), indent=1)
p = sum(1 for r in reqs.values() if r["result"] == "PASS"); f = sum(1 for r in reqs.values() if r["result"] == "FAIL")
ns = sum(1 for r in reqs.values() if r["result"] == "NOT-TESTED")
print(f"merged {len(parts)} part(s): rows with a test: {len(reqs)} — {p} PASS, {f} FAIL, {ns} NOT-TESTED (every clause skipped)"
      + (f" (browser {browser['passed']}/{browser['tests']} tests passed, {browser['skipped']} skipped)" if browser["ran"] else "")
      + (f"; {superseded} test(s) ran again in a later part, and the later run stands" if superseded else ""))
for rid, r in sorted(reqs.items()):
    if r["result"] == "FAIL":
        print(f"  FAIL {rid} — {r['reason']}" + (f" — {r['screenshot']}" if r["screenshot"] else ""))
print(f"JSON: {os.environ['TF_OUT']}")
PY
  exit 0
fi

source "$HERE/tf-lock.sh"; tf_take_lock "verify-tests${PART:+ $PART}"   # one browser check at a time (TF-048)
PWJSON="tests/.artifacts/verify/playwright${PART:+-$PART}.json"; PWLOG="tests/.artifacts/verify/playwright${PART:+-$PART}.log"; UNITLOG=""; UNITLINE=""
ran_any=0

if [[ $BROWSER -eq 1 ]]; then
  # A desktop head is reached over its debugging address (tf-verify-boot.sh prints mode=cdp). The tests
  # get it as CDP_URL as well as BASE_URL: Lekhak's helper fell back to its own default port and every
  # desktop test failed after ten minutes (Lekhak TF-021). --base is that address when it answers
  # /json/version; without --base, boot.json's url when its mode is cdp.
  CDPURL=""
  if [[ -n "$BASE" ]]; then
    curl -s -m 3 "${BASE%/}/json/version" 2>/dev/null | grep -q webSocketDebuggerUrl && CDPURL="${BASE%/}"
  elif [[ -f tests/.artifacts/verify/boot.json ]]; then
    CDPURL="$(python3 -c 'import json,sys
b = json.load(open(sys.argv[1]))
print(b.get("url", "") if b.get("mode") == "cdp" and not b.get("stopped") else "")' tests/.artifacts/verify/boot.json 2>/dev/null)"
    [[ -n "$CDPURL" ]] && BASE="$CDPURL"
  fi
  # A Mac Catalyst head (boot.json mode=appium) is reached through Appium: its tests get APPIUM_URL
  # TF_BUNDLE_ID and TF_APP_PATH, and open their session with .tfcore/utils/tf-appium.mjs.
  APPIUMURL=""; BUNDLEID=""; APPPATH=""
  [[ -f tests/.artifacts/verify/boot.json ]] && read -r APPIUMURL BUNDLEID APPPATH < <(python3 -c 'import json,sys
b = json.load(open(sys.argv[1]))
print(b.get("url", ""), b.get("bundle_id", ""), b.get("app_path", "")) if b.get("mode") == "appium" and not b.get("stopped") else print()' tests/.artifacts/verify/boot.json 2>/dev/null)
  if ls tests/verify/*.spec.* >/dev/null 2>&1 || ls tests/verify/**/*.spec.* >/dev/null 2>&1; then
    # --base reaches the tests only as BASE_URL, which Playwright never reads by itself. When neither
    # the config nor a spec reads it, every test opens the config's own address, where an older build
    # may still be running and pass in the new one's name (TfLens TF-031, 2026-09-11): refuse instead.
    if [[ -n "$BASE" ]] && ! grep -qs "BASE_URL" playwright.config.* tests/verify/*.spec.* tests/verify/**/*.spec.*; then
      echo "browser tests: NOT RUN — nothing reads BASE_URL, so the tests would open another address than --base $BASE; run bash .tfcore/utils/tf-verify-env.sh, which makes playwright.config.ts read it"
      rm -f "$PWJSON"
    elif [[ -n "$CDPURL" ]] && ! grep -qsE "env(\.|\[['\"])CDP_URL" playwright.config.* tests/verify/*.ts tests/verify/**/*.ts; then
      echo "browser tests: NOT RUN — $CDPURL is a desktop app's debugging address and no test reads CDP_URL, so they would attach to another address; make the connectOverCDP helper read process.env.CDP_URL first"
      rm -f "$PWJSON"
    elif node -e "require.resolve('@playwright/test')" >/dev/null 2>&1; then
      PWARGS=(--reporter=json); [[ -n "$SHARD" ]] && PWARGS+=("--shard=$SHARD")
      # (the block below ends in SCOPEPY, not PY: tests/regression lifts the PY blocks out verbatim)
      # Lekhak TF-017: a verify of a list of ids runs only the browser tests carrying those ids, and
      # none when no row in scope has a screen and no file under tests/verify/ names one of them. A
      # verify of one no-screen NFR row ran the whole suite and was stopped at 30 minutes. ui,
      # functional and all run everything; so do --spec, --all-specs and a run without list.json.
      SCOPE=""
      [[ $ALLSPECS -eq 0 && ${#SPECS[@]} -eq 0 && -f "$LIST" ]] && SCOPE="$(python3 - "$LIST" <<'SCOPEPY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
if str(d.get("scope", "")).strip().lower() in ("", "ui", "functional", "all"):
    sys.exit(0)
rows = d.get("rows", [])
ids = [r["id"] for r in rows if r.get("id")]
if ids:
    print(("screen " if any(r.get("screen") for r in rows) else "none ") + "|".join(ids))
SCOPEPY
)"
      if [[ "$SCOPE" == none\ * ]] && ! grep -rqsE "${SCOPE#none }" tests/verify; then
        echo "browser tests: skipped — no row in scope (${SCOPE#none }) has a screen and no file under tests/verify/ names one; its tests are unit tests (--all-specs runs every spec anyway)"
        rm -f "$PWJSON"
      else
        [[ -n "$SCOPE" ]] && PWARGS+=(--grep "${SCOPE#* }")
        APPIUM_URL="$APPIUMURL" TF_BUNDLE_ID="$BUNDLEID" TF_APP_PATH="$APPPATH" CDP_URL="$CDPURL" BASE_URL="$BASE" PLAYWRIGHT_JSON_OUTPUT_NAME="$PWJSON" npx playwright test "${PWARGS[@]}" ${SPECS[@]+"${SPECS[@]}"} > "$PWLOG" 2>&1
        echo "browser tests: ran${SHARD:+ shard $SHARD}${SPECS:+ (${#SPECS[@]} spec argument(s))}${SCOPE:+ only the tests carrying ${SCOPE#* } (the scope in $LIST)} (log $PWLOG)"; ran_any=1
      fi
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
  tf_read_lines TESTPROJ < <(find tests -name '*.csproj' -not -path 'tests/.artifacts/*' -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' 2>/dev/null | sort)
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
    # the stamp sits on the project's own drive: one in /tmp takes its time from WSL's clock and the
    # report on /mnt/c from Windows', which drift apart, so a fresh report could read as older (2026-10-02)
    mkdir -p tests/.artifacts; STAMP="$(mktemp tests/.artifacts/.unit-stamp.XXXXXX)"
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
                                      "reason": "", "screenshot": "", "outcomes": {}})
    # each test's own outcome, so a merge can let a later run of the same test stand (Lekhak TF-007),
    # and where it ran, so a unit pass never stands in for a skipped on-app test (Sevak TF-004)
    r["outcomes"][name] = {"outcome": outcome, "reason": (reason or "")[:200], "screenshot": shot, "source": source}
    if r["source"] != source:
        r["source"] = "browser+unit"
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
        # a pass has no reason: every non-failure was once written "unit test skipped" (Lekhak TF-018)
        for rid in set(ID.findall(name)):
            add(rid, outcome, name, "unit",
                "unit test failed: " + name[:120] if outcome == "fail"
                else "unit test skipped: " + name[:120] if outcome == "skip" else "")
# Sevak TF-004: a row that has an on-app test is accepted on the app. When every on-app test of the
# row was skipped (`test.skip()`: not observable on this host) and none failed, a passing unit test
# with the same id does not measure it: the row is NOT-TESTED, with the skip's reason. A failure, from
# either side, still makes it FAIL; a row with no on-app test is graded on its unit tests as before.
for rid, r in reqs.items():
    app = [x for x in r["outcomes"].values() if x.get("source") == "browser"]
    if app and all(x["outcome"] == "skip" for x in app) and r["result"] == "PASS":
        why = next((x["reason"] for x in app if x["reason"]), "the test was skipped")
        r["result"] = "NOT-TESTED"
        r["reason"] = ("on-app test skipped (" + why + "); a unit test does not measure on-app acceptance")[:200]
unit["passed"] = sum(1 for r in reqs.values() if r["source"] == "unit" and r["result"] == "PASS")
unit["failed"] = sum(1 for r in reqs.values() if r["source"] == "unit" and r["result"] == "FAIL")
unit["not_tested"] = sum(1 for r in reqs.values() if r["source"] == "unit" and r["result"] == "NOT-TESTED")

import datetime
ran_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump({"reqs": reqs, "browser": browser, "unit": unit, "ran_at": ran_at}, open(os.environ["TF_OUT"], "w"), indent=1)
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

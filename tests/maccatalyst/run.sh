#!/usr/bin/env bash
# tests/maccatalyst/run.sh — self-test for the Mac Catalyst head of the verify scripts (2026-10-07).
# Writes the fixture app (tests/maccatalyst/make-app.sh: four Shell tabs, one good, one with a
# list, one with an empty list, one with two buttons on top of each other) and checks:
#   1. tf-verify-boot.sh   picks the maccatalyst head unasked on a Mac, builds, starts the app,
#                          prints BOOTED mode=appium with the bundle id
#   2. tf-verify-screens.sh --appium  Home and Posts OK; Empty render EMPTY (zero-rows); Overlap
#                          visual FAIL (overlap) and render EMPTY (an empty label); a screenshot per
#                          screen the size of the app's window, not of the display
#   3. tf-appium.mjs       an acceptance-style session finds a control by AutomationId and clicks it
#   4. tf-verify-verdict.sh  REQ-UI-001/002 pass render and visual, 003 and 004 RENDER-FAIL
#   5. tf-verify-boot.sh stop  no copy of the app is left running (Appium relaunches it under a
#                          new pid, so this proves stop goes by the .app, not the boot pid)
#   6. a Blazor Hybrid head (make-hybrid.sh): boots with webview=yes; the check runs without control
#      names, Home OK, Crowded visual FAIL, Broken render ERROR (the error bar); the verdict writes
#      "control names not measured"; stop leaves nothing running
# Before all that, on any machine with node (Linux CI included): the grading itself, over the saved
# element trees in tests/maccatalyst/sources/ (--from-source): overlap found, the error bar found,
# "no window" said plainly, a text cut off by its cell and a scrolled log line not read as overlaps.
# The live part needs a Mac with Xcode, the MAUI workload, and Appium with the mac2 driver
# (docs/TechieFlow-Setup.md §0a, §0b step 3); anywhere else it prints SKIP. The first run takes minutes.
# Run: bash tests/maccatalyst/run.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $*"; }
bad() { fail=$((fail+1)); echo "FAIL $*"; }
check() { if [[ "$2" == 0 ]]; then ok "$1"; else bad "$1"; fi; }
has() { grep -q -- "$2" <<<"$1"; echo $?; }
done_() { echo "maccatalyst self-test: $pass passed, $fail failed${1:+ ($1)}"; [[ $fail -eq 0 ]]; exit $?; }

# ---- 0a. tf-maccatalyst-check.sh, on hand-made projects (any machine: it only reads files) --------
K="$ROOT/tests/.artifacts/maccatalyst-rules"; rm -rf "$K"
mkproj() { # name manifest(yes|no) delegate(yes|no) keychain(none|bare|debug|profile)
  local d="$K/$1/src/App" e
  mkdir -p "$d/Platforms/MacCatalyst"
  { echo '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFrameworks>net10.0-maccatalyst</TargetFrameworks><UseMaui>true</UseMaui>'
    [[ "$4" == profile ]] && echo '<CodesignProvisioningProfile>Dev</CodesignProvisioningProfile>'
    [[ "$4" == debug ]] && echo '<CodesignEntitlements>Platforms\MacCatalyst\Entitlements.plist</CodesignEntitlements><CodesignEntitlements Condition="Debug">Platforms\MacCatalyst\Entitlements.Debug.plist</CodesignEntitlements>'
    echo '</PropertyGroup></Project>'; } > "$d/App.csproj"
  if [[ "$2" == yes ]]; then
    printf '%s\n' '<plist><dict><key>UIApplicationSceneManifest</key><dict><key>UISceneConfigurations</key><dict>' \
      '<key>UIWindowSceneSessionRoleApplication</key><array><dict><key>UISceneDelegateClassName</key>' '<string>SceneDelegate</string></dict></array></dict></dict></dict></plist>' > "$d/Platforms/MacCatalyst/Info.plist"
  else echo '<plist><dict></dict></plist>' > "$d/Platforms/MacCatalyst/Info.plist"; fi
  [[ "$3" == yes ]] && echo '[Register("SceneDelegate")] public class SceneDelegate : MauiUISceneDelegate { }' > "$d/Platforms/MacCatalyst/AppDelegate.cs"
  e='<plist><dict><key>keychain-access-groups</key><array><string>x</string></array></dict></plist>'
  [[ "$4" != none ]] && echo "$e" > "$d/Platforms/MacCatalyst/Entitlements.plist"
  [[ "$4" == debug ]] && echo '<plist><dict></dict></plist>' > "$d/Platforms/MacCatalyst/Entitlements.Debug.plist"
  return 0
}
rules() { (cd "$K/$1" && bash "$ROOT/.tfcore/utils/tf-maccatalyst-check.sh" 2>&1; echo "exit=$?"); }
mkproj good yes yes none; mkproj nomanifest no no none; mkproj nodelegate yes no none
mkproj keychain yes yes bare; mkproj keydebug yes yes debug; mkproj keyprofile yes yes profile
out="$(rules good)";       check "rules: manifest and delegate in place is OK" "$(has "$out" "^OK   src/App/App.csproj")"
out="$(rules nomanifest)"; check "rules: no scene manifest is a FAIL, exit 1" "$(grep -q "FAIL .*has no UIApplicationSceneManifest" <<<"$out" && grep -q "exit=1" <<<"$out"; echo $?)"
out="$(rules nodelegate)"; check "rules: a manifest naming an unregistered delegate is a FAIL" "$(has "$out" "FAIL .*names the scene delegate SceneDelegate")"
out="$(rules keychain)";   check "rules: keychain with no profile is a WARN, exit 0" "$(grep -q "WARN .*keychain-access-groups" <<<"$out" && grep -q "exit=0" <<<"$out"; echo $?)"
out="$(rules keydebug)";   check "rules: a Debug entitlements file without the keychain is OK" "$(has "$out" "^OK ")"
out="$(rules keyprofile)"; check "rules: a provisioning profile is OK" "$(has "$out" "^OK ")"

# ---- 0. the grading, from saved element trees (any machine with node) --------------------------
if command -v node >/dev/null 2>&1; then
  O="$ROOT/tests/.artifacts/maccatalyst-offline"; mkdir -p "$O"
  SRC="$(ls "$HERE"/sources/*.xml | paste -sd, -)"
  out="$(node "$ROOT/.tfcore/utils/tf-verify-native.mjs" --from-source "$SRC" --no-names --boot /nonexistent --json-out "$O/web.json" --shots-dir "$O/shots" 2>&1)"
  check "offline: overlapping buttons are visual FAIL" "$(has "$out" "^FAIL overlap .*Button \"Save\" overlaps Button \"Cancel\"")"
  check "offline: the error bar is render ERROR" "$(has "$out" "^FAIL error-bar .*render ERROR.*error bar is showing")"
  check "offline: no window is said plainly" "$(has "$out" "no-window .*the app has no window open")"
  check "offline: a scrolled log line is not an overlap in a web view" "$(has "$out" "^OK   scrolled-text")"
  check "offline: every screen records the names as not measured" "$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if d['anchors_not_measured'] and all(s.get('anchors_not_measured') for s in d['screens']) else 1)" "$O/web.json"; echo $?)"
  out="$(node "$ROOT/.tfcore/utils/tf-verify-native.mjs" --from-source "$HERE/sources/clipped-text.xml" --boot /nonexistent --json-out "$O/native.json" --shots-dir "$O/shots" 2>&1)"
  check "offline: a text cut off by its cell is not an overlap (native rules, text compared)" "$(has "$out" "^OK   clipped-text")"
else
  echo "SKIP offline cases: node is not installed"
fi

[[ "$(uname -s)" == Darwin ]] || done_ "live part skipped: not a Mac"
command -v appium >/dev/null 2>&1 || done_ "live part skipped: appium is not installed (§0b step 3)"
appium driver list --installed 2>&1 | grep -q mac2 || done_ "live part skipped: the mac2 driver is not installed (§0b step 3)"
F="$ROOT/tests/.artifacts/maccatalyst-fixture"
bash "$HERE/make-app.sh" "$F" >/dev/null || { echo "could not write the fixture"; exit 2; }
mkdir -p "$F/.tfcore" && ln -sfn "$ROOT/.tfcore/utils" "$F/.tfcore/utils"
cd "$F" || exit 2
export TF_METRICS_ROOT="$F"; unset CLAUDE_PROJECT_DIR; export TF_PROJECT_DIR="$F"
U=".tfcore/utils"; V="tests/.artifacts/verify"
trap 'bash $U/tf-verify-boot.sh stop >/dev/null 2>&1' EXIT

# ---- 1. boot ----------------------------------------------------------------------------------
out="$(bash $U/tf-verify-boot.sh start --dry-run 2>&1)"
check "boot picks the maccatalyst head unasked" "$(has "$out" "PICK head=maccatalyst project=src/TfMacFixture/TfMacFixture.csproj")"
out="$(bash $U/tf-verify-boot.sh start 2>&1)"; rc=$?; echo "     $out" | cut -c1-200
check "boot reports BOOTED mode=appium (exit $rc)" "$(has "$out" "BOOTED head=maccatalyst mode=appium")"
check "boot names the bundle id" "$(has "$out" "bundle=com.techieflow.macfixture")"
AURL="$(python3 -c 'import json;print(json.load(open("tests/.artifacts/verify/boot.json"))["url"])')"

# ---- 2. screens -------------------------------------------------------------------------------
out="$(bash $U/tf-verify-screens.sh --list $V/list.json --appium "$AURL" 2>&1)"; rc=$?; echo "$out" | sed 's/^/     /'
check "screens exits 5 (some screens fail)" "$([[ $rc == 5 ]]; echo $?)"
check "Home OK" "$(has "$out" "^OK   Home")"
check "Posts OK" "$(has "$out" "^OK   Posts")"
check "Empty: the list with no rows is render EMPTY" "$(has "$out" "Empty .*render EMPTY.*\"empty-list\" (CollectionView) has no rows")"
check "Overlap: the two buttons are visual FAIL" "$(has "$out" "Overlap .*visual FAIL.*save overlaps cancel")"
check "Overlap: the empty label is render EMPTY" "$(has "$out" "anchored control \"status\" (StaticText) is empty")"
size="$(python3 - "$V/screens.json" <<'PY'
import json, struct, sys
d = json.load(open(sys.argv[1]))
s = d["screens"][0]["widths"][0]
with open(s["screenshot"], "rb") as f:
    head = f.read(24)
w, h = struct.unpack(">II", head[16:24])
# a window screenshot has the size of the window (or twice it, on a Retina display); a display shot is larger
print("ok" if (w, h) in ((s["width"], s["height"]), (2 * s["width"], 2 * s["height"])) else f"{w}x{h} vs window {s['width']}x{s['height']}")
PY
)"
check "the screenshot is the app's window, not the display ($size)" "$([[ "$size" == ok ]]; echo $?)"

# ---- 3. an acceptance-style session -----------------------------------------------------------
out="$(APPIUM_URL="$AURL" TF_BUNDLE_ID=com.techieflow.macfixture TF_APP_PATH="$(python3 -c 'import json;print(json.load(open("tests/.artifacts/verify/boot.json"))["app_path"])')" node --input-type=module -e "
import { openSession } from '$ROOT/.tfcore/utils/tf-appium.mjs';
const s = await openSession(process.env.APPIUM_URL, { bundleId: process.env.TF_BUNDLE_ID, appPath: process.env.TF_APP_PATH });
try { await s.click(await s.find('-ios predicate string', \"elementType == 9 AND label == 'Home'\")); await s.click(await s.find('accessibility id', 'refresh')); console.log('CLICKED'); }
finally { await s.close(); }" 2>&1)"
check "tf-appium.mjs finds a control by AutomationId and clicks it" "$(has "$out" "CLICKED")"

# ---- 4. verdict -------------------------------------------------------------------------------
out="$(bash $U/tf-verify-verdict.sh FxMac 2>&1)"; echo "$out" | grep -E "REQ-UI" | sed 's/^/     /' | cut -c1-200
check "verdict: REQ-UI-003 RENDER-FAIL" "$(has "$out" "REQ-UI-003.*RENDER-FAIL")"
check "verdict: REQ-UI-004 RENDER-FAIL" "$(has "$out" "REQ-UI-004.*RENDER-FAIL")"
check "verdict: REQ-UI-001 does not fail render or visual" "$(grep "REQ-UI-001" <<<"$out" | grep -qE "RENDER-FAIL|VISUAL-FAIL|BUILD-FAIL"; [[ $? == 1 ]]; echo $?)"

# ---- 5. stop ----------------------------------------------------------------------------------
bash $U/tf-verify-boot.sh stop >/dev/null 2>&1; sleep 1
check "stop leaves no copy of the app running" "$(pgrep -f "TfMacFixture.app/Contents/MacOS" >/dev/null; [[ $? == 1 ]]; echo $?)"
trap - EXIT

# ---- 6. a Blazor Hybrid head, without control names (owner decision A) ----------------------
H="$ROOT/tests/.artifacts/maccatalyst-hybrid"
bash "$HERE/make-hybrid.sh" "$H" >/dev/null || { echo "could not write the hybrid fixture"; exit 2; }
mkdir -p "$H/.tfcore" && ln -sfn "$ROOT/.tfcore/utils" "$H/.tfcore/utils"
cd "$H" || exit 2
export TF_METRICS_ROOT="$H" TF_PROJECT_DIR="$H"
trap 'bash $U/tf-verify-boot.sh stop >/dev/null 2>&1' EXIT
out="$(bash $U/tf-verify-boot.sh start 2>&1)"; rc=$?; echo "     $out" | cut -c1-200
check "hybrid: boots with webview=yes (exit $rc)" "$(has "$out" "BOOTED head=maccatalyst mode=appium .*webview=yes")"
out="$(bash $U/tf-verify-screens.sh --list $V/list.json --appium "$AURL" 2>&1)"; echo "$out" | sed 's/^/     /' | cut -c1-200
check "hybrid: Home OK without names" "$(has "$out" "^OK   Home .*names not measured")"
check "hybrid: Crowded's buttons are visual FAIL" "$(has "$out" "Crowded .*visual FAIL.*Button \"Save\" overlaps Button \"Cancel\"")"
check "hybrid: Broken shows the error bar, render ERROR" "$(has "$out" "Broken .*render ERROR.*error bar is showing")"
out="$(bash $U/tf-verify-verdict.sh FxHybrid 2>&1)"; echo "$out" | grep -E "REQ-UI" | sed 's/^/     /' | cut -c1-200
check "hybrid verdict: the Remark says the names were not measured" "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));r=[x for x in d["rows"] if x["id"]=="REQ-UI-101"][0];sys.exit(0 if "Home renders and looks right (names not measured on a Mac)" in r["remark"] else 1)' $V/verdicts.json; echo $?)"
check "hybrid verdict: REQ-UI-103 RENDER-FAIL" "$(has "$out" "REQ-UI-103.*RENDER-FAIL")"
bash $U/tf-verify-boot.sh stop >/dev/null 2>&1; sleep 1
check "hybrid: stop leaves no copy of the app running" "$(pgrep -f "TfMacHybrid.app/Contents/MacOS" >/dev/null; [[ $? == 1 ]]; echo $?)"
trap - EXIT
done_

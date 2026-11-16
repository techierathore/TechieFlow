#!/usr/bin/env bash
# tf-mac-host-check.sh — what stands between this Mac and a mac2 session, in one line that names its fix.
#
#   bash .tfcore/utils/tf-mac-host-check.sh                                 before the build
#   bash .tfcore/utils/tf-mac-host-check.sh --session "<reason>" [<stage>] [<appium log>]   after a session that did not open
#
# tf-verify-boot.sh calls both forms for a Mac Catalyst head. Moved out of that script on 2026-11-15
# (TrStudio TF-001; the boot script is at its size limit). It reads the tools on PATH and the log it is
# handed, nothing else, so its test (tests/faults/run.sh ts_001) runs on any machine with stand-in tools.
#
# Before the build: prints the reason and exits 1, or prints nothing and exits 0. Two set-up faults of a
# fresh macOS 27 / Xcode 27 machine, each of which stops every mac2 session after a build of minutes with
# an error that does not name its fix:
#   1. mac2 turns Automation Mode on for each session; when macOS wants a password for that, it never
#      comes and the session fails "Timed out while enabling automation mode". `automationmodetool` says
#      so, in capitals on macOS 26 ("This device REQUIRES user authentication") and in small letters on
#      macOS 27.2 ("requires"). Until 2026-11-15 only the capitals matched, so on 27.2 the boot built the
#      app, the driver's helper stopped with xcodebuild code 65, and the reason pointed at Accessibility.
#   2. mac2 builds its WebDriverAgentMac with the Xcode on this Mac. Before 4.1.1 that build fails under
#      Xcode 27 (deployment target 10.15 below its 12.0 minimum, xcodebuild exit 65). An `appium driver
#      update mac2` leaves the driver unloadable ("Cannot find package 'appium'"), so the fix named is to
#      uninstall and install again.
# --session: prints "; <the fix>" for the reason a failed session gave, or nothing. Automation Mode is
# looked for in the reason and in the Appium log, where the driver's helper says it in its own words.
set -u
AUTO="sudo automationmodetool enable-automationmode-without-authentication"
REINSTALL="appium driver uninstall mac2; appium driver install mac2"
if [[ "${1:-}" == --session ]]; then
  why="${2:-}"; stage="${3:-}"; log="${4:-}"
  if grep -qi 'automation mode' <<<"$why" || { [[ -n "$log" && -f "$log" ]] && grep -qi 'enabling automation mode' "$log"; }; then
    echo "; run once, with an administrator password: $AUTO"
  elif grep -qE 'Cannot find package|Could not find a driver|xcodebuild|code 65' <<<"$why"; then
    echo "; the mac2 driver does not load or cannot build its helper: $REINSTALL"
  elif [[ "$stage" == session ]]; then
    echo "; a mac2 session that cannot start is usually a permission: System Settings > Privacy & Security > Accessibility (the terminal, and WebDriverAgentRunner-Runner)"
  fi
  exit 0
fi
if command -v automationmodetool >/dev/null 2>&1 && automationmodetool 2>&1 | grep -qi '^This device requires user authentication'; then
  echo "macOS asks for a password before Automation Mode comes on, so no mac2 session can open. Run once, with an administrator password: $AUTO"; exit 1
fi
if command -v appium >/dev/null 2>&1; then
  M2="$(appium driver list --installed --json 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("mac2", {}).get("version", ""))
except Exception: print("?")' 2>/dev/null)"
  XMAJ="$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9]*\).*/\1/p' | head -1)"
  if [[ -z "$M2" ]]; then
    echo "Appium's mac2 driver is not installed. Run: appium driver install mac2"; exit 1
  elif [[ "$M2" != "?" && "${XMAJ:-0}" -ge 27 ]] && python3 -c 'import sys
v = tuple(int(x) for x in sys.argv[1].split("-")[0].split(".")[:3])
sys.exit(0 if v < (4, 1, 1) else 1)' "$M2"; then
    echo "the mac2 driver $M2 cannot build its helper with Xcode $XMAJ (4.1.1 is the first that can). Run: $REINSTALL"; exit 1
  fi
fi
exit 0

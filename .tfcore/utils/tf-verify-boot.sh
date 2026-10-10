#!/usr/bin/env bash
# tf-verify-boot.sh — start the application for a verify, reach it, and stop it (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-boot.sh start [--head web|windows|static] [--project <csproj>] [--dry-run]
#                                              [--port N] [--config Release] [--static <dir>] [--probe-path /healthz]
#                                              [--environment Development]   (web: ASPNETCORE_ENVIRONMENT)
#   bash .tfcore/utils/tf-verify-boot.sh stop [--port N]
#   bash .tfcore/utils/tf-verify-boot.sh status [--port N]
#
# Heads:
#   web      a project on Microsoft.NET.Sdk.Web: published by `tf-build.sh publish` (its rungs, one
#            build at a time) into tests/.artifacts/verify/run-<port>/, and that copy is run on the
#            side that built it, reading its settings from the project folder as `dotnet run` does.
#            Builders side by side never serve each other's half-written build (TF-043). A standalone
#            WebAssembly project is still started with `dotnet run`. Prints BOOTED mode=base url=….
#   windows  a MAUI Blazor Hybrid head (UseMaui + a net*-windows target): started Windows-side with
#            WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222, the DevTools port
#            relayed to every interface by tf-cdp-relay.ps1, and reached from WSL over CDP. Prints
#            BOOTED mode=cdp url=http://<host>:9223. Proven on MyDiary, 2026-09-06.
#   static   a folder of HTML served by python3 (the framework self-test, a mockup set).
#   maccatalyst  a MAUI project with a net*-maccatalyst target, on a Mac only: built by tf-build.sh,
#            its .app started here, and reached over Appium's mac2 driver at the address in
#            core-config.yaml runtimeVerification.appium.maccatalyst.url (default
#            http://localhost:4723; a local Appium that is down is started and later stopped).
#            Prints BOOTED mode=appium url=<appium> bundle=<id>. An SDK that names an older Xcode
#            is built again with -p:ValidateXcodeVersion=false, and the state says so. A Blazor Hybrid
#            head is driven without control names (its data-testid is not readable on a Mac): the
#            state says webview, and those rows say the name check was not measured.
#            BOOTED only once a mac2 session has opened and the app shows a window of its own, not a
#            system dialog; that window is saved as boot-<port>-window.png (Lekhak TF-026). Before the
#            build it checks the two things a fresh macOS 27 / Xcode 27 machine lacks, and names the fix:
#            Automation Mode allowed without a password, and a mac2 driver new enough for this Xcode.
#            `stop` quits the app as Cmd-Q does, and kills it only when it has not quit in 15 s.
#   android, ios: no driver ships in this framework version. NONE with that reason; their rows
#            are recorded as not verified, never as static-only passes.
# Without --head the script picks web when a web project exists, else (on a Mac) maccatalyst when a
# MAUI project with that target exists, else windows when a MAUI project with a windows target
# exists, else NONE. --project names the project when there are several.
# The state goes to tests/.artifacts/verify/boot-<port>.json and the app log to app-<port>.log, one pair
# per app, so builders booting side by side never empty or stop each other's (TF-034); boot.json is a
# copy of the latest start's, which the verdict reads. `stop --port N` stops that app only; a bare
# `stop` stops the one boot.json names, and refuses while two or more are running. `stop` kills what
# `start` started and nothing else. Never asks anyone to start anything.
# Exit 0 booted / stopped · 2 NONE (reason printed; kind=build-error, host or no-driver) · 3 usage.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/tf-portable.sh"   # bash-4 and GNU-only spellings go through the shim (stock Mac)
DIR="tests/.artifacts/verify"; STATE="$DIR/boot.json"; LOG="$DIR/app.log"; KEYED=""
mkdir -p "$DIR"
# once the port is known: this app's own state file and log (TF-034)
keyed() { KEYED="$DIR/boot-$1.json"; LOG="$DIR/app-$1.log"; : > "$LOG"; }

PLATFORM="linux"
U="$(uname -s 2>/dev/null || echo windows)"
if [[ "$U" == Darwin* ]]; then PLATFORM="macos"
elif [[ "$U" == Linux* ]]; then grep -qiE "microsoft|wsl" /proc/version 2>/dev/null && PLATFORM="wsl"
else PLATFORM="windows"; fi

winarg() { # a Windows path as a cmd.exe argument: bare when it has no space (a quote passed
  # through the WSL bridge reaches dotnet as part of the path: "does not exist: \"C:\...\""; miss 23)
  if [[ "$1" == *" "* ]]; then printf '"%s"' "$1"; else printf '%s' "$1"; fi; }
json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

write_state() { # head mode url pids rung project reason kind
  TF_BOOT_FILES="$STATE $KEYED" TF_BOOT_LOG="$LOG" python3 - "$@" <<'PY'
import json, os, sys, datetime
head, mode, url, pids, rung, project, reason, kind = sys.argv[1:9]
s = {"head": head, "mode": mode, "url": url, "pids": [int(p) for p in pids.split() if p.isdigit()],
     "rung": rung, "project": project, "reason": reason, "reason_kind": kind, "stopped": False,
     "platform": sys.argv[9] if len(sys.argv) > 9 else "", "log": os.environ["TF_BOOT_LOG"],
     "started": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
for f in os.environ["TF_BOOT_FILES"].split():
    json.dump(s, open(f, "w"), indent=1)
PY
}
set_state() { # key value-as-JSON: one more field on this start's state files
  TF_BOOT_FILES="$STATE $KEYED" python3 -c 'import json,os,sys
for p in os.environ["TF_BOOT_FILES"].split():
    s=json.load(open(p)); s[sys.argv[1]]=json.loads(sys.argv[2]); json.dump(s,open(p,"w"),indent=1)' "$1" "$2"
}

find_projects() { # prints csproj paths under src/, source/, the root and one level down; never tests
  find . -maxdepth 4 -name '*.csproj' -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' \
       -not -path './tests/*' -not -path '*/test/*' -not -path '*Tests/*' -not -path '*.Tests/*' 2>/dev/null | sed 's#^\./##' | sort
}
is_web()  { grep -qE 'Microsoft\.NET\.Sdk\.Web|Microsoft\.NET\.Sdk\.BlazorWebAssembly' "$1"; }
is_maui_win() { grep -qiE '<UseMaui>[[:space:]]*true|Microsoft\.NET\.Sdk\.Maui' "$1" && grep -qE 'net[0-9.]+-windows' "$1"; }
is_maui_mac() { grep -qiE '<UseMaui>[[:space:]]*true|Microsoft\.NET\.Sdk\.Maui' "$1" && grep -qE 'net[0-9.]+-maccatalyst' "$1"; }

poll_http() { # url seconds pid-to-watch(optional) -> 0 when it answers
  local url="$1" secs="$2" pid="${3:-}" i=0 code
  while [[ $i -lt $secs ]]; do
    code="$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$url" 2>/dev/null || true)"
    # Any HTTP answer means the app is serving; this asks whether it is up, not whether the page is
    # right. A Web API with nothing at / answers 404, and was polled for 120 s, called "not brought up"
    # and stopped while its log said "Application started" (AppManager TF-004).
    [[ "$code" =~ ^[1-5][0-9][0-9]$ ]] && return 0
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then return 1; fi
    sleep 2; i=$((i+2))
  done
  return 1
}
WRONG_RUNG='NETSDK1178|Microsoft\.(iOS|Android|MacCatalyst|tvOS)\.Sdk|Workload ID|WindowsAppSDK|command not found|No such file or directory|workload.*not installed'
CODE_ERR='error (CS|RZ|BL|XC|XLS)[0-9]{3,5}|error MSB[0-9]{4}: .*(does not exist|could not be found)|error NU1'

cmd="${1:-}"; shift || true
SPORT=""; [[ "${1:-}" == "--port" && "$cmd" != "start" ]] && SPORT="${2:-}"
case "$cmd" in
  status) f="$STATE"; [[ -n "$SPORT" ]] && f="$DIR/boot-$SPORT.json"
          if [[ -f "$f" ]]; then cat "$f"; else echo "NONE no boot state${SPORT:+ for port $SPORT}"; fi; exit 0 ;;
  stop)
    if [[ -n "$SPORT" ]]; then
      [[ -f "$DIR/boot-$SPORT.json" ]] || { echo "STOPPED nothing was started on port $SPORT"; exit 0; }
    else
      [[ -f "$STATE" ]] || { echo "STOPPED nothing was started"; exit 0; }
      # a bare stop while several apps run could stop another builder's: name the port instead
      live="$(python3 - "$DIR" <<'PY'
import glob, json, os, re, sys
out = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], "boot-*.json"))):
    try:
        s = json.load(open(f))
    except Exception:
        continue
    alive = False
    for p in s.get("pids", []):
        try:
            os.kill(p, 0)
            alive = True
        except Exception:
            pass
    if not s.get("stopped") and alive:
        out.append(re.sub(r"^boot-(.+)[.]json$", r"\1", os.path.basename(f)))
print(" ".join(out))
PY
)"
      if [[ $(wc -w <<<"$live") -ge 2 ]]; then
        echo "NOT-STOPPED $(( $(wc -w <<<"$live") )) apps are running (ports ${live// /, }); stop yours with: bash .tfcore/utils/tf-verify-boot.sh stop --port <n>"; exit 2
      fi
    fi
    python3 - "$DIR" "$SPORT" <<'PY'
import json, os, re, signal, subprocess, sys, time
d, port = sys.argv[1], sys.argv[2]
main = os.path.join(d, "boot.json")
path = os.path.join(d, f"boot-{port}.json") if port else main
s = json.load(open(path))
# A Mac Catalyst head is quit the way Cmd-Q quits it. Killed, macOS offered at the next start to reopen
# the windows of a run that "quit unexpectedly", and that dialog stood in front of the first screen
# (Lekhak TF-026). It is killed below only when it has not quit within 15 s.
if s.get("bundle_id") and s.get("app_path") and not s.get("stopped"):
    exe_dir = os.path.join(s["app_path"], "Contents", "MacOS") + os.sep
    def mac_running():
        out = subprocess.run(["ps", "-A", "-ww", "-o", "command="], capture_output=True).stdout.decode(errors="replace")
        return any(exe_dir in line for line in out.splitlines())
    if mac_running():
        bid = s["bundle_id"].replace('"', "")
        try:
            subprocess.run(["osascript", "-e", f'if application id "{bid}" is running then tell application id "{bid}" to quit'], capture_output=True, timeout=30)
        except Exception:
            pass
        for _ in range(15):
            if not mac_running():
                break
            time.sleep(1)
for pid in s.get("pids", []):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            subprocess.run(["pkill", "-" + sig.name.replace("SIG", ""), "-P", str(pid)], capture_output=True)
            os.kill(pid, sig)
        except ProcessLookupError:
            break
        except Exception:
            pass
        time.sleep(1)
image = s.get("win_image") or ""
if s.get("win_pids"):
    # this boot's own processes only (Sevak TF-003: /IM stopped every copy, another agent's included)
    for wp in s["win_pids"]:
        subprocess.run(["taskkill.exe", "/F", "/T", "/PID", str(wp)], capture_output=True)
elif image:
    # a state written before win_pids: by name, as before, unless another start of it is still up
    others = []
    for f in os.listdir(d):
        if f.startswith("boot-") and f.endswith(".json") and os.path.join(d, f) != path:
            try:
                o = json.load(open(os.path.join(d, f)))
                if o.get("win_image") == image and not o.get("stopped") and o.get("pids") != s.get("pids"):
                    others.append(f)
            except Exception:
                pass
    if not others:
        subprocess.run(["taskkill.exe", "/F", "/T", "/IM", image], capture_output=True)
if s.get("win_port"):
    ps = f"Get-NetTCPConnection -LocalPort {s['win_port']} -State Listen -ErrorAction SilentlyContinue | ForEach-Object {{ Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }}"
    subprocess.run(["powershell.exe", "-NoProfile", "-Command", ps], capture_output=True)
# An app whose starter died is nobody's child any more, so the kills above miss it and it keeps its
# port and its files. The published copy names it: stop whatever runs from run-<port>/ (TF-043).
m = re.search(r":(\d+)$", s.get("url") or "")
run_port = port or (m.group(1) if m else "")
marks = [os.path.join(os.getcwd(), d, f"run-{run_port}") + os.sep] if run_port else []
# A Mac Catalyst head: opening an Appium session starts the app again under a new process, so the
# pid written at boot is gone and the app is not; stop whatever runs from this boot's .app.
if s.get("app_path"):
    marks.append(os.path.join(s["app_path"], "Contents", "MacOS") + os.sep)
if marks:
    try:
        procs = [p for p in os.listdir("/proc") if p.isdigit()]
    except Exception:
        procs = []
    cmds = []   # (pid, command line)
    for p in procs:
        try:
            cmd = open(f"/proc/{p}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
        except Exception:
            continue
        cmds.append((int(p), cmd))
    if not procs:
        # No /proc (macOS): the same list from ps, full width so the run-<port>/ path is not cut off.
        try:
            out = subprocess.run(["ps", "-A", "-ww", "-o", "pid=,command="], capture_output=True).stdout.decode(errors="replace")
        except Exception:
            out = ""
        for line in out.splitlines():
            pid, _, cmd = line.strip().partition(" ")
            if pid.isdigit():
                cmds.append((int(pid), cmd))
    for pid, cmd in cmds:
        if any(mk in cmd for mk in marks) and pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except Exception:
                pass
s["stopped"] = True
json.dump(s, open(path, "w"), indent=1)
# the same app under its other name: boot.json and its own boot-<port>.json
twins = [main] if port else ([os.path.join(d, f"boot-{m.group(1)}.json")] if m else [])
for f in twins:
    try:
        o = json.load(open(f))
        if o.get("pids") == s.get("pids"):
            o["stopped"] = True
            json.dump(o, open(f, "w"), indent=1)
    except Exception:
        pass
print(f"STOPPED head={s.get('head')} mode={s.get('mode')} pids={s.get('pids')}")
PY
    exit 0 ;;
  start) ;;
  *) sed -n '2,39p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 3 ;;
esac

HEAD=""; PROJECT=""; PORT=""; CONFIG=""; STATIC=""; PROBE="/"; DRYRUN=0; ENVNAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment) ENVNAME="${2:-}"; shift 2 ;;   # the web head's ASPNETCORE_ENVIRONMENT (Lekhak TF-001)
    --probe-path) PROBE="${2:-/}"; [[ "$PROBE" == /* ]] || PROBE="/$PROBE"; shift 2 ;;
    --dry-run) DRYRUN=1; shift ;;   # print which project and head would boot, and stop (TF-010)
    --head) HEAD="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    --static) STATIC="${2:-}"; HEAD="static"; shift 2 ;;
    *) echo "tf-verify-boot: unknown argument $1" >&2; exit 3 ;;
  esac
done

# ---- static ---------------------------------------------------------------------------
if [[ "$HEAD" == "static" ]]; then
  [[ -d "$STATIC" ]] || { echo "NONE head=static reason=folder $STATIC does not exist"; write_state static none "" "" "" "$STATIC" "folder missing" host; exit 2; }
  PORT="${PORT:-5099}"
  if curl -s -o /dev/null -m 2 "http://localhost:$PORT/" 2>/dev/null; then
    echo "NONE head=static reason=port $PORT is already in use; stop that process or pass --port"; exit 2
  fi
  keyed "$PORT"
  nohup python3 -m http.server "$PORT" --directory "$STATIC" --bind 127.0.0.1 > "$LOG" 2>&1 &
  PID=$!
  if poll_http "http://localhost:$PORT/" 20 "$PID"; then
    write_state static base "http://localhost:$PORT" "$PID" "python3 http.server" "$STATIC" "" "" "$PLATFORM"
    echo "BOOTED head=static mode=base url=http://localhost:$PORT pid=$PID log=$LOG stop=\"bash .tfcore/utils/tf-verify-boot.sh stop --port $PORT\""; exit 0
  fi
  kill "$PID" 2>/dev/null; write_state static none "" "" "" "$STATIC" "http.server did not answer on $PORT" host
  echo "NONE head=static reason=http.server did not answer on $PORT (log $LOG)"; exit 2
fi

# ---- pick the project and the head ------------------------------------------------------
tf_read_lines ALL < <(find_projects)
WEB=(); WIN=(); MAC=()
for p in ${ALL[@]+"${ALL[@]}"}; do is_web "$p" && WEB+=("$p"); is_maui_win "$p" && WIN+=("$p"); is_maui_mac "$p" && MAC+=("$p"); done
# a Mac Catalyst head is picked unasked only on a Mac, the one host that runs it
[[ "$PLATFORM" == "macos" ]] || MAC=()
# Several web projects: the one that serves screens. The first in sorted order booted AppManager's
# external API, which has no screens, in front of its admin site (AppManager TF-010). A project
# serves screens when its own folder holds .razor or .cshtml pages, or it references a project
# built with the Razor SDK. One such project is taken and said so; several, or none, stop with the
# candidates named, because a guess between them grades the wrong app.
serves_screens() { # csproj -> 0 when it draws pages
  local d; d="$(dirname "$1")"
  find "$d" -maxdepth 3 \( -name '*.razor' -o -name '*.cshtml' \) -not -path '*/bin/*' -not -path '*/obj/*' -print -quit 2>/dev/null | grep -q . && return 0
  local ref
  while read -r ref; do
    ref="$(sed 's#\\#/#g' <<<"$ref")"
    [[ -f "$d/$ref" ]] && grep -qE 'Microsoft\.NET\.Sdk\.Razor' "$d/$ref" && return 0
  done < <(grep -oE '<ProjectReference[^>]*Include="[^"]+"' "$1" 2>/dev/null | sed -E 's/.*Include="([^"]+)".*/\1/')
  return 1
}
pick_web() { # sets PROJECT from WEB, or prints NONE and exits
  if [[ ${#WEB[@]} -le 1 ]]; then PROJECT="${WEB[0]:-}"; return; fi
  local ui=()
  for p in "${WEB[@]}"; do serves_screens "$p" && ui+=("$p"); done
  if [[ ${#ui[@]} -eq 1 ]]; then
    PROJECT="${ui[0]}"
    echo "tf-verify-boot: ${#WEB[@]} web projects; $PROJECT serves screens (.razor/.cshtml pages or a Razor SDK reference), the other(s) do not — booting it; --project names another"
  else
    write_state web none "" "" "" "" "${#WEB[@]} web projects and no single one serving screens" host "$PLATFORM"
    echo "NONE head=web reason=${#WEB[@]} web projects (${WEB[*]}) and ${#ui[@]} of them serve screens${ui[*]:+ (${ui[*]})}; name one with --project"; exit 2
  fi
}
if [[ -n "$PROJECT" ]]; then
  [[ -f "$PROJECT" ]] || { echo "NONE reason=--project $PROJECT does not exist"; exit 3; }
  if [[ -z "$HEAD" ]]; then
    is_web "$PROJECT" && HEAD=web
    [[ -z "$HEAD" && "$PLATFORM" == "macos" ]] && is_maui_mac "$PROJECT" && HEAD=maccatalyst
    [[ -z "$HEAD" ]] && is_maui_win "$PROJECT" && HEAD=windows
  fi
elif [[ -z "$HEAD" ]]; then
  if [[ ${#WEB[@]} -gt 0 ]]; then HEAD=web; pick_web
  elif [[ ${#MAC[@]} -gt 0 ]]; then HEAD=maccatalyst; PROJECT="${MAC[0]}"
  elif [[ ${#WIN[@]} -gt 0 ]]; then HEAD=windows; PROJECT="${WIN[0]}"; fi
else
  case "$HEAD" in web) pick_web ;; windows) PROJECT="${WIN[0]:-}" ;; maccatalyst) PROJECT="${MAC[0]:-}" ;; esac
fi
if [[ $DRYRUN -eq 1 ]]; then echo "PICK head=${HEAD:-none} project=${PROJECT:-none}"; exit 0; fi
case "$HEAD" in
  android|ios)
    write_state "$HEAD" none "" "" "" "${PROJECT:-}" "no driver for the $HEAD head ships in this framework version" no-driver "$PLATFORM"
    echo "NONE head=$HEAD reason=no driver for the $HEAD head ships in this framework version; its rows are recorded as not verified"; exit 2 ;;
  maccatalyst)
    [[ "$PLATFORM" == "macos" ]] || { write_state maccatalyst none "" "" "" "${PROJECT:-}" "a Mac Catalyst head runs only on a Mac" host "$PLATFORM"
      echo "NONE head=maccatalyst kind=host reason=a Mac Catalyst head runs only on a Mac, this is $PLATFORM"; exit 2; } ;;
  web|windows) ;;
  "") write_state none none "" "" "" "" "no web project and no MAUI project with a windows target found under src/, source/ or the root" host "$PLATFORM"
      echo "NONE head=none reason=no web project (Microsoft.NET.Sdk.Web) and no MAUI project with a windows target found; name one with --project"; exit 2 ;;
  *) echo "NONE reason=unknown head $HEAD"; exit 3 ;;
esac
[[ -n "$PROJECT" ]] || { write_state "$HEAD" none "" "" "" "" "no project for head $HEAD" host "$PLATFORM"; echo "NONE head=$HEAD reason=no project found for that head; name one with --project"; exit 2; }
PDIR="$(dirname "$PROJECT")"; PNAME="$(basename "$PROJECT" .csproj)"
ASM="$(grep -oE '<AssemblyName>[^<]+' "$PROJECT" 2>/dev/null | head -1 | sed 's/<AssemblyName>//')"; ASM="${ASM:-$PNAME}"
CFGARGS=(); [[ -n "$CONFIG" ]] && CFGARGS=(-c "$CONFIG")

# ---- maccatalyst (MAUI on this Mac, reached over Appium's mac2 driver) -----------------------
if [[ "$HEAD" == "maccatalyst" ]]; then
  # A Blazor Hybrid head draws its screens in a web view, and on a Mac neither data-testid nor an
  # HTML id reaches mac2 or the macOS accessibility tree (probed 2026-10-07). It is driven all the
  # same, without control names (owner decision A): the state says webview, the screen check skips
  # the name check, and the verdict writes it as not measured.
  WEBVIEW=0; grep -q 'Microsoft\.AspNetCore\.Components\.WebView\.Maui' "$PROJECT" && WEBVIEW=1
  TFM="$(grep -oE 'net[0-9.]+-maccatalyst[0-9.]*' "$PROJECT" | head -1)"
  # the endpoint the app registers (an uncommented maccatalyst: entry with a url), else this Mac
  AURL="$(python3 - <<'PY'
import re
try:
    t = open(".tfcore/core-config.yaml", encoding="utf-8").read()
except Exception:
    t = ""
m = re.search(r"(?m)^[ \t]+maccatalyst:[ \t]*(?:\{[^}\n]*url:[ \t]*([^,}\s]+)|\n[ \t]+url:[ \t]*(\S+))", t)
print((m.group(1) or m.group(2)) if m else "")
PY
)"
  AURL="${AURL:-http://localhost:4723}"; AURL="${AURL%/}"
  APORT="${AURL##*:}"; [[ "$APORT" =~ ^[0-9]+$ ]] || APORT=4723
  keyed "$APORT"
  mac_none() { # reason: a host fault found before anything was started
    write_state maccatalyst none "" "" "" "$PROJECT" "$1" host "$PLATFORM"
    echo "NONE head=maccatalyst kind=host reason=$1"; exit 2; }
  # Lekhak TF-026: two set-up faults of a fresh macOS 27 / Xcode 27 machine, each of which stopped every
  # mac2 session with an error that does not name its fix. Checked here, before a build of minutes.
  # 1. mac2 turns Automation Mode on for each session; when that needs a password it never comes, and
  #    the session fails with "Timed out while enabling automation mode".
  if command -v automationmodetool >/dev/null 2>&1 && automationmodetool 2>&1 | grep -q '^This device REQUIRES user authentication'; then
    mac_none "macOS asks for a password before Automation Mode comes on, so no mac2 session can open. Run once, with an administrator password: sudo automationmodetool enable-automationmode-without-authentication"
  fi
  # 2. mac2 builds its WebDriverAgentMac with the Xcode on this Mac. Before 4.1.1 that build fails
  #    under Xcode 27 (deployment target 10.15 below its 12.0 minimum, xcodebuild exit 65). An
  #    `appium driver update mac2` left the driver unloadable ("Cannot find package 'appium'");
  #    uninstalling and installing again is what worked.
  if command -v appium >/dev/null 2>&1; then
    M2="$(appium driver list --installed --json 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("mac2", {}).get("version", ""))
except Exception: print("?")' 2>/dev/null)"
    XMAJ="$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9]*\).*/\1/p' | head -1)"
    REINSTALL="appium driver uninstall mac2; appium driver install mac2"
    if [[ -z "$M2" ]]; then
      mac_none "Appium's mac2 driver is not installed. Run: appium driver install mac2"
    elif [[ "$M2" != "?" && "${XMAJ:-0}" -ge 27 ]] && python3 -c 'import sys
v = tuple(int(x) for x in sys.argv[1].split("-")[0].split(".")[:3])
sys.exit(0 if v < (4, 1, 1) else 1)' "$M2"; then
      mac_none "the mac2 driver $M2 cannot build its helper with Xcode $XMAJ (4.1.1 is the first that can). Run: $REINSTALL"
    fi
  fi
  ready() { curl -s -m 3 "$AURL/status" 2>/dev/null | grep -q '"ready":true'; }
  APPIUM_PID=""
  if ! ready; then
    # boot it yourself: a local Appium that is down is started here and stopped by `stop`
    if [[ "$AURL" =~ ^http://(localhost|127\.0\.0\.1): ]] && command -v appium >/dev/null 2>&1; then
      nohup appium --address 127.0.0.1 --port "$APORT" > "$DIR/appium-$APORT.log" 2>&1 < /dev/null &
      APPIUM_PID=$!; i=0
      while [[ $i -lt 60 ]] && ! ready; do sleep 2; i=$((i+2)); done
    fi
    if ! ready; then
      [[ -n "$APPIUM_PID" ]] && kill "$APPIUM_PID" 2>/dev/null
      write_state maccatalyst none "" "" "" "$PROJECT" "Appium did not answer at $AURL/status" host "$PLATFORM"
      echo "NONE head=maccatalyst kind=host reason=Appium did not answer at $AURL/status$([[ -z "$APPIUM_PID" ]] && ! command -v appium >/dev/null 2>&1 && echo '; appium is not installed (docs/TechieFlow-Setup.md §0b step 3)')"; exit 2
    fi
  fi
  stop_appium() { [[ -n "$APPIUM_PID" ]] && kill "$APPIUM_PID" 2>/dev/null; }
  # the Mac rules first (coding-standards-dotnet.md §9): a missing scene manifest is stopped here,
  # before a build that macOS 27 would end at the first window; a WARN is printed and the boot goes on
  chk="$(bash "$HERE/tf-maccatalyst-check.sh" "$PROJECT" 2>&1)"; crc=$?
  printf '%s\n' "$chk" >> "$LOG"; grep -E '^WARN' <<<"$chk" >&2
  OSMAJOR="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
  if [[ $crc -eq 1 && "${OSMAJOR:-0}" -ge 27 ]]; then
    stop_appium; first="$(grep -m1 -E '^FAIL' <<<"$chk" | sed -E 's/^FAIL [^:]+: //')"
    write_state maccatalyst none "" "" "tf-maccatalyst-check.sh" "$PROJECT" "$first" build-error "$PLATFORM"
    echo "NONE head=maccatalyst kind=build-error reason=$first (bash .tfcore/utils/tf-maccatalyst-check.sh)"; exit 2
  fi
  [[ $crc -eq 1 ]] && grep -E '^FAIL' <<<"$chk" | sed 's/^FAIL/WARN (fatal from macOS 27)/' >&2
  BARGS=(-f "$TFM" -c "${CONFIG:-Debug}")
  echo "### build $PROJECT -f $TFM" >> "$LOG"
  out="$(bash "$HERE/tf-build.sh" build "$PROJECT" -- "${BARGS[@]}" 2>&1)"; brc=$?
  # A Mac Catalyst SDK names the one Xcode it was made for, and refuses a newer one with an error
  # tf-build.sh reads as a missing workload (NOT-RUN). Built again with the check off; the state says so.
  XNOTE=""; blog="$(grep -oE 'log [^ ]+[.]log' <<<"$out" | tail -1 | cut -c5-)"
  if [[ $brc -ne 0 && -n "$blog" ]] && grep -qs 'requires Xcode' "$blog"; then
    XNOTE="$(grep -ohE 'requires Xcode [0-9.]+[.] The current version of Xcode is [0-9.]+' "$blog" | head -1)"
    printf '%s\n### again with -p:ValidateXcodeVersion=false (%s)\n' "$out" "$XNOTE" >> "$LOG"
    out="$(bash "$HERE/tf-build.sh" build "$PROJECT" -- "${BARGS[@]}" -p:ValidateXcodeVersion=false 2>&1)"; brc=$?
  fi
  printf '%s\n' "$out" >> "$LOG"
  verdict="$(grep -E '^(PASS|FAIL|NOT-RUN)' <<<"$out" | tail -1)"
  if [[ $brc -ne 0 ]]; then
    stop_appium
    kind=host; [[ $brc -eq 1 ]] && kind=build-error
    write_state maccatalyst none "" "" "tf-build.sh build -f $TFM" "$PROJECT" "${verdict:-the build failed}" "$kind" "$PLATFORM"
    echo "NONE head=maccatalyst kind=$kind reason=${verdict:-the build failed} (log $LOG)"; exit 2
  fi
  APP="$(ls -td "$PDIR/bin/${CONFIG:-Debug}/$TFM"/*.app "$PDIR/bin/${CONFIG:-Debug}/$TFM"/*/*.app 2>/dev/null | head -1)"
  if [[ -z "$APP" ]]; then
    stop_appium; write_state maccatalyst none "" "" "tf-build.sh build -f $TFM" "$PROJECT" "the build wrote no .app under $PDIR/bin/${CONFIG:-Debug}/$TFM" host "$PLATFORM"
    echo "NONE head=maccatalyst kind=host reason=the build wrote no .app under $PDIR/bin/${CONFIG:-Debug}/$TFM (log $LOG)"; exit 2
  fi
  APP="$(cd "$APP" && pwd)"
  BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)"
  EXE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null)"
  if OLD="$(pgrep -f "$APP/Contents/MacOS/$EXE" | head -1)" && [[ -n "$OLD" ]]; then
    stop_appium; write_state maccatalyst none "" "" "" "$PROJECT" "another copy of $EXE is already running (pid $OLD)" host "$PLATFORM"
    echo "NONE head=maccatalyst kind=host reason=another copy of $EXE is already running (pid $OLD), and mac2 would attach to either; stop it first"; exit 2
  fi
  MARK="$DIR/.launch-$APORT"; : > "$MARK"; ROOT_LOG="$PWD/$LOG"
  # Opened the way Finder opens it: macOS kills a sandboxed app started from its binary directly
  # ("Killed: 9", Lekhak BlogAdmin, 2026-10-07). Its output goes to the log through open's own options.
  # -ApplePersistenceIgnoreState: never offer to reopen the windows of an earlier run (Lekhak TF-026)
  OPENERR="$(open -n -o "$ROOT_LOG" --stderr "$ROOT_LOG" "$APP" --args -ApplePersistenceIgnoreState YES 2>&1)"; printf '%s\n' "$OPENERR" >> "$LOG"
  APP_PID=""; i=0
  while [[ $i -lt 10 && -z "$APP_PID" ]]; do sleep 1; i=$((i+1)); APP_PID="$(pgrep -f "$APP/Contents/MacOS/$EXE" | head -1)"; done
  i=0; while [[ -n "$APP_PID" && $i -lt 8 ]] && kill -0 "$APP_PID" 2>/dev/null; do sleep 1; i=$((i+1)); done
  if [[ -z "$APP_PID" ]] || ! kill -0 "$APP_PID" 2>/dev/null; then
    stop_appium
    crash="$(find "$HOME/Library/Logs/DiagnosticReports" -name "$EXE-*.ips" -newer "$MARK" 2>/dev/null | head -1)"
    hint=""; grep -qs NoSceneLifecycleAdoption "$crash" && hint="; macOS stops a UIKit app that has not adopted scenes: add UIApplicationSceneManifest to Platforms/MacCatalyst/Info.plist and a SceneDelegate : MauiUISceneDelegate"
    # macOS refused to start it at all (Lekhak BlogAdmin, 2026-10-07: "Launch failed", POSIX 163): a
    # locally signed build that asks for keychain-access-groups, which needs a provisioning profile
    if grep -q 'Launch failed' <<<"$OPENERR"; then
      hint="; macOS refused to start it ($(grep -oE 'Code=[0-9]+ "[^"]*"' <<<"$OPENERR" | tail -1))"
      codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q keychain-access-groups && hint="$hint: the build is signed locally (ad hoc) and asks for keychain-access-groups, which needs a provisioning profile; leave that entitlement out of Debug builds or set CodesignProvisioningProfile"
    fi
    write_state maccatalyst none "" "" "tf-build.sh build -f $TFM" "$PROJECT" "the app quit on start${crash:+ (crash report $crash)}$hint" build-error "$PLATFORM"
    echo "NONE head=maccatalyst kind=build-error reason=the app quit on start${crash:+ (crash report $crash)}$hint (log $LOG)"; exit 2
  fi
  write_state maccatalyst appium "$AURL" "$APP_PID $APPIUM_PID" "tf-build.sh build -f $TFM" "$PROJECT" "" "" "$PLATFORM"
  set_state bundle_id "$(json_escape "$BUNDLE")"
  set_state app_path "$(json_escape "$APP")"
  # Lekhak TF-026: a running process and an answering Appium are not a boot. A mac2 session has to open
  # and find the app's own window on view, not a system dialog, before this says BOOTED.
  SHOT="$PWD/$DIR/boot-$APORT-window.png"
  FIRST="$(TF_A="$AURL" TF_B="$BUNDLE" TF_P="$APP" TF_S="$SHOT" node --input-type=module -e "
import { firstScreen } from '$HERE/tf-appium.mjs';
const r = await firstScreen(process.env.TF_A, { bundleId: process.env.TF_B, appPath: process.env.TF_P, shot: process.env.TF_S });
console.log(JSON.stringify(r));" 2>&1 | tail -1)"
  printf '### first screen: %s\n' "$FIRST" >> "$LOG"
  fs() { python3 -c 'import json,sys
try: print(json.loads(sys.argv[1]).get(sys.argv[2]) or "")
except Exception: print("")' "$FIRST" "$1"; }
  if [[ "$(fs ok)" != "True" ]]; then
    why="$(fs reason)"; why="${why:-$(cut -c1-200 <<<"$FIRST")}"
    fix=""
    case "$why" in
      *[Aa]utomation\ mode*) fix="; run once, with an administrator password: sudo automationmodetool enable-automationmode-without-authentication" ;;
      *"Cannot find package"*|*"Could not find a driver"*|*xcodebuild*|*"code 65"*) fix="; the mac2 driver does not load or cannot build its helper: appium driver uninstall mac2; appium driver install mac2" ;;
    esac
    [[ "$(fs stage)" == session && -z "$fix" ]] && fix="; a mac2 session that cannot start is usually a permission: System Settings > Privacy & Security > Accessibility (the terminal, and WebDriverAgentRunner-Runner)"
    bash "${BASH_SOURCE[0]}" stop --port "$APORT" >/dev/null 2>&1
    write_state maccatalyst none "" "" "tf-build.sh build -f $TFM" "$PROJECT" "the app started but its first screen was not reached: $why$fix" host "$PLATFORM"
    echo "NONE head=maccatalyst kind=host reason=the app started but its first screen was not reached: $why$fix (log $LOG)"; exit 2
  fi
  set_state first_screen "$(json_escape "$SHOT")"
  DISMISSED="$(fs dismissed)"
  [[ -n "$DISMISSED" ]] && { set_state dismissed "$(json_escape "$DISMISSED")"; echo "tf-verify-boot: $DISMISSED" >&2; }
  [[ -n "$XNOTE" ]] && set_state xcode_check "$(json_escape "off: $XNOTE")"
  [[ $WEBVIEW -eq 1 ]] && set_state webview true
  echo "BOOTED head=maccatalyst mode=appium url=$AURL bundle=$BUNDLE project=$PROJECT tfm=$TFM$([[ $WEBVIEW -eq 1 ]] && echo ' webview=yes (control names not measured)') pid=$APP_PID${APPIUM_PID:+ appium-pid=$APPIUM_PID}${XNOTE:+ xcode-check=off ($XNOTE)} window=$DIR/boot-$APORT-window.png log=$LOG stop=\"bash .tfcore/utils/tf-verify-boot.sh stop --port $APORT\""
  exit 0
fi

# ---- web ------------------------------------------------------------------------------
if [[ "$HEAD" == "web" ]]; then
  if [[ -z "$PORT" ]]; then
    LS="$PDIR/Properties/launchSettings.json"
    [[ -f "$LS" ]] && PORT="$(grep -oE 'http://localhost:[0-9]+' "$LS" | head -1 | sed 's#.*:##')"
    PORT="${PORT:-5099}"
  fi
  if curl -s -o /dev/null -m 2 "http://localhost:$PORT/" 2>/dev/null; then
    echo "NONE head=web reason=port $PORT is already in use; stop that process or pass --port"; exit 2
  fi
  URL="http://localhost:$PORT"
  keyed "$PORT"
  # TF-043. `dotnet run` served the shared bin/ and obj/, which the next builder rewrites under a
  # running app: on TfLens, 2026-09-12, four apps side by side, one sent its stylesheet as 200 with
  # 0 bytes, one answered 500, and one ran a dll older than its own source. Each looked healthy and
  # every measurement taken on it was wrong. So the app runs from a copy of its own, published by
  # tf-build.sh, which lets one build run at a time; settings, secrets and files beside the project
  # are read from the project folder, as `dotnet run` reads them.
  if ! grep -q 'Microsoft\.NET\.Sdk\.BlazorWebAssembly' "$PROJECT"; then
    ROOTDIR="$PWD"; RUN="$DIR/run-$PORT"
    rm -rf "$RUN"
    echo "### publish $PROJECT into $RUN" >> "$LOG"
    # Debug unless --config says otherwise: `dotnet publish` alone builds Release, which is not the app
    # `dotnet run` ran, and a Release publish over a Debug-built tree stamped the pages with one scope
    # and the stylesheet with another (TfLens cluster E, in TF-043)
    pub="$(bash "$HERE/tf-build.sh" publish "$PROJECT" -- -o "$RUN" -c "${CONFIG:-Debug}" 2>&1)"; prc=$?
    printf '%s\n' "$pub" >> "$LOG"
    verdict="$(grep -E '^(PASS|FAIL|NOT-RUN)' <<<"$pub" | tail -1)"
    if [[ $prc -eq 1 ]]; then
      first="$(grep -E 'error (CS|RZ|BL|XC|XLS|MSB|NU)[0-9]+' <<<"$pub" | head -1 | sed 's/^[[:space:]]*//' | cut -c1-160)"
      write_state web none "" "" "tf-build.sh publish" "$PROJECT" "build error: ${first:-$verdict}" build-error "$PLATFORM"
      echo "NONE head=web kind=build-error reason=the code does not build: ${first:-$verdict} (log $LOG)"; exit 2
    elif [[ $prc -ne 0 || ! -f "$RUN/$ASM.dll" ]]; then
      reason="${verdict:-the publish wrote no $ASM.dll into $RUN}"
      write_state web none "" "" "tf-build.sh publish" "$PROJECT" "$reason" host "$PLATFORM"
      echo "NONE head=web kind=host reason=$reason (log $LOG)"; exit 2
    fi
    # what `dotnet run` sets from the launch profile; the environment above all, which picks the
    # settings file and whether the secrets are read
    tf_read_lines LSENV < <(TF_BOOT_ENV="$ENVNAME" python3 - "$PDIR/Properties/launchSettings.json" <<'PY'
import json, os, sys
try:
    profiles = json.load(open(sys.argv[1], encoding="utf-8-sig")).get("profiles", {})
except Exception:
    profiles = {}
env = next((dict(p.get("environmentVariables") or {}) for p in profiles.values() if p.get("commandName") == "Project"), {})
env.setdefault("ASPNETCORE_ENVIRONMENT", "Development")
if os.environ.get("ASPNETCORE_ENVIRONMENT"):
    env["ASPNETCORE_ENVIRONMENT"] = os.environ["ASPNETCORE_ENVIRONMENT"]
if os.environ.get("TF_BOOT_ENV"):
    env["ASPNETCORE_ENVIRONMENT"] = os.environ["TF_BOOT_ENV"]
for k, v in env.items():
    print(f"{k}={v}")
PY
)
    WIN=""
    case "$verdict" in
      *"via cmd.exe"*|*"via winrun"*|*"via powershell.exe"*)
        WIN=1; WPD="$(winarg "$(wslpath -w "$PDIR")")"; WDLL="$(winarg "$(wslpath -w "$RUN/$ASM.dll")")"
        WWEB=""; [[ -d "$RUN/wwwroot" ]] && WWEB="--webroot $(winarg "$(wslpath -w "$RUN/wwwroot")")"
        sets=""; for kv in ${LSENV[@]+"${LSENV[@]}"}; do sets+="set $kv&& "; done
        nohup cmd.exe /c "cd /d $WPD && ${sets}dotnet $WDLL --urls $URL --contentRoot $WPD $WWEB" >> "$LOG" 2>&1 < /dev/null &
        PID=$!; label="cmd.exe /c dotnet" ;;
      *)
        runner="dotnet"; [[ "$verdict" == *"via ~/.dotnet/dotnet"* ]] && runner="$HOME/.dotnet/dotnet"
        # Lekhak TF-001. A copy run on the WSL side reads user-secrets from ~/.microsoft/usersecrets,
        # while `dotnet user-secrets set` on Windows wrote them to %APPDATA%\Microsoft\UserSecrets:
        # "Required configuration value(s) not set" on an app that starts under `dotnet run`. The
        # secrets reader looks under $APPDATA first on any system, so when only the Windows store
        # holds this project's secrets, the app is pointed at it.
        SID="$(grep -oE '<UserSecretsId>[^<]+' "$PROJECT" 2>/dev/null | head -1 | sed 's/<UserSecretsId>//')"
        if [[ -n "$SID" && ! -f "$HOME/.microsoft/usersecrets/$SID/secrets.json" ]] && [[ "$PLATFORM" == wsl || -n "${TF_WIN_APPDATA:-}" ]]; then
          WAD="${TF_WIN_APPDATA:-}"
          if [[ -z "$WAD" ]] && command -v cmd.exe >/dev/null 2>&1; then
            WAD="$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r')"; [[ -n "$WAD" ]] && WAD="$(wslpath -u "$WAD" 2>/dev/null)"
          fi
          if [[ -n "$WAD" && -f "$WAD/Microsoft/UserSecrets/$SID/secrets.json" ]]; then
            LSENV+=("APPDATA=$WAD")
            echo "tf-verify-boot: user-secrets $SID are in the Windows store only; the app reads them from $WAD/Microsoft/UserSecrets"
          fi
        fi
        WEBR=(); [[ -d "$RUN/wwwroot" ]] && WEBR=(--webroot "$ROOTDIR/$RUN/wwwroot")
        # the redirections belong to the whole background group and the group becomes the app: a group
        # left waiting on its app kept this script's output open, so a caller reading it waited for ever
        ( cd "$PDIR" || exit 1; exec env ${LSENV[@]+"${LSENV[@]}"} nohup "$runner" "$ROOTDIR/$RUN/$ASM.dll" --urls "$URL" --contentRoot "$PWD" ${WEBR[@]+"${WEBR[@]}"} ) \
            >> "$ROOTDIR/$LOG" 2>&1 < /dev/null &
        PID=$!; label="$([[ "$runner" == dotnet ]] && echo dotnet || echo '~/.dotnet/dotnet')" ;;
    esac
    if poll_http "$URL$PROBE" 120 "$PID"; then
      write_state web base "$URL" "$PID" "$label (published copy)" "$PROJECT" "" "" "$PLATFORM"
      set_state run_dir "$(json_escape "$RUN")"
      [[ -n "$WIN" ]] && set_state win_port "$PORT"
      echo "BOOTED head=web mode=base url=$URL rung=$label project=$PROJECT copy=$RUN pid=$PID log=$LOG stop=\"bash .tfcore/utils/tf-verify-boot.sh stop --port $PORT\""; exit 0
    fi
    pkill -P "$PID" 2>/dev/null; kill "$PID" 2>/dev/null
    [[ -n "$WIN" ]] && powershell.exe -NoProfile -Command "Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1
    last="$(grep -vE '^[[:space:]]*$' "$LOG" | tail -3 | tr '\n' ' ' | cut -c1-240)"
    # say what the log says: "no rung brought it up" sent a reader to the build when the app had started
    said=""; grep -q 'Now listening on' "$LOG" && said=" although its log says it is listening"
    write_state web none "" "" "$label (published copy)" "$PROJECT" "the published copy did not answer on $URL$PROBE within 120 s$said" host "$PLATFORM"
    echo "NONE head=web kind=host reason=the published copy of $PROJECT did not answer on $URL$PROBE within 120 s$said; last lines: $last (log $LOG)"; exit 2
  fi
  # a standalone WebAssembly project has no server of its own to publish: `dotnet run` serves it
  rungs=()
  case "$PLATFORM" in
    wsl) command -v dotnet >/dev/null 2>&1 && rungs+=("dotnet"); [[ -x "$HOME/.dotnet/dotnet" ]] && rungs+=("$HOME/.dotnet/dotnet"); command -v cmd.exe >/dev/null 2>&1 && rungs+=("cmd.exe") ;;
    *) rungs+=("dotnet") ;;
  esac
  [[ ${#rungs[@]} -gt 0 ]] || { write_state web none "" "" "" "$PROJECT" "no dotnet on this host" host "$PLATFORM"; echo "NONE head=web reason=no dotnet found on $PLATFORM"; exit 2; }
  tried=()
  for r in "${rungs[@]}"; do
    echo "### rung: $r" >> "$LOG"
    case "$r" in
      cmd.exe)
        WP="$(winarg "$(wslpath -w "$PROJECT")")"
        nohup cmd.exe /c "dotnet run --project $WP ${CFGARGS[*]:-} --urls $URL" >> "$LOG" 2>&1 < /dev/null &
        PID=$!; label="cmd.exe /c dotnet" ;;
      *)
        ASPNETCORE_ENVIRONMENT="${ENVNAME:-${ASPNETCORE_ENVIRONMENT:-Development}}" nohup "$r" run --project "$PROJECT" ${CFGARGS[@]+"${CFGARGS[@]}"} --urls "$URL" >> "$LOG" 2>&1 < /dev/null &
        PID=$!; label="$r" ;;
    esac
    tried+=("$label")
    if poll_http "$URL$PROBE" 120 "$PID"; then
      WP_PORT=""; [[ "$r" == "cmd.exe" ]] && WP_PORT="$PORT"
      write_state web base "$URL" "$PID" "$label" "$PROJECT" "" "" "$PLATFORM"
      [[ -n "$WP_PORT" ]] && set_state win_port "$WP_PORT"
      echo "BOOTED head=web mode=base url=$URL rung=$label project=$PROJECT pid=$PID log=$LOG stop=\"bash .tfcore/utils/tf-verify-boot.sh stop --port $PORT\""; exit 0
    fi
    pkill -P "$PID" 2>/dev/null; kill "$PID" 2>/dev/null
    # killing cmd.exe on this side leaves the Windows-side app running and holding the build output
    # (TF-034): stop whatever listens on THIS start's port, never by program name
    [[ "$r" == "cmd.exe" ]] && powershell.exe -NoProfile -Command "Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1
    seg="$(awk '/^### rung: /{p=0} index($0,"### rung: '"$r"'")==1{p=1} p' "$LOG")"
    if grep -qE "$CODE_ERR" <<<"$seg" && ! grep -qE "$WRONG_RUNG" <<<"$seg"; then
      first="$(grep -E 'error (CS|RZ|BL|XC|XLS|MSB|NU)[0-9]+' <<<"$seg" | head -1 | sed 's/^[[:space:]]*//' | cut -c1-160)"
      write_state web none "" "" "$label" "$PROJECT" "build error: $first" build-error "$PLATFORM"
      echo "NONE head=web kind=build-error reason=the code does not build via $label: $first (log $LOG)"; exit 2
    fi
  done
  write_state web none "" "" "" "$PROJECT" "no rung answered on $URL; tried ${tried[*]}" host "$PLATFORM"
  echo "NONE head=web kind=host reason=no rung brought $PROJECT up on $URL within 120 s; tried: ${tried[*]} (log $LOG)"; exit 2
fi

# ---- windows (MAUI Blazor Hybrid over CDP) --------------------------------------------------
[[ "$PLATFORM" == "wsl" || "$PLATFORM" == "windows" ]] || { write_state windows none "" "" "" "$PROJECT" "a Windows head runs only from WSL or Windows" host "$PLATFORM"; echo "NONE head=windows reason=a Windows head runs only from WSL or Windows, this is $PLATFORM"; exit 2; }
command -v cmd.exe >/dev/null 2>&1 || { write_state windows none "" "" "" "$PROJECT" "cmd.exe not reachable" host "$PLATFORM"; echo "NONE head=windows reason=cmd.exe is not reachable from this shell"; exit 2; }
TFM="$(grep -oE 'net[0-9.]+-windows[0-9.]*' "$PROJECT" | head -1)"
RELAY_PORT="${PORT:-9223}"; keyed "$RELAY_PORT"
# Each boot drives its own embedded browser (Sevak TF-003). The DevTools port was 9222 for every
# head, so with two up the relay on 9223 listed pages of both apps and a smoke drove the other
# agent's window. The port now follows the relay port (9223 keeps 9222). A second head while one is
# up also gets its own WebView2 data folder: two copies of one app would otherwise share one browser
# process, whose single DevTools port lists both.
if [[ "$RELAY_PORT" == "9223" ]]; then CDP_PORT=9222; else CDP_PORT=$((RELAY_PORT + 20000)); fi
OTHERS="$(python3 - "$DIR" "$RELAY_PORT" <<'PY'
import glob, json, os, sys
n = 0
for f in glob.glob(os.path.join(sys.argv[1], "boot-*.json")):
    if f.endswith(f"boot-{sys.argv[2]}.json"):
        continue
    try:
        s = json.load(open(f))
    except Exception:
        continue
    if s.get("head") == "windows" and s.get("mode") == "cdp" and not s.get("stopped"):
        n += 1
print(n)
PY
)"
UDF_SET=""
if [[ "${OTHERS:-0}" -gt 0 ]]; then
  UDF="$DIR/webview-$RELAY_PORT"; mkdir -p "$UDF"
  UDF_SET="set WEBVIEW2_USER_DATA_FOLDER=$(wslpath -w "$UDF")&& "
  echo "tf-verify-boot: $OTHERS other Windows head(s) up — this one gets DevTools port $CDP_PORT and its own WebView2 data folder ($UDF), so neither sees the other's pages" >&2
fi
WP="$(winarg "$(wslpath -w "$PROJECT")")"; RELAY="$(wslpath -w "$HERE/tf-cdp-relay.ps1")"
echo "### windows head: $PROJECT -f $TFM (DevTools $CDP_PORT, relay $RELAY_PORT)" >> "$LOG"
# this start's own Windows processes: the app's ids before it, so the new ones are this boot's and
# stop kills them alone, never every copy of the program (taskkill /IM stopped another agent's app)
win_ids() { powershell.exe -NoProfile -Command "Get-Process -Name '$ASM' -ErrorAction SilentlyContinue | ForEach-Object { \$_.Id }" 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | sort; }
BEFORE_IDS="$(win_ids)"
nohup cmd.exe /c "${UDF_SET}set WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=$CDP_PORT&& dotnet run --project $WP -f $TFM ${CFGARGS[*]:-}" >> "$LOG" 2>&1 < /dev/null &
APP_PID=$!
nohup powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RELAY" -ListenPort "$RELAY_PORT" -TargetPort "$CDP_PORT" >> "$DIR/relay.log" 2>&1 < /dev/null &
RELAY_PID=$!
GW="$(ip route 2>/dev/null | awk '/default/{print $3; exit}')"
HOSTS=("localhost"); [[ -n "$GW" ]] && HOSTS+=("$GW")
i=0; URL=""
while [[ $i -lt 300 && -z "$URL" ]]; do
  for h in "${HOSTS[@]}"; do
    if curl -s -m 2 "http://$h:$RELAY_PORT/json/version" 2>/dev/null | grep -q '"webSocketDebuggerUrl"'; then URL="http://$h:$RELAY_PORT"; break; fi
  done
  [[ -n "$URL" ]] && break
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    seg="$(cat "$LOG")"
    if grep -qE "$CODE_ERR" <<<"$seg"; then
      first="$(grep -E 'error (CS|RZ|BL|XC|XLS|MSB|NU)[0-9]+' <<<"$seg" | head -1 | sed 's/^[[:space:]]*//' | cut -c1-160)"
      kill "$RELAY_PID" 2>/dev/null
      write_state windows none "" "" "cmd.exe /c dotnet run -f $TFM" "$PROJECT" "build error: $first" build-error "$PLATFORM"
      echo "NONE head=windows kind=build-error reason=the code does not build: $first (log $LOG)"; exit 2
    fi
  fi
  sleep 3; i=$((i+3))
done
MINE="$(comm -13 <(printf '%s\n' "$BEFORE_IDS") <(win_ids) | tr '\n' ' ')"
if [[ -z "$URL" ]]; then
  pkill -P "$APP_PID" 2>/dev/null; kill "$APP_PID" "$RELAY_PID" 2>/dev/null
  for w in $MINE; do taskkill.exe /F /T /PID "$w" >/dev/null 2>&1; done
  write_state windows none "" "" "cmd.exe /c dotnet run -f $TFM" "$PROJECT" "the DevTools port $RELAY_PORT never answered within 300 s" host "$PLATFORM"
  echo "NONE head=windows kind=host reason=the app's DevTools port never answered on ${HOSTS[*]}:$RELAY_PORT within 300 s (log $LOG, relay $DIR/relay.log)"; exit 2
fi
write_state windows cdp "$URL" "$APP_PID $RELAY_PID" "cmd.exe /c dotnet run -f $TFM" "$PROJECT" "" "" "$PLATFORM"
set_state win_image "\"$ASM.exe\""
set_state win_pids "[$(tr ' ' '\n' <<<"$MINE" | grep -E '^[0-9]+$' | paste -sd, -)]"
set_state cdp_port "$CDP_PORT"
echo "BOOTED head=windows mode=cdp url=$URL project=$PROJECT tfm=$TFM pids=$APP_PID,$RELAY_PID image=$ASM.exe log=$LOG"
exit 0

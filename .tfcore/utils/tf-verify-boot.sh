#!/usr/bin/env bash
# tf-verify-boot.sh — start the application for a verify, reach it, and stop it (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-boot.sh start [--head web|windows|static] [--project <csproj>]
#                                              [--port N] [--config Release] [--static <dir>]
#   bash .tfcore/utils/tf-verify-boot.sh stop [--port N]
#   bash .tfcore/utils/tf-verify-boot.sh status [--port N]
#
# Heads:
#   web      a project on Microsoft.NET.Sdk.Web: started with `dotnet run --urls`, first through
#            the rungs tf-build.sh knows (dotnet, ~/.dotnet/dotnet, then Windows-side cmd.exe on
#            WSL), polled until it answers. Prints BOOTED mode=base url=http://localhost:PORT.
#   windows  a MAUI Blazor Hybrid head (UseMaui + a net*-windows target): started Windows-side with
#            WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222, the DevTools port
#            relayed to every interface by tf-cdp-relay.ps1, and reached from WSL over CDP. Prints
#            BOOTED mode=cdp url=http://<host>:9223. Proven on MyDiary, 2026-09-06.
#   static   a folder of HTML served by python3 (the framework self-test, a mockup set).
#   android, ios, maccatalyst: no driver ships in this framework version. NONE with that reason;
#            their rows are recorded as not verified, never as static-only passes.
# Without --head the script picks web when a web project exists, else windows when a MAUI project
# with a windows target exists, else NONE. --project names the project when there are several.
# The state goes to tests/.artifacts/verify/boot-<port>.json and the app log to app-<port>.log, one pair
# per app, so builders booting side by side never empty or stop each other's (TF-034); boot.json is a
# copy of the latest start's, which the verdict reads. `stop --port N` stops that app only; a bare
# `stop` stops the one boot.json names, and refuses while two or more are running. `stop` kills what
# `start` started and nothing else. Never asks anyone to start anything.
# Exit 0 booted / stopped · 2 NONE (reason printed; kind=build-error, host or no-driver) · 3 usage.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
is_maui_win() { grep -qiE '<UseMaui>\s*true|Microsoft\.NET\.Sdk\.Maui' "$1" && grep -qE 'net[0-9.]+-windows' "$1"; }

poll_http() { # url seconds pid-to-watch(optional) -> 0 when it answers
  local url="$1" secs="$2" pid="${3:-}" i=0 code
  while [[ $i -lt $secs ]]; do
    code="$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$url" 2>/dev/null || true)"
    [[ "$code" =~ ^[23] ]] && return 0
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
        echo "NOT-STOPPED $(wc -w <<<"$live") apps are running (ports ${live// /, }); stop yours with: bash .tfcore/utils/tf-verify-boot.sh stop --port <n>"; exit 2
      fi
    fi
    python3 - "$DIR" "$SPORT" <<'PY'
import json, os, re, signal, subprocess, sys, time
d, port = sys.argv[1], sys.argv[2]
main = os.path.join(d, "boot.json")
path = os.path.join(d, f"boot-{port}.json") if port else main
s = json.load(open(path))
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
if image:
    subprocess.run(["taskkill.exe", "/F", "/T", "/IM", image], capture_output=True)
if s.get("win_port"):
    ps = f"Get-NetTCPConnection -LocalPort {s['win_port']} -State Listen -ErrorAction SilentlyContinue | ForEach-Object {{ Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }}"
    subprocess.run(["powershell.exe", "-NoProfile", "-Command", ps], capture_output=True)
s["stopped"] = True
json.dump(s, open(path, "w"), indent=1)
# the same app under its other name: boot.json and its own boot-<port>.json
m = re.search(r":(\d+)$", s.get("url") or "")
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
  *) sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 3 ;;
esac

HEAD=""; PROJECT=""; PORT=""; CONFIG=""; STATIC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
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
mapfile -t ALL < <(find_projects)
WEB=(); WIN=()
for p in "${ALL[@]}"; do is_web "$p" && WEB+=("$p"); is_maui_win "$p" && WIN+=("$p"); done
if [[ -n "$PROJECT" ]]; then
  [[ -f "$PROJECT" ]] || { echo "NONE reason=--project $PROJECT does not exist"; exit 3; }
  if [[ -z "$HEAD" ]]; then is_web "$PROJECT" && HEAD=web; [[ -z "$HEAD" ]] && is_maui_win "$PROJECT" && HEAD=windows; fi
elif [[ -z "$HEAD" ]]; then
  if [[ ${#WEB[@]} -gt 0 ]]; then HEAD=web; PROJECT="${WEB[0]}"
  elif [[ ${#WIN[@]} -gt 0 ]]; then HEAD=windows; PROJECT="${WIN[0]}"; fi
else
  case "$HEAD" in web) PROJECT="${WEB[0]:-}" ;; windows) PROJECT="${WIN[0]:-}" ;; esac
fi
case "$HEAD" in
  android|ios|maccatalyst)
    write_state "$HEAD" none "" "" "" "${PROJECT:-}" "no driver for the $HEAD head ships in this framework version" no-driver "$PLATFORM"
    echo "NONE head=$HEAD reason=no driver for the $HEAD head ships in this framework version; its rows are recorded as not verified"; exit 2 ;;
  web|windows) ;;
  "") write_state none none "" "" "" "" "no web project and no MAUI project with a windows target found under src/, source/ or the root" host "$PLATFORM"
      echo "NONE head=none reason=no web project (Microsoft.NET.Sdk.Web) and no MAUI project with a windows target found; name one with --project"; exit 2 ;;
  *) echo "NONE reason=unknown head $HEAD"; exit 3 ;;
esac
[[ -n "$PROJECT" ]] || { write_state "$HEAD" none "" "" "" "" "no project for head $HEAD" host "$PLATFORM"; echo "NONE head=$HEAD reason=no project found for that head; name one with --project"; exit 2; }
PDIR="$(dirname "$PROJECT")"; PNAME="$(basename "$PROJECT" .csproj)"
ASM="$(grep -oE '<AssemblyName>[^<]+' "$PROJECT" 2>/dev/null | head -1 | sed 's/<AssemblyName>//')"; ASM="${ASM:-$PNAME}"
CFGARGS=(); [[ -n "$CONFIG" ]] && CFGARGS=(-c "$CONFIG")

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
        nohup cmd.exe /c "dotnet run --project $WP ${CFGARGS[*]} --urls $URL" >> "$LOG" 2>&1 < /dev/null &
        PID=$!; label="cmd.exe /c dotnet" ;;
      *)
        ASPNETCORE_ENVIRONMENT="${ASPNETCORE_ENVIRONMENT:-Development}" nohup "$r" run --project "$PROJECT" "${CFGARGS[@]}" --urls "$URL" >> "$LOG" 2>&1 < /dev/null &
        PID=$!; label="$r" ;;
    esac
    tried+=("$label")
    if poll_http "$URL/" 120 "$PID"; then
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
      first="$(grep -E 'error (CS|RZ|BL|XC|XLS|MSB|NU)[0-9]+' <<<"$seg" | head -1 | sed 's/^\s*//' | cut -c1-160)"
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
CDP_PORT=9222; RELAY_PORT="${PORT:-9223}"; keyed "$RELAY_PORT"
WP="$(winarg "$(wslpath -w "$PROJECT")")"; RELAY="$(wslpath -w "$HERE/tf-cdp-relay.ps1")"
echo "### windows head: $PROJECT -f $TFM" >> "$LOG"
nohup cmd.exe /c "set WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=$CDP_PORT&& dotnet run --project $WP -f $TFM ${CFGARGS[*]}" >> "$LOG" 2>&1 < /dev/null &
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
      first="$(grep -E 'error (CS|RZ|BL|XC|XLS|MSB|NU)[0-9]+' <<<"$seg" | head -1 | sed 's/^\s*//' | cut -c1-160)"
      kill "$RELAY_PID" 2>/dev/null
      write_state windows none "" "" "cmd.exe /c dotnet run -f $TFM" "$PROJECT" "build error: $first" build-error "$PLATFORM"
      echo "NONE head=windows kind=build-error reason=the code does not build: $first (log $LOG)"; exit 2
    fi
  fi
  sleep 3; i=$((i+3))
done
if [[ -z "$URL" ]]; then
  pkill -P "$APP_PID" 2>/dev/null; kill "$APP_PID" "$RELAY_PID" 2>/dev/null
  taskkill.exe /F /T /IM "$ASM.exe" >/dev/null 2>&1
  write_state windows none "" "" "cmd.exe /c dotnet run -f $TFM" "$PROJECT" "the DevTools port $RELAY_PORT never answered within 300 s" host "$PLATFORM"
  echo "NONE head=windows kind=host reason=the app's DevTools port never answered on ${HOSTS[*]}:$RELAY_PORT within 300 s (log $LOG, relay $DIR/relay.log)"; exit 2
fi
write_state windows cdp "$URL" "$APP_PID $RELAY_PID" "cmd.exe /c dotnet run -f $TFM" "$PROJECT" "" "" "$PLATFORM"
set_state win_image "\"$ASM.exe\""
echo "BOOTED head=windows mode=cdp url=$URL project=$PROJECT tfm=$TFM pids=$APP_PID,$RELAY_PID image=$ASM.exe log=$LOG"
exit 0

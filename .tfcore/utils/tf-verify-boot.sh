#!/usr/bin/env bash
# tf-verify-boot.sh — start the application for a verify, reach it, and stop it (Sitting 4c, 2026-09-06).
#
#   bash .tfcore/utils/tf-verify-boot.sh start [--head web|windows|static] [--project <csproj>] [--dry-run]
#                                              [--port N] [--config Release] [--static <dir>] [--probe-path /healthz]
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
# An app whose starter died is nobody's child any more, so the kills above miss it and it keeps its
# port and its files. The published copy names it: stop whatever runs from run-<port>/ (TF-043).
m = re.search(r":(\d+)$", s.get("url") or "")
run_port = port or (m.group(1) if m else "")
if run_port:
    mark = os.path.join(os.getcwd(), d, f"run-{run_port}") + os.sep
    try:
        procs = [p for p in os.listdir("/proc") if p.isdigit()]
    except Exception:
        procs = []
    for p in procs:
        try:
            cmd = open(f"/proc/{p}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
        except Exception:
            continue
        if mark in cmd and int(p) != os.getpid():
            try:
                os.kill(int(p), signal.SIGKILL)
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
  *) sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 3 ;;
esac

HEAD=""; PROJECT=""; PORT=""; CONFIG=""; STATIC=""; PROBE="/"; DRYRUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
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
mapfile -t ALL < <(find_projects)
WEB=(); WIN=()
for p in "${ALL[@]}"; do is_web "$p" && WEB+=("$p"); is_maui_win "$p" && WIN+=("$p"); done
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
  if [[ -z "$HEAD" ]]; then is_web "$PROJECT" && HEAD=web; [[ -z "$HEAD" ]] && is_maui_win "$PROJECT" && HEAD=windows; fi
elif [[ -z "$HEAD" ]]; then
  if [[ ${#WEB[@]} -gt 0 ]]; then HEAD=web; pick_web
  elif [[ ${#WIN[@]} -gt 0 ]]; then HEAD=windows; PROJECT="${WIN[0]}"; fi
else
  case "$HEAD" in web) pick_web ;; windows) PROJECT="${WIN[0]:-}" ;; esac
fi
if [[ $DRYRUN -eq 1 ]]; then echo "PICK head=${HEAD:-none} project=${PROJECT:-none}"; exit 0; fi
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
      first="$(grep -E 'error (CS|RZ|BL|XC|XLS|MSB|NU)[0-9]+' <<<"$pub" | head -1 | sed 's/^\s*//' | cut -c1-160)"
      write_state web none "" "" "tf-build.sh publish" "$PROJECT" "build error: ${first:-$verdict}" build-error "$PLATFORM"
      echo "NONE head=web kind=build-error reason=the code does not build: ${first:-$verdict} (log $LOG)"; exit 2
    elif [[ $prc -ne 0 || ! -f "$RUN/$ASM.dll" ]]; then
      reason="${verdict:-the publish wrote no $ASM.dll into $RUN}"
      write_state web none "" "" "tf-build.sh publish" "$PROJECT" "$reason" host "$PLATFORM"
      echo "NONE head=web kind=host reason=$reason (log $LOG)"; exit 2
    fi
    # what `dotnet run` sets from the launch profile; the environment above all, which picks the
    # settings file and whether the secrets are read
    mapfile -t LSENV < <(python3 - "$PDIR/Properties/launchSettings.json" <<'PY'
import json, os, sys
try:
    profiles = json.load(open(sys.argv[1], encoding="utf-8-sig")).get("profiles", {})
except Exception:
    profiles = {}
env = next((dict(p.get("environmentVariables") or {}) for p in profiles.values() if p.get("commandName") == "Project"), {})
env.setdefault("ASPNETCORE_ENVIRONMENT", "Development")
if os.environ.get("ASPNETCORE_ENVIRONMENT"):
    env["ASPNETCORE_ENVIRONMENT"] = os.environ["ASPNETCORE_ENVIRONMENT"]
for k, v in env.items():
    print(f"{k}={v}")
PY
)
    WIN=""
    case "$verdict" in
      *"via cmd.exe"*|*"via winrun"*|*"via powershell.exe"*)
        WIN=1; WPD="$(winarg "$(wslpath -w "$PDIR")")"; WDLL="$(winarg "$(wslpath -w "$RUN/$ASM.dll")")"
        WWEB=""; [[ -d "$RUN/wwwroot" ]] && WWEB="--webroot $(winarg "$(wslpath -w "$RUN/wwwroot")")"
        sets=""; for kv in "${LSENV[@]}"; do sets+="set $kv&& "; done
        nohup cmd.exe /c "cd /d $WPD && ${sets}dotnet $WDLL --urls $URL --contentRoot $WPD $WWEB" >> "$LOG" 2>&1 < /dev/null &
        PID=$!; label="cmd.exe /c dotnet" ;;
      *)
        runner="dotnet"; [[ "$verdict" == *"via ~/.dotnet/dotnet"* ]] && runner="$HOME/.dotnet/dotnet"
        WEBR=(); [[ -d "$RUN/wwwroot" ]] && WEBR=(--webroot "$ROOTDIR/$RUN/wwwroot")
        # the redirections belong to the whole background group and the group becomes the app: a group
        # left waiting on its app kept this script's output open, so a caller reading it waited for ever
        ( cd "$PDIR" || exit 1; exec env "${LSENV[@]}" nohup "$runner" "$ROOTDIR/$RUN/$ASM.dll" --urls "$URL" --contentRoot "$PWD" "${WEBR[@]}" ) \
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
    last="$(grep -vE '^\s*$' "$LOG" | tail -3 | tr '\n' ' ' | cut -c1-240)"
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
        nohup cmd.exe /c "dotnet run --project $WP ${CFGARGS[*]} --urls $URL" >> "$LOG" 2>&1 < /dev/null &
        PID=$!; label="cmd.exe /c dotnet" ;;
      *)
        ASPNETCORE_ENVIRONMENT="${ASPNETCORE_ENVIRONMENT:-Development}" nohup "$r" run --project "$PROJECT" "${CFGARGS[@]}" --urls "$URL" >> "$LOG" 2>&1 < /dev/null &
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

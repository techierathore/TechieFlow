#!/usr/bin/env bash
# tf-build.sh — build, test or run a .NET target on whatever host this is, trying the
# invocation rungs in order and stopping at the first that works (Sitting 4b, 2026-09-05;
# replaces the prose ladder build-invocation-ladder.md §0 to §C).
#
#   bash .tfcore/utils/tf-build.sh [build] [<target>] [-- <extra dotnet args>]
#   bash .tfcore/utils/tf-build.sh test  [<target>] [-- <extra dotnet args>]
#   bash .tfcore/utils/tf-build.sh run   <project>  [-- <extra dotnet args>]
#   bash .tfcore/utils/tf-build.sh probe                 # print the platform and the rungs, run nothing
#
# <target> is a .sln, .slnx or .csproj relative to the current folder (default: the one
# solution or project found here). Output goes to tests/.artifacts/build/<UTC time>.log.
#
# Prints ONE verdict line the agent copies into the status log row:
#   PASS  built on wsl via cmd.exe /c dotnet (rung 4) — 0 warnings
#   FAIL  real compile errors on wsl via ~/.dotnet/dotnet (rung 2): 3 CS errors, first: …
#   NOT-RUN no rung could run dotnet on wsl; tried: dotnet, ~/.dotnet/dotnet, cmd.exe, winrun, powershell.exe
# Exit 0 PASS · 1 FAIL (the code is wrong: fix it) · 2 NOT-RUN (the host is wrong: never a
# project blocker; say which rungs were tried).
#
# Rungs by host (docs/TechieFlow-How-It-Works.md; build-invocation-ladder.md §D keeps the
# runtime-driver table, which this script does not replace):
#   macOS / native Linux / native Windows:  dotnet
#   WSL, no MAUI head in the target:        dotnet · ~/.dotnet/dotnet · winrun · cmd.exe /c dotnet · powershell.exe dotnet
#   WSL, a MAUI head in the target:         cmd.exe /c dotnet · winrun · powershell.exe dotnet   (workloads live Windows-side)
#   OpenCode Docker (TF_OPENCODE_DOCKER=1 or winrun + TF_WINDOWS_APP_PATH): MAUI → winrun; else dotnet
# A workload / SDK-missing error (NETSDK1178, Microsoft.iOS/Android/MacCatalyst.Sdk, Workload ID,
# WindowsAppSDK, command not found) means the wrong rung: the next one is tried, nothing is logged
# as a blocker. A CS#### error means the code is wrong: the rung stays and the script exits 1.
# A locked output file (MSB3021, MSB3027, "being used by another process") is neither: the same
# rung waits and tries again, then says NOT-RUN naming the lock; it never falls to the next rung
# (TF-035). On WSL a build that changes side -- a WSL rung, then a Windows one, over the same obj/,
# in this run or since the last -- first clears obj/**/scopedcss: a Blazor build names each scoped
# stylesheet by a hash of the path, the two sides hash differently, and the incremental target
# kept the old names, so every page's own styles stopped applying (TfLens, 2026-09-11).
set -u

MODE="build"; TARGET=""; EXTRA=()
case "${1:-}" in
  build|test|run|probe) MODE="$1"; shift ;;
esac
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then shift; EXTRA=("$@"); break; fi
  TARGET="$1"; shift
done

# ---- platform -------------------------------------------------------------------------
PLATFORM="linux"
U="$(uname -s 2>/dev/null || echo windows)"
if [[ "$U" == Darwin* ]]; then PLATFORM="macos"
elif [[ "$U" == Linux* ]]; then
  if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then PLATFORM="wsl"
  elif [[ "${TF_OPENCODE_DOCKER:-}" == "1" ]] || { [[ -x /usr/local/bin/winrun ]] && [[ -n "${TF_WINDOWS_APP_PATH:-}" ]]; }; then PLATFORM="docker"
  fi
elif [[ "$U" == windows || "$U" == MINGW* || "$U" == MSYS* || "$U" == CYGWIN* ]]; then PLATFORM="windows"
fi
PLATFORM="${TF_BUILD_PLATFORM:-$PLATFORM}"   # the self-tests only

# ---- target ---------------------------------------------------------------------------
if [[ -z "$TARGET" && "$MODE" != "probe" ]]; then
  mapfile -t CANDS < <(ls -1 *.slnx *.sln 2>/dev/null; ls -1 *.csproj 2>/dev/null)
  if [[ ${#CANDS[@]} -eq 1 ]]; then TARGET="${CANDS[0]}"
  elif [[ ${#CANDS[@]} -gt 1 ]]; then echo "NOT-RUN more than one solution or project here; name one: ${CANDS[*]}"; exit 2
  fi
fi

# ---- does the target include a MAUI head? ----------------------------------------------
maui=0
projects=()
if [[ -n "$TARGET" ]]; then
  case "$TARGET" in
    *.csproj) projects=("$TARGET") ;;
    *.sln)  mapfile -t projects < <(grep -oE '"[^"]+\.csproj"' "$TARGET" 2>/dev/null | tr -d '"' | tr '\\' '/') ;;
    *.slnx) mapfile -t projects < <(grep -oE 'Path="[^"]+\.csproj"' "$TARGET" 2>/dev/null | sed 's/Path="//; s/"$//' | tr '\\' '/') ;;
  esac
  base="$(dirname "$TARGET")"
  for p in "${projects[@]}"; do
    f="$p"; [[ -f "$f" ]] || f="$base/$p"
    [[ -f "$f" ]] || continue
    if grep -qiE '<UseMaui>\s*true|Microsoft\.NET\.Sdk\.Maui|net[0-9.]+-(android|ios|maccatalyst|windows10)' "$f"; then maui=1; fi
  done
fi

# ---- rungs -----------------------------------------------------------------------------
rungs=()
case "$PLATFORM" in
  macos|linux|windows) rungs=("dotnet") ;;
  docker) if [[ $maui -eq 1 ]]; then rungs=("winrun"); else rungs=("dotnet" "winrun"); fi ;;
  wsl)
    if [[ $maui -eq 1 ]]; then rungs=("cmd.exe" "winrun" "powershell.exe")
    else rungs=("dotnet" "$HOME/.dotnet/dotnet" "winrun" "cmd.exe" "powershell.exe"); fi ;;
esac

if [[ "$MODE" == "probe" ]]; then
  echo "platform: $PLATFORM · target: ${TARGET:-none} · maui head: $([[ $maui -eq 1 ]] && echo yes || echo no)"
  echo "rungs, in order: ${rungs[*]}"
  exit 0
fi
[[ -z "$TARGET" && "$MODE" != "run" ]] && { echo "NOT-RUN no .sln, .slnx or .csproj here; name the target"; exit 2; }

# ---- the dotnet verb -------------------------------------------------------------------
verb="$MODE"
args=("$verb")
[[ -n "$TARGET" ]] && args+=("$TARGET")
[[ "$MODE" == "run" ]] && args=("run" "--project" "$TARGET")
args+=("${EXTRA[@]}")

mkdir -p tests/.artifacts/build
LOG="tests/.artifacts/build/$(date -u +%Y%m%dT%H%M%SZ)-$MODE-$$.log"   # two builds in one second never share a log
LOCKED='error MSB302[17]|being used by another process|Access to the path .* is denied'
# which side of a WSL machine a rung builds on, and the project folders whose obj/ it writes
side_of() { case "$1" in winrun|cmd.exe|powershell.exe) echo windows ;; *) echo wsl ;; esac; }
pdirs=(); for p in "${projects[@]}"; do f="$p"; [[ -f "$f" ]] || f="${base:-.}/$p"; [[ -f "$f" ]] && pdirs+=("$(dirname "$f")"); done
cross_side() { # side: clear the scoped-css outputs another side built, then mark this side
  local d cleared=0
  for d in "${pdirs[@]}"; do
    [[ -d "$d/obj" ]] || continue
    if [[ "$(cat "$d/obj/.tf-build-side" 2>/dev/null)" != "$1" ]] && [[ -n "$(find "$d/obj" -type d -name scopedcss -print -quit 2>/dev/null)" ]]; then
      find "$d/obj" -type d -name scopedcss -prune -exec rm -rf {} + 2>/dev/null; cleared=1
    fi
    echo "$1" > "$d/obj/.tf-build-side"
  done
  [[ $cleared -eq 1 ]] && echo "note  the scoped stylesheets were built on the other side of this machine; cleared so the $1 build names them itself"
}
WRONG_RUNG='NETSDK1178|Microsoft\.(iOS|Android|MacCatalyst|tvOS)\.Sdk|Workload ID|not recognized|WindowsAppSDK|command not found|No such file or directory|is not recognized as an internal or external command|The term .* is not recognized|workload.*not installed|Inadequate permissions'

tried=()
n=0
for r in "${rungs[@]}"; do
  n=$((n+1))
  case "$r" in
    dotnet)          cmd=(dotnet "${args[@]}"); label="dotnet" ;;
    */.dotnet/dotnet) cmd=("$r" "${args[@]}"); label="~/.dotnet/dotnet" ;;
    winrun)          cmd=(winrun "dotnet ${args[*]}"); label="winrun dotnet" ;;
    cmd.exe)         cmd=(cmd.exe /c "dotnet ${args[*]}"); label="cmd.exe /c dotnet" ;;
    powershell.exe)  cmd=(powershell.exe -Command "dotnet ${args[*]}"); label="powershell.exe dotnet" ;;
  esac
  tried+=("$label")
  [[ "$PLATFORM" == "wsl" ]] && cross_side "$(side_of "$r")"
  for attempt in $(seq 0 "${TF_BUILD_LOCK_RETRIES:-2}"); do
    from=$(( $(wc -l < "$LOG" 2>/dev/null || echo 0) + 1 ))
    { echo "### rung $n: ${cmd[*]}"; "${cmd[@]}" 2>&1; echo "### exit $?"; } >> "$LOG" 2>&1
    rc="$(tail -1 "$LOG" | sed 's/### exit //')"
    seg="$(tail -n +"$from" "$LOG")"      # this attempt's lines only
    [[ "$rc" != "0" ]] && grep -qE "$LOCKED" <<<"$seg" || break
    [[ $attempt -lt ${TF_BUILD_LOCK_RETRIES:-2} ]] && sleep "${TF_BUILD_LOCK_WAIT:-15}"
  done
  if [[ "$rc" == "0" ]]; then
    warns="$(grep -cE 'warning [A-Z]+[0-9]+' <<<"$seg" || true)"
    echo "PASS  $MODE on $PLATFORM via $label (rung $n) — $warns warning line(s); log $LOG"
    exit 0
  fi
  # Code errors: C# (CS), Razor (RZ), Blazor (BL), XAML (XC, XLS), missing reference (MSB/NU).
  # Until 2026-09-06 only CS counted, so a build failing on sixteen Razor RZ9991 errors was
  # taken for a wrong rung and reported NOT-RUN "host issue" (MISS-TechieFlow-20260906-03).
  if grep -qE 'error (CS|RZ|BL|XC|XLS)[0-9]{3,5}|error MSB[0-9]{4}: .*(does not exist|could not be found)|error NU1' <<<"$seg" && ! grep -qE "$WRONG_RUNG" <<<"$seg"; then
    errs="$(grep -cE 'error (CS|RZ|BL|XC|XLS|MSB|NU)[0-9]+' <<<"$seg" || true)"
    first="$(grep -E 'error (CS|RZ|BL|XC|XLS|MSB|NU)[0-9]+' <<<"$seg" | head -1 | sed 's/^\s*//' | cut -c1-160)"
    echo "FAIL  real errors on $PLATFORM via $label (rung $n): $errs error line(s), first: $first; log $LOG"
    grep -E 'error (CS|RZ|BL|XC|XLS|MSB|NU)[0-9]+' <<<"$seg" | sed 's/^\s*//' | sort -u | head -10
    exit 1
  fi
  if [[ "$MODE" == "test" ]] && grep -qE 'Failed!|Failed:\s+[1-9]|Tests? failed' <<<"$seg"; then
    echo "FAIL  tests failed on $PLATFORM via $label (rung $n); log $LOG"
    grep -E 'Failed |Failed!|Error Message|Total tests|Passed!' <<<"$seg" | head -12
    exit 1
  fi
  # a locked output file: the rung is right and the code is fine; another rung over the same obj/
  # is exactly what broke the stylesheets (TF-035), so stop here and name the lock
  if grep -qE "$LOCKED" <<<"$seg"; then
    first="$(grep -E "$LOCKED" <<<"$seg" | head -1 | sed 's/^\s*//' | cut -c1-200)"
    echo "NOT-RUN the build output is held by a running process (still after $((${TF_BUILD_LOCK_RETRIES:-2} + 1)) tries on $label): $first. Stop that app -- bash .tfcore/utils/tf-verify-boot.sh stop --port <its port> -- and build again. Not a code error; log $LOG"
    exit 2
  fi
  # anything else (workload, wrong rung, tool absent): try the next rung
done
echo "NOT-RUN no rung could $MODE on $PLATFORM; tried: ${tried[*]}. This is a host issue, never a project blocker; log $LOG"
exit 2

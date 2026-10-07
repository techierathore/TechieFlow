#!/usr/bin/env bash
# tf-maccatalyst-check.sh — the Mac Catalyst rules a MAUI project must meet before its Mac app can
# start (coding-standards-dotnet.md §9; 2026-10-07). Reads files only: runs the same on Windows (WSL,
# Git Bash), Linux and a Mac, so a team without a Mac finds these before the Mac build does.
#
#   bash .tfcore/utils/tf-maccatalyst-check.sh [<csproj> ...]   (default: every project with a
#                                                                net*-maccatalyst target)
#
# FAIL  the scene manifest: Platforms/MacCatalyst/Info.plist has no UIApplicationSceneManifest, or
#       names a scene delegate no class in the project registers as a MauiUISceneDelegate. On
#       macOS 27 such an app quits at its first window (the stock `dotnet new maui` template has none).
# WARN  the keychain: an entitlements file asks for keychain-access-groups and the project names no
#       provisioning profile and no Debug entitlements file without it. macOS refuses to start a
#       locally signed (ad hoc) build that asks for it ("Launch failed", POSIX 163).
# Prints one line per finding and an OK line per clean project.
# Exit 0 no FAIL (WARNs allowed) · 1 a FAIL · 3 usage.
set -u
case "${1:-}" in -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

PROJECTS=("$@")
if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  while IFS= read -r p; do PROJECTS+=("$p"); done < <(
    find . -maxdepth 5 -name '*.csproj' -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' \
         -not -path './tests/.artifacts/*' 2>/dev/null | sed 's#^\./##' | sort)
fi
fails=0; seen=0
for P in ${PROJECTS[@]+"${PROJECTS[@]}"}; do
  [[ -f "$P" ]] || { echo "tf-maccatalyst-check: $P does not exist" >&2; exit 3; }
  grep -qE 'net[0-9.]+-maccatalyst' "$P" || continue
  grep -qiE '<UseMaui>[[:space:]]*true|Microsoft\.NET\.Sdk\.Maui' "$P" || continue
  seen=$((seen+1)); D="$(dirname "$P")"; M="$D/Platforms/MacCatalyst"; found=0
  # --- the scene manifest and its delegate
  PL="$M/Info.plist"
  if [[ ! -f "$PL" ]]; then
    echo "FAIL $P: $PL is missing"; fails=$((fails+1)); found=1
  elif ! grep -q 'UIApplicationSceneManifest' "$PL"; then
    echo "FAIL $P: $PL has no UIApplicationSceneManifest; on macOS 27 the app quits at its first window. Add the manifest and a SceneDelegate : MauiUISceneDelegate (coding-standards-dotnet.md §9)"
    fails=$((fails+1)); found=1
  else
    # the delegate the manifest names: the <string> after UISceneDelegateClassName
    DEL="$(tr -d '\n\r' < "$PL" | grep -oE '<key>UISceneDelegateClassName</key>[[:space:]]*<string>[^<]+' | head -1 | sed 's/.*<string>//')"
    if [[ -n "$DEL" ]] && ! grep -rqsE "Register\(\"$DEL\"\)" "$D" --include='*.cs'; then
      echo "FAIL $P: Info.plist names the scene delegate $DEL, and no class in the project carries [Register(\"$DEL\")] (a class deriving from MauiUISceneDelegate)"
      fails=$((fails+1)); found=1
    elif [[ -n "$DEL" ]] && ! grep -rqs 'MauiUISceneDelegate' "$D" --include='*.cs'; then
      echo "FAIL $P: [Register(\"$DEL\")] is there, but no class derives from MauiUISceneDelegate"
      fails=$((fails+1)); found=1
    fi
  fi
  # --- the keychain permission on a locally signed build
  ENTS=()
  while IFS= read -r e; do [[ -n "$e" ]] && ENTS+=("$D/$(tr '\\' '/' <<<"$e")"); done < <(
    grep -oE '<CodesignEntitlements[^>]*>[^<]+' "$P" | sed 's/<CodesignEntitlements[^>]*>//')   # a Condition= one too
  [[ ${#ENTS[@]} -eq 0 && -f "$M/Entitlements.plist" ]] && ENTS=("$M/Entitlements.plist")
  with=0; without=0
  for e in ${ENTS[@]+"${ENTS[@]}"}; do
    [[ -f "$e" ]] || continue
    if grep -q 'keychain-access-groups' "$e"; then with=1; else without=1; fi
  done
  if [[ $with -eq 1 && $without -eq 0 ]] && ! grep -q '<CodesignProvisioningProfile>' "$P"; then
    echo "WARN $P: the entitlements ask for keychain-access-groups and the project names no provisioning profile; macOS will not start a locally signed build that asks for it. Sign with a development certificate and profile, or give Debug builds an entitlements file without it (coding-standards-dotnet.md §9)"
    found=1
  fi
  [[ $found -eq 0 ]] && echo "OK   $P: scene manifest and delegate in place; no keychain permission a local build cannot have"
done
[[ $seen -eq 0 ]] && echo "NONE no MAUI project with a Mac Catalyst target"
[[ $fails -eq 0 ]]

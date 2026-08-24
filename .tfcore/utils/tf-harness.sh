#!/usr/bin/env bash
# TechieFlow harness answer-machine (docs/Adapter-Design.md §2.4).
#
# One deterministic place for "which harness am I in / where is the root /
# what tier is this phase / what model is that tier here". Task templates and
# scripts call this instead of hard-coding either harness's dialect.
#
# USAGE
#   tf-harness.sh detect                    -> claude-code | opencode | codex | unknown
#   tf-harness.sh root                      -> project root path
#   tf-harness.sh enabled                   -> true | false   (routing.yaml flag)
#   tf-harness.sh tier <phase|subagent>     -> frontier | standard | economy | inherit
#   tf-harness.sh model <tier> [harness]    -> model id for the tier on the harness
#   tf-harness.sh effort <tier>             -> high | medium | low
#   tf-harness.sh invoke task <name> "<args>"   -> the harness's slash form
#   tf-harness.sh invoke agent <name> "<args>"  -> the harness's invocation form
#   tf-harness.sh session                   -> the session pointer JSON for this harness
#
# Answers print on stdout; unknown answers print "unknown"/"inherit" rather than
# failing (callers embed this in prompts and next-command strings — a hard error
# there is worse than a graceful unknown). Usage errors exit 2.
#
# HARNESS DETECTION mirrors tf-emit.sh: TF_HARNESS (set by the harness bridge —
# the OpenCode plugin's shell.env — never by an agent) beats the marker-variable
# scan, which beats the /proc ancestry walk. See DECISIONS.md 2026-08-20 §3.

set +e

CMD="${1:-}"

# --- root ------------------------------------------------------------------
_root() {
  if [[ -n "${TF_PROJECT_DIR:-}" && -d "${TF_PROJECT_DIR:-}" ]]; then printf '%s' "$TF_PROJECT_DIR"; return; fi
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "${CLAUDE_PROJECT_DIR:-}" ]]; then printf '%s' "$CLAUDE_PROJECT_DIR"; return; fi
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -d "$d/.tfcore" ]] && { printf '%s' "$d"; return; }
    d="$(dirname "$d")"
  done
  printf '%s' "$PWD"
}

# --- detect ----------------------------------------------------------------
_detect() {
  case "${TF_HARNESS:-}" in claude-code|opencode|codex) printf '%s' "$TF_HARNESS"; return ;; esac
  if [[ -n "${CODEX_THREAD_ID:-}${CODEX_SESSION_ID:-}" ]]; then printf 'codex'; return; fi
  if [[ -n "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}${CLAUDE_CODE_SESSION_ID:-}${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf 'claude-code'; return
  fi
  local k
  for k in $(compgen -v | grep '^OPENCODE' 2>/dev/null); do printf 'opencode'; return; done
  # /proc ancestry walk (Linux/WSL); bounded
  local pid=$PPID name ppid seen=0 stat
  while [[ -n "$pid" && "$pid" -gt 1 && $seen -lt 12 ]]; do
    seen=$((seen + 1))
    stat="$(cat /proc/$pid/stat 2>/dev/null)" || break
    name="${stat#*(}"; name="${name%%)*}"
    ppid="$(printf '%s' "${stat##*) }" | awk '{print $2}')"
    case "$name" in
      *opencode*) printf 'opencode'; return ;;
      *codex*)    printf 'codex'; return ;;
      *claude*)   printf 'claude-code'; return ;;
    esac
    pid="$ppid"
  done
  printf 'unknown'
}

# --- routing.yaml lookups (flat two-space format — see the file header) -----
_ryaml() { printf '%s/.tfcore/routing.yaml' "$(_root)"; }

_enabled() {
  local f; f="$(_ryaml)"
  [[ -f "$f" ]] || { printf 'false'; return; }
  awk -F': *' '/^enabled:/ {print $2; found=1; exit} END {if (!found) print "false"}' "$f" | tr -d ' \r'
}

# tier for a phase or subagent name
_tier() {
  local want="$1" f; f="$(_ryaml)"
  [[ -f "$f" ]] || { printf 'inherit'; return; }
  awk -v want="$want" '
    /^[a-z]+:/ { sect=$1; sub(":", "", sect) }
    (sect=="phases" || sect=="subagents") && $1==want":" { print $2; found=1; exit }
    END { if (!found) print "inherit" }
  ' "$f" | tr -d ' \r'
}

# model id for a tier on a harness
_model() {
  local tier="$1" harness="$2" f; f="$(_ryaml)"
  [[ -f "$f" ]] || { printf 'inherit'; return; }
  local key="claude"
  [[ "$harness" == "opencode" ]] && key="opencode"
  [[ "$harness" == "codex" ]] && key="codex"
  awk -v tier="$tier" -v key="$key" '
    /^tiers:/          { in_tiers=1; next }
    /^[a-z]+:/         { in_tiers=0 }
    in_tiers && $1==tier":" { in_tier=1; next }
    in_tiers && in_tier && $1==key":" { print $2; found=1; exit }
    in_tiers && in_tier && /^  [a-z-]+:$/ { in_tier=0 }
    END { if (!found) print "inherit" }
  ' "$f" | tr -d ' \r'
}

_effort() {
  local tier="$1" f; f="$(_ryaml)"
  [[ -f "$f" ]] || return 0
  awk -v tier="$tier" '
    /^effort:/  { in_e=1; next }
    /^[a-z]+:/  { if (NR>1 && $0 !~ /^effort:/) in_e=0 }
    in_e && $1==tier":" { print $2; exit }
  ' "$f" | tr -d ' \r'
}

case "$CMD" in
  detect)  _detect;  echo ;;
  root)    _root;    echo ;;
  enabled) _enabled; echo ;;
  tier)
    [[ -n "${2:-}" ]] || { echo "usage: tf-harness.sh tier <phase|subagent>" >&2; exit 2; }
    _tier "$2"
    ;;
  model)
    [[ -n "${2:-}" ]] || { echo "usage: tf-harness.sh model <tier> [harness]" >&2; exit 2; }
    _model "$2" "${3:-$(_detect)}"
    ;;
  effort)
    [[ -n "${2:-}" ]] || { echo "usage: tf-harness.sh effort <tier>" >&2; exit 2; }
    _effort "$2"
    ;;
  invoke)
    KIND="${2:-}"; NAME="${3:-}"; ARGS="${4:-}"
    [[ -n "$KIND" && -n "$NAME" ]] || { echo "usage: tf-harness.sh invoke <task|agent> <name> [args]" >&2; exit 2; }
    H="$(_detect)"
    case "$KIND" in
      task)
        if [[ "$H" == "codex" ]]; then printf 'Use the $techieflow-%s skill with arguments: %s\n' "${NAME%-phase}" "$ARGS"
        elif [[ "$H" == "opencode" ]]; then printf '/techieflow:tasks:%s %s\n' "$NAME" "$ARGS"
        else printf '/TechieFlow:tasks:%s %s\n' "$NAME" "$ARGS"; fi
        ;;
      agent)
        if [[ "$H" == "codex" ]]; then printf 'Delegate to the `%s` Codex subagent with: %s\n' "$NAME" "$ARGS"
        elif [[ "$H" == "opencode" ]]; then printf 'opencode run --agent %s "%s"   (TUI: Tab to %s, then type: %s)\n' "$NAME" "$ARGS" "$NAME" "$ARGS"
        else printf '/TechieFlow:agents:%s %s\n' "$NAME" "$ARGS"; fi
        ;;
      *) echo "usage: tf-harness.sh invoke <task|agent> <name> [args]" >&2; exit 2 ;;
    esac
    ;;
  session)
    H="$(_detect)"
    F="$(_root)/.tfcore/.session/$H.json"
    if [[ -f "$F" ]]; then cat "$F"; else echo '{}'; fi
    ;;
  *)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
exit 0

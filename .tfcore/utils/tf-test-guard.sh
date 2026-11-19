#!/usr/bin/env bash
# tf-test-guard.sh — no seed and no test step may write to the project's own git repository (Chatur TF-037).
#
#   source .tfcore/utils/tf-test-guard.sh; tf_test_guard <project root>     # this shell and all it starts
#   bash .tfcore/utils/tf-test-guard.sh <project root> -- <command …>       # one command
#   bash .tfcore/utils/tf-test-guard.sh --ceiling <project root> -- <cmd>   # a seed: git also cannot climb out
#
# WHY. On 15 Nov a test fixture's .git folder under Chatur's tests/.artifacts/ was half deleted (objects,
# refs and config gone, HEAD and index left). git no longer counted it as a repository and walked up to
# Chatur's own; a seed then wrote four check-ins onto Chatur's main branch and made three branches there.
# A seed or a spec is the project's own code, so the rule sits under it, whatever state its folders are in:
#  - a `git` put first on PATH asks the real git which repository a command would touch. When that is the
#    project's own and the command is not a read (status, log, show, diff, rev-parse …, or the listing form
#    of branch, tag, config, remote, stash, worktree), it is refused with exit 1 and a line on stderr.
#    init and clone make a repository of their own and always run. Any other repository is left alone.
#  - with --ceiling (seeds), GIT_CEILING_DIRECTORIES holds the project's top folder: git started below it
#    never finds the project's repository at all. Not set for the unit-test run: a build reads git there.
# Not covered: a program that runs git by its full path or reads .git itself, and git run on the Windows
# side of WSL (tf-build.sh's cmd.exe and powershell rungs).
# Exit (as a runner): the command's own; 1 a write refused. Never prints a git config value.

_tfg_abs() { (cd "$1" 2>/dev/null && pwd -P); }

tf_test_guard() {   # <project root> [ceiling]
  local root="$1" ceil="${2:-}" real gd top dir here
  if [[ -n "${TF_GUARD_REPO:-}" && "$(command -v git 2>/dev/null)" == */git-guard/git ]]; then return 0; fi
  real="$(command -v git 2>/dev/null)" || return 0
  gd="$("$real" -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  gd="$(_tfg_abs "$gd")" || return 0
  top="$("$real" -C "$root" rev-parse --show-toplevel 2>/dev/null)"
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/tf-test-guard.sh"
  dir="$root/tests/.artifacts/git-guard"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '#!/usr/bin/env bash\nexec bash %q --git "$@"\n' "$here" > "$dir/git.$$" && chmod +x "$dir/git.$$" && mv -f "$dir/git.$$" "$dir/git" || return 0
  export TF_REAL_GIT="$real" TF_GUARD_REPO="$gd" PATH="$(_tfg_abs "$dir"):$PATH"
  if [[ -n "$ceil" && -n "$top" ]]; then export GIT_CEILING_DIRECTORIES="$top${GIT_CEILING_DIRECTORIES:+:$GIT_CEILING_DIRECTORIES}"; fi
}

_tfg_read() {   # <subcommand> <its arguments …>: 0 when the command only reads
  local sub="$1"; shift
  local a; local -i pos=0 list=0
  for a in "$@"; do
    case "$sub:$a" in
      branch:-[dDmMcCfu]|branch:--delete|branch:--move|branch:--copy|branch:--force|branch:--set-upstream-to*|branch:--unset-upstream|branch:--edit-description|branch:--track*) return 1 ;;
      tag:-[dasumFf]|tag:--delete|tag:--annotate|tag:--sign|tag:--force|tag:--message*|tag:--file*) return 1 ;;
      *:-l|*:--list|*:-a|*:-r|*:--all|*:--remotes|*:--show-current|*:--contains*|*:--no-contains*|*:--merged*|*:--no-merged*|*:--points-at*) list=1 ;;
      *:-*) ;;
      *) pos=$((pos+1)) ;;
    esac
  done
  case "$sub" in
    status|log|show|diff|rev-parse|ls-files|ls-tree|ls-remote|cat-file|rev-list|for-each-ref|show-ref|describe|blame|grep|merge-base|name-rev|shortlog|whatchanged|version|help|var|check-ignore|check-attr|count-objects|diff-tree|diff-files|diff-index|cherry|show-branch|--version|--help) return 0 ;;
    branch|tag) [[ $pos -eq 0 || $list -eq 1 ]] ;;
    config) [[ " $* " == *" --get"* || " $* " == *" --list "* || " $* " == *" -l "* || "${1:-}" == get || "${1:-}" == list ]] ;;
    remote) [[ $# -eq 0 || "$1" == -v || "$1" == show || "$1" == get-url ]] ;;
    stash) [[ "${1:-}" == list || "${1:-}" == show ]] ;;
    worktree) [[ "${1:-}" == list ]] ;;
    reflog|notes) [[ $# -eq 0 || "$1" == show || "$1" == list ]] ;;
    symbolic-ref) [[ $pos -le 1 && " $* " != *" -d "* && " $* " != *" --delete "* ]] ;;
    *) return 1 ;;
  esac
}

_tfg_git() {   # the `git` on PATH while guarded
  local real="${TF_REAL_GIT:-}" sub="" a gd
  local -a glob=()
  [[ -x "$real" ]] || { echo "tf-test-guard: the real git is not known (TF_REAL_GIT); refused: git $*" >&2; return 1; }
  local -a args=("$@")
  local i=0 n=${#args[@]}
  while [[ $i -lt $n ]]; do
    a="${args[$i]}"
    case "$a" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--config-env) glob+=("$a" "${args[$((i+1))]:-}"); i=$((i+2)) ;;
      -*) glob+=("$a"); i=$((i+1)) ;;
      *) sub="$a"; break ;;
    esac
  done
  if [[ -z "$sub" || "$sub" == init || "$sub" == clone ]]; then exec "$real" "$@"; fi
  if _tfg_read "$sub" "${args[@]:$((i+1))}"; then exec "$real" "$@"; fi
  gd="$("$real" ${glob[@]+"${glob[@]}"} rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exec "$real" "$@"
  gd="$(_tfg_abs "$gd")"
  if [[ -n "$gd" && "$gd" == "${TF_GUARD_REPO:-}" ]]; then
    echo "tf-test-guard: refused \`git $sub\`: it would write to the project's own repository ($(dirname "$gd")). A seed or a test writes only to a repository of its own, under tests/.artifacts/; when its .git folder is broken, git finds the project's instead (Chatur TF-037)." >&2
    return 1
  fi
  exec "$real" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" == --git ]]; then shift; _tfg_git "$@"; exit $?; fi
  ceil=""; [[ "${1:-}" == --ceiling ]] && { ceil=1; shift; }
  root="${1:?usage: tf-test-guard.sh [--ceiling] <project root> -- <command …>}"; shift
  [[ "${1:-}" == -- ]] && shift
  [[ $# -gt 0 ]] || { echo "tf-test-guard: no command given" >&2; exit 2; }
  tf_test_guard "$root" "$ceil"
  exec "$@"
fi

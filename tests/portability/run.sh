#!/usr/bin/env bash
# tests/portability/run.sh — keeps every shell script runnable on a stock Mac.
#
# A stock Mac has bash 3.2 at /bin/bash and the BSD sed, date, stat, xargs, grep and find, with
# no GNU coreutils. This check fails when a script outside the shim library
# (.tfcore/utils/tf-portable.sh) uses a GNU-only command, a GNU-only option, a GNU-only regex
# escape or a bash-4-only feature, and names the shim function or the portable spelling to use.
# Then it runs the shim's own unit tests (shim-tests.sh, next to this file).
#
#   bash tests/portability/run.sh              scan + shim unit tests
#   bash tests/portability/run.sh --scan-only  scan only
#
# A line that must keep a flagged construct (it sits inside embedded Python, or it is guarded)
# goes in exceptions.txt next to this file, with a comment saying why. Exit 0 = clean.
#
# Not checkable with a pattern, so reviewed by hand and listed in docs/Mac-Portability-Progress.md:
# "${arr[@]}" of an EMPTY array under `set -u` (an unbound-variable error before bash 4.4 — use
# ${arr[@]+"${arr[@]}"}), and `wc` output compared as text (BSD wc pads it with blanks).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCAN_ONLY=0; [[ "${1:-}" == "--scan-only" ]] && SCAN_ONLY=1
EXCEPTIONS="$HERE/exceptions.txt"

# id @@ extended regex (POSIX classes only: this runs under BSD grep too) @@ what to use instead
# A boundary that is not part of a longer word, path or option name:
B='(^|[^A-Za-z0-9_./-])'
RULES=(
  "timeout@@${B}g?timeout[[:space:]]+(-[A-Za-z-]+[[:space:]]+)*[0-9]@@tf_timeout (macOS has no timeout)"
  "setsid@@${B}setsid([^A-Za-z0-9_]|\$)@@tf_setsid (macOS has no setsid)"
  "sed-inplace@@${B}sed[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-[A-Za-z]*i|--in-place)@@tf_sed_inplace (BSD sed -i needs a backup suffix)"
  "sed-gnu-regex@@${B}sed[[:space:]].*(\\\\[sSwW+?|nt]|['\"]0,/)@@[[:space:]] / [^[:space:]] / * and -E; no 0,/re/ address, no \\n or \\t in a replacement (GNU sed only)"
  "stat-format@@${B}stat[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-c|--format|--printf|-f[[:space:]]*['\"]?%)@@tf_stat_mtime / tf_stat_size (stat -c is GNU, stat -f is BSD)"
  "date-parse@@${B}date[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-d|--date|-r)([[:space:]=]|\$)@@tf_date_from (date -d is GNU; BSD date -r takes seconds, not a file)"
  "date-nanoseconds@@${B}date[[:space:]][^|;)]*%[0-9]*N@@tf_epoch_frac (BSD date has no %N)"
  "touch-date@@${B}touch[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-d|--date)@@touch -t \"\$(tf_date_from WHEN +%Y%m%d%H%M.%S)\" (touch -d is GNU)"
  "xargs-r@@${B}xargs[[:space:]]+(-[A-Za-z0-9]+[[:space:]]+)*(-[A-Za-z0-9]*r|--no-run-if-empty)@@skip the call when the input is empty (BSD xargs has no -r)"
  "readlink-f@@${B}readlink[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*[fem]@@tf_realpath"
  "realpath@@${B}realpath([^A-Za-z0-9_]|\$)@@tf_realpath / tf_relpath (no realpath before macOS 13, no --relative-to on any Mac)"
  "grep-perl@@${B}[ef]?grep[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-[A-Za-z]*P|--perl-regexp)@@grep -E (BSD grep has no -P)"
  "grep-gnu-regex@@${B}[ef]?grep[[:space:]].*\\\\[sSwWbB<>]@@[[:space:]], [A-Za-z0-9_] or explicit boundaries (\\s \\w \\b are GNU grep extensions)"
  "grep-bre-alternation@@${B}grep[[:space:]]+(-[A-DF-Za-z]+[[:space:]]+)*('[^']*\\\\\\||\"[^\"]*\\\\\\|)@@grep -E 'a|b' (\\| in a basic regex is a GNU extension)"
  "find-gnu@@${B}find[[:space:]].*-(printf|fprintf|regextype|readable|writable|executable|xtype)([[:space:]]|\$)@@a loop over find -print, or a portable test"
  "mktemp-gnu@@${B}mktemp[[:space:]].*(--suffix|--tmpdir|-p[[:space:]])@@mktemp with a template, or mktemp -d and a name inside it"
  "gnu-only-tool@@${B}(md5sum|sha1sum|sha256sum|tac|nproc|numfmt|flock|shuf|truncate)([^A-Za-z0-9_.-]|\$)@@a portable alternative (not on a stock Mac)"
  "gnu-only-option@@(base64[[:space:]]+-w|${B}cp[[:space:]].*--parents|${B}ln[[:space:]]+-[A-Za-z]*r|(^|[;&|(][[:space:]]*)install[[:space:]]+-D|${B}head[[:space:]]+-n[[:space:]]*-[0-9]|${B}du[[:space:]]+-[A-Za-z]*b|${B}sort[[:space:]].*(-V|--version-sort)|${B}xargs[[:space:]].*(-d[[:space:]]|--delimiter)|${B}sed[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*r[[:space:]])@@the portable option (GNU-only option)"
  "pgrep-a@@${B}pgrep[[:space:]]+(.*[[:space:]])?-[A-Za-z]*a([[:space:]]|\$)@@ps -A -o args= | grep (pgrep -a lists command lines on Linux only)"
  "proc-fs@@/proc/@@guard it: macOS has no /proc"
  "mapfile@@${B}(mapfile|readarray)([^A-Za-z0-9_]|\$)@@tf_read_lines (bash 4)"
  "assoc-array@@(^|[^A-Za-z0-9_])(declare|local|typeset)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*A@@plain arrays or a case statement (bash 4)"
  "nameref@@(^|[^A-Za-z0-9_])(declare|local|typeset)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*n([[:space:]]|\$)@@eval with a checked name (bash 4.3)"
  "declare-glu@@(^|[^A-Za-z0-9_])(declare|local|typeset)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*[glu]([[:space:]]|\$)@@a plain assignment, tr for case (bash 4)"
  "case-modification@@\\\$\\{[A-Za-z_][A-Za-z0-9_]*(\\[[^]]*\\])?(,,?|\\^\\^?)[^}]*\\}@@tr '[:upper:]' '[:lower:]' (bash 4)"
  "param-transform@@\\\$\\{[A-Za-z_][A-Za-z0-9_]*(\\[[^]]*\\])?@[QEPAaUuLK]\\}@@printf %q, or spell it out (bash 4.4)"
  "negative-index@@\\\$\\{#?[A-Za-z_][A-Za-z0-9_]*\\[-[0-9]+\\]@@\${arr[\${#arr[@]}-1]} (bash 4.3)"
  "test-v@@\\[\\[?[[:space:]]+-v[[:space:]]@@[[ -n \"\${var+set}\" ]] (bash 4.2)"
  "printf-time@@%\\([^)]*\\)T@@date (bash 4.2)"
  "printf-v-array@@${B}printf[[:space:]]+-v[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\\[@@printf into a plain variable, then assign (bash 4.1)"
  "bash4-variable@@\\\$\\{?(EPOCHSECONDS|EPOCHREALTIME|BASHPID|BASH_ARGV0|SRANDOM)@@date +%s, \$\$ or sh -c 'echo \$PPID' (bash 4+)"
  "wait-n@@(^|[^A-Za-z0-9_])wait[[:space:]]+-[A-Za-z]*n@@wait for a named pid (bash 4.3)"
  "amp-redirect@@&>>|\\|&@@>>file 2>&1 and 2>&1 | (bash 4)"
  "coproc@@(^|[^A-Za-z0-9_])coproc([^A-Za-z0-9_]|\$)@@a background job and a fifo (bash 4)"
  "shopt-bash4@@globstar|lastpipe|autocd|direxpand|checkjobs|dirspell|compat4[0-9]@@find (bash 4 shell option)"
  "case-fallthrough@@;;&|;&[[:space:]]*(\$|#)@@repeat the branch (bash 4)"
  "brace-range@@\\{-?0[0-9]+\\.\\.[0-9-]+\\}|\\{[^{} ]*\\.\\.[^{} ]*\\.\\.[^{} ]*\\}@@seq, or a while loop (bash 4 zero-padded or stepped ranges)"
  "auto-fd@@\\{[A-Za-z_][A-Za-z0-9_]*\\}(<|>|<>|>>|>&-|<&-)@@a fixed descriptor number (bash 4.1)"
  "read-bash4@@(^|[^A-Za-z0-9_])read[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-t[[:space:]]*[0-9]*\\.|-[A-Za-z]*[Ni])@@whole-second -t, no -N or -i (bash 4)"
)

# ---- the files: every .sh in the repository except the shim and this folder
FILES=()
while IFS= read -r f; do FILES[${#FILES[@]}]="$f"; done < <(
  cd "$ROOT" && find . \( -name .git -o -name node_modules -o -path ./tests/.artifacts \) -prune -o -name '*.sh' -type f -print \
    | sed 's#^\./##' | grep -v '^\.tfcore/utils/tf-portable\.sh$' | grep -v '^tests/portability/' | LC_ALL=C sort)

# ---- exceptions: "<rule-id> <path> <text the line contains>", one per line, # comments allowed
EXC=()
if [[ -f "$EXCEPTIONS" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in ''|'#'*) continue ;; esac
    EXC[${#EXC[@]}]="$line"
  done < "$EXCEPTIONS"
fi
USED=()
excepted() { # rule path text -> 0 when an exception covers it
  local i e rid rpath rtext
  i=0
  while [[ $i -lt ${#EXC[@]} ]]; do
    e="${EXC[$i]}"; rid="${e%% *}"; e="${e#* }"; rpath="${e%% *}"; rtext="${e#* }"
    if [[ "$rid" == "$1" && "$rpath" == "$2" && "$3" == *"$rtext"* ]]; then USED[$i]=1; return 0; fi
    i=$((i + 1))
  done
  return 1
}

FOUND=0
REPORT=""
cd "$ROOT" || exit 2
for rule in "${RULES[@]}"; do
  id="${rule%%@@*}"; rest="${rule#*@@}"; advice="${rest##*@@}"; re="${rest%@@*}"
  hits="$(grep -nE -- "$re" "${FILES[@]}" 2>/dev/null)"
  [[ -z "$hits" ]] && continue
  while IFS= read -r hit; do
    path="${hit%%:*}"; rest2="${hit#*:}"; lineno="${rest2%%:*}"; text="${rest2#*:}"
    case "$text" in *[![:space:]]*) ;; *) continue ;; esac
    stripped="$(printf '%s' "$text" | sed 's/^[[:space:]]*//')"
    case "$stripped" in '#'*) continue ;; esac      # a shell comment line
    excepted "$id" "$path" "$text" && continue
    FOUND=$((FOUND + 1))
    REPORT="${REPORT}${path}:${lineno}: [${id}] $(printf '%s' "$stripped" | cut -c1-150)
      use: ${advice}
"
  done <<< "$hits"
done

# ---- here-documents inside $( ) or <( ): bash 3.2 reads their text for quotes and brackets,
# so an apostrophe or a lone ")" in the embedded program breaks the script on a Mac.
if command -v python3 >/dev/null 2>&1; then
  hd="$(python3 "$HERE/heredoc-scan.py" "${FILES[@]}")"
  if [[ -n "$hd" ]]; then
    while IFS= read -r hit; do
      path="${hit%%:*}"; rest2="${hit#*:}"; lineno="${rest2%%:*}"; text="${rest2#*:}"
      excepted heredoc-in-substitution "$path" "$text" && continue
      FOUND=$((FOUND + 1))
      REPORT="${REPORT}${path}:${lineno}: [heredoc-in-substitution]${text}
      use: read the program into a variable first (IFS= read -r -d '' PROG <<'EOF' ... EOF), then python3 -c \"\$PROG\"
"
    done <<< "$hd"
  fi
else
  echo "note  python3 not found: the here-document check was skipped"
fi

# ---- exceptions that no longer match anything are stale
STALE=0
i=0
while [[ $i -lt ${#EXC[@]} ]]; do
  if [[ -z "${USED[$i]:-}" ]]; then
    echo "stale exception (matches nothing any more; remove it from tests/portability/exceptions.txt): ${EXC[$i]}"
    STALE=$((STALE + 1))
  fi
  i=$((i + 1))
done

SCAN_RC=0
if [[ $FOUND -gt 0 ]]; then
  printf '%s' "$REPORT"
  echo "portability: $FOUND non-portable use(s) in ${#FILES[@]} script(s). Use the function or spelling named above, or add a commented exception to tests/portability/exceptions.txt when the line is guarded."
  SCAN_RC=1
elif [[ $STALE -gt 0 ]]; then
  echo "portability: $STALE stale exception(s)"; SCAN_RC=1
else
  echo "portability: no GNU-only or bash-4-only construct in ${#FILES[@]} script(s) (${#EXC[@]} commented exception(s))"
fi

[[ $SCAN_ONLY -eq 1 ]] && exit $SCAN_RC
# the shim tests run either way, so a failing scan does not hide how the shim behaves here
bash "$HERE/shim-tests.sh" || exit 1
exit $SCAN_RC

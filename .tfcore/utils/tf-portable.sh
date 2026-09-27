# tf-portable.sh — the few commands that differ between Linux/WSL (GNU tools, bash 4+) and a
# stock Mac (bash 3.2 at /bin/bash, BSD sed/date/stat, no GNU coreutils). Sourced, not run:
#   source "$(dirname "${BASH_SOURCE[0]}")/tf-portable.sh"
# Every function uses the native tool when it is there, so Linux and WSL behave exactly as they
# did before this file existed; the fallback runs only where the native tool is missing.
# Plain functions only: sourcing it defines functions and nothing else (no variables, no traps,
# no set options). Bash 3.2 safe. The check tests/portability/run.sh keeps GNU-only and
# bash-4-only constructs out of every other script; add a function here instead.
#
#   tf_timeout DURATION CMD [ARG...]     timeout(1); 124 when the time runs out
#   tf_setsid [--exec] CMD [ARG...]      setsid(1); --exec replaces the calling (sub)shell
#   tf_sed_inplace SED-ARG... FILE       sed -i on GNU and BSD sed, no backup file left behind
#   tf_stat_mtime FILE                   modification time, epoch seconds
#   tf_stat_size FILE                    size in bytes
#   tf_date_from [-u] WHEN [+FORMAT]     date -d WHEN; WHEN is @EPOCH, "-10 min", "+2 hours",
#                                        "now", or YYYY-MM-DD[( |T)HH:MM[:SS]][Z]
#   tf_epoch_frac                        seconds since the epoch with a fraction (date +%s.%N)
#   tf_realpath PATH                     realpath(1)
#   tf_relpath BASE PATH                 realpath --relative-to=BASE PATH
#   tf_read_lines ARRAY-NAME             mapfile -t ARRAY-NAME (reads stdin)

# ---- tf_timeout ---------------------------------------------------------------------------
# GNU timeout, then Homebrew's gtimeout, then a perl fallback (perl ships with macOS). The
# fallback runs the command in its own process group, sends the group TERM when the time is up
# and exits 124, the code timeout(1) uses; otherwise it exits with the command's own status
# (128+N when signal N ended it), and 126/127 when the command cannot be run, as timeout(1) does.
tf_timeout() {
  if [ $# -lt 2 ]; then echo "tf_timeout: usage: tf_timeout DURATION COMMAND [ARG...]" >&2; return 125; fi
  if command -v timeout >/dev/null 2>&1; then timeout "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"; return $?; fi
  _tf_timeout_perl "$@"
}
_tf_timeout_perl() {
  local dur="$1" secs; shift
  case "$dur" in
    *s) secs="${dur%s}" ;;
    *m) secs="$(awk -v n="${dur%m}" 'BEGIN { print n * 60 }')" ;;
    *h) secs="$(awk -v n="${dur%h}" 'BEGIN { print n * 3600 }')" ;;
    *d) secs="$(awk -v n="${dur%d}" 'BEGIN { print n * 86400 }')" ;;
    *) secs="$dur" ;;
  esac
  case "$secs" in ''|*[!0-9.]*) echo "tf_timeout: invalid time interval '$dur'" >&2; return 125 ;; esac
  perl -e '
    use strict; use POSIX ();
    my $secs = shift @ARGV;
    my $pid = fork();
    if (!defined $pid) { print STDERR "tf_timeout: fork failed: $!\n"; exit 125; }
    if ($pid == 0) {
      setpgrp(0, 0);   # its own process group, so the whole tree is stopped, as timeout(1) does
      exec { $ARGV[0] } @ARGV;
      my $code = $!{ENOENT} ? 127 : 126;
      print STDERR "tf_timeout: failed to run command \x27$ARGV[0]\x27: $!\n";
      POSIX::_exit($code);
    }
    my $fired = 0;
    $SIG{ALRM} = sub { $fired = 1; kill("TERM", -$pid) or kill("TERM", $pid); };
    $SIG{TERM} = sub { kill "TERM", $pid; };
    $SIG{INT}  = sub { kill "INT", $pid; };
    if ($secs > 0) {
      my $whole = int($secs); $whole++ if $whole < $secs;   # alarm takes whole seconds; round up
      alarm($whole);
    }
    my $got;
    do { $got = waitpid($pid, 0); } while ($got == -1 && $!{EINTR});
    my $status = $?;
    alarm(0);
    exit 124 if $fired;
    exit(128 + ($status & 127)) if $status & 127;
    exit($status >> 8);
  ' "$secs" "$@"
}

# ---- tf_setsid ----------------------------------------------------------------------------
# util-linux setsid, then python3 os.setsid, then perl POSIX::setsid. As setsid(1) does, a
# caller that already leads a process group is forked first and the parent returns 0 at once.
# --exec: replace the calling (sub)shell with it, like `exec setsid CMD`.
tf_setsid() {
  local ex=""
  if [ "${1:-}" = "--exec" ]; then ex=exec; shift; fi
  if [ $# -lt 1 ]; then echo "tf_setsid: usage: tf_setsid [--exec] COMMAND [ARG...]" >&2; return 1; fi
  if command -v setsid >/dev/null 2>&1; then $ex setsid "$@"
  elif command -v python3 >/dev/null 2>&1; then $ex python3 -c "$(_tf_setsid_py)" "$@"
  elif command -v perl >/dev/null 2>&1; then $ex perl -e "$(_tf_setsid_pl)" "$@"
  else echo "tf_setsid: needs setsid, python3 or perl; none is on PATH" >&2; return 127
  fi
}
_tf_setsid_py() {
  printf '%s\n' \
    'import os, sys' \
    'if os.getpgrp() == os.getpid():' \
    '    if os.fork() != 0:' \
    '        os._exit(0)' \
    'os.setsid()' \
    'try:' \
    '    os.execvp(sys.argv[1], sys.argv[1:])' \
    'except OSError as e:' \
    '    sys.stderr.write("setsid: failed to execute %s: %s\n" % (sys.argv[1], e.strerror))' \
    '    os._exit(127 if e.errno == 2 else 126)'
}
_tf_setsid_pl() {
  printf '%s\n' \
    'use POSIX ();' \
    'if (getpgrp() == $$) { my $p = fork(); POSIX::_exit(0) if $p; }' \
    'POSIX::setsid();' \
    'exec { $ARGV[0] } @ARGV;' \
    'my $c = $!{ENOENT} ? 127 : 126;' \
    'print STDERR "setsid: failed to execute $ARGV[0]: $!\n";' \
    'POSIX::_exit($c);'
}

# ---- tf_sed_inplace -----------------------------------------------------------------------
# GNU sed takes -i alone; BSD sed needs -i '' for "no backup". The sed script itself must be
# one both seds understand (no \s, \+, \n in a replacement, 0,/re/ addresses).
tf_sed_inplace() {
  if [ $# -lt 2 ]; then echo "tf_sed_inplace: usage: tf_sed_inplace SED-ARG... FILE" >&2; return 2; fi
  if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi
}

# ---- tf_stat_mtime / tf_stat_size ---------------------------------------------------------
tf_stat_mtime() {
  if stat -c %Y / >/dev/null 2>&1; then stat -c %Y "$1"; else stat -f %m "$1"; fi
}
tf_stat_size() {
  if stat -c %s / >/dev/null 2>&1; then stat -c %s "$1"; else stat -f %z "$1"; fi
}

# ---- tf_date_from -------------------------------------------------------------------------
# GNU date reads almost anything with -d; BSD date reads @EPOCH with -r and a fixed layout
# with -j -f. The WHEN forms listed at the top cover every caller in this framework. On GNU
# date the WHEN is handed to date -d unchanged, so the output is exactly what it was.
tf_date_from() {
  local utc="" when fmt epoch
  if [ "${1:-}" = "-u" ]; then utc="-u"; shift; fi
  when="${1:-}"; fmt="${2:-}"
  if [ -z "$when" ]; then echo "tf_date_from: usage: tf_date_from [-u] WHEN [+FORMAT]" >&2; return 1; fi
  if date -d @0 +%s >/dev/null 2>&1; then
    if [ -n "$fmt" ]; then date $utc -d "$when" "$fmt"; else date $utc -d "$when"; fi
    return $?
  fi
  epoch="$(_tf_date_epoch $utc "$when")" || return 1
  if [ -n "$fmt" ]; then date $utc -r "$epoch" "$fmt"; else date $utc -r "$epoch"; fi
}
# WHEN → epoch seconds without GNU date -d. @EPOCH, now and relative offsets are plain
# arithmetic; an absolute date goes through BSD date -j -f (GNU date on a machine that has it).
_tf_date_epoch() {
  local utc="" when now n unit mult value layout
  if [ "${1:-}" = "-u" ]; then utc="-u"; shift; fi
  when="$1"; now="$(date +%s)"
  case "$when" in
    now) echo "$now"; return 0 ;;
    @*) echo "${when#@}"; return 0 ;;
  esac
  case "$when" in
    [+-][0-9]*|[0-9]*[a-z]*)
      n="$(printf '%s' "$when" | sed -E 's/^([+-]?[0-9]+).*/\1/')"
      unit="$(printf '%s' "$when" | sed -E 's/^[+-]?[0-9]+[[:space:]]*//; s/[[:space:]]*ago$//')"
      case "$unit" in
        s|sec|secs|second|seconds) mult=1 ;;
        min|mins|minute|minutes) mult=60 ;;
        hour|hours) mult=3600 ;;
        day|days) mult=86400 ;;
        week|weeks) mult=604800 ;;
        *) mult="" ;;
      esac
      if [ -n "$mult" ]; then
        n="${n#+}"
        case "$when" in *ago) n=$(( -n )) ;; esac
        echo $(( now + n * mult )); return 0
      fi ;;
  esac
  value="$when"; layout=""
  case "$value" in *Z) value="${value%Z}"; utc="-u" ;; esac
  value="$(printf '%s' "$value" | sed 's/T/ /')"
  case "$value" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) value="$value 00:00:00" ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "[0-9][0-9]:[0-9][0-9]) value="$value:00" ;;
  esac
  case "$value" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]) layout="%Y-%m-%d %H:%M:%S" ;;
  esac
  if [ -z "$layout" ]; then echo "date: invalid date '$when'" >&2; return 1; fi
  if date -d @0 +%s >/dev/null 2>&1; then date $utc -d "$value" +%s; else date $utc -j -f "$layout" "$value" +%s; fi
}

# ---- tf_epoch_frac ------------------------------------------------------------------------
# GNU date +%s.%N; BSD date prints a literal N, so the fallback asks perl or python3.
tf_epoch_frac() {
  local v
  v="$(date +%s.%N 2>/dev/null)"
  case "$v" in *N|'') ;; *) printf '%s\n' "$v"; return 0 ;; esac
  if command -v perl >/dev/null 2>&1; then perl -MTime::HiRes=time -e 'printf("%.9f\n", time)'
  else python3 -c 'import time; print("%.9f" % time.time())'
  fi
}

# ---- tf_realpath / tf_relpath -------------------------------------------------------------
tf_realpath() {
  if [ $# -ne 1 ]; then echo "tf_realpath: usage: tf_realpath PATH" >&2; return 1; fi
  if command -v realpath >/dev/null 2>&1 && realpath / >/dev/null 2>&1; then realpath "$1"; return $?; fi
  python3 -c 'import os, sys
p = sys.argv[1]
if not os.path.exists(os.path.dirname(os.path.abspath(p)) or "/"):
    sys.stderr.write("realpath: %s: No such file or directory\n" % p); sys.exit(1)
print(os.path.realpath(p))' "$1"
}
tf_relpath() {
  if [ $# -ne 2 ]; then echo "tf_relpath: usage: tf_relpath BASE PATH" >&2; return 1; fi
  if realpath --relative-to=/ / >/dev/null 2>&1; then realpath --relative-to="$1" "$2"; return $?; fi
  python3 -c 'import os, sys
print(os.path.relpath(os.path.realpath(sys.argv[2]), os.path.realpath(sys.argv[1])))' "$1" "$2"
}

# ---- tf_read_lines ------------------------------------------------------------------------
# mapfile -t NAME < <(cmd)  becomes  tf_read_lines NAME < <(cmd)
# One element per line, newline removed, a last line without a newline kept, nothing else
# touched (leading blanks and backslashes stay). NAME is emptied first, as mapfile does.
tf_read_lines() {
  case "${1:-}" in
    ''|[0-9]*|*[!A-Za-z0-9_]*) echo "tf_read_lines: usage: tf_read_lines ARRAY-NAME < input" >&2; return 2 ;;
  esac
  local _tf_rl_line _tf_rl_i=0
  eval "$1=()"
  while IFS= read -r _tf_rl_line || [ -n "$_tf_rl_line" ]; do
    eval "$1[\$_tf_rl_i]=\$_tf_rl_line"
    _tf_rl_i=$(( _tf_rl_i + 1 ))
  done
  return 0
}

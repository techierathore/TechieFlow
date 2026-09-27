#!/usr/bin/env bash
# tests/portability/shim-tests.sh — unit tests for .tfcore/utils/tf-portable.sh.
# Each function is tested through its public name (the native tool on this machine) and, where
# the fallback can run here too, through the fallback directly, so a Linux run also proves the
# code a Mac takes. Bash 3.2 safe. Exit 0 = every case passed. Run by tests/portability/run.sh.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SHIM="$ROOT/.tfcore/utils/tf-portable.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
is()  { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/tf-portable-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# ---- sourcing has no side effects: no new variables, traps or shell options
bash -c '
  compgen -v | grep -v "^PIPESTATUS\$" | LC_ALL=C sort > "$1/vars.before"; set -o > "$1/opts.before"; trap -p > "$1/traps.before"
  source "$2"
  compgen -v | grep -v "^PIPESTATUS\$" | LC_ALL=C sort > "$1/vars.after"; set -o > "$1/opts.after"; trap -p > "$1/traps.after"
' _ "$WORK" "$SHIM"
if cmp -s "$WORK/vars.before" "$WORK/vars.after" && cmp -s "$WORK/opts.before" "$WORK/opts.after" \
   && cmp -s "$WORK/traps.before" "$WORK/traps.after"; then ok "sourcing sets no variable, option or trap"
else bad "sourcing changed variables, options or traps"; fi

# shellcheck source=/dev/null
source "$SHIM"

# ---- tf_timeout, native and the perl fallback
for fn in tf_timeout _tf_timeout_perl; do
  if [[ "$fn" == _tf_timeout_perl ]] && ! command -v perl >/dev/null 2>&1; then echo "skip $fn (no perl)"; continue; fi
  t0=$(date +%s); $fn 1 sleep 10; rc=$?; t1=$(date +%s)
  is "$fn: a command that runs out of time exits 124" "$rc" 124
  if [[ $((t1 - t0)) -le 4 ]]; then ok "$fn: stops it at the limit ($((t1 - t0))s)"; else bad "$fn: took $((t1 - t0))s for a 1s limit"; fi
  $fn 5 sh -c 'exit 3'; is "$fn: passes the command's own exit code" "$?" 3
  $fn 5 true; is "$fn: 0 when the command succeeds in time" "$?" 0
  is "$fn: the command reads the caller's stdin" "$(printf 'in\n' | $fn 5 cat)" "in"
  $fn 5 tf-no-such-command-xyz 2>/dev/null; is "$fn: 127 for a command that does not exist" "$?" 127
  $fn 2s true; is "$fn: takes a duration with a unit (2s)" "$?" 0
  rc="$( { $fn 5 sh -c 'kill -TERM $$'; echo $?; } 2>/dev/null )"
  is "$fn: 128+N when signal N ends the command" "$rc" 143
done
is "tf_timeout: usage error without a command" "$(tf_timeout 5 2>/dev/null; echo $?)" 125

# ---- with the native tools taken off PATH, the public functions pick the fallbacks
mkdir -p "$WORK/bin"
for t in perl python3 sleep sh awk cat ps tr; do
  p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$WORK/bin/$t"
done
( PATH="$WORK/bin"; tf_timeout 1 sleep 5; echo $? ) > "$WORK/fb" 2>&1
is "tf_timeout without timeout(1) on PATH: falls back, 124" "$(cat "$WORK/fb")" 124
( PATH="$WORK/bin"; tf_setsid sh -c 'echo "$$ $(ps -o pgid= -p $$)"' ) > "$WORK/fb" 2>&1
out="$(cat "$WORK/fb")"
is "tf_setsid without setsid(1) on PATH: falls back" "$(printf '%s' "${out#* }" | tr -d ' ')" "${out%% *}"
mkdir -p "$WORK/fbreal/x"; ln -s "$WORK/fbreal/x" "$WORK/fblink"
is "tf_realpath without realpath(1) on PATH: falls back" "$( PATH="$WORK/bin"; tf_realpath "$WORK/fblink" )" "$(cd -P "$WORK/fbreal/x" && pwd)"
is "tf_relpath without realpath(1) on PATH: falls back" "$( PATH="$WORK/bin"; tf_relpath "$WORK/fbreal" "$WORK/fblink" )" "x"

# ---- tf_setsid: the command leads a new session, so it is its own process-group leader
setsid_check() { # label, then the runner words
  local label="$1"; shift
  local out pid pgid
  out="$("$@" sh -c 'echo "$$ $(ps -o pgid= -p $$)"' 2>&1)"
  pid="${out%% *}"; pgid="$(printf '%s' "${out#* }" | tr -d ' ')"
  is "$label: the command leads its own process group" "$pgid" "$pid"
}
setsid_check "tf_setsid" tf_setsid
out="$( (tf_setsid --exec sh -c 'echo "$$ $(ps -o pgid= -p $$)"') )"
is "tf_setsid --exec: runs in a new process group" "$(printf '%s' "${out#* }" | tr -d ' ')" "${out%% *}"
if command -v python3 >/dev/null 2>&1; then setsid_check "tf_setsid python3 fallback" python3 -c "$(_tf_setsid_py)"; fi
if command -v perl >/dev/null 2>&1; then setsid_check "tf_setsid perl fallback" perl -e "$(_tf_setsid_pl)"; fi
( tf_setsid sh -c 'exit 7' ); rc=$?
if [[ $rc -eq 7 || $rc -eq 0 ]]; then ok "tf_setsid: returns (rc $rc)"; else bad "tf_setsid: rc $rc"; fi
python3 -c "$(_tf_setsid_py)" tf-no-such-command-xyz 2>/dev/null; is "tf_setsid python3 fallback: 127 for a missing command" "$?" 127

# ---- tf_sed_inplace
mkdir -p "$WORK/sed"; printf 'alpha\nbeta\n' > "$WORK/sed/f.txt"
tf_sed_inplace 's/beta/gamma/' "$WORK/sed/f.txt"
is "tf_sed_inplace: edits the file" "$(cat "$WORK/sed/f.txt")" "alpha
gamma"
tf_sed_inplace -E 's/(al)pha/\1ways/' "$WORK/sed/f.txt"
is "tf_sed_inplace: takes sed options before the script" "$(head -1 "$WORK/sed/f.txt")" "always"
is "tf_sed_inplace: leaves no backup file" "$(ls "$WORK/sed" | tr '\n' ' ')" "f.txt "

# ---- tf_stat_mtime / tf_stat_size
printf 'abcde' > "$WORK/five"
is "tf_stat_size: bytes" "$(tf_stat_size "$WORK/five")" 5
touch -t 202001020304.05 "$WORK/five"
is "tf_stat_mtime: epoch seconds" "$(tf_stat_mtime "$WORK/five")" "$(tf_date_from 2020-01-02T03:04:05 +%s)"
tf_stat_size "$WORK/missing" >/dev/null 2>&1; [[ $? -ne 0 ]] && ok "tf_stat_size: fails on a missing file" || bad "tf_stat_size: missing file succeeded"

# ---- tf_date_from, and _tf_date_epoch (the arithmetic a Mac uses)
is "tf_date_from: @EPOCH in UTC" "$(tf_date_from -u @0 +%Y-%m-%dT%H:%M:%SZ)" "1970-01-01T00:00:00Z"
is "tf_date_from: ISO with Z" "$(tf_date_from -u 2026-01-01T10:20:30Z +%s)" 1767262830
is "tf_date_from: a date alone is midnight" "$(tf_date_from -u 2026-01-01 +%s)" 1767225600
is "tf_date_from: date and minutes" "$(tf_date_from -u '2026-01-01 10:20' +%H:%M:%S)" "10:20:00"
now=$(date +%s); got=$(tf_date_from -u '-10 min' +%s); d=$(( now - 600 - got ))
if [[ ${d#-} -le 2 ]]; then ok "tf_date_from: -10 min"; else bad "tf_date_from: -10 min off by $d s"; fi
now=$(date +%s); got=$(tf_date_from '+2 hours' +%s); d=$(( now + 7200 - got ))
if [[ ${d#-} -le 2 ]]; then ok "tf_date_from: +2 hours"; else bad "tf_date_from: +2 hours off by $d s"; fi
tf_date_from -u 'not a date' +%s >/dev/null 2>&1; [[ $? -ne 0 ]] && ok "tf_date_from: fails on nonsense" || bad "tf_date_from: accepted nonsense"
is "_tf_date_epoch: @N" "$(_tf_date_epoch -u @1234)" 1234
for w in '-5 min' '-10 minutes' '+1 min' '-3 days' '-1 hour' '3 days ago' '+15 min'; do
  a=$(_tf_date_epoch -u "$w"); b=$(tf_date_from -u "$w" +%s); d=$(( a - b ))
  if [[ ${d#-} -le 2 ]]; then ok "_tf_date_epoch: '$w'"; else bad "_tf_date_epoch: '$w' gave $a, date gave $b"; fi
done
is "_tf_date_epoch: ISO with Z" "$(_tf_date_epoch 2026-01-01T10:20:30Z)" 1767262830

# ---- tf_epoch_frac
v="$(tf_epoch_frac)"
case "$v" in [0-9]*.[0-9]*) ok "tf_epoch_frac: seconds.fraction ($v)" ;; *) bad "tf_epoch_frac: '$v'" ;; esac

# ---- tf_realpath / tf_relpath
mkdir -p "$WORK/real/a/b"; ln -s "$WORK/real/a" "$WORK/link"
want="$(cd -P "$WORK/real/a/b" && pwd)"
is "tf_realpath: resolves a symlink" "$(tf_realpath "$WORK/link/b")" "$want"
is "tf_realpath: resolves .." "$(tf_realpath "$WORK/real/a/b/..")" "$(cd -P "$WORK/real/a" && pwd)"
tf_realpath "$WORK/nope/deeper/x" >/dev/null 2>&1; [[ $? -ne 0 ]] && ok "tf_realpath: fails when the parent is missing" || bad "tf_realpath: missing parent succeeded"
is "tf_relpath: a path under the base" "$(tf_relpath "$WORK/real" "$WORK/real/a/b")" "a/b"
is "tf_relpath: through a symlink" "$(tf_relpath "$WORK/real" "$WORK/link/b")" "a/b"

# ---- tf_read_lines
tf_read_lines L < <(printf 'one two\n  lead\\back\n\nlast')
is "tf_read_lines: one element per line" "${#L[@]}" 4
is "tf_read_lines: keeps blanks and backslashes" "${L[1]}" '  lead\back'
is "tf_read_lines: keeps an empty line" "${L[2]}" ""
is "tf_read_lines: keeps a last line without a newline" "${L[3]}" "last"
L=(stale); tf_read_lines L < /dev/null
is "tf_read_lines: empties the array on no input" "${#L[@]}" 0
tf_read_lines 'bad name' < /dev/null 2>/dev/null; is "tf_read_lines: refuses a bad name" "$?" 2

echo "tf-portable: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

# tf-lock.sh — one build or browser check at a time per repository. Sourced, not run.
#   source "$HERE/tf-lock.sh"; tf_take_lock <label>     waits for the lock, then holds it until exit
# The lock is the folder tests/.artifacts/build/.lock and, inside it, the file `owner`
# ("<pid> <host> <label> <time>"). A lock whose process has gone is taken over. A script started by the
# holder (tf-verify-tests.sh running tf-build.sh) shares it through TF_REPO_LOCK_PID.
# TF_BUILD_LOCK_MAX seconds to wait (1800). (TF-043, TfLens TF-048)
#
# FW-002 (2026-11-08): on the Ubuntu 26.04 CI runner two builds still ran at once ("order: start start
# end end", runs 42474539895 and 42486414491), with the age check already in python. Every decision here
# leaned on an outside tool (mkdir to claim, cut and hostname to read the owner), and that runner ships
# different core tools from Ubuntu 24.04 and macOS. Nothing outside bash decides any more: the lock is
# CLAIMED by creating `owner` with bash's no-clobber redirection (an exclusive create, which fails when
# the file exists whatever mkdir said), the owner is read with `read`, and the host is $HOSTNAME.
# TF_LOCK_TRACE=<file> appends every decision to that file (tests/regression/run.sh fw_002 prints it).
TF_LOCK="tests/.artifacts/build/.lock"
_tf_lock_trace() { [[ -n "${TF_LOCK_TRACE:-}" ]] && printf '%s %s %s\n' "$$" "$(date -u +%H:%M:%S)" "$1" >> "$TF_LOCK_TRACE"; return 0; }
_tf_lock_owner_pid() { local p _r; read -r p _r < "$TF_LOCK/owner" 2>/dev/null; printf '%s' "${p:-}"; }
tf_release_lock() {
  if [[ "$(_tf_lock_owner_pid)" == "$$" ]]; then
    _tf_lock_trace "release"
    # never rm -rf: a waiter may already have claimed a new owner inside the folder, and an empty folder
    # left behind is harmless (a claim needs only the owner file to be absent)
    rm -f "$TF_LOCK/owner"; rmdir "$TF_LOCK" 2>/dev/null
  fi
}
tf_take_lock() {
  local label="${1:-}" waited=0 max="${TF_BUILD_LOCK_MAX:-1800}" said=0 owner opid ohost _rest age
  if [[ -n "${TF_REPO_LOCK_PID:-}" ]] && kill -0 "$TF_REPO_LOCK_PID" 2>/dev/null; then
    _tf_lock_trace "shared with holder $TF_REPO_LOCK_PID ($label)"; return 0
  fi
  while :; do
    # the folder first, every time: the holder removes it on release, and a claim into a missing folder
    # fails without an owner to read, which spun a waiter for ever (found by fw_002 before it shipped)
    mkdir -p "$TF_LOCK" 2>/dev/null
    # the claim: an exclusive create of the owner file, by bash itself
    if ( set -C; printf '%s %s %s %s\n' "$$" "${HOSTNAME:-}" "${label:-?}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TF_LOCK/owner" ) 2>/dev/null; then
      _tf_lock_trace "took ($label)"
      break
    fi
    owner=""; opid=""; ohost=""
    read -r opid ohost _rest < "$TF_LOCK/owner" 2>/dev/null
    owner="${opid:+$opid $ohost $_rest}"
    if [[ -z "$opid" ]]; then
      # an owner file not written yet, or a lock folder its holder never filled: taken over only when it
      # is over 60 s old, measured in seconds by python
      age="$(python3 -c 'import os,sys,time; print(int(time.time() - os.stat(sys.argv[1]).st_mtime))' "$TF_LOCK/owner" 2>/dev/null)"
      if [[ "$age" =~ ^[0-9]+$ && $age -gt 60 ]]; then
        _tf_lock_trace "empty owner ${age}s old: taken over"; rm -f "$TF_LOCK/owner"; continue
      fi
      if [[ ! -e "$TF_LOCK/owner" ]]; then
        # released between our claim and our read, or the folder could not be made: try again after a beat,
        # never in a tight loop, and count it against the limit like any other wait
        _tf_lock_trace "no owner to read: try again"; sleep 1; waited=$((waited + 1))
        if [[ $waited -ge $max ]]; then
          echo "NOT-RUN could not take the build lock in $TF_LOCK for $((max / 60)) minutes (the folder cannot be written?). Not a code error"
          exit 2
        fi
        continue
      fi
      _tf_lock_trace "owner not written yet (${age:-?}s): wait"
    elif [[ "$ohost" == "${HOSTNAME:-}" ]] && [[ "$opid" =~ ^[0-9]+$ ]] && ! kill -0 "$opid" 2>/dev/null; then
      # read it once more just before removing it, so a waiter never removes an owner another waiter has
      # just claimed in the meantime
      local again=""; read -r again _rest < "$TF_LOCK/owner" 2>/dev/null
      [[ "$again" == "$opid" ]] && { _tf_lock_trace "holder $opid has gone: taken over"; rm -f "$TF_LOCK/owner"; }
      continue
    else
      _tf_lock_trace "held by $opid on ${ohost:-?}: wait"
    fi
    [[ $said -eq 0 ]] && { echo "wait  another build or browser check is running in this repository (${owner:-starting}); this one starts when it finishes" >&2; said=1; }
    if [[ $waited -ge $max ]]; then
      echo "NOT-RUN another build or browser check held this repository for $((max / 60)) minutes ($owner). If nothing is running, remove $TF_LOCK and run again. Not a code error"
      exit 2
    fi
    sleep 3; waited=$((waited + 3))
  done
  export TF_REPO_LOCK_PID=$$
  trap tf_release_lock EXIT
}

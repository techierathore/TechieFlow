# tf-lock.sh — one build or browser check at a time per repository. Sourced, not run.
#   source "$HERE/tf-lock.sh"; tf_take_lock <label>     waits for the lock, then holds it until exit
# A directory, because mkdir is atomic on every drive this runs on. A lock whose process has gone
# is taken over. A script started by the holder (tf-verify-tests.sh running tf-build.sh) shares it
# through TF_REPO_LOCK_PID. TF_BUILD_LOCK_MAX seconds to wait (1800). (TF-043, TfLens TF-048)
TF_LOCK="tests/.artifacts/build/.lock"
tf_release_lock() { [[ "$(cut -d' ' -f1 "$TF_LOCK/owner" 2>/dev/null)" == "$$" ]] && rm -rf "$TF_LOCK"; }
tf_take_lock() {
  local label="${1:-}" waited=0 max="${TF_BUILD_LOCK_MAX:-1800}" said=0 owner opid ohost age
  if [[ -n "${TF_REPO_LOCK_PID:-}" ]] && kill -0 "$TF_REPO_LOCK_PID" 2>/dev/null; then return 0; fi
  mkdir -p "$(dirname "$TF_LOCK")"
  while ! mkdir "$TF_LOCK" 2>/dev/null; do
    owner="$(cat "$TF_LOCK/owner" 2>/dev/null)"; opid="$(cut -d' ' -f1 <<<"$owner")"; ohost="$(cut -d' ' -f2 <<<"$owner")"
    if [[ -z "$owner" ]]; then
      # No owner yet: the holder is between its mkdir and its owner write, or died there. Taken over only
      # when the lock is over 60 s old, measured in seconds by python. `find -mmin +1` answered "old" for a
      # lock made a moment before on the Ubuntu 26.04 runner: two builds ran at once ("order: start start
      # end end", run 42474539895, FW-002). tests/regression/run.sh fw_002.
      age="$(python3 -c 'import os,sys,time; print(int(time.time() - os.stat(sys.argv[1]).st_mtime))' "$TF_LOCK" 2>/dev/null)"
      [[ "$age" =~ ^[0-9]+$ && $age -gt 60 ]] && { rm -rf "$TF_LOCK"; continue; }
    elif [[ "$ohost" == "$(hostname)" ]] && ! kill -0 "$opid" 2>/dev/null; then
      rm -rf "$TF_LOCK"; continue
    fi
    [[ $said -eq 0 ]] && { echo "wait  another build or browser check is running in this repository (${owner:-starting}); this one starts when it finishes" >&2; said=1; }
    if [[ $waited -ge $max ]]; then
      echo "NOT-RUN another build or browser check held this repository for $((max / 60)) minutes ($owner). If nothing is running, remove $TF_LOCK and run again. Not a code error"
      exit 2
    fi
    sleep 3; waited=$((waited + 3))
  done
  # written whole and renamed into place, so a waiter never reads a half-written owner as "no owner"
  echo "$$ $(hostname) $label $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TF_LOCK/owner.$$" && mv -f "$TF_LOCK/owner.$$" "$TF_LOCK/owner"
  export TF_REPO_LOCK_PID=$$
  trap tf_release_lock EXIT
}

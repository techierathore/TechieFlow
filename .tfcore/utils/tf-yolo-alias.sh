#!/usr/bin/env bash
# tf-yolo-alias.sh — put the `tfyolo` command in this machine's shell profile, once (owner, 2026-10-14).
#
#   bash .tfcore/utils/tf-yolo-alias.sh install    add it to ~/.bashrc and/or ~/.zshrc (idempotent)
#   bash .tfcore/utils/tf-yolo-alias.sh remove     take it out again
#   bash .tfcore/utils/tf-yolo-alias.sh status     say where it is
#
# `tfyolo` is a small shell function, the same text in bash and zsh. Typed anywhere inside a
# TechieFlow project, it finds the project's .tfcore/utils/tf-yolo-start.sh above the current folder
# and runs it: YOLO on, Claude Code started in bypass mode in this terminal, YOLO off when the session
# ends. `tfyolo -c` continues the last conversation. It never opens or closes a window: exit the
# session you are in (/exit), then type it in the same terminal, or type it in another tab.
# The function lives between two marker lines and is replaced whole on a second install, so an update
# to it reaches the profile by running install again. Profiles: ~/.zshrc when the login shell is zsh
# or the file exists (macOS), ~/.bashrc when the login shell is bash or the file exists (WSL, Linux).
# A new terminal picks it up; an open one needs `source ~/.bashrc` (or ~/.zshrc). Exit 0; 2 bad use.

set -u
BEGIN="# >>> TechieFlow tfyolo >>>"
END="# <<< TechieFlow tfyolo <<<"
HOME_DIR="${TF_HOME:-$HOME}"

block() {
  cat <<'FN'
# >>> TechieFlow tfyolo >>>
# Start Claude Code in bypass mode with TechieFlow YOLO on, in the project around this folder.
# `tfyolo -c` continues the last conversation. Added by .tfcore/utils/tf-yolo-alias.sh; remove with
# `bash .tfcore/utils/tf-yolo-alias.sh remove`.
tfyolo() {
  _tf_d="$PWD"
  while [ "$_tf_d" != "/" ] && [ ! -f "$_tf_d/.tfcore/utils/tf-yolo-start.sh" ]; do _tf_d="$(dirname "$_tf_d")"; done
  if [ ! -f "$_tf_d/.tfcore/utils/tf-yolo-start.sh" ]; then
    echo "tfyolo: no TechieFlow project around $PWD (no .tfcore/utils/tf-yolo-start.sh above it)" >&2
    unset _tf_d; return 2
  fi
  bash "$_tf_d/.tfcore/utils/tf-yolo-start.sh" "$@"
  _tf_rc=$?; unset _tf_d; return $_tf_rc
}
# <<< TechieFlow tfyolo <<<
FN
}

profiles() {
  local sh; sh="$(basename "${SHELL:-}")"
  [[ "$sh" == zsh || -f "$HOME_DIR/.zshrc" ]] && echo "$HOME_DIR/.zshrc"
  [[ "$sh" == bash || -f "$HOME_DIR/.bashrc" ]] && echo "$HOME_DIR/.bashrc"
  [[ "$sh" != zsh && "$sh" != bash && ! -f "$HOME_DIR/.zshrc" && ! -f "$HOME_DIR/.bashrc" ]] && echo "$HOME_DIR/.bashrc"
  return 0
}

strip() {  # the file without our block
  awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$1"
}

case "${1:-status}" in
  install)
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      tmp="$p.tftmp.$$"
      if [[ -f "$p" ]]; then strip "$p" > "$tmp"; else : > "$tmp"; fi
      # one blank line before the block, never a growing run of them
      [[ -s "$tmp" && -n "$(tail -c 1 "$tmp")" ]] && echo "" >> "$tmp"
      block >> "$tmp"
      cat "$tmp" > "$p"; rm -f "$tmp"
      echo "tfyolo: installed in $p (open a new terminal, or: source $p)"
    done < <(profiles)
    ;;
  remove)
    for p in "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc"; do
      [[ -f "$p" ]] && grep -qxF "$BEGIN" "$p" || continue
      tmp="$p.tftmp.$$"; strip "$p" > "$tmp"; cat "$tmp" > "$p"; rm -f "$tmp"
      echo "tfyolo: removed from $p"
    done
    ;;
  status)
    found=0
    for p in "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc"; do
      [[ -f "$p" ]] && grep -qxF "$BEGIN" "$p" && { echo "tfyolo: in $p"; found=1; }
    done
    [[ $found -eq 1 ]] || echo "tfyolo: not installed (bash .tfcore/utils/tf-yolo-alias.sh install)"
    ;;
  *) echo "usage: tf-yolo-alias.sh install|remove|status" >&2; exit 2 ;;
esac
exit 0

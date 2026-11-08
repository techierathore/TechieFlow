#!/usr/bin/env bash
# tf-gitignore-blocks.sh — append TechieFlow's managed .gitignore blocks (FW-2026-11-08).
#
#   source .tfcore/utils/tf-gitignore-blocks.sh
#   tf_gitignore_block <list.tsv> <block> <dry-run 0|1>
#
# Sourced by scaffold-greenfield.sh, scaffold-brownfield.sh and update-framework.sh, run in the
# target project's folder. The lines come from .tfcore/data/gitignore-blocks.tsv, the same file the
# Node installer (scripts/install.mjs) reads, so the four routes write the same .gitignore.
# Append-only and idempotent: an entry whose pattern already matches a line is skipped, and the
# owner's own lines are never rewritten. bash 3.2 clean (no mapfile, no associative arrays).

tf_gitignore_block() {
  local list="$1" want="$2" dry="${3:-0}"
  local header="" label="" blk line pat present=""
  local missing=()
  if [[ ! -f "$list" ]]; then
    echo "  .gitignore — $want entries NOT checked: $list is missing (reinstall the framework)"
    return 0
  fi
  # tr strips CR so a Windows-authored .gitignore still matches the $-anchor
  [[ -f .gitignore ]] && present="$(tr -d '\r' < .gitignore)"
  while IFS=$'\t' read -r blk line pat; do
    case "$blk" in ''|'#'*) continue ;; esac
    if [[ "$blk" == "@$want" ]]; then header="$line"; label="$pat"; continue; fi
    [[ "$blk" == "$want" ]] || continue
    if [[ -n "$present" ]] && grep -qE "$pat" <<<"$present"; then continue; fi
    missing+=("$line")
  done < "$list"
  [[ -n "$label" ]] || label="$want entries"
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "  .gitignore — $label already present"
  elif [[ "$dry" == "1" ]]; then
    echo "  .gitignore — WOULD add $label: ${missing[*]}"
  else
    { echo ""
      echo "$header"
      printf '%s\n' "${missing[@]}"
    } >> .gitignore
    echo "  .gitignore — added $label: ${missing[*]}"
  fi
  return 0
}

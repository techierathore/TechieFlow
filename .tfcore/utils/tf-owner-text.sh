#!/usr/bin/env bash
# tf-owner-text.sh — check text written for the owner: plain words, every upstream problem with
# what it affects and the prompt that fixes it, every named command with the line to paste, and
# a command's closing message ending on the next prompt (MISS-TechieFlow-20260911-03).
#
#   bash .tfcore/utils/tf-owner-text.sh [--root <dir>] [--final] <file> ...
#   printf '%s' "<message>" | bash .tfcore/utils/tf-owner-text.sh --final --stdin
#
# The Stop hook runs it on a command's closing message and on every free-form document that
# message hands the owner. Details: tf-owner-text.py. Exit 0 clean, 1 a FAIL, 2 could not run.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "tf-owner-text: python3 is required" >&2; exit 2; }
exec python3 "$HERE/tf-owner-text.py" "$@"

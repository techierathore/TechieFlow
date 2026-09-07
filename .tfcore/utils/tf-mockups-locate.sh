#!/usr/bin/env bash
# tf-mockups-locate.sh — bring every mockup in the repository into docs/mockups/.
#
#   bash .tfcore/utils/tf-mockups-locate.sh            # move, then list docs/mockups/
#   bash .tfcore/utils/tf-mockups-locate.sh --dry-run  # only report
#
# Finds folders named mockup(s), wireframe(s), designs or screens outside
# docs/mockups/ and moves their .html/.png/.jpg/.svg files there, so the
# framework's one mockup folder is the only one. Run at brownfield day-1 and by
# the mockups task before it links or draws anything.
# Thin wrapper over tf-mockups-locate.py; Python 3 standard library only.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "tf-mockups-locate: python3 is required (standard library only)." >&2
  exit 2
fi
exec python3 "$SELF_DIR/tf-mockups-locate.py" "$@"

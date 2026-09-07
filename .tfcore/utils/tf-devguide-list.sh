#!/usr/bin/env bash
# tf-devguide-list.sh — the work list for *devguide.
#
#   bash .tfcore/utils/tf-devguide-list.sh MyApp              # app: routes in code vs UIDesign screens, roles
#   bash .tfcore/utils/tf-devguide-list.sh MyApp --update     # plus which existing entries changed
#   bash .tfcore/utils/tf-devguide-list.sh MyApp --phase 2    # a later phase of a Large project
#
# Kind comes from core-config.yaml: an app lists routed pages; a UI library its public
# components and the sample page that shows each; a service library its registrations,
# interfaces and classes and the sample that calls each. Prints NOTHING when no code exists.
# Writes nothing. Thin wrapper over tf-devguide-list.py; Python 3 stdlib only.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "tf-devguide-list: python3 is required (standard library only)." >&2
  exit 2
fi
exec python3 "$SELF_DIR/tf-devguide-list.py" "$@"

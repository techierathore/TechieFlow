#!/usr/bin/env bash
# tf-doc-tests.sh — run the unit tests when a test reads a document this command changed (Lekhak TF-016, 2026-09-30).
#
#   bash .tfcore/utils/tf-doc-tests.sh <doc> [<doc>…] [--target <sln|csproj>]
#
# A project may guard a document with a unit test: Lekhak's VerificationRuleDocTests reads
# docs/Lekhak-UsageGuide.md and fails when the REQ-NFR-042 paragraph is gone. *amend-docs removed that
# paragraph, ran no test, closed green, and only CI noticed. This script looks for test source files
# (a path containing "test") that name one of the documents, by file name or by name without ".md".
# When one does, it runs the unit tests through tf-build.sh test. Prints ONE line:
#   NONE     no test reads <docs>; nothing to run                             exit 0
#   PASS     <n> test file(s) read <docs> (<files>); the unit tests pass — <build line>   exit 0
#   FAIL     <n> test file(s) read <docs> (<files>); the unit tests fail — <build line>   exit 1
#   NOT-RUN  the tests could not be run — <reason>                                         exit 2
# A FAIL means the phase is not closed: a test guards text this command changed.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/tf-portable.sh"   # tf_read_lines, for bash 3.2 on a stock Mac
DOCS=(); TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) DOCS+=("$1"); shift ;;
  esac
done
[[ ${#DOCS[@]} -gt 0 ]] || { echo "tf-doc-tests: name at least one document" >&2; exit 2; }

READERS="$(python3 - "${DOCS[@]}" <<'PY'
import os, sys
names = set()
for d in sys.argv[1:]:
    b = os.path.basename(d)
    names.add(b)
    stem = os.path.splitext(b)[0]
    if len(stem) >= 6:          # "README" alone would match half the code; a real document name is longer
        names.add(stem)
EXT = (".cs", ".fs", ".vb", ".ts", ".tsx", ".js", ".mjs", ".py", ".java", ".kt", ".go", ".rs", ".rb", ".swift", ".dart", ".php")
SKIP = {"node_modules", "bin", "obj", ".git", ".tfcore", ".claude", ".opencode", "docs", ".artifacts"}
hits = []
for root, dirs, files in os.walk("."):
    dirs[:] = [x for x in dirs if x not in SKIP and not (x.startswith(".") and x != ".")]
    for fn in files:
        p = os.path.join(root, fn)[2:]
        if not fn.endswith(EXT) or "test" not in p.lower():
            continue
        try:
            t = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if any(n in t for n in names):
            hits.append(p)
print("\n".join(sorted(hits)))
PY
)"
if [[ -z "$READERS" ]]; then
  echo "NONE     no test reads ${DOCS[*]}; nothing to run"
  exit 0
fi
N="$(wc -l <<<"$READERS" | tr -d ' ')"; LIST="$(tr '\n' ',' <<<"$READERS" | sed 's/,$//; s/,/, /g')"

# the same target choice as tf-verify-tests.sh: a root solution, else the only test project under tests/
ROOTSLN="$(compgen -G '*.sln'; compgen -G '*.slnx'; compgen -G '*.csproj')"
tf_read_lines TESTPROJ < <(find tests -name '*.csproj' -not -path 'tests/.artifacts/*' -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' 2>/dev/null | sort)
[[ -z "$TARGET" && -z "$ROOTSLN" && ${#TESTPROJ[@]} -eq 1 ]] && TARGET="${TESTPROJ[0]}"
if [[ -z "$TARGET" && -z "$ROOTSLN" ]]; then
  if [[ ${#TESTPROJ[@]} -gt 1 ]]; then
    echo "NOT-RUN  $N test file(s) read ${DOCS[*]} ($LIST), but there is no solution here and ${#TESTPROJ[@]} test projects; name one with --target"
  else
    echo "NOT-RUN  $N test file(s) read ${DOCS[*]} ($LIST), but no .NET solution or test project is here; run the project's own unit tests and report them"
  fi
  exit 2
fi
LINE="$(bash "$HERE/tf-build.sh" test ${TARGET:+"$TARGET"} 2>&1 | grep -m1 -E '^(PASS|FAIL|NOT-RUN)' || true)"
case "$LINE" in
  PASS*)    echo "PASS     $N test file(s) read ${DOCS[*]} ($LIST); the unit tests pass — $LINE"; exit 0 ;;
  FAIL*)    echo "FAIL     $N test file(s) read ${DOCS[*]} ($LIST); the unit tests fail — $LINE"; exit 1 ;;
  *)        echo "NOT-RUN  the unit tests could not be run — ${LINE:-tf-build.sh printed no verdict}"; exit 2 ;;
esac

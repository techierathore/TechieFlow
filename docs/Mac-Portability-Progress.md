# Mac portability — progress

Goal: every shell script in this repository runs on a stock macOS (bash 3.2 at /bin/bash, BSD
sed/date/stat/xargs/grep, no GNU coreutils, no Homebrew) and behaves exactly as before on Linux
and WSL. Branch `mac-portability`, one draft pull request to `main`. Ravi reviews and merges.

| # | Session | Status | Result |
|---|---------|--------|--------|
| 1 | Inventory and a check in code | Done | 123 pattern hits in 20 scripts plus 5 found by reading (below); `tests/portability/run.sh` wired into `npm run validate`, fails listing every site |
| 2 | Shim library `.tfcore/utils/tf-portable.sh` | Not started | |
| 3 | tf-goal.sh, tf-yolo.sh, tf-build.sh | Not started | |
| 4 | Everything else; the check passes | Not started | |
| 5 | macOS job in CI, draft pull request | Not started | |
| 6 | Docs | Not started | |

## Inventory (session 1)

Found by `bash tests/portability/run.sh --scan-only` on the unchanged scripts: **123** non-portable
uses in 20 of the 65 scripts. By kind: timeout 23, GNU regex escapes in grep (`\s`, `\b`) 16,
`date -d` / `date -r FILE` 13, `sed -i` 12, GNU-only sed (`\s`, `0,/re/`, `\n` in a replacement)
10, mapfile 9, `\|` in a basic grep regex 9, realpath 6, `touch -d` 4, `pgrep -a` 4, `xargs -r` 3,
here-documents inside `$( )` that bash 3.2 cannot parse 3, `date +%N` 3, setsid 2, md5sum 2,
`stat -c` 1, negative array index 1, `mktemp --suffix` 1, `declare -A` 1.

None found: `readlink -f`, `grep -P`, `${var,,}` / `${var^^}`, `&>>`, `|&`, coproc, globstar,
`printf -v` into an array, `find -printf`, namerefs, `declare -g/-l/-u`, `[[ -v`, `${var@Q}`,
`wait -n`, `;;&`, `{01..10}`, `{fd}>`. Lines that only look like these (inside embedded Python or
JavaScript) are in `tests/portability/exceptions.txt` with the reason.

By file and line (line numbers as on `main` before this branch):

- `tests/goal/run.sh` (8): 167 timeout, 177 timeout, 186 timeout, 125 touch-date, 63 pgrep-a, 75 pgrep-a, 100 pgrep-a, 121 pgrep-a
- `tests/regression/run.sh` (48): 1414 timeout, 1459 timeout, 1630 timeout, 1771 timeout, 1827 timeout, 1828 timeout, 1865 timeout, 1911 timeout, 1970 timeout, 2026 timeout, 2102 timeout, 2297 timeout, 2447 timeout, 2553 timeout, 2769 timeout, 2775 timeout, 2795 timeout, 2804 timeout, 2861 timeout, 2895 timeout, 858 sed-inplace, 1714 sed-inplace, 1815 sed-inplace, 2490 sed-inplace, 2708 sed-inplace, 3015 sed-inplace, 3113 sed-inplace, 941 date-parse, 976 date-parse, 1292 date-parse, 1314 date-parse, 1320 date-parse, 2220 date-parse, 2221 date-parse, 1805 date-nanoseconds, 1806 date-nanoseconds, 1808 date-nanoseconds, 936 touch-date, 938 touch-date, 1377 touch-date, 171 grep-bre-alternation, 344 grep-bre-alternation, 669 grep-bre-alternation, 726 grep-bre-alternation, 3216 grep-bre-alternation, 793 gnu-only-tool (md5sum), 795 gnu-only-tool (md5sum), 1073 heredoc-in-substitution
- `.tfcore/utils/tf-goal.sh` (9): 485 setsid, 486 setsid, 494 stat-format, 165 date-parse, 443 date-parse, 453 date-parse, 623 date-parse, 439 grep-gnu-regex, 572 negative-index
- `.tfcore/utils/tf-verify-env.sh` (8): 67 sed-inplace, 69 sed-inplace, 80 sed-inplace, 83 sed-inplace, 86 sed-inplace, 69 sed-gnu-regex, 83 sed-gnu-regex, 86 sed-gnu-regex
- `.tfcore/utils/tf-build.sh` (12): 194 sed-gnu-regex, 196 sed-gnu-regex, 207 sed-gnu-regex, 88 grep-gnu-regex, 194 grep-gnu-regex, 196 grep-gnu-regex, 199 grep-gnu-regex, 207 grep-gnu-regex, 69 mapfile, 81 mapfile, 82 mapfile, 129 mapfile
- `.tfcore/utils/tf-status-evidence.sh` (8): 34 sed-gnu-regex, 35 date-parse, 44 xargs-r, 25 grep-gnu-regex, 34 grep-gnu-regex, 54 grep-gnu-regex, 56 grep-gnu-regex, 42 mapfile
- `.tfcore/utils/tf-verify-boot.sh` (10): 301 sed-gnu-regex, 388 sed-gnu-regex, 419 sed-gnu-regex, 71 grep-gnu-regex, 301 grep-gnu-regex, 350 grep-gnu-regex, 388 grep-gnu-regex, 419 grep-gnu-regex, 218 mapfile, 311 mapfile
- `tests/routing/run.sh` (2): 179 date-parse, 288 grep-bre-alternation
- `.tfcore/telemetry/install-metrics.sh` (2): 95 xargs-r, 99 xargs-r
- `scaffold-brownfield.sh` (1): 37 realpath
- `scaffold-greenfield.sh` (1): 36 realpath
- `tests/mirror/run.sh` (6): 151 realpath, 168 realpath, 183 realpath, 148 grep-gnu-regex, 187 grep-bre-alternation, 148 mapfile
- `update-framework.sh` (1): 110 realpath
- `tests/bugs/run.sh` (1): 70 grep-bre-alternation
- `tests/verify/run.sh` (1): 135 grep-bre-alternation
- `.tfcore/utils/tf-assets.sh` (1): 95 mktemp-gnu
- `.tfcore/utils/tf-verify-tests.sh` (1): 121 mapfile
- `tests/requirements/run.sh` (1): 30 assoc-array
- `.tfcore/hooks/block-git.sh` (1): 88 heredoc-in-substitution
- `.tfcore/utils/tf-emit.sh` (1): 588 heredoc-in-substitution

Found by reading, not by a pattern (5):
- `.tfcore/utils/tf-harness.sh:55` reads `/proc/<pid>/stat` to find the harness; on a Mac the walk
  stops at once and prints `unknown`.
- `tests/regression/run.sh:2241` a `\|` alternation in a double-quoted basic grep regex.
- `wc` output compared as text (BSD `wc` pads it with blanks): `tests/regression/run.sh:572` and
  `tests/regression/run.sh:2261`.
- `"${arr[@]}"` of an empty array under `set -u` is an "unbound variable" error before bash 4.4.
  No pattern can tell an empty array from a full one; reviewed file by file in sessions 3 and 4.

## Decisions taken

- Git: the hook `.tfcore/hooks/block-git.sh` and the deny rules in `.claude/settings.json` block
  every git write from the shell and cannot know that this task has the owner's permission. They
  were left as they are; the branch, the commits and the draft pull request were made through the
  GitHub API tools instead.
- A local bash 3.2 to test with could not be fetched (the session's network policy refused the
  download). The bash-3.2 checks here are static (the pattern check, and a scan that emulates how
  bash 3.2 reads here-documents inside `$( )`); the macOS CI job of session 5 is the real test.
- The check is `tests/portability/run.sh` with `heredoc-scan.py` (the here-document scan) and
  `exceptions.txt` (one commented line per allowed site; an entry that matches nothing fails the
  check, so the list cannot rot).
- Linux baseline in this session before any change (rsync installed first): goal, routing, mirror,
  doc-check and regression pass; bugs (3 failures), verify (22) and requirements (9, caused by
  those two) fail because this container has no Playwright browser and no .NET SDK. Runs after
  each change are compared against these exact failure lists.

## Left for the owner

- `.tfcore/utils/tf-verify-boot.sh` (embedded Python in `stop`): a leftover app is also searched
  for through `/proc`; on a Mac that search fails quietly inside try/except, and only the pid-file
  path stops the app.

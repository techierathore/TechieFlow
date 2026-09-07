#!/usr/bin/env bash
# tests/mirror/run.sh — harness parity (FR-40; Session 5, 2026-09-07, from MISS-TechieFlow-20260905-02:
# six task files edited in .tfcore were not copied to the Claude Code mirror for five days and no
# check ran). Checks:
#   1. every persona and task under .tfcore/{agents,tasks}/ is byte-identical in .claude/commands/TechieFlow/
#   2. the mirror holds nothing .tfcore no longer has (a removed command must be gone from both)
#   3. every .tfcore/tasks/*.md and .tfcore/agents/*.md is referenced from opencode.jsonc,
#      and every {file:./.tfcore/...} reference in opencode.jsonc resolves to a file
#   4. every task file is under the FR-43 frontier budget of 7,000 words, and the shared rule files
#      together stay under 3,000 (FR-44); every persona under 1,500
# Run: bash tests/mirror/run.sh   (a second's work; the distribution pipeline runs it too)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $*"; }
bad() { fail=$((fail+1)); echo "FAIL $*"; }
M="$ROOT/.claude/commands/TechieFlow"

# 1. byte-identical mirror
for kind in agents tasks; do
  n=0; d=0
  for f in "$ROOT/.tfcore/$kind"/*.md; do
    b="$(basename "$f")"; n=$((n+1))
    if [[ ! -f "$M/$kind/$b" ]]; then bad "$kind/$b is missing from the Claude Code mirror"; d=$((d+1))
    elif ! cmp -s "$f" "$M/$kind/$b"; then bad "$kind/$b differs from the Claude Code mirror (cp -p .tfcore/$kind/$b .claude/commands/TechieFlow/$kind/$b)"; d=$((d+1)); fi
  done
  [[ $d -eq 0 ]] && ok "$n $kind file(s) byte-identical in the Claude Code mirror"
done

# 2. nothing stale in the mirror
stale=0
for kind in agents tasks; do
  for f in "$M/$kind"/*.md; do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    [[ -f "$ROOT/.tfcore/$kind/$b" ]] || { bad "mirror holds $kind/$b, which .tfcore no longer has (remove it)"; stale=$((stale+1)); }
  done
done
[[ $stale -eq 0 ]] && ok "the mirror holds nothing .tfcore no longer has"

# 3. opencode.jsonc references
OC="$ROOT/opencode.jsonc"
if [[ -f "$OC" ]]; then
  miss=0
  for f in "$ROOT/.tfcore/tasks"/*.md "$ROOT/.tfcore/agents"/*.md; do
    rel="${f#$ROOT/}"
    [[ "$(basename "$f")" == _* ]] && continue    # a shared rule file is read by the tasks that name it, not registered as a command
    grep -qF "{file:./$rel}" "$OC" || { bad "opencode.jsonc does not reference $rel"; miss=$((miss+1)); }
  done
  [[ $miss -eq 0 ]] && ok "every command task and persona is referenced from opencode.jsonc"
  broken=0
  while IFS= read -r ref; do
    [[ -f "$ROOT/$ref" ]] || { bad "opencode.jsonc references $ref, which does not exist"; broken=$((broken+1)); }
  done < <(grep -o '{file:\./[^}]*}' "$OC" | sed 's/{file:\.\///; s/}$//' | sort -u)
  [[ $broken -eq 0 ]] && ok "every {file:} reference in opencode.jsonc resolves"
else
  bad "opencode.jsonc not found"
fi

# 4. instruction budgets
over=0
for f in "$ROOT/.tfcore/tasks"/*.md; do
  w=$(wc -w < "$f"); [[ $w -le 7000 ]] || { bad "$(basename "$f") is $w words, over the 7,000-word frontier budget (FR-43)"; over=$((over+1)); }
done
[[ $over -eq 0 ]] && ok "every task file is under 7,000 words (FR-43)"
shared=$(cat "$ROOT/.tfcore/tasks"/_*.md | wc -w)
[[ $shared -le 3000 ]] && ok "shared rule files total $shared words (FR-44: under 3,000)" || bad "shared rule files total $shared words, over 3,000 (FR-44)"
overp=0
for f in "$ROOT/.tfcore/agents"/*.md; do
  w=$(wc -w < "$f"); [[ $w -le 1500 ]] || { bad "$(basename "$f") is $w words, over the 1,500-word persona cap (FR-44)"; overp=$((overp+1)); }
done
[[ $overp -eq 0 ]] && ok "every persona is under 1,500 words (FR-44)"

# 5. the two readable surfaces (Session 6, 2026-09-07)
#    The briefing and the README are what a person reads first. They grew to 344 KB and 121 KB, and
#    nothing counted them or noticed when they named a command the framework had removed.
brief="$ROOT/WorkFlow-Context.md"; readme="$ROOT/README.md"
if [[ -f $brief ]]; then
  w=$(wc -w < "$brief")
  [[ $w -le 3000 ]] && ok "WorkFlow-Context.md is $w words (budget 3,000)" \
                    || bad "WorkFlow-Context.md is $w words, over the 3,000-word budget; the log belongs in docs/CHANGELOG.md"
else bad "WorkFlow-Context.md not found"; fi
if [[ -f $readme ]]; then
  w=$(wc -w < "$readme")
  [[ $w -le 4000 ]] && ok "README.md is $w words (budget 4,000)" \
                    || bad "README.md is $w words, over the 4,000-word budget; move the detail into docs/"
else bad "README.md not found"; fi

# 5b. no readable surface names a command the framework removed in Sitting 4c
gone_hits=0
for f in "$brief" "$readme"; do
  [[ -f $f ]] || continue
  while read -r cmd; do
    if grep -qi -- "$cmd" "$f"; then
      bad "$(basename "$f") names '$cmd', a command removed in Sitting 4c"; gone_hits=$((gone_hits+1))
    fi
  done <<< "author-brd
create-brd
advanced-elicitation
document-project
index-docs
shard-doc
execute-checklist
kb-mode-interaction"
done
[[ $gone_hits -eq 0 ]] && ok "no readable surface names a removed command"

# 5c. FR-47 — a public-facing document names no private project.
#     The names themselves are never written into this repository: they are read from a per-machine
#     file, ~/.techieflow/private-names.txt (one name per line, '#' comments). Without it the check
#     says so and passes, because a clone on another machine cannot know the owner's private repos.
priv_file="${TF_PRIVATE_NAMES:-$HOME/.techieflow/private-names.txt}"
if [[ -f $priv_file ]]; then
  leaks=0
  mapfile -t priv < <(grep -v '^\s*#' "$priv_file" | grep -v '^\s*$' | tr -d '\r')
  while IFS= read -r f; do
    for n in "${priv[@]}"; do
      grep -q -w -- "$n" "$f" 2>/dev/null && { bad "FR-47: $(realpath --relative-to="$ROOT" "$f") names a private project"; leaks=$((leaks+1)); }
    done
  done < <(printf '%s\n' "$readme" "$brief"; find "$ROOT/.tfcore/templates" -name '*.md' -o -name '*.yaml' 2>/dev/null)
  [[ $leaks -eq 0 ]] && ok "FR-47: the README, the briefing and the templates name no private project (${#priv[@]} names checked)"
else
  ok "FR-47: skipped, no private-name list at $priv_file"
fi

echo
echo "mirror self-test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]

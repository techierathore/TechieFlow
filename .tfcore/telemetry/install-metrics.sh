#!/usr/bin/env bash
# TechieFlow telemetry — per-repo setup. Called AUTOMATICALLY by
# update-framework.sh, scaffold-brownfield.sh and scaffold-greenfield.sh.
#
#   You do NOT normally run this yourself. Refreshing the framework sets up
#   telemetry as part of the same command — there is no separate install step.
#
#   Run it directly only to CORRECT the project classification:
#       .tfcore/telemetry/install-metrics.sh <repo> --type library
#
# WHAT IT DOES (idempotent, non-interactive, safe on every re-run):
#   1. creates docs/metrics/ and seeds the four empty streams
#   2. writes docs/metrics/README.md (for a human who finds the files)
#   3. records metrics.project_type in .tfcore/core-config.yaml — auto-detected
#      ONCE, printed loudly, then never touched again (core-config.yaml is a
#      preserved file, so the classification survives every framework refresh)
#   4. installs .git/hooks/pre-commit (and retires the old post-commit)
#   5. warns if a .gitignore pattern would swallow docs/metrics/
#
# IT NEVER INVOKES GIT. The hooks directory is located by reading the filesystem
# (.git/ as a directory, or the `gitdir:` pointer when .git is a file), so this
# script runs identically whether a human or an agent triggered the refresh, and
# .tfcore/hooks/block-git.sh stays exactly as it is. Installing a hook is a file
# copy; it is not a git operation.
#
# Telemetry has no veto: this script prints warnings, never aborts its caller.
set -uo pipefail

TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TARGET=""
PTYPE=""
DRY=0
QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)     PTYPE="${2:-}"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    --quiet)    QUIET=1; shift ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    *)          TARGET="$1"; shift ;;
  esac
done

say() { [[ $QUIET -eq 1 ]] || echo "$@"; }

[[ -n "$TARGET" ]] || { echo "usage: install-metrics.sh <repo> [--type app|library|docs|framework] [--dry-run]" >&2; exit 1; }
[[ -d "$TARGET" ]] || { echo "not a directory: $TARGET" >&2; exit 1; }
cd "$TARGET" || exit 1
TARGET="$(pwd -P)"

[[ -d .tfcore ]] || { say "  telemetry — no .tfcore/ here, skipped"; exit 0; }

CFG=".tfcore/core-config.yaml"

# --- 1. project_type -----------------------------------------------------
# Read whatever is already recorded. Once set, it is NEVER re-guessed — the
# owner's classification always wins over the heuristic.
EXISTING=""
if [[ -f "$CFG" ]]; then
  EXISTING="$(sed -n '/^metrics:[[:space:]]*$/,/^[^[:space:]#]/p' "$CFG" 2>/dev/null \
              | sed -n 's/^[[:space:]]\{1,\}project_type:[[:space:]]*["'"'"']\{0,1\}\([a-z]*\).*/\1/p' | head -1)"
fi

# Heuristic, run ONCE per repo and then never again (the answer is preserved in
# core-config.yaml). Kept deliberately cheap: build output and package caches are
# PRUNED and the walk is depth-limited, because an unpruned scan of a large repo on
# a /mnt/c mount takes minutes — and this runs inside every framework refresh.
_scan() {  # _scan <maxdepth> <find-expr...>   -> prints the first match, then stops
  find . -maxdepth "$1" \
       \( -type d \( -name bin -o -name obj -o -name node_modules -o -name .git \
                     -o -name .vs -o -name artifacts -o -name TestResults \) -prune \) \
       -o "${@:2}" -print 2>/dev/null | head -1
}

_csprojs() {
  find . -maxdepth 5 \
       \( -type d \( -name bin -o -name obj -o -name node_modules -o -name .git \
                     -o -name .vs -o -name artifacts \) -prune \) \
       -o -name '*.csproj' -print 2>/dev/null | head -60
}

detect_type() {
  # framework: this repo DEPLOYS the framework rather than consuming it
  [[ -f scaffold-brownfield.sh && -d .tfcore/tasks ]] && { echo framework; return; }

  local projects packable heads name
  projects="$(_csprojs)"

  # docs: a markdown/spec repo — no source at all
  [[ -z "$projects" ]] && { echo docs; return; }

  # Packable = genuinely published. IsPackable is usually <IsPackable>false</IsPackable>
  # on test projects, so only an explicit `true` counts.
  packable="$(printf '%s\n' "$projects" | xargs -r grep -lE \
      '<(PackageId>|GeneratePackageOnBuild>[[:space:]]*true|IsPackable>[[:space:]]*true)' 2>/dev/null)"

  # A shipped executable/hostable head: console/desktop (Exe), MAUI, or ASP.NET/Blazor host.
  heads="$(printf '%s\n' "$projects" | xargs -r grep -lE \
      '<OutputType>[[:space:]]*Exe|<UseMaui>[[:space:]]*true|Sdk="Microsoft\.NET\.Sdk\.(Web|BlazorWebAssembly)"' 2>/dev/null)"

  # THE DECIDING TEST: is a packaged project the product, or merely a helper?
  # A library repo's package carries the repo's own name (TrBlazeUI.Components);
  # an app's packable support libs do not (AstroLyfe ships AstroCore, SwissEphStd
  # and is still an app). Name-match beats "has any packable project", which would
  # misclassify every app that factors a NuGet-published helper out of its solution.
  name="$(ls docs/*-Checklist.md 2>/dev/null | head -1)"
  name="$(basename "${name:-$PWD}" 2>/dev/null)"; name="${name%-Checklist.md}"
  [[ -z "$name" ]] && name="$(basename "$PWD")"
  if [[ -n "$packable" ]] && printf '%s\n' "$packable" \
       | grep -qiE "/${name}(\.[A-Za-z0-9._-]+)?\.csproj$"; then
    echo library; return
  fi

  # A shipped head means it is an app, however many helper packages ride along.
  [[ -n "$heads" ]] && { echo app; return; }

  # No head at all, but something is published -> a library.
  [[ -n "$packable" ]] && { echo library; return; }

  # Last resorts: runtime screens -> app; otherwise assume app and let the owner correct.
  [[ -n "$(_scan 6 \( -name '*.razor' -o -name '*.xaml' \))" ]] && { echo app; return; }
  echo app
}

GUESSED=0
UPGRADED=0
if [[ -n "$PTYPE" ]]; then
  :
elif [[ "$EXISTING" == "docs" ]]; then
  # `docs` AT SCAFFOLD TIME IS NOT A CLASSIFICATION — IT IS THE ABSENCE OF ONE.
  #
  # scaffold-greenfield.sh runs this script at scaffold time, when the repo is by
  # definition docs-only: the day-1 documents exist and src/ does not. detect_type()
  # correctly answers `docs`, writes it, and the "auto-detected once, then never
  # re-guessed" rule freezes it there. So EVERY greenfield project is born labelled
  # `docs` and stays that way until somebody notices — which cost TfLens 225 gate
  # records (visual gates included) filed under a project_type whose definition says
  # gates cannot fire, and whose figures never pool with the apps it belongs beside.
  #
  # So `docs` alone is re-examined on a later refresh, and ONLY upgrades: once real
  # heads or a published package appear, the tree has answered the question that was
  # unanswerable at scaffold time. Everything else is left exactly as it was —
  # app/library/framework are never re-guessed, and an owner's `--type` always wins
  # (it takes the branch above). A genuine docs repo never grows a head, so it is
  # never touched.
  REDETECTED="$(detect_type)"
  if [[ -n "$REDETECTED" && "$REDETECTED" != "docs" ]]; then
    PTYPE="$REDETECTED"; GUESSED=1; UPGRADED=1
  else
    PTYPE="$EXISTING"
  fi
elif [[ -n "$EXISTING" ]]; then
  PTYPE="$EXISTING"
else
  PTYPE="$(detect_type)"
  GUESSED=1
fi

case "$PTYPE" in
  app|library|docs|framework) ;;
  *) echo "  ⚠ telemetry — invalid project_type '$PTYPE' (app|library|docs|framework); leaving unset" >&2; PTYPE="$EXISTING" ;;
esac

# THE FRAMEWORK REPO CLASSIFIES ITSELF, AND NOTHING IS WRITTEN DOWN.
#
# This file is the template. scaffold-greenfield/brownfield copy .tfcore/ with
# `rsync -a --ignore-existing`, so core-config.yaml lands in a brand-new app
# verbatim — and an existing classification always wins over the heuristic
# (EXISTING above). Writing `project_type: framework` here would therefore stamp
# `framework` on every app scaffolded afterwards, silently, with no way for the
# owner to notice until a report pooled them wrongly.
#
# So the readers detect it structurally instead (tf-emit.sh _project_type(),
# tf-metrics.sh project_type()): scaffold-brownfield.sh beside .tfcore/tasks/ IS
# the framework template and nothing else is. Same answer, nothing to leak.
if [[ "$PTYPE" == "framework" && -f scaffold-brownfield.sh && -d .tfcore/tasks ]]; then
  say "  $CFG — project_type: framework, DETECTED from the tree, not recorded"
  say "                  (this file is the scaffold template — writing it here would"
  say "                   misclassify every app created from it)"
elif [[ -n "$PTYPE" && "$EXISTING" != "$PTYPE" ]]; then
  if [[ $DRY -eq 1 ]]; then
    if [[ $GUESSED -eq 1 ]]; then
      say "  $CFG — WOULD set metrics.project_type: $PTYPE  (auto-detected)"
    else
      say "  $CFG — WOULD set metrics.project_type: $PTYPE"
    fi
  elif [[ -n "$EXISTING" ]]; then
    python3 - "$CFG" "$PTYPE" <<'PY' 2>/dev/null
import re, sys
p, t = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
s = re.sub(r"(^metrics:[ \t]*\n(?:[ \t]+.*\n)*?[ \t]+project_type:[ \t]*)\S+",
           lambda m: m.group(1) + t, s, count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
PY
    if [[ $UPGRADED -eq 1 ]]; then
      say "  $CFG — metrics.project_type UPGRADED 'docs' → '$PTYPE'"
      say "                  ('docs' was recorded at scaffold time, before this repo had any"
      say "                   source. Records already written carry the old value — see"
      say "                   .tfcore/telemetry/SCHEMA.md §1.)"
    else
      say "  $CFG — metrics.project_type changed to '$PTYPE'"
    fi
  else
    {
      echo ""
      echo "# metrics: telemetry classification. PRESERVED per-project — the framework"
      echo "# scripts never overwrite core-config.yaml, so this survives every refresh."
      echo "# app | library | docs | framework — see .tfcore/telemetry/SCHEMA.md §1."
      echo "# Gate-catch metrics are only comparable between projects of the SAME type:"
      echo "# a library has no screens, so it can never fail the visual-truth gate."
      echo "metrics:"
      echo "  project_type: $PTYPE"
    } >> "$CFG"
    if [[ $GUESSED -eq 1 ]]; then
      say "  $CFG — metrics.project_type: $PTYPE  (AUTO-DETECTED — correct it with:"
      say "                  .tfcore/telemetry/install-metrics.sh . --type app|library|docs|framework)"
    else
      say "  $CFG — metrics.project_type: $PTYPE"
    fi
  fi
fi

# --- 2. docs/metrics/ + the five streams ---------------------------------
if [[ $DRY -eq 1 ]]; then
  [[ -d docs/metrics ]] && say "  docs/metrics/ — present" \
                        || say "  docs/metrics/ — WOULD create + seed runs/gates/sessions/commits/misses.jsonl"
else
  mkdir -p docs/metrics
  NEW=()
  for s in runs gates sessions commits misses; do
    [[ -f "docs/metrics/$s.jsonl" ]] || { : > "docs/metrics/$s.jsonl"; NEW+=("$s"); }
  done
  [[ ${#NEW[@]} -gt 0 ]] && say "  docs/metrics/ — seeded ${NEW[*]}" || say "  docs/metrics/ — streams present"
fi

# --- 3. docs/metrics/README.md -------------------------------------------
if [[ $DRY -eq 0 ]]; then
cat > docs/metrics/README.md <<'MD'
# docs/metrics — development telemetry

Append-only JSONL. **Tracked by git on purpose** — this is the project's own
development history, and it is the one thing the framework cannot reconstruct
after the fact.

| File | One record per | Written by |
|---|---|---|
| `runs.jsonl` | framework command run | the task, at completion |
| `gates.jsonl` | REQ verdict per verify run — **the primary stream** | `verify-phase` §6a, `triage-issues` |
| `sessions.jsonl` | agent session | the `SessionEnd` hook |
| `commits.jsonl` | commit | the repo's own `pre-commit` hook |
| `misses.jsonl` | a requirement/behaviour an agent MISSED, and what fixing it cost | `verify-phase`, `build-phase`, `triage-issues`, `fix-issues`, `amend-docs`, `*log-miss` |

`misses.jsonl` is the one stream with **three** record kinds — `miss` (opened: what
was missed, which phase/agent/model let it through, who found it), `miss-fix`
(closed: the repair run and its token/cost window, linked by `miss_id`) and
`miss-amend` (completes a field the `miss` left empty — it can fill a `null` and
can never overwrite a value, so it adds to the history without revising it). It is
what makes "how much did that miss cost to fix" answerable. SCHEMA.md §5.5.

Schema, enums, and every known limitation: `.tfcore/telemetry/SCHEMA.md`.
Report: `/TechieFlow:agents:flow-master *metrics <AppName>` (OpenCode: `/flow-master *metrics <AppName>`) → `METRICS.md`.

**All five files are created empty, on purpose, and an empty one is not a fault.**
The installer seeds the set so every repo has the same shape and no writer has to
guess whether its stream exists. A stream stays at zero bytes until something
actually happens: `gates.jsonl` until the first `*verify`, `runs.jsonl` until the
first framework command, `sessions.jsonl` until the first agent session ends, and
`commits.jsonl` until your first commit after telemetry was installed, and
`misses.jsonl` until an agent misses something (which it will). Commit
these empty files along with the rest — a tracked empty stream is what makes the
first record a one-line diff instead of a new file appearing from nowhere.

**Never edit these files by hand, never sort them, never compact them.** They are
a log. Rewriting one destroys exactly the history it exists to keep. To correct or
complete a record, append another one: a later `gates.jsonl` record supersedes an
earlier verdict, a `miss-fix` closes a `miss`, and
`bash .tfcore/utils/tf-emit.sh --amend <miss_id> <field> <value>` fills a field a
`miss` left empty (it refuses to overwrite one that is not empty). If nothing fits
what you need to correct, say so rather than editing — that is a framework defect
worth reporting, and it is how the amend path came to exist.

**No secrets, no content, no client data** — records carry IDs, counts, durations,
verdicts and file paths at most. Never requirement text, prompt text, file
contents, or commit subjects. Assume every line here could become public.

## Working on more than one machine

`.gitattributes` gives these streams `merge=union`, so two machines appending to
the same file keep **both** sides' lines instead of conflicting. Pull, push, carry
on — you never hand-resolve a log, which is the one way records get silently
dropped. Union merge can leave a record duplicated or out of chronological order;
every consumer sorts on `ts` and de-duplicates commits on `sha`, so neither costs
you anything.

**`commits.jsonl` needs no collecting.** The `pre-commit` hook *reconciles*: it
writes a record for every commit reachable from HEAD that the file does not
already have, then stages that one file so the records ship **inside** the commit
you are making. So after you pull another machine's work, your next commit here
records all of it. The commit log is itself an append-only log that push and pull
already replicate everywhere; this stream is a projection of it.

Three things worth knowing:

- **It stages exactly one path** — `docs/metrics/commits.jsonl`, nothing else. On
  a partial commit (`git commit -- <paths>`) it writes the record but does **not**
  stage, so it can never smuggle a file into a commit you deliberately scoped.
- **The lag is one commit, and it is committed rather than pending.** At
  pre-commit time HEAD is still the previous commit, so the record for the commit
  you are making ships in the next one. Your working tree is clean when the commit
  finishes — that is the whole reason this is a pre-commit hook and not a
  post-commit one.
- The hook lives in `.git/hooks/`, which is **not** part of the repository, so
  every clone needs its own. `update-framework.sh <repo>` installs it, and
  `tf-metrics.sh --report` warns when the clone you are standing in has none. If
  you already have your own `pre-commit` hook, the installer leaves it alone and
  tells you — add `bash .tfcore/telemetry/pre-commit` to it if you want both.

Merge commits, `--no-verify`, rebases and cherry-picks skip the hook entirely.
Nothing is lost: reconciling means the next ordinary commit — here or on any
machine that pulls — notices those commits are missing and writes them.

To fill in a machine's history immediately rather than waiting for a commit:

    .tfcore/telemetry/tf-metrics.sh --backfill-commits .

Idempotent — already-recorded shas are skipped — so run it as often as you like.
It is also why the hook is optional: delete it and reconcile by hand instead.
MD
fi

# --- 4. pre-commit hook — located WITHOUT invoking git -------------------
# Since 2026-08-11 the commit-telemetry hook is **pre**-commit, so the record
# ships INSIDE the commit and the working tree is clean afterwards. The old
# post-commit hook wrote its line after the commit was sealed, which left
# commits.jsonl permanently dirty with no reachable clean state. Our own
# post-commit is therefore REMOVED here; a foreign one is never touched.
HOOKS_DIR=""
if [[ -d .git ]]; then
  HOOKS_DIR=".git/hooks"
elif [[ -f .git ]]; then
  # worktree / submodule: ".git" is a file containing "gitdir: <path>"
  GD="$(sed -n 's/^gitdir:[[:space:]]*//p' .git | head -1)"
  [[ -n "$GD" ]] && { [[ "$GD" = /* ]] || GD="$TARGET/$GD"; [[ -d "$GD" ]] && HOOKS_DIR="$GD/hooks"; }
fi

if [[ -z "$HOOKS_DIR" ]]; then
  say "  pre-commit — not a work tree yet; commits.jsonl stays empty (re-run the updater after init)"
else
  SRC="$TEMPLATE/.tfcore/telemetry/pre-commit"
  DEST="$HOOKS_DIR/pre-commit"
  OLD="$HOOKS_DIR/post-commit"

  # 4a. retire OUR post-commit. Identified by the template's own marker, so a
  #     hook you wrote yourself is left exactly where it is.
  if [[ -f "$OLD" ]] && grep -q 'TechieFlow telemetry' "$OLD" 2>/dev/null; then
    if [[ $DRY -eq 1 ]]; then
      say "  $OLD — WOULD remove (superseded by pre-commit)"
    else
      rm -f "$OLD" && say "  $OLD — removed (superseded by pre-commit)"
    fi
  fi

  # 4b. install pre-commit. A pre-commit hook is where people put lint and test
  #     gates, so unlike the old post-commit path this NEVER replaces one it did
  #     not write. Losing someone's lint gate to a telemetry install would be a
  #     far worse outcome than not collecting commit records.
  if [[ -f "$DEST" ]] && ! grep -q 'TechieFlow telemetry' "$DEST" 2>/dev/null; then
    echo "  ⚠ $DEST already exists and is NOT the TechieFlow hook — left untouched."
    echo "    Commit telemetry is not installed here. To have both, add this line to"
    echo "    your hook:  bash .tfcore/telemetry/pre-commit"
    echo "    (or reconcile by hand: tf-metrics.sh --backfill-commits .)"
  elif [[ -f "$DEST" ]] && cmp -s "$SRC" "$DEST"; then
    say "  $DEST — already current"
  elif [[ $DRY -eq 1 ]]; then
    say "  $DEST — WOULD install the commit-telemetry hook"
  else
    mkdir -p "$HOOKS_DIR" 2>/dev/null
    cp "$SRC" "$DEST" && chmod +x "$DEST" && say "  $DEST — installed"
  fi
fi

# --- 5. the data must stay TRACKED --------------------------------------
if [[ -f .gitignore ]] && tr -d '\r' < .gitignore | grep -qE '^/?docs/?$|^/?docs/metrics'; then
  echo "  ⚠ .gitignore has a pattern that would swallow docs/metrics/ — the telemetry data"
  echo "    MUST be tracked. Add an explicit negation:  !docs/metrics/  and  !docs/metrics/**"
fi

exit 0

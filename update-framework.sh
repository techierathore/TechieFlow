#!/usr/bin/env bash
# update-framework.sh — Refresh the TechieFlow v4 framework in an ALREADY-SCAFFOLDED
# project, without touching any of your work product.
#
# Use this when the reference framework at /mnt/c/3AIGenCode/TechieFlow/ has
# evolved (new tasks, updated workflows, agent fixes) and you want those
# changes in an existing project.
#
# Differs from scaffold-brownfield.sh:
#   scaffold-*  → rsync --ignore-existing (never updates existing files)
#   update      → rsync (force-overwrite) on FRAMEWORK files only, with an
#                 explicit preserve-list for everything that contains your
#                 per-project content.
#
# Usage:
#   /mnt/c/3AIGenCode/TechieFlow/update-framework.sh /path/to/existing-app
#   /mnt/c/3AIGenCode/TechieFlow/update-framework.sh /path/to/app --dry-run
#   /mnt/c/3AIGenCode/TechieFlow/update-framework.sh /path/to/app --keep-permissions
#   /mnt/c/3AIGenCode/TechieFlow/update-framework.sh   (defaults to $PWD)
#
# .claude/settings.json is REFRESHED BY DEFAULT to the canonical yolo-except-git
# block (allow all Bash; ask only on rm/rmdir/sudo; DENY git/gh outright — git is
# manual in TechieFlow, agents never run it — plus a PreToolUse hook,
# .tfcore/hooks/block-git.sh, that also blocks compound forms like
# "cd x && git log" which prefix rules miss) so every project stays in sync
# automatically — no per-app flag needed. This kills the "asked for permission
# 100 times" friction: the old enumerated allow-list missed WSL command variants
# (e.g. ~/.dotnet/dotnet build) and prompted on every one. The refresh is
# idempotent (no .bak churn when already current) and backs up any differing old
# file to settings.json.bak. Per-project approvals live in settings.local.json,
# which is never touched. Opt out for a locked-down project with --keep-permissions.
#
# Force-overwritten (framework — reference repo is source of truth):
#   .tfcore/{tasks,templates,agents,checklists,data,utils,hooks}/ (stock workflows/agent-teams trimmed)
#   .tfcore/{enhanced-ide-development-workflow,user-guide,working-in-the-brownfield}.md
#   .tfcore/install-manifest.yaml
#   .tfcore/TOKEN-GUIDE.md
#   .claude/commands/TechieFlow/ subtree (TechieFlow agents + skills)
#   .opencode/command/TechieFlow/ subtree
#   .claude/settings.json               (yolo-except-git; --keep-permissions to skip)
#   WORKFLOW.html
#
# Ensured (append-only, idempotent):
#   .gitignore — framework block (.tfcore/, .claude/, .opencode/, /CLAUDE.md,
#   /WORKFLOW.html, /opencode.jsonc, /.tf-scaffold-note.txt): deployed copies
#   must never be committed in an app repo. Existing entries are respected;
#   nothing is removed or rewritten.
#
# Preserved (per-project work product — never touched):
#   .tfcore/core-config.yaml         (customTechnicalDocuments paths)
#   docs/                               (BRD, Architecture, Coding-Standards, etc.)
#   src/, tests/                        (your code)
#   PROJECT-STATUS.md, CLAUDE.md        (per-project state)
#   .editorconfig                       (per-project)
#   .claude/settings.local.json         (per-machine one-off approvals — never touched)
#   .claude/{trblazeui,techierag}.md    (NuGet-deployed library agents)
#   .opencode/command/{trblazeui,techierag}.md
#   opencode.jsonc                      (may have project-specific agents)
#   .tf-scaffold-note.txt
#
# Idempotent: re-running with the same reference repo produces the same result.

set -euo pipefail

TEMPLATE="/mnt/c/3AIGenCode/TechieFlow"

DRY_RUN=0
KEEP_PERMS=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --keep-permissions) KEEP_PERMS=1 ;;
    # --refresh-permissions kept for back-compat; refreshing is now the default
    --refresh-permissions) KEEP_PERMS=0 ;;
    -*)
      echo "Unknown flag: $arg" >&2
      echo "Usage: update-framework.sh [/path/to/app] [--dry-run] [--keep-permissions]" >&2
      exit 2
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$arg"
      else
        echo "Unexpected extra argument: $arg" >&2
        exit 2
      fi
      ;;
  esac
done

TARGET="${TARGET:-$PWD}"
TARGET="$(realpath "$TARGET")"

if [[ "$TARGET" == "$TEMPLATE" || "$TARGET" == "$TEMPLATE"/* ]]; then
  echo "Refusing to update the reference template itself." >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync not found. Install it -- Linux/WSL: sudo apt-get install rsync  |  macOS: brew install rsync (usually preinstalled)  |  native Windows: run this script from WSL or Git Bash" >&2
  exit 1
fi

if [[ ! -d "$TARGET" ]]; then
  echo "Target directory does not exist: $TARGET" >&2
  exit 1
fi

# --------------------------------------------------------------------------
# 0. ONE-TIME MIGRATION — legacy .bmad-core/ layout → .tfcore/ + TechieFlow/.
#    Older projects were scaffolded with the previous folder/command names
#    (.bmad-core/, .claude/commands/BMad/, .opencode/command/BMad/, the split
#    bmad-master + bmad-orchestrator agents, slashPrefix: BMad). Rename the core
#    in place (preserving your per-project core-config.yaml + docs), delete the
#    old harness mirror dirs, patch core-config + opencode.jsonc, then let the
#    normal force-overwrite below bring everything current (the split super-agents
#    collapse into flow-master, bmad-kb → techieflow-kb, etc. via rsync --delete).
# --------------------------------------------------------------------------
if [[ ! -d "$TARGET/.tfcore" && -d "$TARGET/.bmad-core" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "→ DRY RUN — $TARGET uses the legacy .bmad-core/ layout."
    echo "  A real run would MIGRATE it first:"
    echo "    • mv .bmad-core/ → .tfcore/   (keeps your core-config.yaml + docs)"
    echo "    • rm -rf .claude/commands/BMad/  .opencode/command/BMad/   (old mirrors)"
    echo "    • patch .tfcore/core-config.yaml (slashPrefix: TechieFlow, .tfcore paths)"
    echo "    • back up & replace a legacy opencode.jsonc"
    echo "    • delete the disposable legacy scaffold note"
    echo "    • remove trimmed stock dirs (workflows/, agent-teams/) if present"
    echo "    • flag (not edit) any stale framework refs in YOUR CLAUDE.md / PROJECT-STATUS.md / docs"
    echo "  …then apply the usual framework refresh. Re-run without --dry-run to do it."
    echo ""
    exit 0
  fi

  echo "→ Migrating legacy .bmad-core/ layout to .tfcore/ in: $TARGET"
  mv "$TARGET/.bmad-core" "$TARGET/.tfcore"
  echo "  .bmad-core/ → .tfcore/   (per-project core-config.yaml + any docs preserved)"

  # Patch the preserved (not force-synced) core-config.yaml.
  if [[ -f "$TARGET/.tfcore/core-config.yaml" ]]; then
    sed -i -e 's/\.bmad-core/.tfcore/g' \
           -e 's/^slashPrefix:[[:space:]]*BMad/slashPrefix: TechieFlow/' \
           "$TARGET/.tfcore/core-config.yaml"
    echo "  patched .tfcore/core-config.yaml (slashPrefix: TechieFlow, .tfcore paths)"
  fi

  # Old harness mirror dirs — removed; the TechieFlow/ subtrees are recreated below.
  rm -rf "$TARGET/.claude/commands/BMad" "$TARGET/.opencode/command/BMad"
  echo "  removed legacy .claude/commands/BMad/ and .opencode/command/BMad/"

  # Legacy data/utils basenames — rsync --delete in step 1 handles them, but the
  # KB rename is removed here too so no stale techieflow-kb sibling lingers if the
  # template ever stops shipping data/.
  rm -f "$TARGET/.tfcore/data/bmad-kb.md" "$TARGET/.tfcore/utils/bmad-doc-template.md"

  # Legacy scaffold note — a disposable one-time note whose body is now stale
  # stock text; remove it rather than rename (renaming would keep stale content).
  if [[ -f "$TARGET/.bmad-scaffold-note.txt" ]]; then
    rm -f "$TARGET/.bmad-scaffold-note.txt"
    echo "  removed disposable legacy .bmad-scaffold-note.txt"
  fi

  # A legacy opencode.jsonc points at .bmad-core/ paths and the old bmad-* agent
  # keys (incl. the now-merged bmad-master/bmad-orchestrator) — structurally stale.
  # Back it up and drop in the current template so the harness wires flow-master.
  if [[ -f "$TARGET/opencode.jsonc" ]] && grep -qE '\.bmad-core|bmad-(master|orchestrator|analyst|architect|verifier)|BMad:' "$TARGET/opencode.jsonc"; then
    cp "$TARGET/opencode.jsonc" "$TARGET/opencode.jsonc.bak"
    cp "$TEMPLATE/opencode.jsonc" "$TARGET/opencode.jsonc"
    echo "  opencode.jsonc — legacy version backed up to opencode.jsonc.bak, replaced with current template"
  fi
  echo ""
fi

if [[ ! -d "$TARGET/.tfcore" ]]; then
  echo "$TARGET does not look scaffolded (no .tfcore/ or legacy .bmad-core/ found)." >&2
  echo "Use scaffold-brownfield.sh or scaffold-greenfield.sh first." >&2
  exit 1
fi

cd "$TARGET"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "→ DRY RUN — showing what would change in: $TARGET"
  echo ""
  RSYNC_FLAGS="-ain"    # itemize, archive, dry-run
else
  echo "→ Updating TechieFlow framework in: $TARGET"
  echo "  (your docs/, src/, tests/, PROJECT-STATUS.md, CLAUDE.md are NOT touched)"
  echo ""
  RSYNC_FLAGS="-a"
fi

# Library agents are NuGet-deployed at the command ROOTS only
# (.claude/<lib>.md, .opencode/command/<lib>.md). The TechieFlow subtrees and
# .tfcore/ never receive NuGet files, so those rsyncs run WITHOUT excludes —
# letting --delete purge any stale legacy copies of trblazeui.md/techierag.md.
# The top-level command loops below skip those basenames explicitly instead.

# --------------------------------------------------------------------------
# 1. .tfcore/ — framework subdirs only; core-config.yaml is per-project
# --------------------------------------------------------------------------
FRAMEWORK_SUBDIRS=(
  agents
  tasks
  templates
  checklists
  data
  utils
  hooks
  workflows
  agent-teams
)

for dir in "${FRAMEWORK_SUBDIRS[@]}"; do
  if [[ -d "$TEMPLATE/.tfcore/$dir" ]]; then
    echo "  .tfcore/$dir/"
    rsync $RSYNC_FLAGS --delete \
      "$TEMPLATE/.tfcore/$dir/" ".tfcore/$dir/"
  elif [[ -d ".tfcore/$dir" ]]; then
    # Dir exists in the target but no longer ships with the framework. The two
    # known-trimmed stock dirs (workflows/, agent-teams/ — stock story-flow cruft,
    # trimmed 2026-06-12) are removed so a migrated project stays clean; anything
    # else is only flagged (conservative — could be intentional local content).
    case "$dir" in
      workflows|agent-teams)
        if [[ $DRY_RUN -eq 1 ]]; then
          echo "  WOULD remove stale stock dir .tfcore/$dir/ (no longer ships)"
        else
          rm -rf ".tfcore/$dir"
          echo "  removed stale stock dir .tfcore/$dir/ (no longer ships)"
        fi
        ;;
      *)
        echo "  NOTE: .tfcore/$dir/ no longer ships with the framework — safe to delete manually."
        ;;
    esac
  fi
done

# Top-level .tfcore/*.md framework docs — overwrite individually
for f in enhanced-ide-development-workflow.md user-guide.md working-in-the-brownfield.md install-manifest.yaml TOKEN-GUIDE.md; do
  if [[ -f "$TEMPLATE/.tfcore/$f" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      rsync $RSYNC_FLAGS "$TEMPLATE/.tfcore/$f" ".tfcore/$f" || true
    else
      cp "$TEMPLATE/.tfcore/$f" ".tfcore/$f"
    fi
  fi
done

# core-config.yaml is preserved (per-project customTechnicalDocuments paths)
if [[ -f .tfcore/core-config.yaml ]]; then
  echo "  .tfcore/core-config.yaml — preserved (per-project)"
fi

# --------------------------------------------------------------------------
# 2. .claude/commands/TechieFlow/ — force-overwrite; library agents at root preserved
# --------------------------------------------------------------------------
[[ $DRY_RUN -eq 1 ]] || mkdir -p .claude/commands/TechieFlow
echo "  .claude/commands/TechieFlow/"
rsync $RSYNC_FLAGS --delete \
  "$TEMPLATE/.claude/commands/TechieFlow/" .claude/commands/TechieFlow/

# Sync canonical agents → harness path (paranoia in case agents/ rsync above
# excluded something via globs; this guarantees the harness sees the latest).
# Sourced from the TEMPLATE, not the target's .tfcore/agents/ — equivalent
# after step 1, but keeps --dry-run previews accurate.
rsync $RSYNC_FLAGS \
  "$TEMPLATE/.tfcore/agents/" .claude/commands/TechieFlow/agents/

# Top-level short-form commands (e.g. /generate-html) — force-overwrite by name.
# These live at .claude/commands/ root so the short slash form works; the rsync
# above only covers the TechieFlow/ subtree, so sync them explicitly. The NuGet-deployed
# library personas are skipped — they must never be overwritten by the framework.
for src in "$TEMPLATE"/.claude/commands/*.md; do
  [[ -f "$src" ]] || continue
  f="$(basename "$src")"
  case "$f" in trblazeui.md|techierag.md) continue ;; esac
  echo "  .claude/commands/$f"
  rsync $RSYNC_FLAGS "$src" ".claude/commands/$f"
done

# .claude/settings.json — REFRESHED BY DEFAULT to the canonical yolo-except-git
# block (allow all Bash; ask on rm/rmdir/sudo; DENY git/gh + the block-git.sh
# PreToolUse hook — git is manual, agents never run it) so every project stays in sync
# without per-app fiddling. settings.json is framework baseline; genuine
# per-project approvals belong in settings.local.json (which is NEVER touched).
# Opt out for a deliberately locked-down project with --keep-permissions.
# Idempotent: if the file already matches the canonical block, it is left as-is
# (no needless .bak churn on re-runs). When it differs, the old file is backed up.
CANONICAL_SETTINGS='{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash",
      "Edit",
      "Write",
      "MultiEdit",
      "NotebookEdit",
      "Read",
      "Glob",
      "Grep",
      "TodoWrite",
      "WebFetch",
      "WebSearch",
      "Task"
    ],
    "ask": [
      "Bash(rm *)",
      "Bash(rmdir *)",
      "Bash(sudo *)"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf /*)",
      "Bash(rm -rf ~)",
      "Bash(rm -rf ~/*)",
      "Bash(git)",
      "Bash(git *)",
      "Bash(gh)",
      "Bash(gh *)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/block-git.sh\""
          }
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-status.sh\""
          },
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-verify.sh\""
          }
        ]
      }
    ]
  }
}'
if [[ $KEEP_PERMS -eq 1 ]]; then
  if [[ -f .claude/settings.json ]]; then
    echo "  .claude/settings.json — preserved (--keep-permissions)"
  fi
elif [[ -f .claude/settings.json ]] && [[ "$(cat .claude/settings.json)" == "$CANONICAL_SETTINGS" ]]; then
  echo "  .claude/settings.json — already current (yolo-except-git)"
elif [[ $DRY_RUN -eq 1 ]]; then
  echo "  .claude/settings.json — WOULD refresh to yolo-except-git (use --keep-permissions to opt out)"
else
  mkdir -p .claude
  if [[ -f .claude/settings.json ]]; then
    cp .claude/settings.json .claude/settings.json.bak
    echo "  .claude/settings.json — old version backed up to settings.json.bak"
  fi
  printf '%s\n' "$CANONICAL_SETTINGS" > .claude/settings.json
  echo "  .claude/settings.json — refreshed to yolo-except-git"
fi

# Library agents at .claude/ root are NuGet-deployed and never touched
for f in trblazeui.md techierag.md; do
  if [[ -f ".claude/$f" ]]; then
    echo "  .claude/$f — preserved (NuGet-deployed)"
  fi
done

# --------------------------------------------------------------------------
# 3. .opencode/command/TechieFlow/ — force-overwrite
# --------------------------------------------------------------------------
[[ $DRY_RUN -eq 1 ]] || mkdir -p .opencode/command/TechieFlow
echo "  .opencode/command/TechieFlow/"
rsync $RSYNC_FLAGS --delete \
  "$TEMPLATE/.opencode/command/TechieFlow/" .opencode/command/TechieFlow/

# Sync canonical agents → opencode harness path. Sourced from the TEMPLATE,
# not the target's .tfcore/agents/ — equivalent after step 1, but keeps
# --dry-run previews accurate.
rsync $RSYNC_FLAGS \
  "$TEMPLATE/.tfcore/agents/" .opencode/command/TechieFlow/agents/

# Top-level short-form commands for OpenCode (e.g. /generate-html).
# NuGet-deployed library personas are skipped — never overwrite them.
for src in "$TEMPLATE"/.opencode/command/*.md; do
  [[ -f "$src" ]] || continue
  f="$(basename "$src")"
  case "$f" in trblazeui.md|techierag.md) continue ;; esac
  echo "  .opencode/command/$f"
  rsync $RSYNC_FLAGS "$src" ".opencode/command/$f"
done

# opencode.jsonc preserved (may have project-specific agent block)
if [[ -f opencode.jsonc ]]; then
  echo "  opencode.jsonc — preserved (per-project)"
fi

# Library agents under .opencode/command/ root preserved
for f in trblazeui.md techierag.md; do
  if [[ -f ".opencode/command/$f" ]]; then
    echo "  .opencode/command/$f — preserved (NuGet-deployed)"
  fi
done

# --------------------------------------------------------------------------
# 4. WORKFLOW.html — canonical workflow guide, always overwrite
# --------------------------------------------------------------------------
if [[ -f "$TEMPLATE/WORKFLOW.html" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    rsync $RSYNC_FLAGS "$TEMPLATE/WORKFLOW.html" "WORKFLOW.html" || true
  else
    cp "$TEMPLATE/WORKFLOW.html" "WORKFLOW.html"
  fi
  echo "  WORKFLOW.html"
fi

# --------------------------------------------------------------------------
# 5. NuGet persona shims — Claude Code only scans .claude/commands/ for slash
#    commands, but NuGet auto-deploy drops library personas at .claude/<lib>.md.
#    Mirror them into .claude/commands/ so /trblazeui and /techierag resolve.
#    The NuGet-deployed file is authoritative — always overwrite the shim.
# --------------------------------------------------------------------------
for lib in trblazeui techierag; do
  if [[ -f ".claude/$lib.md" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  WOULD shim .claude/$lib.md → .claude/commands/$lib.md"
    else
      cp ".claude/$lib.md" ".claude/commands/$lib.md"
      echo "  shimmed .claude/$lib.md → .claude/commands/$lib.md"
    fi
  fi
done

# --------------------------------------------------------------------------
# 6. Stale opencode.jsonc detection — opencode.jsonc is preserved (per-project),
#    but the 2026-06-12 trim removed the stock agents (dev/pm/po/qa/sm/ux-expert)
#    from .tfcore/agents/. An old opencode.jsonc that still wires them would
#    point at files step 1's --delete just removed.
# --------------------------------------------------------------------------
if [[ -f opencode.jsonc ]] && grep -qE 'agents/(dev|pm|po|qa|sm|ux-expert)\.md' opencode.jsonc; then
  echo ""
  echo "  ⚠ opencode.jsonc references trimmed stock agents (dev/pm/po/qa/sm/ux-expert),"
  echo "    whose files were just removed from .tfcore/agents/. Copy the template's"
  echo "    opencode.jsonc ($TEMPLATE/opencode.jsonc) or delete those agent entries."
fi

# --------------------------------------------------------------------------
# 7. Stale framework refs in YOUR work product — flagged, never auto-edited.
#    After a layout change, per-project files you own (CLAUDE.md, PROJECT-STATUS,
#    .gitignore, docs, HTML renders) may still point at the old layout. The
#    framework will NOT rewrite your files — it lists them so you can update or
#    regenerate them. (docs/OldDocs/ — your own history — is intentionally skipped.)
# --------------------------------------------------------------------------
STALE_PAT='\.bmad-core|/BMad:|BMad:agents:|bmad-master|bmad-orchestrator|bmad-analyst|bmad-architect|bmad-verifier'
STALE_HITS=()
while IFS= read -r cand; do
  [[ -f "$cand" ]] || continue
  grep -lqE "$STALE_PAT" "$cand" 2>/dev/null && STALE_HITS+=("$cand")
done < <(
  { [[ -f CLAUDE.md ]] && echo CLAUDE.md
    [[ -f PROJECT-STATUS.md ]] && echo PROJECT-STATUS.md
    [[ -f .gitignore ]] && echo .gitignore
    find docs -maxdepth 1 -type f \( -name '*.md' -o -name '*.html' \) 2>/dev/null
    find . -maxdepth 1 -type f -name '*.html' 2>/dev/null
  } | sort -u
)
if [[ ${#STALE_HITS[@]} -gt 0 ]]; then
  echo ""
  echo "  ⚠ These files YOU own still reference the old framework layout (NOT auto-edited):"
  for sf in "${STALE_HITS[@]}"; do echo "      $sf"; done
  echo "    Update the pointers (.bmad-core→.tfcore, /BMad:→/TechieFlow:,"
  echo "    bmad-master/bmad-orchestrator→flow-master) or regenerate them"
  echo "    (re-run day-1 / *refresh-status / *render-workflow-docs)."
fi

# --------------------------------------------------------------------------
# 8. .gitignore — ensure the framework block. Everything the framework deploys
#    into a project is a COPY (source of truth: the TechieFlow reference repo,
#    or the NuGet package for the library personas) — committing the copies
#    just adds churn on every refresh. Append-only + idempotent: any existing
#    anchored/slash variant of an entry is respected; user content is never
#    rewritten. NOTE: ignore rules do not UNtrack already-committed files —
#    if any of these are already tracked, the owner must run
#    `git rm -r --cached <path>` once (git is manual, owner-only).
# --------------------------------------------------------------------------
GI_LINES=(".tfcore/" ".claude/" ".opencode/" "/CLAUDE.md" "/WORKFLOW.html" "/opencode.jsonc" "/.tf-scaffold-note.txt")
GI_PATS=('^/?\.tfcore/?$' '^/?\.claude/?$' '^/?\.opencode/?$' '^/?CLAUDE\.md$' '^/?WORKFLOW\.html$' '^/?opencode\.jsonc$' '^/?\.tf-scaffold-note\.txt$')
GI_MISSING=()
for i in "${!GI_LINES[@]}"; do
  # tr strips CR so CRLF .gitignore files (Windows-authored) still match the $-anchor
  [[ -f .gitignore ]] && tr -d '\r' < .gitignore | grep -qE "${GI_PATS[$i]}" && continue
  GI_MISSING+=("${GI_LINES[$i]}")
done
if [[ ${#GI_MISSING[@]} -eq 0 ]]; then
  echo "  .gitignore — framework entries already present"
elif [[ $DRY_RUN -eq 1 ]]; then
  echo "  .gitignore — WOULD add framework entries: ${GI_MISSING[*]}"
else
  { echo ""
    echo "# TechieFlow framework — deployed copies, never commit (managed by scaffold/update-framework.sh)"
    printf '%s\n' "${GI_MISSING[@]}"
  } >> .gitignore
  echo "  .gitignore — added framework entries: ${GI_MISSING[*]}"
fi

# --------------------------------------------------------------------------
# Done
# --------------------------------------------------------------------------
echo ""
if [[ $DRY_RUN -eq 1 ]]; then
  echo "✔ Dry run complete — no files changed."
  echo "  Re-run without --dry-run to apply."
else
  echo "✔ Framework updated. Your docs/, src/, tests/, and per-project state files were NOT touched."
  echo ""
  echo "Reminder:"
  echo "  - In Claude Code, RESTART the session so the new task/agent definitions are loaded."
  echo "  - If a task file references a new template under .tfcore/templates/v4custom/,"
  echo "    that template is now in place locally."
fi

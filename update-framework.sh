#!/usr/bin/env bash
# update-framework.sh — Refresh the TechieFlow v4 framework in an ALREADY-SCAFFOLDED
# project, without touching any of your work product.
#
# Use this when the reference framework repo (wherever it lives — this script
# finds it from its own location) has evolved (new tasks, updated workflows,
# agent fixes) and you want those changes in an existing project.
#
# Differs from scaffold-brownfield.sh:
#   scaffold-*  → rsync --ignore-existing (never updates existing files)
#   update      → rsync (force-overwrite) on FRAMEWORK files only, with an
#                 explicit preserve-list for everything that contains your
#                 per-project content.
#
# Usage (run from wherever the TechieFlow repo lives — WSL, macOS, Linux):
#   /path/to/TechieFlow/update-framework.sh /path/to/existing-app
#   /path/to/TechieFlow/update-framework.sh /path/to/app --dry-run
#   /path/to/TechieFlow/update-framework.sh /path/to/app --keep-permissions
#   /path/to/TechieFlow/update-framework.sh   (defaults to $PWD)
#
# .claude/settings.json is REFRESHED BY DEFAULT to the canonical yolo-except-git-writes-writes
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
#   .opencode/command/ root top-level short-form commands (e.g. /generate-html)
#   .opencode/plugin/*.js               (guard bridge + telemetry — runs the same
#                                        .tfcore/hooks/ guards Claude Code runs)
#   .opencode/opencode.jsonc            (framework config copy; wins over the
#                                        root opencode.jsonc on conflicting keys;
#                                        {file:} refs rewritten to ../.tfcore/)
#   .claude/settings.json               (yolo-except-git-writes; --keep-permissions to skip)
#   WORKFLOW.html
#
# OpenCode agents/tasks are NOT mirrored to .opencode/command/TechieFlow/ (that
# subtree was removed — it only registered phantom slash commands). OpenCode
# loads them from opencode.jsonc via {file:./.tfcore/...} references.
#
# Ensured (append-only, idempotent):
#   .gitignore — framework block (.tfcore/, .claude/, .opencode/, /CLAUDE.md,
#   /WORKFLOW.html, /opencode.jsonc, /.tf-scaffold-note.txt): deployed copies
#   must never be committed in an app repo. Existing entries are respected;
#   nothing is removed or rewritten.
#
# Preserved (per-project work product — never touched):
#   .tfcore/core-config.yaml         (customTechnicalDocuments paths)
#   .tfcore/routing.yaml             (per-project model routing; deployed once
#                                     with enabled: false, then owner-tuned)
#   docs/                               (BRD, Architecture, Coding-Standards, etc.)
#   src/, tests/                        (your code)
#   PROJECT-STATUS.md, CLAUDE.md        (per-project state)
#   .editorconfig                       (per-project)
#   .claude/settings.local.json         (per-machine one-off approvals — never touched)
#   .claude/{trblazeui,techierag}.md    (NuGet-deployed library agents)
#   .opencode/command/{trblazeui,techierag}.md
#   opencode.jsonc                      (may have project-specific agents; the
#                                        framework's keys now arrive via the
#                                        refreshed .opencode/opencode.jsonc)
#   .tf-scaffold-note.txt
#
# Idempotent: re-running with the same reference repo produces the same result.

set -euo pipefail

# The reference framework is wherever this script lives — no hardcoded path,
# so the repo works from WSL (/mnt/c/...), macOS (/Volumes/...), or Linux.
TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    # temp-file + mv instead of sed -i: BSD sed (macOS) treats "-i -e" as a
    # backup suffix and would litter a core-config.yaml-e file
    sed -e 's/\.bmad-core/.tfcore/g' \
        -e 's/^slashPrefix:[[:space:]]*BMad/slashPrefix: TechieFlow/' \
        "$TARGET/.tfcore/core-config.yaml" > "$TARGET/.tfcore/core-config.yaml.tmp" \
      && mv "$TARGET/.tfcore/core-config.yaml.tmp" "$TARGET/.tfcore/core-config.yaml"
    echo "  patched .tfcore/core-config.yaml (slashPrefix: TechieFlow, .tfcore paths)"
  fi

  # Old harness mirror dirs — removed; the Claude Code TechieFlow/ subtree is
  # recreated below (OpenCode no longer uses a .opencode/command/TechieFlow/ mirror).
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
# (.claude/<lib>.md, .opencode/command/<lib>.md). The .claude/commands/TechieFlow/
# subtree and .tfcore/ never receive NuGet files, so those rsyncs run WITHOUT
# excludes — letting --delete purge any stale legacy copies of
# trblazeui.md/techierag.md. The top-level command loops below skip those
# basenames explicitly instead.

# --------------------------------------------------------------------------
# 1. .tfcore/ — framework subdirs only; core-config.yaml is per-project
# --------------------------------------------------------------------------
FRAMEWORK_SUBDIRS=(
  agents
  tasks
  telemetry
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

# routing.yaml — deployed if missing, PRESERVED if present (per-project: the
# rollout plan flips `enabled: true` one app at a time and the owner tunes the
# tier→model map per machine/provider; clobbering it would silently un-route
# an app — see docs/Adapter-Design.md §5.2, DECISIONS.md 2026-08-19 §2).
if [[ -f .tfcore/routing.yaml ]]; then
  echo "  .tfcore/routing.yaml — preserved (per-project routing declaration)"
elif [[ -f "$TEMPLATE/.tfcore/routing.yaml" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    rsync $RSYNC_FLAGS "$TEMPLATE/.tfcore/routing.yaml" ".tfcore/routing.yaml" || true
  else
    cp "$TEMPLATE/.tfcore/routing.yaml" ".tfcore/routing.yaml"
  fi
  echo "  .tfcore/routing.yaml — deployed (enabled: false; routing is opt-in per app)"
fi

# Re-emit (or clean) the routing bindings from THIS app's routing.yaml:
# .claude/commands/tf/<phase>.md wrappers + .claude/agents/tf-*.md +
# .opencode/opencode.json when enabled: true; all of them removed when false.
# Manifest-driven — never touches files it did not generate.
if [[ $DRY_RUN -eq 1 ]]; then
  echo "  (routing bindings: tf-routing-bind.sh runs on a real update, per this app's routing.yaml)"
else
  bash .tfcore/utils/tf-routing-bind.sh . | sed 's/^/  /'
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

# .claude/settings.json — REFRESHED BY DEFAULT to the canonical yolo-except-git-writes-writes
# block (allow all Bash; DENY every git/gh WRITE subcommand in every mode; NO settings
# `ask` rules — a settings ask prompts even in bypass mode, so rm/rmdir/sudo asks are
# issued by the block-git.sh PreToolUse hook and withheld in YOLO (_yolo-mode.md,
# 2026-08-21); read-only git is decided by the same hook) so every project stays in sync
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
    "ask": [],
    "deny": [
      "Bash(rm -rf /)", "Bash(rm -rf /*)", "Bash(rm -rf ~)", "Bash(rm -rf ~/*)",
      "Bash(git commit*)", "Bash(git push*)", "Bash(git add*)", "Bash(git rm*)",
      "Bash(git mv*)", "Bash(git reset*)", "Bash(git checkout*)", "Bash(git switch*)",
      "Bash(git restore*)", "Bash(git merge*)", "Bash(git rebase*)", "Bash(git cherry-pick*)",
      "Bash(git revert*)", "Bash(git clean*)", "Bash(git am*)", "Bash(git apply*)",
      "Bash(git init*)", "Bash(git clone*)", "Bash(git pull*)", "Bash(git fetch*)",
      "Bash(git filter-branch*)", "Bash(git filter-repo*)", "Bash(git gc*)", "Bash(git prune*)",
      "Bash(git update-ref*)", "Bash(git symbolic-ref*)", "Bash(git replace*)", "Bash(git update-index*)",
      "Bash(git commit-tree*)", "Bash(git write-tree*)", "Bash(git read-tree*)", "Bash(git fast-import*)",
      "Bash(git send-email*)", "Bash(git request-pull*)", "Bash(git svn*)",
      "Bash(gh pr create*)", "Bash(gh pr merge*)", "Bash(gh pr close*)", "Bash(gh pr edit*)",
      "Bash(gh pr comment*)", "Bash(gh pr review*)", "Bash(gh pr ready*)", "Bash(gh pr reopen*)",
      "Bash(gh pr lock*)", "Bash(gh pr unlock*)", "Bash(gh pr update-branch*)", "Bash(gh pr checkout*)",
      "Bash(gh issue create*)", "Bash(gh issue close*)", "Bash(gh issue edit*)", "Bash(gh issue comment*)",
      "Bash(gh issue delete*)", "Bash(gh issue reopen*)", "Bash(gh issue pin*)", "Bash(gh issue unpin*)",
      "Bash(gh issue lock*)", "Bash(gh issue unlock*)", "Bash(gh issue transfer*)", "Bash(gh issue develop*)",
      "Bash(gh repo create*)", "Bash(gh repo delete*)", "Bash(gh repo fork*)", "Bash(gh repo clone*)",
      "Bash(gh repo edit*)", "Bash(gh repo sync*)", "Bash(gh repo archive*)", "Bash(gh repo unarchive*)",
      "Bash(gh repo rename*)", "Bash(gh repo set-default*)", "Bash(gh repo deploy-key add*)", "Bash(gh repo deploy-key delete*)",
      "Bash(gh release create*)", "Bash(gh release delete*)", "Bash(gh release upload*)", "Bash(gh release edit*)",
      "Bash(gh workflow run*)", "Bash(gh workflow enable*)", "Bash(gh workflow disable*)", "Bash(gh run cancel*)",
      "Bash(gh run rerun*)", "Bash(gh run delete*)", "Bash(gh secret set*)", "Bash(gh secret delete*)",
      "Bash(gh variable set*)", "Bash(gh variable delete*)", "Bash(gh label create*)", "Bash(gh label delete*)",
      "Bash(gh label edit*)", "Bash(gh auth login*)", "Bash(gh auth logout*)", "Bash(gh auth refresh*)",
      "Bash(gh auth setup-git*)", "Bash(gh gist create*)", "Bash(gh gist delete*)", "Bash(gh gist edit*)",
      "Bash(gh ssh-key add*)", "Bash(gh gpg-key add*)", "Bash(gh cache delete*)"
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
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/session-pointer.sh\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/session-pointer.sh\""
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/metrics-session.sh\""
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
  echo "  .claude/settings.json — already current (yolo-except-git-writes)"
elif [[ $DRY_RUN -eq 1 ]]; then
  echo "  .claude/settings.json — WOULD refresh to yolo-except-git-writes (use --keep-permissions to opt out)"
else
  mkdir -p .claude
  if [[ -f .claude/settings.json ]]; then
    cp .claude/settings.json .claude/settings.json.bak
    echo "  .claude/settings.json — old version backed up to settings.json.bak"
  fi
  printf '%s\n' "$CANONICAL_SETTINGS" > .claude/settings.json
  echo "  .claude/settings.json — refreshed to yolo-except-git-writes"
fi

# Library agents at .claude/ root are NuGet-deployed and never touched
for f in trblazeui.md techierag.md; do
  if [[ -f ".claude/$f" ]]; then
    echo "  .claude/$f — preserved (NuGet-deployed)"
  fi
done

# --------------------------------------------------------------------------
# 3. .opencode/command/ root — top-level short-form commands only.
# The old .opencode/command/TechieFlow/ mirror is GONE: OpenCode loads agents
# and tasks from opencode.jsonc {file:./.tfcore/...} references, and the mirror
# only registered phantom slash commands. NuGet-deployed library personas are
# skipped — never overwrite them.
# --------------------------------------------------------------------------
[[ $DRY_RUN -eq 1 ]] || mkdir -p .opencode/command
for src in "$TEMPLATE"/.opencode/command/*.md; do
  [[ -f "$src" ]] || continue
  f="$(basename "$src")"
  case "$f" in trblazeui.md|techierag.md) continue ;; esac
  echo "  .opencode/command/$f"
  if [[ $DRY_RUN -eq 1 && ! -d .opencode/command ]]; then
    continue
  fi
  rsync $RSYNC_FLAGS "$src" ".opencode/command/$f"
done

# --------------------------------------------------------------------------
# 3c. OpenCode harness bridge — FRAMEWORK-OWNED, always refreshed (D-1 fix,
# DECISIONS.md 2026-08-20). Two pieces:
#   .opencode/plugin/*.js       guard bridge: runs the same .tfcore/hooks/
#                               guards Claude Code runs (git ban, status shape,
#                               Verified ledger) + telemetry with real cost
#   .opencode/opencode.jsonc    the framework's OpenCode config, a copy of the
#                               template's opencode.jsonc
# OpenCode merges .opencode/opencode.jsonc AFTER the root opencode.jsonc, so
# the framework file WINS on conflicting keys (verified against OpenCode
# 1.18.18 — DECISIONS.md 2026-08-19 §7). The root file stays preserved below
# for project-specific additions (extra agents, MCP, LSP). Both paths are
# inside .opencode/, which the managed .gitignore block already ignores.
# --------------------------------------------------------------------------
[[ $DRY_RUN -eq 1 ]] || mkdir -p .opencode/plugin
for src in "$TEMPLATE"/.opencode/plugin/*.js; do
  [[ -f "$src" ]] || continue
  f="$(basename "$src")"
  echo "  .opencode/plugin/$f — framework-owned, refreshed"
  rsync $RSYNC_FLAGS "$src" ".opencode/plugin/$f" || true
done
echo "  .opencode/opencode.jsonc — framework-owned, refreshed (wins over root opencode.jsonc on conflicting keys)"
# {file:...} refs resolve relative to the CONFIG FILE's directory, so the
# template's ./.tfcore/ paths must become ../.tfcore/ when the copy lives in
# .opencode/ (verified: a bad ref hard-fails the whole config load).
[[ $DRY_RUN -eq 1 ]] || sed 's|{file:\./\.tfcore/|{file:../.tfcore/|g' "$TEMPLATE/opencode.jsonc" > ".opencode/opencode.jsonc"

# Root opencode.jsonc preserved (project-specific agents/MCP/LSP; every
# framework key now also arrives via .opencode/opencode.jsonc, which wins).
# Warn when it still carries the pre-2026-08-20 bare agent-level
# "bash": "allow" — under OpenCode's last-match-wins permission evaluation
# that shape voided the root git/gh denies for the agent (DECISIONS.md
# 2026-08-20 §2). The refreshed .opencode/opencode.jsonc re-arms the denies.
if [[ -f opencode.jsonc ]]; then
  echo "  opencode.jsonc — preserved (per-project; framework config refreshed at .opencode/opencode.jsonc)"
  if tr -d ' \t\r\n' < opencode.jsonc | grep -q '"bash":"allow"'; then
    echo "  ⚠ root opencode.jsonc has a bare agent-level \"bash\": \"allow\" — that shape voided the"
    echo "    git/gh denies for the agent. The refreshed .opencode/opencode.jsonc re-arms them;"
    echo "    delete the stale agent block from the root file when convenient."
  fi
fi

# 4b. Codex adapter. Preserve project-owned config.toml; refresh the framework
# policy files and regenerate agents/skills from canonical .tfcore content.
echo "  .codex/ + .agents/skills/ — Codex adapter"
if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p .codex/agents .codex/rules .agents/skills
  [[ -f .codex/config.toml ]] || cp "$TEMPLATE/.codex/config.toml" .codex/config.toml
  cp "$TEMPLATE/.codex/hooks.json" .codex/hooks.json
  cp "$TEMPLATE/.codex/rules/techieflow.rules" .codex/rules/techieflow.rules
  python3 .tfcore/utils/tf-codex-bind.py "$TARGET" || echo "  ⚠ Codex bindings could not be generated (python3 required)"
  echo "  Codex hooks changed or installed — trust this repository and review /hooks"
else
  echo "  WOULD preserve/create .codex/config.toml; refresh hooks/rules; regenerate agents/skills"
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
# 5. NuGet persona shims — LEGACY RESCUE ONLY, never an overwrite.
#    Written when both libraries deployed their Claude persona to .claude/<lib>.md,
#    a path Claude Code never scans (TR-001/TR-RAG-001), so this mirrored it into
#    .claude/commands/ to make /trblazeui and /techierag resolve. Both libraries
#    took the suggested fix on 2026-07-04 and now deploy to .claude/commands/<lib>.md
#    DIRECTLY, so that premise — and the "the root file is authoritative" comment
#    this block used to carry — are both false today.
#
#    It used to `cp` unconditionally. In a repo still holding a pre-2026-07-04
#    .claude/<lib>.md, that copied the STALE legacy file over the FRESH one
#    `dotnet build` had just written — silently, every run. No repo currently has
#    a legacy file (surveyed 2026-08-24: 0 of 16 WSL repos, so this never fired),
#    but a restored old clone or an un-rebuilt machine would re-arm it, and the
#    Mac clones were not surveyable from here.
#
#    Now it only fills a GAP: shim when .claude/commands/<lib>.md is absent, which
#    is exactly the case the shim existed for. A present file is left alone — it
#    came from the current NuGet target and outranks anything at the legacy path.
# --------------------------------------------------------------------------
for lib in trblazeui techierag; do
  [[ -f ".claude/$lib.md" ]] || continue
  if [[ -f ".claude/commands/$lib.md" ]]; then
    if ! cmp -s ".claude/$lib.md" ".claude/commands/$lib.md"; then
      echo "  ⚠ .claude/$lib.md (legacy path) differs from .claude/commands/$lib.md (current"
      echo "    NuGet target). Keeping the commands/ copy — it is the one dotnet build writes."
      echo "    The legacy file is dead weight; delete it when convenient."
    fi
    continue
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  WOULD shim legacy .claude/$lib.md → .claude/commands/$lib.md (no current copy present)"
  else
    cp ".claude/$lib.md" ".claude/commands/$lib.md"
    echo "  shimmed legacy .claude/$lib.md → .claude/commands/$lib.md (no current copy present)"
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

# The mandatory framework instructions (build ladder, operating contract) ship
# in the FRAMEWORK-OWNED .opencode/opencode.jsonc, which this script refreshes
# every run and which WINS over the root file on conflicting keys (DECISIONS.md
# 2026-08-20 §5, runtime-verified 2026-08-19 §7f). Before that two-file split
# the root file was the only framework config, and these two checks audited it
# — which, after the split, fired on every correctly-maintained app (the root
# file legitimately holds project-only keys) and told the owner to hand-copy
# framework config into a file this script PRESERVES and never refreshes, where
# it would silently rot. Audit the file that must actually carry them instead:
# the deployed copy in a real run, the template in --dry-run (what would land).
if [[ $DRY_RUN -eq 1 ]]; then OC_FW="$TEMPLATE/opencode.jsonc"; else OC_FW=".opencode/opencode.jsonc"; fi
if [[ -f "$OC_FW" ]]; then
  for _oc_req in "build-invocation-ladder.md:the mandatory build-invocation ladder instruction (OpenCode Docker may choose direct dotnet/cmd.exe and report false blockers)" \
                 "opencode-operating-contract.md:the OpenCode operating contract instruction (OpenCode may stop after a green build instead of running smoke + verify + status gates)"; do
    _oc_file="${_oc_req%%:*}"; _oc_desc="${_oc_req#*:}"
    if ! grep -qF ".tfcore/templates/v4custom/$_oc_file" "$OC_FW"; then
      echo ""
      echo "  ⚠ $OC_FW is missing $_oc_desc."
      echo "    This is a FRAMEWORK defect, not a per-project one — the framework-owned"
      echo "    OpenCode config is generated from $TEMPLATE/opencode.jsonc."
      echo "    Report it; do NOT hand-edit the app's root opencode.jsonc to compensate."
    fi
  done
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
GI_LINES=(".tfcore/" ".claude/" ".opencode/" ".codex/" ".agents/skills/" "/CLAUDE.md" "/WORKFLOW.html" "/opencode.jsonc" "/.tf-scaffold-note.txt")
GI_PATS=('^/?\.tfcore/?$' '^/?\.claude/?$' '^/?\.opencode/?$' '^/?\.codex/?$' '^/?\.agents/skills/?$' '^/?CLAUDE\.md$' '^/?WORKFLOW\.html$' '^/?opencode\.jsonc$' '^/?\.tf-scaffold-note\.txt$')
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
# 8b. .gitignore — agent test-harness & log artifacts. The verifier SELF-
#     PROVISIONS npm/Playwright per project (verify-phase §1) and Serilog
#     writes logs/ by standing default — all machine-generated, all
#     regenerable, never the owner's to triage at commit time. Root-anchored
#     (/package.json) so a genuine nested frontend package is not swept up.
#     playwright.config.ts stays TRACKED (committed test suites depend on it).
#     CANONICAL LOCATION since 2026-08-10: every run artifact goes under
#     tests/.artifacts/ (pinned by playwright.config.ts outputDir). The bare
#     test-results/ and the test-results-*/ glob are LEGACY-ONLY entries — agents
#     used to write per-cluster siblings (test-results-cluster-a/ ...) that the
#     bare pattern never matched, so screenshot dumps piled up untracked at the
#     repo root. A compliant run now writes none of them.
#     Same reminder as 8: ignore rules don't UNtrack already-committed files —
#     run `git rm -r --cached <path>` once for any of these already tracked.
# --------------------------------------------------------------------------
GI2_LINES=("node_modules/" "/package.json" "/package-lock.json" "tests/.artifacts/" "test-results/" "test-results-*/" "/scripts-*/" "playwright-report/" ".verify/" "logs/" "/docs/.last-verify.json" ".DS_Store")
GI2_PATS=('^/?node_modules/?$' '^/?package\.json$' '^/?package-lock\.json$' '^/?tests/\.artifacts/?$' '^/?test-results/?$' '^/?test-results-\*/?$' '^/scripts-\*/?$' '^/?playwright-report/?$' '^/?\.verify/?$' '^/?logs/?$' '^/?docs/\.last-verify\.json$' '^\.DS_Store$')
GI2_MISSING=()
for i in "${!GI2_LINES[@]}"; do
  [[ -f .gitignore ]] && tr -d '\r' < .gitignore | grep -qE "${GI2_PATS[$i]}" && continue
  GI2_MISSING+=("${GI2_LINES[$i]}")
done
if [[ ${#GI2_MISSING[@]} -eq 0 ]]; then
  echo "  .gitignore — agent-artifact entries already present"
elif [[ $DRY_RUN -eq 1 ]]; then
  echo "  .gitignore — WOULD add agent-artifact entries: ${GI2_MISSING[*]}"
else
  { echo ""
    echo "# TechieFlow agent artifacts — machine-generated test harness & logs, never commit (managed by scaffold/update-framework.sh)"
    printf '%s\n' "${GI2_MISSING[@]}"
  } >> .gitignore
  echo "  .gitignore — added agent-artifact entries: ${GI2_MISSING[*]}"
fi

# 8c. Telemetry — docs/metrics/, the project classification, and the pre-commit
#     hook, refreshed on every update so a repo can never drift out of it. There
#     is deliberately no separate install command: telemetry rides this script.
#     The setup script never invokes git — it locates .git/hooks by reading the
#     filesystem, because installing a hook is a file copy, not a git operation,
#     so block-git.sh stays exactly as it is and no permission prompt is needed.
#     project_type is auto-detected ONCE and then preserved; correct it with
#         .tfcore/telemetry/install-metrics.sh . --type app|library|docs|framework
if [[ $DRY_RUN -eq 1 ]]; then
  bash "$TEMPLATE/.tfcore/telemetry/install-metrics.sh" . --dry-run || true
else
  bash "$TEMPLATE/.tfcore/telemetry/install-metrics.sh" . || true
fi

# 8d. .gitattributes — line endings, and the append-only merge strategy.
#     TWO problems live in this one file.
#
#     (a) LINE ENDINGS. This portfolio is worked on from macOS, WSL and native
#         Windows. With core.autocrlf=true (the Git-for-Windows default) and
#         nothing but `* text=auto`, git normalises the COMMITTED blob to LF but
#         still smudges the WORKING TREE to CRLF on checkout. GitHub Desktop
#         reports that as "This file uses 'LF' line endings, but Git is configured
#         to convert them to 'CRLF' the next time the file is checked out" — and
#         it is the same mechanism that CRLF-broke every *.sh in this framework on
#         2026-07-11. `eol=lf` pins the WORKING TREE to LF on every platform.
#         *.bat/*.cmd are pinned back to CRLF: the Windows command processor
#         requires it. docs/metrics/*.jsonl is named explicitly as well as covered
#         by the `*` rule — a log appended to by machine must never acquire mixed
#         endings, and that line has to carry merge=union anyway.
#
#     (b) MERGING. Two machines appending to the same append-only log conflict on
#         every sync, and resolving such a conflict by hand silently DROPS
#         records — the one failure mode an append-only log must not have.
#         `merge=union` is a built-in low-level driver: it keeps BOTH sides' added
#         lines and needs no per-machine config. Trade-off, documented in
#         SCHEMA.md: a union merge can duplicate a record written on both sides,
#         and line order stops being chronological. Both are harmless — every
#         consumer parses line-by-line and sorts on `ts`, and commit records
#         de-duplicate on sha. Losing a record is not harmless.
#
#     Append-only and idempotent like the .gitignore blocks above: an existing
#     equivalent line wins and user content is never rewritten. The ONE exception
#     is the un-pinned telemetry line written by the 2026-08-10 version of this
#     block, which is replaced — leaving both would mean two rules for one path.
GA_LINES=("* text=auto eol=lf" "*.bat text eol=crlf" "*.cmd text eol=crlf" "docs/metrics/*.jsonl text eol=lf merge=union")
GA_PATS=('^\*[[:space:]]+text=auto[[:space:]]+eol=lf$' '^\*\.bat[[:space:]]+text[[:space:]]+eol=crlf$' '^\*\.cmd[[:space:]]+text[[:space:]]+eol=crlf$' '^docs/metrics/\*\.jsonl[[:space:]]+text[[:space:]]+eol=lf[[:space:]]+merge=union$')
GA_LEGACY='^docs/metrics/\*\.jsonl[[:space:]]+merge=union[[:space:]]*$'
GA_MISSING=()
for i in "${!GA_LINES[@]}"; do
  [[ -f .gitattributes ]] && tr -d '\r' < .gitattributes | grep -qE "${GA_PATS[$i]}" && continue
  GA_MISSING+=("${GA_LINES[$i]}")
done
if [[ -f .gitattributes ]] && tr -d '\r' < .gitattributes | grep -qE "$GA_LEGACY"; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  .gitattributes — WOULD drop the legacy un-pinned telemetry line (superseded)"
  else
    awk '!/^docs\/metrics\/\*\.jsonl[[:space:]]+merge=union[[:space:]]*$/ &&
       !/^# TechieFlow telemetry . append-only logs; keep BOTH sides on merge/' .gitattributes > .gitattributes.tf-tmp \
      && mv .gitattributes.tf-tmp .gitattributes \
      && echo "  .gitattributes — dropped the legacy un-pinned telemetry line (superseded)"
  fi
fi
if [[ ${#GA_MISSING[@]} -eq 0 ]]; then
  echo "  .gitattributes — line-ending + merge rules already present"
elif [[ $DRY_RUN -eq 1 ]]; then
  echo "  .gitattributes — WOULD add: ${GA_MISSING[*]}"
else
  { echo ""
    echo "# TechieFlow — LF working tree on every platform (CRLF only where Windows demands it),"
    echo "# and append-only telemetry logs that keep BOTH sides on merge."
    echo "# Managed by scaffold/update-framework.sh."
    printf '%s\n' "${GA_MISSING[@]}"
  } >> .gitattributes
  echo "  .gitattributes — added: ${GA_MISSING[*]}"
  echo "    RENORMALIZE ONCE, yourself, in this repo so the committed blobs match:"
  echo "        git add --renormalize . && git commit -m \"Normalize line endings\""
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

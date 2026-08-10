#!/usr/bin/env bash
# scaffold-brownfield.sh — Drop the TechieFlow v4 framework into an EXISTING project.
#
# For a NEW project use scaffold-greenfield.sh instead — it creates empty
# src/ and tests/ folders that would be redundant here.
#
# Usage (run from wherever the TechieFlow repo lives — WSL, macOS, Linux):
#   /path/to/TechieFlow/scaffold-brownfield.sh /path/to/existing-app
#   /path/to/TechieFlow/scaffold-brownfield.sh    (defaults to $PWD)
#
# What it does:
#   - Adds .tfcore/, .claude/commands/, .opencode/command/TechieFlow/ if missing
#   - Adds .claude/settings.json (yolo-except-git) if missing
#   - Copies WORKFLOW.html and opencode.jsonc if missing
#   - Drops a note pointing to the brownfield day-1 /analyst prompt
#
# What it deliberately does NOT touch:
#   - src/, tests/, or any existing code/test folders
#   - existing files anywhere — uses rsync --ignore-existing
#   - existing docs/ contents
#
# Library agent files (TrBlazeUI / TechieRag) excluded — they land via NuGet
# auto-deploy on the project's next `dotnet build`.
#
# Idempotent: re-running won't overwrite existing files — with one exception:
# the harness agent mirrors (.claude/commands/TechieFlow/agents/ and
# .opencode/command/TechieFlow/agents/) are force-synced from .tfcore/agents/
# on every run, and NuGet persona shims are refreshed from .claude/<lib>.md.

set -euo pipefail

# The reference framework is wherever this script lives — no hardcoded path,
# so the repo works from WSL (/mnt/c/...), macOS (/Volumes/...), or Linux.
TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$PWD}"
TARGET="$(realpath "$TARGET")"

if [[ "$TARGET" == "$TEMPLATE" || "$TARGET" == "$TEMPLATE"/* ]]; then
  echo "Refusing to scaffold into the template itself." >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync not found. Install it -- Linux/WSL: sudo apt-get install rsync  |  macOS: brew install rsync (usually preinstalled)  |  native Windows: run this script from WSL or Git Bash" >&2
  exit 1
fi

if [[ ! -d "$TARGET" ]]; then
  echo "Target directory does not exist: $TARGET" >&2
  echo "Brownfield means an EXISTING project. For a new one use scaffold-greenfield.sh." >&2
  exit 1
fi

cd "$TARGET"

# Sanity check: warn (don't block) if no signs of a .NET project
HAS_CSPROJ=$(find . -maxdepth 4 \( -name "*.csproj" -o -name "*.sln" \) 2>/dev/null | head -1)
if [[ -z "$HAS_CSPROJ" ]]; then
  echo "⚠ Warning: no .csproj or .sln found within 4 levels of $TARGET" >&2
  echo "  This script is intended for existing .NET projects." >&2
  if [[ -t 0 ]]; then
    read -r -p "No .csproj/.sln found — continue anyway? [y/N] " REPLY
    if [[ ! "$REPLY" =~ ^[yY]$ ]]; then
      echo "Aborted." >&2
      exit 1
    fi
  else
    echo "  (stdin is not a TTY — continuing despite the warning.)" >&2
  fi
  echo ""
fi

# Sanity check: warn if already scaffolded — they probably want update, not scaffold
if [[ -d .tfcore ]]; then
  echo "ℹ This project already has .tfcore/ — it appears to be already scaffolded."
  echo "  scaffold-brownfield.sh uses --ignore-existing, so existing framework files"
  echo "  (tasks, templates, workflows, agents) will NOT be updated."
  echo ""
  echo "  If you want to refresh framework files from the reference repo while preserving"
  echo "  your docs/, src/, tests/, PROJECT-STATUS.md, CLAUDE.md — use this instead:"
  echo "    $TEMPLATE/update-framework.sh \"$TARGET\""
  echo ""
  echo "  Continuing with scaffold (will only fill in any missing files)..."
  echo ""
fi

echo "→ Adding TechieFlow v4 framework to existing project: $TARGET"

# Library-deployed agent filenames — keep these out of the command roots
# (.claude/commands/, .opencode/command/) so NuGet-deployed personas are
# never overwritten by the framework copy. The .tfcore/ copy and the
# step-3b force-sync deliberately do NOT use these: the template's TechieFlow
# subtrees no longer carry library personas, and NuGet never deploys there.
LIB_EXCLUDES=(--exclude='trblazeui.md' --exclude='techierag.md')

# 1. TechieFlow core
rsync -a --ignore-existing \
  "$TEMPLATE/.tfcore/" .tfcore/

# 2. Claude Code slash commands
mkdir -p .claude/commands
rsync -a --ignore-existing "${LIB_EXCLUDES[@]}" \
  "$TEMPLATE/.claude/commands/" .claude/commands/

# 3. OpenCode commands
mkdir -p .opencode/command/TechieFlow
rsync -a --ignore-existing "${LIB_EXCLUDES[@]}" \
  "$TEMPLATE/.opencode/command/TechieFlow/" .opencode/command/TechieFlow/

# 3b. FORCE-sync agent files from .tfcore/agents/ to both harness paths.
# .tfcore/agents/ is canonical (TechieFlow personas + commands). The harness
# folders MUST mirror it or slash commands like *day1-brownfield won't appear.
# This step overwrites the harness copies — do NOT edit them directly; edit
# .tfcore/agents/ and re-run the scaffold.
echo "  syncing agent files from .tfcore/agents/ → harness paths"
rsync -a \
  .tfcore/agents/ .claude/commands/TechieFlow/agents/
rsync -a \
  .tfcore/agents/ .opencode/command/TechieFlow/agents/

# 4. Reference files at root — only if missing
[[ -f WORKFLOW.html ]]  || cp "$TEMPLATE/WORKFLOW.html"  .
[[ -f opencode.jsonc ]] || cp "$TEMPLATE/opencode.jsonc" .

# 5. .claude/settings.json — yolo-except-git, only if missing
if [[ ! -f .claude/settings.json ]]; then
  cat > .claude/settings.json <<'JSON'
{
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
}
JSON
  echo "  created .claude/settings.json"
else
  echo "  .claude/settings.json already exists — preserved"
fi

# 6. NuGet persona shims — Claude Code only scans .claude/commands/ for slash
# commands, but NuGet auto-deploy drops library personas at .claude/<lib>.md.
# Mirror them into .claude/commands/ so /trblazeui and /techierag resolve.
# The NuGet-deployed file is authoritative — always overwrite the shim.
for lib in trblazeui techierag; do
  if [[ -f "$TARGET/.claude/$lib.md" ]]; then
    cp "$TARGET/.claude/$lib.md" "$TARGET/.claude/commands/$lib.md"
    echo "  shimmed .claude/$lib.md → .claude/commands/$lib.md"
  fi
done

# 7. Scaffold note — path-neutral; does not leak template location into the project
if [[ ! -f .tf-scaffold-note.txt ]]; then
  cat > .tf-scaffold-note.txt <<'NOTE'
Scaffolded by the TechieFlow v4 customized brownfield scaffold script.

This is a BROWNFIELD project — your existing src/, tests/, and docs/ contents
were NOT touched. Only the TechieFlow framework files were added.

Added (only missing files filled — re-runs are safe):
  .tfcore/                  ← TechieFlow v4 customized (agents, tasks, templates)
  .claude/commands/            ← Claude Code slash commands (TechieFlow agents)
  .claude/settings.json        ← yolo-except-git permissions
  .opencode/command/TechieFlow/      ← OpenCode slash commands
  WORKFLOW.html                ← the human workflow guide (open in a browser; §17 = macOS / Windows / Linux)
  opencode.jsonc               ← OpenCode config
  .gitignore                   ← framework entries appended (deployed copies stay uncommitted)

All TechieFlow templates the analyst will need live LOCALLY in this project under:
  .tfcore/templates/v4custom/

So the project is portable — copy this whole tree to another machine and the
analyst can author every doc without reaching back to the original template.

Library agents (TrBlazeUI, TechieRag) auto-deploy on `dotnet build` IF the
project already references the NuGet packages. To add them:
  dotnet add <YourProject>.csproj package TrBlazeUI
  dotnet add <YourProject>.csproj package TechieRag
  dotnet build

Next step (brownfield day-1):
  Start Claude Code in this folder and run:
    /analyst *day1-brownfield <AppName>
  (Replace <AppName> with PascalCase name, e.g. AppManager, TrTools.)

  That single command will produce all six day-1 deliverables in one pass:
    docs/<AppName>-Architecture.md
    docs/<AppName>-BRD.md
    docs/<AppName>-Coding-Standards.md
    .editorconfig
    PROJECT-STATUS.md
    CLAUDE.md

  Then review the docs and edit directly if needed.

You can delete this note once you've read it.
NOTE
fi

# 8. .gitignore — ensure the framework block. Everything this script deploys
#    is a COPY (source of truth: the TechieFlow reference repo, or the NuGet
#    package for library personas) and must never be committed in the app repo.
#    Append-only + idempotent: existing anchored/slash variants are respected;
#    user content is never rewritten.
GI_LINES=(".tfcore/" ".claude/" ".opencode/" "/CLAUDE.md" "/WORKFLOW.html" "/opencode.jsonc" "/.tf-scaffold-note.txt")
GI_PATS=('^/?\.tfcore/?$' '^/?\.claude/?$' '^/?\.opencode/?$' '^/?CLAUDE\.md$' '^/?WORKFLOW\.html$' '^/?opencode\.jsonc$' '^/?\.tf-scaffold-note\.txt$')
GI_MISSING=()
for i in "${!GI_LINES[@]}"; do
  # tr strips CR so CRLF .gitignore files (Windows-authored) still match the $-anchor
  [[ -f .gitignore ]] && tr -d '\r' < .gitignore | grep -qE "${GI_PATS[$i]}" && continue
  GI_MISSING+=("${GI_LINES[$i]}")
done
if [[ ${#GI_MISSING[@]} -gt 0 ]]; then
  { echo ""
    echo "# TechieFlow framework — deployed copies, never commit (managed by scaffold/update-framework.sh)"
    printf '%s\n' "${GI_MISSING[@]}"
  } >> .gitignore
  echo "  .gitignore — added framework entries: ${GI_MISSING[*]}"
else
  echo "  .gitignore — framework entries already present"
fi

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
GI2_LINES=("node_modules/" "/package.json" "/package-lock.json" "tests/.artifacts/" "test-results/" "test-results-*/" "playwright-report/" ".verify/" "logs/" "/docs/.last-verify.json" ".DS_Store")
GI2_PATS=('^/?node_modules/?$' '^/?package\.json$' '^/?package-lock\.json$' '^/?tests/\.artifacts/?$' '^/?test-results/?$' '^/?test-results-\*/?$' '^/?playwright-report/?$' '^/?\.verify/?$' '^/?logs/?$' '^/?docs/\.last-verify\.json$' '^\.DS_Store$')
GI2_MISSING=()
for i in "${!GI2_LINES[@]}"; do
  [[ -f .gitignore ]] && tr -d '\r' < .gitignore | grep -qE "${GI2_PATS[$i]}" && continue
  GI2_MISSING+=("${GI2_LINES[$i]}")
done
if [[ ${#GI2_MISSING[@]} -gt 0 ]]; then
  { echo ""
    echo "# TechieFlow agent artifacts — machine-generated test harness & logs, never commit (managed by scaffold/update-framework.sh)"
    printf '%s\n' "${GI2_MISSING[@]}"
  } >> .gitignore
  echo "  .gitignore — added agent-artifact entries: ${GI2_MISSING[*]}"
else
  echo "  .gitignore — agent-artifact entries already present"
fi

# 8c. Telemetry — docs/metrics/, the project classification, and the post-commit
#     hook. Set up HERE, as part of the scaffold, so there is no second command
#     for the owner to remember. The setup script never invokes git: it finds
#     .git/hooks by reading the filesystem, because installing a hook is a file
#     copy, not a git operation. block-git.sh is untouched.
#     docs/metrics/ is TRACKED on purpose — it is the project's own development
#     history, and the one thing the framework cannot reconstruct afterwards.
bash "$TEMPLATE/.tfcore/telemetry/install-metrics.sh" . || true

# 8d. .gitattributes — union-merge the telemetry streams. They are append-only
#     logs edited on more than one machine (the portfolio is split across a Mac
#     and WSL, and several repos are cloned on both). Two machines appending to
#     the same file conflict on every sync, and resolving such a conflict by hand
#     silently DROPS records — the one failure mode an append-only log must not
#     have. `merge=union` is a built-in low-level driver: it keeps BOTH sides'
#     added lines, needs no per-machine config, and is exactly right here.
#     Trade-off, documented in SCHEMA.md: a union merge can duplicate a record
#     that was written on both sides, and line order stops being chronological.
#     Both are harmless — every consumer parses line-by-line and sorts on `ts`,
#     and commit records de-duplicate on sha. Losing a record is not harmless.
GA_LINES=("docs/metrics/*.jsonl merge=union")
GA_PATS=('^docs/metrics/\*\.jsonl[[:space:]]+merge=union$')
GA_MISSING=()
for i in "${!GA_LINES[@]}"; do
  [[ -f .gitattributes ]] && tr -d '\r' < .gitattributes | grep -qE "${GA_PATS[$i]}" && continue
  GA_MISSING+=("${GA_LINES[$i]}")
done
if [[ ${#GA_MISSING[@]} -eq 0 ]]; then
  echo "  .gitattributes — telemetry merge strategy already present"
else
  { echo ""
    echo "# TechieFlow telemetry — append-only logs; keep BOTH sides on merge (managed by scaffold/update-framework.sh)"
    printf '%s\n' "${GA_MISSING[@]}"
  } >> .gitattributes
  echo "  .gitattributes — added telemetry merge strategy: ${GA_MISSING[*]}"
fi

echo ""
echo "✔ Done. Existing source tree was NOT touched."
echo ""
echo "Next: cd \"$TARGET\""
echo "      open WORKFLOW.html in a browser"
echo "      start Claude Code, follow §7 brownfield day-1 /analyst prompt"

#!/usr/bin/env bash
# scaffold-brownfield.sh — Drop the TechieFlow v4 framework into an EXISTING project.
#
# For a NEW project use scaffold-greenfield.sh instead — it creates empty
# src/ and tests/ folders that would be redundant here.
#
# Usage:
#   /mnt/c/3AIGenCode/TechieFlow/scaffold-brownfield.sh /path/to/existing-app
#   /mnt/c/3AIGenCode/TechieFlow/scaffold-brownfield.sh    (defaults to $PWD)
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

TEMPLATE="/mnt/c/3AIGenCode/TechieFlow"
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
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(sudo *)"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf /*)",
      "Bash(rm -rf ~)",
      "Bash(rm -rf ~/*)"
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

echo ""
echo "✔ Done. Existing source tree was NOT touched."
echo ""
echo "Next: cd \"$TARGET\""
echo "      open WORKFLOW.html in a browser"
echo "      start Claude Code, follow §7 brownfield day-1 /analyst prompt"

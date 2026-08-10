#!/usr/bin/env bash
# scaffold-greenfield.sh — Bootstrap a NEW (greenfield) project with this TechieFlow v4 setup.
#
# For an EXISTING project (brownfield) use scaffold-brownfield.sh instead —
# it skips creating src/ and tests/ folders that would clash with your code.
#
# Usage (run from wherever the TechieFlow repo lives — WSL, macOS, Linux):
#   /path/to/TechieFlow/scaffold-greenfield.sh /path/to/new/project
#   /path/to/TechieFlow/scaffold-greenfield.sh    (defaults to $PWD)
#
# Copies the TechieFlow v4 setup (your customizations, not the npm-latest v6) plus a
# pre-built .claude/settings.json that auto-allows everything except deletes/sudo
# (ask) and git/gh (DENIED — git is manual; a PreToolUse hook backs the deny).
# Creates empty src/, tests/playwright/, tests/unit/ ready for use.
#
# Library-deployed agent files are explicitly excluded — they land via
# `dotnet build` once the project adds the NuGet packages:
#   .claude/trblazeui.md, .opencode/command/trblazeui.md, .trblazeui/
#   .claude/techierag.md, .opencode/command/techierag.md, .techierag/
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
# BSD realpath (macOS) has no -m for not-yet-existing paths — create first,
# then resolve; the template-refusal check below cleans up an empty mistake.
mkdir -p "$TARGET"
TARGET="$(realpath "$TARGET")"

if [[ "$TARGET" == "$TEMPLATE" || "$TARGET" == "$TEMPLATE"/* ]]; then
  echo "Refusing to scaffold into the template itself. Pass a different path." >&2
  rmdir "$TARGET" 2>/dev/null || true
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync not found. Install it -- Linux/WSL: sudo apt-get install rsync  |  macOS: brew install rsync (usually preinstalled)  |  native Windows: run this script from WSL or Git Bash" >&2
  exit 1
fi

cd "$TARGET"

# Sanity check: warn if already scaffolded — they probably want update, not scaffold
if [[ -d .tfcore ]]; then
  echo "ℹ This project already has .tfcore/ — it appears to be already scaffolded."
  echo "  scaffold-greenfield.sh uses --ignore-existing, so existing framework files"
  echo "  (tasks, templates, workflows, agents) will NOT be updated."
  echo ""
  echo "  If you want to refresh framework files from the reference repo while preserving"
  echo "  your docs/, src/, tests/, PROJECT-STATUS.md, CLAUDE.md — use this instead:"
  echo "    $TEMPLATE/update-framework.sh \"$TARGET\""
  echo ""
  echo "  Continuing with scaffold (will only fill in any missing files)..."
  echo ""
fi

echo "→ Scaffolding TechieFlow v4 (customized) into: $TARGET"

# Library-deployed agent filenames — keep these out of the command roots
# (.claude/commands/, .opencode/command/) so NuGet-deployed personas are
# never overwritten by the framework copy. The .tfcore/ copy and the
# step-3b force-sync deliberately do NOT use these: the template's TechieFlow
# subtrees no longer carry library personas, and NuGet never deploys there.
LIB_EXCLUDES=(--exclude='trblazeui.md' --exclude='techierag.md')

# 1. TechieFlow core agents/tasks/templates
rsync -a --ignore-existing \
  "$TEMPLATE/.tfcore/" .tfcore/

# 2. Claude Code slash commands (TechieFlow agents only — library agents excluded)
mkdir -p .claude/commands
rsync -a --ignore-existing "${LIB_EXCLUDES[@]}" \
  "$TEMPLATE/.claude/commands/" .claude/commands/

# 3. OpenCode commands (TechieFlow agents only)
mkdir -p .opencode/command/TechieFlow
rsync -a --ignore-existing "${LIB_EXCLUDES[@]}" \
  "$TEMPLATE/.opencode/command/TechieFlow/" .opencode/command/TechieFlow/

# 3b. FORCE-sync agent files from .tfcore/agents/ to both harness paths.
# .tfcore/agents/ is canonical (TechieFlow personas + commands). The harness
# folders MUST mirror it or slash commands like *day1-greenfield won't appear.
# This step overwrites the harness copies — do NOT edit them directly; edit
# .tfcore/agents/ and re-run the scaffold.
echo "  syncing agent files from .tfcore/agents/ → harness paths"
rsync -a \
  .tfcore/agents/ .claude/commands/TechieFlow/agents/
rsync -a \
  .tfcore/agents/ .opencode/command/TechieFlow/agents/

# 4. Reference files at project root — only if missing
[[ -f WORKFLOW.html ]]   || cp "$TEMPLATE/WORKFLOW.html"   .
[[ -f opencode.jsonc ]]  || cp "$TEMPLATE/opencode.jsonc"  .

# 5. .claude/settings.json — yolo-except-git. ONLY write if missing,
#    so per-project tweaks survive scaffold re-runs.
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

# 6. Project skeleton folders (mkdir -p is idempotent)
mkdir -p tests/playwright tests/unit src

# 7. Scaffold note — path-neutral; does not leak template location into the project
if [[ ! -f .tf-scaffold-note.txt ]]; then
  cat > .tf-scaffold-note.txt <<'NOTE'
Scaffolded by the TechieFlow v4 customized greenfield scaffold script.

This is a NEW (greenfield) project — empty src/ and tests/ folders are ready.

Folders/files created (only missing files filled — re-runs are safe):
  .tfcore/                  ← TechieFlow v4 customized (agents, tasks, templates)
  .claude/commands/            ← Claude Code slash commands (TechieFlow agents)
  .claude/settings.json        ← yolo-except-git permissions
  .opencode/command/TechieFlow/      ← OpenCode slash commands
  WORKFLOW.html                ← the human workflow guide (open in a browser; §17 = macOS / Windows / Linux)
  opencode.jsonc               ← OpenCode config
  .gitignore                   ← framework entries appended (deployed copies stay uncommitted)
  tests/playwright/  tests/unit/  src/

All TechieFlow templates the analyst will need live LOCALLY in this project under:
  .tfcore/templates/v4custom/

So the project is portable — copy this whole tree to another machine and the
analyst can author every doc without reaching back to the original template.

Next: create the .NET solution, add your library NuGet packages, build once:
  dotnet new sln -n MyApp
  dotnet new blazor -n MyApp.Web -o src/MyApp.Web && dotnet sln add src/MyApp.Web
  dotnet add src/MyApp.Web package TrBlazeUI    # if UI involved
  dotnet add src/MyApp.Web package TechieRag    # if AI/RAG involved
  dotnet build       ← deploys .claude/<lib>.md, .opencode/command/<lib>.md,
                                .<lib>/<Lib>-AI-Reference.md

Then start Claude Code in this folder and run:
  /analyst *day1-greenfield <AppName>
(Replace <AppName> with PascalCase name, e.g. AppManager, AstroLyfe.)

That single command will produce all six day-1 deliverables in one pass.

You can delete this note once you've read it.
NOTE
fi

# 8. NuGet persona shims — Claude Code only scans .claude/commands/ for slash
# commands, but NuGet auto-deploy drops library personas at .claude/<lib>.md.
# Mirror them into .claude/commands/ so /trblazeui and /techierag resolve.
# The NuGet-deployed file is authoritative — always overwrite the shim.
for lib in trblazeui techierag; do
  if [[ -f "$TARGET/.claude/$lib.md" ]]; then
    cp "$TARGET/.claude/$lib.md" "$TARGET/.claude/commands/$lib.md"
    echo "  shimmed .claude/$lib.md → .claude/commands/$lib.md"
  fi
done

# 9. .gitignore — ensure the framework block. Everything this script deploys
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

# 9b. .gitignore — agent test-harness & log artifacts. The verifier SELF-
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
echo "✔ Done."
echo ""
echo "Next: cd \"$TARGET\""
echo "      dotnet new sln + blazor + add TrBlazeUI/TechieRag NuGets + dotnet build"
echo "      open WORKFLOW.html, start Claude Code, follow §7 greenfield day-1 prompt"

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
#   - Adds .tfcore/, .claude/commands/ if missing
#   - Adds .claude/settings.json (yolo-except-git-writes-writes; hook-gated deletes) if missing
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
# the harness agent mirror (.claude/commands/TechieFlow/agents/) is force-synced
# from .tfcore/agents/ on every run, and NuGet persona shims are refreshed from
# .claude/<lib>.md. (The .opencode/command/TechieFlow/ mirror was removed —
# OpenCode loads agents/tasks from opencode.jsonc {file:...} refs instead.)

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

# 3. (Removed) OpenCode command mirror (.opencode/command/TechieFlow/) is NOT
# deployed. OpenCode loads agents/tasks from opencode.jsonc via {file:./.tfcore/...}
# references; the mirror only registered phantom slash commands. Claude Code is
# the only harness that reads .claude/commands/TechieFlow/ (synced in 3b).

# 3b. FORCE-sync agent files from .tfcore/agents/ to the Claude harness path.
# .tfcore/agents/ is canonical (TechieFlow personas + commands). The harness
# folder MUST mirror it or slash commands like *day1-brownfield won't appear.
# This step overwrites the harness copy — do NOT edit it directly; edit
# .tfcore/agents/ and re-run the scaffold.
echo "  syncing agent files from .tfcore/agents/ → .claude/commands/TechieFlow/agents/"
rsync -a \
  .tfcore/agents/ .claude/commands/TechieFlow/agents/

# 4. Reference files at root — only if missing
[[ -f WORKFLOW.html ]]  || cp "$TEMPLATE/WORKFLOW.html"  .
[[ -f opencode.jsonc ]] || cp "$TEMPLATE/opencode.jsonc" .

# 4b. OpenCode harness bridge — framework-owned, ALWAYS refreshed (like 3b):
# the guard-bridge plugin (runs the same .tfcore/hooks/ guards Claude Code
# runs) and the framework's config copy. OpenCode merges .opencode/opencode.jsonc
# AFTER the root file, so the framework copy wins on conflicting keys
# (DECISIONS.md 2026-08-20).
mkdir -p .opencode/plugin
for src in "$TEMPLATE"/.opencode/plugin/*.js; do
  [[ -f "$src" ]] || continue
  cp "$src" .opencode/plugin/
done
# {file:...} refs resolve relative to the config file's directory — rewrite
# ./.tfcore/ to ../.tfcore/ for the copy living inside .opencode/.
sed 's|{file:\./\.tfcore/|{file:../.tfcore/|g' "$TEMPLATE/opencode.jsonc" > .opencode/opencode.jsonc

# 4c. Codex adapter — repository skills, custom agents, hooks and exec policy.
# Config is a project baseline and is preserved when already present; the
# framework-owned hooks/rules and generated agents/skills are refreshed.
mkdir -p .codex/agents .codex/rules .agents/skills
[[ -f .codex/config.toml ]] || cp "$TEMPLATE/.codex/config.toml" .codex/config.toml
cp "$TEMPLATE/.codex/hooks.json" .codex/hooks.json
cp "$TEMPLATE/.codex/rules/techieflow.rules" .codex/rules/techieflow.rules
python3 .tfcore/utils/tf-codex-bind.py "$TARGET" || echo "  ⚠ Codex bindings could not be generated (python3 required)"
echo "  Codex adapter installed — trust this repository and review /hooks before relying on guards"

# 5. .claude/settings.json — yolo-except-git-writes, only if missing
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
  .claude/settings.json        ← yolo-except-git-writes permissions
  WORKFLOW.html                ← the human workflow guide (open in a browser; §17 = macOS / Windows / Linux)
  opencode.jsonc               ← OpenCode config (loads agents/tasks from .tfcore/ via {file:...} refs)
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
GI_LINES=(".tfcore/" ".claude/" ".opencode/" ".codex/" ".agents/skills/" "/CLAUDE.md" "/WORKFLOW.html" "/opencode.jsonc" "/.tf-scaffold-note.txt")
GI_PATS=('^/?\.tfcore/?$' '^/?\.claude/?$' '^/?\.opencode/?$' '^/?\.codex/?$' '^/?\.agents/skills/?$' '^/?CLAUDE\.md$' '^/?WORKFLOW\.html$' '^/?opencode\.jsonc$' '^/?\.tf-scaffold-note\.txt$')
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
GI2_LINES=("node_modules/" "/package.json" "/package-lock.json" "tests/.artifacts/" "test-results/" "test-results-*/" "/scripts-*/" "playwright-report/" ".verify/" "logs/" "/docs/.last-verify.json" ".DS_Store")
GI2_PATS=('^/?node_modules/?$' '^/?package\.json$' '^/?package-lock\.json$' '^/?tests/\.artifacts/?$' '^/?test-results/?$' '^/?test-results-\*/?$' '^/scripts-\*/?$' '^/?playwright-report/?$' '^/?\.verify/?$' '^/?logs/?$' '^/?docs/\.last-verify\.json$' '^\.DS_Store$')
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

# 8c. Telemetry — docs/metrics/, the project classification, and the pre-commit
#     hook. Set up HERE, as part of the scaffold, so there is no second command
#     for the owner to remember. The setup script never invokes git: it finds
#     .git/hooks by reading the filesystem, because installing a hook is a file
#     copy, not a git operation. block-git.sh is untouched.
#     docs/metrics/ is TRACKED on purpose — it is the project's own development
#     history, and the one thing the framework cannot reconstruct afterwards.
bash "$TEMPLATE/.tfcore/telemetry/install-metrics.sh" . || true

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
  awk '!/^docs\/metrics\/\*\.jsonl[[:space:]]+merge=union[[:space:]]*$/ &&
       !/^# TechieFlow telemetry . append-only logs; keep BOTH sides on merge/' .gitattributes > .gitattributes.tf-tmp \
    && mv .gitattributes.tf-tmp .gitattributes \
    && echo "  .gitattributes — dropped the legacy un-pinned telemetry line (superseded)"
fi
if [[ ${#GA_MISSING[@]} -eq 0 ]]; then
  echo "  .gitattributes — line-ending + merge rules already present"
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

echo ""
echo "✔ Done. Existing source tree was NOT touched."
echo ""
echo "Next: cd \"$TARGET\""
echo "      open WORKFLOW.html in a browser"
echo "      start Claude Code, follow §7 brownfield day-1 /analyst prompt"

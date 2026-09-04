#!/usr/bin/env node
// scripts/install.mjs — the TechieFlow installer that ships in the npm package.
//
//   npx @techierathore/techieflow@latest install                add the framework to an existing project
//   npx @techierathore/techieflow@latest install --greenfield   the same, for a new project (adds src/ and tests/)
//   npx @techierathore/techieflow@latest update                 refresh the framework in a project that has it
//   npx @techierathore/techieflow@latest uninstall --force      remove the framework files again
//
// Flags:
//   --target=<folder>    the project folder (default: the current folder)
//   --dry-run            print what would happen, write nothing
//   --force              install: skip the "no .csproj found" question; uninstall: really delete
//   --no-gitignore       do not edit .gitignore or .gitattributes
//   --greenfield         install only: also create src/, tests/playwright/, tests/unit/
//   --keep-permissions   update only: leave .claude/settings.json as it is
//   --help
//
// It does what scaffold-brownfield.sh, scaffold-greenfield.sh and update-framework.sh do,
// step for step, so a project set up by either route ends up with the same files.
// scripts/test-install.mjs proves that by running both routes and comparing the results.
//
// Needs: node, bash and python3. The framework's own helper scripts (telemetry setup,
// build-output ignore audit, Codex bindings) are run exactly as the shell scripts run them.

import { spawnSync } from "node:child_process";
import {
  appendFileSync, chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync,
  readdirSync, renameSync, rmSync, rmdirSync, statSync, writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";

// ---------------------------------------------------------------- arguments

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const command = args.find((a) => !a.startsWith("-")) ?? "install";
const flags = args.filter((a) => a.startsWith("-"));
const knownFlags = ["--dry-run", "--force", "--no-gitignore", "--greenfield", "--keep-permissions", "--help", "-h"];
const targetArg = flags.find((f) => f.startsWith("--target="));
const target = resolve(targetArg ? targetArg.slice("--target=".length) : process.cwd());
const dryRun = flags.includes("--dry-run");
const force = flags.includes("--force");
const greenfield = flags.includes("--greenfield");
const keepPermissions = flags.includes("--keep-permissions");
const manageGitignore = !flags.includes("--no-gitignore");
const wantHelp = flags.includes("--help") || flags.includes("-h");

function usage() {
  console.log(`TechieFlow installer

  npx @techierathore/techieflow@latest install                add the framework to an existing project
  npx @techierathore/techieflow@latest install --greenfield   the same, for a new project (adds src/ and tests/)
  npx @techierathore/techieflow@latest update                 refresh the framework in a project that has it
  npx @techierathore/techieflow@latest uninstall --force      remove the framework files again

Flags:
  --target=<folder>    the project folder (default: the current folder)
  --dry-run            print what would happen, write nothing
  --force              install: skip the "no .csproj found" question; uninstall: really delete
  --no-gitignore       do not edit .gitignore or .gitattributes
  --greenfield         install only: also create src/, tests/playwright/, tests/unit/
  --keep-permissions   update only: leave .claude/settings.json as it is

install never overwrites a file that already exists. update overwrites framework files and
leaves your own files alone: docs/, src/, tests/, PROJECT-STATUS.md, CLAUDE.md, .editorconfig,
.tfcore/core-config.yaml, .tfcore/routing.yaml, .claude/settings.local.json and the NuGet-deployed
library personas. Needs node, bash and python3.`);
}

// ---------------------------------------------------------------- small helpers

const say = (line) => console.log(line);
const warn = (line) => console.error(line);
const would = dryRun ? "WOULD " : "";
const rel = (path) => relative(target, path).split(sep).join("/");
const read = (path) => readFileSync(path, "utf8");
const libraryPersonas = new Set(["trblazeui.md", "techierag.md"]);

// Files a working clone may hold that a clean checkout does not. The shell scripts run
// from a clone and copy them by accident; the installer never copies them.
function isLocalOnly(sourcePath) {
  const name = basename(sourcePath);
  const r = relative(sourceRoot, sourcePath).split(sep).join("/");
  return name === ".DS_Store" || name === "Thumbs.db" || name === "desktop.ini" || name.endsWith(".bak")
    || name.startsWith("tmpclaude-") || r === ".tfcore/.session" || r.startsWith(".tfcore/.session/");
}

function sameFile(a, b) {
  try {
    const sa = statSync(a);
    const sb = statSync(b);
    if (sa.size !== sb.size || (sa.mode & 0o777) !== (sb.mode & 0o777)) return false;
    return readFileSync(a).equals(readFileSync(b));
  } catch {
    return false;
  }
}

// Copy one file. Prints one line per change. Returns true when the file was (or would be) written.
function copyFile(source, destination, { onlyIfMissing = false, quiet = false } = {}) {
  const exists = existsSync(destination);
  if (onlyIfMissing && exists) return false;
  if (exists && sameFile(source, destination)) return false;
  if (!quiet) say(`  ${would}${exists ? "update" : "create"} ${rel(destination)}`);
  if (!dryRun) {
    mkdirSync(dirname(destination), { recursive: true });
    copyFileSync(source, destination);
    chmodSync(destination, statSync(source).mode & 0o777);
  }
  return true;
}

function writeText(destination, text, { onlyIfMissing = false } = {}) {
  const exists = existsSync(destination);
  if (onlyIfMissing && exists) return false;
  if (exists && read(destination) === text) return false;
  say(`  ${would}${exists ? "update" : "create"} ${rel(destination)}`);
  if (!dryRun) {
    mkdirSync(dirname(destination), { recursive: true });
    writeFileSync(destination, text);
  }
  return true;
}

// Copy a whole folder, like rsync -a. onlyIfMissing = rsync --ignore-existing.
// deleteExtra = rsync --delete (the destination ends up with exactly the source's files).
function copyTree(source, destination, { onlyIfMissing = false, deleteExtra = false, excludeNames = new Set() } = {}) {
  const excluded = (path) => excludeNames.has(basename(path)) || isLocalOnly(path);
  const walk = (from, to) => {
    for (const entry of readdirSync(from, { withFileTypes: true })) {
      const s = join(from, entry.name);
      const d = join(to, entry.name);
      if (excluded(s)) continue;
      if (entry.isDirectory()) {
        if (!dryRun) mkdirSync(d, { recursive: true });
        walk(s, d);
      } else if (entry.isFile()) copyFile(s, d, { onlyIfMissing });
    }
  };
  if (!dryRun) mkdirSync(destination, { recursive: true });
  if (existsSync(source)) walk(source, destination);
  if (deleteExtra && existsSync(destination)) {
    const prune = (from, to) => {
      for (const entry of readdirSync(to, { withFileTypes: true })) {
        const s = join(from, entry.name);
        const d = join(to, entry.name);
        if (!existsSync(s) || excluded(s)) {
          say(`  ${would}delete ${rel(d)}${entry.isDirectory() ? "/" : ""}`);
          if (!dryRun) rmSync(d, { recursive: true, force: true });
        } else if (entry.isDirectory()) prune(s, d);
      }
    };
    prune(source, destination);
  }
}

function removeEmptyFolders(paths) {
  for (const p of paths) {
    const full = join(target, p);
    try {
      if (existsSync(full) && statSync(full).isDirectory() && readdirSync(full).length === 0) rmdirSync(full);
    } catch { /* leave it */ }
  }
}

// Run one of the framework's own helper scripts, printing its output like the shell scripts do.
function runBash(script, scriptArgs, { allowFailure = true } = {}) {
  const result = spawnSync("bash", [script, ...scriptArgs], { cwd: target, stdio: "inherit", env: process.env });
  if (result.error) throw new Error(`bash could not be started: ${result.error.message}`);
  if (result.status !== 0 && !allowFailure) throw new Error(`${basename(script)} exited with ${result.status}`);
  return result.status;
}

let pythonCommand = null;
function findPython() {
  for (const candidate of ["python3", "python"]) {
    const result = spawnSync(candidate, ["--version"], { encoding: "utf8" });
    if (!result.error && result.status === 0 && /Python 3/.test(`${result.stdout}${result.stderr}`)) return candidate;
  }
  return null;
}

function runPython(scriptArgs, { capture = false } = {}) {
  return spawnSync(pythonCommand, scriptArgs, {
    cwd: target,
    encoding: "utf8",
    stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit",
    env: process.env,
  });
}

function checkTools() {
  const bash = spawnSync("bash", ["-c", "true"]);
  if (bash.error || bash.status !== 0) {
    throw new Error("bash was not found. The framework's hooks and helper scripts run under bash.\n"
      + "  macOS and Linux have it. On Windows, run this command inside WSL or Git Bash.");
  }
  pythonCommand = findPython();
  if (!pythonCommand) {
    throw new Error("python3 was not found. It powers the HTML renderer, the telemetry writer, the Codex bindings and every guard hook.\n"
      + "  Install it and run this command again:\n"
      + "    macOS:          brew install python3\n"
      + "    Ubuntu / WSL:   sudo apt-get install -y python3\n"
      + "    Windows:        https://www.python.org/downloads/ (tick \"Add to PATH\")\n"
      + "  Without it the project would look installed while its guard hooks stay silent.");
  }
}

function ensureSafeTarget() {
  if (target === sourceRoot || target.startsWith(`${sourceRoot}${sep}`)) throw new Error("Refusing to install into the framework itself. Pass --target=<your project folder>.");
  if (target === resolve("/") || target === resolve(homedir())) throw new Error("Refusing to install into the filesystem root or your home folder.");
  if (existsSync(target) && lstatSync(target).isSymbolicLink()) throw new Error(`Refusing a target that is a symbolic link: ${target}`);
}

// ---------------------------------------------------------------- managed blocks in .gitignore and .gitattributes

// Same lines, same patterns and same header text as the shell scripts. Append-only: an
// entry already present in any anchored or slash variant is respected, nothing is rewritten.
const frameworkIgnore = {
  lines: [".tfcore/", ".claude/", ".opencode/", ".codex/", ".agents/skills/", "/CLAUDE.md", "/WORKFLOW.html", "/opencode.jsonc", "/.tf-scaffold-note.txt"],
  patterns: [/^\/?\.tfcore\/?$/, /^\/?\.claude\/?$/, /^\/?\.opencode\/?$/, /^\/?\.codex\/?$/, /^\/?\.agents\/skills\/?$/, /^\/?CLAUDE\.md$/, /^\/?WORKFLOW\.html$/, /^\/?opencode\.jsonc$/, /^\/?\.tf-scaffold-note\.txt$/],
  header: ["# TechieFlow framework — deployed copies, never commit (managed by scaffold/update-framework.sh)"],
  label: "framework entries",
};
const artifactIgnore = {
  lines: ["node_modules/", "/package.json", "/package-lock.json", "tests/.artifacts/", "test-results/", "test-results-*/", "/scripts-*/", "playwright-report/", ".verify/", "logs/", "/docs/.last-verify.json", ".DS_Store"],
  patterns: [/^\/?node_modules\/?$/, /^\/?package\.json$/, /^\/?package-lock\.json$/, /^\/?tests\/\.artifacts\/?$/, /^\/?test-results\/?$/, /^\/?test-results-\*\/?$/, /^\/scripts-\*\/?$/, /^\/?playwright-report\/?$/, /^\/?\.verify\/?$/, /^\/?logs\/?$/, /^\/?docs\/\.last-verify\.json$/, /^\.DS_Store$/],
  header: ["# TechieFlow agent artifacts — machine-generated test harness & logs, never commit (managed by scaffold/update-framework.sh)"],
  label: "agent-artifact entries",
};
const attributes = {
  lines: ["* text=auto eol=lf", "*.bat text eol=crlf", "*.cmd text eol=crlf", "docs/metrics/*.jsonl text eol=lf merge=union"],
  patterns: [/^\*[ \t]+text=auto[ \t]+eol=lf$/, /^\*\.bat[ \t]+text[ \t]+eol=crlf$/, /^\*\.cmd[ \t]+text[ \t]+eol=crlf$/, /^docs\/metrics\/\*\.jsonl[ \t]+text[ \t]+eol=lf[ \t]+merge=union$/],
  header: [
    "# TechieFlow — LF working tree on every platform (CRLF only where Windows demands it),",
    "# and append-only telemetry logs that keep BOTH sides on merge.",
    "# Managed by scaffold/update-framework.sh.",
  ],
  label: "line-ending + merge rules",
};
const legacyAttributeLine = /^docs\/metrics\/\*\.jsonl[ \t]+merge=union[ \t]*$/;

function fileLines(path) {
  return existsSync(path) ? read(path).replace(/\r/g, "").split("\n") : [];
}

function ensureBlock(fileName, block) {
  const path = join(target, fileName);
  const present = fileLines(path);
  const missing = block.lines.filter((_, i) => !present.some((line) => block.patterns[i].test(line)));
  if (!missing.length) { say(`  ${fileName} — ${block.label} already present`); return false; }
  if (dryRun) { say(`  ${fileName} — WOULD add ${block.label}: ${missing.join(" ")}`); return true; }
  appendFileSync(path, `\n${block.header.join("\n")}\n${missing.join("\n")}\n`);
  say(`  ${fileName} — added ${block.label}: ${missing.join(" ")}`);
  return true;
}

function ensureGitattributes() {
  const path = join(target, ".gitattributes");
  if (existsSync(path) && fileLines(path).some((line) => legacyAttributeLine.test(line))) {
    if (dryRun) say("  .gitattributes — WOULD drop the legacy un-pinned telemetry line (superseded)");
    else {
      const kept = read(path).replace(/\n$/, "").split("\n")
        .filter((line) => !legacyAttributeLine.test(line) && !/^# TechieFlow telemetry .* append-only logs; keep BOTH sides on merge/.test(line));
      writeFileSync(path, `${kept.join("\n")}\n`);
      say("  .gitattributes — dropped the legacy un-pinned telemetry line (superseded)");
    }
  }
  if (ensureBlock(".gitattributes", attributes) && !dryRun) {
    say("    RENORMALIZE ONCE, yourself, in this repo so the committed blobs match:");
    say('        git add --renormalize . && git commit -m "Normalize line endings"');
  }
}

// ---------------------------------------------------------------- text the shell scripts write

const canonicalSettings = String.raw`{
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
          },
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-artifacts.sh\""
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
          },
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/sweep-artifacts.sh\""
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
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.tfcore/hooks/guard-status-html.sh\""
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
}`;

const brownfieldNote = `Scaffolded by the TechieFlow v4 customized brownfield scaffold script.

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

Library agents (TrBlazeUI, TechieRag) auto-deploy on \`dotnet build\` IF the
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
`;

const greenfieldNote = `Scaffolded by the TechieFlow v4 customized greenfield scaffold script.

This is a NEW (greenfield) project — empty src/ and tests/ folders are ready.

Folders/files created (only missing files filled — re-runs are safe):
  .tfcore/                  ← TechieFlow v4 customized (agents, tasks, templates)
  .claude/commands/            ← Claude Code slash commands (TechieFlow agents)
  .claude/settings.json        ← yolo-except-git-writes permissions
  WORKFLOW.html                ← the human workflow guide (open in a browser; §17 = macOS / Windows / Linux)
  opencode.jsonc               ← OpenCode config (loads agents/tasks from .tfcore/ via {file:...} refs)
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

Then start your harness in this folder and run day-1:
  Claude Code:  /analyst *day1-greenfield <AppName>
                (full form: /TechieFlow:agents:analyst *day1-greenfield <AppName>)
  OpenCode:     /flow-analyst *day1-greenfield <AppName>
(Replace <AppName> with PascalCase name, e.g. AppManager, AstroLyfe.)

That single command will produce all six day-1 deliverables in one pass.

You can delete this note once you've read it.
`;

// ---------------------------------------------------------------- steps shared by install and update

// The OpenCode config copy inside .opencode/ has its {file:} paths pointed one folder up.
const openCodeConfigCopy = () => read(join(sourceRoot, "opencode.jsonc")).replaceAll("{file:./.tfcore/", "{file:../.tfcore/");

function shippedFiles(folder, extension) {
  const full = join(sourceRoot, folder);
  if (!existsSync(full)) return [];
  return readdirSync(full).filter((f) => f.endsWith(extension) && statSync(join(full, f)).isFile()).sort();
}

function deployOpenCodeBridge() {
  if (!dryRun) mkdirSync(join(target, ".opencode", "plugin"), { recursive: true });
  for (const plugin of shippedFiles(".opencode/plugin", ".js")) copyFile(join(sourceRoot, ".opencode", "plugin", plugin), join(target, ".opencode", "plugin", plugin));
  writeText(join(target, ".opencode", "opencode.jsonc"), openCodeConfigCopy());
}

function deployCodexAdapter() {
  say("  .codex/ + .agents/skills/ — Codex adapter");
  if (dryRun) { say("  WOULD preserve/create .codex/config.toml; refresh hooks/rules; regenerate agents/skills"); return; }
  for (const folder of [".codex/agents", ".codex/rules", ".agents/skills"]) mkdirSync(join(target, folder), { recursive: true });
  copyFile(join(sourceRoot, ".codex", "config.toml"), join(target, ".codex", "config.toml"), { onlyIfMissing: true });
  copyFile(join(sourceRoot, ".codex", "hooks.json"), join(target, ".codex", "hooks.json"));
  copyFile(join(sourceRoot, ".codex", "rules", "techieflow.rules"), join(target, ".codex", "rules", "techieflow.rules"));
  const result = runPython([join(target, ".tfcore", "utils", "tf-codex-bind.py"), target]);
  if (result.status !== 0) say("  ⚠ Codex bindings could not be generated (python3 required)");
}

function deployHousekeeping() {
  if (manageGitignore) {
    ensureBlock(".gitignore", frameworkIgnore);
    ensureBlock(".gitignore", artifactIgnore);
  } else say("  .gitignore — not edited (--no-gitignore)");
  if (dryRun && !existsSync(target)) {
    say("  gitignore audit — WOULD run once the folder exists (build-output rules for the detected stack)");
    say("  telemetry — WOULD create docs/metrics/ and seed runs/gates/sessions/commits/misses.jsonl");
  } else {
    // Build-output rules for the stack the project is written in, and whether that output is
    // already tracked. Reads .git/index directly; never runs git.
    runBash(join(sourceRoot, ".tfcore", "utils", "tf-gitignore-audit.sh"), [".", manageGitignore && !dryRun ? "--fix" : "--dry-run"]);
    // Telemetry: docs/metrics/, the project classification and the pre-commit hook. Never runs git.
    runBash(join(sourceRoot, ".tfcore", "telemetry", "install-metrics.sh"), dryRun ? [".", "--dry-run"] : ["."]);
  }
  if (manageGitignore) ensureGitattributes();
  else say("  .gitattributes — not edited (--no-gitignore)");
}

function shimLegacyPersonas({ gapOnly }) {
  for (const lib of ["trblazeui", "techierag"]) {
    const legacy = join(target, ".claude", `${lib}.md`);
    const current = join(target, ".claude", "commands", `${lib}.md`);
    if (!existsSync(legacy)) continue;
    if (gapOnly && existsSync(current)) {
      if (!readFileSync(legacy).equals(readFileSync(current))) {
        say(`  ⚠ .claude/${lib}.md (legacy path) differs from .claude/commands/${lib}.md (current`);
        say("    NuGet target). Keeping the commands/ copy — it is the one dotnet build writes.");
        say("    The legacy file is dead weight; delete it when convenient.");
      }
      continue;
    }
    if (dryRun) { say(`  WOULD shim .claude/${lib}.md → .claude/commands/${lib}.md`); continue; }
    mkdirSync(dirname(current), { recursive: true });
    copyFileSync(legacy, current);
    chmodSync(current, statSync(legacy).mode & 0o777);
    say(`  shimmed ${gapOnly ? "legacy " : ""}.claude/${lib}.md → .claude/commands/${lib}.md${gapOnly ? " (no current copy present)" : ""}`);
  }
}

// ---------------------------------------------------------------- install (scaffold-brownfield.sh / scaffold-greenfield.sh)

function hasDotnetProject(directory, depth = 4) {
  let entries;
  try { entries = readdirSync(directory, { withFileTypes: true }); } catch { return false; }
  for (const entry of entries) {
    if (entry.isFile() && (entry.name.endsWith(".csproj") || entry.name.endsWith(".sln"))) return true;
    if (entry.isDirectory() && depth > 1 && hasDotnetProject(join(directory, entry.name), depth - 1)) return true;
  }
  return false;
}

async function install() {
  ensureSafeTarget();
  if (greenfield) {
    if (!existsSync(target)) { say(`  ${would}create ${target}/`); if (!dryRun) mkdirSync(target, { recursive: true }); }
  } else if (!existsSync(target)) {
    throw new Error(`Target directory does not exist: ${target}\nBrownfield means an EXISTING project. For a new one add --greenfield.`);
  }
  if (existsSync(target) && !statSync(target).isDirectory()) throw new Error(`Target is not a directory: ${target}`);

  if (!greenfield && !hasDotnetProject(target)) {
    warn(`⚠ Warning: no .csproj or .sln found within 4 levels of ${target}`);
    warn("  This command is intended for existing .NET projects.");
    if (process.stdin.isTTY && !force) {
      const rl = createInterface({ input: process.stdin, output: process.stdout });
      const answer = (await rl.question("No .csproj/.sln found — continue anyway? [y/N] ")).trim();
      rl.close();
      if (!/^[yY]$/.test(answer)) throw new Error("Aborted.");
    } else warn("  (continuing despite the warning.)");
    say("");
  }

  if (existsSync(join(target, ".tfcore"))) {
    say("ℹ This project already has .tfcore/ — it appears to be already installed.");
    say("  install never updates existing framework files (tasks, templates, agents).");
    say("  To refresh them while keeping your docs/, src/, tests/, PROJECT-STATUS.md, CLAUDE.md, run:");
    say("    npx @techierathore/techieflow@latest update");
    say("");
    say("  Continuing with install (will only fill in any missing files)...");
    say("");
  }

  say(`→ ${dryRun ? "DRY RUN — " : ""}${greenfield ? "Scaffolding TechieFlow into" : "Adding TechieFlow framework to existing project"}: ${target}`);

  // 1. framework core, never overwriting
  copyTree(join(sourceRoot, ".tfcore"), join(target, ".tfcore"), { onlyIfMissing: true });
  // 2. Claude Code slash commands (library personas excluded: NuGet deploys those)
  copyTree(join(sourceRoot, ".claude", "commands"), join(target, ".claude", "commands"), { onlyIfMissing: true, excludeNames: libraryPersonas });
  // 3b. force-sync the personas into the Claude mirror from the project's own .tfcore/agents/
  say("  syncing agent files from .tfcore/agents/ → .claude/commands/TechieFlow/agents/");
  copyTree(dryRun ? join(sourceRoot, ".tfcore", "agents") : join(target, ".tfcore", "agents"), join(target, ".claude", "commands", "TechieFlow", "agents"));
  // 4. reference files at the root, only if missing
  copyFile(join(sourceRoot, "WORKFLOW.html"), join(target, "WORKFLOW.html"), { onlyIfMissing: true });
  copyFile(join(sourceRoot, "opencode.jsonc"), join(target, "opencode.jsonc"), { onlyIfMissing: true });
  // 4b. OpenCode bridge, always refreshed
  deployOpenCodeBridge();
  // 4c. Codex adapter
  deployCodexAdapter();
  if (!dryRun) say("  Codex adapter installed — trust this repository and review /hooks before relying on guards");
  // 5. Claude Code permissions, only if missing
  if (writeText(join(target, ".claude", "settings.json"), `${canonicalSettings}\n`, { onlyIfMissing: true })) { if (!dryRun) say("  created .claude/settings.json"); }
  else say("  .claude/settings.json already exists — preserved");
  // 6. greenfield skeleton
  if (greenfield) {
    for (const folder of ["tests/playwright", "tests/unit", "src"]) {
      if (!existsSync(join(target, folder))) { say(`  ${would}create ${folder}/`); if (!dryRun) mkdirSync(join(target, folder), { recursive: true }); }
    }
  }
  // 7. scaffold note, only if missing
  writeText(join(target, ".tf-scaffold-note.txt"), greenfield ? greenfieldNote : brownfieldNote, { onlyIfMissing: true });
  // 8. NuGet persona shims: the deployed file is authoritative, always refresh the shim
  shimLegacyPersonas({ gapOnly: false });
  // 9. .gitignore, build-output audit, telemetry, .gitattributes
  deployHousekeeping();

  say("");
  if (dryRun) { say("✔ Dry run complete — no files changed."); return; }
  say(greenfield ? "✔ Done." : "✔ Done. Existing source tree was NOT touched.");
  say("");
  say(`Next: cd "${target}"`);
  if (greenfield) say("      dotnet new sln + blazor + add TrBlazeUI/TechieRag NuGets + dotnet build");
  say("      open WORKFLOW.html in a browser");
  say(`      start Claude Code or OpenCode and run the ${greenfield ? "greenfield" : "brownfield"} day-1 command from .tf-scaffold-note.txt`);
}

// ---------------------------------------------------------------- update (update-framework.sh)

const frameworkSubdirs = ["agents", "tasks", "telemetry", "templates", "checklists", "data", "utils", "hooks", "workflows", "agent-teams"];
const frameworkTopFiles = ["enhanced-ide-development-workflow.md", "user-guide.md", "working-in-the-brownfield.md", "install-manifest.yaml", "TOKEN-GUIDE.md"];
const legacyConfigPattern = /\.bmad-core|bmad-(master|orchestrator|analyst|architect|verifier)|BMad:/;

function migrateLegacyLayout() {
  if (existsSync(join(target, ".tfcore")) || !existsSync(join(target, ".bmad-core"))) return true;
  if (dryRun) {
    say(`→ DRY RUN — ${target} uses the legacy .bmad-core/ layout.`);
    say("  A real run would MIGRATE it first:");
    say("    • mv .bmad-core/ → .tfcore/   (keeps your core-config.yaml + docs)");
    say("    • rm -rf .claude/commands/BMad/  .opencode/command/BMad/   (old mirrors)");
    say("    • patch .tfcore/core-config.yaml (slashPrefix: TechieFlow, .tfcore paths)");
    say("    • back up & replace a legacy opencode.jsonc");
    say("    • delete the disposable legacy scaffold note");
    say("    • remove trimmed stock dirs (workflows/, agent-teams/) if present");
    say("    • flag (not edit) any stale framework refs in YOUR CLAUDE.md / PROJECT-STATUS.md / docs");
    say("  …then apply the usual framework refresh. Re-run without --dry-run to do it.");
    say("");
    return false;
  }
  say(`→ Migrating legacy .bmad-core/ layout to .tfcore/ in: ${target}`);
  renameSync(join(target, ".bmad-core"), join(target, ".tfcore"));
  say("  .bmad-core/ → .tfcore/   (per-project core-config.yaml + any docs preserved)");
  const config = join(target, ".tfcore", "core-config.yaml");
  if (existsSync(config)) {
    writeFileSync(config, read(config).replace(/\.bmad-core/g, ".tfcore").replace(/^slashPrefix:[ \t]*BMad/m, "slashPrefix: TechieFlow"));
    say("  patched .tfcore/core-config.yaml (slashPrefix: TechieFlow, .tfcore paths)");
  }
  rmSync(join(target, ".claude", "commands", "BMad"), { recursive: true, force: true });
  rmSync(join(target, ".opencode", "command", "BMad"), { recursive: true, force: true });
  say("  removed legacy .claude/commands/BMad/ and .opencode/command/BMad/");
  rmSync(join(target, ".tfcore", "data", "bmad-kb.md"), { force: true });
  rmSync(join(target, ".tfcore", "utils", "bmad-doc-template.md"), { force: true });
  if (existsSync(join(target, ".bmad-scaffold-note.txt"))) {
    rmSync(join(target, ".bmad-scaffold-note.txt"));
    say("  removed disposable legacy .bmad-scaffold-note.txt");
  }
  const rootConfig = join(target, "opencode.jsonc");
  if (existsSync(rootConfig) && legacyConfigPattern.test(read(rootConfig))) {
    copyFileSync(rootConfig, `${rootConfig}.bak`);
    copyFileSync(join(sourceRoot, "opencode.jsonc"), rootConfig);
    say("  opencode.jsonc — legacy version backed up to opencode.jsonc.bak, replaced with current template");
  }
  say("");
  return true;
}

function refreshRootOpenCodeConfig() {
  const rootConfig = join(target, "opencode.jsonc");
  if (!existsSync(rootConfig)) return;
  const audit = runPython([join(sourceRoot, ".tfcore", "utils", "tf-opencode-audit.py"), join(sourceRoot, "opencode.jsonc"), "opencode.jsonc"], { capture: true });
  const output = audit.status === 0 ? audit.stdout : "";
  const [verdict = "", ...rest] = output.split("\n");
  let replaced = false;
  if (verdict === "current") say("  opencode.jsonc — already current (matches template)");
  else if (verdict === "refresh") {
    if (dryRun) say("  opencode.jsonc — WOULD refresh from template (no project-only content; old file → .bak)");
    else {
      copyFileSync(rootConfig, `${rootConfig}.bak`);
      copyFileSync(join(sourceRoot, "opencode.jsonc"), rootConfig);
      say("  opencode.jsonc — refreshed from template (no project-only content; old file → opencode.jsonc.bak)");
      replaced = true;
    }
  } else if (verdict.startsWith("project|")) {
    say(`  opencode.jsonc — preserved (project-only keys: ${verdict.slice("project|".length)})`);
    say("    Framework keys still arrive via .opencode/opencode.jsonc, which wins on conflicts.");
    say("    Fold those keys into a fresh copy of the package's opencode.jsonc when convenient.");
  } else say(`  opencode.jsonc — preserved (could not audit: ${verdict.replace(/^unknown\|/, "")})`);

  const deadRefs = rest.filter((l) => l.startsWith("DIAG|dead-ref|")).map((l) => l.split("|")[2]);
  const bareBash = rest.filter((l) => l.startsWith("DIAG|bare-bash-allow|")).map((l) => l.split("|")[2]);
  if (deadRefs.length && replaced) {
    say(`  ✔ opencode.jsonc — ${deadRefs.length} dead {file:} ref(s) RESOLVED by the refresh`);
    say("    (they were in the old file, kept as opencode.jsonc.bak; OpenCode's whole");
    say("     config load was failing on them until now)");
  } else {
    for (const ref of deadRefs.slice(0, 5)) {
      say(`  ⚠ opencode.jsonc references a file that does not exist: ${ref}`);
      say("    A dead {file:} ref hard-fails OpenCode's ENTIRE config load.");
    }
  }
  if (!replaced) {
    for (const where of bareBash) {
      say(`  ⚠ opencode.jsonc has a bare "bash": "allow" at ${where} — that shape voids the`);
      say("    git/gh denies (agent rules are appended AFTER the root ruleset).");
    }
  }
}

function reportStaleReferences() {
  const rootConfig = join(target, "opencode.jsonc");
  if (existsSync(rootConfig) && /agents\/(dev|pm|po|qa|sm|ux-expert)\.md/.test(read(rootConfig))) {
    say("");
    say("  ⚠ opencode.jsonc references trimmed stock agents (dev/pm/po/qa/sm/ux-expert),");
    say("    whose files were just removed from .tfcore/agents/. Copy the package's");
    say("    opencode.jsonc or delete those agent entries.");
  }
  const frameworkConfig = dryRun ? join(sourceRoot, "opencode.jsonc") : join(target, ".opencode", "opencode.jsonc");
  if (existsSync(frameworkConfig)) {
    const text = read(frameworkConfig);
    for (const [file, description] of [
      ["build-invocation-ladder.md", "the mandatory build-invocation ladder instruction (OpenCode Docker may choose direct dotnet/cmd.exe and report false blockers)"],
      ["opencode-operating-contract.md", "the OpenCode operating contract instruction (OpenCode may stop after a green build instead of running smoke + verify + status gates)"],
    ]) {
      if (!text.includes(`.tfcore/templates/v4custom/${file}`)) {
        say("");
        say(`  ⚠ ${rel(frameworkConfig)} is missing ${description}.`);
        say("    This is a FRAMEWORK defect, not a per-project one. Report it; do NOT hand-edit");
        say("    the app's root opencode.jsonc to compensate.");
      }
    }
  }
  const stale = /\.bmad-core|\/BMad:|BMad:agents:|bmad-master|bmad-orchestrator|bmad-analyst|bmad-architect|bmad-verifier/;
  const candidates = new Set(["CLAUDE.md", "PROJECT-STATUS.md", ".gitignore"]);
  const docs = join(target, "docs");
  if (existsSync(docs)) for (const f of readdirSync(docs)) if (/\.(md|html)$/.test(f) && statSync(join(docs, f)).isFile()) candidates.add(`docs/${f}`);
  for (const f of readdirSync(target)) if (f.endsWith(".html") && statSync(join(target, f)).isFile()) candidates.add(f);
  const hits = [...candidates].sort().filter((f) => existsSync(join(target, f)) && statSync(join(target, f)).isFile() && stale.test(read(join(target, f))));
  if (hits.length) {
    say("");
    say("  ⚠ These files YOU own still reference the old framework layout (NOT auto-edited):");
    for (const hit of hits) say(`      ${hit}`);
    say("    Update the pointers (.bmad-core→.tfcore, /BMad:→/TechieFlow:,");
    say("    bmad-master/bmad-orchestrator→flow-master) or regenerate them");
    say("    (re-run day-1 / *refresh-status / *render-workflow-docs).");
  }
}

function update() {
  ensureSafeTarget();
  if (!existsSync(target)) throw new Error(`Target directory does not exist: ${target}`);
  if (!migrateLegacyLayout()) return;
  if (!existsSync(join(target, ".tfcore"))) {
    throw new Error(`${target} does not look installed (no .tfcore/ or legacy .bmad-core/ found).\nRun \`npx @techierathore/techieflow@latest install\` first.`);
  }

  if (dryRun) say(`→ DRY RUN — showing what would change in: ${target}\n`);
  else {
    say(`→ Updating TechieFlow framework in: ${target}`);
    say("  (your docs/, src/, tests/, PROJECT-STATUS.md, CLAUDE.md are NOT touched)\n");
  }

  // 1. .tfcore/ framework folders: overwrite and delete extras; core-config.yaml and routing.yaml are per-project
  for (const dir of frameworkSubdirs) {
    const source = join(sourceRoot, ".tfcore", dir);
    const destination = join(target, ".tfcore", dir);
    if (existsSync(source)) {
      say(`  .tfcore/${dir}/`);
      copyTree(source, destination, { deleteExtra: true });
    } else if (existsSync(destination)) {
      if (dir === "workflows" || dir === "agent-teams") {
        say(`  ${would}remove${dryRun ? "" : "d"} stale stock dir .tfcore/${dir}/ (no longer ships)`);
        if (!dryRun) rmSync(destination, { recursive: true, force: true });
      } else say(`  NOTE: .tfcore/${dir}/ no longer ships with the framework — safe to delete manually.`);
    }
  }
  for (const file of frameworkTopFiles) {
    if (existsSync(join(sourceRoot, ".tfcore", file))) copyFile(join(sourceRoot, ".tfcore", file), join(target, ".tfcore", file));
  }
  if (existsSync(join(target, ".tfcore", "core-config.yaml"))) say("  .tfcore/core-config.yaml — preserved (per-project)");
  if (existsSync(join(target, ".tfcore", "routing.yaml"))) say("  .tfcore/routing.yaml — preserved (per-project routing declaration)");
  else if (existsSync(join(sourceRoot, ".tfcore", "routing.yaml"))) {
    copyFile(join(sourceRoot, ".tfcore", "routing.yaml"), join(target, ".tfcore", "routing.yaml"));
    say("  .tfcore/routing.yaml — deployed (enabled: false; routing is opt-in per app)");
  }
  if (dryRun) say("  (routing bindings: tf-routing-bind.sh runs on a real update, per this app's routing.yaml)");
  else runBash(join(target, ".tfcore", "utils", "tf-routing-bind.sh"), ["."]);

  // 2. Claude Code mirror: overwrite and delete extras; personas re-synced from the package
  if (!dryRun) mkdirSync(join(target, ".claude", "commands", "TechieFlow"), { recursive: true });
  say("  .claude/commands/TechieFlow/");
  copyTree(join(sourceRoot, ".claude", "commands", "TechieFlow"), join(target, ".claude", "commands", "TechieFlow"), { deleteExtra: true });
  copyTree(join(sourceRoot, ".tfcore", "agents"), join(target, ".claude", "commands", "TechieFlow", "agents"));
  for (const file of shippedFiles(".claude/commands", ".md")) {
    if (libraryPersonas.has(file)) continue;
    say(`  .claude/commands/${file}`);
    copyFile(join(sourceRoot, ".claude", "commands", file), join(target, ".claude", "commands", file));
  }
  // .claude/settings.json: refreshed to the canonical block unless --keep-permissions
  const settingsPath = join(target, ".claude", "settings.json");
  if (keepPermissions) {
    if (existsSync(settingsPath)) say("  .claude/settings.json — preserved (--keep-permissions)");
  } else if (existsSync(settingsPath) && read(settingsPath).replace(/\n+$/, "") === canonicalSettings) {
    say("  .claude/settings.json — already current (yolo-except-git-writes)");
  } else if (dryRun) {
    say("  .claude/settings.json — WOULD refresh to yolo-except-git-writes (use --keep-permissions to opt out)");
  } else {
    mkdirSync(dirname(settingsPath), { recursive: true });
    if (existsSync(settingsPath)) {
      copyFileSync(settingsPath, `${settingsPath}.bak`);
      say("  .claude/settings.json — old version backed up to settings.json.bak");
    }
    writeFileSync(settingsPath, `${canonicalSettings}\n`);
    say("  .claude/settings.json — refreshed to yolo-except-git-writes");
  }
  for (const file of libraryPersonas) if (existsSync(join(target, ".claude", file))) say(`  .claude/${file} — preserved (NuGet-deployed)`);

  // 3. OpenCode short-form commands, bridge plugin, framework config copy, root config audit
  if (!dryRun) mkdirSync(join(target, ".opencode", "command"), { recursive: true });
  for (const file of shippedFiles(".opencode/command", ".md")) {
    if (libraryPersonas.has(file)) continue;
    say(`  .opencode/command/${file}`);
    if (dryRun && !existsSync(join(target, ".opencode", "command"))) continue;
    copyFile(join(sourceRoot, ".opencode", "command", file), join(target, ".opencode", "command", file));
  }
  for (const plugin of shippedFiles(".opencode/plugin", ".js")) say(`  .opencode/plugin/${plugin} — framework-owned, refreshed`);
  say("  .opencode/opencode.jsonc — framework-owned, refreshed (wins over root opencode.jsonc on conflicting keys)");
  deployOpenCodeBridge();
  refreshRootOpenCodeConfig();

  // 4b. Codex adapter
  deployCodexAdapter();
  if (!dryRun) say("  Codex hooks changed or installed — trust this repository and review /hooks");
  for (const file of libraryPersonas) if (existsSync(join(target, ".opencode", "command", file))) say(`  .opencode/command/${file} — preserved (NuGet-deployed)`);

  // 4. WORKFLOW.html, always refreshed
  if (existsSync(join(sourceRoot, "WORKFLOW.html"))) {
    copyFile(join(sourceRoot, "WORKFLOW.html"), join(target, "WORKFLOW.html"));
    say("  WORKFLOW.html");
  }
  // 5. NuGet persona shims: gap-fill only, never an overwrite
  shimLegacyPersonas({ gapOnly: true });
  // 6, 7. messages about stale references in files the owner owns
  reportStaleReferences();
  // 8. .gitignore, build-output audit, telemetry, .gitattributes
  deployHousekeeping();

  say("");
  if (dryRun) {
    say("✔ Dry run complete — no files changed.");
    say("  Re-run without --dry-run to apply.");
    return;
  }
  say("✔ Framework updated. Your docs/, src/, tests/, and per-project state files were NOT touched.");
  say("");
  say("Reminder:");
  say("  - In Claude Code, RESTART the session so the new task/agent definitions are loaded.");
  say("  - If a task file references a new template under .tfcore/templates/v4custom/,");
  say("    that template is now in place locally.");
}

// ---------------------------------------------------------------- uninstall

function uninstall() {
  ensureSafeTarget();
  if (!existsSync(join(target, ".tfcore"))) throw new Error(`${target} has no .tfcore/ folder; nothing to uninstall.`);
  const removals = [];
  const kept = [];
  const plan = (path, why = "") => { if (existsSync(join(target, path)) || lstatSync(join(target, path), { throwIfNoEntry: false })) removals.push([path, why]); };
  const keep = (path, why) => { if (existsSync(join(target, path))) kept.push([path, why]); };
  const sameAsShipped = (path, shipped) => existsSync(join(target, path)) && readFileSync(join(target, path)).equals(readFileSync(join(sourceRoot, shipped)));

  plan(".tfcore", "(holds .tfcore/core-config.yaml and .tfcore/routing.yaml, your per-project settings — copy them out first if you want them)");
  plan(".claude/commands/TechieFlow");
  for (const file of shippedFiles(".claude/commands", ".md")) if (!libraryPersonas.has(file)) plan(`.claude/commands/${file}`);
  if (existsSync(join(target, ".claude", "settings.json"))) {
    if (read(join(target, ".claude", "settings.json")).replace(/\n+$/, "") === canonicalSettings) plan(".claude/settings.json");
    else keep(".claude/settings.json", "you changed it");
  }
  if (existsSync(join(target, ".claude", "commands", "tf"))) plan(".claude/commands/tf", "(generated by routing)");
  const agentsDir = join(target, ".claude", "agents");
  if (existsSync(agentsDir)) for (const f of readdirSync(agentsDir)) if (f.endsWith(".md") && read(join(agentsDir, f)).includes("generated by tf-routing-bind.sh")) plan(`.claude/agents/${f}`, "(generated by routing)");
  for (const plugin of shippedFiles(".opencode/plugin", ".js")) plan(`.opencode/plugin/${plugin}`);
  plan(".opencode/opencode.jsonc");
  plan(".opencode/opencode.json", "(generated by routing)");
  for (const file of shippedFiles(".opencode/command", ".md")) if (!libraryPersonas.has(file)) plan(`.opencode/command/${file}`);
  plan(".codex/hooks.json");
  plan(".codex/rules/techieflow.rules");
  if (existsSync(join(target, ".codex", "config.toml"))) {
    if (sameAsShipped(".codex/config.toml", ".codex/config.toml")) plan(".codex/config.toml");
    else keep(".codex/config.toml", "you changed it");
  }
  const codexAgents = join(target, ".codex", "agents");
  if (existsSync(codexAgents)) for (const f of readdirSync(codexAgents)) {
    if (f.endsWith(".toml") && /description = "TechieFlow [a-z-]+ (specialist|role)\."/.test(read(join(codexAgents, f)))) plan(`.codex/agents/${f}`);
    else keep(`.codex/agents/${f}`, "not written by the framework");
  }
  const skills = join(target, ".agents", "skills");
  if (existsSync(skills)) for (const f of readdirSync(skills)) if (f.startsWith("techieflow-")) plan(`.agents/skills/${f}`);
  for (const lib of [".trblazeui", ".techierag"]) {
    if (!existsSync(join(target, lib))) continue;
    const rest = readdirSync(join(target, lib)).filter((f) => f !== ".codex-agent-package-owned" && f !== ".gitignore");
    plan(`${lib}/.codex-agent-package-owned`);
    if (rest.length === 0) plan(`${lib}/.gitignore`);
  }
  for (const [path, shipped] of [["WORKFLOW.html", "WORKFLOW.html"], ["opencode.jsonc", "opencode.jsonc"]]) {
    if (!existsSync(join(target, path))) continue;
    if (sameAsShipped(path, shipped)) plan(path);
    else keep(path, "you changed it");
  }
  plan(".tf-scaffold-note.txt");
  const hook = join(target, ".git", "hooks", "pre-commit");
  if (existsSync(hook) && read(hook).includes("TechieFlow telemetry")) plan(".git/hooks/pre-commit", "(telemetry hook)");
  keep("docs/metrics", "your project's telemetry history");
  for (const lib of libraryPersonas) {
    keep(`.claude/commands/${lib}`, "NuGet-deployed");
    keep(`.claude/${lib}`, "NuGet-deployed");
    keep(`.opencode/command/${lib}`, "NuGet-deployed");
  }
  keep(".claude/settings.local.json", "per-machine");
  keep(".gitattributes", "line-ending policy, kept");

  say(`→ ${force ? (dryRun ? "DRY RUN — " : "") : "PREVIEW — "}Uninstalling TechieFlow from: ${target}`);
  for (const [path, why] of removals) say(`  ${force && !dryRun ? "remove" : "would remove"} ${path}${why ? ` ${why}` : ""}`);
  for (const [path, why] of kept) say(`  keep   ${path} — ${why}`);
  if (manageGitignore) say(`  ${force && !dryRun ? "remove" : "would remove"} the framework block from .gitignore (the agent-artifact and build-output blocks stay: they describe your own build output)`);
  if (!force || dryRun) {
    say("");
    say("No files were removed. Run again with --force to remove them.");
    return;
  }
  for (const [path] of removals) rmSync(join(target, path), { recursive: true, force: true });
  if (manageGitignore) removeFrameworkIgnoreBlock();
  removeEmptyFolders([".claude/commands", ".claude/agents", ".claude", ".opencode/plugin", ".opencode/command", ".opencode", ".codex/agents", ".codex/rules", ".codex", ".agents/skills", ".agents", ".trblazeui", ".techierag"]);
  say("");
  say("✔ TechieFlow removed. Your docs/, src/, tests/ and docs/metrics/ were not touched.");
}

function removeFrameworkIgnoreBlock() {
  const path = join(target, ".gitignore");
  if (!existsSync(path)) return;
  const original = read(path);
  const lines = original.split("\n");
  const headerIndex = lines.findIndex((l) => l.replace(/\r$/, "") === frameworkIgnore.header[0]);
  if (headerIndex === -1) return;
  const managed = new Set(frameworkIgnore.lines);
  let end = headerIndex + 1;
  while (end < lines.length && managed.has(lines[end].replace(/\r$/, ""))) end++;
  let start = headerIndex;
  if (start > 0 && lines[start - 1].replace(/\r$/, "") === "") start--;
  lines.splice(start, end - start);
  writeFileSync(path, lines.join("\n"));
}

// ---------------------------------------------------------------- main

async function main() {
  const unknown = flags.filter((f) => !knownFlags.includes(f) && !f.startsWith("--target="));
  if (unknown.length) throw new Error(`Unknown flag: ${unknown.join(" ")}. Run with --help to see the flags.`);
  if (wantHelp) { usage(); return; }
  if (!["install", "update", "uninstall"].includes(command)) throw new Error(`Unknown command: ${command}. Use install, update or uninstall.`);
  if (greenfield && command !== "install") throw new Error("--greenfield only applies to install.");
  if (keepPermissions && command !== "update") throw new Error("--keep-permissions only applies to update.");
  checkTools();
  if (command === "install") await install();
  else if (command === "update") update();
  else uninstall();
}

main().catch((error) => {
  console.error(`${command} failed: ${error.message}`);
  process.exit(1);
});

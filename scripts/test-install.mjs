#!/usr/bin/env node
// scripts/test-install.mjs — proves that the npm installer produces exactly the same
// files as the three shell scripts.
//
// How it works, in plain words:
//   1. It packs this repository with `npm pack` and unpacks the result into a temporary
//      folder. That unpacked copy is a clean copy of the framework: it holds only the
//      files the package ships, none of the local-only files a working clone collects
//      (session files, node_modules, personal settings). The three shell scripts are
//      copied next to it so they can run from that clean copy.
//   2. For brownfield, greenfield, update and the old .bmad-core layout, it runs the shell
//      script on one folder and the installer on a second, identical folder, then
//      compares every file in both (path, content, executable bit). Any difference fails.
//   3. It checks the installed Claude mirror against .tfcore/ and every {file:} reference
//      in both installed opencode.jsonc files.
//   4. It checks uninstall, --dry-run, --no-gitignore, --keep-permissions, a second run,
//      and the one-shot `npm exec` form that `npx` uses.
//
// Every check runs even if an earlier one fails; the summary at the end lists them all.
// Exit code 0 means every check passed.
//
// Needs: node, npm, bash, python3 and rsync (rsync only because the shell scripts use it).
// Pass --keep to leave the temporary folder on disk for inspection.

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  appendFileSync, chmodSync, copyFileSync, cpSync, existsSync, mkdirSync, mkdtempSync,
  readFileSync, readdirSync, readlinkSync, rmSync, statSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const installer = join(root, "scripts", "install.mjs");
const keepSandbox = process.argv.includes("--keep");
const sandbox = mkdtempSync(join(tmpdir(), "techieflow-install-"));
const failures = [];
const notes = [];
let passed = 0;

// The Codex binder (.tfcore/utils/tf-codex-bind.py) needs Python 3.10 or newer. On an older
// Python both routes print a warning and skip the Codex agents and skills, so those files are
// only expected when the binder can run.
const pythonVersion = (() => {
  const result = spawnSync("python3", ["--version"], { encoding: "utf8" });
  const match = /Python (\d+)\.(\d+)/.exec(`${result.stdout ?? ""}${result.stderr ?? ""}`);
  return match ? `${match[1]}.${match[2]}` : "unknown";
})();
const codexBinderRuns = (() => {
  const [major, minor] = pythonVersion.split(".").map(Number);
  return major > 3 || (major === 3 && minor >= 10);
})();
if (!codexBinderRuns) notes.push(`python3 is ${pythonVersion}; the Codex binder needs 3.10 or newer, so neither route generates .codex/agents/ or .agents/skills/ on this machine (CI does).`);

// ---------------------------------------------------------------- helpers

function check(name, fn) {
  try {
    fn();
    passed++;
    console.log(`ok    ${name}`);
  } catch (error) {
    failures.push(`${name}\n      ${error.message.split("\n").join("\n      ")}`);
    console.log(`FAIL  ${name}\n      ${error.message.split("\n").join("\n      ")}`);
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? root,
    encoding: "utf8",
    input: "", // stdin is not a terminal, so the shell scripts never wait for an answer
    env: { ...process.env, TF_NO_INSTALL: "1", ...options.env },
    shell: options.shell ?? false,
  });
  if (result.error) throw result.error;
  if (result.status !== 0 && !options.allowFailure) {
    throw new Error(`${command} ${args.join(" ")} exited with ${result.status}\n${result.stdout}${result.stderr}`);
  }
  return result;
}

const node = (args, options) => run(process.execPath, args, options);

function npm(args, options = {}) {
  if (process.env.npm_execpath) return node([process.env.npm_execpath, ...args], options);
  const onWindows = process.platform === "win32";
  return run(onWindows ? "npm.cmd" : "npm", args, { ...options, shell: onWindows });
}

const shell = (script, args, options) => run("bash", [script, ...args], options);

// A snapshot maps every relative path in a folder to what it is: a directory, a link, or a
// file described by its executable bit and the SHA-256 of its content.
function snapshot(directory) {
  const entries = new Map();
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      const rel = relative(directory, path).split("\\").join("/");
      if (entry.isSymbolicLink()) entries.set(rel, `link:${readlinkSync(path)}`);
      else if (entry.isDirectory()) { entries.set(`${rel}/`, "dir"); walk(path); }
      else {
        const executable = (statSync(path).mode & 0o111) ? "x" : "-";
        entries.set(rel, `${executable}:${createHash("sha256").update(readFileSync(path)).digest("hex")}`);
      }
    }
  };
  walk(directory);
  return entries;
}

function diffSnapshots(left, right, leftLabel, rightLabel) {
  const lines = [];
  for (const [path, value] of left) {
    if (!right.has(path)) lines.push(`only in ${leftLabel}: ${path}`);
    else if (right.get(path) !== value) lines.push(`differs: ${path}`);
  }
  for (const path of right.keys()) if (!left.has(path)) lines.push(`only in ${rightLabel}: ${path}`);
  return lines;
}

function assertSameTree(shellDir, installerDir) {
  const lines = diffSnapshots(snapshot(shellDir), snapshot(installerDir), "shell result", "installer result");
  assert(lines.length === 0, `${lines.length} difference(s) between the shell script and the installer:\n${lines.join("\n")}`);
}

function assertUnchanged(before, directory, what) {
  const lines = diffSnapshots(before, snapshot(directory), "before", "after");
  assert(lines.length === 0, `${what} changed the folder:\n${lines.join("\n")}`);
}

const read = (path) => readFileSync(path, "utf8");
const lines = (path) => read(path).replace(/\r/g, "").split("\n");

// Every file under .claude/commands/TechieFlow/<sub>/ must equal .tfcore/<sub>/ byte for byte.
function mirrorDifferences(project) {
  const core = join(project, ".tfcore");
  const mirror = join(project, ".claude", "commands", "TechieFlow");
  const out = [];
  for (const sub of readdirSync(mirror)) {
    out.push(...diffSnapshots(snapshot(join(core, sub)), snapshot(join(mirror, sub)), `.tfcore/${sub}`, `mirror ${sub}`));
  }
  return out;
}

// Every {file:...} reference resolves relative to the folder holding the config file.
function unresolvedReferences(configPath) {
  const text = read(configPath);
  const refs = [...new Set([...text.matchAll(/\{file:([^}]*)\}/g)].map((m) => m[1]))];
  return refs.filter((ref) => !existsSync(join(dirname(configPath), ref)));
}

// ---------------------------------------------------------------- fixtures

// A small existing .NET project: enough for the brownfield checks, the build-output
// ignore audit and the pre-commit hook (a .git/hooks folder is enough; no git is run).
function seedProject(dir, { dotnet = true, gitDir = true, legacyPersona = true } = {}) {
  mkdirSync(dir, { recursive: true });
  if (dotnet) {
    mkdirSync(join(dir, "src", "App"), { recursive: true });
    writeFileSync(join(dir, "src", "App", "App.csproj"), '<Project Sdk="Microsoft.NET.Sdk.Web">\n</Project>\n');
    writeFileSync(join(dir, "src", "App", "Program.cs"), "// application code\n");
  }
  writeFileSync(join(dir, ".gitignore"), "# Project rules\n/dist/\n");
  mkdirSync(join(dir, "docs"), { recursive: true });
  writeFileSync(join(dir, "docs", "notes.md"), "project document\n");
  if (gitDir) mkdirSync(join(dir, ".git", "hooks"), { recursive: true });
  if (legacyPersona) {
    mkdirSync(join(dir, ".claude"), { recursive: true });
    writeFileSync(join(dir, ".claude", "trblazeui.md"), "# legacy NuGet persona\n");
  }
}

// Drift that update must repair, and owner content that update must leave alone.
function perturbInstalledProject(dir) {
  appendFileSync(join(dir, ".tfcore", "tasks", "build-phase.md"), "\nlocal edit that update must undo\n");
  writeFileSync(join(dir, ".tfcore", "tasks", "stale-old-task.md"), "no longer ships\n");
  mkdirSync(join(dir, ".tfcore", "workflows"), { recursive: true });
  writeFileSync(join(dir, ".tfcore", "workflows", "old.yaml"), "stock cruft\n");
  mkdirSync(join(dir, ".tfcore", "mine"), { recursive: true });
  writeFileSync(join(dir, ".tfcore", "mine", "keep.md"), "owner content\n");
  appendFileSync(join(dir, ".tfcore", "core-config.yaml"), "customTechnicalDocuments: docs/MyApp-Architecture.md\n");
  appendFileSync(join(dir, ".tfcore", "routing.yaml"), "# owner tuned\n");
  const settings = join(dir, ".claude", "settings.json");
  writeFileSync(settings, read(settings).replace("{\n", '{\n  "ownerKey": true,\n'));
  writeFileSync(join(dir, ".claude", "settings.local.json"), "{ \"local\": true }\n");
  writeFileSync(join(dir, ".claude", "commands", "trblazeui.md"), "# NuGet persona v2\n");
  rmSync(join(dir, ".claude", "commands", "TechieFlow", "tasks", "verify-phase.md"));
  writeFileSync(join(dir, ".claude", "commands", "TechieFlow", "tasks", "old.md"), "stale mirror file\n");
  mkdirSync(join(dir, ".opencode", "command"), { recursive: true });
  writeFileSync(join(dir, ".opencode", "command", "techierag.md"), "# NuGet persona\n");
  appendFileSync(join(dir, ".opencode", "plugin", "techieflow.js"), "\n// local edit\n");
  appendFileSync(join(dir, "WORKFLOW.html"), "<!-- local edit -->\n");
  appendFileSync(join(dir, "opencode.jsonc"), "// a comment only, no project keys\n");
  appendFileSync(join(dir, ".codex", "config.toml"), "\n# owner tuned\n");
  appendFileSync(join(dir, ".codex", "hooks.json"), "\n");
  writeFileSync(join(dir, "PROJECT-STATUS.md"), "# status\n");
  writeFileSync(join(dir, "CLAUDE.md"), "# claude\n");
  writeFileSync(join(dir, "docs", "MyApp-BRD.md"), "# BRD\n");
}

// The pre-2026-06 layout that update-framework.sh migrates in place.
function seedLegacyProject(dir) {
  seedProject(dir, { legacyPersona: false });
  mkdirSync(join(dir, ".bmad-core", "tasks"), { recursive: true });
  mkdirSync(join(dir, ".bmad-core", "data"), { recursive: true });
  writeFileSync(join(dir, ".bmad-core", "core-config.yaml"), "slashPrefix: BMad\ndevDebugLog: .bmad-core/debug.md\ncustomTechnicalDocuments: docs/Mine.md\n");
  writeFileSync(join(dir, ".bmad-core", "tasks", "old.md"), "old task\n");
  writeFileSync(join(dir, ".bmad-core", "data", "bmad-kb.md"), "old kb\n");
  mkdirSync(join(dir, ".claude", "commands", "BMad"), { recursive: true });
  writeFileSync(join(dir, ".claude", "commands", "BMad", "x.md"), "old mirror\n");
  writeFileSync(join(dir, ".bmad-scaffold-note.txt"), "old note\n");
  writeFileSync(join(dir, "opencode.jsonc"), '{ "agent": { "bmad-master": { "prompt": "{file:./.bmad-core/agents/bmad-master.md}" } } }\n');
  writeFileSync(join(dir, "CLAUDE.md"), "See .bmad-core/ for the framework.\n");
}

// The clean copy of the framework: what `npm pack` ships, plus the three shell scripts.
function stageCleanTemplate() {
  const packed = npm(["pack", "--json", `--pack-destination=${sandbox}`]);
  const tarball = join(sandbox, basename(JSON.parse(packed.stdout)[0].filename));
  const template = join(sandbox, "template");
  mkdirSync(template);
  run("tar", ["-xzf", tarball, "-C", template, "--strip-components=1"]);
  for (const script of ["scaffold-brownfield.sh", "scaffold-greenfield.sh", "update-framework.sh"]) {
    copyFileSync(join(root, script), join(template, script));
    chmodSync(join(template, script), 0o755);
  }
  return { template, tarball };
}

// ---------------------------------------------------------------- the checks

try {
  const { template, tarball } = stageCleanTemplate();
  console.log(`clean template staged from ${basename(tarball)}`);

  // ---- brownfield: scaffold-brownfield.sh versus `install`
  const brownShell = join(sandbox, "brownfield-shell");
  const brownNpm = join(sandbox, "brownfield-installer");
  seedProject(brownShell);
  seedProject(brownNpm);
  shell(join(template, "scaffold-brownfield.sh"), [brownShell]);
  node([installer, "install", `--target=${brownNpm}`]);

  check("brownfield: installer result equals scaffold-brownfield.sh result", () => assertSameTree(brownShell, brownNpm));
  check("brownfield: no node_modules, package.json or lock file left in the target", () => {
    for (const path of ["node_modules", "package.json", "package-lock.json"]) assert(!existsSync(join(brownNpm, path)), `${path} was left behind`);
  });
  check("brownfield: the expected files are present", () => {
    for (const path of [
      ".tfcore/tasks/build-phase.md", ".tfcore/core-config.yaml", ".tfcore/routing.yaml",
      ".claude/commands/TechieFlow/agents/analyst.md", ".claude/commands/TechieFlow/tasks/build-phase.md",
      ".claude/commands/generate-html.md", ".claude/settings.json", ".claude/commands/trblazeui.md",
      ".opencode/plugin/techieflow.js", ".opencode/opencode.jsonc", "opencode.jsonc", "WORKFLOW.html",
      ".codex/config.toml", ".codex/hooks.json", ".codex/rules/techieflow.rules",
      ...(codexBinderRuns ? [".codex/agents/analyst.toml", ".agents/skills/techieflow-build/SKILL.md"] : []),
      ".tf-scaffold-note.txt",
      "docs/metrics/runs.jsonl", "docs/metrics/gates.jsonl", "docs/metrics/sessions.jsonl",
      "docs/metrics/commits.jsonl", "docs/metrics/misses.jsonl", "docs/metrics/README.md",
      ".git/hooks/pre-commit", ".gitattributes",
    ]) assert(existsSync(join(brownNpm, path)), `missing ${path}`);
    assert(!existsSync(join(brownNpm, ".claude/commands/techierag.md")), "a library persona was installed from the framework");
    assert(!existsSync(join(brownNpm, ".tfcore/.session")), "a local-only session folder was installed");
    assert(!existsSync(join(brownNpm, ".opencode/command/generate-html.md")), "install deployed a file only update deploys");
  });
  check("brownfield: project files are untouched", () => {
    assert(read(join(brownNpm, ".gitignore")).startsWith("# Project rules\n/dist/\n"), "project .gitignore rules were rewritten");
    assert(read(join(brownNpm, "docs/notes.md")) === "project document\n", "docs/ content changed");
    assert(read(join(brownNpm, "src/App/Program.cs")) === "// application code\n", "src/ content changed");
    assert(read(join(brownNpm, ".claude/trblazeui.md")) === "# legacy NuGet persona\n", "a NuGet-deployed persona changed");
  });
  check("brownfield: managed .gitignore entries present, docs/metrics not ignored", () => {
    const all = new Set(lines(join(brownNpm, ".gitignore")));
    for (const entry of [".tfcore/", ".claude/", ".opencode/", ".codex/", ".agents/skills/", "/CLAUDE.md", "/WORKFLOW.html", "/opencode.jsonc", "/.tf-scaffold-note.txt", "node_modules/", "/package.json", "/package-lock.json", "bin/", "obj/"]) {
      assert(all.has(entry), `.gitignore is missing ${entry}`);
    }
    assert(!all.has("docs/") && !all.has("docs/metrics/"), ".gitignore hides docs/metrics");
  });
  check("brownfield: Claude mirror is byte-identical to .tfcore/", () => {
    const diff = mirrorDifferences(brownNpm);
    assert(diff.length === 0, `${diff.length} mirror difference(s):\n${diff.join("\n")}`);
  });
  check("brownfield: every {file:} reference in both opencode.jsonc files resolves", () => {
    for (const file of ["opencode.jsonc", ".opencode/opencode.jsonc"]) {
      const bad = unresolvedReferences(join(brownNpm, file));
      assert(bad.length === 0, `${file} has unresolved references: ${bad.join(", ")}`);
    }
    assert(read(join(brownNpm, ".opencode/opencode.jsonc")).includes("{file:../.tfcore/"), ".opencode/opencode.jsonc does not point one folder up");
  });
  check("brownfield: a second install run changes nothing", () => {
    const before = snapshot(brownNpm);
    node([installer, "install", `--target=${brownNpm}`]);
    assertUnchanged(before, brownNpm, "the second install run");
  });

  // ---- greenfield: scaffold-greenfield.sh versus `install --greenfield`
  const greenShell = join(sandbox, "greenfield-shell");
  const greenNpm = join(sandbox, "greenfield-installer");
  shell(join(template, "scaffold-greenfield.sh"), [greenShell]);
  node([installer, "install", "--greenfield", `--target=${greenNpm}`]);
  check("greenfield: installer result equals scaffold-greenfield.sh result", () => assertSameTree(greenShell, greenNpm));
  check("greenfield: solution skeleton folders and greenfield note", () => {
    for (const path of ["src", "tests/playwright", "tests/unit"]) assert(existsSync(join(greenNpm, path)), `missing ${path}/`);
    assert(read(join(greenNpm, ".tf-scaffold-note.txt")).includes("greenfield"), "note is not the greenfield note");
  });
  check("greenfield: Claude mirror and OpenCode references", () => {
    const diff = mirrorDifferences(greenNpm);
    assert(diff.length === 0, `${diff.length} mirror difference(s):\n${diff.join("\n")}`);
    const bad = unresolvedReferences(join(greenNpm, ".opencode/opencode.jsonc"));
    assert(bad.length === 0, `unresolved references: ${bad.join(", ")}`);
  });

  // ---- update: update-framework.sh versus `update`, starting from one installed project
  const updateShell = join(sandbox, "update-shell");
  const updateNpm = join(sandbox, "update-installer");
  cpSync(brownNpm, updateShell, { recursive: true });
  cpSync(brownNpm, updateNpm, { recursive: true });
  perturbInstalledProject(updateShell);
  perturbInstalledProject(updateNpm);
  shell(join(template, "update-framework.sh"), [updateShell]);
  node([installer, "update", `--target=${updateNpm}`]);
  check("update: installer result equals update-framework.sh result", () => assertSameTree(updateShell, updateNpm));
  check("update: framework files refreshed", () => {
    assert(read(join(updateNpm, ".tfcore/tasks/build-phase.md")) === read(join(template, ".tfcore/tasks/build-phase.md")), "edited task not restored");
    assert(!existsSync(join(updateNpm, ".tfcore/tasks/stale-old-task.md")), "stale task not deleted");
    assert(!existsSync(join(updateNpm, ".tfcore/workflows")), "stale stock folder not removed");
    assert(existsSync(join(updateNpm, ".claude/commands/TechieFlow/tasks/verify-phase.md")), "deleted mirror file not restored");
    assert(!existsSync(join(updateNpm, ".claude/commands/TechieFlow/tasks/old.md")), "stale mirror file not deleted");
    assert(read(join(updateNpm, "WORKFLOW.html")) === read(join(template, "WORKFLOW.html")), "WORKFLOW.html not refreshed");
    assert(read(join(updateNpm, "opencode.jsonc")) === read(join(template, "opencode.jsonc")), "root opencode.jsonc with no project keys not refreshed");
    assert(existsSync(join(updateNpm, "opencode.jsonc.bak")), "old opencode.jsonc not backed up");
    assert(read(join(updateNpm, ".opencode/plugin/techieflow.js")) === read(join(template, ".opencode/plugin/techieflow.js")), "plugin not refreshed");
    assert(existsSync(join(updateNpm, ".opencode/command/generate-html.md")), "short-form OpenCode command not deployed");
    assert(read(join(updateNpm, ".codex/hooks.json")) === read(join(template, ".codex/hooks.json")), "Codex hooks not refreshed");
    assert(existsSync(join(updateNpm, ".claude/settings.json.bak")), "old settings.json not backed up");
    assert(!read(join(updateNpm, ".claude/settings.json")).includes("ownerKey"), "settings.json not refreshed");
  });
  check("update: owner content preserved", () => {
    assert(read(join(updateNpm, ".tfcore/core-config.yaml")).includes("customTechnicalDocuments: docs/MyApp-Architecture.md"), "core-config.yaml lost the owner's line");
    assert(read(join(updateNpm, ".tfcore/routing.yaml")).includes("# owner tuned"), "routing.yaml was replaced");
    assert(existsSync(join(updateNpm, ".tfcore/mine/keep.md")), "an unknown .tfcore folder was deleted");
    assert(read(join(updateNpm, ".claude/settings.local.json")) === "{ \"local\": true }\n", "settings.local.json touched");
    assert(read(join(updateNpm, ".claude/commands/trblazeui.md")) === "# NuGet persona v2\n", "NuGet persona under .claude/commands overwritten");
    assert(read(join(updateNpm, ".opencode/command/techierag.md")) === "# NuGet persona\n", "NuGet persona under .opencode/command overwritten");
    assert(read(join(updateNpm, ".codex/config.toml")).includes("# owner tuned"), ".codex/config.toml replaced");
    for (const path of ["PROJECT-STATUS.md", "CLAUDE.md", "docs/MyApp-BRD.md", "docs/notes.md", "src/App/Program.cs"]) {
      assert(existsSync(join(updateNpm, path)), `${path} missing after update`);
    }
  });
  check("update: Claude mirror and OpenCode references after update", () => {
    const diff = mirrorDifferences(updateNpm);
    assert(diff.length === 0, `${diff.length} mirror difference(s):\n${diff.join("\n")}`);
    for (const file of ["opencode.jsonc", ".opencode/opencode.jsonc"]) {
      const bad = unresolvedReferences(join(updateNpm, file));
      assert(bad.length === 0, `${file} has unresolved references: ${bad.join(", ")}`);
    }
  });

  // ---- update on a project that is already current: nothing to back up
  const currentShell = join(sandbox, "update-current-shell");
  const currentNpm = join(sandbox, "update-current-installer");
  cpSync(brownNpm, currentShell, { recursive: true });
  cpSync(brownNpm, currentNpm, { recursive: true });
  shell(join(template, "update-framework.sh"), [currentShell]);
  node([installer, "update", `--target=${currentNpm}`]);
  check("update on a current project: same result as the shell script, no backups made", () => {
    assertSameTree(currentShell, currentNpm);
    assert(!existsSync(join(currentNpm, ".claude/settings.json.bak")), "settings.json was backed up although it was current");
    assert(!existsSync(join(currentNpm, "opencode.jsonc.bak")), "opencode.jsonc was backed up although it was current");
  });

  // ---- update --dry-run writes nothing (both routes)
  const dryShell = join(sandbox, "update-dry-shell");
  const dryNpm = join(sandbox, "update-dry-installer");
  cpSync(brownNpm, dryShell, { recursive: true });
  cpSync(brownNpm, dryNpm, { recursive: true });
  perturbInstalledProject(dryShell);
  perturbInstalledProject(dryNpm);
  check("update --dry-run: neither route changes a file", () => {
    const beforeShell = snapshot(dryShell);
    const beforeNpm = snapshot(dryNpm);
    shell(join(template, "update-framework.sh"), [dryShell, "--dry-run"]);
    node([installer, "update", "--dry-run", `--target=${dryNpm}`]);
    assertUnchanged(beforeShell, dryShell, "update-framework.sh --dry-run");
    assertUnchanged(beforeNpm, dryNpm, "update --dry-run");
  });

  // ---- update --keep-permissions leaves an edited settings.json alone
  const keepShell = join(sandbox, "update-keep-shell");
  const keepNpm = join(sandbox, "update-keep-installer");
  cpSync(brownNpm, keepShell, { recursive: true });
  cpSync(brownNpm, keepNpm, { recursive: true });
  perturbInstalledProject(keepShell);
  perturbInstalledProject(keepNpm);
  shell(join(template, "update-framework.sh"), [keepShell, "--keep-permissions"]);
  node([installer, "update", "--keep-permissions", `--target=${keepNpm}`]);
  check("update --keep-permissions: same result as the shell script, settings.json kept", () => {
    assertSameTree(keepShell, keepNpm);
    assert(read(join(keepNpm, ".claude/settings.json")).includes("ownerKey"), "settings.json was refreshed despite --keep-permissions");
    assert(!existsSync(join(keepNpm, ".claude/settings.json.bak")), "a backup was made despite --keep-permissions");
  });

  // ---- update on the old .bmad-core layout
  const legacyShell = join(sandbox, "legacy-shell");
  const legacyNpm = join(sandbox, "legacy-installer");
  seedLegacyProject(legacyShell);
  seedLegacyProject(legacyNpm);
  shell(join(template, "update-framework.sh"), [legacyShell]);
  node([installer, "update", `--target=${legacyNpm}`]);
  check("update of the old .bmad-core layout: same result as the shell script", () => {
    assertSameTree(legacyShell, legacyNpm);
    assert(!existsSync(join(legacyNpm, ".bmad-core")), ".bmad-core was not renamed");
    assert(read(join(legacyNpm, ".tfcore/core-config.yaml")).includes("slashPrefix: TechieFlow"), "core-config.yaml not patched");
    assert(read(join(legacyNpm, ".tfcore/core-config.yaml")).includes("customTechnicalDocuments: docs/Mine.md"), "core-config.yaml owner line lost");
    assert(!existsSync(join(legacyNpm, ".claude/commands/BMad")), "old mirror not removed");
    assert(existsSync(join(legacyNpm, "opencode.jsonc.bak")), "legacy opencode.jsonc not backed up");
  });

  // ---- uninstall: preview first, then --force
  const uninstallDir = join(sandbox, "uninstall");
  cpSync(brownNpm, uninstallDir, { recursive: true });
  check("uninstall without --force removes nothing", () => {
    const before = snapshot(uninstallDir);
    node([installer, "uninstall", `--target=${uninstallDir}`]);
    assertUnchanged(before, uninstallDir, "uninstall without --force");
  });
  check("uninstall --force removes the framework and keeps the project", () => {
    node([installer, "uninstall", "--force", `--target=${uninstallDir}`]);
    for (const path of [".tfcore", ".claude/commands/TechieFlow", ".claude/commands/generate-html.md", ".claude/settings.json", ".opencode", ".codex", ".agents", "WORKFLOW.html", "opencode.jsonc", ".tf-scaffold-note.txt", ".git/hooks/pre-commit"]) {
      assert(!existsSync(join(uninstallDir, path)), `${path} still present after uninstall`);
    }
    for (const path of ["docs/notes.md", "docs/metrics/runs.jsonl", "docs/metrics/README.md", "src/App/App.csproj", ".claude/trblazeui.md", ".claude/commands/trblazeui.md", ".gitattributes"]) {
      assert(existsSync(join(uninstallDir, path)), `${path} was removed by uninstall`);
    }
    const ignore = read(join(uninstallDir, ".gitignore"));
    assert(ignore.startsWith("# Project rules\n/dist/\n"), "project .gitignore rules changed");
    const all = new Set(ignore.replace(/\r/g, "").split("\n"));
    for (const entry of [".tfcore/", ".claude/", "/WORKFLOW.html", "/opencode.jsonc"]) assert(!all.has(entry), `.gitignore still lists ${entry}`);
    assert(!ignore.includes("deployed copies, never commit"), ".gitignore still carries the framework block header");
    assert(all.has("node_modules/") && all.has("bin/"), "uninstall removed ignore rules that describe the project's own build output");
  });

  // ---- install --dry-run and --no-gitignore
  check("install --greenfield --dry-run creates nothing", () => {
    const dryTarget = join(sandbox, "dry-greenfield");
    node([installer, "install", "--greenfield", "--dry-run", `--target=${dryTarget}`]);
    assert(!existsSync(dryTarget), "dry run created the target folder");
  });
  check("install --dry-run on an existing project changes nothing", () => {
    const dryTarget = join(sandbox, "dry-brownfield");
    seedProject(dryTarget);
    const before = snapshot(dryTarget);
    node([installer, "install", "--dry-run", `--target=${dryTarget}`]);
    assertUnchanged(before, dryTarget, "install --dry-run");
  });
  check("install --no-gitignore leaves .gitignore and .gitattributes alone", () => {
    const target = join(sandbox, "no-gitignore");
    seedProject(target);
    node([installer, "install", "--no-gitignore", `--target=${target}`]);
    assert(read(join(target, ".gitignore")) === "# Project rules\n/dist/\n", ".gitignore was edited");
    assert(!existsSync(join(target, ".gitattributes")), ".gitattributes was created");
    assert(existsSync(join(target, ".tfcore/tasks/build-phase.md")), "framework was not installed");
  });
  check("install refuses the framework's own folder", () => {
    const result = node([installer, "install", `--target=${root}`], { allowFailure: true });
    assert(result.status !== 0, "installing into the framework repository was not refused");
  });
  check("update refuses a folder that has no framework", () => {
    const target = join(sandbox, "not-scaffolded");
    seedProject(target);
    const result = node([installer, "update", `--target=${target}`], { allowFailure: true });
    assert(result.status !== 0, "update did not refuse a folder without .tfcore/");
  });

  // ---- the one-shot form: what `npx @techierathore/techieflow@latest install` runs
  const npxTarget = join(sandbox, "npx-install");
  seedProject(npxTarget);
  check("one-shot `npm exec` install from the packed tarball matches the installer", () => {
    npm(["exec", "--yes", `--package=${tarball}`, "--", "techieflow", "install"], { cwd: npxTarget });
    assertSameTree(brownNpm, npxTarget);
    for (const path of ["node_modules", "package.json", "package-lock.json"]) assert(!existsSync(join(npxTarget, path)), `${path} left behind by npm exec`);
  });
} catch (error) {
  failures.push(`setup: ${error.message}`);
  console.log(`FAIL  setup\n      ${error.message.split("\n").join("\n      ")}`);
} finally {
  if (keepSandbox) console.log(`temporary folder kept: ${sandbox}`);
  else rmSync(sandbox, { recursive: true, force: true });
}

console.log("");
for (const note of notes) console.log(`note: ${note}`);
if (failures.length) {
  console.log(`${passed} check(s) passed, ${failures.length} failed:`);
  for (const failure of failures) console.log(`  - ${failure}`);
  process.exit(1);
}
console.log(`installer tests passed (${passed} checks)`);

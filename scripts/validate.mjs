#!/usr/bin/env node
// scripts/validate.mjs — the checks that run before every publish and on every push.
//
//   1. Mirror parity: every file under .claude/commands/TechieFlow/<sub>/ is byte-identical
//      to .tfcore/<sub>/. Claude Code only reads the mirror, so drift means Claude Code and
//      OpenCode run different instructions.
//   2. OpenCode references: every {file:...} in opencode.jsonc points at a file that exists.
//      One dead reference makes OpenCode reject the whole config.
//   3. Shell syntax: `bash -n` on every .sh file in the repository.
//   4. Package contents: `npm pack --dry-run` succeeds, ships every file the shell scripts
//      deploy, and ships none of the local-only or per-machine files.
//
// Exit code 0 means every check passed. Any failure exits 1 and names the problem.

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const problems = [];
let passed = 0;

function check(name, fn) {
  try {
    fn();
    passed++;
    console.log(`ok    ${name}`);
  } catch (error) {
    problems.push(`${name}: ${error.message}`);
    console.log(`FAIL  ${name}\n      ${error.message.split("\n").join("\n      ")}`);
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const skipDirectories = new Set([".git", "node_modules"]);

function filesUnder(directory) {
  const out = [];
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      if (entry.isDirectory()) { if (!skipDirectories.has(entry.name)) walk(join(current, entry.name)); }
      else if (entry.isFile()) out.push(join(current, entry.name));
    }
  };
  if (existsSync(directory)) walk(directory);
  return out;
}

const rel = (path) => relative(root, path).split("\\").join("/");

// ---- 1. mirror parity
check("Claude mirror is byte-identical to .tfcore/", () => {
  const mirror = join(root, ".claude", "commands", "TechieFlow");
  const differences = [];
  for (const sub of readdirSync(mirror)) {
    const coreFiles = new Map(filesUnder(join(root, ".tfcore", sub)).map((f) => [relative(join(root, ".tfcore", sub), f), f]));
    const mirrorFiles = new Map(filesUnder(join(mirror, sub)).map((f) => [relative(join(mirror, sub), f), f]));
    for (const [name, corePath] of coreFiles) {
      if (!mirrorFiles.has(name)) differences.push(`missing from mirror: ${sub}/${name}`);
      else if (!readFileSync(corePath).equals(readFileSync(mirrorFiles.get(name)))) differences.push(`content differs: ${sub}/${name}`);
    }
    for (const name of mirrorFiles.keys()) if (!coreFiles.has(name)) differences.push(`only in mirror: ${sub}/${name}`);
  }
  assert(differences.length === 0, `${differences.length} difference(s) between .tfcore/ and .claude/commands/TechieFlow/:\n${differences.join("\n")}\nFix: copy the changed files from .tfcore/ over the mirror, or re-run the scaffold's agent sync for every folder.`);
});

// ---- 2. OpenCode references
check("every {file:} reference in opencode.jsonc resolves", () => {
  const text = readFileSync(join(root, "opencode.jsonc"), "utf8");
  const refs = [...new Set([...text.matchAll(/\{file:([^}]*)\}/g)].map((m) => m[1]))];
  assert(refs.length > 0, "opencode.jsonc contains no {file:} references at all");
  const dead = refs.filter((ref) => !existsSync(join(root, ref)));
  assert(dead.length === 0, `dead references:\n${dead.join("\n")}`);
});

// ---- 3. shell syntax
check("bash -n passes on every .sh file", () => {
  const scripts = filesUnder(root).filter((f) => f.endsWith(".sh"));
  assert(scripts.length > 0, "no .sh files found");
  const version = spawnSync("bash", ["-c", "echo $BASH_VERSION"], { encoding: "utf8" });
  if (version.error) throw new Error(`bash could not be started: ${version.error.message}`);
  const bashVersion = version.stdout.trim();
  const broken = [];
  for (const script of scripts) {
    const result = spawnSync("bash", ["-n", script], { encoding: "utf8" });
    if (result.error) throw new Error(`bash could not be started: ${result.error.message}`);
    if (result.status !== 0) broken.push(`${rel(script)}: ${result.stderr.trim()}`);
  }
  if (broken.length && /^[123]\./.test(bashVersion)) {
    broken.push(`This terminal's bash is ${bashVersion}, Apple's old copy. The framework needs bash 4 or newer.`,
      "On a Mac: install it with `brew install bash`, put /opt/homebrew/bin first on the PATH in ~/.zshrc,",
      "then open a NEW terminal window and run the command again. Check with: which -a bash");
  }
  assert(broken.length === 0, broken.join("\n"));
  console.log(`      ${scripts.length} script(s) checked with bash ${bashVersion}`);
});

// ---- 4. package contents
const libraryPersonas = new Set(["trblazeui.md", "techierag.md"]);

// What the three shell scripts copy out of this repository into a project.
function deployedFiles() {
  const out = [];
  for (const f of filesUnder(join(root, ".tfcore"))) {
    const r = rel(f);
    if (!r.startsWith(".tfcore/.session/")) out.push(r);
  }
  for (const f of filesUnder(join(root, ".claude", "commands"))) {
    if (!libraryPersonas.has(f.split("/").pop())) out.push(rel(f));
  }
  for (const f of filesUnder(join(root, ".opencode", "plugin"))) if (f.endsWith(".js")) out.push(rel(f));
  for (const f of filesUnder(join(root, ".opencode", "command"))) {
    if (f.endsWith(".md") && !libraryPersonas.has(f.split("/").pop())) out.push(rel(f));
  }
  out.push(".codex/config.toml", ".codex/hooks.json");
  for (const f of filesUnder(join(root, ".codex", "rules"))) out.push(rel(f));
  out.push("opencode.jsonc", "WORKFLOW.html");
  return out.filter((r) => !/(^|\/)(\.DS_Store|Thumbs\.db|desktop\.ini)$/.test(r) && !r.endsWith(".bak"));
}

const mustNotShip = [
  ".tfcore/.session", ".claude/settings.json", ".claude/settings.local.json",
  ".claude/trblazeui.md", ".claude/techierag.md",
  ".claude/commands/trblazeui.md", ".claude/commands/techierag.md",
  ".opencode/command/trblazeui.md", ".opencode/command/techierag.md",
  ".opencode/node_modules", ".opencode/package.json", ".opencode/package-lock.json", ".opencode/.gitignore",
  ".codex/agents", ".agents", ".techierag", ".trblazeui", ".github",
  "scaffold-brownfield.sh", "scaffold-greenfield.sh", "update-framework.sh",
  "scripts/test-install.mjs", "scripts/validate.mjs",
  "docs/TechieFlow-Requirements.md", "docs/TechieFlow-How-It-Works.md", "docs/metrics",
  "DECISIONS.md", "WorkFlow-Context.md", "CodexChanges.md",
];
// The package ships the framework plus the installer's own three files under scripts/.
// Those never reach a project: the installer copies the framework folders only.
const mustShip = [
  "package.json", "LICENSE", "README.md", "docs/TechieFlow-Installation.md",
  "scripts/install.mjs", "scripts/npm-postinstall.mjs", "scripts/npm-cleanup.mjs",
];

check("npm pack --dry-run succeeds and ships the right files", () => {
  const onWindows = process.platform === "win32";
  const result = process.env.npm_execpath
    ? spawnSync(process.execPath, [process.env.npm_execpath, "pack", "--dry-run", "--json"], { cwd: root, encoding: "utf8" })
    : spawnSync(onWindows ? "npm.cmd" : "npm", ["pack", "--dry-run", "--json"], { cwd: root, encoding: "utf8", shell: onWindows });
  if (result.error) throw new Error(`npm could not be started: ${result.error.message}`);
  assert(result.status === 0, `npm pack --dry-run failed:\n${result.stdout}${result.stderr}`);
  const packed = new Set(JSON.parse(result.stdout)[0].files.map((f) => f.path));
  const missing = [...deployedFiles(), ...mustShip].filter((f) => !packed.has(f));
  const leaked = [...packed].filter((p) => mustNotShip.some((bad) => p === bad || p.startsWith(`${bad}/`)));
  const report = [];
  if (missing.length) report.push(`files the shell scripts deploy but the package does not ship:\n${missing.join("\n")}`);
  if (leaked.length) report.push(`files that must not ship:\n${leaked.join("\n")}`);
  assert(report.length === 0, report.join("\n"));
  console.log(`      ${packed.size} file(s) in the package`);
});

console.log("");
if (problems.length) {
  console.log(`${passed} check(s) passed, ${problems.length} failed`);
  process.exit(1);
}
console.log(`validation passed (${passed} checks)`);

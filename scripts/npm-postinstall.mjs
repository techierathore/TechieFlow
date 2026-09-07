#!/usr/bin/env node
// scripts/npm-postinstall.mjs — the install hook, for when someone runs
//
//   npm install @techierathore/techieflow
//
// instead of the documented `npx @techierathore/techieflow@latest install`. npm runs this
// hook after it has put the package under node_modules/. The hook installs the framework
// into the project (the folder npm was run in), then starts npm-cleanup.mjs detached to
// remove the package from node_modules/, package.json and package-lock.json once npm has
// finished writing them. The result is the same as the npx command: the framework's hidden
// folders, and no npm files that were not there before.
//
// npm 12 and newer do not run install hooks unless the project allows them, so on those
// versions a plain `npm install` only places the package under node_modules/. The fix is
// to run the documented npx command, which installs the framework and tidies that up.
//
// The hook does nothing when the package is not being installed as a dependency of some
// other folder: `npx`, `npm exec`, `npm pack`, `npm publish` and `npm install` inside
// this repository all skip it.

import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const target = process.env.INIT_CWD ? resolve(process.env.INIT_CWD) : null;
const dependencyInstall = ["install", "ci"].includes(process.env.npm_command)
  && target !== null
  && target !== packageRoot
  && existsSync(join(target, "node_modules", "@techierathore", "techieflow"));

if (!dependencyInstall) process.exit(0);

const installed = spawnSync(process.execPath, [join(packageRoot, "scripts", "install.mjs"), "install", `--target=${target}`], {
  cwd: target,
  env: process.env,
  stdio: "inherit",
});
if (installed.status !== 0) process.exit(installed.status ?? 1);

const cleanup = spawn(process.execPath, [join(packageRoot, "scripts", "npm-cleanup.mjs"), target], {
  cwd: target,
  detached: true,
  stdio: "ignore",
  windowsHide: true,
});
cleanup.unref();
console.log("TechieFlow installed. The temporary npm files (node_modules, package.json, package-lock.json entries) are being removed.");

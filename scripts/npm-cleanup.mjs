#!/usr/bin/env node
// scripts/npm-cleanup.mjs — removes the package's own footprint after a plain `npm install`.
//
// The framework is not an application dependency. `npm install @techierathore/techieflow`
// still puts the package under node_modules/ and writes it into package.json and
// package-lock.json. Once the framework files are in place, this removes that footprint:
//
//   node_modules/@techierathore/techieflow   the package folder
//   node_modules/@techierathore              when nothing else is in it
//   node_modules/.bin/techieflow*            the command shims
//   the package's entry in package.json, package-lock.json and node_modules/.package-lock.json
//
// If npm created package.json, package-lock.json or node_modules only for this install
// (an empty folder, or a .NET project), they are removed as well. A project's own
// package.json, lock file and node_modules are kept, minus the entry for this package.
//
// Used two ways:
//   - by npm-postinstall.mjs, detached, after the install hook has deployed the framework.
//     npm writes package.json, package-lock.json and node_modules/.package-lock.json AFTER
//     the hook has run, so the detached process waits for that last write before it starts.
//   - by install.mjs, straight away, when the package is found under node_modules/ of the
//     project it just installed into. That happens when the owner ran `npm install` on an
//     npm that skips install hooks (npm 12 and newer) and then ran the real command.

import { existsSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

export const packageName = "@techierathore/techieflow";
const dependencyKeys = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"];
const lockKey = `node_modules/${packageName}`;

function readJson(path) {
  try { return JSON.parse(readFileSync(path, "utf8")); } catch { return null; }
}

const writeJson = (path, value) => writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);

// True for a package.json that npm created for this install alone: nothing in it except
// empty dependency tables once this package's entry is gone.
function isEmptyManifest(manifest) {
  return Object.entries(manifest).every(([key, value]) =>
    dependencyKeys.includes(key) && value && typeof value === "object" && Object.keys(value).length === 0);
}

// Drops this package from a package.json object. Returns true when something was removed.
function dropFromManifest(manifest) {
  let changed = false;
  for (const key of dependencyKeys) {
    if (manifest?.[key] && packageName in manifest[key]) { delete manifest[key][packageName]; changed = true; }
  }
  return changed;
}

// Drops this package from a package-lock.json object (root file or the hidden one in node_modules).
function dropFromLock(lock) {
  let changed = false;
  if (lock?.packages) {
    if (lockKey in lock.packages) { delete lock.packages[lockKey]; changed = true; }
    if (lock.packages[""] && dropFromManifest(lock.packages[""])) changed = true;
  }
  if (lock?.dependencies && packageName in lock.dependencies) { delete lock.dependencies[packageName]; changed = true; }
  return changed;
}

// Does this project folder hold the package as an npm dependency artifact?
export function hasDependencyFootprint(target) {
  const manifest = readJson(join(target, "package.json"));
  return existsSync(join(target, "node_modules", "@techierathore", "techieflow"))
    || dependencyKeys.some((key) => manifest?.[key] && packageName in manifest[key]);
}

// Removes the footprint. Returns the list of things removed, in plain words, for the caller to print.
export function removeDependencyFootprint(target) {
  const removed = [];
  const nm = join(target, "node_modules");
  const scopeDir = join(nm, "@techierathore");
  const packageDir = join(scopeDir, "techieflow");
  const bin = join(nm, ".bin");

  if (existsSync(packageDir)) { rmSync(packageDir, { recursive: true, force: true }); removed.push("node_modules/@techierathore/techieflow/"); }
  if (existsSync(scopeDir) && readdirSync(scopeDir).every((e) => e === ".DS_Store")) rmSync(scopeDir, { recursive: true, force: true });
  if (existsSync(bin)) {
    for (const shim of readdirSync(bin)) {
      if (shim === "techieflow" || shim.startsWith("techieflow.")) { rmSync(join(bin, shim), { force: true }); removed.push(`node_modules/.bin/${shim}`); }
    }
  }

  const manifestPath = join(target, "package.json");
  const manifest = readJson(manifestPath);
  let manifestRemoved = false;
  if (manifest && dropFromManifest(manifest)) {
    if (isEmptyManifest(manifest)) { rmSync(manifestPath, { force: true }); manifestRemoved = true; removed.push("package.json (npm created it for this install)"); }
    else { writeJson(manifestPath, manifest); removed.push(`the ${packageName} entry in package.json`); }
  }

  const lockPath = join(target, "package-lock.json");
  if (manifestRemoved) {
    if (existsSync(lockPath)) { rmSync(lockPath, { force: true }); removed.push("package-lock.json (npm created it for this install)"); }
  } else {
    const lock = readJson(lockPath);
    if (lock && dropFromLock(lock)) { writeJson(lockPath, lock); removed.push(`the ${packageName} entry in package-lock.json`); }
  }

  if (existsSync(nm)) {
    const bookkeeping = (entry) => entry === ".package-lock.json" || entry === ".DS_Store"
      || (entry === ".bin" && readdirSync(bin).every((e) => e === ".DS_Store"));
    if (readdirSync(nm).every(bookkeeping)) { rmSync(nm, { recursive: true, force: true }); removed.push("node_modules/ (npm created it for this install)"); }
    else {
      const hiddenPath = join(nm, ".package-lock.json");
      const hidden = readJson(hiddenPath);
      if (hidden && dropFromLock(hidden)) writeJson(hiddenPath, hidden);
    }
  }
  return removed;
}

// ---- standalone use: node npm-cleanup.mjs <project folder>, started detached by the install hook.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const target = process.argv[2];
  if (!target || !existsSync(target)) process.exit(0);
  const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
  const hiddenLock = join(target, "node_modules", ".package-lock.json");
  // npm's last write is node_modules/.package-lock.json. Wait for it to name this package,
  // then a moment longer for npm to close it. Give up waiting after 60 seconds (for example
  // when npm was told not to write a lock file) and clean up anyway.
  for (let waited = 0; waited < 60_000; waited += 200) {
    const hidden = readJson(hiddenLock);
    if (hidden?.packages && lockKey in hidden.packages) break;
    await sleep(200);
  }
  await sleep(500);
  // On Windows npm may still hold a handle for a moment; retry briefly.
  for (let attempt = 0; attempt < 50; attempt++) {
    try { removeDependencyFootprint(target); break; } catch { await sleep(200); }
  }
}

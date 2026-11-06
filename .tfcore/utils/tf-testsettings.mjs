// tf-testsettings.mjs — the verify harness's settings for Node: the screen and mockup checks, the
// register-test-users script, and any verify spec (Sevak TF-015). The same two files and rules as
// tf-testsettings.py, which documents the keys:
//   tests/verify/testsettings.json        committed; every key, with empty values
//   tests/verify/testsettings.Local.json  git-ignored; this machine's real values, laid over it key by key
// Keys are read with ':' between levels: setting('Verify:Login:User'), setting('TestUsers:1:Password').
// No environment variable is a setting. setting(key, 'OLD_NAME') still reads OLD_NAME for one release when
// the files leave the key empty, and says on stderr where to move it.
//
//   import { setting, testSettings, setLocal } from '../../.tfcore/utils/tf-testsettings.mjs';
import fs from 'node:fs';
import path from 'node:path';

export const SETTINGS_DIR = process.env.TF_TESTSETTINGS_DIR || path.join('tests', 'verify');
export const BASE_FILE = path.join(SETTINGS_DIR, 'testsettings.json');
export const LOCAL_FILE = path.join(SETTINGS_DIR, 'testsettings.Local.json');

function readJson(file) {
  let text;
  try { text = fs.readFileSync(file, 'utf8').replace(/^﻿/, ''); } catch { return {}; }
  try {
    const v = JSON.parse(text);
    return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
  } catch (e) {
    process.stderr.write(`tf-testsettings: ${file} is not valid JSON (${e.message}); it is ignored\n`);
    return {};
  }
}

function layer(base, over) {
  const out = { ...base };
  for (const [k, v] of Object.entries(over)) {
    const cur = out[k];
    const both = v && typeof v === 'object' && !Array.isArray(v) && cur && typeof cur === 'object' && !Array.isArray(cur);
    out[k] = both ? layer(cur, v) : v;
  }
  return out;
}

/** testsettings.json with testsettings.Local.json laid over it (read fresh each call). */
export function testSettings() { return layer(readJson(BASE_FILE), readJson(LOCAL_FILE)); }

function lookup(tree, key) {
  let node = tree;
  for (const part of key.split(/[:.]/).filter(Boolean)) {
    if (node && typeof node === 'object' && !Array.isArray(node)) {
      const hit = Object.keys(node).find((k) => k.toLowerCase() === part.toLowerCase());
      if (hit === undefined) return undefined;
      node = node[hit];
    } else if (Array.isArray(node) && /^\d+$/.test(part)) {
      node = node[Number(part)];
    } else return undefined;
  }
  return node;
}

const str = (v) => (v === undefined || v === null ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v));

/** One setting as a string; '' when unset. envName: the old variable, read for one release only. */
export function setting(key, envName = null) {
  const s = testSettings();
  let v = str(lookup(s, key));
  const k = key.toLowerCase().replace(/\./g, ':');
  if (!v && (k === 'verify:login:user' || k === 'verify:login:password')) {
    const n = str(lookup(s, 'Verify:Login:TestUser'));
    if (n) v = str(lookup(s, `TestUsers:${n}:${k.endsWith('user') ? 'Email' : 'Password'}`));
  }
  if (!v && envName && process.env[envName]) {
    process.stderr.write(`tf-testsettings: ${envName} is read for one more release only; move it to ${LOCAL_FILE} as "${key}" (no environment variable is a setting, stack rule Q11.2)\n`);
    v = process.env[envName];
  }
  return v;
}

/** Writes one key into the git-ignored Local file only, keeping everything else in it. */
export function setLocal(key, value) {
  const tree = readJson(LOCAL_FILE);
  const parts = key.split(/[:.]/).filter(Boolean);
  let node = tree;
  for (const part of parts.slice(0, -1)) {
    const hit = Object.keys(node).find((k) => k.toLowerCase() === part.toLowerCase()) ?? part;
    if (!node[hit] || typeof node[hit] !== 'object' || Array.isArray(node[hit])) node[hit] = {};
    node = node[hit];
  }
  const last = parts[parts.length - 1];
  node[Object.keys(node).find((k) => k.toLowerCase() === last.toLowerCase()) ?? last] = value;
  fs.mkdirSync(SETTINGS_DIR, { recursive: true });
  fs.writeFileSync(`${LOCAL_FILE}.tmp`, `${JSON.stringify(tree, null, 2)}\n`);
  fs.renameSync(`${LOCAL_FILE}.tmp`, LOCAL_FILE);
}

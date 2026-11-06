// tf-register-test-users.mjs — registers an AppManager app's own test users, once, by the owner (stack rule Q4a).
//
//   node .tfcore/utils/tf-register-test-users.mjs [--appsettings <file>]... [--dry-run]
//
// The ONLY place a test user is ever registered on a shared AppManager. A verify test never registers
// one: it may submit Register with a test user's address only after signing in as that user in the same
// test, and stops when the sign-in is refused (Sevak TF-016). This script refuses to run inside a verify.
//
// Reads (tf-testsettings.mjs: tests/verify/testsettings.json under the git-ignored testsettings.Local.json):
//   TestUsers:<n>:Email, FirstName, LastName   the usage guide's Test users, by their number
//   AppManager:BaseUrl, ApiKey, ApplicationId, DeviceId   where to register; when the settings leave them
//     empty, from each --appsettings file in turn (an appsettings.Development.json, or the project's user
//     secrets.json with flat "AppManager:ApiKey" keys), later files winning
// For each user with an Email and no Password yet: asks AppManager for its public key
// (GET /AuthSvc/public-key), generates a password, sends it encrypted (RSA-OAEP, SHA-256) to
// POST /AuthSvc/register under the app's ApplicationId, and on success writes TestUsers:<n>:Password into
// tests/verify/testsettings.Local.json only. A password is never printed. A user that already has a
// password is skipped, so it is safe to run again. --dry-run says what it would do and calls nothing.
// Exit 0 all done · 1 a registration failed · 2 settings missing · 3 refused (inside a verify).
import crypto from 'node:crypto';
import fs from 'node:fs';
import { setting, setLocal, testSettings, LOCAL_FILE } from './tf-testsettings.mjs';

const argv = process.argv.slice(2);
const dry = argv.includes('--dry-run');
const files = argv.flatMap((a, i) => (a === '--appsettings' && argv[i + 1] ? [argv[i + 1]] : []));

try {
  const marker = JSON.parse(fs.readFileSync('.tfcore/.session/phase.json', 'utf8'));
  if (marker && marker.cmd === 'verify-phase') {
    console.error('tf-register-test-users: REFUSED — a verify is running. Test users are registered by the owner, never by a verify (stack rule Q4a).');
    process.exit(3);
  }
} catch { /* no marker: not inside a command */ }

function flat(obj, pre = '', out = {}) {
  for (const [k, v] of Object.entries(obj || {})) {
    const key = pre ? `${pre}:${k}` : k;
    if (v && typeof v === 'object' && !Array.isArray(v)) flat(v, key, out); else out[key.toLowerCase()] = v;
  }
  return out;
}
const fromFiles = {};
for (const f of files) {
  try { Object.assign(fromFiles, flat(JSON.parse(fs.readFileSync(f, 'utf8').replace(/^﻿/, '')))); }
  catch (e) { console.error(`tf-register-test-users: ${f} could not be read (${e.message})`); process.exit(2); }
}
const am = (k) => setting(`AppManager:${k}`) || String(fromFiles[`appmanager:${k.toLowerCase()}`] ?? '');
const baseUrl = am('BaseUrl').replace(/\/+$/, '');
const apiKey = am('ApiKey');
const appId = am('ApplicationId');
const deviceId = am('DeviceId') || 'techieflow-test-user-setup';

const users = Object.entries(testSettings().TestUsers || {})
  .filter(([, u]) => u && typeof u === 'object' && u.Email)
  .map(([n, u]) => ({ n, email: u.Email, first: u.FirstName || 'Test', last: u.LastName || `User${n}`, has: Boolean(u.Password) }));
if (!users.length) {
  console.error('tf-register-test-users: no TestUsers:<n>:Email in tests/verify/testsettings.json; list the usage guide\'s Test users there first');
  process.exit(2);
}
const todo = users.filter((u) => !u.has);
for (const u of users.filter((x) => x.has)) console.log(`${u.email}: already has a password in the settings, skipped`);
if (!todo.length) process.exit(0);
if (!baseUrl || !apiKey || !appId) {
  console.error(`tf-register-test-users: AppManager ${[!baseUrl && 'BaseUrl', !apiKey && 'ApiKey', !appId && 'ApplicationId'].filter(Boolean).join(', ')} not set; `
    + 'put them in tests/verify/testsettings.Local.json under "AppManager", or pass --appsettings <the app\'s settings or secrets file>');
  process.exit(2);
}
if (dry) {
  for (const u of todo) console.log(`${u.email}: would be registered on ${baseUrl} under application ${appId}; password into ${LOCAL_FILE} as TestUsers:${u.n}:Password`);
  process.exit(0);
}
const headers = { 'Content-Type': 'application/json', 'X-Api-Key': apiKey, 'X-Device-Id': deviceId };
let pem;
try {
  const r = await fetch(`${baseUrl}/AuthSvc/public-key`, { headers });
  const b = await r.json().catch(() => ({}));
  pem = b?.data?.publicKey;
  if (!pem) { console.error(`tf-register-test-users: the public key call answered ${r.status} ${b?.errorCode ?? ''}`.trim()); process.exit(1); }
} catch (e) { console.error(`tf-register-test-users: ${baseUrl} could not be reached (${e.message})`); process.exit(1); }

let failed = 0;
for (const u of todo) {
  const password = `${crypto.randomBytes(15).toString('base64url')}Aa7#`;   // AppManager's rule: every class of character
  const encryptedPassword = crypto.publicEncrypt({ key: pem, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' },
    Buffer.from(password, 'utf8')).toString('base64');
  const r = await fetch(`${baseUrl}/AuthSvc/register`, { method: 'POST', headers,
    body: JSON.stringify({ email: u.email, encryptedPassword, firstName: u.first, lastName: u.last, applicationId: appId }) });
  const b = await r.json().catch(() => ({}));
  if (r.ok && b.success !== false) {
    setLocal(`TestUsers:${u.n}:Email`, u.email);
    setLocal(`TestUsers:${u.n}:Password`, password);
    console.log(`${u.email}: registered (user id ${b?.data?.userId ?? '?'}); password written to ${LOCAL_FILE} as TestUsers:${u.n}:Password`);
  } else {
    failed += 1;
    console.log(`${u.email}: NOT registered — ${r.status} ${b.errorCode ?? ''} ${b.message ?? ''}`.trim());
  }
}
process.exit(failed ? 1 : 0);

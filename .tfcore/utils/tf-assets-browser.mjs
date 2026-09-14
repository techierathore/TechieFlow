// TechieFlow — the documents tf-assets.sh grades, fetched through a signed-in browser
// (AppManager TF-011, 2026-09-14). Driven by tf-assets.sh when --login-path is given; run that.
//
// tf-assets reads what a page DECLARES and fetches each asset. It fetched the page with a bare HTTP
// request, and an app whose sign-in lives in the page's own connection answers 401 to every bare
// request: "declared 0, graded 0" on every path. Here each path is opened in a browser tab that
// signed in through the page's form (tf-login.mjs), judged by what it draws, and its document — the
// head with every stylesheet and script it declares — handed back for grading. The assets themselves
// are still fetched one by one by tf-assets.sh, so a 404 stays observable.
//
//   node tf-assets-browser.mjs --base URL --paths "/a,/b" --login-path /login --user U --password P
//        [--storage-state file] [--cookie 'k=v'] --json-out <file>
// Writes {"login": {...}, "pages": {"/a": {"status": 401, "reached": "…", "signed_out": false,
// "url": "...", "html": "<!doctype…"}}}. Exit 0 always except a usage error (3).

import { chromium } from 'playwright';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { signIn, reach } from './tf-login.mjs';

const argv = process.argv.slice(2);
const arg = (name, dflt = null) => { const i = argv.indexOf(name); return i >= 0 && i + 1 < argv.length ? argv[i + 1] : dflt; };
const BASE = (arg('--base') || '').replace(/\/$/, '');
const PATHS = (arg('--paths', '/') || '').split(',').map((p) => p.trim()).filter(Boolean).map((p) => (p.startsWith('/') ? p : '/' + p));
const OUT = arg('--json-out');
const COOKIE = arg('--cookie'); const STORAGE = arg('--storage-state');
const LOGIN_OPTS = { base: BASE, loginPath: arg('--login-path'), user: arg('--user'), password: arg('--password'), settle: 1500, renderWait: 5000 };
if (!BASE || !OUT) { console.error('usage: tf-assets-browser.mjs --base URL --paths /a,/b --login-path /login --user U --password P --json-out file'); process.exit(3); }

const browser = await chromium.launch();
const ctxOpts = { ignoreHTTPSErrors: true };
if (STORAGE && existsSync(STORAGE)) ctxOpts.storageState = STORAGE;
const ctx = await browser.newContext(ctxOpts);
if (COOKIE) {
  const u = new URL(BASE);
  for (const pair of COOKIE.split(';')) {
    const [name, ...v] = pair.trim().split('=');
    if (name && v.length) await ctx.addCookies([{ name: name.trim(), value: v.join('='), domain: u.hostname, path: '/' }]);
  }
}
const page = await ctx.newPage();
const login = await signIn(page, LOGIN_OPTS);
const pages = {};
for (const p of PATHS) {
  const nav = await reach(page, LOGIN_OPTS, p);
  let html = '';
  if (nav.status && nav.status < 400 && !nav.signedOut) {
    try { html = await page.content(); } catch (e) { html = ''; }
  }
  pages[p] = { status: nav.status, document_status: nav.document_status ?? nav.status, url: nav.url || '',
               reached: nav.reached || '', signed_out: !!nav.signedOut, error: nav.error || '', html };
}
await browser.close();
mkdirSync(dirname(resolve(OUT)), { recursive: true });
writeFileSync(resolve(OUT), JSON.stringify({ login, pages }));

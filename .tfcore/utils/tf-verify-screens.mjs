// tf-verify-screens.mjs — drive every screen and check that it renders and looks right.
// Run through tf-verify-screens.sh, not directly. Sitting 4c, 2026-09-06.
//
// Two of the seven verify checks, over one browser session:
//   render  every control the mockup anchors (data-testid) is present and shows something; no
//           table with a header and no rows; no blank page; no Blazor error; no console error.
//   visual  no two visible controls overlap; no anchored control has zero size or sits off-screen;
//           no horizontal overflow; the page has a stylesheet.
// At every width it saves a full-page screenshot. Verdicts: render OK | EMPTY | ERROR | UNREACHABLE,
// visual OK | FAIL, each with its findings. Findings use the telemetry classes (blank-data,
// zero-rows, exception, overlap, clipped, offscreen, other). It writes a JSON file the verdict
// script reads and prints one line per screen. It never decides a row's status.
//
// Modes: --base URL (a served app, a new browser) or --cdp URL (attach to a running Blazor Hybrid
// app's WebView2 over its DevTools port; screens are reached by pushState, the way the router does).

import { chromium } from 'playwright';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const argv = process.argv.slice(2);
const arg = (n, d = null) => { const i = argv.indexOf(n); return i >= 0 && i + 1 < argv.length ? argv[i + 1] : d; };
const args = (n) => argv.flatMap((a, i) => (a === n && i + 1 < argv.length ? [argv[i + 1]] : []));

const BASE = (arg('--base') || '').replace(/\/$/, '');
const CDP = arg('--cdp') || '';
const LIST = arg('--list');
const MOCKUPS = arg('--mockups', 'docs/mockups');
const WIDTHS = (arg('--widths', '1280,390')).split(',').map((w) => parseInt(w.trim(), 10)).filter(Boolean);
const OUT = arg('--json-out', 'tests/.artifacts/verify/screens.json');
const SHOTS = arg('--shots-dir', 'tests/.artifacts/verify/screens');
const LOGIN_PATH = arg('--login-path');
const USER = arg('--user'); const PASS = arg('--password');
const COOKIE = arg('--cookie'); const STORAGE = arg('--storage-state');
const SETTLE = parseInt(arg('--wait', '1500'), 10);
const ATTR = arg('--testid-attr', 'data-testid');

if (!BASE && !CDP) { console.error('tf-verify-screens: --base URL or --cdp URL is required'); process.exit(3); }

// ---------------------------------------------------------------- screens
let screens = [];
if (LIST) {
  const l = JSON.parse(readFileSync(LIST, 'utf8'));
  screens = (l.screens || []).map((s) => ({ name: s.name, route: s.route, mockup: s.mockup || '', rows: s.rows || [] }));
}
for (const s of args('--screen')) {
  const m = s.match(/^([^=]+)=(.+)$/);
  if (m) screens.push({ name: m[1], route: m[2], mockup: `${MOCKUPS}/${m[1].toLowerCase().replace(/[^a-z0-9]+/g, '-')}.html`, rows: [] });
}
if (!screens.length) { console.error('tf-verify-screens: no screens (--list <json> or --screen name=/route)'); process.exit(3); }

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const anchorsOf = (mockup) => {
  if (!mockup || !existsSync(mockup)) return null;
  const html = readFileSync(mockup, 'utf8');
  const re = new RegExp(`${ATTR}\\s*=\\s*["']([^"']+)["']`, 'g');
  const out = new Set(); let m;
  while ((m = re.exec(html))) out.add(m[1]);
  return [...out];
};

// ---------------------------------------------------------------- browser
let browser, cdpPage = null;
if (CDP) {
  try { browser = await chromium.connectOverCDP(CDP, { timeout: 15000 }); }
  catch (e) { console.log(`UNREACHABLE cdp ${CDP}: ${e.message.split('\n')[0]}`); writeOut({ unreachable: true, error: e.message }); process.exit(2); }
  const ctx = browser.contexts()[0];
  cdpPage = ctx && ctx.pages()[0];
  if (!cdpPage) { console.log(`UNREACHABLE cdp ${CDP}: no page in the attached app`); writeOut({ unreachable: true }); process.exit(2); }
} else {
  browser = await chromium.launch();
}

function writeOut(extra, results = [], login = null) {
  const summary = {
    mode: CDP ? 'cdp' : 'base', base: BASE || CDP, widths: WIDTHS, login,
    screens: results,
    summary: {
      screens: results.length,
      render_ok: results.filter((r) => r.render === 'OK').length,
      render_fail: results.filter((r) => r.render === 'EMPTY' || r.render === 'ERROR').length,
      unreachable: results.filter((r) => r.render === 'UNREACHABLE').length,
      visual_ok: results.filter((r) => r.visual === 'OK').length,
      visual_fail: results.filter((r) => r.visual === 'FAIL').length,
    },
    ...extra,
  };
  mkdirSync(dirname(resolve(OUT)), { recursive: true });
  writeFileSync(OUT, JSON.stringify(summary, null, 2));
  return summary;
}

async function login(page) {
  if (!LOGIN_PATH || !USER) return { attempted: false };
  try {
    await page.goto(BASE + LOGIN_PATH, { waitUntil: 'domcontentloaded', timeout: 30000 });
    const user = page.locator(`[${ATTR}*="user" i], [${ATTR}*="email" i], input[type="email"], input[name*="user" i], input[name*="email" i], input[id*="user" i], input[id*="email" i], input[type="text"]`).first();
    const pass = page.locator(`[${ATTR}*="pass" i], input[type="password"]`).first();
    const btn = page.locator(`[${ATTR}*="login" i], [${ATTR}*="signin" i], [${ATTR}*="submit" i], button[type="submit"], form button, input[type="submit"]`).first();
    await user.fill(USER, { timeout: 10000 });
    await pass.fill(PASS || '', { timeout: 10000 });
    await Promise.all([page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {}), btn.click({ timeout: 10000 })]);
    await page.waitForTimeout(SETTLE);
    const url = page.url();
    const still = url.startsWith(BASE + LOGIN_PATH);
    return { attempted: true, ok: !still, url };
  } catch (e) {
    return { attempted: true, ok: false, error: e.message.split('\n')[0] };
  }
}

async function contextFor(width) {
  if (CDP) { await cdpPage.setViewportSize({ width, height: width < 600 ? 844 : 800 }).catch(() => {}); return { page: cdpPage, close: async () => {} }; }
  const opts = { viewport: { width, height: width < 600 ? 844 : 800 } };
  if (STORAGE && existsSync(STORAGE)) opts.storageState = STORAGE;
  const ctx = await browser.newContext(opts);
  if (COOKIE) {
    const u = new URL(BASE);
    await ctx.addCookies(COOKIE.split(';').map((kv) => { const [k, ...v] = kv.trim().split('='); return { name: k, value: v.join('='), domain: u.hostname, path: '/' }; }));
  }
  const page = await ctx.newPage();
  return { page, close: () => ctx.close() };
}

async function navigate(page, route) {
  if (CDP) {
    try {
      await page.evaluate((r) => { history.pushState({}, '', r); window.dispatchEvent(new PopStateEvent('popstate', { state: {} })); }, route);
      await page.waitForTimeout(SETTLE);
      return { status: 200, url: page.url() };
    } catch (e) { return { status: 0, error: e.message.split('\n')[0] }; }
  }
  try {
    const resp = await page.goto(BASE + route, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    await page.waitForTimeout(SETTLE);
    return { status: resp ? resp.status() : 0, url: page.url() };
  } catch (e) { return { status: 0, error: e.message.split('\n')[0] }; }
}

// what the page says about itself: anchors, tables, text, boxes
async function inspect(page, anchors, attr) {
  return page.evaluate(({ anchors, attr }) => {
    const vis = (el) => {
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden' || cs.opacity === '0') return false;
      if (el.getAttribute('aria-hidden') === 'true') return false;
      const r = el.getBoundingClientRect();
      if (r.width <= 1 && r.height <= 1 && cs.position === 'absolute') return false; // sr-only
      return true;
    };
    const sheetOk = (l) => { try { return !!l.sheet && l.sheet.cssRules.length > 0; } catch (e) { return !!l.sheet; } };
    const styled = [...document.querySelectorAll('link[rel~="stylesheet"]')].some(sheetOk)
      || [...document.querySelectorAll('style')].some(sheetOk);
    const failedSheets = [...document.querySelectorAll('link[rel~="stylesheet"]')].filter((l) => !l.sheet).map((l) => l.getAttribute('href'));
    const out = { anchors: [], tables: [], text_len: (document.body.innerText || '').trim().length, boxes: [],
      controls: document.querySelectorAll('input, select, textarea, img, svg, canvas, video').length,
      blazor_error: !!document.querySelector('#blazor-error-ui') && vis(document.querySelector('#blazor-error-ui')),
      overflow_x: document.documentElement.scrollWidth > document.documentElement.clientWidth + 2,
      styled, failed_sheets: failedSheets, vw: window.innerWidth, vh: window.innerHeight };
    for (const id of anchors || []) {
      const el = document.querySelector(`[${attr}="${CSS.escape(id)}"]`);
      if (!el) { out.anchors.push({ id, present: false }); continue; }
      const tag = el.tagName.toLowerCase();
      const r = el.getBoundingClientRect();
      const text = (el.innerText || el.value || el.getAttribute('aria-label') || '').trim();
      const filled = text.length > 0 || ['input', 'select', 'textarea', 'img', 'svg', 'canvas', 'video', 'iframe'].includes(tag) || el.querySelector('img,svg,canvas,input,select,textarea,button,a') !== null;
      out.anchors.push({ id, present: true, visible: vis(el), filled, tag, w: Math.round(r.width), h: Math.round(r.height), x: Math.round(r.left), y: Math.round(r.top) });
    }
    for (const t of document.querySelectorAll('table')) {
      if (!vis(t)) continue;
      const rows = t.querySelectorAll('tbody tr').length;
      const head = t.querySelector('thead') !== null;
      const cells = [...t.querySelectorAll('tbody td')].filter((c) => (c.innerText || '').trim().length > 0).length;
      out.tables.push({ id: t.getAttribute(attr) || t.id || '', rows, head, filled_cells: cells });
    }
    const sel = `[${attr}], a, button, input, select, textarea, [role="button"], h1, h2`;
    const els = [...document.querySelectorAll(sel)].filter(vis);
    els.forEach((el, i) => {
      const r = el.getBoundingClientRect();
      out.boxes.push({ i, id: el.getAttribute(attr) || '', tag: el.tagName.toLowerCase(), text: (el.innerText || el.value || '').trim().slice(0, 40),
        x: r.left, y: r.top, w: r.width, h: r.height, anchored: el.hasAttribute(attr) });
    });
    // ancestry so a button inside its card is never an "overlap"
    out.rel = [];
    for (let a = 0; a < els.length; a++) for (let b = a + 1; b < els.length; b++) {
      if (els[a].contains(els[b]) || els[b].contains(els[a])) out.rel.push([a, b]);
    }
    return out;
  }, { anchors, attr });
}

function grade(info, consoleErrors, width) {
  const findings = [];
  if (info.blazor_error) findings.push({ check: 'render', class: 'exception', detail: 'the Blazor error bar is showing' });
  // a failed fetch ("Failed to load resource … 404") is the assets check's finding, not a page error
  const pageErrors = consoleErrors.filter((e) => !/^Failed to load resource/i.test(e));
  for (const e of pageErrors.slice(0, 3)) findings.push({ check: 'render', class: 'exception', detail: `console error: ${e.slice(0, 120)}` });
  if (info.text_len < 15 && info.controls === 0 && !info.anchors.some((a) => a.present)) findings.push({ check: 'render', class: 'blank-data', detail: `the page is blank (${info.text_len} characters of text, no control)` });
  for (const a of info.anchors) {
    if (!a.present) findings.push({ check: 'render', class: 'blank-data', detail: `anchored control "${a.id}" is not on the page` });
    else if (a.visible && !a.filled) findings.push({ check: 'render', class: 'blank-data', detail: `anchored control "${a.id}" (${a.tag}) is empty` });
  }
  for (const t of info.tables) {
    if (t.head && t.rows === 0) findings.push({ check: 'render', class: 'zero-rows', detail: `table ${t.id || '(unnamed)'} has a header and no rows` });
    else if (t.rows > 0 && t.filled_cells === 0) findings.push({ check: 'render', class: 'blank-data', detail: `table ${t.id || '(unnamed)'} has ${t.rows} rows and every cell is blank` });
  }
  if (!info.styled) findings.push({ check: 'visual', class: 'other', detail: 'no stylesheet is loaded: the page is unstyled' + (info.failed_sheets.length ? ` (${info.failed_sheets.join(', ')} did not load)` : '') });
  if (info.overflow_x) findings.push({ check: 'visual', class: 'offscreen', detail: `the page scrolls sideways at ${width}px` });
  for (const a of info.anchors) {
    if (a.present && a.visible && (a.w === 0 || a.h === 0)) findings.push({ check: 'visual', class: 'clipped', detail: `anchored control "${a.id}" has zero ${a.w === 0 ? 'width' : 'height'}` });
    if (a.present && a.visible && a.w > 0 && (a.x + a.w > info.vw + 2 || a.x < -2)) findings.push({ check: 'visual', class: 'offscreen', detail: `anchored control "${a.id}" sits outside the viewport at ${width}px` });
  }
  const rel = new Set(info.rel.map(([a, b]) => `${a}-${b}`));
  const boxes = info.boxes.filter((b) => b.w > 0 && b.h > 0);
  let overlaps = 0;
  for (let i = 0; i < boxes.length && overlaps < 5; i++) for (let j = i + 1; j < boxes.length && overlaps < 5; j++) {
    const a = boxes[i], b = boxes[j];
    if (rel.has(`${a.i}-${b.i}`)) continue;
    const ix = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
    const iy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
    if (ix <= 4 || iy <= 4) continue;
    const inter = ix * iy, small = Math.min(a.w * a.h, b.w * b.h);
    if (inter / small > 0.9) continue;       // one lies inside the other by design (a badge on a card)
    if (inter / small < 0.25) continue;      // a touch, not an overlap
    overlaps++;
    const nm = (e) => e.id || `${e.tag} "${e.text || ''}"`;
    findings.push({ check: 'visual', class: 'overlap', detail: `${nm(a)} overlaps ${nm(b)} at ${width}px` });
  }
  const render = findings.some((f) => f.check === 'render' && f.class === 'exception') ? 'ERROR'
    : findings.some((f) => f.check === 'render') ? 'EMPTY' : 'OK';
  const visual = findings.some((f) => f.check === 'visual') ? 'FAIL' : 'OK';
  return { render, visual, findings };
}

// ---------------------------------------------------------------- run
mkdirSync(SHOTS, { recursive: true });
const results = [];
let loginResult = null;
let firstUnreachable = false;
for (const width of WIDTHS) {
  const { page, close } = await contextFor(width);
  const consoleErrors = [];
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
  page.on('pageerror', (e) => consoleErrors.push(String(e.message || e)));
  if (!CDP) { const l = await login(page); if (loginResult === null) loginResult = l; }
  for (const s of screens) {
    let r = results.find((x) => x.name === s.name);
    if (!r) { r = { name: s.name, route: s.route, mockup: s.mockup, rows: s.rows, anchors: anchorsOf(s.mockup), widths: [] }; results.push(r); }
    consoleErrors.length = 0;
    const nav = await navigate(page, s.route);
    const shot = `${SHOTS}/${slug(s.name)}-${width}.png`;
    const entry = { width, url: nav.url || '', status: nav.status, screenshot: shot, console_errors: [] };
    const redirectedToLogin = LOGIN_PATH && nav.url && new URL(nav.url).pathname.startsWith(LOGIN_PATH) && !s.route.startsWith(LOGIN_PATH);
    if (nav.status === 0 || nav.status >= 400 || redirectedToLogin) {
      entry.render = 'UNREACHABLE'; entry.visual = 'n/a';
      entry.findings = [{ check: 'render', class: 'other', detail: nav.status === 0 ? `could not open ${s.route}: ${nav.error || 'no response'}` : redirectedToLogin ? `${s.route} redirected to the sign-in page (not signed in)` : `${s.route} answered HTTP ${nav.status}` }];
      if (nav.status === 0 && results.length === 1 && width === WIDTHS[0]) firstUnreachable = true;
    } else {
      const info = await inspect(page, r.anchors || [], ATTR);
      const g = grade(info, consoleErrors, width);
      Object.assign(entry, g);
      entry.console_errors = consoleErrors.slice(0, 5);
      entry.anchors_present = (info.anchors || []).filter((a) => a.present).length;
    }
    try { await page.screenshot({ path: shot, fullPage: !CDP }); } catch (e) { entry.screenshot = ''; }
    r.widths.push(entry);
  }
  await close();
}
for (const r of results) {
  const rs = r.widths.map((w) => w.render);
  r.render = rs.includes('UNREACHABLE') ? 'UNREACHABLE' : rs.includes('ERROR') ? 'ERROR' : rs.includes('EMPTY') ? 'EMPTY' : 'OK';
  r.visual = r.widths.some((w) => w.visual === 'FAIL') ? 'FAIL' : r.render === 'UNREACHABLE' ? 'n/a' : 'OK';
  r.anchors_n = (r.anchors || []).length;
  const notes = r.widths.flatMap((w) => (w.findings || []).map((f) => `${f.detail}`)).slice(0, 4);
  console.log(`${r.render === 'OK' && r.visual === 'OK' ? 'OK  ' : 'FAIL'} ${r.name} (${r.route}) — render ${r.render}, visual ${r.visual}, ${r.anchors_n} anchors${r.mockup && !existsSync(r.mockup) ? ' (no mockup file)' : ''}${notes.length ? ' — ' + notes.join('; ') : ''}`);
}
const out = writeOut({}, results, loginResult);
if (loginResult && loginResult.attempted && !loginResult.ok) console.log(`LOGIN failed at ${BASE}${LOGIN_PATH}: ${loginResult.error || 'still on the sign-in page'}`);
console.log(`screens ${out.summary.screens}: render ${out.summary.render_ok} OK / ${out.summary.render_fail} failed / ${out.summary.unreachable} unreachable; visual ${out.summary.visual_ok} OK / ${out.summary.visual_fail} failed; screenshots ${SHOTS}; JSON ${OUT}`);
if (!CDP) await browser.close(); else await browser.close().catch(() => {});
process.exit(firstUnreachable && out.summary.unreachable === out.summary.screens ? 2 : (out.summary.render_fail + out.summary.visual_fail + out.summary.unreachable) ? 5 : 0);

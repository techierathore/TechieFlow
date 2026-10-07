// tf-verify-native.mjs — the render and visual checks on a MAUI Mac Catalyst head, over Appium mac2.
// Run through tf-verify-screens.sh --appium <url>, not directly.
//
// The native twin of tf-verify-screens.mjs: the same list.json in, the same screens.json out (mode
// "appium"), so tf-verify-verdict.sh grades a Mac screen exactly as a web one. The mockup's
// data-testid anchors are looked for as AutomationId (the accessibility identifier the Mac shows).
//   render  every anchored control is present and shows something (text, a value, or content
//           inside it); an anchored list has rows; the window is not blank; no error bar.
//   visual  no two visible controls overlap; no anchored control has zero size or sits outside
//           the window. (A native window has no stylesheet and no sideways page scroll to check.)
// A web view head (Blazor Hybrid; boot.json webview, or --no-names): on a Mac neither data-testid
// nor an HTML id reaches mac2, so controls are not matched by name. Everything else runs: blank
// window, error bar (--error-text, repeatable; the defaults are the stock Blazor messages), overlap,
// and the screenshot. Each screen records anchors_not_measured, and the verdict says the name check
// was not measured (owner decision A, 2026-10-07).
// A screen is reached by clicking, inside the app, the control whose AutomationId is
// nav-<screen name> or, failing that, the tab, button, link or list item labelled with the screen's
// name; the first screen in the list may be the one the app opens on. The session opens the app by
// its .app path (boot.json app_path, or --app-path) when known, else by bundle id. A screen with no
// such control is UNREACHABLE and says what to add. The screenshot is the app's window alone (mac2's
// own screenshot is the whole display, other windows included). One window size: the app's own.
// --from-source a.xml,b.xml grades saved page sources instead of a running app (one screen per
// file, no screenshot): how the self-tests check the grading where there is no Mac.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, resolve } from 'node:path';
import { openSession, parseSource, descendants } from './tf-appium.mjs';

const argv = process.argv.slice(2);
const arg = (n, d = null) => { const i = argv.indexOf(n); return i >= 0 && i + 1 < argv.length ? argv[i + 1] : d; };
const args = (n) => argv.flatMap((a, i) => (a === n && i + 1 < argv.length ? [argv[i + 1]] : []));
const APPIUM = (arg('--appium') || '').replace(/\/$/, '');
const BOOT = arg('--boot', 'tests/.artifacts/verify/boot.json');
const boot = existsSync(BOOT) ? JSON.parse(readFileSync(BOOT, 'utf8')) : {};
const BUNDLE = arg('--bundle') || boot.bundle_id || '';
const APP_PATH = arg('--app-path') || boot.app_path || '';
const LIST = arg('--list');
const MOCKUPS = arg('--mockups', 'docs/mockups');
const OUT = arg('--json-out', 'tests/.artifacts/verify/screens.json');
const SHOTS = arg('--shots-dir', 'tests/.artifacts/verify/screens');
const RENDER_WAIT = parseInt(arg('--render-wait', '5000'), 10);
const SETTLE = parseInt(arg('--wait', '1500'), 10);   // after a click, before the first look
const ATTR = arg('--testid-attr', 'data-testid');
const FROM_SOURCE = (arg('--from-source') || '').split(',').filter(Boolean);
const NO_NAMES = argv.includes('--no-names') || boot.webview === true;
const ERROR_TEXTS = [...args('--error-text'), 'An unhandled error has occurred', 'An error has occurred. This application may no longer respond']
  .map((t) => t.toLowerCase());
if (!FROM_SOURCE.length && (!APPIUM || !(BUNDLE || APP_PATH))) { console.error('tf-verify-native: --appium URL and the app (boot.json from tf-verify-boot.sh, --bundle or --app-path) are required'); process.exit(3); }

let screens = [];
if (LIST) screens = (JSON.parse(readFileSync(LIST, 'utf8')).screens || []).map((s) => ({ name: s.name, route: s.route, mockup: s.mockup || '', rows: s.rows || [] }));
for (const s of args('--screen')) {
  const m = s.match(/^([^=]+)=(.*)$/);
  if (m) screens.push({ name: m[1], route: m[2], mockup: `${MOCKUPS}/${m[1].toLowerCase().replace(/[^a-z0-9]+/g, '-')}.html`, rows: [] });
}
if (FROM_SOURCE.length && !screens.length) screens = FROM_SOURCE.map((f) => ({ name: basename(f).replace(/\.xml$/, ''), route: '', mockup: '', rows: [] }));
if (!screens.length) { console.error('tf-verify-native: no screens (--list <json> or --screen name=route)'); process.exit(3); }

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const anchorsOf = (mockup) => {   // as tf-verify-screens.mjs: an attribute on an element, not in a style or script
  if (!mockup || !existsSync(mockup)) return null;
  const html = readFileSync(mockup, 'utf8').replace(/<!--[\s\S]*?-->/g, '').replace(/<(style|script)\b[\s\S]*?<\/\1\s*>/gi, '');
  const re = new RegExp(`<[^>]*?\\b${ATTR}\\s*=\\s*["']([^"']+)["']`, 'g');
  const out = new Set(); let m;
  while ((m = re.exec(html))) out.add(m[1]);
  return [...out];
};

const LISTS = new Set(['CollectionView', 'Table', 'Outline']);
const CHROME = new Set(['TabBar', 'Toolbar', 'NavigationBar', 'MenuBar', 'Menu']);
const LEAF = new Set(['Button', 'StaticText', 'TextField', 'SecureTextField', 'TextView', 'Image', 'CheckBox', 'Switch', 'Slider',
  'PopUpButton', 'ComboBox', 'Link', 'RadioButton', 'SegmentedControl', 'Stepper', 'DatePicker', 'ProgressIndicator', 'Cell']);
const WEB_CONTROLS = new Set(['Button', 'Link', 'TextField', 'SecureTextField', 'TextView', 'CheckBox', 'RadioButton', 'PopUpButton', 'ComboBox', 'Heading']);
const shows = (n) => [n.label, n.value, n.title].some((t) => (t || '').trim().length > 0);

function windowOf(nodes) { return nodes.find((n) => n.type === 'Window'); }
// chrome: bars, menus, and what sits directly on the window (its title, its three buttons)
function inChrome(nodes, n) {
  if (n.parent >= 0 && nodes[n.parent].type === 'Window') return true;
  for (let p = n.parent; p >= 0; p = nodes[p].parent) if (CHROME.has(nodes[p].type)) return true;
  return CHROME.has(n.type);
}

// the app has drawn something: text or a control in its content, the window's own title not counted
function hasContent(nodes) {
  const win = windowOf(nodes);
  return !!win && descendants(nodes, win.i).some((n) => !inChrome(nodes, n) && ((n.type === 'StaticText' && shows(n)) || (LEAF.has(n.type) && n.type !== 'StaticText')));
}

function grade(nodes, anchors) {
  const findings = [];
  const win = windowOf(nodes);
  const inside = win ? descendants(nodes, win.i) : [];
  const content = inside.filter((n) => !inChrome(nodes, n));
  const out = { anchors: [] };
  for (const id of NO_NAMES ? [] : anchors || []) {
    const n = inside.find((x) => x.id === id);
    if (!n) { out.anchors.push({ id, present: false }); findings.push({ check: 'render', class: 'blank-data', detail: `anchored control "${id}" is not on the screen (no AutomationId="${id}")` }); continue; }
    const sub = descendants(nodes, n.i);
    const lists = [n, ...sub].filter((x) => LISTS.has(x.type));
    const cells = sub.filter((x) => x.type === 'Cell').length;
    const filled = shows(n) || sub.some((x) => shows(x) || x.type === 'Cell' || x.type === 'Image' || x.type === 'TextField');
    out.anchors.push({ id, present: true, type: n.type, filled, x: n.x, y: n.y, w: n.w, h: n.h, rows: lists.length ? cells : undefined });
    if (lists.length && cells === 0) findings.push({ check: 'render', class: 'zero-rows', detail: `list "${id}" (${lists[0].type}) has no rows` });
    else if (!filled) findings.push({ check: 'render', class: 'blank-data', detail: `anchored control "${id}" (${n.type}) is empty` });
    if (n.w === 0 || n.h === 0) findings.push({ check: 'visual', class: 'clipped', detail: `anchored control "${id}" has zero ${n.w === 0 ? 'width' : 'height'}` });
    else if (win && (n.x < win.x - 2 || n.y < win.y - 2 || n.x + n.w > win.x + win.w + 2 || n.y + n.h > win.y + win.h + 2)) findings.push({ check: 'visual', class: 'offscreen', detail: `anchored control "${id}" sits outside the window` });
  }
  // the error bar: shown text naming the app's own crash (a hidden bar is not in the tree at all)
  const bar = content.find((n) => n.w > 0 && n.h > 0 && ERROR_TEXTS.some((t) => [n.label, n.value].some((v) => (v || '').toLowerCase().includes(t))));
  if (bar) findings.push({ check: 'render', class: 'exception', detail: `the application's error bar is showing ("${(bar.label || bar.value).slice(0, 80)}")` });
  if (!win) findings.push({ check: 'render', class: 'blank-data', detail: 'the app has no window open' });
  else if (!content.some((n) => (n.type === 'StaticText' && shows(n)) || (LEAF.has(n.type) && n.type !== 'StaticText'))) findings.push({ check: 'render', class: 'blank-data', detail: 'the window is blank (no text, no control)' });
  // overlap: visible leaf controls, never a control and one inside it; the same thresholds as the web
  // check, on the rectangle each one PAINTS in. The tree gives a text its full size even where its box
  // cuts it off: a table cell's comment, drawn as "Seeded approved…" in a 50 pt row, reported 170 pt
  // and "overlapped" the button under the table (Lekhak Comments, 2026-10-07). So each rectangle is
  // cut to every container's; the tree says nothing of overflow, so text that truly spills out of its
  // box is not seen here.
  const clip = (n) => {
    let x1 = n.x, y1 = n.y, x2 = n.x + n.w, y2 = n.y + n.h;
    for (let p = n.parent; p >= 0 && nodes[p].type !== 'Window'; p = nodes[p].parent) {
      const a = nodes[p]; if (a.w <= 0 || a.h <= 0) continue;
      x1 = Math.max(x1, a.x); y1 = Math.max(y1, a.y); x2 = Math.min(x2, a.x + a.w); y2 = Math.min(y2, a.y + a.h);
    }
    return { ...n, x: x1, y: y1, w: Math.max(0, x2 - x1), h: Math.max(0, y2 - y1) };
  };
  // In a web view plain text is not compared, as the web check compares controls only (links,
  // buttons, fields, headings): the tree does not say a box scrolls, so the lines of a scrolled log
  // report places under the next card (Lekhak AI Story Studio, 2026-10-07).
  const kinds = NO_NAMES ? WEB_CONTROLS : LEAF;
  const boxes = content.filter((n) => kinds.has(n.type) && n.w > 0 && n.h > 0).map(clip).filter((n) => n.w > 0 && n.h > 0);
  const anc = (a, b) => { for (let p = b.parent; p >= 0; p = nodes[p].parent) if (p === a.i) return true; return false; };
  let overlaps = 0;
  for (let i = 0; i < boxes.length && overlaps < 5; i++) for (let j = i + 1; j < boxes.length && overlaps < 5; j++) {
    const a = boxes[i], b = boxes[j];
    if (anc(a, b) || anc(b, a)) continue;
    const ix = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x), iy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
    if (ix <= 4 || iy <= 4) continue;
    const r = (ix * iy) / Math.min(a.w * a.h, b.w * b.h);
    if (r > 0.9 || r < 0.25) continue;
    overlaps++;
    const nm = (e) => e.id || `${e.type} "${(e.label || e.value || '').slice(0, 40)}"`;
    findings.push({ check: 'visual', class: 'overlap', detail: `${nm(a)} overlaps ${nm(b)}` });
  }
  const render = findings.some((f) => f.class === 'exception') ? 'ERROR' : findings.some((f) => f.check === 'render') ? 'EMPTY' : 'OK';
  const visual = findings.some((f) => f.check === 'visual') ? 'FAIL' : 'OK';
  return { render, visual, findings, anchors_present: out.anchors.filter((a) => a.present).length, window: win ? { w: win.w, h: win.h } : null };
}

function writeOut(results, extra = {}, width = 0) {
  const summary = {
    mode: 'appium', base: APPIUM, bundle_id: BUNDLE, widths: width ? [width] : [], login: null, screens: results, skipped: [],
    anchors_not_measured: NO_NAMES,
    summary: {
      screens: results.length, skipped: 0,
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

let s = null;
if (!FROM_SOURCE.length) {
  try { s = await openSession(APPIUM, { bundleId: BUNDLE, appPath: APP_PATH }); }
  catch (e) {
    console.log(`UNREACHABLE appium ${APPIUM} (${APP_PATH || BUNDLE}): ${e.message}`);
    console.log('  a mac2 session that cannot start is usually a permission: System Settings > Privacy & Security > Accessibility (the terminal, and WebDriverAgentRunner-Runner)');
    writeOut(screens.map((x) => ({ ...x, anchors: anchorsOf(x.mockup), render: 'UNREACHABLE', visual: 'n/a', widths: [{ width: 0, render: 'UNREACHABLE', visual: 'n/a', findings: [{ check: 'render', class: 'other', detail: `no Appium session: ${e.message}` }] }] })), { unreachable: true, error: e.message });
    process.exit(2);
  }
}

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
const q = (t) => t.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
async function reach(name, first) {
  const win = await s.find('-ios predicate string', 'elementType == 4').catch(() => null);
  // Button 9, RadioButton 10, Link 42 (a web view's menu), Cell 75
  for (const [using, value] of [['accessibility id', `nav-${slug(name)}`],
    ['-ios predicate string', `elementType IN {9, 10, 42, 75} AND label ==[c] '${q(name)}'`]]) {
    const el = await s.find(using, value, win).catch(() => null);
    if (el) { await s.click(el); await sleep(SETTLE); return { how: using === 'accessibility id' ? `clicked nav-${slug(name)}` : `clicked the control labelled "${name}"`, win }; }
  }
  return first ? { how: 'the screen the app opens on (no control named it)', win } : { how: '', win };
}

mkdirSync(SHOTS, { recursive: true });
const results = []; let width = 0;
for (const [i, sc] of screens.entries()) {
  const r = { name: sc.name, route: sc.route, mockup: sc.mockup, rows: sc.rows, anchors: anchorsOf(sc.mockup), widths: [] };
  if (NO_NAMES) r.anchors_not_measured = true;
  results.push(r);
  const shot = `${SHOTS}/${slug(sc.name)}-mac.png`;
  let entry;
  try {
    // the first screen: opening the session starts the app again, and a web view took about eight
    // seconds to draw its first page, menu included (2026-10-07). Wait for it before looking for the menu.
    if (s && i === 0) { const t1 = Date.now(); while (Date.now() - t1 < Math.max(RENDER_WAIT, 20000) && !hasContent(parseSource(await s.source()))) await sleep(300); }
    const nav = FROM_SOURCE.length ? { how: `saved source ${FROM_SOURCE[i]}` } : await reach(sc.name, i === 0);
    if (!nav.how) {
      entry = { width, url: '', status: 0, screenshot: '', render: 'UNREACHABLE', visual: 'n/a',
        findings: [{ check: 'render', class: 'other', detail: `no control reaches ${sc.name}: give its tab, flyout item, link or button AutomationId="nav-${slug(sc.name)}", or the label "${sc.name}"` }] };
    } else {
      const t0 = Date.now();
      const src = async () => parseSource(FROM_SOURCE.length ? readFileSync(FROM_SOURCE[i], 'utf8') : await s.source());
      let nodes = await src();
      const want = NO_NAMES ? [] : r.anchors || [];
      while (!FROM_SOURCE.length && Date.now() - t0 < RENDER_WAIT && !(want.length ? nodes.some((n) => want.includes(n.id)) : hasContent(nodes))) {
        await sleep(300); nodes = await src();
      }
      const g = grade(nodes, want);
      if (g.window) width = g.window.w;
      entry = { width: g.window ? g.window.w : 0, height: g.window ? g.window.h : 0, url: '', status: 200, reached: nav.how, render_wait_ms: Date.now() - t0,
        screenshot: FROM_SOURCE.length ? '' : shot, render: g.render, visual: g.visual, findings: g.findings, anchors_present: g.anchors_present, console_errors: [] };
      if (NO_NAMES) entry.anchors_not_measured = true;
      if (s) { try { writeFileSync(shot, Buffer.from(await s.shot(nav.win), 'base64')); } catch (e) { entry.screenshot = ''; } }
    }
  } catch (e) {
    entry = { width, url: '', status: 0, screenshot: '', render: 'UNREACHABLE', visual: 'n/a', findings: [{ check: 'render', class: 'other', detail: `Appium: ${e.message}` }] };
  }
  r.widths.push(entry);
  r.render = entry.render; r.visual = entry.visual; r.anchors_n = (r.anchors || []).length;
  const notes = (entry.findings || []).map((f) => f.detail).slice(0, 4);
  const names = NO_NAMES ? 'names not measured (web view)' : `${r.anchors_n} anchors${r.mockup && !existsSync(r.mockup) ? ' (no mockup file)' : ''}`;
  console.log(`${r.render === 'OK' && r.visual === 'OK' ? 'OK  ' : 'FAIL'} ${r.name} (${r.route}) — render ${r.render}, visual ${r.visual}, ${names}${notes.length ? ' — ' + notes.join('; ') : ''}`);
}
if (s) await s.close();
const out = writeOut(results, {}, width);
console.log(`screens ${out.summary.screens}: render ${out.summary.render_ok} OK / ${out.summary.render_fail} failed / ${out.summary.unreachable} unreachable; visual ${out.summary.visual_ok} OK / ${out.summary.visual_fail} failed${NO_NAMES ? '; control names not measured (web view)' : ''}; screenshots ${SHOTS}; JSON ${OUT}`);
process.exit(out.summary.unreachable === out.summary.screens ? 2 : (out.summary.render_fail + out.summary.visual_fail + out.summary.unreachable) ? 5 : 0);

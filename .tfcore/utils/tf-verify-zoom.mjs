// tf-verify-zoom.mjs — presses the OS zoom keys on a Blazor Hybrid head and measures what they did
// (coding-standards-dotnet.md §9b; Lekhak, 2026-10-11). Called by tf-verify-zoom.sh; see there.
//
// Mac (--appium): mac2 presses Cmd+= / Cmd+- / Cmd+0 as real keys, so they go through the menu bar the
// way a person's do; macOS takes the window alone after each. The accessibility tree does not follow a
// WKWebView's page zoom (its text heights stayed 13 px at 130% on BlogAdmin), so the level is measured
// from the pictures: the scale that best maps the actual-size picture onto the zoomed one, from the
// first row where the two differ (the web view's top edge; the title bar above it does not zoom).
// Windows and any Chromium web view (--cdp): Playwright presses Ctrl+= / Ctrl+- / Ctrl+0 in the page
// and reads the zoom it paints at (CSS zoom on <html> times the device pixel ratio).

import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { inflateSync } from 'node:zlib';
import { join } from 'node:path';

const args = process.argv.slice(2);
const opt = (k, d = '') => { const i = args.indexOf(k); return i >= 0 && i + 1 < args.length ? args[i + 1] : d; };
const flag = (k) => args.includes(k);
const OUT = opt('--out', 'tests/.artifacts/verify/zoom');
const LEAVE = parseInt(opt('--leave', '0'), 10) || 0;
const STEPS = [
  // what is pressed, how often, the level expected afterwards (1.0 = actual size)
  { key: 'reset', n: 1, want: 1.0, say: 'actual size' },
  { key: 'in', n: 3, want: 1.3, say: 'zoom in 3 times' },
  { key: 'out', n: 1, want: 1.2, say: 'zoom out once' },
  { key: 'reset', n: 1, want: 1.0, say: 'actual size again' },
];
const TOL = 0.05;

// ---- PNG, 8-bit RGB or RGBA, not interlaced: what screencapture and sips write -------------------
export function decodePng(buf) {
  let p = 8, w = 0, h = 0, ct = 0; const idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p); const type = buf.toString('latin1', p + 4, p + 8);
    const data = buf.subarray(p + 8, p + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); ct = data[9]; if (data[8] !== 8 || data[12]) throw new Error('only 8-bit, non-interlaced PNG'); }
    if (type === 'IDAT') idat.push(data);
    if (type === 'IEND') break;
    p += 12 + len;
  }
  const bpp = ct === 6 ? 4 : ct === 2 ? 3 : ct === 0 ? 1 : ct === 4 ? 2 : 0;
  if (!bpp) throw new Error(`PNG colour type ${ct} not read`);
  const raw = inflateSync(Buffer.concat(idat)); const stride = w * bpp;
  const px = Buffer.alloc(h * stride); const gray = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)]; const src = y * (stride + 1) + 1; const row = y * stride;
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? px[row + x - bpp] : 0; const b = y ? px[row - stride + x] : 0; const c = x >= bpp && y ? px[row - stride + x - bpp] : 0;
      let v = raw[src + x];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const pp = a + b - c; const pa = Math.abs(pp - a), pb = Math.abs(pp - b), pc = Math.abs(pp - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      px[row + x] = v & 255;
    }
    for (let x = 0; x < w; x++) { const o = row + x * bpp; gray[y * w + x] = bpp >= 3 ? 0.299 * px[o] + 0.587 * px[o + 1] + 0.114 * px[o + 2] : px[o]; }
  }
  return { w, h, gray };
}

// a picture shrunk to 640 px wide by sips (macOS), so the search stays quick
function load(file) {
  const small = file.replace(/\.png$/, '.small.png');
  try { execFileSync('sips', ['-Z', '1000', file, '--out', small], { stdio: 'ignore' }); } catch { /* not macOS: read it whole */ }
  return decodePng(readFileSync(existsSync(small) ? small : file));
}

// The page zoom that turns picture `base` (actual size) into picture `zoomed`. Page zoom scales every
// horizontal position from the web view's left edge, but not always vertical ones: a header or sidebar
// sized to the window height keeps its height (BlogAdmin's did), so a 2-D match read 121% for 130%.
// So the two pictures are compared across the window only: for each column, how much vertical edge
// (a border, a box side, the strokes of text) it holds below the title bar, and the scale that best
// lines the actual-size profile up with the zoomed one. The title bar is the rows the two share.
export function scaleBetween(zoomed, base) {
  const { w, h } = base; if (zoomed.w !== w || zoomed.h !== h) return { scale: 0, why: 'the two pictures differ in size' };
  let top = 0;
  for (; top < h; top++) { let d = 0; for (let x = 0; x < w; x++) d += Math.abs(zoomed.gray[top * w + x] - base.gray[top * w + x]); if (d / w > 2) break; }
  if (top >= h - 10) return { scale: 1, top, why: 'the pictures are the same' };
  const profile = (img) => {
    const p = new Float64Array(w);
    for (let y = top; y < h; y++) for (let x = 0; x + 1 < w; x++) p[x] += Math.abs(img.gray[y * w + x + 1] - img.gray[y * w + x]);
    return p;
  };
  const pz = profile(zoomed), pb = profile(base);
  let best = { scale: 0, r: -2 };
  for (let s = 0.5; s <= 3.0001; s += 0.01) {
    let n = 0, sa = 0, sb = 0, saa = 0, sbb = 0, sab = 0;
    for (let x = 0; x < w; x++) {
      const bx = x / s; const i = Math.floor(bx); if (i + 1 >= w) break;
      const a = pz[x], b = pb[i] + (pb[i + 1] - pb[i]) * (bx - i);
      n++; sa += a; sb += b; saa += a * a; sbb += b * b; sab += a * b;
    }
    if (n < w / 4) continue;
    const r = (sab - (sa * sb) / n) / Math.sqrt(Math.max(1e-9, (saa - (sa * sa) / n) * (sbb - (sb * sb) / n)));
    if (r > best.r) best = { scale: Math.round(s * 100) / 100, r };
  }
  return { scale: best.scale, top };
}

const RESULT = { checks: [], kept_checked: false, head: '', evidence: '' };
const line = (ok, text) => { console.log(`${ok ? 'OK  ' : 'FAIL'} ${text}`); RESULT.checks.push({ ok, text }); return ok; };

async function mac() {
  const { openSession, parseSource, appPid, windowShot } = await import('./tf-appium.mjs');
  let boot = {}; try { boot = JSON.parse(readFileSync('tests/.artifacts/verify/boot.json', 'utf8')); } catch { /* flags only */ }
  const appPath = opt('--app', boot.app_path || ''); const bundleId = opt('--bundle', boot.bundle || '');
  let s;
  try { s = await openSession(opt('--appium'), { bundleId, appPath }); }
  catch (e) { line(false, `no session on the app at ${opt('--appium')}: ${e.message} (boot it with bash .tfcore/utils/tf-verify-boot.sh start --head maccatalyst)`); return 2; }
  const pid = appPid(appPath);
  let ok = true; let k = 0;
  const shot = (name, same = false) => { const f = join(OUT, `${String(same ? k : k++).padStart(2, '0')}-${name}-mac.png`); return windowShot(pid, f) ? f : ''; };
  const press = async (key) => {
    await s.call('POST', '/execute/sync', { script: 'macos: keys', args: [{ keys: [{ key: { in: '=', out: '-', reset: '0' }[key], modifierFlags: 1 << 4 }] }] });
    await new Promise((r) => setTimeout(r, 700));
  };
  // the View menu names the three commands
  const nodes = parseSource(await s.source());
  const view = nodes.find((n) => n.type === 'MenuBarItem' && /^view$/i.test(n.title || n.label));
  const items = []; if (view) { const todo = [...view.kids]; while (todo.length) { const n = nodes[todo.shift()]; if (n.type === 'MenuItem') items.push(n.title || n.label); todo.push(...n.kids); } }
  const missing = ['Zoom In', 'Zoom Out', 'Actual Size'].filter((t) => !items.includes(t));
  ok = line(!missing.length, missing.length ? `the View menu has no ${missing.join(', ')} (it has: ${items.filter(Boolean).join(', ') || 'no View menu'})` : 'View › Zoom In, Zoom Out, Actual Size are in the menu bar') && ok;
  // A mac2 session starts the app again: wait for a drawn page that holds still for two pictures
  // (the first ones on BlogAdmin were the bare window while Blazor started)
  const ink = (f) => { const g = load(f); let e = 0; for (let i = 1; i < g.gray.length; i++) e += Math.abs(g.gray[i] - g.gray[i - 1]); return e / g.gray.length; };
  let opened = ''; let last = -1;
  for (let t = Date.now(); Date.now() - t < 60000;) {
    const f = shot('as-opened', true); const e = f ? ink(f) : 0;   // a bare window reads 0.04, a drawn page 0.96
    if (e > 0.2 && last > 0 && Math.abs(e - last) / last < 0.02) { opened = f; break; }
    last = e; await new Promise((r) => setTimeout(r, 1500));
  }
  k++;
  if (!opened) { await s.close(); line(false, 'the app showed no drawn page within 60 s'); return 2; }
  await press('reset'); const actual = shot('actual-size');
  if (!opened || !actual) { await s.close(); return line(false, 'could not take the window (the terminal needs Screen Recording)') ? 0 : 5; }
  RESULT.head = 'maccatalyst'; RESULT.evidence = actual;
  const base = load(actual);
  const restored = scaleBetween(load(opened), base).scale;
  console.log(`INFO opened at ${Math.round(restored * 100)}% (the level the last run left; run again after a restart with --leave 3 before it to check the level is kept)`);
  if (flag('--expect-restored')) RESULT.kept_checked = true;
  if (flag('--expect-restored')) ok = line(Math.abs(restored - parseFloat(opt('--expect-restored'))) <= TOL, `opened at ${Math.round(restored * 100)}%, expected ${Math.round(parseFloat(opt('--expect-restored')) * 100)}% from the last run`) && ok;
  for (const st of STEPS.slice(1)) {
    for (let i = 0; i < st.n; i++) await press(st.key);
    const f = shot(st.key); const got = f ? scaleBetween(load(f), base).scale : 0;
    ok = line(Math.abs(got - st.want) <= TOL, `${st.say} (Cmd+${{ in: '=', out: '-', reset: '0' }[st.key]}): ${Math.round(got * 100)}%, expected ${Math.round(st.want * 100)}%`) && ok;
  }
  for (let i = 0; i < LEAVE; i++) await press('in');
  if (LEAVE) console.log(`INFO left at ${100 + LEAVE * 10}% for the restart check`);
  await s.close();
  return ok ? 0 : 5;
}

async function cdp() {
  const { chromium } = await import('playwright');
  let browser;
  try { browser = await chromium.connectOverCDP(opt('--cdp')); }
  catch (e) { line(false, `nothing answers at ${opt('--cdp')}: ${e.message.split('\n')[0]}`); return 2; }
  const page = browser.contexts().flatMap((c) => c.pages()).find((p) => !p.url().startsWith('devtools:')) || null;
  if (!page) { line(false, 'no page to drive at ' + opt('--cdp')); return 2; }
  const level = () => page.evaluate(() => (parseFloat(getComputedStyle(document.documentElement).zoom) || 1) * window.devicePixelRatio);
  let ok = true; let k = 0;
  const press = async (key) => { await page.keyboard.press({ in: 'Control+Equal', out: 'Control+Minus', reset: 'Control+Digit0' }[key]); await page.waitForTimeout(400); };
  RESULT.head = 'cdp';
  const opened = await level(); await press('reset'); const base = await level();
  console.log(`INFO opened at ${Math.round((opened / base) * 100)}% (the level the last run left)`);
  if (flag('--expect-restored')) RESULT.kept_checked = true;
  if (flag('--expect-restored')) ok = line(Math.abs(opened / base - parseFloat(opt('--expect-restored'))) <= TOL, `opened at ${Math.round((opened / base) * 100)}%, expected ${Math.round(parseFloat(opt('--expect-restored')) * 100)}%`) && ok;
  for (const st of STEPS.slice(1)) {
    for (let i = 0; i < st.n; i++) await press(st.key);
    await page.screenshot({ path: join(OUT, `${String(k++).padStart(2, '0')}-${st.key}-cdp.png`) }).catch(() => {});
    const got = (await level()) / base;
    ok = line(Math.abs(got - st.want) <= TOL, `${st.say} (Ctrl+${{ in: '=', out: '-', reset: '0' }[st.key]}): ${Math.round(got * 100)}%, expected ${Math.round(st.want * 100)}%`) && ok;
  }
  // Ctrl+wheel up is one step in
  await page.mouse.move(200, 200); await page.keyboard.down('Control'); await page.mouse.wheel(0, -100); await page.keyboard.up('Control'); await page.waitForTimeout(400);
  const wheel = (await level()) / base;
  ok = line(Math.abs(wheel - 1.1) <= TOL, `Ctrl+wheel up: ${Math.round(wheel * 100)}%, expected 110%`) && ok;
  await press('reset');
  for (let i = 0; i < LEAVE; i++) await press('in');
  if (LEAVE) console.log(`INFO left at ${100 + LEAVE * 10}% for the restart check`);
  await browser.close().catch(() => {});
  return ok ? 0 : 5;
}

if (process.argv[1] && process.argv[1].endsWith('tf-verify-zoom.mjs')) {
  if (flag('--scale')) {           // tf-verify-zoom.mjs --scale <zoomed.png> <actual.png>: the measure alone
    console.log(scaleBetween(load(args[args.indexOf('--scale') + 1]), load(args[args.indexOf('--scale') + 2])).scale);
    process.exit(0);
  }
  mkdirSync(OUT, { recursive: true });
  const rc = flag('--appium') ? await mac() : flag('--cdp') ? await cdp() : (console.error('tf-verify-zoom: --appium <url> or --cdp <url>'), 3);
  if (opt('--json-out')) writeFileSync(opt('--json-out'), JSON.stringify({ ...RESULT, verdict: rc === 0 ? 'PASS' : 'FAIL' }, null, 1));
  process.exit(rc);
}

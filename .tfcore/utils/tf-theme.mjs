// tf-theme.mjs — draw a page in its light or its dark theme, and measure what a reader sees in it.
// Shared by tf-verify-screens and tf-mockup-parity, as tf-login.mjs is (Lekhak TF-024).
//
// Why: every screen was graded in light mode only. Lekhak's owner then found 20 of 20 desktop admin
// screens unreadable in dark mode (text at 1.03 : 1, white panels inside a dark shell), all Verified.
//
// A theme is put on a page the two ways a stack listens for one, knowing nothing about the stack:
//   - the browser's colour scheme (prefers-color-scheme), emulated;
//   - the light/dark value of every data-*theme/mode/scheme attribute on <html> and <body>, and the
//     light/dark mode classes there (dark, theme-dark …). A page that declares none is given
//     data-theme and data-bs-theme; a page with no such class is given, for dark, the class `dark`
//     (Tailwind's switch, and the one an app setting data-theme and the class together also reads).
// Each call returns a function that puts the page back the way it was: an attached desktop head is
// the viewer's app. A page whose painted surface does not change between the two has no dark theme;
// `surface` and `differs` tell. `audit` is the contrast rule the visual check applies.

export const THEMES = ['light', 'dark'];

// --themes light,dark | light | dark | auto (the default: light, and dark when the app has one)
export function parseThemes(v) {
  const s = String(v || 'auto').toLowerCase().trim();
  if (s === 'auto') return null;
  const t = [...new Set(s.split(',').map((x) => x.trim()).filter((x) => THEMES.includes(x)))];
  return t.length ? t : null;
}

const FORCE = (want) => {
  const MODE = /^(?:(?:theme|mode|scheme|color)[-_])?(?:dark|light)(?:[-_](?:theme|mode|scheme))?$/i;
  const other = want === 'dark' ? /light/ig : /dark/ig;
  const before = [];
  let declared = false, classed = false;
  for (const [where, el] of [['html', document.documentElement], ['body', document.body]]) {
    if (!el) continue;
    for (const a of [...el.attributes]) {
      if (!/^data-.*(theme|mode|scheme)/i.test(a.name) || !/(dark|light)/i.test(a.value)) continue;
      declared = true;
      before.push({ where, attr: a.name, value: a.value });
      el.setAttribute(a.name, a.value.replace(other, want));
    }
    const toks = [...el.classList].filter((c) => MODE.test(c));
    if (toks.length) {
      declared = classed = true;
      before.push({ where, cls: toks });
      for (const c of toks) { el.classList.remove(c); el.classList.add(c.replace(other, want)); }
    }
  }
  if (!declared) {
    const h = document.documentElement;
    for (const name of ['data-theme', 'data-bs-theme']) {
      if (h.hasAttribute(name)) continue;            // a theme by name (data-theme="corporate") is left alone
      before.push({ where: 'html', attr: name, value: null });
      h.setAttribute(name, want);
    }
  }
  // a page with no light/dark class gets `dark` for the dark pass even when it declared data-theme:
  // an app whose switch sets both (Lekhak) was otherwise drawn half dark, a state it never shows (Lekhak TF-033)
  const h = document.documentElement;
  if (want === 'dark' && !classed && !h.classList.contains('dark')) { before.push({ where: 'html', added: 'dark' }); h.classList.add('dark'); }
  return before;
};

const RESTORE = (before) => {
  for (const b of [...before].reverse()) {
    const el = b.where === 'body' ? document.body : document.documentElement;
    if (!el) continue;
    if (b.added) el.classList.remove(b.added);
    else if (b.cls) {
      for (const c of [...el.classList]) if (/^(?:(?:theme|mode|scheme|color)[-_])?(?:dark|light)(?:[-_](?:theme|mode|scheme))?$/i.test(c)) el.classList.remove(c);
      for (const c of b.cls) el.classList.add(c);
    } else if (b.value === null) el.removeAttribute(b.attr);
    else el.setAttribute(b.attr, b.value);
  }
};

const SETTLE_ANIMATIONS = () => {
  let n = 0;
  for (const a of document.getAnimations()) {   // getAnimations() flushes style, so a fade the change just started is in it
    try { if (Number.isFinite(a.effect?.getComputedTiming().endTime)) { a.finish(); n++; } } catch (e) { /* not finishable */ }
  }
  return n;
};

// Draws the page in `want` and returns the function that puts it back.
export async function useTheme(page, want, settle = 350) {
  await page.emulateMedia({ colorScheme: want }).catch(() => {});
  const before = await page.evaluate(FORCE, want).catch(() => null);
  if (settle) await page.waitForTimeout(settle);
  // Sevak TF-007: a theme change starts the page's CSS fades (`transition: all .12s`), and the mockup,
  // read with no settle, gave its light colour in dark mode. Every fade and finite animation is run to
  // its end, so what is read is the colour the page settles on; a spinner (infinite) is left running.
  await page.evaluate(SETTLE_ANIMATIONS).catch(() => {});
  return async () => {
    if (before) await page.evaluate(RESTORE, before).catch(() => {});
    await page.emulateMedia({ colorScheme: null }).catch(() => {});
  };
}

// The luminance painted at five points of the window (and behind <body>), 0 = black, 1 = white.
const SURFACE = () => {
  // the browser converts the colour, never a regex: a page themed in oklch() reads back as "oklch(…)",
  // which an rgb() pattern skipped, so every surface counted as white and no dark theme was seen (Sevak TF-005)
  const cv = document.createElement('canvas'); cv.width = cv.height = 1;
  const cx = cv.getContext('2d', { willReadFrequently: true });
  const parse = (c) => { if (!c || c === 'transparent' || !cx) return null; cx.clearRect(0, 0, 1, 1); cx.fillStyle = 'rgba(0,0,0,0)'; cx.fillStyle = String(c); cx.fillRect(0, 0, 1, 1); const d = cx.getImageData(0, 0, 1, 1).data; return [d[0], d[1], d[2], d[3] / 255]; };
  const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); };
  const behind = (el) => {
    const layers = [];
    for (let e = el; e; e = e.parentElement) { const c = parse(getComputedStyle(e).backgroundColor); if (c && c[3] > 0) { layers.push(c); if (c[3] >= 0.99) break; } }
    let out = layers.length && layers[layers.length - 1][3] >= 0.99 ? layers.pop() : [255, 255, 255, 1];
    while (layers.length) { const t = layers.pop(), a = t[3]; out = [t[0] * a + out[0] * (1 - a), t[1] * a + out[1] * (1 - a), t[2] * a + out[2] * (1 - a), 1]; }
    return out;
  };
  const w = window.innerWidth, h = window.innerHeight;
  const pts = [[0.5, 0.5], [0.2, 0.3], [0.8, 0.3], [0.2, 0.8], [0.8, 0.8]];
  return [document.body, ...pts.map(([x, y]) => document.elementFromPoint(x * w, y * h))].map((el) => (el ? +lum(behind(el)).toFixed(3) : null));
};
export const surface = (page) => page.evaluate(SURFACE).catch(() => null);
// two surface readings differ when any point's luminance moved by more than 0.15
export const differs = (a, b) => !!a && !!b && a.some((x, i) => x !== null && b[i] !== null && Math.abs(x - b[i]) > 0.15);
// a reading that is mostly dark: the theme a mockup that declares none is drawn in
export const looksDark = (s) => !!s && s.filter((x) => x !== null && x < 0.2).length > s.filter((x) => x !== null).length / 2;

// The contrast rule (Lekhak TF-024), measured on what is painted:
//   - every visible text run and form-field value reaches `min` : 1 (3.0, WCAG AA for large text)
//     against the first opaque background behind it; disabled controls are exempt, as WCAG exempts
//     them, and text over an image or a gradient is not measured (the colour behind it is not one);
//   - in dark mode, no box larger than 2% of the window paints a background lighter than 0.8
//     relative luminance (a white card or panel left in a dark shell).
// Returns { low: [...], light: [...], low_n, light_n }, each list cut to `cap`.
const AUDIT = ({ dark, min, cap }) => {
  const cv = document.createElement('canvas'); cv.width = cv.height = 1;   // oklch() and every other syntax, as SURFACE
  const cx = cv.getContext('2d', { willReadFrequently: true });
  const parse = (c) => { if (!c || c === 'transparent' || !cx) return null; cx.clearRect(0, 0, 1, 1); cx.fillStyle = 'rgba(0,0,0,0)'; cx.fillStyle = String(c); cx.fillRect(0, 0, 1, 1); const d = cx.getImageData(0, 0, 1, 1).data; return [d[0], d[1], d[2], d[3] / 255]; };
  const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); };
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const blend = (t, u) => { const a = t[3]; return [t[0] * a + u[0] * (1 - a), t[1] * a + u[1] * (1 - a), t[2] * a + u[2] * (1 - a), 1]; };
  const behind = (el) => {
    const layers = [];
    for (let e = el; e; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.backgroundImage && cs.backgroundImage !== 'none') return null;   // an image or a gradient
      const c = parse(cs.backgroundColor);
      if (c && c[3] > 0) { layers.push(c); if (c[3] >= 0.99) break; }
    }
    let out = layers.length && layers[layers.length - 1][3] >= 0.99 ? layers.pop() : [255, 255, 255, 1];
    while (layers.length) out = blend(layers.pop(), out);
    return out;
  };
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return false;
    for (let e = el; e; e = e.parentElement) {
      const s = getComputedStyle(e);
      if (s.display === 'none' || s.visibility === 'hidden' || Number(s.opacity) < 0.1) return false;
    }
    return r.bottom > 0 && r.right > 0;
  };
  const where = (el) => {
    const id = el.getAttribute('data-testid');
    const cls = String(el.getAttribute('class') || '').split(/\s+/).filter(Boolean).slice(0, 2).join('.');
    return `${el.tagName.toLowerCase()}${id ? `[data-testid=${id}]` : ''}${cls ? '.' + cls : ''}`;
  };
  const rgb = (c) => `rgb(${c.slice(0, 3).map(Math.round).join(',')})`;
  const EXEMPT = '[disabled],[aria-disabled="true"],svg,script,style,noscript,template';
  const low = [], light = [], seen = new Set();
  const measure = (el, text) => {
    const fg = parse(getComputedStyle(el).color);
    if (!fg || fg[3] < 0.05) return;
    const bg = behind(el);
    if (!bg) return;
    const r = ratio(blend(fg, bg), bg);
    const key = where(el) + '|' + text.slice(0, 30);
    if (r < min && !seen.has(key)) { seen.add(key); low.push({ text: text.slice(0, 40), fg: rgb(fg), bg: rgb(bg), ratio: Math.round(r * 100) / 100, where: where(el) }); }
  };
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const text = (n.textContent || '').trim();
    const el = n.parentElement;
    if (!text || !el || !/[\p{L}\p{N}]/u.test(text) || el.closest(EXEMPT) || !visible(el)) continue;   // icon glyphs are not text a reader reads
    measure(el, text);
  }
  for (const el of document.querySelectorAll('input:not([type=checkbox]):not([type=radio]):not([type=range]):not([type=hidden]):not([type=color]),textarea,select')) {
    if (el.disabled || el.closest(EXEMPT) || !visible(el)) continue;
    const text = String(el.value || '').trim();
    if (text) measure(el, text);
  }
  if (dark) {
    const area = window.innerWidth * window.innerHeight, flagged = [];
    for (const el of document.querySelectorAll('body *')) {
      if (el.closest('img,svg,video,canvas,picture,iframe') || flagged.some((f) => f.contains(el)) || !visible(el)) continue;
      const c = parse(getComputedStyle(el).backgroundColor);
      if (!c || c[3] < 0.5) continue;
      const r = el.getBoundingClientRect();
      const shown = Math.max(0, Math.min(r.right, window.innerWidth) - Math.max(r.left, 0)) * Math.max(0, Math.min(r.bottom, window.innerHeight) - Math.max(r.top, 0));
      if (shown / area > 0.02 && lum(c) > 0.8) { flagged.push(el); light.push({ bg: rgb(c), share: Math.round(shown / area * 100), where: where(el), text: (el.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 40) }); }
    }
  }
  low.sort((a, b) => a.ratio - b.ratio);
  return { low: low.slice(0, cap), light: light.slice(0, cap), low_n: low.length, light_n: light.length };
};
export const audit = (page, dark, min = 3.0, cap = 5) => page.evaluate(AUDIT, { dark, min, cap }).catch(() => null);

// ---- Sevak TF-018: a mockup control that belongs to a later phase -------------------------------------
// A mockup draws the whole screen, the parts a later phase builds included (Sevak's sidebar draws the
// phase 5 screens' nav items in phase 4). Each was reported "not on the page", and the only excuses were
// marks that say something else (data-tf-state) on a file a build may not edit. The mockups task now
// writes data-tf-phase="<n>" on such a control or on a box around it. While the phase being graded is
// lower than n, the mark is read as another state of the screen: the control is not owed, and when the
// app draws it anyway it is graded like any other. From phase n on the mark means nothing.
// gradedPhase: --phase N, else the phase in the list.json given or the one tf-verify-list.sh last wrote,
// else appPhase in .tfcore/core-config.yaml; null when none says (then every control is owed).
import { existsSync as tfExists, readFileSync as tfRead } from 'node:fs';
export function gradedPhase(argPhase, listPath) {
  const n = (v) => { const x = parseInt(v, 10); return Number.isFinite(x) && x > 0 ? x : null; };
  if (n(argPhase)) return n(argPhase);
  for (const f of [listPath, 'tests/.artifacts/verify/list.json']) {
    if (!f || !tfExists(f)) continue;
    try { const p = n(JSON.parse(tfRead(f, 'utf8')).phase); if (p) return p; } catch (e) { /* next source */ }
    if (f === listPath) break;   // a list that was named and says no phase: do not read another run's
  }
  try {
    const m = tfRead('.tfcore/core-config.yaml', 'utf8').match(/^appPhase:\s*["']?(\d+)/m);
    if (m) return n(m[1]);
  } catch (e) { /* no config here */ }
  return null;
}
// run on a mockup page right after it loads; returns how many controls it marked
export const markLaterPhase = (page, phase) => (phase === null || phase === undefined ? Promise.resolve(0)
  : page.evaluate((ph) => {
    let n = 0;
    for (const el of document.querySelectorAll('[data-tf-phase]')) {
      const of = parseInt(el.getAttribute('data-tf-phase'), 10);
      if (Number.isFinite(of) && of > ph && !el.hasAttribute('data-tf-state')) { el.setAttribute('data-tf-state', `phase-${of}`); el.setAttribute('data-tf-later', ''); n++; }
    }
    return n;
  }, phase).catch(() => 0));
// A later phase's box the app already draws is no other state (TrStudio TF-003): left marked on the mockup
// only, it drops out of the mockup's sibling count while the app's copy is still counted, and every box after
// it is paired with its neighbour. The app draws it when it holds the box's own anchor (or one inside it); a
// box with no anchor, when the anchor around it holds a box of the same tag and the same text. Those boxes are
// unmarked on the mockup page; returns how many, so the caller reads the mockup again.
export const laterReached = async (mockPage, appPage) => {
  const boxes = await mockPage.evaluate(() => {
    const t = (el) => (el.textContent || '').replace(/\s+/g, ' ').trim();
    return [...document.querySelectorAll('[data-tf-later]')].map((el) => ({
      ids: [el, ...el.querySelectorAll('[data-testid]')].map((x) => x.getAttribute('data-testid')).filter(Boolean),
      tag: el.tagName, text: t(el), anchor: el.parentElement?.closest('[data-testid]')?.getAttribute('data-testid') || null }));
  }).catch(() => []);
  if (!boxes.length) return 0;
  const drawn = await appPage.evaluate((bs) => {
    const seen = (el) => !!el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
    const t = (el) => (el.textContent || '').replace(/\s+/g, ' ').trim();
    const by = (id) => document.querySelector(`[data-testid="${CSS.escape(id)}"]`);
    return bs.map((b) => (b.ids.length ? b.ids.some((id) => seen(by(id)))
      : !!b.text && !!b.anchor && [...(by(b.anchor)?.querySelectorAll(b.tag) || [])].some((x) => seen(x) && t(x) === b.text)));
  }, boxes).catch(() => boxes.map(() => false));
  if (!drawn.some(Boolean)) return 0;
  return mockPage.evaluate((d) => {
    let n = 0;
    [...document.querySelectorAll('[data-tf-later]')].forEach((el, i) => { if (d[i]) { el.removeAttribute('data-tf-state'); el.removeAttribute('data-tf-later'); n++; } });
    return n;
  }, drawn).catch(() => 0);
};

// ---- the mockup check's site theme: read from the mockup, put on the app, put back (tf-mockup-parity.mjs) ----
// The theme a page declares: data-* attributes on <html> and <body> whose name says theme, mode or
// scheme (data-theme, data-bs-theme, data-site-theme, data-color-mode …), and the class tokens there
// that name a light or dark mode (dark, light, theme-dark, dark-mode …), which a class-driven dark mode
// such as Tailwind's `dark` uses. A utility class such as bg-light does not count.
// Nothing about any one stack. The class tokens are kept under `<where>|class`, '' when there are none.
export const READ_THEME = () => {
  const MODE = /^(?:(?:theme|mode|scheme|color)[-_])?(?:dark|light)(?:[-_](?:theme|mode|scheme))?$/i;
  const out = {};
  for (const [where, el] of [['html', document.documentElement], ['body', document.body]]) {
    if (!el) continue;
    for (const a of el.attributes) if (/^data-.*(theme|mode|scheme)/i.test(a.name)) out[`${where}|${a.name}`] = a.value;
    out[`${where}|class`] = [...el.classList].filter((c) => MODE.test(c)).join(' ');
  }
  return out;
};
// A page declares a theme when it has such an attribute or mode class. A mockup that declares none
// leaves the app as it is.
export const DECLARES_THEME = (t) => !!t && Object.entries(t).some(([k, v]) => !k.endsWith('|class') || v);
// Sets those attributes and mode classes on this page; returns what it had, so the same call puts it
// back. An attribute the page lacked is removed again on the way back (value null). For `|class` the
// page's own mode tokens are replaced by the given ones; every other class is left alone.
export const APPLY_THEME = (t) => {
  const MODE = /^(?:(?:theme|mode|scheme|color)[-_])?(?:dark|light)(?:[-_](?:theme|mode|scheme))?$/i;
  const before = {}; let changed = false;
  for (const [k, v] of Object.entries(t || {})) {
    const [where, name] = k.split('|');
    const el = where === 'body' ? document.body : document.documentElement;
    if (!el) continue;
    if (name === 'class') {
      const had = [...el.classList].filter((c) => MODE.test(c));
      const want = String(v || '').split(/\s+/).filter(Boolean);
      before[k] = had.join(' ');
      if (had.slice().sort().join(' ') !== want.slice().sort().join(' ')) changed = true;
      for (const c of had) el.classList.remove(c);
      for (const c of want) el.classList.add(c);
      continue;
    }
    const had = el.getAttribute(name);
    before[k] = had;
    if (had !== v) changed = true;
    if (v === null) el.removeAttribute(name); else el.setAttribute(name, v);
  }
  return { before, changed };
};

// ---- the screen check's mockup helper (tf-verify-screens.mjs) ----
import { pathToFileURL } from 'node:url';
// The anchors a mockup HIDES at one width and shows at another: a sidebar that becomes a slide-out
// menu on a phone is not owed at 390px. Worked out by drawing the mockup itself at each width. An
// anchor the mockup hides at every width -- a closed dialog -- is still owed. None is excused when
// the mockup cannot be drawn.
export async function hiddenByWidth(b, mockup, anchors, WIDTHS, ATTR) {
  const out = {};
  if (!b || !mockup || !tfExists(mockup) || !anchors || !anchors.length) return out;
  const shown = {};
  for (const width of WIDTHS) {
    let ctx;
    try {
      ctx = await b.newContext({ viewport: { width, height: width < 600 ? 844 : 800 } });
      const p = await ctx.newPage();
      await p.goto(pathToFileURL(mockup).href, { waitUntil: 'load', timeout: 15000 });
      shown[width] = await p.evaluate(({ anchors, attr }) => anchors.filter((id) => {
        const el = document.querySelector(`[${attr}="${CSS.escape(id)}"]`);
        if (!el) return false;
        const r = el.getBoundingClientRect();
        const seen = el.checkVisibility ? el.checkVisibility({ visibilityProperty: true, opacityProperty: true }) : true;
        return seen && r.width > 0 && r.height > 0;
      }), { anchors, attr: ATTR });
    } catch (e) { return {}; } finally { if (ctx) await ctx.close().catch(() => {}); }
  }
  const everShown = new Set(Object.values(shown).flat());
  for (const width of WIDTHS) out[width] = anchors.filter((id) => everShown.has(id) && !shown[width].includes(id));
  return out;
}

// The anchors a mockup marks as belonging to another state of the screen: a reason
// shown only while the database is down, a result shown only after "Test". The mockup says so with
// data-tf-state="<state>" (or data-state-testid="<id>") on the control or on a box around it. Such a control is not owed on the
// first view; when it is drawn and visible it is graded like any other. A control on a box marked
// data-tf-sample (a sample row a fresh app has no data for) is treated the same way.
export async function stateOnlyOf(b, mockup, anchors, PHASE, ATTR) {
  if (!mockup || !tfExists(mockup) || !anchors || !anchors.length) return [];
  if (b) {
    let ctx;
    try {
      ctx = await b.newContext();
      const p = await ctx.newPage();
      await p.goto(pathToFileURL(mockup).href, { waitUntil: 'load', timeout: 15000 });
      await markLaterPhase(p, PHASE);   // a later phase's control is another state until its phase
      return await p.evaluate(({ anchors, attr }) => anchors.filter((id) => {
        const el = document.querySelector(`[${attr}="${CSS.escape(id)}"]`);
        return !!el && !!el.closest('[data-tf-state],[data-state-testid],[data-tf-sample]');
      }), { anchors, attr: ATTR });
    } catch (e) { /* fall through to the mark on the control itself */ } finally { if (ctx) await ctx.close().catch(() => {}); }
  }
  const html = tfRead(mockup, 'utf8');
  const later = (id) => {   // data-tf-phase on the control's own tag, read without a browser
    const m = html.match(new RegExp(`<[^>]*\\b${ATTR}\\s*=\\s*["']${id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}["'][^>]*>`));
    const ph = m && m[0].match(/\bdata-tf-phase\s*=\s*["']?(\d+)/);
    return !!ph && PHASE !== null && parseInt(ph[1], 10) > PHASE;
  };
  return anchors.filter((id) => later(id) || new RegExp(`<[^>]*\\bdata-(?:tf-state|state-testid|tf-sample)\\b[^>]*\\b${ATTR}\\s*=\\s*["']${id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}["']|<[^>]*\\b${ATTR}\\s*=\\s*["']${id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}["'][^>]*\\bdata-(?:tf-state|state-testid|tf-sample)\\b`).test(html));
}

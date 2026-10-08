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
//     data-theme, data-bs-theme and, for dark, the class `dark` (Tailwind's switch).
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
  let declared = false;
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
      declared = true;
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
    if (want === 'dark' && !h.classList.contains('dark')) { before.push({ where: 'html', added: 'dark' }); h.classList.add('dark'); }
  }
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

// Draws the page in `want` and returns the function that puts it back.
export async function useTheme(page, want, settle = 350) {
  await page.emulateMedia({ colorScheme: want }).catch(() => {});
  const before = await page.evaluate(FORCE, want).catch(() => null);
  if (settle) await page.waitForTimeout(settle);
  return async () => {
    if (before) await page.evaluate(RESTORE, before).catch(() => {});
    await page.emulateMedia({ colorScheme: null }).catch(() => {});
  };
}

// The luminance painted at five points of the window (and behind <body>), 0 = black, 1 = white.
const SURFACE = () => {
  const parse = (c) => { const m = String(c).match(/rgba?\(([^)]+)\)/); if (!m) return null; const p = m[1].split(/[ ,/]+/).filter(Boolean).map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; };
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
  const parse = (c) => { const m = String(c).match(/rgba?\(([^)]+)\)/); if (!m) return null; const p = m[1].split(/[ ,/]+/).filter(Boolean).map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; };
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

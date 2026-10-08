// TechieFlow — mockup-parity gate. Feeds verify-phase §4b2.
//
// Driven by tf-mockup-parity.sh; run that, not this.
//
// WHAT IT ASKS: "does the built screen carry the structure its approved mockup
// draws?" — mechanically, at the same viewports, comparing STRUCTURE and never
// pixels. Pixel diffing on live data is unusable and would be switched off within
// a week; that is why this grades named structural classes instead.
//
// THE FOUR DEFECTS THIS IMPLEMENTATION IS BUILT AROUND (TfLens TF-008/009/011/012).
// They are not four bugs — they are one shape seen four times: *a gate reports on
// what it happens to be able to reach, and reports success when it reaches nothing.*
//
//   TF-008  No gate compared a built screen to its design at all. §4a asks "does the
//           control show data?" (a badge rendered as bare text HAS text) and §4b asks
//           "does anything overlap?" (a header wrapped to two rows overlaps nothing).
//           13 of 14 screens carried structural drift with every gate green.
//
//   TF-009  The first implementation graded six classes and `border-style` was in
//           none of them, so a card lost its dashed "this is an estimate" treatment
//           and passed: a dashed grey border and a solid grey border land in the same
//           semantic COLOUR bucket. -> the `stroke` clause below.
//
//   TF-011  Depth was bounded by how many data-testid anchors the MOCKUP happened to
//           carry, and the gate walked a <table> into tr/td but walked nothing else.
//           So the two screens whose mockups used tables produced 44 findings and
//           looked thorough, while card-built screens produced silence and PASS. The
//           failure is silent AND inverted: **the less of a screen the gate can see,
//           the cleaner its verdict looks.** -> the structural walker, the coverage
//           accounting, and the UNGRADEABLE verdict below. A PASS must mean "graded",
//           never "there was nothing to compare".
//
//   TF-012  The `clip` clause counted screen-reader-only text as overflow, so every
//           accessible screen failed it — 8 of 10 screens, identical message, always.
//           A finding that appears everywhere always trains a reader to skim the whole
//           report, which is the most expensive failure a gate can have. -> isHidden()
//           and the visible-extent overflow measurement below.
//
// It produces FINDINGS and a per-screen verdict. verify-phase §4b2 decides what that
// means for a REQ.

import { chromium } from 'playwright';
import { existsSync, mkdirSync, writeFileSync, readFileSync, readdirSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { signIn, reach } from './tf-login.mjs';
import { parseThemes, useTheme, surface, differs, looksDark } from './tf-theme.mjs';

// ---------------------------------------------------------------- arguments
const argv = process.argv.slice(2);
const arg = (name, dflt = null) => {
  const i = argv.indexOf(name);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : dflt;
};
const flag = (name) => argv.includes(name);

const BASE = (arg('--base') || '').replace(/\/$/, '');
// An embedded-browser desktop head, attached over its DevTools port as tf-verify-screens does; its
// screens are opened the way its router does, by pushState (Lekhak TF-006).
const CDP = arg('--cdp') || '';
const MOCKUPS = arg('--mockups', 'docs/mockups');
const WIDTHS = (arg('--widths', '1280,390') || '').split(',').map((w) => parseInt(w.trim(), 10)).filter(Boolean);
const JSON_OUT = arg('--json-out');
const COOKIE = arg('--cookie');
// A sign-in the page keeps for itself sets no cookie, so --cookie could not reach AppManager's screens
// at all: "app returned HTTP 401" at both widths (AppManager TF-011). The same --login-path, --user,
// --password and --storage-state tf-verify-screens takes, through the shared recipe in tf-login.mjs.
const LOGIN_PATH = arg('--login-path'); const USER = arg('--user'); const PASS = arg('--password');
const STORAGE = arg('--storage-state');
const LOGIN_OPTS = { base: BASE, loginPath: LOGIN_PATH, user: USER, password: PASS, settle: 1500, renderWait: 5000 };
const HEADERS = [];
for (let i = 0; i < argv.length; i++) if (argv[i] === '--header' && argv[i + 1]) HEADERS.push(argv[i + 1]);
const SCREENS = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--screen' && argv[i + 1]) {
    const [name, ...rest] = argv[i + 1].split('=');
    SCREENS.push({ name: name.trim(), route: rest.join('=').trim() || '/' + name.trim() });
  }
}
// Where each screen's mockup is (Lekhak TF-022). --list names the list.json tf-verify-list.sh wrote,
// which holds the path it resolved per screen (docs/mockups/admin/prompt-manager.html); a --screen is
// matched to a listed screen by its mockup's stem or its name, and with no --screen every listed screen
// that has a mockup and a route without a {value} is driven. Without a list, a mockup missing at the top
// of --mockups is looked for in its subfolders, and used when exactly one file has that name.
const MOCK_OF = {};
const LIST = arg('--list');
if (LIST) {
  const slug = (t) => String(t || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  let listed = [];
  try { listed = JSON.parse(readFileSync(LIST, 'utf8')).screens || []; }
  catch (e) { console.error(`tf-mockup-parity: --list ${LIST} unreadable (${String(e.message).slice(0, 80)})`); }
  const byKey = {};
  for (const ls of listed) {
    if (!ls.mockup) continue;
    byKey[basename(ls.mockup).replace(/\.html$/, '')] ??= ls;
    byKey[slug(ls.name)] ??= ls;
  }
  if (!SCREENS.length) {
    for (const ls of listed) {
      if (ls.mockup && ls.route && !ls.route.includes('{')) SCREENS.push({ name: basename(ls.mockup).replace(/\.html$/, ''), route: ls.route });
    }
  }
  for (const s of SCREENS) {
    const ls = byKey[s.name] || byKey[slug(s.name)];
    if (ls) MOCK_OF[s.name] = ls.mockup;
  }
}
const findMockup = (name) => {
  if (MOCK_OF[name]) return resolve(MOCK_OF[name]);
  const top = resolve(MOCKUPS, `${name}.html`);
  if (existsSync(top)) return top;
  const hits = [];
  const walk = (dir, depth) => {
    if (depth > 4) return;
    let ents = [];
    try { ents = readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      if (e.isDirectory() && !e.name.startsWith('.')) walk(join(dir, e.name), depth + 1);
      else if (e.isFile() && e.name === `${name}.html` && dir !== resolve(MOCKUPS)) hits.push(join(dir, e.name));
    }
  };
  walk(resolve(MOCKUPS), 0);
  return hits.length === 1 ? hits[0] : top;
};
const THIN_RATIO = parseFloat(arg('--thin-ratio', '0.25'));
// --keep-app-theme compares the app in the theme it is showing, not the mockup's (Lekhak TF-010)
const KEEP_APP_THEME = flag('--keep-app-theme');
// Lekhak TF-024: a screen is compared in the mockup's own theme and then in the other one. --themes
// light,dark runs both; light or dark alone runs only that one; auto (the default) runs the other one
// once the app shows it has it (what it paints changes when that theme is put on it). In the other
// theme the mockup is drawn in it too; when the mockup does not change under it (no dark styles in the
// mockup), the app is compared with the mockup as drawn and colour is left out, since the mockup says
// nothing about it; every other class is compared.
const THEMES = parseThemes(arg('--themes', 'auto'));
const wantTheme = (t) => !THEMES || THEMES.includes(t);
let otherSeen = false;    // auto: has any screen shown the other theme yet?
// The theme a page declares: data-* attributes on <html> and <body> whose name says theme, mode or
// scheme (data-theme, data-bs-theme, data-site-theme, data-color-mode …), and the class tokens there
// that name a light or dark mode (dark, light, theme-dark, dark-mode …), which a class-driven dark mode
// such as Tailwind's `dark` uses (Lekhak TF-013). A utility class such as bg-light does not count.
// Nothing about any one stack. The class tokens are kept under `<where>|class`, '' when there are none.
const READ_THEME = () => {
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
const DECLARES_THEME = (t) => !!t && Object.entries(t).some(([k, v]) => !k.endsWith('|class') || v);
// Sets those attributes and mode classes on this page; returns what it had, so the same call puts it
// back. An attribute the page lacked is removed again on the way back (value null). For `|class` the
// page's own mode tokens are replaced by the given ones; every other class is left alone.
const APPLY_THEME = (t) => {
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
const MAX_FINDINGS_PER_SCREEN = parseInt(arg('--max-findings', '40'), 10);

if ((!BASE && !CDP) || SCREENS.length === 0) {
  console.error('usage: tf-mockup-parity.sh --base URL|--cdp URL --screen name=/route [--screen ...]');
  process.exit(3);
}

// ------------------------------------------------------------ page-side probe
// Everything below runs INSIDE the browser, on both the mockup and the app, and
// returns one flat index keyed by a stable path key. It is deliberately one
// evaluate() call: two passes over the same DOM can disagree after a re-layout.
// `wanted` names the texts of the mockup's badges, so the app's side can find each one at whatever
// depth the app drew it (TF-045); the mockup's own probe is called without it.
const PROBE = (wanted = []) => {
  const MAX_DEPTH = 4;        // descend this far below an anchor
  const MAX_PER_ANCHOR = 60;  // and no further; a huge subtree is noise, not signal

  // --- TF-012: the third hiding technique, and the only one that leaves a box.
  // display:none and visibility:hidden are already excluded by every geometry
  // check because they have no layout box. The sr-only recipe DOES lay out — a 1px
  // clipped box with white-space:nowrap — so its scrollWidth is meaningless BY
  // CONSTRUCTION (nowrap text in a 1px box guarantees scrollWidth >> clientWidth)
  // and it inflates its ANCESTOR's scrollWidth, which is what the clip clause reads.
  // Visually-hidden text is not visually anything; it is the accessible name a
  // screen reader announces, and a WCAG-conformant app is supposed to have it.
  const isHidden = (el) => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || cs.opacity === '0') return true;
    if ((cs.clipPath || '').replace(/\s/g, '') === 'inset(50%)') return true;
    if (/rect\(\s*0(px)?\s*,?\s*0(px)?\s*,?\s*0(px)?\s*,?\s*0(px)?\s*\)/.test(cs.clip || '')) return true;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return true;      // covers the 1px sr-only box
    return false;
  };

  // --- TF-027: the browser converts the colour, never a regex. getComputedStyle returns a
  // colour in the syntax it was written in, and a component library themed in oklch() came
  // back as "oklch(0.971 0.013 17.38)": read as r/g/b those three numbers are near-black, so
  // every tinted tile, pill and icon in the app bucketed as neutral against a mockup written
  // in hex — "semantic colour differs — mockup negative, app neutral" on tiles plainly red.
  // Painting one pixel and reading it back gives sRGB for any syntax the browser accepts.
  const px = document.createElement('canvas');
  px.width = px.height = 1;
  const pctx = px.getContext('2d', { willReadFrequently: true });
  const RGB = (v) => {
    if (!v || v === 'transparent' || !pctx) return null;
    pctx.clearRect(0, 0, 1, 1);
    pctx.fillStyle = 'rgba(0,0,0,0)';
    pctx.fillStyle = v;                    // an unparseable value leaves it transparent
    pctx.fillRect(0, 0, 1, 1);
    const [r, g, b, a] = pctx.getImageData(0, 0, 1, 1).data;
    return a / 255 < 0.05 ? null : { r, g, b };
  };

  // Semantic BUCKET, never the literal colour: two designs may legitimately differ
  // in shade, and grading the exact value would produce a finding on every screen.
  const bucket = (c) => {
    if (!c) return null;
    const { r, g, b } = c;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    if (mx - mn < 28) return 'neutral';
    // By hue, never by one channel. "Red is highest, so green above 120 is a warning" put a deep
    // amber (180, 83, 9) in `negative` beside a light amber in `warning` — one warning tone on two
    // sides of the line, reported as a colour difference on TfLens /misses (TF-045).
    const d = mx - mn;
    const h = ((mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4) * 60 + 360) % 360;
    if (h < 15 || h >= 330) return 'negative';
    if (h < 70) return 'warning';
    if (h < 185) return 'positive';
    return 'accent';
  };

  // A border nobody draws carries no colour. `border: 1px solid transparent` is how a mockup
  // reserves space, and a page reset that sets border-color everywhere leaves the property set on
  // elements with no border at all: reading it gave a borderless icon the reset's grey and called
  // it a colour difference (TF-038).
  const drawnBorder = (cs) => (parseFloat(cs.borderTopWidth) || 0) > 0 && !!RGB(cs.borderTopColor);

  const semanticColor = (el) => {
    const cs = getComputedStyle(el);
    return bucket(RGB(cs.backgroundColor)) || (drawnBorder(cs) ? bucket(RGB(cs.borderTopColor)) : null) || bucket(RGB(cs.color));
  };

  // --- TF-009: the seventh class. A mockup says "provisional / estimated /
  // inactive" with a border STYLE precisely because it stays legible on both the
  // light and the dark surface without spending a colour on it — so a gate that
  // reads every other border property but not this one keeps missing that whole
  // vocabulary. Quantised to the three values that carry meaning rather than the
  // full CSS keyword set, so the clause stays as noise-free as the colour buckets.
  const strokeOf = (el) => {
    const cs = getComputedStyle(el);
    const q = (s) => (s === 'none' || s === 'hidden' ? 'none'
      : s === 'dashed' || s === 'dotted' ? 'dashed' : 'solid');
    const sides = ['borderTopStyle', 'borderRightStyle', 'borderBottomStyle', 'borderLeftStyle'].map((k) => q(cs[k]));
    const drawn = drawnBorder(cs);       // width AND a colour: transparent draws nothing (TF-038)
    const style = drawn ? sides[0] : 'none';
    return { style, uniform: new Set(sides).size === 1, visible: drawn };
  };

  const ICON = 'svg, img, i[class*="icon"], span[class*="icon"], [class*="bi-"], [class*="fa-"]';
  // A box the mockup marks as another state of the screen is left out of the comparison (Lekhak
  // TF-011), and so is everything inside it when a box around it is counted: the download icon in a
  // "newer build" banner was reported on the card holding the banner (Chatur TF-001).
  // data-tf-state="sample-data" is not another state: it is sample data, the data-tf-sample rule
  // (Chatur TF-005). Left out here, a list the app fills with real rows read "app carries an icon the
  // mockup does not" on every row.
  const STATE = '[data-tf-state]:not([data-tf-state="sample-data"]),[data-state-testid]';
  const SAMPLE = '[data-tf-sample],[data-tf-state="sample-data"]';
  const own = (el, sel) => [...el.querySelectorAll(sel)].filter((x) => !x.closest(STATE) || el.closest(STATE));
  const ownText = (el) => {
    if (!el.querySelector(STATE) || el.closest(STATE)) return el.textContent || '';
    const c = el.cloneNode(true);
    for (const x of c.querySelectorAll(STATE)) x.remove();
    return c.textContent || '';
  };
  const hasIcon = (el) => own(el, ICON).length > 0;
  // how many icons the element carries at any depth: a component library that wraps an icon
  // one element deeper than the mockup moves it to another path key without removing it (TF-027)
  const iconCount = (el) => own(el, ICON).filter((i) => !i.parentElement || !i.parentElement.closest('svg')).length;
  // Every icon on the page by number, so the node side can tell that an anchor and the wrappers
  // above it hold the same icon as the element it sits in: the icon clause asks "any icon inside?",
  // and one Select chevron was reported at four levels of TfLens /misses (TF-046).
  const iconNo = new Map([...document.querySelectorAll(ICON)].map((i, n) => [i, n]));
  const iconIds = (el) => own(el, ICON).map((i) => iconNo.get(i));
  const depthOf = (el) => { let n = 0; for (let p = el.parentElement; p; p = p.parentElement) n++; return n; };

  // "Chrome" = a badge / pill / chip: a small element with its own fill or ring and
  // a rounded edge. The mockup drawing one and the app rendering bare text is the
  // canonical TF-008 escape — a status pill flattened to plain text is the one value
  // on a page meant to be read at a glance.
  const chromeOn = (el) => {
    const r = el.getBoundingClientRect();
    if (r.height > 44 || r.height < 6) return null;    // a card is not a badge
    const cs = getComputedStyle(el);
    const radius = parseFloat(cs.borderTopLeftRadius) || 0;
    const filled = !!RGB(cs.backgroundColor);
    const ringed = drawnBorder(cs);      // a transparent ring is not a ring (TF-038)
    return { badge: (filled || ringed) && radius >= 6, filled, ringed, radius: Math.round(radius) };
  };

  // --- TF-047: the treatment one element away. A component library draws the ring and the radius on
  // the box AROUND the control the mockup styles (an InputGroup around a filter input, a nav <li>
  // around the active link), and a mockup does the reverse. Keys pair by position, so the badge and
  // stroke clauses compared the control with the plain box beside the one that carries the treatment:
  // "badge on nav > a[4], app plain" on TfLens's sidebar, on every screen. The element's neighbours
  // one step away are kept here — the parent when it is the same row (same height, its other
  // children carrying no text: an icon, or the box a library wraps one in) and the only child when
  // it is — so a clause can accept the treatment there.
  const nearOf = (el) => {
    const out = [];
    const h = el.getBoundingClientRect().height;
    const sameRow = (x) => Math.abs(x.getBoundingClientRect().height - h) <= 8;
    const p = el.parentElement;
    if (p && p !== document.body && sameRow(p)
        && [...p.children].every((s) => s === el || isHidden(s) || !(s.textContent || '').trim())) out.push(p);
    const kids = [...el.children].filter((c) => !isHidden(c));
    if (kids.length === 1 && sameRow(kids[0])) out.push(kids[0]);
    return out;
  };

  // Only text that is genuinely a single inline run can be graded for wrapping or
  // token fit. A container with block children has no meaningful line count, and
  // pretending otherwise is how a card-shaped anchor buys nothing (TF-011).
  const inlineOnly = (el) => {
    for (const c of el.children) {
      const d = getComputedStyle(c).display;
      if (d !== 'inline' && d !== 'inline-block' && d !== 'contents') return false;
    }
    return (el.textContent || '').trim().length > 0;
  };

  const lineCount = (el) => {
    if (!inlineOnly(el)) return null;
    const cs = getComputedStyle(el);
    let lh = parseFloat(cs.lineHeight);
    if (!lh || Number.isNaN(lh)) lh = (parseFloat(cs.fontSize) || 16) * 1.2;
    // the text's height only: padding and borders are not rows. A badge with 4px padding and
    // `line-height: 1` read 18 / 9.756 = 1.85, rounded to 2 rows (AppManager TF-015).
    const h = el.getBoundingClientRect().height
      - ['paddingTop', 'paddingBottom', 'borderTopWidth', 'borderBottomWidth'].reduce((s, k) => s + (parseFloat(cs[k]) || 0), 0);
    if (!(h > 0) || !lh) return null;
    return Math.max(1, Math.round(h / lh));
  };

  // A formatted number must never break mid-digit. The longest unbreakable token is
  // what the cell actually has to fit; the mockup's own column width is the claim
  // that it does.
  const tokenFit = (el) => {
    if (!inlineOnly(el)) return null;
    const text = (el.textContent || '').trim();
    if (!text) return null;
    const longest = text.split(/\s+/).reduce((a, b) => (b.length > a.length ? b : a), '');
    if (longest.length < 4) return null;
    const range = document.createRange();
    let w = 0;
    try {
      const tn = [...el.childNodes].find((n) => n.nodeType === 3 && n.textContent.includes(longest));
      if (!tn) return null;
      const at = tn.textContent.indexOf(longest);
      range.setStart(tn, at);
      range.setEnd(tn, at + longest.length);
      w = range.getBoundingClientRect().width;
    } catch (e) { return null; }
    const cs = getComputedStyle(el);
    const avail = el.clientWidth - (parseFloat(cs.paddingLeft) || 0) - (parseFloat(cs.paddingRight) || 0);
    if (!w || avail <= 0) return null;
    return { fits: w <= avail + 1, token: longest.slice(0, 24) };
  };

  // --- TF-012 again, on the measuring side. scrollWidth includes the phantom
  // extent of an sr-only descendant, so the ancestor is measured from the right
  // edge of its VISIBLE descendants instead whenever a hidden one is present.
  // A descendant inside a scroller is painted only as far as that scroller's edge, so its own box
  // must be cut by every ancestor that clips before it can count as the card overflowing. Without
  // that, a table scrolling inside its wrapper — the layout the BRD asks for — read as a card cut
  // off at 390px (TF-039). The same rectangle tf-verify-screens measures since TF-021.
  // The cut stops BELOW `stop`: the element being measured must not cut its own content, or a card
  // that really clips would read as holding everything (it did, from TF-039 until TF-042).
  const paintedRight = (c, stop) => {
    const r = c.getBoundingClientRect();
    let x1 = r.left, x2 = r.right;
    for (let a = c.parentElement; a && a !== stop; a = a.parentElement) {
      if (getComputedStyle(a).overflowX !== 'visible') {
        const ar = a.getBoundingClientRect();
        x1 = Math.max(x1, ar.left); x2 = Math.min(x2, ar.right);
      }
    }
    return x2 > x1 ? x2 : null;
  };

  // --- TF-042: overflow is not clipping. An element whose overflow-x is `visible` draws what spills
  // past its edge in full, so it is cut off only where an ancestor that clips ends first. Reading
  // scrollWidth alone called a sidebar "cut off" because its rail handle straddles its edge by 8px,
  // on every TfLens screen, with nothing clipped anywhere up to <html> (2026-09-12).
  const cutAbove = (el, right) => {
    for (let a = el.parentElement; a; a = a.parentElement) {
      if (getComputedStyle(a).overflowX === 'visible') continue;
      if (right > a.getBoundingClientRect().left + a.clientLeft + a.clientWidth + 2) return true;
    }
    return false;
  };

  const clipOf = (el) => {
    const hiddenKids = [...el.querySelectorAll('*')].filter(isHidden);
    const box = el.getBoundingClientRect();
    let overX, right;
    if (hiddenKids.length === 0) {
      overX = el.scrollWidth - el.clientWidth;
      right = box.left + el.clientLeft + el.scrollWidth;
    } else {
      right = box.left;
      for (const c of el.querySelectorAll('*')) {
        if (isHidden(c)) continue;
        const r = c.getBoundingClientRect();
        if (r.width > 0) {
          const painted = paintedRight(c, el);
          if (painted !== null) right = Math.max(right, painted);
        }
      }
      overX = Math.max(0, Math.round(right - (box.left + el.clientWidth)));
    }
    let x = overX > 2;
    if (x && getComputedStyle(el).overflowX === 'visible') x = cutAbove(el, right);
    const overY = el.scrollHeight - el.clientHeight;
    return { x, y: overY > 2, sr_excluded: hiddenKids.length };
  };

  const sigOf = (el) => {
    const r = el.getBoundingClientRect();
    const chrome = chromeOn(el);
    const near = nearOf(el);
    return {
      // the badge and the visible border one element away, for the clauses to accept (TF-047)
      near: {
        badge: near.some((n) => chromeOn(n)?.badge === true),
        stroke: near.map(strokeOf).find((s) => s.visible) || null,
      },
      tag: el.tagName.toLowerCase(),
      text: ownText(el).trim().replace(/\s+/g, ' ').slice(0, 60),
      badge: chrome ? chrome.badge : null,
      full: ownText(el).trim().replace(/\s+/g, ' ').slice(0, 400),
      // a box the mockup marks as sample data, drawn only when the app has data there (Chatur TF-002)
      sample: el.matches(SAMPLE),
      icon: hasIcon(el),
      icons: iconCount(el),
      icon_ids: iconIds(el),   // which icons, so a finding repeated at a container can be told apart (TF-046)
      // the anchors inside and the icons each holds, so a row graded on its own can be taken off
      // the box around it (Chatur TF-006)
      nested: own(el, '[data-testid]').filter((x) => !isHidden(x))
        .map((x) => ({ id: x.getAttribute('data-testid'), ids: iconIds(x),
          top: x.parentElement?.closest('[data-testid]') === el })).slice(0, 200),
      depth: depthOf(el),
      // badges drawn anywhere inside, so a badge one wrapper deeper still counts under its parent (TF-045)
      badges: own(el, '*').filter((c) => !isHidden(c) && chromeOn(c)?.badge).length,
      color: semanticColor(el),
      stroke: strokeOf(el),
      wrap: lineCount(el),
      clip: clipOf(el),
      token: tokenFit(el),
      w: Math.round(r.width),
      h: Math.round(r.height),
      inline: inlineOnly(el),
    };
  };

  // --- the walker. TF-011's cheapest real win: the first implementation descended a
  // <table> into tr/td and NOTHING ELSE, which is the entire reason table-shaped
  // mockups produced 44 findings and card-shaped ones produced silence. That was
  // luck, not design. This descends ANY anchored subtree by a structural path key,
  // so a card, a column, a grid, a <dl> and a list are all walked the same way a
  // table already was. Keys pair only when both sides produce them, so extra depth
  // costs precision nothing — it only ever adds comparisons that were impossible
  // before.
  // A box the mockup marks as another state of the screen (data-tf-state="<state>", or
  // data-state-testid="<id>") is not on the first view, so it is neither walked nor counted when its
  // siblings are numbered: a database-down alert first in a card moved every row below it one place,
  // and the Host/Port row was compared with the alert (Lekhak TF-011).
  const stateOnly = (el) => el.matches(STATE);
  const keyOf = (el, parentKey) => {
    const tag = el.tagName.toLowerCase();
    let n = 0;
    for (const s of el.parentElement ? el.parentElement.children : []) {
      if (s === el) break;
      if (s.tagName === el.tagName && !stateOnly(s)) n++;
    }
    return `${parentKey} > ${tag}[${n}]`;
  };

  // --- TF-045: the same badge, one wrapper deeper. Keys are positional, so a component library that
  // wraps a card header's contents in one more <div> moves every badge in it to a key the mockup
  // never has: 32 "missing" findings on three TfLens screens, each drawn on the page with the right
  // text. For every text a mockup badge carries, the elements under the same anchor that carry it
  // are kept here at any depth, so the node side can find the badge where the app put it. Digits
  // are folded, because live data is not the mockup's sample: "87 of 91" is "39 of 41". Case is
  // kept: a card titled "Draft" is not its badge "draft".
  const norm = (t) => (t || '').replace(/\d[\d,.]*/g, '#').replace(/\s+/g, ' ').trim();
  const want = new Set((wanted || []).map(norm).filter(Boolean));
  const pool = {};

  const index = {};
  const anchors = [...document.querySelectorAll('[data-testid]')];
  const allTestIds = anchors.map((a) => a.getAttribute('data-testid'));

  for (const a of anchors) {
    const id = a.getAttribute('data-testid');
    if (!id || index[id]) continue;
    if (isHidden(a) || a.closest(STATE)) continue;   // TF-011
    index[id] = sigOf(a);
    let budget = MAX_PER_ANCHOR;
    const walk = (el, key, depth) => {
      if (depth > MAX_DEPTH || budget <= 0) return;
      for (const c of el.children) {
        if (budget <= 0) return;
        if (c.hasAttribute('data-testid')) continue;   // it gets its own top-level entry
        if (isHidden(c)) continue;                     // TF-012
        if (stateOnly(c)) continue;                    // another state of the screen (TF-011)
        const k = keyOf(c, key);
        index[k] = sigOf(c);
        budget--;
        walk(c, k, depth + 1);
      }
    };
    walk(a, id, 1);
    if (want.size) {
      const found = [];
      const queue = [[a, id, 0]];
      let seen = 0;
      while (queue.length && seen < 800 && found.length < 30) {
        const [el, key, depth] = queue.shift();
        if (depth >= 12) continue;
        for (const c of el.children) {
          if (c.hasAttribute('data-testid') || isHidden(c) || stateOnly(c)) continue;
          seen++;
          const k = keyOf(c, key);
          if (want.has(norm((c.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 60)))) found.push({ key: k, ...sigOf(c) });
          queue.push([c, k, depth + 1]);
        }
      }
      pool[id] = found;
    }
  }

  const de = document.documentElement;
  // the shell's content scroll container, when it has one: a box that scrolls inside itself, no
  // taller than the viewport (a table wrapper that grows with its rows is not one), at least 60% of
  // its width and half its height, and across the viewport's centre (a side menu, or a drawer parked
  // off screen, is not one). Without one the document is the app's scroller (AppManager TF-014).
  // A box that only scrolls sideways is not one either: `overflow-x: auto` alone makes the browser
  // compute overflow-y as auto too, so Bootstrap's .table-responsive looked like a shell at 390px
  // (AppManager TF-028). Skipped: a box whose only child is a table, and a box wider inside than
  // out whose height fits its content.
  const scroller = [...document.querySelectorAll('body *')].find((el) => {
    const o = getComputedStyle(el).overflowY;
    if (o !== 'auto' && o !== 'scroll') return false;
    if (el.children.length === 1 && el.children[0].tagName === 'TABLE') return false;
    if (el.scrollWidth > el.clientWidth + 1 && el.scrollHeight <= el.clientHeight + 1) return false;
    const r = el.getBoundingClientRect(), cx = de.clientWidth / 2;
    return r.height <= de.clientHeight + 2 && r.width >= de.clientWidth * 0.6 && r.height >= de.clientHeight / 2
      && r.left <= cx && r.right >= cx;
  });
  return {
    index,
    pool,
    anchors: anchors.length,
    testids: allTestIds,
    doc: {
      scrollHeight: de.scrollHeight,
      clientHeight: de.clientHeight,
      scrollWidth: de.scrollWidth,
      clientWidth: de.clientWidth,
      scroller: scroller ? `${scroller.tagName.toLowerCase()}${scroller.id ? '#' + scroller.id : ''}${scroller.className ? '.' + String(scroller.className).trim().split(/\s+/)[0] : ''}` : null,
    },
  };
};

// ------------------------------------------------------------------- diffing
// A clause returns a finding, `null` (not applicable — do NOT count it as graded),
// or `false` (applicable and agreeing). The three are kept distinct because
// conflating "agreed" with "not asked" is precisely how TF-011 happened.
// The same folding the page-side probe uses: spacing and digits (TF-045).
const norm = (t) => (t || '').replace(/\d[\d,.]*/g, '#').replace(/\s+/g, ' ').trim();

const CLAUSES = {
  badge: (m, a) => {
    if (m.badge === null || a.badge === null) return null;
    if (m.badge === a.badge) return false;
    // TF-047: the side without the treatment carries it one element away — the same control, drawn
    // by a library on the box around it or the box inside it. That is agreement, not drift.
    if ((m.badge ? a : m).near?.badge) return false;
    return `mockup renders this as a ${m.badge ? 'badge/pill' : 'plain element'}, app renders it as a ${a.badge ? 'badge/pill' : 'plain element'}`;
  },
  icon: (m, a) => (m.icon === a.icon ? false
    : m.icon && !a.icon ? 'mockup carries an icon here; the app does not'
      : 'app carries an icon the mockup does not'),
  color: (m, a) => (m.color === null || a.color === null ? null
    : m.color !== a.color ? `semantic colour differs — mockup ${m.color}, app ${a.color}` : false),
  // TF-009
  stroke: (m, a) => {
    if (!m.stroke || !a.stroke) return null;
    let ms = m.stroke, as = a.stroke;
    // TF-047: a side that draws no border of its own is read at the border one element away, and
    // only when the sides disagree — two plain elements inside a ringed box still agree as before.
    if (ms.style !== as.style || ms.visible !== as.visible) {
      if (!ms.visible && m.near?.stroke) ms = m.near.stroke;
      if (!as.visible && a.near?.stroke) as = a.near.stroke;
    }
    if (ms.style !== as.style) {
      return `border style differs — mockup ${ms.style}, app ${as.style}`
        + (ms.style === 'dashed' ? ' (a dashed rule is how a mockup says "estimate / provisional"; losing it makes an estimate look measured)' : '');
    }
    if (ms.visible !== as.visible) {
      return `border presence differs — mockup ${ms.visible ? 'has a visible rule' : 'has none'}, app ${as.visible ? 'has one' : 'has none'}`;
    }
    return false;
  },
  // TF-047: a row count says something only about the same text. Live data that reads differently
  // from the mockup's sample wraps differently for that reason alone, so the clause is not applicable
  // (null, never counted as graded) unless the digit-folded texts match.
  wrap: (m, a) => (m.wrap === null || a.wrap === null || norm(m.full) !== norm(a.full) ? null
    : a.wrap > m.wrap ? `wraps to ${a.wrap} rows where the mockup keeps it on ${m.wrap}` : false),
  clip: (m, a) => (!m.clip || !a.clip ? null
    : (a.clip.x && !m.clip.x) ? 'content is cut off horizontally; the mockup is not clipped'
      : (a.clip.y && !m.clip.y) ? 'content is cut off vertically; the mockup is not clipped' : false),
  token: (m, a) => (m.token === null || a.token === null ? null
    : m.token.fits && !a.token.fits
      ? `value cell is narrower than its longest unbreakable token ("${a.token.token}") — it breaks mid-token`
      : false),
};

// Which clauses require having reached INSIDE a container rather than merely
// touching its outer box. TF-011's `harness` screen graded three column CONTAINERS
// and reported PASS: colour and stroke are computable on any box, so counting them
// as coverage is what let a screen the gate never really looked at read as clean.
const CONTENT_CLAUSES = new Set(['badge', 'icon', 'wrap', 'token']);

function diff(mock, app, screen, width, skip = null) {
  // --- Chatur TF-002: sample data the app is not showing. A mockup draws a list full of sample rows
  // and a fresh app has none, so every icon on a sample row read as missing. A box the mockup marks
  // data-tf-sample is compared when the app draws something at its place; when it draws nothing
  // there, the box and everything in it are "not measured", and its icons and badges are taken off
  // the boxes around it. A seed script (tests/verify/seed/) puts the app in the drawn state instead.
  const notMeasured = [];
  const mockAll = mock.index;   // before anything is dropped (Chatur TF-007)
  // the mockup's sample rows that carry their own anchor (commit-row-N), read before any is dropped
  const fold = (id) => id.replace(/\d+/g, '#');
  const sampleRows = new Set(Object.keys(mock.index).filter((k) => !k.includes(' > ') && mock.index[k].sample));
  const sampleShapes = new Set([...sampleRows].map(fold));
  const idx = { ...mock.index };
  for (const key of Object.keys(mock.index)) {
    const m = mock.index[key];
    if (!m.sample || app.index[key] || notMeasured.some((k) => key.startsWith(k + ' > '))) continue;
    notMeasured.push(key);
    for (const k of Object.keys(idx)) if (k === key || k.startsWith(key + ' > ')) delete idx[k];
    const gone = new Set(m.icon_ids || []);
    for (let up = key; up.includes(' > ');) {
      up = up.slice(0, up.lastIndexOf(' > '));
      const a = idx[up];
      if (!a) continue;
      const icons = Math.max(0, (a.icons ?? 0) - (m.icons ?? 0));
      idx[up] = { ...a, icons, icon: a.icon && icons > 0, icon_ids: (a.icon_ids || []).filter((i) => !gone.has(i)),
        badges: Math.max(0, (a.badges ?? 0) - (m.badges ?? 0) - (m.badge === true ? 1 : 0)) };
    }
  }
  mock = { ...mock, index: idx };
  // --- Chatur TF-006: a sample row graded on its own is not the box's icon too. The mockup's table
  // lost its sample rows' icons when their tbody was not measured, while the app's table still counted
  // every row's: "app carries an icon the mockup does not" on a box whose rows were each compared. A
  // row anchored as a mockup sample row, or as more of the same (commit-row-7 beside commit-row-1), is
  // left out of every box around it on both sides; an icon of the box's own is still counted.
  const strip = (index, goneOf) => Object.fromEntries(Object.entries(index).map(([k, s]) => {
    const gone = goneOf(k, s);
    const ids = (s.icon_ids || []).filter((i) => !gone.has(i));
    const cut = (s.icon_ids || []).length - ids.length;
    if (!cut) return [k, s];
    const icons = Math.max(0, (s.icons ?? 0) - cut);
    return [k, { ...s, icons, icon: icons > 0, icon_ids: ids }];
  }));
  const dropRows = (index, isRow) => strip(index, (k, s) => new Set((s.nested || []).filter((n) => isRow(n.id)).flatMap((n) => n.ids)));
  if (sampleRows.size) {
    mock = { ...mock, index: dropRows(mock.index, (id) => sampleRows.has(id)) };
    app = { ...app, index: dropRows(app.index, (id) => sampleRows.has(id) || (!(id in mock.index) && sampleShapes.has(fold(id)))) };
  }
  // --- Chatur TF-007: the app's rows in the place of sample rows not measured. The mockup's list box
  // lost the icons of sample rows the app does not draw (recent-tflens, tools-table > tbody[0]), while
  // the app's box kept the icons of the real rows it draws there instead (recent-chatur, a wrapped
  // tbody): "app carries an icon the mockup does not" on Start, Prerequisites, Providers, Corrections and
  // the file tree. The app's rows in that place — the children and anchors of the box holding the sample
  // rows that the mockup does not have — are left out of every box around them, as the sample rows are
  // on the mockup's side, there taken off every box too, anchors around the list included.
  // A row's icons come off the boxes AROUND it only: an element above it that holds all of them. A
  // button inside the row keeps its own icon, or it reads as one the mockup does not carry.
  const appAll = app.index;
  const rowsGone = (rows, all) => (k, s) => {
    const had = new Set(all[k]?.icon_ids || s.icon_ids || []);
    return new Set(rows.filter((r) => (s.depth ?? 0) < r.depth && r.ids.every((i) => had.has(i))).flatMap((r) => r.ids));
  };
  const inPlace = [];
  // The app's rows in that place are what the mockup does not have under the same box and of the
  // same kind as the sample row (a tbody for a tbody, an <a> for an <a>), the outermost of them; only
  // when there is none of that kind, every child of the box the mockup does not have. A heading or a
  // toolbar of the box's own is not a row.
  const takeRows = (box, tag) => {
    const a = appAll[box];
    if (!a) return;
    const tagOf = (k) => k.slice(k.lastIndexOf(' > ') + 3).replace(/\[\d+\]$/, '');
    const same = Object.keys(appAll).filter((k) => k.startsWith(box + ' > ') && !(k in mockAll) && tagOf(k) === tag);
    const rows = same.filter((k) => !same.some((o) => o !== k && k.startsWith(o + ' > ')))
      .map((k) => ({ ids: appAll[k].icon_ids || [], depth: appAll[k].depth ?? 0 }));
    for (const n of a.nested || []) {
      if (!(n.id in mockAll) && appAll[n.id]?.tag === tag) rows.push({ ids: n.ids, depth: appAll[n.id].depth ?? 0 });
    }
    if (!rows.length) {
      for (const k of Object.keys(appAll)) {
        if (k.startsWith(box + ' > ') && !k.slice(box.length + 3).includes(' > ') && !(k in mockAll)) {
          rows.push({ ids: appAll[k].icon_ids || [], depth: appAll[k].depth ?? 0 });
        }
      }
      // and the box's own anchors the mockup does not have: a scroll area holding the rows
      for (const n of a.nested || []) {
        if (n.top && !(n.id in mockAll) && appAll[n.id]) rows.push({ ids: n.ids, depth: appAll[n.id].depth ?? 0 });
      }
    }
    inPlace.push(...rows);
  };
  const sampleGone = [];
  for (const k of notMeasured) {
    sampleGone.push({ ids: mockAll[k].icon_ids || [], depth: mockAll[k].depth ?? 0 });
    if (k.includes(' > ')) { takeRows(k.slice(0, k.lastIndexOf(' > ')), mockAll[k].tag); continue; }
    // an anchored sample row: the nearest mockup box holding it
    const box = Object.keys(mockAll).filter((b) => (mockAll[b].nested || []).some((n) => n.id === k))
      .sort((x, y) => (mockAll[y].depth ?? 0) - (mockAll[x].depth ?? 0))[0];
    if (box) takeRows(box, mockAll[k].tag);
  }
  const some = (rows) => rows.filter((r) => r.ids.length);
  if (some(sampleGone).length) mock = { ...mock, index: strip(mock.index, rowsGone(some(sampleGone), mockAll)) };
  if (some(inPlace).length) app = { ...app, index: strip(app.index, rowsGone(some(inPlace), appAll)) };
  const findings = [];
  const clauseCoverage = Object.fromEntries(Object.keys(CLAUSES).map((k) => [k, 0]));
  clauseCoverage.missing = 0;
  let compared = 0, contentGraded = 0, relocated = 0;
  const iconsShort = {};   // parent key -> icons the app still owes under it (TF-027)
  const badgesShort = {};  // parent key -> badges the app still owes under it (TF-045)
  const usedApp = new Set();
  const iconSeen = [];     // icon findings with the side that holds the icons (TF-046)

  // --- TF-047: the same icon in another child. Pairing is by position, so a card header that a
  // library wraps in one more <div> pairs the mockup's description with the app's toolbar, and the
  // toolbar's icon reads as one "the mockup does not" carry — while the header holds exactly one
  // icon on both sides. The rule the `missing` clause has followed since TF-027, one wrapper further:
  // an icon finding is dropped when the parent or the grandparent is paired and carries the same
  // number of icons on both sides. Bounded to a few icons, so a coincidence across a whole page
  // (one lost, one added) stays reported.
  const iconMoved = (key) => {
    let k = key;
    for (let up = 0; up < 2; up++) {
      if (!k.includes(' > ')) return false;
      k = k.slice(0, k.lastIndexOf(' > '));
      const pm = mock.index[k], pa = app.index[k];
      if (!pm || !pa) return false;
      const n = pm.icons ?? 0;
      if (n > 0 && n <= 4 && n === (pa.icons ?? 0)) return true;
    }
    return false;
  };

  for (const key of Object.keys(mock.index)) {
    const m = mock.index[key];
    let a = app.index[key];
    let appKey = key;

    // --- TF-045: a badge the app draws at another depth is the same badge. Found by its text under
    // the same anchor, it is compared like any paired element, so a badge whose colour or ring really
    // differs is still reported, and so is one the app turned into plain text.
    if (!a && m.badge === true && m.text) {
      const root = key.split(' > ')[0];
      const cands = ((app.pool || {})[root] || []).filter((c) => !usedApp.has(c.key) && norm(c.text) === norm(m.text));
      // a badge first, then the same kind of element, then one no mockup key already pairs with;
      // among equals the shallowest, which is the order the probe found them in
      const score = (c) => (c.badge === true ? 4 : 0) + (c.tag === m.tag ? 2 : 0) + (c.key in mock.index ? 0 : 1);
      const pick = cands.reduce((best, c) => (!best || score(c) > score(best) ? c : best), null);
      if (pick) { a = pick; appKey = pick.key; usedApp.add(pick.key); relocated++; }
    }

    // --- the `missing` clause. Key-pairing alone cannot see an element that is
    // NOT THERE, and "a control the mockup draws as a badge rendered as plain text"
    // and "an icon omitted" are the first two rows of TF-008's own escape table.
    // A missing element has no signature to compare, so it needs its own clause.
    //
    // Deliberately narrow: only a mockup element that is CHROME (a badge/pill) or
    // CARRIES AN ICON is reported when absent, and only when its parent paired. An
    // unrestricted "the DOM shapes differ" report would fire on every incidental
    // wrapper div and become the always-present finding TF-012 warns about — the
    // fastest way to train a reader to skim the whole report.
    if (!a) {
      const parentKey = key.includes(' > ') ? key.slice(0, key.lastIndexOf(' > ')) : null;
      const parentPaired = parentKey ? !!app.index[parentKey] : false;
      // an icon is missing only when the paired parent carries fewer icons than the mockup's
      // does. Pairing is by position, so an icon the app draws one wrapper deeper sits under
      // another key and was reported missing on every sidebar group and tile (TF-027).
      // and no more reports under one parent than it is icons short
      if (m.icon === true && parentPaired && mock.index[parentKey] && !(parentKey in iconsShort)) {
        iconsShort[parentKey] = Math.max(0, (mock.index[parentKey].icons ?? 0) - (app.index[parentKey].icons ?? 0));
      }
      const iconGone = m.icon === true && parentPaired && (iconsShort[parentKey] || 0) > 0;
      if (iconGone && m.badge !== true) iconsShort[parentKey]--;
      // A badge not found by its text (live data reads otherwise) is missing only while the paired
      // parent draws fewer badges than the mockup's does, the rule icons follow since TF-027 (TF-045).
      if (m.badge === true && parentPaired && mock.index[parentKey] && !(parentKey in badgesShort)) {
        badgesShort[parentKey] = Math.max(0, (mock.index[parentKey].badges ?? 0) - (app.index[parentKey].badges ?? 0));
      }
      const badgeGone = m.badge === true && parentPaired && (badgesShort[parentKey] || 0) > 0;
      if (badgeGone) badgesShort[parentKey]--;
      if (parentPaired && (m.badge === true || iconGone)) {
        clauseCoverage.missing++;
        contentGraded++;
      }
      if (parentPaired && (m.badge === true ? badgeGone : iconGone)) {
        // Say what was seen. "Flattened into plain text" is true only when the app shows the text;
        // said of a badge the tool had merely failed to find, it sent a reader after a wrong cause.
        const shown = m.text && norm(app.index[parentKey].full).includes(norm(m.text));
        findings.push({
          screen, width, class: 'missing', key,
          detail: m.badge !== true
            ? `the mockup carries an icon here and the app renders no such element`
            : shown
              ? `the mockup draws a badge/pill here ("${m.text}"); the app shows that text with no badge/pill around it — the value is flattened into plain text`
              : `the mockup draws a badge/pill here ("${m.text}"); it could not be located in the app — no element under this parent carries that text, and the app draws ${app.index[parentKey].badges ?? 0} badge(s) there where the mockup draws ${mock.index[parentKey].badges ?? 0}`,
          mockup_text: m.text, app_text: null,
        });
      }
      continue;
    }
    compared++;
    for (const [name, fn] of Object.entries(CLAUSES)) {
      if (skip && skip.has(name)) continue;     // a clause the mockup says nothing about in this theme (TF-024)
      const r = fn(m, a);
      if (r === null) continue;
      clauseCoverage[name]++;
      if (CONTENT_CLAUSES.has(name)) contentGraded++;
      if (r) {
        if (name === 'icon' && iconMoved(key)) continue;   // the same icon, another child (TF-047)
        const f = { screen, width, class: name, key, ...(appKey !== key ? { app_key: appKey } : {}), detail: r, mockup_text: m.text, app_text: a.text };
        findings.push(f);
        if (name === 'icon') iconSeen.push({ f, side: m.icon ? m : a });
      }
    }
  }

  // --- TF-046: one icon, one finding. "Is there an icon inside?" is true of the element that carries
  // the icon and of every element above it, so each container repeated the finding. A finding is
  // dropped when every icon it holds is already reported on a deeper element, on the side that has
  // the icons; a container holding an extra icon of its own is still reported.
  const repeat = new Set();
  for (const x of iconSeen) {
    const ids = x.side.icon_ids || [];
    const below = new Set(iconSeen
      .filter((y) => y !== x && y.f.detail === x.f.detail && (y.side.depth ?? 0) > (x.side.depth ?? 0))
      .flatMap((y) => y.side.icon_ids || []));
    if (ids.length && ids.every((i) => below.has(i))) repeat.add(x.f);
  }
  return { findings: findings.filter((f) => !repeat.has(f)), compared, contentGraded, clauseCoverage, relocated, notMeasured };
}

// ---------------------------------------------------------------------- main
const results = [];
let hardFail = false;

const browser = await chromium.launch();
const ctxOpts = { ignoreHTTPSErrors: true };
if (STORAGE && existsSync(STORAGE)) ctxOpts.storageState = STORAGE;
const ctx = await browser.newContext(ctxOpts);
let cdpBrowser = null, cdpPage = null;
if (CDP) {
  try {
    cdpBrowser = await chromium.connectOverCDP(CDP, { timeout: 15000 });
    const c = cdpBrowser.contexts()[0];
    cdpPage = c && c.pages()[0];
  } catch (e) { console.error(`tf-mockup-parity: UNREACHABLE cdp ${CDP}: ${e.message.split('\n')[0]}`); }
  if (!cdpPage) {
    console.error(`tf-mockup-parity: UNREACHABLE cdp ${CDP}: no page in the attached app`);
    await browser.close(); process.exit(2);
  }
}
// the attached app's router, not a document load: a desktop head has no server to answer a goto
async function reachCdp(page, route) {
  try {
    await page.evaluate((r) => { history.pushState({}, '', r); window.dispatchEvent(new PopStateEvent('popstate', { state: {} })); }, route);
    await page.waitForTimeout(LOGIN_OPTS.settle);
    return { status: 200, url: page.url() };
  } catch (e) { return { status: 0, error: e.message.split('\n')[0] }; }
}
if (COOKIE && !CDP) {
  const u = new URL(BASE);
  for (const pair of COOKIE.split(';')) {
    const [name, ...v] = pair.trim().split('=');
    if (name && v.length) await ctx.addCookies([{ name: name.trim(), value: v.join('='), domain: u.hostname, path: '/' }]);
  }
}
if (HEADERS.length) {
  const h = {};
  for (const line of HEADERS) { const i = line.indexOf(':'); if (i > 0) h[line.slice(0, i).trim()] = line.slice(i + 1).trim(); }
  await ctx.setExtraHTTPHeaders(h);
}

// One app tab per width, signed in once and kept on the app, and one tab for the mockups. A sign-in
// the page keeps for itself lives in that tab: a fresh tab per screen would be signed out every time
// (AppManager TF-011). The mockup tab never touches the app, so the app tab never leaves it.
const tabs = {};
let loginResult = null;
for (const width of WIDTHS) {
  const size = { width, height: width < 700 ? 844 : 800 };
  const app = CDP ? cdpPage : await ctx.newPage(); if (!CDP) await app.setViewportSize(size);
  const mock = await ctx.newPage(); await mock.setViewportSize(size);
  if (!CDP && LOGIN_PATH && USER) { const l = await signIn(app, LOGIN_OPTS); if (loginResult === null) loginResult = l; }
  tabs[width] = { app, mock };
}
if (loginResult && loginResult.attempted && !loginResult.ok) console.error(`tf-mockup-parity: LOGIN failed at ${BASE}${LOGIN_PATH}: ${loginResult.error || 'still on the sign-in page'}`);

for (const s of SCREENS) {
  const mockPath = findMockup(s.name);
  // TF-008 §3: a screen with no mockup is reported, never silently passed — the
  // same discipline `⚠ STATIC-ONLY` already uses. Silence is not evidence.
  if (!existsSync(mockPath)) {
    results.push({ screen: s.name, route: s.route, verdict: 'NO-MOCKUP', mockup: mockPath,
      note: `no ${s.name}.html under ${MOCKUPS} (or several in its subfolders)${LIST ? ` and none named for it in ${LIST}` : '; pass --list tests/.artifacts/verify/list.json'} — this screen was NOT graded against a design. It must not license a Verified on design grounds.` });
    continue;
  }

  const perWidth = [];
  const notOffered = new Set();
  for (const width of WIDTHS) {
    const { app: page, mock: mockPage } = tabs[width];
    let mock, app, docFindings = [], reached = '', theme = null, own = 'light', ownSurface = null, mockSurface = null, wanted = [];
    try {
      await mockPage.goto(pathToFileURL(mockPath).href, { waitUntil: 'load' });
      mock = await mockPage.evaluate(PROBE);
      // The document may answer 401 and still draw the screen signed in (AppManager TF-006/TF-011):
      // reach() judges by what the page draws, signs in again from inside the page when it must, and
      // returns 200 only when the screen was really drawn signed in.
      if (CDP) await page.setViewportSize({ width, height: width < 700 ? 844 : 800 }).catch(() => {});
      const nav = CDP ? await reachCdp(page, s.route) : await reach(page, LOGIN_OPTS, s.route);
      if (nav.status === 0 || nav.status >= 400 || nav.signedOut) {
        perWidth.push({ width, error: nav.status === 0 ? `could not open ${s.route}: ${nav.error || 'no response'}`
          : nav.signedOut ? `app returned HTTP ${nav.document_status ?? nav.status} and stayed signed out (sign-in ${LOGIN_PATH && USER ? 'did not hold' : 'not given: --login-path/--user/--password or --cookie'})`
          : `app returned HTTP ${nav.status}` });
        continue;
      }
      reached = nav.reached || '';
      await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
      wanted = [...new Set(Object.values(mock.index).filter((x) => x.badge === true && x.text).map((x) => x.text))];
      // Lekhak TF-010: the app is drawn in the mockup's theme for the comparison. The app kept the
      // viewer's saved dark theme, the mockup was light, and every primary button read "mockup accent,
      // app neutral". The mockup's theme attributes on <html> and <body> are copied onto the app page
      // and the app's own are put back afterwards, so an attached app is left as the viewer had it.
      // Lekhak TF-013: a light/dark class on <html> or <body> is carried the same way, or a class-driven
      // dark mode (class="dark") kept its dark colours under the mockup's light data-theme.
      const mockRead = KEEP_APP_THEME ? null : await mockPage.evaluate(READ_THEME);
      const mockTheme = DECLARES_THEME(mockRead) ? mockRead : null;
      // The mockup's own theme: what it declares, or, declaring none, what it paints (TF-024). A mockup
      // that declares none now has the app put in that theme too (its colour scheme as well as its
      // attributes), so a viewer's saved dark theme no longer decides what a light mockup is compared with.
      mockSurface = await surface(mockPage);
      own = mockTheme ? (Object.values(mockTheme).some((v) => /dark/i.test(String(v || ''))) ? 'dark' : 'light')
        : looksDark(mockSurface) ? 'dark' : 'light';
      const saved = mockTheme ? await page.evaluate(APPLY_THEME, mockTheme).catch(() => null) : null;
      if (saved && saved.changed) { theme = { mockup: mockTheme, app_had: saved.before }; await page.waitForTimeout(400); }
      const putBack = KEEP_APP_THEME ? null : await useTheme(page, own);
      try { app = await page.evaluate(PROBE, wanted); ownSurface = await surface(page); }
      finally {   // in the reverse order they were put on
        if (putBack) await putBack();
        if (saved && saved.changed) await page.evaluate(APPLY_THEME, saved.before).catch(() => {});
      }

      // TF-008 §2. Cheap, no false positives in a shell-scrolled app, and it would
      // have caught the /routing void on its own: 2607px of document against a
      // 900px viewport, ~1700px of it blank, with the app shell repainted at the
      // bottom because the page had escaped the shell's scroll container. No gate
      // looked at document height, so that passed too.
      // Only when the shell has a content scroll container: an app whose document is its only
      // scroller (a long report page) has escaped nothing (AppManager TF-014).
      if (app.doc.scroller && app.doc.scrollHeight > app.doc.clientHeight + 2) {
        docFindings.push({
          screen: s.name, width, class: 'document-scroll', key: 'document',
          detail: `document.scrollHeight ${app.doc.scrollHeight} exceeds clientHeight ${app.doc.clientHeight} — the page has escaped the app shell's scroll container (${app.doc.scroller})`,
        });
      }
    } catch (e) {
      perWidth.push({ width, error: String(e).slice(0, 200) });
      continue;
    }
    const d = diff(mock, app, s.name, width);
    d.findings.push(...docFindings);
    if (wantTheme(own)) {
      perWidth.push({ width, mode: own, ...d, mockAnchors: mock.anchors, appAnchors: app.anchors,
        appTestIds: app.testids, mockTestIds: mock.testids, ...(reached ? { reached } : {}), ...(theme ? { theme } : {}) });
    }

    // --- Lekhak TF-024: the other theme. Both pages are drawn in it and put back after, so an
    // attached app is left in the viewer's theme. Every finding here says which theme it is in.
    const other = own === 'dark' ? 'light' : 'dark';
    if (KEEP_APP_THEME || !wantTheme(other)) continue;
    let backApp = null, backMock = null;
    try {
      backApp = await useTheme(page, other);
      backMock = await useTheme(mockPage, other, 0);
      if (!THEMES && !otherSeen && !differs(ownSurface, await surface(page))) { notOffered.add(other); continue; }
      otherSeen = true;
      // A mockup that does not change under the other theme does not draw it: forcing it there only
      // strips the styles it keys on its own theme (a badge losing its fill). The app in the other theme
      // is then compared with the mockup as drawn, colour left out.
      const mockDraws = differs(mockSurface, await surface(mockPage));
      if (!mockDraws) { await backMock(); backMock = null; }
      const mockO = mockDraws ? await mockPage.evaluate(PROBE) : mock;
      const appO = await page.evaluate(PROBE, wanted);
      const d2 = diff(mockO, appO, s.name, width, mockDraws ? null : new Set(['color']));
      for (const f of d2.findings) f.theme = other;
      perWidth.push({ width, mode: other, mockup_draws_theme: mockDraws, ...d2, mockAnchors: mockO.anchors, appAnchors: appO.anchors,
        appTestIds: appO.testids, mockTestIds: mockO.testids, ...(reached ? { reached } : {}) });
    } catch (e) {
      perWidth.push({ width, mode: other, error: String(e).slice(0, 200) });
    } finally {
      if (backMock) await backMock();
      if (backApp) await backApp();
    }
  }

  const ok = perWidth.filter((w) => !w.error);
  const findings = ok.flatMap((w) => w.findings).slice(0, MAX_FINDINGS_PER_SCREEN);
  const compared = ok.reduce((a, w) => a + (w.compared || 0), 0);
  const contentGraded = ok.reduce((a, w) => a + (w.contentGraded || 0), 0);
  const appAnchors = Math.max(0, ...ok.map((w) => w.appAnchors || 0));
  const mockAnchors = Math.max(0, ...ok.map((w) => w.mockAnchors || 0));

  // --- TF-011's central rule, encoded. A PASS from a gate whose stated purpose is
  // "a built screen is graded against its approved mockup, mechanically" must mean
  // the screen was GRADED. So a screen where no clause that requires reaching
  // inside a container ever fired is UNGRADEABLE, never PASS. Note the measure is
  // deliberately NOT an anchor ratio: `coverage` graded deeply off 8 body anchors
  // while `harness` graded nothing off 7, because the difference was table-vs-card,
  // not count. Count comparisons that could have produced a finding.
  //
  // An UNGRADEABLE screen is NOT-OBSERVABLE in checklist terms and must not license
  // a `Verified` — the same principle the perf gate already applies with
  // PERF-UNMEASURED.
  //
  // PRECEDENCE: a finding is positive evidence of a defect and outranks the absence
  // of evidence, so FAIL beats UNGRADEABLE. But a FAIL that graded nothing else must
  // not read as a thorough screen with one problem — `coverage.ungradeable` stays
  // true either way, so the report can say both things at once.
  const ungradeable = contentGraded === 0;
  let verdict;
  if (ok.length === 0) verdict = 'ERROR';
  else if (findings.length) verdict = 'FAIL';
  else if (ungradeable) verdict = 'UNGRADEABLE';
  else verdict = 'PASS';

  // --- TF-011 §2: report the anchor deficit as an ACTIONABLE list, so closing the
  // gap is mechanical rather than a research task.
  const mockSet = new Set(ok.flatMap((w) => w.mockTestIds || []));
  const unanchored = [...new Set(ok.flatMap((w) => w.appTestIds || []))].filter((t) => !mockSet.has(t));

  if (verdict === 'FAIL' || verdict === 'ERROR') hardFail = true;

  results.push({
    screen: s.name, route: s.route, verdict,
    coverage: {
      compared, content_graded: contentGraded, ungradeable,
      // badges found by their text at another depth than the mockup's (TF-045)
      relocated: ok.reduce((n, w) => n + (w.relocated || 0), 0),
      // sample boxes the app drew nothing at, so not compared (Chatur TF-002)
      not_measured: [...new Set(ok.flatMap((w) => w.notMeasured || []))],
      app_controls: appAnchors, mockup_anchors: mockAnchors,
      ratio: appAnchors ? +(compared / appAnchors).toFixed(2) : null,
      thin: appAnchors > 0 && compared / appAnchors < THIN_RATIO,
      by_clause: ok.reduce((acc, w) => {
        for (const [k, v] of Object.entries(w.clauseCoverage || {})) acc[k] = (acc[k] || 0) + v;
        return acc;
      }, {}),
    },
    findings_n: findings.length,
    findings,
    anchor_deficit: {
      n: unanchored.length,
      // Named so the fix is a mechanical edit to the mockup, not a research task.
      add_data_testid_to_mockup: unanchored.slice(0, 30),
    },
    // the themes it was compared in, and one the app showed no sign of having (TF-024)
    themes: [...new Set(ok.map((w) => w.mode).filter(Boolean))],
    ...(notOffered.size ? { themes_not_offered: [...notOffered] } : {}),
    widths: perWidth.map((w) => ({ width: w.width, ...(w.mode ? { mode: w.mode } : {}),
      ...(w.mockup_draws_theme === false ? { colour_not_compared: 'the mockup draws no ' + w.mode + ' theme' } : {}), error: w.error || null,
      compared: w.compared || 0, content_graded: w.contentGraded || 0, findings: (w.findings || []).length,
      not_measured: (w.notMeasured || []).length,
      ...(w.reached ? { reached: w.reached } : {}),       // how a 401 screen was reached signed in (TF-011)
      ...(w.theme ? { theme: w.theme } : {}) })),          // the app was drawn in the mockup's theme (Lekhak TF-010)
  });
}

await browser.close();
if (cdpBrowser) await cdpBrowser.close().catch(() => {});   // disconnects; the app keeps running

const summary = {
  status: 'measured',
  base: BASE || CDP, mode: CDP ? 'cdp' : 'base',
  widths: WIDTHS,
  screens_n: results.length,
  pass: results.filter((r) => r.verdict === 'PASS').length,
  fail: results.filter((r) => r.verdict === 'FAIL').length,
  ungradeable: results.filter((r) => r.verdict === 'UNGRADEABLE').length,
  // Counted separately from the verdict so a FAIL cannot hide the fact that the
  // rest of the screen was never graded (TF-011).
  screens_with_no_coverage: results.filter((r) => r.coverage && r.coverage.ungradeable).length,
  no_mockup: results.filter((r) => r.verdict === 'NO-MOCKUP').length,
  error: results.filter((r) => r.verdict === 'ERROR').length,
  findings_n: results.reduce((a, r) => a + (r.findings_n || 0), 0),
  screens: results,
};

const text = JSON.stringify(summary, null, 2);
console.log(text);
if (JSON_OUT) {
  mkdirSync(dirname(resolve(JSON_OUT)), { recursive: true });
  writeFileSync(resolve(JSON_OUT), text);
}

// 5 = at least one screen FAILed or errored. UNGRADEABLE and NO-MOCKUP are NOT
// failures — they are absences of evidence, and verify-phase §4b2 must treat them
// as NOT-OBSERVABLE rather than as either a pass or a defect. Exit 6 says at least
// one screen could not be graded, so a caller cannot read exit 0 as coverage.
process.exit(hardFail ? 5
  : (summary.ungradeable + summary.no_mockup + summary.screens_with_no_coverage > 0 ? 6 : 0));

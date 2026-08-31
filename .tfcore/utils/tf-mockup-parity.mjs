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
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// ---------------------------------------------------------------- arguments
const argv = process.argv.slice(2);
const arg = (name, dflt = null) => {
  const i = argv.indexOf(name);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : dflt;
};
const flag = (name) => argv.includes(name);

const BASE = (arg('--base') || '').replace(/\/$/, '');
const MOCKUPS = arg('--mockups', 'docs/mockups');
const WIDTHS = (arg('--widths', '1280,390') || '').split(',').map((w) => parseInt(w.trim(), 10)).filter(Boolean);
const JSON_OUT = arg('--json-out');
const COOKIE = arg('--cookie');
const HEADERS = [];
for (let i = 0; i < argv.length; i++) if (argv[i] === '--header' && argv[i + 1]) HEADERS.push(argv[i + 1]);
const SCREENS = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--screen' && argv[i + 1]) {
    const [name, ...rest] = argv[i + 1].split('=');
    SCREENS.push({ name: name.trim(), route: rest.join('=').trim() || '/' + name.trim() });
  }
}
const THIN_RATIO = parseFloat(arg('--thin-ratio', '0.25'));
const MAX_FINDINGS_PER_SCREEN = parseInt(arg('--max-findings', '40'), 10);

if (!BASE || SCREENS.length === 0) {
  console.error('usage: tf-mockup-parity.sh --base URL --screen name=/route [--screen ...]');
  process.exit(3);
}

// ------------------------------------------------------------ page-side probe
// Everything below runs INSIDE the browser, on both the mockup and the app, and
// returns one flat index keyed by a stable path key. It is deliberately one
// evaluate() call: two passes over the same DOM can disagree after a re-layout.
const PROBE = () => {
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

  const RGB = (v) => {
    const m = (v || '').match(/-?[\d.]+/g);
    if (!m || m.length < 3) return null;
    const a = m.length > 3 ? parseFloat(m[3]) : 1;
    return a < 0.05 ? null : { r: +m[0], g: +m[1], b: +m[2] };
  };

  // Semantic BUCKET, never the literal colour: two designs may legitimately differ
  // in shade, and grading the exact value would produce a finding on every screen.
  const bucket = (c) => {
    if (!c) return null;
    const { r, g, b } = c;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
    if (mx - mn < 28) return 'neutral';
    if (r > g && r > b) return g > 120 ? 'warning' : 'negative';
    if (g > r && g > b) return 'positive';
    if (b > r && b > g) return 'accent';
    return 'neutral';
  };

  const semanticColor = (el) => {
    const cs = getComputedStyle(el);
    return bucket(RGB(cs.backgroundColor)) || bucket(RGB(cs.borderTopColor)) || bucket(RGB(cs.color));
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
    const w = parseFloat(cs.borderTopWidth) || 0;
    const style = w === 0 ? 'none' : sides[0];
    return { style, uniform: new Set(sides).size === 1, visible: w > 0 };
  };

  const hasIcon = (el) => !!el.querySelector('svg, img, i[class*="icon"], span[class*="icon"], [class*="bi-"], [class*="fa-"]');

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
    const ringed = (parseFloat(cs.borderTopWidth) || 0) > 0;
    return { badge: (filled || ringed) && radius >= 6, filled, ringed, radius: Math.round(radius) };
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
    const h = el.getBoundingClientRect().height;
    if (!h || !lh) return null;
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
  const clipOf = (el) => {
    const hiddenKids = [...el.querySelectorAll('*')].filter(isHidden);
    let overX;
    if (hiddenKids.length === 0) {
      overX = el.scrollWidth - el.clientWidth;
    } else {
      const box = el.getBoundingClientRect();
      let right = box.left;
      for (const c of el.querySelectorAll('*')) {
        if (isHidden(c)) continue;
        const r = c.getBoundingClientRect();
        if (r.width > 0) right = Math.max(right, r.right);
      }
      overX = Math.max(0, Math.round(right - (box.left + el.clientWidth)));
    }
    const overY = el.scrollHeight - el.clientHeight;
    return { x: overX > 2, y: overY > 2, sr_excluded: hiddenKids.length };
  };

  const sigOf = (el) => {
    const r = el.getBoundingClientRect();
    const chrome = chromeOn(el);
    return {
      tag: el.tagName.toLowerCase(),
      text: (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 60),
      badge: chrome ? chrome.badge : null,
      icon: hasIcon(el),
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
  const keyOf = (el, parentKey) => {
    const tag = el.tagName.toLowerCase();
    let n = 0;
    for (const s of el.parentElement ? el.parentElement.children : []) {
      if (s === el) break;
      if (s.tagName === el.tagName) n++;
    }
    return `${parentKey} > ${tag}[${n}]`;
  };

  const index = {};
  const anchors = [...document.querySelectorAll('[data-testid]')];
  const allTestIds = anchors.map((a) => a.getAttribute('data-testid'));

  for (const a of anchors) {
    const id = a.getAttribute('data-testid');
    if (!id || index[id]) continue;
    if (isHidden(a)) continue;
    index[id] = sigOf(a);
    let budget = MAX_PER_ANCHOR;
    const walk = (el, key, depth) => {
      if (depth > MAX_DEPTH || budget <= 0) return;
      for (const c of el.children) {
        if (budget <= 0) return;
        if (c.hasAttribute('data-testid')) continue;   // it gets its own top-level entry
        if (isHidden(c)) continue;                     // TF-012
        const k = keyOf(c, key);
        index[k] = sigOf(c);
        budget--;
        walk(c, k, depth + 1);
      }
    };
    walk(a, id, 1);
  }

  const de = document.documentElement;
  return {
    index,
    anchors: anchors.length,
    testids: allTestIds,
    doc: {
      scrollHeight: de.scrollHeight,
      clientHeight: de.clientHeight,
      scrollWidth: de.scrollWidth,
      clientWidth: de.clientWidth,
    },
  };
};

// ------------------------------------------------------------------- diffing
// A clause returns a finding, `null` (not applicable — do NOT count it as graded),
// or `false` (applicable and agreeing). The three are kept distinct because
// conflating "agreed" with "not asked" is precisely how TF-011 happened.
const CLAUSES = {
  badge: (m, a) => (m.badge === null || a.badge === null ? null
    : m.badge !== a.badge
      ? `mockup renders this as a ${m.badge ? 'badge/pill' : 'plain element'}, app renders it as a ${a.badge ? 'badge/pill' : 'plain element'}`
      : false),
  icon: (m, a) => (m.icon === a.icon ? false
    : m.icon && !a.icon ? 'mockup carries an icon here; the app does not'
      : 'app carries an icon the mockup does not'),
  color: (m, a) => (m.color === null || a.color === null ? null
    : m.color !== a.color ? `semantic colour differs — mockup ${m.color}, app ${a.color}` : false),
  // TF-009
  stroke: (m, a) => {
    if (!m.stroke || !a.stroke) return null;
    if (m.stroke.style !== a.stroke.style) {
      return `border style differs — mockup ${m.stroke.style}, app ${a.stroke.style}`
        + (m.stroke.style === 'dashed' ? ' (a dashed rule is how a mockup says "estimate / provisional"; losing it makes an estimate look measured)' : '');
    }
    if (m.stroke.visible !== a.stroke.visible) {
      return `border presence differs — mockup ${m.stroke.visible ? 'has a visible rule' : 'has none'}, app ${a.stroke.visible ? 'has one' : 'has none'}`;
    }
    return false;
  },
  wrap: (m, a) => (m.wrap === null || a.wrap === null ? null
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

function diff(mock, app, screen, width) {
  const findings = [];
  const clauseCoverage = Object.fromEntries(Object.keys(CLAUSES).map((k) => [k, 0]));
  clauseCoverage.missing = 0;
  let compared = 0, contentGraded = 0;

  for (const key of Object.keys(mock.index)) {
    const m = mock.index[key];
    const a = app.index[key];

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
      if (parentPaired && (m.badge === true || m.icon === true)) {
        clauseCoverage.missing++;
        contentGraded++;
        findings.push({
          screen, width, class: 'missing', key,
          detail: m.badge
            ? `the mockup draws a badge/pill here ("${m.text}") and the app renders no such element — the value is flattened into plain text`
            : `the mockup carries an icon here and the app renders no such element`,
          mockup_text: m.text, app_text: null,
        });
      }
      continue;
    }
    compared++;
    for (const [name, fn] of Object.entries(CLAUSES)) {
      const r = fn(m, a);
      if (r === null) continue;
      clauseCoverage[name]++;
      if (CONTENT_CLAUSES.has(name)) contentGraded++;
      if (r) findings.push({ screen, width, class: name, key, detail: r, mockup_text: m.text, app_text: a.text });
    }
  }
  return { findings, compared, contentGraded, clauseCoverage };
}

// ---------------------------------------------------------------------- main
const results = [];
let hardFail = false;

const browser = await chromium.launch();
const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
if (COOKIE) {
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

for (const s of SCREENS) {
  const mockPath = resolve(MOCKUPS, `${s.name}.html`);
  // TF-008 §3: a screen with no mockup is reported, never silently passed — the
  // same discipline `⚠ STATIC-ONLY` already uses. Silence is not evidence.
  if (!existsSync(mockPath)) {
    results.push({ screen: s.name, route: s.route, verdict: 'NO-MOCKUP', mockup: mockPath,
      note: 'no docs/mockups/<screen>.html — this screen was NOT graded against a design. It must not license a Verified on design grounds.' });
    continue;
  }

  const perWidth = [];
  for (const width of WIDTHS) {
    const page = await ctx.newPage();
    await page.setViewportSize({ width, height: width < 700 ? 844 : 800 });
    let mock, app, docFindings = [];
    try {
      await page.goto(pathToFileURL(mockPath).href, { waitUntil: 'load' });
      mock = await page.evaluate(PROBE);
      const resp = await page.goto(BASE + s.route, { waitUntil: 'networkidle' });
      if (resp && resp.status() >= 400) {
        perWidth.push({ width, error: `app returned HTTP ${resp.status()}` });
        await page.close();
        continue;
      }
      app = await page.evaluate(PROBE);

      // TF-008 §2. Cheap, no false positives in a shell-scrolled app, and it would
      // have caught the /routing void on its own: 2607px of document against a
      // 900px viewport, ~1700px of it blank, with the app shell repainted at the
      // bottom because the page had escaped the shell's scroll container. No gate
      // looked at document height, so that passed too.
      if (app.doc.scrollHeight > app.doc.clientHeight + 2) {
        docFindings.push({
          screen: s.name, width, class: 'document-scroll', key: 'document',
          detail: `document.scrollHeight ${app.doc.scrollHeight} exceeds clientHeight ${app.doc.clientHeight} — the page has escaped the app shell's scroll container`,
        });
      }
    } catch (e) {
      perWidth.push({ width, error: String(e).slice(0, 200) });
      await page.close();
      continue;
    }
    const d = diff(mock, app, s.name, width);
    d.findings.push(...docFindings);
    perWidth.push({ width, ...d, mockAnchors: mock.anchors, appAnchors: app.anchors,
      appTestIds: app.testids, mockTestIds: mock.testids });
    await page.close();
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
    widths: perWidth.map((w) => ({ width: w.width, error: w.error || null,
      compared: w.compared || 0, content_graded: w.contentGraded || 0, findings: (w.findings || []).length })),
  });
}

await browser.close();

const summary = {
  status: 'measured',
  base: BASE,
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

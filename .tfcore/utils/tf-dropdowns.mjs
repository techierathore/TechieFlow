// tf-dropdowns.mjs — open every dropdown on a screen once and grade the list it shows (TfLens TF-058).
// Imported by tf-verify-screens.mjs; not run on its own.
//
// A closed picker matches its mockup whatever its list does. TfLens's repository picker opened a list as
// narrow as "All repos", so every name read "techierathore/", and every gate passed: the menu walk opens
// menus, not a Select's list, and a test that clicks an option by its text works when the text is cut.
//
// Each visible trigger is clicked once: [role="combobox"], [aria-haspopup="listbox"], and a picker built
// as a menu, [aria-haspopup="menu"|"true"] outside a menu bar (Chatur TF-031: a project picker built as a
// TrBlazeUI DropdownMenu was never opened; the menu bar is the menu walk's). The list is the box the
// trigger's aria-controls names, else the [role="listbox"] or [role="menu"] shown now. It is graded on:
//   - an option whose text is cut: the option, or an element inside it, holds more than it shows
//     (scrollWidth > clientWidth) without letting it spill, or the option reaches past the list's edge;
//   - an option whose own text wraps onto a second line in a list narrower than the window (Chatur TF-031:
//     every tier option wrapped in a 160 px list; a label and a description on two lines is no wrap);
//   - a list that opens outside the window.
// A native <select> is not opened (the system draws its list), but its closed box is the page's: a select
// whose widest option is wider than its box, less padding and the arrow, cuts its text (Lekhak TF-041; the
// rule of Lekhak's own cutSelects test: canvas text width in the select's own font).
// Pickers inside a dialog (Sevak TF-038): each visible [aria-haspopup="dialog"] trigger that ends nothing is
// clicked, the pickers in the dialog it opens are graded the same way, and the dialog is closed. A list is
// closed by a click on its trigger before Escape, so a dialog holding it stays open.
// Nothing is chosen. A trigger that opens no list (disabled in this state, or a search box that waits for
// typing) is passed over. The result says how many lists were opened and which pickers the mockup draws
// inside another state of the screen were not reached, so a clean result is not read as "every list measured".

const TRIG = '[role="combobox"],[aria-haspopup="listbox"],[aria-haspopup="menu"],[aria-haspopup="true"]';
const LIST = '[role="listbox"],[role="menu"]';

const MEASURE = (i) => {
  const trig = document.querySelector(`[data-tf-dd="${i}"]`);
  if (!trig) return null;
  const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden'; };
  const id = trig.getAttribute('aria-controls');
  const lb = [id && document.getElementById(id), ...document.querySelectorAll('[role="listbox"],[role="menu"]')]
    .find((x) => x && vis(x) && !x.closest('[role="menubar"]') && !x.contains(trig));
  if (!lb) return null;
  const opts = [...lb.querySelectorAll('[role="option"],[role^="menuitem"]')].filter(vis);
  if (!opts.length) return null;
  const box = lb.getBoundingClientRect();
  const short = (el) => el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1 && getComputedStyle(el).overflowX !== 'visible';
  const txt = (o) => (o.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 50);
  const cut = opts.filter((o) => short(o) || [...o.querySelectorAll('*')].some(short) || o.getBoundingClientRect().right > box.right + 1).map(txt);
  // a text run broken across lines: the line boxes of one text node, told apart by their top edge
  const wraps = (o) => {
    const w = document.createTreeWalker(o, NodeFilter.SHOW_TEXT);
    for (let n = w.nextNode(); n; n = w.nextNode()) {
      if (!n.textContent.trim()) continue;
      const r = document.createRange(); r.selectNodeContents(n);
      const tops = new Set([...r.getClientRects()].filter((x) => x.width > 0).map((x) => Math.round(x.top / 4)));
      if (tops.size > 1) return true;
    }
    return false;
  };
  const wrapped = box.width < innerWidth - 32 ? opts.filter(wraps).map(txt) : [];
  const off = box.left < -1 || box.top < -1 || box.right > innerWidth + 1 || box.bottom > innerHeight + 1;
  const name = trig.getAttribute('aria-label') || trig.getAttribute('data-testid') || trig.closest('[data-testid]')?.getAttribute('data-testid')
    || (trig.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40);
  return { name, cut, wrapped, of: opts.length, width: Math.round(box.width), off };
};

// the native selects in `scope` whose widest option does not fit the closed box
const SELECTS = (scope) => {
  const root = scope ? document.querySelector(scope) : document;
  if (!root) return [];
  const cv = document.createElement('canvas').getContext('2d');
  const out = [];
  for (const s of root.querySelectorAll('select')) {
    const r = s.getBoundingClientRect();
    if (!(r.width > 0 && r.height > 0) || s.multiple || s.size > 1 || !s.options.length) continue;
    const cs = getComputedStyle(s);
    cv.font = `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
    const room = s.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) - (cs.appearance === 'none' ? 0 : 20);
    let widest = 0, text = '';
    for (const o of s.options) { const w = cv.measureText(o.text).width; if (w > widest) { widest = w; text = o.text; } }
    if (widest > room + 1) {
      out.push({ name: s.getAttribute('aria-label') || s.getAttribute('data-testid') || s.closest('[data-testid]')?.getAttribute('data-testid') || s.id || s.name || 'a select',
        text: text.slice(0, 50), need: Math.round(widest), room: Math.round(room) });
    }
  }
  return out;
};

// mark the triggers inside `scope` (a dialog) or on the page, outside any dialog; returns their marks
const MARK = ({ trig, scope, from }) => {
  const root = scope ? document.querySelector(scope) : document;
  if (!root) return [];
  const t = [...root.querySelectorAll(trig)].filter((el) => {
    const r = el.getBoundingClientRect();
    return el.tagName !== 'SELECT' && r.width > 0 && r.height > 0 && !el.disabled && el.getAttribute('aria-disabled') !== 'true'
      && !el.closest('[role="menubar"],[role="menu"],[role="listbox"]') && (scope || !el.closest('[role="dialog"],[role="alertdialog"],dialog[open]'))
      && !el.hasAttribute('data-tf-dd');
  });
  return t.map((el, k) => { el.setAttribute('data-tf-dd', String(from + k)); return String(from + k); });
};

async function gradeList(page, i, width, o, out, tally, where) {
  const trig = page.locator(`[data-tf-dd="${i}"]`).first();
  if (await trig.click({ timeout: 3000 }).then(() => false, () => true)) return;
  let got = null;
  for (let t = 0; t < o.settle && !got; t += 150) { await page.waitForTimeout(150); got = await page.evaluate(MEASURE, i).catch(() => null); }
  // closed by its own trigger first, so a dialog around it stays open; Escape only when that leaves it open
  if (got) await trig.click({ timeout: 2000 }).catch(() => {});
  await page.waitForTimeout(150);
  if (await page.evaluate(MEASURE, i).catch(() => null)) { await page.keyboard.press('Escape').catch(() => {}); await page.waitForTimeout(150); }
  if (!got) return;
  tally.opened++; tally.names.push(got.name);
  const at = `${where}at ${width}px`;
  if (got.cut.length) out.push({ check: 'visual', class: 'clipped', detail: `the list of "${got.name}" cuts ${got.cut.length} option(s) short ${at}, such as "${got.cut[0]}"` });
  if (got.wrapped.length) out.push({ check: 'visual', class: 'clipped', detail: `the list of "${got.name}" is too narrow: ${got.wrapped.length} of ${got.of} option(s) wrap onto a second line in its ${got.width} px ${at}, such as "${got.wrapped[0]}"` });
  if (got.off) out.push({ check: 'visual', class: 'offscreen', detail: `the list of "${got.name}" opens outside the window ${at}` });
}

const ENDS = /\b(exit|quit|sign out|log ?out|delete|remove|uninstall|reset|discard)\b/i;

// -> [{ check: 'visual', class, detail }] for the screen open in page, at this width; the array also
// carries `.tally` = { opened, triggers, selects, dialogs, names }
export async function dropdownFindings(page, width, o = {}) {
  const opt = { max: o.max ?? 8, settle: o.settle ?? 900 };
  await page.evaluate(() => document.querySelectorAll('[data-tf-dd]').forEach((x) => x.removeAttribute('data-tf-dd'))).catch(() => {});
  const out = [], tally = { opened: 0, triggers: 0, selects: 0, dialogs: 0, names: [] };
  const marks = await page.evaluate(MARK, { trig: TRIG, scope: null, from: 0 }).catch(() => []);
  tally.triggers += marks.length;
  for (const i of marks.slice(0, opt.max)) await gradeList(page, i, width, opt, out, tally, '');
  const cutSel = (list, where) => { for (const s of list) out.push({ check: 'visual', class: 'clipped', detail: `the select "${s.name}" cuts its text ${where}at ${width}px: "${s.text}" needs ${s.need} px, the box has ${s.room} px` }); };
  const sel = await page.evaluate(SELECTS, null).catch(() => []);
  tally.selects += await page.evaluate(() => document.querySelectorAll('select').length).catch(() => 0);
  cutSel(sel, '');
  // the dialogs this screen opens through a dialog trigger, each once
  const openers = await page.evaluate((ends) => [...document.querySelectorAll('[aria-haspopup="dialog"]')].filter((el) => {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && !el.disabled && !new RegExp(ends, 'i').test(el.textContent || '') && !el.closest('[role="dialog"],dialog[open]');
  }).map((el, k) => { el.setAttribute('data-tf-dlg', String(k)); return String(k); }), ENDS.source).catch(() => []);
  let next = 1000;
  for (const k of openers.slice(0, o.dialogs ?? 4)) {
    const op = page.locator(`[data-tf-dlg="${k}"]`).first();
    if (await op.click({ timeout: 3000 }).then(() => false, () => true)) continue;
    const dlg = '[role="dialog"]:not([data-tf-dlg-seen]),[role="alertdialog"]:not([data-tf-dlg-seen]),dialog[open]:not([data-tf-dlg-seen])';
    const shown = await page.waitForSelector(dlg, { state: 'visible', timeout: 2500 }).then(() => true, () => false);
    if (!shown) continue;
    tally.dialogs++;
    const label = await page.evaluate((k) => { const el = document.querySelector(`[data-tf-dlg="${k}"]`); return (el?.getAttribute('data-testid') || el?.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40); }, k).catch(() => k);
    const scope = '[data-tf-dlg-open]';
    await page.evaluate((sel) => { const d = [...document.querySelectorAll(sel)].pop(); if (d) d.setAttribute('data-tf-dlg-open', ''); }, dlg).catch(() => {});
    const inner = await page.evaluate(MARK, { trig: TRIG, scope, from: next }).catch(() => []);
    next += 100; tally.triggers += inner.length;
    for (const i of inner.slice(0, opt.max)) await gradeList(page, i, width, opt, out, tally, `in the dialog "${label}" `);
    cutSel(await page.evaluate(SELECTS, scope).catch(() => []), `in the dialog "${label}" `);
    await page.keyboard.press('Escape').catch(() => {});
    await page.waitForSelector(scope, { state: 'detached', timeout: 2000 }).catch(() => {});
    await page.evaluate(() => document.querySelectorAll('[data-tf-dlg-open]').forEach((d) => { d.removeAttribute('data-tf-dlg-open'); d.setAttribute('data-tf-dlg-seen', ''); })).catch(() => {});
  }
  out.tally = tally;
  return out;
}

// The pickers a mockup draws inside another state of the screen (a dialog, a later step, data-tf-state),
// by the anchor that names them: what a clean result has not measured unless the app's own list was opened.
export async function mockupStatePickers(browser, mockupUrl) {
  if (!browser || !mockupUrl) return [];
  let ctx;
  try {
    ctx = await browser.newContext(); const p = await ctx.newPage();
    await p.goto(mockupUrl, { waitUntil: 'load', timeout: 15000 });
    return await p.evaluate(() => [...document.querySelectorAll('select,[role="combobox"],[aria-haspopup="listbox"],[aria-haspopup="menu"],button.pick')]
      .filter((el) => el.closest('[data-tf-state]:not([data-tf-state="sample-data"]):not([data-tf-state="popup-open"]),[data-state-testid]'))
      .map((el) => ({ id: el.getAttribute('data-testid') || el.closest('[data-testid]')?.getAttribute('data-testid') || '',
        state: el.closest('[data-tf-state],[data-state-testid]').getAttribute('data-tf-state') || 'another state' }))
      .filter((x) => x.id));
  } catch (e) { return []; } finally { if (ctx) await ctx.close().catch(() => {}); }
}

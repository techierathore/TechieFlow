// tf-menus.mjs — open every menu, click every item, and say which screens a click reaches (Chatur TF-011).
// Imported by tf-verify-screens.mjs and tf-mockup-parity.mjs; not run on its own.
//
// Both gates used to load each route directly and compare the closed page with its mockup. A closed
// menu bar matches its mockup, so File, Edit and View holding only "Nothing to do yet" passed, and
// Settings, Prerequisites and Repository passed though no click in the desktop app opened them.
//
// The mockup says what the menus are: a box marked data-tf-state="popup-open" is a menu or drop-down
// drawn open, and the nearest box around it with a data-testid is what opens it. For each one the app
// draws, the walk opens it and grades it against the mockup:
//   - an item the mockup draws and the app lacks;
//   - a menu whose every item is disabled where the mockup draws one enabled (a single disabled item
//     is the state the app is in, no file open, and is only noted in the JSON);
//   - placeholder text ("Nothing to do yet", "Coming soon", "Not built yet", "TODO", and any
//     --placeholder-text a project adds) the mockup does not itself draw;
//   - an enabled item that does nothing when clicked: no address, window, dialog, zoom, text or theme
//     changed. A choice that is already the state (Light, in a light app) is clicked again after a
//     sibling has moved the state, and the theme the walk changed is put back (Sevak TF-006).
// An item the mockup marks data-tf-sample is sample data and is not owed by its label; a pick-list (a
// select's options) is checked but not clicked; a trigger disabled in this state is passed over. A menu inside
// a box marked as another state (data-tf-state="mockup-only" …) is not owed at all. An item whose
// label ends the session or the work (Exit, Quit, Sign out, Log out, Close …, Delete, Remove, and any
// --no-click pattern) is checked but never clicked. A mockup that marks no menu still has the app's own menus opened: every
// [aria-haspopup="menu"|"true"] and every trigger in a [role=menubar], graded on placeholder text and on
// items that do nothing. A popup that is not a menu (a popover, role="group") is the box the trigger's
// aria-controls names.
// A menu item the mockup links to another mockup (<a href="prerequisites.html">) is the way into that
// screen. reachability() says which screens had such a way in and were reached by none of those clicks.

export const PLACEHOLDERS = ['Nothing to do yet', 'Coming soon', 'Not built yet', 'Not implemented yet', 'TODO'];
export const NO_CLICK = ['exit', 'quit', 'sign out', 'log out', 'logout', 'close', 'delete', 'remove', 'uninstall'];

// "Nothing to do yet" in any case; "TODO" only in capitals, so a board's "To do" column is not one
export const placeholderRe = (extra = []) => [...PLACEHOLDERS, ...extra].map((p) =>
  new RegExp(`(^|[^A-Za-z])${p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^A-Za-z])`, p === p.toUpperCase() ? '' : 'i'));

export const norm = (s) => String(s || '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
// the same item: one label is the other plus at most two short words (a shortcut: "Settings… Ctrl+,"),
// so "Run" is not "Run queue…"
const sameLabel = (a, b) => {
  const [x, y] = [norm(a), norm(b)].sort((p, q) => p.length - q.length);
  if (x.length < 2) return false;
  if (x === y) return true;
  if (!y.startsWith(x + ' ')) return false;
  const extra = y.slice(x.length + 1).split(' ');
  return extra.length <= 2 && extra.every((w) => w.length <= 4);
};

// --------------------------------------------------------------- the mockup's menus (in the page)
const READ_MOCK = (attr) => {
  const ITEM = 'button, a[href], [role^="menuitem"], [role="option"]';
  const label = (el) => {
    const c = el.cloneNode(true);
    c.querySelectorAll('.sub, kbd, .tick, [class*="shortcut"], svg, [data-shortcut]').forEach((x) => x.remove());
    return (c.textContent || '').replace(/\s+/g, ' ').trim();
  };
  const out = [];
  for (const p of document.querySelectorAll('[data-tf-state="popup-open"]')) {
    if (p.parentElement && p.parentElement.closest('[data-tf-state="popup-open"]')) continue;          // a submenu
    if (p.parentElement && p.parentElement.closest('[data-tf-state]:not([data-tf-state="popup-open"]):not([data-tf-state="sample-data"]),[data-state-testid]')) continue;
    const wrap = p.parentElement && p.parentElement.closest(`[${attr}]`);
    const btn = wrap && [...wrap.querySelectorAll('button, [role="button"], [role="menuitem"]')].find((b) => !p.contains(b));
    const items = [...p.querySelectorAll(ITEM)]
      .filter((el) => !el.parentElement.closest(ITEM) || el.parentElement.closest(ITEM) === el)
      .filter((el) => { const sub = el.closest('[data-tf-state="popup-open"]'); return sub === p; })
      .map((el) => ({ label: label(el), disabled: !!el.disabled || el.getAttribute('aria-disabled') === 'true',
        href: el.tagName === 'A' ? (el.getAttribute('href') || '') : '',
        sample: !!el.closest('[data-tf-sample],[data-tf-state="sample-data"]') }))
      .filter((x) => x.label);
    out.push({ popup: p.getAttribute(attr) || '', trigger: wrap ? wrap.getAttribute(attr) : '', trigger_text: btn ? label(btn) : '',
      text: (p.textContent || '').replace(/\s+/g, ' ').trim(), items });
  }
  return out;
};

export async function mockupMenus(page, attr = 'data-testid') {
  try { return await page.evaluate(READ_MOCK, attr); } catch (e) { return []; }
}

// --------------------------------------------------------------- the app's side (in the page)
const MENU_SEL = '[role="menu"], [role="listbox"], [role="menubar"] [data-state="open"], [data-tf-menu-open]';
const APP_ITEMS = ({ popupId, attr, controls }) => {
  const ITEM = '[role^="menuitem"], [role="option"], button, a[href]';
  const vis = (el) => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
  // the popup by its name when the app carries it; any open menu only when it does not (the walk closes
  // every menu before it opens one, so an open one is the one just opened)
  let box = popupId ? document.querySelector(`[${attr}="${CSS.escape(popupId)}"]`) : null;
  // a popover opened by an aria-haspopup trigger is no menu: it is the box the trigger's aria-controls names
  if ((!box || !vis(box)) && controls) { const c = document.getElementById(controls); if (c && vis(c)) { box = c; c.setAttribute('data-tf-walk-popup', ''); } }
  if (!box) box = [...document.querySelectorAll('[role="menu"], [role="listbox"]')].filter(vis).pop() || null;
  if (!box || !vis(box)) return null;
  document.querySelectorAll('[data-tf-walk]').forEach((el) => el.removeAttribute('data-tf-walk'));   // an earlier menu's marks
  const text = (el) => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
  const items = [...box.querySelectorAll(ITEM)].filter(vis)
    .filter((el) => { const up = el.parentElement && el.parentElement.closest(ITEM); return !up || !box.contains(up) || up === box; })
    .map((el, i) => {
      el.setAttribute('data-tf-walk', String(i));
      // the value already chosen does nothing when chosen again, so it is never "an item that does nothing"
      const checked = el.getAttribute('aria-checked') === 'true' || el.getAttribute('aria-selected') === 'true' || el.getAttribute('data-state') === 'checked'
        || !!el.querySelector('svg[class*="check"], [data-icon="check"], [data-lucide="check"]') || /✓|✔/.test(el.textContent || '');
      // disabled by attribute, or by taking no pointer events at all (TrBlazeUI's menu items set only
      // pointer-events:none and half opacity, with no aria-disabled)
      return { i, label: text(el), disabled: el.matches(':disabled') || el.getAttribute('aria-disabled') === 'true' || el.hasAttribute('data-disabled')
        || getComputedStyle(el).pointerEvents === 'none',
        checkbox: /checkbox/.test(el.getAttribute('role') || '') || (el.hasAttribute('aria-checked') && !/radio/.test(el.getAttribute('role') || '')), checked };
    });
  const choice = box.getAttribute('role') === 'listbox' || (items.length > 0 && [...box.querySelectorAll('[data-tf-walk]')].every((e) => e.getAttribute('role') === 'option'));
  return { found_by: box.getAttribute(attr) === popupId ? 'testid' : 'role', text: text(box), items, choice };
};

// What a click can change, menus left out: the address, the text a reader sees, open dialogs, the zoom,
// the theme (light/dark classes and data-*theme attributes on <html> and <body>, and what they paint).
const SIGNATURE = (menuSel) => {
  const inMenu = (n) => { const e = n.nodeType === 1 ? n : n.parentElement; return !!(e && e.closest(menuSel + ', [data-tf-walk-popup]')); };
  const parts = [];
  const w = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
  for (let n = w.nextNode(); n; n = w.nextNode()) {
    const t = n.textContent.trim();
    if (!t || inMenu(n)) continue;
    const e = n.parentElement;
    if (e && e.checkVisibility && !e.checkVisibility({ visibilityProperty: true, opacityProperty: true })) continue;
    parts.push(t);
  }
  let h = 0; const s = parts.join('\u0001');
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  const dialogs = [...document.querySelectorAll('[role="dialog"], [role="alertdialog"], dialog[open]')]
    .filter((d) => { const r = d.getBoundingClientRect(); return r.width > 0 && r.height > 0; }).length;
  const ids = [...document.querySelectorAll('[data-testid]')].filter((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && !inMenu(e); })
    .map((e) => e.getAttribute('data-testid')).slice(0, 400);
  const MODE = /^(?:(?:theme|mode|scheme|color)[-_])?(?:dark|light)(?:[-_](?:theme|mode|scheme))?$/i;
  const look = [document.documentElement, document.body].filter(Boolean).map((el) => {
    const cs = getComputedStyle(el);
    return [[...el.classList].filter((c) => MODE.test(c)).sort().join(' '),
      [...el.attributes].filter((a) => /^data-.*(theme|mode|scheme)/i.test(a.name)).map((a) => `${a.name}=${a.value}`).sort().join(' '),
      cs.backgroundColor, cs.colorScheme].join('|');
  }).join('||');
  return { url: location.href, text: h, len: s.length, dialogs, zoom: `${window.devicePixelRatio}|${getComputedStyle(document.documentElement).zoom || ''}|${document.body ? document.body.style.zoom : ''}`, look, ids };
};
const changed = (a, b) => a.url !== b.url || a.text !== b.text || a.dialogs !== b.dialogs || a.zoom !== b.zoom || a.look !== b.look;
const effectOf = (before, after) => !before || !after ? 'unknown' : before.url !== after.url ? 'navigated' : before.dialogs !== after.dialogs ? 'opened a dialog'
  : before.zoom !== after.zoom ? 'zoomed' : before.look !== after.look ? 'changed the theme' : before.text !== after.text ? 'changed the page' : 'nothing';

// A point on plain text, outside every menu, list, dialog and control, to click a menu shut.
const NEUTRAL = () => {
  const CTRL = 'a, button, input, select, textarea, label, summary, [role="button"], [role="menuitem"], [role="tab"], [role="link"], [role="option"], [role="combobox"], [role="menu"], [role="listbox"], [role="dialog"], [onclick], [tabindex]';
  const W = window.innerWidth, H = window.innerHeight;
  for (let y = 0.15; y < 1; y += 0.1) for (let x = 0.05; x < 1; x += 0.1) {
    const e = document.elementFromPoint(W * x, H * y);
    if (!e || e === document.documentElement || e.closest(CTRL)) continue;
    return { x: Math.round(W * x), y: Math.round(H * y) };
  }
  return null;
};

// --------------------------------------------------------------- the walk
// page: the app tab on a screen that draws these menus. o.back(): reopens that screen as it was.
// o.pages(): every app tab/window open now (a desktop head's new window, a web app's new tab).
// Returns { menus: [...what each menu held and did...], findings: [{detail, class, popup}], clicks: [...] }
export async function walkMenus(page, mockMenus, o = {}) {
  const attr = o.attr || 'data-testid';
  const settle = o.settle ?? 1200;
  const pr = placeholderRe(o.placeholders || []);
  const noClick = [...NO_CLICK, ...(o.noClick || [])].map((x) => norm(x));
  const pagesNow = o.pages || (async () => page.context().pages());
  const findings = [], clicks = [], menus = [];
  // o.mockText: the mockup's own text, so a placeholder the design itself draws is not held against the app
  const placeholderIn = (t) => pr.find((re) => re.test(t) && !re.test(o.mockText || ''));
  const says = (m) => m.trigger_text || m.trigger || m.popup || 'a menu';

  let list = (mockMenus || []).filter((m) => m.items.length);
  const fromMockup = list.length > 0;
  if (!fromMockup) {
    // the app's own menus, when the mockup marks none
    const found = await page.evaluate(({ attr }) => {
      const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
      const t = [...document.querySelectorAll('[aria-haspopup="menu"], [aria-haspopup="true"], [role="menubar"] [role="menuitem"], [role="menubar"] button')].filter(vis);
      return t.map((el, i) => { el.setAttribute('data-tf-walk-trigger', String(i)); return { trigger: '', trigger_walk: String(i), trigger_text: (el.innerText || el.getAttribute('aria-label') || '').trim().slice(0, 40), popup: '', items: [] }; });
    }, { attr }).catch(() => []);
    list = found;
  }

  // Opens one menu. Returns its items, or why not: { missing } (the render check reports a missing
  // control; a screen in another state, with no project open, draws no such trigger), { disabled } (a
  // trigger disabled in this state: not a finding), { opened: false }. When the trigger is gone because the
  // last click moved the screen on, the screen is reopened once.
  const findTrigger = async (m) => {
    let trig = m.trigger_walk ? page.locator(`[data-tf-walk-trigger="${m.trigger_walk}"]`) : m.trigger ? page.locator(`[${attr}="${m.trigger}"]`) : null;
    if (!m.trigger && !m.trigger_walk && m.trigger_text) trig = page.getByRole('menuitem', { name: m.trigger_text, exact: true }).or(page.getByRole('button', { name: m.trigger_text, exact: true }));
    return trig && (await trig.count()) ? trig.first() : null;
  };
  // Escape does not close every menu bar (TrBlazeUI's stays open, and so does it on a click in an empty
  // corner), so: Escape, then a click on plain text outside any menu or control, then the trigger
  // again, and last the screen reopened, until no menu or list is open
  const anyOpen = () => page.evaluate(() => [...document.querySelectorAll('[role="menu"], [role="listbox"], [data-tf-walk-popup]')]
    .some((e) => { const r = e.getBoundingClientRect(); const c = getComputedStyle(e); return r.width > 0 && r.height > 0 && c.visibility !== 'hidden'; })).catch(() => false);
  const shut = async (m) => {
    for (let k = 0; k < 3 && await anyOpen(); k++) {
      if (k === 0) await page.keyboard.press('Escape').catch(() => {});
      else if (k === 1) { const pt = await page.evaluate(NEUTRAL).catch(() => null); if (pt) await page.mouse.click(pt.x, pt.y).catch(() => {}); }
      else if (m) { const t = await findTrigger(m); if (t) await t.click({ timeout: 2000 }).catch(() => {}); }
      await page.waitForTimeout(200);
    }
    // one that will not close (a TrBlazeUI menu after an item that did nothing) goes with the screen
    if (o.back && await anyOpen()) await o.back();
  };
  const open = async (m, retry = true) => {
    await shut(m);
    let trig = await findTrigger(m);
    if (!trig && retry && o.back) { await o.back(); trig = await findTrigger(m); }
    if (!trig) return { missing: true };
    const inner = trig.locator('button, [role="button"], [role="menuitem"], [role="combobox"]').first();
    const tries = [trig];
    if (await inner.count()) tries.push(inner);
    // a trigger that is itself disabled, or whose only button is, cannot be opened in this state
    const off = async (l) => l.evaluate((e) => e.matches(':disabled') || e.getAttribute('aria-disabled') === 'true').catch(() => false);
    if (await off(trig) || (tries.length > 1 && await off(inner))) return { disabled: true };
    // a trigger clicked before the page is interactive, or toggled open and shut by one click, is
    // clicked again: three times at most
    for (const t of [...tries, tries[0], tries[0]]) {
      await t.click({ timeout: 3000 }).catch(() => {});
      await page.waitForTimeout(250);
      m.controls = (await t.getAttribute('aria-controls').catch(() => null)) || (await trig.getAttribute('aria-controls').catch(() => null)) || m.controls || '';
      for (let k = 0; k < 8; k++) {
        const items = await page.evaluate(APP_ITEMS, { popupId: m.popup, attr, controls: m.controls }).catch(() => null);
        if (items && items.items.length) return items;
        await page.waitForTimeout(150);
      }
    }
    return { opened: false };
  };
  // the item with that label in the menu as it is drawn now: a menu that redraws itself when it opens
  // (Blazor re-rendering on the trigger's pointerdown) has dropped the marks the first reading put on it
  const current = async (m, label) => {
    await page.waitForTimeout(200);
    const now = await page.evaluate(APP_ITEMS, { popupId: m.popup, attr, controls: m.controls }).catch(() => null);
    return now && now.items.find((x) => x.label === label);
  };
  // one item clicked from a freshly opened menu, for the second look and the putting back below
  const press = async (m, label) => {
    const again = await open(m);
    const fresh = again.items && await current(m, label);
    if (!fresh || fresh.disabled) { await shut(m); return 'menu did not reopen'; }
    const before = await page.evaluate(SIGNATURE, MENU_SEL).catch(() => null);
    await page.locator(`[data-tf-walk="${fresh.i}"]`).first().click({ timeout: 3000 }).catch(() => {});
    let after = null;
    for (let t = 0; t < settle; t += 150) {
      await page.waitForTimeout(150);
      after = await page.evaluate(SIGNATURE, MENU_SEL).catch(() => null);
      if (before && after && changed(before, after)) break;
    }
    await page.keyboard.press('Escape').catch(() => {});
    await shut(m);
    return effectOf(before, after);
  };

  for (const m of list) {
    const name = says(m);
    const got = await open(m);
    const rec = { popup: m.popup, trigger: m.trigger || m.trigger_text, mockup_items: m.items.length, items: [] };
    menus.push(rec);
    if (got.missing) { rec.result = 'no trigger on the page (the render check reports a missing control)'; continue; }
    if (got.disabled) { rec.result = 'trigger disabled in this state'; continue; }
    if (got.opened === false) {
      findings.push({ class: 'menu', popup: m.popup, detail: `the menu "${name}" opens nothing when clicked` });
      rec.result = 'did not open'; continue;
    }
    rec.items = got.items.map((x) => ({ label: x.label, disabled: x.disabled }));
    const ph = placeholderIn(got.text);
    if (ph) findings.push({ class: 'placeholder', popup: m.popup, detail: `the menu "${name}" shows placeholder text "${got.text.match(ph)[0].trim()}"` });
    // what the mockup owes. One item disabled is the state the app is in (no file open, nothing to
    // redo), so it is noted; a menu whose every item is disabled where the mockup draws one enabled is
    // a menu that does nothing, which is a finding.
    const offVsMock = [];
    for (const want of m.items) {
      if (want.sample) continue;
      const have = got.items.find((x) => sameLabel(x.label, want.label));
      // drawn as a heading in the menu rather than an item ("Recent projects" over the list) is drawn
      if (!have && norm(want.label).length >= 6 && ` ${norm(got.text)} `.includes(` ${norm(want.label)} `)) continue;
      if (!have) findings.push({ class: 'menu', popup: m.popup, detail: `the menu "${name}" has no "${want.label}" item, which the mockup draws` });
      else if (have.disabled && !want.disabled) offVsMock.push(have.label);
    }
    if (offVsMock.length) rec.disabled_where_mockup_enabled = offVsMock;
    if (got.items.every((x) => x.disabled) && m.items.some((x) => !x.disabled))
      findings.push({ class: 'menu', popup: m.popup, detail: `every item of the menu "${name}" is disabled; the mockup draws ${m.items.filter((x) => !x.disabled).length} of them enabled` });
    // a pick-list (a select's options) chooses a value; its items are the data, not commands to click
    if (got.choice) { rec.result = 'pick-list: items checked, not clicked'; await shut(m); continue; }
    const startLook = ((await page.evaluate(SIGNATURE, MENU_SEL).catch(() => null)) || {}).look;
    const mine = [];
    // click every enabled item, one at a time, from a freshly opened menu
    for (const item of got.items) {
      const want = m.items.find((x) => sameLabel(item.label, x.label));
      const c = { popup: m.popup, menu: name, label: item.label, href: want ? want.href : '', disabled: item.disabled };
      clicks.push(c); mine.push({ c, item });
      if (item.disabled) { c.effect = 'disabled'; continue; }
      if (noClick.some((n) => norm(item.label) === n || norm(item.label).startsWith(n + ' '))) { c.effect = 'not clicked (ends the session or deletes)'; continue; }
      const again = await open(m);
      const fresh = again.items && await current(m, item.label);
      if (!fresh) { c.effect = 'menu did not reopen'; continue; }
      if (fresh.disabled) { c.effect = 'disabled'; await shut(m); continue; }
      const before = await page.evaluate(SIGNATURE, MENU_SEL).catch(() => null);
      const pagesBefore = new Set(await pagesNow());
      const events = [];
      const onPage = () => events.push('window'); const onDl = () => events.push('download'); const onFc = () => events.push('file chooser'); const onDg = (d) => { events.push('dialog'); d.dismiss().catch(() => {}); };
      page.context().on('page', onPage); page.on('download', onDl); page.on('filechooser', onFc); page.on('dialog', onDg);
      await page.locator(`[data-tf-walk="${fresh.i}"]`).first().click({ timeout: 3000 }).catch((e) => { c.error = e.message.split('\n')[0]; });
      let after = null, newPages = [];
      for (let t = 0; t < settle; t += 150) {
        await page.waitForTimeout(150);
        newPages = (await pagesNow()).filter((p) => !pagesBefore.has(p));
        after = await page.evaluate(SIGNATURE, MENU_SEL).catch(() => null);
        if (newPages.length || events.length || (before && after && changed(before, after))) break;
      }
      page.context().off('page', onPage); page.off('download', onDl); page.off('filechooser', onFc); page.off('dialog', onDg);
      // where it landed: a new window or tab, or this one
      let landed = null;
      for (const np of newPages) {
        await np.waitForLoadState('domcontentloaded', { timeout: 8000 }).catch(() => {});
        await np.waitForTimeout(settle).catch(() => {});
        landed = { url: np.url(), ids: (await np.evaluate(SIGNATURE, MENU_SEL).catch(() => ({ ids: [] }))).ids, window: true };
      }
      if (!landed && after) landed = { url: after.url, ids: after.ids, window: false };
      c.landed = landed ? { url: landed.url, window: landed.window, ids: landed.ids } : null;
      c.ids_before = before ? before.ids : [];
      c.effect = c.error ? 'could not be clicked' : newPages.length ? 'opened a window' : events.length ? events.join(', ') : effectOf(before, after);
      if (c.error) findings.push({ class: 'menu', popup: m.popup, detail: `"${name} › ${item.label}" could not be clicked (${c.error.slice(0, 80)})` });
      // put the app back: a new window closed (a web tab only; a desktop head's window is the owner's),
      // a dialog dismissed, a toggled item toggled back, the screen reopened when the address moved
      if (!o.keepWindows) for (const np of newPages) await np.close().catch(() => {});
      await page.keyboard.press('Escape').catch(() => {});   // a dialog the item opened
      await shut(m);
      if (item.checkbox && c.effect !== 'nothing') {
        const back = await open(m);
        const b = back.items && await current(m, item.label);
        if (b) { await page.locator(`[data-tf-walk="${b.i}"]`).first().click({ timeout: 3000 }).catch(() => {}); await page.waitForTimeout(300); }
        await shut(m);
      }
      const now = await page.evaluate(SIGNATURE, MENU_SEL).catch(() => null);
      if (o.back && (!now || !before || now.url !== before.url || now.dialogs > before.dialogs)) await o.back();
    }
    // a choice that was already the state (Light in a light app) shows nothing: when a sibling moved the
    // theme or the page in place, that sibling is clicked first and the choice looked at again
    const donor = mine.find((x) => !x.item.checkbox && /^changed the (theme|page)$/.test(x.c.effect || ''));
    for (const { c, item } of mine) {
      if (c.effect !== 'nothing' || item.checked) continue;
      if (donor && donor.item.label !== item.label && !/^menu did not reopen/.test(await press(m, donor.item.label))) {
        const second = await press(m, item.label);
        if (second !== 'nothing' && !/^menu did not reopen|^unknown/.test(second)) { c.effect = `${second} (once "${donor.item.label}" had moved the state)`; continue; }
      }
      findings.push({ class: 'menu', popup: m.popup, detail: `"${name} › ${item.label}" does nothing when clicked` });
    }
    // the theme put back as the walk found it: an attached desktop head is the viewer's app
    if (startLook) {
      const themed = mine.filter((x) => /^changed the theme/.test(x.c.effect || '')).map((x) => x.item);
      const order = [...themed.filter((x) => x.checked), ...themed.filter((x) => !x.checked)];
      for (const it of order) {
        if (((await page.evaluate(SIGNATURE, MENU_SEL).catch(() => null)) || {}).look === startLook) break;
        await press(m, it.label);
      }
    }
    await shut(m);
  }
  return { from_mockup: fromMockup, menus, findings, clicks };
}

// Text a placeholder screen shows: the deny list, less what the mockup itself draws.
export async function placeholdersOnPage(page, mockText = '', extra = []) {
  const text = await page.evaluate(() => (document.body ? document.body.innerText : '') || '').catch(() => '');
  return placeholderRe(extra).filter((re) => re.test(text) && !re.test(mockText)).map((re) => text.match(re)[0].replace(/^[^A-Za-z]|[^A-Za-z]$/g, '').trim());
}

// --------------------------------------------------------------- the way into each screen
// screens: [{ name, route, mockup, anchors }]. clicks: from every walk. A screen has a way in when a
// menu item the mockup draws links to its mockup file. It is reached when one of those clicks landed on
// its route, or on a page showing at least half of its anchors that were not showing before the click.
// A screen whose every way in was left unclicked (Sign out) is not judged.
export function reachability(screens, clicks) {
  const base = (p) => String(p || '').split(/[?#]/)[0].split('/').pop();
  const routeRe = (r) => new RegExp('^' + String(r || '').split('?')[0].replace(/[.*+?^$()|[\]\\]/g, '\\$&').replace(/\\?\{[^}]*\}/g, '[^/]+').replace(/\/$/, '') + '/?$', 'i');
  const out = {};
  for (const s of screens) {
    if (!s.mockup) continue;
    const ways = clicks.filter((c) => c.href && base(c.href) === base(s.mockup));
    if (!ways.length) continue;
    const tried = ways.filter((c) => c.effect && !/^not clicked|^menu did not reopen/.test(c.effect));
    if (!tried.length) continue;
    const re = routeRe(s.route_pattern || s.route);
    const want = (s.anchors || []).filter((a) => !(s.state_only || []).includes(a));
    const hit = tried.find((c) => {
      if (!c.landed) return false;
      let path = '';
      try { path = new URL(c.landed.url).pathname; } catch (e) { path = ''; }
      if (path && re.test(path) && c.effect !== 'nothing') return true;
      if (!want.length) return false;
      const fresh = want.filter((a) => (c.landed.ids || []).includes(a) && !(c.landed.window ? [] : c.ids_before || []).includes(a));
      return fresh.length >= Math.ceil(want.length / 2);
    });
    out[s.name] = hit ? { reached: true, by: `${hit.menu} › ${hit.label}` }
      : { reached: false, tried: tried.map((c) => `${c.menu} › ${c.label} (${c.effect}${c.landed ? `, at ${(() => { try { return new URL(c.landed.url).pathname; } catch (e) { return c.landed.url; } })()}` : ''})`) };
  }
  return out;
}

// tf-dropdowns.mjs — open every dropdown on a screen once and grade the list it shows (TfLens TF-058).
// Imported by tf-verify-screens.mjs; not run on its own.
//
// A closed picker matches its mockup whatever its list does. TfLens's repository picker opened a list as
// narrow as "All repos", so every name read "techierathore/", and every gate passed: the menu walk opens
// menus, not a Select's list, and a test that clicks an option by its text works when the text is cut.
//
// Each visible [role="combobox"] or [aria-haspopup="listbox"] trigger is clicked once. A native <select>
// is left out: the system draws its list, and the page cannot measure it. The list is the box the
// trigger's aria-controls names, else the [role="listbox"] shown now. It is graded on two things:
//   - an option whose text is cut: the option, or an element inside it, holds more than it shows
//     (scrollWidth > clientWidth) without letting it spill, or the option reaches past the list's edge;
//   - a list that opens outside the window.
// Nothing is chosen: Escape closes the list, and a click on the trigger if it stays open. A trigger that
// opens no list (disabled in this state, or a search box that waits for typing) is passed over.

const MEASURE = (i) => {
  const trig = document.querySelector(`[data-tf-dd="${i}"]`);
  if (!trig) return null;
  const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden'; };
  const id = trig.getAttribute('aria-controls');
  const lb = [id && document.getElementById(id), ...document.querySelectorAll('[role="listbox"]')].find((x) => x && vis(x));
  if (!lb) return null;
  const opts = [...lb.querySelectorAll('[role="option"]')].filter(vis);
  if (!opts.length) return null;
  const box = lb.getBoundingClientRect();
  const short = (el) => el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1 && getComputedStyle(el).overflowX !== 'visible';
  const cut = opts.filter((o) => short(o) || [...o.querySelectorAll('*')].some(short) || o.getBoundingClientRect().right > box.right + 1)
    .map((o) => (o.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 50));
  const off = box.left < -1 || box.top < -1 || box.right > innerWidth + 1 || box.bottom > innerHeight + 1;
  const name = trig.getAttribute('aria-label') || trig.getAttribute('data-testid') || trig.closest('[data-testid]')?.getAttribute('data-testid')
    || (trig.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40);
  return { name, cut, off };
};

// -> [{ check: 'visual', class, detail }] for the screen open in page, at this width
export async function dropdownFindings(page, width, o = {}) {
  const max = o.max ?? 8, settle = o.settle ?? 900;
  const n = await page.evaluate(() => {
    document.querySelectorAll('[data-tf-dd]').forEach((x) => x.removeAttribute('data-tf-dd'));
    const t = [...document.querySelectorAll('[role="combobox"],[aria-haspopup="listbox"]')].filter((el) => {
      const r = el.getBoundingClientRect();
      return el.tagName !== 'SELECT' && r.width > 0 && r.height > 0 && !el.disabled && el.getAttribute('aria-disabled') !== 'true';
    });
    t.forEach((el, i) => el.setAttribute('data-tf-dd', String(i)));
    return t.length;
  }).catch(() => 0);
  const out = [];
  for (let i = 0; i < Math.min(n, max); i++) {
    const trig = page.locator(`[data-tf-dd="${i}"]`).first();
    if (await trig.click({ timeout: 3000 }).then(() => false, () => true)) continue;
    let got = null;
    for (let t = 0; t < settle && !got; t += 150) { await page.waitForTimeout(150); got = await page.evaluate(MEASURE, String(i)).catch(() => null); }
    await page.keyboard.press('Escape').catch(() => {});
    await page.waitForTimeout(150);
    if (got && await page.evaluate(MEASURE, String(i)).catch(() => null)) await trig.click({ timeout: 2000 }).catch(() => {});
    if (!got) continue;
    if (got.cut.length) out.push({ check: 'visual', class: 'clipped', detail: `the list of "${got.name}" cuts ${got.cut.length} option(s) short at ${width}px, such as "${got.cut[0]}"` });
    if (got.off) out.push({ check: 'visual', class: 'offscreen', detail: `the list of "${got.name}" opens outside the window at ${width}px` });
  }
  return out;
}

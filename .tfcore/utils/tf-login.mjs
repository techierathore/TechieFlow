// TechieFlow — the one sign-in recipe the browser-driven checks share (AppManager TF-011, 2026-09-14).
//
// tf-verify-screens.mjs learned to sign in through a page's own form (TF-033, TF-044) and to reach a
// screen whose document answers 401 because the sign-in lives in the page, not in a cookie
// (AppManager TF-006). tf-mockup-parity.mjs and tf-assets took only --cookie, so on such an app they
// could not get past the sign-in at all. The recipe lives here so every check reaches a screen the
// same way, and a lesson learned in one is learned in all.
//
//   signIn(page, o)          -> { attempted, ok, url, attempts, error }
//   signedOut(page, o)       -> true when the page is the sign-in page
//   navigateInApp(page, o, route) -> true when the page drew something different
//   reach(page, o, route)    -> { status, url, reached, signedOut, error }: open a route, signed in
//
// o = { base, loginPath, user, password, attr = 'data-testid', settle = 1500, renderWait = 5000 }

// The first visible, usable match, trying the selectors IN ORDER. `.first()` over one selector list
// takes whichever match comes first in the page, so `input[type="text"]` at the end of the list
// picked a header search box standing before the email field (TF-044).
export async function pick(scope, selectors) {
  for (const sel of selectors) {
    const c = scope.locator(sel).first();
    if (await c.count() && await c.isVisible().catch(() => false)) return c;
  }
  return null;
}

const LOGIN_ATTEMPTS = 4;
const opts = (o) => ({ attr: 'data-testid', settle: 1500, renderWait: 5000, ...o, base: (o.base || '').replace(/\/$/, '') });

// The usual sign-in addresses, tried in this order after the one the caller named when that page has no
// user field: Chatur signs in at /sign-in and the check was told /login, so it stopped with "no user or
// email field found" (Chatur TF-019).
export const LOGIN_PATHS = ['/login', '/sign-in', '/signin', '/account/login', '/Account/Login'];

export async function signIn(page, o) {
  const { base, user, password, attr, settle } = opts(o);
  let { loginPath } = opts(o);
  if (!loginPath || !user) return { attempted: false };
  const onLogin = () => page.url().startsWith(base + loginPath);
  try {
    const INPUT = ':is(input, textarea)';
    const USER_FIELD = [`${INPUT}[${attr}*="email" i]`, `${INPUT}[${attr}*="user" i]`, 'input[type="email"]', 'input[autocomplete="username"]',
                        'input[name*="email" i]', 'input[name*="user" i]', 'input[id*="email" i]', 'input[id*="user" i]', 'form input[type="text"]'];
    const tried = [];
    for (const path of [loginPath, ...LOGIN_PATHS.filter((x) => x.toLowerCase() !== loginPath.toLowerCase())]) {
      tried.push(path);
      await gotoRetry(page, base + path, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
      // a page that draws its form a moment after it arrives has no field to pick yet
      await page.waitForSelector('input', { state: 'visible', timeout: tried.length === 1 ? 15000 : 5000 }).catch(() => {});
      // the address the form is really on: an app that sends /login on to /sign-in signs in at /sign-in
      if (await pick(page, USER_FIELD)) { loginPath = (page.url().startsWith(base) && page.url().slice(base.length).split(/[?#]/)[0]) || path; break; }
    }
    // every check that reads the sign-in address afterwards (signedOut, the redirect test) reads this one
    if (loginPath !== o.loginPath) { o.loginPathAsked = o.loginPath; o.loginPath = loginPath; }
    const moved = o.loginPathAsked ? { login_path: loginPath, login_path_asked: o.loginPathAsked } : {};
    if (!(await pick(page, USER_FIELD))) return { attempted: true, ok: false, error: `no user or email field found on the sign-in page (tried ${tried.join(', ')})` };
    const PASS_FIELD = ['input[type="password"]', `${INPUT}[${attr}*="pass" i]`];
    // The button, never a field: "login-email" and "login-pass" contain "login" too, and taking the
    // first test id with "login" in it clicked the email box, so sign-in never submitted (TF-033).
    const BTN = `:is(button, a, [role="button"], input[type="submit"], input[type="button"])`;
    const BUTTON = ['button[type="submit"]', 'input[type="submit"]', `${BTN}[${attr}*="submit" i]`, `${BTN}[${attr}*="signin" i]`,
                    `${BTN}[${attr}*="sign-in" i]`, `${BTN}[${attr}*="login" i]`, 'button'];
    // A page drawn on the server first and made interactive a moment later replaces its fields when
    // it becomes interactive: what was typed before that is gone, and a press before it does nothing.
    // Waiting for the network proves neither, and every stack takes its own time. So the test is the
    // result: the typed values are still in the fields when the button is pressed, and the page then
    // leaves the sign-in address. Otherwise type again and press again. TfLens, 2026-09-12: the email
    // read back empty the instant after it was typed, and the second attempt signed in (TF-044).
    let why = 'the typed values did not stay in the fields';
    for (let attempt = 1; attempt <= LOGIN_ATTEMPTS; attempt++) {
      if (!onLogin()) break;
      const u = await pick(page, USER_FIELD);
      if (!u) return { attempted: true, ok: false, error: 'no user or email field found on the sign-in page' };
      const p = await pick(page, PASS_FIELD);
      try {
        await u.fill(user, { timeout: 10000 });
        if (p) await p.fill(password || '', { timeout: 10000 });
        await page.waitForTimeout(400);
        const kept = (await u.inputValue()) === user && (!p || (await p.inputValue()) === (password || ''));
        if (!kept) { why = 'the typed values did not stay in the fields'; continue; }
        const form = u.locator('xpath=ancestor::form[1]');
        const btn = (await form.count() ? await pick(form, BUTTON) : null) || await pick(page, BUTTON);
        if (!btn) return { attempted: true, ok: false, error: 'no sign-in button found (a submit button, or a button whose test id says submit, signin or login)' };
        await btn.click({ timeout: 10000 });
        await page.waitForURL((x) => !x.href.startsWith(base + loginPath), { timeout: 6000 }).catch(() => {});
        why = 'the form was submitted with the values in place and the page stayed on the sign-in address';
      } catch (e) {
        if (onLogin()) why = e.message.split('\n')[0];
      }
      if (!onLogin()) {
        await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
        await page.waitForTimeout(settle);
        return { attempted: true, ok: true, url: page.url(), attempts: attempt, ...moved };
      }
    }
    if (!onLogin()) return { attempted: true, ok: true, url: page.url(), attempts: 1, ...moved };
    return { attempted: true, ok: false, url: page.url(), attempts: LOGIN_ATTEMPTS, ...moved, error: `still on the sign-in page after ${LOGIN_ATTEMPTS} attempts: ${why}` };
  } catch (e) {
    return { attempted: true, ok: false, error: e.message.split('\n')[0] };
  }
}

// The page is signed out when it sits on the sign-in address, or when it draws a sign-in form: a
// password field WITH a button that says sign in / log in beside it. A password field alone is not
// the sign-in page — AppManager's signed-in "Create user" form has one for the new account, and
// reading it as the sign-in page graded that screen unreachable (AppManager TF-012).
export async function signedOut(page, o) {
  const { loginPath, attr } = opts(o);
  try {
    if (loginPath && new URL(page.url()).pathname.startsWith(loginPath)) return true;
    const pw = page.locator('input[type="password"]').first();
    if (!(await pw.count()) || !(await pw.isVisible().catch(() => false))) return false;
    const form = pw.locator('xpath=ancestor::form[1]');
    const scope = (await form.count()) ? form : page;
    const BTN = ':is(button, a, [role="button"], input[type="submit"], input[type="button"])';
    const said = scope.locator(`${BTN}:visible`).filter({ hasText: /^\s*(sign\s*in|log\s*in|login|signin)\s*$/i }).first();
    if (await said.count()) return true;
    const named = scope.locator(`${BTN}[${attr}*="signin" i], ${BTN}[${attr}*="sign-in" i], ${BTN}[${attr}*="login" i]`).first();
    return (await named.count()) > 0 && (await named.isVisible().catch(() => false));
  } catch (e) { return true; }
}

// Open a route from inside the page, the way its own links do, so a sign-in held by the page survives.
// It counts only when the page drew something different: a server-drawn page has no router to answer
// the event, and grading the page it was already on under another screen's name would be a false pass.
export async function navigateInApp(page, o, route) {
  const { settle } = opts(o);
  try {
    const before = await page.evaluate(() => document.body ? document.body.innerText : '');
    await page.evaluate((r) => { history.pushState({}, '', r); window.dispatchEvent(new PopStateEvent('popstate', { state: {} })); }, route);
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    await page.waitForTimeout(settle);
    const after = await page.evaluate(() => document.body ? document.body.innerText : '');
    return after !== before;
  } catch (e) { return false; }
}

// Wait for the page to draw something: an anchored control, text, or a form control (TF-021).
export async function waitForRender(page, o, anchors = []) {
  const { attr, renderWait } = opts(o);
  if (renderWait <= 0) return 0;
  const t0 = Date.now();
  try {
    await page.waitForFunction(({ anchors, attr }) => {
      if (anchors && anchors.length) return anchors.some((id) => document.querySelector(`[${attr}="${CSS.escape(id)}"]`));
      return (document.body && (document.body.innerText || '').trim().length > 0)
        || document.querySelectorAll('input, select, textarea, img, svg, canvas, video').length > 0;
    }, { anchors, attr }, { timeout: renderWait, polling: 100 });
  } catch (e) { /* nothing appeared in time: grade what is there */ }
  return Date.now() - t0;
}

// Open a route signed in. The document of a signed-in screen may answer 401 or 403 when the sign-in
// lives in the page's own connection and not in a cookie (AppManager TF-006): then the page is judged
// by what it draws. Signed in, the screen is reached and `reached` says how. Still signed out, the
// tool signs in again and opens the screen from inside the page. Returns the status to grade on:
// 200 when the page drew the screen signed in, whatever the document answered.
export async function reach(page, o, route) {
  const { base, loginPath, user, settle } = opts(o);
  let status = 0, url = '', error = '';
  try {
    const resp = await gotoRetry(page, base + route, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    await page.waitForTimeout(settle);
    status = resp ? resp.status() : 0; url = page.url();
  } catch (e) { return { status: 0, url: '', reached: '', signedOut: false, error: e.message.split('\n')[0] }; }
  const out = { status, document_status: status, url, reached: '', signedOut: false, error };
  if (loginPath && user && (status === 401 || status === 403)) {
    await waitForRender(page, o);
    let how = `answered HTTP ${status}, then drew the screen signed in`;
    if (await signedOut(page, o)) {
      how = '';
      const again = await signIn(page, o);
      if (again.ok && await navigateInApp(page, o, route) && !(await signedOut(page, o))) how = `answered HTTP ${status}; opened from inside the page after signing in`;
    }
    if (how) { out.reached = how; out.status = 200; out.url = page.url(); }
    else out.signedOut = true;
  } else if (loginPath && url && new URL(url).pathname.startsWith(loginPath) && !route.startsWith(loginPath)) {
    out.signedOut = true;
  }
  return out;
}

// ---- a desktop head: arriving on a screen, and a window that draws ----------------------------
// Lekhak TF-037: on a desktop head a screen is opened by pushState, which changes the address at once,
// while the app draws the new page a moment later. The check read the anchors and took the screenshot
// in between: AI Setup's four anchors were "not on the page" over a picture of AI Story Studio. So the
// anchors present BEFORE the move are noted, and after it the check waits (bounded) until the address
// matches the route and one of the screen's own anchors that was not there before is attached, then
// until the page stops changing for 300 ms. It never decides anything: on the timeout the page is
// graded as it stands, and `arrived: false` says so.
// 2026-11-10: "could not open /blank/: page.goto: net::ERR_NETWORK_CHANGED". Chromium cancels every request
// in flight when the machine's network changes (a Wi-Fi or VPN switch, a virtual adapter coming up; on
// WSL the Windows host's changes arrive too), a page on 127.0.0.1 included, and the screen was graded
// unreachable for it. That says nothing about the app, so the load is tried again, twice, a second apart.
// Any other failure is thrown at once, as before.
export async function gotoRetry(page, url, options = {}, pause = 1000) {
  for (let attempt = 0; ; attempt++) {
    try { return await page.goto(url, options); } catch (e) {
      if (attempt >= 2 || !/ERR_NETWORK_CHANGED|ERR_NETWORK_IO_SUSPENDED/.test(String(e && e.message))) throw e;
      await new Promise((r) => setTimeout(r, pause));
    }
  }
}

export async function anchorsPresent(page, anchors = [], attr = 'data-testid') {
  if (!anchors || !anchors.length) return [];
  try {
    return await page.evaluate(({ anchors, attr }) => anchors.filter((id) => document.querySelector(`[${attr}="${CSS.escape(id)}"]`)), { anchors, attr });
  } catch (e) { return []; }
}

export async function waitArrived(page, route, anchors = [], before = [], o = {}) {
  const { attr, renderWait } = opts(o);
  const want = (route || '').split(/[?#]/)[0];
  const fresh = (anchors || []).filter((a) => !(before || []).includes(a));
  const t0 = Date.now();
  let arrived = true;
  try {
    // 2026-11-10: one new control was enough, and a control every screen shares counted as new when the
    // page before had none. A page drawn late by an EARLIER move (the app still finishing what the last
    // tool asked of it) then passed for this screen: AI Setup was compared on Story Studio's page, top
    // bar matching, "PASS, compared 1 of the app's 2 controls" (lk_037b, 2 full runs in 5). The screen
    // has arrived when a control that was not there before is attached AND at least half of the
    // screen's own controls are; a page of another screen holds the shared ones only.
    const all = (anchors || []);
    await page.waitForFunction(({ want, fresh, all, attr }) => {
      const on = (id) => !!document.querySelector(`[${attr}="${CSS.escape(id)}"]`);
      const enough = all.filter(on).length >= Math.ceil(all.length / 2);
      if (fresh.some(on) && enough) return true;
      const norm = (x) => (x || '').replace(/\/+$/, '').toLowerCase() || '/';
      const rx = new RegExp('^' + norm(want).split(/(\{[^}]*\})/).map((p) => p.startsWith('{') ? '[^/]+' : p.replace(/[.*+?^$()|[\]\\]/g, '\\$&')).join('') + '$');
      return !fresh.length && enough && rx.test(norm(location.pathname));
    }, { want, fresh, all, attr }, { timeout: Math.max(renderWait, 5000), polling: 100 });
  } catch (e) {
    // the wait ran out. A first view that draws fewer than half of its mockup's controls (the rest belong
    // to data it does not have yet) has still arrived when one of its new controls is there, as before;
    // it only took the whole wait to say so. Nothing new at all: not arrived.
    arrived = fresh.length > 0 && (await anchorsPresent(page, fresh, attr)).length > 0;
  }
  // then quiet: nothing in the page changed for 300 ms (at most 3 s), so the top bar has caught up too
  await page.evaluate(() => new Promise((res) => {
    let t; const done = () => { mo.disconnect(); clearTimeout(cap); clearTimeout(t); res(); };
    const mo = new MutationObserver(() => { clearTimeout(t); t = setTimeout(done, 300); });
    const cap = setTimeout(done, 3000); t = setTimeout(done, 300);
    mo.observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true });
  })).catch(() => {});
  return { ms: Date.now() - t0, arrived, fresh: fresh.length };
}

// Lekhak TF-038: a desktop head the last browser test left ON the screen's route (scrolled to the Review
// queue, its switch still on) was measured as the test left it, and the top bar read "cut off". A move to
// the same route changes nothing, so TF-037's wait had nothing to wait for. Every screen is now opened from
// its own first state: when the app is already on the route it is first moved to another one ('/', or a
// route no page answers when the screen is '/') and back, so the app draws the screen afresh; then the
// window and every scrolled box go back to the top. `reset` says when the hop was made.
const samePath = (a, b) => {
  const n = (x) => ((x || '').split(/[?#]/)[0].replace(/\/+$/, '') || '/').toLowerCase();
  return n(a) === n(b) && ((a || '').split('#')[0].split('?')[1] || '') === ((b || '').split('#')[0].split('?')[1] || '');
};
const pushRoute = (page, r) => page.evaluate((x) => { history.pushState({}, '', x); window.dispatchEvent(new PopStateEvent('popstate', { state: {} })); }, r);
const quiet = (page) => page.evaluate(() => new Promise((res) => {
  let t; const done = () => { mo.disconnect(); clearTimeout(cap); clearTimeout(t); res(); };
  const mo = new MutationObserver(() => { clearTimeout(t); t = setTimeout(done, 300); });
  const cap = setTimeout(done, 3000); t = setTimeout(done, 300);
  mo.observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true });
})).catch(() => {});
export async function scrollToTop(page) {
  await page.evaluate(() => {
    window.scrollTo(0, 0);
    for (const el of document.querySelectorAll('*')) if (el.scrollTop > 0 || el.scrollLeft > 0) { el.scrollTop = 0; el.scrollLeft = 0; }
  }).catch(() => {});
  // one frame to paint, bounded: a minimized window draws none (Sevak TF-011) and would wait forever
  await page.evaluate(() => new Promise((r) => { requestAnimationFrame(() => r()); setTimeout(r, 300); })).catch(() => {});
}
export async function openFresh(page, route, anchors = [], o = {}) {
  let reset = false;
  const here = await page.evaluate(() => location.pathname + location.search).catch(() => '');
  if (samePath(here, route)) {
    const away = samePath(route, '/') ? '/tf-verify-away' : '/';
    const was = await page.evaluate(() => (document.body ? document.body.innerText : '')).catch(() => '');
    await pushRoute(page, away);
    // until the app has drawn the other page (an app that draws late, Lekhak TF-037, would otherwise draw
    // it in the middle of the measurement), bounded; then quiet
    await page.waitForFunction((w) => (document.body ? document.body.innerText : '') !== w, was,
      { timeout: Math.max(opts(o).renderWait, 5000), polling: 100 }).catch(() => {});
    await quiet(page);
    reset = true;
  }
  const before = await anchorsPresent(page, anchors, opts(o).attr);
  await pushRoute(page, route);
  const a = await waitArrived(page, route, anchors, before, o);
  await scrollToTop(page);
  return { ...a, reset };
}

// Sevak TF-011: a minimized Windows app window draws no frames, so every click waits for a control to
// be "stable" and times out, and each was reported as a defect of the screen. requestAnimationFrame
// callbacks are counted for `ms`; none means the window is not drawing.
export async function framesDrawn(page, ms = 1000) {
  try {
    return await page.evaluate((ms) => new Promise((res) => {
      let n = 0; const t0 = performance.now();
      const tick = () => { n++; if (performance.now() - t0 < ms) requestAnimationFrame(tick); };
      requestAnimationFrame(tick);
      setTimeout(() => res(n), ms);
    }), ms);
  } catch (e) { return -1; }
}

// Restore the head's own window, by the Windows process ids the boot recorded (boot.json win_pids):
// ShowWindow(SW_RESTORE) on that process's main window, no keyboard or mouse input. Returns what it did.
export async function restoreWindow(cdpUrl, dir = 'tests/.artifacts/verify') {
  const { existsSync, readdirSync, readFileSync } = await import('node:fs');
  const { spawnSync } = await import('node:child_process');
  let pids = [];
  try {
    const files = existsSync(dir) ? readdirSync(dir).filter((f) => /^boot(-\d+)?\.json$/.test(f)) : [];
    for (const f of files) {
      const b = JSON.parse(readFileSync(`${dir}/${f}`, 'utf8'));
      if (b.stopped || !Array.isArray(b.win_pids) || !b.win_pids.length) continue;
      if (cdpUrl && b.url && b.url.replace(/\/$/, '') !== cdpUrl.replace(/\/$/, '') && f !== 'boot.json') continue;
      pids = b.win_pids.filter((p) => /^\d+$/.test(String(p)));
      if (pids.length) break;
    }
  } catch (e) { /* no boot record: nothing to restore */ }
  if (!pids.length) return 'no Windows process id in the boot record';
  const ps = 'Add-Type -Name W -Namespace TfW -MemberDefinition \'[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);\'; '
    + `foreach ($i in @(${pids.join(',')})) { $p = Get-Process -Id $i -ErrorAction SilentlyContinue; if ($p -and $p.MainWindowHandle -ne 0) { [void][TfW.W]::ShowWindow($p.MainWindowHandle, 9); 'restored ' + $i } }`;
  const r = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', ps], { encoding: 'utf8', timeout: 20000 });
  if (r.error) return `could not run powershell.exe: ${r.error.code || r.error.message}`;
  return (r.stdout || '').trim() || `no window found for process ${pids.join(', ')}`;
}

// framesDrawn, then restoreWindow and count again: { drawing, frames, restored }
export async function ensureDrawing(page, cdpUrl) {
  let frames = await framesDrawn(page, 500);
  if (frames !== 0) return { drawing: true, frames };
  const restored = await restoreWindow(cdpUrl);
  frames = await framesDrawn(page, 1000);
  return { drawing: frames !== 0, frames, restored };
}

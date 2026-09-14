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

export async function signIn(page, o) {
  const { base, loginPath, user, password, attr, settle } = opts(o);
  if (!loginPath || !user) return { attempted: false };
  const onLogin = () => page.url().startsWith(base + loginPath);
  try {
    await page.goto(base + loginPath, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    // a page that draws its form a moment after it arrives has no field to pick yet
    await page.waitForSelector('input', { state: 'visible', timeout: 15000 }).catch(() => {});
    const INPUT = ':is(input, textarea)';
    const USER_FIELD = [`${INPUT}[${attr}*="email" i]`, `${INPUT}[${attr}*="user" i]`, 'input[type="email"]', 'input[autocomplete="username"]',
                        'input[name*="email" i]', 'input[name*="user" i]', 'input[id*="email" i]', 'input[id*="user" i]', 'form input[type="text"]'];
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
        return { attempted: true, ok: true, url: page.url(), attempts: attempt };
      }
    }
    if (!onLogin()) return { attempted: true, ok: true, url: page.url(), attempts: 1 };
    return { attempted: true, ok: false, url: page.url(), attempts: LOGIN_ATTEMPTS, error: `still on the sign-in page after ${LOGIN_ATTEMPTS} attempts: ${why}` };
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
    const resp = await page.goto(base + route, { waitUntil: 'domcontentloaded', timeout: 30000 });
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

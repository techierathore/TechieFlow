// tf-appium.mjs — the few WebDriver calls a native head needs, over Node's own fetch (no package).
// Used by tf-verify-native.mjs; an acceptance test of a native head may import it too:
//   import { openSession, parseSource } from '<repo>/.tfcore/utils/tf-appium.mjs';
//   const s = await openSession(process.env.APPIUM_URL, { bundleId: process.env.TF_BUNDLE_ID, appPath: process.env.TF_APP_PATH });
//   await s.click(await s.find('accessibility id', 'save'));  …  await s.close();
// Every control is found inside the app under test by its AutomationId (the accessibility
// identifier); nothing here types or clicks at a screen position. Type into a field with
// `await s.type(el, 'text')`, the one way a Blazor Hybrid form on a Mac took the text.

import { execFileSync } from 'node:child_process';
import { statSync } from 'node:fs';

const W3C_EL = 'element-6066-11e4-a52e-4f735466cecf';

async function call(base, method, path, body) {
  const r = await fetch(base + path, {
    method, headers: { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(300000),
  });
  const j = await r.json().catch(() => ({ value: { message: `HTTP ${r.status}, not JSON` } }));
  if (!r.ok || (j.value && j.value.error)) throw new Error((j.value && j.value.message || `HTTP ${r.status}`).split('\n')[0]);
  return j.value;
}

// A session on the Mac Catalyst app (mac2), by its .app path when known: by bundle id alone mac2
// answered "could not be found" for a build outside /Applications that macOS had not registered
// (Lekhak TF-003; seen again 2026-10-07). skipAppKill: the app is tf-verify-boot.sh's to stop, so
// ending the session leaves it running for the next check.
export async function openSession(url, { bundleId, appPath = '', automationName = 'Mac2', platformName = 'mac', extra = {} } = {}) {
  const base = url.replace(/\/$/, '');
  const which = appPath ? { 'appium:appPath': appPath } : { 'appium:bundleId': bundleId };
  const v = await call(base, 'POST', '/session', { capabilities: { alwaysMatch: {
    platformName, 'appium:automationName': automationName, ...which,
    'appium:skipAppKill': true, 'appium:newCommandTimeout': 300, ...extra } } });
  const sp = `/session/${v.sessionId}`;
  const s = {
    id: v.sessionId,
    call: (m, p, b) => call(base, m, sp + p, b),
    source: () => s.call('GET', '/source'),
    find: async (using, value, from = null) => Object.values(await s.call('POST', from ? `/element/${from}/element` : '/element', { using, value }))[0],
    findAll: async (using, value, from = null) => (await s.call('POST', from ? `/element/${from}/elements` : '/elements', { using, value })).map((e) => e[W3C_EL] || Object.values(e)[0]),
    click: (el) => s.call('POST', `/element/${el}/click`, {}),
    // Typing into a field. A Blazor Hybrid form on a Mac kept its @bind empty or half filled when the
    // value was set through Accessibility, through mac2's "set value", or by key events posted to the
    // process ("The text must have valid value", Lekhak TF-026). What reached it: a click on the field,
    // then W3C key actions, a key down and up per character.
    type: async (el, text) => {
      await s.click(el);
      const actions = [...String(text)].flatMap((c) => [{ type: 'keyDown', value: c }, { type: 'keyUp', value: c }]);
      await s.call('POST', '/actions', { actions: [{ type: 'key', id: 'keyboard', actions }] });
      await s.call('DELETE', '/actions').catch(() => {});
    },
    shot: (el) => s.call('GET', el ? `/element/${el}/screenshot` : '/screenshot'),
    close: () => call(base, 'DELETE', sp).catch(() => {}),
  };
  return s;
}

// What the app shows first, for tf-verify-boot.sh: BOOTED only when a mac2 session opens and the app
// has a window of its own that is not a system dialog (Lekhak TF-026: BOOTED was printed while no
// session could open, and once while the app's only window was macOS's "quit unexpectedly while
// reopening windows" dialog). That dialog is answered Don't Reopen, which only skips restoring old
// windows, and the answer is reported. The window alone is saved to `shot`. Never throws.
export async function firstScreen(url, { bundleId = '', appPath = '', shot = '', wait = 30000 } = {}) {
  let s;
  try { s = await openSession(url, { bundleId, appPath }); }
  catch (e) { return { ok: false, stage: 'session', reason: e.message }; }
  const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
  const DIALOG = new Set(['Dialog', 'Sheet', 'SystemDialog']);
  const LEAF = new Set(['Button', 'TextField', 'SecureTextField', 'TextView', 'Image', 'CheckBox', 'Switch', 'Slider', 'PopUpButton',
    'ComboBox', 'Link', 'RadioButton', 'SegmentedControl', 'Stepper', 'DatePicker', 'ProgressIndicator', 'Cell']);
  const out = { ok: false, stage: 'window', dismissed: '' };
  try {
    for (const t0 = Date.now(); Date.now() - t0 < wait; await sleep(500)) {
      const nodes = parseSource(await s.source());
      const label = (n) => n.title || n.label || '';
      const reopen = nodes.find((n) => n.type === 'Button' && /^don.t reopen$/i.test(label(n)));
      if (reopen && !out.dismissed) {
        const el = await s.find('-ios predicate string', `elementType == 9 AND (title BEGINSWITH[c] 'Don' OR label BEGINSWITH[c] 'Don')`).catch(() => null);
        if (el) { await s.click(el); out.dismissed = 'macOS asked to reopen the windows of a run that did not quit; answered Don\'t Reopen'; continue; }
      }
      const dialog = nodes.find((n) => DIALOG.has(n.type)) || reopen;
      const win = nodes.find((n) => n.type === 'Window' && n.w >= 200 && n.h >= 150 && !descendants(nodes, n.i).some((d) => DIALOG.has(d.type)));
      // drawn: text or a control in the window's content, as tf-verify-native counts it: what sits
      // directly on the window (its title, its three buttons) and the bars are not content. A web view
      // took about eight seconds to draw its first page; until then the window is blank.
      const chrome = (n) => n.parent === win.i || ['TabBar', 'Toolbar', 'NavigationBar', 'MenuBar', 'Menu'].some((t) => {
        for (let p = n.i; p >= 0; p = nodes[p].parent) if (nodes[p].type === t) return true;
        return false; });
      const drawn = win && descendants(nodes, win.i).some((n) => !chrome(n) && (n.type === 'StaticText' ? !!label(n).trim() || !!(n.value || '').trim() : LEAF.has(n.type)));
      if (win && !dialog && drawn) {
        out.ok = true; out.window = { w: win.w, h: win.h };
        if (shot) {
          await sleep(500);   // the first frame of a web view fades in
          // the window alone (TF-027: mac2's element shot is a crop of the display, banners included)
          if (appPath && windowShot(appPid(appPath), shot)) out.shot = shot;
          else {
            const el = await s.find('-ios predicate string', 'elementType == 4').catch(() => null);
            if (el) { const { writeFileSync } = await import('node:fs'); writeFileSync(shot, Buffer.from(await s.shot(el), 'base64')); out.shot = shot; }
          }
        }
        return out;
      }
      out.reason = dialog ? `the app shows a dialog, not its first screen: "${(label(dialog) || dialog.type).slice(0, 80)}"`
        : win ? 'the app\'s window is on view but blank (no text, no control)' : 'the app has no window of its own on view';
    }
    out.reason = `${out.reason || 'no window'} after ${Math.round(wait / 1000)} s`;
    return out;
  } catch (e) { return { ...out, reason: `Appium: ${e.message}` }; }
  finally { await s.close(); }
}

// The page source (XCUIElementType… XML) as a flat list of nodes with their parent index, so a
// caller can walk a subtree without an XML package.
export function parseSource(xml) {
  const un = (s) => s.replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#10;/g, '\n').replace(/&amp;/g, '&');
  const nodes = []; const stack = [];
  const re = /<(\/?)(XCUIElementType\w+)([^>]*?)(\/?)>/g; let m;
  while ((m = re.exec(xml))) {
    if (m[1]) { stack.pop(); continue; }
    const a = {}; let am; const are = /(\w+)="([^"]*)"/g;
    while ((am = are.exec(m[3]))) a[am[1]] = un(am[2]);
    const n = { i: nodes.length, type: m[2].replace('XCUIElementType', ''), id: a.identifier || '', label: a.label || '', value: a.value || '',
      title: a.title || '', x: +a.x || 0, y: +a.y || 0, w: +a.width || 0, h: +a.height || 0, parent: stack.length ? stack[stack.length - 1] : -1, kids: [] };
    if (n.parent >= 0) nodes[n.parent].kids.push(n.i);
    nodes.push(n);
    if (!m[4]) stack.push(n.i);
  }
  return nodes;
}

export function descendants(nodes, i) {
  const out = []; const todo = [...nodes[i].kids];
  while (todo.length) { const k = todo.shift(); out.push(nodes[k]); todo.push(...nodes[k].kids); }
  return out;
}

// --- the app's own window, through macOS rather than mac2 (Lekhak TF-027) ---------------------------
// mac2 cannot resize a window, and its element screenshot is a crop of the display, so a notification
// banner over the window landed in every picture. macOS itself does both: System Events resizes the
// window (the app's minimum size still holds, and the size it really took is returned), and
// screencapture -l takes the window alone by its window number.
const run = (cmd, args) => { try { return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 20000 }).trim(); } catch { return ''; } };

// the pid of the app running from this .app (a mac2 session starts it again under a new pid)
export function appPid(appPath) {
  const out = run('pgrep', ['-f', `${appPath.replace(/\/$/, '')}/Contents/MacOS/`]);
  return parseInt(out.split('\n')[0], 10) || 0;
}

// { id, x, y, w, h } of the app's largest normal window on view, or null
export function macWindow(pid) {
  if (!pid) return null;
  const js = `ObjC.import('CoreGraphics');
    const l = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements, 0)));
    JSON.stringify(l.filter((w) => w.kCGWindowOwnerPID == ${pid} && w.kCGWindowLayer == 0)
      .map((w) => ({ id: w.kCGWindowNumber, x: w.kCGWindowBounds.X, y: w.kCGWindowBounds.Y, w: w.kCGWindowBounds.Width, h: w.kCGWindowBounds.Height })))`;
  try { return JSON.parse(run('osascript', ['-l', 'JavaScript', '-e', js]) || '[]').sort((a, b) => b.w * b.h - a.w * a.h)[0] || null; }
  catch { return null; }
}

// sets the front window's size; returns the size it took ({ w, h }), or null when macOS refused
// (the terminal needs Accessibility, as mac2 does)
export function resizeWindow(pid, w, h) {
  if (!pid) return null;
  const tell = `tell application "System Events" to tell (first process whose unix id is ${pid})`;
  run('osascript', ['-e', `${tell} to set size of window 1 to {${w}, ${h}}`]);
  const got = run('osascript', ['-e', `${tell} to get size of window 1`]).split(/,\s*/).map(Number);
  return got.length === 2 && got.every((n) => n > 0) ? { w: got[0], h: got[1] } : null;
}

// the window alone, by its window number; true when the file was written
export function windowShot(pid, file) {
  const win = macWindow(pid);
  if (!win) return false;
  run('screencapture', ['-x', '-o', '-l', String(win.id), file]);
  try { return statSync(file).size > 0; } catch { return false; }
}

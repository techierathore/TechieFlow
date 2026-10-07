// tf-appium.mjs — the few WebDriver calls a native head needs, over Node's own fetch (no package).
// Used by tf-verify-native.mjs; an acceptance test of a native head may import it too:
//   import { openSession, parseSource } from '<repo>/.tfcore/utils/tf-appium.mjs';
//   const s = await openSession(process.env.APPIUM_URL, { bundleId: process.env.TF_BUNDLE_ID, appPath: process.env.TF_APP_PATH });
//   await s.click(await s.find('accessibility id', 'save'));  …  await s.close();
// Every control is found inside the app under test by its AutomationId (the accessibility
// identifier); nothing here types or clicks at a screen position.

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
    shot: (el) => s.call('GET', el ? `/element/${el}/screenshot` : '/screenshot'),
    close: () => call(base, 'DELETE', sp).catch(() => {}),
  };
  return s;
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

// tests/faults/fake-mac2.mjs — a stand-in Appium mac2 server for the Mac screen checker's click paths.
//   node fake-mac2.mjs <model.json> <port-file>
// Serves the few WebDriver calls tf-appium.mjs and tf-verify-native.mjs make, over an app described in the
// model: { start, h, max_scroll, surface, pages: { key: [ {type, label, to, y, sw, surface} ] } }.
// A control whose centre is outside the window (after scrolling) takes no click, as on a real Mac (TrStudio
// TF-007). `to` opens that page; `sw` sets the surface; a control with `surface` shows only on that surface.
// A TextField or SecureTextField takes text from key actions only when it is all letters and digits (TrStudio's
// form dropped "@" and "!"), and any text from "macos: keys"; a control with `login` {user, pass, to} opens `to`
// when the two fields hold them. Every click and scroll is appended to <model>.log. Node standard library only.
import { createServer } from 'node:http';
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';

const model = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const LOG = `${process.argv[2]}.log`;
const W3C = 'element-6066-11e4-a52e-4f735466cecf';
const H = model.h || 800;
let page = model.start, surface = model.surface || '', scroll = 0, ver = 0, focus = null;
const val = {};   // field label -> text
const esc = (t) => String(t).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const shown = () => (model.pages[page] || []).filter((c) => !c.surface || c.surface === surface);
const rect = (c) => ({ x: 20, y: c.y - scroll, width: 200, height: 20 });
const source = () => `<?xml version="1.0"?><XCUIElementTypeApplication><XCUIElementTypeWindow x="0" y="0" width="1280" height="${H}" title="Fx">`
  + `<XCUIElementTypeWebView x="0" y="28" width="1280" height="${H - 28}"><XCUIElementTypeStaticText value="Page ${esc(page)}" x="20" y="${40 - scroll}" width="300" height="20"/>`
  + shown().map((c) => { const r = rect(c), v = /TextField/.test(c.type || '') ? ` value="${esc(c.type === 'SecureTextField' ? '•'.repeat((val[c.label] || '').length) : val[c.label] || '')}"` : '';
    return `<XCUIElementType${c.type || 'Link'} label="${esc(c.label)}"${v} x="${r.x}" y="${r.y}" width="${r.width}" height="${r.height}"/>`; }).join('')
  + '</XCUIElementTypeWebView></XCUIElementTypeWindow></XCUIElementTypeApplication>';
function find(using, value) {
  if (using !== '-ios predicate string') return [];
  if (/^elementType == 4$/.test(value)) return ['w'];
  const fld = value.match(/^elementType == (49|50)$/);
  if (fld) return shown().map((c, i) => [c, i]).filter(([c]) => c.type === (fld[1] === '49' ? 'TextField' : 'SecureTextField')).map(([, i]) => `${ver}-${i}`);
  const m = value.match(/(==\[c\]|CONTAINS\[c\]|BEGINSWITH\[c\]) '((?:[^'\\]|\\.)*)'/);
  if (!m) return [];
  const want = m[2].replace(/\\(.)/g, '$1').toLowerCase();
  const ok = (l) => (m[1].startsWith('==') ? l === want : m[1].startsWith('CONTAINS') ? l.includes(want) : l.startsWith(want));
  return shown().map((c, i) => [c, i]).filter(([c]) => ok(String(c.label).toLowerCase())).map(([, i]) => `${ver}-${i}`);
}
const ctl = (id) => { const [v, i] = id.split('-').map(Number); return v === ver ? shown()[i] : null; };
const send = (res, code, value) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ value })); };
const none = (res) => send(res, 404, { error: 'no such element', message: 'An element could not be located' });
createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    const b = body ? JSON.parse(body) : {};
    const p = req.url.replace(/^\/session\/s1/, '');
    if (req.method === 'POST' && req.url === '/session') return send(res, 200, { sessionId: 's1', capabilities: {} });
    if (req.method === 'DELETE') return send(res, 200, null);
    if (p === '/source') return send(res, 200, source());
    let m = p.match(/^(?:\/element\/([^/]+))?\/element(s?)$/);
    if (m && req.method === 'POST') {
      const ids = find(b.using, b.value);
      if (m[2]) return send(res, 200, ids.map((id) => ({ [W3C]: id })));
      return ids.length ? send(res, 200, { [W3C]: ids[0] }) : none(res);
    }
    if ((m = p.match(/^\/element\/([^/]+)\/rect$/))) {
      if (m[1] === 'w') return send(res, 200, { x: 0, y: 0, width: 1280, height: H });
      const c = ctl(m[1]); return c ? send(res, 200, rect(c)) : none(res);
    }
    if ((m = p.match(/^\/element\/([^/]+)\/attribute\/(\w+)$/))) {
      const c = ctl(m[1]); if (!c) return none(res);
      return send(res, 200, m[2] === 'label' ? c.label : m[2] === 'value' ? (c.type === 'SecureTextField' ? '•'.repeat((val[c.label] || '').length) : val[c.label] || '') : '');
    }
    if ((m = p.match(/^\/element\/([^/]+)\/clear$/))) { const c = ctl(m[1]); if (c) val[c.label] = ''; return send(res, 200, null); }
    if ((m = p.match(/^\/element\/([^/]+)\/click$/))) {
      const c = ctl(m[1]);
      if (!c) return none(res);
      const r = rect(c), cy = r.y + r.height / 2, lands = cy >= 0 && cy <= H;
      appendFileSync(LOG, `click ${c.label} ${lands ? 'landed' : 'outside the window'}\n`);
      if (/TextField/.test(c.type || '')) focus = c.label;
      if (lands && c.login && Object.values(val).length && shown().every((x) => !/TextField/.test(x.type || '') || val[x.label] === (x.type === 'TextField' ? c.login.user : c.login.pass))) { page = c.login.to; scroll = 0; ver++; }
      if (lands && (c.to || c.sw)) { if (c.to) { page = c.to; scroll = 0; } if (c.sw) surface = c.sw; ver++; }
      return send(res, 200, null);
    }
    if (p === '/execute/sync' && /scroll/.test(b.script || '')) {
      const d = (b.args && b.args[0] && b.args[0].deltaY) || 0;
      scroll = Math.max(0, Math.min(model.max_scroll || 0, scroll - d * 4));
      appendFileSync(LOG, `scroll ${d} -> ${scroll}\n`);
      return send(res, 200, null);
    }
    if (/screenshot$/.test(p)) return send(res, 200, 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
    if (p === '/actions' && req.method === 'POST') {
      const t = (b.actions || []).flatMap((a) => a.actions || []).filter((a) => a.type === 'keyDown').map((a) => a.value).join('');
      if (focus && /^[A-Za-z0-9]*$/.test(t)) val[focus] = (val[focus] || '') + t;
      appendFileSync(LOG, `keys ${/^[A-Za-z0-9]*$/.test(t) ? 'taken' : 'dropped'}\n`);
      return send(res, 200, null);
    }
    if (p === '/actions') return send(res, 200, null);
    if (p === '/execute/sync' && /keys/.test(b.script || '')) { if (focus) val[focus] = (val[focus] || '') + ((b.args && b.args[0] && b.args[0].keys) || []).join(''); return send(res, 200, null); }
    return send(res, 404, { error: 'unknown command', message: `fake-mac2: ${req.method} ${p}` });
  });
}).listen(0, '127.0.0.1', function () { writeFileSync(process.argv[3], String(this.address().port)); });

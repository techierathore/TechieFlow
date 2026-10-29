// tests/maccatalyst/fake-appium.mjs — a stand-in for Appium mac2, so the Mac head's screen check can be
// run on any machine with node (Chatur TF-016, Sevak TF-014). It serves saved element trees, one per
// screen, from a folder: <dir>/start.xml first, then whatever a click leads to.
//   node fake-appium.mjs <port> <dir>
// A click on a control labelled X opens <dir>/X.xml when it exists (lower case, spaces as dashes). A click
// on "Sign in" or "Log in" opens <dir>/home.xml only when both fields were typed into; the typed text is
// appended to <dir>/typed.txt. Only the calls tf-appium.mjs makes are answered.
import { createServer } from 'node:http';
import { appendFileSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseSource } from '../../.tfcore/utils/tf-appium.mjs';

const [port, dir] = process.argv.slice(2);
const TYPES = { 4: 'Window', 9: 'Button', 10: 'RadioButton', 42: 'Link', 49: 'TextField', 50: 'SecureTextField', 75: 'Cell' };
let page = 'start', focus = null;
const typed = {};
const xml = () => readFileSync(join(dir, `${page}.xml`), 'utf8');
const nodes = () => parseSource(xml());

function matches(n, using, value) {
  if (using === 'accessibility id') return n.id === value;
  const types = (value.match(/elementType (?:==|IN) \{?([\d, ]+)\}?/) || [, ''])[1].split(',').map((x) => TYPES[x.trim()]);
  if (!types.includes(n.type)) return false;
  const eq = value.match(/label ==\[c\] '([^']*)'/), has = value.match(/label CONTAINS\[c\] '([^']*)'/);
  const lab = (n.label || n.title || '').toLowerCase();
  if (eq) return lab === eq[1].toLowerCase();
  if (has) return lab.includes(has[1].toLowerCase());
  return true;
}
const el = (i) => ({ 'element-6066-11e4-a52e-4f735466cecf': `${page}:${i}` });

createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    const send = (code, value) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ value })); };
    const b = body ? JSON.parse(body) : {};
    const u = req.url;
    if (req.method === 'POST' && u === '/session') return send(200, { sessionId: 'fx', capabilities: {} });
    if (req.method === 'DELETE' && u === '/session/fx') return send(200, null);
    if (u === '/session/fx/source') return send(200, xml());
    if (u.endsWith('/screenshot')) return send(200, '');
    if (u === '/session/fx/actions') {
      if (req.method === 'POST' && focus !== null) {
        const text = b.actions[0].actions.filter((a) => a.type === 'keyDown').map((a) => a.value).join('');
        typed[focus] = (typed[focus] || '') + text;
        appendFileSync(join(dir, 'typed.txt'), `${focus}=${text}\n`);
      }
      return send(200, null);
    }
    let m = u.match(/^\/session\/fx(?:\/element\/([^/]+))?\/element$/);
    if (req.method === 'POST' && m) {
      const all = nodes();
      const within = m[1] ? new Set(descend(all, +m[1].split(':')[1])) : null;
      const hit = all.find((n) => (!within || within.has(n.i)) && matches(n, b.using, b.value));
      return hit ? send(200, el(hit.i)) : send(404, { error: 'no such element', message: 'An element could not be located' });
    }
    m = u.match(/^\/session\/fx\/element\/([^/]+)\/click$/);
    if (m) {
      const [p, i] = m[1].split(':'); const n = parseSource(readFileSync(join(dir, `${p}.xml`), 'utf8'))[+i];
      focus = n.type === 'TextField' || n.type === 'SecureTextField' ? n.type : null;
      const lab = (n.label || n.title || '').toLowerCase();
      if (/^(sign|log) in$/.test(lab)) { if (typed.TextField && typed.SecureTextField) page = 'home'; }
      else if (n.type !== 'TextField' && n.type !== 'SecureTextField') {
        const next = lab.replace(/[^a-z0-9]+/g, '-');
        if (existsSync(join(dir, `${next}.xml`))) page = next;
      }
      return send(200, null);
    }
    send(404, { error: 'unknown command', message: `${req.method} ${u}` });
  });
}).listen(+port, '127.0.0.1');

function descend(all, i) {
  const out = []; const todo = [...all[i].kids];
  while (todo.length) { const k = todo.shift(); out.push(k); todo.push(...all[k].kids); }
  return out;
}

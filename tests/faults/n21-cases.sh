# tests/faults/n21-cases.sh — sourced by tests/faults/run.sh; the cases of 21 Nov 2026. Each fails on the scripts of
# 20 Nov and passes now, with a control half. Uses run.sh's ok/bad/note/$SCRATCH/$UTILS/_parity and n16-cases.sh's _fx/_doc.

# --- TfLens TF-061: a failed sign-in was graded FAIL and RENDER-FAIL --------------------------------------------------
# On 19 Nov the shared account service answered 500, so nobody could sign in: tf-verify-screens.sh printed "LOGIN
# failed", every screen behind Sign in answered with the sign-in page, and every test stopped at page.waitForURL on
# /login. The verdict wrote FAIL (acceptance) and RENDER-FAIL, moved a Verified row, and the emit would have logged one
# miss a row. A row behind a failed sign-in is now NOT-MEASURED: it keeps its status and gets no gate record and no
# miss (tf_signin.py). Controls: the Sign-in screen's own row still fails on its own test; and when the screen check
# did sign in, a test that stops on the sign-in path is still a FAIL.
_tf061_fx() {   # <dir>: a project with four rows on three screens, listed
  local d="$1"; rm -rf "$d"
  mkdir -p "$d/.tfcore/.session" "$d/.tfcore/utils" "$d/docs/metrics" "$d/docs/mockups" "$d/tests/.artifacts/verify"; cp -r "$UTILS/." "$d/.tfcore/utils/"
  for s in runs gates sessions commits misses; do : > "$d/docs/metrics/$s.jsonl"; done
  printf 'appPhase: 1\nappKind: app\nappSize: S\n' > "$d/.tfcore/core-config.yaml"
  printf '# Fx — UI Design\n\n### Screen: Login (`/login`)\n\n### Screen: Estimates (`/estimates`)\n\n### Screen: Routing (`/routing`)\n' > "$d/docs/Fx-UIDesign.md"
  cat > "$d/docs/Fx-Checklist.md" <<'MD'
# Fx — Checklist

| ID | Title | Status | % | Remarks | Details |
|---|---|---|---|---|---|
| REQ-UI-001 | Sign in | Implemented | 90% | | [view](#d-req-ui-001) |
| REQ-UI-078 | Estimates table | Implemented | 90% | | [view](#d-req-ui-078) |
| REQ-UI-079 | Estimates range | Implemented | 90% | | [view](#d-req-ui-079) |
| REQ-UI-081 | Routing column | Verified | 100% | | [view](#d-req-ui-081) |

## UI / Pages

<a id="d-req-ui-001"></a>
- **REQ-UI-001** — the sign-in form. *Acceptance:* When the user looks on Login, then the form shows.

<a id="d-req-ui-078"></a>
- **REQ-UI-078** — the estimates table. *Acceptance:* When the user looks on Estimates, then the table shows.

<a id="d-req-ui-079"></a>
- **REQ-UI-079** — the range. *Acceptance:* When the user looks on Estimates, then the range shows.

<a id="d-req-ui-081"></a>
- **REQ-UI-081** — a column. *Acceptance:* When the user looks on Routing, then the column shows.
MD
  ( cd "$d" && TF_SKIP_SELFCHECK=1 bash .tfcore/utils/tf-verify-list.sh Fx all --phase 1 >/dev/null 2>&1 )
  printf '{"mode":"base","url":"http://localhost:9283","head":"web","rung":"run"}' > "$d/tests/.artifacts/verify/boot.json"
}
_tf061_ev() {   # <dir> <login json> <walled: yes|no> <the wait the tests failed on>: tests.json and screens.json of the run
  python3 - "$1/tests/.artifacts/verify" "$2" "$3" "$4" <<'PY'
import json, sys
d, login, walled, wait = sys.argv[1], sys.argv[2], sys.argv[3] == "yes", sys.argv[4]
t = lambda rid, reason: {"result": "FAIL", "source": "browser", "tests": [f"{rid} shows"], "skipped": [], "passed": 0, "failed": 1, "reason": reason, "screenshot": ""}
json.dump({"reqs": {"REQ-UI-001": t("REQ-UI-001", "expect(locator('h1')).toHaveText: expected 'Sign in' received 'Welcome'"),
                    "REQ-UI-078": t("REQ-UI-078", wait), "REQ-UI-081": t("REQ-UI-081", wait)},
           "browser": {"ran": True}, "unit": {"ran": False}}, open(f"{d}/tests.json", "w"))
ok = lambda n, r: {"name": n, "route": r, "render": "OK", "visual": "OK", "widths": [{"width": 1280, "theme": "light", "findings": []}]}
wall = lambda n, r: {"name": n, "route": r, "render": "UNREACHABLE", "visual": "n/a", "widths": [{"width": 1280, "findings": [
    {"check": "render", "class": "other", "detail": f"{r} redirected to the sign-in page (not signed in)"}]}]}
if login != "none":
    side = wall if walled else ok
    json.dump({"mode": "base", "login": json.loads(login), "skipped": [],
               "screens": [ok("Login", "/login"), side("Estimates", "/estimates"), side("Routing", "/routing")]}, open(f"{d}/screens.json", "w"))
PY
}
_tf061_run() { ( cd "$1" && export TF_SKIP_SELFCHECK=1 TF_METRICS_ROOT="$1"; bash .tfcore/utils/tf-verify-verdict.sh Fx --apply 2>&1; bash .tfcore/utils/tf-verify-emit.sh Fx 2>&1 ); }
_tf061_got() {   # <dir>: each row's verdict and status, then the rows with a gate record and with a miss
  python3 - "$1" <<'PY'
import json, sys
d = sys.argv[1]
v = json.load(open(f"{d}/tests/.artifacts/verify/verdicts.json"))["rows"]
ids = lambda f: ",".join(sorted({json.loads(l)["req_id"][-3:] for l in open(f"{d}/docs/metrics/{f}.jsonl") if l.strip()})) or "-"
print(" ".join(f"{r['id'][-3:]}={r['verdict']}/{r['status']}" for r in v), "gates:" + ids("gates"), "misses:" + ids("misses"))
PY
}
tf_061() {
  local d="$SCRATCH/tf061" got out
  local wait='TimeoutError: page.waitForURL: Timeout 60000ms exceeded. waiting for navigation until "load" navigated to "http://localhost:9283/login"'
  _tf061_fx "$d"; _tf061_ev "$d" '{"attempted":true,"ok":false,"error":"still on the sign-in page after 3 attempts: HTTP 500"}' yes "$wait"
  out="$(_tf061_run "$d")"; got="$(_tf061_got "$d" 2>&1)"
  [[ "$got" == "001=FAIL/FAIL 078=NOT-MEASURED/Implemented 079=NOT-MEASURED/Implemented 081=NOT-MEASURED/Verified gates:001 misses:001" ]] \
    && grep -q '| REQ-UI-081 | Routing column | Verified | 100% | .*not measured — sign-in failed' "$d/docs/Fx-Checklist.md" \
    && grep -q 'not measured, the sign-in failed: 3 row(s)' <<<"$out" \
    && ok tf_061a "sign-in failed: the three rows behind it are not measured and keep their status, no gate record, no miss; the Sign-in row still fails" \
    || bad tf_061a "$got // $(grep 'REQ-UI-081' "$d/docs/Fx-Checklist.md" | cut -c1-160)"
  _tf061_fx "$d"; _tf061_ev "$d" none no "$wait"
  out="$(_tf061_run "$d")"; got="$(_tf061_got "$d" 2>&1)"
  [[ "$got" == "001=FAIL/FAIL 078=NOT-MEASURED/Implemented 079=NOT-DRIVEN/Implemented 081=NOT-MEASURED/Verified gates:001 misses:001" ]] \
    && ok tf_061b "no screen check ran and a test stopped waiting on the sign-in path: that row is not measured either" \
    || bad tf_061b "$got"
  _tf061_fx "$d"; _tf061_ev "$d" '{"attempted":true,"ok":true,"url":"http://localhost:9283/repos"}' no "$wait"
  out="$(_tf061_run "$d")"; got="$(_tf061_got "$d" 2>&1)"
  [[ "$got" == "001=FAIL/FAIL 078=FAIL/FAIL 079=NOT-TESTED/Implemented 081=FAIL/FAIL gates:001,078,081 misses:001,078,081" ]] \
    && ok tf_061c "the screen check signed in and the screens drew: a test that stops on the sign-in path is still a FAIL, with its record and miss" \
    || bad tf_061c "$got"
}

# --- TrStudio TF-011: a mockup's empty slider track read as a missing badge -------------------------------------------
# docs/mockups/video-studio.html draws Duration and Motion strength as <div class="slider"><i></i><b></b></div>: 6 px
# tall, fully rounded, filled, no text. The app draws a range input. The track was a badge the app "did not draw", so
# four Video studio rows could not pass. A drawn slider is now matched to the app's range input (or a library's
# role="slider" handle) by count under the same parent, and a mockup box with no text, no icon and no badge class
# (badge, pill, chip, tag, dot) is not reported as a missing badge. Controls: a slider the app does not draw at all is
# reported as a missing slider; a textless dot of class "dot" and a pill with text the app leaves out are still missing.
ts_011() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ts_011 — needs playwright\n'; return; }
  local d="$SCRATCH/ts011" out b='margin:0;padding:24px;font-family:sans-serif;background:#fff;color:#17171f'
  local css='<style>.card{border:1px solid #e5e5ef;border-radius:12px;padding:16px;width:420px}.slider{position:relative;height:6px;background:#f0f0f7;border-radius:999px;margin:8px 0 2px}.slider>i{position:absolute;left:0;top:0;height:100%;background:#7c3aed;border-radius:999px}.slider>b{position:absolute;top:50%;width:16px;height:16px;border-radius:999px;background:#fff;border:2px solid #7c3aed;transform:translate(-50%,-50%)}.dot{display:inline-block;width:8px;height:8px;border-radius:999px;background:#dc2626}.badge{display:inline-block;border:1px solid #ddd0fb;border-radius:999px;padding:2px 10px;font-size:12px;background:#f1ecfe}.skel{display:block;height:10px;border-radius:999px;background:#f0f0f7;margin-top:8px}</style>'
  local row='<div><span>%s</span><span>%s</span></div>'
  _sl() { printf "<div style=\"margin-bottom:14px\">$row%s</div>" "$1" "$2" "$3"; }
  local ms='<div class="slider"><i style="width:40%"></i><b style="left:40%"></b></div>' as='<input type="range" min="2" max="10" value="5" style="width:100%">'
  local m; m="$(_doc mockup "$b" "$css<h1 data-testid=\"title\">Video studio</h1><div class=\"card\" data-testid=\"card-controls\"><h3>Controls</h3>$(_sl Duration 5s "$ms")$(_sl 'Motion strength' 0.7 "$ms")<div data-testid=\"state\"><em>Status</em><span class=\"dot\"></span><span class=\"badge\">Queued</span><span class=\"skel\"></span></div></div>")"
  _app() { _doc app "$b" "$css<h1 data-testid=\"title\">Video studio</h1><div class=\"card\" data-testid=\"card-controls\"><h3>Controls</h3>$(_sl Duration 5s "$1")$(_sl 'Motion strength' 0.7 "$1")<div data-testid=\"state\"><em>Status</em>$2</div></div>"; }
  _fx "$d" video "$m" "$(_app "$as" '<span class="dot"></span><span class="badge">Queued</span>')"
  out="$(TF_PARITY_ARGS=--no-menus _parity "$d" video /video/)"
  [[ "$out" != NO-RESULT ]] && ! grep -q ' missing ' <<<"$out" \
    && ok ts_011a "a mockup's drawn slider where the app draws a range input, and a textless box with no badge class: no missing badge" \
    || bad ts_011a "still reported: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  _fx "$d" video "$m" "$(_app '' '')"
  out="$(TF_PARITY_ARGS=--no-menus _parity "$d" video /video/)"
  [[ "$(grep -c '^1280 card-controls > div\[[01]\] > div\[1\] missing the mockup draws a slider here' <<<"$out")" == 2 ]] \
    && grep -q '^1280 state > span\[0\] missing' <<<"$out" && grep -q '^1280 state > span\[1\] missing' <<<"$out" && ! grep -q 'span\[2\] missing' <<<"$out" \
    && ok ts_011b "a slider the app does not draw is a missing slider; a dot of class dot and a pill with text left out are still missing" \
    || bad ts_011b "a real missing element was lost: $(tr '\n' '|' <<<"$out" | cut -c1-400)"
}

# --- Chatur TF-049: a ticked menu item whose only effect is its own tick read as "does nothing when clicked" ---------
# Chatur's View › Show hidden files is a menuitemcheckbox: its tick shows only inside the menu, which the click shuts,
# and with no hidden file in the open project nothing else on the page moves. The walk saw no change and reported it,
# so five screens read render EMPTY. The walk now opens the menu again and reads the item's tick: a tick that moved is
# an effect ("toggled its tick"), and it is put back. Control: a tickable item whose tick never moves, and a plain
# item that does nothing, are still reported.
ch_049() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_049 — needs playwright\n'; return; }
  local d="$SCRATCH/ch049" port srv out
  rm -rf "$d"; mkdir -p "$d/docs/mockups" "$d/site"
  printf '<!doctype html><html><body><h1 data-testid="title">Workbench</h1><button data-testid="view">View</button></body></html>\n' > "$d/docs/mockups/main.html"
  cat > "$d/site/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{font:14px system-ui;margin:0;padding:16px}[role=menu]{display:none;border:1px solid #ccc}[role=menu].o{display:block}</style></head><body>
<h1 data-testid="title">Workbench</h1><p data-testid="files">src README.md</p>
<button data-testid="view" aria-haspopup="menu" aria-expanded="false" aria-controls="m" onclick="t()">View</button>
<div role="menu" id="m"><button role="menuitemcheckbox" aria-checked="false" onclick="this.setAttribute('aria-checked',this.getAttribute('aria-checked')==='true'?'false':'true');c()">Show hidden files</button><button role="menuitemcheckbox" aria-checked="false" onclick="c()">Dead toggle</button><button role="menuitem" onclick="c()">Nothing</button></div>
<script>function t(){var m=document.getElementById('m');m.classList.toggle('o');document.querySelector('[data-testid=view]').setAttribute('aria-expanded',m.classList.contains('o'))}
function c(){document.getElementById('m').classList.remove('o');document.querySelector('[data-testid=view]').setAttribute('aria-expanded','false')}</script></body></html>
HTML
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"; cp "$UTILS"/tf-*.mjs "$d/"
  port="$(_free_port)"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d" && tf_timeout 300 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen main=/ --widths 1280 --themes light \
      --render-wait 800 --wait 300 --json-out "$d/s.json" --shots-dir "$d/shots" > "$d/s.log" 2>&1 )
  kill "$srv" 2>/dev/null
  out="$(grep -ohE '"?View › [A-Za-z ]+"? does nothing when clicked' "$d/s.log" "$d/s.json" 2>/dev/null | sort -u)"
  local eff; eff="$(python3 -c "import json;print([c.get('effect') for c in json.load(open('$d/s.json'))['menus']['clicks'] if c.get('label')=='Show hidden files'])" 2>&1)"
  ! grep -q 'Show hidden files' <<<"$out" && grep -q 'toggled its tick' <<<"$eff" \
    && ok ch_049a "a ticked menu item whose only effect is its own tick counts as doing something" \
    || bad ch_049a "effect: $eff // $(tr '\n' '|' <<<"$out") $(grep -m2 -i 'menu' "$d/s.log" | tr '\n' '|' | cut -c1-200)"
  grep -q 'View › Dead toggle' <<<"$out" && grep -q 'View › Nothing' <<<"$out" \
    && ok ch_049b "a tickable item whose tick never moves, and a plain item that does nothing, are still reported" \
    || bad ch_049b "a real do-nothing item lost its finding: $(tr '\n' '|' <<<"$out") $(tail -3 "$d/s.log" | tr '\n' '|' | cut -c1-200)"
}

# --- Chatur TF-051: a side sheet the screen check opened itself was graded as overlapping the page -------------------
# Chatur's subbar holds "Open navigation", a TrBlazeUI SheetTrigger (aria-haspopup="dialog"). In the light pass the
# dropdown walk opens every dialog trigger once, presses Escape and moves on; the Sheet does not close on Escape, so the
# dark pass measured "subbar overlaps subnav-sheet". A dialog Escape leaves open is now closed by its own Close button,
# then by a click beside it (on its backdrop); one that stays open is named, and the overlap at that width is not
# measured (as Sevak TF-043 does for a list). Controls: a sheet nothing closes is named and gives no overlap; two
# controls that really overlap are still reported.
_ch051_page() {   # <closes: backdrop|close|never> -> a 390 px page with a subbar, a sheet trigger and a real overlap
  local close=''
  case "$1" in backdrop) close='document.getElementById("ov").onclick=shut;' ;; close) close='document.getElementById("x").onclick=shut;' ;; esac
  cat <<HTML
<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font:14px system-ui;background:#fff;color:#111}.dark body{background:#111;color:#eee}
#sub{display:flex;align-items:center;height:44px;padding:0 8px;border-bottom:1px solid #ccc}#ov{position:fixed;inset:0;z-index:50;background:rgba(0,0,0,.6)}
#sh{position:fixed;left:0;top:0;bottom:0;width:256px;z-index:50;background:#fff;padding:16px;box-sizing:border-box}[hidden]{display:none!important}</style></head><body>
<div data-testid="subbar" id="sub"><button data-testid="subnav-trigger" aria-label="Open navigation" aria-haspopup="dialog" aria-expanded="false" aria-controls="sh" onclick="op()">≡</button><span>Agents</span></div>
<main style="padding:16px"><h1 data-testid="title">Agents</h1><button data-testid="a" style="position:relative;width:120px;height:40px">Save</button><button data-testid="b" style="position:relative;left:-60px;width:120px;height:40px">Cancel</button></main>
<div id="ov" data-state="open" hidden></div><div id="sh" data-testid="subnav-sheet" role="dialog" aria-modal="true" data-state="open" hidden><h2>Chatur</h2><a href="#">General</a> <button id="x"><span style="position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)">Close</span>×</button></div>
<script>function op(){ov.hidden=false;sh.hidden=false;document.querySelector('[data-testid=subnav-trigger]').setAttribute('aria-expanded','true')}
function shut(){ov.hidden=true;sh.hidden=true;document.querySelector('[data-testid=subnav-trigger]').setAttribute('aria-expanded','false')}$close</script></body></html>
HTML
}
ch_051() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_051 — needs playwright\n'; return; }
  local d="$SCRATCH/ch051" port srv out s
  rm -rf "$d"; mkdir -p "$d/docs/mockups" "$d/site"
  for s in backdrop close never; do
    mkdir -p "$d/site/$s"; _ch051_page "$s" > "$d/site/$s/index.html"
    printf '<!doctype html><html><body><div data-testid="subbar"><button data-testid="subnav-trigger">≡</button></div><h1 data-testid="title">Agents</h1><button data-testid="a">Save</button><button data-testid="b">Cancel</button></body></html>\n' > "$d/docs/mockups/$s.html"
  done
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"; cp "$UTILS"/tf-*.mjs "$d/"
  port="$(_free_port)"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d" && tf_timeout 300 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen backdrop=/backdrop/ --screen close=/close/ --screen never=/never/ \
      --widths 390 --themes light,dark --no-menus --json-out "$d/s.json" --shots-dir "$d/shots" > "$d/s.log" 2>&1 )
  kill "$srv" 2>/dev/null
  out="$(python3 -c "
import json
for s in json.load(open('$d/s.json'))['screens']:
    for w in s['widths']:
        ov = sorted({f['detail'].split(' at ')[0] for f in w.get('findings', []) if f['class'] == 'overlap'})
        print(s['name'], w.get('theme'), 'sheet' if any('subnav-sheet' in o for o in ov) else '-', 'real' if any(o.startswith('a overlaps b') for o in ov) else '-', 'nm' if str(w.get('overlap','')).startswith('not measured') else '-', ','.join((w.get('dropdowns') or {}).get('unclosed') or []) or '-')" 2>&1)"
  grep -q '^backdrop dark - real - -$' <<<"$out" && grep -q '^close dark - real - -$' <<<"$out" \
    && ok ch_051a "a side sheet Escape does not close is shut by its backdrop or its Close button before the dark pass: no overlap with the subbar" \
    || bad ch_051a "the sheet was left open and measured: $(tr '\n' '|' <<<"$out")"
  grep -qE '^never light - real - (Open navigation|subnav-trigger)' <<<"$out" && grep -qE '^never dark - - nm (Open navigation|subnav-trigger)$' <<<"$out" \
    && ok ch_051b "a sheet nothing closes is named as not closed and the overlap there is not measured, never an overlap" \
    || bad ch_051b "the stuck sheet was measured or not named: $(tr '\n' '|' <<<"$out")"
}

# --- AstroLyfe TF-065: a light-only app was graded in dark mode once its UI library shipped .dark colours ----------
# AstroLyfe sets <meta name="color-scheme" content="light"> and :root{color-scheme:light} and never uses the class
# `dark`; TrBlazeUI 2.2.6 defines its colours again under :where(.dark). The dark pass adds the class `dark`, the
# library's colours turn on under the app's white header, and every screen failed in dark mode. A page that still says
# color-scheme light only (meta, <html>, <body>) once dark is put on has no dark theme: it is left light, read as "no
# dark theme", and not graded in dark, also under --themes light,dark. Controls: an app whose .dark sets color-scheme
# dark, and a page whose meta says "light dark", are still graded in dark.
_tf065_page() {   # <meta content or ''> <dark color-scheme or ''>
  local meta='' cs=''
  [[ -n "$1" ]] && meta="<meta name=\"color-scheme\" content=\"$1\">"
  [[ -n "$2" ]] && cs="color-scheme:$2;"
  printf '<!doctype html><html><head><meta charset="utf-8">%s<style>:root{color-scheme:light;--bg:#fff;--fg:#111;--card:#fff}html.dark{%s--bg:#0b0b10;--fg:#eee;--card:#16161d}body{margin:0;font:14px system-ui;background:var(--bg);color:var(--fg)}header{background:#fff;color:#111;padding:12px}.card{background:var(--card);color:var(--fg);margin:16px;padding:24px;min-height:300px}</style></head><body><header data-testid="top">AstroLyfe</header><main class="card"><h1 data-testid="title">Testing run</h1><button data-testid="go">Run</button></main></body></html>\n' "$meta" "$cs"
}
as_065() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: as_065 — needs playwright\n'; return; }
  local d="$SCRATCH/as065" port srv out s
  rm -rf "$d"; mkdir -p "$d/docs/mockups" "$d/site/lightonly" "$d/site/realdark" "$d/site/both"
  _tf065_page light '' > "$d/site/lightonly/index.html"; _tf065_page '' dark > "$d/site/realdark/index.html"; _tf065_page 'light dark' '' > "$d/site/both/index.html"
  for s in lightonly realdark both; do printf '<!doctype html><html><body><header data-testid="top">AstroLyfe</header><h1 data-testid="title">Testing run</h1><button data-testid="go">Run</button></body></html>\n' > "$d/docs/mockups/$s.html"; done
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"; cp "$UTILS"/tf-*.mjs "$d/"
  port="$(_free_port)"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  for t in auto light,dark; do
    ( cd "$d" && tf_timeout 300 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen lightonly=/lightonly/ --screen realdark=/realdark/ --screen both=/both/ \
        --widths 1280 --themes "$t" --no-menus --json-out "$d/s-${t%%,*}.json" --shots-dir "$d/shots" > "$d/s-${t%%,*}.log" 2>&1 )
  done
  kill "$srv" 2>/dev/null
  out="$(for t in auto light; do python3 -c "
import json
for s in json.load(open('$d/s-$t.json'))['screens']:
    print('$t', s['name'], 'dark' if any(w.get('theme') == 'dark' for w in s['widths']) else 'light-only', s.get('dark') or '-')" 2>&1; done)"
  grep -q '^auto lightonly light-only not offered$' <<<"$out" && grep -q '^light lightonly light-only not offered$' <<<"$out" \
    && ok as_065a "a page that says color-scheme light only has no dark theme: not graded in dark, in auto and under --themes light,dark" \
    || bad as_065a "the light-only page was graded in dark: $(tr '\n' '|' <<<"$out")"
  grep -q '^auto realdark dark' <<<"$out" && grep -q '^light realdark dark' <<<"$out" && grep -q '^light both dark' <<<"$out" \
    && ok as_065b "an app whose dark theme sets color-scheme dark, and a page that says light dark, are still graded in dark" \
    || bad as_065b "a real dark theme lost its dark pass: $(tr '\n' '|' <<<"$out")"
  # the mockup check, under --themes light,dark: the light-only app's dark pass is "not offered", the real one's is run
  for s in lightonly realdark; do
    TF_PARITY_ARGS="--themes light,dark --no-menus" _parity "$d" "$s" "/$s/" >/dev/null
    out+=$'\n'"parity $s $(python3 -c "import json;print(','.join(json.load(open('$d/parity.json'))['screens'][0].get('themes_not_offered') or ['-']))" 2>&1)"
  done
  grep -q '^parity lightonly dark$' <<<"$out" && grep -q '^parity realdark -$' <<<"$out" \
    && ok as_065c "the mockup check under --themes light,dark: no dark pass for the light-only app, a dark pass for the real one" \
    || bad as_065c "$(grep '^parity' <<<"$out" | tr '\n' '|')"
}

# --- Chatur TF-050: the unit-test leg could not finish inside one 10-minute call, and nothing was kept --------------
# On Chatur's cmd.exe rung the build alone takes 2 to 9 minutes and the REQ-UI-048 tests 6.4; the agent's call is cut
# at 10 minutes, `dotnet test` on Windows carries on and finishes into its log, but no tests.json is written. Now:
# --no-build is handed to `dotnet test` (after one build), --from-log <log> only parses a finished log into the same
# JSON, and the unit run first says where its log goes and how to read it if the call is cut off. Controls: a log with
# no end-of-run line (dotnet still running) and a log that is not there are refused, and nothing is written or run.
ch_050() {
  local d="$SCRATCH/ch050" out rc
  rm -rf "$d"; mkdir -p "$d/.tfcore/utils" "$d/tests/unit/Fx.Tests" "$d/tests/.artifacts/build" "$d/tests/.artifacts/verify"
  cp "$UTILS"/tf-verify-tests.sh "$UTILS"/tf-portable.sh "$UTILS"/tf-lock.sh "$UTILS"/tf-req-ids.py "$UTILS"/tf-test-guard.sh "$d/.tfcore/utils/"
  for f in tf-verify-around.sh tf-verify-settings.py; do [[ -f "$UTILS/$f" ]] && cp "$UTILS/$f" "$d/.tfcore/utils/"; done
  : > "$d/tests/unit/Fx.Tests/Fx.Tests.csproj"
  cat > "$d/.tfcore/utils/tf-build.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> tests/.artifacts/build-args.txt
printf '  Passed REQ-UI-048 the run panel shows the steps [2 ms]\nPassed!  - Failed: 0, Passed: 1, Skipped: 0, Total: 1\n' > tests/.artifacts/build/20261120T070249Z-test-1.log
echo "PASS  test (stand-in); log tests/.artifacts/build/20261120T070249Z-test-1.log"
SH
  local L="tests/.artifacts/build/20261120T070249Z-test-29448.log" H="tests/.artifacts/build/20261120T080000Z-test-30000.log"
  printf 'Build succeeded.\n  Passed REQ-UI-048 the run panel shows the steps [2 m 1 s]\n  Passed REQ-UI-048 a step that fails is red [1 m 3 s]\n  Failed REQ-UI-049 the board scrolls [3 s]\nFailed!  - Failed: 1, Passed: 2, Skipped: 0, Total: 3, Duration: 6 m 24 s - Fx.Tests.dll (net10.0)\n' > "$d/$L"
  printf 'Build succeeded.\n  Passed REQ-UI-048 the run panel shows the steps [2 m 1 s]\n' > "$d/$H"
  out="$(cd "$d" && bash .tfcore/utils/tf-verify-tests.sh --no-browser --no-build --target tests/unit/Fx.Tests/Fx.Tests.csproj --filter 'DisplayName~REQ-UI-04' 2>&1)"
  grep -q -- '--no-build' "$d/tests/.artifacts/build-args.txt" 2>/dev/null && grep -q -- '--from-log' <<<"$out" \
    && ok ch_050a "--no-build reaches dotnet test, and the unit run says first how to read its log if the call is cut off" \
    || bad ch_050a "args: $(cat "$d/tests/.artifacts/build-args.txt" 2>/dev/null) // $(tr '\n' '|' <<<"$out" | cut -c1-240)"
  rm -f "$d/tests/.artifacts/build-args.txt"
  out="$(cd "$d" && bash .tfcore/utils/tf-verify-tests.sh --no-browser --from-log "$L" --json-out tests/.artifacts/verify/tests-fromlog.json 2>&1)"; rc=$?
  local got; got="$(python3 -c "import json;r=json.load(open('$d/tests/.artifacts/verify/tests-fromlog.json'))['reqs'];print(' '.join(f'{k}={v[\"result\"]}' for k,v in sorted(r.items())))" 2>&1)"
  [[ $rc -eq 0 && "$got" == "REQ-UI-048=PASS REQ-UI-049=FAIL" && ! -f "$d/tests/.artifacts/build-args.txt" ]] \
    && ok ch_050b "--from-log parses a finished log into tests.json, with its passes and failures, and runs nothing" \
    || bad ch_050b "rc $rc; $got; ran: $(cat "$d/tests/.artifacts/build-args.txt" 2>/dev/null) // $(tr '\n' '|' <<<"$out" | cut -c1-200)"
  rm -f "$d/tests/.artifacts/verify/tests-unfinished.json"
  out="$(cd "$d" && bash .tfcore/utils/tf-verify-tests.sh --no-browser --from-log "$H" --json-out tests/.artifacts/verify/tests-unfinished.json 2>&1)"; rc=$?
  local out2 rc2; out2="$(cd "$d" && bash .tfcore/utils/tf-verify-tests.sh --no-browser --from-log tests/.artifacts/build/none.log --json-out tests/.artifacts/verify/tests-none.json 2>&1)"; rc2=$?
  [[ $rc -eq 2 && $rc2 -eq 2 && ! -f "$d/tests/.artifacts/verify/tests-unfinished.json" && ! -f "$d/tests/.artifacts/verify/tests-none.json" && ! -f "$d/tests/.artifacts/build-args.txt" ]] \
    && grep -q 'no end-of-run line' <<<"$out" \
    && ok ch_050c "a log with no end-of-run line (dotnet still running) and a missing log are refused; nothing is written or run" \
    || bad ch_050c "rc $rc/$rc2 // $(tr '\n' '|' <<<"$out$out2" | cut -c1-240)"
}

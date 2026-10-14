#!/usr/bin/env bash
# Sevak TF-006 fixture: a page themed in oklch(), as a TrBlazeUI app is. It carries a theme menu
# (Light, already chosen; Dark; Match system, which resolves to light) that switches data-theme and the
# class `dark` on <html>, and a workspace switcher whose trigger (aria-haspopup="true", aria-controls)
# opens a popover with role="group", not a menu. A second page puts oklch text on an oklch background
# at about 1.2 : 1. Writes $1/docs/mockups and $1/site.
d="$1"; mkdir -p "$d/docs/mockups" "$d/site/app" "$d/site/faint"
css='<style>:root{--bg:oklch(0.985 0.002 270);--fg:oklch(0.21 0.02 270);--card:oklch(1 0 0)}html[data-theme="dark"]{--bg:oklch(0.16 0.02 270);--fg:oklch(0.93 0.01 270);--card:oklch(0.21 0.02 270)}
body{margin:0;font:14px/20px system-ui;background:var(--bg);color:var(--fg);min-height:100vh} .bar{display:flex;gap:8px;padding:6px}
button{color:var(--fg);background:var(--card);border:1px solid var(--fg)} .pop{position:absolute;top:36px;background:var(--card);border:1px solid var(--fg);display:flex;flex-direction:column;z-index:5}
.pop[hidden]{display:none} main{padding:16px}</style>'
mock='<div class="bar"><button data-testid="theme-toggle">Theme</button><button data-testid="ws-switch">Alpha</button></div><main><h1 data-testid="title">Today</h1><p data-testid="body-text">Three things to do.</p></main>'
printf '<!doctype html><html data-theme="light"><head><meta charset="utf-8"><title>app</title>%s</head><body>%s</body></html>\n' "$css" "$mock" > "$d/docs/mockups/app.html"
printf '<!doctype html><html data-theme="light"><head><meta charset="utf-8"><title>faint</title>%s</head><body><main><h1 data-testid="title">Faint</h1><p data-testid="body-text">Hard to read.</p></main></body></html>\n' "$css" > "$d/docs/mockups/faint.html"
cat > "$d/site/app/index.html" <<HTML
<!doctype html><html data-theme="light"><head><meta charset="utf-8"><title>app</title>$css</head><body>
<div class="bar">
 <span style="position:relative"><button data-testid="theme-toggle" aria-haspopup="menu" aria-label="Change theme" onclick="tog('tm',event)">Theme</button>
  <div id="tm" class="pop" role="menu" hidden><button role="menuitem" onclick="pick('light')">Light</button><button role="menuitem" onclick="pick('dark')">Dark</button><button role="menuitem" onclick="pick('system')">Match system</button></div></span>
 <span style="position:relative"><button data-testid="ws-switch" aria-haspopup="true" aria-expanded="false" aria-controls="ws-pop" onclick="tog('ws-pop',event)">Alpha</button>
  <div id="ws-pop" class="pop" role="group" hidden><button onclick="ws('Alpha')">Alpha</button><button onclick="ws('Beta')">Beta</button></div></span>
</div>
<main><h1 data-testid="title">Today</h1><p data-testid="body-text">Three things to do in <b id="w">Alpha</b>.</p></main>
<script>
function shut(){document.querySelectorAll('.pop').forEach(p=>p.hidden=true);document.querySelector('[aria-controls]').setAttribute('aria-expanded','false');}
function tog(id,e){e.stopPropagation();var p=document.getElementById(id),o=p.hidden;shut();p.hidden=!o;if(id==='ws-pop')e.currentTarget.setAttribute('aria-expanded',String(o));}
function pick(m){var dark=m==='dark'||(m==='system'&&matchMedia('(prefers-color-scheme: dark)').matches);var h=document.documentElement;h.setAttribute('data-theme',dark?'dark':'light');h.classList.toggle('dark',dark);shut();}
function ws(n){document.getElementById('w').textContent=n;document.querySelector('[aria-controls]').textContent=n;shut();}
document.addEventListener('click',shut);document.addEventListener('keydown',e=>{if(e.key==='Escape')shut();});
</script></body></html>
HTML
printf '<!doctype html><html data-theme="light"><head><meta charset="utf-8"><title>faint</title>%s</head><body><main><h1 data-testid="title">Faint</h1><p data-testid="body-text" style="color:oklch(0.9 0.005 270)">Hard to read.</p></main></body></html>\n' "$css" > "$d/site/faint/index.html"

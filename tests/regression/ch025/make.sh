#!/usr/bin/env bash
# Chatur TF-025 fixture: a branch picker that really switches. The app keeps the branch checked out in
# localStorage, ticks it in the menu, and tells the server about every checkout (GET /checkout?b=<name>),
# which server.py appends to $1/checkouts.log. The mockup draws the picker open with main ticked.
# Writes $1/docs/mockups, $1/site and $1/server.py.
d="$1"; mkdir -p "$d/docs/mockups" "$d/site/main" "$d/site/repository"
css='<style>body{margin:0;font:14px/20px system-ui} .bar{display:flex;gap:8px;padding:4px;border-bottom:1px solid #ccc} .menu{position:relative} .drop{display:none;position:absolute;top:28px;left:0;background:#fff;border:1px solid #ccc;min-width:220px;flex-direction:column;z-index:5} .menu.open .drop{display:flex} .drop>*{text-align:left;padding:4px 8px} main{padding:16px}</style>'
js='<script>function menu(b,e){e.stopPropagation();var m=b.parentElement;var o=m.classList.contains("open");document.querySelectorAll(".menu.open").forEach(function(x){x.classList.remove("open")});if(!o)m.classList.add("open");}document.addEventListener("click",function(){document.querySelectorAll(".menu.open").forEach(function(x){x.classList.remove("open")})});document.addEventListener("keydown",function(e){if(e.key==="Escape")document.querySelectorAll(".menu.open").forEach(function(x){x.classList.remove("open")})});</script>'
page() { printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title>%s%s</head><body>%s<main><h1 data-testid="title">%s</h1><p data-testid="body-text">The %s screen with its real content.</p></main></body></html>\n' "$1" "$css" "$js" "$2" "$1" "$1"; }
page main '<div class="bar" data-testid="toolbar">
 <div class="menu" data-testid="branch-pick"><button onclick="menu(this,event)">main</button>
  <div class="drop" data-testid="branch-pop" data-tf-state="popup-open"><button><span class="tick">✓</span>main</button><button><span class="tick"></span>feature/board</button><button><span class="tick"></span>run/BRD-96-101</button><a href="repository.html">Open the repository…</a></div></div>
</div>' > "$d/docs/mockups/main.html"
page repository '' > "$d/docs/mockups/repository.html"
app='<div class="bar" data-testid="toolbar">
 <div class="menu" data-testid="branch-pick"><button id="trig" onclick="menu(this,event)">main</button>
  <div class="drop" data-testid="branch-pop" role="menu" id="pop"></div></div>
</div>
<script>
var NAMES = ["main", "feature/board", "run/BRD-96-101"];
var TICK = "<svg width=\"14\" height=\"14\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" class=\"lucide-icon\" aria-hidden=\"true\"><path d=\"M20 6L9 17l-5-5\"/></svg>";
function head(){ return localStorage.getItem("b") || "main"; }
function draw(){
  var h = head(); document.getElementById("trig").textContent = h;
  var pop = document.getElementById("pop"); pop.innerHTML = "";
  NAMES.forEach(function(n){ var b = document.createElement("button"); b.setAttribute("role", "menuitem");
    b.innerHTML = (n === h ? TICK : "") + "<span>" + n + "</span>";
    b.onclick = function(e){ if (n === head()) return; localStorage.setItem("b", n); fetch("/checkout?b=" + encodeURIComponent(n)); draw(); };
    pop.appendChild(b); });
  var r = document.createElement("button"); r.setAttribute("role", "menuitem"); r.textContent = "Open the repository…";
  r.onclick = function(){ location.href = "/repository/"; }; pop.appendChild(r);
}
draw();
</script>'
page main "$app" > "$d/site/main/index.html"
page repository '' > "$d/site/repository/index.html"
cat > "$d/server.py" <<'PY'
import http.server, os, sys, urllib.parse
ROOT = sys.argv[2]
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=os.path.join(ROOT, "site"), **k)
    def log_message(self, *a): pass
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/checkout":
            with open(os.path.join(ROOT, "checkouts.log"), "a") as f:
                f.write(urllib.parse.parse_qs(u.query).get("b", [""])[0] + "\n")
            self.send_response(204); self.end_headers(); return
        super().do_GET()
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY

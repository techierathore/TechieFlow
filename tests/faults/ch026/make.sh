#!/usr/bin/env bash
# Chatur TF-026 fixture: File › Recent projects ▸ opens a project per row. The app keeps the open project
# in localStorage, shows its name in the menu bar, and tells the server about every open
# (GET /open?p=<name>), which server.py appends to $1/opens.log. The last row, Project list, goes to Start.
# Writes $1/docs/mockups, $1/site and $1/server.py.
d="$1"; mkdir -p "$d/docs/mockups" "$d/site/main" "$d/site/start"
css='<style>body{margin:0;font:14px/20px system-ui} .bar{display:flex;gap:8px;padding:4px;border-bottom:1px solid #ccc} .menu{position:relative} .drop,.sub{display:none;position:absolute;background:#fff;border:1px solid #ccc;min-width:200px;flex-direction:column;z-index:5} .drop{top:28px;left:0} .sub{top:0;left:200px} .menu.open>.drop,.drop .open>.sub{display:flex} .drop button,.sub button{text-align:left;padding:4px 8px} .row{position:relative} main{padding:16px}</style>'
page() { printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title>%s</head><body>%s<main><h1 data-testid="title">%s</h1><p data-testid="body-text">The %s screen with its real content.</p></main></body></html>\n' "$1" "$css" "$2" "$1" "$1"; }
page main '<div class="bar" data-testid="menubar"><span data-testid="project-name">WbA</span>
 <div class="menu" data-testid="file-menu"><button>File</button>
  <div class="drop" data-testid="file-pop" data-tf-state="popup-open"><button>New project</button><a href="start.html">Recent projects ▸</a></div></div>
</div>' > "$d/docs/mockups/main.html"
page start '' > "$d/docs/mockups/start.html"
app='<div class="bar" data-testid="menubar"><span data-testid="project-name" id="cur"></span>
 <div class="menu" data-testid="file-menu"><button id="trig" aria-haspopup="menu" onclick="tog(event)">File</button>
  <div class="drop" data-testid="file-pop" role="menu">
   <button role="menuitem" onclick="go(event)">New project</button>
   <div class="row" id="rrow"><button role="menuitem" aria-haspopup="menu" aria-controls="recent" aria-expanded="false" id="rbtn" onclick="sub(event)">Recent projects</button>
    <div class="sub" role="menu" id="recent"></div></div>
  </div></div>
</div>
<script>
function cur(){ return localStorage.getItem("p") || "WbA"; }
function shut(){ document.querySelectorAll(".open").forEach(function(x){x.classList.remove("open")}); document.getElementById("rbtn").setAttribute("aria-expanded","false"); }
function tog(e){ e.stopPropagation(); var m = e.target.parentElement, o = m.classList.contains("open"); shut(); if (!o) { draw(); m.classList.add("open"); } }
function sub(e){ e.stopPropagation(); document.getElementById("rrow").classList.add("open"); document.getElementById("rbtn").setAttribute("aria-expanded","true"); }
function go(e){ e.stopPropagation(); shut(); document.querySelector("[data-testid=title]").textContent = "New project " + Date.now(); }
function draw(){
  document.getElementById("cur").textContent = cur();
  var r = document.getElementById("recent"); r.innerHTML = "";
  var names = ["WbA", "AlphaApp", "BetaTool"].filter(function(n){ return n !== cur(); }); names.unshift(cur());
  names.forEach(function(n){ var b = document.createElement("button"); b.setAttribute("role","menuitem"); b.textContent = n;
    b.onclick = function(e){ e.stopPropagation(); localStorage.setItem("p", n); fetch("/open?p=" + n); shut(); draw(); document.querySelector("[data-testid=title]").textContent = n + " workbench"; };
    r.appendChild(b); });
  var l = document.createElement("button"); l.setAttribute("role","menuitem"); l.textContent = "Project list";
  l.onclick = function(){ location.href = "/start/"; }; r.appendChild(l);
}
document.addEventListener("click", shut);
document.addEventListener("keydown", function(e){ if (e.key === "Escape") shut(); });
draw();
</script>'
page main "$app" > "$d/site/main/index.html"
page start '' > "$d/site/start/index.html"
cat > "$d/server.py" <<'PY'
import http.server, os, sys, urllib.parse
ROOT = sys.argv[2]
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=os.path.join(ROOT, "site"), **k)
    def log_message(self, *a): pass
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/open":
            with open(os.path.join(ROOT, "opens.log"), "a") as f:
                f.write(urllib.parse.parse_qs(u.query).get("p", [""])[0] + "\n")
            self.send_response(204); self.end_headers(); return
        super().do_GET()
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY

#!/usr/bin/env bash
# Chatur TF-022 fixture: a menu bar whose File menu holds a submenu row, "Recent projects ▸", built as
# TrBlazeUI's MenubarSub draws it (role="menuitem", aria-haspopup="menu", aria-expanded false → true on a
# click, a second role="menu" beside it). A click opens the submenu and changes nothing else on the page.
# Its children: "Alpha" opens a project (the page text changes) and "Beta" does nothing, which must still
# be reported. "New" in the File menu changes the page. Writes $1/docs/mockups and $1/site.
d="$1"; mkdir -p "$d/docs/mockups" "$d/site/main"
css='<style>body{margin:0;font:14px/20px system-ui} .bar{display:flex;gap:8px;padding:4px;border-bottom:1px solid #ccc} .menu{position:relative} .drop,.sub{display:none;position:absolute;background:#fff;border:1px solid #ccc;min-width:200px;flex-direction:column;z-index:5} .drop{top:28px;left:0} .sub{top:0;left:200px} .menu.open>.drop{display:flex} .row{position:relative} .row.open>.sub{display:flex} .drop button,.sub button{text-align:left;padding:4px 8px} main{padding:16px}</style>'
js='<script>
function shut(){document.querySelectorAll(".open").forEach(x=>x.classList.remove("open"));document.querySelectorAll("[aria-expanded]").forEach(x=>x.setAttribute("aria-expanded","false"));}
function menu(b,e){e.stopPropagation();var m=b.parentElement;var o=m.classList.contains("open");shut();if(!o)m.classList.add("open");}
function sub(b,e){e.stopPropagation();var r=b.parentElement;r.classList.add("open");b.setAttribute("aria-expanded","true");}
function say(t){shut();document.querySelector("[data-testid=body-text]").textContent=t;}
document.addEventListener("click",shut);document.addEventListener("keydown",e=>{if(e.key==="Escape")shut();});
</script>'
page() { printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title>%s%s</head><body>%s<main><h1 data-testid="title">%s</h1><p data-testid="body-text">The %s screen with its real content.</p></main></body></html>\n' "$1" "$css" "$js" "$2" "$1" "$1"; }
page main '<div class="bar" data-testid="menubar">
 <div class="menu" data-testid="file-menu"><button onclick="menu(this,event)">File</button>
  <div class="drop" data-testid="file-pop" data-tf-state="popup-open"><button>New</button><button>Recent projects ▸</button></div></div>
</div>' > "$d/docs/mockups/main.html"
page main '<div class="bar" data-testid="menubar" role="menubar">
 <div class="menu" data-testid="file-menu"><button onclick="menu(this,event)" aria-haspopup="menu">File</button>
  <div class="drop" data-testid="file-pop" role="menu">
   <button role="menuitem" onclick="say(&quot;A new project.&quot;)">New</button>
   <div class="row"><button role="menuitem" aria-haspopup="menu" aria-expanded="false" aria-controls="recent-sub" onclick="sub(this,event)">Recent projects ▸</button>
    <div class="sub" id="recent-sub" role="menu"><button role="menuitem" onclick="say(&quot;Project Alpha is open.&quot;)">Alpha</button><button role="menuitem" onclick="event.stopPropagation()">Beta</button></div></div>
  </div></div>
</div>' > "$d/site/main/index.html"

#!/usr/bin/env bash
# Chatur TF-020 fixture: a branch menu drawn open in the mockup, and an app whose menu holds the branch
# checked out ("main", ticked by an icon that carries no name: TrBlazeUI's <svg class="lucide-icon"> with
# the check path alone) and "Open the repository…". Picking main again has nothing to do. A second menu
# holds an unticked item that does nothing, which must still be reported. Writes $1/docs/mockups and $1/site.
d="$1"; mkdir -p "$d/docs/mockups" "$d/site/main" "$d/site/repository"
css='<style>body{margin:0;font:14px/20px system-ui} .bar{display:flex;gap:8px;padding:4px;border-bottom:1px solid #ccc} .menu{position:relative} .drop{display:none;position:absolute;top:28px;left:0;background:#fff;border:1px solid #ccc;min-width:200px;flex-direction:column;z-index:5} .menu.open .drop{display:flex} .drop>*{text-align:left;padding:4px 8px} main{padding:16px}</style>'
js='<script>function menu(b,e){e.stopPropagation();var m=b.parentElement;var o=m.classList.contains("open");document.querySelectorAll(".menu.open").forEach(x=>x.classList.remove("open"));if(!o)m.classList.add("open");}document.addEventListener("click",()=>document.querySelectorAll(".menu.open").forEach(x=>x.classList.remove("open")));document.addEventListener("keydown",e=>{if(e.key==="Escape")document.querySelectorAll(".menu.open").forEach(x=>x.classList.remove("open"));});</script>'
page() { printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title>%s%s</head><body>%s<main><h1 data-testid="title">%s</h1><p data-testid="body-text">The %s screen with its real content.</p></main></body></html>\n' "$1" "$css" "$js" "$2" "$1" "$1"; }
tick='<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="lucide-icon" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 6L9 17l-5-5"/></svg>'
page main '<div class="bar" data-testid="toolbar">
 <div class="menu" data-testid="branch-pick"><button onclick="menu(this,event)">main</button>
  <div class="drop" data-testid="branch-pop" data-tf-state="popup-open"><button>main</button><a href="repository.html">Open the repository…</a></div></div>
 <div class="menu" data-testid="view-pick"><button onclick="menu(this,event)">View</button>
  <div class="drop" data-testid="view-pop" data-tf-state="popup-open"><button>Refresh</button></div></div>
</div>' > "$d/docs/mockups/main.html"
page repository '' > "$d/docs/mockups/repository.html"
page main "<div class=\"bar\" data-testid=\"toolbar\">
 <div class=\"menu\" data-testid=\"branch-pick\"><button onclick=\"menu(this,event)\">main <span>2 to push</span></button>
  <div class=\"drop\" data-testid=\"branch-pop\" role=\"menu\"><button role=\"menuitem\" data-testid=\"toolbar-branch-main\">$tick<span>main</span></button><button role=\"menuitem\" onclick=\"location.href='/repository/'\">Open the repository…</button></div></div>
 <div class=\"menu\" data-testid=\"view-pick\"><button onclick=\"menu(this,event)\">View</button>
  <div class=\"drop\" data-testid=\"view-pop\" role=\"menu\"><button role=\"menuitem\">Refresh</button></div></div>
</div>" > "$d/site/main/index.html"
page repository '' > "$d/site/repository/index.html"

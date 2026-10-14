#!/usr/bin/env bash
# Chatur TF-011 fixture: mockups drawing File, View and Tools open (data-tf-state="popup-open"), and two
# builds of one app. bad: File holds only a disabled "Nothing to do yet", View › Prerequisites does
# nothing, Prerequisites says "Coming soon". good: every item works. Writes $1/docs/mockups and $1/site.
d="$1"; mkdir -p "$d/docs/mockups"
css='<style>body{margin:0;font:14px/20px system-ui} .bar{display:flex;gap:8px;padding:4px;border-bottom:1px solid #ccc} .menu{position:relative} .drop{display:none;position:absolute;top:28px;left:0;background:#fff;border:1px solid #ccc;min-width:160px;flex-direction:column;z-index:5} .menu.open .drop{display:flex} .drop>*{text-align:left;padding:4px 8px} main{padding:16px}</style>'
js='<script>function menu(b,e){e.stopPropagation();var m=b.parentElement;var o=m.classList.contains("open");document.querySelectorAll(".menu.open").forEach(x=>x.classList.remove("open"));if(!o)m.classList.add("open");}document.addEventListener("click",()=>document.querySelectorAll(".menu.open").forEach(x=>x.classList.remove("open")));document.addEventListener("keydown",e=>{if(e.key==="Escape"){document.querySelectorAll(".menu.open").forEach(x=>x.classList.remove("open"));var d=document.querySelector("dialog[open]");if(d)d.close();}});</script>'
mockbar='<div class="bar" data-testid="menubar">
 <div class="menu" data-testid="menu-file"><button onclick="menu(this,event)">File</button>
  <div class="drop" data-testid="menu-file-items" data-tf-state="popup-open"><button>New project…<span class="sub">⌘N</span></button><button>Exit<span class="sub">⌘Q</span></button></div></div>
 <div class="menu" data-testid="menu-view"><button onclick="menu(this,event)">View</button>
  <div class="drop" data-testid="menu-view-items" data-tf-state="popup-open"><a href="prerequisites.html">Prerequisites</a></div></div>
 <div class="menu" data-testid="menu-tools"><button onclick="menu(this,event)">Tools</button>
  <div class="drop" data-testid="menu-tools-items" data-tf-state="popup-open"><a href="settings.html">Settings…<span class="sub">⌘,</span></a></div></div>
</div>'
page() { printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title>%s%s</head><body>%s<main><h1 data-testid="title">%s</h1><p data-testid="body-text">%s</p></main><dialog data-testid="new-dialog"><p>Name the project</p></dialog></body></html>\n' "$1" "$css" "$js" "$2" "$1" "$3"; }
for s in main prerequisites settings; do page "$s" "$mockbar" "The $s screen with its real content." > "$d/docs/mockups/$s.html"; done
badbar='<div class="bar" data-testid="menubar">
 <div class="menu" data-testid="menu-file"><button onclick="menu(this,event)">File</button>
  <div class="drop" data-testid="menu-file-items" role="menu"><button role="menuitem" disabled>Nothing to do yet</button></div></div>
 <div class="menu" data-testid="menu-view"><button onclick="menu(this,event)">View</button>
  <div class="drop" data-testid="menu-view-items" role="menu"><button role="menuitem">Prerequisites</button></div></div>
 <div class="menu" data-testid="menu-tools"><button onclick="menu(this,event)">Tools</button>
  <div class="drop" data-testid="menu-tools-items" role="menu"><button role="menuitem" onclick="location.href=\x27/bad/settings/\x27">Settings…</button></div></div>
</div>'
goodbar='<div class="bar" data-testid="menubar">
 <div class="menu" data-testid="menu-file"><button onclick="menu(this,event)">File</button>
  <div class="drop" data-testid="menu-file-items" role="menu"><button role="menuitem" onclick="document.querySelector(\x27dialog\x27).showModal()">New project… <kbd>Ctrl+N</kbd></button><button role="menuitem" onclick="document.body.innerHTML=\x27bye\x27">Exit</button></div></div>
 <div class="menu" data-testid="menu-view"><button onclick="menu(this,event)">View</button>
  <div class="drop" data-testid="menu-view-items" role="menu"><button role="menuitem" onclick="window.open(\x27/good/prerequisites/\x27)">Prerequisites</button></div></div>
 <div class="menu" data-testid="menu-tools"><button onclick="menu(this,event)">Tools</button>
  <div class="drop" data-testid="menu-tools-items" role="menu"><button role="menuitem" onclick="location.href=\x27/good/settings/\x27">Settings… <kbd>Ctrl+,</kbd></button></div></div>
</div>'
for v in bad good; do for s in main prerequisites settings; do mkdir -p "$d/site/$v/$s"; bar="$badbar"; [[ $v == good ]] && bar="$goodbar"
  txt="The $s screen with its real content."; [[ $v == bad && $s == prerequisites ]] && txt="Coming soon"
  page "$s" "$(printf "$bar")" "$txt" > "$d/site/$v/$s/index.html"; done; done
# a mockup that marks no menu, and an app whose own menu (aria-haspopup) holds only "Coming soon"
mkdir -p "$d/docs/mockups-plain" "$d/site/plain"
page "plain" "" "The plain screen with its real content." > "$d/docs/mockups-plain/plain.html"
page "plain" '<div class="bar"><div class="menu"><button aria-haspopup="menu" onclick="menu(this,event)">Reports</button><div class="drop" role="menu"><button role="menuitem">Coming soon</button></div></div></div>' "The plain screen with its real content." > "$d/site/plain/index.html"

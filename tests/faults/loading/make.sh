#!/usr/bin/env bash
# Chatur TF-035 and Lekhak TF-045 fixture: four tab screens inside one window frame. The frame's three
# controls are drawn at once, as a desktop-style window draws its menu bar. The tab's five controls come
# later: after 3.2 s on `board` (fetched by a timer, as a live connection brings data, so the network is
# idle in between), never on `never`, which shows "Loading board…" for good, and never on `broken`, which
# shows no loading sign at all. `plain` draws its tab at once, without the two icons its mockup carries.
# Writes $1/docs/mockups and $1/site (served as it is).
d="$1"; mkdir -p "$d/docs/mockups"
ic='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"></rect></svg>'
frame='<div data-testid="menubar">File Edit View</div><div data-testid="toolbar"><button>Run</button></div><div data-testid="files-panel">Files</div>'
tab="<div data-testid=\"board-filters\"><button data-testid=\"board-add\">$ic Add</button></div><h2 data-testid=\"board-title\">Requirements board</h2><ul data-testid=\"board-list\"><li data-testid=\"board-row\">$ic REQ-FN-001 first row</li></ul>"
head='<!doctype html><html><head><meta charset="utf-8"><style>body{font:14px/20px system-ui;margin:0;padding:16px;background:#fff;color:#111} button{height:32px}</style></head><body>'
app() { printf '%s%s<main id="tab">%s</main><script>%s</script></body></html>\n' "$head" "$frame" "$1" "$2"; }
for s in board never broken plain; do
  mkdir -p "$d/site/$s"
  printf '%s%s<main id="tab">%s</main></body></html>\n' "$head" "$frame" "$tab" > "$d/docs/mockups/$s.html"
done
printf '%s' "$tab" > "$d/site/tab.html"
app '' 'setTimeout(function(){fetch("/tab.html").then(function(r){return r.text()}).then(function(t){document.getElementById("tab").innerHTML=t})},3200)' > "$d/site/board/index.html"
app '<p>Loading board…</p>' '' > "$d/site/never/index.html"
app '' '' > "$d/site/broken/index.html"
app "${tab//$ic/}" '' > "$d/site/plain/index.html"

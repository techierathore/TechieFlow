# tests/faults/n16-cases.sh — sourced by tests/faults/run.sh; the cases of 16 Nov 2026 (Chatur TF-037, Sevak TF-040
# to TF-044). Each case fails on the scripts of 4659972 and passes now; each has a control half that a real finding
# still shows. run.sh is near the test-file size cap, so these live here.

# git runs here only in the case's own scratch repositories: the ceiling stops any git from climbing out of the
# scratch folder into this repository, and the config is nobody's.
_g() { GIT_CEILING_DIRECTORIES="$SCRATCH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
       GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com "$@"; }
_top() { _g git -C "$1" rev-parse --show-toplevel 2>/dev/null; }
_free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }

# --- Chatur TF-037: a half-swept test repository let a seed write to the project's own repository -----------------
# The sweep deleted old files one by one, so a fixture's .git lost objects, refs and config and kept its newer HEAD
# and index. git no longer saw a repository there and walked up to Chatur's own; repository.sh, which checked only
# that the folder exists, wrote four check-ins onto Chatur's main and made three branches. Now (a) the sweep takes
# a folder holding .git whole or leaves it whole, and (b) a seed runs under tf-test-guard.sh: even with its fixture
# half deleted by any other means, it cannot write to the project's repository. Controls: an old plain file and a
# fixture that is old throughout still go; a seed writing to a whole fixture repository of its own still writes.
ch_037() {
  local d="$SCRATCH/ch037" p f f2 g out own0 own1 br0 br1
  p="$d/proj"; f="$p/tests/.artifacts/verify/fixtures/repo"; f2="$p/tests/.artifacts/verify/fixtures/stale"; g="$p/tests/.artifacts/verify/fixtures/good"
  mkdir -p "$p/.tfcore" "$f" "$f2" "$p/tests/verify/seed"
  printf 'tests/.artifacts/\n' > "$p/.gitignore"
  _g git -C "$p" init -q -b main && _g git -C "$p" add .gitignore && _g git -C "$p" commit -q -m own
  for r in "$f" "$f2"; do echo x > "$r/a.txt"; _g git -C "$r" init -q -b main && _g git -C "$r" add -A && _g git -C "$r" commit -q -m fx; done
  [[ "$(_top "$f")" == "$f" && "$(_top "$p")" == "$p" ]] || { bad ch_037a "the scratch repositories could not be made"; return; }
  find "$p/tests/.artifacts" -exec touch -t "$(tf_date_from '-10 days' +%Y%m%d%H%M.%S)" {} +
  touch "$f/.git/HEAD" "$f/.git/index"                     # Chatur's state: HEAD and index newer than the rest
  echo old > "$p/tests/.artifacts/old.log"; aged "$p/tests/.artifacts/old.log" '-10 days'
  CLAUDE_PROJECT_DIR="$p" TF_SWEEP_FORCE=1 bash "$HOOKS/sweep-artifacts.sh" </dev/null >/dev/null 2>&1
  [[ "$(_top "$f")" == "$f" && -d "$f/.git/objects" ]] \
    && ok ch_037a "the sweep leaves a test repository whose .git has newer files whole: git still finds the fixture, not the project" \
    || bad ch_037a "the sweep half-deleted the fixture's .git; git from the fixture now finds: $(_top "$f")"
  [[ ! -e "$f2" && ! -e "$p/tests/.artifacts/old.log" ]] \
    && ok ch_037b "a test repository old throughout is removed whole, and an old plain file still goes" \
    || bad ch_037b "the stale fixture or the old file was kept: $(ls -A "$f2" 2>/dev/null | tr '\n' ' ') $(ls "$p/tests/.artifacts/old.log" 2>/dev/null)"
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_037c — needs playwright\n'; return; }
  # (b) the fixture half-deleted by hand, whatever did it; a seed shaped like Chatur's repository.sh of 15 Nov
  rm -rf "$f/.git/objects" "$f/.git/refs" "$f/.git/config"
  cat > "$p/tests/verify/seed/repo.sh" <<EOF
cd "$f" && [ -d .git ] || exit 1
git commit -q --allow-empty -m "[verify-seed] h1"; git branch run/BRD-96-101; git update-ref refs/heads/run/BRD-88-95 HEAD; exit 0
EOF
  cat > "$p/tests/verify/seed/good.sh" <<EOF
mkdir -p "$g" && cd "$g" && git init -q -b main . && git commit -q --allow-empty -m "[verify-seed] h1" && git branch run/BRD-1
EOF
  mkdir -p "$p/site/repo" "$p/site/good"; for s in repo good; do printf '<!doctype html><h1>%s</h1><button>Go</button>\n' "$s" > "$p/site/$s/index.html"; done
  printf '{"screens":[{"name":"repo","route":"/repo/","seed":"tests/verify/seed/repo.sh"},{"name":"good","route":"/good/","seed":"tests/verify/seed/good.sh"}]}' > "$p/list.json"
  ln -sfn "$(_pw_dir)/node_modules" "$p/node_modules"; cp "$UTILS"/tf-*.mjs "$p/"; cp "$UTILS/tf-test-guard.sh" "$p/" 2>/dev/null
  own0="$(_g git -C "$p" rev-list --all --count)"; br0="$(_g git -C "$p" for-each-ref refs/heads | wc -l | tr -d ' ')"
  local port srv; port="$(_free_port)"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$p/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$p" && _g tf_timeout 200 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --list list.json --widths 1280 --themes light --no-menus --json-out "$p/s.json" --shots-dir "$p/shots" > "$p/s.log" 2>&1 )
  kill "$srv" 2>/dev/null
  own1="$(_g git -C "$p" rev-list --all --count)"; br1="$(_g git -C "$p" for-each-ref refs/heads | wc -l | tr -d ' ')"
  out="$(python3 -c "
import json
for s in json.load(open('$p/s.json'))['screens']: print(s['name'], (s.get('seed') or {}).get('ok'), (s.get('seed') or {}).get('output','')[:160])" 2>&1)"
  [[ "$own1" == "$own0" && "$br1" == "$br0" ]] && grep -qE '^repo .*(not a git repository|tf-test-guard: refused)' <<<"$out" \
    && ok ch_037c "a seed run on a half-deleted fixture writes nothing to the project's repository ($own0 check-in(s), $br0 branch(es) before and after): git finds no repository there" \
    || bad ch_037c "the project's repository changed (check-ins $own0 → $own1, branches $br0 → $br1) or git still found one: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  # the browser and unit-test runs carry no ceiling (a build reads git there): the guard's own git refuses the writes
  ( cd "$p" && _g bash "$UTILS/tf-test-guard.sh" "$p" -- bash "$p/tests/verify/seed/repo.sh" ) > "$p/e.log" 2>&1
  own1="$(_g git -C "$p" rev-list --all --count)"; br1="$(_g git -C "$p" for-each-ref refs/heads | wc -l | tr -d ' ')"
  [[ "$own1" == "$own0" && "$br1" == "$br0" ]] && [[ "$(grep -c 'tf-test-guard: refused' "$p/e.log")" == 3 ]] \
    && ok ch_037e "a spec or unit test run from the project root, the fixture half deleted: the commit, the branch and the ref are each refused, and the project's repository is unchanged" \
    || bad ch_037e "the project's repository changed (check-ins $own0 → $own1, branches $br0 → $br1): $(tr '\n' '|' < "$p/e.log" | cut -c1-300)"
  # an app the verify boots runs `git` by name under the same guard (Chatur's app does: ProcessStartInfo("git"))
  mkdir -p "$p/.tfcore/utils" "$p/static"; cp "$UTILS"/tf-*.sh "$UTILS"/tf-*.py "$p/.tfcore/utils/" 2>/dev/null; echo '<p>x</p>' > "$p/static/index.html"
  ( cd "$p" && bash .tfcore/utils/tf-verify-boot.sh start --head static --static static --port "$(_free_port)" ) > "$p/boot.log" 2>&1
  local bp; bp="$(python3 -c "import json;print((json.load(open('$p/tests/.artifacts/verify/boot.json')).get('pids') or [''])[0])" 2>/dev/null)"
  if [[ -r "/proc/$bp/environ" ]]; then
    tr '\0' '\n' < "/proc/$bp/environ" | grep -q '^PATH=[^:]*git-guard' \
      && ok ch_037f "an app booted for a verify runs with the guard's git first on its PATH" \
      || bad ch_037f "the booted app has no guard on its PATH: $(tr '\0' '\n' < "/proc/$bp/environ" | grep '^PATH=' | cut -c1-120)"
  else printf 'skipped: ch_037f — needs /proc (Linux)\n'; fi
  ( cd "$p" && bash .tfcore/utils/tf-verify-boot.sh stop ) >/dev/null 2>&1
  [[ "$(_g git -C "$g" rev-list --all --count 2>/dev/null)" == 1&& "$(_g git -C "$g" for-each-ref refs/heads | wc -l | tr -d ' ')" == 2 ]] && grep -q '^good True' <<<"$out" \
    && ok ch_037d "a seed writing to a whole test repository of its own still writes its check-in and branch" \
    || bad ch_037d "the guard stopped a seed writing to its own fixture: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- Sevak's mockup-check cases: each page is the entry's own smallest page (Sevak tests/.artifacts/verify/ui16/fx) --
# _fx <dir> <screen> <mockup page> <app page>: whole pages, as Sevak filed them
_fx() { mkdir -p "$1/docs/mockups" "$1/site/$2"; printf '%s\n' "$3" > "$1/docs/mockups/$2.html"; printf '%s\n' "$4" > "$1/site/$2/index.html"; rm -f "$1/parity.json"; }
_doc() { printf '<!doctype html><html><head><meta charset="utf-8"><title>%s</title></head>\n<body style="%s">%s</body></html>' "$1" "$2" "$3"; }

# --- Sevak TF-040: a gradient with a see-through stop read as a strong colour --------------------------------------
# fillOf took the mean of the stops' red, green and blue, then blended only the mean opacity over the background: a
# stop at 5% counted as a full third of the colour, and the near-white wizard page box read "accent". Each stop is
# now seen over what is behind it first. Control: an app box painted with an opaque accent gradient is still accent.
sv_040() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_040 — needs playwright\n'; return; }
  local d="$SCRATCH/sv040" out b='margin:0;background:#f6f7f9;font-family:sans-serif'
  local in='<h1 data-testid="title">Set up</h1><button data-testid="go">Continue</button>'
  local m; m="$(_doc mockup "$b" "<div data-testid=\"page-box\" style=\"min-height:300px;padding:24px;background:linear-gradient(160deg,#eef2ff 0%,#f6f7f9 45%,#f6f7f9 100%)\">$in</div>")"
  _fx "$d" gradbox "$m" "$(_doc app "$b" "<div data-testid=\"page-box\" style=\"min-height:300px;padding:24px;background-image:linear-gradient(to bottom,rgba(79,70,229,.05),#f6f7f9,#f6f7f9)\">$in</div>")"
  out="$(_parity "$d" gradbox /gradbox/)"
  [[ "$out" != NO-RESULT ]] && ! grep -qE '^[0-9]+ page-box color' <<<"$out" \
    && ok sv_040a "a page box painted with the accent at 5% over the background reads neutral, as the mockup's near-white gradient does" \
    || bad sv_040a "the see-through gradient still reads as a colour: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  _fx "$d" gradbox "$m" "$(_doc app "$b" "<div data-testid=\"page-box\" style=\"min-height:300px;padding:24px;background-image:linear-gradient(to bottom,#6366f1,#4f46e5)\">$in</div>")"
  out="$(_parity "$d" gradbox /gradbox/)"
  grep -qE '^1280 page-box color .*mockup neutral, app accent' <<<"$out" \
    && ok sv_040b "a page box painted with an opaque accent gradient is still reported as accent where the mockup is neutral" \
    || bad sv_040b "the opaque gradient lost its colour finding: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- Sevak TF-041: a progress bar's fill reported as a missing badge ---------------------------------------------
# The mockup's fill (an <i>, 8 px, fully rounded, a gradient) was "small, filled, rounded", so a badge; the app's
# fill (TrBlazeUI's Progress: an unrounded div moved by a transform) sits under another key, and the missing clause
# said a badge was gone. A textless box in a progress bar, or as tall as a track that clips it, is a fill. Control:
# a real badge the mockup draws beside the bar and the app leaves out is still reported missing.
sv_041() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_041 — needs playwright\n'; return; }
  local d="$SCRATCH/sv041" out b='margin:0;padding:24px;background:#fff;font-family:sans-serif'
  local mb='<div data-testid="bar" style="height:8px;border-radius:999px;background:#eef0f4;overflow:hidden"><i style="display:block;width:33%;height:100%;background:linear-gradient(90deg,#6366f1,#4f46e5);border-radius:999px"></i></div>'
  local ab='<div data-testid="bar" role="progressbar" aria-valuenow="33" aria-valuemin="0" aria-valuemax="100" style="position:relative;height:8px;border-radius:999px;background:#eef0f4;overflow:hidden"><div style="height:100%;width:100%;background:#4f46e5;transform:translateX(-67%)"></div></div>'
  local pill='<span style="display:inline-block;padding:2px 8px;border-radius:999px;font-size:12px;background:#dbeafe;color:#1e40af">Draft</span>'
  _fx "$d" bar "$(_doc mockup "$b" "<div data-testid=\"card\"><h1 data-testid=\"title\">Step 1 of 3</h1>$mb<button data-testid=\"go\">Continue</button></div>")" \
               "$(_doc app "$b" "<div data-testid=\"card\"><h1 data-testid=\"title\">Step 1 of 3</h1>$ab<button data-testid=\"go\">Continue</button></div>")"
  out="$(_parity "$d" bar /bar/)"
  [[ "$out" != NO-RESULT ]] && ! grep -qE ' bar( > i\[0\])? (missing|badge)' <<<"$out" \
    && ok sv_041a "a progress bar drawn as a rounded <i> in the mockup and as a library's clipped fill in the app: no missing badge" \
    || bad sv_041a "the bar's fill is still read as a badge: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  _fx "$d" bar "$(_doc mockup "$b" "<div data-testid=\"card\"><h1 data-testid=\"title\">Step 1 of 3</h1>$mb<p>$pill</p><button data-testid=\"go\">Continue</button></div>")" \
               "$(_doc app "$b" "<div data-testid=\"card\"><h1 data-testid=\"title\">Step 1 of 3</h1>$ab<p>Saved</p><button data-testid=\"go\">Continue</button></div>")"
  out="$(_parity "$d" bar /bar/)"
  grep -qE '^1280 card > p\[0\] > span\[0\] missing' <<<"$out" && ! grep -qE ' bar > i\[0\] ' <<<"$out" \
    && ok sv_041b "a status badge the mockup draws beside the bar and the app leaves out is still reported missing; the fill is not" \
    || bad sv_041b "the real missing badge was lost, or the fill came back: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- Sevak TF-042: a tab a badge on one side only, drawn as a div in the mockup and a button in the app ------------
# chromeOn asked a control for a full radius before it was a pill, and any other element for 6 px: the mockup's
# <div class="tab active"> (7 px on 27 px) was a pill, TrBlazeUI's <button role="tab"> (7.5 px on 28 px) was not.
# When either side is a control (or role="tab") both are judged by the control's rule. Control: an app tab drawn
# fully rounded where the mockup's is a 7 px box is still reported.
sv_042() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_042 — needs playwright\n'; return; }
  local d="$SCRATCH/sv042" out b='margin:0;padding:24px;background:#f6f7f9;font-family:sans-serif' r
  local m; m="$(_doc mockup "$b" '<div data-testid="card"><h1 data-testid="title">Settings</h1>
<div data-testid="tabs" style="display:flex;gap:2px;background:#eef0f4;border-radius:9px;padding:3px;width:max-content">
<div data-testid="tab-general" style="padding:6px 16px;border-radius:7px;font-size:13px;font-weight:600;background:#fff;cursor:pointer">General</div>
<div data-testid="tab-other" style="padding:6px 16px;border-radius:7px;font-size:13px;cursor:pointer">Other</div></div>
<button data-testid="go">Save</button></div>')"
  _app() { _doc app "$b" "<div data-testid=\"card\"><h1 data-testid=\"title\">Settings</h1>
<div data-testid=\"tabs\" role=\"tablist\" style=\"display:inline-flex;height:40px;align-items:center;background:#eef0f4;border-radius:9px;padding:4px;box-sizing:border-box\">
<button role=\"tab\" aria-selected=\"true\" data-testid=\"tab-general\" style=\"padding:6px 12px;border:0;border-radius:$1;font-size:14px;font-weight:500;background:#fff;cursor:pointer\">General</button>
<button role=\"tab\" aria-selected=\"false\" data-testid=\"tab-other\" style=\"padding:6px 12px;border:0;border-radius:7.5px;font-size:14px;background:transparent;cursor:pointer\">Other</button></div>
<button data-testid=\"go\">Save</button></div>"; }
  _fx "$d" tab "$m" "$(_app 7.5px)"
  out="$(_parity "$d" tab /tab/)"
  [[ "$out" != NO-RESULT ]] && ! grep -qE ' tab-general badge' <<<"$out" \
    && ok sv_042a "a tab drawn as a div with a 7 px corner in the mockup and as a button with 7.5 px in the app: both plain, no badge finding" \
    || bad sv_042a "the tab is still a badge on one side only: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  _fx "$d" tab "$m" "$(_app 999px)"
  out="$(_parity "$d" tab /tab/)"
  grep -qE '^1280 tab-general badge mockup renders this as a plain element, app renders' <<<"$out" \
    && ok sv_042b "an app tab drawn fully rounded where the mockup's is a 7 px box is still reported as a pill on one side" \
    || bad sv_042b "the real shape difference was lost: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}
# the other way round (Inbox's Choose a file): the mockup draws a <button> (7 px on 32 px), the app a <span> drawn as a
# button inside the drop zone (8 px), as Sevak's Inbox.razor does
sv_042c() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_042c — needs playwright\n'; return; }
  local d="$SCRATCH/sv042c" out b='margin:0;padding:24px;background:#f6f7f9;font-family:sans-serif'
  _fx "$d" inbox "$(_doc mockup "$b" '<div data-testid="inbox-file" style="display:flex;flex-direction:column;align-items:center;gap:8px;padding:16px;border:1px dashed #ccc"><div><b>Drop a file here</b></div><button data-testid="inbox-choose-file" style="height:32px;padding:0 12px;border:1px solid #d0d4dc;border-radius:7px;background:#fff;font-weight:600">Choose a file</button></div>')" \
                 "$(_doc app "$b" '<div data-testid="inbox-file" style="padding:16px;border:1px dashed #ccc"><div style="display:flex;flex-direction:column;align-items:center;gap:8px"><b>Drop a file here</b><span data-testid="inbox-choose-file" style="display:inline-flex;align-items:center;border:1px solid #d0d4dc;border-radius:8px;padding:.28rem .7rem;font-size:12.5px;font-weight:600;background:#fff">Choose a file</span></div></div>')"
  out="$(_parity "$d" inbox /inbox/)"
  [[ "$out" != NO-RESULT ]] && ! grep -qE ' inbox-choose-file badge' <<<"$out" \
    && ok sv_042c "the other way round: a button in the mockup and a span drawn as one in the app, the same box: no badge finding" \
    || bad sv_042c "the file button is a badge on one side only: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# the shape of Automations, Tasks, Plan and App settings: Sevak anchors a <span> around TrBlazeUI's tab button
# (Automations.razor: <span class="td-tab-anchor" data-testid="auto-tab-schedules"><TabsTrigger …>), so the button
# is one element in; the mockup draws <div class="tab active">. Control: the button drawn fully rounded still shows.
sv_042d() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_042d — needs playwright\n'; return; }
  local d="$SCRATCH/sv042d" out b='margin:0;padding:24px;background:#f6f7f9;font-family:sans-serif' m
  m="$(_doc mockup "$b" '<div data-testid="card"><h1>Automations</h1><div style="display:flex;gap:2px;background:#eef0f4;border-radius:9px;padding:3px;width:max-content"><div class="tab active" data-testid="auto-tab-schedules" style="padding:7px 16px;border-radius:7px;font-size:13px;font-weight:600;background:#fff">Schedules</div><div data-testid="auto-tab-runs" style="padding:7px 16px;border-radius:7px;font-size:13px">Runs</div></div></div>')"
  _app() { _doc app "$b" "<div data-testid=\"card\"><h1>Automations</h1><div role=\"tablist\" style=\"display:inline-flex;height:45px;align-items:center;background:#eef0f4;border-radius:9px;padding:4px;box-sizing:border-box\"><span class=\"td-tab-anchor\" data-testid=\"auto-tab-schedules\"><button role=\"tab\" aria-selected=\"true\" style=\"height:37px;padding:6px 12px;border:0;border-radius:$1;font-size:14px;background:#fff\">Schedules</button></span><span data-testid=\"auto-tab-runs\"><button role=\"tab\" style=\"height:37px;padding:6px 12px;border:0;border-radius:7.5px;font-size:14px;background:transparent\">Runs</button></span></div></div>"; }
  _fx "$d" automations "$m" "$(_app 7.5px)"
  out="$(_parity "$d" automations /automations/)"
  [[ "$out" != NO-RESULT ]] && ! grep -qE ' auto-tab-schedules badge' <<<"$out" \
    && ok sv_042d "a tab anchored on a span around the library's tab button: judged as a control, no badge finding" \
    || bad sv_042d "the span-anchored tab is still a badge on one side only: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  _fx "$d" automations "$m" "$(_app 999px)"
  out="$(_parity "$d" automations /automations/)"
  grep -qE '^1280 auto-tab-schedules badge mockup renders this as a plain element, app renders' <<<"$out" \
    && ok sv_042e "the same tab button drawn fully rounded is still reported as a pill on one side" \
    || bad sv_042e "the real shape difference was lost: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- Sevak TF-043: the screen check opened a date picker's calendar it could not close ------------------------------
# tf-dropdowns.mjs clicked the From date picker (aria-haspopup="true"); its calendar is no list, so nothing closed it
# (TrBlazeUI's calendar also ignores Escape and its own button, TR-050), and the dark pass measured it under the top
# bar: "topbar overlaps button November … in dark mode". Whatever a click opened is now closed (trigger, Escape, a
# click on an empty spot); one that stays open is named, not opened again, and that width's overlap is not measured.
# Control: a real overlap of two controls on another screen is still reported.
sv_043() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_043 — needs playwright\n'; return; }
  local d="$SCRATCH/sv043" port srv s out
  mkdir -p "$d/docs/mockups"
  local top='<div data-testid="topbar" style="position:fixed;top:0;left:0;right:0;height:56px;background:#fff;border-bottom:1px solid #ddd;display:flex;align-items:center;padding:0 16px;z-index:5"><b>Sevak</b></div>'
  local js='<script>
var t=document.getElementById("from"),c=document.getElementById("cal");
t.addEventListener("click",function(){c.style.display="block";t.setAttribute("aria-expanded","true");});
if(c.dataset.mode==="outside")document.addEventListener("mousedown",function(e){if(!c.contains(e.target)&&e.target!==t){c.style.display="none";t.setAttribute("aria-expanded","false");}});
</script>'
  for s in events stuck; do
    mkdir -p "$d/site/$s"
    printf '<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;font:14px system-ui">%s<main style="padding:72px 16px 16px"><h1 data-testid="title">Event log</h1><button data-testid="from" id="from" aria-haspopup="true" aria-expanded="false">From 1 Nov 2026</button><div id="cal" data-mode="%s" style="display:none;position:fixed;top:40px;left:200px;width:240px;background:#fff;border:1px solid #ccc;padding:4px;z-index:9"><button>November</button> <button>2026</button><div role="grid"><button>1</button><button>2</button></div></div></main>%s</body></html>\n' \
      "$top" "$([[ $s == events ]] && echo outside || echo never)" "$js" > "$d/site/$s/index.html"
    printf '<!doctype html><html><body>%s<main style="padding:72px 16px"><h1 data-testid="title">Event log</h1><button data-testid="from">From</button></main></body></html>\n' "$top" > "$d/docs/mockups/$s.html"
  done
  mkdir -p "$d/site/real"
  printf '<!doctype html><html><body style="margin:0">%s<main style="padding:72px 16px"><h1 data-testid="title">Real</h1><button data-testid="a" style="position:relative;width:120px;height:40px">Save</button><button data-testid="b" style="position:relative;left:-60px;width:120px;height:40px">Cancel</button></main></body></html>\n' "$top" > "$d/site/real/index.html"
  printf '<!doctype html><html><body>%s<main style="padding:72px 16px"><h1 data-testid="title">Real</h1><button data-testid="a">Save</button><button data-testid="b">Cancel</button></main></body></html>\n' "$top" > "$d/docs/mockups/real.html"
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"; cp "$UTILS"/tf-*.mjs "$d/"
  port="$(_free_port)"
  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$d/site" >/dev/null 2>&1 & srv=$!
  sleep 1
  ( cd "$d" && tf_timeout 300 node tf-verify-screens.mjs --base "http://127.0.0.1:$port" --mockups docs/mockups --screen events=/events/ --screen stuck=/stuck/ --screen real=/real/ \
      --widths 1280,390 --themes light,dark --no-menus --json-out "$d/s.json" --shots-dir "$d/shots" > "$d/s.log" 2>&1 )
  kill "$srv" 2>/dev/null
  out="$(python3 -c "
import json
for s in json.load(open('$d/s.json'))['screens']:
    ov = [w.get('width') for w in s['widths'] for f in w.get('findings', []) if f['class'] == 'overlap']
    dd = s.get('dropdowns') or {}
    print(s['name'], 'overlap' if ov else '-', 'unclosed=' + ','.join(dd.get('unclosed') or []) or '-', sum(1 for w in s['widths'] if str(w.get('overlap','')).startswith('not measured')))" 2>&1)"
  grep -q '^events - unclosed= 0$' <<<"$out" \
    && ok sv_043a "a calendar that closes only on a click outside it is closed after it is graded: no overlap with the top bar in the dark pass" \
    || bad sv_043a "the calendar was left open and measured: $(tr '\n' '|' <<<"$out") $(grep -m1 'events' "$d/s.log" | cut -c1-200)"
  grep -qE '^stuck - unclosed=from [1-9]' <<<"$out" && grep -q 'could not close the list of from; not opened again' "$d/s.log" \
    && ok sv_043b "a calendar nothing closes is named as not closed, not opened again, and the overlap check is left out where it is open" \
    || bad sv_043b "the stuck calendar was measured or not named: $(tr '\n' '|' <<<"$out") $(grep -m1 'stuck' "$d/s.log" | cut -c1-200)"
  grep -q '^real overlap' <<<"$out" \
    && ok sv_043c "two controls that really overlap are still reported" \
    || bad sv_043c "the real overlap was lost: $(tr '\n' '|' <<<"$out")"
}

# --- Sevak TF-044: the first-run wizard "not measured" at 390, because every address leads back to it --------------
# openFresh hops away from a screen it is already on and back, so the screen is opened fresh. On a new install every
# route sends the user to /setup: the hop came back to the wizard, its controls never left, none was new, and
# "the app did not move to /setup" at 390. When the hop comes back to the screen by itself, the screen is open: it
# has arrived when half its controls are there. Control: a screen whose controls never appear is still not measured.
sv_044() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: sv_044 — needs playwright\n'; return; }
  local d="$SCRATCH/sv044" port cport exe srv br out
  mkdir -p "$d/docs/mockups" "$d/site"
  printf '<!doctype html><html><body><h1 data-testid="wizard-title">Set up Sevak</h1><input data-testid="wizard-name"><button data-testid="wizard-next">Next</button><div data-tf-phase="1"><input data-testid="wizard-key"><button data-testid="wizard-test">Test</button><button data-testid="wizard-finish">Finish</button></div></body></html>\n' > "$d/docs/mockups/setup-wizard.html"
  printf '<!doctype html><html><body><h1 data-testid="never-title">Never</h1><button data-testid="never-go">Go</button></body></html>\n' > "$d/docs/mockups/never.html"
  cat > "$d/site/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{font:14px system-ui;margin:0;padding:16px}</style></head><body><div id="root"></div><script>
function draw(){ if(location.pathname!=='/setup') history.replaceState(null,'','/setup');
 document.getElementById('root').innerHTML='<h1 data-testid="wizard-title">Set up Sevak</h1><input data-testid="wizard-name"><button data-testid="wizard-next">Next</button><p>Step 1 of 3</p>'; }
addEventListener('popstate',draw); draw();
</script></body></html>
HTML
  printf 'import http.server,sys\nclass H(http.server.SimpleHTTPRequestHandler):\n    def log_message(self,*a): pass\n    def translate_path(self,p): return sys.argv[2]\nhttp.server.ThreadingHTTPServer(("127.0.0.1",int(sys.argv[1])),H).serve_forever()\n' > "$d/serve.py"
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"; cp "$UTILS"/tf-*.mjs "$d/"
  port="$(_free_port)"; cport="$(_free_port)"
  python3 "$d/serve.py" "$port" "$d/site/index.html" >/dev/null 2>&1 & srv=$!
  exe="$(cd "$d" && node -e "import('playwright').then(p=>console.log(p.chromium.executablePath()))" 2>/dev/null)"
  "$exe" --headless=new --no-sandbox --remote-debugging-port="$cport" --user-data-dir="$d/profile" "http://127.0.0.1:$port/" >/dev/null 2>&1 & br=$!
  local i=0; while [[ $i -lt 30 ]] && ! curl -s -m 2 "http://127.0.0.1:$cport/json/version" | grep -q webSocketDebuggerUrl; do sleep 1; i=$((i+1)); done
  sleep 2
  ( cd "$d" && tf_timeout 300 node tf-mockup-parity.mjs --cdp "http://127.0.0.1:$cport" --mockups docs/mockups --screen setup-wizard=/setup --screen never=/never \
      --widths 1280,390 --themes light --render-wait 1500 --no-menus --json-out "$d/p.json" > "$d/p.log" 2>&1 )
  kill "$br" "$srv" 2>/dev/null; wait "$br" 2>/dev/null
  out="$(python3 -c "
import json
for s in json.load(open('$d/p.json'))['screens']:
    print(s['screen'], s.get('verdict'), ' '.join(str(w.get('width')) for w in s.get('widths_detail', s.get('per_width', [])) if 'not measured' in str(w.get('error',''))) or '-', 'NM' if 'did not move to' in json.dumps(s) else 'M')" 2>&1)"
  grep -qE '^setup-wizard (PASS|FAIL) .* M$' <<<"$out" \
    && ok sv_044a "a wizard every address leads back to is compared at 1280 and at 390: never 'not measured'" \
    || bad sv_044a "the wizard was not measured: $(tr '\n' '|' <<<"$out") $(grep -m2 'setup-wizard\|not measured' "$d/p.log" | tr '\n' '|' | cut -c1-240)"
  grep -qE '^never .* NM$' <<<"$out" \
    && ok sv_044b "a screen none of whose controls ever appear is still 'not measured', never compared with the page on view" \
    || bad sv_044b "the screen that never arrived was compared: $(tr '\n' '|' <<<"$out")"
}

# tests/faults/ts-cases.sh — sourced by tests/faults/run.sh; the TrStudio cases of 16 Nov 2026 (TF-003 to TF-007).
# run.sh is near the test-file size cap (tests/mirror/size-check.py), so these live here and run from there.
# Each case fails on the scripts of 572b111 and passes now; each has a control half that a real finding still shows.

# --- TrStudio TF-003: graded at phase 1, a phase 3 box the app already draws shifted every box after it ----------
# markLaterPhase made the mockup's phase 3 box another state, so keyOf stopped counting it; the app's copy was still
# counted, and "Setup link" (bordered) was compared with the app's "Note": "border style differs". A later box the
# app draws is kept on both sides; one the app does not draw is still left out, and a real difference still shows.
ts_003() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ts_003 — needs playwright\n'; return; }
  local d="$SCRATCH/ts003" out bd='style="border-top:1px solid #ccc"'
  local m="<div class=\"bar\" data-testid=\"card\"><div>Title</div><div data-tf-phase=\"3\">Remember me</div><div>Note</div><div $bd>Setup link</div></div><div class=\"bar\" data-testid=\"card-two\"><div>Title</div><div data-tf-phase=\"3\" data-testid=\"remember-me-row\">Remember me</div><div>Note</div><div $bd>Setup link</div></div>"
  _pages "$d" login "$m" "${m//data-tf-phase=\"3\" /}"
  out="$(TF_PARITY_ARGS='--phase 1' _parity "$d" login /login/)"
  [[ "$out" != NO-RESULT ]] && ! grep -qE ' card(-two)?( |$)' <<<"$out" \
    && ok ts_003a "graded at phase 1, a phase 3 box the app already draws (with or without an anchor) is paired on both sides: no finding" \
    || bad ts_003a "the boxes after a drawn later-phase box were paired with their neighbours: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  # the app has not built phase 3 (no Remember me), and draws Setup link with no rule: that is a real finding
  _pages "$d" login "$m" '<div class="bar" data-testid="card"><div>Title</div><div>Note</div><div>Setup link</div></div><div class="bar" data-testid="card-two"><div>Title</div><div>Note</div><div style="border-top:1px solid #ccc">Setup link</div></div>'
  out="$(TF_PARITY_ARGS='--phase 1' _parity "$d" login /login/)"
  grep -qE '^1280 card > div\[2\] stroke .*mockup solid' <<<"$out" && ! grep -qE ' card-two( |$)' <<<"$out" \
    && ok ts_003b "a phase 3 box the app does not draw is still left out, and a missing rule on the box after it is still reported" \
    || bad ts_003b "the not-yet-built case lost its finding or gained one: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- TrStudio TF-005: a fixed-height button was counted as two lines --------------------------------------------
# lineCount divided the box height less padding by the line height; a 32 px button with no vertical padding and a
# 20 px line is "2 rows". Rows are now counted from the text's own line boxes. A label that really wraps still shows.
ts_005() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ts_005 — needs playwright\n'; return; }
  local d="$SCRATCH/ts005" out b='border:1px solid #999;background:#fff;font:14px/20px system-ui;border-radius:6px'
  _pages "$d" registry "<p><button data-testid=\"btn-test-connection\" style=\"$b;padding:4px 10px\">Test connection</button> <button data-testid=\"btn-save-key\" style=\"$b;padding:4px 10px\">Save the key</button></p>" \
    "<p><button data-testid=\"btn-test-connection\" style=\"$b;height:32px;padding:0 12px;white-space:nowrap\">Test connection</button> <button data-testid=\"btn-save-key\" style=\"$b;padding:4px 10px;width:56px\">Save the key</button></p>"
  out="$(_parity "$d" registry /registry/)"
  [[ "$out" != NO-RESULT ]] && ! grep -q ' btn-test-connection wrap ' <<<"$out" \
    && ok ts_005a "a fixed-height button whose label sits on one line is one row: no wrap finding" \
    || bad ts_005a "the fixed-height button was counted as more than one row: $(grep ' btn-test-connection ' <<<"$out" | tr '\n' '|' | cut -c1-240)"
  grep -q '^1280 btn-save-key wrap wraps to [2-9] rows' <<<"$out" && grep -q '^390 btn-save-key wrap ' <<<"$out" \
    && ok ts_005b "a label that really wraps in a narrow button is still a wrap finding, at both widths" \
    || bad ts_005b "a real wrap was lost: $(tr '\n' '|' <<<"$out" | cut -c1-240)"
}

# --- the Mac screen checker's click paths, against tests/faults/fake-mac2.mjs ----------------------------------
_mac2() {   # <dir> [checker args]: model.json and list.json there; prints "name|render|reached or finding" per screen
  local d="$1" pf="$1/port" pid; shift
  rm -f "$pf" "$d/model.json.log"; node "$ROOT/tests/faults/fake-mac2.mjs" "$d/model.json" "$pf" & pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$pf" ]] && break; sleep 0.3; done
  ( cd "$d" && tf_timeout 120 node "$UTILS/tf-verify-native.mjs" --appium "http://127.0.0.1:$(cat "$pf")" --bundle fx --list list.json \
      --json-out s.json --shots-dir shots --render-wait 300 --wait 50 --widths 1280 "$@" > run.log 2>&1 )
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  python3 -c "
import json,sys
for r in json.load(open(sys.argv[1]))['screens']:
    w = r['widths'][0]; print(r['name'] + '|' + r['render'] + '|' + (w.get('reached') or '; '.join(f['detail'] for f in w.get('findings', []))))" "$d/s.json" 2>&1
}
_listfx() {   # <dir> <screen name=route …>: a checklist and UIDesign naming those screens, one UI row each
  local d="$1" i=0 kv; shift; mkdir -p "$d/docs"
  { printf '# Fx — Checklist\n\n| ID | Title | Status | %% | Remarks | Details |\n|---|---|---|---|---|---|\n'
    for kv in "$@"; do i=$((i+1)); printf '| REQ-UI-%03d | %s | Done | 90%% | | |\n' "$i" "${kv%%=*}"; done; printf '\n'
    i=0; for kv in "$@"; do i=$((i+1)); printf -- '- **REQ-UI-%03d** — %s. *Acceptance:* %s shows.\n' "$i" "${kv%%=*}" "${kv%%=*}"; done; } > "$d/docs/Fx-Checklist.md"
  { printf '# Fx — UI Design\n\n'; for kv in "$@"; do printf '### Screen: %s (%s)\n\nA screen.\n\n' "${kv%%=*}" "${kv#*=}"; done; } > "$d/docs/Fx-UIDesign.md"
  printf '<Project Sdk="Microsoft.NET.Sdk.Razor"></Project>\n' > "$d/src/App/App.csproj"
  ( cd "$d" && python3 "$UTILS/tf-verify-list.py" Fx ui --phase 1 --json-out list.json 2>&1 )
}
_navof() { python3 -c "import json,sys; print({s['name']: (s.get('nav_from',''), s.get('nav')) for s in json.load(open(sys.argv[1]))['screens']})" "$1" 2>&1; }

# --- TrStudio TF-004: no click path started from the screen the app opens on ----------------------------------
# navigation() seeded its search only with links in files that are not pages, so Register, reached only by Login's
# own "Create an account", had no path; and the checker took no screen but "/" as the one on view. A page's own
# links now count, and the checker tells which screen is on view by that screen's own links, and plans from it.
ts_004() {
  command -v node >/dev/null 2>&1 || { printf 'skipped: ts_004 — needs node\n'; return; }
  local d="$SCRATCH/ts004" out nav
  mkdir -p "$d/src/App/Pages"
  printf '@page "/login"\n<a href="/register">Create an account</a>\n<a href="/forgot-password">Forgot password</a>\n' > "$d/src/App/Pages/Login.razor"
  printf '@page "/register"\n<div>Already have an account? <a href="/login">Sign in</a></div>\n' > "$d/src/App/Pages/Register.razor"
  printf '@page "/forgot-password"\n<a href="/login">Back to sign in</a>\n' > "$d/src/App/Pages/Forgot.razor"
  printf '@page "/orphan"\n<p>nobody links here</p>\n' > "$d/src/App/Pages/Orphan.razor"
  out="$(_listfx "$d" 'Login=/login' 'Register=/register' 'Forgot password=/forgot-password' 'Orphan=/orphan')"; nav="$(_navof "$d/list.json")"
  grep -q "'Register': ('/login', \['Create an account'\])" <<<"$nav" && grep -q "Register (/register).*reached from /login by clicking 'Create an account'" <<<"$out" \
    && grep -q "'Orphan': ('', None)" <<<"$nav" \
    && ok ts_004a "a screen reached only by the opening screen's own link has that path, from that screen; a screen nothing links to has none" \
    || bad ts_004a "the opening screen's links were not followed: $nav"
  python3 - "$d/model.json" <<'PY'
import json, sys
json.dump({"start": "login", "pages": {
  "login": [{"label": "Forgot password", "to": "forgot-password", "y": 330}, {"label": "Create an account", "to": "register", "y": 360}],
  "register": [{"label": "Sign in", "to": "login", "y": 300}],
  "forgot-password": [{"label": "Back to sign in", "to": "login", "y": 300}], "orphan": []}}, open(sys.argv[1], "w"))
PY
  out="$(_mac2 "$d")"
  grep -q '^Login|OK|already on view' <<<"$out" && grep -q '^Register|OK|clicked "Create an account"$' <<<"$out" \
    && grep -q '^Forgot password|OK|clicked "Sign in" > "Forgot password"$' <<<"$out" \
    && ok ts_004b "on the Mac the opening screen is found on view by its own links, and Register and Forgot password are reached from it by clicks" \
    || bad ts_004b "the click paths did not start from the opening screen: $(tr '\n' '/' <<<"$out" | cut -c1-400)"
  grep -q '^Orphan|UNREACHABLE|no control reaches Orphan' <<<"$out" \
    && ok ts_004c "a screen no link reaches is still UNREACHABLE, never graded on whatever is on view" \
    || bad ts_004c "the screen nothing reaches was not reported: $(grep '^Orphan' <<<"$out")"
}

# --- TrStudio TF-006: a menu built in code, and screens behind "Switch to Management" -----------------------------
# tf-verify-list.py read only href/Href in .razor files, so a sidebar built from C# data gave no path; and the checker
# never pressed a surface switch. A call whose first two arguments are a label and a route is a menu link now, and a
# label not on view is looked for again after a "Switch to …" control is pressed.
ts_006() {
  command -v node >/dev/null 2>&1 || { printf 'skipped: ts_006 — needs node\n'; return; }
  local d="$SCRATCH/ts006" out nav
  mkdir -p "$d/src/App/Pages" "$d/src/App/Navigation"
  for r in avatar avatar/characters gallery admin/setup/hardware admin/policy compare; do printf '@page "/%s"\n<p>%s</p>\n' "$r" "$r" > "$d/src/App/Pages/$(tr '/' '_' <<<"$r").razor"; done
  printf '@page "/avatar"\n<a href="@vExportUrl">Export WAV</a>\n' > "$d/src/App/Pages/avatar.razor"   # a computed route names no screen
  cat > "$d/src/App/Navigation/NavSets.cs" <<'CS'
public static class NavSets {
  static object Creator() => new List<AppNavItem> { new("Avatar Studio", "/avatar", "user"), new("Characters", "/avatar/characters", "users"), new("Gallery", "/gallery", "grid") };
  static object Management() => new List<AppNavItem> { new("Hardware & Setup", "/admin/setup/hardware", "cpu", new[] { "/admin/setup" }) };
  public const string Compare = "/api/v1/compare";
  static object Api() => Map("Compare", "/api/v1/compare");
}
CS
  out="$(_listfx "$d" 'Character library=/avatar/characters' 'Hardware and setup=/admin/setup/hardware' 'Gallery=/gallery' 'Content policy=/admin/policy' 'Comparison=/compare')"; nav="$(_navof "$d/list.json")"
  grep -q "'Character library': ('', \['Characters'\])" <<<"$nav" && grep -q "'Hardware and setup': ('', \['Hardware & Setup'\])" <<<"$nav" \
    && grep -q "'Comparison': ('', None)" <<<"$nav" \
    && ok ts_006a "a menu built as C# data gives each screen its label to click; an API route, or a link whose route is computed, is no link" \
    || bad ts_006a "the menu built in code was not read: $nav"
  python3 - "$d/model.json" "$d/list.json" <<'PY'
import json, sys
menu = [{"label": "Characters", "to": "avatar/characters", "y": 100, "surface": "creator"}, {"label": "Gallery", "to": "gallery", "y": 130, "surface": "creator"},
        {"label": "Switch to Management", "sw": "management", "y": 160, "surface": "creator"},
        {"label": "Hardware & Setup", "to": "admin/setup/hardware", "y": 100, "surface": "management"},
        {"label": "Switch to Creator studio", "sw": "creator", "y": 160, "surface": "management"}]
json.dump({"start": "avatar", "surface": "creator", "pages": {k: menu for k in ["avatar", "avatar/characters", "gallery", "admin/setup/hardware"]}}, open(sys.argv[1], "w"))
l = json.load(open(sys.argv[2]))
l.setdefault("links", []).append({"from": "", "to": "admin/policy", "label": "Content Policy", "project": ""})   # in no surface the app shows
l["screens"] = [s for s in l["screens"] if s["name"] != "Comparison"]
for s in l["screens"]:
    if s["name"] == "Content policy": s["nav"] = ["Content Policy"]
json.dump(l, open(sys.argv[2], "w"))
PY
  out="$(_mac2 "$d")"
  grep -q '^Character library|OK|clicked "Characters"$' <<<"$out" && grep -q '^Hardware and setup|OK|clicked "Switch to Management" > "Hardware & Setup"$' <<<"$out" \
    && grep -q '^Gallery|OK|clicked "Switch to Creator studio" > "Gallery"$' <<<"$out" \
    && ok ts_006b "the checker presses \"Switch to Management\" to reach a management screen, and switches back for a creator one" \
    || bad ts_006b "a screen behind the surface switch was not reached: $(tr '\n' '/' <<<"$out" | cut -c1-400)"
  grep -q '^Content policy|UNREACHABLE|' <<<"$out" \
    && ok ts_006c "a menu label no surface shows is still UNREACHABLE" \
    || bad ts_006c "a label on no surface was not reported: $(grep '^Content policy' <<<"$out")"
}

# --- TrStudio TF-007: a click below the window, and the screen reported reached ------------------------------------
# Register's "Sign in" sat below the window; the click landed outside it and did nothing, and the checker wrote
# "OK Login … clicked "Sign in"" with a picture of Register. The control is scrolled into the window first, and a
# click that changes nothing in the window is reported: the screen is not reached.
ts_007() {
  command -v node >/dev/null 2>&1 || { printf 'skipped: ts_007 — needs node\n'; return; }
  local d="$SCRATCH/ts007" out
  mkdir -p "$d"
  _m7() { python3 -c "
import json, sys
json.dump({'start': 'register', 'max_scroll': int(sys.argv[2]), 'pages': {
  'register': [{'label': 'Help', 'y': 300}, {'label': 'Sign in', 'to': 'login', 'y': 900}],
  'login': [{'label': 'Create an account', 'to': 'register', 'y': 300}], 'help': []}}, open(sys.argv[1], 'w'))" "$d/model.json" "$1"
    printf '%s' '{"screens":[{"name":"Register","route":"/register","key":"register","rows":[]},{"name":"Login","route":"/login","key":"login","nav":["Sign in"],"rows":[]},{"name":"Help","route":"/help","key":"help","nav":["Help"],"rows":[]}],"links":[{"from":"register","to":"login","label":"Sign in","project":""},{"from":"register","to":"help","label":"Help","project":""},{"from":"login","to":"register","label":"Create an account","project":""}]}' > "$d/list.json"; }
  _m7 400; out="$(_mac2 "$d")"
  grep -q '^Login|OK|clicked "Sign in"$' <<<"$out" && grep -q '^scroll' "$d/model.json.log" && grep -q '^click Sign in landed' "$d/model.json.log" && ! grep -q 'outside the window' "$d/model.json.log" \
    && ok ts_007a "a link below the window is scrolled into it before the click, and the click lands" \
    || bad ts_007a "the link was clicked outside the window: $(grep '^Login' <<<"$out") // $(tr '\n' '/' < "$d/model.json.log")"
  _m7 0; out="$(_mac2 "$d")"
  grep -q '^Login|UNREACHABLE|.*"Sign in" sits outside the window and could not be scrolled into it' <<<"$out" \
    && grep -q '^Help|UNREACHABLE|.*the click on "Help" changed nothing in the window' <<<"$out" \
    && ok ts_007b "a control that cannot be brought into the window, and a click that changes nothing, are each reported not reached" \
    || bad ts_007b "a click that did not land was reported as reached: $(tr '\n' '/' <<<"$out" | cut -c1-400)"
  # TrStudio, 16 Nov, on the real app: "Account" was matched to "Create an account" and Register graded as Account
  python3 -c "
import json, sys
json.dump({'start': 'login', 'pages': {'login': [{'label': 'Create an account', 'to': 'register', 'y': 300}, {'label': '\U0001F4F7 Images', 'to': 'images', 'y': 330}],
  'register': [], 'images': [], 'account': []}}, open(sys.argv[1], 'w'))" "$d/model.json"
  printf '%s' '{"screens":[{"name":"Account","route":"/account","key":"account","nav":["Account"],"rows":[]},{"name":"Images","route":"/images","key":"images","nav":["Images"],"rows":[]}]}' > "$d/list.json"
  out="$(_mac2 "$d")"
  grep -q '^Images|OK|clicked "Images"$' <<<"$out" && grep -q '^Account|UNREACHABLE|' <<<"$out" \
    && ok ts_007c "a label with an icon in front is still the menu item, but \"Account\" is never \"Create an account\"" \
    || bad ts_007c "a label was matched inside a longer one: $(tr '\n' '/' <<<"$out" | cut -c1-300)"
}

# --- TrStudio, 16 Nov, on the real app: the Mac sign-in typed nothing --------------------------------------------
# The checker types with W3C key actions (Lekhak TF-026). TrStudio's form took none of a text holding "@", "!" or
# "#": the fields kept their placeholders and the sign-in failed, so no screen behind it was measured. The field
# is read back now, and typed again with mac2's own "macos: keys" when it does not hold the text. The test user
# and password below are fixture values. Control half: plain text typed by key actions is still taken as before.
ts_007d() {
  command -v node >/dev/null 2>&1 || { printf 'skipped: ts_007d — needs node\n'; return; }
  local d="$SCRATCH/ts007d" out u="$1" w="$2"
  mkdir -p "$d"
  python3 -c "
import json, sys
json.dump({'start': 'login', 'pages': {'login': [{'type': 'TextField', 'label': 'Email', 'y': 200}, {'type': 'SecureTextField', 'label': 'Password', 'y': 240},
  {'type': 'Button', 'label': 'Sign in', 'y': 280, 'login': {'user': sys.argv[2], 'pass': sys.argv[3], 'to': 'home'}}],
  'home': [{'label': 'Gallery', 'to': 'gallery', 'y': 100}], 'gallery': [{'label': 'Gallery', 'to': 'gallery', 'y': 100}]}}, open(sys.argv[1], 'w'))" "$d/model.json" "$u" "$w"
  printf '%s' '{"screens":[{"name":"Gallery","route":"/gallery","key":"gallery","nav":["Gallery"],"rows":[]}]}' > "$d/list.json"
  out="$(_mac2 "$d" --user "$u" --password "$w")"
  grep -q '^LOGIN signed in' "$d/run.log" && grep -q '^Gallery|OK|clicked "Gallery"$' <<<"$out"
}
ts_007e() {
  ts_007d 'tester@fx.test' 'Fx!pw#2026' \
    && ok ts_007d "a user and password holding @, ! and # reach the form; the Mac head signs in and reaches the screen behind it" \
    || bad ts_007d "the sign-in typed nothing: $(grep -m1 '^LOGIN' "$SCRATCH/ts007d/run.log")"
  ts_007d 'tester' 'Fxpw2026' && grep -q '^keys taken' "$SCRATCH/ts007d/model.json.log" \
    && ok ts_007e "plain text is still typed by key actions, as Lekhak's form needed" \
    || bad ts_007e "plain text no longer went through key actions: $(tr '\n' '/' < "$SCRATCH/ts007d/model.json.log" | cut -c1-200)"
}

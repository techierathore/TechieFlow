# tests/faults/n19-cases.sh — sourced by tests/faults/run.sh; the cases of 19 Nov 2026. Each fails on the scripts
# the projects had on 18 Nov (the working tree of 16 Nov, afternoon) and passes now, with a control half.
# Uses run.sh's ok/bad/note/$SCRATCH/$UTILS and n16-cases.sh's _fx/_doc; _parity is run.sh's.

# --- Chatur TF-045: two anchors that measure alike were called a badge on one side --------------------------------
# The 16 Nov rule (Sevak TF-042) judges a pair by the control's rule when either side is a control "one element away".
# On Chatur's routing tiers the wrapper measures the same on both sides (0 px on 28 px, no fill, no ring), but only the
# mockup's wrapper counted its rounded button as one element away, so the mockup side was read as a pill and the app's
# as plain. Two anchors that measure alike now agree. Control: a trigger the app draws square where the mockup's is
# round is still reported, at the button's own key.
ch_045() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_045 — needs playwright\n'; return; }
  local d="$SCRATCH/ch045" out b='margin:0;padding:24px;font-family:sans-serif;background:#fff'
  local ch='<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>'
  local pk='height:28px;padding:0 9px;border:1px solid #e3e5ea;border-radius:999px;background:#fff;font-size:12.5px;display:inline-flex;align-items:center;gap:7px'
  local m; m="$(_doc mockup "$b" "<h1 data-testid=\"title\">Routing</h1><table data-testid=\"agents\"><tr><td>Analyst</td><td><div style=\"position:relative;display:inline-flex\" data-testid=\"analyst-tier\"><button style=\"$pk\" data-testid=\"analyst-tier-button\"><span>Tier 2</span>$ch</button><div data-tf-state=\"popup-open\" style=\"display:none\"><button>Tier 1</button></div></div></td></tr></table><button style=\"$pk\" data-testid=\"mode-button\"><span>Dark</span>$ch</button>")"
  # Chatur's app: the library's Select root (the anchor) around its trigger, with one more small box beside it
  _app() { _doc app "$b" "<h1 data-testid=\"title\">Routing</h1><table data-testid=\"agents\"><tr><td>Analyst</td><td><div style=\"position:relative;display:flex;height:28px;width:256px\" data-testid=\"analyst-tier\"><button type=\"button\" role=\"combobox\" aria-haspopup=\"listbox\" aria-expanded=\"false\" style=\"$pk;width:256px;justify-content:space-between;border-radius:$1\" data-testid=\"analyst-tier-button\"><span>Tier 2</span>$ch</button><div style=\"position:absolute;left:0;top:0;width:4px;height:4px\"></div></div></td></tr></table><button type=\"button\" style=\"$pk;border-radius:$1\" data-testid=\"mode-button\"><span>Dark</span>$ch</button>"; }
  _fx "$d" routing "$m" "$(_app 9999px)"
  out="$(TF_PARITY_ARGS=--no-menus _parity "$d" routing /routing/)"
  [[ "$out" != NO-RESULT ]] && ! grep -qE ' (analyst-tier|mode-button > span\[0\]) badge' <<<"$out" \
    && ok ch_045a "a wrapper that measures alike on both sides (0 px on 28 px, no fill, no ring) is no badge on one side only" \
    || bad ch_045a "the wrapper is still a badge on one side: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  _fx "$d" routing "$m" "$(_app 6px)"
  out="$(TF_PARITY_ARGS=--no-menus _parity "$d" routing /routing/)"
  grep -qE '^1280 analyst-tier-button badge mockup renders this as a badge/pill, app' <<<"$out" \
    && ok ch_045b "a trigger the app draws square where the mockup's is round is still reported, at the trigger's key" \
    || bad ch_045b "the real shape difference was lost: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- TfLens TF-059: a mockup switch's empty track read as a missing badge ------------------------------------------
# TfLens's mockups draw the theme switch as <button class="switch"> holding two icons and <span class="trk"> (36x20,
# fully rounded, filled, no text); the app draws two icons and TrBlazeUI's Switch, a button[role="switch"], which the
# badge count leaves out as a toggle. The mockup's track was a badge the app "did not draw". A textless pill under a
# parent where the app draws a switch the mockup does not is now that switch's track. The same page fails on every
# version of the check since 11 Nov, so the 16 Nov change is not its cause. Controls: a bell's textless dot the app
# leaves out is still missing, and so is the track when the app draws no switch at all.
tf_059() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: tf_059 — needs playwright\n'; return; }
  local d="$SCRATCH/tf059" out b='margin:0;font-family:sans-serif;background:#fff'
  local sv='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="4"/></svg>'
  local hd='display:flex;align-items:center;justify-content:space-between;height:56px;padding:0 16px;border-bottom:1px solid #e2e8f0'
  local trk='<span style="display:inline-block;width:36px;height:20px;border-radius:999px;background:#f1f5f9;border:1px solid #e2e8f0"></span>'
  local dot='<span style="display:inline-block;width:8px;height:8px;border-radius:999px;background:#ef4444"></span>'
  local sw='<button type="button" role="switch" aria-checked="false" aria-label="Dark mode" style="width:36px;height:20px;border-radius:999px;background:#f1f5f9;border:1px solid #e2e8f0;padding:0"><span style="display:block;width:14px;height:14px;border-radius:999px;background:#0f172a;margin:2px"></span></button>'
  local m; m="$(_doc mockup "$b" "<header style=\"$hd\" data-testid=\"header\"><h1 data-testid=\"title\">Routing</h1><button data-testid=\"theme-toggle\" style=\"display:inline-flex;align-items:center;gap:8px;background:none;border:0\">$sv$trk</button><button data-testid=\"bell\" style=\"background:none;border:0\">$sv$dot</button></header><p data-testid=\"body\">Rows</p>")"
  _app() { _doc app "$b" "<header style=\"$hd\" data-testid=\"header\"><h1 data-testid=\"title\">Routing</h1><div data-testid=\"theme-toggle\" style=\"display:flex;align-items:center;gap:8px\">$sv$1</div><button data-testid=\"bell\" style=\"background:none;border:0\">$sv$2</button></header><p data-testid=\"body\">Rows</p>"; }
  _fx "$d" routing "$m" "$(_app "$sw" "$dot")"
  out="$(_parity "$d" routing /routing/)"
  [[ "$out" != NO-RESULT ]] && ! grep -qE ' theme-toggle > span\[0\] missing' <<<"$out" \
    && ok tf_059a "a mockup switch's empty track, where the app draws a library switch: no missing badge" \
    || bad tf_059a "the switch's track is still a missing badge: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
  _fx "$d" routing "$m" "$(_app '' '')"
  out="$(_parity "$d" routing /routing/)"
  grep -qE '^1280 bell > span\[0\] missing' <<<"$out" && grep -qE '^1280 theme-toggle > span\[0\] missing' <<<"$out" \
    && ok tf_059b "a bell's textless dot the app leaves out, and a track where the app draws no switch, are still missing" \
    || bad tf_059b "a real missing pill was lost: $(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- Chatur TF-039: the register script sent applicationId beside an API key ----------------------------------------
# AppManager reads the application from the API key and refuses a register call that also names one ("400 The
# applicationId parameter does not match the API key's application"); Chatur's own register call leaves it out. The
# script sent it always and refused to run without it. Now it is sent, and needed, only when no key is set. Control:
# with no key, the ApplicationId is sent as before; with neither, the script still stops with exit 2.
ch_039() {
  command -v node >/dev/null 2>&1 || { printf 'skipped: ch_039 — needs node\n'; return; }
  local d="$SCRATCH/ch039" out rc port am
  mkdir -p "$d/tests/verify"; cp "$UTILS/tf-testsettings.mjs" "$UTILS/tf-register-test-users.mjs" "$d/"
  cat > "$d/am.mjs" <<'JS'
import http from 'node:http'; import crypto from 'node:crypto'; import fs from 'node:fs';
const { publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048, publicKeyEncoding: { type: 'spki', format: 'pem' }, privateKeyEncoding: { type: 'pkcs8', format: 'pem' } });
http.createServer((req, res) => { let body = ''; req.on('data', (c) => { body += c; }); req.on('end', () => {
  res.setHeader('Content-Type', 'application/json');
  if (req.url === '/AuthSvc/public-key') return res.end(JSON.stringify({ success: true, data: { publicKey } }));
  const b = JSON.parse(body || '{}'), key = req.headers['x-api-key'];
  fs.appendFileSync(process.argv[3], JSON.stringify({ key: !!key, app: b.applicationId ?? null }) + '\n');
  if (key && b.applicationId) { res.statusCode = 400; return res.end('{"success":false,"message":"The applicationId parameter does not match the API key\'s application"}'); }
  if (!key && !b.applicationId) { res.statusCode = 400; return res.end('{"success":false,"message":"applicationId is required"}'); }
  res.end('{"success":true,"data":{"userId":7}}'); }); }).listen(Number(process.argv[2]), '127.0.0.1');
JS
  port="$(_free_port)"; node "$d/am.mjs" "$port" "$d/log" >/dev/null 2>&1 & am=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do python3 -c "import socket,sys;socket.create_connection(('127.0.0.1',$port),1)" 2>/dev/null && break; sleep 1; done
  _set() { printf '{"TestUsers": {"1": {"Email": "fx-owner@fx.app", "Password": ""}}, "AppManager": {"BaseUrl": "http://127.0.0.1:%s", "ApiKey": "%s", "ApplicationId": "%s"}}\n' "$port" "$1" "$2" > "$d/tests/verify/testsettings.json"; rm -f "$d/tests/verify/testsettings.Local.json" "$d/log"; }
  _set k-123 chatur; out="$(cd "$d" && node tf-register-test-users.mjs 2>&1)"; rc=$?
  local l1; l1="$(cat "$d/log" 2>/dev/null)"
  _set k-123 ""; local o2; o2="$(cd "$d" && node tf-register-test-users.mjs 2>&1)"; local rc2=$?
  [[ $rc -eq 0 && $rc2 -eq 0 && "$l1" == '{"key":true,"app":null}' ]] && grep -q 'registered (user id 7)' <<<"$out$o2" \
    && ok ch_039a "with an API key the register call names no applicationId, and a key with no ApplicationId is enough" \
    || bad ch_039a "exit $rc/$rc2, sent: $l1 // $(tr '\n' ' ' <<<"$out $o2" | cut -c1-200)"
  _set "" chatur; out="$(cd "$d" && node tf-register-test-users.mjs 2>&1)"; rc=$?; l1="$(cat "$d/log" 2>/dev/null)"
  _set "" ""; o2="$(cd "$d" && node tf-register-test-users.mjs 2>&1)"; rc2=$?
  kill "$am" 2>/dev/null; wait "$am" 2>/dev/null
  [[ $rc -eq 0 && "$l1" == '{"key":false,"app":"chatur"}' && $rc2 -eq 2 ]] && grep -q 'not set' <<<"$o2" && ! grep -q 'k-123' <<<"$out$o2" \
    && ok ch_039b "with no key the ApplicationId is sent as before; with neither the script stops (exit 2); no key is printed" \
    || bad ch_039b "exit $rc/$rc2, sent: $l1 // $(tr '\n' ' ' <<<"$out $o2" | cut -c1-200)"
}

# --- Chatur TF-038: a verify run from a separate copy split its writes between the copy and the repository ----------
# tf-emit.sh sends records to the project the session names (CLAUDE_PROJECT_DIR), while the verdict wrote the checklist
# cells and docs/.last-verify.json into the folder it ran in. Copying the copy's docs/ home then replaced the
# repository's streams with older ones. Now the verdict writes where the records go, when that project holds the
# checklist graded, and the emit follows the verdict (verdicts.json "home"): nothing needs copying back. Control: a
# verify run with no project named keeps everything in the folder it runs in.
ch_038() {
  local d="$SCRATCH/ch038" R C out
  R="$d/R"; C="$d/C"; mkdir -p "$R/.tfcore/.session" "$R/docs/metrics" "$R/tests/.artifacts/verify"; cp -r "$UTILS" "$R/.tfcore/"
  for s in runs gates sessions commits misses; do : > "$R/docs/metrics/$s.jsonl"; done
  printf 'appPhase: 1\nappKind: app\nappSize: S\n' > "$R/.tfcore/core-config.yaml"
  printf '# Fx — Checklist\n\n| ID | Title | Status | %% | Remarks | Details |\n|---|---|---|---|---|---|\n| REQ-FN-001 | Add | Implemented | 90%% | | |\n' > "$R/docs/Fx-Checklist.md"
  cp -r "$R" "$C"
  _run() {   # <cwd> <project the session names, or empty>
    ( cd "$1" && export CLAUDE_PROJECT_DIR="$2" TF_SKIP_SELFCHECK=1
      bash .tfcore/utils/tf-verify-list.sh Fx all --phase 1 >/dev/null 2>&1
      printf '{"reqs":{"REQ-FN-001":{"result":"FAIL","source":"unit","tests":["REQ-FN-001 adds"],"skipped":[],"passed":0,"failed":1,"reason":"expected 2 got 1","screenshot":""}},"browser":{"ran":false},"unit":{"ran":true,"line":"FAIL unit"}}' > tests/.artifacts/verify/tests.json
      bash .tfcore/utils/tf-verify-verdict.sh Fx --apply 2>&1; bash .tfcore/utils/tf-verify-emit.sh Fx 2>&1 ) ; }
  out="$(_run "$C" "$R")"
  grep -q '| REQ-FN-001 | Add | FAIL ' "$R/docs/Fx-Checklist.md" && [[ -f "$R/docs/.last-verify.json" && -s "$R/docs/metrics/gates.jsonl" ]] \
    && grep -q '| Implemented |' "$C/docs/Fx-Checklist.md" && [[ ! -e "$C/docs/.last-verify.json" && ! -s "$C/docs/metrics/gates.jsonl" ]] \
    && ok ch_038a "a verify run from a copy writes its checklist cells, ledger and records into one place, the project the session names" \
    || bad ch_038a "split: repository $(grep -o 'REQ-FN-001 | Add | [A-Za-z ]*' "$R/docs/Fx-Checklist.md"), $(wc -l < "$R/docs/metrics/gates.jsonl") gate(s); copy $(grep -o 'REQ-FN-001 | Add | [A-Za-z ]*' "$C/docs/Fx-Checklist.md"), $(wc -l < "$C/docs/metrics/gates.jsonl") gate(s)"
  rm -rf "$C"; cp -r "$R" "$C"; for s in runs gates misses; do : > "$C/docs/metrics/$s.jsonl"; done; rm -f "$C/docs/.last-verify.json"
  local g0; g0="$(wc -l < "$R/docs/metrics/gates.jsonl")"
  out="$(_run "$C" "")"
  [[ -s "$C/docs/metrics/gates.jsonl" && -f "$C/docs/.last-verify.json" && "$(wc -l < "$R/docs/metrics/gates.jsonl")" == "$g0" ]] \
    && ok ch_038b "with no project named, a verify keeps everything in the folder it runs in, as before" \
    || bad ch_038b "the copy's own verify wrote elsewhere: $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
}

# --- Sevak TF-045: the status gate's doc-test step built inside the repository -------------------------------------
# The owner runs Sevak from the repository's bin/ this week and had every build made in a copy; the gate's step 4,
# tf-doc-tests.sh, still built the test projects where it stood. `buildCopy:` in core-config.yaml (or --root) now
# names the copy: the changed documents are copied into it and the tests build and run there; a buildCopy that does
# not exist is NOT-RUN, never a build here. Control: with no copy named, the tests run here as before. The build is a
# stand-in tf-build.sh that records where it ran and which text it read.
sv_045() {
  local d="$SCRATCH/sv045" r c out
  r="$d/repo"; c="$d/copy"; mkdir -p "$r/.tfcore" "$r/docs" "$r/tests/Fx.Tests"; cp -r "$UTILS" "$r/.tfcore/"
  cat > "$r/.tfcore/utils/tf-build.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p tests/Fx.Tests/bin && echo built > tests/Fx.Tests/bin/marker
echo "$(pwd -P) | $(grep -c 'REQ-NFR-042' docs/Fx-UsageGuide.md)" >> "$TF_SV045_LOG"
echo "PASS  test (stand-in)"
SH
  printf 'appPhase: 1\n' > "$r/.tfcore/core-config.yaml"
  printf '# Fx — Usage Guide\n\nREQ-NFR-042 old text\n' > "$r/docs/Fx-UsageGuide.md"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$r/tests/Fx.Tests/Fx.Tests.csproj"
  printf 'class DocTests { string P = "docs/Fx-UsageGuide.md"; }\n' > "$r/tests/Fx.Tests/DocTests.cs"
  cp -r "$r" "$c"; rm -rf "$c/.tfcore/core-config.yaml"
  printf '# Fx — Usage Guide\n\nREQ-NFR-042 new text\nREQ-NFR-042 second line\n' > "$r/docs/Fx-UsageGuide.md"   # the command's change
  export TF_SV045_LOG="$d/log"; : > "$d/log"
  printf 'appPhase: 1\nbuildCopy: %s\n' "$c" > "$r/.tfcore/core-config.yaml"
  out="$(cd "$r" && bash .tfcore/utils/tf-doc-tests.sh docs/Fx-UsageGuide.md 2>&1)"
  [[ "$(cat "$d/log")" == "$(cd "$c" && pwd -P) | 2" && ! -e "$r/tests/Fx.Tests/bin" && -f "$c/tests/Fx.Tests/bin/marker" ]] && grep -q '^PASS' <<<"$out" \
    && ok sv_045a "with buildCopy set, the doc tests build and run in the copy, on this command's text; nothing is built in the repository" \
    || bad sv_045a "built in: $(cat "$d/log") // repo bin: $(ls "$r/tests/Fx.Tests/bin" 2>/dev/null) // $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
  : > "$d/log"; printf 'appPhase: 1\nbuildCopy: %s/gone\n' "$d" > "$r/.tfcore/core-config.yaml"
  out="$(cd "$r" && bash .tfcore/utils/tf-doc-tests.sh docs/Fx-UsageGuide.md 2>&1)"; local rc=$?
  [[ $rc -eq 2 && ! -s "$d/log" && ! -e "$r/tests/Fx.Tests/bin" ]] && grep -q '^NOT-RUN .*does not exist; nothing was built here' <<<"$out" \
    && ok sv_045b "a buildCopy that does not exist is NOT-RUN, naming it; nothing is built in the repository" \
    || bad sv_045b "exit $rc, ran in: $(cat "$d/log") // $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
  : > "$d/log"; printf 'appPhase: 1\n' > "$r/.tfcore/core-config.yaml"
  out="$(cd "$r" && bash .tfcore/utils/tf-doc-tests.sh docs/Fx-UsageGuide.md 2>&1)"
  [[ "$(cat "$d/log")" == "$(cd "$r" && pwd -P) | 2" ]] && grep -q '^PASS' <<<"$out" \
    && ok sv_045c "with no copy named, the doc tests run here as before" \
    || bad sv_045c "ran in: $(cat "$d/log") // $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
  unset TF_SV045_LOG
}

# --- Lekhak TF-046: tf-fix-close.sh stopped with KeyError 'started' ------------------------------------------------
# Lekhak's runs.jsonl holds build-phase fix records with no start time (six of them, three of 18 Nov). The follow-up
# scan (Lekhak TF-039) took the first such record as "the run before this close" and read its missing start: a Python
# traceback after the first output line, the report lost. A record with no start is now left out of the scan and
# counted in the report. Control: the follow-up still finds a real earlier fix and files its miss-fix under it.
lk_046() {
  local d="$SCRATCH/lk046" M out
  M="$d/docs/metrics"; mkdir -p "$M" "$d/.tfcore"; for s in runs gates sessions commits misses; do : > "$M/$s.jsonl"; done
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  cat > "$M/runs.jsonl" <<'J'
{"kind":"run","app":"Fx","cmd":"build-phase","mode":"fix","started":"2026-11-18T14:00:00Z","ended":"2026-11-18T14:30:00Z","reqs_touched":["REQ-UI-161"],"v":1,"ts":"2026-11-18T14:30:00Z"}
{"kind":"run","app":"Fx","cmd":"build-phase","mode":"fix","ended":"2026-11-18T15:49:00Z","reqs_touched":["REQ-UI-162"],"v":1,"ts":"2026-11-18T15:49:00Z"}
{"kind":"run","app":"Fx","cmd":"verify-phase","mode":"verify","started":"2026-11-18T17:30:00Z","ended":"2026-11-18T17:40:00Z","v":1,"ts":"2026-11-18T17:40:00Z"}
J
  cat > "$M/misses.jsonl" <<'J'
{"kind":"miss","miss_id":"MISS-Fx-20261118-49","req_id":"REQ-UI-163","req_class":"UI","miss_class":"wrong-behaviour","artifact":"src","severity":"major","found_by":"owner","app":"Fx","v":1,"ts":"2026-11-18T17:10:00Z"}
{"kind":"miss","miss_id":"MISS-Fx-20261118-40","req_id":"REQ-UI-161","req_class":"UI","miss_class":"wrong-behaviour","artifact":"src","severity":"major","found_by":"owner","app":"Fx","v":1,"ts":"2026-11-18T13:50:00Z"}
J
  cat > "$M/gates.jsonl" <<'J'
{"kind":"gate","app":"Fx","run_id":"2026-11-18T17:20:00Z","req_id":"REQ-UI-163","req_class":"UI","attempt":1,"verdict":"Verified","gate":null,"v":1,"ts":"2026-11-18T17:40:00Z"}
{"kind":"gate","app":"Fx","run_id":"2026-11-18T17:20:00Z","req_id":"REQ-UI-161","req_class":"UI","attempt":2,"verdict":"Verified","gate":null,"v":1,"ts":"2026-11-18T17:41:00Z"}
J
  printf '{"run_id":"2026-11-18T17:20:00Z","rows":{"REQ-UI-163":"PASS"}}\n' > "$d/docs/.last-verify.json"
  out="$(cd "$d" && bash "$UTILS/tf-fix-close.sh" Fx --reqs REQ-UI-163 --subagents builder --build pass --files 16 --cmd build-phase --started 2026-11-18T17:20:00Z 2>&1)"
  ! grep -qE 'Traceback|KeyError' <<<"$out" && grep -q 'run record written' <<<"$out" && grep -q '1 earlier build-phase run record(s) carry no start time' <<<"$out" \
    && ok lk_046a "a run record with no start time is left out of the follow-up and named; the close finishes its report" \
    || bad lk_046a "$(tr '\n' ' ' <<<"$out" | cut -c1-260)"
  grep -q '"miss_id":"MISS-Fx-20261118-49".*"verdict_after":"Verified"' "$M/misses.jsonl" \
    && grep -q '"miss_id":"MISS-Fx-20261118-40".*"verdict_after":"Verified".*"fix_run_id":"2026-11-18T14:00:00Z"' "$M/misses.jsonl" \
    && ok lk_046b "the row's own miss-fix is written, and the follow-up still files the earlier fix's row under that fix" \
    || bad lk_046b "miss-fix records: $(grep -c miss-fix "$M/misses.jsonl") // $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
}
# the source of those records: a close with no --started and no marker wrote its run record with no start time
lk_046c() {
  local d="$SCRATCH/lk046c" M out
  M="$d/docs/metrics"; mkdir -p "$M" "$d/.tfcore"; for s in runs gates sessions commits misses; do : > "$M/$s.jsonl"; done
  printf 'appPhase: 1\n' > "$d/.tfcore/core-config.yaml"
  printf '{"kind":"miss","miss_id":"MISS-Fx-20261118-49","req_id":"REQ-UI-163","req_class":"UI","miss_class":"wrong-behaviour","artifact":"src","severity":"major","found_by":"owner","app":"Fx","v":1,"ts":"2026-11-18T17:10:00Z"}\n' > "$M/misses.jsonl"
  printf '{"run_id":"x","rows":{"REQ-UI-163":"PASS"}}\n' > "$d/docs/.last-verify.json"
  out="$(cd "$d" && bash "$UTILS/tf-fix-close.sh" Fx --reqs REQ-UI-163 --subagents builder --build pass --cmd build-phase 2>&1)"
  [[ ! -s "$M/runs.jsonl" ]] && grep -q 'run record not written: no --started and no marker' <<<"$out" && grep -q '"verdict_after":"Verified"' "$M/misses.jsonl" \
    && ok lk_046c "a close with no start writes no run record without a start time, says so, and still writes the miss-fix" \
    || bad lk_046c "runs: $(head -c 200 "$M/runs.jsonl") // $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
}

# --- TfLens TF-060: a later phase's row could not reach an earlier phase's screen -----------------------------------
# REQ-UI-081 (phase 4) adds a column to Routing, which is phase 2's screen; tf-verify-list read only phase 4's UIDesign
# and printed "no screen resolved", so the row was graded on its test alone. A row no screen of its own phase owns is
# now resolved against the earlier phases' UIDesigns, by its mockup, its screen's name or a route its entry names, and
# that screen is driven for it. No document changes. Control: a row whose mockup no phase draws stays unresolved, and
# a row of the phase's own screen keeps it.
tf_060() {
  local d="$SCRATCH/tf060" out
  mkdir -p "$d/docs/mockups" "$d/.tfcore" "$d/tests/.artifacts/verify"; printf 'appPhase: 4\nappKind: app\nappSize: L\n' > "$d/.tfcore/core-config.yaml"
  : > "$d/docs/mockups/routing.html"; : > "$d/docs/mockups/estimates.html"
  printf '# Fx — Phase 2 UI Design\n\n### Screen: Routing & economics (`/routing`)\n\nMockup: docs/mockups/routing.html\n' > "$d/docs/Fx-P2-UIDesign.md"
  printf '# Fx — Phase 4 UI Design\n\n### Screen: Estimates (`/estimates`)\n\nMockup: docs/mockups/estimates.html\n' > "$d/docs/Fx-P4-UIDesign.md"
  cat > "$d/docs/Fx-P4-Checklist.md" <<'MD'
# Fx — Phase 4 Checklist

| ID | Title | Status | % | Remarks | Details |
|---|---|---|---|---|---|
| REQ-UI-078 | Estimates table | Implemented | 90% | | [view](#d-req-ui-078) |
| REQ-UI-081 | Routing drift table gains a column | Implemented | 90% | | [view](#d-req-ui-081) |
| REQ-UI-082 | Export banner | Implemented | 90% | | [view](#d-req-ui-082) |

## UI / Pages

<a id="d-req-ui-078"></a>
- **REQ-UI-078** — the estimates table. *Acceptance:* When the user opens Estimates, then the table shows. *Mockup:* docs/mockups/estimates.html.

<a id="d-req-ui-081"></a>
- **REQ-UI-081** — a column after `observed model`. The screen is phase 2's. *Acceptance:* When the user opens Routing, then the column shows. *Mockup:* docs/mockups/routing.html.

<a id="d-req-ui-082"></a>
- **REQ-UI-082** — a banner. *Acceptance:* When the user opens Banner, then it shows. *Mockup:* docs/mockups/banner.html.
MD
  out="$(cd "$d" && TF_SKIP_SELFCHECK=1 bash "$UTILS/tf-verify-list.sh" Fx all --phase 4 2>&1)"
  local got; got="$(python3 -c "
import json; j = json.load(open('$d/tests/.artifacts/verify/list.json'))
r = {x['id']: x.get('route') for x in j['rows']}
print(r.get('REQ-UI-081'), r.get('REQ-UI-078'), r.get('REQ-UI-082') or '-', sorted(s['route'] for s in j['screens']), j['unresolved'])" 2>&1)"
  [[ "$got" == "/routing /estimates - ['/estimates', '/routing'] ['REQ-UI-082']" ]] && grep -q "REQ-UI-081.*Routing & economics /routing (phase 2's screen)" <<<"$out" \
    && ok tf_060a "a phase-4 row on phase 2's screen resolves to that screen, which is driven for it; its own screen and an unknown one as before" \
    || bad tf_060a "$got // $(grep 'REQ-UI-08' <<<"$out" | tr '\n' ' ' | cut -c1-200)"
}

# --- TrStudio TF-008: the status facts printed a phase line the status guard refuses --------------------------------
# With a long phase name ("One desktop app with the engine inside (Mac first)") the facts' current_phase line ran to
# 122 characters and guard-status.sh refuses one over 120. The phase name now gives way first, then the line is cut.
# Control: a short phase name is printed whole.
ts_008() {
  local d="$SCRATCH/ts008" line st="PROJECT-STATUS"; _bl_fx "$d" 2 Fx-P2-Checklist.md
  _ph() { printf '# Fx — Phases\n\n## Phases\n\n| # | Name | Rows |\n|---|---|---|\n| 1 | Foundations | 10 |\n| 2 | %s | 12 |\n' "$1" > "$d/docs/Fx-Phases.md"; }
  _guard() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":"---\n"+sys.argv[2]+"\n---\n"}}))' "$d/$st.md" "$1" \
             | bash "$HOOKS/guard-status.sh" >/dev/null 2>&1; }
  _ph "One desktop app with the engine inside (Mac first) and every studio screen drawn in the same shell"
  line="$(cd "$d" && python3 "$UTILS/tf-status-facts.py" Fx amend-docs 2>&1 | grep -m1 '^current_phase:')"
  [[ -n "$line" && ${#line} -le 135 ]] && _guard "$line" && grep -q 'Phase 2 of 2 (One desktop' <<<"$line" \
    && ok ts_008a "the facts' current_phase line with a long phase name is short enough for the status guard to take as printed" \
    || bad ts_008a "${#line} characters, refused by the guard: $line"
  _ph "Foundations two"
  line="$(cd "$d" && python3 "$UTILS/tf-status-facts.py" Fx amend-docs 2>&1 | grep -m1 '^current_phase:')"
  grep -q 'Phase 2 of 2 (Foundations two)' <<<"$line" && _guard "$line" \
    && ok ts_008b "a short phase name is printed whole" || bad ts_008b "$line"
}

# --- TrStudio TF-010: an invisible native select was graded for text a label under it shows whole --------------------
# Video studio draws the chosen model in a div that wraps, with the real <select> laid over it at opacity 0 so a click
# still opens the list; the screen check measured the select's closed box: "cuts its text … needs 350 px, the box has
# 240 px". A select nobody sees is not graded; the label under it is, when it cuts its text sideways. Controls: a
# visible select too narrow for its option, and a label under an invisible select that cuts its text, are reported.
ts_010() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ts_010 — needs playwright\n'; return; }
  local d="$SCRATCH/ts010" out long='Wan 2.2 Animate 14B fp8 scaled (high noise) with the long LoRA set'
  local css='<style>body{margin:0;font:14px/20px system-ui;padding:16px}.wrap{position:relative;width:240px}.lbl{border:1px solid #ccc;padding:6px 8px;border-radius:6px}.nat{position:absolute;inset:0;width:100%;height:100%;opacity:0}.cut{white-space:nowrap;overflow:hidden}</style>'
  _pg() { mkdir -p "$d/docs/mockups" "$d/site/video"; printf '<!doctype html><html><head><meta charset="utf-8"></head><body><h1>Video studio</h1><div data-testid="model">m</div><div data-testid="other">o</div></body></html>\n' > "$d/docs/mockups/video.html"
          printf '<!doctype html><html><head><meta charset="utf-8">%s</head><body><h1>Video studio</h1><div class="wrap" data-testid="model"><div class="lbl %s">%s</div><select class="nat" aria-label="Model"><option>%s</option></select></div><div data-testid="other">%s</div></body></html>\n' "$css" "$1" "$long" "$long" "$2" > "$d/site/video/index.html"; }
  _pg "" ""
  out="$(_screens "$d" video)"
  [[ -n "$out" ]] && grep -q '^DD' <<<"$out" && ! grep -q 'the select "Model" cuts its text' <<<"$out" \
    && ok ts_010a "a select at opacity 0 over a label that wraps its value onto two lines is not graded for cut text" \
    || bad ts_010a "$(tr '\n' '|' <<<"$out" | cut -c1-300)"
  _pg cut "<select aria-label=\"Slot A\" style=\"width:120px\"><option>$long</option></select>"
  out="$(_screens "$d" video)"
  grep -q '^1280 clipped the select "Model" cuts its text' <<<"$out" && grep -q '^1280 clipped the select "Slot A" cuts its text' <<<"$out" \
    && ok ts_010b "a label under an invisible select that cuts its text, and a visible select too narrow for its option, are still reported" \
    || bad ts_010b "$(tr '\n' '|' <<<"$out" | cut -c1-300)"
}

# --- TrStudio TF-009: the Mac boot warned "no provisioning profile" for a project that names one -------------------
# tf-maccatalyst-check.sh looked for <CodesignProvisioningProfile> only; TrStudio names its profile the way MAUI's Mac
# targets read it, <CodesignProvision>, in a Condition'ed group. Either now counts. Control: keychain entitlements and
# no profile at all are still a WARN.
ts_009() {
  local d="$SCRATCH/ts009" out
  _mp() { mkdir -p "$d/$1/src/App/Platforms/MacCatalyst"
    printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFrameworks>net10.0-maccatalyst</TargetFrameworks><UseMaui>true</UseMaui></PropertyGroup>%s</Project>\n' "$2" > "$d/$1/src/App/App.csproj"
    printf '<plist><dict><key>UIApplicationSceneManifest</key><dict><key>UISceneConfigurations</key><dict><key>UIWindowSceneSessionRoleApplication</key><array><dict><key>UISceneDelegateClassName</key><string>SceneDelegate</string></dict></array></dict></dict></dict></plist>\n' > "$d/$1/src/App/Platforms/MacCatalyst/Info.plist"
    echo '[Register("SceneDelegate")] public class SceneDelegate : MauiUISceneDelegate { }' > "$d/$1/src/App/Platforms/MacCatalyst/AppDelegate.cs"
    echo '<plist><dict><key>keychain-access-groups</key><array><string>x</string></array></dict></plist>' > "$d/$1/src/App/Platforms/MacCatalyst/Entitlements.Debug.plist"; }
  _mp named '<PropertyGroup Condition="$(TargetFramework.Contains(&apos;-maccatalyst&apos;)) and &apos;$(Configuration)&apos; == &apos;Debug&apos;"><CodesignProvision>Mac Catalyst Team Provisioning Profile: com.example.app</CodesignProvision><CodesignEntitlements>Platforms\MacCatalyst\Entitlements.Debug.plist</CodesignEntitlements></PropertyGroup>'
  _mp none '<PropertyGroup><CodesignEntitlements>Platforms\MacCatalyst\Entitlements.Debug.plist</CodesignEntitlements></PropertyGroup>'
  out="$(cd "$d/named" && bash "$UTILS/tf-maccatalyst-check.sh" 2>&1)"
  ! grep -q 'names no provisioning profile' <<<"$out" && grep -q '^OK ' <<<"$out" \
    && ok ts_009a "a project that names its profile with CodesignProvision gets no 'no provisioning profile' warning" \
    || bad ts_009a "$(tr '\n' ' ' <<<"$out" | cut -c1-240)"
  out="$(cd "$d/none" && bash "$UTILS/tf-maccatalyst-check.sh" 2>&1)"
  grep -q '^WARN .*names no provisioning profile' <<<"$out" \
    && ok ts_009b "keychain entitlements with no profile at all still warn" || bad ts_009b "$(tr '\n' ' ' <<<"$out" | cut -c1-240)"
}

# --- Chatur TF-046: a CsWinRT compile error was called a host problem -------------------------------------------------
# tf-build.sh counted CS, RZ, BL, XC and XLS errors as code; CsWinRT1032 on a line of MauiFolderPicker.cs matched none,
# so every rung was tried and the verdict read "NOT-RUN … host issue". An error that points at a line of a source file
# is now the code's, whatever raised it. Control: a workload error with no source line still moves to the next rung.
# Stand-in dotnet and cmd.exe on PATH; nothing is built.
ch_046() {
  local d="$SCRATCH/ch046" out; mkdir -p "$d/bin" "$d/home" "$d/p"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$d/p/Fx.csproj"
  printf '#!/usr/bin/env bash\necho called >> "%s/cmd.calls"; echo "Build succeeded."; exit 0\n' "$d" > "$d/bin/cmd.exe"
  _b() { printf '#!/usr/bin/env bash\necho "%s"; exit 1\n' "$1" > "$d/bin/dotnet"; chmod +x "$d/bin/"*; rm -f "$d/cmd.calls"
         ( cd "$d" && HOME="$d/home" PATH="$d/bin:/usr/bin:/bin" TF_BUILD_PLATFORM=wsl TF_BUILD_LOCK_WAIT=0 bash "$UTILS/tf-build.sh" build p/Fx.csproj ) 2>&1; }
  out="$(_b 'C:\\src\\Chatur\\Platform\\MauiFolderPicker.cs(23,9): error CsWinRT1032: Collection expressions targeting IEnumerable<string> are not supported [p/Fx.csproj]')"
  grep -q '^FAIL  real errors .*CsWinRT1032' <<<"$out" && [[ ! -f "$d/cmd.calls" ]] \
    && ok ch_046a "an analyzer's error on a line of a .cs file is a code error on the first rung; no other rung is tried" \
    || bad ch_046a "$(grep -E '^(FAIL|NOT-RUN|PASS)' <<<"$out" | head -1 | cut -c1-200) // other rung tried: $([[ -f "$d/cmd.calls" ]] && echo yes || echo no)"
  out="$(_b 'error NETSDK1178: workload missing')"
  grep -q '^PASS' <<<"$out" && [[ -f "$d/cmd.calls" ]] \
    && ok ch_046b "a workload error with no source line still moves to the next rung" \
    || bad ch_046b "$(grep -E '^(FAIL|NOT-RUN|PASS)' <<<"$out" | head -1 | cut -c1-200)"
}

# --- Chatur TF-047: a menu item that opens the secondary window "does nothing when clicked" ------------------------
# On Chatur's Windows head, Settings and Licence open a second web view (ISecondaryWindow.Open): a new browser target
# that no page list of the check shows, so the walk saw nothing change. The browser's page targets are now compared
# before and after a click that changed nothing else. Here the item asks a helper to open a page in a browser context
# of its own, which the check's connection does not list. Control: an item that really does nothing is still reported.
ch_047() {
  [[ -n "$(_pw_dir)" ]] || { printf 'skipped: ch_047 — needs playwright\n'; return; }
  local d="$SCRATCH/ch047" port cport hport exe srv br hp out
  mkdir -p "$d/docs/mockups" "$d/site"
  printf '<!doctype html><html><body><h1 data-testid="title">Start</h1><button data-testid="account">Account</button></body></html>\n' > "$d/docs/mockups/main.html"
  port="$(_free_port)"; cport="$(_free_port)"; hport="$(_free_port)"
  cat > "$d/site/index.html" <<HTML
<!doctype html><html><head><meta charset="utf-8"><style>body{font:14px system-ui;margin:0;padding:16px}[role=menu]{display:none;border:1px solid #ccc}[role=menu].o{display:block}</style></head><body>
<h1 data-testid="title">Start</h1><button data-testid="account" aria-haspopup="menu" aria-expanded="false" aria-controls="m" onclick="t()">Account</button>
<div role="menu" id="m"><button role="menuitem" onclick="fetch('http://127.0.0.1:$hport/second');c()">Settings</button><button role="menuitem" onclick="c()">Nothing</button></div>
<script>function t(){var m=document.getElementById('m');m.classList.toggle('o');document.querySelector('[data-testid=account]').setAttribute('aria-expanded',m.classList.contains('o'))}
function c(){document.getElementById('m').classList.remove('o');document.querySelector('[data-testid=account]').setAttribute('aria-expanded','false')}</script></body></html>
HTML
  cat > "$d/second.mjs" <<'JS'
import http from 'node:http'; import { chromium } from 'playwright';
const [hp, cdp] = process.argv.slice(2); let n = 0;
http.createServer(async (req, res) => { res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.url === '/second') { const b = await chromium.connectOverCDP(cdp); const c = await b.newContext(); await c.newPage(); n++; }
  res.end(String(n)); }).listen(Number(hp), '127.0.0.1');
JS
  printf 'import http.server,sys\nclass H(http.server.SimpleHTTPRequestHandler):\n    def log_message(self,*a): pass\n    def translate_path(self,p): return sys.argv[2]\nhttp.server.ThreadingHTTPServer(("127.0.0.1",int(sys.argv[1])),H).serve_forever()\n' > "$d/serve.py"
  ln -sfn "$(_pw_dir)/node_modules" "$d/node_modules"; cp "$UTILS"/tf-*.mjs "$d/"
  python3 "$d/serve.py" "$port" "$d/site/index.html" >/dev/null 2>&1 & srv=$!
  exe="$(cd "$d" && node -e "import('playwright').then(p=>console.log(p.chromium.executablePath()))" 2>/dev/null)"
  "$exe" --headless=new --no-sandbox --remote-debugging-port="$cport" --user-data-dir="$d/profile" "http://127.0.0.1:$port/" >/dev/null 2>&1 & br=$!
  local i=0; while [[ $i -lt 30 ]] && ! curl -s -m 2 "http://127.0.0.1:$cport/json/version" | grep -q webSocketDebuggerUrl; do sleep 1; i=$((i+1)); done
  ( cd "$d" && exec node second.mjs "$hport" "http://127.0.0.1:$cport" ) >/dev/null 2>&1 & hp=$!
  sleep 2
  ( cd "$d" && tf_timeout 300 node tf-verify-screens.mjs --cdp "http://127.0.0.1:$cport" --mockups docs/mockups --screen main=/ --widths 1280 --themes light \
      --render-wait 800 --wait 300 --json-out "$d/s.json" --shots-dir "$d/shots" > "$d/s.log" 2>&1 )
  local opened; opened="$(curl -s -m 2 "http://127.0.0.1:$hport/count")"
  kill "$br" "$srv" "$hp" 2>/dev/null; wait "$br" 2>/dev/null
  out="$(grep -h 'does nothing when clicked' "$d/s.log" "$d/s.json" 2>/dev/null | grep -oE '"?Account › [A-Za-z]+"? does nothing when clicked' | sort -u)"
  [[ "${opened:-0}" -ge 1 ]] && ! grep -q 'Settings' <<<"$out" \
    && ok ch_047a "a menu item that opens a window in a web view no page list shows counts as doing something" \
    || bad ch_047a "opened ${opened:-0} window(s); $(tr '\n' '|' <<<"$out") $(grep -m2 -i 'menu' "$d/s.log" | tr '\n' '|' | cut -c1-200)"
  grep -q 'Account › Nothing' <<<"$out" \
    && ok ch_047b "an item that really does nothing is still reported" \
    || bad ch_047b "the do-nothing item lost its finding: $(tr '\n' '|' <<<"$out") $(tail -3 "$d/s.log" | tr '\n' '|' | cut -c1-200)"
}

# --- Chatur TF-048: the doc-test step built in the repository, though the run built everything else in a copy ------
# Morning of 19 Nov; this case fails on the scripts of the night before (sv_045's --root and buildCopy already in).
# Chatur's copy was C:\ChaturRuns\fix-20261118-night. On WSL `[[ -d ]]` cannot see that form, so --root or buildCopy
# named with it was "does not exist"; with no copy named the step built in the repository without a word. A Windows
# path is now read through wslpath, and with no copy named the step says first that it builds here. A stand-in wslpath
# maps C:\ onto the case's own folder. Control: a Windows path to a copy that is not there still builds nothing here.
ch_048() {
  local d="$SCRATCH/ch048" r c out rc
  r="$d/Fx"; c="$d/mnt/c/FxRuns/fix-night"; mkdir -p "$r/.tfcore" "$r/docs" "$r/tests/unit/Fx.Tests" "$d/bin"; cp -r "$UTILS" "$r/.tfcore/"
  cat > "$r/.tfcore/utils/tf-build.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p tests/unit/Fx.Tests/bin && echo built > tests/unit/Fx.Tests/bin/marker
echo "$(pwd -P) | $(grep -c 'BRD-229' docs/Fx-BRD.md)" >> "$TF_CH048_LOG"
echo "PASS  test (stand-in)"
SH
  cat > "$d/bin/wslpath" <<'SH'
#!/usr/bin/env bash
p="${2//\\//}"; d="$(printf '%s' "${p%%:*}" | tr 'A-Z' 'a-z')"; echo "$TF_CH048_MNT/$d${p#?:}"
SH
  chmod +x "$d/bin/wslpath"
  printf 'appPhase: 3\n' > "$r/.tfcore/core-config.yaml"
  printf '# Fx — BRD\n\nBRD-228 old\n' > "$r/docs/Fx-BRD.md"
  printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$r/tests/unit/Fx.Tests/Fx.Tests.csproj"
  printf 'class BrdTests { string P = "docs/Fx-BRD.md"; }\n' > "$r/tests/unit/Fx.Tests/BrdTests.cs"
  mkdir -p "$(dirname "$c")"; cp -r "$r" "$c"
  printf '# Fx — BRD\n\nBRD-228 old\nBRD-229 new\n' > "$r/docs/Fx-BRD.md"   # the command's change
  export TF_CH048_LOG="$d/log" TF_CH048_MNT="$d/mnt"; : > "$d/log"
  out="$(cd "$r" && PATH="$d/bin:$PATH" bash .tfcore/utils/tf-doc-tests.sh docs/Fx-BRD.md --root 'C:\FxRuns\fix-night' 2>&1)"
  [[ "$(cat "$d/log")" == "$(cd "$c" && pwd -P) | 1" && ! -e "$r/tests/unit/Fx.Tests/bin" ]] && grep -q '^PASS' <<<"$out" \
    && ok ch_048a "--root with a Windows path (C:\\FxRuns\\fix-night) builds and runs the doc tests in that copy, on this command's text; nothing here" \
    || bad ch_048a "built in: $(cat "$d/log") // repo bin: $(ls "$r/tests/unit/Fx.Tests/bin" 2>/dev/null) // $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
  : > "$d/log"; rm -rf "$c/tests/unit/Fx.Tests/bin"; printf 'appPhase: 3\nbuildCopy: C:\\FxRuns\\fix-night\n' > "$r/.tfcore/core-config.yaml"
  out="$(cd "$r" && PATH="$d/bin:$PATH" bash .tfcore/utils/tf-doc-tests.sh docs/Fx-BRD.md 2>&1)"
  [[ "$(cat "$d/log")" == "$(cd "$c" && pwd -P) | 1" && ! -e "$r/tests/unit/Fx.Tests/bin" ]] && grep -q '^PASS' <<<"$out" \
    && ok ch_048b "buildCopy written as a Windows path is the same copy" \
    || bad ch_048b "built in: $(cat "$d/log") // $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
  : > "$d/log"; printf 'appPhase: 3\n' > "$r/.tfcore/core-config.yaml"
  out="$(cd "$r" && PATH="$d/bin:$PATH" bash .tfcore/utils/tf-doc-tests.sh docs/Fx-BRD.md 2>&1)"
  [[ "$(cat "$d/log")" == "$(cd "$r" && pwd -P) | 1" ]] && [[ "$(head -1 <<<"$out")" == "note     no separate copy named"*"build and run here, in $(cd "$r" && pwd -P)"* ]] && grep -q '^PASS' <<<"$out" \
    && ok ch_048c "with no copy named the step says first that the tests build here, then runs them here as before" \
    || bad ch_048c "ran in: $(cat "$d/log") // $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
  : > "$d/log"; rm -rf "$r/tests/unit/Fx.Tests/bin"
  out="$(cd "$r" && PATH="$d/bin:$PATH" bash .tfcore/utils/tf-doc-tests.sh docs/Fx-BRD.md --root 'C:\FxRuns\gone' 2>&1)"; rc=$?
  [[ $rc -eq 2 && ! -s "$d/log" && ! -e "$r/tests/unit/Fx.Tests/bin" ]] && grep -q '^NOT-RUN .*does not exist; nothing was built here' <<<"$out" \
    && ok ch_048d "control: a Windows path to a copy that is not there is NOT-RUN; nothing is built here" \
    || bad ch_048d "exit $rc, ran in: $(cat "$d/log") // $(tr '\n' ' ' <<<"$out" | cut -c1-200)"
  unset TF_CH048_LOG TF_CH048_MNT
}

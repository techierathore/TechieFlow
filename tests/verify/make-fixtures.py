#!/usr/bin/env python3
"""Builds the throw-away project tests/verify/run.sh verifies against: a static "app" with one good
screen, one empty screen, one overlapping screen and one unstyled screen; a checklist, UIDesign,
BRD and UsageGuide in the Session 3 shapes; anchored mockups; a Playwright spec named by row id.
Written under $TF_FIXTURE_DIR (default tests/.artifacts/verify-fixture)."""
import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FX = os.environ.get("TF_FIXTURE_DIR") or os.path.join(ROOT, "tests", ".artifacts", "verify-fixture")
APP = os.path.join(FX, "fx-app")


def w(rel, text):
    p = os.path.join(APP, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text.lstrip("\n"))


if os.path.isdir(APP):
    for name in os.listdir(APP):
        if name != "node_modules":   # keep the installed browser tooling between runs
            shutil.rmtree(os.path.join(APP, name), ignore_errors=True) if os.path.isdir(os.path.join(APP, name)) else os.remove(os.path.join(APP, name))
os.makedirs(APP, exist_ok=True)

# the framework, as update-framework.sh would leave it
shutil.copytree(os.path.join(ROOT, ".tfcore", "utils"), os.path.join(APP, ".tfcore", "utils"), dirs_exist_ok=True)
shutil.copytree(os.path.join(ROOT, ".tfcore", "hooks"), os.path.join(APP, ".tfcore", "hooks"), dirs_exist_ok=True)
shutil.copytree(os.path.join(ROOT, ".tfcore", "telemetry"), os.path.join(APP, ".tfcore", "telemetry"), dirs_exist_ok=True)
shutil.copytree(os.path.join(ROOT, ".tfcore", "templates"), os.path.join(APP, ".tfcore", "templates"), dirs_exist_ok=True)
w(".tfcore/core-config.yaml", """
appName: FxApp
appSize: S
appKind: app
appPhase: 1
metrics:
  project_type: app
""")
os.makedirs(os.path.join(APP, "docs", "metrics"), exist_ok=True)

CSS = "body{font-family:sans-serif;margin:0} header{padding:12px;background:#223;color:#fff} main{padding:16px} table{border-collapse:collapse} td,th{border:1px solid #999;padding:4px 8px} button{padding:6px 12px}"
w("site/site.css", CSS)
w("site/index.html", """
<!doctype html><html><head><meta charset="utf-8"><title>Home</title><link rel="stylesheet" href="site.css"><script src="app.js"></script></head>
<body><header data-testid="header"><h1>FxApp</h1><nav><a href="entries.html" data-testid="nav-entries">Entries</a></nav></header>
<main><h2>Today</h2>
<ul data-testid="entry-list"><li>Morning walk</li><li>Lunch with Ana</li><li>Read chapter 4</li></ul>
<button data-testid="new-entry">New entry</button>
<button data-testid="settings">Settings</button>
</main></body></html>
""")
w("site/app.js", "console.log('fx');")
w("site/entries.html", """
<!doctype html><html><head><meta charset="utf-8"><title>Entries</title><link rel="stylesheet" href="site.css"></head>
<body><header data-testid="header"><h1>FxApp</h1></header>
<main><h2>Entries</h2>
<table data-testid="entries-table"><thead><tr><th>Date</th><th>Title</th></tr></thead><tbody></tbody></table>
<span data-testid="entry-count">3 entries</span>
</main></body></html>
""")
w("site/broken.html", """
<!doctype html><html><head><meta charset="utf-8"><title>Editor</title><link rel="stylesheet" href="site.css">
<style>.bar{position:relative;height:60px}.bar button{position:absolute;top:10px;width:140px;height:36px}#s{left:20px}#c{left:60px}</style></head>
<body><header data-testid="header"><h1>FxApp</h1></header>
<main><h2>Editor</h2><textarea data-testid="body" rows="4" cols="40">Some text here</textarea>
<div class="bar"><button id="s" data-testid="save">Save</button><button id="c" data-testid="cancel">Cancel</button></div>
</main></body></html>
""")
w("site/unstyled.html", """
<!doctype html><html><head><meta charset="utf-8"><title>Settings</title><link rel="stylesheet" href="missing.css"></head>
<body><header data-testid="header"><h1>FxApp</h1></header>
<main><h2>Settings</h2><label>Theme <select data-testid="theme"><option>Light</option><option>Dark</option></select></label>
<button data-testid="save-settings">Save</button></main></body></html>
""")

for name, title, body in [
    ("home", "Home", '<header data-testid="header"><h1>FxApp</h1><nav><a href="entries.html" data-testid="nav-entries">Entries</a></nav></header><main><ul data-testid="entry-list"><li>…</li></ul><button data-testid="new-entry">New entry</button><button data-testid="settings">Settings</button></main>'),
    ("entries", "Entries", '<header data-testid="header"><h1>FxApp</h1></header><main><table data-testid="entries-table"><thead><tr><th>Date</th><th>Title</th></tr></thead><tbody><tr><td>…</td><td>…</td></tr></tbody></table><span data-testid="entry-count">n entries</span></main>'),
    ("editor", "Editor", '<header data-testid="header"><h1>FxApp</h1></header><main><textarea data-testid="body"></textarea><div><button data-testid="save">Save</button><button data-testid="cancel">Cancel</button></div></main>'),
    ("settings", "Settings", '<header data-testid="header"><h1>FxApp</h1></header><main><select data-testid="theme"><option>Light</option></select><button data-testid="save-settings">Save</button></main>'),
]:
    w(f"docs/mockups/{name}.html", f'<!doctype html><html><head><meta charset="utf-8"><title>{title}</title><link rel="stylesheet" href="site.css"></head><body>{body}</body></html>\n')
w("docs/mockups/site.css", CSS)

w("docs/FxApp-UIDesign.md", """
# FxApp — UIDesign

| | |
|---|---|
| App | FxApp |
| Kind | app |
| Size | S |

## Design system

Plain.

## Screens

### Screen: Home (`/`)
Mockup: docs/mockups/home.html

### Screen: Entries (`/entries.html`)
Mockup: docs/mockups/entries.html

### Screen: Editor (`/broken.html`)
Mockup: docs/mockups/editor.html

### Screen: Settings (`/unstyled.html`)
Mockup: docs/mockups/settings.html
""")
w("docs/FxApp-BRD.md", """
# FxApp — BRD

## Screens and flow

| Screen | Route | Role | Mockup | Fields |
|---|---|---|---|---|
| Home | / | User | docs/mockups/home.html | — |
| Quick settings | on / | User | docs/mockups/home.html | theme |
| Entries | /entries.html | User | docs/mockups/entries.html | — |
""")
w("docs/FxApp-UsageGuide.md", """
# FxApp — UsageGuide

## Test users

| # | User | Password source | Role | Exists |
|---|---|---|---|---|
| 1 | tester | none, no sign-in | User | yes |

## Execution guide

Static.
""")
w("docs/FxApp-Checklist.md", """
# FxApp — Checklist

## Goal

Fixture.

## Requirements Status

| ID | Requirement | Status | % | Remarks | Details |
|---|---|---|---|---|---|
| REQ-UI-001 | Home lists today's entries | Implemented | 75% | built | [d](#d-req-ui-001) |
| REQ-UI-002 | Entries table | Implemented | 75% | built | [d](#d-req-ui-002) |
| REQ-UI-003 | Editor buttons | Verified | 100% | old pass | [d](#d-req-ui-003) |
| REQ-UI-004 | Settings page | Implemented | 75% | built | [d](#d-req-ui-004) |
| REQ-FN-005 | Save a quick setting | Implemented | 75% | built | [d](#d-req-fn-005) |
| REQ-FN-006 | Count badge | Implemented | 75% | built | [d](#d-req-fn-006) |
| REQ-NFR-007 | Logs | Implemented | 75% | built | [d](#d-req-nfr-007) |
| REQ-NFR-008 | Home speed | Implemented | 75% | built | [d](#d-req-nfr-008) |
| REQ-FN-009 | Dropped | N/A | 0% | out of scope | [d](#d-req-fn-009) |

## Home

- <a id="d-req-ui-001"></a> **REQ-UI-001** (BRD-1) Home lists today's entries. Mockup: docs/mockups/home.html
  - *Acceptance:* When the user opens Home, then the entry list on Home shows today's entries.
- <a id="d-req-fn-005"></a> **REQ-FN-005** (BRD-2) Save a quick setting.
  - *Acceptance:* When the user taps Save on Quick settings, then the theme is stored.
- <a id="d-req-fn-006"></a> **REQ-FN-006** (BRD-3) Count badge.
  - *Acceptance:* When the user opens the list on Entries, then the count equals the rows.

## Entries

- <a id="d-req-ui-002"></a> **REQ-UI-002** (BRD-4) Entries table. Mockup: docs/mockups/entries.html
  - *Acceptance:* When the user opens the list on Entries, then every entry is a row with its date and title.

## Editor

- <a id="d-req-ui-003"></a> **REQ-UI-003** (BRD-5) Editor buttons. Mockup: docs/mockups/editor.html
  - *Acceptance:* When the user types text on Editor, then Save and Cancel sit side by side.

## Settings

- <a id="d-req-ui-004"></a> **REQ-UI-004** (BRD-6) Settings page. Mockup: docs/mockups/settings.html
  - *Acceptance:* When the user picks a theme on Settings, then the page shows it styled.

## Non-functional

- <a id="d-req-nfr-007"></a> **REQ-NFR-007** (BRD-7) Logs.
  - *Acceptance:* When the app runs, then the log file records each screen opened.
- <a id="d-req-nfr-008"></a> **REQ-NFR-008** (BRD-8) Home speed.
  - *Acceptance:* When a user opens Home, then it answers within the budget. perf-budget: p95 ttfb <= 500ms @ concurrency 1
- <a id="d-req-fn-009"></a> **REQ-FN-009** (BRD-9) Dropped.
  - *Acceptance:* When nothing, then nothing.
""")

w("tests/verify/verify.spec.js", """
const { test, expect } = require('@playwright/test');
const BASE = process.env.BASE_URL || 'http://localhost:5117';
test('REQ-UI-001 home lists entries', async ({ page }) => {
  await page.goto(BASE + '/');
  await expect(page.locator('[data-testid="entry-list"] li')).toHaveCount(3);
});
test('REQ-UI-002 entries table has rows', async ({ page }) => {
  await page.goto(BASE + '/entries.html');
  await expect(page.locator('[data-testid="entries-table"]')).toBeVisible();
});
test('REQ-UI-003 editor buttons present', async ({ page }) => {
  await page.goto(BASE + '/broken.html');
  await expect(page.locator('[data-testid="save"]')).toBeVisible();
});
test('REQ-UI-004 settings page opens', async ({ page }) => {
  await page.goto(BASE + '/unstyled.html');
  await expect(page.locator('[data-testid="theme"]')).toBeVisible();
});
test('REQ-FN-005 quick setting is stored', async ({ page }) => {
  await page.goto(BASE + '/');
  await expect(page.locator('[data-testid="stored-theme"]')).toBeVisible({ timeout: 1500 });
});
""")

# a perf measurement over budget for REQ-NFR-008
w("tests/.artifacts/verify/perf/REQ-NFR-008.json", """
{"status":"ok","build_config":"Release","levels":[{"concurrency":1,"samples":40,"weak":false,"errors":0,"error_rate":0,"non_200":[],"redirect_rate":0,
 "ttfb_ms":{"p50":320,"p95":900,"max":1300},"load_ms":{"p50":400,"p95":1100,"max":1500}}]}
""")
for name, body in {
    "ok.json": '{"status":"ok","build_config":"Release","levels":[{"concurrency":50,"samples":60,"weak":false,"errors":0,"error_rate":0,"non_200":[],"redirect_rate":0,"ttfb_ms":{"p50":100,"p95":410,"max":600},"load_ms":{"p50":200,"p95":500,"max":700}}]}',
    "marginal.json": '{"status":"ok","build_config":"Release","levels":[{"concurrency":50,"samples":60,"weak":false,"errors":0,"error_rate":0,"non_200":[],"redirect_rate":0,"ttfb_ms":{"p50":100,"p95":600,"max":900},"load_ms":{"p50":200,"p95":500,"max":700}}]}',
    "debug.json": '{"status":"ok","build_config":"Debug","levels":[{"concurrency":50,"samples":60,"weak":false,"errors":0,"error_rate":0,"non_200":[],"redirect_rate":0,"ttfb_ms":{"p50":100,"p95":300,"max":400},"load_ms":{"p50":200,"p95":500,"max":700}}]}',
    "shed.json": '{"status":"ok","build_config":"Release","levels":[{"concurrency":50,"samples":30,"weak":false,"errors":20,"error_rate":0.4,"non_200":[],"redirect_rate":0,"ttfb_ms":{"p50":100,"p95":300,"max":400},"load_ms":{"p50":200,"p95":500,"max":700}}]}',
    "weak.json": '{"status":"ok","build_config":"Release","levels":[{"concurrency":50,"samples":4,"weak":true,"errors":0,"error_rate":0,"non_200":[],"redirect_rate":0,"ttfb_ms":{"p50":100,"p95":300,"max":400},"load_ms":{"p50":200,"p95":500,"max":700}}]}',
    "redirected.json": '{"status":"redirected","base":"x"}',
}.items():
    w(f"perf-cases/{name}", body + "\n")

print(APP)
